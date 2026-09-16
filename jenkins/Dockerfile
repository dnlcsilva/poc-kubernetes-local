FROM jenkins/jenkins:lts-jdk21@sha256:c1e4c349365f6d16d88595b2c5f7e8ff39b8ae1d061f62420bac193b4b9616d0

ARG KUBECTL_VERSION=v1.37.0
ARG KUBECTL_SHA256=6129359f4e1f3848a5572ccb0b26cf28b8ca08cef38c95a765b2f64a2c961a2f
ARG HELM_VERSION=v3.22.0
ARG TRIVY_VERSION=v0.74.0
ARG COSIGN_VERSION=v3.1.3
ARG COSIGN_SHA256=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71
ARG DOCKER_VERSION=29.8.0

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl python3 python3-pip python3-venv \
       skopeo rsync \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
    && echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - \
    && chmod +x /usr/local/bin/kubectl

RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && install -m 0755 /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker.tgz /tmp/docker

RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tgz \
    && tar -xzf /tmp/helm.tgz -C /tmp \
    && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/helm.tgz /tmp/linux-amd64
RUN curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin "$TRIVY_VERSION"

RUN curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" \
      -o /usr/local/bin/cosign \
    && echo "${COSIGN_SHA256}  /usr/local/bin/cosign" | sha256sum -c - \
    && chmod +x /usr/local/bin/cosign

RUN jenkins-plugin-cli --plugins \
    configuration-as-code \
    workflow-aggregator \
    credentials-binding \
    pipeline-stage-view \
    timestamper

RUN apt-get purge -y git make unzip

COPY jenkins/casc/jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml
COPY jenkins/init.groovy.d/10-create-job.groovy /usr/share/jenkins/ref/init.groovy.d/10-create-job.groovy
COPY Jenkinsfile /opt/poc/Jenkinsfile

USER jenkins
