#!/usr/bin/env bash
# Modulo: aggiornamento sistema e pacchetti base

module_base() {
  info "Aggiornamento indice pacchetti..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  info "Aggiornamento distribuzione e patch di sicurezza..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade

  # dist-upgrade per eventuali cambi di dipendenze (nuova release minor)
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    dist-upgrade

  apt-get -y autoremove --purge
  apt-get -y autoclean

  info "Installazione pacchetti base..."
  apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    gcc \
    wget \
    vim \
    htop \
    unzip \
    jq \
    git \
    rsync \
    cron \
    sudo \
    fail2ban \
    unattended-upgrades \
    apt-listchanges

  # Aggiornamenti automatici di sicurezza
  if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    dpkg-reconfigure -plow unattended-upgrades || true
  fi

  cat > /etc/apt/apt.conf.d/50unattended-upgrades-local <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

  systemctl enable unattended-upgrades 2>/dev/null || true
  systemctl restart unattended-upgrades 2>/dev/null || true

  success "Sistema aggiornato e pacchetti base installati."
}

module_base
