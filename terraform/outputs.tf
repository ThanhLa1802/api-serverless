output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}
output "s3_bucket_name" {
  value = aws_s3_bucket.uploads.bucket
}