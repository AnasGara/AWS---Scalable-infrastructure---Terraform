"""HTTP contract tests against a real local server, with no AWS dependencies."""
import importlib.util
import json
from pathlib import Path
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

spec = importlib.util.spec_from_file_location("server", Path(__file__).parents[1] / "app/server.py")
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)


class HTTPContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), server_module.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_health(self):
        with urllib.request.urlopen(self.url + "/healthz") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(json.load(response), {"status": "ok"})
            self.assertEqual(response.headers["Cache-Control"], "no-store")

    def test_home(self):
        with urllib.request.urlopen(self.url + "/") as response:
            payload = json.load(response)
            self.assertEqual(payload["service"], "scalable-iac")
            self.assertTrue(payload["hostname"])

    def test_unknown_route(self):
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(self.url + "/missing")
        self.assertEqual(caught.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
