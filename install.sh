#!/usr/bin/env bash
#
# debian-provision — Script modulare per provisioning server Debian
#
# Uso interattivo (sulla macchina):
#   sudo bash install.sh
#   sudo bash install.sh --all
#   sudo bash install.sh --modules base,ufw,smtp,docker,monit,logwatch
#
# Uso non interattivo (AWS user-data / CI):
#   sudo CONFIG_FILE=/path/to/config.env bash install.sh --all --non-interactive
#
# Aggiungere moduli: crea modules/XX-nome.sh seguendo gli esempi esistenti
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

VERSION="1.0.0"
SELECTED_MODULES=()
RUN_ALL=false
SKIP_CONFIRM=false

usage() {
  cat <<EOF
${BOLD}debian-provision v${VERSION}${NC} — Provisioning modulare Debian

${BOLD}USO:${NC}
  sudo $0 [opzioni]

${BOLD}OPZIONI:${NC}
  -h, --help              Mostra questo aiuto
  -a, --all               Esegue tutti i moduli in ordine
  -m, --modules LISTA     Moduli da eseguire (es. base,ufw,smtp,docker,monit,logwatch)
  -c, --config FILE       File .env con variabili di configurazione
  -n, --non-interactive   Nessun prompt (usa default o variabili da config)
  -y, --yes               Salta conferma finale
  -l, --list              Elenca moduli disponibili

${BOLD}MODULI DISPONIBILI:${NC}
  base      Aggiornamento sistema + pacchetti essenziali
  ufw       Firewall UFW
  smtp      Relay SMTP condiviso (msmtp) per email di sistema
  docker    Docker Engine (repo ufficiale)
  monit     Monitoraggio servizi
  logwatch  Report log giornalieri

${BOLD}ESEMPIO AWS USER-DATA:${NC}
  #cloud-config
  write_files:
    - path: /root/provision-config.env
      content: |
        MONIT_ADMIN_EMAIL=admin@example.com
        LOGWATCH_EMAIL=admin@example.com
        UFW_SSH_PORT=54321
        DOCKER_USERS=ubuntu
  runcmd:
    - curl -fsSL https://.../install.sh -o /root/install.sh
    - chmod +x /root/install.sh
    - CONFIG_FILE=/root/provision-config.env /root/install.sh --all --non-interactive -y

${BOLD}VARIABILI CONFIG (esempi):${NC}
  SMTP_ENABLED, SMTP_HOST, SMTP_PORT, SMTP_TLS, SMTP_USER, SMTP_PASSWORD, SMTP_FROM
  MONIT_ADMIN_EMAIL, MONIT_SERVICES
  LOGWATCH_EMAIL, LOGWATCH_DETAIL, LOGWATCH_SERVICES
  UFW_SSH_PORT, UFW_ALLOW_HTTP, UFW_EXTRA_PORTS, UFW_EXTRA_UDP_PORTS
  (porte: PORTA, PORTA/tcp, PORTA/udp, PORTA/both — separate da virgola)
  DOCKER_USERS, DOCKER_INSTALL_COMPOSE

EOF
}

map_module_alias() {
  local alias="$1"
  case "$alias" in
    base|00-base)         echo "00-base.sh" ;;
    ufw|01-ufw)           echo "01-ufw.sh" ;;
    smtp|02-smtp)         echo "02-smtp.sh" ;;
    docker|02-docker|03-docker) echo "03-docker.sh" ;;
    monit|03-monit|04-monit)   echo "04-monit.sh" ;;
    logwatch|04-logwatch|05-logwatch) echo "05-logwatch.sh" ;;
    *)                    echo "${alias}.sh" ;;
  esac
}

show_menu() {
  echo
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║     Debian Server Provisioning v${VERSION}     ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo
  echo "Seleziona i moduli da installare (numeri separati da virgola):"
  echo
  local i=1
  local -a menu_modules=()
  while IFS= read -r mod; do
    menu_modules+=("$mod")
    local name
    name="$(module_name_from_path "$mod")"
    printf "  %2d) %s\n" "$i" "${name#??-}"
  ((i++))
  done < <(list_modules)
  echo
  echo "   a) Tutti i moduli"
  echo "   q) Esci"
  echo
  read -rp "Scelta: " choice

  if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
    info "Uscita."
    exit 0
  fi

  if [[ "$choice" == "a" || "$choice" == "A" ]]; then
    RUN_ALL=true
    return
  fi

  IFS=',' read -ra CHOICES <<< "$choice"
  for c in "${CHOICES[@]}"; do
    c="$(echo "$c" | xargs)"
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#menu_modules[@]} )); then
      SELECTED_MODULES+=("${menu_modules[$((c-1))]}")
    else
      warn "Scelta non valida: $c"
    fi
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -a|--all) RUN_ALL=true; shift ;;
      -m|--modules)
        IFS=',' read -ra MODS <<< "$2"
        for m in "${MODS[@]}"; do
          SELECTED_MODULES+=("$(map_module_alias "$(echo "$m" | xargs)")")
        done
        shift 2 ;;
      -c|--config) CONFIG_FILE="$2"; shift 2 ;;
      -n|--non-interactive) INTERACTIVE="no"; shift ;;
      -y|--yes) SKIP_CONFIRM=true; shift ;;
      -l|--list)
        echo "Moduli disponibili:"
        while IFS= read -r mod; do
          echo "  - $(module_name_from_path "$mod")"
        done < <(list_modules)
        exit 0 ;;
      *) die "Opzione sconosciuta: $1 (usa --help)" ;;
    esac
  done
}

main() {
  parse_args "$@"

  require_root
  require_debian
  detect_interactive

  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  [[ -n "$CONFIG_FILE" ]] && load_config "$CONFIG_FILE"

  if [[ "$RUN_ALL" == true ]]; then
    while IFS= read -r mod; do
      SELECTED_MODULES+=("$mod")
    done < <(list_modules)
  elif [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
    if [[ "$INTERACTIVE" == "yes" ]]; then
      show_menu
      if [[ "$RUN_ALL" == true ]]; then
        SELECTED_MODULES=()
        while IFS= read -r mod; do
          SELECTED_MODULES+=("$mod")
        done < <(list_modules)
      fi
    else
      die "Specifica --all o --modules in modalità non interattiva."
    fi
  fi

  if [[ ${#SELECTED_MODULES[@]} -eq 0 ]]; then
    die "Nessun modulo selezionato."
  fi

  echo
  info "Moduli da eseguire:"
  for mod in "${SELECTED_MODULES[@]}"; do
    echo "  • $(module_name_from_path "$mod")"
  done
  echo

  if [[ "$SKIP_CONFIRM" != true ]] && [[ "$INTERACTIVE" == "yes" ]]; then
    confirm "Procedere con l'installazione?" "y" || exit 0
  fi

  local start_time
  start_time="$(date +%s)"

  for mod in "${SELECTED_MODULES[@]}"; do
    run_module "$(basename "$mod")"
  done

  save_runtime_config "/etc/debian-provision/runtime.env"

  local elapsed=$(( $(date +%s) - start_time ))
  echo
  success "Provisioning completato in ${elapsed}s."
  info "Log completo: ${LOG_FILE}"
  info "Per aggiungere moduli: crea un file in ${MODULES_DIR}/"
}

main "$@"
