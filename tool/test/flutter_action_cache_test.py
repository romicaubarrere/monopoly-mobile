"""Keep the SDK layout migration separate from immutable legacy caches."""

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


def flutter_options():
    for path in sorted((ROOT / ".github/workflows").glob("*.yml")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            if "uses: subosito/flutter-action@" not in line:
                continue
            # Read only this action's more deeply indented `with` options.
            indent = line.index("uses:") - 2
            options = []
            for following in lines[index + 1:]:
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                options.append(following)
            yield path.name, "\n".join(options)


class FlutterActionCacheTests(unittest.TestCase):
    def test_sdk_layout_has_a_shared_nonlegacy_cache_key_in_every_job(self):
        actions = list(flutter_options())
        self.assertGreaterEqual(len(actions), 4)
        keys = set()
        for path, options in actions:
            with self.subTest(path=path, options=options):
                match = re.search(r"cache-key: '([^']+)'", options)
                self.assertIsNotNone(match, "v2.21 and v2.23 SDK layouts need distinct cache keys")
                key = match.group(1)
                self.assertTrue(key.startswith("flutter-sdk-layout-v2-"))
                for dimension in ("os", "channel", "version", "arch", "hash"):
                    self.assertIn(f":{dimension}:", key)
                keys.add(key)
        self.assertEqual(1, len(keys), "all jobs must share the migrated SDK cache")

    def test_migration_keeps_the_pinned_sdk_and_existing_cache_inputs(self):
        pin = json.loads((ROOT / ".fvmrc").read_text())["flutter"]
        actions = list(flutter_options())
        self.assertGreaterEqual(len(actions), 4)
        for path, options in actions:
            with self.subTest(path=path, options=options):
                self.assertIn(f"flutter-version: '{pin}'", options)
                self.assertIn("channel: stable", options)
                self.assertIn("cache: true", options)
                self.assertNotIn("flutter-version-file:", options)
                self.assertNotIn("pub-cache:", options)


if __name__ == "__main__":
    unittest.main()
