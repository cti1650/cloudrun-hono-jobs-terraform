# =============================================================================
# Pages (IAP-protected web service)
# =============================================================================

resource "google_project_service" "iap" {
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# Cloud Run Pages runtime SA
resource "google_service_account" "pages" {
  account_id   = "${local.sa_prefix}-pages-sa"
  display_name = "Cloud Run Pages Runtime"
}

resource "google_cloud_run_v2_service" "pages" {
  name     = local.pages_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.pages.email

    containers {
      image = local.pages_image
      ports {
        container_port = 8080
      }
    }
  }

  iap_enabled = true

  depends_on = [
    google_project_service.run,
    google_project_service.iap,
  ]
}

# Grant IAP-secured Web App User to specified principals
# var.iap_members example: ["user:foo@example.com", "group:team@example.com"]
resource "google_iap_web_cloud_run_service_iam_member" "pages_users" {
  for_each               = toset(var.iap_members)
  project                = var.project_id
  location               = var.region
  cloud_run_service_name = google_cloud_run_v2_service.pages.name
  role                   = "roles/iap.httpsResourceAccessor"
  member                 = each.value
}

# --- Outputs ---

output "pages_url" {
  description = "Pages Cloud Run URL (IAP protected)"
  value       = google_cloud_run_v2_service.pages.uri
}
