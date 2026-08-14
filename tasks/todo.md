# Todo List: Deploy Qwen3.8-27B-GGUF with Self-Healing & 1-Click Installer

- [x] 1. Initial system discovery and architecture design <!-- id: 1 -->
- [x] 2. Download and deploy `Qwen3.8-27B-UD-Q4_K_XL.gguf` + `mmproj-F16.gguf` on remote server <!-- id: 2 -->
- [x] 3. Configure AVX2 multi-threaded inference with Flash Attention & Turbo 8-bit KV Cache (`-ctk q8_0 -ctv q8_0`) <!-- id: 3 -->
- [x] 4. Configure Linux kernel virtual memory tuning (`vm.swappiness=10`, `vm.vfs_cache_pressure=50`) <!-- id: 4 -->
- [x] 5. Harden systemd service with cgroups v2 memory bounds (28G/32G), CPU quota (550%), and OOMScoreAdjust <!-- id: 5 -->
- [x] 6. Create, install, and verify active health watchdog sentinel (`qwen-sentinel.service`) <!-- id: 6 -->
- [x] 7. Verify simulated crash recovery & automated self-healing <!-- id: 7 -->
- [x] 8. Verify isolation of `/opt/potato` on port 8080 <!-- id: 8 -->
- [x] 9. Build 1-click autonomous installer (`deploy.sh`) with colored output and health validation <!-- id: 9 -->
- [x] 10. Update and push to GitHub repository & GitHub Gist <!-- id: 10 -->
