#!/bin/bash
################################################################################
# Script for installing Odoo 20 on Ubuntu 24.04 LTS (and newer)
# For Debian, use odoo_install_debian.sh instead
# Author: Yenthe Van Ginneken
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different http_ports
#-------------------------------------------------------------------------------
# Odoo 20 raised its minimum requirements:
#   * Python  >= 3.12 (was 3.10 in Odoo 19) -> Ubuntu 24.04 or newer is required
#   * PostgreSQL >= 16 (was 13 in Odoo 19)
# The script refuses to run when those are not met instead of producing a broken
# installation.
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# Set to true if you want to install it, false if you don't need it or have it already installed.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# The interface Odoo listens on. Odoo 20 changed the default from 0.0.0.0 to 127.0.0.1,
# so an Odoo 20 install is only reachable from the machine itself unless this is set.
# Leave empty to let the script decide: 127.0.0.1 when Nginx is installed in front of
# Odoo (the proxy connects locally, which is the safer setup), 0.0.0.0 otherwise so the
# server stays reachable like it was on Odoo 19 and below.
HTTP_INTERFACE=""
# Choose the Odoo version which you want to install. For example: 20.0, 19.0 or saas-20.1.
# When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 20.0
OE_VERSION="20.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Install PostgreSQL from the official postgresql.org repository (PGDG) instead of the
# distribution package. This gives you a recent PostgreSQL and the matching pgvector build.
INSTALL_POSTGRESQL_PGDG="True"
# PostgreSQL major version to install when INSTALL_POSTGRESQL_PGDG is "True".
# Odoo 20 requires PostgreSQL 16 or above.
POSTGRESQL_VERSION="17"
# How the Python dependencies are installed:
#   "apt" -> distribution packages parsed from Odoo's own debian/control (recommended by Odoo)
#   "pip" -> pip install -r requirements.txt (needs --break-system-packages on Ubuntu 24.04)
DEPENDENCIES_MODE="apt"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="False"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
# Set the website name
WEBSITE_NAME="_"
# Set the Odoo gevent port. This is the port used by the websocket (live chat, bus, ...).
# It replaces the 'longpolling_port' option which was removed in Odoo 20.
GEVENT_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
# Odoo 20 ships an alternative in-house PDF engine called Paper Muncher. wkhtmltopdf stays
# the default engine, Paper Muncher is opt-in. Set to "True" to install the binary.
# Note: Paper Muncher is currently only released for amd64.
INSTALL_PAPER_MUNCHER="False"
PAPER_MUNCHER_VERSION="0.8.0"
# Use a systemd unit instead of the legacy /etc/init.d script.
USE_SYSTEMD="True"

# Minimum versions required by Odoo 20 (see odoo/release.py in the odoo/odoo repository).
MIN_PYTHON_MAJOR="3"
MIN_PYTHON_MINOR="12"
MIN_PG_VERSION="16"

# Helper: is systemd the init system that is actually running?
# The systemctl binary can be present without systemd being PID 1 (containers, chroots,
# WSL1), in which case every systemctl call fails. /run/systemd/system only exists when
# systemd is really running, which is the check systemd itself documents.
systemd_is_running() {
  [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

# Helper: pip install with optional --break-system-packages (Ubuntu 24.04 / PEP 668)
pip_install() {
  if pip3 help install 2>/dev/null | grep -q -- '--break-system-packages'; then
    sudo -H pip3 install --break-system-packages "$@"
  else
    sudo -H pip3 install "$@"
  fi
}

#--------------------------------------------------
# Detect the OS and the architecture
#--------------------------------------------------
detect_arch() {
  local arch_raw
  arch_raw="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  case "$arch_raw" in
    amd64|x86_64)   ARCH_DEB="amd64";;
    i386|i686)      ARCH_DEB="i386";;
    arm64|aarch64)  ARCH_DEB="arm64";;
    armhf|armv7l)   ARCH_DEB="armhf";;
    *)              ARCH_DEB="$arch_raw";;
  esac

  DISTRO_ID="$(. /etc/os-release 2>/dev/null && echo "$ID")"
  DISTRO_CODENAME="$(lsb_release -c -s 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME"))"
  DISTRO_RELEASE="$(lsb_release -r -s 2>/dev/null || (. /etc/os-release 2>/dev/null && echo "$VERSION_ID"))"
  DISTRO_ID="${DISTRO_ID:-ubuntu}"
  DISTRO_CODENAME="${DISTRO_CODENAME:-noble}"
  DISTRO_RELEASE="${DISTRO_RELEASE:-24.04}"
}

#--------------------------------------------------
# Preflight checks: Odoo 20 needs Python 3.12+
#--------------------------------------------------
check_python_version() {
  echo -e "\n---- Checking the Python version ----"
  if ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y python3
  fi

  if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (${MIN_PYTHON_MAJOR}, ${MIN_PYTHON_MINOR}) else 1)"; then
    echo "------------------------ERROR------------------------------"
    echo "Odoo ${OE_VERSION} requires Python ${MIN_PYTHON_MAJOR}.${MIN_PYTHON_MINOR} or above but this system has:"
    python3 --version
    printf "Ubuntu 22.04 ships Python 3.10 and can no longer run Odoo 20.\nUse Ubuntu 24.04 LTS or newer.\n"
    echo "-----------------------------------------------------------"
    exit 1
  fi
  echo "Python version OK: $(python3 --version)"
}

detect_arch

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n---- Update Server ----"
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl wget gnupg lsb-release git libpq-dev python3-pip

check_python_version

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Install PostgreSQL Server ----"
if [ "$INSTALL_POSTGRESQL_PGDG" = "True" ]; then
    if [ "$POSTGRESQL_VERSION" -lt "$MIN_PG_VERSION" ]; then
        echo "------------------------ERROR------------------------------"
        echo "Odoo ${OE_VERSION} requires PostgreSQL ${MIN_PG_VERSION} or above,"
        echo "but POSTGRESQL_VERSION is set to ${POSTGRESQL_VERSION}."
        echo "-----------------------------------------------------------"
        exit 1
    fi
    echo -e "\n---- Installing PostgreSQL V${POSTGRESQL_VERSION} from the PGDG repository ----"
    sudo install -d -m 0755 /usr/share/keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/postgresql.gpg
    sudo sh -c "echo 'deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt ${DISTRO_CODENAME}-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
    sudo apt-get update -y
    sudo apt-get install -y postgresql-${POSTGRESQL_VERSION} postgresql-client-${POSTGRESQL_VERSION}
else
    echo -e "\n---- Installing the default postgreSQL version based on the Linux version ----"
    sudo apt-get install -y postgresql postgresql-client
fi

# Make sure PostgreSQL is up before we talk to it (Ubuntu 24.04 uses systemd).
sudo systemctl start postgresql >/dev/null 2>&1 \
  || sudo service postgresql start >/dev/null 2>&1 \
  || sudo /etc/init.d/postgresql start >/dev/null 2>&1 \
  || true
PG_WAIT=0
until sudo -u postgres pg_isready >/dev/null 2>&1; do
    PG_WAIT=$((PG_WAIT + 1))
    if [ "$PG_WAIT" -gt 60 ]; then
        echo "------------------------ERROR------------------------------"
        echo "PostgreSQL did not become available after 60 seconds."
        echo "-----------------------------------------------------------"
        exit 1
    fi
    sleep 1
done

# Odoo 20 refuses to run on PostgreSQL older than 16.
PG_SERVER_MAJOR="$POSTGRESQL_VERSION"
PG_SERVER_VERSION=$(sudo -u postgres psql -tAc "SHOW server_version_num;" 2>/dev/null)
if [ -n "$PG_SERVER_VERSION" ]; then
    PG_SERVER_MAJOR=$((PG_SERVER_VERSION / 10000))
    echo -e "\n---- Detected PostgreSQL major version: ${PG_SERVER_MAJOR} ----"
    if [ "$PG_SERVER_MAJOR" -lt "$MIN_PG_VERSION" ]; then
        echo "------------------------ERROR------------------------------"
        echo "Odoo ${OE_VERSION} requires PostgreSQL ${MIN_PG_VERSION} or above but version ${PG_SERVER_MAJOR} is running."
        echo "Set INSTALL_POSTGRESQL_PGDG to \"True\" to install a supported version."
        echo "-----------------------------------------------------------"
        exit 1
    fi
fi

if [ "$IS_ENTERPRISE" = "True" ]; then
    # pgvector is needed by the Odoo Enterprise AI modules (RAG for AI agents).
    echo -e "\n---- Installing pgvector for the Enterprise AI features ----"
    if sudo apt-get install -y "postgresql-${PG_SERVER_MAJOR}-pgvector"; then
        # The Odoo role is intentionally not a superuser, so it cannot run CREATE EXTENSION
        # itself. Creating the extension in template1 makes every new database inherit it.
        sudo -u postgres psql -v ON_ERROR_STOP=1 -d template1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
SQL
    else
        echo "WARNING: could not install postgresql-${PG_SERVER_MAJOR}-pgvector."
        echo "The Odoo Enterprise AI modules will not be able to use RAG until it is installed."
    fi
fi

echo -e "\n---- Creating the ODOO PostgreSQL User  ----"
# Create the role with CREATEDB (Odoo needs it to create/drop databases) but WITHOUT
# SUPERUSER. A superuser role can run 'COPY ... FROM PROGRAM', which lets anyone who
# reaches an Odoo admin turn SQL access into shell command execution as the postgres
# OS user. Keeping the role non-superuser closes that privilege-escalation path and
# matches Odoo's deployment guidance. See:
# https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html
sudo su - postgres -c "createuser -d -R -S $OE_USER" 2> /dev/null || true

#--------------------------------------------------
# Create the Odoo system user
#--------------------------------------------------
echo -e "\n---- Create ODOO system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
#The user should also be added to the sudo'ers group.
sudo adduser $OE_USER sudo

echo -e "\n---- Create Log directory ----"
sudo mkdir -p /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/

#--------------------------------------------------
# Install the Python dependencies
#--------------------------------------------------
# Returns the first package of an 'a|b|c' alternative that actually exists in the
# configured apt sources. Odoo's debian/control uses alternatives (for example
# 'python3-lxml-html-clean | python3-lxml') which apt-get install does not understand.
apt_pick_alternative() {
  local spec="$1" candidate
  local IFS='|'
  for candidate in $spec; do
    if apt-cache show "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

install_dependencies_with_apt() {
  local control="$OE_HOME_EXT/debian/control"
  local packages=() spec picked

  if [ ! -f "$control" ]; then
    echo "Could not find $control, falling back to pip."
    return 1
  fi

  echo -e "\n---- Installing the Odoo dependencies from the distribution packages ----"
  # Same parsing as Odoo's own setup/debinstall.sh, with alternatives resolved.
  while read -r spec; do
    [ -z "$spec" ] && continue
    # debian/control asks for the unversioned postgresql-client. With the PGDG
    # repository enabled that resolves to the newest client available, which pulls in a
    # second major version next to the server we just installed. Pin it to the server.
    if [ "$spec" = "postgresql-client" ]; then
      packages+=("postgresql-client-${PG_SERVER_MAJOR}")
      continue
    fi
    if picked=$(apt_pick_alternative "$spec"); then
      packages+=("$picked")
    else
      echo "WARNING: no package found for '${spec}', skipping."
    fi
  done < <(sed -n '/^Depends:/,/^[A-Z]/p' "$control" \
           | awk '/^ [a-z]/ { gsub(/,/,"") ; gsub(" ", "") ; print $NF }' | sort -u)

  # debian/control only lists python3-ldap as a "Recommends", and a few addons declare
  # their own external dependencies that are not part of the server requirements.
  packages+=(python3-ldap python3-phonenumbers python3-google-auth)

  if [ ${#packages[@]} -eq 0 ]; then
    echo "Could not parse any package out of $control, falling back to pip."
    return 1
  fi

  sudo apt-get install -y --no-install-recommends "${packages[@]}"
}

install_dependencies_with_pip() {
  echo -e "\n---- Installing the Odoo dependencies with pip ----"
  sudo apt-get install -y python3-pip python3-dev python3-wheel python3-setuptools \
      build-essential libxslt1-dev libzip-dev libldap2-dev libsasl2-dev libxmlsec1-dev \
      pkg-config libpng-dev libjpeg-dev
  pip_install -r "$OE_HOME_EXT/requirements.txt"
  # Extra libraries used by some addons but not listed in requirements.txt.
  pip_install phonenumbers google-auth python-ldap
}

if [ "$DEPENDENCIES_MODE" = "apt" ]; then
  install_dependencies_with_apt || install_dependencies_with_pip
else
  install_dependencies_with_pip
fi

echo -e "\n---- Installing nodeJS NPM and rtlcss for RTL support ----"
sudo apt-get install -y nodejs npm
sudo npm install -g rtlcss

#--------------------------------------------------
# Install Wkhtmltopdf if needed
#--------------------------------------------------
# Odoo 20 keeps wkhtmltopdf as the default PDF engine (the base_report_wkhtmltox module
# is auto-installed). Headers and footers only render correctly with the 0.12.6 build
# that is patched against Qt, which is NOT the build shipped by Ubuntu/Debian.
# See https://github.com/odoo/odoo/wiki/Wkhtmltopdf
WKHTMLTOPDF_VERSION="0.12.6.1-3"

wkhtmltopdf_packaging_codename() {
  # The wkhtmltopdf project only publishes builds for a handful of releases; map the
  # running distribution onto the closest one that is available.
  case "$DISTRO_CODENAME" in
    jammy|noble|oracular|plucky|questing|resolute) echo "jammy";;
    bullseye)                                      echo "bullseye";;
    bookworm|trixie|forky)                         echo "bookworm";;
    *)                                             echo "";;
  esac
}

install_wkhtmltopdf_patched() {
  local codename deb url tmp
  codename="$(wkhtmltopdf_packaging_codename)"
  [ -z "$codename" ] && return 1

  # jammy has no i386/armhf build, bookworm has no armhf build.
  case "$codename:$ARCH_DEB" in
    jammy:amd64|jammy:arm64|bookworm:amd64|bookworm:arm64|bookworm:i386|bullseye:amd64|bullseye:arm64|bullseye:i386) ;;
    *) return 1;;
  esac

  deb="wkhtmltox_${WKHTMLTOPDF_VERSION}.${codename}_${ARCH_DEB}.deb"
  url="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/${deb}"
  tmp="$(mktemp -d)"

  echo -e "\n---- Downloading wkhtmltopdf ${WKHTMLTOPDF_VERSION} (${codename}/${ARCH_DEB}) ----"
  if ! wget -q -O "${tmp}/${deb}" "$url"; then
    rm -rf "$tmp"
    return 1
  fi
  # apt-get install on a local file resolves the dependencies for us.
  if ! sudo apt-get install -y "${tmp}/${deb}"; then
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  return 0
}

install_wkhtmltopdf_from_distribution() {
  sudo apt-get update -y
  if sudo apt-get install -y wkhtmltopdf; then
    echo "wkhtmltopdf installed from the distribution repositories ($ARCH_DEB)."
    return 0
  fi
  return 1
}

wkhtml_create_symlinks_if_needed() {
  if [ -x /usr/local/bin/wkhtmltopdf ] && ! command -v wkhtmltopdf >/dev/null 2>&1; then
    sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin || true
  fi
  if [ -x /usr/local/bin/wkhtmltoimage ] && ! command -v wkhtmltoimage >/dev/null 2>&1; then
    sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin || true
  fi
}

if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
  echo -e "\n---- Installing wkhtmltopdf (architecture detected: $ARCH_DEB) ----"

  if install_wkhtmltopdf_patched; then
    echo -e "\n---- Installed the patched Qt build of wkhtmltopdf, headers and footers will work ----"
  elif install_wkhtmltopdf_from_distribution; then
    echo -e "\n---- WARNING: installed the distribution build of wkhtmltopdf ----"
    echo -e "---- It is NOT patched against Qt, report headers and footers may be missing ----"
  else
    echo -e "\n---- Could not install wkhtmltopdf ----"
  fi

  echo -e "\n---- Ensure that the links are in /usr/local/bin ----"
  wkhtml_create_symlinks_if_needed

  if command -v wkhtmltopdf >/dev/null 2>&1; then
    echo -e "\n---- wkhtmltopdf available at: $(command -v wkhtmltopdf) ($(wkhtmltopdf --version 2>/dev/null | head -n 1)) ----"
  else
    echo -e "\n----- WARNING: wkhtmltopdf was not installed. You can install it manually later ----"
  fi
else
  echo -e "\n---- Wkhtmltopdf will not be installed at the user's choice ----"
fi

#--------------------------------------------------
# Install Paper Muncher (optional Odoo 20 PDF engine)
#--------------------------------------------------
paper_muncher_codename() {
  case "$DISTRO_CODENAME" in
    jammy|noble|plucky|resolute|bookworm|trixie) echo "$DISTRO_CODENAME";;
    oracular|questing)                           echo "noble";;
    forky)                                       echo "trixie";;
    *)                                           echo "";;
  esac
}

if [ "$INSTALL_PAPER_MUNCHER" = "True" ]; then
  echo -e "\n---- Installing Paper Muncher ${PAPER_MUNCHER_VERSION} ----"
  if [ "$ARCH_DEB" != "amd64" ]; then
    echo "WARNING: Paper Muncher is only released for amd64, skipping on ${ARCH_DEB}."
  else
    PM_CODENAME="$(paper_muncher_codename)"
    PM_TMP="$(mktemp -d)"
    PM_OK="False"
    if [ -n "$PM_CODENAME" ]; then
      PM_DEB="paper-muncher_v${PAPER_MUNCHER_VERSION}_${PM_CODENAME}_amd64.deb"
      PM_URL="https://github.com/odoo/paper-muncher/releases/download/v${PAPER_MUNCHER_VERSION}/${PM_DEB}"
      if wget -q -O "${PM_TMP}/${PM_DEB}" "$PM_URL" && sudo apt-get install -y "${PM_TMP}/${PM_DEB}"; then
        PM_OK="True"
      fi
    fi
    if [ "$PM_OK" = "False" ]; then
      # Fall back on the generic tarball, which Odoo looks up at /opt/paper-muncher/bin.
      PM_TAR="paper-muncher_v${PAPER_MUNCHER_VERSION}_generic_epoll_amd64.tar.gz"
      PM_URL="https://github.com/odoo/paper-muncher/releases/download/v${PAPER_MUNCHER_VERSION}/${PM_TAR}"
      if wget -q -O "${PM_TMP}/${PM_TAR}" "$PM_URL"; then
        sudo mkdir -p /opt/paper-muncher
        sudo tar -xzf "${PM_TMP}/${PM_TAR}" -C /opt/paper-muncher --strip-components=1
        PM_OK="True"
      fi
    fi
    rm -rf "$PM_TMP"

    if command -v paper-muncher >/dev/null 2>&1; then
      echo "Paper Muncher available at: $(command -v paper-muncher)"
    elif [ -x /opt/paper-muncher/bin/paper-muncher ]; then
      echo "Paper Muncher available at: /opt/paper-muncher/bin/paper-muncher"
    else
      echo "WARNING: Paper Muncher could not be installed."
    fi
  fi
fi

#--------------------------------------------------
# Install the Enterprise addons
#--------------------------------------------------
if [ $IS_ENTERPRISE = "True" ]; then
    # Odoo Enterprise install!
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an offical Odoo partner and you need access to\nhttp://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done

    echo -e "\n---- Added Enterprise code under $OE_HOME/enterprise/addons ----"
    echo -e "\n---- Installing Enterprise specific libraries ----"
    # Odoo 20 Enterprise declares these external Python dependencies in its manifests.
    if [ "$DEPENDENCIES_MODE" = "apt" ]; then
        sudo apt-get install -y --no-install-recommends \
            python3-paramiko python3-jwt python3-xmlsec python3-phonenumbers \
            || pip_install paramiko pyjwt xmlsec phonenumbers
    else
        pip_install paramiko pyjwt xmlsec phonenumbers
    fi
fi

echo -e "\n---- Create custom module directory ----"
sudo su $OE_USER -c "mkdir -p $OE_HOME/custom/addons"

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

#--------------------------------------------------
# Create the server configuration file
#--------------------------------------------------
echo -e "* Creating server config file"
sudo touch /etc/${OE_CONFIG}.conf
sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi
sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"
# Security: once your database(s) exist, set list_db = False to disable the
# unauthenticated database selector/manager (/web/database/*), which otherwise
# lets anyone enumerate database names. Left commented so the web database
# manager still works for creating the first database right after install.
sudo su root -c "printf '; list_db = False\n' >> /etc/${OE_CONFIG}.conf"
if [ -z "$HTTP_INTERFACE" ]; then
    if [ "$INSTALL_NGINX" = "True" ]; then
        HTTP_INTERFACE="127.0.0.1"
    else
        HTTP_INTERFACE="0.0.0.0"
    fi
fi
# Odoo 20 defaults http_interface to 127.0.0.1 (it was 0.0.0.0 up to Odoo 19), so it has
# to be written explicitly or the server is only reachable from localhost.
sudo su root -c "printf 'http_interface = ${HTTP_INTERFACE}\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
# 'longpolling_port' was removed in Odoo 20, the websocket worker uses 'gevent_port'.
sudo su root -c "printf 'gevent_port = ${GEVENT_PORT}\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"

if [ $IS_ENTERPRISE = "True" ]; then
    # The enterprise addons have to come first so that they override the community ones.
    sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "* Create startup file"
sudo su root -c "echo '#!/bin/sh' >> $OE_HOME_EXT/start.sh"
sudo su root -c "echo 'sudo -u $OE_USER $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf' >> $OE_HOME_EXT/start.sh"
sudo chmod 755 $OE_HOME_EXT/start.sh

#--------------------------------------------------
# Adding ODOO as a service
#--------------------------------------------------
if [ "$USE_SYSTEMD" = "True" ] && systemd_is_running; then
  echo -e "* Create systemd unit file"
  cat <<EOF > ~/$OE_CONFIG.service
[Unit]
Description=Odoo $OE_VERSION ($OE_CONFIG)
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$OE_CONFIG
PermissionsStartOnly=true
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
KillMode=mixed
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  sudo mv ~/$OE_CONFIG.service /etc/systemd/system/$OE_CONFIG.service
  sudo chmod 644 /etc/systemd/system/$OE_CONFIG.service
  sudo chown root: /etc/systemd/system/$OE_CONFIG.service
  sudo systemctl daemon-reload
  sudo systemctl enable $OE_CONFIG
else
  echo -e "* Create init file"
  cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/\${NAME}.pid
# Additional options that are passed to the Daemon.
DAEMON_OPTS="-c \$CONFIGFILE"
[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
[ -f \$PIDFILE ] || return 1
pid=\`cat \$PIDFILE\`
[ -d /proc/\$pid ] && return 0
return 1
}
case "\${1}" in
start)
echo -n "Starting \${DESC}: "
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
stop)
echo -n "Stopping \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
echo "\${NAME}."
;;
restart|force-reload)
echo -n "Restarting \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
sleep 1
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
*)
N=/etc/init.d/\$NAME
echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
exit 1
;;
esac
exit 0
EOF

  echo -e "* Security Init File"
  sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
  sudo chmod 755 /etc/init.d/$OE_CONFIG
  sudo chown root: /etc/init.d/$OE_CONFIG

  echo -e "* Start ODOO on Startup"
  sudo update-rc.d $OE_CONFIG defaults
fi

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  echo -e "\n---- Installing and setting up Nginx ----"
  sudo apt-get install -y nginx
  cat <<EOF > ~/odoo
upstream ${OE_CONFIG} {
  server 127.0.0.1:$OE_PORT;
}

upstream ${OE_CONFIG}chat {
  server 127.0.0.1:$GEVENT_PORT;
}

map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;

  # set proper server name after domain set
  server_name $WEBSITE_NAME;

  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";

  #   odoo    log files
  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log       /var/log/nginx/$OE_USER-error.log;

  #   increase    proxy   buffer  size
  proxy_buffers   16  64k;
  proxy_buffer_size   128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  #   force   timeouts    if  the backend dies
  proxy_next_upstream error   timeout invalid_header  http_500    http_502
  http_503;

  types {
    text/less less;
    text/scss scss;
  }

  #   enable  data    compression
  gzip    on;
  gzip_min_length 1100;
  gzip_buffers    4   32k;
  gzip_types  text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary   on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  # Odoo 20 serves the bus over a websocket on the gevent port. This location has to
  # come before the catch-all one and needs the Upgrade/Connection headers.
  location /websocket {
    proxy_pass http://${OE_CONFIG}chat;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  location / {
    proxy_pass    http://${OE_CONFIG};
    # by default, do not forward anything
    proxy_redirect off;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
  }

  # cache some static data in memory for 60mins.
  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404      1m;
    proxy_buffering    on;
    expires 864000;
    proxy_pass    http://${OE_CONFIG};
  }
}
EOF

  sudo mv ~/odoo /etc/nginx/sites-available/$WEBSITE_NAME
  sudo ln -sf /etc/nginx/sites-available/$WEBSITE_NAME /etc/nginx/sites-enabled/$WEBSITE_NAME
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo service nginx reload
  sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
  echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/$WEBSITE_NAME"
else
  echo "Nginx isn't installed due to choice of the user!"
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ]  && [ $WEBSITE_NAME != "_" ];then
  sudo apt-get update -y
  sudo apt-get install -y snapd
  sudo snap install core; snap refresh core
  sudo snap install --classic certbot
  sudo ln -sf /snap/bin/certbot /usr/bin/certbot
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
  if [ "$ADMIN_EMAIL" = "odoo@example.com" ]; then
      echo "Certbot does not support registering odoo@example.com. You should use real e-mail address."
  fi

  if [ "$WEBSITE_NAME" = "_" ]; then
      echo "Website name is set as _. Cannot obtain SSL Certificate for _. You should use real website address."
  fi
fi

echo -e "* Starting Odoo Service"
if [ "$USE_SYSTEMD" = "True" ] && systemd_is_running; then
  sudo systemctl start $OE_CONFIG
else
  sudo su root -c "/etc/init.d/$OE_CONFIG start"
fi
echo "-----------------------------------------------------------"
echo "Done! The Odoo server is up and running. Specifications:"
echo "Odoo version: $OE_VERSION"
echo "Listening on: ${HTTP_INTERFACE}:${OE_PORT}"
echo "Gevent (websocket) port: $GEVENT_PORT"
echo "User service: $OE_USER"
echo "Configuraton file location: /etc/${OE_CONFIG}.conf"
echo "Logfile location: /var/log/$OE_USER"
echo "User PostgreSQL: $OE_USER"
echo "Code location: $OE_HOME_EXT"
echo "Addons folder: $OE_HOME/custom/addons"
echo "Password superadmin (database): $OE_SUPERADMIN"
echo "Start Odoo service: sudo service $OE_CONFIG start"
echo "Stop Odoo service: sudo service $OE_CONFIG stop"
echo "Restart Odoo service: sudo service $OE_CONFIG restart"
if [ $INSTALL_NGINX = "True" ]; then
  echo "Nginx configuration file: /etc/nginx/sites-available/$WEBSITE_NAME"
fi
if [ "$INSTALL_PAPER_MUNCHER" = "True" ]; then
  echo "Paper Muncher is installed. To use it instead of wkhtmltopdf, install the"
  echo "'base_report_paper_muncher' module and set the 'report.pdf_engine_default'"
  echo "system parameter to 'paper-muncher'."
fi
echo "-----------------------------------------------------------"
