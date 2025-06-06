# Cloud Build default bucket permissions
# This grants the GitHub Actions service account access to the Cloud Build bucket

data "google_storage_bucket" "cloudbuild_default" {
  name = "${var.project_id}_cloudbuild"
}

resource "google_storage_bucket_iam_member" "github_actions_cloudbuild_access" {
  bucket = data.google_storage_bucket.cloudbuild_default.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_actions.email}"
  
  depends_on = [google_service_account.github_actions]
}

# Also ensure Cloud Build service account can use our service accounts
resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Grant Cloud Build permission to deploy to Cloud Run
resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Allow Cloud Build to act as the microservice service account
resource "google_service_account_iam_member" "cloudbuild_act_as_microservice" {
  service_account_id = google_service_account.microservice.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}