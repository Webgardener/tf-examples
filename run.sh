VAULT_NS       ?= green
VAULT_POD      ?= vault-0
VAULT_KEY_FILE ?= manifests/local/.vault-unseal-key

.PHONY: start vault-init vault-unseal vault-wait

start:
	k3d cluster start dmzrasc
	kubectl -n $(VAULT_NS) rollout status statefulset/vault --timeout=120s
	$(MAKE) vault-unseal

# Attend que l'API Vault réponde (code 0 = descellé, 2 = scellé, 1 = injoignable)
vault-wait:
	@echo "Attente de l'API Vault..."
	@for i in $$(seq 1 60); do \
	  code=$$(kubectl -n $(VAULT_NS) exec $(VAULT_POD) -- vault status >/dev/null 2>&1; echo $$?); \
	  if [ "$$code" = "0" ] || [ "$$code" = "2" ]; then exit 0; fi; \
	  sleep 1; \
	done; \
	echo "Timeout : Vault ne répond pas"; exit 1

# One-time : initialise Vault et sauvegarde la clé localement (gitignoré)
vault-init: vault-wait
	@if kubectl -n $(VAULT_NS) exec $(VAULT_POD) -- vault operator init -status >/dev/null 2>&1; then \
	  echo "Vault déjà initialisé"; \
	else \
	  echo "Initialisation de Vault..."; \
	  kubectl -n $(VAULT_NS) exec $(VAULT_POD) -- \
	    vault operator init -key-shares=1 -key-threshold=1 -format=json \
	    > $(VAULT_KEY_FILE).json; \
	  jq -r '.unseal_keys_b64[0]' $(VAULT_KEY_FILE).json > $(VAULT_KEY_FILE); \
	  echo "Clé d'unseal -> $(VAULT_KEY_FILE)"; \
	  echo "Root token   : $$(jq -r '.root_token' $(VAULT_KEY_FILE).json)"; \
	fi
	$(MAKE) vault-unseal

vault-unseal: vault-wait
	@if [ ! -f $(VAULT_KEY_FILE) ]; then \
	  echo "Pas de clé ($(VAULT_KEY_FILE)) — lance 'make vault-init' d'abord."; exit 1; \
	fi
	@if kubectl -n $(VAULT_NS) exec $(VAULT_POD) -- vault status >/dev/null 2>&1; then \
	  echo "Vault déjà descellé"; \
	else \
	  echo "Unseal..."; \
	  kubectl -n $(VAULT_NS) exec $(VAULT_POD) -- \
	    vault operator unseal "$$(cat $(VAULT_KEY_FILE))"; \
	fi
