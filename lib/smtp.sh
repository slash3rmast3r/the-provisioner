#!/usr/bin/env bash
# Funzioni SMTP condivise (msmtp + integrazione Monit/Logwatch)

SMTP_MARKER="/etc/debian-provision/smtp.configured"

smtp_is_enabled() {
  [[ "${SMTP_ENABLED:-no}" =~ ^[Yy] ]] && [[ -n "${SMTP_HOST:-}" ]]
}

smtp_is_configured() {
  [[ -f "$SMTP_MARKER" ]]
}

# Chiede configurazione SMTP completa (o legge da env/config)
prompt_smtp_config() {
  local default_host="${SMTP_HOST:-${MONIT_SMTP_SERVER:-}}"

  prompt_var SMTP_ENABLED  "Configurare relay SMTP autenticato? (yes/no)" "${SMTP_ENABLED:-yes}"
  if [[ ! "$SMTP_ENABLED" =~ ^[Yy] ]]; then
    export SMTP_ENABLED="no"
    return 0
  fi

  prompt_var SMTP_HOST     "Server SMTP (hostname)"                    "$default_host"
  prompt_var SMTP_PORT     "Porta SMTP (587=STARTTLS, 465=SSL)"        "${SMTP_PORT:-587}"
  prompt_var SMTP_TLS      "Crittografia (starttls, ssl, none)"        "${SMTP_TLS:-starttls}"
  prompt_var SMTP_USER     "Username SMTP (es. email@dominio.it)"      "${SMTP_USER:-}"
  prompt_var SMTP_PASSWORD "Password SMTP"                             "${SMTP_PASSWORD:-}" "yes"
  prompt_var SMTP_FROM     "Email mittente (From)"                     "${SMTP_FROM:-${SMTP_USER}}"

  if [[ -z "$SMTP_HOST" || -z "$SMTP_USER" || -z "$SMTP_PASSWORD" ]]; then
    die "SMTP_HOST, SMTP_USER e SMTP_PASSWORD sono obbligatori quando SMTP_ENABLED=yes"
  fi
}

# Configura msmtp come relay di sistema (usato da Logwatch, cron, ecc.)
configure_msmtp() {
  smtp_is_enabled || return 0

  info "Configurazione relay SMTP con msmtp..."
  apt-get -y install msmtp msmtp-mta

  local tls_enabled="on"
  local tls_starttls="on"
  case "${SMTP_TLS,,}" in
    ssl)
      tls_starttls="off"
      ;;
    none)
      tls_enabled="off"
      tls_starttls="off"
      ;;
    starttls|*)
      tls_starttls="on"
      ;;
  esac

  mkdir -p /etc/debian-provision
  cat > /etc/msmtprc <<EOF
# Generato da debian-provision — non modificare manualmente senza backup
defaults
auth           on
tls            ${tls_enabled}
tls_starttls   ${tls_starttls}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           ${SMTP_HOST}
port           ${SMTP_PORT}
from           ${SMTP_FROM}
user           ${SMTP_USER}
password       ${SMTP_PASSWORD}

account default : default
EOF
  chmod 600 /etc/msmtprc

  touch /var/log/msmtp.log
  chmod 640 /var/log/msmtp.log

  # msmtp-mta fornisce /usr/sbin/sendmail per Logwatch e altri tool
  update-alternatives --set mta /usr/bin/msmtp-mta 2>/dev/null || true

  date -Iseconds > "$SMTP_MARKER"
  success "msmtp configurato → ${SMTP_HOST}:${SMTP_PORT}"
}

# Configura SMTP se non già fatto (chiamato da Monit/Logwatch senza modulo smtp)
smtp_ensure_configured() {
  if smtp_is_configured; then
    return 0
  fi

  # Retrocompatibilità: MONIT_SMTP_SERVER senza auth → non forzare SMTP relay
  if [[ -z "${SMTP_HOST:-}" && -z "${SMTP_USER:-}" && -n "${MONIT_SMTP_SERVER:-}" ]]; then
    if [[ "$INTERACTIVE" == "yes" ]] && confirm "Configurare autenticazione SMTP per ${MONIT_SMTP_SERVER}?" "y"; then
      export SMTP_HOST="$MONIT_SMTP_SERVER"
      prompt_smtp_config
      configure_msmtp
    fi
    return 0
  fi

  if [[ -n "${SMTP_HOST:-}" || "${SMTP_ENABLED:-}" =~ ^[Yy] ]]; then
    prompt_smtp_config
    configure_msmtp
  fi
}

# Blocco mailserver per /etc/monit/monitrc
render_monit_mailserver() {
  if smtp_is_enabled; then
    local tls_line=""
    case "${SMTP_TLS,,}" in
      ssl)   tls_line="    using ssl" ;;
      none)  tls_line="" ;;
      *)     tls_line="    using tlsv12" ;;
    esac
    cat <<EOF
set mailserver ${SMTP_HOST} port ${SMTP_PORT}
    username "${SMTP_USER}" password "${SMTP_PASSWORD}"
${tls_line}
EOF
  elif [[ -n "${MONIT_SMTP_SERVER:-}" ]]; then
    echo "set mailserver ${MONIT_SMTP_SERVER}"
  else
    echo "set mailserver localhost"
  fi
}

# Invia email di test tramite msmtp
smtp_send_test() {
  smtp_is_enabled || { warn "SMTP non abilitato, test saltato."; return 0; }
  local to="${1:-${SMTP_FROM}}"
  info "Invio email di test a ${to}..."
  if echo "Test debian-provision da $(hostname -f) alle $(date)" \
    | msmtp -a default "$to" 2>/dev/null; then
    success "Email di test inviata a ${to}"
  else
    warn "Invio email di test fallito. Controlla /var/log/msmtp.log"
  fi
}
