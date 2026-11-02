import concurrent.futures
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

CONTROL = Path(__file__).resolve().parents[1] / "mods/caffeinate/control.sh"
WORKER = """
import concurrent.futures
import json
import subprocess
import sys

def control(action):
    result = subprocess.run(
        ['/bin/sh', sys.argv[1], action], capture_output=True, text=True, timeout=10
    )
    return [result.returncode, result.stdout.strip(), result.stderr.strip()]

for line in sys.stdin:
    with concurrent.futures.ThreadPoolExecutor() as pool:
        results = list(pool.map(control, json.loads(line)))
    print(json.dumps(results), flush=True)
"""


class CaffeinateLifecycle(unittest.TestCase):
    def setUp(self):
        if sys.platform != "darwin":
            self.fail("These lifecycle tests require macOS's caffeinate and lockf")
        self.scratch = tempfile.TemporaryDirectory(prefix="herdr-caffeinate-")
        self.addCleanup(self.scratch.cleanup)
        self.worker = subprocess.Popen(
            [sys.executable, "-u", "-c", WORKER, str(CONTROL)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=dict(os.environ, TMPDIR=self.scratch.name),
        )
        self.addCleanup(self.stop_worker)

    def request(self, *actions):
        self.worker.stdin.write(json.dumps(actions) + "\n")
        self.worker.stdin.flush()
        line = self.worker.stdout.readline()
        self.assertTrue(line, "Controller worker exited without a response")
        return json.loads(line)

    def control(self, *actions):
        results = self.request(*actions)
        for code, _, error in results:
            self.assertEqual(code, 0, error)
        return [state for _, state, _ in results]

    def helpers(self):
        result = subprocess.run(
            [
                "/usr/bin/pgrep",
                "-f",
                "-x",
                f"/usr/bin/caffeinate -is -w {self.worker.pid}",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.stdout.split()

    def wait_count(self, count):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            helpers = self.helpers()
            if len(helpers) == count:
                return helpers
            time.sleep(0.05)
        self.fail(f"Expected {count} helpers, found {helpers}")

    def stop_worker(self):
        if self.worker.poll() is None:
            self.worker.terminate()
            self.worker.wait(timeout=5)
        self.wait_count(0)
        self.worker.stdin.close()
        self.worker.stdout.close()

    def test_concurrent_starts_are_idempotent(self):
        self.assertEqual(self.control("status"), ["off"])
        self.assertEqual(self.control("start", "start", "start"), ["on"] * 3)
        original = self.wait_count(1)
        self.assertEqual(self.control("start", "status"), ["on", "on"])
        self.assertEqual(self.helpers(), original)

    def test_stop_is_complete_before_immediate_restart(self):
        self.assertEqual(self.control("start"), ["on"])
        self.assertEqual(self.control("stop"), ["off"])
        self.assertEqual(self.helpers(), [])
        self.assertEqual(self.control("stop"), ["off"])
        self.assertEqual(self.control("status"), ["off"])
        self.assertEqual(self.control("start"), ["on"])
        self.wait_count(1)

    def test_helper_exits_when_gui_process_dies(self):
        self.assertEqual(self.control("start"), ["on"])
        self.worker.kill()
        self.worker.wait(timeout=5)
        self.wait_count(0)

    def test_lock_recovers_after_its_owner_is_killed(self):
        lock = Path(self.scratch.name) / f"herdr-app-caffeinate-{os.getuid()}.lock"
        holder = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                'exec 9>"$1"; /usr/bin/lockf -t 5 9; echo ready; read -r line',
                "sh",
                str(lock),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )

        def cleanup_holder():
            if holder.poll() is None:
                holder.kill()
                holder.wait(timeout=5)
            holder.stdin.close()
            holder.stdout.close()

        self.addCleanup(cleanup_holder)
        self.assertEqual(holder.stdout.readline().strip(), "ready")
        with concurrent.futures.ThreadPoolExecutor() as pool:
            pending = pool.submit(self.control, "start")
            try:
                with self.assertRaises(concurrent.futures.TimeoutError):
                    pending.result(timeout=0.2)
            finally:
                holder.kill()
                holder.wait(timeout=5)
            self.assertEqual(pending.result(timeout=5), ["on"])
        self.wait_count(1)
        self.assertTrue(lock.is_file())
        self.assertEqual(self.control("stop"), ["off"])
        self.assertEqual(self.control("status"), ["off"])

    def test_invalid_action_fails_without_starting_a_helper(self):
        code, _, error = self.request("invalid")[0]
        self.assertEqual(code, 2)
        self.assertIn("Usage:", error)
        self.assertEqual(self.helpers(), [])


if __name__ == "__main__":
    unittest.main()
