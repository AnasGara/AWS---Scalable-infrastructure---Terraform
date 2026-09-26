variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_account_id" {
  type        = string
  description = "Expected AWS account; provider refuses to deploy elsewhere."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide a 12-digit AWS account ID."
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

variable "environment" {
  type    = string
  default = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Use development, staging, or production."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 8, 21)) && can(regex("/16$", var.vpc_cidr))
    error_message = "Provide an IPv4 /16 VPC CIDR."
  }
}

variable "certificate_arn" {
  type        = string
  description = "Issued ACM certificate in the deployment region, matching domain_name."
  validation {
    condition     = startswith(var.certificate_arn, "arn:aws:acm:${var.aws_region}:${var.aws_account_id}:certificate/")
    error_message = "Provide an ACM certificate ARN in the deployment region and account."
  }
}

variable "domain_name" {
  type        = string
  description = "Application DNS name covered by the ACM certificate."
}

variable "route53_zone_id" {
  type        = string
  description = "Existing public hosted zone in this account."
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "m6i.large"], var.instance_type)
    error_message = "Choose a supported x86_64 instance type."
  }
}

variable "ami_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Pinned x86_64 AL2023 AMI. Null resolves the current AWS SSM public parameter. Pin after initial evaluation."
}

variable "min_size" {
  type    = number
  default = 2
  validation {
    condition     = var.min_size >= 2 && floor(var.min_size) == var.min_size
    error_message = "At least two instances are required."
  }
}

variable "desired_capacity" {
  type    = number
  default = 2
  validation {
    condition     = floor(var.desired_capacity) == var.desired_capacity && var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "Desired capacity must be an integer between min_size and max_size."
  }
}

variable "max_size" {
  type    = number
  default = 6
  validation {
    condition     = floor(var.max_size) == var.max_size && var.max_size >= var.min_size
    error_message = "Maximum capacity must be an integer at least min_size."
  }
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Protects ALB and RDS. Disable deliberately before teardown."
}

variable "alarm_email" {
  type        = string
  default     = null
  description = "Optional SNS email recipient; subscription must be confirmed."
}
