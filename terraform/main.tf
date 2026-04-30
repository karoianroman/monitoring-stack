terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Uncomment to store state in GCS (recommended for portfolio)
  # backend "gcs" {
  #   bucket = "YOUR_BUCKET_NAME"
  #   prefix = "monitoring-stack/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ── Static External IP ──────────────────────────────────────────────
resource "google_compute_address" "monitoring_ip" {
  name   = "${var.instance_name}-ip"
  region = var.region
}

# ── Firewall: allow Grafana, Prometheus, App ────────────────────────
resource "google_compute_firewall" "monitoring_ingress" {
  name    = "${var.instance_name}-ingress"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "3000", "9090", "8000"]
  }

  source_ranges = var.allowed_cidr_blocks
  target_tags   = ["monitoring"]

  description = "Allow SSH, Grafana (3000), Prometheus (9090), FastAPI (8000)"
}

# ── GCE VM ──────────────────────────────────────────────────────────
resource "google_compute_instance" "monitoring_vm" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["monitoring"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20 # GB
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.monitoring_ip.address
    }
  }

  metadata = {
    startup-script = file("${path.module}/startup.sh")
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  labels = {
    env     = "portfolio"
    purpose = "monitoring"
  }
}
