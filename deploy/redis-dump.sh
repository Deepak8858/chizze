#!/bin/bash
PASS='Dream$8858'
redis-cli -a "$PASS" --no-auth-warning BGSAVE
sleep 2
sudo cp /var/lib/redis/dump.rdb /tmp/dump.rdb
sudo chmod 644 /tmp/dump.rdb
echo "=== DBSIZE ==="
redis-cli -a "$PASS" --no-auth-warning DBSIZE
echo "=== KEYS ==="
redis-cli -a "$PASS" --no-auth-warning KEYS '*' | head -50
