import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../tool/prepare_stream_json_v3_compat.cjs', import.meta.url), 'utf8');
const root = '/synthetic/node_modules/firebase-tools';
// Minimal synthetic import/call sites, not vendored upstream modules. The
// installed-module and stream behavior tests cover the real dependency too.
const targets = {
  'lib/commands/auth-import.js': [
    'const Pick = require("stream-json/filters/Pick");',
    'const StreamArray = require("stream-json/streamers/StreamArray");',
    'Pick.withParser({ filter: /^users$/ })',
    'StreamArray.streamArray()',
  ].join('\n'),
  'lib/database/import.js': [
    'const Filter = require("stream-json/filters/Filter");',
    'const StreamObject = require("stream-json/streamers/StreamObject");',
    'Filter.withParser({ filter: () => true })',
    'StreamObject.streamObject()',
  ].join('\n'),
  'lib/frameworks/next/index.js': [
    'const Pick_1 = require("stream-json/filters/Pick");',
    'const StreamObject_1 = require("stream-json/streamers/StreamObject");',
    '(0, stream_json_1.parser)({ packValues: false, packKeys: true, streamValues: false })',
    '(0, Pick_1.pick)({ filter: "dependencies" })',
    '(0, StreamObject_1.streamObject)()',
  ].join('\n'),
};

function harness({ firebase = '15.29.0', streamJson = '3.5.0' } = {}) {
  const files = new Map(Object.entries(targets).map(([name, value]) => [path.join(root, name), value]));
  const writes = [];
  const reads = [];
  const require = (name) => {
    if (name === 'node:path') return path;
    if (name === path.join(root, 'package.json')) return { version: firebase };
    if (name === 'node:fs') return {
      readFileSync(file) {
        reads.push(file);
        if (file === '/synthetic/node_modules/stream-json/package.json') {
          return JSON.stringify({ version: streamJson });
        }
        assert.ok(files.has(file), 'synthetic file must exist');
        return files.get(file);
      },
      writeFileSync(file, value) {
        writes.push(file);
        files.set(file, value);
      },
    };
    throw new Error(`Unexpected dependency: ${name}`);
  };
  require.resolve = (name) => {
    assert.equal(name, 'firebase-tools/package.json');
    return path.join(root, 'package.json');
  };
  return { files, reads, writes, run: () => vm.runInNewContext(source, { require }) };
}

test('prepares all three modules and is byte-idempotent without second writes', () => {
  const fixture = harness();
  fixture.run();
  assert.equal(fixture.writes.length, 3);
  const prepared = new Map(fixture.files);
  const [auth, database, next] = [...prepared.values()];
  assert.match(auth, /Pick\.default\.withParserAsStream/);
  assert.match(auth, /StreamArray\.default\.asStream/);
  assert.match(database, /Filter\.default\.withParserAsStream/);
  assert.match(database, /StreamObject\.default\.asStream/);
  assert.match(next, /parser\.asStream\(\{ packValues: false, packKeys: true, streamValues: false \}\)/);
  assert.match(next, /Pick_1\.default\.asStream/);
  assert.match(next, /StreamObject_1\.default\.asStream/);
  for (const text of prepared.values()) {
    assert.doesNotMatch(text, /stream-json\/(filters|streamers)\/[A-Z]/);
    assert.match(text, /stream-json\/(filters|streamers)\/[a-z-]+\.js/);
  }
  fixture.writes.length = 0;
  fixture.run();
  assert.deepEqual(fixture.files, prepared);
  assert.deepEqual(fixture.writes, []);
});

for (const versions of [
  { firebase: '15.28.1' },
  { firebase: '15.30.0' },
  { streamJson: '3.4.0' },
  { streamJson: '3.6.0' },
]) {
  test(`unreviewed version fails before module reads/writes: ${JSON.stringify(versions)}`, () => {
    const fixture = harness(versions);
    const before = new Map(fixture.files);
    assert.throws(fixture.run, /Unsupported Firebase stream-json compatibility target/);
    assert.equal(fixture.reads.length, 1); // stream-json version only.
    assert.deepEqual(fixture.writes, []);
    assert.deepEqual(fixture.files, before);
  });
}

for (const [file, text] of Object.entries(targets)) {
  for (const corruption of ['missing', 'duplicate-old', 'mixed-old-new', 'duplicate-new']) {
    test(`upstream drift fails before every write: ${file} ${corruption}`, () => {
      const fixture = harness();
      const firstLine = text.split('\n')[0];
      let corrupted;
      if (corruption === 'missing') corrupted = text.replace(firstLine, 'changed upstream import');
      if (corruption === 'duplicate-old') corrupted = `${text}\n${firstLine}`;
      if (corruption === 'mixed-old-new' || corruption === 'duplicate-new') {
        const prepared = harness();
        prepared.run();
        corrupted = prepared.files.get(path.join(root, file));
        corrupted += `\n${corruption === 'mixed-old-new' ? firstLine : corrupted.split('\n')[0]}`;
      }
      fixture.files.set(path.join(root, file), corrupted);
      const before = new Map(fixture.files);
      assert.throws(fixture.run, /Unexpected firebase-tools compatibility target/);
      assert.deepEqual(fixture.files, before);
      assert.deepEqual(fixture.writes, []);
    });
  }
}

test('missing later module cannot leave earlier modules rewritten', () => {
  const fixture = harness();
  fixture.files.delete(path.join(root, 'lib/frameworks/next/index.js'));
  const before = new Map(fixture.files);
  assert.throws(fixture.run, /synthetic file must exist/);
  assert.deepEqual(fixture.files, before);
  assert.deepEqual(fixture.writes, []);
});
