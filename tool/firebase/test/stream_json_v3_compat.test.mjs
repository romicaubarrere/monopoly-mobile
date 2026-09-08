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

test('Auth JSON stream preserves fragmented UTF-8 users and ignores other fields', async () => {
  const Chain = require('stream-chain');
  const pick = require('stream-json/filters/pick.js').default;
  const streamArray = require('stream-json/streamers/stream-array.js').default;
  const users = [{ localId: 'synthetic-ñ', displayName: '🎲' }, { localId: 'synthetic-2' }];
  const input = Buffer.from(JSON.stringify({ ignored: { users: ['not-selected'] }, users }), 'utf8');
  const result = await collect(new Chain([
    Readable.from([...input].map((byte) => Buffer.from([byte]))),
    pick.withParserAsStream({ filter: /^users$/ }),
    streamArray.asStream(),
  ]));
  assert.deepEqual(result, users.map((value, key) => ({ key, value })));
  assert.deepEqual(await collect(new Chain([
    Readable.from(['{"users":[]}']),
    pick.withParserAsStream({ filter: /^users$/ }),
    streamArray.asStream(),
  ])), []);
});

test('Auth parser rejects truncated JSON instead of reporting a complete import', async () => {
  const Chain = require('stream-chain');
  const pick = require('stream-json/filters/pick.js').default;
  const streamArray = require('stream-json/streamers/stream-array.js').default;
  await assert.rejects(collect(new Chain([
    Readable.from(['{"users":[{"localId":"synthetic"}']),
    pick.withParserAsStream({ filter: /^users$/ }),
    streamArray.asStream(),
  ])));
});

test('RTDB path filter preserves the selected subtree outer structure', async () => {
  const Chain = require('stream-chain');
  const filter = require('stream-json/filters/filter.js').default;
  const streamObject = require('stream-json/streamers/stream-object.js').default;
  const input = JSON.stringify({ projects: { one: { value: 'ñ' }, two: { value: 'excluded' } }, other: 4 });
  const result = await collect(new Chain([
    Readable.from([input]),
    filter.withParserAsStream({ filter: 'projects/one', pathSeparator: '/' }),
    streamObject.asStream(),
  ]));
  assert.deepEqual(result, [{ key: 'projects', value: { one: { value: 'ñ' } } }]);
});

test('Next lockfile pipeline retains dependency names/tree with upstream flags', async () => {
  const Chain = require('stream-chain');
  const { parser } = require('stream-json');
  const pick = require('stream-json/filters/pick.js').default;
  const streamObject = require('stream-json/streamers/stream-object.js').default;
  const input = JSON.stringify({
    dependencies: { first: { version: '1.0.0', dependencies: { nested: { version: '2.0.0' } } }, second: { version: '3.0.0' } },
    devDependencies: { excluded: { version: '4.0.0' } },
  });
  const result = await collect(new Chain([
    Readable.from([input]),
    parser.asStream({ packValues: false, packKeys: true, streamValues: false }),
    pick.asStream({ filter: 'dependencies' }),
    streamObject.asStream(),
  ]));
  // Upstream deliberately drops scalar values: this path discovers the tree
  // of dependency names, not package versions. Preserve its parser options.
  assert.deepEqual(result, [
    { key: 'first', value: { dependencies: { nested: {} } } },
    { key: 'second', value: {} },
  ]);
});
