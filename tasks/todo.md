# Todo List: Deploy Qwen3.8-27B-GGUF with OpenAI-Compatible API

- [x] 1. Initial system discovery and architecture design <!-- id: 1 -->
- [x] 2. Initialize local repository & comprehensive deployment scripts/docs (`deploy.sh`, `qwen-server.service`, `README.md`, `GIST.md`, `test_client.py`) <!-- id: 2 -->
- [x] 3. Install prerequisites on remote host (`aria2`, `/opt/qwen-server` directories) <!-- id: 3 -->
- [x] 4. Download and setup `llama-server` (build 10431) in `/opt/qwen-server/bin` <!-- id: 4 -->
- [x] 5. Download multimodal projector `mmproj-F16.gguf` <!-- id: 5 -->
- [x] 6. Download `Qwen3.8-27B-UD-Q4_K_XL.gguf` (~16.7 GB) via aria2 <!-- id: 6 -->
- [x] 7. Create and register `/etc/systemd/system/qwen-server.service` on port 8000 <!-- id: 7 -->
- [x] 8. Start and enable `qwen-server.service` <!-- id: 8 -->
- [x] 9. Configure firewall rule for port 8000 (`ufw allow 8000/tcp`) <!-- id: 9 -->
- [x] 10. Verify OpenAI endpoints (`/v1/models`, `/v1/chat/completions` streaming & non-streaming) <!-- id: 10 -->
- [x] 11. Verify isolation of `/opt/potato` (port 8080) <!-- id: 11 -->
- [x] 12. Create final walkthrough document <!-- id: 12 -->
