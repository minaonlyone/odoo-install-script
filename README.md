# Odoo 20 Install Script

One-shot installer for **Odoo 20.0** on Ubuntu 24.04 LTS+ and Debian 13+, for x86, x86_64 and ARM.

> **Ported from [Yenthe666/InstallScript](https://github.com/Yenthe666/InstallScript) 19.0.**
> All credit for the original script goes to [Yenthe Van Ginneken](https://github.com/Yenthe666),
> which itself builds on the install script by
> [André Schenkels](https://github.com/aschenkels-ictstudio/openerp-install-scripts).
> This repository is the Odoo 20.0 port of that work, kept MIT licensed.
> The changes were also submitted upstream as
> [Yenthe666/InstallScript#473](https://github.com/Yenthe666/InstallScript/pull/473).

## Which script do I use?

| Script | Target |
|---|---|
| `odoo_install.sh` | Ubuntu 24.04 LTS and newer |
| `odoo_install_debian.sh` | Debian 13 (trixie) and newer |

Both share the same logic and options; only the defaults differ (distribution codename,
certbot install method).

## Requirements for Odoo 20

Odoo 20 raised its minimum requirements. The scripts check these and abort with a clear
message instead of producing a broken install:

| | Odoo 19 | Odoo 20 |
|---|---|---|
| Python | 3.10+ | **3.12+** |
| PostgreSQL | 13+ | **16+** |
| `http_interface` default | `0.0.0.0` | **`127.0.0.1`** |

Because of the Python requirement, **Ubuntu 22.04 (Python 3.10) and Debian 12
(Python 3.11) can no longer run Odoo 20**. Use Ubuntu 24.04 LTS or Debian 13 or newer.

### The `http_interface` change

This is the one most likely to catch you out. Odoo 20 binds to `127.0.0.1` by default, so
a fresh install on a VPS is unreachable from anywhere but the machine itself. Odoo 19 even
warns about it in advance:

> `missing http_interface, using 0.0.0.0 by default, will change to 127.0.0.1 in 20.0`

These scripts write it explicitly: `0.0.0.0` on a plain install, `127.0.0.1` when Nginx is
installed in front of Odoo. Override with `HTTP_INTERFACE`.

## Installation

### 1. Download the script

Ubuntu:
```bash
wget https://raw.githubusercontent.com/minaonlyone/odoo-install-script/main/odoo_install.sh
```

Debian:
```bash
wget https://raw.githubusercontent.com/minaonlyone/odoo-install-script/main/odoo_install_debian.sh
```

### 2. Configure it

Open the script and edit the variables at the top.

| Option | Meaning |
|---|---|
| `OE_USER` | System user Odoo runs as. Default `odoo`. |
| `OE_VERSION` | Odoo version to install. Default `20.0`. |
| `OE_PORT` | HTTP port. Default `8069`. |
| `HTTP_INTERFACE` | Interface to bind. Empty = auto (`0.0.0.0`, or `127.0.0.1` with Nginx). |
| `GEVENT_PORT` | Websocket port (live chat, bus, notifications). Default `8072`. |
| `IS_ENTERPRISE` | `True` to install Enterprise on top. Requires access to `odoo/enterprise`. |
| `INSTALL_POSTGRESQL_PGDG` | Install PostgreSQL from postgresql.org instead of the distro. |
| `POSTGRESQL_VERSION` | PostgreSQL major version. Default `17`. Odoo 20 needs 16+. |
| `DEPENDENCIES_MODE` | `apt` (distribution packages, recommended) or `pip` (`requirements.txt`). |
| `INSTALL_WKHTMLTOPDF` | Install wkhtmltopdf. Default `True`. |
| `INSTALL_PAPER_MUNCHER` | Install Paper Muncher, the new Odoo 20 PDF engine. amd64 only, opt-in. |
| `USE_SYSTEMD` | `False` to keep the legacy `/etc/init.d` service. |
| `GENERATE_RANDOM_PASSWORD` | Generate a random master password. Default `True`. |
| `OE_SUPERADMIN` | Master password when not generating a random one. |
| `INSTALL_NGINX` | Install and configure Nginx. Default `False`. |
| `WEBSITE_NAME` | Domain for the Nginx config. |
| `ENABLE_SSL` | Install certbot and enable HTTPS. Needs `INSTALL_NGINX` and a real `ADMIN_EMAIL`. |
| `ADMIN_EMAIL` | Email for the Let's Encrypt registration. |

### 3. Run it

```bash
chmod +x odoo_install.sh
sudo ./odoo_install.sh
```

## Dependency handling

By default the scripts install the Python dependencies from the **distribution packages**,
parsed out of Odoo's own `debian/control`. This is the method Odoo documents, and it avoids
fighting PEP 668 on Ubuntu 24.04.

Odoo's `debian/control` uses alternatives such as `python3-lxml-html-clean | python3-lxml`,
which `apt-get install` does not understand. The scripts resolve each one to the first
package that actually exists in the configured sources.

Set `DEPENDENCIES_MODE="pip"` to install from `requirements.txt` instead.

## PDF engines

Odoo 20 has a pluggable PDF engine. `base_report_wkhtmltox` is `auto_install`, so
**wkhtmltopdf stays the default**.

The scripts install the official `0.12.6.1-3` build that is patched against Qt, because the
build shipped by Ubuntu and Debian is not, and report headers and footers silently go
missing with it. The distribution package is only used as a fallback, with a warning.

To use [Paper Muncher](https://odoo.github.io/paper-muncher/) instead, set
`INSTALL_PAPER_MUNCHER="True"` and then:

1. Install the `base_report_paper_muncher` module in your database.
2. Set the `report.pdf_engine_default` system parameter to `paper-muncher`
   (Settings ‣ Technical ‣ System Parameters).

## Enterprise

Set `IS_ENTERPRISE="True"`. You need to be an official Odoo partner with access to
[github.com/odoo/enterprise](https://github.com/odoo/enterprise).

The script also installs `pgvector` and creates the `vector` extension in `template1`, which
the Enterprise AI modules need for RAG. It is created in `template1` on purpose: the Odoo
PostgreSQL role is deliberately **not** a superuser, so it cannot run `CREATE EXTENSION`
itself, and inheriting from `template1` means every new database gets it.

## Nginx and the websocket

If you enable Nginx, the generated config proxies `/websocket` to the gevent port with the
`Upgrade` / `Connection` headers the Odoo bus requires. `longpolling_port` was removed in
Odoo 20 and the config file writes `gevent_port` instead.

If you run Odoo behind Nginx you should also configure workers. See the
[Odoo deployment guide](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html).

## Testing

`test_install/` contains a Docker setup that runs either script in a clean container:

```bash
cd test_install
docker compose build
docker compose up -d
docker compose exec odoo20-ubuntu bash -c 'cp /opt/odoo-install/odoo_install.sh /root/run.sh && chmod +x /root/run.sh && /root/run.sh'
```

This port was verified end to end on Ubuntu 24.04 and Debian 13 (arm64) and on amd64 for
Paper Muncher: PostgreSQL 17 from PGDG, all 48 dependencies resolved from `debian/control`,
wkhtmltopdf `0.12.6.1 (with patched qt)`, pgvector 0.8.6, 868 Enterprise modules, and
Odoo 20.0 booting and serving the web client in both Community (53 apps) and Enterprise
(80 apps) mode.

## Minimal server requirements

Use at least **2 GB of RAM**. A Linux instance typically uses 300–500 MB and the rest has to
be split between Odoo, PostgreSQL and everything else. Installs on 1 GB machines are known
to fail.

## License

MIT. See [LICENSE](LICENSE). Original copyright Yenthe V.G, with the Odoo 20 port
copyright added alongside it.
