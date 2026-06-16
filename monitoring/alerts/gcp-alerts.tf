# =============================================================================
# GCP ALERT POLICIES — Cloud Monitoring
# =============================================================================
# Alert Policies para monitorar a saúde do GKE, aplicações e infraestrutura.
# Todos os alertas notificam via email e podem ser integrados ao PagerDuty.
# =============================================================================

variable "gcp_project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "gke_cluster_name" {
  description = "Nome do cluster GKE"
  type        = string
}

variable "notification_email" {
  description = "E-mail para notificações de alerta"
  type        = string
  default     = "devops-team@empresa.com"
}

variable "app_name" {
  description = "Nome da aplicação"
  type        = string
  default     = "devops-platform"
}

# =============================================================================
# NOTIFICATION CHANNEL — E-mail
# =============================================================================

resource "google_monitoring_notification_channel" "email" {
  display_name = "DevOps Team Email"
  type         = "email"
  project      = var.gcp_project_id

  labels = {
    email_address = var.notification_email
  }

  force_delete = false
}

# =============================================================================
# ALERT: CPU alta nos nodes GKE (>80%)
# =============================================================================

resource "google_monitoring_alert_policy" "gke_high_cpu" {
  display_name = "[${var.app_name}] GKE — CPU alta nos nodes (>80%)"
  project      = var.gcp_project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "CPU dos nodes GKE está acima de 80%. Verifique workloads intensivos ou considere escalar o node pool."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "CPU > 80% por 5 minutos"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\"",
        "resource.type=\"k8s_node\"",
        "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0.80
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.node_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close = "1800s"  # Fecha automaticamente após 30 min sem disparar
  }
}

# =============================================================================
# ALERT: Memória alta nos nodes GKE (>85%)
# =============================================================================

resource "google_monitoring_alert_policy" "gke_high_memory" {
  display_name = "[${var.app_name}] GKE — Memória alta nos nodes (>85%)"
  project      = var.gcp_project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Memória dos nodes GKE está acima de 85%. Risco de OOMKill nos pods. Verificar memory limits ou adicionar nodes."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Memória > 85% por 5 minutos"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\"",
        "resource.type=\"k8s_node\"",
        "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0.85
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.node_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# =============================================================================
# ALERT: Error Rate alta na aplicação (>1%)
# =============================================================================

resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "[${var.app_name}] Error Rate alta (>1%)"
  project      = var.gcp_project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Taxa de erros HTTP 5xx acima de 1%. Verificar logs da aplicação e status dos deployments blue/green."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Error rate > 1% por 3 minutos"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"prometheus.googleapis.com/http_requests_total/counter\"",
        "resource.type=\"prometheus_target\"",
        "metric.label.status_code=~\"5.*\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0.01  # 1% de taxa de erro
      duration        = "180s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# =============================================================================
# ALERT: Latência P99 alta (>2s)
# =============================================================================

resource "google_monitoring_alert_policy" "high_latency" {
  display_name = "[${var.app_name}] Latência P99 alta (>2s)"
  project      = var.gcp_project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Latência P99 acima de 2 segundos. Verificar recursos dos pods, conexões de banco de dados e possíveis gargalos."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Latência P99 > 2s por 5 minutos"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"prometheus.googleapis.com/http_request_duration_seconds/histogram\"",
        "resource.type=\"prometheus_target\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 2.0
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_99"
        cross_series_reducer = "REDUCE_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]
}

# =============================================================================
# ALERT: Pod CrashLoopBackOff (>5 restarts)
# =============================================================================

resource "google_monitoring_alert_policy" "pod_crash_loop" {
  display_name = "[${var.app_name}] Pod em CrashLoopBackOff"
  project      = var.gcp_project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Um ou mais pods estão em CrashLoopBackOff com mais de 5 restarts. Verificar logs: kubectl logs -p <pod-name> -n <namespace>"
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Pod restarts > 5 em 10 minutos"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"kubernetes.io/container/restart_count\"",
        "resource.type=\"k8s_container\"",
        "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "600s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = [
          "resource.label.pod_name",
          "resource.label.namespace_name",
        ]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.name]

  alert_strategy {
    auto_close            = "3600s"
    notification_rate_limit {
      period = "300s"  # Máximo 1 notificação por 5 minutos
    }
  }
}
