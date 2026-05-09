# Runbook — Canary Deployment

**Versão:** 1.0  
**Última atualização:** 2026-05-09  
**Time responsável:** Plataforma / DevOps  
**Tempo total estimado:** 2–4 horas (deploy completo com todos os estágios)  
**Impacto no usuário:** Mínimo — apenas uma fração do tráfego recebe a nova versão a cada estágio

---

## Índice

1. [Visão Geral](#visão-geral)
2. [Estratégia de Pesos Recomendados](#estratégia-de-pesos-recomendados)
3. [Pré-requisitos](#pré-requisitos)
4. [Deploy Canary via GitHub Actions](#deploy-canary-via-github-actions)
5. [Deploy Canary Manual](#deploy-canary-manual)
6. [Métricas a Monitorar](#métricas-a-monitorar)
7. [Critérios de Promoção](#critérios-de-promoção)
8. [Critérios de Rollback](#critérios-de-rollback)
9. [Comandos Úteis](#comandos-úteis)
10. [Troubleshooting](#troubleshooting)

---

## Visão Geral

Na estratégia canary, a nova versão é exposta a uma pequena porcentagem do tráfego real enquanto a versão estável continua atendendo a maioria dos usuários. O tráfego é incrementado progressivamente conforme a versão canary demonstra estabilidade.

```
  Usuários (100%)
        │
        ▼
  ┌─────────────────────────────────────────────┐
  │            Ingress / Load Balancer           │
  │         (weighted routing via annotations)   │
  └────────────────┬─────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
   95% do tráfego        5% do tráfego
        │                     │
        ▼                     ▼
  ┌───────────────┐    ┌─────────────────┐
  │  Deployment   │    │   Deployment    │
  │   Stable      │    │    Canary       │
  │  (v1.2.3)     │    │   (v1.3.0)      │
  │  3 réplicas   │    │   1 réplica     │
  └───────────────┘    └─────────────────┘
```

**Quando usar canary vs blue-green:**

| Critério | Canary | Blue-Green |
|----------|--------|------------|
| Mudanças de alto risco | Ideal | Alternativa |
| Mudanças rápidas e simples | Overkill | Ideal |
| Precisa de dados reais de usuários | Sim | Não |
| Tempo disponível para deploy | 2–4 horas | 15–30 minutos |
| Rollback necessário às vezes | Gradual | Instantâneo |

---

## Estratégia de Pesos Recomendados

O progresso canary segue uma escala logarítmica para minimizar o impacto de possíveis problemas:

```
  Tempo     │  Peso Canary  │  Peso Stable  │  Duração do estágio
  ──────────┼───────────────┼───────────────┼─────────────────────
  Estágio 1 │      5%       │      95%      │  30 minutos
  Estágio 2 │     10%       │      90%      │  30 minutos
  Estágio 3 │     25%       │      75%      │  30 minutos
  Estágio 4 │     50%       │      50%      │  30 minutos
  Estágio 5 │    100%       │       0%      │  (promoção completa)
```

**Regra de parada:** Se qualquer métrica definida nos critérios de rollback for violada em **qualquer estágio**, reverter imediatamente para 0% canary (rollback completo).

**Promoção completa (100%):** Quando o canary chega a 100%, o deployment stable é atualizado para a nova versão e o deployment canary é removido. A partir desse momento, todos os usuários recebem a nova versão.

---

## Pré-requisitos

### Ferramentas

```bash
# Verificar se kubectl está configurado para o cluster correto
kubectl config current-context

# Verificar acesso ao namespace
kubectl auth can-i patch ingresses -n production
kubectl auth can-i scale deployments -n production
```

### Verificar estado inicial antes do canary

```bash
# O deployment stable deve estar saudável
kubectl get deployment sample-app-stable -n production
# READY deve ser igual a DESIRED

# O deployment canary NÃO deve existir antes de iniciar
kubectl get deployment sample-app-canary -n production 2>/dev/null && \
  echo "ATENÇÃO: Canary já existe! Verifique se há um deploy em andamento." || \
  echo "OK: Nenhum canary ativo"

# Peso atual deve ser 0 (nenhum tráfego canary)
kubectl get ingress sample-app-canary -n production \
  -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}' \
  2>/dev/null && echo "" || echo "OK: Nenhum ingress canary ativo"
```

---

## Deploy Canary via GitHub Actions

Esta é a forma **recomendada**. O workflow `deploy-canary.yml` implementa todos os estágios automaticamente com monitoramento entre cada um.

### Configurar os inputs do workflow

No arquivo `.github/workflows/deploy-canary.yml`, os parâmetros de canary_weight controlam o peso inicial. Para um deploy completo de todos os estágios, o workflow é chamado sequencialmente para cada peso.

### Disparar o workflow

```bash
# Via GitHub CLI — disparo manual com peso inicial de 5%
gh workflow run deploy-canary.yml \
  --field image_tag=sha-abc1234 \
  --field canary_weight=10 \
  --field namespace=production \
  --field cluster_type=gke

# Acompanhar execução
gh run watch
```

### Promover para o próximo estágio

Após validar as métricas do estágio atual, dispare o workflow novamente com o próximo peso:

```bash
# Promover de 5% para 10%
gh workflow run deploy-canary.yml \
  --field image_tag=sha-abc1234 \
  --field canary_weight=10

# Promover de 10% para 25%
gh workflow run deploy-canary.yml \
  --field image_tag=sha-abc1234 \
  --field canary_weight=25

# E assim sucessivamente até 100%
```

---

## Deploy Canary Manual

### Estágio 1 — Criar o deployment canary com 5% do tráfego

```bash
# Define a imagem da nova versão
NOVA_IMAGEM="us-central1-docker.pkg.dev/meu-projeto/repo/sample-app:sha-abc1234"

# Cria o deployment canary a partir do stable (se não existir)
kubectl get deployment sample-app-stable -n production -o json | \
  python3 -c "
import json, sys
d = json.load(sys.stdin)
d['metadata']['name'] = 'sample-app-canary'
d['spec']['selector']['matchLabels']['track'] = 'canary'
d['spec']['template']['metadata']['labels']['track'] = 'canary'
d['spec']['replicas'] = 1
d.pop('status', None)
d['metadata'].pop('resourceVersion', None)
d['metadata'].pop('uid', None)
d['metadata'].pop('creationTimestamp', None)
d['metadata'].pop('generation', None)
print(json.dumps(d, indent=2))
" | kubectl apply -f -

# Atualiza a imagem do canary
kubectl set image deployment/sample-app-canary \
  sample-app=${NOVA_IMAGEM} \
  -n production

# Aguarda o canary estar pronto
kubectl rollout status deployment/sample-app-canary \
  -n production \
  --timeout=300s

echo "Canary pronto. Configurando 5% de tráfego..."
```

### Estágio 2 — Configurar o peso do tráfego

```bash
chmod +x scripts/canary-promote.sh

# Configura 5% de tráfego para o canary
./scripts/canary-promote.sh \
  --cluster-type=gke \
  --namespace=production \
  --service=sample-app \
  --new-weight=5 \
  --threshold=1.0 \
  --monitor=120

echo "5% do tráfego agora vai para o canary. Monitorar por 30 minutos."
```

### Progressão manual dos pesos

```bash
# Após 30 minutos sem alertas, promover para 10%
./scripts/canary-promote.sh \
  --cluster-type=gke \
  --namespace=production \
  --service=sample-app \
  --new-weight=10

# Após mais 30 minutos, promover para 25%
./scripts/canary-promote.sh --cluster-type=gke --namespace=production \
  --service=sample-app --new-weight=25

# Após mais 30 minutos, promover para 50%
./scripts/canary-promote.sh --cluster-type=gke --namespace=production \
  --service=sample-app --new-weight=50

# Promoção completa: 100%
./scripts/canary-promote.sh --cluster-type=gke --namespace=production \
  --service=sample-app --new-weight=100
```

### Estágio final — Finalizar a promoção (100%)

Quando o canary atinge 100%, ele se torna o stable:

```bash
# Atualiza o deployment stable com a nova imagem
NOVA_IMAGEM="us-central1-docker.pkg.dev/meu-projeto/repo/sample-app:sha-abc1234"
kubectl set image deployment/sample-app-stable \
  sample-app=${NOVA_IMAGEM} \
  -n production

kubectl rollout status deployment/sample-app-stable \
  -n production \
  --timeout=600s

# Remove o deployment canary (não é mais necessário)
kubectl delete deployment sample-app-canary -n production --ignore-not-found

# Remove o ingress canary
kubectl delete ingress sample-app-canary -n production --ignore-not-found

echo "Promoção completa! 100% do tráfego agora vai para a nova versão."
```

---

## Métricas a Monitorar

Para cada estágio, monitore as métricas abaixo por pelo menos **30 minutos** antes de promover:

### Métricas de Aplicação (Grafana)

| Métrica | Baseline normal | Threshold de rollback |
|---------|----------------|-----------------------|
| Taxa de erro HTTP (5xx) | < 0,05% | > 1% |
| Latência p50 | < 50ms | Aumento > 50% |
| Latência p99 | < 300ms | Aumento > 100% |
| Taxa de sucesso (2xx) | > 99,9% | < 99% |
| Throughput (req/s) | baseline ±10% | Queda > 30% |

### Métricas de Infraestrutura (Kubernetes)

```bash
# CPU e memória dos pods canary
kubectl top pods -l "app=sample-app,track=canary" -n production

# Restart count (deve ser 0)
kubectl get pods -l "app=sample-app,track=canary" -n production \
  -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount'

# Verificar se há OOMKilled
kubectl describe pods -l "app=sample-app,track=canary" -n production \
  | grep -A2 "Last State"
```

### Queries úteis no Grafana / Cloud Monitoring

```
# Taxa de erro dos pods canary (PromQL)
rate(http_requests_total{job="sample-app",track="canary",status=~"5.."}[5m])
  /
rate(http_requests_total{job="sample-app",track="canary"}[5m])
* 100

# Latência p99 do canary vs stable
histogram_quantile(0.99,
  rate(http_request_duration_seconds_bucket{job="sample-app"}[5m])
) by (track)
```

---

## Critérios de Promoção

Um estágio pode ser promovido para o próximo peso quando **todos** os critérios abaixo forem atendidos:

- [ ] Tempo mínimo do estágio decorrido (30 minutos)
- [ ] Taxa de erro HTTP abaixo de 1% nos últimos 15 minutos
- [ ] Nenhum pod canary em CrashLoopBackOff ou OOMKilled
- [ ] Latência p99 não aumentou mais de 50% em relação ao stable
- [ ] Nenhum alerta crítico ativo no PagerDuty relacionado ao serviço
- [ ] Restart count dos pods canary é zero

**Promoção de 50% → 100%:** requer aprovação adicional do Tech Lead ou engenheiro sênior.

---

## Critérios de Rollback

Execute rollback **imediatamente** se qualquer um dos itens abaixo for verdadeiro:

- Taxa de erro HTTP > 1% por mais de 5 minutos consecutivos
- Algum pod canary em CrashLoopBackOff
- Latência p99 > 2x o valor do stable
- Alerta crítico disparado no PagerDuty relacionado ao serviço
- Reclamações diretas de usuários afetados
- Detecção de regressão em funcionalidade crítica (ex: falha no checkout, autenticação)

---

## Comandos Úteis

### Ver status atual do canary

```bash
# Resumo completo do estado do canary
echo "=== Deployments ==="
kubectl get deployments -n production \
  -l app=sample-app \
  -o custom-columns='NOME:.metadata.name,DESEJADO:.spec.replicas,PRONTO:.status.readyReplicas,IMAGEM:.spec.template.spec.containers[0].image'

echo ""
echo "=== Peso do tráfego canary (GKE/nginx) ==="
kubectl get ingress sample-app-canary -n production \
  -o jsonpath='Peso canary: {.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}%{"\n"}' \
  2>/dev/null || echo "Nenhum ingress canary ativo (stable recebe 100%)"

echo ""
echo "=== Pods e restarts ==="
kubectl get pods -n production \
  -l app=sample-app \
  -o custom-columns='POD:.metadata.name,TRACK:.metadata.labels.track,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,IMAGEM:.spec.containers[0].image'
```

### Rollback imediato (sem script)

```bash
# Remove o ingress canary — todo tráfego volta para o stable instantaneamente
kubectl delete ingress sample-app-canary -n production --ignore-not-found

# Remove o deployment canary
kubectl delete deployment sample-app-canary -n production --ignore-not-found

echo "Rollback concluído. 100% do tráfego no stable."
```

### Rollback via script

```bash
chmod +x scripts/canary-promote.sh

# Peso 0 = rollback completo
./scripts/canary-promote.sh \
  --cluster-type=gke \          # ou aks
  --namespace=production \
  --service=sample-app \
  --new-weight=0
```

### Verificar logs dos pods canary

```bash
# Logs em tempo real de todos os pods canary
kubectl logs \
  -l "app=sample-app,track=canary" \
  -n production \
  -f \
  --all-containers \
  --prefix

# Buscar erros nos últimos 15 minutos
kubectl logs \
  -l "app=sample-app,track=canary" \
  -n production \
  --since=15m \
  | grep -iE "(error|exception|fatal|panic|5[0-9][0-9])" | tail -50
```

### Comparar versões stable vs canary

```bash
# Exibe qual versão cada deployment está rodando
echo "Stable:"
kubectl get deployment sample-app-stable -n production \
  -o jsonpath='{.spec.template.spec.containers[0].image}' && echo

echo "Canary:"
kubectl get deployment sample-app-canary -n production \
  -o jsonpath='{.spec.template.spec.containers[0].image}' && echo
```

### Forçar redistribuição do tráfego (se o peso não estiver funcionando)

```bash
# Para GKE com nginx-ingress: verifica se o ingress canary tem as annotations corretas
kubectl get ingress sample-app-canary -n production -o yaml | grep -A5 annotations

# Corrige as annotations manualmente se necessário
kubectl annotate ingress sample-app-canary -n production \
  "nginx.ingress.kubernetes.io/canary=true" \
  "nginx.ingress.kubernetes.io/canary-weight=10" \
  --overwrite
```

---

## Troubleshooting

### O peso do canary não está sendo respeitado

**Verificar:** O nginx-ingress está instalado e configurado corretamente?
```bash
kubectl get pods -n ingress-nginx
kubectl get ingressclass
```

**Verificar:** O ingress canary existe e tem as annotations certas?
```bash
kubectl describe ingress sample-app-canary -n production | grep -A10 Annotations
```

**Solução alternativa para GKE sem nginx-ingress:** Usar escala de réplicas como proxy de peso (o script canary-promote.sh faz isso automaticamente para AKS).

---

### O deployment canary não sobe

**Verificar logs:**
```bash
kubectl describe deployment sample-app-canary -n production | grep -A10 Events
kubectl describe pods -l "app=sample-app,track=canary" -n production | tail -30
```

**Causa comum:** Imagem inválida ou inacessível no registry.
```bash
# Verifica se o pull secret está configurado
kubectl get secrets -n production | grep registry

# Testa o pull manualmente
kubectl run test-pull \
  --image=us-central1-docker.pkg.dev/meu-projeto/repo/sample-app:sha-abc1234 \
  --restart=Never \
  -n production
kubectl delete pod test-pull -n production
```

---

### Métricas de erro aumentaram no canary

**Não entre em pânico — siga a ordem:**

1. Execute o rollback imediato:
   ```bash
   ./scripts/canary-promote.sh \
     --cluster-type=gke \
     --namespace=production \
     --service=sample-app \
     --new-weight=0
   ```

2. Investigue os logs do canary:
   ```bash
   kubectl logs -l "app=sample-app,track=canary" -n production --previous --tail=200
   ```

3. Compare o diff da imagem entre stable e canary para identificar a regressão.

4. Reporte o incidente e documente no pós-mortem.

---

## Referências

- **Script:** `/scripts/canary-promote.sh` — código-fonte com lógica de pesos e monitoramento
- **Workflow:** `.github/workflows/deploy-canary.yml` — pipeline automatizado
- **Workflow reutilizável:** `.github/workflows/reusable-deploy-k8s.yml`
- **Runbook blue-green:** `docs/runbooks/blue-green-deployment.md`
- **Arquitetura:** `docs/architecture/multi-cloud-design.md`
- **nginx-ingress canary:** https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#canary
