# Evidências da POC

As capturas abaixo foram obtidas durante a execução real da POC.

## Estado da plataforma

O `make status` confirma os containers de CI, os dois nodes Kubernetes, os pods da plataforma, Ingress, HPA, releases Helm e os checks de saúde. A visão do namespace `poc` complementa a validação com os recursos gerenciados pela aplicação.

![Status dos containers, nodes e pods](01a-status-nodes-pods.png)

![Status de Ingress, HPA, Helm e saúde](01b-status-health.png)

![Recursos gerenciados no namespace poc](01c-poc-resources.png)

## Pipeline Jenkins

A build `#2` concluiu todos os stages, incluindo testes, análises de segurança, publicação, assinatura, deploy GitOps e smoke test.

![Pipeline Jenkins com deploy pelo Argo CD](02-jenkins-argocd.png)

## Qualidade no SonarQube

O Quality Gate foi aprovado, com notas A em segurança e confiabilidade, cobertura de 98% e duplicação de 0%.

![Quality Gate e métricas do SonarQube](03-sonarqube-quality-gate.png)

## Scan da imagem com Trivy

O pipeline usa `--exit-code 1` para bloquear vulnerabilidades `HIGH` e `CRITICAL`. O relatório da imagem `harbor.local/poc/poc-app:1.0.2` terminou sem findings de segurança.

![Comando e gate do Trivy](04a-trivy-gate.png)

![Resumo do scan da imagem](04b-trivy-summary.png)

![Resultado limpo do Trivy](04c-trivy-clean.png)

## Imagens no Harbor

O repositório `poc/poc-app` contém tags versionadas, cada uma associada ao seu digest e marcada como assinada.

![Artefatos versionados e assinados no Harbor](05-harbor-signed-artifacts.png)

## Assinatura com Cosign

A assinatura foi publicada no Harbor e verificada pelo digest com a chave pública. A verificação do transparency log é feita offline nesta POC local; em produção, a recomendação é integrar Rekor ou mecanismo equivalente.

![Assinatura Cosign verificada pelo digest](06-cosign-verification.png)

## Observabilidade no Grafana

Os dashboards cobrem aplicação, pods, nodes, Prometheus e Alertmanager. O dashboard `POC App` reúne disponibilidade, targets, requisições, CPU, memória e logs.

![Dashboards selecionados para a POC](07a-grafana-dashboards.png)

![Métricas e logs da aplicação](07b-grafana-poc-app.png)

## Logs no Loki

O Grafana Explore consulta `{namespace="poc"}` e apresenta o volume e as linhas de log dos pods, incluindo chamadas a `/healthz` e `/metrics` com resposta HTTP 200.

![Consulta dos logs da aplicação no Loki](08-loki-logs.png)

## Política com Kyverno

O admission webhook bloqueou a criação de `nginx:latest` pela policy `disallow-latest-tag`, exigindo uma versão explícita ou digest.

![Kyverno bloqueando imagem com tag latest](09-kyverno-deny-latest.png)

## Aplicação e endpoints

A página principal identifica o ambiente `local`, a versão implantada `1.0.2` e a plataforma Kubernetes. A documentação OpenAPI apresenta os endpoints disponíveis.

![Página principal da aplicação](10-app-home.png)

![Documentação OpenAPI da aplicação](10b-api-docs.png)

## HPA e métricas

O HPA mantém duas réplicas, com limite de cinco e meta de 70% de CPU. As métricas mostram o consumo dos pods e dos dois nodes.

![HPA e métricas de pods e nodes](11-hpa-metrics.png)

## Scan de secrets

O Trivy verifica o workspace com o scanner de secrets e `--exit-code 1`. Apenas `.git` e `.venv`, que são diretórios gerados, ficam fora da varredura.

![Secret Scan concluído sem findings](12-secret-scan.png)

## Health check

O endpoint `/healthz` respondeu HTTP 200 com `{"status":"ok"}` por meio do Ingress.

![Resposta do health check](13-healthcheck.png)

## Argo CD

A aplicação `poc-app` permaneceu `Synced` e `Healthy`, com todos os recursos gerenciados após o deploy.

![Argo CD com a aplicação Synced e Healthy](14-argocd-synced-healthy.png)
