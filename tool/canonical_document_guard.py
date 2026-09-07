"""Fail-closed, offline-testable Confluence ADF mutation guard (Trello #70).

Only status/evidence edits inside explicitly allowed existing H2 sections are
supported. This tool does not authorize source promotion or product decisions.
"""

import argparse
import base64
from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timezone
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid


TOOL_VERSION = 1
MAX_RESPONSE_BYTES = 8 * 1024 * 1024


class GuardError(Exception):
    """Only fixed, non-content-bearing codes may cross the logging boundary."""


class TransportError(GuardError):
    pass


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def decode(value):
    def unique(pairs):
        result = {}
        for key, item in pairs:
            if key in result:
                raise GuardError("duplicateJsonKey")
            result[key] = item
        return result

    try:
        return json.loads(value, object_pairs_hook=unique,
                          parse_constant=lambda _: reject("invalidJson"))
    except (ValueError, TypeError, RecursionError):
        raise GuardError("invalidJson") from None


def reject(code):
    raise GuardError(code)


def text_content(node):
    if isinstance(node, list):
        return "\n".join(text_content(item) for item in node)
    if not isinstance(node, dict):
        reject("invalidAdf")
    if node.get("type") == "text":
        value = node.get("text")
        if not isinstance(value, str):
            reject("invalidAdf")
        return value
    # Inline runs form one string; containers add boundaries between blocks.
    if not isinstance(node.get("content", []), list):
        reject("invalidAdf")
    sep = "" if node.get("type") in ("paragraph", "heading") else "\n"
    return sep.join(text_content(item) for item in node.get("content", []))


def sections(body):
    if not body.strip() or body.strip().lower() in ("noop", "probe", "test"):
        reject("trivialCandidate")
    doc = decode(body)
    if (not isinstance(doc, dict) or doc.get("type") != "doc"
            or type(doc.get("version")) is not int or doc["version"] != 1
            or not isinstance(doc.get("content"), list)):
        reject("invalidAdf")
    if not text_content(doc).strip() or text_content(doc).strip().lower() in (
            "noop", "probe", "test"):
        reject("trivialCandidate")
    result = {"": []}
    heading = ""
    for node in doc["content"]:
        if not isinstance(node, dict) or not isinstance(node.get("attrs", {}), dict):
            reject("invalidAdf")
        if (node.get("type") == "heading"
                and node.get("attrs", {}).get("level") == 2):
            heading = text_content(node)
            if not heading or heading in result:
                reject("ambiguousSection")
            result[heading] = []
        result[heading].append(node)
    return doc, result


@dataclass(frozen=True)
class Page:
    id: str
    title: str
    space_id: str
    status: str
    version: int
    body: str
    parent_id: str = ""
    owner_id: str = ""
    message: str = ""

    def identity(self):
        return (self.id, self.title, self.space_id, self.status,
                self.parent_id, self.owner_id)

    def same_content(self, other):
        return self.identity() == other.identity() and self.body == other.body

    @classmethod
    def from_api(cls, raw):
        try:
            page = cls(
                id=raw["id"], title=raw["title"], space_id=raw["spaceId"],
                status=raw["status"], version=raw["version"]["number"],
                body=raw["body"]["atlas_doc_format"]["value"],
                parent_id=raw.get("parentId") or "", owner_id=raw.get("ownerId") or "",
                message=raw["version"].get("message", ""))
            if (not all(isinstance(x, str) for x in (*page.identity(), page.body, page.message))
                    or not re.fullmatch(r"[0-9]+", page.id)
                    or not page.title or not page.space_id
                    or type(page.version) is not int or page.version < 1):
                reject("invalidPage")
            return page
        except (KeyError, TypeError, AttributeError):
            raise TransportError("invalidPage") from None


def check_policy(body, policy):
    if (not isinstance(policy, dict) or set(policy) != {
            "allowedSections", "protectedSections", "requiredText"}):
        reject("invalidPolicy")
    for key in policy:
        values = policy[key]
        if (not isinstance(values, list) or not values
                or not all(isinstance(x, str) and x.strip() for x in values)
                or len(values) != len(set(values))):
            reject("invalidPolicy")
    if set(policy["allowedSections"]) & set(policy["protectedSections"]):
        reject("invalidPolicy")
    doc, parts = sections(body)
    if not set(policy["allowedSections"] + policy["protectedSections"]) <= set(parts):
        reject("missingSection")
    visible = text_content(doc)
    if not all(marker in visible for marker in policy["requiredText"]):
        reject("missingInvariant")
    return doc, parts


def validate(before, candidate, policy):
    if before.status != "current" or before.identity() != candidate.identity():
        reject("unexpectedIdentity")
    if before.version != candidate.version:
        reject("unexpectedVersion")
    old_doc, old = check_policy(before.body, policy)
    new_doc, new = check_policy(candidate.body, policy)
    if (list(old) != list(new)
            or encode({k: v for k, v in old_doc.items() if k != "content"})
            != encode({k: v for k, v in new_doc.items() if k != "content"})):
        reject("unexpectedStructure")
    changes = []
    for index, (name, nodes) in enumerate(old.items()):
        # Python equality aliases True/1/1.0; protected JSON must not do so.
        if encode(nodes) == encode(new[name]):
            continue
        if name not in policy["allowedSections"]:
            reject("unintendedDiff")
        # The heading itself is not mutable even inside an allowed section.
        if encode(nodes[0]) != encode(new[name][0]):
            reject("unexpectedStructure")
        changes.append({"sectionIndex": index, "beforeHash": digest(encode(nodes)),
                        "afterHash": digest(encode(new[name]))})
    if not changes:
        reject("noStructuralChange")
    return changes


class Journal:
    """Independent private files; exclusive writes plus fsync before any PUT.

    Local files are trusted operator inputs, not a second canonical source.
    A process lock prevents two invocations from reconciling an in-flight PUT.
    """

    def __init__(self, path):
        self.path = Path(path)
        info = self.path.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) & 0o077):
            reject("unsafeSnapshotDirectory")
        resolved = self.path.resolve(strict=True)
        if any((parent / ".git").exists() for parent in (resolved, *resolved.parents)):
            reject("snapshotInsideRepository")

    @classmethod
    def create(cls, root):
        root = Path(root).resolve(strict=True)
        if any((parent / ".git").exists() for parent in (root, *root.parents)):
            reject("snapshotInsideRepository")
        journal = cls(tempfile.mkdtemp(prefix="canonical-guard-", dir=root))
        directory = os.open(root, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        return journal

    def save(self, name, value):
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        fd = os.open(self.path / name, flags, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(encode(value))
            stream.flush()
            os.fsync(stream.fileno())
        directory = os.open(self.path, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)

    def read(self, name):
        fd = os.open(self.path / name, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "r", encoding="utf-8", newline="") as stream:
            info = os.fstat(stream.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) & 0o077):
                reject("unsafeSnapshotFile")
            return decode(stream.read())

    def exists(self, name):
        return (self.path / name).exists()

    @contextmanager
    def lock(self):
        fd = os.open(self.path / "lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                reject("operationInProgress")
            yield
        finally:
            os.close(fd)


def capture(transport, page_id, policy, root, code_ref):
    page = transport.get(page_id)
    if page.id != page_id or page.status != "current":
        reject("unexpectedIdentity")
    check_policy(page.body, policy)
    journal = Journal.create(root)
    journal.save("snapshot.json", {
        "schemaVersion": 1, "toolVersion": TOOL_VERSION, "codeRef": code_ref,
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "site": transport.site, "operationId": str(uuid.uuid4()),
        "page": asdict(page), "bodyHash": digest(page.body),
        "policy": policy, "policyHash": digest(encode(policy))})
    return journal


def apply(transport, journal, body, code_ref=None):
    with journal.lock():
        snapshot = journal.read("snapshot.json")
        before = Page(**snapshot["page"])
        policy = snapshot["policy"]
        if (snapshot["schemaVersion"] != 1 or snapshot["toolVersion"] != TOOL_VERSION
                or snapshot["site"] != transport.site
                or snapshot["bodyHash"] != digest(before.body)
                or snapshot["policyHash"] != digest(encode(policy))):
            reject("snapshotMismatch")
        candidate = replace(before, body=body)
        changes = validate(before, candidate, policy)
        plan = {"body": body, "bodyHash": digest(body), "changes": changes}
        if journal.exists("plan.json"):
            if journal.read("plan.json") != plan:
                reject("operationCollision")
        else:
            journal.save("plan.json", plan)
        snapshot = {**snapshot, "executionCodeRef": code_ref or snapshot["codeRef"]}
        if journal.exists("outcome.json"):
            return journal.read("outcome.json")
        message = "cfg-guard:" + snapshot["operationId"]
        if not journal.exists("attempt.json"):
            current = transport.get(before.id)
            if current != before:
                reject("concurrentEdit")
            # Read-back of the durable capture completed before this marker.
            journal.save("attempt.json", {"expectedVersion": before.version,
                                         "message": message})
            try:
                transport.put(candidate, before.version, message)
            except TransportError:
                # Includes unknown ACK, HTTP errors and malformed responses.
                # Reconcile by GET; never blindly send the same PUT again.
                pass
        return reconcile(transport, journal, snapshot, before, candidate, message)


def finish(journal, snapshot, before, candidate, status, observed=None, history=None):
    outcome = {
        "toolVersion": TOOL_VERSION, "codeRef": snapshot["executionCodeRef"],
        "captureCodeRef": snapshot["codeRef"],
        "operationClass": "statusEvidence", "operationId": snapshot["operationId"],
        "pageId": before.id, "predecessorVersion": before.version,
        "expectedSuccessorVersion": before.version + 1,
        "observedVersion": observed.version if observed else None,
        "predecessorHash": digest(before.body), "intendedHash": digest(candidate.body),
        "observedHash": digest(observed.body) if observed else None,
        "verification": status, "history": history or "notVerified",
        "rollback": ("verified" if status == "rolledBack" else
                     "unverified" if journal.exists("rollback-attempt.json") else "notAttempted"),
    }
    journal.save("outcome.json", outcome)
    return outcome


def reconcile(transport, journal, snapshot, before, candidate, message):
    try:
        current = transport.get(before.id)
    except TransportError:
        # Keep the attempt unfinished so a later apply can GET-only reconcile.
        reject("verificationUnavailable")
    if journal.exists("rollback-attempt.json"):
        if (current.version == before.version + 2
                and current.message == message + ":rollback"
                and current.same_content(before)):
            return finish(journal, snapshot, before, candidate, "rolledBack", current)
        return finish(journal, snapshot, before, candidate, "quarantined", current)
    if current == before:
        return finish(journal, snapshot, before, candidate, "notApplied", current)
    owned = current.version == before.version + 1 and current.message == message
    if not owned:
        return finish(journal, snapshot, before, candidate, "quarantined", current)
    if current.same_content(candidate):
        check_policy(current.body, snapshot["policy"])
        history = "unavailable"
        try:
            predecessor = transport.history(before.id, before.version)
            successor = transport.history(before.id, current.version)
            if (predecessor.version != before.version
                    or not predecessor.same_content(before)
                    or successor != current):
                return finish(journal, snapshot, before, candidate, "quarantined", current,
                              "mismatch")
            history = "verified"
        except TransportError:
            pass  # G8 is supporting evidence, not a substitute for G1/G6.
        except GuardError:
            return finish(journal, snapshot, before, candidate, "quarantined", current,
                          "mismatch")
        return finish(journal, snapshot, before, candidate, "verified", current, history)
    if journal.exists("failed-write.json"):
        if journal.read("failed-write.json") != asdict(current):
            return finish(journal, snapshot, before, candidate, "quarantined", current)
    else:
        journal.save("failed-write.json", asdict(current))
    # Identity/ownership moves are not repaired by this status-only tool.
    if current.identity() != before.identity():
        return finish(journal, snapshot, before, candidate, "quarantined", current)
    try:
        fresh = transport.get(before.id)
    except TransportError:
        return finish(journal, snapshot, before, candidate, "quarantined", current)
    if fresh != current:
        return finish(journal, snapshot, before, candidate, "quarantined", fresh)
    journal.save("rollback-attempt.json", {"expectedVersion": current.version,
                                          "bodyHash": digest(before.body)})
    try:
        transport.put(before, current.version, message + ":rollback")
    except TransportError:
        pass
    # Re-read even after an ambiguous rollback ACK; never repeat compensation.
    return reconcile(transport, journal, snapshot, before, candidate, message)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise TransportError("redirectRejected")


class Confluence:
    """Explicit next-version REST writer; no automatic retries or redirects."""

    def __init__(self, site, email, token):
        parsed = urllib.parse.urlsplit(site)
        if (parsed.scheme != "https" or not parsed.hostname
                or not parsed.hostname.endswith(".atlassian.net")
                or parsed.username or parsed.password or parsed.port not in (None, 443)
                or parsed.path not in ("", "/") or parsed.query or parsed.fragment):
            reject("invalidSite")
        if not email or not token or ":" in email or "\n" in email or "\n" in token:
            reject("missingCredentials")
        self.site = "https://" + parsed.hostname
        self._authorization = "Basic " + base64.b64encode(
            (email + ":" + token).encode("utf-8")).decode("ascii")
        self._opener = urllib.request.build_opener(NoRedirect())

    def _request(self, method, path, payload=None):
        request = urllib.request.Request(
            self.site + "/wiki/api/v2" + path,
            data=encode(payload).encode("utf-8") if payload is not None else None,
            headers={"Authorization": self._authorization, "Accept": "application/json",
                     "Content-Type": "application/json"}, method=method)
        try:
            with self._opener.open(request, timeout=30) as response:
                raw = response.read(MAX_RESPONSE_BYTES + 1)
                if len(raw) > MAX_RESPONSE_BYTES:
                    raise TransportError("responseTooLarge")
                return decode(raw.decode("utf-8"))
        except (OSError, ValueError, http.client.HTTPException, GuardError):
            # Do not expose exception text, URL queries, bodies or credentials.
            raise TransportError("transportFailure") from None

    def get(self, page_id, version=None):
        if not re.fullmatch(r"[0-9]+", page_id):
            reject("invalidPageId")
        query = "?body-format=atlas_doc_format"
        if version is not None:
            query += "&version=" + str(version)
        page = Page.from_api(self._request("GET", "/pages/" + page_id + query))
        if page.id != page_id:
            raise TransportError("unexpectedIdentity")
        return page

    def put(self, page, expected_version, message):
        self._request("PUT", "/pages/" + page.id, {
            "id": page.id, "status": page.status, "title": page.title,
            "body": {"representation": "atlas_doc_format", "value": page.body},
            "version": {"number": expected_version + 1, "message": message}})

    def history(self, page_id, version):
        metadata = self._request("GET", "/pages/" + page_id + "/versions/" + str(version))
        page = self.get(page_id, version)
        if (not isinstance(metadata, dict) or metadata.get("number") != version
                or page.version != version or metadata.get("message", "") != page.message):
            reject("historyMismatch")
        return page


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", required=True)
    commands = parser.add_subparsers(dest="command", required=True)
    capture_parser = commands.add_parser("capture", help="GET-only independent snapshot")
    capture_parser.add_argument("--page-id", required=True)
    capture_parser.add_argument("--policy", required=True)
    capture_parser.add_argument("--snapshot-root", required=True)
    apply_parser = commands.add_parser("apply", help="one guarded write / GET-only reconciliation")
    apply_parser.add_argument("--snapshot", required=True)
    apply_parser.add_argument("--candidate", required=True, help="exact UTF-8 ADF body file")
    args = parser.parse_args(argv)
    try:
        client = Confluence(args.site, os.environ.get("CONFLUENCE_EMAIL"),
                            os.environ.get("CONFLUENCE_API_TOKEN"))
        repo = Path(__file__).resolve().parent.parent
        ref = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True,
                             capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                               check=True, capture_output=True, text=True).stdout
        code_ref = ref + ("-dirty" if dirty else "")
        if args.command == "capture":
            policy = decode(Path(args.policy).read_text(encoding="utf-8"))
            journal = capture(client, args.page_id, policy, args.snapshot_root, code_ref)
            print(encode({"verification": "captured", "snapshot": str(journal.path),
                          "toolVersion": TOOL_VERSION, "codeRef": code_ref}))
            return 0
        # newline='' preserves the intended body bytes across platforms.
        with open(args.candidate, encoding="utf-8", newline="") as stream:
            body = stream.read()
        result = apply(client, Journal(args.snapshot), body, code_ref)
        print(encode(result))
        return 0 if result["verification"] == "verified" else 1
    except GuardError as error:
        print(encode({"verification": "blocked", "reason": str(error)}), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError, RecursionError, subprocess.SubprocessError):
        print(encode({"verification": "blocked", "reason": "localFailure"}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
