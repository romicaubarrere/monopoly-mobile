'use strict';

// firebase-tools 15.28.1 imports stream-json 1.x CommonJS entry points.
// stream-json 3.5.0 fixes the reported OSV but is ESM-only, lower-cases its
// paths, and exposes Node streams through .asStream() helpers. Adapt the exact
// legacy imports and stream factories after npm ci, before the emulator CLI loads.
const { readFileSync, writeFileSync } = require('node:fs');
const { dirname, join } = require('node:path');

const firebaseToolsPackagePath = require.resolve('firebase-tools/package.json');
const firebaseToolsRoot = dirname(firebaseToolsPackagePath);
const firebaseToolsVersion = require(firebaseToolsPackagePath).version;
const streamJsonPackagePath = join(
  dirname(firebaseToolsRoot),
  'stream-json',
  'package.json',
);
const streamJsonVersion = JSON.parse(readFileSync(streamJsonPackagePath, 'utf8')).version;

if (firebaseToolsVersion !== '15.28.1' || streamJsonVersion !== '3.5.0') {
  throw new Error(
    `Unsupported Firebase stream-json compatibility target: firebase-tools@${firebaseToolsVersion}, stream-json@${streamJsonVersion}`,
  );
}

const rewrites = [
  {
    file: 'lib/commands/auth-import.js',
    replacements: [
      [
        'const Pick = require("stream-json/filters/Pick");',
        'const Pick = require("stream-json/filters/pick.js");',
      ],
      [
        'const StreamArray = require("stream-json/streamers/StreamArray");',
        'const StreamArray = require("stream-json/streamers/stream-array.js");',
      ],
      [
        'Pick.withParser({ filter: /^users$/ })',
        'Pick.default.withParserAsStream({ filter: /^users$/ })',
      ],
      [
        'StreamArray.streamArray()',
        'StreamArray.default.asStream()',
      ],
    ],
  },
  {
    file: 'lib/database/import.js',
    replacements: [
      [
        'const Filter = require("stream-json/filters/Filter");',
        'const Filter = require("stream-json/filters/filter.js");',
      ],
      [
        'const StreamObject = require("stream-json/streamers/StreamObject");',
        'const StreamObject = require("stream-json/streamers/stream-object.js");',
      ],
      [
        'Filter.withParser({',
        'Filter.default.withParserAsStream({',
      ],
      [
        'StreamObject.streamObject()',
        'StreamObject.default.asStream()',
      ],
    ],
  },
  {
    file: 'lib/frameworks/next/index.js',
    replacements: [
      [
        'const Pick_1 = require("stream-json/filters/Pick");',
        'const Pick_1 = require("stream-json/filters/pick.js");',
      ],
      [
        'const StreamObject_1 = require("stream-json/streamers/StreamObject");',
        'const StreamObject_1 = require("stream-json/streamers/stream-object.js");',
      ],
      [
        '(0, stream_json_1.parser)({ packValues: false, packKeys: true, streamValues: false })',
        'stream_json_1.parser.asStream({ packValues: false, packKeys: true, streamValues: false })',
      ],
      [
        '(0, Pick_1.pick)({ filter: "dependencies" })',
        'Pick_1.default.asStream({ filter: "dependencies" })',
      ],
      [
        '(0, StreamObject_1.streamObject)()',
        'StreamObject_1.default.asStream()',
      ],
    ],
  },
];

for (const { file, replacements } of rewrites) {
  const filePath = join(firebaseToolsRoot, file);
  const original = readFileSync(filePath, 'utf8');
  let rewritten = original;

  for (const [before, after] of replacements) {
    if (rewritten.includes(after)) {
      continue;
    }
    if (!rewritten.includes(before)) {
      throw new Error(`Expected firebase-tools import not found: ${file}: ${before}`);
    }
    rewritten = rewritten.replace(before, after);
  }

  if (rewritten !== original) {
    writeFileSync(filePath, rewritten);
  }
}
