terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {}
}

locals {
  # SA account_id is 6-30 chars, so truncate prefix for SA names
  sa_prefix       = substr(var.prefix, 0, min(20, length(var.prefix)))
  # api_config_id max 63 chars, suffix "-config-YYYYMMDDhhmmss" is 22 chars, so api_id max 41 chars
  api_id_full     = "${var.prefix}-${var.api_id}"
  api_id          = substr(local.api_id_full, 0, min(41, length(local.api_id_full)))
  repository_name = "${var.prefix}-${var.repository_name}"
  app_name        = "${var.prefix}-${var.app_image_name}"
  job_name        = "${var.prefix}-${var.job_image_name}"
  pages_name      = "${var.prefix}-${var.pages_image_name}"
  app_image       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/${var.app_image_name}:${var.app_image_tag}"
  job_image       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/${var.job_image_name}:${var.job_image_tag}"
  pages_image     = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/${var.pages_image_name}:latest"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# Enable required APIs
# =============================================================================

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudscheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# =============================================================================
# Artifact Registry
# =============================================================================

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = local.repository_name
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

# Cloud Build service account permissions
data "google_project" "project" {}

resource "google_project_iam_member" "cloudbuild_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [google_project_service.cloudbuild]
}

# =============================================================================
# Service Accounts
# =============================================================================

# Cloud Scheduler -> Cloud Run Jobs invoker
resource "google_service_account" "scheduler" {
  account_id   = "${local.sa_prefix}-sched-sa"
  display_name = "Cloud Scheduler Job Invoker"
}

# Cloud Run Service runtime SA (for Secret Manager access)
resource "google_service_account" "app" {
  account_id   = "${local.sa_prefix}-app-sa"
  display_name = "Cloud Run Service Runtime"
}

# Cloud Run Job runtime SA (for Secret Manager access)
resource "google_service_account" "job" {
  account_id   = "${local.sa_prefix}-job-sa"
  display_name = "Cloud Run Job Runtime"
}

# Client service account for API testing
resource "google_service_account" "api_client" {
  account_id   = "${local.sa_prefix}-client-sa"
  display_name = "API Client Service Account"
}

# =============================================================================
# Cloud Run Service (Hono API)
# =============================================================================

resource "google_cloud_run_v2_service" "app" {
  name     = local.app_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.app.email

    containers {
      image = local.app_image
      ports {
        container_port = 8080
      }

      dynamic "env" {
        for_each = toset(var.secret_names)
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.secrets[env.value].secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.app_access,
  ]
}

# =============================================================================
# Cloud Run Jobs
# =============================================================================

resource "google_cloud_run_v2_job" "job" {
  name     = local.job_name
  location = var.region

  template {
    template {
      service_account = google_service_account.job.email

      containers {
        image = local.job_image
        env {
          name  = "TASK_NAME"
          value = "example"
        }

        dynamic "env" {
          for_each = toset(var.secret_names)
          content {
            name = env.value
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.secrets[env.value].secret_id
                version = "latest"
              }
            }
          }
        }
      }
      max_retries = 1
      timeout     = "600s"
    }
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.job_access,
  ]
}

# Grant scheduler SA permission to invoke the job
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.job.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# =============================================================================
# Cloud Scheduler
# =============================================================================

resource "google_cloud_scheduler_job" "job_trigger" {
  name      = "${local.job_name}-trigger"
  region    = var.region
  schedule  = var.job_schedule
  time_zone = var.job_schedule_timezone

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.job.name}:run"

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [
    google_project_service.cloudscheduler,
    google_cloud_run_v2_job_iam_member.scheduler_invoker,
  ]
}

# =============================================================================
# API Client Key (for testing)
# =============================================================================

resource "google_service_account_key" "api_client_key" {
  service_account_id = google_service_account.api_client.name
}
