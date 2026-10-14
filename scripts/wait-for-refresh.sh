#!/usr/bin/env bash
# Terraform starts instance refresh asynchronously. Treat failures as deployment failures.
set -euo pipefail
asg="$1"
for ((attempt=0; attempt<120; attempt++)); do
  status=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$asg" \
    --max-records 1 --query 'InstanceRefreshes[0].Status' --output text)
  case "$status" in
    Successful|None) exit 0 ;;
    Pending|InProgress|Baking|RollbackInProgress) sleep 15 ;;
    *) echo "Instance refresh failed: $status" >&2; exit 1 ;;
  esac
done
echo "Timed out waiting for instance refresh" >&2
exit 1
