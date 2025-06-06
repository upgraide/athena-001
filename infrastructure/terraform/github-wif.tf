# GitHub Workload Identity Federation Configuration
# This enables keyless authentication from GitHub Actions to Google Cloud

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo'"
  type        = string
  default     = "upgraide/athena-001"
}

# Workload Identity Pool for GitHub
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
  description              = "Pool for GitHub Actions authentication"
  disabled                  = false
  project                   = var.project_id
}

# Workload Identity Provider for GitHub
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"
  description                        = "OIDC provider for GitHub Actions"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  
  attribute_condition = "assertion.repository == '${var.github_repository}'"
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service Account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions CI/CD"
}

# Grant necessary permissions to the GitHub Actions service account
resource "google_project_iam_member" "github_actions_permissions" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudbuild.builds.editor",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
    "roles/storage.objectAdmin",
    "roles/datastore.importExportAdmin",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/cloudbuild.builds.builder",
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Allow GitHub to impersonate the service account
resource "google_service_account_iam_member" "github_actions_workload_identity" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Service Account for GitHub Actions Production (separate for production deployments)
resource "google_service_account" "github_actions_prod" {
  account_id   = "github-actions-prod-sa"
  display_name = "GitHub Actions Production Service Account"
  description  = "Service account for GitHub Actions production deployments"
}

# Grant production permissions (more restrictive)
resource "google_project_iam_member" "github_actions_prod_permissions" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.reader",
    "roles/iam.serviceAccountUser",
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions_prod.email}"
}

# Allow GitHub to impersonate the production service account
resource "google_service_account_iam_member" "github_actions_prod_workload_identity" {
  service_account_id = google_service_account.github_actions_prod.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Output the configuration needed for GitHub Actions
output "github_wif_provider" {
  description = "Workload Identity Provider for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_service_account" {
  description = "Service Account email for GitHub Actions"
  value       = google_service_account.github_actions.email
}

output "github_service_account_prod" {
  description = "Service Account email for GitHub Actions production"
  value       = google_service_account.github_actions_prod.email
}

# Create a local file with GitHub secrets configuration
resource "local_file" "github_secrets" {
  filename = "${path.module}/../../.github-secrets"
  content  = <<-EOT
    # GitHub Secrets Configuration
    # Add these to your GitHub repository secrets
    
    WIF_PROVIDER=${google_iam_workload_identity_pool_provider.github.name}
    WIF_SERVICE_ACCOUNT=${google_service_account.github_actions.email}
    WIF_SERVICE_ACCOUNT_PROD=${google_service_account.github_actions_prod.email}
    GCP_PROJECT_ID=${var.project_id}
  EOT
  
  depends_on = [
    google_iam_workload_identity_pool_provider.github,
    google_service_account.github_actions,
    google_service_account.github_actions_prod
  ]
}