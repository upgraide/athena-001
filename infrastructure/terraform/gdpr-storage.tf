# GDPR Export Storage Bucket
resource "google_storage_bucket" "gdpr_exports" {
  name     = "${var.project_id}-gdpr-exports"
  location = var.region

  lifecycle_rule {
    condition {
      age = 30  # Delete exports after 30 days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = false
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_key.id
  }

  uniform_bucket_level_access = true

  labels = {
    purpose     = "gdpr-exports"
    compliance  = "gdpr"
    environment = "production"
  }
}

# IAM binding for service account access
resource "google_storage_bucket_iam_member" "gdpr_bucket_writer" {
  bucket = google_storage_bucket.gdpr_exports.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create a signed URL service account for temporary access
resource "google_service_account" "gdpr_url_signer" {
  account_id   = "gdpr-url-signer"
  display_name = "GDPR Export URL Signer"
  description  = "Service account for signing GDPR export URLs"
}

resource "google_service_account_key" "gdpr_url_signer_key" {
  service_account_id = google_service_account.gdpr_url_signer.name
}

resource "google_storage_bucket_iam_member" "gdpr_url_signer" {
  bucket = google_storage_bucket.gdpr_exports.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.gdpr_url_signer.email}"
}