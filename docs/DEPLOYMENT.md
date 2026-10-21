# Deployment guide

## 1. Prerequisites and account choices

Use a dedicated AWS workload account. Install Terraform 1.13.5, AWS CLI v2, Python 3.12+, Git and Bash (Git Bash or WSL on Windows). Authenticate locally with AWS IAM Identity Center/SSO; do not create permanent CI access keys.

You need:

- An AWS account ID and target region (default `eu-central-1`) with at least two standard AZs.
- An existing public Route 53 hosted zone in that account and an application DNS name in it.
- An **issued ACM certificate in the same region as the ALB**, covering the application hostname. Complete ACM DNS validation first and retain its validation record for renewal.
- A GitHub repository whose default deployment branch is `main` and access to environment/ruleset settings.
- Permissions for initial bootstrap: S3, IAM/OIDC and role policies. Use your organization's approved provisioning role. Bootstrap is deliberately outside the CI role's management scope.
- Quota headroom for two NAT gateways/EIPs, at least three EC2 instances during a two-instance rollout (more at larger capacity), ALB and Multi-AZ PostgreSQL 17 with the selected instance class.

Review [security](SECURITY.md) and [costs](ARCHITECTURE.md) before provisioning. Do not use shared production accounts with unrelated workloads without narrowing the deployment policy.

```bash
aws sso login --profile YOUR_PROFILE
export AWS_PROFILE=YOUR_PROFILE
aws sts get-caller-identity
```

PowerShell equivalent: `$env:AWS_PROFILE = 'YOUR_PROFILE'`. In all subsequent Terraform commands replace `terraform` with its installed executable path if needed.

## 2. Create the state bucket and CI identity

Copy `bootstrap/bootstrap.example.tfvars` to `bootstrap/terraform.tfvars`. Set the real account, region, exact `OWNER/REPOSITORY`, and hosted zone. If a GitHub OIDC provider already exists in this AWS account, supply `existing_oidc_provider_arn`; do not try to create a duplicate.

The default project is `scalable-iac`. The bootstrap policy is intentionally tied to `scalable-iac-production`. If renaming the project, update the bootstrap input, workload input, and workflow `TF_VAR_project` together. This version of the pipeline deploys only the production root/state key.

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap plan -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
terraform -chdir=bootstrap output -raw backend_config > infra/backend.hcl
terraform -chdir=bootstrap output -raw deploy_role_arn
terraform -chdir=bootstrap output -raw state_bucket
```

PowerShell 5 users: shell redirection can write UTF-16. Generate the backend file as UTF-8 using `terraform -chdir=bootstrap output -raw backend_config | Set-Content -Encoding utf8 infra/backend.hcl` or copy the output into a UTF-8 file.

Bootstrap begins with **local state** because its bucket does not yet exist. Keep `bootstrap/terraform.tfstate` and any backup in an encrypted, access-controlled location. It is excluded from Git. For a team, migrate it to a separately administered state backend; add an approved backend block to bootstrap and use `terraform init -migrate-state`. Do not point it at the application's `production/terraform.tfstate` key. Never discard bootstrap state or destroy its bucket as part of workload cleanup.

## 3. Configure GitHub before merging

Create a GitHub environment named exactly **`production`**. Restrict its deployment branches to **selected branch `main` only**. This is a security requirement: OIDC tokens for environment jobs contain an environment subject rather than a branch subject, so AWS trust alone does not enforce `main`.

Set these environment variables (Settings → Environments → production → Variables):

| Variable | Value |
| --- | --- |
| `AWS_ACCOUNT_ID` | 12-digit workload account |
| `AWS_REGION` | Same region used for bootstrap and workload |
| `AWS_DEPLOY_ROLE_ARN` | Bootstrap `deploy_role_arn` output |
| `TF_STATE_BUCKET` | Bootstrap `state_bucket` output |
| `ACM_CERTIFICATE_ARN` | Issued certificate ARN for the app hostname |
| `DOMAIN_NAME` | For example `app.example.com` |
| `ROUTE53_ZONE_ID` | Existing public hosted zone ID |
| `ALARM_EMAIL` | Optional operations email; confirm the SNS subscription |
| `AMI_ID` | Optional approved AL2023 x86_64 AMI; blank follows AWS SSM parameter |

No AWS key secrets are required. Set `ALARM_EMAIL` to enable email alerts in CI. Confirm the SNS subscription after apply. Until then, alarms have no confirmed email recipient.

Protect `main` with a ruleset requiring PR reviews and the **`validate`** status check from the Validate workflow. Block force pushes and direct pushes; restrict bypass permissions. Require review of Terraform, IAM, workflow and application changes by the responsible infrastructure team. Set CODEOWNERS to real team handles if your organization uses it; no fake owners are preconfigured.

Optional required reviewers on the environment add a human gate **before** the entire deployment job. For fully automatic deployment after merge, leave that gate off and rely on enforced PR review. This workflow does not offer a separate approval of its live plan. If that is required, split plan/apply into protected jobs and securely bind the saved plan to the exact commit and run.

## 4. First local AWS plan

Copy `infra/production.example.tfvars` to `infra/terraform.tfvars` and replace all placeholders. CI does not read this ignored file; its values come from workflow environment variables. Keep those two configurations aligned.

```bash
terraform -chdir=infra init -backend-config=backend.hcl -lockfile=readonly
terraform -chdir=infra validate
terraform -chdir=infra plan -lock-timeout=5m -out=production.tfplan
terraform -chdir=infra show production.tfplan
```

Check the account/region, six non-overlapping subnets, two NAT gateways, two EC2 instances, external HTTPS ALB, private Multi-AZ RDS, DNS record, IAM changes and log destinations. Resolve all authorization and regional capacity/engine errors before applying. The real plan is sensitive: do not commit it, post it to public PRs, or upload it to broadly accessible artifacts.

The default AMI resolves the current AL2023 x86_64 image from AWS SSM. For repeatable rollouts, set an approved `ami_id` locally and `AMI_ID` in the GitHub environment. Add explicit workflow environment values for other non-default tuning inputs. Provider lock files do not pin AMIs or OS packages.

## 5. Deploy through GitHub

Push a feature branch, open a PR, and wait for Validate. Review and merge into `main`. Deploy production performs offline checks, assumes the OIDC role, initializes the locked remote backend, creates a real saved plan for that merge revision, and applies exactly that plan. It waits for the latest instance refresh and checks the public HTTPS application. `workflow_dispatch` can rerun deployment from `main` for recovery.

The production concurrency group serializes workflow runs; S3 locking also protects against local Terraform writers. GitHub can replace pending runs with newer pending runs, so not every intermediate commit is guaranteed its own deployment. Each executing run checks out its own event revision, and a later successful run converges to the newest deployed revision. Never manually apply concurrently.

First creation may take 20–45 minutes or longer depending on AWS. An apply error does not mean nothing was created: inspect state and rerun plan before retrying. Do not delete state to work around failures.

## 6. Acceptance checks in AWS

```bash
terraform -chdir=infra output
python scripts/smoke-test.py "$(terraform -chdir=infra output -raw application_url)"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names scalable-iac-production
aws rds describe-db-instances --db-instance-identifier scalable-iac-production
```

Verify both targets are healthy and occupy separate AZs; instances have no public IPs; HTTP redirects to HTTPS; hostname responses vary over repeated requests; RDS is Multi-AZ and not public; log streams and ALB log objects appear; SSM lists both instances online; the SNS email is confirmed. Check the CloudWatch alarm configuration and deliver a controlled alarm test to the operations recipient.

In a non-production rehearsal, replace one instance, perform a controlled RDS failover, and restore a backup into a separate DB. Record measured availability and recovery times. Mock tests cannot establish these results.
