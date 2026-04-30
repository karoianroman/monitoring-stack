# 📊 Monitoring Stack — Terraform + Prometheus + Grafana + FastAPI

> **Portfolio project:** Production-grade observability stack provisioned with Terraform on GCP.

## 🏗️ Architecture

```
GCP (europe-west1)
└── GCE VM  ← provisioned by Terraform
    └── Docker Compose
        ├── fastapi-app   :8000  → /metrics (Prometheus format)
        ├── prometheus    :9090  → scrapes app + node-exporter
        ├── grafana       :3000  → pre-built dashboards
        └── node-exporter        → host CPU/RAM/disk metrics
```

## 🚀 Quick Start

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- GCP project with billing enabled
- `gcloud` CLI authenticated

### 1. Provision infrastructure

```bash
cd terraform/

# Edit variables if needed
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform plan
terraform apply
```

Terraform outputs the URLs:
```
grafana_url    = "http://X.X.X.X:3000"
prometheus_url = "http://X.X.X.X:9090"
fastapi_url    = "http://X.X.X.X:8000"
```

### 2. Access Grafana

- URL: `http://<VM_IP>:3000`
- Login: `admin` / `admin123`
- Dashboard **"FastAPI Application Monitoring"** is pre-loaded automatically

### 3. Generate traffic (demo)

```bash
# Install hey — HTTP load generator
brew install hey   # macOS
# or: go install github.com/rakyll/hey@latest

APP_URL="http://<VM_IP>:8000"

# Normal traffic
hey -n 500 -c 10 "$APP_URL/orders"

# POST requests (with ~10% errors)
hey -n 200 -c 5 -m POST "$APP_URL/orders"

# Slow endpoint
hey -n 50 -c 3 "$APP_URL/slow"
```

## 📈 Grafana Dashboard Panels

| Panel | Metric | Description |
|-------|--------|-------------|
| Request Rate | `rate(http_requests_total[1m])` | Requests per second |
| Error Rate | 5xx / total | Percentage of failed requests |
| P95 Latency | `histogram_quantile(0.95, ...)` | 95th percentile response time |
| Active Users | `app_active_users` | Custom gauge metric |
| Request Rate by Endpoint | per `handler` label | Which endpoints are hit |
| Status Codes | per `status` label | 200 vs 500 breakdown |
| DB Query Duration | `app_db_query_duration_seconds` | SELECT vs INSERT latency |
| Orders by Status | `app_orders_total` | created / failed / fetched |
| Host CPU | `node_cpu_seconds_total` | VM CPU usage |

## 🗂️ Project Structure

```
monitoring-stack/
├── terraform/
│   ├── main.tf          # GCE VM, Firewall, Static IP
│   ├── variables.tf     # Configurable parameters
│   ├── outputs.tf       # URLs after apply
│   └── startup.sh       # Installs Docker, starts stack
├── monitoring/
│   ├── docker-compose.yml
│   ├── prometheus/
│   │   └── prometheus.yml        # Scrape configs
│   └── grafana/
│       └── provisioning/
│           ├── datasources/      # Auto-configured Prometheus source
│           └── dashboards/       # Auto-loaded FastAPI dashboard
└── app/
    ├── main.py           # FastAPI with custom metrics
    ├── requirements.txt
    └── Dockerfile
```

## 🔧 Key Technologies

| Tool | Role |
|------|------|
| **Terraform** | Infrastructure as Code — provisions GCE VM, firewall, static IP |
| **Docker Compose** | Orchestrates all containers on the VM |
| **Prometheus** | Time-series metrics collection |
| **Grafana** | Visualization + auto-provisioned dashboards |
| **Node Exporter** | Host-level metrics (CPU, RAM, disk) |
| **FastAPI** | Demo app with `prometheus_fastapi_instrumentator` |

## 🧹 Teardown

```bash
cd terraform/
terraform destroy
```

All resources (VM, IP, firewall) are deleted. Docker volumes are destroyed with the VM.

## ☁️ Cloud Run Variant

To monitor an existing Cloud Run app instead of running FastAPI on the VM:

1. Add `/metrics` endpoint to your Cloud Run service
2. Make it publicly accessible (or use IAP)
3. In `prometheus.yml`, replace `app:8000` with your Cloud Run URL:

```yaml
scrape_configs:
  - job_name: "cloud-run-app"
    scheme: https
    metrics_path: "/metrics"
    static_configs:
      - targets: ["your-service-abc123-ew.a.run.app"]
```
