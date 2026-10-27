# VPC Core
resource "aws_vpc" "raosecops_vpc_core" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "raosecops-vpc-core"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Hardening Default VPC Security Group
resource "aws_default_security_group" "raosecops_default_sg" {
  vpc_id = aws_vpc.raosecops_vpc_core.id

  tags = {
    Name        = "raosecops-default-sg-restricted"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "raosecops_igw" {
  vpc_id = aws_vpc.raosecops_vpc_core.id

  tags = {
    Name        = "raosecops-igw"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Public Subnet
resource "aws_subnet" "raosecops_subnet_public" {
  vpc_id                  = aws_vpc.raosecops_vpc_core.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name        = "raosecops-subnet-public"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Route Table & Association
resource "aws_route_table" "raosecops_rt_public" {
  vpc_id = aws_vpc.raosecops_vpc_core.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.raosecops_igw.id
  }

  tags = {
    Name        = "raosecops-rt-public"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_route_table_association" "raosecops_rta" {
  subnet_id      = aws_subnet.raosecops_subnet_public.id
  route_table_id = aws_route_table.raosecops_rt_public.id
}

# Security Group
resource "aws_security_group" "raosecops_sg_secure" {
  name        = "raosecops-sg-secure"
  description = "Hardened security group with restricted access"
  vpc_id      = aws_vpc.raosecops_vpc_core.id

  ingress {
    description = "Allow SSH only from trusted admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.50/32"]
  }

  egress {
    description = "Allow outbound HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "raosecops-sg-secure"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# KMS Key with Defined Policy (CKV2_AWS_64)
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "raosecops_kms" {
  description             = "KMS Key for raosecops infrastructure encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "raosecops-kms-key"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Log Group & Flow Logs
resource "aws_cloudwatch_log_group" "raosecops_flow_log_group" {
  name              = "/aws/vpc/raosecops-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.raosecops_kms.arn

  tags = {
    Name        = "raosecops-flow-log-group"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role" "raosecops_flow_log_role" {
  name = "raosecops-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "raosecops_flow_log_policy" {
  name = "raosecops-vpc-flow-log-policy"
  role = aws_iam_role.raosecops_flow_log_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.raosecops_flow_log_group.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "raosecops_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.raosecops_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.raosecops_flow_log_group.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.raosecops_vpc_core.id
}

# IAM Role & Instance Profile for EC2
resource "aws_iam_role" "raosecops_bastion_role" {
  name = "raosecops-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "raosecops_bastion_profile" {
  name = "raosecops-bastion-profile"
  role = aws_iam_role.raosecops_bastion_role.name
}

# Hardened Bastion EC2 Instance
resource "aws_instance" "raosecops_bastion" {
  ami                  = "ami-0c7217cdde317cfec"
  instance_type        = "t2.micro"
  subnet_id            = aws_subnet.raosecops_subnet_public.id
  security_groups      = [aws_security_group.raosecops_sg_secure.id]
  iam_instance_profile = aws_iam_instance_profile.raosecops_bastion_profile.name

  monitoring    = true
  ebs_optimized = true

  root_block_device {
    encrypted  = true
    kms_key_id = aws_kms_key.raosecops_kms.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "raosecops-bastion-instance"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# Hardened S3 Analytics Bucket
#checkov:skip=CKV_AWS_144: "Cross-region replication not required for dev bucket"
#checkov:skip=CKV2_AWS_62: "Event notifications not required for dev bucket"
resource "aws_s3_bucket" "raosecops_data_bucket" {
  bucket = "raosecops-secure-analytics-bucket-9912"

  tags = {
    Name        = "raosecops-data-bucket"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "raosecops_s3_versioning" {
  bucket = aws_s3_bucket.raosecops_data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raosecops_s3_encryption" {
  bucket = aws_s3_bucket.raosecops_data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.raosecops_kms.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raosecops_s3_block" {
  bucket                  = aws_s3_bucket.raosecops_data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raosecops_s3_lifecycle" {
  bucket = aws_s3_bucket.raosecops_data_bucket.id

  rule {
    id     = "archive-and-abort-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Hardened S3 Logs Bucket
#checkov:skip=CKV_AWS_144: "Cross-region replication not required for logs bucket"
#checkov:skip=CKV2_AWS_62: "Event notifications not required for logs bucket"
resource "aws_s3_bucket" "raosecops_logs_bucket" {
  bucket = "raosecops-secure-logs-bucket-9912"

  tags = {
    Name        = "raosecops-logs-bucket"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "raosecops_logs_versioning" {
  bucket = aws_s3_bucket.raosecops_logs_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raosecops_logs_encryption" {
  bucket = aws_s3_bucket.raosecops_logs_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.raosecops_kms.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raosecops_logs_block" {
  bucket                  = aws_s3_bucket.raosecops_logs_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raosecops_logs_lifecycle" {
  bucket = aws_s3_bucket.raosecops_logs_bucket.id

  rule {
    id     = "transition-and-abort-logs"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_logging" "raosecops_s3_logging" {
  bucket        = aws_s3_bucket.raosecops_data_bucket.id
  target_bucket = aws_s3_bucket.raosecops_logs_bucket.id
  target_prefix = "log/"
}

resource "aws_flow_log" "raosecops_vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
