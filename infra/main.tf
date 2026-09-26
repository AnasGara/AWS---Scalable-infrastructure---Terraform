data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

locals {
  name = "${var.project}-${var.environment}"
  azs  = slice(sort(data.aws_availability_zones.available.names), 0, 2)
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

check "capacity" {
  assert {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size && var.max_size >= var.min_size && floor(var.desired_capacity) == var.desired_capacity && floor(var.max_size) == var.max_size
    error_message = "Capacity must be integral and min <= desired <= max."
  }
}

module "network" {
  source   = "./modules/network"
  name     = local.name
  vpc_cidr = var.vpc_cidr
  azs      = local.azs
}

module "service" {
  source              = "./modules/service"
  name                = local.name
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  certificate_arn     = var.certificate_arn
  instance_type       = var.instance_type
  ami_id              = var.ami_id
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  deletion_protection = var.deletion_protection
  region              = var.aws_region
  # Instances need NAT routes before cloud-init can download packages.
  depends_on = [module.network]
}

module "database" {
  source              = "./modules/database"
  name                = local.name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.database_subnet_ids
  app_security_group  = module.service.app_security_group_id
  instance_class      = var.db_instance_class
  deletion_protection = var.deletion_protection
}

resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = module.service.alb_dns_name
    zone_id                = module.service.alb_zone_id
    evaluate_target_health = true
  }
}
