# POC — Ambiente Kubernetes Local (DevOps)

POC local para demonstrar Kubernetes, CI/CD, segurança, observabilidade e práticas DevOps sem dependência de provedor Cloud. O projeto é executado diretamente em Linux pelo terminal.

## O que está implementado

- Kubernetes local com **kind** (control-plane + worker).
- **ingress-nginx** publicando aplicação, Harbor, Grafana e Prometheus, além do Argo CD quando instalado.
- Aplicação **FastAPI** com página inicial, `/healthz` e `/metrics`.
- Configuração exposta com segurança em `/info` e endpoint `/secure` protegido por `X-API-Key`.
- **Dockerfile multi-stage**, usuário não-root e `HEALTHCHECK`.
- Testes automatizados com **pytest**.
- **Helm Chart** com Deployment, Service, Ingress, HPA, ConfigMap, Secret e ServiceMonitor.
- **Metrics Server** para o HPA.
- **Harbor** como registry local.
- **Jenkins** local configurado como código (JCasC), com pipeline pré-criado.
- **SonarQube** para análise estática/SAST, com Quality Gate bloqueante.
- **Trivy Secret Scan** como gate para impedir credenciais no repositório.
- **Trivy** como gate para vulnerabilidades HIGH/CRITICAL.
- **Cosign** assinando e verificando a imagem antes do deploy.
- **Prometheus + Grafana** para métricas.
- **Loki + Promtail** para logs.
- **Kyverno** bloqueando imagens com `:latest`.
- **Argo CD** como diferencial opcional.

## Arquitetura

```text
Terminal
   |
   +----------------------- Makefile / scripts --------------------+
       |                                                           |
       v                                                           v
     Docker                                                     kind
       |                                                           |
       +-- Jenkins                                                  +-- ingress-nginx
       +-- SonarQube + PostgreSQL                                   +-- poc-app (Helm)
       |                                                            +-- HPA / Metrics Server
       |                                                            +-- Prometheus / Grafana
       +--> Tests -> Sonar -> Build -> Trivy -> Harbor -> Cosign -> Helm
                                                                    +-- Loki / Promtail
                                                                    +-- Kyverno
                                                                    `-- Argo CD (opcional)
```

O Jenkins utiliza `network_mode: host` propositalmente nesta POC Linux. Assim, ele acessa o API Server do kind em `127.0.0.1:6443` usando o kubeconfig local, evitando adaptações inseguras de TLS.

## Requisitos

As imagens, os charts e as ferramentas baixadas durante o bootstrap têm versões
fixadas nos Dockerfiles e scripts. Para as ferramentas já instaladas no host, o
projeto valida versões mínimas compatíveis. Isso reduz mudanças inesperadas
entre execuções.

Tenha instalados:

- Docker Engine 20.10 ou superior
- Docker Compose 2.0 ou superior
- kind 0.33.0 ou superior
- kubectl 1.37.0 ou superior
- Helm 3.22 ou superior, ainda na linha 3.x
- Git
- curl
- Python 3.12 ou superior

Recomendação prática: **16 GB de RAM ou mais e 4 CPUs ou mais** para executar a stack completa confortavelmente.

O cluster usa Kubernetes 1.37.0 por meio da imagem oficial `kindest/node`,
fixada por digest. O Jenkins usa `kubectl` 1.37.0 para manter o cliente da
pipeline alinhado ao API Server.

Valide o host antes da instalação:

```bash
make check
```

A POC não cria nem consome recursos de um provedor Cloud. Na primeira execução,
é necessário acesso à internet para baixar imagens, charts e pacotes.

## Subir tudo

```bash
make up
```

O comando solicita as senhas de Harbor e Jenkins sem exibi-las. Elas são
entregues ao runtime dos respectivos serviços e não são gravadas na árvore do
projeto. Os containers, volumes e Secrets que as armazenam são removidos por
`make down`.

Esse comando executa de forma idempotente:

1. cria o cluster kind;
2. instala ingress-nginx;
3. instala Metrics Server;
4. instala Prometheus/Grafana;
5. instala Loki/Promtail;
6. instala Kyverno e a policy de segurança;
7. instala Harbor;
8. cria o projeto `poc` no Harbor;
9. configura os nodes kind para consumir `harbor.local` via HTTP local;
10. sobe SonarQube;
11. gera o token Sonar usado pelo Jenkins;
12. sobe Jenkins já configurado como código;
13. cria o pipeline `poc-kubernetes-local`;
14. faz build/deploy local inicial da aplicação;
15. publica os serviços pelo Ingress e valida `/healthz`.

## URLs e credenciais

```bash
make info
```

Não registre a saída desse comando em logs, screenshots ou arquivos
versionados.

Principais acessos:

| Serviço | URL | Credencial de laboratório |
| --- | --- | --- |
| Aplicação | `http://poc.local` | - |
| Jenkins | `http://localhost:8080` | `admin` / senha informada no bootstrap |
| SonarQube | `http://localhost:9000` | `admin / admin` no primeiro acesso |
| Harbor | `http://harbor.local` | `admin` / senha informada no bootstrap |
| Grafana | `http://grafana.local` | gerada pelo chart |
| Prometheus | `http://prometheus.local` | sem autenticação |
| Argo CD (opcional) | `http://argocd.local` | gerada por `make argocd` |

Durante o `make up`, o bootstrap adiciona via `sudo` os hosts que ainda não
existirem:

```text
127.0.0.1 poc.local harbor.local grafana.local prometheus.local argocd.local
```

Sem alterar `/etc/hosts`, o healthcheck pode ser testado assim:

```bash
curl -H 'Host: poc.local' http://127.0.0.1/healthz
```

Uso do ConfigMap e do Secret pela aplicação:

```bash
curl -H 'Host: poc.local' http://127.0.0.1/info
curl -H 'Host: poc.local' \
  -H 'X-API-Key: change-me-local-only' \
  http://127.0.0.1/secure
```

O endpoint `/info` informa ambiente e versão e apenas confirma se a chave está
configurada; o valor de `API_KEY` nunca é retornado. O endpoint `/secure`
compara a chave recebida com o Secret usando comparação resistente a timing
attacks.

## Testes locais

```bash
make test
```

Executa:

```text
pytest com cobertura
helm lint
validação dos dashboards JSON
renderização dos manifests de monitoramento com Kustomize
leitura dos manifests do Argo CD
```

## Jenkins

O Jenkins é criado automaticamente e configurado com **Jenkins Configuration as Code**.

URL:

```text
http://localhost:8080
```

Usuário e senha:

```text
admin / senha informada em JENKINS_ADMIN_PASSWORD durante o bootstrap
```

O job abaixo já existe após `make up`:

```text
poc-kubernetes-local
```

O código-fonte é montado em `/workspace` como somente leitura e sincronizado para o workspace do job. Isso mantém a POC totalmente local, inclusive quando receber apenas o `.zip`.

### Pipeline

```text
Sync Source
   |
Secret Scan (qualquer segredo detectado = fail)
   |
Unit Tests + cobertura XML
   |
SonarQube SAST + Quality Gate
   |
Docker Build
   |
Trivy Scan (HIGH/CRITICAL = fail)
   |
Push Harbor
   |
Cosign: assinatura e verificação por digest
   |
Helm Lint
   |
Helm deploy (modo padrão) ou atualização da Application (modo Argo CD)
   |
Smoke Test /healthz
```

No modo padrão, Jenkins executa o `helm upgrade`. Depois que `make argocd` cria
a `Application`, o mesmo estágio deixa de usar Helm diretamente, atualiza a tag
desejada no recurso do Argo CD e aguarda o estado `Synced` e `Healthy`. Somente
o Argo CD altera a aplicação no cluster nesse modo.

As imagens do pipeline usam versão baseada no número do build:

```text
harbor.local/poc/poc-app:1.0.<BUILD_NUMBER>
```

A tag `latest` não é utilizada.

## Harbor e pull pelo kind

Harbor é publicado pelo Ingress em:

```text
http://harbor.local
```

O bootstrap cria o projeto público `poc` e configura `/etc/containerd/certs.d/harbor.local/hosts.toml` em cada node kind para permitir pull do registry HTTP local.

O pipeline usa `skopeo` para publicar no Harbor sem exigir que o Docker daemon do host seja configurado globalmente como insecure registry.

O scanner interno do Harbor permanece desativado. O Trivy do Jenkins é o gate oficial e bloqueia imagens vulneráveis antes que sejam publicadas no registry, evitando duplicação de análise e consumo desnecessário de recursos no ambiente local.

## Assinatura de imagens

Depois do push, o pipeline resolve o digest imutável da imagem, assina esse
digest com Cosign e verifica a assinatura antes de permitir o deploy. A chave
privada, a chave pública e sua senha ficam no Secret
`poc/poc-image-signing`, criado automaticamente no primeiro pipeline. Nenhuma
chave é gravada no repositório ou em arquivo persistente do Jenkins.

Como o Harbor desta POC usa HTTP local e o ambiente não possui Rekor, o Cosign
usa uma configuração local sem transparency log. A verificação criptográfica
continua bloqueante; em produção, devem ser usados TLS, um transparency log e
uma chave protegida por KMS ou secret manager.

## Observabilidade

Grafana:

```text
http://grafana.local
```

As credenciais do Grafana são exibidas por:

```bash
make info
```

O `ServiceMonitor` coleta `/metrics` da aplicação. Para manter a demonstração
objetiva, os dashboards genéricos do `kube-prometheus-stack` ficam desativados
e cinco dashboards versionados são provisionados automaticamente:

- `POC App`: disponibilidade, targets, requisições, CPU, memória e logs da aplicação;
- `Kubernetes / Pods`: estado, restarts, CPU e memória dos pods;
- `Kubernetes / Nodes`: disponibilidade, CPU e memória dos nodes;
- `Alertmanager / POC`: alertas e notificações;
- `Prometheus / POC`: saúde, targets, regras, ingestão e armazenamento.

Os monitores de etcd, kube-proxy, scheduler e controller-manager ficam
desativados. No kind, esses endpoints de métricas não são publicados nos IPs
dos nodes e permaneceriam permanentemente `DOWN`; nodes, pods e aplicação
continuam sendo coletados normalmente.

O alerta `PocAppDown` entra em estado firing quando nenhum target saudável da
aplicação é encontrado por mais de um minuto:

```bash
kubectl get prometheusrule poc-app-alerts -n monitoring
```

Regras e alertas podem ser consultados em `http://prometheus.local/rules` e
`http://prometheus.local/alerts`.

O `AlertmanagerConfig` do chart encaminha somente `PocAppDown` para o webhook
`/alerts`. A chamada usa Bearer token lido do Secret da release, envia também a
notificação de recuperação e incrementa a métrica
`poc_alert_notifications_total{status="firing|resolved"}`.

Consulta Loki sugerida:

```text
{namespace="poc"}
```

Loki é instalado pelo chart mantido `grafana-community/loki` em modo
monolítico e efêmero, adequado ao volume desta POC. Promtail é instalado por
um chart separado para atender ao requisito explícito do desafio.

O Promtail foi mantido intencionalmente para aderência literal ao desafio,
apesar de estar descontinuado. Em uma evolução para produção, o agente de
coleta deve ser substituído pelo Grafana Alloy, preservando o Loki como backend
e as consultas LogQL existentes.

## HPA

```bash
kubectl get hpa -n poc
kubectl top pods -n poc
```

Configuração padrão:

```text
minReplicas: 2
maxReplicas: 5
target CPU: 70%
```

O teste de carga validado nesta POC levou o Deployment de 2 até 5 réplicas. Depois da retirada da carga, o HPA aguardou sua janela de estabilização e retornou automaticamente ao mínimo de 2 réplicas. Os eventos podem ser conferidos com:

```bash
kubectl describe hpa poc-app -n poc
```

## Segurança / Kyverno

Teste de negação:

```bash
kubectl run should-fail --image=nginx:latest
```

A admissão deve ser bloqueada pela policy `disallow-latest-tag`.

A policy também bloqueia imagens sem tag explícita e cobre `containers`, `initContainers` e `ephemeralContainers`. Imagens referenciadas por digest são aceitas.

O Deployment também aplica:

- `runAsNonRoot`;
- UID não-root;
- `readOnlyRootFilesystem`;
- `allowPrivilegeEscalation: false`;
- `seccompProfile: RuntimeDefault`;
- drop de todas as Linux capabilities;
- requests/limits;
- readiness e liveness probes.

## Deploy manual/local

Para um deploy rápido sem executar o pipeline:

```bash
make deploy TAG=1.0.1
```

Para demonstrar uma alteração visual, edite `app/static/index.html` e use uma
nova tag no comando. A página consulta `/info` para exibir o ambiente e a versão
implantada.

O fluxo faz build local, carrega a imagem nos nodes kind e executa Helm.
Esse comando é bloqueado quando o modo Argo CD está ativo.

## Rollback

O Deployment inclui checksums do ConfigMap e do Secret no pod template. Assim, alterações de configuração geram um RollingUpdate e também podem ser revertidas pelo histórico do Helm.

Rollback automático para a revisão anterior:

```bash
make rollback
```

Ou informe a revisão:

```bash
make rollback REV=2
```

Histórico:

```bash
helm history poc-app -n poc
```

Esses comandos valem para o modo Jenkins + Helm. No modo Argo CD, o rollback
deve alterar a tag desejada na `Application`; o `make rollback` é bloqueado para
evitar concorrência.

## Logs e troubleshooting

```bash
make status
make logs
```

`make logs` acompanha a saída continuamente; use `Ctrl+C` para encerrá-lo.

Comandos úteis:

```bash
kubectl get pods -n poc -o wide
kubectl describe pod -n poc <pod>
kubectl logs -n poc <pod>
kubectl get events -n poc --sort-by=.lastTimestamp
kubectl get ingress -A
kubectl top nodes
kubectl top pods -n poc
```

Para `ImagePullBackOff` do pipeline:

```bash
docker exec poc-devops-worker cat /etc/containerd/certs.d/harbor.local/hosts.toml
docker exec poc-devops-worker getent hosts harbor.local
kubectl describe pod -n poc <pod>
```

## Argo CD (opcional)

Instale o diferencial separadamente:

```bash
make argocd REPO_URL=https://github.com/sua-organizacao/seu-repositorio.git
```

Se o projeto já possuir um remote Git chamado `origin`, `REPO_URL` pode ser
omitido. O repositório precisa estar acessível pelo Argo CD; repositórios
privados exigem uma credencial cadastrada previamente.

O comando instala o Argo CD, cria a `Application` com `prune` e `selfHeal` e
preserva inicialmente a mesma imagem que já está em execução. A partir desse
momento, Jenkins continua executando testes, SonarQube, build, Trivy e push no
Harbor, mas não executa mais `helm upgrade`. Ele atualiza a versão desejada na
`Application` e aguarda o Argo CD concluir o deploy.

URL e credencial:

```bash
make info
```

Acesse:

```text
http://argocd.local
```

O chart continua vindo do repositório Git informado. Para uma evolução GitOps
estrita, o Jenkins passaria a gravar a nova tag em um repositório de configuração
em vez de atualizar o parâmetro da `Application` pela API Kubernetes.

## Relatório da entrega

### Decisões técnicas

A solução foi desenhada para ser totalmente reproduzível em uma máquina Linux,
sem depender de AWS, Azure, GCP ou outro provedor Cloud. O kind fornece um
cluster Kubernetes real sobre containers Docker, com baixo custo de recursos e
criação e remoção automatizadas.

O Jenkins foi adotado como ferramenta principal de CI. Sua configuração é
declarativa por meio de Jenkins Configuration as Code, e o pipeline permanece
versionado no `Jenkinsfile`. O Harbor funciona como registry local, enquanto o
Helm mantém o deployment da aplicação reproduzível. O Argo CD é opcional e,
quando ativado, torna-se o único responsável por aplicar a versão da aplicação
no cluster, evitando concorrência com o deploy direto do Jenkins.

A segurança é aplicada em camadas. O pipeline executa testes, análise SonarQube,
scan de secrets, scan de vulnerabilidades com Trivy e assinatura da imagem com
Cosign antes do deploy. No cluster, o Kyverno rejeita imagens sem versão ou com
tag `latest`, e a aplicação executa como usuário não-root, sem capabilities e
com filesystem somente leitura.

Prometheus e Grafana foram escolhidos para métricas, Loki e Promtail para logs e
Alertmanager para alertas. Os dashboards genéricos foram desativados e
substituídos por cinco dashboards direcionados à demonstração. O Promtail foi
mantido porque é citado no desafio, embora uma evolução deva utilizar Grafana
Alloy.

Senhas são solicitadas sem eco durante o bootstrap. O token do SonarQube é
gerado automaticamente, o kubeconfig usado pelo Jenkins fica em um diretório de
runtime protegido fora do repositório, e as chaves do Cosign ficam em um Secret
do Kubernetes.

### Dificuldades encontradas

Durante a execução completa foram identificados e corrigidos:

- agendamento do ingress-nginx no control-plane com taint;
- classe de Ingress ausente na instalação inicial do Harbor;
- ausência do Docker CLI na primeira imagem do Jenkins;
- sobreposição entre diretórios de fontes e testes no SonarQube;
- relatório de cobertura fora do filesystem do scanner;
- imagens com vulnerabilidades corrigíveis bloqueadas pelo Trivy;
- conflito entre os datasources Prometheus e Loki no Grafana;
- limite de annotation do CRD do Argo CD;
- targets de control plane indisponíveis no ambiente kind;
- ausência de rollout após alterações de ConfigMap e Secret.

As correções foram validadas com pipeline completo, publicação e assinatura da
imagem no Harbor, deploy no Kubernetes, coleta de métricas e logs, alertas
`firing` e `resolved`, bloqueio de imagens sem versão pelo Kyverno e escala do
HPA entre duas e cinco réplicas.

### Melhorias futuras

- substituir Promtail por Grafana Alloy, mantendo Loki e as consultas LogQL;
- adicionar TLS local confiável ao Harbor e aos Ingresses;
- evoluir para GitOps estrito, com atualização da tag em um repositório de
  configuração;
- implementar estratégia Blue/Green ou Canary;
- integrar o Alertmanager a um canal externo de notificação;
- migrar a `ClusterPolicy` legada do Kyverno para a API `policies.kyverno.io`
  antes da remoção definitiva de `kyverno.io/v1`;
- utilizar External Secrets ou SOPS para os secrets de laboratório;
- usar KMS ou secret manager para as chaves de assinatura;
- manter um espelho interno de imagens, charts e pacotes para execução offline.


## Limpeza

```bash
make down
```

Remove containers e volumes do CI, o cluster kind, os arquivos temporários e
as imagens criadas pelo projeto (`poc-app:*` e
`poc-devops-jenkins:latest`). Imagens-base e dependências permanecem no cache
do Docker para acelerar a próxima execução.

## Observações de segurança

As senhas de Harbor e Jenkins são exigidas por variável de ambiente e não são
persistidas na árvore do projeto. O token Sonar é gerado em memória e entregue
diretamente ao credential store do Jenkins. O kubeconfig usado pelo container
fica no diretório de runtime do usuário, fora do repositório, com permissão
`600`. Em produção, essas credenciais seriam fornecidas por um secret manager,
com TLS, autenticação centralizada e rotação automática.
