# ── REST API ───────────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "pipeline" {
  name        = "field-report-pipeline-api"
  description = "Field Report Pipeline API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ── /upload-url ────────────────────────────────────────────────────────────────

resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.pipeline.id
  parent_id   = aws_api_gateway_rest_api.pipeline.root_resource_id
  path_part   = "upload-url"
}

# GET /upload-url — returns presigned PUT URL for intake bucket

resource "aws_api_gateway_method" "get_upload_url" {
  rest_api_id   = aws_api_gateway_rest_api.pipeline.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_upload_url" {
  rest_api_id             = aws_api_gateway_rest_api.pipeline.id
  resource_id             = aws_api_gateway_resource.upload_url.id
  http_method             = aws_api_gateway_method.get_upload_url.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.query.invoke_arn
}

# CORS — OPTIONS /upload-url

resource "aws_api_gateway_method" "options_upload_url" {
  rest_api_id   = aws_api_gateway_rest_api.pipeline.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_upload_url" {
  rest_api_id = aws_api_gateway_rest_api.pipeline.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.options_upload_url.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_upload_url_200" {
  rest_api_id = aws_api_gateway_rest_api.pipeline.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.options_upload_url.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# depends_on required — integration response creation races the mock integration
# registration in API Gateway (T-004 from Project A).
resource "aws_api_gateway_integration_response" "options_upload_url_200" {
  rest_api_id = aws_api_gateway_rest_api.pipeline.id
  resource_id = aws_api_gateway_resource.upload_url.id
  http_method = aws_api_gateway_method.options_upload_url.http_method
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.options_upload_url,
    aws_api_gateway_method_response.options_upload_url_200,
  ]

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ── Deployment and stage ───────────────────────────────────────────────────────
# triggers.redeployment forces a new deployment whenever any method or
# integration changes — required because API Gateway deployments are immutable.

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.pipeline.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload_url.id,
      aws_api_gateway_method.get_upload_url.id,
      aws_api_gateway_integration.get_upload_url.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.pipeline.id
  stage_name    = "prod"
}

# ── Lambda permission ──────────────────────────────────────────────────────────

resource "aws_lambda_permission" "api_gateway_query" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pipeline.execution_arn}/*/*"
}
