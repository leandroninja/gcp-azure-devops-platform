#!/usr/bin/env bash
# =============================================================================
# setup-azure-oidc.sh — Configura Azure OIDC para GitHub Actions
# =============================================================================
# Cria App Registration no Azure AD com Federated Credentials para que
# o GitHub Actions autentique sem armazenar secrets de client credentials.
#
# Uso:
#   ./setup-azure-oidc.sh \
#     --subscription-id="00000000-0000-0000-0000-000000000000" \
#     --resource-group="rg-devops-platform" \
#     --github-org="minha-org" \
#     --github-repo="gcp-azure-devops-platform"
#
# Pré-requisitos:
#   - az CLI instalado e autenticado (az login)
#   - Permissões: Application.ReadWrite.All no Azure AD
#                 User Access Administrator ou Owner no Resource Group
# =============================================================================

set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] ${*:2}"; }
log_info()    { log "INFO " "$@"; }
log_success() { log "OK   " "$@"; }
log_error()   { log "ERROR" "$@"; exit 1; }

# Argumentos
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
GITHUB_ORG=""
GITHUB_REPO=""
APP_NAME="github-actions-devops-platform"

for arg in "$@"; do
    case "$arg" in
        --subscription-id=*) SUBSCRIPTION_ID="${arg#*=}" ;;
        --resource-group=*)  RESOURCE_GROUP="${arg#*=}"  ;;
        --github-org=*)      GITHUB_ORG="${arg#*=}"      ;;
        --github-repo=*)     GITHUB_REPO="${arg#*=}"     ;;
        --app-name=*)        APP_NAME="${arg#*=}"        ;;
        --help)
            echo "Uso: $0 --subscription-id=<id> --resource-group=<rg> --github-org=<org> --github-repo=<repo>"
            exit 0
            ;;
        *)
            log_error "Argumento desconhecido: ${arg}"
            ;;
    esac
done

[[ -z "$SUBSCRIPTION_ID" ]] && log_error "--subscription-id é obrigatório"
[[ -z "$RESOURCE_GROUP"  ]] && log_error "--resource-group é obrigatório"
[[ -z "$GITHUB_ORG"      ]] && log_error "--github-org é obrigatório"
[[ -z "$GITHUB_REPO"     ]] && log_error "--github-repo é obrigatório"

if ! command -v az &>/dev/null; then
    log_error "az CLI não encontrado. Instale em: https://learn.microsoft.com/cli/azure"
fi

log_info "Verificando autenticação no Azure..."
az account show &>/dev/null || log_error "Execute 'az login' primeiro"

# Define a subscription ativa
az account set --subscription "${SUBSCRIPTION_ID}"
log_info "Subscription ativa: ${SUBSCRIPTION_ID}"

# =============================================================================
# Obtém informações do tenant
# =============================================================================
TENANT_ID=$(az account show --query tenantId -o tsv)
log_info "Tenant ID: ${TENANT_ID}"

# =============================================================================
# Cria App Registration no Azure AD
# =============================================================================
log_info "Criando App Registration '${APP_NAME}'..."

# Verifica se já existe
EXISTING_APP_ID=$(az ad app list \
    --display-name "${APP_NAME}" \
    --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING_APP_ID" && "$EXISTING_APP_ID" != "None" ]]; then
    log_info "App Registration já existe: ${EXISTING_APP_ID}"
    CLIENT_ID="${EXISTING_APP_ID}"
else
    CLIENT_ID=$(az ad app create \
        --display-name "${APP_NAME}" \
        --query appId -o tsv)
    log_success "App Registration criada: ${CLIENT_ID}"

    # Cria o Service Principal associado
    az ad sp create --id "${CLIENT_ID}" --query id -o tsv >/dev/null
    log_success "Service Principal criado"
fi

# Aguarda propagação no Azure AD
sleep 10

SP_OBJECT_ID=$(az ad sp show --id "${CLIENT_ID}" --query id -o tsv)
log_info "Service Principal Object ID: ${SP_OBJECT_ID}"

# =============================================================================
# Configura Federated Credentials para OIDC
# =============================================================================
log_info "Configurando Federated Credentials para GitHub Actions..."

# Credential para push na branch main (deploys)
MAIN_CREDENTIAL_NAME="github-actions-main"
log_info "  Criando credential para branch main..."

MAIN_CRED_EXISTS=$(az ad app federated-credential list \
    --id "${CLIENT_ID}" \
    --query "[?name=='${MAIN_CREDENTIAL_NAME}'].name" -o tsv 2>/dev/null || echo "")

if [[ -z "$MAIN_CRED_EXISTS" ]]; then
    az ad app federated-credential create \
        --id "${CLIENT_ID}" \
        --parameters "{
            \"name\": \"${MAIN_CREDENTIAL_NAME}\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main\",
            \"description\": \"Permite autenticação do GitHub Actions na branch main\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" >/dev/null
    log_success "  Credential 'main' criada"
else
    log_info "  Credential 'main' já existe"
fi

# Credential para Pull Requests (terraform plan)
PR_CREDENTIAL_NAME="github-actions-pull-requests"
log_info "  Criando credential para Pull Requests..."

PR_CRED_EXISTS=$(az ad app federated-credential list \
    --id "${CLIENT_ID}" \
    --query "[?name=='${PR_CREDENTIAL_NAME}'].name" -o tsv 2>/dev/null || echo "")

if [[ -z "$PR_CRED_EXISTS" ]]; then
    az ad app federated-credential create \
        --id "${CLIENT_ID}" \
        --parameters "{
            \"name\": \"${PR_CREDENTIAL_NAME}\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:pull_request\",
            \"description\": \"Permite autenticação do GitHub Actions em Pull Requests (terraform plan)\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" >/dev/null
    log_success "  Credential 'pull_request' criada"
else
    log_info "  Credential 'pull_request' já existe"
fi

# Credential para environments específicos (production, staging)
for env in "production" "staging"; do
    ENV_CREDENTIAL_NAME="github-actions-env-${env}"
    log_info "  Criando credential para environment '${env}'..."

    ENV_CRED_EXISTS=$(az ad app federated-credential list \
        --id "${CLIENT_ID}" \
        --query "[?name=='${ENV_CREDENTIAL_NAME}'].name" -o tsv 2>/dev/null || echo "")

    if [[ -z "$ENV_CRED_EXISTS" ]]; then
        az ad app federated-credential create \
            --id "${CLIENT_ID}" \
            --parameters "{
                \"name\": \"${ENV_CREDENTIAL_NAME}\",
                \"issuer\": \"https://token.actions.githubusercontent.com\",
                \"subject\": \"repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${env}\",
                \"description\": \"Permite autenticação do GitHub Actions no environment ${env}\",
                \"audiences\": [\"api://AzureADTokenExchange\"]
            }" >/dev/null
        log_success "  Credential environment '${env}' criada"
    else
        log_info "  Credential environment '${env}' já existe"
    fi
done

# =============================================================================
# Atribui roles ao Service Principal
# =============================================================================
log_info "Atribuindo roles ao Service Principal..."

# Verifica se o Resource Group existe, cria se não existir
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    log_info "Resource Group '${RESOURCE_GROUP}' não encontrado — criando..."
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "eastus" \
        --query id -o tsv >/dev/null
    log_success "Resource Group criado"
fi

RG_SCOPE=$(az group show --name "${RESOURCE_GROUP}" --query id -o tsv)

# Contributor: para provisionar recursos via Terraform
log_info "  Atribuindo Contributor no Resource Group..."
az role assignment create \
    --assignee "${SP_OBJECT_ID}" \
    --role "Contributor" \
    --scope "${RG_SCOPE}" \
    --output none 2>/dev/null || log_info "  Contributor já atribuído"

# Key Vault Secrets Officer: para gerenciar secrets no Key Vault
log_info "  Atribuindo Key Vault Secrets Officer..."
az role assignment create \
    --assignee "${SP_OBJECT_ID}" \
    --role "Key Vault Secrets Officer" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --output none 2>/dev/null || log_info "  Key Vault Secrets Officer já atribuído"

# AKS Cluster Admin: para gerenciar o cluster AKS
log_info "  Atribuindo Azure Kubernetes Service Cluster Admin Role..."
az role assignment create \
    --assignee "${SP_OBJECT_ID}" \
    --role "Azure Kubernetes Service Cluster Admin Role" \
    --scope "${RG_SCOPE}" \
    --output none 2>/dev/null || log_info "  AKS Admin Role já atribuído"

log_success "Roles atribuídas com sucesso"

# =============================================================================
# Configura Storage Account para estado Terraform (se necessário)
# =============================================================================
STORAGE_ACCOUNT_NAME="stterraformstate$(echo "${SUBSCRIPTION_ID}" | tr -d '-' | cut -c1-8)"

log_info "Verificando Storage Account para estado Terraform..."
if ! az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    log_info "Criando Storage Account '${STORAGE_ACCOUNT_NAME}' para estado Terraform..."
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "eastus" \
        --sku "Standard_LRS" \
        --kind "StorageV2" \
        --enable-hierarchical-namespace false \
        --min-tls-version "TLS1_2" \
        --allow-blob-public-access false \
        --output none

    az storage container create \
        --name "tfstate" \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --auth-mode login \
        --output none

    log_success "Storage Account e container 'tfstate' criados"
else
    log_info "Storage Account já existe"
fi

# Atribui acesso ao SP no Storage Account
az role assignment create \
    --assignee "${SP_OBJECT_ID}" \
    --role "Storage Blob Data Contributor" \
    --scope "$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)" \
    --output none 2>/dev/null || true

# =============================================================================
# Exibe resumo e instruções
# =============================================================================
echo ""
echo "============================================================"
echo "  AZURE OIDC CONFIGURADO COM SUCESSO"
echo "============================================================"
echo ""
echo "Adicione estes secrets no repositório GitHub:"
echo "  GitHub → Settings → Secrets and variables → Actions"
echo ""
echo "  AZURE_CLIENT_ID:         ${CLIENT_ID}"
echo "  AZURE_TENANT_ID:         ${TENANT_ID}"
echo "  AZURE_SUBSCRIPTION_ID:   ${SUBSCRIPTION_ID}"
echo "  AZURE_RESOURCE_GROUP:    ${RESOURCE_GROUP}"
echo "  AZURE_STORAGE_ACCOUNT:   ${STORAGE_ACCOUNT_NAME}"
echo "  AZURE_STORAGE_CONTAINER: tfstate"
echo ""
echo "Exemplo de uso no workflow GitHub Actions:"
echo ""
echo "  - uses: azure/login@v2"
echo "    with:"
echo "      client-id:       \${{ secrets.AZURE_CLIENT_ID }}"
echo "      tenant-id:       \${{ secrets.AZURE_TENANT_ID }}"
echo "      subscription-id: \${{ secrets.AZURE_SUBSCRIPTION_ID }}"
echo ""
echo "============================================================"
