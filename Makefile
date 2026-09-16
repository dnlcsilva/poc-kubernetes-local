SHELL := /bin/bash
.DEFAULT_GOAL := help
TAG ?= 1.0.0
REV ?=
REPO_URL ?= $(shell git config --get remote.origin.url 2>/dev/null)

.PHONY: help up info status test down check argocd deploy logs rollback

help:
	@printf '%s\n' \
	  'POC Kubernetes Local' \
	  '' \
	  '  make check   Valida os pre-requisitos locais' \
	  '  make up      Sobe a POC obrigatoria' \
	  '  make info    Mostra URLs e credenciais' \
	  '  make status  Mostra a saude dos componentes' \
	  '  make test    Executa as validacoes locais' \
	  '  make down    Remove a POC' \
	  '' \
	  'Operacao:' \
	  '  make logs                    Mostra os logs da aplicacao' \
	  '  make deploy TAG=1.0.1        Faz deploy local com Helm' \
	  '  make rollback [REV=2]        Reverte o release Helm' \
	  '' \
	  'Opcional:' \
	  '  make argocd REPO_URL=https://...  Ativa o CD pelo Argo CD' \
	  ''

check:
	./scripts/check-prereqs.sh

up:
	TAG=$(TAG) ./scripts/up.sh

info:
	./scripts/show-info.sh

argocd:
	./scripts/configure-hosts.sh
	REPO_URL="$(REPO_URL)" ./scripts/install-argocd.sh

deploy:
	./scripts/deploy-app.sh $(TAG)

test:
	./scripts/test.sh

status:
	./scripts/ops.sh status

logs:
	./scripts/ops.sh logs

rollback:
	./scripts/ops.sh rollback $(REV)

down:
	./scripts/destroy.sh
