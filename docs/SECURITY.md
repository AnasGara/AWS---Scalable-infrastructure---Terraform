# Security model

## Trust and administrative boundaries

GitHub uses OIDC to assume a two-hour AWS session. Trust checks `aud = sts.amazonaws.com` and an exact `repo:OWNER/REPO:environment:production` subject. There is no wildcard repository, branch or environment subject. The GitHub production environment **must restrict deployments to main**. Environment-based OIDC subjects do not encode the branch; the workflow's `if` condition alone is not an adequate authorization boundary if someone can change workflows on another branch.

PR checks have no AWS credentials and do not use `pull_request_target`. The deploy workflow runs only on `main` pushes or manual dispatch on `main`. Require peer review and branch rules, protect environment settings and repository administrators, and review action SHA updates. Anyone able to merge malicious Terraform or application code into the deployment branch can act within the deployment role's permissions.

## Deployment role limitations

The bootstrap policy is a **reference provisioning policy, not a least-privilege production boundary**. It deliberately permits service-wide EC2, ELB, Auto Scaling, RDS, CloudWatch, Logs and SNS operations on `*` to support resource creation, reconciliation and deletion. These privileges can affect unrelated resources in a shared account. Route 53 changes are scoped to one hosted zone; ALB log buckets to a name prefix; state access to one key and lock file; workload IAM changes to the two named roles and one instance profile. It has no `AdministratorAccess` and does not permit editing the bootstrap deployment role itself.

Workload role-policy editing and attachment permissions can still be used to escalate the **instance role**, and a deployment operator can launch code using it. The scoped IAM names do not make untrusted Terraform safe. In a mature account, use organization-enforced permissions boundaries on workload roles, restrict allowed managed policies, enforce required tags/regions with SCPs, and generate narrower service/resource policies from a measured deployment. Test both create and update paths under those controls. A dedicated account is the recommended boundary for this reference project.

The role can create and tag Secrets Manager secrets to support RDS-managed credentials and describe KMS keys. It has no `secretsmanager:GetSecretValue` permission. Bootstrap cannot fully prove effective authorization: SCPs, permissions boundaries, regional restrictions, AWS-managed service behavior and service-linked-role creation must be checked with a real plan/apply. Do not infer production authorization success from a mocked test.

## Network and workload

- Only the ALB is internet-facing. Application instances have no public address and no SSH ingress/key pair.
- The app accepts port 8080 only from the ALB security group. Its outbound access permits TCP 443 and PostgreSQL to the database group. DNS uses the VPC resolver.
- The database accepts TCP 5432 only from the app security group. It has no public endpoint or internet route and requires SSL.
- Instances require IMDSv2. Root EBS and database storage are encrypted. The service runs as an unprivileged system account with systemd filesystem protections.
- SSM instance permissions are provided by AWS's managed core policy. Restrict who can initiate sessions and record/audit administrative sessions at the account level.

ALB-to-app traffic is HTTP inside the VPC. There is no WAF, authentication or request-level rate limiting in the demo. Evaluate these before exposing a real workload. A minimal Python stdlib HTTP server is appropriate for demonstration, not for a high-throughput application runtime.

## State, secrets and logs

State/plan files are sensitive operational records. State is private, SSE-S3 encrypted, TLS-only and versioned. The S3 lock file is separate from the state object. Only the lock file needs DeleteObject for normal Terraform operations. No CI plan artifact is published. Git ignores state, plans, real tfvars and backend configuration; examples remain committed.

RDS manages the master password. No Terraform data source reads its value. Treat the secret ARN and endpoint as operational metadata, and create a separate least-privilege application credential when integrating a real app. Never place passwords in user data or environment tfvars.

The sample app avoids logging query strings or request text. ALB access logs can still contain URLs and client IPs; apply the organization's privacy/access policy. This reference uses AWS-managed encryption instead of customer-managed keys. Adopt CMKs and corresponding key policies where required; ALB access logs specifically use SSE-S3.

Report suspected compromise through your organization's incident channel. Suspend the GitHub environment, revoke/deny role assumption, investigate CloudTrail and workload changes, rotate affected application credentials and restore from reviewed code/state. Do not delete state as an incident-response shortcut.
