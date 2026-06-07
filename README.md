# zeroclaw-create

Interactive one-shot installer for running one or more [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) assistants in Docker on a single host.

It asks a few questions, generates a minimal `docker-compose.yml` under `/opt/zeroclaw/<instance>`, brings it up, and drops you straight into onboarding.

## Why

The published ZeroClaw Docker images (`:latest`, `:debian`, …) **do not bundle the web dashboard** — the frontend was decoupled from the binary and only ships in the standalone packages, so a bare `docker run` serves `503 Web dashboard not available`. This script fixes that by fetching the dashboard from the matching release tarball and mounting it, so the browser UI and `/onboard` flow work out of the box (or you can skip it and configure from the console).

## Requirements

- Linux **x86_64** host with Docker + Docker Compose v2
- `curl`, `tar` (standard on most systems)
- Run as **root** (it writes to `/opt/zeroclaw` and `chmod`s the data dir)

## Usage

```bash
curl -fsSLO https://raw.githubusercontent.com/<you>/zeroclaw-create/main/zeroclaw-create.sh
chmod +x zeroclaw-create.sh
sudo ./zeroclaw-create.sh
```

You'll be asked for:

| Prompt | Default | Notes |
|--------|---------|-------|
| **Instance name** | `default` | Becomes the folder `/opt/zeroclaw/<name>` and the compose project name |
| **Host interface** | `0.0.0.0` | `127.0.0.1` = this machine only (reach via SSH tunnel); `0.0.0.0` = LAN |
| **Port** | `42617` | Host port to publish |
| **Web dashboard** | `yes` | `no` = headless; configure later with `zeroclaw onboard` |

When it finishes it prints the URL and the one-time **pairing code**, then launches the onboarding wizard in your terminal.

## What it creates

```
/opt/zeroclaw/<instance>/
├── docker-compose.yml
├── data/          # persistent: config.toml, memory, sessions  (survives updates)
└── web/           # dashboard assets (only if dashboard enabled)
```

The image is pinned by digest and the dashboard is version-matched to it, so an instance never drifts on its own.

## Multiple instances per host

Just run it again with a different name and port:

```bash
sudo ./zeroclaw-create.sh   # mail-bot  → /opt/zeroclaw/mail-bot   :42617
sudo ./zeroclaw-create.sh   # ops-bot   → /opt/zeroclaw/ops-bot    :42618
```

Each gets its own directory, compose project, network, and data.

## Updating

Re-run the script with the **same instance name**. It pulls the latest stable image, refreshes the matching dashboard, and recreates the container — **your `./data` is preserved** (config auto-migrates). The onboarding wizard reappears but is non-destructive (choose *keep* to leave your setup untouched).

> "Latest" means the latest **stable** release (the `:debian` tag). Pre-release/beta versions are not published as Docker images and aren't reachable through this script.

## Managing an instance

```bash
cd /opt/zeroclaw/<instance>
docker compose logs -f          # follow logs (pairing code shown on boot)
docker compose restart          # restart
docker compose down             # stop & remove (data dir is kept)
docker compose exec zeroclaw zeroclaw onboard   # re-run console onboarding
```
