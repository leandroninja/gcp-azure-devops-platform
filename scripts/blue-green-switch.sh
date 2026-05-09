#!/usr/bin/env bash
# =============================================================================
# blue-green-switch.sh — Alterna tráfego entre slots blue e green
# =============================================================================
# Uso:
#   ./blue-green-switch.sh \
#     --cluster-type=gke \
#     --namespace=production \
#     --service=sample-app \
#     --new-slot=green
#
# Exit codes:
#   0 — sucesso
#   1 — erro de argumento ou configuração
#   2 — cluster não encontrado ou inacessível
#   3 — health check falhou (rollback necessário)
#   4 — timeout aguardando pods
# =============================================================================

set -euo pipefail

# =============================================================================
# Funções de log estruturado
# =============================================================================
log() {
    local level="$1"
    shift
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [${level}] $*" >&2
}

log_info()    { log "INFO " "$@"; }
log_warn()    { log "WARN " "$@"; }
log_error()   { log "ERROR" "$@"; }
log_success() { log "OK   " "$@"; }

# =============================================================================
# Variáveis padrão
# =============================================================================
CLUSTER_TYPE=""
NAMESPACE="production"
SERVICE_NAME="sample-app"
NEW_SLOT=""
MAX_RETRIES=10
RETRY_INTERVAL=30
ROLLOUT_TIMEOUT=600

# =============================================================================
# Parse de argumentos
# =============================================================================
for arg in "$@"; do
    case "$arg" in
        --cluster-type=*)  CLUSTER_TYPE="${arg#*=}" ;;
        --namespace=*)     NAMESPACE="${arg#*=}"    ;;
        --service=*)       SERVICE_NAME="${arg#*=}" ;;
        --new-slot=*)      NEW_SLOT="${arg#*=}"     ;;
        --max-retries=*)   MAX_RETRIES="${arg#*=}"  ;;
        --help)
            echo "Uso: $0 --cluster-type=<gke|aks> --namespace=<ns> --service=<svc> --new-slot=<blue|green>"
            exit 0
            ;;
        *)
            log_error "Argumento desconhecido: ${arg}"
            exit 1
            ;;
    esac
done

# =============================================================================
# Validações
# =============================================================================
validate_args() {
    local errors=0

    if [[ -z "$CLUSTER_TYPE" ]]; then
        log_error "Parâmetro --cluster-type é obrigatório (gke ou aks)"
        errors=$((errors+1))
    fi

    if [[ ! "$CLUSTER_TYPE" =~ ^(gke|aks|both)$ ]]; then
        log_error "--cluster-type deve ser 'gke', 'aks' ou 'both', mas foi: ${CLUSTER_TYPE}"
        errors=$((errors+1))
    fi

    if [[ -z "$NEW_SLOT" ]]; then
        log_error "Parâmetro --new-slot é obrigatório (blue ou green)"
        errors=$((errors+1))
    fi

    if [[ ! "$NEW_SLOT" =~ ^(blue|green)$ ]]; then
        log_error "--new-slot deve ser 'blue' ou 'green', mas foi: ${NEW_SLOT}"
        errors=$((errors+1))
    fi

    if [[ -z "$NAMESPACE" ]]; then
        log_error "Parâmetro --namespace é obrigatório"
        errors=$((errors+1))
    fi

    if [[ -z "$SERVICE_NAME" ]]; then
        log_error "Parâmetro --service é obrigatório"
        errors=$((errors+1))
    fi

    if [[ "$errors" -gt 0 ]]; then
        log_error "${errors} erro(s) de validação encontrado(s)"
        exit 1
    fi
}

# =============================================================================
# Verifica se kubectl está disponível e o cluster acessível
# =============================================================================
check_cluster_access() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl não encontrado no PATH"
        exit 2
    fi

    log_info "Verificando acesso ao cluster..."
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Não foi possível conectar ao cluster Kubernetes"
        exit 2
    fi
    log_success "Acesso ao cluster confirmado"
}

# =============================================================================
# Detecta o slot atualmente ativo via label do Service
# =============================================================================
get_active_slot() {
    local current_slot
    current_slot=$(kubectl get service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.selector.slot}' 2>/dev/null || echo "unknown")
    echo "$current_slot"
}

# =============================================================================
# Verifica saúde do deployment alvo antes de mudar o tráfego
# =============================================================================
check_deployment_health() {
    local slot="$1"
    local deployment_name="${SERVICE_NAME}-${slot}"

    log_info "Verificando saúde do deployment ${deployment_name}..."

    # Verifica se o deployment existe
    if ! kubectl get deployment "${deployment_name}" -n "${NAMESPACE}" &>/dev/null; then
        log_error "Deployment ${deployment_name} não encontrado no namespace ${NAMESPACE}"
        return 1
    fi

    # Conta réplicas prontas
    local ready_replicas
    local desired_replicas
    ready_replicas=$(kubectl get deployment "${deployment_name}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    desired_replicas=$(kubectl get deployment "${deployment_name}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    ready_replicas="${ready_replicas:-0}"
    desired_replicas="${desired_replicas:-1}"

    log_info "Réplicas prontas: ${ready_replicas}/${desired_replicas}"

    if [[ "$ready_replicas" -lt "$desired_replicas" ]]; then
        log_warn "Deployment ${deployment_name} não está totalmente pronto (${ready_replicas}/${desired_replicas})"
        return 1
    fi

    # Verifica pods em CrashLoopBackOff
    local crash_count
    crash_count=$(kubectl get pods \
        -l "app=${SERVICE_NAME},slot=${slot}" \
        -n "${NAMESPACE}" \
        --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || echo "0")

    if [[ "$crash_count" -gt 0 ]]; then
        log_error "${crash_count} pod(s) em CrashLoopBackOff no slot ${slot}"
        return 1
    fi

    log_success "Deployment ${deployment_name} está saudável"
    return 0
}

# =============================================================================
# Aguarda o deployment estar completamente disponível (com retentativas)
# =============================================================================
wait_for_deployment() {
    local slot="$1"
    local deployment_name="${SERVICE_NAME}-${slot}"

    log_info "Aguardando rollout completo do deployment ${deployment_name}..."
    kubectl rollout status deployment/"${deployment_name}" \
        -n "${NAMESPACE}" \
        --timeout="${ROLLOUT_TIMEOUT}s" || {
        log_error "Timeout aguardando rollout do deployment ${deployment_name}"
        exit 4
    }
    log_success "Rollout de ${deployment_name} concluído"
}

# =============================================================================
# Executa o switch do selector do Service
# =============================================================================
switch_service_selector() {
    local new_slot="$1"
    local deployment_name="${SERVICE_NAME}-${new_slot}"

    log_info "Atualizando selector do Service ${SERVICE_NAME} para slot ${new_slot}..."

    # Patch atômico no selector do Service
    kubectl patch service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        --type=json \
        -p="[{\"op\": \"replace\", \"path\": \"/spec/selector/slot\", \"value\": \"${new_slot}\"}]"

    # Atualiza anotações do Service para rastreamento
    kubectl annotate service "${SERVICE_NAME}" \
        -n "${NAMESPACE}" \
        "active-slot=${new_slot}" \
        "last-switch-timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --overwrite

    log_success "Selector do Service atualizado para slot ${new_slot}"
}

# =============================================================================
# Verifica conectividade pós-switch via port-forward
# =============================================================================
verify_post_switch() {
    local new_slot="$1"
    local retries=0
    local success=false

    log_info "Verificando conectividade pós-switch no slot ${new_slot}..."

    # Port-forward temporário para verificação
    kubectl port-forward \
        "service/${SERVICE_NAME}" \
        18080:80 \
        -n "${NAMESPACE}" &>/dev/null &
    local pf_pid=$!
    sleep 3

    while [[ "$retries" -lt "$MAX_RETRIES" ]]; do
        retries=$((retries+1))
        log_info "Health check tentativa ${retries}/${MAX_RETRIES}..."

        local response
        response=$(curl -sf --max-time 5 "http://localhost:18080/health" 2>/dev/null || echo "FALHA")

        if echo "$response" | grep -q '"status":"ok"'; then
            local serving_slot
            serving_slot=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('slot','unknown'))" 2>/dev/null || echo "unknown")

            if [[ "$serving_slot" == "$new_slot" ]]; then
                log_success "Slot ${new_slot} está respondendo corretamente"
                success=true
                break
            else
                log_warn "Health check OK mas slot inesperado: esperado=${new_slot}, recebido=${serving_slot}"
            fi
        else
            log_warn "Health check falhou (tentativa ${retries}/${MAX_RETRIES})"
        fi

        sleep "${RETRY_INTERVAL}"
    done

    kill "$pf_pid" 2>/dev/null || true

    if [[ "$success" != "true" ]]; then
        log_error "Health check falhou após ${MAX_RETRIES} tentativas"
        return 3
    fi

    return 0
}

# =============================================================================
# Exibe resumo do switch
# =============================================================================
print_summary() {
    local previous_slot="$1"
    local new_slot="$2"

    echo ""
    echo "============================================================"
    echo "  SWITCH BLUE-GREEN CONCLUÍDO"
    echo "============================================================"
    echo "  Cluster:   ${CLUSTER_TYPE}"
    echo "  Namespace: ${NAMESPACE}"
    echo "  Service:   ${SERVICE_NAME}"
    echo "  Anterior:  ${previous_slot}"
    echo "  Novo:      ${new_slot}"
    echo "  Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "============================================================"
    echo ""
}

# =============================================================================
# FLUXO PRINCIPAL
# =============================================================================
main() {
    log_info "=== Iniciando Blue-Green Switch ==="
    log_info "Cluster: ${CLUSTER_TYPE} | Namespace: ${NAMESPACE} | Service: ${SERVICE_NAME} | Novo slot: ${NEW_SLOT}"

    validate_args
    check_cluster_access

    # Detecta slot atual
    local current_slot
    current_slot=$(get_active_slot)
    log_info "Slot atualmente ativo: ${current_slot}"

    # Verifica se já está no slot desejado
    if [[ "$current_slot" == "$NEW_SLOT" ]]; then
        log_warn "O slot ${NEW_SLOT} já está ativo — nenhuma ação necessária"
        exit 0
    fi

    # Garante que o deployment destino está pronto
    wait_for_deployment "$NEW_SLOT"

    # Health check antes do switch
    local retry=0
    while ! check_deployment_health "$NEW_SLOT"; do
        retry=$((retry+1))
        if [[ "$retry" -ge "$MAX_RETRIES" ]]; then
            log_error "Deployment do slot ${NEW_SLOT} não está saudável após ${MAX_RETRIES} tentativas"
            log_error "Switch ABORTADO — produção continua no slot ${current_slot}"
            exit 3
        fi
        log_warn "Aguardando ${RETRY_INTERVAL}s antes da próxima tentativa (${retry}/${MAX_RETRIES})..."
        sleep "${RETRY_INTERVAL}"
    done

    # Executa o switch
    switch_service_selector "$NEW_SLOT"

    # Aguarda alguns segundos para o switch propagar
    log_info "Aguardando 10s para propagação do switch..."
    sleep 10

    # Verifica saúde pós-switch
    if ! verify_post_switch "$NEW_SLOT"; then
        log_error "Verificação pós-switch falhou! Revertendo para slot ${current_slot}..."
        switch_service_selector "$current_slot"
        log_error "ROLLBACK executado — tráfego revertido para slot ${current_slot}"
        exit 3
    fi

    print_summary "$current_slot" "$NEW_SLOT"
    log_success "Switch blue-green concluído com sucesso!"
}

main "$@"
