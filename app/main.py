from fastapi import FastAPI, HTTPException
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Histogram, Gauge
import random
import time
import uvicorn

app = FastAPI(title="FastAPI Monitored App", version="1.0.0")

# Custom metrics
orders_total = Counter(
    "app_orders_total",
    "Total number of orders",
    ["status"]
)

active_users = Gauge(
    "app_active_users",
    "Number of currently active users"
)

db_query_duration = Histogram(
    "app_db_query_duration_seconds",
    "Database query duration",
    ["operation"],
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.0]
)

# Auto-instrument all HTTP endpoints
Instrumentator().instrument(app).expose(app)


@app.get("/")
def root():
    return {"status": "ok", "service": "FastAPI Monitored App"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/orders")
def get_orders():
    """Simulate order listing with DB query."""
    latency = random.uniform(0.01, 0.3)
    with db_query_duration.labels(operation="SELECT").time():
        time.sleep(latency)

    count = random.randint(10, 100)
    orders_total.labels(status="fetched").inc()
    return {"orders": count, "latency_ms": round(latency * 1000, 2)}


@app.post("/orders")
def create_order():
    """Simulate order creation."""
    latency = random.uniform(0.05, 0.5)
    with db_query_duration.labels(operation="INSERT").time():
        time.sleep(latency)

    # Randomly fail 10% of requests to show error metrics
    if random.random() < 0.1:
        orders_total.labels(status="failed").inc()
        raise HTTPException(status_code=500, detail="DB connection failed")

    orders_total.labels(status="created").inc()
    return {"order_id": random.randint(1000, 9999), "status": "created"}


@app.get("/users/active")
def get_active_users():
    """Simulate active user count."""
    count = random.randint(5, 50)
    active_users.set(count)
    return {"active_users": count}


@app.get("/slow")
def slow_endpoint():
    """Intentionally slow endpoint to demonstrate latency metrics."""
    time.sleep(random.uniform(1.0, 2.5))
    return {"message": "slow response"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
