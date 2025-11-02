#!/bin/bash
# Promote user to admin
# Usage: ./user-promote-admin.sh CONTAINER_NAME USER_EMAIL

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

# Verify user exists
cursor.execute('SELECT role FROM user WHERE email = ?', ('$USER_EMAIL',))
result = cursor.fetchone()

if not result:
    print('Error: User $USER_EMAIL not found')
    exit(1)

if result[0] == 'admin':
    print('Info: User is already an admin')
    exit(0)

# Update user role to admin
cursor.execute('UPDATE user SET role = ? WHERE email = ?',
               ('admin', '$USER_EMAIL'))

conn.commit()
conn.close()

print('✅ Successfully promoted $USER_EMAIL to admin')
"

if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
