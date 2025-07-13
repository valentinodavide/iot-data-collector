# CI/CD Pipeline

## Overview
Automated deployment pipeline for the IoT Data Collector system using GitHub Actions.

## Workflow: Deploy to AWS EKS

**Trigger**: Push to `main` branch (backend or k8s changes)
**Target**: AWS EKS cluster (infrastructure must exist)

### Prerequisites
1. **Infrastructure deployed** via `./deploy.sh aws-infra`
2. **GitHub Secrets configured** (choose one approach):
   - **Option A (Simple)**: `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
   - **Option B (Secure)**: GitHub OIDC with IAM role (recommended for production)

### Pipeline Steps
1. **Build**: Docker image with timestamp tag
2. **Push**: Image to ECR repository  
3. **Deploy**: Application to existing EKS cluster
4. **Verify**: Deployment rollout status

### Manual Deployment
For infrastructure deployment, use:
```bash
./deploy.sh aws-infra
```

### Monitoring
- Check workflow runs in GitHub Actions tab
- Monitor deployment: `kubectl get pods -n iot-system`