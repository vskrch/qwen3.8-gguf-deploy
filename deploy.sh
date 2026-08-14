#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B-GGUF Deployment Script for llama-server
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

echo "=== [1/7] Creating isolated directory structure at ${INSTALL_DIR} ==="
mkdir -p "${BIN_DIR}" "${MODELS_DIR}" "${LOGS_DIR}"

echo "=== [2/7] Installing dependencies (aria2, curl, tar) ==="
apt-get update -qq && apt-get install -y -qq aria2 curl tar

echo "=== [3/7] Downloading & Installing llama-server ==="
TMP_DIR=$(mktemp -d)
curl -L -s "${LLAMA_TAR_URL}" -o "${TMP_DIR}/llama.tar.gz"
tar -xzf "${TMP_DIR}/llama.tar.gz" -C "${TMP_DIR}"
cp -r "${TMP_DIR}"/llama-b10431/* "${BIN_DIR}/"
chmod +x "${BIN_DIR}/llama-server"
rm -rf "${TMP_DIR}"

echo "=== [4/7] Downloading Qwen3.8-27B GGUF model via multi-threaded aria2 ==="
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

echo "=== [5/7] Creating Systemd Service /etc/systemd/system/qwen-server.service ==="
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
    --alias Qwen3.8-27B,qwen3.8-27b,qwen \\
    --flash-attn on
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "=== [6/7] Configuring firewall rule for port ${PORT} ==="
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PORT}/tcp comment 'Qwen LLM OpenAI API' || true
fi

echo "=== [7/7] Reloading systemd, enabling and starting qwen-server ==="
systemctl daemon-reload
systemctl enable --now qwen-server

echo "=== Service Status ==="
systemctl status qwen-server --no-pager || true

echo "=== Deployment Complete ==="
echo "Endpoint: http://localhost:${PORT}/v1/chat/completions"
echo "Models:   http://localhost:${PORT}/v1/models"
