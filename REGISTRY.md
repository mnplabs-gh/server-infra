# Service Registry

This registry is the **Single Source of Truth** for all containers and services hosted on the VM. When adding, modifying, or retiring a service, update this table.

---

## Active Services

| Service Name | Public Hostname | Compose Name | Internal Docker DNS | Memory Limit | CPU Limit | Runner / CI | Persistent Data |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Cloudflare Tunnel** | N/A (Ingress) | `core` | `core-cloudflared` | `128m` | `0.1` | server-infra CI/CD (`mnplabs-runner`) | None (Stateless) |
| **Portainer CE** | `portainer.mnplabs.in` | `core` | `core-portainer:9000` | `128m` | `0.2` | server-infra CI/CD (`mnplabs-runner`) | Volume: `core-portainer_data` |
| **Portfolio Web** | `portfolio.mnplabs.in` | `portfolio` | `portfolio-web:8080` | `384m` | `0.3` | portfolio CI/CD (`mnplabs-runner`) | None |
| **Portfolio API** | Internal (`/api`) | `portfolio` | `portfolio-server:3000` | `256m` | `0.2` | portfolio CI/CD (`mnplabs-runner`) | MongoDB (Atlas / external) |
| **AI Interviewer Web** | `ai-interviewer.mnplabs.in` | `ai-interviewer` | `ai-interviewer-web:8080` | `128m` | `0.1` | ai-interviewer CI/CD (`mnplabs-runner`) | None |
| **AI Interviewer API** | Internal (`/api`) | `ai-interviewer` | `ai-interviewer-server:3000` | `1024m` (1G) | `0.4` | ai-interviewer CI/CD (`mnplabs-runner`) | MongoDB (Atlas / external) |

---

## Total Resource Allocation Budget

Based on Oracle Cloud Always Free Ampere VM (Up to 4 OCPU, 24 GB RAM):

| Category | Allocated RAM | Allocated vCPU |
| :--- | :--- | :--- |
| **Core Infrastructure** (Tunnel, Logs, Systemd) | ~256 MB | 0.2 OCPU |
| **Active Applications** (`portfolio` + `ai-interviewer`) | ~1.8 GB | 1.0 OCPU |
| **Host System Reserve** (Kernel, OS, Docker daemon) | ~1.0 GB | 0.5 OCPU |
| **Available Headroom for New Apps** | **> 20.0 GB** | **> 2.3 OCPU** |

> [!NOTE]
> Even on a 1-OCPU / 6GB or 1GB instance, our conservative per-container limits (`mem_limit`) and 4GB swap space ensure stable operation with zero out-of-memory crashes.

---

## Network Architecture & Isolation

All public traffic flows through the `web-gateway` bridge network:

```text
[Cloudflare Edge]
       │ (Encrypted WireGuard/QUIC outbound tunnel)
       ▼
[core-cloudflared container]
       ├── (bridge: web-gateway) ──> [portfolio-web:8080] ──> [portfolio-server] (private network)
       └── (bridge: web-gateway) ──> [ai-interviewer-web:8080] ──> [ai-interviewer-server] (private network)
```

- **Frontends**: Connect to `web-gateway` so Cloudflare Tunnel can reach them.
- **Backends / APIs**: Only connect to their application's private compose network. The web frontend proxies `/api` to the backend. No external internet or unrelated container can reach backend APIs directly.
- **Databases**: MongoDB is hosted externally (e.g. Atlas M0) or kept on isolated volume networks.
