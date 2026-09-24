variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "app_security_group" { type = string }
variable "instance_class" { type = string }
variable "deletion_protection" { type = bool }

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-db-"
  description = "PostgreSQL from application instances only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.app_security_group
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "postgres" {
  security_group_id            = var.app_security_group
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "postgres17"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_db_instance" "this" {
  identifier                      = var.name
  engine                          = "postgres"
  engine_version                  = "17"
  instance_class                  = var.instance_class
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "application"
  username                        = "dbadmin"
  manage_master_user_password     = true
  multi_az                        = true
  publicly_accessible             = false
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  parameter_group_name            = aws_db_parameter_group.this.name
  backup_retention_period         = 14
  backup_window                   = "02:00-03:00"
  maintenance_window              = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade      = true
  apply_immediately               = false
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final"
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  depends_on                      = [aws_cloudwatch_log_group.this]
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = toset(["postgresql", "upgrade"])
  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = 30
}

output "endpoint" { value = aws_db_instance.this.endpoint }
output "secret_arn" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
output "identifier" { value = aws_db_instance.this.identifier }
