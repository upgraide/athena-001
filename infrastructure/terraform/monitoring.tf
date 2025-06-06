# Standalone Monitoring Configuration (no dependencies on services)

# Data source to get the project number
data "google_project" "project" {
  project_id = var.project_id
}

# Notification channel for alerts
resource "google_monitoring_notification_channel" "email" {
  display_name = "Athena Finance Alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  enabled = true
}

# General Cloud Run alerts (applies to all services)
resource "google_monitoring_alert_policy" "cloud_run_request_latency" {
  display_name = "High Request Latency"
  combiner     = "OR"
  
  conditions {
    display_name = "Request latency > 2s"
    
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\""
      duration        = "300s"  # 5 minutes
      comparison      = "COMPARISON_GT"
      threshold_value = 2000  # 2 seconds in milliseconds
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.service_name"]
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

resource "google_monitoring_alert_policy" "cloud_run_error_rate" {
  display_name = "High Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Error rate > 5%"
    
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND metric.label.response_code_class!=\"2xx\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.service_name"]
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Memory usage alerts
resource "google_monitoring_alert_policy" "memory_usage_high" {
  display_name = "High Memory Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Memory usage > 80%"
    
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.service_name"]
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Firestore alerts - commented out until metrics are available
# resource "google_monitoring_alert_policy" "firestore_read_latency" {
#   display_name = "Firestore High Read Latency"
#   combiner     = "OR"
#   
#   conditions {
#     display_name = "Read latency > 500ms"
#     
#     condition_threshold {
#       filter          = "metric.type=\"firestore.googleapis.com/document/read_latencies\" AND resource.type=\"firestore_instance\""
#       duration        = "300s"
#       comparison      = "COMPARISON_GT"
#       threshold_value = 500  # milliseconds
#       
#       aggregations {
#         alignment_period     = "60s"
#         per_series_aligner   = "ALIGN_PERCENTILE_95"
#         cross_series_reducer = "REDUCE_MEAN"
#       }
#     }
#   }
#   
#   notification_channels = [google_monitoring_notification_channel.email.id]
# }

# Log-based metric for authentication failures
resource "google_logging_metric" "auth_failures" {
  name   = "auth_failures"
  filter = "resource.type=\"cloud_run_revision\" AND severity=ERROR AND jsonPayload.event=\"LOGIN_FAILED\""
  description = "Count of authentication failures"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Alert for authentication failures
resource "google_monitoring_alert_policy" "auth_failure_spike" {
  display_name = "Authentication Failure Spike"
  combiner     = "OR"
  
  conditions {
    display_name = "Auth failures > 10 per minute"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/auth_failures\" AND resource.type=\"cloud_run_revision\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# Dashboard for monitoring
resource "google_monitoring_dashboard" "athena_finance" {
  dashboard_json = jsonencode({
    displayName = "Athena Finance Dashboard"
    gridLayout = {
      widgets = [
        {
          title = "Request Rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.service_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Request Latency (p95)"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_latencies\" AND resource.type=\"cloud_run_revision\""
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_PERCENTILE_95"
                    crossSeriesReducer = "REDUCE_MEAN"
                    groupByFields      = ["resource.service_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Error Rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND metric.label.response_code_class!=\"2xx\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                    groupByFields    = ["resource.service_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Memory Usage"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"run.googleapis.com/container/memory/utilizations\" AND resource.type=\"cloud_run_revision\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                    groupByFields    = ["resource.service_name"]
                  }
                }
              }
            }]
          }
        },
        {
          title = "Authentication Failures"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"logging.googleapis.com/user/auth_failures\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}

# Budget alert for cost monitoring
resource "google_billing_budget" "monthly_budget" {
  billing_account = var.billing_account_id
  display_name    = "Athena Finance Monthly Budget"
  
  budget_filter {
    projects               = ["projects/${data.google_project.project.number}"]
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }
  
  amount {
    specified_amount {
      currency_code = "EUR"
      units         = var.monthly_budget_amount
    }
  }
  
  threshold_rules {
    threshold_percent = 0.5
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.2
    spend_basis      = "CURRENT_SPEND"
  }
  
  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }
}

# Variables needed
variable "alert_email" {
  description = "Email address for monitoring alerts"
  default     = "joao@upgraide.ai"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID"
  default     = ""  # We'll need to get this
}

variable "monthly_budget_amount" {
  description = "Monthly budget in EUR"
  default     = "100"  # Default to 100 EUR, can be adjusted
}

# project_id variable is already defined in security.tf

# Outputs
output "dashboard_url" {
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.athena_finance.id}"
  description = "URL to the monitoring dashboard"
}