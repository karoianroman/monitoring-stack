output "vm_external_ip" {
  description = "External IP of the monitoring VM"
  value       = google_compute_address.monitoring_ip.address
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${google_compute_address.monitoring_ip.address}:3000"
}

output "prometheus_url" {
  description = "Prometheus UI URL"
  value       = "http://${google_compute_address.monitoring_ip.address}:9090"
}

output "fastapi_url" {
  description = "FastAPI app URL"
  value       = "http://${google_compute_address.monitoring_ip.address}:8000"
}

output "ssh_command" {
  description = "SSH into the VM"
  value       = "gcloud compute ssh ${google_compute_instance.monitoring_vm.name} --zone=${var.zone} --project=${var.project_id}"
}
