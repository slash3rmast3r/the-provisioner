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

# --- Attendi rete e aggiorna indice pacchetti ---
for attempt in $(seq 1 30); do
  apt-get update -qq && break
  echo "In attesa di rete... tentativo ${attempt}/30"
  sleep 10
done

apt-get install -y git ca-certificates

# --- Scarica debian-provision (scegli una sorgente) ---
PROVISION_DIR="/opt/debian-provision"
PROVISION_REPO="${PROVISION_REPO:-https://github.com/TUO-ORG/debian-provision.git}"

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

# --- Configurazione non interattiva ---
cat > /root/provision-config.env <<'ENV'
SMTP_ENABLED=yes
SMTP_HOST=mail.example.com
SMTP_PORT=587
SMTP_TLS=starttls
SMTP_USER=admin@example.com
SMTP_PASSWORD=CAMBIA_PASSWORD
SMTP_FROM=admin@example.com

MONIT_ADMIN_EMAIL=admin@example.com
MONIT_CHECK_INTERVAL=60
MONIT_SERVICES=ssh,docker,filesystem

LOGWATCH_EMAIL=admin@example.com
LOGWATCH_DETAIL=Med
LOGWATCH_RANGE=Yesterday
LOGWATCH_SERVICES=All
LOGWATCH_FORMAT=text
LOGWATCH_CRON_HOUR=6

UFW_SSH_PORT=54321
UFW_ALLOW_HTTP=yes
UFW_ALLOW_HTTPS=yes
UFW_EXTRA_PORTS=
UFW_EXTRA_UDP_PORTS=

DOCKER_INSTALL_COMPOSE=yes
DOCKER_USERS=admin
ENV
chmod 600 /root/provision-config.env

# --- Esegui provisioning completo ---
CONFIG_FILE=/root/provision-config.env \
  "${PROVISION_DIR}/install.sh" --all --non-interactive -y

echo "debian-provision completato con successo"
