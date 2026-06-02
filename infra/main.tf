terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "field-report-terraform-state"
    key          = "field-report-pipeline/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "field-report-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# Shared infrastructure provisioned by Project A
data "aws_dynamodb_table" "field_reports" {
  name = var.shared_dynamodb_table_name
}

data "aws_sns_topic" "field_report_notifications" {
  name = var.shared_sns_topic_name
}
