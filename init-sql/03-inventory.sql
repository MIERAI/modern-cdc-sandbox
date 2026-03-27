-- 模拟 ERP/库存系统的表
CREATE TABLE IF NOT EXISTS inventory (
    product_id INTEGER PRIMARY KEY,
    warehouse_id INTEGER,
    quantity INTEGER DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS warehouses (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    location VARCHAR(200)
);

-- 启用 WAL 高清摄像模式
ALTER TABLE inventory REPLICA IDENTITY FULL;
ALTER TABLE warehouses REPLICA IDENTITY FULL;

-- 初始数据
INSERT INTO warehouses (name, location) VALUES ('Central WH', 'New York'), ('West Coast WH', 'Los Angeles');
