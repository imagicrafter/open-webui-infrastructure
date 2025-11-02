#!/bin/bash
# List users from Open WebUI database
# Usage: ./user-list.sh CONTAINER_NAME [filter]
# Filters: all (default), admin, non-admin, pending

CONTAINER_NAME="$1"
FILTER="${2:-all}"

if [ -z "$CONTAINER_NAME" ]; then
    echo "Error: Container name required"
    exit 1
fi

# Query database and return JSON
# Pass filter to Python to avoid quote escaping issues
docker exec "$CONTAINER_NAME" python3 -c "
import sqlite3
import json
import sys

conn = sqlite3.connect('/app/backend/data/webui.db')
cursor = conn.cursor()

# Build query based on filter
filter_type = '$FILTER'

if filter_type == 'admin':
    query = 'SELECT id, email, role, created_at, name FROM user WHERE role = ? ORDER BY created_at'
    cursor.execute(query, ('admin',))
elif filter_type == 'user':
    query = 'SELECT id, email, role, created_at, name FROM user WHERE role = ? ORDER BY created_at'
    cursor.execute(query, ('user',))
elif filter_type == 'pending':
    query = 'SELECT id, email, role, created_at, name FROM user WHERE role = ? ORDER BY created_at'
    cursor.execute(query, ('pending',))
elif filter_type == 'non-admin':
    query = 'SELECT id, email, role, created_at, name FROM user WHERE role IN (?, ?) ORDER BY created_at'
    cursor.execute(query, ('user', 'pending'))
else:
    query = 'SELECT id, email, role, created_at, name FROM user ORDER BY created_at'
    cursor.execute(query)

users = []
for row in cursor.fetchall():
    users.append({
        'id': row[0],
        'email': row[1],
        'role': row[2],
        'created_at': row[3],
        'name': row[4] if row[4] else ''
    })

conn.close()
print(json.dumps(users))
"
