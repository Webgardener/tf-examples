ZK_POD ?= zookeeper-0     # <release>-zookeeper-0
ZK_BIN ?= /opt/bitnami/zookeeper/bin/zkCli.sh

kafka-wait:
	@echo "Attente de l'enregistrement du broker dans ZooKeeper..."
	@for i in $$(seq 1 90); do \
	  ids=$$(kubectl -n green exec $(ZK_POD) -- $(ZK_BIN) -server localhost:2181 ls /brokers/ids 2>/dev/null); \
	  if echo "$$ids" | grep -qE '\[[0-9]'; then \
	    echo "Broker enregistré dans ZK"; exit 0; \
	  fi; \
	  sleep 2; \
	done; \
	echo "Timeout: aucun broker dans /brokers/ids"; exit 1
