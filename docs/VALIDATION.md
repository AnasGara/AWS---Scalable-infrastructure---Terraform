# Validation record

Verified locally on 2026-10-27 using Windows amd64, Terraform **1.13.5**, AWS provider **6.70.0**, Python **3.12**, Git Bash and Actionlint **1.7.7**.

| Check | Result |
| --- | --- |
| `terraform fmt -check -recursive` | Pass |
| Bootstrap `terraform validate` | Pass |
| Workload `terraform validate` | Pass |
| Bootstrap `terraform test` | 1 passed, 0 failed |
| Workload `terraform test` | 6 passed, 0 failed |
| Python HTTP contract tests | 3 passed |
| Bash rollout-waiter scenarios | Success, no refresh, transition, rollback, cancellation, API error and timeout pass |
| Bash syntax, waiter and user-data template | Pass |
| Actionlint workflow checks | Pass; optional ShellCheck/Pyflakes integrations disabled |
| GitHub YAML parsing | Pass |
| Local Markdown link targets | Pass |
| Git ignore checks for local tools, state, tfvars, backend and plans | Pass |

The Terraform tests use `mock_provider "aws"`; no real cloud resources are created, including in mocked apply tests. Coverage checks two-AZ tier layout, per-AZ NAT, database route isolation, private app addressing, HTTPS redirect, encrypted storage, IMDSv2, ASG health/capacity, private encrypted Multi-AZ RDS, backup/deletion settings, state versioning/public access and exact OIDC environment trust. Negative cases reject single-instance minimums and invalid ASG capacity. HTTP tests use a real local ephemeral HTTP server.

The direct Terraform provider download stalled in this environment. For local verification, the official Windows provider archive was downloaded through byte-range requests, reassembled, and checked against HashiCorp's published SHA256 manifest before use in an ignored local filesystem mirror. Terraform's archive was also checked against its published SHA256 manifest. Both committed provider lock files include the local Windows package hash and official archive checksums, including Linux amd64 for CI. The Linux runtime itself was not executed locally. Actionlint's archive was checked against its release checksum manifest.

No AWS deployment, real AWS plan, GitHub workflow execution, live HTTPS smoke test, load test, AZ outage, RDS failover or backup restore has been performed. No credentials or account/domain/certificate inputs were supplied for deployment. Effective IAM/SCP permissions, quotas, regional RDS class/version availability, bootstrap package installation and real recovery behavior remain live acceptance checks in [DEPLOYMENT.md](DEPLOYMENT.md) and [PROJECT_PLAN.md](PROJECT_PLAN.md).

Reproduce the checks with README.md's commands. A successful local test result does not replace review of the real AWS plan or the cloud acceptance exercises.
