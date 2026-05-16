# =============================================================================
# MÓDULO GCP NETWORKING — VPC Privada, Subnets, Cloud NAT, Firewall
# =============================================================================

# VPC principal — sem subnets automáticas (modo custom)
resource "google_compute_network" "main" {
  name                    = "${var.app_name}-${var.environment}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC principal da plataforma ${var.app_name} (${var.environment})"

  project = var.project_id
}

# Subnet privada principal — nodes GKE e workloads
resource "google_compute_subnetwork" "main" {
  name          = "${var.app_name}-${var.environment}-subnet-main"
  ip_cidr_range = "10.0.0.0/20"    # 4096 IPs para nodes
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id
  description   = "Subnet principal — nodes GKE e workloads"

  # Habilita Private Google Access (acesso a APIs Google sem NAT)
  private_ip_google_access = true

  # VPC Flow Logs para auditoria e troubleshooting de rede
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  # Ranges secundários para Pods e Services do GKE
  secondary_ip_range {
    range_name    = "${var.app_name}-${var.environment}-pods"
    ip_cidr_range = "10.4.0.0/14"   # 262144 IPs para pods
  }

  secondary_ip_range {
    range_name    = "${var.app_name}-${var.environment}-services"
    ip_cidr_range = "10.8.0.0/20"   # 4096 IPs para services
  }
}

# Subnet para recursos de gerenciamento (bastion, etc.)
resource "google_compute_subnetwork" "management" {
  name          = "${var.app_name}-${var.environment}-subnet-mgmt"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id
  description   = "Subnet de gerenciamento — acesso interno e ferramentas"

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# =============================================================================
# CLOUD ROUTER — necessário para o Cloud NAT
# =============================================================================

resource "google_compute_router" "main" {
  name    = "${var.app_name}-${var.environment}-router"
  region  = var.region
  network = google_compute_network.main.id
  project = var.project_id

  bgp {
    asn = 64514
  }
}

# =============================================================================
# CLOUD NAT — saída para internet sem IPs públicos nos nodes
# =============================================================================

resource "google_compute_router_nat" "main" {
  name                               = "${var.app_name}-${var.environment}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Timeout de conexão TCP (segundos)
  tcp_established_idle_timeout_sec   = 1200
  tcp_transitory_idle_timeout_sec    = 30

  # Habilitando logs de NAT para auditoria
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# =============================================================================
# FIREWALL RULES
# =============================================================================

# Regra padrão: nega todo tráfego de entrada (segurança por padrão)
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${var.app_name}-${var.environment}-deny-all-ingress"
  network     = google_compute_network.main.id
  project     = var.project_id
  description = "Nega todo tráfego de entrada por padrão. Outras regras com prioridade menor permitem tráfego específico."
  direction   = "INGRESS"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Permite comunicação interna dentro da VPC
resource "google_compute_firewall" "allow_internal" {
  name        = "${var.app_name}-${var.environment}-allow-internal"
  network     = google_compute_network.main.id
  project     = var.project_id
  description = "Permite comunicação interna entre recursos da VPC"
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    "10.0.0.0/20",   # Subnet principal
    "10.1.0.0/24",   # Subnet de gerenciamento
    "10.4.0.0/14",   # Range de Pods GKE
    "10.8.0.0/20",   # Range de Services GKE
  ]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Permite health checks do Google Cloud Load Balancer
resource "google_compute_firewall" "allow_health_checks" {
  name        = "${var.app_name}-${var.environment}-allow-health-checks"
  network     = google_compute_network.main.id
  project     = var.project_id
  description = "Permite health checks do Google Cloud Load Balancer"
  direction   = "INGRESS"
  priority    = 900

  allow {
    protocol = "tcp"
    ports    = ["8080", "8443", "10256"]
  }

  # IPs dos health checkers do Google Cloud
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16",
  ]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Permite acesso SSH apenas da subnet de gerenciamento (via IAP)
resource "google_compute_firewall" "allow_ssh_iap" {
  name        = "${var.app_name}-${var.environment}-allow-ssh-iap"
  network     = google_compute_network.main.id
  project     = var.project_id
  description = "Permite SSH apenas via Identity-Aware Proxy (IAP)"
  direction   = "INGRESS"
  priority    = 800

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IPs do IAP do Google
  source_ranges = ["35.235.240.0/20"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Permite tráfego HTTPS de entrada (Load Balancer externo)
resource "google_compute_firewall" "allow_https_ingress" {
  name        = "${var.app_name}-${var.environment}-allow-https"
  network     = google_compute_network.main.id
  project     = var.project_id
  description = "Permite tráfego HTTPS de entrada para o Load Balancer"
  direction   = "INGRESS"
  priority    = 700

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
