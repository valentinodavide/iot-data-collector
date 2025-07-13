# 📊 Cloud Architect - Take-Home Assignment

## 📉 Objective

Design, containerize, and deploy a real-world microservice-based web application that integrates with AWS, demonstrating your ability to:

* Architect scalable, secure infrastructure
* Implement cloud-native services
* Automate deployments and observability
* Use NodeJS simple web application for testing
* Use available sources/services for testing.

During the interview, you'll present your solution, walk through your AWS deployment, and discuss design decisions.

---

## 🛠️ Functional Requirements

### Build an **IoT Data Collector System**:

#### Required Components:

1. **MQTT Broker Integration**

   * Local: Use **Mosquitto** broker in Docker
   * Cloud: Suggest equivalent solution and explain the suggestion

2. **Database Layer**

   * Local: MongoDb, PostgreSQL or SQLite
   * Cloud:Suggest equivalent solution and explain the suggestion

3. **Monitoring & Observability**

   * Metrics exposed via `/metrics` endpoint. (suggest and use available services that can export this data) 
   * Local & Cloud: Use **Prometheus** to scrape metrics
   * Integrate **Grafana** dashboards (e.g., MQTT msg rate, DB writes)

---

## 📆 Deliverables

1. **GitHub Repository** with:

   * Application code
   * Dockerfiles
   * Kubernetes manifests / Helm charts
   * Terraform or AWS CDK setup
   * GitHub Actions or similar CI/CD workflows
   * `README.md` or `/docs/assignment.pdf`:

     * Architecture diagrams
     * Step-by-step deployment guide
     * Security and monitoring explanation
     * Optional: AWS cost estimates

2. **Interview Demo**

   * Walkthrough of AWS setup (live or recorded)
   * Design reasoning and trade-offs
   * CI/CD, Secrets, and Monitoring setup

---

## 🪓 Technical Stack

| Component              | Local Version         | AWS Cloud Equivalent |
| ---------------------- | --------------------- | -------------------- |
| MQTT Broker            | Mosquitto (Docker)    | AWS IoT Core         |
| REST API Backend       | Node.js / Python / Go | Same container       |
| Database               | PostgreSQL / MongoDB (Docker)   | AWS RDS / DynamoDB   |
| Monitoring             | Prometheus + Grafana  | Prometheus + Grafana |
| Kubernetes             | minikube / kind       | AWS EKS              |
| Infrastructure as Code | -                     | Terraform or AWS CDK |
| CI/CD                  | GitHub Actions (optional)       | GitHub Actions (optional)      |

---

## 🚀 Notes

* Keep the codebase and infrastructure simple, modular, and focused.
* Ensure everything is reproducible using the provided instructions.
* Your AWS deployment should be available to demonstrate or share via screencast.

Good luck!
