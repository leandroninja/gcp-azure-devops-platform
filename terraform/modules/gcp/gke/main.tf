# =============================================================================
# MÓDULO GCP GKE — Cluster Kubernetes Privado com CMEK e Workload Identity
# =============================================================================

# Chave KMS para criptografia de secrets do etcd (CMEK)
resource "google_kms_key_ring" "gke" {
  name     = "${var.app_name}-${var.environment}-gke-keyring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "gke_secrets" {
  name            = "${var.app_name}-${var.environment}-gke-secrets-key"
  key_ring        = google_kms_key_ring.gke.id
  rotation_period = "7776000s"  # Rotação automática a cada 90 dias

  lifecycle {
    prevent_destroy = true  # Proteção contra destruição acidental
  }
}

# Permissão para o GKE usar a chave KMS
resource "google_kms_crypto_key_iam_member" "gke_encrypt_decrypt" {
  crypto_key_id = google_kms_crypto_key.gke_secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@container-engine-robot.iam.gserviceaccount.com"
}

data "google_project" "current" {
  project_id = var.project_id
}

# =============================================================================
# CLUSTER GKE PRIVADO
# =============================================================================

resource "google_container_cluster" "main" {
  name     = "${var.app_name}-${var.environment}-gke"
  location = var.region
  project  = var.project_id

  # Remove o node pool padrão e usa node pools customizados
  remove_default_node_pool = true
  initial_node_count       = 1

  # Versão do Kubernetes via release channel
  release_channel {
    channel = "REGULAR"
  }
  min_master_version = var.gke_config.cluster_version

  # Rede e subnet
  network    = var.network_id
  subnetwork = var.subnetwork_id

  # Ranges de IPs para Pods e Services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.svcs_range_name
  }

  # Cluster privado: nodes sem IP público, control plane com IP privado
  private_cluster_config {
    enable_private_nodes    = var.gke_config.enable_private_nodes
    enable_private_endpoint = false   # Mantém endpoint público para acesso CI/CD
    master_ipv4_cidr_block  = var.gke_config.master_cidr

    master_global_access_config {
      enabled = true
    }
  }

  # Workload Identity: pods usam Service Accounts GCP sem chaves
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Binary Authorization: apenas imagens assinadas e verificadas
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Network Policy (CALICO): controle de tráfego entre pods
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Criptografia de secrets do etcd com CMEK
  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.gke_secrets.id
  }

  # Configurações do Master Auth (desabilita auth básica)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Autorização do Master: restringe acesso ao control plane
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.0/8"
      display_name = "Redes internas"
    }
    # Adicione CIDRs adicionais para acesso de runners CI/CD se necessário
  }

  # Addons do cluster
  addons_config {
    # HTTP Load Balancing (necessário para Ingress GKE)
    http_load_balancing {
      disabled = false
    }

    # HPA (Horizontal Pod Autoscaler)
    horizontal_pod_autoscaling {
      disabled = false
    }

    # Network Policy addon (CALICO)
    network_policy_config {
      disabled = false
    }

    # GKE Managed Prometheus para monitoramento
    gke_backup_agent_config {
      enabled = true
    }
  }

  # Configuração de monitoramento e logging
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "CONTROLLER_MANAGER",
      "SCHEDULER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
    ]
  }

  # Manutenção: janela de manutenção de baixo impacto
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T03:00:00Z"
      end_time   = "2024-01-01T07:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Resource Labels para governança e billing
  resource_labels = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
    team        = "devops"
  }

  depends_on = [google_kms_crypto_key_iam_member.gke_encrypt_decrypt]
}

# =============================================================================
# NODE POOL PRINCIPAL
# =============================================================================

resource "google_container_node_pool" "main" {
  name       = "${var.app_name}-${var.environment}-node-pool"
  cluster    = google_container_cluster.main.id
  location   = var.region
  project    = var.project_id

  # Auto-scaling regional (por zona)
  autoscaling {
    min_node_count  = var.gke_config.node_pool_min_count
    max_node_count  = var.gke_config.node_pool_max_count
    location_policy = "BALANCED"
  }

  # Gerenciamento automático dos nodes
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade progressivo dos nodes
  upgrade_settings {
    max_surge       = 2
    max_unavailable = 0
    strategy        = "SURGE"
  }

  node_config {
    machine_type = var.gke_config.node_machine_type
    disk_size_gb = var.gke_config.node_disk_size_gb
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"

    # Service Account com permissões mínimas
    service_account = var.gke_sa_email

    # Scopes OAuth mínimos (as permissões reais vêm da SA)
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity nos nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded Instance: proteção contra rootkits e bootkits
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Labels nos nodes para seleção via nodeSelector
    labels = {
      environment = var.environment
      app         = var.app_name
      node-pool   = "main"
    }

    # Taints: sem taints no pool principal
    # Para pools de uso específico, adicionar taints aqui

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = [
      "${var.app_name}-${var.environment}-gke-node",
    ]
  }

  lifecycle {
    ignore_changes = [
      node_config[0].resource_labels,
    ]
  }
}

# =============================================================================
# NAMESPACES KUBERNETES
# =============================================================================

# Aguarda o cluster estar pronto antes de criar namespaces
resource "null_resource" "gke_ready" {
  depends_on = [google_container_node_pool.main]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Aguardando cluster GKE estar disponível..."
      gcloud container clusters get-credentials ${google_container_cluster.main.name} \
        --region ${var.region} \
        --project ${var.project_id}
    EOT
  }
}

resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"
    labels = {
      environment  = "production"
      app          = var.app_name
      "managed-by" = "terraform"
    }
    annotations = {
      "deployment.strategy" = "blue-green"
    }
  }

  depends_on = [null_resource.gke_ready]
}

resource "kubernetes_namespace" "staging" {
  metadata {
    name = "staging"
    labels = {
      environment  = "staging"
      app          = var.app_name
      "managed-by" = "terraform"
    }
    annotations = {
      "deployment.strategy" = "canary"
    }
  }

  depends_on = [null_resource.gke_ready]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      environment  = var.environment
      app          = "monitoring"
      "managed-by" = "terraform"
    }
  }

  depends_on = [null_resource.gke_ready]
}
