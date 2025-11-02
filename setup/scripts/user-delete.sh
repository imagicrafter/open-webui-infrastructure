#!/bin/bash
# Delete user account with complete data cleanup
# Usage: ./user-delete.sh CONTAINER_NAME USER_EMAIL

CONTAINER_NAME="$1"
USER_EMAIL="$2"

if [ -z "$CONTAINER_NAME" ] || [ -z "$USER_EMAIL" ]; then
    echo "Error: Container name and user email required"
    exit 1
fi

# Execute comprehensive user deletion with cleanup
docker exec "$CONTAINER_NAME" python3 -c "
import sqlite3
import sys

conn = sqlite3.connect('/app/backend/data/webui.db')
cursor = conn.cursor()

# Get user info
cursor.execute('SELECT id, role, created_at, name FROM user WHERE email = ?', ('$USER_EMAIL',))
user = cursor.fetchone()

if not user:
    print('Error: User $USER_EMAIL not found')
    conn.close()
    exit(1)

user_id = user[0]
user_role = user[1]
user_created_at = user[2]
user_name = user[3] or 'Unknown'

# Check if this is the primary admin (first created)
cursor.execute('SELECT MIN(created_at) FROM user WHERE role = \"admin\"')
min_admin_timestamp = cursor.fetchone()[0]

if user_role == 'admin' and user_created_at == min_admin_timestamp:
    print('Error: Cannot delete primary admin')
    print('Promote another admin to primary first')
    conn.close()
    exit(1)

print(f'Deleting user: {user_name} ($USER_EMAIL)')
print(f'User ID: {user_id}')
print(f'Role: {user_role}')

# Begin comprehensive deletion
try:
    # 1. Delete chats and shared chats
    cursor.execute('SELECT id FROM chat WHERE user_id = ?', (user_id,))
    chat_ids = [row[0] for row in cursor.fetchall()]
    shared_chat_ids = [f'shared-{chat_id}' for chat_id in chat_ids]

    if shared_chat_ids:
        placeholders = ','.join('?' * len(shared_chat_ids))
        cursor.execute(f'DELETE FROM chat WHERE user_id IN ({placeholders})', shared_chat_ids)

    cursor.execute('DELETE FROM chat WHERE user_id = ?', (user_id,))
    chats_deleted = cursor.rowcount

    # 2. Delete OAuth sessions (not handled by Open WebUI)
    cursor.execute('DELETE FROM oauth_session WHERE user_id = ?', (user_id,))
    oauth_deleted = cursor.rowcount

    # 3. Delete memories (not handled by Open WebUI)
    cursor.execute('DELETE FROM memory WHERE user_id = ?', (user_id,))
    memories_deleted = cursor.rowcount

    # 4. Delete feedbacks (not handled by Open WebUI)
    cursor.execute('DELETE FROM feedback WHERE user_id = ?', (user_id,))
    feedbacks_deleted = cursor.rowcount

    # 5. Delete messages (channel messages, not handled by Open WebUI)
    cursor.execute('DELETE FROM message WHERE user_id = ?', (user_id,))
    messages_deleted = cursor.rowcount

    # 6. Delete message reactions
    cursor.execute('DELETE FROM message_reaction WHERE user_id = ?', (user_id,))
    reactions_deleted = cursor.rowcount

    # 7. Delete files (not handled by Open WebUI)
    cursor.execute('DELETE FROM file WHERE user_id = ?', (user_id,))
    files_deleted = cursor.rowcount

    # 8. Delete folders (not handled by Open WebUI)
    cursor.execute('DELETE FROM folder WHERE user_id = ?', (user_id,))
    folders_deleted = cursor.rowcount

    # 9. Remove from groups
    cursor.execute('DELETE FROM \"group\" WHERE user_ids LIKE ?', (f'%{user_id}%',))
    groups_updated = cursor.rowcount

    # 10. Delete auth record
    cursor.execute('DELETE FROM auth WHERE id = ?', (user_id,))
    auth_deleted = cursor.rowcount

    # 11. Delete user record
    cursor.execute('DELETE FROM user WHERE id = ?', (user_id,))
    user_deleted = cursor.rowcount

    conn.commit()

    print('✅ Successfully deleted user and all associated data:')
    print(f'   - Chats: {chats_deleted}')
    print(f'   - OAuth sessions: {oauth_deleted}')
    print(f'   - Memories: {memories_deleted}')
    print(f'   - Feedbacks: {feedbacks_deleted}')
    print(f'   - Channel messages: {messages_deleted}')
    print(f'   - Message reactions: {reactions_deleted}')
    print(f'   - Files: {files_deleted}')
    print(f'   - Folders: {folders_deleted}')
    print(f'   - Group memberships: {groups_updated}')
    print(f'   - Auth records: {auth_deleted}')
    print(f'   - User record: {user_deleted}')

except Exception as e:
    conn.rollback()
    print(f'Error during deletion: {e}')
    conn.close()
    exit(1)

conn.close()
"

if [ $? -eq 0 ]; then
    exit 0
else
    exit 1
fi
