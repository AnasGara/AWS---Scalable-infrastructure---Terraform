mock_provider "aws" {}
variables {
  aws_account_id             = "123456789012"
  github_repository          = "example/infrastructure"
  route53_zone_id            = "Z0123456789"
  existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

run "state_and_trust_contract" {
  command = plan
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State recovery requires versioning."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "State bucket must block public access."
  }
  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example/infrastructure:environment:production"
    error_message = "OIDC trust must be restricted to the exact repository and production environment."
  }
}
