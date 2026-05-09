# Runbook — Blue-Green Deployment

**Versão:** 1.0  
**Última atualização:** 2026-05-09  
**Time responsável:** Plataforma / DevOps  
**Tempo estimado de execução:** 10–20 minutos  
**Impacto no usuário:** Zero downtime (quando executado corretamente)

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Pré-requisitos](#pré-requisitos)
3. [Verificar Qual Slot Está Ativo](#verificar-qual-slot-está-ativo)
4. [Deploy via GitHub Actions](#deploy-via-github-actions)
5. [Deploy Manual (passo a passo)](#deploy-manual-passo-a-passo)
6. [Verificar Saúde Após o Switch](#verificar-saúde-após-o-switch)
7. [Como Fazer Rollback](#como-fazer-rollback)
8. [Troubleshooting Comum](#troubleshooting-comum)
9. [Referências](#referências)

---

## Visão Geral

A estratégia blue-green mantém dois ambientes de produção idênticos chamados **slot blue** e **slot green**. Em qualquer momento, apenas um slot recebe tráfego real dos usuários (o slot "ativo"). O outro slot (o "inativo") fica disponível para receber o novo deployment.

```
                     ┌─────────────────────────────────────┐
                     │         Load Balancer / Ingress      │
                     │          (100% do tráfego)           │
                     └─────────────┬───────────────────────┘
                                   │
                      ┌────────────▼────────────┐
                      │   Service Kubernetes     │
                      │  selector: slot=ATIVO    │
                      └────────────┬────────────┘
                                   │
               ┌───────────────────┴───────────────────┐
               │                                       │
   ┌───────────▼───────────┐             ┌─────────────▼─────────┐
   │   Deployment Blue     │             │   Deployment Green     │
   │  (slot=blue)          │             │  (slot=green)          │
   │  ● ATIVO (recebe      │             │  ○ INATIVO (recebe     │
   │    tráfego real)      │             │    deploy da versão    │
   │  v1.2.3               │             │    nova v1.3.0)        │
   └───────────────────────┘             └───────────────────────┘
```

**Fluxo de deploy:**
1. Nova versão é deployada no slot **inativo** (sem impacto nos usuários)
2. Health checks validam o slot inativo
3. O Service é atualizado para apontar para o slot com a nova versão
4. O slot anterior fica em standby (disponível para rollback imediato)

**Vantagem principal:** rollback leva menos de 30 segundos — basta mudar o seletor do Service de volta.

---

## Pré-requisitos

### Ferramentas necessárias

| Ferramenta | Versão mínima | Como instalar |
|------------|---------------|---------------|
| `kubectl`  | 1.28+         | `gcloud components install kubectl` ou `az aks install-cli` |
| `curl`     | 7.68+         | Geralmente já instalado |
| `jq`       | 1.6+          | `apt install jq` / `brew install jq` |
| `bash`     | 4.0+          | Padrão na maioria dos sistemas |

### Acesso ao cluster

**GKE:**
```bash
# Autenticar no GCP
gcloud auth login

# Obter credenciais do cluster
gcloud container clusters get-credentials NOME_DO_CLUSTER \
  --region us-central1 \
  --project ID_DO_PROJETO
```

**AKS:**
```bash
# Autenticar no Azure
az login

# Obter credenciais do cluster
az aks get-credentials \
  --resource-group rg-devops-platform \
  --name NOME_DO_CLUSTER
```

### Verificar permissões mínimas

```bash
# Verifica se você tem permissão para patch em Services
kubectl auth can-i patch services -n production

# Verifica se você tem permissão para set image em Deployments
kubectl auth can-i patch deployments -n production

# Resultado esperado: yes
```

---

## Verificar Qual Slot Está Ativo

### Método 1 — Via seletor do Service (mais confiável)

```bash
# Exibe o slot atualmente ativo
kubectl get service sample-app \
  -n production \
  -o jsonpath='{.spec.selector.slot}' && echo

# Saída esperada: blue  (ou green)
```

### Método 2 — Via anotação do Service

```bash
# Exibe histórico do último switch
kubectl get service sample-app \
  -n production \
  -o jsonpath='{.metadata.annotations}' | jq .

# Saída esperada:
# {
#   "active-slot": "blue",
#   "last-switch-timestamp": "2026-05-09T14:30:00Z"
# }
```

### Método 3 — Via pods ativos

```bash
# Lista pods com seus slots e versões de imagem
kubectl get pods -n production \
  -l app=sample-app \
  -o custom-columns='NOME:.metadata.name,SLOT:.metadata.labels.slot,IMAGEM:.spec.containers[0].image,STATUS:.status.phase'
```

### Script de status rápido

```bash
# Exibe status completo de ambos os slots
for SLOT in blue green; do
  echo "=== Slot: ${SLOT} ==="
  kubectl get deployment "sample-app-${SLOT}" \
    -n production \
    -o custom-columns='DEPLOYMENT:.metadata.name,DESEJADO:.spec.replicas,PRONTO:.status.readyReplicas,IMAGEM:.spec.template.spec.containers[0].image' \
    2>/dev/null || echo "Deployment não encontrado"
done

echo ""
echo "=== Slot Ativo ==="
kubectl get service sample-app -n production \
  -o jsonpath='Ativo: {.spec.selector.slot}{"\n"}'
```

---

## Deploy via GitHub Actions

Esta é a forma **recomendada** para deploys em produção, pois garante:
- Auditoria completa de quem aprovou e quando
- Health checks automáticos
- Rollback automático em caso de falha
- Notificações de status

### Passos

1. **Merge na branch `main`** (ou crie um workflow dispatch manual)

2. **Acompanhe o workflow:**
   ```
   GitHub → Actions → Deploy Blue-Green → Último run
   ```

3. **Se o ambiente for `production`:** aguarde a aprovação do revisor designado  
   (ver configuração em `.github/environments/production.yml`)

4. **O workflow executa automaticamente:**
   - Detecta o slot inativo
   - Faz `kubectl set image` no slot inativo
   - Aguarda o rollout completar
   - Chama `scripts/blue-green-switch.sh` para trocar o tráfego
   - Executa health check por até 10 minutos
   - Faz rollback automático se o health check falhar

5. **Verifique o resultado** no summary do workflow e no comentário do PR

---

## Deploy Manual (Passo a Passo)

Use este procedimento **apenas em emergências** onde o pipeline de CI/CD não está disponível.

### Etapa 1 — Identificar o slot inativo

```bash
ACTIVE_SLOT=$(kubectl get service sample-app \
  -n production \
  -o jsonpath='{.spec.selector.slot}')

if [[ "$ACTIVE_SLOT" == "blue" ]]; then
  TARGET_SLOT="green"
else
  TARGET_SLOT="blue"
fi

echo "Slot ativo: ${ACTIVE_SLOT}"
echo "Slot para deploy: ${TARGET_SLOT}"
```

### Etapa 2 — Atualizar a imagem no slot inativo

```bash
NOVA_IMAGEM="us-central1-docker.pkg.dev/meu-projeto/repo/sample-app:SHA_DO_COMMIT"

kubectl set image deployment/sample-app-${TARGET_SLOT} \
  sample-app=${NOVA_IMAGEM} \
  -n production

echo "Imagem atualizada no slot ${TARGET_SLOT}: ${NOVA_IMAGEM}"
```

### Etapa 3 — Aguardar o rollout completar

```bash
kubectl rollout status deployment/sample-app-${TARGET_SLOT} \
  -n production \
  --timeout=600s
```

### Etapa 4 — Verificar saúde do slot inativo antes do switch

```bash
# Verifica réplicas
kubectl get deployment sample-app-${TARGET_SLOT} \
  -n production \
  -o wide

# Verifica logs dos pods (busca por erros)
kubectl logs \
  -l "app=sample-app,slot=${TARGET_SLOT}" \
  -n production \
  --tail=50 \
  | grep -iE "(error|exception|fatal|panic)" | head -20

echo "Se não apareceu nenhum erro, prossiga para o switch"
```

### Etapa 5 — Executar o switch de tráfego

```bash
chmod +x scripts/blue-green-switch.sh

./scripts/blue-green-switch.sh \
  --cluster-type=gke \           # ou aks
  --namespace=production \
  --service=sample-app \
  --new-slot=${TARGET_SLOT}
```

**O script automaticamente:**
- Valida a saúde do slot destino
- Executa o patch atômico no Service
- Verifica conectividade pós-switch via port-forward
- Faz rollback automático se o health check falhar

### Etapa 6 — Confirmar o switch

```bash
# Confirma que o Service está apontando para o slot correto
kubectl get service sample-app -n production \
  -o jsonpath='Slot ativo: {.spec.selector.slot}{"\n"}'

# Confirma que os pods corretos estão recebendo tráfego
kubectl get endpoints sample-app -n production -o wide
```

---

## Verificar Saúde Após o Switch

### Health check via endpoint HTTP

```bash
# Via port-forward temporário
kubectl port-forward service/sample-app 18080:80 -n production &
PF_PID=$!
sleep 3

curl -sf http://localhost:18080/health | jq .

# Resultado esperado:
# {
#   "status": "ok",
#   "slot": "green",   <-- deve ser o slot que acabou de receber o deploy
#   "version": "1.3.0",
#   "timestamp": "2026-05-09T14:35:00Z"
# }

kill $PF_PID
```

### Verificar métricas de erro no Grafana

1. Acesse o Grafana em `https://grafana.devops-platform.interno`
2. Abra o dashboard **"Application Health — Blue-Green"**
3. Verifique as métricas por 5–10 minutos após o switch:
   - **Taxa de erro HTTP** deve permanecer abaixo de 0,1%
   - **Latência p99** não deve aumentar mais de 20% em relação à baseline
   - **Throughput** deve estar estável

### Verificar logs em tempo real

```bash
# Acompanha logs do slot recém-ativado
kubectl logs \
  -l "app=sample-app,slot=${TARGET_SLOT}" \
  -n production \
  -f \
  --tail=100
```

---

## Como Fazer Rollback

### Rollback imediato (menos de 30 segundos)

```bash
# Identifica o slot anterior (o que estava ativo antes do deploy)
CURRENT_SLOT=$(kubectl get service sample-app \
  -n production \
  -o jsonpath='{.spec.selector.slot}')

if [[ "$CURRENT_SLOT" == "blue" ]]; then
  ROLLBACK_SLOT="green"
else
  ROLLBACK_SLOT="blue"
fi

echo "Revertendo para slot: ${ROLLBACK_SLOT}"

# Executa o rollback via script
./scripts/blue-green-switch.sh \
  --cluster-type=gke \
  --namespace=production \
  --service=sample-app \
  --new-slot=${ROLLBACK_SLOT}
```

### Rollback manual direto (sem script — para emergências críticas)

```bash
# Identifica o slot de rollback
ROLLBACK_SLOT="blue"   # ou green — o slot que estava ativo antes

# Patch direto no Service — operação atômica, menos de 1 segundo
kubectl patch service sample-app \
  -n production \
  --type=json \
  -p="[{\"op\": \"replace\", \"path\": \"/spec/selector/slot\", \"value\": \"${ROLLBACK_SLOT}\"}]"

# Confirma o rollback
kubectl get service sample-app \
  -n production \
  -o jsonpath='Rollback aplicado. Slot ativo: {.spec.selector.slot}{"\n"}'
```

### Verificar saúde após rollback

```bash
# Aguarda 30 segundos para propagação
sleep 30

# Verifica saúde
kubectl get pods -l "app=sample-app,slot=${ROLLBACK_SLOT}" -n production

# Verifica endpoint de saúde
kubectl port-forward service/sample-app 18080:80 -n production &
sleep 3
curl -s http://localhost:18080/health | jq '{status,slot,version}'
kill %1
```

---

## Troubleshooting Comum

### Problema: Script retorna "Deployment não encontrado"

**Sintoma:** `blue-green-switch.sh` falha com erro sobre deployment não existir

**Causa provável:** O deployment do slot inativo foi deletado ou o nome está incorreto

**Solução:**
```bash
# Lista todos os deployments no namespace
kubectl get deployments -n production -l app=sample-app

# Verifica se os dois slots existem
kubectl get deployment sample-app-blue -n production
kubectl get deployment sample-app-green -n production

# Se um dos deployments não existir, recriar a partir do outro
kubectl get deployment sample-app-blue -n production -o yaml | \
  sed 's/name: sample-app-blue/name: sample-app-green/' | \
  sed 's/slot: blue/slot: green/' | \
  kubectl apply -f -
```

---

### Problema: Health check falha após o switch

**Sintoma:** `verify_post_switch` retorna "Health check falhou após N tentativas"

**Causa provável 1:** Pods ainda inicializando (liveness probe não passou)

**Solução:**
```bash
# Verifica eventos dos pods
kubectl describe pods -l "app=sample-app,slot=green" -n production | grep -A5 Events

# Verifica se há falhas de readiness probe
kubectl get events -n production --sort-by='.lastTimestamp' | grep -i "readiness\|liveness"
```

**Causa provável 2:** Variáveis de ambiente ou secrets ausentes no slot de destino

**Solução:**
```bash
# Compara as env vars entre os dois slots
kubectl get deployment sample-app-blue -n production -o jsonpath='{.spec.template.spec.containers[0].env}' | jq .
kubectl get deployment sample-app-green -n production -o jsonpath='{.spec.template.spec.containers[0].env}' | jq .
```

---

### Problema: Pods em CrashLoopBackOff após switch

**Sintoma:** Pods ficam reiniciando continuamente

**Ação imediata:** Execute o rollback antes de investigar
```bash
./scripts/blue-green-switch.sh \
  --cluster-type=gke \
  --namespace=production \
  --service=sample-app \
  --new-slot=blue   # voltando para o slot seguro
```

**Investigação:**
```bash
# Logs do pod que crashou
kubectl logs \
  -l "app=sample-app,slot=green" \
  -n production \
  --previous \
  --tail=100

# Eventos do pod
kubectl describe pod \
  $(kubectl get pod -l "app=sample-app,slot=green" -n production -o name | head -1) \
  -n production
```

---

### Problema: Service não atualiza o seletor

**Sintoma:** O patch do Service retorna erro de permissão

**Solução:**
```bash
# Verifica permissões da sua conta
kubectl auth can-i patch services -n production

# Se não tiver permissão, solicite ao time de ops ou use o pipeline de CI/CD
# que usa a Service Account correta
```

---

### Problema: Tráfego ainda vai para o slot antigo após o switch

**Sintoma:** Health check retorna slot errado mesmo após patch do Service

**Causa provável:** Cache do DNS interno ou do kube-proxy ainda está propagando

**Solução:**
```bash
# Aguarda a propagação (geralmente 30–60 segundos)
sleep 60

# Verifica os endpoints ativos do Service
kubectl get endpoints sample-app -n production -o wide

# Força nova resolução verificando os pods alvo
kubectl describe endpoints sample-app -n production | grep Addresses
```

---

## Referências

- **Script:** `/scripts/blue-green-switch.sh` — código-fonte completo com comentários
- **Workflow:** `.github/workflows/deploy-blue-green.yml` — pipeline de deploy automatizado
- **Workflow reutilizável:** `.github/workflows/reusable-deploy-k8s.yml`
- **Runbook canary:** `docs/runbooks/canary-deployment.md`
- **Arquitetura:** `docs/architecture/multi-cloud-design.md`
- **Documentação Kubernetes:** https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
