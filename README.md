# Qwen3.8-27B-GGUF Deployment & OpenAI Compatible Serving

Complete guide and reference for deploying, configuring, serving, and troubleshooting **Qwen3.8-27B-GGUF** ([`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)) with fully OpenAI-compatible REST API endpoints.

---

## 1. Overview & Architecture

- **Model**: `Qwen3.8-27B-UD-Q4_K_XL.gguf` (~16.69 GB) + `mmproj-F16.gguf` (0.86 GB)
- **Serving Engine**: `llama-server` (llama.cpp build 10431 with AVX2 optimizations)
- **Base Endpoint**: `http://<SERVER_IP>:8000/v1`
- **Isolation**: Stored under `/opt/qwen-server` and managed via `qwen-server.service` (no conflict with `/opt/potato` on port 8080).

---

## 2. Directory Structure

```
/opt/qwen-server/
├── bin/
│   ├── llama-server
│   └── lib*.so (shared libraries)
├── models/
│   ├── Qwen3.8-27B-UD-Q4_K_XL.gguf
│   └── mmproj-F16.gguf
└── logs/
```

---

## 3. Quick Start / Installation

### Automatic Deployment
Run the included `deploy.sh` as root:
```bash
sudo bash deploy.sh
```

### Manual Step-by-Step Installation

1. **Install Prerequisites**:
   ```bash
   sudo apt-get update && sudo apt-get install -y aria2 curl tar
   sudo mkdir -p /opt/qwen-server/{bin,models,logs}
   ```

2. **Download llama.cpp Server**:
   ```bash
   curl -L -s https://github.com/ggml-org/llama.cpp/releases/download/b10431/llama-b10431-bin-ubuntu-x64.tar.gz -o /tmp/llama.tar.gz
   tar -xzf /tmp/llama.tar.gz -C /tmp/
   sudo cp -r /tmp/llama-b10431/* /opt/qwen-server/bin/
   sudo chmod +x /opt/qwen-server/bin/llama-server
   rm -rf /tmp/llama*
   ```

3. **Download Model Weights (Accelerated 16-thread download)**:
   ```bash
   sudo aria2c -x 16 -s 16 -k 1M --file-allocation=none \
       --dir="/opt/qwen-server/models" --out="Qwen3.8-27B-UD-Q4_K_XL.gguf" \
       "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/Qwen3.8-27B-UD-Q4_K_XL.gguf"

   sudo aria2c -x 16 -s 16 -k 1M --file-allocation=none \
       --dir="/opt/qwen-server/models" --out="mmproj-F16.gguf" \
       "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/main/mmproj-F16.gguf"
   ```

4. **Install Systemd Service**:
   ```bash
   sudo cp qwen-server.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now qwen-server
   ```

---

## 4. Service Management

| Action | Command |
| :--- | :--- |
| **Check Status** | `sudo systemctl status qwen-server` |
| **View Live Logs** | `sudo journalctl -u qwen-server -f` |
| **Restart Service** | `sudo systemctl restart qwen-server` |
| **Stop Service** | `sudo systemctl stop qwen-server` |
| **Start Service** | `sudo systemctl start qwen-server` |

---

## 5. Configuration & Tuning

Edit `/etc/systemd/system/qwen-server.service` and reload (`sudo systemctl daemon-reload && sudo systemctl restart qwen-server`):

- **Threads (`-t`)**: Set to number of physical CPU cores (e.g. `-t 6`).
- **Context Window (`-c`)**: Default is `-c 8192`. Increase to `16384` or `32768` if needed for long documents.
- **Port (`--port`)**: Default is `8000`. Change if needed.
- **Batch Size (`-b` / `-ub`)**: E.g. `-b 512 -ub 512` for CPU prompt processing throughput.
- **Flash Attention (`--flash-attn`)**: Enabled by default for lower memory usage and faster attention.

---

## 6. Using the OpenAI-Compatible API

### 6.1 cURL Example

```bash
curl http://10.0.0.73:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello! What is your name?"}
    ],
    "temperature": 0.7,
    "max_tokens": 200
  }'
```

### 6.2 Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://10.0.0.73:8000/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="Qwen3.8-27B",
    messages=[
        {"role": "user", "content": "Write a quick Python function to calculate fibonacci numbers."}
    ],
    temperature=0.7,
    max_tokens=256
)

print(response.choices[0].message.content)
```

### 6.3 Streaming Support

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://10.0.0.73:8000/v1",
    api_key="not-needed"
)

stream = client.chat.completions.create(
    model="Qwen3.8-27B",
    messages=[{"role": "user", "content": "Tell me a short sci-fi story."}],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content is not None:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

---

## 7. Troubleshooting Guide

### Issue 1: Port Conflict / Connection Refused
- **Symptom**: `curl: (7) Failed to connect to 10.0.0.73 port 8000: Connection refused`
- **Fix**: Check `sudo journalctl -u qwen-server -n 50`. If port 8000 is taken, change `--port <NEW_PORT>` in `/etc/systemd/system/qwen-server.service` and restart.

### Issue 2: Out of Memory (OOM) or Process Killed
- **Symptom**: Systemd logs show `status=137/KILL` or `SIGKILL`.
- **Fix**: Reduce context window `-c 4096` or `-c 8192` in `/etc/systemd/system/qwen-server.service`.

### Issue 3: Slow Generation on CPU
- **Symptom**: High latency per token.
- **Fix**:
  1. Ensure `--flash-attn` is enabled.
  2. Match `-t` to the physical CPU core count (e.g. `-t 6`).
  3. Ensure no other heavy background CPU tasks are pinning all cores.

### Issue 4: Dynamic Shared Library Issues
- **Symptom**: `error while loading shared libraries: libllama.so...`
- **Fix**: Ensure `Environment="LD_LIBRARY_PATH=/opt/qwen-server/bin"` is defined in the systemd service file.
