terraform {
  backend "s3" {
    bucket         = "my-data-quality-bucket-thanh"
    key            = "serverless-ai-demo/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# -----------------------------
# S3 BUCKET
# -----------------------------
resource "aws_s3_bucket" "uploads" {
  bucket = var.s3_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------
# DYNAMODB TABLE
# -----------------------------
resource "aws_dynamodb_table" "files" {
  name         = "ai_demo_files"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_id"

  attribute {
    name = "file_id"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------
# LAMBDA ROLE
# -----------------------------
resource "aws_iam_role" "lambda_role" {
  name = "lambda_ai_demo_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_access_policy" {
  name = "lambda_access_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.files.arn
      }
    ]
  })
}

# -----------------------------
# LAMBDA FUNCTION
# -----------------------------
resource "aws_lambda_function" "ai_demo" {
  function_name = "ai_demo_function"
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_role.arn

  filename         = "${path.module}/../lambda/deployment.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/deployment.zip")

  environment {
    variables = {
      S3_BUCKET    = aws_s3_bucket.uploads.bucket
      DYNAMO_TABLE = aws_dynamodb_table.files.name
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.ai_demo.function_name}"
  retention_in_days = 14
}

# -----------------------------
# API GATEWAY HTTP API (v2)
# -----------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "ai-demo-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ai_demo.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /analyze"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# -----------------------------
# 🔥 FIX QUAN TRỌNG: Tạo Stage
# -----------------------------
resource "aws_apigatewayv2_stage" "test" {
  api_id = aws_apigatewayv2_api.api.id
  name   = "test"

  auto_deploy = true
}

# Cho phép API gọi Lambda
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ai_demo.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
