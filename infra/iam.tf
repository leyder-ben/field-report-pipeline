locals {
  lambda_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  bedrock_resources = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
    "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-*"
  ]
}

# ─── extract_report Lambda ────────────────────────────────────────────────────
# Pass 1: reads uploaded file from intake, calls Bedrock for classification,
# invokes merge_summarize with the page manifest.

resource "aws_iam_role" "extract_report" {
  name               = "extract-report-lambda-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "extract_report" {
  name = "extract-report-lambda-policy"
  role = aws_iam_role.extract_report.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "IntakeRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.intake.arn}/*"
      },
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = local.bedrock_resources
      },
      {
        Sid      = "InvokeMergeSummarize"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:field-report-merge-summarize"
      }
    ]
  })
}

# ─── merge_summarize Lambda ───────────────────────────────────────────────────
# Pass 2: receives page manifest, calls Bedrock for extraction per document
# type, writes to DynamoDB, moves original to processed bucket, publishes SNS.

resource "aws_iam_role" "merge_summarize" {
  name               = "merge-summarize-lambda-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "merge_summarize" {
  name = "merge-summarize-lambda-policy"
  role = aws_iam_role.merge_summarize.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "IntakeReadDelete"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.intake.arn}/*"
      },
      {
        Sid      = "ProcessedWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.processed.arn}/*"
      },
      {
        Sid      = "DynamoDBWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = data.aws_dynamodb_table.field_reports.arn
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = data.aws_sns_topic.field_report_notifications.arn
      },
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = local.bedrock_resources
      }
    ]
  })
}

# ─── query Lambda ─────────────────────────────────────────────────────────────
# Handles GET /reports (filtered queries) and GET /reports?action=presigned_url.
# Presigned URL generation works by signing with the Lambda's own role — the
# role needs s3:PutObject on the intake bucket for the signature to be valid.

resource "aws_iam_role" "query" {
  name               = "pipeline-query-lambda-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "query" {
  name = "pipeline-query-lambda-policy"
  role = aws_iam_role.query.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "DynamoDBRead"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem"]
        Resource = data.aws_dynamodb_table.field_reports.arn
      },
      {
        Sid      = "PresignedUpload"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.intake.arn}/*"
      }
    ]
  })
}

# ─── nl_query Lambda ──────────────────────────────────────────────────────────
# Phase 2: converts natural language string to DynamoDB filter via Bedrock Haiku,
# then executes the query.

resource "aws_iam_role" "nl_query" {
  name               = "pipeline-nl-query-lambda-role"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy" "nl_query" {
  name = "pipeline-nl-query-lambda-policy"
  role = aws_iam_role.nl_query.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "DynamoDBRead"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem"]
        Resource = data.aws_dynamodb_table.field_reports.arn
      },
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = local.bedrock_resources
      }
    ]
  })
}

# ─── GitHub Actions deploy role ───────────────────────────────────────────────
# OIDC provider already exists from Project A (T-002) — use data source, do not
# recreate it.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "deploy" {
  name = "field-report-pipeline-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/field-report-pipeline:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "field-report-pipeline-deploy-policy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaDeploy"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:field-report-*"
      },
      {
        Sid    = "UISync"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.ui.arn,
          "${aws_s3_bucket.ui.arn}/*"
        ]
      }
    ]
  })
}
