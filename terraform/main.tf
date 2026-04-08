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
  app_image       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/${var.app_image_name}:${var.app_image_tag}"
  job_image       = "${var.region}-docker.pkg.dev/${var.project_id}/${local.repository_name}/${var.job_image_name}:${var.job_image_tag}"
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

resource "google_project_service" "cloudscheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
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

# API Gateway -> Cloud Run Service invoker
resource "google_service_account" "api_gateway" {
  account_id   = "${local.sa_prefix}-gw-sa"
  display_name = "API Gateway Invoker"
}

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

resource "google_cloud_run_v2_service_iam_member" "api_gateway_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.api_gateway.email}"
}

# =============================================================================
# API Gateway
# =============================================================================

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
# Secret Manager
# =============================================================================

resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(var.secret_names)
  secret_id = "${var.prefix}-${each.key}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "secrets" {
  for_each    = toset(var.secret_names)
  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = var.secret_values[each.key]
}

# Grant Cloud Run Service SA access to secrets
resource "google_secret_manager_secret_iam_member" "app_access" {
  for_each  = toset(var.secret_names)
  secret_id = google_secret_manager_secret.secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# Grant Cloud Run Job SA access to secrets
resource "google_secret_manager_secret_iam_member" "job_access" {
  for_each  = toset(var.secret_names)
  secret_id = google_secret_manager_secret.secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.job.email}"
}

# =============================================================================
# API Client Key (for testing)
# =============================================================================

resource "google_service_account_key" "api_client_key" {
  service_account_id = google_service_account.api_client.name
}
