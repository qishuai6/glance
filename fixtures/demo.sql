-- 用户表结构（含中文注释）
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);

/* 多行注释
   测试跨行 */
INSERT INTO users (id, name, email) VALUES (1, '七帅', 'qishuai@example.com');
SELECT * FROM users WHERE id = 42 AND name LIKE '%帅%';
