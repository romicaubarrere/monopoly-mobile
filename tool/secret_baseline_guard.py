"""Validate the one public-fixture exception before detect-secrets loads it.

The pure validator needs only the standard library. The CLI obtains the pinned
hook's defaults in a clean subprocess; it never imports configuration from the
candidate baseline. No scan, baseline update, or automatic approval happens here.
"""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


VERSION = "1.5.0"
BASELINE = ".secrets.baseline"
FIXTURES = "backend/command_service/test/fixtures"
REPORT = FIXTURES + "/public_snapshot_sizes.json"
FINDING_TYPE = "Hex High Entropy String"
# Same fixed occurrences as public_snapshot_size_evidence.dart. Generator and
# Dart golden equality remain required; this is not a new domain serializer.
PUBLIC_PATHS = {
    "bankruptcy_plans.json": (
        "declareA.initialState", "declareA.stateAfter",
        "declareB.initialState", "declareB.stateAfter",
        "deadline.initialState", "deadline.stateAfter",
    ),
    "tax_free_parking_plans.json": (
        "tax.initialState", "tax.plans.a.stateAfter", "tax.plans.b.stateAfter",
        "debt.initialState", "debt.plans.a.stateAfter",
        "collection.initialState", "collection.plans.a.stateAfter",
        "collection.plans.b.stateAfter", "zeroCollection.initialState",
        "zeroCollection.plans.a.stateAfter",
    ),
}
# Mirrors the existing AuthorityPublicSnapshot boundary, not a new privacy rule.
PRIVATE_KEYS = frozenset((
    "authorization", "authtoken", "authenticatedactoruid", "actoruid",
    "gamesecrets", "memberuidbyplayerid", "memberuids", "privatedeckstate",
    "seed", "seedbytes", "streamcounters", "futuredeck", "futuredeckorder",
    "token", "uid",
))


class GuardError(Exception):
    """Only fixed codes, never candidate values or file contents, are emitted."""


def reject(code):
    raise GuardError(code)


def decode(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                reject("duplicateJsonKey")
            result[key] = value
        return result

    try:
        return json.loads(text, object_pairs_hook=unique,
                          parse_constant=lambda _: reject("invalidJson"))
    except (ValueError, TypeError, RecursionError):
        raise GuardError("invalidJson") from None


def encoded(value):
    # Unlike Python equality, JSON preserves true/1/1.0 distinctions.
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"), allow_nan=False)


def snapshot_bytes(snapshot):
    def normalize(value):
        if value is None or type(value) in (str, bool, int):
            return value
        if type(value) is list:
            return [normalize(item) for item in value]
        if type(value) is dict:
            if any(type(key) is not str or key.lower() in PRIVATE_KEYS for key in value):
                reject("nonPublicSnapshot")
            # Dart's String.compareTo sorts UTF-16 code units, not code points.
            return {key: normalize(value[key]) for key in sorted(
                value, key=lambda key: key.encode("utf-16-be"))}
        reject("nonIntegerSnapshotJson")

    if (type(snapshot) is not dict
            or type(snapshot.get("schemaVersion")) is not int
            or snapshot["schemaVersion"] != 1
            or type(snapshot.get("stateVersion")) is not int
            or snapshot["stateVersion"] < 0
            or type(snapshot.get("gameId")) is not str or not snapshot["gameId"]):
        reject("invalidPublicSnapshot")
    try:
        return json.dumps(normalize(snapshot), ensure_ascii=False,
                          separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (UnicodeError, RecursionError):
        raise GuardError("invalidSnapshotJson") from None


def expected_report(fixtures):
    snapshots = []
    for filename, paths in PUBLIC_PATHS.items():
        for path in paths:
            try:
                value = fixtures[filename]
                for segment in path.split("."):
                    value = value[segment]
            except (KeyError, TypeError):
                raise GuardError("missingPublicSnapshot") from None
            raw = snapshot_bytes(value)
            snapshots.append({
                "fixture": filename, "snapshotPath": path,
                "serializedSnapshotBytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            })
    return {
        "formatVersion": 1,
        "evidenceKind": "synthetic-public-snapshot-fixtures",
        "serialization": "CanonicalDomainJson/UTF-8",
        "snapshots": snapshots,
    }


def validate(baseline, report_text, fixtures, defaults):
    """Reject broad exemptions and hashes not reproducible from curated inputs."""
    if (type(baseline) is not dict or set(baseline) != {
            "version", "plugins_used", "filters_used", "results", "generated_at"}
            or baseline["version"] != VERSION
            or type(baseline["generated_at"]) is not str
            or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
                                baseline["generated_at"])):
        reject("invalidBaselineSchema")
    if (defaults.get("version") != VERSION or any(
            encoded(baseline[key]) != encoded(defaults[key])
            for key in ("plugins_used", "filters_used"))):
        reject("nonDefaultDetectorSettings")

    report = expected_report(fixtures)
    if encoded(decode(report_text)) != encoded(report):
        reject("publicSnapshotReportMismatch")
    # Baseline identity in 1.5.0 is filename + type + SHA1(secret text), not
    # line number. Three repeated initial states yield 14 identities for 16
    # occurrences. Checking the first line also prevents silent hook rewrites.
    public_hashes = {item["sha256"] for item in report["snapshots"]}
    if len(report["snapshots"]) != 16 or len(public_hashes) != 14:
        reject("publicSnapshotScopeChanged")
    entries = []
    seen = set()
    for number, line in enumerate(report_text.splitlines(), 1):
        match = re.fullmatch(r'\s*"sha256"\s*:\s*"([a-f0-9]{64})"\s*,?\s*', line)
        if match and match[1] in public_hashes and match[1] not in seen:
            seen.add(match[1])
            entries.append({
                "type": FINDING_TYPE, "filename": REPORT,
                "hashed_secret": hashlib.sha1(match[1].encode("utf-8")).hexdigest(),
                "is_verified": False, "line_number": number, "is_secret": False,
            })
    if seen != public_hashes or encoded(baseline["results"]) != encoded({REPORT: entries}):
        reject("unapprovedBaselineEntry")
    return {"publicSnapshotOccurrences": 16, "approvedHashIdentities": 14}


def pinned_defaults():
    # -I ignores PYTHONPATH/user-site; this fresh process has never loaded the
    # candidate baseline. In particular, no candidate filter/plugin is imported.
    source = (
        "import json; from detect_secrets.__version__ import VERSION; "
        "from detect_secrets.core.usage import ParserBuilder; "
        "from detect_secrets.settings import get_settings; "
        "ParserBuilder().add_pre_commit_arguments().parse_args([]); "
        "print(json.dumps(dict(version=VERSION, **get_settings().json())))"
    )
    try:
        result = subprocess.run([sys.executable, "-I", "-B", "-c", source],
                                check=True, capture_output=True, text=True, timeout=30)
        defaults = decode(result.stdout)
    except (OSError, subprocess.SubprocessError):
        raise GuardError("pinnedDetectorUnavailable") from None
    if type(defaults) is not dict or defaults.get("version") != VERSION:
        reject("pinnedDetectorVersionMismatch")
    return defaults


def validate_checkout(root, defaults):
    baseline = decode((root / BASELINE).read_text(encoding="utf-8"))
    report_text = (root / REPORT).read_text(encoding="utf-8")
    fixtures = {name: decode((root / FIXTURES / name).read_text(encoding="utf-8"))
                for name in PUBLIC_PATHS}
    return validate(baseline, report_text, fixtures, defaults)


def main(arguments=None):
    args = sys.argv[1:] if arguments is None else arguments
    if args:
        print("Usage: python tool/secret_baseline_guard.py", file=sys.stderr)
        return 64
    try:
        result = validate_checkout(Path(__file__).resolve().parents[1], pinned_defaults())
    except GuardError as error:
        print("Secret baseline rejected: " + str(error), file=sys.stderr)
        return 1
    except (OSError, UnicodeError, ValueError, TypeError, RecursionError):
        print("Secret baseline rejected: invalidInput", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
