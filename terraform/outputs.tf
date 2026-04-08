output "cloud_run_url" {
  description = "Cloud Run service URL (internal)"
  value       = google_cloud_run_v2_service.app.uri
}

output "api_gateway_url" {
  description = "API Gateway URL (public endpoint)"
  value       = "https://${google_api_gateway_gateway.gateway.default_hostname}"
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = google_api_gateway_api.api.api_id
}

output "api_client_service_account_email" {
  description = "API Client Service Account email"
  value       = google_service_account.api_client.email
}

output "api_client_service_account_key" {
  description = "API Client Service Account key (base64 encoded)"
  value       = google_service_account_key.api_client_key.private_key
  sensitive   = true
}

output "api_managed_service" {
  description = "API Gateway managed service (used as audience for ID tokens)"
  value       = google_api_gateway_api.api.managed_service
}

output "job_name" {
  description = "Cloud Run Job name"
  value       = google_cloud_run_v2_job.job.name
}

output "scheduler_job_name" {
  description = "Cloud Scheduler job name"
  value       = google_cloud_scheduler_job.job_trigger.name
}
