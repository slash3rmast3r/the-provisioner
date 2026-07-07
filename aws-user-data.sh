#!/bin/bash
# =============================================================================
# AWS EC2 / Lightsail — Script di avvio (user-data)
#
# ISTRUZIONI:
# 1. Carica la cartella debian-provision su un repo git o bucket S3
# 2. Modifica PROVISION_REPO e le credenziali SMTP qui sotto
# 3. Apri la porta SSH 54321 nel firewall Lightsail / Security Group EC2
# 4. Incolla questo script nel campo "User data" (EC2) o "Script di avvio" (Lightsail)
# =============================================================================

exec > >(tee /var/log/debian-provision-boot.log) 2>&1
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Attendi rete (bootstrap completo dopo il clone) ---
for attempt in $(seq 1 30); do
  apt-get update -qq && break
  echo "In attesa di rete... tentativo ${attempt}/30"
  sleep 10
done

# Minimo necessario per clonare il repository
apt-get install -y git ca-certificates

# --- Scarica debian-provision (scegli una sorgente) ---
PROVISION_DIR="/opt/debian-provision"
PROVISION_REPO="${PROVISION_REPO:-https://github.com/slash3rmast3r/the-provisioner.git}"

# Opzione A: git clone
if [[ ! -f "${PROVISION_DIR}/install.sh" ]]; then
  git clone --depth 1 "${PROVISION_REPO}" "${PROVISION_DIR}"
fi

# Opzione B: tarball da S3 (decommenta se preferisci)
# apt-get install -y awscli
# aws s3 cp s3://tuo-bucket/debian-provision.tar.gz /tmp/debian-provision.tar.gz
# tar xzf /tmp/debian-provision.tar.gz -C /opt

find "${PROVISION_DIR}" -name '*.sh' -exec sed -i 's/\r$//' {} +
chmod +x "${PROVISION_DIR}/install.sh"

# --- Bootstrap sistema: update, upgrade, dist-upgrade, clean, pacchetti base ---
# shellcheck source=lib/common.sh
source "${PROVISION_DIR}/lib/common.sh"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
apt_bootstrap_system

# --- Configurazione non interattiva ---
cat > /root/provision-config.env <<'ENV'
SMTP_ENABLED=yes
SMTP_HOST=mail.overthecloud.it
SMTP_PORT=587
SMTP_TLS=starttls
SMTP_USER=info@overthecloud.it
SMTP_PASSWORD=sUiCiD3_66666678
SMTP_FROM=noreply@overthecloud.it

MONIT_ADMIN_EMAIL=info@overthecloud.it
MONIT_CHECK_INTERVAL=10
MONIT_SERVICES=ssh,docker,filesystem,smtp

LOGWATCH_EMAIL=info@overthecloud.it
LOGWATCH_DETAIL=Med
LOGWATCH_RANGE=Yesterday
LOGWATCH_SERVICES=All
LOGWATCH_FORMAT=text
LOGWATCH_CRON_HOUR=12

UFW_SSH_PORT=54321
UFW_ALLOW_HTTP=yes
UFW_ALLOW_HTTPS=yes
UFW_EXTRA_PORTS=80,443,25,110,143,465,587,993,995,53,20,21
UFW_EXTRA_UDP_PORTS=53,67

DOCKER_INSTALL_COMPOSE=yes
DOCKER_USERS=admin
ENV
chmod 600 /root/provision-config.env

# --- Esegui provisioning completo ---
CONFIG_FILE=/root/provision-config.env \
  "${PROVISION_DIR}/install.sh" --all --non-interactive -y

echo "The Provisioner completato con successo!"
