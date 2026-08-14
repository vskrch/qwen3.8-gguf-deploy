# Todo List: Implement Self-Healing, Auto-Memory Optimization & Crash Recovery

- [ ] 1. Design and configure Linux Virtual Memory kernel optimizations (`vm.swappiness=10`, `vm.vfs_cache_pressure=50`) <!-- id: 1 -->
- [ ] 2. Harden `qwen-server.service` with cgroups v2 resource boundaries (`MemoryHigh`, `MemoryMax`, `CPUQuota`, `OOMScoreAdjust`, `Nice`, auto-restart policies) <!-- id: 2 -->
- [ ] 3. Create active health check & self-healing sentinel daemon (`qwen-sentinel.sh` and `qwen-sentinel.service`) <!-- id: 3 -->
- [ ] 4. Deploy and enable the sentinel on `10.0.0.73` <!-- id: 4 -->
- [ ] 5. Test and verify self-healing (simulate stall/crash and verify auto-recovery and memory clearance) <!-- id: 5 -->
- [ ] 6. Update local repository & GitHub docs/scripts <!-- id: 6 -->
