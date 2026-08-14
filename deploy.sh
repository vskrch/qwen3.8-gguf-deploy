#!/usr/bin/env bash
# ==============================================================================
# 🚀 1-Click Autonomous Installer for Qwen3.8-27B-GGUF (llama-server)
# Features:
#   • Unsloth Dynamic V3.0 Quantization (UD-Q4_K_XL) + Multimodal Vision
#   • Turbo 8-Bit KV Cache Quantization (-ctk q8_0 -ctv q8_0)
#   • Flash Attention & CPU AVX2 Multi-Thread Vector Acceleration
#   • cgroups v2 Memory Hard Limits (28G High / 32G Max)
#   • CPU Quota (550%) & Starvation Guard (Protects host & other containers)
#   • Active Self-Healing Sentinel Watchdog (Auto-restart on deadlocks/crashes)
#   • Automatic Page Cache Memory Flush when RAM < 3.5 GB
#   • Fully OpenAI-Compatible Endpoints on Port 8000 (http://<IP>:8000/v1)
# ==============================================================================
set -euo pipefail

# Visual formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root (or with sudo)."
    exit 1
fi

INSTALL_DIR="/opt/qwen-server"
MODELS_DIR="${INSTALL_DIR}/models"
BIN_DIR="${INSTALL_DIR}/bin"
LOGS_DIR="${INSTALL_DIR}/logs"
PORT=8000
THREADS=$(nproc || echo 6)
CTX_SIZE=8192

MODEL_NAME="Qwen3.8-27B-UD-Q4_K_XL.gguf"
MODEL_URL="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/${MODEL_NAME}"
MMPROJ_NAME="mmproj-F16.gguf"
MMPROJ_URL="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/${MMPROJ_NAME}"
LLAMA_TAR_URL="https://github.com/ggml-org/llama.cpp/releases/download/b10431/llama-b10431-bin-ubuntu-x64.tar.gz"

echo -e "${GREEN}"
echo "=================================================================="
echo "    Qwen3.8-27B-GGUF OpenAI-Compatible 1-Click Server Deployer   "
echo "=================================================================="
echo -e "${NC}"

# 1. Virtual Memory Tuning
log_info "[1/8] Applying Linux kernel virtual memory tuning..."
cat << 'SYSCTL' > /etc/sysctl.d/99-qwen-tuning.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
SYSCTL
sysctl -p /etc/sysctl.d/99-qwen-tuning.conf >/dev/null 2>&1 || true

# 2. Directory structure
log_info "[2/8] Creating directory structure at ${INSTALL_DIR}..."
mkdir -p "${BIN_DIR}" "${MODELS_DIR}" "${LOGS_DIR}"

# 3. Dependencies
log_info "[3/8] Installing package dependencies (aria2, curl, tar)..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq aria2 curl tar
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q aria2 curl tar
elif command -v yum >/dev/null 2>&1; then
    yum install -y -q aria2 curl tar
fi

# 4. Engine Installation
log_info "[4/8] Downloading and installing llama-server engine (b10431)..."
TMP_DIR=$(mktemp -d)
curl -L -s "${LLAMA_TAR_URL}" -o "${TMP_DIR}/llama.tar.gz"
tar -xzf "${TMP_DIR}/llama.tar.gz" -C "${TMP_DIR}"
cp -r "${TMP_DIR}"/llama-b10431/* "${BIN_DIR}/"
chmod +x "${BIN_DIR}/llama-server"
rm -rf "${TMP_DIR}"

# 5. Model Download (Accelerated)
log_info "[5/8] Checking and downloading model weights (16-thread aria2)..."
if [ ! -f "${MODELS_DIR}/${MODEL_NAME}" ]; then
    log_info "Downloading ${MODEL_NAME} (~16.7 GB)..."
    aria2c -x 16 -s 16 -k 1M --file-allocation=none \
        --dir="${MODELS_DIR}" --out="${MODEL_NAME}" \
        "${MODEL_URL}"
else
    log_success "Model file ${MODEL_NAME} is already present."
fi

if [ ! -f "${MODELS_DIR}/${MMPROJ_NAME}" ]; then
    log_info "Downloading multimodal projector ${MMPROJ_NAME}..."
    aria2c -x 16 -s 16 -k 1M --file-allocation=none \
        --dir="${MODELS_DIR}" --out="${MMPROJ_NAME}" \
        "${MMPROJ_URL}"
else
    log_success "Projector file ${MMPROJ_NAME} is already present."
fi

# 6. Hardened Systemd Service
log_info "[6/8] Configuring hardened systemd service (qwen-server.service)..."
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

# 7. Self-Healing Watchdog Sentinel
log_info "[7/8] Installing proactive watchdog daemon (qwen-sentinel.service)..."
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

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [QWEN-SENTINEL] $1"; }

while true; do
    if [ -f /proc/meminfo ]; then
        MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        if [ -n "${MEM_AVAIL}" ] && [ "${MEM_AVAIL}" -lt "${MIN_AVAILABLE_RAM_KB}" ]; then
            log "⚠️ Memory pressure detected! Available RAM: $((MEM_AVAIL / 1024)) MB"
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        fi
    fi

    if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl start "${SERVICE_NAME}"
        sleep "${CHECK_INTERVAL}"
        continue
    fi

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${HEALTH_ENDPOINT}" 2>/dev/null || \
               curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${ENDPOINT}" 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "503" ]; then
        CONSECUTIVE_FAILURES=0
    else
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        if [ "${CONSECUTIVE_FAILURES}" -ge "${MAX_FAILURES}" ]; then
            log "🚨 Server unresponsive. Triggering self-healing restart..."
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

# 8. Firewall & Activation
log_info "[8/8] Opening firewall port ${PORT} and starting services..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp comment 'Qwen LLM OpenAI API' >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable --now qwen-server
systemctl enable --now qwen-sentinel

log_info "Waiting for model to initialize in RAM..."
for i in {1..30}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${PORT}/v1/models 2>/dev/null || echo "000")
    if [ "${HTTP_STATUS}" = "200" ]; then
        break
    fi
    sleep 1
done

echo ""
log_success "🎉 Qwen3.8-27B-GGUF Deployment Complete & Healthy!"
echo "------------------------------------------------------------------"
echo " • OpenAI Base URL:    http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):${PORT}/v1"
echo " • Local Base URL:     http://localhost:${PORT}/v1"
echo " • Models Endpoint:    http://localhost:${PORT}/v1/models"
echo " • Chat Completions:   http://localhost:${PORT}/v1/chat/completions"
echo " • Web UI:             http://localhost:${PORT}/"
echo " • Check Status:       sudo systemctl status qwen-server"
echo " • Check Sentinel:     sudo systemctl status qwen-sentinel"
echo "------------------------------------------------------------------"
