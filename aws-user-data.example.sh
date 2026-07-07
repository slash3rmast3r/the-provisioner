#!/bin/bash
# =============================================================================
# AWS EC2 / Lightsail — Script di avvio (user-data)
#
# REPO PRIVATA: imposta GIT_TOKEN qui sotto (vedi istruzioni in README o sotto).
# NON committare questo file con token/password reali nel repository git.
#
# 1. Crea un GitHub PAT (read-only, solo su questo repo)
# 2. Incolla il token in GIT_TOKEN nello script che mandi a Lightsail
# 3. Apri la porta SSH 54321 nel firewall Lightsail
# 4. Incolla questo script nel campo "Script di avvio" di Lightsail
# =============================================================================

exec > >(tee /var/log/debian-provision-boot.log) 2>&1
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- CREDENZIALI BOOT (compila solo nello script incollato in Lightsail) ---
GIT_TOKEN=""                    # GitHub PAT read-only (repo privata)
# GIT_TOKEN="ghp_xxxxxxxxxxxx"  # oppure decommenta e incolla qui

PROVISION_DIR="/opt/debian-provision"
PROVISION_REPO="https://github.com/slash3rmast3r/the-provisioner.git"

# --- Attendi rete ---
for attempt in $(seq 1 30); do
  apt-get update -qq && break
  echo "In attesa di rete... tentativo ${attempt}/30"
  sleep 10
done

apt-get install -y git ca-certificates

# --- Clone repository (pubblica o privata con PAT) ---
clone_provisioner_repo() {
  local dest="$1"
  local repo_url="$PROVISION_REPO"

  if [[ -n "${GIT_TOKEN}" ]]; then
    # GitHub: https://x-access-token:TOKEN@github.com/owner/repo.git
    repo_url="https://x-access-token:${GIT_TOKEN}@github.com/slash3rmast3r/the-provisioner.git"
    info_msg "Clone repo privata con PAT"
  fi

  git clone --depth 1 "${repo_url}" "${dest}"
}

info_msg() { echo "[$(date '+%F %T')] $*"; }

if [[ ! -f "${PROVISION_DIR}/install.sh" ]]; then
  clone_provisioner_repo "${PROVISION_DIR}"
fi

# --- Opzione alternativa: tarball da S3 (nessun git sul server) ---
# apt-get install -y curl
# PRESIGNED_URL="https://s3.amazonaws.com/bucket/the-provisioner.tar.gz?X-Amz-..."
# curl -fsSL "${PRESIGNED_URL}" -o /tmp/the-provisioner.tar.gz
# mkdir -p /opt && tar xzf /tmp/the-provisioner.tar.gz -C /opt

find "${PROVISION_DIR}" -name '*.sh' -exec sed -i 's/\r$//' {} +
chmod +x "${PROVISION_DIR}/install.sh"

# --- Bootstrap sistema ---
# shellcheck source=lib/common.sh
source "${PROVISION_DIR}/lib/common.sh"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
apt_bootstrap_system

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

CONFIG_FILE=/root/provision-config.env \
  "${PROVISION_DIR}/install.sh" --all --non-interactive -y

echo "The Provisioner completato con successo"
