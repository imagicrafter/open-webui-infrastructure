#!/bin/bash
# Demote admin to user
# Usage: ./user-demote-admin.sh CONTAINER_NAME USER_EMAIL

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
cursor.execute('SELECT role, created_at FROM user WHERE email = ?', ('$USER_EMAIL',))
result = cursor.fetchone()

if not result:
    print('Error: User $USER_EMAIL not found')
    exit(1)

if result[0] != 'admin':
    print('Info: User is not an admin')
    exit(0)

# Check if this is the primary admin (first created)
cursor.execute('SELECT MIN(created_at) FROM user WHERE role = \"admin\"')
min_timestamp = cursor.fetchone()[0]

if result[1] == min_timestamp:
    print('Error: Cannot demote primary admin')
    print('Promote another admin to primary first')
    exit(1)

# Update user role to user
cursor.execute('UPDATE user SET role = ? WHERE email = ?',
               ('user', '$USER_EMAIL'))

conn.commit()
conn.close()

print('✅ Successfully demoted $USER_EMAIL to user')
"

if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
