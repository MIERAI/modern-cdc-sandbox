# Modern CDC Sandbox Makefile

.PHONY: up down setup status stress-bulk stress-trickle stress-fury web-ui help

# 1. Infrastructure
up:
	docker-compose up -d
	@echo "Waiting for services to be ready (60s)..."
	@sleep 60
	@echo "Creating MinIO bucket..."
	@docker exec $$(docker ps -qf "name=minio") mc alias set myminio http://localhost:9000 minio_admin minio_password
	@docker exec $$(docker ps -qf "name=minio") mc mb myminio/modern-cdc-bucket || true

# 2. Setup
setup:
	@echo "Registering Debezium Postgres Source..."
	@curl -i -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d @config/source-config.json

# 3. Mode 1: Bulk Injection (100,000 rows at once)
stress-bulk:
	@echo "Mode 1: Bulk Injection starting..."
	@docker exec $$(docker ps -qf "name=postgres") psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO users (username, email) SELECT 'user_' || i, 'user_' || i || '@example.com' FROM generate_series(1, 100) AS i ON CONFLICT DO NOTHING;"
	@docker exec $$(docker ps -qf "name=postgres") psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO products (name, price, stock_count) SELECT 'product_' || i, (random()*100)::decimal(10,2), 1000 FROM generate_series(1, 100) AS i ON CONFLICT DO NOTHING;"
	@docker exec $$(docker ps -qf "name=postgres") psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO orders (user_id, product_id, quantity, order_data) SELECT (random()*99+1)::int, (random()*99+1)::int, (random()*5+1)::int, '{\"source\": \"bulk\"}'::jsonb FROM generate_series(1, 100000) AS i;"

# 4. Mode 2: Continuous Trickle (Simulated real-time traffic)
stress-trickle:
	@echo "Mode 2: Continuous Trickle starting..."
	@python3 scripts/traffic-generator.py

# 5. Mode 3: Fury Mode (Extreme high-speed loop)
stress-fury:
	@echo "Mode 3: Fury Mode starting..."
	@docker exec $$(docker ps -qf "name=postgres") psql -U sandbox_user -d sandbox_db -c "CALL start_fury_traffic(10);"

# 6. Cleanup
down:
	docker-compose down -v

# 7. Monitoring
web-ui:
	@echo "------------------------------------------------------------------"
	@echo "MinIO Web UI:    http://localhost:9001 (minio_admin / minio_password)"
	@echo "Kafka Connect:   http://localhost:8083/connectors"
	@echo "Postgres Port:   5434"
	@echo "------------------------------------------------------------------"

help:
	@echo "Available stress modes:"
	@echo "  make stress-bulk    - Insert 100k rows in one shot"
	@echo "  make stress-trickle - Continuous slow traffic (Python)"
	@echo "  make stress-fury    - Extreme high-speed internal loop"
