# Banking Service Cloud Run deployment
resource "google_cloud_run_service" "banking_service" {
  name     = "banking-service"
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.microservice.email
      
      containers {
        image = "gcr.io/${var.project_id}/banking-service:latest"
        
        ports {
          container_port = 8084
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "NODE_ENV"
          value = "production"
        }
        
        env {
          name  = "BANKING_SERVICE_PORT"
          value = "8084"
        }
        
        env {
          name  = "GOCARDLESS_ENV"
          value = "production"
        }
        
        env {
          name  = "APP_URL"
          value = "https://banking-service-${substr(sha256("${var.project_id}-banking"), 0, 8)}.europe-west3.run.app"
        }
        
        env {
          name  = "FRONTEND_URL"
          value = "http://localhost:3000"
        }
        
        env {
          name  = "ENABLE_ML_CATEGORIZATION"
          value = "true"
        }
        
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        
        env {
          name  = "VERTEX_AI_LOCATION"
          value = "us-central1"
        }
        
        resources {
          limits = {
            cpu    = "2"
            memory = "1Gi"
          }
        }
      }
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "100"
        "run.googleapis.com/cpu-throttling" = "false"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_service_account.microservice,
    google_project_service.vertex_ai
  ]
}

# Allow unauthenticated access to callback endpoint only
resource "google_cloud_run_service_iam_member" "banking_service_invoker" {
  service  = google_cloud_run_service.banking_service.name
  location = google_cloud_run_service.banking_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# GoCardless API credentials in Secret Manager
resource "google_secret_manager_secret" "gocardless_secret_id" {
  secret_id = "gocardless-secret-id"
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "gocardless_secret_key" {
  secret_id = "gocardless-secret-key"
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Grant access to secrets
resource "google_secret_manager_secret_iam_member" "banking_service_gocardless_id" {
  secret_id = google_secret_manager_secret.gocardless_secret_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.microservice.email}"
}

resource "google_secret_manager_secret_iam_member" "banking_service_gocardless_key" {
  secret_id = google_secret_manager_secret.gocardless_secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.microservice.email}"
}

# KMS key for banking data encryption
resource "google_kms_crypto_key" "banking_data_key" {
  name     = "banking-data-key"
  key_ring = google_kms_key_ring.security.id
  purpose  = "ENCRYPT_DECRYPT"

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Grant KMS access to service account
resource "google_kms_crypto_key_iam_member" "banking_service_encrypt" {
  crypto_key_id = google_kms_crypto_key.banking_data_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.microservice.email}"
}

# Firestore indexes for banking collections
resource "google_firestore_index" "bank_connections_user" {
  collection = "bank_connections"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "createdAt"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "bank_accounts_user" {
  collection = "bank_accounts"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "isActive"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "createdAt"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "transactions_user_date" {
  collection = "transactions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "transactions_account_date" {
  collection = "transactions"
  
  fields {
    field_path = "accountId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "DESCENDING"
  }
}

# Additional indexes for enhanced transaction sync
resource "google_firestore_index" "transactions_user_date_asc" {
  collection = "transactions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "ASCENDING"
  }
}

resource "google_firestore_index" "transactions_user_category" {
  collection = "transactions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "category"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "transactions_user_business" {
  collection = "transactions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "isBusinessExpense"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "date"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "subscriptions_user_status" {
  collection = "subscriptions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
}

resource "google_firestore_index" "subscriptions_user_merchant" {
  collection = "subscriptions"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "merchantName"
    order      = "ASCENDING"
  }
}

# Output the service URL
output "banking_service_url" {
  value = google_cloud_run_service.banking_service.status[0].url
}