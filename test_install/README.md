# Odoo 20 Installer Test Environment

This folder provides a minimal Docker setup to exercise the installer scripts in clean
containers:

| Service | Image | Script under test | Host port |
|---|---|---|---|
| `odoo20-ubuntu` | `ubuntu:24.04` | `../odoo_install.sh` | 8069 |
| `odoo20-debian` | `debian:13` | `../odoo_install_debian.sh` | 8169 |

## Prerequisites
- Docker 24+
- Docker Compose plugin (`docker compose` CLI)

## Build the Images
```bash
docker compose build
```

## Start the Test Containers
Run the containers detached so they stay online for manual testing:
```bash
docker compose up -d
```

## Run an Installer Script Inside a Container

Ubuntu:
```bash
docker compose exec odoo20-ubuntu bash -c 'cp /opt/odoo-install/odoo_install.sh /root/run.sh && chmod +x /root/run.sh && /root/run.sh'
```

Debian:
```bash
docker compose exec odoo20-debian bash -c 'cp /opt/odoo-install/odoo_install_debian.sh /root/run.sh && chmod +x /root/run.sh && /root/run.sh'
```

The scripts are mounted read-only, so they are copied into the container before running.
They run as root inside the container, so the bundled `sudo` calls succeed without
additional configuration. The images already set locale and timezone data to avoid
interactive prompts from `tzdata`.

## Verify the Install
```bash
docker compose exec odoo20-ubuntu /etc/init.d/odoo-server start
curl -sSI http://localhost:8069/web/database/selector | head -n 1
```

## Reset the Environment
To destroy the test containers and start fresh:
```bash
docker compose down -v
```

Re-run the **Build** and **Start** steps to begin another test cycle.

## Notes for Odoo 20

- Odoo 20 requires Python 3.12+, so the images have to stay on Ubuntu 24.04+ / Debian 13+.
  Ubuntu 22.04 (Python 3.10) and Debian 12 (Python 3.11) are rejected by the scripts.
- Containers have no `systemd`, so the scripts automatically fall back to the
  `/etc/init.d` service. Start the server with `/etc/init.d/odoo-server start`.
- PostgreSQL is not started by an init system inside the container either; the scripts
  fall back to `service postgresql start` and then `/etc/init.d/postgresql start`.
- Paper Muncher (`INSTALL_PAPER_MUNCHER="True"`) is only published for amd64. On an
  Apple Silicon or other arm64 host, test it with an amd64 container:
  `docker compose build --build-arg TARGETPLATFORM=linux/amd64` or run the image with
  `--platform linux/amd64`.
