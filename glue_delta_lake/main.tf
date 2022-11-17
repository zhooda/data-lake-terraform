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

locals {
  # name  = "grh-${replace(basename(path.cwd), "_", "-")}"
  name  = var.name
  _name = replace(var.name, "-", "_")
  # _name = "grh-${basename(path.cwd)}"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${local.name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ca-central-1a", "ca-central-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false
  create_igw         = true

  create_database_subnet_group           = true
  create_database_internet_gateway_route = true
  create_database_subnet_route_table     = true
  database_subnets                       = ["10.0.3.0/24", "10.0.4.0/24"]
  database_subnet_group_name             = "${local.name}-subnet-group"

  enable_dns_hostnames = true
  enable_dns_support   = true

  manage_default_network_acl = true
  default_network_acl_tags   = { Name = "${local.name}-default" }

  manage_default_route_table = true
  default_route_table_tags   = { Name = "${local.name}-default" }

  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }
  default_security_group_ingress = [
    {
      description      = "allow all"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]
  default_security_group_egress = [
    {
      description      = "allow all"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  tags = {
    Name        = "${local.name}-vpc"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }
}

resource "aws_db_instance" "mssql" {
  depends_on = [
    module.vpc
  ]

  allocated_storage      = "20"
  storage_type           = "gp2"
  engine                 = "sqlserver-se"
  engine_version         = "15.00.4236.7.v1"
  instance_class         = "db.m5.large"
  identifier             = "${local.name}-mssql"
  username               = "admin"
  password               = "ma1nus3r"
  license_model          = "license-included"
  skip_final_snapshot    = true
  publicly_accessible    = true
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  tags = {
    Name        = "${local.name}-mssql"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }

}

resource "aws_s3_bucket" "dms_bucket" {
  bucket = "${local.name}-dms-bucket"


  tags = {
    Name        = "${local.name}-dms-bucket"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }
}

resource "aws_s3_object" "glue_cdc_job_object" {
  bucket = aws_s3_bucket.dms_bucket.bucket
  key    = "scripts/glue_cdc_job.py"
  source = "lake_job.py"
  etag   = filemd5("lake_job.py")
}

resource "aws_s3_object" "delta_core_object" {
  bucket = aws_s3_bucket.dms_bucket.bucket
  key    = "lib/delta-core_2.12-1.0.1.jar"
  source = "resources/delta-core_2.12-1.0.1.jar"
  etag   = filemd5("resources/delta-core_2.12-1.0.1.jar")
}

resource "aws_glue_job" "glue_cdc_job" {
  name              = "${local.name}-glue-cdc-job"
  role_arn          = aws_iam_role.glue_role.arn
  glue_version      = "3.0"
  number_of_workers = 10
  worker_type       = "G.1X"

  command {
    script_location = "s3://${aws_s3_bucket.dms_bucket.bucket}/${aws_s3_object.glue_cdc_job_object.key}"
  }

  default_arguments = {
    "--full_load"            = "false"
    "--merge_key"            = "id"
    "--raw_zone_path"        = "s3://${aws_s3_bucket.dms_bucket.bucket}/dms/"
    "--structured_zone_path" = "s3://${aws_s3_bucket.dms_bucket.bucket}/delta/"
    "--table_schema"         = "test"
    "--table_name"           = "test"

    "--job-bookmark-option"              = "job-bookmark-enable"
    "--job-language"                     = "python"
    "--enable-glue-datacatalog"          = "true"
    "--TempDir"                          = "s3://aws-glue-assets-037182765867-ca-central-1/temporary/"
    "--enable-metrics"                   = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://aws-glue-assets-037182765867-ca-central-1/sparkHistoryLogs/"
    "--enable-job-insights"              = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--extra-jars"                       = "s3://${aws_s3_bucket.dms_bucket.bucket}/lib/delta-core_2.12-1.0.1.jar"
    "--extra-py-files"                   = "s3://${aws_s3_bucket.dms_bucket.bucket}/lib/delta-core_2.12-1.0.1.jar"
  }
}

data "aws_iam_policy_document" "s3_admin_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:*",
      "s3-object-lambda:*",
    ]

    resources = [
      aws_s3_bucket.dms_bucket.arn,
    ]
  }
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com", "glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dms_role" {
  name               = "${local.name}-dms-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json

  inline_policy {
    name   = "${local._name}_dms_s3_admin_policy"
    policy = data.aws_iam_policy_document.s3_admin_policy.json
  }

  tags = {
    Name        = "${local.name}-dms-role"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${local.name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json

  # inline_policy {
  #   name   = "${local._name}_glue_s3_admin_policy"
  #   policy = data.aws_iam_policy_document.s3_admin_policy.json
  # }

  tags = {
    Name        = "${local.name}-glue-role"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }
}

resource "aws_iam_role_policy_attachment" "dms_admin_attachment" {
  role       = aws_iam_role.dms_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "glue_service_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

module "database_migration_service" {
  source  = "terraform-aws-modules/dms/aws"
  version = "~> 1.0"

  # Subnet group
  repl_subnet_group_name        = "${local.name}-dms-subnet-group"
  repl_subnet_group_description = "DMS Subnet group"
  repl_subnet_group_subnet_ids  = module.vpc.public_subnets

  # Instance
  repl_instance_allocated_storage            = 50
  repl_instance_auto_minor_version_upgrade   = true
  repl_instance_allow_major_version_upgrade  = true
  repl_instance_apply_immediately            = true
  repl_instance_engine_version               = "3.4.7"
  repl_instance_multi_az                     = false
  repl_instance_preferred_maintenance_window = "sun:10:30-sun:14:30"
  repl_instance_publicly_accessible          = true
  repl_instance_class                        = "dms.t3.micro"
  repl_instance_id                           = "${local.name}-dms-replication-instance"
  repl_instance_vpc_security_group_ids       = [module.vpc.default_security_group_id]
  repl_instance_tags = {
    Name        = "${local.name}-dms-replication-instance"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }

  endpoints = {
    source = {
      database_name = "test"
      endpoint_id   = "${local.name}-mssql-source"
      endpoint_type = "source"
      engine_name   = "sqlserver"
      username      = "admin"
      password      = "ma1nus3r"
      port          = 1433
      server_name   = split(":", aws_db_instance.mssql.endpoint)[0]
      ssl_mode      = "none"
      tags = {
        EndpointType = "source"
        Terraform    = var.tag_terraform
        Environment  = var.tag_env
        Owner        = var.tag_owner
      }
      #   extra_connection_attributes = "heartbeatFrequency=1;"
    }

    destination = {
      endpoint_id   = "${local.name}-s3-destination"
      endpoint_type = "target"
      engine_name   = "s3"
      s3_settings = {
        service_access_role_arn = aws_iam_role.dms_role.arn
        bucket_name             = aws_s3_bucket.dms_bucket.bucket
        bucket_folder           = "dms"
        cdc_path                = "cdc"
        data_format             = "parquet"
        compression_type        = "NONE"
        timestamp_column_name   = "last_updated"
      }
      tags = {
        EndpointType = "destination"
        Terraform    = var.tag_terraform
        Environment  = var.tag_env
        Owner        = var.tag_owner
      }
    }
  }

  replication_tasks = {
    cdc_ex = {
      replication_task_id       = "${local.name}-mssql-s3-cdc-task"
      migration_type            = "full-load-and-cdc"
      replication_task_settings = file("task_settings.json")
      table_mappings            = file("table_mappings.json")
      source_endpoint_key       = "source"
      target_endpoint_key       = "destination"
      tags = {
        Task        = "SQL Server to S3"
        Terraform   = var.tag_terraform
        Environment = var.tag_env
        Owner       = var.tag_owner
      }
    }
  }


  tags = {
    Name        = "${local.name}-dms"
    Terraform   = var.tag_terraform
    Environment = var.tag_env
    Owner       = var.tag_owner
  }
}

module "redshift_cluster" {
  source = "cloudposse/redshift-cluster/aws"
  # Cloud Posse recommends pinning every module to a specific version
  # version = "x.x.x"
  name = "${local.name}-redshift-cluster"

  subnet_ids             = module.vpc.public_subnets
  vpc_security_group_ids = [module.vpc.default_security_group_id]

  admin_user            = "awsuser"
  admin_password        = "R3dsh1ft"
  database_name         = "dev"
  node_type             = "dc2.large"
  cluster_type          = "single-node"
  publicly_accessible   = true
  allow_version_upgrade = true

  # context = module.this.context
}

output "db_endpoint" {
  value = aws_db_instance.mssql.endpoint
}

output "redshift_role_arn" {
  value = module.redshift_cluster.endpoint
}
# output "db-name" {
#   value = aws_db_instance.mssql.
# }
