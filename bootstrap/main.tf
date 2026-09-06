terraform {
  required_version = "~> 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = { Project = var.project, ManagedBy = "Terraform", Component = "bootstrap" }
  }
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}
variable "aws_account_id" { type = string }
variable "github_repository" {
  type        = string
  description = "Exact case-sensitive OWNER/REPOSITORY."
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use OWNER/REPOSITORY."
  }
}
variable "project" {
  type    = string
  default = "scalable-iac"
  validation {
    condition     = length(var.project) >= 3 && length(var.project) <= 16 && can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.project))
    error_message = "Project must be 3-16 lowercase letters/numbers, with single internal hyphens and a leading letter."
  }
}
variable "existing_oidc_provider_arn" {
  type        = string
  default     = null
  description = "Set when this account already has the GitHub Actions OIDC provider."
}

locals {
  name = "${var.project}-production"
}

resource "aws_s3_bucket" "state" {
  bucket_prefix = "${var.project}-tfstate-"
  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.project}-github-deploy"
  max_session_duration = 7200
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.existing_oidc_provider_arn != null ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:production"
        }
      }
    }]
  })
}

# Service-wide provisioning permissions are explicit, not AdministratorAccess.
# Use a dedicated AWS workload account; see docs/SECURITY.md for the boundary.
resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProvisionWorkloadServices"
        Effect = "Allow"
        Action = [
          "ec2:*", "elasticloadbalancing:*", "autoscaling:*", "rds:*",
          "cloudwatch:*", "logs:*", "sns:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "ApplicationDNS"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/ami-amazon-linux-latest/*"
      },
      {
        Sid      = "WorkloadLogBuckets"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::${local.name}-alb-logs-*", "arn:aws:s3:::${local.name}-alb-logs-*/*"]
      },
      {
        Sid      = "StateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "StateReadWrite"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.state.arn}/production/terraform.tfstate"
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/production/terraform.tfstate.tflock"
      },
      {
        Sid    = "WorkloadRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile", "iam:UntagInstanceProfile", "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          "arn:aws:iam::${var.aws_account_id}:role/${local.name}-instance",
          "arn:aws:iam::${var.aws_account_id}:role/${local.name}-flow-logs",
          "arn:aws:iam::${var.aws_account_id}:instance-profile/${local.name}-instance"
        ]
      },
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = ["arn:aws:iam::${var.aws_account_id}:role/${local.name}-instance", "arn:aws:iam::${var.aws_account_id}:role/${local.name}-flow-logs"]
        Condition = { StringEquals = { "iam:PassedToService" = ["ec2.amazonaws.com", "vpc-flow-logs.amazonaws.com"] } }
      },
      {
        Effect    = "Allow"
        Action    = "iam:CreateServiceLinkedRole"
        Resource  = "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/*"
        Condition = { StringEquals = { "iam:AWSServiceName" = ["autoscaling.amazonaws.com", "elasticloadbalancing.amazonaws.com", "rds.amazonaws.com"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret", "secretsmanager:TagResource"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:DescribeKey"]
        Resource = "*"
      }
    ]
  })
}

variable "route53_zone_id" {
  type        = string
  description = "Hosted zone that the workload deployment can update."
}

output "state_bucket" { value = aws_s3_bucket.state.id }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "backend_config" {
  value = <<-HCL
    bucket = "${aws_s3_bucket.state.id}"
    key = "production/terraform.tfstate"
    region = "${var.aws_region}"
    encrypt = true
    use_lockfile = true
  HCL
}
