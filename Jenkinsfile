pipeline {
  agent any

  environment {
    APP_VERSION = "1.0.${BUILD_NUMBER}"
    IMAGE = "harbor.local/poc/poc-app:${APP_VERSION}"
    COSIGN_KEY = 'k8s://poc/poc-image-signing'
    SONAR_HOST_URL = 'http://127.0.0.1:9000'
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Sync Source') {
      steps {
        sh '''
          rsync -a --delete \
            --exclude .git \
            --exclude .venv \
            --exclude __pycache__ \
            --exclude .pytest_cache \
            --exclude .coverage \
            --exclude coverage.xml \
            /workspace/ ./
        '''
      }
    }

    stage('Secret Scan') {
      steps {
        sh '''
          trivy fs \
            --scanners secret \
            --exit-code 1 \
            --skip-dirs .git \
            --skip-dirs .venv \
            .
        '''
      }
    }

    stage('Unit Tests') {
      steps {
        sh '''
          python3 -m venv .venv
          . .venv/bin/activate
          pip install --quiet --upgrade pip
          pip install --quiet -r app/requirements-dev.txt
          cd app
          python -m pytest -q --cov=main --cov-report=xml:coverage.xml
          sed -i -E 's#<source>[^<]+</source>#<source>/usr/src/app</source>#' coverage.xml
        '''
      }
    }

    stage('SonarQube SAST') {
      steps {
        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
          sh '''
            SCANNER_CONTAINER="sonar-scanner-${BUILD_TAG}"
            trap 'docker rm -f "${SCANNER_CONTAINER}" >/dev/null 2>&1 || true' EXIT

            docker create --name "${SCANNER_CONTAINER}" --network host \
              -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
              -e SONAR_TOKEN="${SONAR_TOKEN}" \
              sonarsource/sonar-scanner-cli@sha256:23ca0f137965d9dff2198074043fd48d386280bc5d0ccac8c8349cea4cf096a9 \
              -Dsonar.projectKey=poc-kubernetes-local \
              -Dsonar.sources=app \
              -Dsonar.tests=app/tests \
              -Dsonar.qualitygate.wait=true \
              -Dsonar.qualitygate.timeout=300 \
              -Dsonar.working.directory=/tmp/.scannerwork >/dev/null

            docker cp app "${SCANNER_CONTAINER}:/usr/src/app"
            docker cp sonar-project.properties "${SCANNER_CONTAINER}:/usr/src/sonar-project.properties"
            docker start -a "${SCANNER_CONTAINER}"
          '''
        }
      }
    }

    stage('Docker Build') {
      steps {
        sh 'docker build -t ${IMAGE} app'
      }
    }

    stage('Trivy Scan') {
      steps {
        sh 'trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed ${IMAGE}'
      }
    }

    stage('Push Harbor') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
          sh '''
            skopeo copy \
              --dest-tls-verify=false \
              --dest-creds "${HARBOR_USER}:${HARBOR_PASS}" \
              "docker-daemon:${IMAGE}" \
              "docker://${IMAGE}"
          '''
        }
      }
    }

    stage('Cosign') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'harbor-creds', usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
          sh '''
            set +x
            kubectl config use-context kind-poc-devops >/dev/null
            kubectl get namespace poc >/dev/null 2>&1 || kubectl create namespace poc >/dev/null

            key_prefix="/tmp/${BUILD_TAG}-cosign"
            trap 'rm -f "${key_prefix}.key" "${key_prefix}.pub"' EXIT

            if ! kubectl get secret poc-image-signing -n poc >/dev/null 2>&1; then
              export COSIGN_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
              cosign generate-key-pair \
                --output-key-prefix "${key_prefix}" \
                "${COSIGN_KEY}" >/dev/null
              unset COSIGN_PASSWORD
              echo '[INFO] Chave Cosign criada no Secret poc/poc-image-signing.'
            fi

            image_digest=$(skopeo inspect \
              --tls-verify=false \
              --creds "${HARBOR_USER}:${HARBOR_PASS}" \
              --format '{{.Digest}}' \
              "docker://${IMAGE}")
            image_repository="${IMAGE%:*}"
            image_by_digest="${image_repository}@${image_digest}"

            cosign sign --yes \
              --signing-config jenkins/cosign-signing-config.json \
              --allow-http-registry \
              --key "${COSIGN_KEY}" \
              --registry-username "${HARBOR_USER}" \
              --registry-password "${HARBOR_PASS}" \
              "${image_by_digest}" >/dev/null

            cosign verify \
              --allow-http-registry \
              --insecure-ignore-tlog=true \
              --key "${COSIGN_KEY}" \
              --registry-username "${HARBOR_USER}" \
              --registry-password "${HARBOR_PASS}" \
              "${image_by_digest}" >/dev/null

            echo "[OK] Assinatura Cosign verificada: ${image_by_digest}"
          '''
        }
      }
    }

    stage('Helm Lint') {
      steps {
        sh 'helm lint helm/poc-app'
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          kubectl config use-context kind-poc-devops

          if kubectl get application poc-app -n argocd >/dev/null 2>&1; then
            echo '[INFO] Modo GitOps ativo: solicitando o deploy ao Argo CD.'
            kubectl patch application poc-app -n argocd --type merge \
              --patch-file=/dev/stdin <<PATCH
{"spec":{"source":{"helm":{"parameters":[{"name":"image.repository","value":"harbor.local/poc/poc-app"},{"name":"image.tag","value":"${APP_VERSION}"},{"name":"image.pullPolicy","value":"Always"}]}}}}
PATCH
            kubectl annotate application poc-app -n argocd \
              argocd.argoproj.io/refresh=hard --overwrite

            deployed=false
            for i in $(seq 1 100); do
              current_image=$(kubectl get deployment poc-app -n poc \
                -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
              sync_status=$(kubectl get application poc-app -n argocd \
                -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
              health_status=$(kubectl get application poc-app -n argocd \
                -o jsonpath='{.status.health.status}' 2>/dev/null || true)
              if [ "$current_image" = "$IMAGE" ] \
                && [ "$sync_status" = 'Synced' ] \
                && [ "$health_status" = 'Healthy' ]; then
                deployed=true
                break
              fi
              sleep 3
            done

            if [ "$deployed" != true ]; then
              echo '[ERRO] Argo CD nao concluiu o deploy da imagem esperada.' >&2
              kubectl get application poc-app -n argocd -o wide >&2 || true
              exit 1
            fi
          else
            echo '[INFO] Modo Jenkins + Helm ativo.'
            helm upgrade --install poc-app helm/poc-app \
              -n poc --create-namespace \
              --set image.repository=harbor.local/poc/poc-app \
              --set image.tag=${APP_VERSION} \
              --set image.pullPolicy=Always \
              --wait --timeout 5m
          fi

          kubectl rollout status deployment/poc-app -n poc --timeout=180s
        '''
      }
    }

    stage('Smoke Test') {
      steps {
        sh '''
          for i in $(seq 1 20); do
            if curl --fail --silent --show-error -H 'Host: poc.local' http://127.0.0.1/healthz; then
              exit 0
            fi
            sleep 3
          done
          exit 1
        '''
      }
    }
  }

  post {
    always {
      sh 'docker image inspect ${IMAGE} >/dev/null 2>&1 && docker image rm ${IMAGE} >/dev/null 2>&1 || true'
    }
  }
}
