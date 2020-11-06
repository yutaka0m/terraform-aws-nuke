locals {
  tags = {
    Terraform = "true"
  }

  # https://github.com/rebuy-de/aws-nuke/releases
  aws_nuke_version       = "v2.14.0"
  codebuild_project_name = "aws-nuke"
}

data "aws_caller_identity" "current" {}

##################
# IAM
##################
# CodeBuild
resource "aws_iam_role" "codebuild" {
  name               = "aws-nuke-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy" "administrator_access" {
  arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = data.aws_iam_policy.administrator_access.arn
}

# CloudWatch Events
resource "aws_iam_role" "events" {
  name               = "aws-nuke-cloudwatch-events-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role.json
}

data "aws_iam_policy_document" "events_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "events" {
  name   = "aws-nuke-cloudwatch-events-role-policy"
  policy = data.aws_iam_policy_document.events.json
}

data "aws_iam_policy_document" "events" {
  statement {
    effect    = "Allow"
    actions   = ["codebuild:StartBuild"]
    resources = [aws_codebuild_project.this.arn]
  }
}

resource "aws_iam_role_policy_attachment" "events" {
  role       = aws_iam_role.events.name
  policy_arn = aws_iam_policy.events.arn
}

##################
# CodeBuild
##################
resource "aws_codebuild_project" "this" {
  name         = local.codebuild_project_name
  service_role = aws_iam_role.codebuild.arn
  description  = "run aws-nuke"

  environment {
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type            = "LINUX_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = true

    environment_variable {
      name  = "AWS_NUKE_VERSION"
      value = local.aws_nuke_version
    }
    environment_variable {
      name  = "NUKE_CONFIG_BUCKET_ID"
      value = module.s3_bucket_for_aws_nuke.this_s3_bucket_id
    }
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  source {
    type     = "S3"
    location = "${module.s3_bucket_for_aws_nuke.this_s3_bucket_id}/buildspec.zip"
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.this.name
    }
  }

  depends_on = [
    aws_s3_bucket_object.buildspec,
    aws_s3_bucket_object.nuke_config,
  ]

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/codebuild/aws-nuke"
  retention_in_days = 30
}

##################
# S3
##################
module "s3_bucket_for_aws_nuke" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 1.16"

  bucket_prefix = "aws-nuke"

  versioning = {
    enabled = true
  }

  lifecycle_rule = [
    {
      enabled = true
      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = local.tags
}

##################
# Upload to S3
##################
data "archive_file" "buildspec" {
  type        = "zip"
  source_file = "buildspec.yaml"
  output_path = "buildspec.zip"
}

resource "aws_s3_bucket_object" "buildspec" {
  bucket = module.s3_bucket_for_aws_nuke.this_s3_bucket_id
  key    = "buildspec.zip"
  source = data.archive_file.buildspec.output_path
  etag   = filemd5("buildspec.yaml")
}

resource "local_file" "nuke_config" {
  content = templatefile("nuke-config.yaml.tpl", {
    account_id                  = data.aws_caller_identity.current.account_id
    cloudwatch_events_rule_name = aws_cloudwatch_event_rule.this.name
    cloudwatch_log_group_name   = aws_cloudwatch_log_group.this.name
    codebuild_project_name      = local.codebuild_project_name
    s3_bucket_name              = module.s3_bucket_for_aws_nuke.this_s3_bucket_id
  })
  filename = "nuke-config.yaml"
}

resource "aws_s3_bucket_object" "nuke_config" {
  bucket = module.s3_bucket_for_aws_nuke.this_s3_bucket_id
  key    = "nuke-config.yaml"
  source = "nuke-config.yaml"
  etag   = filemd5("nuke-config.yaml.tpl")

  depends_on = [local_file.nuke_config]
}

##################
# CloudWatch Events
##################
resource "aws_cloudwatch_event_rule" "this" {
  name                = "aws-nuke"
  description         = "Run aws-nuke"
  schedule_expression = "cron(0 9 1 * ? *)" # JST:毎月1日の18時
}

resource "aws_cloudwatch_event_target" "this" {
  rule     = aws_cloudwatch_event_rule.this.name
  arn      = aws_codebuild_project.this.arn
  role_arn = aws_iam_role.events.arn
}
