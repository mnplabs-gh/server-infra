# CI/CD Standard: Build on GitHub Free Minutes, Deploy on Host

This document explains the division of labor between GitHub-hosted runners and the host VM runner.

---

## The Rule

> **All CPU-heavy tasks (linting, tests, compilation, Docker image builds) MUST run on GitHub's free-tier hosted runners.**
> **The host machine ONLY runs the final lightweight deployment job.**

---

## Why This Architecture?

| Responsibility | Handled By | Why |
| :--- | :--- | :--- |
| **Typecheck & Tests** | GitHub-hosted runner (`ubuntu-24.04`) | Runs in an isolated ephemeral VM; doesn't pollute host storage; consumes free monthly minutes. |
| **ARM64 Docker Build** | GitHub-hosted runner (`ubuntu-24.04-arm`) | Building Docker layers, compiling native modules, and running Buildx is CPU and RAM intensive. Running it on GitHub keeps your host VM's CPU low and prevents user-facing latency spikes on live apps. |
| **Image Storage** | GitHub Container Registry (GHCR) | Images are securely stored in private packages and pulled directly by the VM over high-speed networks. |
| **Deploy & Restart** | Host Machine Runner (`[self-hosted, linux, arm64]`) | Ultra-fast (~15 seconds): writes `.env`, runs `docker compose pull`, restarts containers, verifies `/api/health`. |

---

## GitHub Free Minutes Breakdown

- Every GitHub personal account receives **2,000 free Actions minutes per month**.
- GitHub provides **standard ARM64 runners** (`ubuntu-24.04-arm`) that qualify for free tier minutes on both public and private repositories.
- Using `ubuntu-24.04-arm` avoids the slow emulation overhead of QEMU (`docker buildx --platform linux/arm64` on an x86 runner). Builds are native ARM64 and typically take 1 to 2 minutes with GitHub Actions layer caching (`type=gha`).

---

## Anatomy of the Pipeline

```text
[ Push to main ]
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ 1. Job: "check"                                         │
│    Runs on: ubuntu-24.04 (GitHub-hosted)               │
│    Actions: npm test, typecheck, lint                   │
└────────────────────────────────────────────────────────┘
       │ (Pass)
       ▼
┌────────────────────────────────────────────────────────┐
│ 2. Job: "build"                                         │
│    Runs on: ubuntu-24.04-arm (GitHub-hosted)           │
│    Actions: Docker buildx -> Tag -> Push to GHCR        │
└────────────────────────────────────────────────────────┘
       │ (Pass)
       ▼
┌────────────────────────────────────────────────────────┐
│ 3. Job: "deploy"                                        │
│    Runs on: [self-hosted, linux, arm64] (The Host VM)  │
│    Actions:                                            │
│      1. Write production secrets to .env               │
│      2. docker compose pull                            │
│      3. docker compose up -d                           │
│      4. curl /api/health                               │
│      5. Clean previous image tags                      │
└────────────────────────────────────────────────────────┘
```

---

## Runner Security & Isolation

- The deploy job runs under an unprivileged user on the VM.
- Secrets never touch git: they are injected directly from GitHub Environment Secrets into the local `.env` file with `umask 077` permissions (read-only by the owner).
- GHCR tokens used for pulling images expire immediately when the workflow job finishes.
