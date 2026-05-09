#!/usr/bin/env bash
# =============================================================================
# setup-gcp-workload-identity.sh — Configura Workload Identity Federation no GCP
# =============================================================================
# Permite que GitHub Actions autentique no GCP via OIDC sem chaves de SA.
#
# Uso:
#   ./setup-gcp-workload-identity.sh \
#     --project-id="meu-projeto-gcp" \
#     --github-org="minha-org" \
#     --github-repo="gcp-azure-devops-platform" \
#     --sa-name="cicd-sa"
#
# Pré-requisitos:
#   - gcloud CLI instalado e autenticado
#   - Permissões: roles/iam.workloadIdentityPoolAdmin, roles/iam.serviceAccountAdmin
# =============================================================================

set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] ${*:2}"; }
log_info()    { log "INFO " "$@"; }
log_success() { log "OK   " "$@"; }
log_error()   { log "ERROR" "$@"; exit 1; }

# =============================================================================
# Argumentos padrão
# =============================================================================
PROJECT_ID=""
GITHUB_ORG=""
GITHUB_REPO=""
SA_NAME="cicd-sa"
POOL_ID="github-actions-pool"
PROVIDER_ID="github-oidc-provider"
LOCATION="global"

for arg in "$@"; do
    case "$arg" in
        --project-id=*)  PROJECT_ID="${arg#*=}"  ;;
        --github-org=*)  GITHUB_ORG="${arg#*=}"  ;;
        --github-repo=*) GITHUB_REPO="${arg#*=}" ;;
        --sa-name=*)     SA_NAME="${arg#*=}"     ;;
        --pool-id=*)     POOL_ID="${arg#*=}"     ;;
        --help)
            echo "Uso: $0 --project-id=<id> --github-org=<org> --github-repo=<repo>"
            exit 0
            ;;
        *)
            log_error "Argumento desconhecido: ${arg}"
            ;;
    esac
done

# =============================================================================
# Validações
# =============================================================================
[[ -z "$PROJECT_ID"  ]] && log_error "--project-id é obrigatório"
[[ -z "$GITHUB_ORG"  ]] && log_error "--github-org é obrigatório"
[[ -z "$GITHUB_REPO" ]] && log_error "--github-repo é obrigatório"

if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI não encontrado. Instale em: https://cloud.google.com/sdk"
fi

log_info "Iniciando configuração do Workload Identity Federation"
log_info "  Projeto:    ${PROJECT_ID}"
log_info "  GitHub Org: ${GITHUB_ORG}"
log_info "  GitHub Repo: ${GITHUB_REPO}"
log_info "  SA Name:    ${SA_NAME}"

# =============================================================================
# Obtém o número do projeto (necessário para resource names)
# =============================================================================
log_info "Obtendo número do projeto..."
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
    --format="value(projectNumber)")
log_info "Número do projeto: ${PROJECT_NUMBER}"

# =============================================================================
# Habilita APIs necessárias
# =============================================================================
log_info "Habilitando APIs necessárias..."
gcloud services enable \
    iamcredentials.googleapis.com \
    sts.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --project="${PROJECT_ID}" \
    --quiet

log_success "APIs habilitadas"

# =============================================================================
# Cria o Workload Identity Pool (se não existir)
# =============================================================================
log_info "Criando Workload Identity Pool '${POOL_ID}'..."

if gcloud iam workload-identity-pools describe "${POOL_ID}" \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" &>/dev/null; then
    log_info "Pool '${POOL_ID}' já existe — pulando criação"
else
    gcloud iam workload-identity-pools create "${POOL_ID}" \
        --location="${LOCATION}" \
        --project="${PROJECT_ID}" \
        --display-name="GitHub Actions Pool" \
        --description="Pool para autenticação de workflows GitHub Actions via OIDC" \
        --quiet
    log_success "Pool criado: ${POOL_ID}"
fi

# =============================================================================
# Cria o OIDC Provider no Pool
# =============================================================================
log_info "Criando OIDC Provider '${PROVIDER_ID}'..."

if gcloud iam workload-identity-pools providers describe "${PROVIDER_ID}" \
    --workload-identity-pool="${POOL_ID}" \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" &>/dev/null; then
    log_info "Provider '${PROVIDER_ID}' já existe — atualizando..."
    PROVIDER_CMD="update-oidc"
else
    PROVIDER_CMD="create-oidc"
fi

gcloud iam workload-identity-pools providers "${PROVIDER_CMD}" "${PROVIDER_ID}" \
    --workload-identity-pool="${POOL_ID}" \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub OIDC Provider" \
    --description="Permite autenticação via tokens OIDC emitidos pelo GitHub Actions" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_ORG}/${GITHUB_REPO}'" \
    --quiet

log_success "Provider OIDC configurado"

# =============================================================================
# Cria o Service Account para CI/CD (se não existir)
# =============================================================================
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

log_info "Configurando Service Account '${SA_EMAIL}'..."

if gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project="${PROJECT_ID}" &>/dev/null; then
    log_info "Service Account já existe"
else
    gcloud iam service-accounts create "${SA_NAME}" \
        --project="${PROJECT_ID}" \
        --display-name="GitHub Actions CI/CD SA" \
        --description="Service Account para pipelines GitHub Actions — Workload Identity" \
        --quiet
    log_success "Service Account criada: ${SA_EMAIL}"
fi

# =============================================================================
# Binding: GitHub Actions pode impersonar o SA via Workload Identity
# =============================================================================
log_info "Configurando IAM binding para Workload Identity..."

# Permite qualquer workflow do repositório específico
MEMBER="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${MEMBER}" \
    --quiet

log_success "IAM binding configurado"

# =============================================================================
# Adiciona permissões mínimas ao SA
# =============================================================================
log_info "Configurando permissões do Service Account..."

ROLES=(
    "roles/container.developer"       # Deploy no GKE
    "roles/run.admin"                  # Cloud Run
    "roles/artifactregistry.writer"   # Push de imagens
    "roles/secretmanager.secretAccessor"  # Leitura de secrets
    "roles/iam.serviceAccountTokenCreator"  # Criar tokens
    "roles/monitoring.viewer"          # Leitura de métricas
)

for role in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="${role}" \
        --quiet
    log_info "  Role adicionada: ${role}"
done

log_success "Permissões configuradas"

# =============================================================================
# Constrói os valores para configurar no GitHub
# =============================================================================
POOL_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/${LOCATION}/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# =============================================================================
# Exibe resumo e instruções
# =============================================================================
echo ""
echo "============================================================"
echo "  WORKLOAD IDENTITY FEDERATION CONFIGURADO COM SUCESSO"
echo "============================================================"
echo ""
echo "Adicione estes secrets no repositório GitHub:"
echo "  GitHub → Settings → Secrets and variables → Actions"
echo ""
echo "  GCP_PROJECT_ID:                   ${PROJECT_ID}"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER:   ${POOL_PROVIDER_RESOURCE}"
echo "  GCP_SERVICE_ACCOUNT:              ${SA_EMAIL}"
echo ""
echo "Exemplo de uso no workflow GitHub Actions:"
echo ""
echo "  - uses: google-github-actions/auth@v2"
echo "    with:"
echo "      workload_identity_provider: \${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}"
echo "      service_account: \${{ secrets.GCP_SERVICE_ACCOUNT }}"
echo ""
echo "============================================================"
