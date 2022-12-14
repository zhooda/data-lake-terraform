# aws provider
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.0"
    }
  }
}

provider "aws" {
  region = "ca-central-1"
}

provider "random" {}
provider "null" {}

module "network" {
  source = "./modules/network"

  name = var.network_name
}


module "mssql" {
  source     = "./modules/mssql"
  identifier = var.mssql_identifier
  username   = var.mssql_username
  password   = var.mssql_password
  # security_group_id = 
  security_group_id = module.network.security_group.id
  subnet_ids        = module.network.subnet_ids
}

module "dms" {
  source            = "./modules/dms"
  dms_bucket_name   = var.dms_bucket_name
  base_name         = var.base_name
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.subnet_ids
  db_secrets_arn    = module.mssql.pass_arn
  security_group_id = module.network.security_group.id
}

# resource "aws_db_instance" "grh_mssql" {
#   allocated_storage   = 20
#   storage_type        = "gp2"
#   engine              = "sqlserver-ex"
#   engine_version      = "15.00.4236.7.v1"
#   instance_class      = "db.t3.small"
#   identifier          = "grh-mssql-sandbox"
#   username            = "admin"
#   password            = "ma1nus3r"
#   license_model       = "license-included"
#   skip_final_snapshot = true
#   # instance_class      = "db.m5.large"
#   # db_name             = "mydb"
# }

# resource "aws_s3_bucket" "raw_bucket" {
#   bucket = "grh_raw_bucket_sandbox"
# }
