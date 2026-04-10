# =============================================================================
# Pages (IAP-protected web service)
# =============================================================================

resource "google_project_service" "iap" {
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

# IAP OAuth Brand (consent screen). Only Internal type is supported by Terraform.
# Requires Google Workspace organization. For external accounts, create manually in GCP Console.
resource "google_iap_brand" "project_brand" {
  count             = var.iap_support_email != "" ? 1 : 0
  support_email     = var.iap_support_email
  application_title = "${var.prefix} Pages"

  depends_on = [google_project_service.iap]
}

# IAP OAuth Client for Cloud Run
resource "google_iap_client" "project_client" {
  count        = var.iap_support_email != "" ? 1 : 0
  display_name = "${var.prefix}-pages-client"
  brand        = google_iap_brand.project_brand[0].name
}

# Cloud Run Pages runtime SA
resource "google_service_account" "pages" {
  account_id   = "${local.sa_prefix}-pages-sa"
  display_name = "Cloud Run Pages Runtime"
}

resource "google_cloud_run_v2_service" "pages" {
  provider = google-beta

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

# Grant IAP service agent permission to invoke Cloud Run
resource "google_cloud_run_v2_service_iam_member" "iap_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pages.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-iap.iam.gserviceaccount.com"

  depends_on = [google_project_service.iap]
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
