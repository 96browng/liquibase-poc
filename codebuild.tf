

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
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.rds_admin_password.arn]
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


resource "aws_iam_role" "code_build_role" {
  name               = "liquibase_code_build_role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_role_policy" "code_build_policy" {
  role   = aws_iam_role.code_build_role.name
  policy = data.aws_iam_policy_document.codebuild_role.json
}


resource "aws_security_group" "allow_codebuild" {
  name        = "allow_codebuild_sg"
  description = "Allow CodeBuild to access the database and internet"
  vpc_id      = module.vpc.vpc_id
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
      value = "jdbc:postgresql://${aws_rds_cluster.postgresql.endpoint}:${aws_rds_cluster.postgresql.port}/${aws_rds_cluster.postgresql.database_name}"
    }

    environment_variable {
      name  = "PASSWORD"
      type  = "SECRETS_MANAGER"
      value = data.aws_secretsmanager_secret.rds_admin_password.name
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