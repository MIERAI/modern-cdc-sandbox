# Modern CDC Sandbox Makefile

.PHONY: up down setup status stress-test web-ui

# 1. 启动所有基础设施
up:
	cd modern-cdc-sandbox && docker-compose up -d
	@echo "Waiting for services to be ready..."
	@sleep 30
	@echo "Creating MinIO bucket..."
	@docker exec modern-cdc-sandbox-minio-1 mc alias set myminio http://localhost:9000 minio_admin minio_password
	@docker exec modern-cdc-sandbox-minio-1 mc mb myminio/modern-cdc-bucket || true

# 2. 注册 CDC 连接器
setup:
	@echo "Registering Debezium Postgres Source..."
	@curl -X POST -H "Content-Type:application/json" localhost:8083/connectors/ -d '@modern-cdc-sandbox/config/source-config.json'

# 3. 停止并清理
down:
	cd modern-cdc-sandbox && docker-compose down -v

# 4. 一键压测 (10万条订单)
stress-test:
	@echo "Injecting 100,000 randomized orders into Postgres..."
	@docker exec modern-cdc-sandbox-postgres-1 psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO users (username, email) SELECT 'user_' || i, 'user_' || i || '@example.com' FROM generate_series(1, 100) AS i;"
	@docker exec modern-cdc-sandbox-postgres-1 psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO products (name, price, stock_count) SELECT 'product_' || i, (random()*100)::decimal(10,2), 1000 FROM generate_series(1, 100) AS i;"
	@docker exec modern-cdc-sandbox-postgres-1 psql -U sandbox_user -d sandbox_db -c \
		"INSERT INTO orders (user_id, product_id, quantity, order_data) \
		 SELECT (random()*99+1)::int, (random()*99+1)::int, (random()*5+1)::int, '{\"source\": \"mobile\", \"campaign\": \"summer_sale\"}'::jsonb \
		 FROM generate_series(1, 100000) AS i;"

# 5. 查看组件控制台地址
web-ui:
	@echo "MinIO Web UI:    http://localhost:9001 (minio_admin / minio_password)"
	@echo "Kafka Connect:   http://localhost:8083/connectors"
	@echo "Postgres Port:   5434"
