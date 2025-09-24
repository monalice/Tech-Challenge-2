# Tech Challenge Bovespa - Terraform Infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Tech-Challenge-Bovespa"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.project_owner
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "tech-challenge-bovespa"
}

variable "project_owner" {
  description = "Project owner"
  type        = string
  default     = "tech-challenge"
}

# Locals
locals {
  bucket_name = "${var.project_name}-${var.environment}-${random_id.bucket_suffix.hex}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.project_owner
  }
}

# Random ID for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for Data Lake
resource "aws_s3_bucket" "data_lake" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name = "Data Lake Bucket"
    Type = "Storage"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "data_lake_versioning" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_encryption" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "data_lake_pab" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.bucket_name}-athena-results"

  tags = merge(local.common_tags, {
    Name = "Athena Results Bucket"
    Type = "Storage"
  })
}

resource "aws_s3_bucket_public_access_block" "athena_results_pab" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Glue scripts
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${local.bucket_name}-glue-scripts"

  tags = merge(local.common_tags, {
    Name = "Glue Scripts Bucket"
    Type = "Storage"
  })
}

# IAM Role for Glue Service
resource "aws_iam_role" "glue_service_role" {
  name = "${var.project_name}-glue-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Glue Service Role"
    Type = "IAM"
  })
}

# IAM Policy for Glue Service
resource "aws_iam_policy" "glue_service_policy" {
  name        = "${var.project_name}-glue-service-policy"
  description = "Policy for Glue service to access S3 and Data Catalog"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_lake.arn,
          "${aws_s3_bucket.data_lake.arn}/raw/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/refined/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:CreateDatabase",
          "glue:GetTable",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetPartition",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:*:catalog",
          "arn:aws:glue:${var.aws_region}:*:database/tech_challenge_bovespa",
          "arn:aws:glue:${var.aws_region}:*:table/tech_challenge_bovespa/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:log-group:/aws-glue/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_policy_attachment" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = aws_iam_policy.glue_service_policy.arn
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_role_policy" {
  role       = aws_iam_role.glue_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Lambda Execution Role"
    Type = "IAM"
  })
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "${var.project_name}-lambda-execution-policy"
  description = "Policy for Lambda to start Glue jobs and access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJob"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:*:job/${var.project_name}-etl"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectMetadata"
        ]
        Resource = [
          "${aws_s3_bucket.data_lake.arn}/raw/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:*:*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_execution_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

# Glue Database
resource "aws_glue_catalog_database" "bovespa_database" {
  name = "tech_challenge_bovespa"

  description = "Database for Bovespa stock market data"

  tags = merge(local.common_tags, {
    Name = "Bovespa Database"
    Type = "Data Catalog"
  })
}

# Upload Glue script to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts.bucket
  key    = "glue_etl_job.py"
  source = "../fase3-glue/glue_etl_job.py"
  etag   = filemd5("../fase3-glue/glue_etl_job.py")

  tags = merge(local.common_tags, {
    Name = "Glue ETL Script"
    Type = "Script"
  })
}

# Glue Job
resource "aws_glue_job" "bovespa_etl" {
  name     = "${var.project_name}-etl"
  role_arn = aws_iam_role.glue_service_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--enable-metrics"                    = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-language"                      = "python"
    "--additional-python-modules"         = "boto3"
  }

  glue_version      = "4.0"
  worker_type      = "G.1X"
  number_of_workers = 2
  timeout          = 60
  max_retries      = 2

  tags = merge(local.common_tags, {
    Name = "Bovespa ETL Job"
    Type = "Data Processing"
  })

  depends_on = [aws_s3_object.glue_script]
}

# Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../fase2-lambda/lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "bovespa_trigger" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-trigger"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      GLUE_JOB_NAME = aws_glue_job.bovespa_etl.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "Bovespa Trigger Function"
    Type = "Compute"
  })

  depends_on = [aws_iam_role_policy_attachment.lambda_execution_policy_attachment]
}

# Lambda permission for S3 to invoke
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bovespa_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake.arn
}

# S3 bucket notification
resource "aws_s3_bucket_notification" "s3_lambda_trigger" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.bovespa_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
    filter_suffix       = ".parquet"
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# Athena Workgroup
resource "aws_athena_workgroup" "bovespa_workgroup" {
  name = "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics         = true
    bytes_scanned_cutoff_per_query     = 1073741824 # 1GB

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "Bovespa Athena Workgroup"
    Type = "Analytics"
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.bovespa_trigger.function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "Lambda Logs"
    Type = "Monitoring"
  })
}

# CloudWatch Log Group for Glue
resource "aws_cloudwatch_log_group" "glue_logs" {
  name              = "/aws-glue/jobs/logs-v2"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "Glue Logs"
    Type = "Monitoring"
  })
}

# Outputs
output "data_lake_bucket_name" {
  description = "Name of the S3 bucket for data lake"
  value       = aws_s3_bucket.data_lake.bucket
}

output "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "glue_scripts_bucket_name" {
  description = "Name of the S3 bucket for Glue scripts"
  value       = aws_s3_bucket.glue_scripts.bucket
}

output "glue_job_name" {
  description = "Name of the Glue ETL job"
  value       = aws_glue_job.bovespa_etl.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.bovespa_trigger.function_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.bovespa_workgroup.name
}

output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.bovespa_database.name
}
