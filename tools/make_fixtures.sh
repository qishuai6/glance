#!/bin/bash
# 生成各格式测试样例文件
set -e
cd "$(dirname "$0")/.."
mkdir -p fixtures
F=fixtures

cat > "$F/sample.md" <<'MDEOF'
# 秒览 Glance 测试文档

这是 **Markdown** 预览测试，包含 *斜体*、~~删除线~~、`行内代码` 和[链接](https://qishuai.vip)。

## 列表

- 复利思维
- 长期主义
  - 嵌套项：微习惯
- [ ] 待办：发一条视频
- [x] 已完成：写口播稿

## 表格

| 标的 | 年化 |
| --- | --- |
| 纳指 ETF | 12.5% |
| 标普 ETF | 10.2% |

## 代码块

```sql
SELECT name, email FROM users WHERE id = 42;
```

> 引用块：普通人别想一夜暴富，做有复利的事。

---

结束。
MDEOF

cat > "$F/demo.sql" <<'EOF'
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
EOF

cat > "$F/data.json" <<'EOF'
{
  "name": "秒览",
  "version": 1.0,
  "tags": ["markdown", "zip", "sql"],
  "config": {
    "debug": false,
    "retries": 3,
    "timeout": 30.5,
    "parent": null
  },
  "items": [
    {"id": 1, "title": "第一项"},
    {"id": 2, "title": "第二项"}
  ]
}
EOF

printf '姓名,城市,粉丝数\n七帅,郑州,8332\n小李,北京,120\n"带,逗号的人",上海,55\n' > "$F/data.csv"
printf '字段1\t字段2\t字段3\n甲\t乙\t丙\n1\t2\t3\n' > "$F/data.tsv"

cat > "$F/config.yaml" <<'EOF'
# 站点配置
site:
  name: qishuai.vip
  port: 443
  debug: false
servers:
  - host: 1.2.3.4
    weight: 5
  - host: 5.6.7.8
    weight: 3
cache:
  enabled: true
  ttl: 300
EOF

cat > "$F/config.toml" <<'EOF'
# 应用配置
[database]
server = "192.168.1.1"
ports = [8001, 8001, 8002]
enabled = true

[servers.alpha]
ip = "10.0.0.1"
EOF

cat > "$F/app.log" <<'EOF'
2026-09-24 09:30:01 INFO [main] 服务启动完成
2026-09-24 09:30:15 DEBUG [db] 连接池初始化 size=10
2026-09-24 09:31:02 WARN [api] 请求超时 2500ms
2026-09-24 09:32:44 ERROR [pay] 支付回调失败 order=8899
2026-09-24 09:33:10 INFO [main] 重试成功
EOF

cat > "$F/demo.swift" <<'EOF'
import SwiftUI

/* 秒览窗口 */
struct ContentView: View {
    @State private var name = "七帅"
    var body: some View {
        VStack(spacing: 12) {
            Text("你好，\(name)")
                .font(.title)
            Button("打招呼") {
                name = "世界" // 更新状态
            }
        }
    }
}
EOF

cat > "$F/demo.py" <<'EOF'
#!/usr/bin/env python3
# 复利计算
def compound(principal: float, rate: float, years: int) -> float:
    """每年复投一次"""
    for _ in range(years):
        principal *= (1 + rate)
    return principal

if __name__ == "__main__":
    print(compound(10000, 0.125, 22))
EOF

cat > "$F/demo.js" <<'EOF'
// 定投计算器
const annualInvest = 10000;
const years = 22;
let total = 0;
for (let i = 0; i < years; i++) {
  total = (total + annualInvest) * 1.125;
}
console.log(`22 岁账户: ${total.toFixed(0)} 元`);
EOF

python3 - <<'PYEOF'
import zipfile, tarfile, io, os
os.chdir("fixtures")

# zip：含中文文件名与子目录
with zipfile.ZipFile("demo.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("projects/秒览/README.md", "# 秒览\n空格预览一切")
    z.writestr("projects/秒览/main.swift", "print(1)")
    z.writestr("assets/logo.txt", "logo data")
    z.writestr("notes.txt", "普通文本条目")

# tar
with tarfile.open("demo.tar", "w") as t:
    data = b"hello tar"
    info = tarfile.TarInfo("docs/readme.txt"); info.size = len(data)
    t.addfile(info, io.BytesIO(data))
    info = tarfile.TarInfo("src/app.py"); info.size = len(data) * 3
    t.addfile(info, io.BytesIO(data * 3))

# tar.gz
with tarfile.open("demo.tgz", "w:gz") as t:
    data = b"gzip content"
    info = tarfile.TarInfo("big/file.bin"); info.size = len(data)
    t.addfile(info, io.BytesIO(data))
    info = tarfile.TarInfo("big/说明.md"); info.size = len(data)
    t.addfile(info, io.BytesIO(data))
print("archives done")
PYEOF

ls -la $F/
