#!/usr/bin/env bash
# Modulo: relay SMTP condiviso (msmtp) per Monit, Logwatch e altri servizi

module_smtp() {
  prompt_smtp_config

  if smtp_is_enabled; then
    configure_msmtp
    if confirm "Inviare email di test?" "n"; then
      prompt_var SMTP_TEST_EMAIL "Destinatario test" "${SMTP_TEST_EMAIL:-${SMTP_FROM}}"
      smtp_send_test "$SMTP_TEST_EMAIL"
    fi
  else
    info "SMTP relay non configurato. Monit/Logwatch useranno localhost o MONIT_SMTP_SERVER."
  fi
}

module_smtp
