# IoT Data Collector System

## 🧩 Overview

This project implements a complete IoT ingestion pipeline with both local development and AWS cloud deployment capabilities:

### Local Stack (minikube):
- MQTT broker (Mosquitto)
- Node.js backend API with Prometheus metrics
- PostgreSQL database
- Prometheus + Grafana for monitoring

### AWS Cloud Stack:
- AWS IoT Core (MQTT)
- Amazon EKS (Kubernetes)
- Amazon RDS PostgreSQL
- Prometheus + Grafana on EKS

### 📁 Structure
- `backend/`: Node.js microservice
- `mqtt/`: Mosquitto broker config
- `db/`: DB init schema
- `monitoring/`: Prometheus + Grafana configuration
- `k8s/`: Kubernetes manifests
- `terraform/`: AWS infrastructure as code
- `deploy.sh`: Unified deployment script
- `.github/workflows/`: CI/CD pipeline


## 📦 Architecture

### Local Development Flow
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   MQTT Client   │───▶│  Mosquitto      │───▶│   Node.js       │
│   (Publisher)   │    │   Broker        │    │   Backend       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    Grafana      │◀───│   Prometheus    │◀───│   PostgreSQL    │
│   Dashboard     │    │   (Metrics)     │    │   Database      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### AWS Cloud Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   IoT Device    │───▶│  AWS IoT Core   │───▶│   EKS Cluster   │
│                 │    │                 │    │   (Backend)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Grafana       │◀───│   Prometheus    │◀───│   Amazon RDS    │
│   (EKS)         │    │   (EKS)         │    │   PostgreSQL    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Data Flow

**Local Environment:**
1. MQTT client publishes to Mosquitto broker on topic `iot/data`
2. Backend connects as MQTT client and receives messages
3. Backend stores messages in PostgreSQL and increments metrics
4. Prometheus scrapes metrics from backend `/metrics` endpoint
5. Grafana visualizes metrics in real-time dashboards

**AWS Environment:**
1. AWS Console MQTT test client publishes to AWS IoT Core on topic `iot/data`
2. Backend connects to IoT Core as MQTT client and receives messages
3. Backend stores messages in RDS PostgreSQL and increments metrics
4. Prometheus scrapes metrics from backend `/metrics` endpoint
5. Grafana visualizes metrics in real-time dashboards


## 📊 Monitoring & Observability

### Metrics Collection
- **Backend Metrics**: `mqtt_messages_total`, `db_inserts_total` counters
- **Prometheus**: 15-second scrape interval from `/metrics` endpoint
- **Health Checks**: `/health` endpoint for Kubernetes probes

### Visualization
- **Grafana Dashboards**: Real-time MQTT message rates and DB insert metrics
- **Auto-provisioned**: Datasources and dashboards configured via code
- **Alerting Ready**: Metrics available for threshold-based alerts


## 🚀 Local Environment

### Prerequisites
- Docker installed
- minikube installed
- kubectl installed
- Mosquitto client tools (optional): `brew install mosquitto`
- Git for cloning the repository

### Deploy Local Environment
```bash
# Deploy to minikube
./deploy.sh local-up
```

### Stop Local Environment
```bash
# Stop everything and minikube
./deploy.sh local-down
```

### 🧪 Testing Local Environment

#### Check Deployment Status
```bash
kubectl get pods -n iot-system
kubectl get svc -n iot-system
```

#### Port Forward Services
```bash
kubectl port-forward svc/backend-service 3000:3000 -n iot-system &
kubectl port-forward svc/grafana-service 3001:3000 -n iot-system &
kubectl port-forward svc/prometheus-service 9090:9090 -n iot-system &
kubectl port-forward svc/mqtt-service 1883:1883 -n iot-system &
kubectl port-forward svc/postgres-service 5432:5432 -n iot-system &
```

#### 📡 Publish Test Messages
```bash
# Single message
mosquitto_pub -h localhost -t iot/data -m "temperature:23"

# Generate test data
for i in {1..10}; do mosquitto_pub -h localhost -t iot/data -m "sensor:$i"; sleep 1; done
```

#### 🔍 Check Results
```bash
# View backend metrics
curl http://localhost:3000/metrics

# Expected counters:
# - mqtt_messages_total
# - db_inserts_total

# Access dashboards
open http://localhost:3001  # Grafana (admin/admin)
open http://localhost:9090  # Prometheus
```

### 🛠️ Services

| Service     | URL / Port         | Description |
|-------------|--------------------|--------------|
| **Backend API** | http://localhost:3000 | Node.js REST API |
| - Health Check | `GET /health` | Service health status |
| - Metrics | `GET /metrics` | Prometheus metrics |
| **Grafana** | http://localhost:3001 | Dashboards (admin/admin) |
| **Prometheus** | http://localhost:9090 | Metrics & monitoring |
| **MQTT Broker** | tcp://localhost:1883 | Message broker |
| **PostgreSQL** | localhost:5432 | Database |


## 🚀 Cloud Deployment (AWS)

### Prerequisites
- AWS CLI configured
- Terraform installed
- kubectl installed
- Docker installed

### Deploy Complete AWS Environment
```bash
# Deploy to default region (eu-west-1)
./deploy.sh aws-up

# Deploy to specific region
./deploy.sh aws-up us-east-1
```

### Destroy AWS Environment
```bash
# Remove all AWS resources (default region)
./deploy.sh aws-down

# Remove from specific region
./deploy.sh aws-down us-east-1
```

### Test AWS Deployment
```bash
# Check deployment status
kubectl get pods -n iot-system
kubectl get svc -n iot-system

# Port forward services
kubectl port-forward svc/backend-service 3000:3000 -n iot-system &
kubectl port-forward svc/prometheus-service 9090:9090 -n iot-system &
kubectl port-forward svc/grafana-service 3001:3000 -n iot-system &

# Test AWS IoT Core using AWS Console:
# 1. Go to AWS IoT Console → Test → MQTT test client
# 2. Subscribe to topic: iot/data
# 3. Publish test message to topic: iot/data
# 4. Check backend metrics for message count

# Check metrics and dashboards
curl http://localhost:3000/metrics
open http://localhost:9090  # Prometheus
open http://localhost:3001  # Grafana (admin/admin)
```


## 💰 Cost Estimation

### Production IoT System Assumptions (Real-World Scenario)
- **IoT Devices**: 10,000 connected devices
- **Message Rate**: 50M messages/month (avg 1 msg/device every 8.6 minutes)
- **Data Retention**: 1 year of historical data
- **Geographic Distribution**: Single region (eu-west-1)

### AWS Monthly Costs (eu-west-1) - Production Configuration

This AWS Pricing Calculator contains the main cost voices for the production environment for this project: https://calculator.aws/#/estimate?id=51a277dea7094dfcb89b36bb2ec72b9bbafdb14b

**Total conservative rounding: ~1.000 USD/month**

### Cost Optimization Options
- **Reserved Instances**: Save 30-40% on EC2 costs
- **Spot Instances**: Save up to 70% for non-critical workloads
- **S3 Archival**: Move old IoT data to S3 Glacier (reduce RDS costs)
- **Auto-scaling**: Scale down during low-traffic periods


## 🔒 Security Implementation

### Local Environment Security
- **Basic Authentication**: Grafana (admin/admin) - development only
- **No Encryption**: MQTT and database connections (development only)
- **Container Isolation**: Docker network segmentation
- **Local Secrets**: Hardcoded credentials (development only)

### Production/AWS Security (Implemented)

#### Identity & Access Management
- **IRSA (IAM Roles for Service Accounts)**: EKS pods use IAM roles instead of access keys
- **Least Privilege**: Service accounts have minimal required permissions
- **AWS Secrets Manager**: Database passwords auto-generated

#### Data Protection
- **Encryption at Rest**: 
  - RDS encrypted with AWS-managed keys
  - ECR images encrypted with AWS-managed keys
- **Encryption in Transit**: 
  - RDS connections use SSL/TLS
  - AWS IoT Core uses WebSocket Secure (WSS)

#### Network Security
- **VPC Architecture**: 
  - Private subnets for RDS (no internet access)
  - Public subnets for NAT gateways only
  - EKS nodes in private subnets
- **Security Groups**: 
  - RDS: Only port 5432 from EKS subnets
  - EKS: Managed by AWS with least privilege

#### Infrastructure Security
- **EKS Cluster**: 
  - Control plane logging enabled
  - Kubernetes RBAC enabled (default)
- **Container Security**: 
  - ECR vulnerability scanning enabled
  - Application metrics via Prometheus

#### IoT Security
- **AWS IoT Core**: WebSocket with SigV4 authentication
- **Device Authentication**: Uses AWS credentials (production would use certificates)
- **Topic-based Authorization**: IAM policies control topic access
- **Message Encryption**: All IoT messages encrypted in transit


## 🏭 Components Choices

| Component | Local | AWS Cloud | Justification |
|-----------|-------|-----------|---------------|
| **MQTT Broker** | Mosquitto (Docker) | AWS IoT Core | Cloud: Managed service with built-in security, device management, and scalability. Local: Containerized for development |
| **Database** | PostgreSQL | Amazon RDS | Managed service with automated backups, high availability, and maintenance |
| **Container Platform** | minikube | Amazon EKS | Kubernetes provides production-grade orchestration and scaling |
| **Monitoring** | Prometheus + Grafana | Same (on EKS) | Industry standard, cloud-native monitoring stack |
| **Infrastructure** | Manual | Terraform | Infrastructure as Code for reproducible, version-controlled deployments |
| **CI/CD** | Manual | GitHub Actions | Automated building and deployment pipeline |

---
