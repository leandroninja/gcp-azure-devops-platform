#!/usr/bin/env bash
# =============================================================================
# validate-local.sh — Validação local completa antes de fazer commit/push
# =============================================================================
# Executa as mesmas verificações que o CI/CD faz no GitHub Actions,
# permitindo detectar e corrigir problemas antes de abrir um PR.
#
# Uso:
#   chmod +x scripts/validate-local.sh
#   ./scripts/validate-local.sh
#   ./scripts/validate-local.sh --skip-checkov   # Pula checkov (mais lento)
#   ./scripts/validate-local.sh --fix-fmt         # Corrige formatação automaticamente
# =============================================================================

set -euo pipefail

# =============================================================================
# Configurações
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKIP_CHECKOV=false
FIX_FORMAT=false
ERRORS=0
WARNINGS=0

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse de argumentos
for arg in "$@"; do
    case "$arg" in
        --skip-checkov)  SKIP_CHECKOV=true ;;
        --fix-fmt)       FIX_FORMAT=true   ;;
        --help)
            echo "Uso: $0 [--skip-checkov] [--fix-fmt]"
            echo "  --skip-checkov  Pula análise checkov (mais rápido)"
            echo "  --fix-fmt       Corrige formatação Terraform automaticamente"
            exit 0
            ;;
    esac
done

# =============================================================================
# Funções auxiliares
# =============================================================================
print_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════${NC}"
}

check_tool() {
    local tool="$1"
    local install_hint="${2:-}"
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${YELLOW}[AVISO] '${tool}' não encontrado${install_hint:+ — ${install_hint}}${NC}"
        WARNINGS=$((WARNINGS+1))
        return 1
    fi
    return 0
}

run_check() {
    local name="$1"
    shift
    echo -n "  Verificando ${name}... "
    if "$@" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FALHOU${NC}"
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

run_check_verbose() {
    local name="$1"
    shift
    echo "  Verificando ${name}..."
    if "$@"; then
        echo -e "  ${GREEN}${name} OK${NC}"
        return 0
    else
        echo -e "  ${RED}${name} FALHOU${NC}"
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

# =============================================================================
# Verificação de ferramentas necessárias
# =============================================================================
print_header "Verificando Ferramentas"

check_tool "terraform" "Instale em: https://terraform.io/downloads"
check_tool "tflint"    "Instale em: https://github.com/terraform-linters/tflint"
check_tool "shellcheck" "Instale: apt/brew install shellcheck"
check_tool "yamllint"   "Instale: pip install yamllint"
check_tool "checkov"    "Instale: pip install checkov"
check_tool "docker"     "Instale em: https://docs.docker.com/get-docker/"
check_tool "kubectl"    "Instale em: https://kubernetes.io/docs/tasks/tools/"

echo ""

# =============================================================================
# TERRAFORM — Formatação
# =============================================================================
print_header "Terraform — Formatação"

if [[ "$FIX_FORMAT" == "true" ]]; then
    echo -n "  Corrigindo formatação... "
    terraform fmt -recursive "${PROJECT_ROOT}/terraform/" && echo -e "${GREEN}OK${NC}" || {
        echo -e "${RED}FALHOU${NC}"
        ERRORS=$((ERRORS+1))
    }
else
    echo -n "  Verificando formatação (terraform fmt -check)... "
    if terraform fmt -check -recursive "${PROJECT_ROOT}/terraform/" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FALHOU${NC} — execute com --fix-fmt para corrigir automaticamente"
        terraform fmt -check -recursive -diff "${PROJECT_ROOT}/terraform/" || true
        ERRORS=$((ERRORS+1))
    fi
fi

# =============================================================================
# TERRAFORM — Validate por módulo
# =============================================================================
print_header "Terraform — Validate"

MODULES=(
    "modules/gcp/networking"
    "modules/gcp/iam"
    "modules/gcp/gke"
    "modules/gcp/secret-manager"
    "modules/azure/networking"
    "modules/azure/aks"
    "modules/azure/key-vault"
)

for module in "${MODULES[@]}"; do
    MODULE_PATH="${PROJECT_ROOT}/terraform/${module}"
    echo -n "  Validando ${module}... "
    if (cd "${MODULE_PATH}" && terraform init -backend=false -input=false &>/dev/null && terraform validate -no-color &>/dev/null); then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FALHOU${NC}"
        (cd "${MODULE_PATH}" && terraform validate -no-color) || true
        ERRORS=$((ERRORS+1))
    fi
done

# =============================================================================
# TFLINT — Análise estática
# =============================================================================
print_header "TFLint — Análise Estática"

if check_tool "tflint" "Instale: https://github.com/terraform-linters/tflint"; then
    echo -n "  Executando tflint... "
    if (cd "${PROJECT_ROOT}/terraform" && tflint --init &>/dev/null && tflint --recursive &>/dev/null); then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}AVISOS encontrados${NC}"
        (cd "${PROJECT_ROOT}/terraform" && tflint --recursive) || true
        WARNINGS=$((WARNINGS+1))
    fi
fi

# =============================================================================
# CHECKOV — Scan de segurança IaC
# =============================================================================
if [[ "$SKIP_CHECKOV" == "false" ]]; then
    print_header "Checkov — Segurança IaC"

    if check_tool "checkov" "Instale: pip install checkov"; then
        echo -n "  Checkov Terraform... "
        if checkov \
            --directory "${PROJECT_ROOT}/terraform" \
            --framework terraform \
            --compact \
            --quiet \
            --soft-fail \
            &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Avisos encontrados (soft-fail)${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        echo -n "  Checkov Kubernetes manifests... "
        if checkov \
            --directory "${PROJECT_ROOT}/apps/sample-app/k8s" \
            --framework kubernetes \
            --compact \
            --quiet \
            --soft-fail \
            &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Avisos encontrados (soft-fail)${NC}"
            WARNINGS=$((WARNINGS+1))
        fi

        echo -n "  Checkov Dockerfile... "
        if checkov \
            --file "${PROJECT_ROOT}/apps/sample-app/Dockerfile" \
            --framework dockerfile \
            --compact \
            --quiet \
            --soft-fail \
            &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}Avisos encontrados (soft-fail)${NC}"
            WARNINGS=$((WARNINGS+1))
        fi
    fi
fi

# =============================================================================
# SHELLCHECK — Análise de scripts Bash
# =============================================================================
print_header "ShellCheck — Scripts Bash"

if check_tool "shellcheck" "Instale: apt/brew install shellcheck"; then
    SHELL_SCRIPTS=$(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f 2>/dev/null || true)

    if [[ -z "$SHELL_SCRIPTS" ]]; then
        echo -e "  ${YELLOW}Nenhum script .sh encontrado em scripts/${NC}"
    else
        ALL_OK=true
        while IFS= read -r script; do
            echo -n "  Verificando $(basename "${script}")... "
            if shellcheck --severity=warning "${script}" &>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}FALHOU${NC}"
                shellcheck --severity=warning "${script}" || true
                ALL_OK=false
                ERRORS=$((ERRORS+1))
            fi
        done <<< "$SHELL_SCRIPTS"
    fi
fi

# =============================================================================
# YAMLLINT — Validação de arquivos YAML
# =============================================================================
print_header "YAML Lint"

if check_tool "yamllint" "Instale: pip install yamllint"; then
    YAML_FILES=$(find "${PROJECT_ROOT}/.github" "${PROJECT_ROOT}/apps/sample-app/k8s" \
        -name "*.yml" -o -name "*.yaml" 2>/dev/null | head -50 || true)

    if [[ -z "$YAML_FILES" ]]; then
        echo -e "  ${YELLOW}Nenhum arquivo YAML encontrado${NC}"
    else
        while IFS= read -r yaml_file; do
            rel_path="${yaml_file#"${PROJECT_ROOT}/"}"
            echo -n "  ${rel_path}... "
            if yamllint -d relaxed "${yaml_file}" &>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}Avisos${NC}"
                WARNINGS=$((WARNINGS+1))
            fi
        done <<< "$YAML_FILES"
    fi
fi

# =============================================================================
# DOCKER BUILD — Validação do Dockerfile
# =============================================================================
print_header "Docker Build (Validação)"

if check_tool "docker"; then
    echo -n "  Build da imagem sample-app... "
    if docker build \
        -t "sample-app:validate-local" \
        -f "${PROJECT_ROOT}/apps/sample-app/Dockerfile" \
        "${PROJECT_ROOT}/apps/sample-app" \
        &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        # Remove imagem de validação
        docker rmi "sample-app:validate-local" &>/dev/null || true
    else
        echo -e "${RED}FALHOU${NC}"
        ERRORS=$((ERRORS+1))
    fi
fi

# =============================================================================
# KUBERNETES — Validação dos manifests
# =============================================================================
print_header "Kubernetes — Validação dos Manifests"

if check_tool "kubectl"; then
    K8S_FILES=$(find "${PROJECT_ROOT}/apps/sample-app/k8s" -name "*.yaml" -type f 2>/dev/null || true)

    if [[ -z "$K8S_FILES" ]]; then
        echo -e "  ${YELLOW}Nenhum manifest Kubernetes encontrado${NC}"
    else
        while IFS= read -r manifest; do
            rel_path="${manifest#"${PROJECT_ROOT}/"}"
            echo -n "  ${rel_path}... "
            if kubectl apply --dry-run=client -f "${manifest}" &>/dev/null; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}Aviso (dry-run)${NC}"
                WARNINGS=$((WARNINGS+1))
            fi
        done <<< "$K8S_FILES"
    fi
fi

# =============================================================================
# Sumário Final
# =============================================================================
echo ""
echo -e "${BLUE}══════════════════════════════════════════${NC}"
echo -e "${BLUE}  SUMÁRIO DA VALIDAÇÃO LOCAL${NC}"
echo -e "${BLUE}══════════════════════════════════════════${NC}"
echo ""

if [[ "$ERRORS" -gt 0 ]]; then
    echo -e "  ${RED}Erros:    ${ERRORS}${NC}"
fi

if [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "  ${YELLOW}Avisos:   ${WARNINGS}${NC}"
fi

if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
    echo -e "  ${GREEN}Tudo OK — pronto para commit!${NC}"
elif [[ "$ERRORS" -eq 0 ]]; then
    echo -e "  ${GREEN}OK com avisos — pode prosseguir com commit${NC}"
else
    echo -e ""
    echo -e "  ${RED}Corrija os erros antes de fazer commit${NC}"
    echo ""
    exit 1
fi

echo ""
