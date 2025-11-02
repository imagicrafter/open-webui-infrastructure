#!/bin/bash
# Promote user to primary admin
# Usage: ./user-promote-primary.sh CONTAINER_NAME USER_EMAIL

CONTAINER_NAME="$1"
USER_EMAIL="$2"

if [ -z "$CONTAINER_NAME" ] || [ -z "$USER_EMAIL" ]; then
    echo "Error: Container name and user email required"
    exit 1
fi

# Execute database update
docker exec "$CONTAINER_NAME" python3 -c "
import sqlite3

conn = sqlite3.connect('/app/backend/data/webui.db')
cursor = conn.cursor()

# Verify user exists and is admin
cursor.execute('SELECT role FROM user WHERE email = ?', ('$USER_EMAIL',))
result = cursor.fetchone()

if not result:
    print('Error: User $USER_EMAIL not found')
    exit(1)

if result[0] != 'admin':
    print('Error: User must be admin to become primary admin')
    print('Current role: ' + result[0])
    exit(1)

# Get the earliest timestamp from any user
cursor.execute('SELECT MIN(created_at) FROM user')
min_timestamp = cursor.fetchone()[0]

# Set selected user to earliest timestamp - 1
new_timestamp = min_timestamp - 1

cursor.execute('UPDATE user SET created_at = ? WHERE email = ?',
               (new_timestamp, '$USER_EMAIL'))

conn.commit()
conn.close()

print('✅ Successfully promoted $USER_EMAIL to primary admin')
print('User is now first in creation order')
"

if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
