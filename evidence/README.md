# Evidências a coletar

Não inclua prints simulados. Execute a POC e capture evidências reais.

1. `make status` com nodes/pods/Ingress/HPA.
2. Jenkins `poc-kubernetes-local` com todos os stages verdes.
3. Log do stage Secret Scan mostrando o repositório sem secrets detectados.
4. Log do stage SonarQube SAST mostrando o resultado do Quality Gate.
5. Log do Trivy mostrando o gate HIGH/CRITICAL.
6. Log do stage Cosign mostrando a assinatura verificada pelo digest.
7. Harbor exibindo `poc/poc-app` com uma tag `1.0.<BUILD_NUMBER>` e sua assinatura.
8. `curl -H 'Host: poc.local' http://127.0.0.1/healthz`.
9. Grafana com métricas do cluster/aplicação.
10. Explore/Loki com `{namespace="poc"}`.
11. `kubectl get hpa -n poc` e `kubectl top pods -n poc`.
12. Kyverno negando `kubectl run should-fail --image=nginx:latest`.
13. `helm history poc-app -n poc` e, se demonstrado, rollback.
14. Argo CD apenas se o diferencial for apresentado.

Sugestão: salvar os arquivos nesta pasta com nomes `01-status.png`, `02-jenkins.png`, etc.
