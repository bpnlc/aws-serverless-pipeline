provider "aws" {
  region = "eu-west-2" # London region
}

# Generate a random suffix so your S3 bucket name is globally unique
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket 
resource "aws_s3_bucket" "upload_bucket" {
  bucket = "serverless-pipeline-upload-${random_id.bucket_suffix.hex}"
}

#  DynamoDB Table 
resource "aws_dynamodb_table" "processed_files" {
  name         = "ProcessedFilesTable"
  billing_mode = "PAY_PER_REQUEST" 
  hash_key     = "file_id"

  attribute {
    name = "file_id"
    type = "S"
  }
}

# SNS Topic & Subscription (The Alert System)
resource "aws_sns_topic" "alerts" {
  name = "DataProcessingAlerts"
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "bipinlamichhane36@gmail.com"
}

# IAM Role & Policy (Security / Least Privilege)
resource "aws_iam_role" "lambda_exec_role" {
  name = "serverless_pipeline_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_dynamodb_sns_policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.processed_files.arn },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = aws_sns_topic.alerts.arn },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

# Package and Deploy Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda_function.zip"
  function_name    = "S3DataProcessor"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.processed_files.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }
}

# S3 Event Notification 
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload_bucket.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.upload_bucket.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}

# Output the Bucket Name 
output "s3_bucket_name" {
  value = aws_s3_bucket.upload_bucket.bucket
}