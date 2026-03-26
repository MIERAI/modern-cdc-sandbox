import psycopg2
import time
import random
import json
import sys

# Connection configuration
try:
    conn = psycopg2.connect(
        host="localhost",
        port=5434,
        database="sandbox_db",
        user="sandbox_user",
        password="sandbox_pass"
    )
    conn.autocommit = True
    cursor = conn.cursor()
except Exception as e:
    print(f"Failed to connect to Postgres: {e}")
    sys.exit(1)

print("Continuous Traffic Generator Started (Trickle Mode)")
print("Press Ctrl+C to stop")

while True:
    try:
        user_id = random.randint(1, 100)
        product_id = random.randint(1, 100)
        qty = random.randint(1, 5)
        
        cursor.execute(
            "INSERT INTO orders (user_id, product_id, quantity, order_data) VALUES (%s, %s, %s, %s)",
            (user_id, product_id, qty, json.dumps({"source": "trickle_generator", "ts": time.time()}))
        )
        print(f"Order Injected: User {user_id} -> Product {product_id}", end='\r')
        
        # Simulating 5-10 orders per second
        time.sleep(random.uniform(0.1, 0.2))
        
    except KeyboardInterrupt:
        print("\nGenerator stopped")
        break
    except Exception as e:
        print(f"\nError: {e}")
        time.sleep(2)
