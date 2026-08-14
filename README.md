# 🚀 Qwen3.8-27B-GGUF Enterprise OpenAI Compatible Server

A commercial-grade, fully automated 1-click deployment suite for serving **Qwen3.8-27B-GGUF** ([`unsloth/Qwen3.8-27B-GGUF`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)) on Linux with **Native Multi-Token Prediction (MTP) Speculative Decoding (~2.22 tokens/sec)**, **Persistent 3.7 GHz CPU Governor**, **mmap+mlock RAM Pinning**, **65k Safe Context**, **cgroups v2 boundaries**, **Self-Healing Watchdog**, **Universal Firewall Config**, and **Global `qwen-admin` CLI**.

---

## ⚡ Commercial 1-Click Installer

Execute this single command on your Linux server:

```bash
curl -sSL https://raw.githubusercontent.com/vskrch/qwen3.8-gguf-deploy/main/deploy.sh | sudo bash
```

Or clone and execute with custom options:

```bash
git clone https://github.com/vskrch/qwen3.8-gguf-deploy.git
cd qwen3.8-gguf-deploy
sudo bash deploy.sh -y --port 8000 --ctx 65536
```

---

## 🛠 Complete 11-Step Enterprise Installer Architecture

`deploy.sh` executes an 11-stage automated deployment pipeline:

1. **Pre-flight & Hardware Integrity Checks**: Validates OS, x86_64 architecture, AVX2 vector SIMD flags, RAM capacity, root disk space, and port availability.
2. **Enterprise Kernel & Virtual Memory Optimization**: Applies `vm.swappiness=10`, `vm.vfs_cache_pressure=50`, `vm.overcommit_memory=1`, and unlimited PAM `memlock` limits.
3. **Persistent CPU Turbo Performance Governor**: Deploys `cpu-performance.service` to lock all CPU cores to maximum Turbo frequency (3.7 GHz+) across reboots.
4. **SSD Virtual Memory Swap Pool**: Provisions a dedicated 32 GB SSD swapfile (`/swapfile_qwen`) for 82.5 GB total virtual memory pool.
5. **Essential Enterprise Package Sync**: Installs and verifies `aria2`, `curl`, `wget`, `tar`, `gzip`, `jq`, and firewall tools.
6. **Native AVX2 Engine Installation**: Deploys the latest optimized `llama-server` engine with custom library paths.
7. **16-Stream Accelerated Model Downloader**: Multi-stream parallel downloading of `Qwen3.8-27B-UD-Q4_K_XL.gguf` with auto-resume and checksum verification.
8. **Hardened Systemd Service with Native MTP Speculation**: Deploys `qwen-server.service` configured with:
   - Native Multi-Token Prediction Speculative Decoding (`--spec-type draft-mtp --spec-draft-n-max 2`)
   - Physical RAM Pinning (`--load-mode mmap+mlock` with `LimitMEMLOCK=infinity`)
   - L3 Cache Micro-Batching (`-b 512 -ub 256`)
   - Turbo 4-bit KV Cache (`-ctk q4_0 -ctv q4_0`) & Flash Attention (`--flash-attn on`)
   - cgroups v2 caps: `MemoryHigh=28G`, `MemoryMax=32G`, `CPUQuota=550%`, `Nice=-5`
9. **Self-Healing Sentinel Watchdog & Safe Disk Reclaimer**: Deploys `qwen-sentinel.service` to monitor health every 20s, auto-restart on deadlocks, drop page cache when RAM < 4 GB, and safely flush used swap back to disk when memory is freed.
10. **Enterprise Firewall & Network Policy**: Automatically opens port 8000 across UFW, Firewalld, and iptables.
11. **Readiness Verification Probe & Global `qwen-admin` Tool**: Polls readiness endpoint until healthy and installs `/usr/local/bin/qwen-admin`.

---

## 🛠 Global Diagnostic CLI (`qwen-admin`)

| Subcommand | Description |
| :--- | :--- |
| `sudo qwen-admin status` | Displays live service status, CPU frequencies, RAM, and swap metrics |
| `sudo qwen-admin logs` | Follows live generation logs and millisecond profiler in real time |
| `sudo qwen-admin sentinel-logs` | Follows memory watchdog events and auto-healing triggers |
| `sudo qwen-admin restart` | Restarts inference server and sentinel watchdog cleanly |
| `sudo qwen-admin test` | Runs an end-to-end streaming latency smoke test |
| `sudo qwen-admin uninstall` | Cleanly purges services, configs, and binaries |

---

## 📡 OpenAI-Compatible API Integration

### Streaming cURL Example (Instant Response)

```bash
curl -N http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B",
    "messages": [
      {"role": "user", "content": "Explain quantum computing briefly."}
    ],
    "stream": true
  }'
```

### Python (Official OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"
)

stream = client.chat.completions.create(
    model="Qwen3.8-27B",
    messages=[{"role": "user", "content": "Explain quantum computing briefly."}],
    stream=True
)

for chunk in stream:
    delta = chunk.choices[0].delta
    if hasattr(delta, "reasoning_content") and delta.reasoning_content:
        print(delta.reasoning_content, end="", flush=True)
    if delta.content:
        print(delta.content, end="", flush=True)
```
