terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  eks_managed_node_groups = {
    main = {
      desired_size   = 3
      max_size       = 10
      min_size       = 3
      instance_types = ["m6i.large"]
      disk_size      = 50

      labels = {
        Environment = "production"
        Workload    = "iot-processing"
      }
    }
  }

  # Cluster logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false
}

# Secrets Manager for DB password
resource "random_id" "secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.cluster_name}-db-password-${random_id.secret_suffix.hex}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "iotuser"
    password = random_password.db_password.result
  })
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# RDS PostgreSQL - Production Configuration
resource "aws_db_instance" "iot_db" {
  identifier = "${var.cluster_name}-db"

  engine         = "postgres"
  engine_version = "15.7"
  instance_class = "db.r6g.large" # Production sizing for IoT workloads

  allocated_storage     = 100
  max_allocated_storage = 1000 # Auto-scaling storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # High Availability
  multi_az                = true
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  db_name  = "iotdb"
  username = "iotuser"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  # SSL Configuration
  ca_cert_identifier = "rds-ca-rsa2048-g1"

  skip_final_snapshot = true
  # For production: enable final snapshot and deletion protection
  # final_snapshot_identifier = "${var.cluster_name}-db-final-snapshot"
  # deletion_protection = true

  tags = {
    Name        = "${var.cluster_name}-database"
    Environment = "production"
  }
}

# ECR Repository
resource "aws_ecr_repository" "iot_backend" {
  name = "iot-backend"

  image_scanning_configuration {
    scan_on_push = true
  }
  
  encryption_configuration {
    encryption_type = "AES256"  # AWS-managed encryption
  }
}

# IoT Core
resource "aws_iot_thing" "iot_device" {
  name = "${var.cluster_name}-device"
}

resource "aws_iot_policy" "iot_policy" {
  name = "${var.cluster_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for EKS nodes to access IoT Core
resource "aws_iam_policy" "iot_access" {
  name = "${var.cluster_name}-iot-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Subscribe",
          "iot:Receive",
          "iot:Publish"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

# IRSA (IAM Roles for Service Accounts) for IoT Core access
module "iot_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${var.cluster_name}-iot-role"

  role_policy_arns = {
    iot_policy = aws_iam_policy.iot_access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["iot-system:iot-backend"]
    }
  }
}

# IAM role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.cluster_name}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# For demo: Use AWS Console MQTT test client to publish to 'iot/data' topic

# Security Groups
resource "aws_security_group" "rds" {
  name_prefix = "${var.cluster_name}-rds"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets
}
