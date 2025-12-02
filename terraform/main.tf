provider "aws" {
  region = var.region
}

# S3 bucket để lưu file
resource "aws_s3_bucket" "uploads" {
  bucket = var.s3_bucket_name
}

resource "aws_s3_bucket_acl" "uploads_acl" {
  bucket = aws_s3_bucket.uploads.id
  acl    = "private"
}

# DynamoDB table để lưu metadata
resource "aws_dynamodb_table" "files" {
  name           = "ai_demo_files"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "file_id"
  attribute {
    name = "file_id"
    type = "S"
  }
}

# IAM role cho Lambda
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
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function
resource "aws_lambda_function" "ai_demo" {
  function_name = "ai_demo_function"
  handler       = "index.lambda_handler"
  runtime       = "python3.11"
  role          = aws_iam_role.lambda_role.arn
  filename      = "${path.module}/../lambda/deployment.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/deployment.zip")
  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.uploads.bucket
      DYNAMO_TABLE = aws_dynamodb_table.files.name
    }
  }
}

#role for lambda to access s3 and dynamodb
resource "aws_iam_role_policy" "lambda_access_policy" {
  name = "lambda_access_policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.files.arn
      }
    ]
  })
}


#cloudwatch log group for lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.ai_demo.function_name}"
  retention_in_days = 14
}

# API Gateway
resource "aws_apigatewayv2_api" "api" {
  name          = "ai-demo-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ai_demo.invoke_arn
}

resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /analyze"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ai_demo.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
