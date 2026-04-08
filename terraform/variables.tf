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
