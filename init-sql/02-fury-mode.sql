-- Fury Mode: High-speed internal loop for stress testing
CREATE OR REPLACE PROCEDURE start_fury_traffic(iterations INT)
LANGUAGE plpgsql
AS $$
BEGIN
  FOR i IN 1..iterations LOOP
    INSERT INTO orders (user_id, product_id, quantity, order_data)
    SELECT 
        (random()*99+1)::int, 
        (random()*99+1)::int, 
        (random()*5+1)::int, 
        '{"source": "fury_generator", "batch": ' || i || '}'::jsonb
    FROM generate_series(1, 10000); 
    
    COMMIT; -- Release WAL to Debezium frequently
  END LOOP;
END;
$$;
