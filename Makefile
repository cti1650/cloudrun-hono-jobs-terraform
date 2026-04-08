.PHONY: setup setup-backend setup-deploy-sa init init-local deploy deploy-app deploy-job apply-registry build-app build-job plan apply destroy local run-job export-key get-token test-health test-hello test-hello-post test-users test-webhook outputs

# Load .env file
-include .env
export

# Defaults
PREFIX ?= myapp
REGION ?= asia-northeast1
REPOSITORY_NAME ?= cloud-run-apps
APP_IMAGE_NAME ?= hono-api
APP_IMAGE_TAG ?= latest
JOB_IMAGE_NAME ?= cloud-run-job
JOB_IMAGE_TAG ?= latest

# Prefixed names (must match Terraform locals)
PREFIXED_REPOSITORY = $(PREFIX)-$(REPOSITORY_NAME)
PREFIXED_APP_NAME = $(PREFIX)-$(APP_IMAGE_NAME)
PREFIXED_JOB_NAME = $(PREFIX)-$(JOB_IMAGE_NAME)

# Terraform variables
TF_VAR_prefix = $(PREFIX)
TF_VAR_project_id = $(PROJECT_ID)
TF_VAR_region = $(REGION)
TF_VAR_repository_name = $(REPOSITORY_NAME)
TF_VAR_app_image_name = $(APP_IMAGE_NAME)
TF_VAR_app_image_tag = $(APP_IMAGE_TAG)
TF_VAR_job_image_name = $(JOB_IMAGE_NAME)
TF_VAR_job_image_tag = $(JOB_IMAGE_TAG)

# Terraform backend
TF_BUCKET = $(PREFIX)-tfstate
TF_BACKEND_CONFIG = -backend-config="bucket=$(TF_BUCKET)" -backend-config="prefix=terraform/state"

# Artifact Registry image paths
APP_IMAGE_PATH = $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(PREFIXED_REPOSITORY)/$(APP_IMAGE_NAME):$(APP_IMAGE_TAG)
JOB_IMAGE_PATH = $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(PREFIXED_REPOSITORY)/$(JOB_IMAGE_NAME):$(JOB_IMAGE_TAG)

# =============================================================================
# Setup
# =============================================================================

setup:
	cp -n .env.example .env || true
	cp -n .envrc.example .envrc || true
	@echo "Please edit .env with your project settings"

setup-backend:
	@echo "Creating GCS bucket for Terraform state..."
	gcloud storage buckets create gs://$(TF_BUCKET) \
		--project=$(PROJECT_ID) \
		--location=$(REGION) \
		--uniform-bucket-level-access \
		--public-access-prevention
	@echo "Bucket gs://$(TF_BUCKET) created."

DEPLOY_SA_NAME = $(shell echo "$(PREFIX)" | cut -c1-20)-deploy-sa
DEPLOY_SA_EMAIL = $(DEPLOY_SA_NAME)@$(PROJECT_ID).iam.gserviceaccount.com

setup-deploy-sa:
	@echo "Creating deploy service account..."
	gcloud iam service-accounts create $(DEPLOY_SA_NAME) \
		--project=$(PROJECT_ID) \
		--display-name="Deploy Service Account"
	@for role in roles/editor roles/storage.admin roles/secretmanager.admin roles/iam.serviceAccountKeyAdmin; do \
		echo "Granting $$role..."; \
		gcloud projects add-iam-policy-binding $(PROJECT_ID) \
			--member="serviceAccount:$(DEPLOY_SA_EMAIL)" \
			--role="$$role" \
			--quiet; \
	done
	@echo "Creating service account key..."
	gcloud iam service-accounts keys create deploy-sa-key.json \
		--iam-account=$(DEPLOY_SA_EMAIL) \
		--project=$(PROJECT_ID)
	@echo ""
	@echo "Done! Set the contents of deploy-sa-key.json as GitHub Actions secret GCP_SA_KEY"
	@echo "Then delete the local key file: rm deploy-sa-key.json"

init:
	@rm -f terraform/local_override.tf
	cd terraform && terraform init $(TF_BACKEND_CONFIG)

init-local:
	@printf 'terraform {\n  backend "local" {}\n}\n' > terraform/local_override.tf
	cd terraform && terraform init -reconfigure
	@echo "Using local state (terraform/terraform.tfstate)"

# =============================================================================
# Deploy
# =============================================================================

deploy: apply-registry build-app build-job apply export-key
	@echo "Deployment complete!"

deploy-app: apply-registry build-app apply export-key
	@echo "App deployment complete!"

deploy-job: apply-registry build-job apply
	@echo "Job deployment complete!"

apply-registry:
	cd terraform && terraform apply \
		-target=google_project_service.artifactregistry \
		-target=google_project_service.cloudbuild \
		-target=google_artifact_registry_repository.app \
		-target=google_project_iam_member.cloudbuild_artifact_writer

build-app:
	cd app && gcloud builds submit --project=$(PROJECT_ID) --tag $(APP_IMAGE_PATH)

build-job:
	cd jobs && gcloud builds submit --project=$(PROJECT_ID) --tag $(JOB_IMAGE_PATH)

plan:
	cd terraform && terraform plan

apply:
	cd terraform && terraform apply

destroy:
	cd terraform && terraform destroy

# =============================================================================
# Local development
# =============================================================================

local:
	cd app && npm run dev

local-install:
	cd app && npm install
	cd jobs && npm install

# =============================================================================
# Job operations
# =============================================================================

run-job:
	gcloud beta run jobs execute $(PREFIXED_JOB_NAME) --project=$(PROJECT_ID) --region=$(REGION) --wait

# =============================================================================
# API testing
# =============================================================================

export-key:
	@echo "Exporting service account key..."
	@cd terraform && terraform output -raw api_client_service_account_key | base64 -d > ../credentials.json
	@echo "Service account key exported to credentials.json"

get-token:
	@AUDIENCE=$$(cd terraform && terraform output -raw api_managed_service); \
	gcloud auth print-identity-token --impersonate-service-account=$$(cd terraform && terraform output -raw api_client_service_account_email) --audiences=$$AUDIENCE

test-health:
	@echo "Testing health endpoint..."
	@GATEWAY_URL=$$(cd terraform && terraform output -raw api_gateway_url); \
	curl -s "$$GATEWAY_URL/health" | jq

test-hello:
	@echo "Testing hello endpoint (requires IAM authentication)..."
	@GATEWAY_URL=$$(cd terraform && terraform output -raw api_gateway_url); \
	AUDIENCE=$$(cd terraform && terraform output -raw api_managed_service); \
	SA_EMAIL=$$(cd terraform && terraform output -raw api_client_service_account_email); \
	TOKEN=$$(gcloud auth print-identity-token --impersonate-service-account=$$SA_EMAIL --audiences=$$AUDIENCE); \
	curl -s -H "Authorization: Bearer $$TOKEN" "$$GATEWAY_URL/api/hello" | jq

test-hello-post:
	@echo "Testing hello POST endpoint (requires IAM authentication)..."
	@GATEWAY_URL=$$(cd terraform && terraform output -raw api_gateway_url); \
	AUDIENCE=$$(cd terraform && terraform output -raw api_managed_service); \
	SA_EMAIL=$$(cd terraform && terraform output -raw api_client_service_account_email); \
	TOKEN=$$(gcloud auth print-identity-token --impersonate-service-account=$$SA_EMAIL --audiences=$$AUDIENCE); \
	curl -s -X POST -H "Authorization: Bearer $$TOKEN" -H "Content-Type: application/json" \
		-d '{"name": "World"}' "$$GATEWAY_URL/api/hello" | jq

test-users:
	@echo "Testing users endpoint (requires IAM authentication)..."
	@GATEWAY_URL=$$(cd terraform && terraform output -raw api_gateway_url); \
	AUDIENCE=$$(cd terraform && terraform output -raw api_managed_service); \
	SA_EMAIL=$$(cd terraform && terraform output -raw api_client_service_account_email); \
	TOKEN=$$(gcloud auth print-identity-token --impersonate-service-account=$$SA_EMAIL --audiences=$$AUDIENCE); \
	curl -s -H "Authorization: Bearer $$TOKEN" "$$GATEWAY_URL/api/users" | jq

test-webhook:
	@echo "Testing webhook endpoint (requires API key)..."
	@GATEWAY_URL=$$(cd terraform && terraform output -raw api_gateway_url); \
	curl -s -X POST -H "x-api-key: $(WEBHOOK_API_KEY)" -H "Content-Type: application/json" \
		-d '{"event": "test"}' "$$GATEWAY_URL/webhook/example" | jq

outputs:
	cd terraform && terraform output
