#!/bin/bash
# Check Active Users Script
# Usage: bash 0-check-active-users.sh <container-name>

CONTAINER_NAME=$1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container-name>"
    echo
    echo "Available containers:"
    docker ps --format '{{.Names}}' | grep openwebui
    exit 1
fi

# Check if container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ ERROR: Container '$CONTAINER_NAME' not found or not running${NC}"
    exit 1
fi

echo -e "${BLUE}=== Active User Check ===${NC}"
echo "Container: $CONTAINER_NAME"
echo "Time: $(date)"
echo

# Extract CLIENT_ID from container name
CLIENT_ID="${CONTAINER_NAME#openwebui-}"

# Determine database location (check both volume and bind mount)
DB_PATH=""

# Check if using bind mount
if docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Type}} {{end}}' | grep -q "bind"; then
    # Using bind mounts
    BIND_MOUNT=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Source}}{{end}}{{end}}')
    if [ -n "$BIND_MOUNT" ]; then
        DB_PATH="${BIND_MOUNT}/webui.db"
    fi
else
    # Using Docker volume
    VOLUME_NAME=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/app/backend/data"}}{{.Name}}{{end}}{{end}}')
    if [ -n "$VOLUME_NAME" ]; then
        DB_PATH="/var/lib/docker/volumes/${VOLUME_NAME}/_data/webui.db"
    fi
fi

if [ -z "$DB_PATH" ]; then
    echo -e "${RED}❌ ERROR: Could not determine database location${NC}"
    exit 1
fi

echo -e "${BLUE}Database location:${NC} $DB_PATH"
echo

# Check if database is accessible
if [ ! -f "$DB_PATH" ] && ! sudo test -f "$DB_PATH"; then
    echo -e "${RED}❌ ERROR: Database not found at $DB_PATH${NC}"
    exit 1
fi

# Function to run SQLite query
# Try multiple methods: Python in container, sqlite3 CLI, or Python on host
run_query() {
    local query="$1"
    local result=""

    # Method 1: Try Python in Docker container (most reliable)
    result=$(docker exec "$CONTAINER_NAME" python3 -c "
import sqlite3
import sys
try:
    conn = sqlite3.connect('/app/backend/data/webui.db')
    cursor = conn.execute(\"\"\"$query\"\"\")
    for row in cursor:
        print('|'.join(str(x) if x is not None else '' for x in row))
    conn.close()
except Exception as e:
    sys.exit(1)
" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # Method 2: Try sqlite3 CLI if available
    if command -v sqlite3 &>/dev/null; then
        if [ -r "$DB_PATH" ]; then
            result=$(sqlite3 "$DB_PATH" "$query" 2>/dev/null)
        else
            result=$(sudo sqlite3 "$DB_PATH" "$query" 2>/dev/null)
        fi

        if [ $? -eq 0 ]; then
            echo "$result"
            return 0
        fi
    fi

    # Method 3: Try Python on host
    if command -v python3 &>/dev/null; then
        result=$(python3 -c "
import sqlite3
import sys
try:
    conn = sqlite3.connect('$DB_PATH')
    cursor = conn.execute(\"\"\"$query\"\"\")
    for row in cursor:
        print('|'.join(str(x) if x is not None else '' for x in row))
    conn.close()
except:
    sys.exit(1)
" 2>/dev/null)

        if [ $? -eq 0 ]; then
            echo "$result"
            return 0
        fi
    fi

    return 1
}

# 1. Check total registered users
echo -e "${BLUE}1. Registered Users${NC}"
TOTAL_USERS=$(run_query "SELECT COUNT(*) FROM user;" 2>/dev/null || echo "0")
ACTIVE_USERS=$(run_query "SELECT COUNT(*) FROM user WHERE last_active_at IS NOT NULL;" 2>/dev/null || echo "0")
TOTAL_USERS=${TOTAL_USERS:-0}
ACTIVE_USERS=${ACTIVE_USERS:-0}
echo "   Total users: $TOTAL_USERS"
echo "   Users who have logged in: $ACTIVE_USERS"
echo

# 2. Check recent activity (last 24 hours)
echo -e "${BLUE}2. Recent Activity (Last 24 Hours)${NC}"
RECENT_ACTIVE=$(run_query "SELECT COUNT(DISTINCT user_id) FROM chat WHERE updated_at > datetime('now', '-24 hours');" 2>/dev/null || echo "0")
RECENT_ACTIVE=${RECENT_ACTIVE:-0}
echo "   Users active in last 24h: $RECENT_ACTIVE"

# 3. Check very recent activity (last hour)
echo -e "${BLUE}3. Very Recent Activity (Last Hour)${NC}"
HOUR_ACTIVE=$(run_query "SELECT COUNT(DISTINCT user_id) FROM chat WHERE updated_at > datetime('now', '-1 hour');" 2>/dev/null || echo "0")
HOUR_ACTIVE=${HOUR_ACTIVE:-0}
echo "   Users active in last hour: $HOUR_ACTIVE"

if [ "$HOUR_ACTIVE" -gt 0 ]; then
    echo -e "   ${YELLOW}⚠️  WARNING: Users active within the last hour!${NC}"
fi
echo

# 4. Check active sessions (if session table exists)
echo -e "${BLUE}4. Active Sessions${NC}"
SESSION_TABLE=$(run_query "SELECT name FROM sqlite_master WHERE type='table' AND name='session';")
if [ -n "$SESSION_TABLE" ]; then
    ACTIVE_SESSIONS=$(run_query "SELECT COUNT(*) FROM session WHERE expires_at > datetime('now');")
    echo "   Active sessions: $ACTIVE_SESSIONS"

    if [ "$ACTIVE_SESSIONS" -gt 0 ]; then
        echo -e "   ${YELLOW}⚠️  WARNING: Active sessions detected!${NC}"
        echo
        echo "   Recent sessions:"
        run_query "SELECT user_id, created_at, expires_at FROM session WHERE expires_at > datetime('now') ORDER BY created_at DESC LIMIT 5;" | while read line; do
            echo "     - $line"
        done
    fi
else
    echo "   Session table not found (using alternative method)"
fi
echo

# 5. Check last activity timestamp
echo -e "${BLUE}5. Most Recent Activity${NC}"
LAST_ACTIVITY=$(run_query "SELECT MAX(updated_at) FROM chat;")
if [ -n "$LAST_ACTIVITY" ] && [ "$LAST_ACTIVITY" != "0" ]; then
    # Check if timestamp is already an epoch (numeric) or datetime string
    if [[ "$LAST_ACTIVITY" =~ ^[0-9]+$ ]]; then
        # Already epoch timestamp
        LAST_EPOCH=$LAST_ACTIVITY
        # Convert to human readable
        LAST_ACTIVITY_HR=$(date -d "@$LAST_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$LAST_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
        echo "   Last chat activity: ${LAST_ACTIVITY_HR:-$LAST_ACTIVITY}"
    else
        # Datetime string, convert to epoch
        echo "   Last chat activity: $LAST_ACTIVITY"
        LAST_EPOCH=$(run_query "SELECT strftime('%s', MAX(updated_at)) FROM chat;")
    fi

    # Calculate time since last activity
    LAST_EPOCH=${LAST_EPOCH:-0}
    NOW_EPOCH=$(date +%s)

    if [ "$LAST_EPOCH" -gt 0 ]; then
        MINUTES_AGO=$(( ($NOW_EPOCH - $LAST_EPOCH) / 60 ))
    else
        MINUTES_AGO=9999
    fi

    if [ "$MINUTES_AGO" -lt 5 ]; then
        echo -e "   ${RED}⚠️  ACTIVE NOW: Last activity $MINUTES_AGO minutes ago!${NC}"
    elif [ "$MINUTES_AGO" -lt 30 ]; then
        echo -e "   ${YELLOW}⚠️  Recent: Last activity $MINUTES_AGO minutes ago${NC}"
    elif [ "$MINUTES_AGO" -lt 1440 ]; then
        HOURS_AGO=$(( $MINUTES_AGO / 60 ))
        echo -e "   ${GREEN}✓ Last activity $HOURS_AGO hours ago${NC}"
    else
        DAYS_AGO=$(( $MINUTES_AGO / 1440 ))
        echo -e "   ${GREEN}✓ Last activity $DAYS_AGO days ago${NC}"
    fi
else
    echo "   No activity found (new deployment?)"
fi
echo

# 6. Check container logs for recent API requests
echo -e "${BLUE}6. Recent API Activity (Last 5 minutes)${NC}"
RECENT_LOGS=$(docker logs "$CONTAINER_NAME" --since 5m 2>&1 | grep -E "POST|GET" | wc -l)
echo "   Recent API requests: $RECENT_LOGS"

if [ "$RECENT_LOGS" -gt 10 ]; then
    echo -e "   ${YELLOW}⚠️  WARNING: High API activity detected!${NC}"
    echo
    echo "   Recent requests:"
    docker logs "$CONTAINER_NAME" --since 5m 2>&1 | grep -E "POST|GET" | tail -5 | sed 's/^/     /'
fi
echo

# 7. Check network connections
echo -e "${BLUE}7. Active Network Connections${NC}"
CONTAINER_ID=$(docker ps --filter "name=^${CONTAINER_NAME}$" --format "{{.ID}}")
if [ -n "$CONTAINER_ID" ]; then
    # Get container PID
    CONTAINER_PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER_NAME")
    if [ -n "$CONTAINER_PID" ] && [ "$CONTAINER_PID" != "0" ]; then
        # Count established connections (requires nsenter, may need sudo)
        CONNECTIONS=$(sudo nsenter -t "$CONTAINER_PID" -n netstat -tn 2>/dev/null | grep ESTABLISHED | wc -l)
        echo "   Active TCP connections: $CONNECTIONS"

        if [ "$CONNECTIONS" -gt 0 ]; then
            echo -e "   ${YELLOW}⚠️  Active connections detected${NC}"
        fi
    else
        echo "   Unable to check network connections (container PID not available)"
    fi
else
    echo "   Unable to check network connections"
fi
echo

# Summary and recommendation
echo -e "${BLUE}=== Summary and Recommendation ===${NC}"
echo

# Determine safety level
SAFETY_SCORE=0
HOUR_ACTIVE=${HOUR_ACTIVE:-0}
RECENT_ACTIVE=${RECENT_ACTIVE:-0}
RECENT_LOGS=${RECENT_LOGS:-0}
MINUTES_AGO=${MINUTES_AGO:-9999}

if [ "$HOUR_ACTIVE" -gt 0 ]; then
    SAFETY_SCORE=$((SAFETY_SCORE + 3))
fi
if [ "$RECENT_ACTIVE" -gt 0 ]; then
    SAFETY_SCORE=$((SAFETY_SCORE + 1))
fi
if [ -n "$LAST_EPOCH" ] && [ "$MINUTES_AGO" -lt 30 ]; then
    SAFETY_SCORE=$((SAFETY_SCORE + 2))
fi
if [ "$RECENT_LOGS" -gt 10 ]; then
    SAFETY_SCORE=$((SAFETY_SCORE + 1))
fi

if [ "$SAFETY_SCORE" -ge 4 ]; then
    echo -e "${RED}⛔ NOT SAFE TO MIGRATE NOW${NC}"
    echo "   Users are actively using the system"
    echo
    echo "   Recommendations:"
    echo "   1. Wait for users to finish their sessions"
    echo "   2. Schedule maintenance window with users"
    echo "   3. Check again later: bash $0 $CONTAINER_NAME"
elif [ "$SAFETY_SCORE" -ge 2 ]; then
    echo -e "${YELLOW}⚠️  CAUTION: Recent activity detected${NC}"
    echo "   Users may have been active recently"
    echo
    echo "   Recommendations:"
    echo "   1. Notify users of upcoming maintenance"
    echo "   2. Wait 15-30 minutes if possible"
    echo "   3. Proceed with migration during low-usage period"
else
    echo -e "${GREEN}✅ SAFE TO MIGRATE${NC}"
    echo "   No recent user activity detected"
    echo
    echo "   You can proceed with migration:"
    echo "   bash 2-backup-deployment.sh $CONTAINER_NAME"
fi

echo
echo "Migration will cause ~2-5 minutes of downtime."
echo "Users will be disconnected during container restart."
