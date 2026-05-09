# =============================================================================
# CLOUD MONITORING — Dashboard GCP
# =============================================================================
# Cria dashboard no Google Cloud Monitoring com painéis para:
# - CPU e Memória dos nodes GKE
# - Tráfego Blue/Green (split de tráfego por slot)
# - Error Rate e Latência
# - Cloud Run (se utilizado)
# =============================================================================

variable "gcp_project_id" {
  description = "ID do projeto GCP para o dashboard"
  type        = string
}

variable "gke_cluster_name" {
  description = "Nome do cluster GKE para filtros do dashboard"
  type        = string
}

variable "app_name" {
  description = "Nome da aplicação para filtros do dashboard"
  type        = string
  default     = "devops-platform"
}

# =============================================================================
# DASHBOARD PRINCIPAL — Visão Geral da Plataforma
# =============================================================================

resource "google_monitoring_dashboard" "platform_overview" {
  project        = var.gcp_project_id
  dashboard_json = jsonencode({
    displayName = "GCP DevOps Platform — Visão Geral"
    mosaicLayout = {
      columns = 12
      tiles = [
        # ---------------------------------------------------------------
        # Painel: CPU dos Nodes GKE
        # ---------------------------------------------------------------
        {
          height = 4
          width  = 6
          widget = {
            title = "CPU dos Nodes GKE (%)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\"",
                      "resource.type=\"k8s_node\"",
                      "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
                    ])
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields     = ["resource.label.node_name"]
                    }
                  }
                }
                plotType = "LINE"
                legendTemplate = "CPU: $${resource.label.node_name}"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        },

        # ---------------------------------------------------------------
        # Painel: Memória dos Nodes GKE
        # ---------------------------------------------------------------
        {
          height = 4
          width  = 6
          xPos   = 6
          widget = {
            title = "Memória dos Nodes GKE (%)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\"",
                      "resource.type=\"k8s_node\"",
                      "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
                    ])
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields     = ["resource.label.node_name"]
                    }
                  }
                }
                plotType = "LINE"
                legendTemplate = "Mem: $${resource.label.node_name}"
              }]
              yAxis = {
                label = "Memory Utilization"
                scale = "LINEAR"
              }
            }
          }
        },

        # ---------------------------------------------------------------
        # Painel: Error Rate por Slot (Blue/Green)
        # ---------------------------------------------------------------
        {
          height = 4
          width  = 6
          yPos   = 4
          widget = {
            title = "Error Rate por Slot (Blue/Green)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"prometheus.googleapis.com/http_requests_total/counter\"",
                      "resource.type=\"prometheus_target\"",
                      "metric.label.status_code=~\"5.*\"",
                    ])
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields     = ["metric.label.slot"]
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = "Erros 5xx — Slot: $${metric.label.slot}"
              }]
              yAxis = {
                label = "Requests/s"
                scale = "LINEAR"
              }
            }
          }
        },

        # ---------------------------------------------------------------
        # Painel: Latência P99 por Slot
        # ---------------------------------------------------------------
        {
          height = 4
          width  = 6
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Latência P99 por Slot (ms)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"prometheus.googleapis.com/http_request_duration_seconds/histogram\"",
                      "resource.type=\"prometheus_target\"",
                    ])
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_PERCENTILE_99"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields     = ["metric.label.slot"]
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = "P99 — Slot: $${metric.label.slot}"
              }]
              yAxis = {
                label = "Latência (s)"
                scale = "LINEAR"
              }
            }
          }
        },

        # ---------------------------------------------------------------
        # Painel: Pods em execução por slot (Blue/Green/Canary)
        # ---------------------------------------------------------------
        {
          height = 4
          width  = 12
          yPos   = 8
          widget = {
            title = "Pods em Execução por Slot"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"kubernetes.io/pod/volume/used_bytes\"",
                      "resource.type=\"k8s_pod\"",
                      "resource.label.cluster_name=\"${var.gke_cluster_name}\"",
                      "metadata.user_labels.app=\"sample-app\"",
                    ])
                    aggregation = {
                      alignmentPeriod   = "60s"
                      perSeriesAligner  = "ALIGN_COUNT"
                      crossSeriesReducer = "REDUCE_COUNT"
                      groupByFields     = ["metadata.user_labels.slot"]
                    }
                  }
                }
                plotType       = "STACKED_BAR"
                legendTemplate = "Slot: $${metadata.user_labels.slot}"
              }]
              yAxis = {
                label = "Número de Pods"
                scale = "LINEAR"
              }
            }
          }
        },
      ]
    }
  })
}
