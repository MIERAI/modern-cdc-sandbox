from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, to_date
from pyspark.sql.types import StructType, IntegerType, TimestampType

# Initialize Spark with exhaustive connection properties
spark = SparkSession.builder \
    .appName("CDC-to-Iceberg-Ingestion") \
    .config("spark.executor.memory", "2g") \
    .config("spark.driver.memory", "1g") \
    .config("spark.sql.catalog.nessie.s3.client.region", "us-east-1") \
    .config("spark.sql.catalog.nessie.s3.endpoint", "http://minio:9000") \
    .config("spark.sql.catalog.nessie.s3.path-style-access", "true") \
    .config("spark.sql.catalog.nessie.s3.access-key-id", "minio_admin") \
    .config("spark.sql.catalog.nessie.s3.secret-access-key", "minio_password") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minio_admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minio_password") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .config("spark.hadoop.fs.s3a.endpoint.region", "us-east-1") \
    .getOrCreate()

# Kafka source configuration
kafka_df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka-1:29092,kafka-2:29092,kafka-3:29092") \
    .option("subscribe", "prod.crm.public.orders") \
    .option("startingOffsets", "earliest") \
    .option("failOnDataLoss", "false") \
    .load()

# Debezium JSON Schema
schema = StructType() \
    .add("after", StructType() \
        .add("id", IntegerType()) \
        .add("user_id", IntegerType()) \
        .add("product_id", IntegerType()) \
        .add("quantity", IntegerType()) \
        .add("updated_at", TimestampType()) \
    )

# Extract, Flatten and Map columns
orders_df = kafka_df.selectExpr("CAST(value AS STRING)") \
    .select(from_json(col("value"), schema).alias("msg")) \
    .select("msg.after.*") \
    .filter(col("id").isNotNull()) \
    .withColumnRenamed("updated_at", "created_at") \
    .withColumn("event_date", to_date(col("created_at")))

# --- INITIALIZATION: Ensure Namespace and Table exist ---
print("Initializing Iceberg table structure...")
spark.sql("CREATE NAMESPACE IF NOT EXISTS nessie.db")
spark.sql("""
    CREATE TABLE IF NOT EXISTS nessie.db.orders (
        id INT,
        user_id INT,
        product_id INT,
        quantity INT,
        created_at TIMESTAMP,
        event_date DATE
    )
    USING iceberg
    PARTITIONED BY (event_date)
""")
print("Table structure ready.")

# Ingestion into Iceberg
query = orders_df.writeStream \
    .format("iceberg") \
    .outputMode("append") \
    .trigger(processingTime='10 seconds') \
    .option("checkpointLocation", "s3a://modern-cdc-bucket/checkpoints/orders") \
    .toTable("nessie.db.orders")

query.awaitTermination()
