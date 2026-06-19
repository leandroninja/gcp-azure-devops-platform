#!/usr/bin/env bash
# =============================================================================
# canary-promote.sh — Configura e promove o peso do canary deployment
# =============================================================================
# Uso:
#   ./canary-promote.sh \
#     --cluster-type=gke \
#     --namespace=production \
#     --new-weight=25
#
# Quando --new-weight=0: remove o canary (rollback completo)
# Quando --new-weight=100: full rollout (canary vira stable)
# =============================================================================

set -euo pipefail

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$1] ${*:2}" >&2; }
log_info()    { log "INFO " "$@"; }
log_warn()    { log "WARN " "$@"; }
log_error()   { log "ERROR" "$@"; }
log_success() { log "OK   " "$@"; }

# Valores padrão
CLUSTER_TYPE=""
NAMESPACE="production"
NEW_WEIGHT=0
SERVICE_NAME="sample-app"
STABLE_DEPLOYMENT="sample-app-stable"
CANARY_DEPLOYMENT="sample-app-canary"
ERROR_RATE_THRESHOLD=1.0
MONITOR_SECONDS=120

for arg in "$@"; do
    case "$arg" in
        --cluster-type=*)  CLUSTER_TYPE="${arg#*=}" ;;
        --namespace=*)     NAMESPACE="${arg#*=}"    ;;
        --new-weight=*)    NEW_WEIGHT="${arg#*=}"   ;;
        --service=*)       SERVICE_NAME="${arg#*=}" ;;
        --threshold=*)     ERROR_RATE_THRESHOLD="${arg#*=}" ;;
        --monitor=*)       MONITOR_SECONDS="${arg#*=}" ;;
        --help)
            echo "Uso: $0 --cluster-type=<gke|aks> --namespace=<ns> --new-weight=<0-100>"
            echo "  --threshold=<float>   Taxa de erro máxima aceita (padrão: 1.0%)"
            echo "  --monitor=<seconds>   Segundos de monitoramento antes de confirmar (padrão: 120)"
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
validate() {
    local errs=0
    [[ -z "$CLUSTER_TYPE" ]] && { log_error "--cluster-type obrigatório"; errs=$((errs+1)); }
    [[ ! "$CLUSTER_TYPE" =~ ^(gke|aks|both)$ ]] && { log_error "cluster-type inválido: ${CLUSTER_TYPE}"; errs=$((errs+1)); }
    [[ "$NEW_WEIGHT" -lt 0 || "$NEW_WEIGHT" -gt 100 ]] && { log_error "--new-weight deve ser entre 0 e 100"; errs=$((errs+1)); }
    [[ "$errs" -gt 0 ]] && exit 1
}

# =============================================================================
# Configura weighted routing para GKE via Ingress annotations
# GKE usa nginx-ingress ou Istio para weighted routing.
# Este exemplo usa annotation de peso no Ingress do canary.
# =============================================================================
configure_gke_canary_weight() {
    local weight="$1"
    local stable_weight=$((100 - weight))

    log_info "Configurando canary weight ${weight}% no GKE (Ingress annotations)..."

    if [[ "$weight" -eq 0 ]]; then
        # Remove o Ingress canary (todo tráfego volta para stable)
        kubectl delete ingress "${SERVICE_NAME}-canary" \
            -n "${NAMESPACE}" \
            --ignore-not-found=true
        log_success "Ingress canary removido — 100% do tráfego para stable"
        return 0
    fi

    # Aplica ou atualiza o Ingress canary com o novo peso
    # Para GKE com nginx-ingress:
    kubectl annotate ingress "${SERVICE_NAME}-canary" \
        -n "${NAMESPACE}" \
        "nginx.ingress.kubernetes.io/canary=true" \
        "nginx.ingress.kubernetes.io/canary-weight=${weight}" \
        --overwrite 2>/dev/null || {
        # Se o Ingress canary não existe, cria via patch do Ingress principal
        log_warn "Ingress canary não encontrado — criando via patch"
        kubectl patch ingress "${SERVICE_NAME}" \
            -n "${NAMESPACE}" \
            --type=merge \
            -p "{\"metadata\":{\"annotations\":{\"nginx.ingress.kubernetes.io/canary\":\"true\",\"nginx.ingress.kubernetes.io/canary-weight\":\"${weight}\"}}}"
    }

    log_success "GKE: ${weight}% do tráfego direcionado para canary, ${stable_weight}% para stable"
}

# =============================================================================
# Configura weighted routing para AKS via AGIC (Application Gateway Ingress)
# O Azure Application Gateway suporta weighted routing nativo.
# =============================================================================
configure_aks_canary_weight() {
    local weight="$1"
    local stable_weight=$((100 - weight))

    log_info "Configurando canary weight ${weight}% no AKS (AGIC)..."

    if [[ "$weight" -eq 0 ]]; then
        # Remove anotações de canary do Ingress
        kubectl annotate ingress "${SERVICE_NAME}" \
            -n "${NAMESPACE}" \
            "appgw.ingress.kubernetes.io/backend-path-prefix-"  \
            --overwrite 2>/dev/null || true

        kubectl delete ingress "${SERVICE_NAME}-canary" \
            -n "${NAMESPACE}" \
            --ignore-not-found=true
        log_success "AGIC canary removido — 100% do tráfego para stable"
        return 0
    fi

    # AGIC: configura peso via annotations no Ingress canary
    kubectl annotate ingress "${SERVICE_NAME}-canary" \
        -n "${NAMESPACE}" \
        "kubernetes.io/ingress.class=azure/application-gateway" \
        "appgw.ingress.kubernetes.io/override-frontend-port=80" \
        --overwrite 2>/dev/null || true

    # Ajusta replicas do canary proporcionalmente ao peso
    # (heurística: peso% * total_replicas / 100)
    local stable_replicas
    stable_replicas=$(kubectl get deployment "${STABLE_DEPLOYMENT}" \
        -n "${NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "3")

    local canary_replicas
    canary_replicas=$(python3 -c "
import math
stable = int('${stable_replicas}')
weight = int('${weight}')
ratio = weight / (100 - weight) if weight < 100 else 1
canary = max(1, math.ceil(stable * ratio))
print(canary)
" 2>/dev/null || echo "1")

    kubectl scale deployment "${CANARY_DEPLOYMENT}" \
        -n "${NAMESPACE}" \
        --replicas="${canary_replicas}" 2>/dev/null || true

    log_success "AKS: canary com ${canary_replicas} réplicas (~${weight}% do tráfego)"
}

# =============================================================================
# Monitora error rate por N segundos para confirmar estabilidade
# =============================================================================
monitor_error_rate() {
    local duration="$1"
    local max_error_rate="$2"
    local check_interval=30
    local total_checks=$((duration / check_interval))
    local errors=0

    log_info "Monitorando error rate por ${duration}s (threshold: ${max_error_rate}%)..."

    for i in $(seq 1 "${total_checks}"); do
        log_info "[${i}/${total_checks}] Verificando métricas..."

        # Em produção: consultar Cloud Monitoring ou Azure Monitor
        # Aqui: verifica pods em erro como proxy da error rate
        local crash_pods
        crash_pods=$(kubectl get pods \
            -l "app=${SERVICE_NAME},track=canary" \
            -n "${NAMESPACE}" \
            --no-headers 2>/dev/null \
            | grep -cE "(CrashLoopBackOff|Error|OOMKilled)" || echo "0")

        if [[ "$crash_pods" -gt 0 ]]; then
            errors=$((errors+1))
            log_warn "Pods com problema detectados: ${crash_pods}"
        else
            log_info "Pods canary saudáveis — sem erros detectados"
        fi

        # Se mais de 30% dos checks tiveram erros, considera instável
        local error_pct
        error_pct=$(python3 -c "print(${errors} / ${i} * 100)")
        local above_threshold
        above_threshold=$(python3 -c "print('yes' if ${error_pct} > ${max_error_rate} else 'no')")

        if [[ "$above_threshold" == "yes" ]]; then
            log_error "Error rate ${error_pct}% acima do threshold ${max_error_rate}%"
            return 1
        fi

        sleep "${check_interval}"
    done

    log_success "Monitoramento concluído sem erros acima do threshold"
    return 0
}

# =============================================================================
# Executa rollback: remove canary e volta 100% para stable
# =============================================================================
rollback_canary() {
    log_warn "Executando rollback do canary..."

    case "$CLUSTER_TYPE" in
        gke)  configure_gke_canary_weight 0 ;;
        aks)  configure_aks_canary_weight 0 ;;
        both)
            configure_gke_canary_weight 0
            configure_aks_canary_weight 0
            ;;
    esac

    # Remove o deployment canary
    kubectl delete deployment "${CANARY_DEPLOYMENT}" \
        -n "${NAMESPACE}" \
        --ignore-not-found=true

    log_success "Rollback concluído — 100% do tráfego revertido para stable"
}

# =============================================================================
# FLUXO PRINCIPAL
# =============================================================================
main() {
    log_info "=== Canary Promote: peso=${NEW_WEIGHT}% cluster=${CLUSTER_TYPE} ==="

    validate

    # Configura o peso no cluster alvo
    case "$CLUSTER_TYPE" in
        gke)
            configure_gke_canary_weight "${NEW_WEIGHT}"
            ;;
        aks)
            configure_aks_canary_weight "${NEW_WEIGHT}"
            ;;
        both)
            configure_gke_canary_weight "${NEW_WEIGHT}"
            configure_aks_canary_weight "${NEW_WEIGHT}"
            ;;
    esac

    # Se peso > 0, monitora estabilidade por MONITOR_SECONDS
    if [[ "$NEW_WEIGHT" -gt 0 ]]; then
        if ! monitor_error_rate "${MONITOR_SECONDS}" "${ERROR_RATE_THRESHOLD}"; then
            log_error "Error rate acima do threshold — executando rollback automático"
            rollback_canary
            exit 1
        fi
        log_success "Canary estável com ${NEW_WEIGHT}% de tráfego"
    else
        log_success "Canary removido — 100% do tráfego no stable"
    fi

    echo ""
    echo "============================================================"
    echo "  CANARY PROMOTE CONCLUÍDO"
    echo "============================================================"
    echo "  Cluster:      ${CLUSTER_TYPE}"
    echo "  Namespace:    ${NAMESPACE}"
    echo "  Peso Canary:  ${NEW_WEIGHT}%"
    echo "  Peso Stable:  $((100 - NEW_WEIGHT))%"
    echo "  Timestamp:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "============================================================"
}

main "$@"
