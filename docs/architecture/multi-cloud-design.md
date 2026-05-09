# Arquitetura Multi-Cloud — GCP + Azure DevOps Platform

**Versão:** 1.0  
**Última atualização:** 2026-05-09  
**Status:** Aprovado  
**Time:** Plataforma / DevOps

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Diagrama ASCII da Arquitetura Completa](#diagrama-ascii-da-arquitetura-completa)
3. [Componentes por Camada](#componentes-por-camada)
4. [Fluxo de Dados entre GCP e Azure](#fluxo-de-dados-entre-gcp-e-azure)
5. [Estratégia de Secrets e IAM](#estratégia-de-secrets-e-iam)
6. [Architecture Decision Records (ADRs)](#architecture-decision-records-adrs)
7. [Limites de Responsabilidade por Cloud](#limites-de-responsabilidade-por-cloud)
8. [Plano de Continuidade e Disaster Recovery](#plano-de-continuidade-e-disaster-recovery)

---

## Visão Geral

Esta plataforma DevOps adota uma arquitetura multi-cloud com **GCP como cloud primária** e **Azure como cloud secundária**. A divisão foi projetada para aproveitar os pontos fortes de cada provedor e evitar lock-in total em um único vendor.

**Princípios de design:**

- **Zero Trust Network:** Sem confiança implícita entre serviços; autenticação em cada chamada
- **GitOps:** Toda infraestrutura é código versionado; nenhuma mudança manual em produção
- **Least Privilege:** Cada identidade tem apenas as permissões mínimas necessárias
- **Observabilidade por padrão:** Logs, métricas e traces são configurados desde a criação

---

## Diagrama ASCII da Arquitetura Completa

```
╔═══════════════════════════════════════════════════════════════════════════════════╗
║                         GITHUB ACTIONS — CI/CD PIPELINE                          ║
║                                                                                   ║
║  ┌─────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐  ║
║  │  Push/  │───▶│  Lint + Test │───▶│  Security Scan  │───▶│  Terraform Plan  │  ║
║  │  PR     │    │  (CI)        │    │  tfsec + checkov│    │  GCP + Azure     │  ║
║  └─────────┘    └──────────────┘    └─────────────────┘    └────────┬─────────┘  ║
║                                                                      │            ║
║  ┌─────────────────────────────────────────────────────────────────▼──────────┐  ║
║  │              Docker Build (multi-platform) → Artifact Registry GCP         │  ║
║  └─────────────────────────────────────────────────────────────────┬──────────┘  ║
║                                                                     │             ║
║              ┌──────────────────────────────────────────────────────▼──────────┐  ║
║              │    Deploy Strategy: Rolling / Blue-Green / Canary               │  ║
║              └──────────────────────┬───────────────────────────────────────────┘  ║
╚═════════════════════════════════════╪═════════════════════════════════════════════╝
                                      │
              ┌───────────────────────┼────────────────────────┐
              │                       │                        │
              ▼                       │                        ▼
╔═════════════════════════╗           │          ╔═════════════════════════╗
║   GOOGLE CLOUD (GCP)    ║           │          ║    MICROSOFT AZURE      ║
║                         ║           │          ║                         ║
║  ┌─────────────────────┐║           │          ║┌─────────────────────┐  ║
║  │   VPC Network       │║           │          ║│   Virtual Network   │  ║
║  │  10.0.0.0/16        │║           │          ║│  10.1.0.0/16        │  ║
║  │                     │║◀──────────┤          ║│                     │  ║
║  │  ┌───────────────┐  │║  VPN/     │          ║│  ┌───────────────┐  │  ║
║  │  │  GKE Cluster  │  │║  Peering  │          ║│  │  AKS Cluster  │  │  ║
║  │  │  (Autopilot)  │  │║           │          ║│  │               │  │  ║
║  │  │               │  │║           │          ║│  │               │  │  ║
║  │  │  ┌──────────┐ │  │║           │          ║│  │  ┌──────────┐ │  │  ║
║  │  │  │ sample-  │ │  │║           │          ║│  │  │ sample-  │ │  │  ║
║  │  │  │  app     │ │  │║           │          ║│  │  │  app     │ │  │  ║
║  │  │  │ blue/    │ │  │║           │          ║│  │  │ blue/    │ │  │  ║
║  │  │  │ green/   │ │  │║           │          ║│  │  │ green/   │ │  │  ║
║  │  │  │ canary   │ │  │║           │          ║│  │  │ canary   │ │  │  ║
║  │  │  └──────────┘ │  │║           │          ║│  │  └──────────┘ │  │  ║
║  │  └───────────────┘  │║           │          ║│  └───────────────┘  │  ║
║  │                     │║           │          ║│                     │  ║
║  │  ┌───────────────┐  │║           │          ║│  ┌───────────────┐  │  ║
║  │  │ Artifact      │  │║           │          ║│  │ Azure         │  │  ║
║  │  │ Registry      │  │║           │          ║│  │ Container     │  │  ║
║  │  │ (Docker imgs) │  │║           │          ║│  │ Registry      │  │  ║
║  │  └───────────────┘  │║           │          ║│  └───────────────┘  │  ║
║  │                     │║           │          ║│                     │  ║
║  │  ┌───────────────┐  │║           │          ║│  ┌───────────────┐  │  ║
║  │  │ Secret        │  │║           │          ║│  │   Key Vault   │  │  ║
║  │  │ Manager       │◀─┼╫───────────┤          ║│  │               │  │  ║
║  │  └───────────────┘  │║  Sync     │          ║│  └───────────────┘  │  ║
║  │                     │║  (ESO)    │          ║│                     │  ║
║  │  ┌───────────────┐  │║           │          ║│  ┌───────────────┐  │  ║
║  │  │ Cloud Storage │  │║           │          ║│  │ Storage       │  │  ║
║  │  │ (TF State)    │  │║           │          ║│  │ Account       │  │  ║
║  │  └───────────────┘  │║           │          ║│  │ (TF State)    │  │  ║
║  └─────────────────────┘║           │          ║│  └───────────────┘  │  ║
║                         ║           │          ║└─────────────────────┘  ║
║  ┌─────────────────────┐║           │          ║┌─────────────────────┐  ║
║  │ Cloud Monitoring    │║           │          ║│ Azure Monitor       │  ║
║  │ + Cloud Logging     │╠═══════════╪══════════╣│ + Log Analytics     │  ║
║  │ + Alerting          │║  Telemetry│ Bridge   ║│ + Alerts            │  ║
║  └─────────────────────┘║           │          ║└─────────────────────┘  ║
║                         ║           │          ║                         ║
║  ┌─────────────────────┐║           │          ║┌─────────────────────┐  ║
║  │ Workload Identity   │║           │          ║│ Managed Identity    │  ║
║  │ Federation (OIDC)   │║           │          ║│ + OIDC Federation   │  ║
║  └─────────────────────┘║           │          ║└─────────────────────┘  ║
╚═════════════════════════╝           │          ╚═════════════════════════╝
                                      │
                            ┌─────────▼─────────┐
                            │   USUÁRIOS FINAIS  │
                            │  (Load Balancer    │
                            │   Global / CDN)    │
                            └───────────────────┘
```

---

## Componentes por Camada

### Camada de CI/CD (GitHub Actions)

| Componente | Descrição | Arquivo |
|------------|-----------|---------|
| Lint + Testes | Valida código a cada PR | `.github/workflows/ci.yml` |
| Terraform Plan | Plan automático em PRs com mudanças em `terraform/` | `.github/workflows/terraform-plan.yml` |
| Docker Build | Build multi-platform + push para Artifact Registry | `.github/workflows/reusable-docker-build.yml` |
| Deploy Kubernetes | Rolling / Blue-Green / Canary em GKE e AKS | `.github/workflows/reusable-deploy-k8s.yml` |
| Security Scan | tfsec + checkov + Trivy a cada commit | `.github/workflows/security-scan.yml` |

### Camada de Computação

| Componente | Cloud | Tecnologia | Uso |
|------------|-------|------------|-----|
| GKE Cluster | GCP | GKE Autopilot | Workload principal |
| AKS Cluster | Azure | AKS Standard | Workload secundário / DR |
| Node Pools | GCP | e2-standard-4 | Workers de aplicação |
| Node Pools | Azure | Standard_D4s_v3 | Workers de aplicação |

### Camada de Armazenamento e Registro

| Componente | Cloud | Uso |
|------------|-------|-----|
| Artifact Registry | GCP | Imagens Docker de todas as aplicações |
| Azure Container Registry | Azure | Espelho das imagens para AKS |
| Cloud Storage | GCP | Estado do Terraform (bucket `tfstate-gcp`) |
| Azure Blob Storage | Azure | Estado do Terraform (container `tfstate-azure`) |

### Camada de Secrets

| Componente | Cloud | Uso |
|------------|-------|-----|
| Secret Manager | GCP | Secrets da aplicação no GKE |
| Azure Key Vault | Azure | Secrets da aplicação no AKS |
| External Secrets Operator | Ambos | Sincroniza secrets do vault para o Kubernetes |
| GitHub Secrets | GitHub | Credenciais de CI/CD (OIDC, não senhas) |

### Camada de Observabilidade

| Componente | Cloud | Uso |
|------------|-------|-----|
| Cloud Monitoring | GCP | Métricas do GKE + alertas |
| Cloud Logging | GCP | Logs centralizados do GKE |
| Azure Monitor | Azure | Métricas do AKS + alertas |
| Log Analytics | Azure | Logs centralizados do AKS |
| Grafana | GCP (self-hosted) | Dashboards unificados multi-cloud |

---

## Fluxo de Dados entre GCP e Azure

### Fluxo 1 — Deploy de nova versão

```
  Developer
      │
      │  git push / PR merge
      ▼
  GitHub Actions
      │
      ├──[1] Build Docker image
      │       └── Push para Artifact Registry (GCP)
      │
      ├──[2] Terraform Plan/Apply
      │       ├── GKE: us-central1 (GCP)
      │       └── AKS: eastus (Azure)
      │
      └──[3] Deploy Kubernetes
              ├── GKE: blue-green switch
              └── AKS: blue-green switch
```

### Fluxo 2 — Sincronização de Secrets

```
  Secret Manager (GCP)                Azure Key Vault
         │                                   │
         │  External Secrets Operator        │
         │  (rodando nos dois clusters)      │
         ▼                                   ▼
  Kubernetes Secret (GKE)        Kubernetes Secret (AKS)
  namespace: production          namespace: production
  nome: app-secrets              nome: app-secrets
```

### Fluxo 3 — Replicação de Imagens Docker

```
  Artifact Registry (GCP)
  us-central1-docker.pkg.dev/projeto/repo/app:sha-abc
          │
          │  Cloud Build trigger (ao receber nova tag)
          │  ou: gcrane copy
          ▼
  Azure Container Registry
  projeto.azurecr.io/app:sha-abc
```

### Fluxo 4 — Telemetria Unificada

```
  GKE Pods                    AKS Pods
  (OpenTelemetry SDK)         (OpenTelemetry SDK)
       │                           │
       ▼                           ▼
  OTEL Collector              OTEL Collector
  (sidecar/daemonset)         (sidecar/daemonset)
       │                           │
       ▼                           ▼
  Cloud Monitoring            Azure Monitor
  (GCP nativo)                (Azure nativo)
       │                           │
       └────────────┬──────────────┘
                    │
                    ▼
               Grafana
          (datasource duplo:
           Cloud Monitoring +
           Azure Monitor)
```

---

## Estratégia de Secrets e IAM

### Princípios

1. **Nenhuma senha ou token estático** — toda autenticação usa OIDC/Workload Identity
2. **Rotação automática** — secrets rodam a cada 30 dias via Cloud Scheduler
3. **Separação por ambiente** — secrets de staging e production são totalmente isolados
4. **Auditoria obrigatória** — todos os acessos a secrets são logados e retidos por 90 dias

### GCP — Workload Identity Federation

O GitHub Actions autentica no GCP sem senha via Workload Identity Federation:

```
  GitHub Actions Runner
  (OIDC token do GitHub: iss=https://token.actions.githubusercontent.com)
          │
          │  Troca de token via STS
          ▼
  Workload Identity Pool (GCP)
  Pool: pool-github-actions
  Provider: provider-github
          │
          │  Impersonação condicional
          │  (condition: repo/branch/environment)
          ▼
  Service Account GCP
  cicd@projeto.iam.gserviceaccount.com
  Roles:
    - roles/container.developer (GKE)
    - roles/artifactregistry.writer (Artifact Registry)
    - roles/secretmanager.secretAccessor (Secret Manager — staging)
```

### Azure — Federated Identity Credential

```
  GitHub Actions Runner
  (OIDC token do GitHub)
          │
          │  Federated Identity Credential
          ▼
  Azure Managed Identity
  (ou App Registration)
  client-id: xxx-yyy-zzz
  Roles:
    - AcrPush (Azure Container Registry)
    - Azure Kubernetes Service Cluster User Role (AKS)
    - Key Vault Secrets Officer (Key Vault — staging)
```

### Kubernetes — ServiceAccount e RBAC

Cada namespace usa ServiceAccounts separadas com RBAC mínimo:

```yaml
# GKE: ServiceAccount da aplicação com acesso apenas ao Secret Manager
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sample-app
  namespace: production
  annotations:
    # Workload Identity: mapeia para uma SA do GCP
    iam.gke.io/gcp-service-account: app-production@projeto.iam.gserviceaccount.com
```

### Hierarquia de Secrets

```
  GitHub Repository Secrets (CI/CD)
  ├── GCP_WORKLOAD_IDENTITY_PROVIDER (pool/provider URI)
  ├── GCP_SERVICE_ACCOUNT (SA email)
  ├── AZURE_CLIENT_ID
  ├── AZURE_TENANT_ID
  └── AZURE_SUBSCRIPTION_ID

  GitHub Environment Secrets: staging
  └── (sobrescreve os repo-level para staging)

  GitHub Environment Secrets: production
  └── (sobrescreve os repo-level para production — SAs com permissões restritas)

  GCP Secret Manager: projeto-staging
  ├── app/database-url
  ├── app/api-key-external
  └── app/jwt-secret

  Azure Key Vault: kv-platform-staging
  ├── app-database-url
  ├── app-api-key-external
  └── app-jwt-secret
```

---

## Architecture Decision Records (ADRs)

### ADR-001 — GCP como cloud primária para workloads de computação

**Status:** Aceito  
**Data:** 2026-01-15

**Contexto:** Foi necessário escolher uma cloud primária para hospedar os workloads Kubernetes principais.

**Decisão:** GCP foi escolhido como cloud primária porque:
- GKE Autopilot reduz a carga operacional de gestão de nodes
- Artifact Registry tem integração nativa com GKE (sem configurar pull secrets)
- Workload Identity Federation tem suporte mais maduro no GCP para OIDC
- Preço por vCPU em GKE Autopilot é previsível e competitivo para workloads intermitentes

**Consequências:** Azure é usado como cloud secundária para DR e diversidade de vendor.

---

### ADR-002 — Estado do Terraform armazenado no Azure Blob Storage

**Status:** Aceito  
**Data:** 2026-01-20

**Contexto:** O estado do Terraform precisa de um backend remoto com locking.

**Decisão:** O estado do Terraform de todos os módulos (GCP e Azure) é armazenado no Azure Blob Storage. O locking nativo do Azure Blob Storage (via lease) elimina a necessidade de uma tabela DynamoDB ou similar.

**Consequências:** Para criar a infraestrutura do GCP pela primeira vez, o Azure deve ser provisionado antes (bootstrap manual documentado no README).

---

### ADR-003 — Deploy Blue-Green como estratégia padrão para produção

**Status:** Aceito  
**Data:** 2026-02-01

**Contexto:** Era necessário escolher uma estratégia de deploy para produção que garantisse zero downtime e rollback rápido.

**Decisão:** Blue-Green é a estratégia padrão para produção porque:
- Rollback leva menos de 30 segundos (patch no Service selector)
- Não requer infraestrutura de weighted routing (nginx-ingress annotation vs Istio)
- Simples de entender e operar durante incidentes
- O slot inativo serve como hot standby imediato

**Alternativa considerada:** Canary foi considerado como padrão, mas foi reservado para deploys de alto risco onde é necessário validar com tráfego real antes de full rollout.

---

### ADR-004 — Autenticação sem senha via OIDC em todos os pipelines

**Status:** Aceito  
**Data:** 2026-02-10

**Contexto:** Pipelines de CI/CD precisam de acesso às clouds para deploy. A prática tradicional usa tokens/senhas estáticas armazenadas como secrets no GitHub.

**Decisão:** Toda autenticação usa OIDC (OpenID Connect) sem credenciais estáticas:
- GCP: Workload Identity Federation com condicional de branch/environment
- Azure: Federated Identity Credentials na App Registration

**Consequências:** Setup inicial é mais complexo (scripts em `scripts/setup-gcp-workload-identity.sh` e `scripts/setup-azure-oidc.sh`), mas elimina o risco de vazamento de tokens e a necessidade de rotação manual.

---

### ADR-005 — Imagens Docker armazenadas apenas no Artifact Registry do GCP

**Status:** Aceito  
**Data:** 2026-02-15

**Contexto:** Com dois clusters Kubernetes (GKE e AKS), é necessário definir onde armazenar as imagens Docker.

**Decisão:** As imagens são construídas uma única vez e armazenadas no Artifact Registry do GCP. O AKS acessa o Artifact Registry via pull secret configurado com uma SA de leitura. Isso evita duplicar o storage de imagens.

**Alternativa considerada:** Replicar imagens para o Azure Container Registry. Pode ser adotado futuramente se a latência de pull no AKS se tornar um problema.

---

## Limites de Responsabilidade por Cloud

| Responsabilidade | GCP | Azure |
|-----------------|-----|-------|
| Workload principal (aplicação) | Primário | Secundário / DR |
| Imagens Docker | Artifact Registry | Pull do GCP (ou ACR como mirror) |
| Estado do Terraform | Backend secundário | Backend primário |
| Gestão de secrets | Secret Manager | Key Vault |
| Monitoramento | Cloud Monitoring | Azure Monitor |
| DNS público | Cloud DNS | Azure DNS (failover) |
| CDN | Cloud CDN | Azure Front Door (DR) |
| Kubernetes | GKE Autopilot | AKS |

---

## Plano de Continuidade e Disaster Recovery

### RTO e RPO

| Cenário | RTO (Recovery Time Objective) | RPO (Recovery Point Objective) |
|---------|-------------------------------|--------------------------------|
| Falha em um pod/deployment | < 2 min (autorecovery K8s) | 0 |
| Falha de um node pool no GKE | < 5 min (GKE Autopilot auto-provision) | 0 |
| Falha total do GKE cluster | < 30 min (failover para AKS) | 0 (se replicação de dados estiver ativa) |
| Indisponibilidade da região GCP | < 60 min (failover para Azure East US) | < 5 min (replicação assíncrona) |
| Catástrofe multi-cloud | 4–8 horas (rebuild via Terraform) | < 24 horas |

### Procedimento de Failover GCP → Azure

```bash
# 1. Confirmar que o GKE está indisponível
kubectl --context=gke_project_us-central1_gke-platform-prod cluster-info

# 2. Atualizar DNS para apontar para o AKS (via Azure Front Door ou Traffic Manager)
az network traffic-manager endpoint update \
  --resource-group rg-devops-platform \
  --profile-name tm-devops-platform \
  --name endpoint-gcp \
  --type externalEndpoints \
  --endpoint-status Disabled

# 3. Verificar saúde do AKS
kubectl --context=aks-platform-prod get nodes
kubectl --context=aks-platform-prod get pods -n production

# 4. Confirmar que a versão correta está rodando no AKS
kubectl --context=aks-platform-prod get pods -n production \
  -o jsonpath='{.items[*].spec.containers[0].image}'
```

### Diagrama de failover simplificado

```
  NORMAL:
  Usuários → Cloud CDN (GCP) → GKE (us-central1) → App

  FAILOVER (GCP indisponível):
  Usuários → Azure Front Door → AKS (eastus) → App
                 ↑
          (DNS TTL: 60s — failover automático via health check)
```
