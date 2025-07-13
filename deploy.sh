#!/bin/bash

# IoT Data Collector Deployment Script
# Usage: ./deploy.sh [local-up|local-down|aws-up|aws-down] [AWS_REGION]

set -e

COMMAND=${1:-local-up}
AWS_REGION=${2:-eu-west-1}

# Function to deploy AWS infrastructure
deploy_aws_infrastructure() {
  echo "Using AWS Region: $AWS_REGION"

  # Check prerequisites
  if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install terraform."
    exit 1
  fi
  
  if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install aws-cli."
    exit 1
  fi
  
  # Deploy Terraform infrastructure
  echo "🏗️  Deploying AWS infrastructure with Terraform..."
  cd terraform
  
  # Initialize Terraform if needed
  if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
  fi
  
  # Plan and apply infrastructure  
  echo "Applying Terraform infrastructure (requires confirmation)..."
  terraform apply
  
  cd ..
  
  # Configure kubectl for EKS
  echo "⚙️  Configuring kubectl for EKS..."
  aws eks update-kubeconfig --name iot-collector --region $AWS_REGION
  
  # Create namespace and service account
  kubectl apply -f k8s/namespace.yaml
  
  # Get outputs for service account
  cd terraform
  IOT_ROLE_ARN=$(terraform output -raw iot_role_arn)
  SECRET_ARN=$(terraform output -raw db_secret_arn)
  cd ..
  
  export IOT_ROLE_ARN="${IOT_ROLE_ARN}"
  export SERVICE_ACCOUNT="iot-backend"
  envsubst < k8s/service-account.yaml | kubectl apply -f -
  
  # Create db-secret for applications
  DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" --region "${AWS_REGION}" --query 'SecretString' --output text | jq -r '.password')
  kubectl create secret generic db-secret \
    --from-literal=password="${DB_PASSWORD}" \
    --namespace=iot-system \
    --dry-run=client -o yaml | kubectl apply -f -
}

case $COMMAND in
  "local-up")
    echo "🏠 Deploying local environment (minikube)..."
    ;;
  "local-down")
    echo "🛑 Stopping local environment..."
    ;;
  "aws-up")
    echo "☁️  Deploying AWS environment..."
    ;;
  "aws-infra")
    echo "🏗️  Deploying AWS infrastructure only..."
    ;;
  "aws-down")
    echo "🗑️  Destroying AWS environment..."
    ;;
  *)
    echo "❌ Usage: ./deploy.sh [local-up|local-down|aws-up|aws-infra|aws-down]"
    echo "  local-up    - Deploy to minikube"
    echo "  local-down  - Stop minikube environment"
    echo "  aws-up      - Deploy complete AWS environment"
    echo "  aws-infra   - Deploy AWS infrastructure only (for CI/CD demo)"
    echo "  aws-down    - Destroy AWS infrastructure"
    exit 1
    ;;
esac

if [ "$COMMAND" = "local-down" ]; then  
  # Stop port forwards
  echo "Stopping port forwards..."
  pkill -f "port-forward" 2>/dev/null || true
  
  # Delete namespace (removes all resources)
  echo "Deleting iot-system namespace..."
  kubectl delete namespace iot-system --ignore-not-found=true
  
  # Stop minikube
  echo "Stopping minikube..."
  minikube stop
  
  echo "✅ Local environment stopped!"
  
elif [ "$COMMAND" = "local-up" ]; then
  # Build container with timestamp for consistency
  echo "🔨 Building container..."
  TIMESTAMP=$(date +%s)
  docker build -t iot-backend:${TIMESTAMP} ./backend
  docker tag iot-backend:${TIMESTAMP} iot-backend:latest
    
  # Check if minikube is running
  if ! minikube status &> /dev/null; then
    echo "🚀 Starting minikube..."
    minikube start
  fi
  
  # Load image into minikube
  echo "📦 Loading image into minikube..."
  minikube image load iot-backend:${TIMESTAMP}
  
  # Deploy with environment variables
  export BACKEND_IMAGE="iot-backend:${TIMESTAMP}"
  export SERVICE_ACCOUNT="default"
  
  kubectl apply -f k8s/namespace.yaml
  kubectl apply -f k8s/secrets.yaml
  kubectl apply -f k8s/configmap-local.yaml
  kubectl apply -f k8s/postgres-deployment.yaml
  kubectl apply -f k8s/mqtt-deployment.yaml
  envsubst < k8s/backend-deployment.yaml | kubectl apply -f -
  kubectl apply -f k8s/prometheus-config.yaml
  kubectl apply -f k8s/prometheus-deployment.yaml
  kubectl apply -f k8s/grafana-config.yaml
  kubectl apply -f k8s/grafana-deployment.yaml
  
  echo "✅ Minikube deployment complete!"
  echo "📊 Check status:"
  echo "  kubectl get pods -n iot-system"
  echo "  kubectl get svc -n iot-system"
  echo "🔗 Port forward services:"
  echo "  kubectl port-forward svc/backend-service 3000:3000 -n iot-system &"
  echo "  kubectl port-forward svc/grafana-service 3001:3000 -n iot-system &"
  echo "  kubectl port-forward svc/prometheus-service 9090:9090 -n iot-system &"
  echo "  kubectl port-forward svc/mqtt-service 1883:1883 -n iot-system &"
  echo "  kubectl port-forward svc/postgres-service 5432:5432 -n iot-system &"
  
elif [ "$COMMAND" = "aws-down" ]; then    
  echo "Using AWS Region: $AWS_REGION"

  # Stop port forwards
  echo "Stopping port forwards..."
  pkill -f "port-forward" 2>/dev/null || true
  
  # Configure kubectl for EKS (if cluster exists)
  echo "Configuring kubectl for EKS..."
  aws eks update-kubeconfig --name iot-collector --region $AWS_REGION 2>/dev/null || echo "EKS cluster not found or already deleted"
  
  # Delete Kubernetes resources (if cluster exists)
  echo "Deleting Kubernetes resources..."
  kubectl delete namespace iot-system --ignore-not-found=true 2>/dev/null || echo "Kubernetes resources not found or cluster unavailable"
  
  # Clean up ECR repository (delete all images)
  echo "Cleaning up ECR repository..."
  ECR_IMAGES=$(aws ecr list-images --repository-name iot-backend --region $AWS_REGION --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
  if [ "$ECR_IMAGES" != "[]" ] && [ "$ECR_IMAGES" != "" ]; then
    echo "Deleting ECR images..."
    aws ecr batch-delete-image --repository-name iot-backend --region $AWS_REGION --image-ids "$ECR_IMAGES" 2>/dev/null || echo "ECR images already deleted or repository not found"
  else
    echo "No ECR images to delete"
  fi
  
  # Destroy Terraform infrastructure
  echo "Destroying Terraform infrastructure..."
  cd terraform
  terraform destroy
  cd ..
  
  echo "✅ AWS environment destroyed!"

elif [ "$COMMAND" = "aws-up" ]; then  
  # Deploy infrastructure first
  deploy_aws_infrastructure
  
  # Check kubectl prerequisite for application deployment
  if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
  fi
  
  # Get outputs for application deployment
  cd terraform
  ECR_URL=$(terraform output -raw ecr_repository_url)
  RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
  IOT_ENDPOINT=$(terraform output -raw iot_endpoint)
  IOT_ROLE_ARN=$(terraform output -raw iot_role_arn)
  SECRET_ARN=$(terraform output -raw db_secret_arn)
  
  if [ -z "$ECR_URL" ] || [ -z "$RDS_ENDPOINT" ] || [ -z "$IOT_ENDPOINT" ] || [ -z "$IOT_ROLE_ARN" ]; then
    echo "❌ Failed to get Terraform outputs. Infrastructure deployment may have failed."
    exit 1
  fi
  
  cd ..
  
  # Build container with appropriate platform
  echo "🔨 Building container for AWS..."
  TIMESTAMP=$(date +%s)
  docker build --platform linux/amd64 -t iot-backend ./backend
  
  # Login to ECR
  echo "🔐 Logging into ECR..."
  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
  
  # Tag and push to ECR with timestamp
  echo "📤 Pushing container to ECR with tag: $TIMESTAMP..."
  docker tag iot-backend:latest ${ECR_URL}:latest
  docker tag iot-backend:latest ${ECR_URL}:${TIMESTAMP}
  docker push ${ECR_URL}:latest
  docker push ${ECR_URL}:${TIMESTAMP}
  
  # Deploy to EKS
  echo "🚀 Deploying application to EKS..."
  
  # Deploy with environment variables (use timestamp tag to force update)
  export BACKEND_IMAGE="${ECR_URL}:${TIMESTAMP}"
  export RDS_ENDPOINT="${RDS_ENDPOINT}"
  export IOT_ENDPOINT="${IOT_ENDPOINT}"
  export IOT_ROLE_ARN="${IOT_ROLE_ARN}"
  export SECRET_ARN="${SECRET_ARN}"
  export AWS_REGION="${AWS_REGION}"
  export SERVICE_ACCOUNT="iot-backend"
  
  # Apply application manifests
  envsubst < k8s/configmap-aws.yaml | kubectl apply -f -
  envsubst < k8s/backend-deployment.yaml | kubectl apply -f -
  
  kubectl apply -f k8s/prometheus-config.yaml
  kubectl apply -f k8s/prometheus-deployment.yaml
  kubectl apply -f k8s/grafana-config.yaml
  kubectl apply -f k8s/grafana-deployment.yaml
  
  echo "✅ AWS deployment complete!"
  echo "📊 Check status:"
  echo "  kubectl get pods -n iot-system"
  echo "  kubectl get svc -n iot-system"
  echo "🔗 Port forward services:"
  echo "  kubectl port-forward svc/backend-service 3000:3000 -n iot-system &"
  echo "  kubectl port-forward svc/grafana-service 3001:3000 -n iot-system &"
  echo "  kubectl port-forward svc/prometheus-service 9090:9090 -n iot-system &"
  echo "🌐 Test IoT Core: AWS Console → IoT Core → Test → MQTT test client"
  echo "  Topic: iot/data"
  
elif [ "$COMMAND" = "aws-infra" ]; then  
  deploy_aws_infrastructure
  
  echo "✅ AWS infrastructure deployment complete!"
  echo "🚀 Application deployment will be handled by CI/CD pipeline"
  echo "📊 Push changes to trigger automated deployment"

fi