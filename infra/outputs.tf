output "intake_bucket_name" {
  description = "S3 bucket where uploaded documents land"
  value       = aws_s3_bucket.intake.id
}

output "processed_bucket_name" {
  description = "S3 bucket where documents are archived after pipeline completes"
  value       = aws_s3_bucket.processed.id
}

output "ui_bucket_name" {
  description = "S3 bucket hosting the upload UI"
  value       = aws_s3_bucket.ui.id
}

output "ui_website_url" {
  description = "Static website URL for the upload form"
  value       = "http://${aws_s3_bucket_website_configuration.ui.website_endpoint}"
}

output "extract_report_role_arn" {
  description = "IAM role ARN for the extract_report Lambda"
  value       = aws_iam_role.extract_report.arn
}

output "merge_summarize_role_arn" {
  description = "IAM role ARN for the merge_summarize Lambda"
  value       = aws_iam_role.merge_summarize.arn
}

output "query_role_arn" {
  description = "IAM role ARN for the query Lambda"
  value       = aws_iam_role.query.arn
}

output "nl_query_role_arn" {
  description = "IAM role ARN for the nl_query Lambda"
  value       = aws_iam_role.nl_query.arn
}

output "deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions deployments"
  value       = aws_iam_role.deploy.arn
}

output "shared_dynamodb_table_arn" {
  description = "ARN of the shared DynamoDB table (provisioned by Project A)"
  value       = data.aws_dynamodb_table.field_reports.arn
}

output "shared_sns_topic_arn" {
  description = "ARN of the shared SNS topic (provisioned by Project A)"
  value       = data.aws_sns_topic.field_report_notifications.arn
}
