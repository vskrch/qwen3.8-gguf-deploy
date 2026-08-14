#!/usr/bin/env bash
# ==============================================================================
# Qwen Server Health & Memory Sentinel Daemon
# Proactive self-healing, deadlock recovery, and memory overload protection
# ==============================================================================
set -u

ENDPOINT="http://127.0.0.1:8000/v1/models"
HEALTH_ENDPOINT="http://127.0.0.1:8000/health"
SERVICE_NAME="qwen-server"
CHECK_INTERVAL=20
CONSECUTIVE_FAILURES=0
MAX_FAILURES=3
MIN_AVAILABLE_RAM_KB=3670016 # 3.5 GB threshold

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [QWEN-SENTINEL] $1"
}

log "Sentinel initialized. Monitoring ${SERVICE_NAME} on port 8000..."

while true; do
    # --------------------------------------------------------------------------
    # 1. Memory Pressure Sentry: Prevent System Overload & OOM Crashes
    # --------------------------------------------------------------------------
    if [ -f /proc/meminfo ]; then
        MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        if [ -n "${MEM_AVAIL}" ] && [ "${MEM_AVAIL}" -lt "${MIN_AVAILABLE_RAM_KB}" ]; then
            log "⚠️ Memory pressure detected! Available RAM: $((MEM_AVAIL / 1024)) MB (Threshold: $((MIN_AVAILABLE_RAM_KB / 1024)) MB)"
            log "🧹 Reclaiming page cache and free buffers..."
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            NEW_MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
            log "✅ Page cache dropped. New Available RAM: $((NEW_MEM / 1024)) MB"
        fi
    fi

    # --------------------------------------------------------------------------
    # 2. Service Active Check
    # --------------------------------------------------------------------------
    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        log "⚠️ Service ${SERVICE_NAME} is inactive. Attempting automatic start..."
        systemctl start "${SERVICE_NAME}"
        CONSECUTIVE_FAILURES=0
        sleep "${CHECK_INTERVAL}"
        continue
    fi

    # --------------------------------------------------------------------------
    # 3. HTTP Health & Responsiveness Check (Detect Hangs / Deadlocks)
    # --------------------------------------------------------------------------
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${HEALTH_ENDPOINT}" 2>/dev/null || \
               curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${ENDPOINT}" 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "503" ]; then
        # 200 = OK, 503 = busy processing another request (still alive)
        CONSECUTIVE_FAILURES=0
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        log "⚠️ Health probe failed (HTTP code: ${HTTP_CODE}, Fail count: ${CONSECUTIVE_FAILURES}/${MAX_FAILURES})"

        if [ "${CONSECUTIVE_FAILURES}" -ge "${MAX_FAILURES}" ]; then
            log "🚨 Server unresponsive for > $((MAX_FAILURES * CHECK_INTERVAL)) seconds. Triggering Self-Healing Restart..."
            systemctl restart "${SERVICE_NAME}"
            CONSECUTIVE_FAILURES=0
            sleep 15
        fi
    fi

    sleep "${CHECK_INTERVAL}"
done
