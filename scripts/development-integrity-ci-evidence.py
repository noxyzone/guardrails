#!/usr/bin/env python3
"""Build a deterministic CI evidence record for Development Integrity.

This offline builder produces exactly the flat CI archive record that the
opt-in QualityGates job publishes as the `quality-gates` artifact. The
aggregate consumer compares that archive file byte-for-byte to
``artifact_record_from_evidence(evidence)``, so the output object is the flat
record itself: no wrapper, no hash, no provenance, no job-result fields. Run
identity, subject revisions, and job applicability/results are validated
fail-closed before the output is created exactly once. This tool does not
activate Development Integrity, generate an Aggregate, or mutate any external
state; it also cannot independently verify the reported job results, which the
workflow inputs bind but the governing authority CLI does not re-check.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

ALLOWED_REPOSITORY = "noxyzone/nocturnalzone"
ALLOWED_EVENT = "push"
ALLOWED_BRANCH = "main"
ARTIFACT_NAME = "quality-gates"
SHA1 = re.compile(r"^[0-9a-f]{40}$")
IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")
COMPONENT_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SUCCESS = "success"
SKIPPED = "skipped"
REJECTED_RESULTS = {"failure", "cancelled", "unknown"}


class Reject(Exception):
    """Raised when an input cannot produce a valid CI evidence record."""


def canonical_bytes(value):
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def require_string(value, label, pattern=None):
    if not isinstance(value, str) or not value:
        raise Reject(f"{label} must be a non-empty string")
    if pattern is not None and pattern.fullmatch(value) is None:
        raise Reject(f"{label} has an invalid format")
    return value


def require_run_id(value):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise Reject("run-id must be a positive integer")
    return value


def require_attempt(value):
    if isinstance(value, bool) or not isinstance(value, int) or value != 1:
        raise Reject("attempt must be exactly 1")
    return value


def parse_boolean(value):
    if value not in {"true", "false"}:
        raise ValueError("applicability must be true or false")
    return value == "true"


def require_job(result, applicable, label):
    """Validate a declared job result and its applicability.

    These workflow inputs are checked here; the Aggregate authority does not
    independently verify individual job results from the remote run.
    """
    if result not in {SUCCESS, SKIPPED} | REJECTED_RESULTS:
        raise Reject(f"{label} result is not classified")
    if result in REJECTED_RESULTS:
        raise Reject(f"{label} is not successful")
    if result == SKIPPED:
        if applicable is not False:
            raise Reject(f"{label} is skipped but applicable")
    elif applicable is not True:
        raise Reject(f"{label} succeeded while marked not applicable")
    return {"result": result, "applicable": applicable}


def build_record(
    *,
    repository,
    operation_id,
    component_id,
    event,
    branch,
    run_id,
    attempt,
    head_sha,
    checkout_tree,
    guardrails_sha,
    detect_result,
    ubuntu_result,
    macos_result,
    ubuntu_applicable,
    macos_applicable,
):
    if repository != ALLOWED_REPOSITORY:
        raise Reject("repository is not the allowed identity")
    if event != ALLOWED_EVENT:
        raise Reject("event must be push")
    if branch != ALLOWED_BRANCH:
        raise Reject("branch must be main")
    run_id = require_run_id(run_id)
    attempt = require_attempt(attempt)
    operation_id = require_string(operation_id, "operation-id", IDENTIFIER)
    component_id = require_string(component_id, "component-id", COMPONENT_ID)
    head_sha = require_string(head_sha, "head-sha", SHA1)
    checkout_tree = require_string(checkout_tree, "checkout-tree", SHA1)
    guardrails_sha = require_string(guardrails_sha, "guardrails-sha", SHA1)
    if detect_result != SUCCESS:
        raise Reject("detect job is not successful")
    require_job(ubuntu_result, ubuntu_applicable, "ubuntu job")
    require_job(macos_result, macos_applicable, "macos job")

    return {
        "id": f"ci-quality-gates-{run_id}-{attempt}",
        "componentID": component_id,
        "operationID": operation_id,
        "revision": head_sha,
        "status": SUCCESS,
        "terminal": True,
        "locator": f"ci-artifact:{ARTIFACT_NAME}:{run_id}:{attempt}",
    }


def write_record(path, record):
    target = Path(path)
    if target.is_symlink():
        raise Reject("output must not be a symlink")
    if target.exists():
        raise Reject("output already exists")
    target.parent.mkdir(parents=True, exist_ok=True)
    data = canonical_bytes(record) + b"\n"
    try:
        descriptor = os.open(
            target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
    except OSError as error:
        raise Reject("output could not be created exclusively") from error
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as error:
        try:
            os.unlink(target)
        except OSError:
            pass
        raise Reject("output could not be written") from error
    directory = os.open(target.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True)
    parser.add_argument("--operation-id", required=True)
    parser.add_argument("--component-id", required=True)
    parser.add_argument("--event", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--attempt", required=True, type=int)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--checkout-tree", required=True)
    parser.add_argument("--guardrails-sha", required=True)
    parser.add_argument("--detect-result", required=True)
    parser.add_argument("--ubuntu-result", required=True)
    parser.add_argument("--macos-result", required=True)
    parser.add_argument(
        "--ubuntu-applicable",
        required=True,
        type=parse_boolean,
    )
    parser.add_argument(
        "--macos-applicable",
        required=True,
        type=parse_boolean,
    )
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args(argv)
    record = build_record(
        repository=arguments.repository,
        operation_id=arguments.operation_id,
        component_id=arguments.component_id,
        event=arguments.event,
        branch=arguments.branch,
        run_id=arguments.run_id,
        attempt=arguments.attempt,
        head_sha=arguments.head_sha,
        checkout_tree=arguments.checkout_tree,
        guardrails_sha=arguments.guardrails_sha,
        detect_result=arguments.detect_result,
        ubuntu_result=arguments.ubuntu_result,
        macos_result=arguments.macos_result,
        ubuntu_applicable=arguments.ubuntu_applicable,
        macos_applicable=arguments.macos_applicable,
    )
    write_record(arguments.output, record)
    print(
        json.dumps(
            {
                "result": "success",
                "recordID": record["id"],
                "locator": record["locator"],
                "output": str(Path(arguments.output).resolve()),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Reject as error:
        print(f"ci-evidence: result=blocked reason={error}", file=sys.stderr)
        sys.exit(2)
