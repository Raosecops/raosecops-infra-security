terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

# --- Core VPC ---
resource "aws_vpc" "raosecops_vpc_core" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "raosecops-core-vpc"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "raosecops_igw" {
  vpc_id = aws_vpc.raosecops_vpc_core.id

  tags = {
    Name = "raosecops-internet-gateway"
  }
}

# --- Public Subnet ---
resource "aws_subnet" "raosecops_public_subnet" {
  vpc_id                  = aws_vpc.raosecops_vpc_core.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-central-1a"

  tags = {
    Name = "raosecops-public-subnet"
  }
}

# --- Public Route Table ---
resource "aws_route_table" "raosecops_public_rt" {
  vpc_id = aws_vpc.raosecops_vpc_core.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.raosecops_igw.id
  }

  tags = {
    Name = "raosecops-public-rt"
  }
}

resource "aws_route_table_association" "raosecops_public_assoc" {
  subnet_id      = aws_subnet.raosecops_public_subnet.id
  route_table_id = aws_route_table.raosecops_public_rt.id
}

# --- Security Group ---
resource "aws_security_group" "raosecops_web_sg" {
  name        = "raosecops-web-sg"
  description = "Security group for web traffic"
  vpc_id      = aws_vpc.raosecops_vpc_core.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "raosecops-web-sg"
  }
}

# --- S3 Bucket for Flow Logs ---
resource "aws_s3_bucket" "raosecops_flow_log_bucket" {
  bucket        = "raosecops-vpc-flow-logs-bucket-unique-12345"
  force_destroy = true

  tags = {
    Name = "raosecops-flow-logs-bucket"
  }
}

resource "aws_s3_bucket_ownership_controls" "raosecops_flow_log_ownership" {
  bucket = aws_s3_bucket.raosecops_flow_log_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "raosecops_flow_log_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.raosecops_flow_log_ownership]
  bucket     = aws_s3_bucket.raosecops_flow_log_bucket.id
  acl        = "private"
}

# --- VPC Flow Log ---
resource "aws_flow_log" "raosecops_vpc_flow_log" {
def    log_destination      = aws_s3_bucket.raosecops_flow_log_bucket.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.raosecops_vpc_core.id

  tags = {
    Name = "raosecops-vpc-flow-log"
  }
}
