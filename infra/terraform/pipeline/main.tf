data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "vpc" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_subnet" "list" {
  count = "${length(data.aws_subnet_ids.vpc.ids)}"
  id    = "${data.aws_subnet_ids.vpc.ids[count.index]}"
}

provider "aws" {
  region = "${var.region}"
}

module "state_bucket" {
	source = "git::ssh://git@github.com/2ndWatch/tfm_state_bucket.git"

	bucket_name = "schittamuru-terraform-state"
  	bucket_users = ["sindhu", "Sriven"]
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.bucket_name}"
  acl           = "private"
  force_destroy = true
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    effect = "Allow"
  }
}

resource "aws_iam_role" "artifacts" {
  name = "artifacts"

  assume_role_policy = "${data.aws_iam_policy_document.artifacts.json}"
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.artifacts.arn}",
      "${aws_s3_bucket.artifacts.arn}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.artifacts.id}"

  policy = "${data.aws_iam_policy_document.codepipeline.json}"
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name = "codebuild-role"

  assume_role_policy = "${data.aws_iam_policy_document.codebuild_assume_role.json}"
}

data "aws_iam_policy_document" "codebuild_policy" {
  statement {
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "autoscaling:*",
      "elasticloadbalancing:*",
      "iam:GetUser",
      "ec2:*",
      "s3:*",
      "kms:*",
      "events:PutEvents",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_policy" "codebuild_policy" {
  name        = "codebuild-policy"
  path        = "/service-role/"
  description = "Policy used in trust relationship with CodeBuild"

  policy = "${data.aws_iam_policy_document.codebuild_policy.json}"
}

resource "aws_iam_policy_attachment" "codebuild_policy_attachment" {
  name       = "codebuild-policy-attachment"
  policy_arn = "${aws_iam_policy.codebuild_policy.arn}"
  roles      = ["${aws_iam_role.codebuild.id}"]
}

resource "aws_codebuild_project" "build_ami" {
  name          = "hellouser-ami-builder"
  description   = "Build and update AMIs to be used with hello user service"
  build_timeout = "30"
  service_role  = "${aws_iam_role.codebuild.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/python:2.7.12"
    type         = "LINUX_CONTAINER"

    environment_variable {
      "name"  = "BUILD_OUTPUT_BUCKET"
      "value" = "${aws_s3_bucket.artifacts.id}"
    }

    environment_variable {
      "name"  = "AWS_REGION"
      "value" = "${var.region}"
    }

    environment_variable {
      "name"  = "BUILD_VPC_ID"
      "value" = "${data.aws_vpc.default.id}"
    }

    environment_variable {
      "name"  = "BUILD_SUBNET_ID"
      "value" = "${data.aws_subnet_ids.vpc.ids[0]}"
    }
  }

  source {
    type = "CODEPIPELINE"
  }

  tags {
    "Environment" = "Prod"
  }
}

resource "aws_codebuild_project" "terraform" {
  name          = "hellouser-deploy"
  description   = "Update and Recycle Autoscaling Groups for HelloUser service"
  build_timeout = "30"
  service_role  = "${aws_iam_role.codebuild.arn}"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/python:2.7.12"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-terraform.yml"
  }

  tags {
    "Environment" = "Prod"
  }
}

resource "aws_codepipeline" "artifacts" {
  name     = "ami-builder"
  role_arn = "${aws_iam_role.artifacts.arn}"

  artifact_store {
    location = "${aws_s3_bucket.artifacts.bucket}"
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "${var.vcs_provider}"
      version          = "1"
      output_artifacts = ["${var.artifact_name}"]

      configuration {
        Owner  = "${var.owner}"
        Repo   = "${var.repo}"
        Branch = "${var.branch}"
        OAuthToken = "${var.oauth_token}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["${var.artifact_name}"]
      version         = "1"

      configuration {
        ProjectName = "${aws_codebuild_project.build_ami.name}"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["${var.artifact_name}"]
      version         = "1"

      configuration {
        ProjectName = "${aws_codebuild_project.terraform.name}"
      }
    }
  }
}

data "aws_iam_policy_document" "sns" {
  statement {
    effect = "Allow"

    actions = ["sns:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = ["${aws_sns_topic.user_updates.arn}"]
  }
}

resource "aws_sns_topic" "user_updates" {
  name = "ami-builder-topic"
}

resource "aws_sns_topic_policy" "default" {
  arn    = "${aws_sns_topic.user_updates.arn}"
  policy = "${data.aws_iam_policy_document.sns.json}"
}

resource "aws_cloudwatch_event_rule" "ami_build" {
  name        = "ami-build-status"
  description = "AmiBuilder-Complete"

  event_pattern = <<PATTERN
{
  "detail-type": [ "AmiBuilder" ],
  "detail": {
    "AmiStatus": [ "Created" ]
  }
}
PATTERN
}
