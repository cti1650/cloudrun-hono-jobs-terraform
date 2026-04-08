# =============================================================================
# API Gateway
# =============================================================================

resource "google_project_service" "apigateway" {
  service            = "apigateway.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicemanagement" {
  service            = "servicemanagement.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicecontrol" {
  service            = "servicecontrol.googleapis.com"
  disable_on_destroy = false
}

# API Gateway -> Cloud Run Service invoker
resource "google_service_account" "api_gateway" {
  account_id   = "${local.sa_prefix}-gw-sa"
  display_name = "API Gateway Invoker"
}

resource "google_cloud_run_v2_service_iam_member" "api_gateway_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_api_gateway_api" "api" {
  provider = google-beta
  api_id   = local.api_id

  depends_on = [
    google_project_service.apigateway,
    google_project_service.servicemanagement,
    google_project_service.servicecontrol,
  ]
}

resource "google_api_gateway_api_config" "api_config" {
  provider      = google-beta
  api           = google_api_gateway_api.api.api_id
  api_config_id = "${local.api_id}-config-${var.api_config_version}"

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tpl", {
        cloud_run_url       = google_cloud_run_v2_service.app.uri
        api_managed_service = google_api_gateway_api.api.managed_service
      }))
    }
  }

  gateway_config {
    backend_config {
      google_service_account = google_service_account.api_gateway.email
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_cloud_run_v2_service_iam_member.api_gateway_invoker]
}

resource "google_api_gateway_gateway" "gateway" {
  provider   = google-beta
  api_config = google_api_gateway_api_config.api_config.id
  gateway_id = "${local.api_id}-gw"
  region     = var.region

  depends_on = [google_api_gateway_api_config.api_config]
}

# --- Outputs ---

output "api_gateway_url" {
  description = "API Gateway URL (public endpoint)"
  value       = "https://${google_api_gateway_gateway.gateway.default_hostname}"
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = google_api_gateway_api.api.api_id
}

output "api_managed_service" {
  description = "API Gateway managed service (used as audience for ID tokens)"
  value       = google_api_gateway_api.api.managed_service
}
