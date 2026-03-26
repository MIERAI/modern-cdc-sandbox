# Modern CDC Sandbox

An end-to-end, enterprise-grade Change Data Capture (CDC) playground.

This project simulates a high-performance data pipeline transferring real-time database changes into a Data Lake (Object Storage), optimized for high throughput and disaster recovery.

## Architecture

PostgreSQL -> Debezium -> Kafka -> Vector -> MinIO (S3)

- PostgreSQL: Source database with logical replication enabled.
- Debezium: Captures row-level changes (INSERT/UPDATE/DELETE) as events.
- Kafka: Acts as a resilient buffer (Persistence layer).
- Vector: Aggregates fine-grained events into compressed micro-batches.
- MinIO: High-performance S3-compatible object storage for data archiving.

## Key Features

- Peak Performance: Verified throughput of 130,000+ TPS on a standard developer machine.
- Disaster Recovery: Built-in Circuit Breaker mechanism using max_slot_wal_keep_size to protect the primary DB during downstream outages.
- Micro-batching: Automatically groups 1000s of small JSON events into a single compressed .gz file to minimize storage costs and API calls.
- Full Metadata: Captures DB-generated IDs, transaction IDs, and LSNs without secondary queries.

## Quick Start

### Prerequisites

Before you begin, ensure you have the following installed:
- Docker & Docker Compose (Latest version)
- Make (To run Makefile commands)
- Curl (To register connectors via API)
- Minimum 4GB RAM allocated to Docker

### 1. Launch Infrastructure
```bash
make up
```

### 2. Setup CDC Pipeline
```bash
make setup
```

### 3. Run Stress Test (100,000 Rows)
```bash
make stress-test
```

### 4. Verify Results
Visit the MinIO Console at http://localhost:9001 (User: minio_admin, Password: minio_password) to see the structured .json.gz files.

## Advanced Scenarios

This sandbox is designed for learning and testing:
- Consumer Lag Recovery: Stop Kafka and see how Postgres handles WAL accumulation.
- Self-Healing: Reboot the database and watch the pipeline automatically re-establish connectivity.
- Schema Evolution: Add columns to Postgres and observe how Debezium adapts.

## Production Readiness

While this sandbox is perfect for local experimentation, running a CDC pipeline at scale requires additional hardening (High Availability, Schema Registry, Monitoring).

Check out the [Production Readiness Guide](./docs/production-readiness.md) for a detailed breakdown of the gaps and solutions.

## License
MIT
