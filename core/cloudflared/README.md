# Cloudflare Tunnel Configuration Guide

Cloudflare Tunnel (`cloudflared`) connects your VM's containers to Cloudflare's edge network without opening any public ports on your VM firewall.

## Two Ways to Manage Routes

### Method 1: Dashboard-Managed Tunnel (Recommended by Cloudflare)

This is the simplest and lowest-maintenance method:
1. In Cloudflare Zero Trust: **Networks** $\rightarrow$ **Tunnels** $\rightarrow$ select your tunnel.
2. Under the **Public Hostnames** tab, click **Add a public hostname**.
3. Fill in:
   - **Subdomain**: `portfolio`
   - **Domain**: `mnplabs.uk`
   - **Service Type**: `HTTP`
   - **URL**: `portfolio-web:8080` (or `localhost:8082` if transitioning)
4. Add hostnames for each app:
   - `ai-interviewer.mnplabs.uk` $\rightarrow$ `HTTP://ai-interviewer-web:8080`
   - `logs.mnplabs.uk` $\rightarrow$ `HTTP://core-dozzle:8080`
5. Click Save. Cloudflare updates the tunnel instantly over the established control connection—no restart needed!

### Method 2: Local `config.yml`

If you manage tunnels via configuration files on the server:
1. Copy `config.example.yml` to `/etc/cloudflared/config.yml`.
2. Replace `<YOUR-TUNNEL-UUID>` with your tunnel ID.
3. Restart `cloudflared`:
   ```bash
   docker compose restart cloudflared
   # or systemctl restart cloudflared if running natively
   ```

## Transitioning from Host Ports (`localhost:8082`) to Docker Network (`portfolio-web:8080`)

- **Before**: Tunnel $\rightarrow$ `localhost:8082` (requires container to publish port `8082` to host).
- **After**: Tunnel $\rightarrow$ `http://portfolio-web:8080` (container joins `web-gateway`, zero host ports published).
- Both can coexist during transition! You can migrate apps one-by-one.
