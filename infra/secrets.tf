# Placeholder for any future API credentials needed by the pipeline.
# Current MVP uses only IAM roles for all AWS service access — no secrets required.
# Add real values here if a third-party API key is introduced later.

resource "aws_secretsmanager_secret" "pipeline_config" {
  name                    = "field-report-pipeline/config"
  description             = "Pipeline configuration and any future API credentials"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "pipeline_config" {
  secret_id = aws_secretsmanager_secret.pipeline_config.id

  secret_string = jsonencode({
    placeholder = "no secrets required for MVP"
  })
}
