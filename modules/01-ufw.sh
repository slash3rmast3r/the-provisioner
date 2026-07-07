#!/usr/bin/env bash
# Modulo: UFW firewall + configurazione porta SSH + fail2ban

# Applica regola UFW per una singola voce porta.
# Formati accettati: 8080 | 8080/tcp | 8080/udp | 8080/both
ufw_apply_port_entry() {
  local entry="$1"
  local default_proto="${2:-tcp}"
  local comment="${3:-Custom}"

  entry="$(echo "$entry" | xargs)"
  [[ -z "$entry" ]] && return 0

  if [[ "${entry,,}" == "yes" || "${entry,,}" == "no" ]]; then
    return 0
  fi

  local port proto
  if [[ "$entry" =~ ^([0-9]+)/(tcp|udp|both)$ ]]; then
    port="${BASH_REMATCH[1]}"
    proto="${BASH_REMATCH[2]}"
  elif [[ "$entry" =~ ^([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
    proto="$default_proto"
  else
    warn "Porta UFW non valida: '${entry}' (usa PORTA, PORTA/tcp, PORTA/udp, PORTA/both)"
    return 0
  fi

  case "$proto" in
    tcp)
      ufw allow "${port}/tcp" comment "$comment"
      info "UFW: consentita ${port}/tcp"
      ;;
    udp)
      ufw allow "${port}/udp" comment "$comment"
      info "UFW: consentita ${port}/udp"
      ;;
    both)
      ufw allow "${port}/tcp" comment "$comment"
      ufw allow "${port}/udp" comment "$comment"
      info "UFW: consentita ${port}/tcp+udp"
      ;;
  esac
}

ufw_apply_port_list() {
  local list="$1"
  local default_proto="${2:-tcp}"
  local comment="${3:-Custom}"
  [[ -n "$list" ]] || return 0
  IFS=',' read -ra PORTS <<< "$list"
  for p in "${PORTS[@]}"; do
    ufw_apply_port_entry "$p" "$default_proto" "$comment"
  done
}

ufw_prompt_port_list() {
  local var_name="$1"
  local question="$2"
  local current="${!var_name:-}"

  if [[ -n "$current" ]]; then
    export "$var_name=$current"
    return 0
  fi

  if [[ "$INTERACTIVE" != "yes" ]]; then
    export "$var_name="
    return 0
  fi

  local input=""
  read -rp "${question} (solo numeri, es. 8080,9000 — Invio per nessuna): " input
  export "$var_name=${input}"
}

# Imposta la porta SSH in sshd (drop-in) e fail2ban
configure_ssh_port() {
  local port="$1"

  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/99-debian-provision-port.conf <<EOF
# Generato da debian-provision
Port ${port}
EOF

  if sshd -t 2>/dev/null; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || systemctl restart ssh
    success "sshd configurato sulla porta ${port}"
  else
    warn "Validazione sshd fallita — configurazione porta non applicata"
    rm -f /etc/ssh/sshd_config.d/99-debian-provision-port.conf
    return 1
  fi

  if command -v fail2ban-client &>/dev/null; then
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/debian-provision.local <<EOF
# Generato da debian-provision
[sshd]
enabled = true
port = ${port}
maxretry = 5
bantime = 3600
findtime = 600
EOF
    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true
    success "fail2ban configurato per SSH porta ${port}"
  fi
}

module_ufw() {
  apt-get -y install ufw

  prompt_var UFW_SSH_PORT "Porta SSH" "${UFW_SSH_PORT:-54321}"
  export UFW_SSH_PORT
  prompt_yes_no UFW_ALLOW_HTTP  "Consentire HTTP (porta 80)?" "${UFW_ALLOW_HTTP:-yes}"
  prompt_yes_no UFW_ALLOW_HTTPS "Consentire HTTPS (porta 443)?" "${UFW_ALLOW_HTTPS:-yes}"
  ufw_prompt_port_list UFW_EXTRA_PORTS     "Porte extra TCP"
  ufw_prompt_port_list UFW_EXTRA_UDP_PORTS "Porte extra UDP"

  configure_ssh_port "$UFW_SSH_PORT"

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "${UFW_SSH_PORT}/tcp" comment 'SSH'

  [[ "$UFW_ALLOW_HTTP" =~ ^[Yy] ]] && ufw allow 80/tcp comment 'HTTP'
  [[ "$UFW_ALLOW_HTTPS" =~ ^[Yy] ]] && ufw allow 443/tcp comment 'HTTPS'

  ufw_apply_port_list "$UFW_EXTRA_PORTS" "tcp" "Custom"
  ufw_apply_port_list "$UFW_EXTRA_UDP_PORTS" "udp" "Custom UDP"

  if confirm "Abilitare UFW ora?" "y"; then
    ufw --force enable
    success "UFW attivo."
    ufw status verbose
    warn "Verifica che il firewall cloud (Lightsail/EC2 Security Group) consenta la porta SSH ${UFW_SSH_PORT}"
  else
    warn "UFW configurato ma non abilitato. Esegui: ufw enable"
  fi
}

module_ufw
