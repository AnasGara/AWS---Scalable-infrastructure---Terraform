"""Exercise the deployment script with optimized Python and fake HTTPS responses."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "scripts/smoke-test.py"

class SmokeGate(unittest.TestCase):
    def run_gate(self, health, home):
        with tempfile.TemporaryDirectory() as directory:
            # sitecustomize is loaded in the child before the real script starts.
            Path(directory, "sitecustomize.py").write_text(
                "import io, urllib.request, time\n"
                "class Response(io.StringIO):\n    status = 200\n"
                f"bodies = iter({[health, home] * 24!r})\n"
                "urllib.request.urlopen = lambda *a, **k: Response(next(bodies))\n"
                "time.sleep = lambda seconds: None\n", encoding="utf-8")
            env = dict(os.environ, PYTHONPATH=directory)
            return subprocess.run([sys.executable, "-O", str(SCRIPT), "https://example.invalid"],
                                  env=env, capture_output=True, text=True, timeout=10)

    def test_accepts_expected_contract_under_optimization(self):
        result = self.run_gate('{"status":"ok"}', '{"service":"scalable-iac"}')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_bad_health_under_optimization(self):
        self.assertNotEqual(self.run_gate('{"status":"broken"}', '{}').returncode, 0)

    def test_rejects_wrong_service_under_optimization(self):
        self.assertNotEqual(self.run_gate('{"status":"ok"}', '{"service":"wrong"}').returncode, 0)
