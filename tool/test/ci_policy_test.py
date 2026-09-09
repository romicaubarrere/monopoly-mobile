"""Exercise the real CI policy script without Git, dependencies or network.

The pinning fixtures cover the repository's line-oriented block-style `uses:`
declarations, not a complete YAML parser: aliases and flow mappings are outside
this lexical gate's contract. Every subprocess operates on disposable copies;
the repository workflows are read-only inputs to the mutation regression.
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tool/check_ci_policy.sh"
SHA = "0123456789abcdef" * 2 + "01234567"
ACTION = "actions/checkout"
REUSABLE = "example/project/.github/workflows/quality.yml"
USES_LINE = re.compile(r"^(\s*(?:-\s+)?uses:\s*)(\S+)(.*)$")


def workflow(value=None, style="named", permissions="  contents: read\n", ref=None):
    header = "name: Fixture\non: push\npermissions:\n" + permissions + "jobs:\n"
    if style == "job":
        return header + f"  quality:\n    uses: {value}\n"
    steps = "  quality:\n    runs-on: ubuntu-latest\n    steps:\n"
    if value is None:
        return header + steps + "      - run: true\n"
    if style == "named":
        steps += f"      - name: Checkout\n        uses: {value}\n"
    elif style == "unnamed":
        steps += f"      - uses: {value}\n"
    else:
        raise ValueError("Unknown fixture style")
    if ref is not None:
        steps += f"        with:\n          ref: {ref}\n"
    return header + steps


def action_for(style):
    return REUSABLE if style == "job" else ACTION


def review_workflow(write_jobs=1):
    jobs = ""
    for index in range(write_jobs):
        jobs += (
            f"  review{index}:\n"
            "    runs-on: ubuntu-latest\n"
            "    permissions:\n"
            "      contents: read\n"
            "      pull-requests: write\n"
            "    steps:\n"
            f"      - uses: {ACTION}@{SHA}\n"
        )
    return "name: Review\non: pull_request\npermissions:\n  contents: read\njobs:\n" + jobs


class CiPolicyTests(unittest.TestCase):
    def run_policy(self, files):
        with tempfile.TemporaryDirectory(prefix="ci policy fixture ") as directory:
            root = Path(directory)
            (root / "tool").mkdir()
            shutil.copyfile(SCRIPT, root / "tool/check_ci_policy.sh")
            workflows = root / ".github/workflows"
            workflows.mkdir(parents=True)
            for name, source in {"ci.yml": workflow(), **files}.items():
                (workflows / name).write_text(source, encoding="utf-8")
            before = {path.relative_to(root): path.read_bytes()
                      for path in root.rglob("*") if path.is_file()}
            result = subprocess.run(
                ["bash", "tool/check_ci_policy.sh"], cwd=root,
                capture_output=True, text=True, timeout=10,
            )
            after = {path.relative_to(root): path.read_bytes()
                     for path in root.rglob("*") if path.is_file()}
            self.assertEqual(before, after, "The policy check must not edit its inputs")
            return result

    def assert_passes(self, files):
        result = self.run_policy(files)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("CI repository policy: PASS", result.stdout)

    def assert_rejected(self, files, message="full commit SHA"):
        result = self.run_policy(files)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertNotIn("CI repository policy: PASS", result.stdout)

    def test_current_repository_workflows_pass_unchanged(self):
        self.assert_passes(self.repository_workflows())

    def test_full_lowercase_sha_passes_in_both_extensions_and_all_styles(self):
        for extension in ("yml", "yaml"):
            for style in ("named", "unnamed", "job"):
                with self.subTest(extension=extension, style=style):
                    self.assert_passes({f"fixture.{extension}": workflow(
                        f"{action_for(style)}@{SHA}", style=style)})

    def test_single_and_double_quoted_sha_pass_in_all_styles(self):
        for quote in ("'", '"'):
            for style in ("named", "unnamed", "job"):
                with self.subTest(quote=quote, style=style):
                    self.assert_passes({"ci.yml": workflow(
                        f"{quote}{action_for(style)}@{SHA}{quote}", style=style)})

    def test_crlf_and_trailing_whitespace_preserve_valid_remote_pins(self):
        for style in ("named", "unnamed", "job"):
            with self.subTest(style=style):
                source = workflow(f"{action_for(style)}@{SHA}   ", style=style)
                self.assert_passes({"fixture.yaml": source.replace("\n", "\r\n")})

    def test_whitespace_and_comments_do_not_change_the_valid_action_value(self):
        for style in ("named", "unnamed", "job"):
            for quote in ("", "'", '"'):
                with self.subTest(style=style, quote=quote):
                    value = f"  {quote}{action_for(style)}@{SHA}{quote}   # release @main   "
                    self.assert_passes({"ci.yml": workflow(value, style=style)})

    def test_named_step_mutable_short_and_missing_refs_are_rejected(self):
        for extension in ("yml", "yaml"):
            for suffix in ("@main", "@v4", "@abcdef0", ""):
                with self.subTest(extension=extension, suffix=suffix):
                    self.assert_rejected({f"fixture.{extension}": workflow(ACTION + suffix)})

    def test_unnamed_step_mutable_short_and_missing_refs_remain_rejected(self):
        for suffix in ("@main", "@v4", "@abcdef0", ""):
            with self.subTest(suffix=suffix):
                self.assert_rejected({"ci.yml": workflow(ACTION + suffix, style="unnamed")})

    def test_reusable_workflow_mutable_short_and_missing_refs_are_rejected(self):
        for suffix in ("@main", "@v4", "@abcdef0", ""):
            with self.subTest(suffix=suffix):
                self.assert_rejected({"fixture.yaml": workflow(REUSABLE + suffix, style="job")})

    def test_quoted_mutable_refs_are_not_mistaken_for_pins(self):
        for quote in ("'", '"'):
            for style in ("named", "unnamed", "job"):
                with self.subTest(quote=quote, style=style):
                    self.assert_rejected({"ci.yml": workflow(
                        f"{quote}{action_for(style)}@main{quote}", style=style)})

    def test_unclosed_or_mismatched_quotes_cannot_disguise_a_reference(self):
        for style in ("named", "unnamed", "job"):
            for opening, closing in (("'", ""), ('"', ""), ("'", '"'), ('"', "'")):
                with self.subTest(style=style, opening=opening, closing=closing):
                    value = f"{opening}{action_for(style)}@{SHA}{closing}"
                    self.assert_rejected({"ci.yml": workflow(value, style=style)})

    def test_sha_in_comment_cannot_disguise_mutable_or_missing_ref(self):
        for style in ("named", "unnamed", "job"):
            for suffix in ("@main", ""):
                with self.subTest(style=style, suffix=suffix):
                    value = f"{action_for(style)}{suffix}  # decoy @{SHA}"
                    self.assert_rejected({"ci.yml": workflow(value, style=style)})

    def test_second_uses_in_comment_cannot_replace_mutable_or_missing_reference(self):
        for style in ("named", "unnamed", "job"):
            for marker in ("uses:", "- uses:"):
                for suffix in ("@main", ""):
                    with self.subTest(style=style, marker=marker, suffix=suffix):
                        value = (f"{action_for(style)}{suffix} # decoy: "
                                 f"{marker} {ACTION}@{SHA}")
                        self.assert_rejected({"ci.yml": workflow(value, style=style)})

    def test_second_mutable_uses_in_comment_does_not_replace_valid_reference(self):
        for style in ("named", "unnamed", "job"):
            for marker in ("uses:", "- uses:"):
                with self.subTest(style=style, marker=marker):
                    value = (f"{action_for(style)}@{SHA} # decoy: "
                             f"{marker} {ACTION}@main")
                    self.assert_passes({"ci.yml": workflow(value, style=style)})

    def test_entire_reference_is_validated_not_just_its_last_at_segment(self):
        for style in ("named", "unnamed", "job"):
            for suffix in (f"@{SHA}@extra", f"@{SHA}-suffix", f"@{SHA}0",
                           f"@{SHA[:-1]}", f"@{SHA.upper()}", f"@main@{SHA}",
                           f"@{SHA}@{SHA}"):
                with self.subTest(style=style, suffix=suffix):
                    self.assert_rejected({"ci.yml": workflow(
                        action_for(style) + suffix, style=style)})

    def test_sha_suffix_does_not_turn_a_local_path_into_a_remote_pin(self):
        for style in ("named", "unnamed", "job"):
            for local in ("./action", "../action"):
                with self.subTest(style=style, local=local):
                    self.assert_rejected({"ci.yml": workflow(f"{local}@{SHA}", style=style)})

    def test_comment_only_uses_line_is_not_an_action(self):
        self.assert_passes({"ci.yml": workflow() + "      # - uses: actions/checkout@main\n"})

    def test_readonly_permissions_and_single_existing_reviewdog_exception_pass(self):
        self.assert_passes({"ci.yml": workflow(f"{ACTION}@{SHA}", style="unnamed"),
                            "pr-review.yml": review_workflow()})

    def test_existing_explicit_write_permission_denials_remain_enforced(self):
        for permission in ("contents", "actions", "checks", "packages", "deployments",
                           "id-token", "pull-requests"):
            with self.subTest(permission=permission):
                self.assert_rejected({"ci.yml": workflow(
                    permissions=f"  {permission}: write\n")}, message="read-only")

    def test_reviewdog_write_exception_does_not_apply_to_another_workflow(self):
        self.assert_rejected({"other-review.yml": review_workflow()}, message="read-only")

    def test_two_reviewdog_write_exceptions_are_rejected(self):
        self.assert_rejected({"pr-review.yml": review_workflow(write_jobs=2)},
                             message="at most one")

    def test_hardcoded_checkout_refs_remain_rejected(self):
        for ref in ("main", "feat/example", SHA):
            with self.subTest(ref=ref):
                self.assert_rejected({"ci.yml": workflow(
                    f"{ACTION}@{SHA}", style="unnamed", ref=ref)},
                    message="must not hardcode")

    def test_dynamic_checkout_ref_remains_allowed(self):
        self.assert_passes({"ci.yml": workflow(
            f"{ACTION}@{SHA}", style="unnamed", ref="${{ github.sha }}")})

    def test_each_real_workflow_action_rejects_an_individual_main_mutation(self):
        originals = self.repository_workflows()
        references = []
        for name, source in originals.items():
            for index, line in enumerate(source.splitlines(keepends=True)):
                match = USES_LINE.fullmatch(line.rstrip("\n"))
                if match:
                    references.append((name, index, match))
        # This is the complete set at #108's baseline. New actions require this
        # evidence count to be deliberately refreshed rather than silently lost.
        self.assertEqual(19, len(references))
        for name, index, match in references:
            with self.subTest(workflow=name, line=index + 1):
                action, separator, ref = match[2].rpartition("@")
                self.assertEqual("@", separator)
                self.assertRegex(ref, r"^[0-9a-f]{40}$")
                lines = originals[name].splitlines(keepends=True)
                lines[index] = match[1] + action + "@main" + match[3] + "\n"
                mutated = {**originals, name: "".join(lines)}
                self.assert_rejected(mutated)
        self.assertEqual(originals, self.repository_workflows())

    @staticmethod
    def repository_workflows():
        return {path.name: path.read_text(encoding="utf-8")
                for path in sorted((ROOT / ".github/workflows").iterdir())
                if path.suffix in (".yml", ".yaml")}


if __name__ == "__main__":
    unittest.main()
