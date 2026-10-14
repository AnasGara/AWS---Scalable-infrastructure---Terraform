#!/usr/bin/env bash
# Exercise the actual rollout waiter without AWS calls or real sleeps.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/aws" <<'AWS'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$STUB_STATUS" == 'API_ERROR' ]]; then exit 42; fi
if [[ "$STUB_STATUS" == 'TRANSITION' ]]; then
  if [[ -f "$STUB_MARKER" ]]; then echo Successful; else touch "$STUB_MARKER"; echo InProgress; fi
else
  echo "$STUB_STATUS"
fi
AWS
cat > "$fixture/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "$fixture/aws" "$fixture/sleep"
export PATH="$fixture:$PATH" STUB_MARKER="$fixture/marker"
for status in Successful None TRANSITION; do
  STUB_STATUS="$status" bash "$repo/scripts/wait-for-refresh.sh" test-group
done
for status in Failed Cancelled RollbackSuccessful API_ERROR Pending; do
  if STUB_STATUS="$status" bash "$repo/scripts/wait-for-refresh.sh" test-group > /dev/null 2>&1; then
    echo "Expected rollout failure for $status" >&2
    exit 1
  fi
done
echo 'Rollout waiter: success, no-refresh, transition, rollback, cancellation, API error and timeout checks passed'
