# ─── Intake bucket ────────────────────────────────────────────────────────────
# Uploaded PDFs and photos land here. S3 event notification to extract_report
# Lambda is defined in lambda.tf after the Lambda ARN is known.

resource "aws_s3_bucket" "intake" {
  bucket = "field-report-intake-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "intake" {
  bucket                  = aws_s3_bucket.intake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow browser PUT via presigned URL. CORS is needed even though the bucket is
# private — the presigned URL carries time-limited credentials; CORS just lets
# the browser make the cross-origin request. Wildcard origin is safe here.
resource "aws_s3_bucket_cors_configuration" "intake" {
  bucket = aws_s3_bucket.intake.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ─── Processed bucket ─────────────────────────────────────────────────────────
# Original files are moved here by merge_summarize after a successful pipeline
# run. Kept private — access only through Lambda.

resource "aws_s3_bucket" "processed" {
  bucket = "field-report-processed-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── Upload UI bucket ─────────────────────────────────────────────────────────
# Static website hosting for the mobile upload form.

resource "aws_s3_bucket" "ui" {
  bucket = "field-report-pipeline-ui-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket                  = aws_s3_bucket.ui.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "ui" {
  bucket = aws_s3_bucket.ui.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# depends_on required — without it Terraform applies the policy before AWS has
# fully propagated the all-false public access block and the PUT is rejected
# (T-003 from Project A).
resource "aws_s3_bucket_policy" "ui" {
  bucket = aws_s3_bucket.ui.id

  depends_on = [aws_s3_bucket_public_access_block.ui]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.ui.arn}/*"
      }
    ]
  })
}
