# Multi-App VM Architecture & Networking

This document details the network topology, security model, and resource boundaries for running multiple containerized applications on a single Oracle Cloud Always Free VM.

---

## 1. Network Topology

```text
[ Internet / Visitors ]
          │
          ▼
[ Cloudflare Edge ]
    • DNS Management (portfolio.mnplabs.uk, ai-interviewer.mnplabs.uk)
    • Automatic HTTPS & SSL termination
    • DDoS protection & rate limiting
    • Cloudflare Turnstile bot protection
          │
          ▼ (Outbound QUIC / HTTP2 Tunnel Connection)
[ Oracle Cloud Always Free VM ]
    │
    ├── Host Systemd Services
    │    ├── mnplabs-runner (Org-wide GitHub Actions Runner for @mnplabs-gh)
    │    ├── cloudflared (WARP private network routing)
    │    └── docker (Container runtime)
    │
    └── Docker Engine
         │
         ├── Shared Bridge Network: "web-gateway"
         │    ├── core-cloudflared (Encrypted outbound Zero Trust tunnel)
         │    ├── portfolio-web (Listening on 8080 internally)
         │    ├── ai-interviewer-web (Listening on 8080 internally)
         │    └── core-dozzle (Listening on 8080 internally)
         │
         ├── Private Network: "portfolio_default"
         │    ├── portfolio-web
         │    └── portfolio-server (Listening internally)
         │
         └── Private Network: "ai-interviewer_default"
              ├── ai-interviewer-web
              └── ai-interviewer-server (Listening internally)
```

### Key Advantages

1. **Isolation by Default**: Backends (`portfolio-server`, `ai-interviewer-server`) reside only on their private project networks. They cannot reach each other, nor can they be reached directly from the tunnel or external network.
2. **DNS Routing**: Containers on `web-gateway` resolve each other via Docker's embedded DNS service. No host ports need to be mapped.
3. **Zero Firewall Holes**: The VM's public IP closes all inbound ports (22, 80, 443). Only the outbound Cloudflare Tunnel connects to Cloudflare Edge. SSH is restricted to private IP (`10.0.0.241`) over VPN / owner network.

---

## 2. Resource Budgeting & Safety

The Oracle Always Free Ampere VM provides:
- **Architecture**: ARM64 (aarch64)
- **vCPUs**: Up to 4 OCPU
- **Memory**: Up to 24 GB RAM
- **Disk**: 50 GB – 200 GB Block Storage

### Prevention of Out-Of-Memory (OOM) Cascades

If an unconstrained container leaks memory, the Linux kernel invokes the OOM killer, which may terminate critical system processes (`dockerd`, `sshd`, or `systemd`).

To make the host resilient:
1. **Explicit `mem_limit` on every container**:
   - Web frontends: 128 MB – 384 MB
   - API backends: 256 MB – 1024 MB
   - Core services: 64 MB – 128 MB
2. **Swapfile (4 GB – 8 GB)**:
   - Configured with `vm.swappiness=10`.
   - Swap acts as an emergency cushion during memory bursts, preventing immediate process termination while keeping disk I/O low during normal operations.
3. **Log Caps**:
   - Standard `/etc/docker/daemon.json` restricts container logs to 3 files of 20MB each.
