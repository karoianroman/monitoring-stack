variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "repo-490410"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "europe-west1-b"
}

variable "instance_name" {
  description = "Name of the monitoring VM"
  type        = string
  default     = "monitoring-stack"
}

variable "machine_type" {
  description = "GCE machine type"
  type        = string
  default     = "e2-small" # 2 vCPU, 2 GB RAM — достатньо для демо
}

variable "service_account_email" {
  description = "Service account for the VM"
  type        = string
  default     = "github-actions-sa@repo-490410.iam.gserviceaccount.com"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access monitoring ports"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Для демо; в prod обмеж своїм IP
}
