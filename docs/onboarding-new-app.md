# Runbook: Onboarding a New Application

Follow these steps to deploy a new application to the shared VM in under 10 minutes.

---

## Checklist

### 1. Register the Application in this Repo
Open [REGISTRY.md](../REGISTRY.md) and allocate:
- **Public Hostname**: e.g., `myapp.mnplabs.in`
- **Compose Project Name**: e.g., `myapp`
- **Internal Container Name**: e.g., `myapp-web:8080`
- **Memory & CPU Caps**: e.g., `256m`, `0.2`

Commit and push the update to `server-infra`.

---

### 2. Configure Cloudflare Tunnel
In Cloudflare Zero Trust:
1. Go to **Networks** $\rightarrow$ **Tunnels** $\rightarrow$ select your tunnel.
2. In the **Public Hostnames** tab, click **Add a public hostname**.
3. Set:
   - **Subdomain**: `myapp`
   - **Domain**: `mnplabs.in`
   - **Type**: `HTTP`
   - **URL**: `myapp-web:8080` (resolves over `web-gateway`)
4. Save the hostname.

---

### 3. Add Compose Configuration to the Application Repo
In your new application's repo, create `deploy/docker-compose.yml` (based on [templates/docker-compose.app.yml](../templates/docker-compose.app.yml)):

```yaml
name: myapp

services:
  web:
    image: ${IMAGE_REPO}/web:${IMAGE_TAG:-latest}
    restart: unless-stopped
    init: true
    mem_limit: 256m
    cpus: 0.2
    networks:
      - web-gateway
    env_file: .env

networks:
  web-gateway:
    name: web-gateway
    external: true
```

---

### 4. Add the Standard CI/CD Workflow
In the application repo, create `.github/workflows/deploy.yml` (based on [templates/github-workflow.app.yml](../templates/github-workflow.app.yml)):
- Ensure `check` runs on `ubuntu-24.04`.
- Ensure `build` runs on `ubuntu-24.04-arm` and pushes to GHCR.
- Ensure `deploy` runs on `[self-hosted, linux, arm64]`.

> [!NOTE]
> Because your VM runs an **organization-level runner** (`@mnplabs-gh`), you do **not** need to install or configure any runner on the host! The runner is automatically available to all repos in `@mnplabs-gh` on day one.

---

### 5. Configure GitHub Secrets & Environments
In the application repo's GitHub settings:
1. Under **Environments**, create an environment named `production`.
2. Add secrets/variables required by the application (e.g. database connection string, API keys).
3. Push to `main`. GitHub Actions will build on GitHub free compute and deploy to the VM automatically!
