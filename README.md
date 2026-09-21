# poc-frontend-nodejs — POC Kubernetes local (k3s) com CI/CD, segurança e observabilidade

Frontend Node.js (`/healthz`, `/readyz`, `/metrics`, `/api/work`) entregue em um cluster **k3s local** (sem cloud),
com pipeline **GitHub Actions self-hosted**, **SonarCloud (SAST)**, **Trivy**, **Harbor**, **cosign**, **Kyverno**,
**GitOps com ArgoCD** e **Canary (Argo Rollouts)**. Métricas no **Prometheus/Grafana já existentes**, logs em **Loki/Promtail**
(Loki fixado em um nó específico) e teste de carga com **k6 (300 usuários)**.

## 1. Arquitetura

```
 dev ──push──▶ GitHub ──▶ Runner self-hosted (VM Ubuntu "CI")
                              │ 1 testes+cobertura ─▶ SonarCloud (SAST + Quality Gate)
                              │ 2 helm lint/template
                              │ 3 docker build ─▶ Trivy (falha HIGH/CRITICAL) ─▶ push Harbor ─▶ cosign sign/verify
                              └ 4 commit do digest em chart/frontend/values-rollout.yaml
                                                     │
              ArgoCD (EXISTENTE) ◀── observa o Git ──┘
                    │ sync
                    ▼
   ┌────────────── cluster k3s ───────────────────────────────────────────┐
   │ ingress-nginx ─▶ Rollout frontend (canary 20%→50%→100% + análise)    │
   │ Harbor · Kyverno (proíbe :latest, exige assinatura) · Argo Rollouts   │
   │ blackbox-exporter (sonda /healthz) · Loki (nó fixo) + Promtail (todos)│
   └──────────────────────────────────────────────────────────────────────┘
        ▲ métricas (PodMonitor/Probe)                    ▲ logs
   Prometheus EXISTENTE  :30900 ──────▶ Grafana EXISTENTE :30300 ◀── Loki
```

| Componente | Origem |
|---|---|
| Grafana `http://201.23.88.239:30300` | **já existe** (integrado) |
| Prometheus `http://201.23.88.239:30900` | **já existe** (integrado) |
| ArgoCD `https://201.23.88.239:30085` | **já existe** (integrado) |
| k3s, ingress-nginx, Harbor, blackbox-exporter, Loki+Promtail, Kyverno, Argo Rollouts | instalados por `scripts/` |
| SonarCloud `julianodevops` | **já existe** (SaaS) |
| runner, k6 | VM de CI (systemd / docker) |

## 2. Estrutura

```
app/            Node.js (Express + prom-client), testes Jest, Dockerfile multi-stage, sonar-project.properties
chart/frontend/ Helm: Deployment|Rollout, Service(+canary), Ingress, HPA, ConfigMap, Secret, PodMonitor, Probe, PrometheusRule, AnalysisTemplate
argocd/         Application (GitOps) e exemplo de credencial de repo privado
k8s/            values do Harbor/ingress-nginx/Loki, policies Kyverno, dashboard Grafana, SonarQube compose, fallback Prometheus
loadtest/       k6-300vu.js
scripts/        instalação, deploy manual, load test, coleta de evidências; scripts/ci = runner e ferramentas
.github/workflows/ci-cd.yaml
examples/       pods que DEVEM ser negados pelo Kyverno
evidencias/     saídas/prints
```

## 3. Pré-requisitos e topologia sugerida

- Ubuntu 22.04/24.04. Mínimo sugerido: **master 4 vCPU/8 GB**, workers 2 vCPU/4 GB, **VM CI 4 vCPU/8 GB** (runner + SonarQube + k6).
- Acesso ao seu cluster: o **ArgoCD existente deve gerenciar este cluster**. Se estiver em outro cluster: `argocd cluster add <contexto>` e ajuste `destination.server` em `argocd/application.yaml`.
- Edite `scripts/env.sh` (ou crie `scripts/env.local.sh`): IPs, senha do Harbor etc. Adicione `harbor.local` e `frontend.local` ao `/etc/hosts` de **cada máquina** que os acessa (o script 01/02 faz isso nos nós; faça também na VM CI e na sua estação):
  `201.23.88.239 harbor.local frontend.local` (troque pelo IP do nó com o ingress).

## 4. Passo a passo

### 4.1 Cluster k3s (VMs)
```bash
# master
./scripts/01-k3s-server.sh            # k3s sem Traefik, registries.yaml (Harbor HTTP), kubeconfig
# cada worker
K3S_TOKEN=<token impresso no master> ./scripts/02-k3s-agent.sh
kubectl get nodes -o wide
```

### 4.2 Plataforma (Harbor, ingress, Loki em nó específico, Kyverno, Rollouts)
```bash
kubectl get nodes                                   # escolha o nó do Loki
LOKI_NODE=<nome-do-no> ./scripts/03-install-platform.sh
```
O script **rotula** o nó (`poc/loki=true`) e o Loki sobe **somente nele** (`nodeSelector`, PVC local-path preso ao nó).
O Promtail roda em todos os nós (precisa ler os logs de cada um). Confirme: `kubectl -n logging get pods -o wide`.
Para trocar de nó depois: remova o label antigo, rotule o novo e recrie o pod (o PVC local-path **não migra** — os logs antigos ficam no nó anterior).

### 4.3 Integração com o Prometheus existente
O chart cria `PodMonitor` (métricas do app), `Probe` (sonda `/healthz`) e `PrometheusRule` (SLIs/alertas). Isso exige o **Prometheus Operator**.

1. Verifique: `kubectl get crd | grep monitoring.coreos.com`
2. Descubra o *selector* do seu Prometheus:
   ```bash
   kubectl get prometheus -A -o yaml | grep -A6 -E "podMonitorSelector|probeSelector|ruleSelector|NamespaceSelector"
   ```
   Se exigir labels (ex.: `release: prom`), informe no deploy: `--set monitoring.labels.release=prom`
   (ou em `values.yaml > monitoring.labels`). Se os `*NamespaceSelector` não forem `{}`, o namespace `frontend` precisa ser selecionado.
3. **Sem Operator?** use `--set monitoring.enabled=false`, adicione `k8s/observability/prometheus-fallback/scrape-jobs.yaml` aos `scrape_configs`
   e gere as regras com `./scripts/10-export-rules.sh` (incluir em `rule_files`).
4. Para o k6 enviar métricas ao Prometheus, ele precisa da flag `--web.enable-remote-write-receiver` (opcional).
5. A análise automática do canary consulta `http://201.23.88.239:30900` (`rollout.analysis.prometheusAddress`); o cluster precisa alcançar essa URL.

Validação: em `http://201.23.88.239:30900/targets` devem aparecer os pods `frontend` e o job `frontend-healthz`.

### 4.4 Integração com o Grafana existente
```bash
GRAFANA_PASSWORD='***' ./scripts/10-grafana-integration.sh     # ou GRAFANA_TOKEN=glsa_...
```
Descobre o datasource Prometheus, **cria o datasource Loki** (`LOKI_URL`, padrão `http://loki.logging.svc.cluster.local:3100` — vale se o Grafana roda **dentro** do cluster;
se estiver fora, exponha o Loki de forma segura e ajuste `LOKI_URL`) e importa o dashboard **Frontend Node.js — SLI/SLO** (`/d/frontend-slo`).
Os painéis de réplicas/CPU usam `kube-state-metrics` e cAdvisor; se o seu Prometheus não os coleta, esses dois painéis ficam vazios.

### 4.5 Harbor
```bash
./scripts/04-harbor-project.sh       # cria o projeto privado "poc"
```
Na UI (`http://harbor.local`, admin / senha do env): *Projects → poc → Robot Accounts → New* (push/pull). Guarde usuário/token para os secrets do GitHub.
> POC em HTTP: por isso `insecure-registries` no Docker do runner, `registries.yaml` no k3s e `allowInsecureRegistry` no Kyverno. Em produção use TLS com CA confiável.

### 4.6 SonarCloud (SAST)
Organização: `https://sonarcloud.io/organizations/julianodevops/`.
1. *+ → Analyze new project* e importe o repositório `poc-frontend-nodejs` (ou crie manualmente). Anote a **Project Key** (*Information*) e,
   se for diferente de `julianodevops_poc-frontend-nodejs`, ajuste `sonar.projectKey` em `app/sonar-project.properties`.
2. Em *Administration → Analysis Method* **desative "Automatic Analysis"** (o pipeline faz a análise por CI e os dois modos são incompatíveis).
3. O token (*My Account → Security*) vai no secret `SONAR_TOKEN`. A URL (`https://sonarcloud.io`) já está no workflow; a organização, em `sonar-project.properties`.
4. Quality Gate: o pipeline falha se o gate do SonarCloud reprovar. SonarCloud também analisa **Pull Requests**.
(O `k8s/sonarqube/docker-compose.yml` fica apenas como alternativa self-hosted e não é usado.)

### 4.7 GitHub Actions self-hosted runner (Ubuntu) — passo a passo
1. **VM CI** com Ubuntu, acesso à internet (GitHub, ghcr/Trivy DB), ao Harbor (`harbor.local`), ao SonarQube e ao cluster.
2. Ferramentas (docker, trivy, cosign 2.x, kubectl, helm, yq, argo rollouts plugin, argocd CLI, `insecure-registries`):
   `sudo -E ./scripts/ci/install-ci-tools.sh`
3. No GitHub: repositório → **Settings → Actions → Runners → New self-hosted runner** (Linux x64). Copie o **token** (vale ~1 h).
4. Instale e registre como serviço:
   ```bash
   sudo REPO_URL=https://github.com/<user>/poc-frontend-nodejs RUNNER_TOKEN=<token> ./scripts/ci/install-github-runner.sh
   ```
   O script cria o usuário `github-runner` (grupo `docker`), baixa a última versão do runner, registra com labels `self-hosted,linux,x64,poc-k8s`
   e instala o serviço systemd. Manualmente seriam: `./config.sh --url ... --token ... --labels poc-k8s` → `sudo ./svc.sh install github-runner` → `sudo ./svc.sh start`.
5. Confira: `systemctl status "actions.runner.*"` e, no GitHub, o runner **Idle**.
6. Para o job `post-deploy-check` copie um kubeconfig para o usuário do runner: `sudo -u github-runner mkdir -p ~github-runner/.kube` e copie `~/.kube/config` do master (com o IP do master no `server:`).
7. **Segurança:** runner self-hosted executa código do repositório — use **repositório privado** (ou proteja PRs de forks).

**Secrets do repositório** (Settings → Secrets and variables → Actions → *Secrets*) — ou `REPO=<user>/poc-frontend-nodejs ./scripts/set-github-secrets.sh`:

| Secret | Obrigatório | Valor |
|---|---|---|
| `SONAR_TOKEN` | sim | token do SonarCloud |
| `HARBOR_USERNAME` / `HARBOR_PASSWORD` | sim | robot account do projeto `poc` (ex.: `robot$poc+ci`) |
| `COSIGN_PRIVATE_KEY` | sim | conteúdo de `cosign.key` |
| `COSIGN_PASSWORD` | sim | senha usada em `05-cosign-keys.sh` |
| `INGRESS_IP` | sim | IP do nó do ingress (`201.23.88.239`) — smoke test |
| `ARGOCD_SERVER` | opcional | `201.23.88.239:30085` |
| `ARGOCD_AUTH_TOKEN` | opcional | `argocd account generate-token --account <usuario>` |

Não há *Variables* obrigatórias (`SONAR_HOST_URL` está fixo no workflow). Ajuste também *Settings → Actions → General → Workflow permissions* para **Read and write**
(o job `gitops-deploy` faz push na `main`; se houver branch protection, permita o push do `github-actions[bot]`).
Token do ArgoCD: habilite `accounts.<usuario>: apiKey` no `argocd-cm` (o `--insecure` do CLI já cobre o certificado autoassinado).
> Confira as versões atuais das actions usadas em `ci-cd.yaml` (`sonarqube-scan-action`, `sonarqube-quality-gate-action`).

### 4.8 cosign + Kyverno
```bash
COSIGN_PASSWORD='***' ./scripts/05-cosign-keys.sh     # gera cosign.key / cosign.pub  → COMMITE cosign.pub
./scripts/06-apply-policies.sh                         # aplica as policies (injeta cosign.pub)
```
Policies: `disallow-latest-tag` (Enforce), `verify-image-signature` (Enforce, só imagens `harbor.local/poc/*` no ns `frontend`), `require-best-practices` (Audit).
Teste (ambos devem ser **negados**):
```bash
kubectl apply -f examples/pod-latest.yaml
kubectl apply -f examples/pod-unsigned.yaml
```
> As policies usam `validationFailureAction` (compatível com várias versões). Em Kyverno mais novo, migre para `failureAction` por regra.
> Os namespaces de infraestrutura estão excluídos da policy de `:latest`.

### 4.8b GitOps com o ArgoCD existente
```bash
# edite argocd/application.yaml (repoURL)
./scripts/08-deploy-argocd.sh                          # kubectl apply -n argocd  (ARGOCD_MODE=cli usa o argocd CLI)
```
Repositório privado: `argocd/repo-secret.example.yaml` (PAT com leitura) ou `argocd repo add`. UI: `https://201.23.88.239:30085`.

## 5. Pipeline (`.github/workflows/ci-cd.yaml`)

| Job | O que faz | Falha se |
|---|---|---|
| `test-sast` | `npm ci`, lint, Jest (cobertura ≥ 80% linhas), SonarCloud scan + Quality Gate | teste/cobertura/gate reprovado |
| `chart-lint` | `helm lint`/`template` (Deployment e Rollout), `trivy config` | chart inválido |
| `build-scan-sign` | build (estágio `test` + final), **Trivy image** (HIGH/CRITICAL corrigíveis), push no Harbor, **cosign sign + verify** por digest | vulnerabilidade, assinatura |
| `gitops-deploy` | grava `image.tag` + `image.digest` em `values-rollout.yaml` e faz commit `[skip ci]` | — |
| `post-deploy-check` | refresh/sync no ArgoCD, acompanha o canary, smoke test | rollout abortado |

Deploy = **commit no Git**; quem aplica no cluster é o ArgoCD (com `selfHeal`). O digest no Git evita *drift* e permite ao Kyverno validar exatamente o conteúdo assinado.

## 6. Deploy manual (sem pipeline/ArgoCD)

```bash
TAG=1.0.0 COSIGN_PASSWORD='***' ./scripts/07-deploy-manual.sh helm      # build, push, assina e helm upgrade --install
TAG=1.0.0 COSIGN_PASSWORD='***' ./scripts/07-deploy-manual.sh kubectl   # helm template | kubectl apply
```
Equivalente passo a passo:
```bash
kubectl create namespace frontend
helm upgrade --install frontend chart/frontend -n frontend \
  --set image.tag=1.0.0 --set image.digest=sha256:<digest> [--set monitoring.labels.release=<rel>]
kubectl -n frontend get deploy,po,svc,ingress,hpa,cm,secret
kubectl -n frontend rollout status deploy/frontend
curl -i http://frontend.local/healthz
```
(Com `--set monitoring.enabled=false` se não houver Operator.)

## 7. Canary / Blue-Green

O modo GitOps usa `rollout.enabled=true` → **Argo Rollouts canary**: 20% → pausa → **análise Prometheus** (taxa de sucesso do canary ≥ 95%) → 50% → pausa → 100%,
com divisão real de tráfego via ingress-nginx. Se a análise falhar, o Rollout **aborta e volta** sozinho para a versão estável.
```bash
kubectl argo rollouts get rollout frontend -n frontend --watch
kubectl argo rollouts promote frontend -n frontend        # avança manualmente
kubectl argo rollouts abort frontend -n frontend          # aborta o canary
```
Demonstração de rollback automático: suba uma versão com `config.ERROR_RATE: "0.5"` (em `values.yaml`) e gere tráfego — a análise reprova.

## 8. Rollback
| Situação | Comando |
|---|---|
| GitOps (recomendado) | `git revert <commit do deploy>` e push → ArgoCD reaplica a versão anterior |
| Canary em andamento | `kubectl argo rollouts abort frontend -n frontend` |
| Voltar revisão do Rollout | `kubectl argo rollouts undo frontend -n frontend` (com ArgoCD, faça o revert no Git também, senão o `selfHeal` reverte) |
| Deploy via Helm | `helm history frontend -n frontend` → `helm rollback frontend <rev> -n frontend` |
| Deploy via Deployment | `kubectl -n frontend rollout undo deploy/frontend` |

## 9. Observabilidade, SLI/SLO/SLA

| Conceito | Definição nesta POC |
|---|---|
| **SLI disponibilidade** | requisições sem 5xx / total (rotas `/` e `/api/*`) — `frontend:sli_availability:ratio_rate*` |
| **SLI latência** | requisições ≤ 300 ms / total — `frontend:sli_latency:ratio_rate*` (p50/p95/p99 também gravados) |
| **SLI /healthz** | `probe_success` e `probe_duration_seconds` (blackbox) + latência do `/healthz` medida pela app |
| **SLO** | disponibilidade **99,5%** e latência **95% ≤ 300 ms**, janela 30 d (`values.yaml > slo`) |
| **SLA** (compromisso externo, exemplo) | **99,0%** de disponibilidade mensal — mais frouxo que o SLO, deixando margem interna |
| **Error budget** | 0,5% → `frontend:error_budget_remaining:ratio30d` |
| **Alertas** | burn rate rápido (14,4× em 5m+1h, crítico), lento (6× em 30m+6h), latência, `/healthz` fora/lento |

Logs: no Grafana (Explore → Loki) — `{namespace="frontend"} | json | status >= 500`. O app loga JSON (método, path, status, duração).
As regras/alertas chegam ao Alertmanager do seu Prometheus (configure receivers, ex.: Slack, lá).

## 10. Teste de carga — k6, 300 usuários
```bash
./scripts/09-loadtest.sh                      # rampa 1 min → 300 VUs por 3 min → descida 30 s
K6_PROMETHEUS=true ./scripts/09-loadtest.sh   # + envia métricas do k6 ao Prometheus (se remote-write receiver estiver ativo)
```
Thresholds = SLOs (erros < 0,5%, p95 < 300 ms). Durante o teste observe: `kubectl -n frontend get hpa -w` (CPU > 60% → escala até 6 réplicas),
o dashboard SLI/SLO (latência, taxa, error budget) e os logs no Loki. O resumo é salvo em `evidencias/k6-summary.txt`.
Rode o k6 de uma máquina fora dos nós do cluster para não competir por CPU com o app.

## 11. Troubleshooting

| Sintoma | Causa provável / ação |
|---|---|
| `docker push` → `http: server gave HTTP response to HTTPS client` | falta `insecure-registries` no Docker do runner (`/etc/docker/daemon.json`) e restart |
| Pod `ImagePullBackOff` no Harbor | `registries.yaml` ausente nos nós (restart do `k3s`/`k3s-agent`), `harbor.local` sem resolução, ou projeto privado sem `imagePullSecret` (deixe o projeto público ou crie o secret) |
| Kyverno nega tudo em `frontend` | chave errada em `cosign.pub` (re-rode 06), imagem não assinada, ou Kyverno sem `allowInsecureRegistry` / sem resolver `harbor.local` (CoreDNS custom) |
| PodMonitor/Probe/Rule não aparecem no Prometheus | falta label do selector (`monitoring.labels`) ou seletor de namespace; veja 4.3 |
| Dashboard sem dados | `kubectl -n frontend get podmonitor`; `/targets` no Prometheus; gere tráfego (SLIs precisam de requisições) |
| Loki `Pending` | label `poc/loki=true` ausente ou PVC preso a outro nó: `kubectl -n logging describe pod` |
| Grafana não lê o Loki | `LOKI_URL` inacessível pelo Grafana (Grafana fora do cluster?) — teste *Save & test* no datasource |
| Sonar: "You are running CI analysis while Automatic Analysis is enabled" | desative *Automatic Analysis* no projeto do SonarCloud |
| Sonar: `Project not found` / 403 | `sonar.projectKey`/`sonar.organization` errados ou token sem permissão na organização |
| Trivy sem DB | VM CI sem acesso à internet: use `--skip-db-update` com DB previamente baixado |
| ArgoCD `OutOfSync` permanente | digest mutado no cluster — mantenha `mutateDigest: false`; confira `selfHeal` vs `argo rollouts undo` |
| Rollout `Degraded` | `kubectl argo rollouts get rollout frontend -n frontend`; veja o `AnalysisRun` (`kubectl -n frontend get analysisrun`) |
| Ingress não responde | `kubectl -n ingress-nginx get svc` (EXTERNAL-IP dos nós), `/etc/hosts`, firewall nas portas 80/443 |

## 12. Checklist de evidências
`./scripts/collect-evidence.sh` grava as saídas de `kubectl`/`helm`/`argo` em `evidencias/output/`. Complemente com prints em `evidencias/`:
1. GitHub Actions — execução verde (todos os jobs) e uma falha proposital (Trivy ou Quality Gate)
2. SonarQube — projeto + Quality Gate; Trivy — relatório do job
3. Harbor — repositório com a imagem e a assinatura (cosign)
4. Kyverno — negação de `:latest` e de imagem não assinada
5. ArgoCD — Application `Synced/Healthy`; canary em andamento
6. Grafana — dashboard SLI/SLO durante o teste de carga; Explore Loki; Prometheus Targets
7. k6 — resumo dos 300 VUs; HPA escalando

## 13. Notas e limitações
- Segredos de demonstração (`Harbor12345`, `change-me`, senhas do compose) — troque; em uso real use Sealed Secrets/SOPS/External Secrets.
- Registry em HTTP e assinatura sem transparência log (`--tlog-upload=false`) por ser ambiente offline/local.
- Versões dos charts e do cosign (`COSIGN_VERSION`, padrão 2.4.1) não estão todas fixadas; registre `helm list -A` nas evidências.
- O chart `grafana/loki-stack` é considerado legado pela Grafana Labs, mas funciona bem para laboratório.
