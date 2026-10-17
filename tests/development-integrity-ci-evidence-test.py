#!/usr/bin/env python3
"""Offline tests for the Development Integrity CI evidence record builder."""

import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.dont_write_bytecode = True

SCRIPT = (
    Path(__file__).resolve().parent.parent
    / "scripts"
    / "development-integrity-ci-evidence.py"
)
SPEC = importlib.util.spec_from_file_location("ci_evidence", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

REPOSITORY = "noxyzone/nocturnalzone"
OPERATION = "AGENTOPS-64-cutover-v1"
COMPONENT = "main-development-chain"
HEAD_SHA = "a" * 40
CHECKOUT_TREE = "b" * 40
GUARDRAILS_SHA = "c" * 40

# The exact evidence entry the aggregate derives the archive record from.
CONSUMER_EVIDENCE = {
    "id": "ci-quality-gates-1001-1",
    "surface": "ci-artifact",
    "componentID": COMPONENT,
    "operationID": OPERATION,
    "revision": HEAD_SHA,
    "status": "success",
    "terminal": True,
    "locator": "ci-artifact:quality-gates:1001:1",
    "artifactPath": "development-integrity/evidence/ci-artifact.json",
    "artifactHash": "d" * 64,
    "provenance": {"classification": "production-evidence", "synthetic": False},
}


def locate_aggregate():
    override = os.environ.get("NUZ_CANDIDATE_AGGREGATE")
    if override:
        path = Path(override)
        return path if path.is_file() else None
    relative = (
        Path("candidates")
        / "development-integrity"
        / "bin"
        / "development-integrity-aggregate.py"
    )
    for base in Path(__file__).resolve().parents:
        candidate = base / relative
        if candidate.is_file():
            return candidate
    return None


AGGREGATE = locate_aggregate()
AGGREGATE_MODULE = None
if AGGREGATE is not None:
    AGGREGATE_SPEC = importlib.util.spec_from_file_location("aggregate", AGGREGATE)
    AGGREGATE_MODULE = importlib.util.module_from_spec(AGGREGATE_SPEC)
    AGGREGATE_SPEC.loader.exec_module(AGGREGATE_MODULE)


def base_args(**overrides):
    args = {
        "repository": REPOSITORY,
        "operation_id": OPERATION,
        "component_id": COMPONENT,
        "event": "push",
        "branch": "main",
        "run_id": 1001,
        "attempt": 1,
        "head_sha": HEAD_SHA,
        "checkout_tree": CHECKOUT_TREE,
        "guardrails_sha": GUARDRAILS_SHA,
        "detect_result": "success",
        "ubuntu_result": "success",
        "macos_result": "success",
        "ubuntu_applicable": True,
        "macos_applicable": True,
    }
    args.update(overrides)
    return args


class BuildTest(unittest.TestCase):
    def test_success_builds_flat_record(self):
        record = MODULE.build_record(**base_args())
        self.assertEqual(record["status"], "success")
        self.assertEqual(record["id"], "ci-quality-gates-1001-1")
        self.assertEqual(record["componentID"], COMPONENT)
        self.assertEqual(record["operationID"], OPERATION)
        self.assertEqual(record["revision"], HEAD_SHA)
        self.assertEqual(record["locator"], "ci-artifact:quality-gates:1001:1")

    def test_record_has_exact_consumer_key_set(self):
        record = MODULE.build_record(**base_args())
        self.assertEqual(
            set(record),
            {
                "id",
                "componentID",
                "operationID",
                "revision",
                "status",
                "terminal",
                "locator",
            },
        )
        self.assertIs(record["terminal"], True)

    @unittest.skipIf(AGGREGATE_MODULE is None, "aggregate candidate not available")
    def test_consumer_derivation_matches_exact_record(self):
        """The aggregate compares archive JSON to this derived dict verbatim."""
        record = MODULE.build_record(**base_args())
        expected = AGGREGATE_MODULE.artifact_record_from_evidence(CONSUMER_EVIDENCE)
        self.assertEqual(record, expected)
        self.assertEqual(
            MODULE.canonical_bytes(record), MODULE.canonical_bytes(expected)
        )

    @unittest.skipIf(AGGREGATE_MODULE is None, "aggregate candidate not available")
    def test_output_file_bytes_equal_consumer_object(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "record.json"
            MODULE.write_record(target, MODULE.build_record(**base_args()))
            archive_json = json.loads(target.read_text())
            expected = AGGREGATE_MODULE.artifact_record_from_evidence(CONSUMER_EVIDENCE)
            self.assertEqual(archive_json, expected)

    def test_deterministic_identical_output(self):
        first = MODULE.build_record(**base_args())
        second = MODULE.build_record(**base_args())
        self.assertEqual(MODULE.canonical_bytes(first), MODULE.canonical_bytes(second))

    def test_no_wrapper_or_hash_fields(self):
        record = MODULE.build_record(**base_args())
        for forbidden in (
            "artifactHash",
            "claim",
            "jobs",
            "subject",
            "run",
            "record",
            "schemaVersion",
            "kind",
        ):
            self.assertNotIn(forbidden, record)


class RejectTest(unittest.TestCase):
    def test_cli_boolean_accepts_only_exact_values(self):
        self.assertIs(MODULE.parse_boolean("true"), True)
        self.assertIs(MODULE.parse_boolean("false"), False)
        for value in ("", "unknown", "True", " false "):
            with self.assertRaises(ValueError):
                MODULE.parse_boolean(value)

    def assert_rejected(self, **overrides):
        with self.assertRaises(MODULE.Reject):
            MODULE.build_record(**base_args(**overrides))

    def test_rejects_other_repository(self):
        self.assert_rejected(repository="noxyzone/other")

    def test_rejects_non_push_event(self):
        self.assert_rejected(event="pull_request")

    def test_rejects_non_main_branch(self):
        self.assert_rejected(branch="develop")

    def test_rejects_second_attempt(self):
        self.assert_rejected(attempt=2)

    def test_rejects_missing_run_id(self):
        self.assert_rejected(run_id=0)

    def test_rejects_short_head_sha(self):
        self.assert_rejected(head_sha="abc123")

    def test_rejects_missing_checkout_tree(self):
        self.assert_rejected(checkout_tree="")

    def test_rejects_upper_case_tree(self):
        self.assert_rejected(checkout_tree="B" * 40)

    def test_rejects_garbage_guardrails_sha(self):
        self.assert_rejected(guardrails_sha="nightly")

    def test_rejects_failed_detect(self):
        self.assert_rejected(detect_result="failure")

    def test_rejects_cancelled_job(self):
        self.assert_rejected(ubuntu_result="cancelled")

    def test_rejects_unknown_job(self):
        self.assert_rejected(macos_result="unknown")

    def test_rejects_skipped_but_applicable(self):
        self.assert_rejected(ubuntu_result="skipped", ubuntu_applicable=True)

    def test_rejects_success_without_applicability(self):
        self.assert_rejected(ubuntu_result="success", ubuntu_applicable=False)

    def test_allows_skipped_when_not_applicable(self):
        record = MODULE.build_record(
            **base_args(macos_result="skipped", macos_applicable=False)
        )
        self.assertEqual(record["status"], "success")

    def test_rejects_invalid_component_id(self):
        self.assert_rejected(component_id="Main Development")

    def test_rejects_empty_operation_id(self):
        self.assert_rejected(operation_id="")


class WorkflowContextTest(unittest.TestCase):
    workflow = SCRIPT.parent.parent / ".github/workflows/quality-gates.yml"

    def input_defaults(self):
        source = self.workflow.read_text()
        defaults = {}
        for name, body in re.findall(
            r"^      (development-integrity-[\w-]+):\n(.*?)(?=^      \S|^jobs:)",
            source,
            re.M | re.S,
        ):
            value = re.search(r"^        default: (.*)$", body, re.M).group(1)
            defaults[name] = value.strip("\"'")
            self.assertRegex(body, r"(?m)^        required: false$")
            expected_type = "boolean" if name.endswith("-evidence") else "string"
            self.assertRegex(body, rf"(?m)^        type: {expected_type}$")
        self.assertEqual(defaults["development-integrity-evidence"], "false")
        for name in ("operation", "component"):
            self.assertEqual(defaults[f"development-integrity-{name}-id"], "")
        return defaults

    def step(self, name, inputs):
        source = self.workflow.read_text()
        match = re.search(
            rf"^      - name: {re.escape(name)}\n(.*?)(?=^      - name:|\Z)",
            source,
            re.M | re.S,
        )
        self.assertIsNotNone(match, name)
        body = match.group(1)
        run = textwrap.dedent(body.split("        run: |\n", 1)[1])
        self.assertNotIn("${{", run)
        env = {}
        for variable, key in re.findall(
            r"^          (\w+): \$\{\{ inputs\.([\w-]+) \}\}$", body, re.M
        ):
            env[variable] = inputs[key]
        return run, env

    def execute(self, name, inputs):
        run, env = self.step(name, inputs)
        with TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / ".guardrails").symlink_to(SCRIPT.parent.parent)
            tools = root / "tools"
            tools.mkdir()
            git = tools / "git"
            git.write_text(
                "#!/usr/bin/env bash\nset -euo pipefail\n"
                'case "$*" in\n'
                "  'rev-parse HEAD')\n"
                '    if [[ "$PWD" == "$GITHUB_WORKSPACE" ]]; then\n'
                '      printf "%s\\n" "$GITHUB_SHA"\n'
                '    else printf "%s\\n" "$TEST_GUARDRAILS_SHA"; fi ;;\n'
                "  'rev-parse HEAD^{tree}') printf '%s\\n' "
                f"'{CHECKOUT_TREE}' ;;\n"
                "  'rev-parse --show-toplevel') "
                'printf "%s\\n" "$GITHUB_WORKSPACE" ;;\n'
                "  *) exit 97 ;;\nesac\n"
            )
            git.chmod(0o700)
            script = root / "step.sh"
            script.write_text(run)
            environment = {
                **os.environ,
                "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                "RUNNER_TEMP": str(root),
                "GITHUB_WORKSPACE": str(root),
                "GITHUB_SHA": HEAD_SHA,
                "GITHUB_REPOSITORY": REPOSITORY,
                "GITHUB_EVENT_NAME": "push",
                "GITHUB_REF_NAME": "main",
                "GITHUB_RUN_ID": "1001",
                "GITHUB_RUN_ATTEMPT": "1",
                "WORKFLOW_JOB_CONTEXT": json.dumps({"workflow_sha": GUARDRAILS_SHA}),
                "TEST_GUARDRAILS_SHA": GUARDRAILS_SHA,
                "DETECT_RESULT": "success",
                "UBUNTU_RESULT": "success",
                "MACOS_RESULT": "success",
                "UBUNTU_APPLICABLE": "true",
                "MACOS_APPLICABLE": "true",
                **env,
            }
            result = subprocess.run(
                ["bash", str(script)], cwd=root, env=environment, capture_output=True
            )
            target = root / "development-integrity" / "ci-evidence.json"
            raw = target.read_bytes() if target.exists() else None
            return result, raw

    def test_workflow_defaults_and_explicit_context(self):
        defaults = self.input_defaults()
        cases = [("", "", OPERATION, COMPONENT)]
        cases.extend(
            (
                f"{chain}.NZ-158.test",
                f"{chain}-development-chain",
                f"{chain}.NZ-158.test",
                f"{chain}-development-chain",
            )
            for chain in ("jira", "quick")
        )
        # The builder is not an authorization allowlist for chain names.
        cases.append(
            ("other.operation", "other-component", "other.operation", "other-component")
        )
        for operation, component, expected_operation, expected_component in cases:
            with self.subTest(operation=operation):
                inputs = {**defaults, "development-integrity-evidence": "true"}
                if operation:
                    inputs["development-integrity-operation-id"] = operation
                    inputs["development-integrity-component-id"] = component
                result, raw = self.execute(
                    "Create Development Integrity CI evidence", inputs
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = MODULE.build_record(
                    **base_args(
                        operation_id=expected_operation, component_id=expected_component
                    )
                )
                self.assertEqual(raw, MODULE.canonical_bytes(expected) + b"\n")
                self.assertEqual(len(json.loads(raw)), 7)
                self.assertIsNotNone(AGGREGATE_MODULE, "Aggregate must run, not skip")
                evidence = {
                    **CONSUMER_EVIDENCE,
                    "operationID": expected_operation,
                    "componentID": expected_component,
                }
                self.assertEqual(
                    json.loads(raw),
                    AGGREGATE_MODULE.artifact_record_from_evidence(evidence),
                )

    def test_workflow_rejects_partial_and_invalid_context(self):
        defaults = self.input_defaults()
        for operation, component in (
            ("native", ""),
            ("", "main-development-chain"),
            (" ", "main-development-chain"),
            ("native", " main-development-chain"),
            ("bad/operation", "main-development-chain"),
            ("native", "Bad_Component"),
        ):
            with self.subTest(operation=operation, component=component):
                result, raw = self.execute(
                    "Create Development Integrity CI evidence",
                    {
                        **defaults,
                        "development-integrity-evidence": "true",
                        "development-integrity-operation-id": operation,
                        "development-integrity-component-id": component,
                    },
                )
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(b"ci-evidence: result=blocked reason=", result.stderr)
                self.assertIsNone(raw)

    def test_disabled_context_guard_executes_actual_step(self):
        defaults = self.input_defaults()
        for flag, operation, component, allowed in (
            ("false", "", "", True),
            ("false", "native", "", False),
            ("false", "", "main-development-chain", False),
            ("false", "native", "main-development-chain", False),
            ("false", " ", "", False),
            ("true", "native", "main-development-chain", True),
            ("true", "", "", True),
        ):
            with self.subTest(flag=flag, operation=operation, component=component):
                result, raw = self.execute(
                    "Validate Development Integrity context inputs",
                    {
                        **defaults,
                        "development-integrity-evidence": flag,
                        "development-integrity-operation-id": operation,
                        "development-integrity-component-id": component,
                    },
                )
                self.assertEqual(result.returncode == 0, allowed, result.stderr)
                self.assertIsNone(raw)

    def test_cli_context_flags_remain_required(self):
        for flag in ("--operation-id", "--component-id"):
            argv = []
            for key, value in base_args().items():
                option = "--" + key.replace("_", "-")
                if option != flag:
                    argv.extend(
                        (
                            option,
                            str(value).lower()
                            if isinstance(value, bool)
                            else str(value),
                        )
                    )
            argv.extend(("--output", "unused.json"))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), *argv], capture_output=True
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn(flag.encode(), result.stderr)

    def test_direct_api_does_not_default_or_accept_wrong_types(self):
        for operation, component in (
            ("", ""),
            (None, COMPONENT),
            (OPERATION, None),
            (True, COMPONENT),
            (OPERATION, 1),
        ):
            with self.subTest(operation=operation, component=component):
                with self.assertRaises(MODULE.Reject):
                    MODULE.build_record(
                        **base_args(operation_id=operation, component_id=component)
                    )


class OutputTest(unittest.TestCase):
    def test_output_is_canonical_json_obsessively_stable(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "record.json"
            record = MODULE.build_record(**base_args())
            MODULE.write_record(target, record)
            raw = target.read_bytes()
            self.assertEqual(raw, MODULE.canonical_bytes(record) + b"\n")
            # canonical: sorted keys, no spaces, newline-terminated
            self.assertEqual(
                raw.decode("utf-8"),
                '{"componentID":"main-development-chain",'
                '"id":"ci-quality-gates-1001-1",'
                '"locator":"ci-artifact:quality-gates:1001:1",'
                '"operationID":"AGENTOPS-64-cutover-v1",'
                '"revision":"' + HEAD_SHA + '",'
                '"status":"success","terminal":true}\n',
            )

    def test_rejects_existing_output(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "record.json"
            target.write_text("{}\n")
            with self.assertRaises(MODULE.Reject):
                MODULE.write_record(target, MODULE.build_record(**base_args()))
            self.assertEqual(target.read_text(), "{}\n")

    def test_rejects_symlink_output(self):
        with TemporaryDirectory() as tmp:
            real = Path(tmp) / "real.json"
            real.write_text("{}\n")
            link = Path(tmp) / "link.json"
            link.symlink_to(real)
            with self.assertRaises(MODULE.Reject):
                MODULE.write_record(link, MODULE.build_record(**base_args()))
            self.assertEqual(real.read_text(), "{}\n")

    def test_writes_create_only_0600(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "nested" / "record.json"
            record = MODULE.build_record(**base_args())
            MODULE.write_record(target, record)
            mode = stat.S_IMODE(target.stat().st_mode)
            self.assertEqual(mode, 0o600)
            self.assertEqual(json.loads(target.read_text()), record)

    def test_no_partial_output_when_output_exists(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "record.json"
            target.write_text("sentinel\n")
            with self.assertRaises(MODULE.Reject):
                MODULE.write_record(target, MODULE.build_record(**base_args()))
            self.assertEqual(target.read_text(), "sentinel\n")
            self.assertEqual([p.name for p in Path(tmp).iterdir()], ["record.json"])

    def test_no_output_written_when_validation_fails(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "record.json"
            with self.assertRaises(MODULE.Reject):
                MODULE.build_record(**base_args(ubuntu_result="failure"))
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
