#!/usr/bin/env bash
# Modulo: Monit - monitoraggio servizi

module_monit() {
  apt-get -y install monit mailutils

  smtp_ensure_configured

  local ssh_port="${UFW_SSH_PORT:-54321}"

  prompt_var MONIT_ADMIN_EMAIL    "Email per notifiche Monit" "${MONIT_ADMIN_EMAIL:-root@localhost}"
  prompt_var MONIT_CHECK_INTERVAL "Intervallo controllo in secondi" "${MONIT_CHECK_INTERVAL:-60}"
  prompt_var MONIT_SERVICES       "Servizi da monitorare (ssh,nginx,docker,filesystem,custom)" "${MONIT_SERVICES:-ssh,docker,filesystem}"

  [[ -f /etc/monit/monitrc ]] && cp /etc/monit/monitrc "/etc/monit/monitrc.bak.$(date +%s)"

  local mailserver_block
  mailserver_block="$(render_monit_mailserver)"

  local mail_from
  if smtp_is_enabled; then
    mail_from="${SMTP_FROM}"
  else
    mail_from="monit@$(hostname -f)"
  fi

  cat > /etc/monit/monitrc <<EOF
set daemon ${MONIT_CHECK_INTERVAL}
set logfile /var/log/monit.log
set idfile /var/lib/monit/id
set statefile /var/lib/monit/state

${mailserver_block}
set eventqueue
    basedir /var/lib/monit/events
    slots 100

set mail-format {
    from:    ${mail_from}
    subject: \$SERVICE \$EVENT at \$DATE on \$HOST
    message: Monit \$ACTION \$SERVICE at \$DATE on \$HOST,

             \$DESCRIPTION

             --
             Monit
}

set alert ${MONIT_ADMIN_EMAIL} but not on { instance, pid, ppid, action }

include /etc/monit/conf-enabled/*
EOF

  chmod 700 /etc/monit/monitrc
  mkdir -p /etc/monit/conf-enabled

  IFS=',' read -ra SVC <<< "$MONIT_SERVICES"
  for svc in "${SVC[@]}"; do
    svc="$(echo "$svc" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$svc" in
      ssh)
        cat > /etc/monit/conf-enabled/ssh <<SSHEOF
check process ssh with pidfile /run/sshd.pid
    start program = "/bin/systemctl start ssh"
    stop program  = "/bin/systemctl stop ssh"
    if failed port ${ssh_port} protocol ssh for 3 cycles then restart
    if 5 restarts within 5 cycles then alert
SSHEOF
        ;;
      nginx)
        cat > /etc/monit/conf-enabled/nginx <<'NGXEOF'
check process nginx with pidfile /run/nginx.pid
    start program = "/bin/systemctl start nginx"
    stop program  = "/bin/systemctl stop nginx"
    if failed host 127.0.0.1 port 80 protocol http for 3 cycles then restart
    if 5 restarts within 5 cycles then alert
NGXEOF
        ;;
      docker)
        cat > /etc/monit/conf-enabled/docker <<'DOCEOF'
check process docker matching "dockerd"
    start program = "/bin/systemctl start docker"
    stop program  = "/bin/systemctl stop docker"
    if 5 restarts within 5 cycles then alert
DOCEOF
        ;;
      filesystem)
        cat > /etc/monit/conf-enabled/filesystem <<'FSEOF'
check filesystem rootfs with path /
    if space usage > 85% for 5 cycles then alert
    if inode usage > 85% for 5 cycles then alert
FSEOF
        ;;
      custom)
        if [[ "$INTERACTIVE" == "yes" ]]; then
          read -rp "Nome processo custom: " custom_name
          read -rp "PID file (es. /var/run/myapp.pid): " custom_pid
          read -rp "Comando start (es. /bin/systemctl start myapp): " custom_start
          read -rp "Comando stop (es. /bin/systemctl stop myapp): " custom_stop
        else
          custom_name="${MONIT_CUSTOM_NAME:-myapp}"
          custom_pid="${MONIT_CUSTOM_PID:-/var/run/myapp.pid}"
          custom_start="${MONIT_CUSTOM_START:-/bin/systemctl start myapp}"
          custom_stop="${MONIT_CUSTOM_STOP:-/bin/systemctl stop myapp}"
        fi
        cat > "/etc/monit/conf-enabled/${custom_name}" <<CUSTOMEOF
check process ${custom_name} with pidfile ${custom_pid}
    start program = "${custom_start}"
    stop program  = "${custom_stop}"
    if 5 restarts within 5 cycles then alert
CUSTOMEOF
        ;;
      *)
        warn "Servizio Monit sconosciuto: ${svc} (saltato)"
        ;;
    esac
  done

  monit -t || die "Configurazione Monit non valida"

  systemctl enable monit
  systemctl restart monit

  success "Monit configurato. Notifiche → ${MONIT_ADMIN_EMAIL} (SSH monitorata su porta ${ssh_port})"
}

module_monit
