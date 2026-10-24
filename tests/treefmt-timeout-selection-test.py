#!/usr/bin/env python3
"""隔離したPATHでGNU timeout候補の選択だけを検証する。"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def find_gnu_timeout():
    for name in ("timeout", "gnutimeout", "gtimeout"):
        path = shutil.which(name)
        if path:
            result = subprocess.run(
                [path, "--version"], capture_output=True, text=True, check=False
            )
            if result.returncode == 0 and result.stdout.startswith(
                tuple(
                    f"{banner_name} (GNU coreutils) "
                    for banner_name in ("timeout", "gnutimeout", "gtimeout")
                )
            ):
                return path
    raise RuntimeError("selection tests require GNU coreutils timeout")


class TreefmtTimeoutSelectionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gnu_timeout = find_gnu_timeout()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="nz-timeout-selection-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.repo = self.base / "repo"
        self.repo.mkdir()
        guardrails = self.base / "guardrails"
        scripts = guardrails / "scripts"
        scripts.mkdir(parents=True)
        self.wrapper = scripts / "treefmt-check.sh"
        self.wrapper.symlink_to(ROOT / "scripts" / "treefmt-check.sh")
        (scripts / "treefmt-timeout-command.sh").symlink_to(
            ROOT / "scripts" / "treefmt-timeout-command.sh"
        )
        for name in ("bash", "dirname", "mktemp", "rm", "awk", "grep"):
            path = shutil.which(name)
            self.assertIsNotNone(path, name)
            (self.bin / name).symlink_to(path)
        for name in ("treefmt.toml", "prettier.cjs", ".swiftformat"):
            (guardrails / name).write_text("", encoding="utf-8")
        self.executable(scripts / "quality-gate-path-filter.sh", "exit 0\n")
        self.executable(
            self.bin / "treefmt", 'printf invoked >"$NZ_SELECTION_FORMATTER"\n'
        )
        self.marker = self.base / "formatter-invoked"
        self.log = self.base / "candidate-log"

    @staticmethod
    def executable(path, body):
        path.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n" + body, encoding="utf-8"
        )
        path.chmod(0o755)

    def candidate(self, name, banner="timeout (GNU coreutils) 9.11", status=0):
        self.executable(
            self.bin / name,
            f'if [[ "${{1-}}" == --version ]]; then\n'
            f"    printf '%s\\n' '{banner}'\n"
            f"    exit {status}\n"
            "fi\n"
            f"printf '%s\\n' '{name}' >>\"$NZ_SELECTION_LOG\"\n"
            'exec "$NZ_SELECTION_REAL_TIMEOUT" "$@"\n',
        )

    def run_wrapper(self, selected=None):
        env = os.environ.copy()
        env.update(
            PATH=str(self.bin),
            NZ_SELECTION_FORMATTER=str(self.marker),
            NZ_SELECTION_LOG=str(self.log),
            NZ_SELECTION_REAL_TIMEOUT=self.gnu_timeout,
        )
        result = subprocess.run(
            [str(self.wrapper), "--repo", str(self.repo)],
            env=env,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
        if selected:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(self.marker.exists())
            self.assertEqual(self.log.read_text(encoding="utf-8"), selected + "\n")
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("GNU coreutils timeout is required", result.stderr)
            self.assertIn("gnu-coreutils", result.stderr)
            self.assertIn("Homebrew", result.stderr)
            self.assertFalse(self.marker.exists())
            self.assertFalse(self.log.exists())
            self.assertNotIn("private-version-detail", result.stderr)

    def test_uutils_timeout_falls_through_to_gnutimeout(self):
        self.candidate("timeout", "timeout (uutils coreutils) 0.9.0")
        self.candidate("gnutimeout", "gnutimeout (GNU coreutils) 9.11")
        self.candidate("gtimeout")
        self.run_wrapper("gnutimeout")

    def test_gnu_timeout_has_priority(self):
        for name in ("timeout", "gnutimeout", "gtimeout"):
            self.candidate(name)
        self.run_wrapper("timeout")

    def test_homebrew_gtimeout(self):
        self.candidate("gtimeout", "gtimeout (GNU coreutils) 9.11")
        self.run_wrapper("gtimeout")

    def test_failed_version_skips_candidate(self):
        self.candidate("timeout", status=1)
        self.candidate("gnutimeout")
        self.run_wrapper("gnutimeout")

    def test_gnu_mention_after_first_line_is_rejected(self):
        self.candidate("timeout", "private-version-detail\nGNU coreutils")
        self.run_wrapper()

    def test_all_non_gnu_are_rejected(self):
        for name in ("timeout", "gnutimeout", "gtimeout"):
            self.candidate(name, "private-version-detail")
        self.run_wrapper()

    def test_no_candidate_is_rejected(self):
        self.run_wrapper()


if __name__ == "__main__":
    unittest.main()
