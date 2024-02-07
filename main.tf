terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.20"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Terraform   = "true"
      Environment = "sandbox"
      Owner       = "Gary Brown"
      Project     = "Liquibase DB schema versioning"
    }
  }
}

data "aws_secretsmanager_secret" "rds_admin_password" {
  arn = aws_rds_cluster.postgresql.master_user_secret[0].secret_arn
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "liquibase-poc-vpc"
  cidr = "10.0.0.0/16"

  azs              = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets  = ["10.0.50.0/24", "10.0.51.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  database_subnets = ["10.0.121.0/24", "10.0.122.0/24"]

  enable_nat_gateway = true

  # dev only
  single_nat_gateway = true
}

resource "aws_rds_cluster" "postgresql" {
  cluster_identifier          = "aurora-cluster-demo"
  engine                      = "aurora-postgresql"
  database_name               = "postgres"
  master_username             = "postgres"
  manage_master_user_password = true
  delete_automated_backups    = true
  skip_final_snapshot         = true

  db_subnet_group_name = module.vpc.database_subnet_group_name

  vpc_security_group_ids = [aws_security_group.allow_database.id]

  tags = {
    Name = "liquibase-target-db"
  }
}

resource "aws_rds_cluster_instance" "cluster_instances" {
  count              = 1
  identifier         = "aurora-cluster-liquibase-${count.index}"
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
}

resource "aws_security_group_rule" "allow_codebuild_inet_rule" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.allow_codebuild.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "allow_database" {
  name        = "allow_database_sg"
  description = "Allow access to the database"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "allow_database_rule" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "TCP"
  security_group_id        = aws_security_group.allow_database.id
  source_security_group_id = aws_security_group.allow_codebuild.id
}
