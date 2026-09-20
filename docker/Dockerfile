# Odoo 20 built with odoo_install.sh, the same script you would run on a server.
FROM ubuntu:24.04

ARG OE_VERSION=20.0
ARG IS_ENTERPRISE=False
ARG INSTALL_WKHTMLTOPDF=True
ARG INSTALL_PAPER_MUNCHER=False
ARG DB_HOST=db
ARG DB_PORT=5432
ARG DB_USER=odoo
ARG DB_PASSWORD=odoo

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    TZ=Etc/UTC

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      sudo ca-certificates curl wget gnupg lsb-release locales apt-utils tzdata git; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone; \
    rm -rf /var/lib/apt/lists/*

COPY odoo_install.sh /opt/odoo-install/odoo_install.sh

# Point the script at the database service and let it do the whole install.
# DB_WAIT is False because the db container is not reachable while the image builds;
# the entrypoint waits for it at run time instead.
RUN set -eux; \
    cd /opt/odoo-install; \
    sed -i \
      -e "s/^OE_VERSION=.*/OE_VERSION=\"${OE_VERSION}\"/" \
      -e "s/^IS_ENTERPRISE=.*/IS_ENTERPRISE=\"${IS_ENTERPRISE}\"/" \
      -e "s/^INSTALL_WKHTMLTOPDF=.*/INSTALL_WKHTMLTOPDF=\"${INSTALL_WKHTMLTOPDF}\"/" \
      -e "s/^INSTALL_PAPER_MUNCHER=.*/INSTALL_PAPER_MUNCHER=\"${INSTALL_PAPER_MUNCHER}\"/" \
      -e "s/^DB_HOST=.*/DB_HOST=\"${DB_HOST}\"/" \
      -e "s/^DB_WAIT=.*/DB_WAIT=\"False\"/" \
      -e "s/^DB_PORT=.*/DB_PORT=\"${DB_PORT}\"/" \
      -e "s/^DB_USER=.*/DB_USER=\"${DB_USER}\"/" \
      -e "s/^DB_PASSWORD=.*/DB_PASSWORD=\"${DB_PASSWORD}\"/" \
      -e "s/^GENERATE_RANDOM_PASSWORD=.*/GENERATE_RANDOM_PASSWORD=\"False\"/" \
      -e "s/^USE_SYSTEMD=.*/USE_SYSTEMD=\"False\"/" \
      odoo_install.sh; \
    chmod +x odoo_install.sh; \
    ./odoo_install.sh; \
    rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8069 8072
VOLUME ["/odoo/custom/addons", "/var/lib/odoo"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
