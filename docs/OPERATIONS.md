# Operations and recovery runbook

## Routine ownership

Assign a service owner, AWS account owner, database owner and incident contact before launch. Subscribe and confirm the SNS alarm recipient. Record the domain, state bucket, region, environment, GitHub role ARN and backup retention in your internal inventory. Set an AWS Budget separately.

Review daily: deployment failures, unhealthy targets, 5xx alarms, database storage and SNS delivery. Review weekly: Dependabot PRs, drift, scaling behavior, NAT/log costs and database backup success. Rehearse restore and AZ-failure behavior regularly in a safe environment.

## Deploy and inspect

Every normal change goes through a PR, Validate and a merge to `main`. Watch the production deployment log. A green apply is followed by refresh completion and HTTPS checks; it does not certify application correctness or database migrations.

```bash
aws sts get-caller-identity
terraform -chdir=infra output
aws autoscaling describe-instance-refreshes --auto-scaling-group-name scalable-iac-production --max-records 5
aws autoscaling describe-scaling-activities --auto-scaling-group-name scalable-iac-production --max-records 10
```

Use Systems Manager Session Manager for an approved diagnostic session:

```bash
aws ssm start-session --target i-REPLACE
# Inside the instance:
sudo systemctl status scalable-iac amazon-cloudwatch-agent
sudo journalctl -u scalable-iac --since '30 minutes ago'
sudo tail -n 100 /var/log/bootstrap.log /var/log/scalable-iac.log
curl --fail http://localhost:8080/healthz
```

Operator permissions and the Session Manager CLI plugin are separate prerequisites. If SSM is unavailable, inspect EC2 system logs and cloud-init output in the console; there is no SSH fallback by design.

## Unhealthy targets or HTTP 502/503

1. Check ALB target health reasons, target count and AZ distribution. Separate ALB-generated 5xx from application-generated 5xx using the two alarms and access logs.
2. Check EC2/ASG activities and whether a refresh or scaling action is active. Ensure desired capacity is at least two and EC2 quota/IP capacity allows replacement instances.
3. On an affected instance, inspect cloud-init/bootstrap logs, systemd service and local `/healthz`. Package failures may indicate NAT routing, DNS, egress or repository availability.
4. Confirm ALB → app TCP 8080 security-group references and app subnet routes. Review VPC flow logs for rejections.
5. If related to a merged change, follow the code rollback below. Do not open SSH or public application ingress to diagnose it.

ALB sends health traffic without relying on the public DNS name. A successful localhost health check does not prove target-group reachability. A public TLS failure with healthy targets usually points to DNS, certificate coverage/status or listener configuration.

## Failed rollout and code rollback

Instance refresh is configured for AWS automatic rollback on refresh failure. If AWS rolls back, the wait script fails the deployment; investigate before retrying. The Terraform launch template/state can still reflect the attempted new version, so re-plan and restore code rather than assuming AWS rollback permanently reconciled configuration.

Revert the offending PR in GitHub and merge the revert after review. The next workflow plans/applies a new launch-template version and rolls it out. Re-running the same failed commit will redeploy that commit; it is not a rollback. Avoid concurrent manual refreshes or console edits.

For emergency recovery, freeze the production environment and coordinate with the account owner. Inspect the latest refresh status and scaling activities, then decide whether to cancel or allow rollback. Make any emergency action explicit in the incident record and reconcile Terraform afterward.

Database changes need a separate compatibility plan. Reverting Terraform does not reverse data migrations, dropped columns, engine upgrades or data deletion. Use forward fixes or a tested restore/cutover strategy.

## Database incident, failover and restore

Check RDS status/events, free storage, connection count, CPU and logs. Multi-AZ failover changes the target behind the database endpoint; clients must reconnect and re-resolve DNS. The standby is not a query endpoint.

In a controlled non-production exercise only:

```bash
aws rds reboot-db-instance --db-instance-identifier scalable-iac-production --force-failover
```

This interrupts connections. Record actual recovery time; no fixed RTO/RPO is promised by this repository. Multi-AZ protects availability, not accidental deletes or regional loss.

For data loss, find a valid automated backup/snapshot and restore into a **new DB identifier** using RDS point-in-time recovery or snapshot restore. Choose the existing isolated DB subnet group and DB security group; confirm encryption, SSL, Multi-AZ configuration, master credential handling and backup policy on the restored DB. Validate data and application migrations before cutover. This is a human-coordinated recovery, not an automated Terraform rollback.

Record/import the restored instance into a reviewed recovery configuration with the correct identifier and lifecycle protection before retiring the original. Run `terraform plan` and inspect replacement intent carefully; do not import a differently named restored database into the unchanged original configuration and apply blindly. Retain the old instance/snapshots until the owner signs off. A regional disaster requires separately designed cross-region backup/restore procedures.

The final snapshot identifier defaults to `scalable-iac-production-final`. If that snapshot already exists, update `final_snapshot_identifier` to a unique reviewed value before teardown. Never resolve this by disabling snapshots on a production database.

## Drift review

From a trusted local AWS session with the correct backend initialized:

```bash
terraform -chdir=infra plan -lock-timeout=5m -detailed-exitcode
```

Exit code 0 = no changes, 2 = changes, 1 = error. Investigate changes before applying. Desired ASG capacity drift is intentionally ignored. Pin the AMI to distinguish intended releases from AWS public-parameter updates. AWS may legitimately update RDS minor versions during maintenance.

There is no scheduled cloud drift job in this version; schedule a trusted read/plan process under your organization's access model if required. Do not give fork PRs state-reading credentials to obtain drift previews.

## Stuck state lock or partial apply

First check running/pending GitHub jobs and other operators. Wait for an active writer. If a job died, verify no Terraform process/apply is still running before considering `terraform force-unlock LOCK_ID`. Record the lock metadata and incident. Never remove the lock just because a plan is slow.

For partial apply failures, preserve state and resources, fix the underlying IAM/quota/API/config issue, and rerun plan. Terraform normally records successfully created resources. Use import only after verifying an orphan really is absent from state; deleting state creates orphaning and replacement risks.

## State recovery

The backend bucket has versioning. If state is corrupted or accidentally overwritten:

1. Freeze all writers and save the current state/object version to an encrypted incident location.
2. Identify a known-good S3 version and compare it with actual AWS resources and the last successful apply.
3. Recover using the organization's reviewed Terraform/S3 state procedure. Inspect lineage/serial and never bypass state checks casually.
4. Run a read-only plan to identify divergence; reconcile imports and configuration with a second reviewer before resuming applies.

Restoring an old state file does not undo infrastructure changes. Database backups are separate. Do not share downloaded state in tickets or chat.

## Deliberate teardown

Destroy is deliberately excluded from GitHub Actions. Confirm account, region, domain impact, data retention and ownership first; freeze automatic deployments so a merge cannot recreate resources. Preserve database backups, ALB logs and Terraform state as required.

1. In reviewed configuration set `deletion_protection = false` for the workload. Apply that change to both ALB and RDS. CI uses environment variables, so configure `TF_VAR_deletion_protection` there or make the deliberate default change through code; editing an ignored local tfvars file does not affect CI.
2. From a trusted local session, initialize the exact production backend and review a saved destroy plan:

```bash
terraform -chdir=infra plan -destroy -lock-timeout=5m -out=destroy.tfplan
terraform -chdir=infra show destroy.tfplan
terraform -chdir=infra apply destroy.tfplan
```

3. The RDS final snapshot is required. Resolve identifier conflicts before proceeding.
4. The ALB access-log bucket has `force_destroy = false`. After ALB deletion stops log delivery, archive required logs and explicitly empty that **exact** workload log bucket using your approved retention procedure. Rerun the reviewed destroy plan for the remaining resources. Never empty the Terraform state bucket.
5. Verify NAT gateways, EIPs, EC2, ALB and DB instances are gone and identify retained snapshots/logs that still incur charges. Some asynchronous cleanup may take time.
6. Retain bootstrap and its state bucket for recovery/audit. Its bucket has Terraform `prevent_destroy`; decommissioning it is a distinct administrative operation with explicit archival and retention decisions.
