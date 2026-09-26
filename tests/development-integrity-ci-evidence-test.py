#!/usr/bin/env python3
"""Offline tests for the Development Integrity CI evidence record builder."""

import importlib.util
import json
import os
import stat
import sys
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
