"""Synthetic CFG-GUARD-01..12 evidence; no Atlassian credentials/network."""

from contextlib import redirect_stderr, redirect_stdout
from dataclasses import replace
import http.client
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import canonical_document_guard as guard


def paragraph(text):
    return {"type": "paragraph", "content": [{"type": "text", "text": text}]}


def heading(text):
    return {"type": "heading", "attrs": {"level": 2},
            "content": [{"type": "text", "text": text}]}


def body(status="Pending", registry="TV-01..TV-41", source="Rules v1.1"):
    # Explicit synthetic document, not a reconstruction of the real Manifest.
    return guard.encode({"type": "doc", "version": 1, "content": [
        heading("Registry"), paragraph(registry),
        heading("Sources"), paragraph(source),
        heading("Evidence"), paragraph(status)]})


POLICY = {"allowedSections": ["Evidence"],
          "protectedSections": ["Registry", "Sources"],
          "requiredText": ["TV-01..TV-41", "Rules v1.1"]}
PAGE = guard.Page(id="123", title="Synthetic controller", space_id="456",
                  status="current", version=7, body=body(), parent_id="1",
                  owner_id="synthetic-author", message="prior write")


class FakeConfluence:
    site = "https://synthetic.atlassian.net"

    def __init__(self):
        self.page = PAGE
        self.calls = []
        self.versions = {PAGE.version: PAGE}
        self.on_get = None
        self.on_put = None
        self.history_failure = False
        self.history_mismatch = False

    def get(self, page_id):
        self.calls.append("GET")
        if self.on_get:
            self.on_get(self)
        return self.page

    def put(self, page, expected_version, message):
        self.calls.append("PUT")
        if self.page.version != expected_version:
            raise guard.TransportError("concurrentEdit")
        self.page = replace(page, version=expected_version + 1, message=message)
        self.versions[self.page.version] = self.page
        if self.on_put:
            self.on_put(self)

    def history(self, page_id, version):
        self.calls.append("HISTORY")
        if self.history_failure:
            raise guard.TransportError("unavailable")
        page = self.versions[version]
        return replace(page, body=body("mismatch")) if self.history_mismatch else page


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.client = FakeConfluence()
        self.journal = guard.capture(self.client, PAGE.id, POLICY, self.temp.name, "synthetic-ref")
        self.candidate = body("Accepted")

    def apply(self):
        return guard.apply(self.client, self.journal, self.candidate)

    def assert_no_put(self):
        self.assertNotIn("PUT", self.client.calls)

    def corrupt_once(self, client):
        client.page = replace(client.page, body=body("corrupted"))
        client.on_put = None

    def test_CFG_GUARD_01_status_update_one_successor_and_durable_snapshot(self):
        result = self.apply()
        self.assertEqual("verified", result["verification"])
        self.assertEqual(8, self.client.page.version)
        self.assertEqual(self.candidate, self.client.page.body)
        self.assertEqual(["GET", "GET", "PUT", "GET", "HISTORY", "HISTORY"], self.client.calls)
        snapshot = self.journal.read("snapshot.json")
        self.assertEqual(PAGE.body, snapshot["page"]["body"])
        self.assertEqual(guard.digest(PAGE.body), snapshot["bodyHash"])
        self.assertEqual(POLICY, snapshot["policy"])
        self.assertEqual(0o700, stat.S_IMODE(self.journal.path.stat().st_mode))
        for file in self.journal.path.iterdir():
            self.assertEqual(0o600, stat.S_IMODE(file.stat().st_mode))
        self.assertEqual([3], [x["sectionIndex"] for x in self.journal.read("plan.json")["changes"]])

    def test_CFG_GUARD_02_stale_predecessor_zero_write(self):
        self.client.page = replace(PAGE, version=8)
        with self.assertRaisesRegex(guard.GuardError, "concurrentEdit"):
            self.apply()
        self.assert_no_put()

    def test_same_version_changed_body_also_fails_closed(self):
        self.client.page = replace(PAGE, body=body("unexpected"))
        with self.assertRaisesRegex(guard.GuardError, "concurrentEdit"):
            self.apply()
        self.assert_no_put()

    def test_CFG_GUARD_03_empty_and_whitespace_zero_write(self):
        for candidate in ("", "  \n\t", guard.encode({"type": "doc", "version": 1, "content": []})):
            with self.subTest(candidate=candidate), self.assertRaises(guard.GuardError):
                guard.apply(self.client, self.journal, candidate)
        self.assert_no_put()

    def test_CFG_GUARD_04_probe_zero_write(self):
        for candidate in ("noop", "PROBE", " test ", guard.encode({
                "type": "doc", "version": 1, "content": [paragraph("noop")]})):
            with self.subTest(candidate=candidate), self.assertRaises(guard.GuardError):
                guard.apply(self.client, self.journal, candidate)
        self.assert_no_put()

    def test_CFG_GUARD_05_missing_invariant_zero_write(self):
        with self.assertRaisesRegex(guard.GuardError, "missingInvariant"):
            guard.apply(self.client, self.journal, body("Accepted", registry="TV-01..TV-42"))
        self.assert_no_put()

    def test_CFG_GUARD_06_source_promotion_even_with_old_marker_retained(self):
        with self.assertRaisesRegex(guard.GuardError, "unintendedDiff"):
            guard.apply(self.client, self.journal, body("Accepted", source="Rules v1.1 + Rules v2.0"))
        self.assert_no_put()

    def test_unexpected_metadata_and_structure_are_rejected(self):
        for field, value in (("id", "999"), ("title", "replacement"), ("space_id", "999"),
                             ("status", "draft"), ("parent_id", "9"), ("owner_id", "other"),
                             ("version", 99)):
            with self.subTest(field=field), self.assertRaises(guard.GuardError):
                guard.validate(PAGE, replace(PAGE, body=self.candidate, **{field: value}), POLICY)
        candidate = json.loads(self.candidate)
        candidate["content"] += [heading("Unexpected"), paragraph("New scope")]
        with self.assertRaisesRegex(guard.GuardError, "unexpectedStructure"):
            guard.apply(self.client, self.journal, guard.encode(candidate))
        candidate["content"][-2] = heading("Evidence")
        with self.assertRaisesRegex(guard.GuardError, "ambiguousSection"):
            guard.apply(self.client, self.journal, guard.encode(candidate))
        self.assert_no_put()

    def test_CFG_GUARD_07_postwrite_mismatch_compensates_exactly(self):
        self.client.on_put = self.corrupt_once
        result = self.apply()
        self.assertEqual("rolledBack", result["verification"])
        self.assertEqual(2, self.client.calls.count("PUT"))
        self.assertEqual(9, self.client.page.version)
        self.assertTrue(PAGE.same_content(self.client.page))
        self.assertEqual(guard.digest(PAGE.body), result["observedHash"])
        self.assertTrue(self.journal.exists("failed-write.json"))

    def test_CFG_GUARD_08_ambiguous_ACK_reconciles_without_second_write(self):
        def lost_ack(client):
            raise guard.TransportError("ambiguous")
        self.client.on_put = lost_ack
        result = self.apply()
        self.assertEqual("verified", result["verification"])
        self.assertEqual(1, self.client.calls.count("PUT"))
        # Same durable operation is safe across a new journal/process instance.
        replay = guard.apply(self.client, guard.Journal(self.journal.path), self.candidate)
        self.assertEqual(result, replay)
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_crash_after_commit_before_verification_reconciles_on_restart(self):
        def crash(client):
            raise SystemExit("simulated process exit")
        self.client.on_put = crash
        with self.assertRaises(SystemExit):
            self.apply()
        self.client.on_put = None
        result = guard.apply(self.client, guard.Journal(self.journal.path), self.candidate)
        self.assertEqual("verified", result["verification"])
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_ambiguous_write_not_committed_never_retries_blindly(self):
        def no_commit(client):
            client.page = PAGE
            raise guard.TransportError("ambiguous")
        self.client.on_put = no_commit
        self.assertEqual("notApplied", self.apply()["verification"])
        self.assertEqual("notApplied", self.apply()["verification"])
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_CFG_GUARD_09_concurrent_edit_before_rollback_is_not_overwritten(self):
        def corrupt_then_race(client):
            self.corrupt_once(client)
            reads = []
            def race(c):
                reads.append(1)
                if len(reads) == 2:
                    c.page = replace(c.page, version=9, body=body("another writer"), message="external")
            client.on_get = race
        self.client.on_put = corrupt_then_race
        result = self.apply()
        self.assertEqual("quarantined", result["verification"])
        self.assertEqual(body("another writer"), self.client.page.body)
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_race_between_compare_and_PUT_uses_next_version_not_latest(self):
        original = self.client.put
        def racing_put(page, expected, message):
            self.client.page = replace(PAGE, version=8, body=body("other"), message="external")
            original(page, expected, message)
        self.client.put = racing_put
        self.assertEqual("quarantined", self.apply()["verification"])
        self.assertEqual(body("other"), self.client.page.body)

    def test_CFG_GUARD_10_history_metadata_and_bodies_verified(self):
        self.assertEqual("verified", self.apply()["history"])

    def test_history_mismatch_quarantines_without_rollback(self):
        self.client.history_mismatch = True
        result = self.apply()
        self.assertEqual("quarantined", result["verification"])
        self.assertEqual("mismatch", result["history"])
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_history_unavailable_does_not_misreport_supporting_evidence(self):
        self.client.history_failure = True
        self.assertEqual("unavailable", self.apply()["history"])

    def test_CFG_GUARD_11_rollback_lost_ACK_is_verified_not_repeated(self):
        def corrupt_then_lose_rollback_ack(client):
            self.corrupt_once(client)
            def lose(c):
                raise guard.TransportError("ambiguous")
            client.on_put = lose
        self.client.on_put = corrupt_then_lose_rollback_ack
        result = self.apply()
        self.assertEqual("rolledBack", result["verification"])
        self.assertEqual("verified", result["rollback"])
        self.assertEqual(2, self.client.calls.count("PUT"))
        self.assertTrue(self.client.page.same_content(PAGE))

    def test_bad_rollback_quarantines_without_recursive_repair(self):
        self.client.on_put = lambda c: setattr(c, "page", replace(c.page, body=body("bad")))
        result = self.apply()
        self.assertEqual("quarantined", result["verification"])
        self.assertEqual("unverified", result["rollback"])
        self.assertEqual(2, self.client.calls.count("PUT"))

    def test_crash_before_rollback_attempt_can_resume_from_failed_snapshot(self):
        self.client.on_put = self.corrupt_once
        save = self.journal.save
        def crash(name, value):
            if name == "rollback-attempt.json":
                raise SystemExit("simulated crash")
            return save(name, value)
        with patch.object(self.journal, "save", side_effect=crash):
            with self.assertRaises(SystemExit):
                self.apply()
        result = self.apply()
        self.assertEqual("rolledBack", result["verification"])
        self.assertEqual(2, self.client.calls.count("PUT"))

    def test_CFG_GUARD_12_unavailable_preflight_zero_write_and_offline_CI(self):
        def unavailable(client):
            raise guard.TransportError("unavailable")
        self.client.on_get = unavailable
        with self.assertRaises(guard.TransportError):
            self.apply()
        self.assert_no_put()
        # All tests in this suite use fake transport or mocked HTTP; no auth.

    def test_unavailable_after_PUT_resumes_by_GET_only(self):
        def lose_reads(client):
            client.on_get = lambda c: guard.reject("verificationUnavailable")
        self.client.on_put = lose_reads
        with self.assertRaisesRegex(guard.GuardError, "verificationUnavailable"):
            self.apply()
        self.client.on_get = None
        self.assertEqual("verified", self.apply()["verification"])
        self.assertEqual(1, self.client.calls.count("PUT"))

    def test_read_only_capture_does_not_write_remote(self):
        self.assertEqual(["GET"], self.client.calls)
        self.assertFalse(self.journal.exists("attempt.json"))

    def test_snapshot_disk_failure_prevents_PUT(self):
        with patch.object(self.journal, "save", side_effect=OSError("synthetic private path")):
            with self.assertRaises(OSError):
                self.apply()
        self.assert_no_put()

    def test_snapshot_tamper_and_different_candidate_fail_closed(self):
        self.apply()
        with self.assertRaisesRegex(guard.GuardError, "operationCollision"):
            guard.apply(self.client, self.journal, body("different"))
        snapshot = self.journal.read("snapshot.json")
        snapshot["bodyHash"] = "invalid"
        with patch.object(self.journal, "read", return_value=snapshot):
            with self.assertRaisesRegex(guard.GuardError, "snapshotMismatch"):
                self.apply()

    def test_concurrent_local_invocation_is_blocked(self):
        with self.journal.lock():
            with self.assertRaisesRegex(guard.GuardError, "operationInProgress"):
                guard.apply(self.client, guard.Journal(self.journal.path), self.candidate)
        self.assert_no_put()

    def test_outcomes_and_diff_do_not_log_bodies_credentials_or_titles(self):
        self.candidate = body("synthetic-confidential-note")
        result = self.apply()
        safe = guard.encode(result) + guard.encode(self.journal.read("plan.json")["changes"])
        for secret in (self.candidate, PAGE.body, PAGE.title, "synthetic-confidential-note"):
            self.assertNotIn(secret, safe)

    def test_snapshots_inside_repo_and_symlink_files_are_rejected(self):
        with self.assertRaisesRegex(guard.GuardError, "snapshotInsideRepository"):
            guard.Journal.create(Path(__file__).resolve().parents[2])
        link = self.journal.path / "linked.json"
        link.symlink_to(self.journal.path / "snapshot.json")
        with self.assertRaises(OSError):
            self.journal.read("linked.json")

    def test_duplicate_JSON_keys_and_permissive_policy_are_rejected(self):
        with self.assertRaisesRegex(guard.GuardError, "duplicateJsonKey"):
            guard.decode('{"version":1,"version":2}')
        for policy in ({}, {**POLICY, "requiredText": []},
                       {**POLICY, "allowedSections": ["Registry"]}):
            with self.assertRaises(guard.GuardError):
                guard.validate(PAGE, replace(PAGE, body=self.candidate), policy)

    def test_protected_JSON_types_cannot_alias_boolean_integer_or_float(self):
        old = json.loads(PAGE.body)
        old["content"][1]["attrs"] = {"syntheticValue": 1}
        before = replace(PAGE, body=guard.encode(old))
        for value in (True, 1.0):
            changed = json.loads(body("Accepted"))
            changed["content"][1]["attrs"] = {"syntheticValue": value}
            with self.subTest(value=value), self.assertRaisesRegex(guard.GuardError, "unintendedDiff"):
                guard.validate(before, replace(before, body=guard.encode(changed)), POLICY)

    def test_site_mismatch_never_reads_or_writes_other_tenant(self):
        other = FakeConfluence()
        other.site = "https://other.atlassian.net"
        with self.assertRaisesRegex(guard.GuardError, "snapshotMismatch"):
            guard.apply(other, self.journal, self.candidate)
        self.assertEqual([], other.calls)


class TransportTests(unittest.TestCase):
    def client(self):
        return guard.Confluence("https://synthetic.atlassian.net", "synthetic@example.invalid", "fake-token")

    def api_page(self, page=PAGE):
        return {"id": page.id, "title": page.title, "status": page.status,
                "spaceId": page.space_id, "parentId": page.parent_id, "ownerId": page.owner_id,
                "body": {"atlas_doc_format": {"value": page.body}},
                "version": {"number": page.version, "message": page.message}}

    def test_REST_exact_body_and_single_successor_payload(self):
        client = self.client()
        with patch.object(client, "_request", return_value={}) as request:
            client.put(PAGE, 7, "operation-marker")
        method, path, payload = request.call_args.args
        self.assertEqual(("PUT", "/pages/123"), (method, path))
        self.assertEqual({"number": 8, "message": "operation-marker"}, payload["version"])
        self.assertEqual(PAGE.body, payload["body"]["value"])
        self.assertEqual("atlas_doc_format", payload["body"]["representation"])
        self.assertNotIn("spaceId", payload)
        self.assertNotIn("ownerId", payload)

    def test_REST_history_uses_metadata_and_exact_version_body(self):
        client = self.client()
        with patch.object(client, "_request", side_effect=[
                {"number": 7, "message": PAGE.message}, self.api_page()]) as request:
            self.assertEqual(PAGE, client.history("123", 7))
        self.assertEqual("/pages/123/versions/7", request.call_args_list[0].args[1])
        self.assertEqual("/pages/123?body-format=atlas_doc_format&version=7",
                         request.call_args_list[1].args[1])

    def test_REST_rejects_redirects_insecure_sites_and_foreign_ids(self):
        for site in ("http://synthetic.atlassian.net", "https://evil.invalid",
                     "https://synthetic.atlassian.net.evil.invalid", "https://user@synthetic.atlassian.net",
                     "https://synthetic.atlassian.net?token=secret", "https://synthetic.atlassian.net:8443"):
            with self.subTest(site=site), self.assertRaises(guard.GuardError):
                guard.Confluence(site, "user", "fake")
        with self.assertRaises(guard.TransportError):
            guard.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid")
        client = self.client()
        with patch.object(client, "_request", return_value=self.api_page(replace(PAGE, id="999"))):
            with self.assertRaises(guard.TransportError):
                client.get("123")

    def test_REST_timeout_is_redacted_and_not_retried(self):
        client = self.client()
        with patch.object(client._opener, "open", side_effect=OSError("fake-token private-body")) as request:
            with self.assertRaises(guard.TransportError) as caught:
                client.put(PAGE, 7, "operation")
            self.assertEqual(1, request.call_count)
        self.assertEqual("transportFailure", str(caught.exception))

    def test_REST_serializes_real_request_and_bounds_decoding_without_network(self):
        client = self.client()
        response = io.BytesIO(guard.encode(self.api_page()).encode("utf-8"))
        with patch.object(client._opener, "open", return_value=response) as opener:
            self.assertEqual(PAGE, client.get("123"))
        request = opener.call_args.args[0]
        self.assertEqual("GET", request.method)
        self.assertEqual("https://synthetic.atlassian.net/wiki/api/v2/pages/123?body-format=atlas_doc_format",
                         request.full_url)
        self.assertEqual(30, opener.call_args.kwargs["timeout"])
        with patch.object(client._opener, "open", return_value=io.BytesIO(b"{}")) as opener:
            client.put(PAGE, 7, "operation")
        request = opener.call_args.args[0]
        self.assertEqual(PAGE.body, json.loads(request.data)["body"]["value"])
        for raw in (b"not-json", b"x" * (guard.MAX_RESPONSE_BYTES + 1)):
            with patch.object(client._opener, "open", return_value=io.BytesIO(raw)):
                with self.assertRaises(guard.TransportError):
                    client.get("123")

    def test_REST_metadata_mismatch_is_not_treated_as_history_outage(self):
        client = self.client()
        with patch.object(client, "_request", side_effect=[{"number": 8}, self.api_page()]):
            with self.assertRaisesRegex(guard.GuardError, "historyMismatch") as result:
                client.history("123", 7)
        self.assertNotIsInstance(result.exception, guard.TransportError)

    def test_REST_truncated_response_is_an_ambiguous_redacted_failure(self):
        client = self.client()
        with patch.object(client._opener, "open", side_effect=http.client.IncompleteRead(b"private")):
            with self.assertRaisesRegex(guard.TransportError, "transportFailure"):
                client.put(PAGE, 7, "operation")

    def test_CLI_missing_credentials_redacted_and_no_network(self):
        output = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), redirect_stderr(output), redirect_stdout(output):
            result = guard.main(["--site", "https://synthetic.atlassian.net", "capture",
                                 "--page-id", "123", "--policy", "unused", "--snapshot-root", "unused"])
        self.assertEqual(1, result)
        self.assertEqual({"verification": "blocked", "reason": "missingCredentials"},
                         json.loads(output.getvalue()))


if __name__ == "__main__":
    unittest.main()
