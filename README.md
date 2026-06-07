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
curl -fsSLO https://raw.githubusercontent.com/nicolaeser/zeroclaw-create/main/zeroclaw-create.sh
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
├── manage.sh      # start / stop / backup / update helper for this instance
├── data/          # persistent: config.toml, secrets.key, *.db memory, receipts/  (survives updates)
├── web/           # dashboard assets (only if dashboard enabled)
└── backups/       # tar.gz snapshots from `./manage.sh backup` (and one before every update)
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

ZeroClaw does **not** auto-update. Subscribe to the release feed (GitHub releases or the Discord `#releases` channel), read the release notes, then update on your own cadence:

```bash
cd /opt/zeroclaw/<instance>
sudo ./manage.sh update
```

`update` runs the whole safe sequence for you:

1. **stop** the container
2. **backup** `data/` — taken cold (container stopped) so the SQLite snapshot is consistent
3. **pull** the latest stable image and re-pin its digest in `docker-compose.yml`
4. **refresh** the version-matched dashboard — new assets are staged in `web.new` and atomically moved into place
5. **start** the container
6. **health** — probe `http://127.0.0.1:<port>/health`

If the dashboard refresh can't reach GitHub it keeps the existing dashboard, still starts the service on the new binary, and warns you to re-run `update` later — a transient fetch failure never leaves the instance stopped.

Your `./data` is preserved and the binary auto-migrates the config on boot. If the startup log warns about a pending schema migration, apply it manually:

```bash
docker compose exec zeroclaw zeroclaw config migrate   # apply any pending schema migrations
docker compose exec zeroclaw zeroclaw config list      # spot-check values after the upgrade
```

> "Latest" means the latest **stable** release (the `:debian` tag). Pre-release/beta versions are not published as Docker images and aren't reachable through this script.
>
> Re-running `zeroclaw-create.sh` with the same instance name does the same image + dashboard refresh and is also how an instance created before this version gets its `manage.sh`.

## Managing an instance

Every instance gets its own `manage.sh`. Run it from the instance directory as root:

```bash
cd /opt/zeroclaw/<instance>
sudo ./manage.sh start      # bring it up        (docker compose up -d)
sudo ./manage.sh stop       # halt it            (docker compose stop)
sudo ./manage.sh restart    # restart the container
sudo ./manage.sh backup     # snapshot data/ -> backups/   (excludes workspace/cache)
sudo ./manage.sh update     # stop -> backup -> pull latest image + dashboard -> start -> health
sudo ./manage.sh logs       # follow logs        (pairing code shown on boot)
sudo ./manage.sh onboard    # re-run console onboarding
sudo ./manage.sh health     # show status + probe /health
```

`manage.sh` is self-contained and always operates on its own directory, so you can copy an instance folder to another host and manage it there without the installer. The raw `docker compose ...` commands still work if you prefer them.

## Backups

`sudo ./manage.sh backup` writes a timestamped archive to `backups/` containing everything that isn't regenerable:

- `data/config.toml` — channel credentials (encrypted if you use the secrets store)
- `data/secrets.key` — master key for the encrypted secrets store; **without it the config's secrets are unrecoverable**
- `data/workspace/*.db` — SQLite conversation memory
- `data/workspace/receipts/` — tool-receipts log

`data/workspace/cache/` is **excluded** — it's regenerable and can be large.

The standalone `backup` command runs **hot** (no downtime); the backup taken inside `update` runs **cold** (container stopped first) so the SQLite snapshot is guaranteed consistent. For scheduled or incremental backups, point restic, borg, or Duplicacy at the `data/` directory (excluding `workspace/cache`).

Restore a snapshot:

```bash
cd /opt/zeroclaw/<instance>
sudo ./manage.sh stop
sudo rm -rf data            # optional — for a pristine restore instead of an overlay
sudo tar xzf backups/zeroclaw-<instance>-<timestamp>.tar.gz -C .
sudo ./manage.sh start
```
