# Modern CDC Sandbox

An end-to-end, enterprise-grade Change Data Capture (CDC) playground.

This project simulates a high-performance data pipeline transferring real-time database changes into a Data Lake (Object Storage), optimized for high throughput and disaster recovery.

## Architecture

PostgreSQL -> Debezium -> Kafka -> Vector -> MinIO (S3)

```mermaid
graph LR
    subgraph "Production Zone"
        DB[(PostgreSQL)] -- "WAL Logs" --> Debezium
    end

    subgraph "Ingestion Pipeline"
        Debezium[Debezium Connect] -- "Real-time JSON" --> Kafka((Kafka Cluster))
        Kafka -- "View Data" --> Console[Redpanda Console]
    end

    subgraph "Aggregation Layer"
        Kafka -- "Continuous Stream" --> Vector[Vector Agent]
        Vector -- "Gzip & Batch" --> MinIO
    end

    subgraph "Data Lake"
        MinIO[MinIO / S3 Storage]
    end

    %% Styles
    style DB fill:#e1f5fe,stroke:#01579b
    style Kafka fill:#fff3e0,stroke:#e65100
    style MinIO fill:#f3e5f5,stroke:#4a148c
    style Vector fill:#f96,stroke:#333
    style Console fill:#ffcdd2,stroke:#b71c1c
```

- PostgreSQL: Source database with logical replication enabled.
- Debezium: Captures row-level changes (INSERT/UPDATE/DELETE) as events.
- Kafka: Acts as a resilient buffer (Persistence layer).
- Vector: Aggregates fine-grained events into compressed micro-batches.
- MinIO: High-performance S3-compatible object storage for data archiving.
- **Redpanda Console**: Web-based UI to visualize real-time message flow in Kafka.

## Key Features

- **Zero-Dependency Stress Tests**: No Python or external runtimes required (Docker-based).
- **Peak Performance**: Verified throughput of 130,000+ TPS on a standard developer machine.
- **Observability Stack**: Built-in real-time throughput dashboards and message inspectors.
- **Disaster Recovery**: Built-in Circuit Breaker mechanism using `max_slot_wal_keep_size` to protect the primary DB during downstream outages.
- **Micro-batching**: Automatically groups 1000s of small JSON events into a single compressed .gz file to minimize storage costs and API calls.

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

### 3. Run Stress Tests (Choose a Mode)

The sandbox provides three modes to simulate different business scenarios:

#### Mode 1: Bulk Injection
Inserts 100,000 rows in a single transaction. Useful for observing how CDC handles large spikes.
```bash
make stress-bulk
```

#### Mode 2: Continuous Trickle
Simulates real-time user traffic (5-10 orders per second) using a shell-based loop. **No Python required.**
```bash
make stress-trickle
```

#### Mode 3: Fury Mode
Extreme high-speed loop using internal DB procedures. Use this to test the physical limits of your hardware.
```bash
make stress-fury
```

### 4. Observability & Monitoring

The sandbox includes built-in tools to watch the data flow:

1.  **Kafka Console**: Open http://localhost:8080 to see real-time JSON messages passing through topics.
2.  **Throughput Dashboard**: Run `make vector-top` to see real-time ingestion/sink metrics (Events In/Out).
3.  **MinIO Web UI**: Open http://localhost:9001 (minio_admin / minio_password) to verify data partitioning in S3.

## Cleanup

To stop the environment, choose one of the following methods:

### Option 1: Full Teardown (Recommended)
Stops all containers and **deletes all data** (volumes). Use this to restore a clean state.
```bash
make down
```

### Option 2: Temporary Stop
Stops the containers but **preserves your data**. Use this if you want to resume later.
```bash
docker-compose stop
```
*To resume, run `docker-compose start`.*

## Advanced Scenarios

This sandbox is designed for learning and testing:
- **Consumer Lag Recovery**: Stop Kafka and see how Postgres handles WAL accumulation.
- **Self-Healing**: Reboot the database and watch the pipeline automatically re-establish connectivity.
- **Schema Evolution**: Add columns to Postgres and observe how Debezium adapts.

## Production Mode (Lakehouse / Iceberg)

For advanced users, this sandbox includes a **Production Mode** that simulates a modern Lakehouse architecture using **Apache Iceberg**, **Project Nessie**, and **Spark Streaming**.

### 1. Launch Production Cluster
This mode requires at least 16GB RAM allocated to Docker.
```bash
make prod-up
```

### 2. Register Multi-Source Connectors
```bash
make prod-setup
```

### 3. Initialize Data & Topics
**Important**: Debezium only creates Kafka topics when it detects data. If you start Spark before injecting data, it will fail with `UnknownTopicOrPartitionException`.
```bash
make stress-bulk
```

### 4. Start Spark Ingestion
```bash
make spark-submit
```

### 5. Query the Data Lake (via Trino)
Once the Spark job shows "numOutputRows: 100000", you can query the data using Trino:
```bash
docker exec mini-data-lake-cdc-trino-1 trino --execute "SELECT count(*) FROM iceberg.db.orders"
```

### Troubleshooting Production Mode

- **Topic Not Found**: If Spark fails to find a topic, ensure you've run `make stress-bulk` to trigger Debezium's capture.
- **Offset Mismatch / Data Loss Error**: If the Spark job fails after a restart with an offset error, reset the checkpoints:
  ```bash
  make prod-reset-checkpoint
  make spark-submit
  ```
- **Resource Constraints**: If Spark hangs with "Initial job has not accepted any resources", restart the Spark cluster:
  ```bash
  docker restart mini-data-lake-cdc-spark-master-1 mini-data-lake-cdc-spark-worker-1
  ```

---

## License
MIT
