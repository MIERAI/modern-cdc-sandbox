# Production Readiness Guide

This document outlines the gaps between this Experimental Sandbox and a Enterprise Production Environment, providing a roadmap for scaling the CDC pipeline.

## 1. High Availability (HA) Architecture

| Component | Sandbox (Current) | Production Requirement |
| :--- | :--- | :--- |
| **Kafka** | Single Broker | 3-5 Nodes + KRaft (or Zookeeper Ensemble) |
| **PostgreSQL** | Single Instance | Patroni + Replication + Sentinel for Auto-Failover |
| **Debezium** | Standalone Mode | Distributed Mode (Connect Cluster) |
| **MinIO** | Local Container | Managed Service (GCS / AWS S3 / Azure Blob) |

## 2. Operational Risks & Mitigations (Crucial)

### Risk 1: The "Catch-up Spike" (CPU Exhaustion)
**Scenario**: If the CDC Pod (Debezium) or Downstream (Kafka) is down for 1 hour, a massive amount of WAL logs will accumulate in Postgres.
**Problem**: Upon restart, Debezium will attempt to "catch up" by reading all pending logs at maximum speed. This causes a **massive CPU spike** on the Primary DB, potentially throttling your main business application.
**Mitigation**:
- **Throttling**: Limit Debezium processing speed using `max.batch.size` and `poll.interval.ms`.
- **Read-Only Extraction**: Upgrade to **PostgreSQL 16+** and enable logical decoding from a **Read-Only Standby**. This physically isolates the extraction load from the primary write traffic.

### Risk 2: WAL Accumulation (Disk Overflow)
**Scenario**: If Kafka is unreachable for a long period (e.g., a weekend).
**Problem**: The Replication Slot will hold WAL logs on the DB disk. At 132GB/day, this can fill up 1TB of disk space in a few days.
**Mitigation**:
- **Circuit Breaker**: Set `max_slot_wal_keep_size` (e.g., 200GB). It's better to lose the sync lag than to crash the entire production database.
- **Monitoring**: Alert when `pg_replication_slots.active` is `false` or lag exceeds 50GB.

### Risk 3: Downstream Bottleneck (Cascading Failure)
**Scenario**: GCS or S3 experiences a slow-down or outage.
**Problem**: High-frequency JSON events (280M+ per day) will pile up in Kafka. If Kafka's disk is too small, it will stop accepting new data from Debezium.
**Mitigation**:
- **Kafka Retention**: Set a strict `retention.bytes` policy on Kafka topics.
- **Backpressure**: Vector/Kafka Connect should have dedicated monitoring for sink errors.

## 3. Data Consistency & Schema Registry

In production, raw JSON is risky. A field change in Postgres could break downstream consumers.
- Solution: Implement Confluent Schema Registry.
- Format: Transition from JSON to Avro or Protobuf for schema enforcement and payload compression.

## 4. Security Hardening

- Encryption: TLS/SSL encryption for all data-in-transit (Postgres -> Kafka -> Vector -> GCS).
- Authentication: SASL/SCRAM for Kafka and RBAC for Database access.

---

## Moving to Production

To see a skeleton of a production-grade deployment, refer to docker-compose.prod.yml (available in this repo for reference, requires 16GB+ RAM).
