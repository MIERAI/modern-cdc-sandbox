# Modern CDC Sandbox Makefile


.PHONY: up down setup status stress-bulk stress-trickle stress-fury vector-top web-ui help \
	prod-up prod-down prod-setup spark-submit

# --- EXPERIMENTAL MODE (Single Node) ---
up:
	docker-compose up -d
	@echo "Waiting for services to be ready (60s)..."
	@sleep 60
	@echo "Creating MinIO bucket..."
	@docker exec $$(docker ps -qf "name=minio") mc alias set myminio http://localhost:9000 minio_admin minio_password
	@docker exec $$(docker ps -qf "name=minio") /bin/sh -c "mc ls myminio/modern-cdc-bucket >/dev/null 2>&1 || mc mb myminio/modern-cdc-bucket"

setup:
	@echo "Registering Debezium Postgres Source..."
	@curl -i -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d @config/source-config.json

# --- PRODUCTION MODE (Lakehouse / Iceberg) ---
prod-up: prod-down
	docker-compose -f docker-compose.prod.yml up -d
	@echo "Waiting for production cluster (90s)..."
	@sleep 90
	@docker exec $$(docker ps -qf "name=minio") mc alias set myminio http://localhost:9000 minio_admin minio_password
	@docker exec $$(docker ps -qf "name=minio") /bin/sh -c "mc ls myminio/modern-cdc-bucket >/dev/null 2>&1 || mc mb myminio/modern-cdc-bucket"

prod-setup:
	@echo "Registering CRM, ERP & Inventory Source Connectors..."
	@curl -i -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d @config/source-connectors/crm-source.json
	@curl -i -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d @config/source-connectors/erp-source.json
	@curl -i -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d @config/source-connectors/inventory-source.json

spark-submit:
	@echo "Submitting Iceberg Ingestion Job to Spark..."
	@echo "Note: If this fails with 'UnknownTopicOrPartitionException', run 'make stress-bulk' first to trigger topic creation."
	@docker exec mini-data-lake-cdc-spark-master-1 /opt/spark/bin/spark-submit \
		--master spark://spark-master:7077 \
		--conf spark.jars.ivy=/tmp/spark-ivy-cache \
		--packages org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.5.2,org.apache.iceberg:iceberg-nessie:1.5.2,org.apache.iceberg:iceberg-aws-bundle:1.5.2,org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.1,org.apache.hadoop:hadoop-aws:3.3.4 \
		--properties-file /config/iceberg/spark-defaults.conf \
		/scripts/iceberg-ingestion.py

prod-reset-checkpoint:
	@echo "Clearing Spark Checkpoints in MinIO..."
	@docker exec $$(docker ps -qf "name=minio") mc rm -r --force myminio/modern-cdc-bucket/checkpoints/orders || true

prod-down:
	docker-compose -f docker-compose.prod.yml down -v

# --- Common Utilities ---
# 3. Mode 1: Bulk Injection (100,000 rows at once)
stress-bulk:
	@echo "Mode 1: Bulk Injection starting..."
	@docker exec $$(docker ps -qf "name=postgres-crm") psql -U crm_user -d crm_db -c \
		"INSERT INTO users (username, email) SELECT 'user_' || i, 'user_' || i || '@example.com' FROM generate_series(1, 100) AS i ON CONFLICT DO NOTHING;"
	@docker exec $$(docker ps -qf "name=postgres-crm") psql -U crm_user -d crm_db -c \
		"INSERT INTO products (name, price, stock_count) SELECT 'product_' || i, (random()*100)::decimal(10,2), 1000 FROM generate_series(1, 100) AS i ON CONFLICT DO NOTHING;"
	@docker exec $$(docker ps -qf "name=postgres-crm") psql -U crm_user -d crm_db -c \
		"INSERT INTO orders (user_id, product_id, quantity, order_data) SELECT (random()*99+1)::int, (random()*99+1)::int, (random()*5+1)::int, '{\"source\": \"bulk\"}'::jsonb FROM generate_series(1, 100000) AS i;"

# 4. Mode 2: Continuous Trickle (Simulated real-time traffic)
stress-trickle:
	@echo "Mode 2: Continuous Trickle starting (Shell Loop)..."
	@echo "Press [Ctrl+C] to stop"
	@while true; do \
		docker exec $$(docker ps -qf "name=postgres-crm") psql -U crm_user -d crm_db -t -c \
			"INSERT INTO orders (user_id, product_id, quantity, order_data) \
			 SELECT (random()*99+1)::int, (random()*99+1)::int, (random()*5+1)::int, \
			 jsonb_build_object('source', 'trickle_shell', 'ts', now()) \
			 RETURNING 'Order Injected: User ' || user_id || ' -> Product ' || product_id;" \
			 | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'; \
		sleep 0.2; \
	done

# 5. Mode 3: Fury Mode (Extreme high-speed loop)
stress-fury:
	@echo "Mode 3: Fury Mode starting..."
	@docker exec $$(docker ps -qf "name=postgres-crm") psql -U crm_user -d crm_db -c "CALL start_fury_traffic(10);"

# 6. Observability
vector-top:
	@docker exec -it $$(docker ps -qf "name=vector") vector top

# 7. Cleanup
down:
	docker-compose down -v

# 8. Monitoring
web-ui:
	@echo "------------------------------------------------------------------"
	@echo "Kafka Console:   http://localhost:8080 (Real-time Message Flow)"
	@echo "MinIO Web UI:    http://localhost:9001 (minio_admin / minio_password)"
	@echo "Spark Master:    http://localhost:8081"
	@echo "Trino SQL UI:    http://localhost:8082"
	@echo "Nessie API:      http://localhost:19120"
	@echo "------------------------------------------------------------------"

help:
	@echo "Production (Lakehouse) Mode:"
	@echo "  make prod-up      - Launch full Spark/Iceberg cluster"
	@echo "  make prod-setup   - Register multi-source connectors"
	@echo "  make spark-submit - Start real-time Lakehouse ingestion"
	@echo "  make prod-down    - Wipe entire production environment"
	@echo ""
	@echo "Experimental Mode:"
	@echo "  make up / down    - Single node Dev setup"
	@echo "  make setup        - Register single source connector"
