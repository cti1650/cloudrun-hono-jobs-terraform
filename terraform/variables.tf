variable "prefix" {
  description = "Resource name prefix to avoid conflicts (e.g. myapp, dev)"
  type        = string
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast1"
}

variable "repository_name" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "cloud-run-apps"
}

# --- Cloud Run Service (API) ---

variable "app_image_name" {
  description = "Container image name for the API service"
  type        = string
  default     = "hono-api"
}

variable "app_image_tag" {
  description = "Container image tag for the API service"
  type        = string
  default     = "latest"
}

variable "api_id" {
  description = "API Gateway ID"
  type        = string
  default     = "hono-api-gateway"
}

variable "api_config_version" {
  description = "API Gateway config version suffix. Increment to force config update (e.g. v1, v2)"
  type        = string
  default     = "v1"
}

# --- Cloud Run Jobs ---

variable "job_image_name" {
  description = "Container image name for Cloud Run Jobs"
  type        = string
  default     = "cloud-run-job"
}

variable "job_image_tag" {
  description = "Container image tag for Cloud Run Jobs"
  type        = string
  default     = "latest"
}

variable "job_schedule" {
  description = "Cron schedule for the Cloud Run Job (Cloud Scheduler)"
  type        = string
  default     = "0 9 * * 1-5"
}

variable "job_schedule_timezone" {
  description = "Timezone for the Cloud Scheduler"
  type        = string
  default     = "Asia/Tokyo"
}

# --- Pages (IAP) ---

variable "pages_image_name" {
  description = "Container image name for the Pages service"
  type        = string
  default     = "pages"
}

variable "iap_members" {
  description = "Principals granted IAP-secured Web App User (e.g. ['user:foo@example.com', 'group:team@example.com'])"
  type        = list(string)
  default     = []
}

variable "iap_support_email" {
  description = "Support email for IAP OAuth brand (must be an owner of the project or a Google Workspace user)"
  type        = string
  default     = ""
}

# --- Secret Manager ---

variable "secret_names" {
  description = "List of secret env var names to create in Secret Manager"
  type        = list(string)
  default     = []
}

variable "secret_values" {
  description = "Map of secret env var names to their values (must match secret_names)"
  type        = map(string)
  default     = {}
  sensitive   = true
}
