# Disaster Recovery & Rebuild Runbook

If the Oracle Cloud VM is accidentally terminated, corrupted, or replaced, follow this runbook to restore all services from scratch.

---

## 1. Launch a New Instance on Oracle Cloud

1. In Oracle Cloud Console: **Compute** $\rightarrow$ **Instances** $\rightarrow$ **Create Instance**.
2. **Shape**: Ampere (ARM64) A1.Flex (Up to 4 OCPU, 24 GB RAM, Always Free).
3. **OS**: Ubuntu 24.04 LTS or Oracle Linux 9.
4. **Networking**: Ensure private IP is assigned, and your SSH key is added.
5. Inbound Security List: Block all inbound ports from `0.0.0.0/0`. Allow inbound SSH (port 22) only from your private management CIDR.

---

## 2. Bootstrap the Host

SSH into the new instance:

```bash
# Clone the infrastructure repo
git clone https://github.com/mnp-gh/server-infra.git ~/server-infra
cd ~/server-infra/bootstrap

# Make scripts executable and run the host setup
chmod +x *.sh
sudo ./setup-host.sh
./install-prune-cron.sh
```

---

## 3. Reconnect Cloudflare Tunnel

1. Open `~/server-infra/core`:
   ```bash
   cd ~/server-infra/core
   cp .env.example .env
   ```
2. Put your `TUNNEL_TOKEN` into `.env`.
3. Start core infrastructure:
   ```bash
   docker compose up -d
   ```
4. Verify tunnel status in Cloudflare Zero Trust Dashboard $\rightarrow$ Networks $\rightarrow$ Tunnels. Status should show **Healthy**.

---

## 4. Re-register GitHub Actions Runner(s)

1. Download and extract the GitHub Actions runner for ARM64:
   ```bash
   mkdir -p ~/actions-runner-portfolio && cd ~/actions-runner-portfolio
   curl -o actions-runner-linux-arm64.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-arm64-2.321.0.tar.gz
   tar xzf actions-runner-linux-arm64.tar.gz
   ```
2. Get the runner token from GitHub repo (Settings $\rightarrow$ Actions $\rightarrow$ Runners $\rightarrow$ New runner).
3. Configure and install systemd service:
   ```bash
   ./config.sh --url https://github.com/mnp-gh/portfolio --token <TOKEN> --name portfolio-gh-runner --labels self-hosted,linux,arm64
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```
4. If using SELinux (Oracle Linux):
   ```bash
   sudo chcon -R -t bin_t ~/actions-runner-*
   sudo systemctl restart actions.runner.*
   ```

---

## 5. Redeploy All Applications

Since all application images are preserved in GitHub Container Registry (GHCR), simply go to GitHub Actions for each repo (`portfolio`, `ai-interviewer`) and trigger the **CI/CD** workflow (or re-run the latest successful deploy job).

Your services will pull their latest images and be fully operational within minutes.
