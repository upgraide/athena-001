terraform {
  backend "gcs" {
    bucket  = "athena-finance-001-terraform-state"
    prefix  = "terraform/state"
  }
}