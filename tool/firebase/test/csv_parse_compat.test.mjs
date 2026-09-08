import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { Readable, Transform } from 'node:stream';
import test from 'node:test';

// Offline installed-package checks with synthetic CSV, not execution evidence
// for auth:import, Auth uploads, emulators, Android or production services.
// The consumer source check ties the exercised readable API to pinned Firebase.
// Advisory: https://github.com/adaltas/node-csv/security/advisories/GHSA-8cw4-87c7-c6xx
const require = createRequire(import.meta.url);
const authImportPath = require.resolve('firebase-tools/lib/commands/auth-import');
const firebaseRequire = createRequire(authImportPath);
const csv = firebaseRequire('csv-parse');

function parseCsv(csvText, options) {
  return new Promise((resolveRows, reject) => {
    // No options is the actual Firebase auth:import CSV call shape.
    const parser = options === undefined ? csv.parse() : csv.parse(options);
    assert.ok(parser instanceof Transform);
    const rows = [];
    const source = Readable.from(
      [...Buffer.from(csvText, 'utf8')].map((byte) => Buffer.from([byte])),
    );

    parser.on('readable', () => {
      let row;
      while ((row = parser.read()) !== null) {
        rows.push(row);
      }
    });
    parser.once('error', (error) => {
      source.destroy();
      reject(error);
    });
    parser.once('end', () => resolveRows(rows));
    source.once('error', (error) => parser.destroy(error));
    source.pipe(parser);
  });
}

test('Firebase consumer and root CommonJS resolve the same patched csv-parse', () => {
  const consumerEntry = firebaseRequire.resolve('csv-parse');
  assert.equal(consumerEntry, require.resolve('csv-parse'));
  assert.equal(csv, require('csv-parse'));
  assert.equal(typeof csv.parse, 'function');

  // package.json is not an exported csv-parse subpath; locate it from the
  // published dist/cjs entry and verify the expected package layout.
  const packagePath = resolve(dirname(consumerEntry), '../../package.json');
  const metadata = JSON.parse(readFileSync(packagePath, 'utf8'));
  assert.equal(metadata.name, 'csv-parse');
  assert.equal(metadata.version, '7.0.2');
  assert.equal(metadata.exports['.'].require.default, './dist/cjs/index.cjs');
  assert.equal(consumerEntry, resolve(dirname(packagePath), metadata.main));
});

test('pinned Firebase CSV consumer uses parse() and the readable array API', () => {
  const firebasePackage = firebaseRequire('firebase-tools/package.json');
  assert.equal(firebasePackage.version, '15.29.0');
  const source = readFileSync(authImportPath, 'utf8');

  for (const expected of [
    'const csv_parse_1 = require("csv-parse");',
    'const parser = (0, csv_parse_1.parse)();',
    '.on("readable",',
    'while ((record = parser.read()) !== null)',
    'const trimmed = record.map(',
    '.on("end",',
    'inStream.pipe(parser);',
  ]) {
    assert.ok(source.includes(expected), `Firebase CSV consumer: ${expected}`);
  }
});

for (const { name, input, expected } of [
  {
    name: 'CRLF, escaped quotes, empty fields and byte-split Unicode',
    input:
      'uid-1,email@example.test,true,"Romí, ""B""",\r\n' +
      'uid-2,,false,🤖,\r\n',
    expected: [
      ['uid-1', 'email@example.test', 'true', 'Romí, "B"', ''],
      ['uid-2', '', 'false', '🤖', ''],
    ],
  },
  {
    name: 'a newline inside a quoted field',
    input: 'uid-1,"línea 1\nlínea 2",\n',
    expected: [['uid-1', 'línea 1\nlínea 2', '']],
  },
  {
    name: 'an empty input',
    input: '',
    expected: [],
  },
  {
    name: 'header-like strings as ordinary array fields without columns options',
    input: '__proto__,__proto__,role\nvalue-1,value-2,synthetic\n',
    expected: [
      ['__proto__', '__proto__', 'role'],
      ['value-1', 'value-2', 'synthetic'],
    ],
  },
]) {
  test(`Firebase CSV parse() preserves ${name}`, { timeout: 5000 }, async () => {
    const rows = await parseCsv(input);
    assert.ok(rows.every(Array.isArray));
    assert.ok(rows.every((row) => row.every((field) => typeof field === 'string')));
    assert.deepEqual(rows, expected);
  });
}

test(
  'Firebase CSV parse() rejects a truncated quoted field',
  { timeout: 5000 },
  async () => {
    await assert.rejects(parseCsv('uid-1,"unterminated\n'), {
      code: 'CSV_QUOTE_NOT_CLOSED',
    });
  },
);

test(
  'GHSA-8cw4-87c7-c6xx duplicate columns cannot replace the record prototype',
  { timeout: 5000 },
  async () => {
    const rows = await parseCsv(
      '__proto__,__proto__,role\nvalue-1,value-2,synthetic\n',
      { columns: true, group_columns_by_name: true },
    );

    assert.equal(rows.length, 1);
    const record = rows[0];
    assert.equal(Object.getPrototypeOf(record), Object.prototype);
    assert.equal(Object.hasOwn(record, '__proto__'), true);
    assert.deepEqual(Object.getOwnPropertyDescriptor(record, '__proto__'), {
      value: ['value-1', 'value-2'],
      writable: true,
      enumerable: true,
      configurable: true,
    });
    assert.equal(record.role, 'synthetic');
    assert.equal(record.length, undefined);
    assert.equal(record['1'], undefined);
    assert.equal(record['2'], undefined);
    assert.deepEqual(Object.keys(record), ['__proto__', 'role']);
    assert.equal(
      JSON.stringify(record),
      '{"__proto__":["value-1","value-2"],"role":"synthetic"}',
    );
  },
);
