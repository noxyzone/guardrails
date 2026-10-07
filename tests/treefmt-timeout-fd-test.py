#!/usr/bin/env python3
"""treefmt-check.shの実行期限まわりのkernel FD保持回帰テスト。

実wrapperを起動し、呼び出し元からpass_fdsで渡したflock済みFDが、wrapper終了直後に
別openからLOCK_EX|LOCK_NBで再取得できることを確認する。旧実装は正常終了後もwatchdog
由来の孤児sleepが継承FDを保持したため、この再取得が期限経過まで失敗した。

GNU timeout委譲後の契約も検証する。formatter自身の正常終了status(124/137を含む)は
期限発火として書き換えられず、formatterのstderrとLC_ALLは本来の値へ保持され、
継承FD 3はwrapperのstderr分離で上書きされない。期限発火そのものは、GNU timeoutの
--verbose診断だけを流す分離logでのみ識別する。

fixtureと証跡は保全し、PIDのkillや削除による掃除は行わない。旧実装で失敗した場合も
孤児の自然終了（設定期限の経過）を待ってから判定する。
"""

import fcntl
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "treefmt-check.sh"
HELPER = SCRIPT.parent / "treefmt-timeout-command.sh"

LC_ALL_UNSET = object()

TIMEOUT_SECONDS = 3
IMMEDIATE_RELEASE_SECONDS = 0.5
NATURAL_RELEASE_SECONDS = 15.0
POLL_INTERVAL_SECONDS = 0.05
TIMEOUT_MESSAGE = f"treefmt timed out after {TIMEOUT_SECONDS}s"

FAKE_TREEFMT = """\
#!/usr/bin/env bash
set -u
printf 'invoked\\n' >"${NZ_FAKE_TREEFMT_INVOKED:?}"
if [[ "${NZ_FAKE_TREEFMT_MODE:-quick}" == "ignore-term" ]]; then
    trap '' TERM
    sleep 5 &
    while true; do
        sleep 0.2
    done
fi
if [[ -n "${NZ_FAKE_TREEFMT_STDERR_LINE:-}" ]]; then
    printf '%s\\n' "${NZ_FAKE_TREEFMT_STDERR_LINE}" >&2
fi
if [[ "${NZ_FAKE_TREEFMT_MODE:-quick}" == "fd3-probe" ]]; then
    IFS= read -r fd3_line <&3
    printf '%s\\n' "$fd3_line" >"${NZ_FAKE_TREEFMT_FD3_OUT:?}"
fi
if [[ "${NZ_FAKE_TREEFMT_MODE:-quick}" == "locale-probe" ]]; then
    printf '%s\\n' "${LC_ALL-<unset>}" >"${NZ_FAKE_TREEFMT_LOCALE_OUT:?}"
fi
sleep 0.2
exit "${NZ_FAKE_TREEFMT_EXIT:-0}"
"""

FAKE_PATH_FILTER = """\
#!/usr/bin/env bash
set -euo pipefail
exit 0
"""


class TreefmtTimeoutFdTest(unittest.TestCase):
    def setUp(self) -> None:
        base = Path("/private/tmp")
        if not base.is_dir():
            base = Path(tempfile.gettempdir())
        self.fixture = Path(tempfile.mkdtemp(prefix="nz-treefmt-fd-fixture-", dir=base))
        guardrails = self.fixture / "guardrails"
        (guardrails / "scripts").mkdir(parents=True)
        (self.fixture / "bin").mkdir()
        self.repo_dir = self.fixture / "repo"
        self.repo_dir.mkdir()
        self.wrapper_path = guardrails / "scripts" / "treefmt-check.sh"
        os.symlink(SCRIPT, self.wrapper_path)
        os.symlink(HELPER, guardrails / "scripts" / "treefmt-timeout-command.sh")
        (guardrails / "treefmt.toml").write_text(
            "[formatter.prettier]\n"
            'command = "prettier"\n'
            'options = ["--config", ".guardrails/prettier.cjs", "--write"]\n',
            encoding="utf-8",
        )
        (guardrails / "prettier.cjs").write_text(
            "module.exports = {};\n", encoding="utf-8"
        )
        (guardrails / ".swiftformat").write_text(
            "--swiftversion 6.0\n", encoding="utf-8"
        )
        fake_filter = guardrails / "scripts" / "quality-gate-path-filter.sh"
        fake_filter.write_text(FAKE_PATH_FILTER, encoding="utf-8")
        fake_treefmt = self.fixture / "bin" / "treefmt"
        fake_treefmt.write_text(FAKE_TREEFMT, encoding="utf-8")
        os.chmod(fake_filter, 0o755)
        os.chmod(fake_treefmt, 0o755)
        self.lock_path = self.fixture / "fd-release.lock"
        self.invoked_marker = self.fixture / "treefmt-invoked"

    def _run_wrapper(
        self,
        label: str,
        mode: str,
        fake_exit: int,
        stderr_line: str | None = None,
        lc_all: object = LC_ALL_UNSET,
        extra_env: dict[str, str] | None = None,
    ):
        env = os.environ.copy()
        env["PATH"] = f"{self.fixture / 'bin'}:{env.get('PATH', '')}"
        env["TREEFMT_TIMEOUT_SECONDS"] = str(TIMEOUT_SECONDS)
        env["NZ_FAKE_TREEFMT_INVOKED"] = str(self.invoked_marker)
        env["NZ_FAKE_TREEFMT_MODE"] = mode
        env["NZ_FAKE_TREEFMT_EXIT"] = str(fake_exit)
        if stderr_line is not None:
            env["NZ_FAKE_TREEFMT_STDERR_LINE"] = stderr_line
        if lc_all is LC_ALL_UNSET:
            env.pop("LC_ALL", None)
        else:
            env["LC_ALL"] = str(lc_all)
        if extra_env:
            env.update(extra_env)
        stdout_path = self.fixture / f"wrapper-{label}.stdout"
        stderr_path = self.fixture / f"wrapper-{label}.stderr"
        lock_fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            # 継承FDはfd 3として渡る前提。ずれていれば境界検証が無効になるため先に表明する。
            self.assertEqual(lock_fd, 3, "inherited lock FD must land at number 3")
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with (
                open(stdout_path, "wb") as stdout_file,
                open(stderr_path, "wb") as stderr_file,
            ):
                completed = subprocess.run(
                    ["bash", str(self.wrapper_path), "--repo", str(self.repo_dir)],
                    cwd=self.repo_dir,
                    env=env,
                    pass_fds=(lock_fd,),
                    stdout=stdout_file,
                    stderr=stderr_file,
                    check=False,
                )
        finally:
            os.close(lock_fd)
        elapsed, last_error = self._wait_for_release()
        return completed.returncode, elapsed, last_error, stdout_path, stderr_path

    def _wait_for_release(self):
        started = time.monotonic()
        deadline = started + NATURAL_RELEASE_SECONDS
        last_error = None
        while True:
            probe_fd = os.open(self.lock_path, os.O_RDWR)
            try:
                fcntl.flock(probe_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(probe_fd, fcntl.LOCK_UN)
                return time.monotonic() - started, None
            except OSError as error:
                last_error = error
            finally:
                os.close(probe_fd)
            if time.monotonic() >= deadline:
                return None, last_error
            time.sleep(POLL_INTERVAL_SECONDS)

    def _assert_immediate_release(self, label, elapsed, last_error, stderr_path):
        if elapsed is None:
            self.fail(
                f"{label}: lock was not released within {NATURAL_RELEASE_SECONDS}s "
                f"after wrapper exit ({last_error}); fixture: {self.fixture}"
            )
        self.assertLessEqual(
            elapsed,
            IMMEDIATE_RELEASE_SECONDS,
            f"{label}: inherited FD kept the lock for {elapsed:.3f}s after wrapper "
            f"exit; stderr evidence: {stderr_path}; fixture: {self.fixture}",
        )

    def test_normal_exit_releases_inherited_fd_immediately(self) -> None:
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "normal", mode="quick", fake_exit=0
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 0, f"stderr evidence: {stderr_path}")
        self._assert_immediate_release("normal", elapsed, last_error, stderr_path)

    def test_nonzero_exit_preserves_status_and_releases_fd(self) -> None:
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "nonzero", mode="quick", fake_exit=49
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 49, f"stderr evidence: {stderr_path}")
        self._assert_immediate_release("nonzero", elapsed, last_error, stderr_path)

    def test_formatter_own_exit_124_is_preserved(self) -> None:
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "exit124", mode="quick", fake_exit=124
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 124, f"stderr evidence: {stderr_path}")
        stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace")
        self.assertNotIn(
            TIMEOUT_MESSAGE, stderr_text, f"stderr evidence: {stderr_path}"
        )
        self._assert_immediate_release("exit124", elapsed, last_error, stderr_path)

    def test_formatter_own_exit_137_is_preserved(self) -> None:
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "exit137", mode="quick", fake_exit=137
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 137, f"stderr evidence: {stderr_path}")
        stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace")
        self.assertNotIn(
            TIMEOUT_MESSAGE, stderr_text, f"stderr evidence: {stderr_path}"
        )
        self._assert_immediate_release("exit137", elapsed, last_error, stderr_path)

    def test_deadline_like_stderr_line_is_not_misdetected(self) -> None:
        forged_line = "timeout: sending signal TERM to command 'forged-treefmt'"
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "forged-stderr", mode="quick", fake_exit=49, stderr_line=forged_line
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 49, f"stderr evidence: {stderr_path}")
        stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace")
        self.assertIn(forged_line, stderr_text, f"stderr evidence: {stderr_path}")
        self.assertNotIn(
            TIMEOUT_MESSAGE, stderr_text, f"stderr evidence: {stderr_path}"
        )
        self._assert_immediate_release(
            "forged-stderr", elapsed, last_error, stderr_path
        )

    def test_inherited_fd3_is_not_clobbered(self) -> None:
        self.lock_path.write_text("fd3-sentinel\n", encoding="utf-8")
        fd3_probe_path = self.fixture / "fd3-probe.out"
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "fd3-probe",
            mode="fd3-probe",
            fake_exit=0,
            extra_env={"NZ_FAKE_TREEFMT_FD3_OUT": str(fd3_probe_path)},
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 0, f"stderr evidence: {stderr_path}")
        self.assertEqual(
            fd3_probe_path.read_text(encoding="utf-8", errors="replace").strip(),
            "fd3-sentinel",
            f"fixture: {self.fixture}",
        )
        self._assert_immediate_release("fd3-probe", elapsed, last_error, stderr_path)

    def test_formatter_locale_is_restored(self) -> None:
        locale_set_path = self.fixture / "locale-set.out"
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "locale-set",
            mode="locale-probe",
            fake_exit=0,
            lc_all="C.UTF-8",
            extra_env={"NZ_FAKE_TREEFMT_LOCALE_OUT": str(locale_set_path)},
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 0, f"stderr evidence: {stderr_path}")
        self.assertEqual(
            locale_set_path.read_text(encoding="utf-8", errors="replace").strip(),
            "C.UTF-8",
            f"fixture: {self.fixture}",
        )
        self._assert_immediate_release("locale-set", elapsed, last_error, stderr_path)

        locale_unset_path = self.fixture / "locale-unset.out"
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "locale-unset",
            mode="locale-probe",
            fake_exit=0,
            extra_env={"NZ_FAKE_TREEFMT_LOCALE_OUT": str(locale_unset_path)},
        )
        self.assertEqual(code, 0, f"stderr evidence: {stderr_path}")
        self.assertEqual(
            locale_unset_path.read_text(encoding="utf-8", errors="replace").strip(),
            "<unset>",
            f"fixture: {self.fixture}",
        )
        self._assert_immediate_release("locale-unset", elapsed, last_error, stderr_path)

    def test_term_ignoring_formatter_times_out_and_releases_fd(self) -> None:
        code, elapsed, last_error, _, stderr_path = self._run_wrapper(
            "ignore-term", mode="ignore-term", fake_exit=0
        )
        self.assertTrue(self.invoked_marker.is_file(), f"fixture: {self.fixture}")
        self.assertEqual(code, 1, f"stderr evidence: {stderr_path}")
        self.assertIn(
            TIMEOUT_MESSAGE,
            stderr_path.read_text(encoding="utf-8", errors="replace"),
            f"stderr evidence: {stderr_path}",
        )
        self._assert_immediate_release("ignore-term", elapsed, last_error, stderr_path)


if __name__ == "__main__":
    suite = unittest.TestLoader().loadTestsFromTestCase(TreefmtTimeoutFdTest)
    result = unittest.TextTestRunner(stream=sys.stdout, verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
