# Kyverno n'est PAS sur docker.io : les images sont sur reg.kyverno.io
# (miroir ghcr.io). Il te faut un remote repo Artifactory dédié, ou un
# mapping vers ton proxy ghcr.io existant.
global:
  image:
    registry: ARTIFACTORY_PLACEHOLDER   # substitué par le Makefile

crds:
  install: true

config:
  # Vérifier AVANT de passer en Enforce :
  #   kubectl -n kyverno get cm kyverno -o jsonpath='{.data.resourceFilters}' | tr ']' ']\n'
  # Les defaults excluent déjà kube-system/kube-public/kube-node-lease/kyverno.
  excludeGroups:
    - system:nodes

  # Ceinture + bretelles sur le namespaceSelector du webhook.
  webhooks:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: [kube-system, kube-public, kube-node-lease, kyverno]

admissionController:
  replicas: 1
  container:
    resources:
      requests: { cpu: 100m, memory: 256Mi }
      limits:   { memory: 512Mi }
  initContainer:
    resources:
      requests: { cpu: 10m, memory: 64Mi }

backgroundController:
  enabled: true        # requis par les mutate SCC sur objets existants
  replicas: 1
  resources:
    requests: { cpu: 50m, memory: 128Mi }

reportsController:
  enabled: true        # requis par `make kyverno-violations`
  replicas: 1
  resources:
    requests: { cpu: 50m, memory: 128Mi }

cleanupController:
  enabled: false       # aucune Cleanup policy en local

# Ces deux hooks Helm tirent docker.io/bitnami/kubectl.
# Désactivés : on fait le cleanup en kubectl dans le Makefile.
webhooksCleanup:
  enabled: false
policyReportsCleanup:
  enabled: false






  KYVERNO_NS       ?= kyverno
KYVERNO_VERSION  ?= 3.5.1
KYVERNO_REGISTRY ?= $(ARTIFACTORY)/kyverno-remote

.PHONY: kyverno kyverno-images kyverno-policies kyverno-verify \
        kyverno-violations kyverno-uninstall

## Contrôle des images AVANT tout pull. À lancer une fois par bump de version.
kyverno-images:
	@helm template kyverno kyverno/kyverno \
	  --version $(KYVERNO_VERSION) -n $(KYVERNO_NS) \
	  -f manifests/local/kyverno-values.yaml \
	  --set global.image.registry=$(KYVERNO_REGISTRY) \
	  | grep -E '^\s+image:' | sort -u

kyverno:
	helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
	helm repo update kyverno
	kubectl create namespace $(KYVERNO_NS) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install kyverno kyverno/kyverno \
	  --version $(KYVERNO_VERSION) \
	  -n $(KYVERNO_NS) \
	  -f manifests/local/kyverno-values.yaml \
	  --set global.image.registry=$(KYVERNO_REGISTRY) \
	  --wait --timeout 5m
	kubectl -n $(KYVERNO_NS) rollout status deploy/kyverno-admission-controller  --timeout=180s
	kubectl -n $(KYVERNO_NS) rollout status deploy/kyverno-background-controller --timeout=180s
	kubectl -n $(KYVERNO_NS) rollout status deploy/kyverno-reports-controller    --timeout=180s
	$(MAKE) kyverno-policies
	$(MAKE) kyverno-verify

kyverno-policies:
	kubectl apply -f policies/
ifeq ($(ENV),local)
	kubectl apply -f manifests/local/storageclass-bnpp.yaml
	kubectl apply -f manifests/local/policies/
endif
	kubectl wait --for=condition=Ready --timeout=90s clusterpolicy --all

## Le webhook est enregistré dynamiquement : Ready sur la ClusterPolicy ne
## garantit pas que la ValidatingWebhookConfiguration est posée.
kyverno-verify:
	@echo ">> attente enregistrement des webhooks"
	@n=0; until kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg >/dev/null 2>&1; do \
	  n=$$((n+1)); [ $$n -ge 30 ] && echo "webhook jamais enregistré" && exit 1; \
	  sleep 2; \
	done
	@echo ">> webhooks OK"
	@kubectl get clusterpolicy -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[0].status,ACTION:.spec.rules[0].validate.failureAction

kyverno-violations:
	@kubectl get policyreport,clusterpolicyreport -A -o json \
	  | jq -r '.items[].results[]? | select(.result=="fail")
	      | "\(.resources[0].namespace // "-")/\(.resources[0].name)\t\(.policy)/\(.rule)\t\(.message)"' \
	  | sort -u

## Le chart ne nettoie plus ses webhooks (hooks désactivés) : on le fait ici,
## sinon des webhooks orphelins en failurePolicy=Fail gèlent le cluster.
kyverno-uninstall:
	-helm uninstall kyverno -n $(KYVERNO_NS)
	-kubectl delete validatingwebhookconfiguration -l webhook.kyverno.io/managed-by=kyverno
	-kubectl delete mutatingwebhookconfiguration   -l webhook.kyverno.io/managed-by=kyverno
	-kubectl delete ns $(KYVERNO_NS)





  init:
	...
	$(MAKE) kyverno          # avant tout déploiement applicatif
	...

start:
	k3d cluster start $(CLUSTER)
	... # wait node Ready, purge Terminating
	kubectl -n $(KYVERNO_NS) rollout status deploy/kyverno-admission-controller --timeout=180s
	$(MAKE) kyverno-verify
	... # ENSUITE seulement : force-recreate + rollout Postgres → Vault → Keycloak → gateway
	$(MAKE) tf-apply
