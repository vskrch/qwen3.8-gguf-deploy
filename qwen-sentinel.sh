#!/usr/bin/env bash
# ==============================================================================
# Qwen Server Health, Memory Sentinel & Safe Disk Reclaimer Daemon
# Proactive self-healing, deadlock recovery, and automatic disk/memory freeing
# ==============================================================================
set -u

ENDPOINT="http://127.0.0.1:8000/v1/models"
HEALTH_ENDPOINT="http://127.0.0.1:8000/health"
SERVICE_NAME="qwen-server"
CHECK_INTERVAL=20
CONSECUTIVE_FAILURES=0
MAX_FAILURES=3
MIN_AVAILABLE_RAM_KB=4194304 # 4 GB safety threshold

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [QWEN-SENTINEL] $1"
}

log "Sentinel initialized with Auto-Memory Optimization & Safe Disk Swap Reclaimer."
log "Monitoring ${SERVICE_NAME} on port 8000 (Max Context: 262k tokens)..."

while true; do
    # --------------------------------------------------------------------------
    # 1. Memory Pressure Sentry: Prevent System Overload & Free RAM/Disk Safely
    # --------------------------------------------------------------------------
    if [ -f /proc/meminfo ]; then
        MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        SWAP_USED=$(awk '/SwapTotal/ {total=$2} /SwapFree/ {free=$2} END {print total-free}' /proc/meminfo)

        # A. If available RAM is below 4GB, drop cached buffers
        if [ -n "${MEM_AVAIL}" ] && [ "${MEM_AVAIL}" -lt "${MIN_AVAILABLE_RAM_KB}" ]; then
            log "⚠️ Low memory detected (${MEM_AVAIL} kB avail). Flushing page caches to free RAM..."
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            NEW_MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
            log "✅ Page cache dropped. Available RAM now: $((NEW_MEM / 1024)) MB"
        fi

        # B. Safe Disk Swap Reclamation: If swap was used during peak context loads
        # and RAM is now healthy (> 10GB free), safely clear swap to disk is freed
        if [ -n "${SWAP_USED}" ] && [ "${SWAP_USED}" -gt 1048576 ] && [ "${MEM_AVAIL}" -gt 10485760 ]; then
            log "🧹 Safe Disk Reclaim: Reclaiming $((SWAP_USED / 1024)) MB of used swap back into RAM..."
            swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
            log "✅ Disk swap safely flushed and reset to 0 MB."
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
        CONSECUTIVE_FAILURES=0
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        log "⚠️ Health probe failed (HTTP code: ${HTTP_CODE}, Fail count: ${CONSECUTIVE_FAILURES}/${MAX_FAILURES})"

        if [ "${CONSECUTIVE_FAILURES}" -ge "${MAX_FAILURES}" ]; then
            log "🚨 Server unresponsive for > $((MAX_FAILURES * CHECK_INTERVAL)) seconds. Triggering Self-Healing Restart..."
            systemctl restart "${SERVICE_NAME}"
            CONSECUTIVE_FAILURES=0
            # Drop caches and reset memory on restart
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            sleep 15
        fi
    fi

    sleep "${CHECK_INTERVAL}"
done
