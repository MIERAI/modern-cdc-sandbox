from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, to_date, expr
from pyspark.sql.types import StructType, StringType, IntegerType, TimestampType

# Initialize Spark with Iceberg and Nessie support
spark = SparkSession.builder \
    .appName("CDC-to-Iceberg-Ingestion") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.nessie", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.nessie.catalog-impl", "org.apache.iceberg.nessie.NessieCatalog") \
    .config("spark.sql.catalog.nessie.uri", "http://nessie:19120/api/v1") \
    .config("spark.sql.catalog.nessie.authentication.type", "NONE") \
    .config("spark.sql.catalog.nessie.ref", "main") \
    .config("spark.sql.catalog.nessie.warehouse", "s3a://modern-cdc-bucket/iceberg-warehouse") \
    .config("spark.sql.catalog.nessie.io-impl", "org.apache.iceberg.aws.s3.S3FileIO") \
    .config("spark.sql.catalog.nessie.s3.endpoint", "http://minio:9000") \
    .config("spark.sql.catalog.nessie.s3.path-style-access", "true") \
    .config("spark.sql.catalog.nessie.s3.access-key-id", "minio_admin") \
    .config("spark.sql.catalog.nessie.s3.secret-access-key", "minio_password") \
    .config("spark.sql.catalog.nessie.client.region", "us-east-1") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "minio_admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "minio_password") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

# Kafka source configuration
kafka_df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka-1:29092,kafka-2:29092,kafka-3:29092") \
    .option("subscribe", "prod.crm.public.orders") \
    .option("startingOffsets", "earliest") \
    .load()

# Debezium JSON Schema
schema = StructType() \
    .add("payload", StructType() \
        .add("after", StructType() \
            .add("id", IntegerType()) \
            .add("user_id", IntegerType()) \
            .add("product_id", IntegerType()) \
            .add("quantity", IntegerType()) \
            .add("created_at", TimestampType()) \
        ) \
    )

# Extract and Flatten
orders_df = kafka_df.selectExpr("CAST(value AS STRING)") \
    .select(from_json(col("value"), schema).alias("msg")) \
    .select("msg.payload.after.*") \
    .filter(col("id").isNotNull()) \
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
