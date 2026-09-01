# Architecture and engineering decisions

## Scope and failure domains

The service uses two standard Availability Zones in one AWS region. Terraform sorts the available AZ names and selects the first two; AWS AZ names are account-specific. The VPC is `10.42.0.0/16` by default. Each tier receives a /24 per AZ:

| Tier | AZ index 0 | AZ index 1 | Default route |
| --- | --- | --- | --- |
| Public | `10.42.0.0/24` | `10.42.1.0/24` | Internet gateway |
| Application | `10.42.10.0/24` | `10.42.11.0/24` | Same-AZ NAT |
| Database | `10.42.20.0/24` | `10.42.21.0/24` | None; VPC local only |

Each NAT gateway needs a public EIP and internet gateway connectivity. Public subnet membership alone does not assign public IPs to EC2; application instances launch only in private subnets. A NAT per AZ costs more than one shared NAT but avoids making one AZ the egress dependency for both application tiers.

The ALB accepts IPv4 public traffic. Port 80 redirects to 443. ACM terminates TLS at the ALB; ALB-to-instance traffic uses HTTP within the VPC. If end-to-end encryption is required, serve HTTPS on instances and change the target group and security-group rules. PostgreSQL enforces TLS through `rds.force_ssl`.

## Compute lifecycle

The launch template contains encrypted root storage, IMDSv2 requirements, SSM IAM, cloud-init and application source. An application source change alters rendered user data, producing a new numeric launch-template version and a rolling instance refresh. Using an explicit version enables Auto Scaling rollback instead of relying on `$Latest`.

Refresh keeps 100% healthy capacity and allows up to 150% capacity while replacing instances. Leave EC2 quota/IP headroom for that surge. Health checks use `/healthz`, every 15 seconds, with a five-minute initial health grace period and three-minute warmup. The readiness endpoint only tests the HTTP process; it deliberately does not test the database. For a real app, define distinct process health and dependency readiness semantics and avoid a database incident triggering mass instance churn.

The ASG starts at two instances and scales toward 60% average CPU, up to six. Terraform ignores subsequent `desired_capacity` drift because target tracking owns it. Change min/max through code to alter the scaling envelope. Editing the desired-capacity input alone will not reset a running group's size. Target tracking CPU is a demo policy; use measured request-rate, latency or queue metrics appropriate to your workload.

Two AZs and two instances do not guarantee full throughput during an AZ loss. Size the surviving AZ's baseline capacity for the required failover load, and load-test that condition before making availability commitments.

Terraform starts refresh but does not wait for its entire lifecycle. `scripts/wait-for-refresh.sh` polls the most recent refresh for up to 30 minutes, fails on terminal failure/cancellation/rollback, and allows no-refresh initial creation. The deployment then checks live HTTPS with DNS and certificate validation. If another actor changes the group outside Terraform, the most-recent-refresh check cannot establish commit identity; prevent manual changes and investigate drift.

The boot process installs Python and the CloudWatch agent from AL2023 repositories through NAT. This keeps the example self-contained but makes startup dependent on package repositories. For production applications, bake and scan a versioned AMI, pin its ID, keep boot work minimal, and promote the same artifact across environments. Use a separate application delivery strategy if app release frequency should be independent of infrastructure changes.

## Data tier

PostgreSQL 17 runs as an RDS Multi-AZ **DB instance**, with one writable primary and one synchronous standby. This is availability, not read scaling. There are no read replicas or read-only database endpoints. RDS chooses the primary AZ; code does not assume which subnet hosts it.

Storage is encrypted gp3 with 20 GiB initially and growth up to 100 GiB. Backups retain 14 days, maintenance is scheduled, minor updates are enabled, and destructive deletion requires disabling protection and taking a final snapshot. `engine_version = "17"` follows an AWS-supported minor in that major version. Check regional availability before deployment and plan major upgrades as explicit migrations. The fixed final snapshot name must be changed if a previous teardown left a snapshot with that name.

The master password is generated and managed by RDS/Secrets Manager; Terraform outputs only the ARN. The demonstration application has network reachability but no password retrieval permission or DB connection logic. To connect a real application:

1. Create a least-privilege application database role and schema through controlled migrations, not as the master user on every boot.
2. Store its credentials in a separate secret; grant only the instance role access to that secret and any required KMS key.
3. Resolve the secret at runtime, require certificate-validated PostgreSQL TLS, and implement rotation/reconnection handling.
4. Keep secret values out of Terraform inputs, user data, plan artifacts, and logs.
5. Rehearse migrations, rollback compatibility, restore and failover with realistic connection pools.

## State and delivery

The application root uses an S3 backend with encryption and native lock files (`use_lockfile = true`). State is versioned and private. A separate bootstrap root avoids the bucket-before-backend dependency and provisions the GitHub repository/environment-bound OIDC role. The role cannot edit its own IAM policy through the workload's IAM resource allowlist, although its workload IAM privileges remain powerful; see SECURITY.md.

PRs run static validation, mocked Terraform plans and local HTTP tests with no AWS token. A merge runs offline checks again, creates a real plan against AWS, and applies that exact binary plan within one job. This makes the apply revision unambiguous and avoids transferring sensitive plans across artifacts. It also means PRs do not receive a real drift-aware AWS plan, and there is no separate live-plan approval. For stricter change control, use a trusted plan service and an approval-bound plan/apply design.

S3 locking prevents simultaneous state writes, and GitHub concurrency avoids deliberately overlapping deployments. Neither replaces branch review, environment restrictions or recovery procedures. State is not a cloud backup. Keep database backups and restoration procedures separately.

## Monitoring and known limits

Application/bootstrap logs and VPC flow logs retain 30 days; RDS PostgreSQL/upgrade logs retain 30 days; ALB access logs expire after 90 days. The ALB log bucket uses SSE-S3 as required by ALB access logging. Log delivery is asynchronous. Bootstrap failures before agent installation must be diagnosed with EC2 console/cloud-init logs.

CloudWatch alarms cover unhealthy targets, load-balancer and target 5xx counts, and low RDS storage. Missing target and database-storage metrics breach their alarms. SNS email is optional and requires confirmation. These alarms are a starting point; configure latency/error-rate SLOs, external synthetic monitoring, DB connections/CPU and memory monitoring according to measured production requirements.

Not included: multi-region recovery, WAF/rate limiting, business authentication, CI security scanners, hardened image pipeline, organization audit trails, cross-account backup vaults, or a full application stack. Keep these in the delivery backlog before onboarding a sensitive workload.

## Cost review

This stack is always-on and is not a free-tier design. No numeric cost estimate is claimed because region, runtime, traffic and current AWS pricing vary. Model these line items in the AWS Pricing Calculator before deployment:

| Component | Cost driver / control |
| --- | --- |
| Two NAT gateways | Two hourly gateway charges, processed data, public IPv4; consider measured VPC endpoint savings |
| ALB | Hourly load balancer, LCU usage, public IPv4 and transfer |
| EC2 + EBS | Minimum two instances, rolling surge, scaling up to six, encrypted gp3 volumes |
| Multi-AZ RDS | Primary and standby instance/storage costs, backup beyond allowance, storage autoscaling |
| Telemetry | Flow/application/DB log ingestion and retention, CloudWatch alarms, ALB S3 objects |
| Supporting services | Route 53 hosted zone/queries, Secrets Manager, S3 state versions/requests, SNS |

Set an account budget and review tags, NAT traffic, idle database capacity and log ingestion. Use a separate lower-cost development design if needed; silently reducing this production root to one NAT or one instance changes its availability properties. Deletion protection does not stop billing.

## Primary references

- [Terraform S3 backend and lock permissions](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform mocked providers](https://developer.hashicorp.com/terraform/language/tests/mocking)
- [GitHub OIDC with AWS and environment protections](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [Auto Scaling instance refresh lifecycle](https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-refresh-overview.html)
- [RDS-managed master passwords](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [ALB access-log permissions and encryption](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html)
