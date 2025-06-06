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
}

provider "google" {
  project = var.project_id
  region  = var.region
  user_project_override = true
  billing_project = var.project_id
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  user_project_override = true
  billing_project = var.project_id
}

variable "project_id" {
  description = "GCP Project ID"
  default     = "athena-finance-001"
}

variable "region" {
  description = "EU region for GDPR compliance"
  default     = "europe-west3" # Frankfurt
}

# KMS Key Ring for encryption
resource "google_kms_key_ring" "security" {
  name     = "athena-security-keyring"
  location = "europe"
}

# Data encryption key with auto-rotation
resource "google_kms_crypto_key" "data_encryption" {
  name     = "data-encryption-key"
  key_ring = google_kms_key_ring.security.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = "2592000s" # 30 days
  
  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }
  
  lifecycle {
    prevent_destroy = true
  }
}

# Application encryption key
resource "google_kms_crypto_key" "app_encryption" {
  name     = "app-encryption-key"
  key_ring = google_kms_key_ring.security.id
  
  purpose          = "ENCRYPT_DECRYPT"
  rotation_period  = "7776000s" # 90 days
  
  lifecycle {
    prevent_destroy = true
  }
}

# Secret Manager for credentials
resource "google_secret_manager_secret" "api_keys" {
  secret_id = "api-keys"
  
  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
      replicas {
        location = "europe-west4"
      }
    }
  }
  
  labels = {
    environment = "production"
    type        = "api-keys"
  }
}

resource "google_secret_manager_secret" "database_credentials" {
  secret_id = "database-credentials"
  
  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
    }
  }
}

# JWT secrets for authentication
resource "google_secret_manager_secret" "jwt_access_secret" {
  secret_id = "jwt-access-secret"
  
  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
    }
  }
  
  labels = {
    environment = "production"
    type        = "authentication"
  }
}

resource "google_secret_manager_secret" "jwt_refresh_secret" {
  secret_id = "jwt-refresh-secret"
  
  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
    }
  }
  
  labels = {
    environment = "production"
    type        = "authentication"
  }
}

# Secure VPC Network
resource "google_compute_network" "secure_vpc" {
  name                    = "athena-secure-vpc"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
}

# Private subnet
resource "google_compute_subnetwork" "private_subnet" {
  name          = "athena-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.secure_vpc.id
  
  # Enable private Google access
  private_ip_google_access = true
  
  # Secondary range for pods (if needed)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "athena-router"
  region  = var.region
  network = google_compute_network.secure_vpc.id
}

# Cloud NAT for outbound traffic
resource "google_compute_router_nat" "nat" {
  name                               = "athena-nat"
  router                            = google_compute_router.router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# VPC Connector subnet (must be /28)
resource "google_compute_subnetwork" "connector_subnet" {
  name          = "athena-connector-subnet"
  ip_cidr_range = "10.0.2.0/28"
  region        = var.region
  network       = google_compute_network.secure_vpc.id
  
  # Enable private Google access
  private_ip_google_access = true
}

# VPC Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "athena-vpc-connector"
  region        = var.region
  
  subnet {
    name = google_compute_subnetwork.connector_subnet.name
  }
  
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3
}

# Firestore with encryption
resource "google_firestore_database" "secure_db" {
  name        = "(default)"
  location_id = "eur3" # EU multi-region
  type        = "FIRESTORE_NATIVE"
  
  concurrency_mode                = "OPTIMISTIC"
  app_engine_integration_mode     = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # Enable deletion protection
  deletion_policy = "DELETE_PROTECTION_ENABLED"
}

# Service Accounts with minimal permissions
resource "google_service_account" "api_gateway" {
  account_id   = "api-gateway-sa"
  display_name = "API Gateway Service Account"
  description  = "Service account for API Gateway with minimal permissions"
}

resource "google_service_account" "microservice" {
  account_id   = "microservice-sa"
  display_name = "Microservice Service Account"
  description  = "Service account for microservices with minimal permissions"
}

# IAM roles for service accounts
# Additional IAM for authentication service
resource "google_project_iam_member" "microservice_jwt_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.microservice.email}"
  
  # This allows microservices to access JWT secrets
  condition {
    title       = "JWT Secrets Access"
    description = "Allow access to JWT secrets only"
    expression  = "resource.name.startsWith('projects/${var.project_id}/secrets/jwt-')"
  }
}

resource "google_project_iam_member" "api_gateway_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_project_iam_member" "api_gateway_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.api_gateway.email}"
}

resource "google_project_iam_member" "microservice_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.microservice.email}"
}

resource "google_project_iam_member" "microservice_kms" {
  project = var.project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.microservice.email}"
}

resource "google_project_iam_member" "microservice_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.microservice.email}"
}

# Cloud Armor security policy
resource "google_compute_security_policy" "security_policy" {
  name = "athena-security-policy"

  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Rate limit rule"
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
}

# Outputs for other modules
output "kms_key_id" {
  value       = google_kms_crypto_key.data_encryption.id
  description = "KMS key ID for data encryption"
}

output "vpc_connector_name" {
  value       = google_vpc_access_connector.connector.name
  description = "VPC connector name for Cloud Run"
}

output "service_account_emails" {
  value = {
    api_gateway  = google_service_account.api_gateway.email
    microservice = google_service_account.microservice.email
  }
  description = "Service account emails"
}