mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/app/test/1234567890abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/test/1234567890abcdef" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}
variables {
  name                = "scalable-iac-production"
  vpc_id              = "vpc-0123456789abcdef0"
  public_subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  private_subnet_ids  = ["subnet-0123456789abcdef2", "subnet-0123456789abcdef3"]
  certificate_arn     = "arn:aws:acm:eu-central-1:123456789012:certificate/test"
  instance_type       = "t3.micro"
  ami_id              = "ami-0123456789abcdef0"
  min_size            = 2
  desired_capacity    = 2
  max_size            = 6
  deletion_protection = true
  region              = "eu-central-1"
}

run "compute_security_contract" {
  command = apply
  module { source = "./modules/service" }
  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition     = one(aws_launch_template.this.block_device_mappings).ebs[0].encrypted
    error_message = "Root volume encryption must remain enabled."
  }
  assert {
    condition     = aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" && aws_lb_listener.https.protocol == "HTTPS"
    error_message = "Public HTTP must redirect to HTTPS."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.app.from_port == 8080 && aws_vpc_security_group_ingress_rule.app.cidr_ipv4 == null
    error_message = "Application ingress must use SG references, not public CIDRs."
  }
  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "ELB" && aws_autoscaling_group.this.min_size >= 2
    error_message = "Application health and a minimum two instances are required."
  }
}

run "invalid_capacity" {
  command = plan
  module { source = "./modules/service" }
  variables { max_size = 1 }
  expect_failures = [aws_autoscaling_group.this]
}
