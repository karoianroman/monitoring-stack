#!/bin/bash
set -euo pipefail

LOG="/var/log/startup.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== Startup script started: $(date) ==="

# ── 1. System update ──────────────────────────────────────────────
apt-get update -y
apt-get install -y ca-certificates curl

# ── 2. Install Docker ─────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# ── 3. Create directory structure ─────────────────────────────────
APP_DIR="/opt/monitoring-stack"
mkdir -p "$APP_DIR"/{app,monitoring/prometheus,monitoring/grafana/provisioning/{datasources,dashboards}}

# ── 4. Write app files ────────────────────────────────────────────
cat > "$APP_DIR/app/requirements.txt" << 'PYEOF'
fastapi==0.115.5
uvicorn==0.32.1
prometheus-fastapi-instrumentator==7.0.0
prometheus-client==0.21.1
PYEOF

cat > "$APP_DIR/app/Dockerfile" << 'DOCKEREOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py .
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
DOCKEREOF

cat > "$APP_DIR/app/main.py" << 'PYEOF'
from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Histogram, Gauge
import random, time

app = FastAPI(title="FastAPI Monitored App", version="1.0.0")

orders_total = Counter("app_orders_total", "Total orders", ["status"])
active_users = Gauge("app_active_users", "Active users")
db_query_duration = Histogram(
    "app_db_query_duration_seconds", "DB query duration",
    ["operation"], buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.0]
)

Instrumentator().instrument(app).expose(app)

@app.get("/")
def root():
    return {"status": "ok", "service": "FastAPI Monitored App"}

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/orders")
def get_orders():
    latency = random.uniform(0.01, 0.3)
    with db_query_duration.labels(operation="SELECT").time():
        time.sleep(latency)
    orders_total.labels(status="fetched").inc()
    return {"orders": random.randint(10, 100)}

@app.post("/orders")
def create_order():
    with db_query_duration.labels(operation="INSERT").time():
        time.sleep(random.uniform(0.05, 0.5))
    if random.random() < 0.1:
        orders_total.labels(status="failed").inc()
        raise HTTPException(status_code=500, detail="DB error")
    orders_total.labels(status="created").inc()
    return {"order_id": random.randint(1000, 9999), "status": "created"}

@app.get("/users/active")
def get_active_users():
    count = random.randint(5, 50)
    active_users.set(count)
    return {"active_users": count}

@app.get("/slow")
def slow_endpoint():
    time.sleep(random.uniform(1.0, 2.5))
    return {"message": "slow response"}
PYEOF

# ── 5. Write monitoring configs ───────────────────────────────────
cat > "$APP_DIR/monitoring/prometheus/prometheus.yml" << 'PROMEOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "fastapi-app"
    metrics_path: "/metrics"
    scrape_interval: 10s
    static_configs:
      - targets: ["app:8000"]

  - job_name: "node-exporter"
    scrape_interval: 30s
    static_configs:
      - targets: ["node-exporter:9100"]
PROMEOF

cat > "$APP_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml" << 'GRAFEOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"
GRAFEOF

cat > "$APP_DIR/monitoring/grafana/provisioning/dashboards/dashboard.yml" << 'GRAFEOF'
apiVersion: 1
providers:
  - name: "default"
    orgId: 1
    folder: "FastAPI Monitoring"
    type: file
    options:
      path: /etc/grafana/provisioning/dashboards
GRAFEOF

# ── 6. Write docker-compose.yml ───────────────────────────────────
cat > "$APP_DIR/monitoring/docker-compose.yml" << 'COMPOSEEOF'
services:
  app:
    build:
      context: ../app
      dockerfile: Dockerfile
    container_name: fastapi-app
    ports:
      - "8000:8000"
    restart: unless-stopped
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:v2.55.1
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--storage.tsdb.retention.time=7d"
      - "--web.enable-lifecycle"
    restart: unless-stopped
    depends_on:
      - app
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:11.3.1
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USERNAME}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana_data:/var/lib/grafana
    restart: unless-stopped
    depends_on:
      - prometheus
    networks:
      - monitoring

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter
    command:
      - "--path.rootfs=/host"
    pid: host
    volumes:
      - "/:/host:ro,rslave"
    restart: unless-stopped
    networks:
      - monitoring

volumes:
  prometheus_data:
  grafana_data:

networks:
  monitoring:
    driver: bridge
COMPOSEEOF

# ── 7. Read secrets from Secret Manager ──────────────────────────
echo "Reading secrets from Secret Manager..."

TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

read_secret() {
  curl -s \
    -H "Authorization: Bearer $TOKEN" \
    "https://secretmanager.googleapis.com/v1/projects/repo-490410/secrets/$1/versions/latest:access" \
    | python3 -c 'import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())'
}

GRAFANA_ADMIN_USERNAME=$(read_secret "grafana-user")
GRAFANA_ADMIN_PASSWORD=$(read_secret "grafana-password")

# ── 8. Start the stack ────────────────────────────────────────────
cd "$APP_DIR/monitoring"
GRAFANA_ADMIN_USERNAME="$GRAFANA_ADMIN_USERNAME" \
GRAFANA_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
docker compose up -d --build

echo "=== Stack started: $(date) ==="
EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
echo "Grafana:    http://$EXTERNAL_IP:3000  (admin / <secret>)"
echo "Prometheus: http://$EXTERNAL_IP:9090"
echo "FastAPI:    http://$EXTERNAL_IP:8000"