mock_provider "aws" {}
variables {
  name     = "scalable-iac-production"
  vpc_cidr = "10.42.0.0/16"
  azs      = ["eu-central-1a", "eu-central-1b"]
}
run "network_isolation_contract" {
  command = apply
  module { source = "./modules/network" }
  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_route.nat) == 2
    error_message = "Private application subnets require independent AZ-local NAT gateways."
  }
  assert {
    condition     = alltrue([for az, subnet in aws_subnet.app : subnet.map_public_ip_on_launch == false])
    error_message = "App subnets must not assign public IP addresses."
  }
  assert {
    condition     = length(aws_route_table.database.route) == 0
    error_message = "Database route table must not contain internet or NAT routes."
  }
  assert {
    condition     = length(distinct(concat([for subnet in aws_subnet.public : subnet.cidr_block], [for subnet in aws_subnet.app : subnet.cidr_block], [for subnet in aws_subnet.database : subnet.cidr_block]))) == 6
    error_message = "The six subnet CIDRs must be distinct."
  }
}
