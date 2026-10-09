mock_provider "aws" {
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:rds-test"
        kms_key_id    = "arn:aws:kms:eu-central-1:123456789012:key/test"
        secret_status = "active"
      }]
    }
  }
}
variables {
  name                = "scalable-iac-production"
  vpc_id              = "vpc-0123456789abcdef0"
  subnet_ids          = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  app_security_group  = "sg-0123456789abcdef0"
  instance_class      = "db.t4g.micro"
  deletion_protection = true
}
run "database_security_contract" {
  command = apply
  module { source = "./modules/database" }
  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.storage_encrypted && !aws_db_instance.this.publicly_accessible
    error_message = "Database must be Multi-AZ, private and encrypted."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "Terraform must not manage a plaintext database password."
  }
  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 14 && !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.deletion_protection
    error_message = "Backups, final snapshot and deletion protection are required."
  }
}
