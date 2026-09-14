"""Dependency-free infrastructure demonstration; replace with your real service."""
import json
import logging
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            status, payload = 200, {"status": "ok"}
        elif self.path == "/":
            status, payload = 200, {
                "service": "scalable-iac",
                "hostname": socket.gethostname(),
                "message": "Private compute behind an HTTPS Application Load Balancer",
            }
        else:
            status, payload = 404, {"error": "not found"}
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Avoid logging attacker-controlled request text or query strings.
        logging.info("http_request client=%s", self.client_address[0])


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    ThreadingHTTPServer(("0.0.0.0", int(os.getenv("PORT", "8080"))), Handler).serve_forever()
