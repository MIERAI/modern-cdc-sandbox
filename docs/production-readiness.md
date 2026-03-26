# Production Readiness Guide

This document outlines the gaps between this Experimental Sandbox and a Enterprise Production Environment, providing a roadmap for scaling the CDC pipeline.

## 1. High Availability (HA) Architecture

| Component | Sandbox (Current) | Production Requirement |
| :--- | :--- | :--- |
| **Kafka** | Single Broker | 3-5 Nodes + KRaft (or Zookeeper Ensemble) |
| **PostgreSQL** | Single Instance | Patroni + Replication + Sentinel for Auto-Failover |
| **Debezium** | Standalone Mode | Distributed Mode (Connect Cluster) |
| **MinIO** | Local Container | Managed Service (GCS / AWS S3 / Azure Blob) |

## 2. Data Consistency & Schema Registry

In production, raw JSON is risky. A field change in Postgres could break downstream consumers.
- Solution: Implement Confluent Schema Registry.
- Format: Transition from JSON to Avro or Protobuf for schema enforcement and payload compression.

## 3. Security Hardening

- Encryption: TLS/SSL encryption for all data-in-transit (Postgres -> Kafka -> Vector -> GCS).
- Authentication: SASL/SCRAM for Kafka and RBAC for Database access.
- Network: VPC peering and Private Service Connect to avoid exposure to the public internet.

## 4. Observability (The "Blind Spot")

A production pipeline is useless if you don't know it's lagging.
- Metrics: Prometheus scraping Kafka JMX metrics and Debezium JMX.
- Visuals: Grafana Dashboards monitoring:
    - Consumer Lag: How many events behind is Kafka?
    - Replication Lag: Is Postgres holding too much WAL?
    - Sink Throughput: How many MiB/s are hitting GCS?

## 5. Circuit Breaker Configuration

The sandbox demonstrates max_slot_wal_keep_size. In production, this must be tuned:
- Calculation: Total Disk Space - (Snapshot Size * 1.2) = Safety Budget for WAL.
- Alerting: Trigger PagerDuty when WAL usage exceeds 70% of the budget.

---

## Moving to Production

To see a skeleton of a production-grade deployment, refer to docker-compose.prod.yml (available in this repo for reference, requires 16GB+ RAM).
