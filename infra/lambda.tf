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

# ── extract_report Lambda — Phase 3 ───────────────────────────────────────────
# ── merge_summarize Lambda — Phase 4 ──────────────────────────────────────────
# ── nl_query Lambda        — Phase 11 ─────────────────────────────────────────
