# Project delivery plan

## Objective and acceptance criteria

Build infrastructure as reviewed production code: an AWS service must span two AZs, isolate public/application/database traffic, scale its compute layer, retain recoverable state/data, and deploy the exact merged revision through GitHub without permanent cloud credentials.

| Milestone | Delivered artifact | Status |
| --- | --- | --- |
| Design | Architecture, subnet/address plan, security model, failure/cost boundaries | Complete |
| State and identity | Separate bootstrap with versioned private S3 and repository/environment-bound OIDC | Implemented and locally tested |
| Network | VPC, public/private/isolated subnets, per-AZ NAT and flow logs | Implemented and locally tested |
| Compute and edge | HTTPS ALB, DNS, private launch template/ASG, rolling refresh, CPU scaling | Implemented and locally tested |
| Data | Private Multi-AZ PostgreSQL, managed master password, SSL, backups and final snapshot | Implemented and locally tested |
| Delivery | PR checks, main saved-plan apply, rollout wait and live smoke-check scripts | Implemented; workflow not run on GitHub |
| Operations | Logging/alarms, deployment, incident, rollback, recovery and teardown guides | Complete |
| Cloud acceptance | Provision, confirm alerts, load-test, replace instance, fail over/restore DB | Requires target account setup and live execution |

## Execution order

1. Select the dedicated workload account, owner, domain, certificate, budget and regional quotas.
2. Review the architecture, IAM boundaries and local validation results.
3. Bootstrap state/OIDC with an approved local administrative session; securely retain bootstrap state.
4. Configure GitHub environment variables, main-only environment deployment rules and required PR checks.
5. Review the first real AWS plan, then deploy through the merged main workflow.
6. Complete live acceptance checks and record measured outcomes. Resolve findings before routing real users.
7. Integrate the real application with scoped database credentials, migrations, image delivery, authentication and workload-specific monitoring.

## Release acceptance checklist

Before real traffic, confirm and record:

- The expected account/region, reviewed plan and deployment commit/run.
- Two healthy private instances in separate AZs, valid HTTPS/DNS and HTTP redirect.
- No public application/database ingress or public instance IPs.
- SSM administration and successful log delivery at every tier.
- Confirmed SNS delivery and externally tested service monitoring.
- Correct Multi-AZ DB status, encryption, backups and a successful separate restore exercise.
- Capacity under normal load, an AZ-loss rehearsal, and a tested rolling replacement.
- Pinned/scanned application artifact, application security review, scoped database access and migration recovery.
- Cost budget, on-call ownership, data retention and account-level audit/guardrails.

No unchecked cloud acceptance item is represented as completed by a local mock test. See VALIDATION.md for the precise evidence available from this build.
