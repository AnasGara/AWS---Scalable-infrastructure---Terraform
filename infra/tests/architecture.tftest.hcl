mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

variables {
  aws_account_id  = "123456789012"
  certificate_arn = "arn:aws:acm:eu-central-1:123456789012:certificate/test"
  domain_name     = "app.example.com"
  route53_zone_id = "Z0123456789"
}

run "high_availability_contract" {
  command = plan
  assert {
    condition     = length(module.network.public_subnet_ids) == 2 && length(module.network.private_subnet_ids) == 2 && length(module.network.database_subnet_ids) == 2
    error_message = "Each tier must span two AZs."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy.treat_missing_data == "breaching"
    error_message = "Loss of target metrics must alert."
  }
}

run "reject_single_instance" {
  command = plan
  variables { min_size = 1 }
  expect_failures = [var.min_size]
}

