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

data "aws_secretsmanager_secret_version" "rds_admin_password_latest_version" {
  secret_id = data.aws_secretsmanager_secret.rds_admin_password.id
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "codebuild_role" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
    ]

    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:*:*:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:Subnet"

      values = module.vpc.database_subnet_arns
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }
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

resource "aws_security_group" "allow_codebuild" {
  name        = "allow_codebuild_sg"
  description = "Allow CodeBuild to access the database and internet"
  vpc_id      = module.vpc.vpc_id
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

resource "aws_iam_role" "code_build_role" {
  name               = "liquibase_code_build_role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_role_policy" "code_build_policy" {
  role   = aws_iam_role.code_build_role.name
  policy = data.aws_iam_policy_document.codebuild_role.json
}

resource "aws_codebuild_project" "liquibase-project" {
  name           = "liquibase-project"
  description    = "codebuild_liquibase_project"
  build_timeout  = 5
  queued_timeout = 5

  service_role = aws_iam_role.code_build_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "URL"
      type  = "PLAINTEXT"
      value = "jdbc:postgresql://${aws_rds_cluster.postgresql.endpoint}"
    }

    environment_variable {
      name  = "PASSWORD"
      type  = "SECRETS_MANAGER"
      value = data.aws_secretsmanager_secret_version.rds_admin_password_latest_version.secret_id
    }
  }

  vpc_config {
    vpc_id             = module.vpc.vpc_id
    subnets            = module.vpc.database_subnets
    security_group_ids = [aws_security_group.allow_codebuild.id]
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/96browng/liquibase-poc.git"
    git_clone_depth = 1
    buildspec       = "buildspec.yaml"

  }
}

resource "aws_codebuild_source_credential" "liquibase_codebuild_github" {
  auth_type   = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token       = var.github_token
}