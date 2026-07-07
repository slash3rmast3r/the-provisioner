#!/usr/bin/env bash
# Modulo: Logwatch - report log giornalieri

module_logwatch() {
  apt-get -y install logwatch mailutils

  smtp_ensure_configured

  prompt_var LOGWATCH_EMAIL     "Email destinatario report Logwatch" "${LOGWATCH_EMAIL:-root@localhost}"
  prompt_var LOGWATCH_DETAIL    "Livello dettaglio (Low, Med, High)" "${LOGWATCH_DETAIL:-Med}"
  prompt_var LOGWATCH_RANGE     "Intervallo report (Yesterday, Today, All)" "${LOGWATCH_RANGE:-Yesterday}"
  prompt_var LOGWATCH_SERVICES  "Servizi da includere (All o lista: sshd,http,postfix)" "${LOGWATCH_SERVICES:-All}"
  prompt_var LOGWATCH_FORMAT    "Formato output (text, html)" "${LOGWATCH_FORMAT:-text}"
  prompt_var LOGWATCH_CRON_HOUR "Ora invio report giornaliero (0-23)" "${LOGWATCH_CRON_HOUR:-6}"

  local mail_from=""
  if smtp_is_enabled; then
    mail_from="MailFrom = ${SMTP_FROM}"
  fi

  mkdir -p /etc/logwatch/conf
  mkdir -p /var/cache/logwatch

  cat > /etc/logwatch/conf/logwatch.conf <<EOF
MailTo = ${LOGWATCH_EMAIL}
${mail_from}
Detail = ${LOGWATCH_DETAIL}
Range = ${LOGWATCH_RANGE}
Format = ${LOGWATCH_FORMAT}
Service = ${LOGWATCH_SERVICES}
EOF

  # Un solo cron giornaliero (evita doppio invio con cron.daily)
  rm -f /etc/cron.daily/00logwatch /etc/cron.daily/logwatch

  if [[ "$LOGWATCH_CRON_HOUR" =~ ^[0-9]+$ ]]; then
    cat > /etc/cron.d/logwatch <<EOF
# Report Logwatch giornaliero — generato da debian-provision
0 ${LOGWATCH_CRON_HOUR} * * * root /usr/sbin/logwatch --output mail
EOF
    chmod 644 /etc/cron.d/logwatch
  else
    warn "LOGWATCH_CRON_HOUR non valido (${LOGWATCH_CRON_HOUR}), cron non creato"
  fi

  if confirm "Eseguire un test Logwatch (output su stdout, senza email)?" "n"; then
    info "Anteprima report Logwatch (prime 50 righe)..."
    set +o pipefail
    /usr/sbin/logwatch --output stdout --range Today --detail Low 2>/dev/null | head -50 || true
    set -o pipefail
  fi

  success "Logwatch configurato. Report → ${LOGWATCH_EMAIL} alle ${LOGWATCH_CRON_HOUR}:00"
}

module_logwatch
