import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import http from 'node:http';
import { createRequire } from 'node:module';
import { Writable } from 'node:stream';
import test from 'node:test';

// Installed-package checks with synthetic inputs, not execution of Firebase
// Hosting, Auth/Firestore emulators, a deployment or a production log pipeline.
// Only NEL is sent as an HTTP header: U+2028/U+2029 token cases are in memory.
// Custom formatters reading req directly / returning objects are not sanitized
// by this test contract; the patch protects Morgan's registered token values.
// Advisory: https://github.com/expressjs/morgan/security/advisories/GHSA-jxfw-x594-9x9m
const require = createRequire(import.meta.url);
const hostingPath = require.resolve('firebase-tools/lib/serve/hosting');
const serverPath = require.resolve('superstatic/lib/server');
const firebaseRequire = createRequire(hostingPath);
const superstaticRequire = createRequire(serverPath);
const morgan = firebaseRequire('morgan');

test('Firebase and Superstatic consumers resolve the same fixed Morgan', () => {
  assert.equal(firebaseRequire('firebase-tools/package.json').version, '15.29.0');
  assert.equal(superstaticRequire('superstatic/package.json').version, '10.0.0');
  for (const consumer of [require, firebaseRequire, superstaticRequire]) {
    assert.equal(consumer.resolve('morgan'), require.resolve('morgan'));
    assert.equal(consumer('morgan'), morgan);
    assert.equal(consumer('morgan/package.json').version, '1.12.0');
  }
  assert.equal(typeof morgan, 'function');
  assert.equal(typeof morgan.compile, 'function');
});

test('pinned consumers retain combined format and the ordinary byte stream', () => {
  const hosting = readFileSync(hostingPath, 'utf8');
  for (const expected of [
    'const morgan = require("morgan");',
    'const morganStream = new stream_1.Writable();',
    'const morganMiddleware = morgan("combined", {',
    'stream: morganStream,',
    'if (chunk instanceof Buffer)',
  ]) {
    assert.ok(hosting.includes(expected), 'Firebase logger call shape changed');
  }
  const server = readFileSync(serverPath, 'utf8');
  assert.ok(server.includes('const networkLogger = require("morgan");'));
  assert.ok(server.includes('app.use(networkLogger("combined"));'));

  const request = syntheticRequest();
  const response = syntheticResponse();
  // Inherit token functions without evaluating the deprecated default getter.
  const tokens = Object.create(morgan);
  tokens.date = () => '01/Jan/2026:00:00:00 +0000';
  assert.equal(
    morgan.compile(morgan.combined)(tokens, request, response),
    '127.0.0.1 - - [01/Jan/2026:00:00:00 +0000] "GET /safe HTTP/1.1" 200 2 "-" "-"',
  );
});

for (const [name, input, escaped] of [
  ['NEL', 'left\u0085right', String.raw`left\u0085right`],
  ['LINE SEPARATOR', 'left\u2028right', String.raw`left\u2028right`],
  ['PARAGRAPH SEPARATOR', 'left\u2029right', String.raw`left\u2029right`],
  ['C0 controls and backslash', 'left\r\n\t\\right', String.raw`left\r\n\t\\right`],
]) {
  test(`registered tokens escape ${name} exactly once`, () => {
    const request = syntheticRequest();
    request.url = input;
    request.headers = {
      'user-agent': input,
      referer: input,
      'x-review': input,
      authorization: `Basic ${Buffer.from(`${input}:x`, 'utf8').toString('base64')}`,
    };
    const response = syntheticResponse();
    const format = ':url|:user-agent|:referrer|:req[x-review]|:remote-user';
    const expected = Array(5).fill(escaped).join('|');
    const line = morgan.compile(format)(morgan, request, response);
    // Boolean assertions avoid printing synthetic Basic-auth contents on RED.
    assert.ok(line === expected, 'all compiled token outputs must escape once');
    assert.equal(/[\r\n\t\u0085\u2028\u2029]/u.test(line), false);
    assert.ok(
      morgan['remote-user'](request, response) === escaped,
      'the previously escaped Basic-auth token must not be double escaped',
    );
    assert.ok(
      morgan.req(request, response, 'x-review') === escaped,
      'registered tokens used by a function formatter must also be safe',
    );
  });
}

test('combined middleware preserves HTTP response and escapes a real NEL header', {
  timeout: 5000,
}, async (context) => {
  const chunks = [];
  let bufferChunks = 0;
  let nextCalls = 0;
  const output = new Writable({
    write(chunk, encoding, callback) {
      if (Buffer.isBuffer(chunk)) bufferChunks += 1;
      chunks.push(chunk.toString('utf8'));
      callback();
    },
  });
  assert.equal(output.writableObjectMode, false);
  const middleware = morgan('combined', { stream: output });
  const server = http.createServer((request, response) => {
    middleware(request, response, () => {
      nextCalls += 1;
      response.setHeader('Content-Length', Buffer.byteLength('ok'));
      response.end('ok');
    });
  });
  context.after(async () => {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
    output.destroy();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const response = await new Promise((resolve, reject) => {
    const request = http.get({
      hostname: '127.0.0.1',
      port: server.address().port,
      path: '/safe',
      agent: false,
      headers: { 'user-agent': 'agent\u0085next' },
    }, (result) => {
      let body = '';
      result.setEncoding('utf8');
      result.on('data', (chunk) => { body += chunk; });
      result.once('error', reject);
      result.once('end', () => resolve({ status: result.statusCode, body }));
    });
    request.once('error', reject);
  });

  assert.deepEqual(response, { status: 200, body: 'ok' });
  assert.equal(nextCalls, 1);
  assert.equal(bufferChunks, 1);
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0].endsWith('\n'), true);
  const record = chunks[0].slice(0, -1);
  assert.equal(/[\r\n\u0085\u2028\u2029]/u.test(record), false);
  assert.equal(record.includes(String.raw`"agent\u0085next"`), true);
  assert.equal(record.includes('"GET /safe HTTP/1.1" 200 2'), true);
});

function syntheticRequest() {
  return {
    method: 'GET',
    url: '/safe',
    headers: {},
    httpVersionMajor: 1,
    httpVersionMinor: 1,
    connection: { remoteAddress: '127.0.0.1' },
  };
}

function syntheticResponse() {
  return { headersSent: true, statusCode: 200, getHeader: () => 2 };
}
