# ── query Lambda ──────────────────────────────────────────────────────────────
# Phase 2: GET /upload-url — generates presigned PUT URL for intake bucket.
# Phase 8: GET /reports — structured DynamoDB query added to same function.

resource "aws_cloudwatch_log_group" "query" {
  name              = "/aws/lambda/field-report-query"
  retention_in_days = 30
}

data "archive_file" "query" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/query"
  output_path = "${path.module}/../lambda/query.zip"
}

resource "aws_lambda_function" "query" {
  function_name    = "field-report-query"
  role             = aws_iam_role.query.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256

  environment {
    variables = {
      INTAKE_BUCKET  = aws_s3_bucket.intake.bucket
      DYNAMODB_TABLE = var.shared_dynamodb_table_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.query,
    aws_iam_role_policy.query,
  ]
}

# ── extract_report Lambda ─────────────────────────────────────────────────────
# Pass 1: triggered by S3 object creation on intake bucket.
# Sends the uploaded PDF or image to Bedrock for page classification.
# Outputs a page manifest and invokes merge_summarize asynchronously.

resource "aws_cloudwatch_log_group" "extract_report" {
  name              = "/aws/lambda/field-report-extract-report"
  retention_in_days = 30
}

data "archive_file" "extract_report" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/extract_report"
  output_path = "${path.module}/../lambda/extract_report.zip"
}

resource "aws_lambda_function" "extract_report" {
  function_name    = "field-report-extract-report"
  role             = aws_iam_role.extract_report.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 1024
  filename         = data.archive_file.extract_report.output_path
  source_code_hash = data.archive_file.extract_report.output_base64sha256

  environment {
    variables = {
      INTAKE_BUCKET           = aws_s3_bucket.intake.bucket
      MERGE_SUMMARIZE_FUNCTION = "field-report-merge-summarize"
      BEDROCK_MODEL_ID        = "us.anthropic.claude-sonnet-4-6"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.extract_report,
    aws_iam_role_policy.extract_report,
  ]
}

# Allow S3 to invoke the Lambda. The depends_on on the notification resource
# ensures this permission exists before S3 tries to validate it.
resource "aws_lambda_permission" "s3_extract_report" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.extract_report.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.intake.arn
}

resource "aws_s3_bucket_notification" "intake" {
  bucket = aws_s3_bucket.intake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.extract_report.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_lambda_permission.s3_extract_report]
}

# ── merge_summarize Lambda — Phase 4 ──────────────────────────────────────────
# ── nl_query Lambda        — Phase 11 ─────────────────────────────────────────
