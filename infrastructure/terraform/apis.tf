# Enable required Google Cloud APIs
resource "google_project_service" "vertex_ai" {
  project = var.project_id
  service = "aiplatform.googleapis.com"
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Add this as a dependency to the banking service
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "firestore.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}