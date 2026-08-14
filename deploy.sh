#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B-GGUF Deployment Script with Self-Healing & Memory Protection
# Fully OpenAI-Compatible Endpoints on Port 8000
# Isolated in /opt/qwen-server (Does NOT touch /opt/potato)
# ==============================================================================
set -euo pipefail

INSTALL_DIR="/opt/qwen-server"
MODELS_DIR="${INSTALL_DIR}/models"
BIN_DIR="${INSTALL_DIR}/bin"
LOGS_DIR="${INSTALL_DIR}/logs"
PORT=8000
THREADS=6
CTX_SIZE=8192
MODEL_NAME="Qwen3.8-27B-UD-Q4_K_XL.gguf"
MODEL_URL="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/${MODEL_NAME}"
MMPROJ_NAME="mmproj-F16.gguf"
MMPROJ_URL="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/${MMPROJ_NAME}"
LLAMA_TAR_URL="https://github.com/ggml-org/llama.cpp/releases/download/b10431/llama-b10431-bin-ubuntu-x64.tar.gz"

echo "=== [1/8] Tuning Linux Virtual Memory Settings ==="
cat << 'SYSCTL' > /etc/sysctl.d/99-qwen-tuning.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
SYSCTL
sysctl -p /etc/sysctl.d/99-qwen-tuning.conf || true

echo "=== [2/8] Creating isolated directory structure at ${INSTALL_DIR} ==="
mkdir -p "${BIN_DIR}" "${MODELS_DIR}" "${LOGS_DIR}"

echo "=== [3/8] Installing dependencies (aria2, curl, tar) ==="
apt-get update -qq && apt-get install -y -qq aria2 curl tar

echo "=== [4/8] Downloading & Installing llama-server ==="
TMP_DIR=$(mktemp -d)
curl -L -s "${LLAMA_TAR_URL}" -o "${TMP_DIR}/llama.tar.gz"
tar -xzf "${TMP_DIR}/llama.tar.gz" -C "${TMP_DIR}"
cp -r "${TMP_DIR}"/llama-b10431/* "${BIN_DIR}/"
chmod +x "${BIN_DIR}/llama-server"
rm -rf "${TMP_DIR}"

echo "=== [5/8] Downloading Qwen3.8-27B GGUF model via multi-threaded aria2 ==="
if [ ! -f "${MODELS_DIR}/${MODEL_NAME}" ]; then
    aria2c -x 16 -s 16 -k 1M --file-allocation=none \
        --dir="${MODELS_DIR}" --out="${MODEL_NAME}" \
        "${MODEL_URL}"
else
    echo "Model file ${MODEL_NAME} already exists."
fi

if [ ! -f "${MODELS_DIR}/${MMPROJ_NAME}" ]; then
    aria2c -x 16 -s 16 -k 1M --file-allocation=none \
        --dir="${MODELS_DIR}" --out="${MMPROJ_NAME}" \
        "${MMPROJ_URL}"
else
    echo "Multimodal projector ${MMPROJ_NAME} already exists."
fi

echo "=== [6/8] Installing Hardened Systemd Service ==="
cat <<EOF > /etc/systemd/system/qwen-server.service
[Unit]
Description=Qwen3.8-27B-GGUF llama-server (OpenAI Compatible API)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="LD_LIBRARY_PATH=${BIN_DIR}"
ExecStart=${BIN_DIR}/llama-server \\
    -m ${MODELS_DIR}/${MODEL_NAME} \\
    --mmproj ${MODELS_DIR}/${MMPROJ_NAME} \\
    --host 0.0.0.0 \\
    --port ${PORT} \\
    -c ${CTX_SIZE} \\
    -t ${THREADS} \\
    -tb ${THREADS} \\
    --parallel 1 \\
    -ctk q8_0 \\
    -ctv q8_0 \\
    --flash-attn on \\
    --alias Qwen3.8-27B,qwen3.8-27b,qwen

# Resource & Memory Boundaries (cgroups v2)
MemoryHigh=28G
MemoryMax=32G
CPUQuota=550%
Nice=5
CPUSchedulingPolicy=other
OOMScoreAdjust=500

# Self-Healing & Failure Recovery
Restart=always
RestartSec=3
StartLimitIntervalSec=300
StartLimitBurst=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "=== [7/8] Installing Self-Healing Sentinel Watchdog ==="
cat << 'SENTINEL' > "${BIN_DIR}/qwen-sentinel.sh"
#!/usr/bin/env bash
set -u
ENDPOINT="http://127.0.0.1:8000/v1/models"
HEALTH_ENDPOINT="http://127.0.0.1:8000/health"
SERVICE_NAME="qwen-server"
CHECK_INTERVAL=20
CONSECUTIVE_FAILURES=0
MAX_FAILURES=3
MIN_AVAILABLE_RAM_KB=3670016

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [QWEN-SENTINEL] $1"
}

log "Sentinel initialized. Monitoring ${SERVICE_NAME} on port 8000..."

while true; do
    if [ -f /proc/meminfo ]; then
        MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        if [ -n "${MEM_AVAIL}" ] && [ "${MEM_AVAIL}" -lt "${MIN_AVAILABLE_RAM_KB}" ]; then
            log "⚠️ Memory pressure detected! Available RAM: $((MEM_AVAIL / 1024)) MB"
            log "🧹 Reclaiming page cache..."
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            NEW_MEM=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
            log "✅ Page cache dropped. New Available RAM: $((NEW_MEM / 1024)) MB"
        fi
    fi

    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        log "⚠️ Service ${SERVICE_NAME} is inactive. Attempting automatic start..."
        systemctl start "${SERVICE_NAME}"
        CONSECUTIVE_FAILURES=0
        sleep "${CHECK_INTERVAL}"
        continue
    fi

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
            sleep 15
        fi
    fi

    sleep "${CHECK_INTERVAL}"
done
SENTINEL
chmod +x "${BIN_DIR}/qwen-sentinel.sh"

cat << 'SNTL_SVC' > /etc/systemd/system/qwen-sentinel.service
[Unit]
Description=Qwen Server Self-Healing Watchdog & Memory Sentinel
After=qwen-server.service
Wants=qwen-server.service

[Service]
Type=simple
User=root
ExecStart=/opt/qwen-server/bin/qwen-sentinel.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SNTL_SVC

echo "=== [8/8] Configuring Firewall & Starting Services ==="
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp comment 'Qwen LLM OpenAI API' || true
fi

systemctl daemon-reload
systemctl enable --now qwen-server
systemctl enable --now qwen-sentinel

echo "=== Deployment & Safeguards Active ==="
echo "Endpoint: http://localhost:${PORT}/v1/chat/completions"
echo "Models:   http://localhost:${PORT}/v1/models"
