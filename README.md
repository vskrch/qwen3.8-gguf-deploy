# Qwen3.8-27B-GGUF Deployment & OpenAI Compatible Serving

Complete guide and reference for deploying, configuring, serving, and troubleshooting **Qwen3.8-27B-GGUF** ([`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)) with **Unsloth Dynamic V3.0 quantization**, **Turbo 8-bit KV Cache**, **cgroups v2 memory bounds**, and **automated self-healing watchdogs**.

---

## 1. Overview & Architecture

- **Model**: `Qwen3.8-27B-UD-Q4_K_XL.gguf` (~16.69 GB) + `mmproj-F16.gguf` (0.86 GB)
- **Quantization**: Unsloth Dynamic V3.0 (Per-tensor importance-weighted quantization)
- **Turbo Optimizations**:
  - **Flash Attention**: `--flash-attn on`
  - **Turbo KV Cache**: `-ctk q8_0 -ctv q8_0` (Halves KV cache RAM, accelerates attention)
  - **CPU AVX2 SIMD**: `-t 6 -tb 6 --parallel 1`
- **Safeguards & Self-Healing**:
  - **cgroups v2 RAM Caps**: `MemoryHigh=28G`, `MemoryMax=32G` (Prevents system OOM)
  - **CPU Starvation Protection**: `CPUQuota=550%`, `Nice=5` (Reserves CPU for host/Potato server)
  - **OOM Score Adjustment**: `OOMScoreAdjust=500` (Protects Potato Docker container)
  - **Active Watchdog (`qwen-sentinel.service`)**: Automated deadlock detection, memory pressure cache-drop, and auto-restart on crash/hang.
- **Base Endpoint**: `http://<SERVER_IP>:8000/v1`

---

## 2. Directory Structure

```
/opt/qwen-server/
├── bin/
│   ├── llama-server
│   ├── qwen-sentinel.sh
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

---

## 4. Service Management

| Action | Command |
| :--- | :--- |
| **Check Server Status** | `sudo systemctl status qwen-server` |
| **Check Sentinel Status** | `sudo systemctl status qwen-sentinel` |
| **View Live Logs** | `sudo journalctl -u qwen-server -f` |
| **Restart Server** | `sudo systemctl restart qwen-server` |
| **Restart Sentinel** | `sudo systemctl restart qwen-sentinel` |

---

## 5. Using the OpenAI-Compatible API

### 5.1 cURL Example

```bash
curl http://10.0.0.73:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is 2 + 2? Give just the number."}
    ],
    "temperature": 0.7,
    "max_tokens": 80
  }'
```

### 5.2 Python (Official OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://10.0.0.73:8000/v1",
    api_key="not-needed"
)

# Standard call with reasoning/thinking support
response = client.chat.completions.create(
    model="Qwen3.8-27B",
    messages=[
        {"role": "user", "content": "Explain CPU vectorization briefly."}
    ],
    max_tokens=150
)

# Qwen3.8 outputs both reasoning (thinking) and final answer
msg = response.choices[0].message
if hasattr(msg, "reasoning_content") and msg.reasoning_content:
    print(f"💭 Thinking:\n{msg.reasoning_content}\n")
print(f"🤖 Answer:\n{msg.content}")

# Streaming example
stream = client.chat.completions.create(
    model="Qwen3.8-27B",
    messages=[{"role": "user", "content": "Write a short haiku."}],
    stream=True
)

for chunk in stream:
    delta = chunk.choices[0].delta
    if hasattr(delta, "reasoning_content") and delta.reasoning_content:
        print(delta.reasoning_content, end="", flush=True)
    if delta.content:
        print(delta.content, end="", flush=True)
```

---

## 6. Self-Healing & Safeguards Reference

### Automatic Crash Recovery
`qwen-server.service` uses `Restart=always` with `RestartSec=3`. If the process crashes or gets killed, systemd automatically restores the service in under 3 seconds.

### Memory & CPU Bounds
- If memory exceeds `28GB`, Linux begins throttling memory allocation.
- If memory attempts to exceed `32GB`, cgroups caps the process without affecting the host or `/opt/potato`.
- `CPUQuota=550%` guarantees at least 50% of one core is always reserved for the host OS and other services.

### Active Sentinel Watchdog
`qwen-sentinel.service` runs every 20 seconds:
1. Pings the health endpoint. If unresponsive for 3 consecutive checks (60s), it issues a restart.
2. Monitors available system RAM. If free memory dips below `3.5GB`, it automatically flushes OS page caches.
