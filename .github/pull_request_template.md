# Descrição das Mudanças

<!--
  Explique de forma clara o que esta PR faz e qual problema resolve.
  Inclua o contexto necessário para que os revisores entendam a motivação
  sem precisar ler todo o código.

  Exemplos:
  - "Adiciona módulo Terraform para criação do cluster GKE com autopilot"
  - "Corrige race condition no script de blue-green switch ao detectar slot ativo"
  - "Atualiza versão do Terraform de 1.6 para 1.7.5"
-->



## Tipo de Mudança

<!--
  Marque com [x] o(s) tipo(s) que se aplicam a esta PR.
  Você pode selecionar mais de um.
-->

- [ ] `bugfix` — Correção de um bug existente (não quebra funcionalidade existente)
- [ ] `feature` — Nova funcionalidade (não quebra funcionalidade existente)
- [ ] `infra` — Mudança na infraestrutura (Terraform, Kubernetes, scripts de CI/CD)
- [ ] `security` — Correção ou melhoria de segurança (autenticação, IAM, secrets, scan)
- [ ] `refactor` — Refatoração de código sem mudança de comportamento
- [ ] `docs` — Apenas documentação (runbooks, READMEs, comentários)
- [ ] `chore` — Manutenção (atualização de dependências, formatação, linting)
- [ ] `breaking change` — Esta mudança quebra alguma compatibilidade existente

---

## Checklist de Qualidade

<!--
  Complete todos os itens antes de solicitar revisão.
  Itens não aplicáveis podem ser marcados com [x] e comentados.
-->

### Infraestrutura como Código (Terraform)

- [ ] `terraform fmt -recursive` executado — código formatado corretamente
- [ ] `tflint --recursive` passou sem erros ou warnings bloqueantes
- [ ] `checkov --directory terraform/` passou ou findings foram documentados/aceitos
- [ ] `terraform validate` passou em todos os módulos modificados
- [ ] Variáveis novas têm descrição e tipo definidos no `variables.tf`
- [ ] Outputs novos têm descrição definida no `outputs.tf`
- [ ] Recursos novos têm tags/labels adequadas (environment, team, cost-center)
- [ ] Não há segredos ou valores sensíveis hardcoded no código Terraform

### Scripts e Automação

- [ ] `shellcheck` passou nos scripts Bash modificados
- [ ] Scripts novos têm `set -euo pipefail` e tratamento de erros
- [ ] Scripts testados localmente com `./scripts/validate-local.sh`

### Segurança

- [ ] Nenhuma credencial, token ou secret foi commitado nesta PR
- [ ] Permissões IAM seguem o princípio do menor privilégio
- [ ] Políticas de rede foram revisadas (firewall rules, NSGs, VPC policies)
- [ ] Vulnerabilidades encontradas pelo Trivy ou Checkov foram triadas

### Kubernetes / Deploy

- [ ] Manifests Kubernetes têm `resource requests` e `limits` definidos
- [ ] Liveness e readiness probes configurados corretamente
- [ ] Estratégia de deploy revisada e adequada para a mudança
- [ ] Health check pós-deploy validado em staging antes de abrir PR para main

### Testes

- [ ] Testes existentes continuam passando (`pytest` / testes unitários)
- [ ] Testes novos adicionados para a funcionalidade introduzida (se aplicável)
- [ ] Testado manualmente em staging (ver seção "Como Testar" abaixo)

### Documentação

- [ ] READMEs e runbooks atualizados para refletir as mudanças
- [ ] Variáveis e outputs Terraform documentados com descrições claras
- [ ] Diagrama de arquitetura atualizado se houver mudança estrutural
- [ ] ADR (Architecture Decision Record) criado se uma decisão importante foi tomada

---

## Resultado do Terraform Plan

<!--
  O workflow de terraform-plan roda automaticamente nesta PR.
  Inclua aqui o resumo do resultado para facilitar a revisão.
  Exemplo: "Plan: 3 to add, 1 to change, 0 to destroy"
-->

**GCP:** _(aguardando execução automática do workflow)_
**Azure:** _(aguardando execução automática do workflow)_

---

## Screenshots / Evidências

<!--
  Se aplicável, adicione capturas de tela, logs de saída relevantes
  ou links para execuções do workflow que demonstrem o funcionamento.

  Exemplos úteis:
  - Screenshot do health check verde pós-deploy em staging
  - Saída do terraform plan com as mudanças esperadas
  - Dashboard do Grafana mostrando métricas estáveis após o deploy
-->

_Nenhuma screenshot necessária para este tipo de mudança_

---

## Como Testar

<!--
  Descreva PASSO A PASSO como um revisor pode validar esta mudança.
  Seja específico — quais comandos rodar, quais endpoints verificar,
  qual comportamento esperar.
-->

### Pré-requisitos para testar localmente

```bash
# Instalar dependências necessárias (se ainda não instaladas)
# Ver scripts/validate-local.sh para validação automatizada
./scripts/validate-local.sh
```

### Passos para validação

1. **Checkout da branch:**
   ```bash
   git checkout <nome-da-branch>
   ```

2. **Validar Terraform:**
   ```bash
   cd terraform
   terraform init
   terraform validate
   terraform fmt -check -recursive
   ```

3. **Validar scripts Bash:**
   ```bash
   shellcheck scripts/*.sh
   ```

4. **Executar testes:**
   ```bash
   pytest apps/ -v
   ```

5. **Verificar em staging:**
   - _(descrever o que verificar no ambiente de staging)_

### Resultado esperado

<!--
  Descreva o que deve acontecer após as mudanças serem aplicadas.
  Exemplo: "O cluster GKE deve ser criado com 3 node pools; o health check
  em /health deve retornar HTTP 200 com {'status': 'ok'}."
-->

---

## Issues Relacionadas

<!--
  Referencie issues relacionadas usando palavras-chave do GitHub:
  - "Closes #123" — fecha a issue automaticamente ao fazer merge
  - "Fixes #456" — idem
  - "Relates to #789" — referência sem fechar automaticamente
-->

Closes #

---

## Notas para os Revisores

<!--
  Informações adicionais que os revisores devem saber:
  - Áreas que precisam de atenção especial
  - Trade-offs e decisões tomadas
  - Dívidas técnicas criadas intencionalmente
  - Dependências externas (outras PRs, deploys, janelas de manutenção)
-->
