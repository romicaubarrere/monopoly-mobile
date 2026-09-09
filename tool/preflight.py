#!/usr/bin/env python3
"""Pinned Dart preflight for Trello #89; source checks are read-only by default."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


# Flutter's pin lives in .fvmrc. Update this only with a reviewed SDK upgrade.
DART_VERSION = "3.13.0"
SOURCE_ROOTS = ("apps", "packages", "backend")


class PreflightError(Exception):
    pass


def in_ci():
    return any(os.environ.get(key, "").lower() not in ("", "0", "false", "no")
               for key in ("CI", "GITHUB_ACTIONS"))


def verify_toolchain(root):
    expected_flutter = json.loads((root / ".fvmrc").read_text(encoding="utf-8"))["flutter"]
    if not isinstance(expected_flutter, str) or not re.fullmatch(r"\d+\.\d+\.\d+", expected_flutter):
        raise PreflightError(".fvmrc must contain an exact Flutter version.")
    flutter = subprocess.run(["flutter", "--version", "--machine"], cwd=root,
                             capture_output=True, text=True, check=True)
    metadata = json.loads(flutter.stdout)
    dart = subprocess.run(["dart", "--version"], cwd=root,
                          capture_output=True, text=True, check=True)
    version = re.search(r"^Dart SDK version: (\S+) ", dart.stdout + dart.stderr, re.MULTILINE)
    if (metadata.get("frameworkVersion") != expected_flutter
            or metadata.get("dartSdkVersion") != DART_VERSION
            or version is None or version[1] != DART_VERSION):
        raise PreflightError(
            f"Use Flutter {expected_flutter} / Dart {DART_VERSION} on PATH "
            "(including the Dart bundled with Flutter); no SDK is installed automatically.")
    print(f"Pinned toolchain: Flutter {expected_flutter} / Dart {DART_VERSION}", flush=True)


def format_sources(root, write=False):
    command = ["dart", "format"]
    if not write:
        command.extend(("--output=none", "--set-exit-if-changed"))
    return subprocess.run([*command, *SOURCE_ROOTS], cwd=root).returncode


def preflight(root, format_local=False, format_only=False):
    if format_local and in_ci():
        raise PreflightError("--format is local-only and is forbidden in CI.")
    if format_local or format_only:
        # Validate both PATH executables before dependency resolution or formatting.
        verify_toolchain(root)
        result = subprocess.run(["flutter", "pub", "get", "--enforce-lockfile"], cwd=root)
        if result.returncode:
            return result.returncode
        result = format_sources(root, write=format_local)
        if result:
            if not format_local:
                print("Formatting drift: run ./tool/preflight.py --format locally, "
                      "inspect the diff, then rerun the preflight.", file=sys.stderr)
            return result
        if format_only:
            return 0
    # ci.sh calls this script's --format-only stage, never this full entrypoint.
    # --format performs its explicit local write first, then checks all gates.
    for script in ("ci.sh", "check_ci_policy.sh", "scan_artifacts.sh"):
        result = subprocess.run(["bash", str(root / "tool" / script)], cwd=root)
        if result.returncode:
            return result.returncode
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", action="store_true", dest="format_local",
                        help="explicitly format local source before checking (forbidden in CI)")
    parser.add_argument("--format-only", action="store_true",
                        help="run only the pinned format stage, not full Foundation gates")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    try:
        return preflight(root, args.format_local, args.format_only)
    except PreflightError as error:
        print(f"Preflight blocked: {error}", file=sys.stderr)
    except FileNotFoundError as error:
        print(f"Preflight blocked: missing command or file: {error.filename}", file=sys.stderr)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.CalledProcessError):
        print("Preflight blocked: could not read the pinned toolchain or run its version checks.",
              file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
