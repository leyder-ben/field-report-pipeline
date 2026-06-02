variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "shared_dynamodb_table_name" {
  description = "DynamoDB table name provisioned by Project A"
  type        = string
  default     = "field-reports"
}

variable "shared_sns_topic_name" {
  description = "SNS topic name provisioned by Project A"
  type        = string
  default     = "field-report-notifications"
}

variable "github_org" {
  description = "GitHub username or organization — used in OIDC trust policy for GitHub Actions deploy role"
  type        = string
}
