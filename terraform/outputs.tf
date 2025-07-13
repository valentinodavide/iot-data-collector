output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.iot_backend.repository_url
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.iot_db.endpoint
}

output "iot_endpoint" {
  description = "AWS IoT Core endpoint"
  value       = data.aws_iot_endpoint.iot_endpoint.endpoint_address
}

output "iot_role_arn" {
  description = "IoT service account role ARN"
  value       = module.iot_irsa.iam_role_arn
}

output "db_secret_arn" {
  description = "Database secret ARN in Secrets Manager"
  value       = aws_secretsmanager_secret.db_password.arn
}

data "aws_iot_endpoint" "iot_endpoint" {
  endpoint_type = "iot:Data-ATS"
}