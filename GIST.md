# ⚡ 1-Click Runbook: Deploy Qwen3.8-27B-GGUF with 262k Context, Memory Guards & Safe Disk Reclaimer

A standalone 1-click deployment guide for serving [`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) on Linux with **262k Max Context**, **Unsloth Dynamic V3.0**, **4-bit Turbo KV Cache**, **cgroups v2 boundaries**, and **Sentinel Safe Disk Reclaimer**.

---

## ⚡ 1-Click One-Liner Install

Run directly on your Linux host:

```bash
curl -sSL https://raw.githubusercontent.com/vskrch/qwen3.8-gguf-deploy/main/deploy.sh | sudo bash
```

---

## 🛠 Standalone Script (Copy-Pasteable)

```bash
sudo bash -c "$(cat << 'EOF'
set -euo pipefail

INSTALL_DIR="/opt/qwen-server"
mkdir -p "${INSTALL_DIR}/bin" "${INSTALL_DIR}/models" "${INSTALL_DIR}/logs"

cat << 'SYSCTL' > /etc/sysctl.d/99-qwen-tuning.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
SYSCTL
sysctl -p /etc/sysctl.d/99-qwen-tuning.conf >/dev/null 2>&1 || true

if [ ! -f /swapfile_qwen ]; then
    fallocate -l 32G /swapfile_qwen 2>/dev/null || dd if=/dev/zero of=/swapfile_qwen bs=1M count=32768
    chmod 600 /swapfile_qwen
    mkswap /swapfile_qwen >/dev/null
    swapon /swapfile_qwen >/dev/null 2>&1 || true
    if ! grep -q "/swapfile_qwen" /etc/fstab; then
        echo "/swapfile_qwen none swap sw 0 0" >> /etc/fstab
    fi
fi

apt-get update -qq && apt-get install -y -qq aria2 curl tar

TMP_DIR=$(mktemp -d)
curl -L -s "https://github.com/ggml-org/llama.cpp/releases/download/b10431/llama-b10431-bin-ubuntu-x64.tar.gz" -o "${TMP_DIR}/llama.tar.gz"
tar -xzf "${TMP_DIR}/llama.tar.gz" -C "${TMP_DIR}"
cp -r "${TMP_DIR}"/llama-b10431/* "${INSTALL_DIR}/bin/"
chmod +x "${INSTALL_DIR}/bin/llama-server"
rm -rf "${TMP_DIR}"

aria2c -x 16 -s 16 -k 1M --file-allocation=none \
    --dir="${INSTALL_DIR}/models" --out="Qwen3.8-27B-UD-Q4_K_XL.gguf" \
    "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_XL.gguf"

aria2c -x 16 -s 16 -k 1M --file-allocation=none \
    --dir="${INSTALL_DIR}/models" --out="mmproj-F16.gguf" \
    "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/mmproj-F16.gguf"

cat <<'SERVICE' > /etc/systemd/system/qwen-server.service
[Unit]
Description=Qwen3.8-27B-GGUF llama-server (OpenAI Compatible API)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/qwen-server
Environment="LD_LIBRARY_PATH=/opt/qwen-server/bin"
ExecStart=/opt/qwen-server/bin/llama-server \
    -m /opt/qwen-server/models/Qwen3.8-27B-UD-Q4_K_XL.gguf \
    --mmproj /opt/qwen-server/models/mmproj-F16.gguf \
    --host 0.0.0.0 \
    --port 8000 \
    -c 262144 \
    -t 6 \
    -tb 6 \
    --parallel 1 \
    -ctk q4_0 \
    -ctv q4_0 \
    --flash-attn on \
    --alias Qwen3.8-27B,qwen3.8-27b,qwen

MemoryHigh=33G
MemoryMax=36G
CPUQuota=550%
Nice=5
CPUSchedulingPolicy=other
OOMScoreAdjust=500

Restart=always
RestartSec=3
StartLimitIntervalSec=300
StartLimitBurst=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

cat << 'SENTINEL' > "${INSTALL_DIR}/bin/qwen-sentinel.sh"
#!/usr/bin/env bash
set -u
ENDPOINT="http://127.0.0.1:8000/v1/models"
HEALTH_ENDPOINT="http://127.0.0.1:8000/health"
SERVICE_NAME="qwen-server"
CHECK_INTERVAL=20
CONSECUTIVE_FAILURES=0
MAX_FAILURES=3
MIN_AVAILABLE_RAM_KB=4194304

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [QWEN-SENTINEL] $1"; }

while true; do
    if [ -f /proc/meminfo ]; then
        MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        SWAP_USED=$(awk '/SwapTotal/ {total=$2} /SwapFree/ {free=$2} END {print total-free}' /proc/meminfo)

        if [ -n "${MEM_AVAIL}" ] && [ "${MEM_AVAIL}" -lt "${MIN_AVAILABLE_RAM_KB}" ]; then
            log "⚠️ Low memory detected. Dropping page caches..."
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        fi

        if [ -n "${SWAP_USED}" ] && [ "${SWAP_USED}" -gt 1048576 ] && [ "${MEM_AVAIL}" -gt 10485760 ]; then
            log "🧹 Safe Disk Reclaim: Reclaiming used swap back into RAM..."
            swapoff -a 2>/dev/null && swapon -a 2>/dev/null || true
            log "✅ Disk swap safely flushed."
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
            log "🚨 Server unresponsive. Restarting and clearing caches..."
            systemctl restart "${SERVICE_NAME}"
            CONSECUTIVE_FAILURES=0
            sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
            sleep 15
        fi
    fi
    sleep "${CHECK_INTERVAL}"
done
SENTINEL
chmod +x "${INSTALL_DIR}/bin/qwen-sentinel.sh"

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

if command -v ufw >/dev/null 2>&1; then
    ufw allow 8000/tcp comment 'Qwen LLM OpenAI API' || true
fi

systemctl daemon-reload
systemctl enable --now qwen-server
systemctl enable --now qwen-sentinel
echo "✅ Qwen3.8-27B with 262k Max Context & Safe Disk Reclaimer is active on port 8000!"
EOF
)"
```

---

## 📡 OpenAI API Verification

```bash
# 1. Models
curl http://localhost:8000/v1/models

# 2. Chat Completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B",
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "max_tokens": 50
  }'
```
