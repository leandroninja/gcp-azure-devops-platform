#!/usr/bin/env bash
# rollback de deploy — reverte para a versao anterior no ambiente alvo
# uso: ./rollback.sh <ambiente> <versao-anterior>
# ex:  ./rollback.sh production v1.2.3

set -euo pipefail

ENVIRONMENT="${1:-}"
PREVIOUS_VERSION="${2:-}"
NAMESPACE="${NAMESPACE:-default}"

if [[ -z "$ENVIRONMENT" || -z "$PREVIOUS_VERSION" ]]; then
  echo "uso: $0 <ambiente> <versao-anterior>"
  echo "  ex: $0 production v1.2.3"
  exit 1
fi

echo "=== Rollback para ${PREVIOUS_VERSION} no ambiente ${ENVIRONMENT} ==="

# verifica se a versao anterior existe no registry
if [[ "$ENVIRONMENT" == "gcp"* ]]; then
  echo "Revertendo no GKE..."
  kubectl rollout undo deployment/sample-app -n "$NAMESPACE"
  kubectl rollout status deployment/sample-app -n "$NAMESPACE" --timeout=5m
elif [[ "$ENVIRONMENT" == "azure"* ]]; then
  echo "Revertendo no AKS..."
  kubectl rollout undo deployment/sample-app -n "$NAMESPACE"
  kubectl rollout status deployment/sample-app -n "$NAMESPACE" --timeout=5m
else
  echo "Erro: ambiente desconhecido '$ENVIRONMENT'. Use 'gcp' ou 'azure'." >&2
  exit 1
fi

echo "Rollback concluido com sucesso para ${PREVIOUS_VERSION}"
