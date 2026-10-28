"""Verify public HTTPS and the infrastructure demo contract after deployment."""
import json
import sys
import time
import urllib.error
import urllib.request

url = sys.argv[1].rstrip("/")
if not url.startswith("https://"):
    raise SystemExit("HTTPS URL required")
for attempt in range(24):
    try:
        with urllib.request.urlopen(url + "/healthz", timeout=10) as response:
            if response.status != 200 or json.load(response) != {"status": "ok"}:
                raise ValueError("Unexpected health response")
        with urllib.request.urlopen(url + "/", timeout=10) as response:
            payload = json.load(response)
            if not isinstance(payload, dict) or payload.get("service") != "scalable-iac":
                raise ValueError("Unexpected service response")
        print("HTTPS health and service checks passed")
        break
    except (urllib.error.URLError, TimeoutError, AssertionError, ValueError):
        if attempt == 23:
            raise
        time.sleep(10)
