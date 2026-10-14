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
            assert response.status == 200 and json.load(response) == {"status": "ok"}
        with urllib.request.urlopen(url + "/", timeout=10) as response:
            assert json.load(response)["service"] == "scalable-iac"
        print("HTTPS health and service checks passed")
        break
    except (urllib.error.URLError, TimeoutError, AssertionError, ValueError):
        if attempt == 23:
            raise
        time.sleep(10)
