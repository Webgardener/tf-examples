KAFKA_POD  ?= kafka-0
KAFKA_BOOT ?= localhost:9092
KAFKA_BIN  ?= kafka-topics.sh        # adapte le chemin selon ta distrib

kafka-wait:
	@echo "Attente de Kafka (broker + leader)..."
	@for i in $$(seq 1 90); do \
	  out=$$(kubectl -n green exec $(KAFKA_POD) -- $(KAFKA_BIN) \
	         --bootstrap-server $(KAFKA_BOOT) --describe 2>/dev/null); \
	  if echo "$$out" | grep -q 'Leader:' && ! echo "$$out" | grep -q 'Leader: -1'; then \
	    echo "Kafka prêt, leaders disponibles"; exit 0; \
	  fi; \
	  sleep 2; \
	done; \
	echo "Timeout: Kafka sans leader"; exit 1
