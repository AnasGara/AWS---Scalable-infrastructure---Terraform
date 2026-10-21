# Configuration reference

Inputs live in `infra/variables.tf`. Use an ignored `infra/terraform.tfvars` for local deployment; GitHub uses explicit `TF_VAR_*` workflow environment values. Ignored local files are not copied to runners. Changes to defaults affect CI unless overridden there.

| Input | Default | Purpose |
| --- | --- | --- |
| `aws_account_id` | Required | Expected 12-digit account, enforced by AWS provider |
| `aws_region` | `eu-central-1` | AWS region; match backend/bootstrap/certificate |
| `project` | `scalable-iac` | Resource prefix; lowercase 3–16 characters |
| `environment` | `production` | `development`, `staging`, or `production` |
| `vpc_cidr` | `10.42.0.0/16` | IPv4 /16, split into six /24 subnets |
| `certificate_arn` | Required | Issued same-region ACM certificate |
| `domain_name` | Required | Public application hostname covered by certificate |
| `route53_zone_id` | Required | Existing public hosted zone in workload account |
| `instance_type` | `t3.micro` | Supported x86 types: t3.micro/small/medium or m6i.large |
| `ami_id` | `null` | Optional pinned AL2023 x86_64 AMI; otherwise AWS public SSM parameter |
| `min_size` | `2` | Minimum healthy baseline; integer ≥2 |
| `desired_capacity` | `2` | Initial size only; target tracking owns it thereafter |
| `max_size` | `6` | Scaling ceiling; allow quota headroom for refresh surge |
| `db_instance_class` | `db.t4g.micro` | Validate PostgreSQL 17 Multi-AZ availability in chosen region |
| `deletion_protection` | `true` | Applies to ALB and RDS; deliberately disable before teardown |
| `alarm_email` | `null` | Optional SNS recipient; confirmation required |

The VPC/subnet layout and AZ count, PostgreSQL major version, backup retention, log retention, TLS policy, CPU target and scaling warmup are reviewed code settings rather than generic inputs. Change them in their owning resource and update tests/docs together. Avoid exposing every resource field as an input without a concrete use case.

## Outputs

| Output | Use |
| --- | --- |
| `application_url` | Public HTTPS endpoint and smoke-test argument |
| `alb_dns_name` | ALB diagnostic name; access through the custom hostname for valid TLS |
| `autoscaling_group_name` | Rollout inspection and waiter argument |
| `database_endpoint` | Internal RDS hostname and port; app does not currently connect |
| `database_secret_arn` | RDS-managed master secret reference, never its value |
| `vpc_id` | Network inventory and diagnostics |

Bootstrap outputs `state_bucket`, `deploy_role_arn` and `backend_config`. State keys are fixed by the current production workflow to `production/terraform.tfstate`. Do not place credentials inside backend HCL.

## Additional environments

The workload variables allow another environment name, but the included GitHub workflow and bootstrap IAM policy are intentionally production-specific. To add staging, create a separate state key, GitHub environment, repository/environment-bound IAM role and workload policy scope; provide independent domain/certificate inputs, concurrency group, and preferably a separate AWS account. Reusing production's deployment role or state key defeats environment isolation. Terraform workspaces alone do not create an IAM/account boundary.

## Version updates

CI uses Terraform 1.13.5 and root constraints accept the 1.13 patch line. Update `.terraform-version`, both workflows and root constraints together for a minor upgrade. The AWS provider is constrained to major 6 and locked to the reviewed selection. Update root lock files using `terraform init -upgrade`, add supported platform checksums via `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`, and rerun all tests. Review the provider changelog and real plan before promotion. Keep bootstrap and workload provider selections aligned.

GitHub Actions are pinned to commit SHAs. Dependabot proposes workflow/provider updates weekly; review pins, release notes and lock-file changes. The sample Python service uses only the standard library and has no pip supply chain.
