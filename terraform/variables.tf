variable "region" {
  default = "east-southeast-1"
}

variable "s3_bucket_name" {
  default = "serverless-ai-${random_id.bucket_id.hex}"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}
