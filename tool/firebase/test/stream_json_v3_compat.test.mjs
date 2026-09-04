import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { Readable } from 'node:stream';
import test from 'node:test';

const require = createRequire(import.meta.url);

function collect(stream) {
  return new Promise((resolve, reject) => {
    const values = [];
    stream.on('data', (value) => values.push(value));
    stream.once('error', reject);
    stream.once('end', () => resolve(values));
  });
}

test('Firebase CLI legacy stream-json pipelines use equivalent v3 Node streams', async () => {
  const Chain = require('stream-chain');
  const pick = require('stream-json/filters/pick.js').default;
  const filter = require('stream-json/filters/filter.js').default;
  const streamArray = require('stream-json/streamers/stream-array.js').default;
  const streamObject = require('stream-json/streamers/stream-object.js').default;

  for (const [name, factory] of [
    ['pick', pick],
    ['filter', filter],
    ['streamArray', streamArray],
    ['streamObject', streamObject],
  ]) {
    assert.equal(typeof factory.asStream, 'function', `${name} Node stream factory`);
  }

  assert.equal(typeof pick.withParserAsStream, 'function', 'pick parser stream factory');
  assert.equal(typeof filter.withParserAsStream, 'function', 'filter parser stream factory');

  const users = await collect(
    new Chain([
      Readable.from(['{"users":[{"id":1},{"id":2}]}']),
      pick.withParserAsStream({ filter: /^users$/ }),
      streamArray.asStream(),
    ]),
  );
  assert.deepEqual(users, [
    { key: 0, value: { id: 1 } },
    { key: 1, value: { id: 2 } },
  ]);

  const objectEntries = await collect(
    new Chain([
      Readable.from(['{"a":1,"b":2}']),
      filter.withParserAsStream({ filter: () => true, pathSeparator: '/' }),
      streamObject.asStream(),
    ]),
  );
  assert.deepEqual(objectEntries, [
    { key: 'a', value: 1 },
    { key: 'b', value: 2 },
  ]);

  for (const modulePath of [
    'firebase-tools/lib/commands/auth-import',
    'firebase-tools/lib/database/import',
    'firebase-tools/lib/frameworks/next',
  ]) {
    assert.doesNotThrow(() => require(modulePath), modulePath);
  }
});
