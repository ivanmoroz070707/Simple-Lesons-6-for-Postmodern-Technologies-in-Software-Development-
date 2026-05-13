terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3       = "http://127.0.0.1:4566"
    lambda   = "http://127.0.0.1:4566"
    dynamodb = "http://127.0.0.1:4566"
    iam      = "http://127.0.0.1:4566"
    sts      = "http://127.0.0.1:4566"
  }
}

resource "aws_s3_bucket" "start" {
  bucket = "s3-start-bucket-ivan"
  lifecycle_rule {
    id      = "clean-up-temp-files"
    enabled = true

    expiration {
      days = 1
    }
  }
}

resource "aws_s3_bucket" "finish" {
  bucket = "s3-finish-bucket-ivan"
}





resource "aws_dynamodb_table" "audit_log" {
  name           = "file-transfer-audit"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "FileName"
  
  attribute {
    name = "FileName"
    type = "S"
  }
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}


data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "s3-copy-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}


resource "aws_lambda_function" "copy_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "copy_s3_file_and_log"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DEST_BUCKET    = aws_s3_bucket.finish.id
      DYNAMODB_TABLE = aws_dynamodb_table.audit_log.name
    }
  }
}


resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.copy_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.start.arn
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.start.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.copy_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}