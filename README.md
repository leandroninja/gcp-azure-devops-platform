# GCP + Azure DevOps Platform

Plataforma DevOps multi-cloud de nível de produção demonstrando maestria em GCP e Azure com GitHub Actions como orquestrador principal de CI/CD.

## Propósito

Esta plataforma provisiona e gerencia infraestrutura Kubernetes em dois clouds simultaneamente:

- **GCP**: GKE (Google Kubernetes Engine) com Workload Identity, Secret Manager e Cloud Monitoring
- **Azure**: AKS (Azure Kubernetes Service) com Key Vault, Azure Monitor e OIDC Federation
- **CI/CD**: GitHub Actions como pipeline primário com suporte a blue-green e canary deployments
- **Segurança**: Scan automático de IaC, containers e dependências em todo PR e push

## Diagrama de Arquitetura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         GITHUB ACTIONS (CI/CD)                          │
│                                                                         │
│  PR → [Security Scan] → [Terraform Plan] → Merge → [Deploy Strategy]   │
│                              │                           │              │
│                    ┌─────────┴─────────┐       ┌────────┴────────┐     │
│                    │  GCP Plan Job     │       │  Azure Plan Job │     │
│                    │  OIDC Auth        │       │  OIDC Auth      │     │
│                    └─────────┬─────────┘       └────────┬────────┘     │
└──────────────────────────────┼──────────────────────────┼──────────────┘
                               │                          │
        ┌──────────────────────┘                          └──────────────────────┐
        │                                                                        │
        ▼                                                                        ▼
┌───────────────────────────────────────┐    ┌───────────────────────────────────────┐
│            GCP (us-central1)          │    │          AZURE (eastus)               │
│                                       │    │                                       │
│  ┌─────────────────────────────────┐  │    │  ┌─────────────────────────────────┐  │
│  │           VPC Privada           │  │    │  │         VNet Privada            │  │
│  │  ┌─────────────┐  ┌──────────┐  │  │    │  │  ┌───────────┐  ┌───────────┐  │  │
│  │  │  GKE Cluster│  │Cloud NAT │  │  │    │  │  │AKS Cluster│  │  Bastion  │  │  │
│  │  │  (privado)  │  │          │  │  │    │  │  │ (privado) │  │           │  │  │
│  │  │  ┌────────┐ │  └──────────┘  │  │    │  │  │ ┌───────┐ │  └───────────┘  │  │
│  │  │  │ Blue   │ │                │  │    │  │  │ │ Blue  │ │                  │  │
│  │  │  │ Green  │ │  ┌──────────┐  │  │    │  │  │ │ Green │ │  ┌───────────┐  │  │
│  │  │  │ Canary │ │  │  Secret  │  │  │    │  │  │ │ Canary│ │  │ Key Vault │  │  │
│  │  │  └────────┘ │  │ Manager  │  │  │    │  │  │ └───────┘ │  │           │  │  │
│  │  └─────────────┘  └──────────┘  │  │    │  │  └───────────┘  └───────────┘  │  │
│  └─────────────────────────────────┘  │    │  └─────────────────────────────────┘  │
│                                       │    │                                       │
│  ┌─────────────────────────────────┐  │    │  ┌─────────────────────────────────┐  │
│  │      Cloud Monitoring           │  │    │  │      Azure Monitor              │  │
│  │  Dashboards + Alert Policies    │  │    │  │  Log Analytics + Alerts         │  │
│  └─────────────────────────────────┘  │    │  └─────────────────────────────────┘  │
└───────────────────────────────────────┘    └───────────────────────────────────────┘

                    ESTRATÉGIAS DE DEPLOY
         ┌─────────────────────────────────────┐
         │          BLUE-GREEN                 │
         │  [Blue v1.0 ATIVO]  [Green v1.1]   │
         │           ↓    switch    ↑          │
         │  [Blue v1.0]  [Green v1.1 ATIVO]   │
         └─────────────────────────────────────┘
         ┌─────────────────────────────────────┐
         │             CANARY                  │
         │  95% → Stable  |  5% → Canary       │
         │  80% → Stable  |  20% → Canary      │
         │  50% → Stable  |  50% → Canary      │
         │  0%  → Stable  |  100% → Canary     │
         └─────────────────────────────────────┘
```

## Tecnologias Utilizadas

| Categoria        | GCP                               | Azure                          |
|-----------------|-----------------------------------|-------------------------------|
| Kubernetes      | GKE (privado, Workload Identity)  | AKS (privado, OIDC)           |
| Secrets         | Secret Manager (CMEK)             | Key Vault (RBAC, purge prot.) |
| Networking      | VPC, Cloud NAT, Firewall          | VNet, NSG, Bastion, DDoS      |
| IAM             | Service Accounts, WIF             | AAD, Managed Identity         |
| Monitoring      | Cloud Monitoring, Alert Policies  | Azure Monitor, Log Analytics  |
| CI/CD           | GitHub Actions (OIDC Federation)  | GitHub Actions (OIDC)         |
| IaC             | Terraform ~> 1.7                  | Terraform ~> 1.7              |

## Pré-requisitos

### Ferramentas Locais
```bash
# Terraform >= 1.7.0
terraform version

# kubectl
kubectl version --client

# gcloud CLI
gcloud version

# Azure CLI
az version

# tflint (linting)
tflint --version

# tfsec (segurança IaC)
tfsec --version

# checkov (segurança IaC)
checkov --version

# Trivy (scan de containers)
trivy --version
```

### Contas e Credenciais

**GCP:**
- Projeto GCP criado
- APIs habilitadas: container.googleapis.com, secretmanager.googleapis.com, cloudkms.googleapis.com, monitoring.googleapis.com
- Bucket GCS para estado Terraform (opcional, Azure Blob é o padrão)

**Azure:**
- Subscription ativa
- Storage Account + Container para estado Terraform
- Permissões: Contributor no Resource Group alvo

**GitHub:**
- Secrets configurados (ver seção abaixo)
- GitHub Actions habilitado no repositório

## Configuração Inicial

### 1. Configurar Workload Identity Federation (GCP)

```bash
# Executa o script de configuração
chmod +x scripts/setup-gcp-workload-identity.sh
./scripts/setup-gcp-workload-identity.sh \
  --project-id="meu-projeto-gcp" \
  --github-org="minha-org" \
  --github-repo="gcp-azure-devops-platform"
```

### 2. Configurar OIDC para Azure

```bash
chmod +x scripts/setup-azure-oidc.sh
./scripts/setup-azure-oidc.sh \
  --subscription-id="00000000-0000-0000-0000-000000000000" \
  --resource-group="rg-devops-platform" \
  --github-org="minha-org" \
  --github-repo="gcp-azure-devops-platform"
```

### 3. Configurar Secrets no GitHub

Após executar os scripts acima, adicione os seguintes secrets no repositório GitHub:

```
# GCP
GCP_PROJECT_ID          → ID do projeto GCP
GCP_WORKLOAD_IDENTITY_PROVIDER → projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER
GCP_SERVICE_ACCOUNT     → cicd-sa@PROJECT_ID.iam.gserviceaccount.com

# Azure
AZURE_CLIENT_ID         → App Registration Client ID
AZURE_TENANT_ID         → Azure AD Tenant ID
AZURE_SUBSCRIPTION_ID   → ID da Subscription
AZURE_STORAGE_ACCOUNT   → Nome do Storage Account para estado Terraform
AZURE_STORAGE_CONTAINER → Nome do Container para estado Terraform
AZURE_RESOURCE_GROUP    → Nome do Resource Group
```

### 4. Configurar tfvars

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edite o arquivo com seus valores
vim terraform/terraform.tfvars
```

### 5. Inicializar Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Estrutura do Projeto

```
gcp-azure-devops-platform/
├── README.md                          # Este arquivo
├── .gitignore                         # Ignora arquivos sensíveis
│
├── .github/
│   └── workflows/
│       ├── ci.yml                     # CI principal: lint, test, build, cost
│       ├── terraform-plan.yml         # Plan em PRs (GCP + Azure)
│       ├── deploy-blue-green.yml      # Blue-Green deployment
│       ├── deploy-canary.yml          # Canary deployment progressivo
│       └── security-scan.yml         # Scan de segurança completo
│
├── terraform/
│   ├── versions.tf                    # Providers e versões
│   ├── backend.tf                     # Estado remoto (Azure Blob / GCS)
│   ├── main.tf                        # Chamada de módulos
│   ├── variables.tf                   # Variáveis globais
│   ├── outputs.tf                     # Outputs globais
│   ├── terraform.tfvars.example       # Exemplo de configuração
│   └── modules/
│       ├── gcp/
│       │   ├── networking/            # VPC, Subnets, Cloud NAT, Firewall
│       │   ├── iam/                   # Service Accounts, Workload Identity
│       │   ├── gke/                   # GKE privado com CMEK
│       │   └── secret-manager/       # Secrets com IAM bindings
│       └── azure/
│           ├── networking/            # VNet, NSG, Bastion, DDoS
│           ├── aks/                   # AKS com CNI, OIDC, monitoring
│           └── key-vault/             # Key Vault com RBAC e soft-delete
│
├── apps/
│   └── sample-app/
│       ├── app.py                     # Flask app com /health /metrics /version
│       ├── requirements.txt           # Dependências Python
│       ├── Dockerfile                 # Multi-stage, non-root, healthcheck
│       └── k8s/
│           ├── deployment-blue.yaml   # Deploy slot blue
│           ├── deployment-green.yaml  # Deploy slot green
│           ├── service.yaml           # Service com selector dinâmico
│           ├── ingress.yaml           # Ingress GKE + AKS com TLS
│           ├── hpa.yaml               # HPA CPU + memória
│           └── canary/
│               └── deployment-canary.yaml  # Deploy canary com annotations
│
├── scripts/
│   ├── blue-green-switch.sh           # Alterna tráfego blue/green
│   ├── canary-promote.sh              # Promove peso do canary
│   ├── setup-gcp-workload-identity.sh # Configura WIF no GCP
│   ├── setup-azure-oidc.sh            # Configura OIDC no Azure
│   └── validate-local.sh             # Validação local completa
│
└── monitoring/
    ├── gcp-dashboard.tf               # Dashboard Cloud Monitoring
    ├── azure-monitor.tf               # Log Analytics + Alertas Azure
    └── alerts/
        ├── gcp-alerts.tf              # Alert Policies GCP
        └── azure-alerts.tf            # Metric Alerts Azure
```

## Workflows GitHub Actions

### CI (`ci.yml`)
Executado em todo PR e push para `main`:
- Lint: yamllint, terraform fmt, shellcheck
- Testes: pytest para scripts Python
- Build Docker: valida sem push
- Custo: infracost comenta estimativa no PR

### Terraform Plan (`terraform-plan.yml`)
Executado em PRs que alteram `terraform/**`:
- Scan de segurança: tfsec + checkov
- Plan GCP com autenticação Workload Identity
- Plan Azure com autenticação OIDC
- Comentário unificado no PR

### Deploy Blue-Green (`deploy-blue-green.yml`)
Deploy com zero downtime:
1. Detecta slot ativo (blue/green)
2. Deploy no slot inativo
3. Health checks e smoke tests
4. Alterna o Service para novo slot
5. Monitora por 5 minutos
6. Rollback automático em caso de falha

### Deploy Canary (`deploy-canary.yml`)
Rollout progressivo com análise automática:
1. Deploy canary com peso inicial (5%)
2. Monitora métricas (error rate, latência)
3. Promove automaticamente se OK
4. Rollback se métricas ultrapassam threshold
5. Full rollout quando canary_weight=100%

### Security Scan (`security-scan.yml`)
Executado em PRs, push e diariamente às 02:00 UTC:
- Trivy: scan de imagens Docker
- tfsec + checkov + infracost: IaC
- Semgrep: SAST para Python e IaC
- Gitleaks: detecção de secrets
- Safety + npm audit: dependências

## Estratégias de Deploy

### Blue-Green
```bash
# Via GitHub Actions (recomendado)
gh workflow run deploy-blue-green.yml \
  -f target_cluster=gke \
  -f image_tag=v1.2.0 \
  -f environment=production

# Via script direto
./scripts/blue-green-switch.sh \
  --cluster-type=gke \
  --namespace=production \
  --service=sample-app \
  --new-slot=green
```

### Canary
```bash
# Via GitHub Actions
gh workflow run deploy-canary.yml \
  -f image_tag=v1.2.0 \
  -f canary_weight=10 \
  -f target=gke

# Promover manualmente
./scripts/canary-promote.sh \
  --cluster-type=gke \
  --namespace=production \
  --new-weight=25
```

## Segurança

- **Sem credenciais hardcoded**: todas as autenticações via OIDC/WIF
- **Secrets criptografados**: GCP Secret Manager com CMEK, Azure Key Vault com purge protection
- **Rede privada**: clusters GKE e AKS sem endpoint público
- **Scan automático**: todo PR passa por análise de segurança
- **Least privilege**: Service Accounts com permissões mínimas necessárias
- **Auditoria**: logs de acesso habilitados em todos os recursos

## Validação Local

```bash
chmod +x scripts/validate-local.sh
./scripts/validate-local.sh
```

## Licença

MIT — uso livre para fins educacionais e demonstração de competências técnicas.

---

## Autor

**Leandro Oliveira Moraes**
Arquiteto Sênior DevOps & Multi-Cloud | Segurança & FinOps
Intel Cloud FinOps Certified | Harness Cloud Cost Management

[![LinkedIn](https://img.shields.io/badge/LinkedIn-leandro--oliveira--26b14768-blue?logo=linkedin)](https://linkedin.com/in/leandro-oliveira-26b14768)
