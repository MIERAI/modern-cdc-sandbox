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
- Python 3 & psycopg2 (Required for stress-trickle mode)
- Minimum 4GB RAM allocated to Docker

### 1. Launch Infrastructure
```bash
make up
```

### 2. Setup CDC Pipeline
```bash
make setup
```

### 3. Run Stress Tests (Choose a Mode)

The sandbox provides three modes to simulate different business scenarios:

#### Mode 1: Bulk Injection
Inserts 100,000 rows in a single transaction. Useful for observing how CDC handles large spikes.
```bash
make stress-bulk
```

#### Mode 2: Continuous Trickle
Simulates real-time user traffic (5-10 orders per second). Great for watching live data flow.
```bash
make stress-trickle
```

#### Mode 3: Fury Mode
Extreme high-speed loop using internal DB procedures. Use this to test the physical limits of your hardware.
```bash
make stress-fury
```

### 4. Verify Results

1. **Web UI**: Open http://localhost:9001 (User: `minio_admin`, Password: `minio_password`).
2. **Data Lake**: Navigate to `modern-cdc-bucket` -> `cdc-raw`.
3. **Structure**: Data is automatically partitioned by table and date:
   `cdc-raw/sandbox.public.orders/date=YYYY-MM-DD/xxxx.log.gz`
4. **Content**: Download and unzip a file to see the standard Debezium JSON format containing the `after` image and the database-generated `id`.

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
