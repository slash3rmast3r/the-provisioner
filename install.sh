#!/usr/bin/env bash
#
# ═══════════════════════════════════════════════════════════════════════════════
#  The Provisioner — install.sh
#  Debian server provisioning (single self-contained file)
#
#  Copyright (c) 2025-2026 Carlo Savino — All rights reserved.
#  SPDX-License-Identifier: BSD-3-Clause
#  Licensed under the BSD 3-Clause License — see LICENSE in the repository.
#  Names may not be used for endorsement without prior written permission.
#  https://github.com/slash3rmast3r/the-provisioner
# ═══════════════════════════════════════════════════════════════════════════════
#
# Nessuna dipendenza da altri file del repository.
# Uso consigliato:  sudo bash install.sh
#
# Postfix relay verso smarthost per Monit, Logwatch e mail di sistema.
#
# Opzionale (non interattivo):
#   sudo SMTP_HOST=smtp.example.com SMTP_USER=... SMTP_PASSWORD=... \
#        INSTALL_DOCKER=yes INSTALL_MONIT=yes \
#        bash install.sh --non-interactive -y
#
# Riavvio automatico (opzionale):
#   ALLOW_REBOOT=yes   — riavvia senza chiedere
#   ALLOW_REBOOT=no    — non riavviare
#   ALLOW_REBOOT=auto  — chiedi a fine script (default)
#

# ── Bootstrap (prima di set -e) ───────────────────────────────────────────────
if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi
if grep -q $'\r' "$0" 2>/dev/null; then
  echo "[debian-provision] Correzione fine riga Windows (CRLF) in corso..." >&2
  sed -i 's/\r$//' "$0"
  exec /usr/bin/env bash "$0" "$@"
fi
echo "[install.sh] debian-provision v1.6.3 — avvio..." >&2

# Nota: NON usare set -e — con pattern [[ cond ]] && cmd le funzioni
# restituiscono exit 1 quando la condizione è falsa e lo script termina in silenzio.
set -uo pipefail

VERSION="1.6.3"
PROVISIONER_AUTHOR="Carlo Savino"
PROVISIONER_EMAIL="info@savinocarlo.it"
PROVISIONER_WEBSITE="www.savinocarlo.it"
PROVISIONER_NAME="The Provisioner"
PROVISIONER_REPO="https://github.com/slash3rmast3r/the-provisioner"
LOG_FILE="/var/log/debian-provision.log"
MARKER_DIR="/etc/debian-provision"
BASE_DONE_MARKER="${MARKER_DIR}/base.done"
SMTP_MARKER="${MARKER_DIR}/smtp.configured"

# Rilevamento release Debian (impostate da detect_debian_release)
DEBIAN_MAJOR=0
DEBIAN_CODENAME=""
DEBIAN_PRETTY=""
DEBIAN_SUITE=""
DOCKER_APT_CODENAME=""
DEBIAN_SUPPORTS_SSH_SOCKET=false
DEBIAN_MIN_MAJOR=11
INTERACTIVE="${INTERACTIVE:-auto}"
SKIP_CONFIRM=false
NON_INTERACTIVE=false
ALLOW_REBOOT="${ALLOW_REBOOT:-${REBOOT_AFTER_INSTALL:-auto}}"
ONLY_MODULES=""
SKIP_BASE=false
MODULE_FORCE="${MODULE_FORCE:-no}"
CONFIG_FILE="${CONFIG_FILE:-}"
PREFLIGHT_STRICT="${PREFLIGHT_STRICT:-yes}"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-auto}"
SSH_PREFLIGHT_CONFIRMED="${SSH_PREFLIGHT_CONFIRMED:-no}"

# Selezione componenti (yes/no/auto — auto = chiedi in interattivo)
INSTALL_BASE="${INSTALL_BASE:-yes}"
INSTALL_BUILD="${INSTALL_BUILD:-auto}"
INSTALL_UFW="${INSTALL_UFW:-auto}"
INSTALL_SMTP="${INSTALL_SMTP:-auto}"
INSTALL_DOCKER="${INSTALL_DOCKER:-auto}"
INSTALL_MONIT="${INSTALL_MONIT:-auto}"
INSTALL_LOGWATCH="${INSTALL_LOGWATCH:-auto}"
INSTALL_CRON="${INSTALL_CRON:-auto}"
INSTALL_BASH_ALIASES="${INSTALL_BASH_ALIASES:-auto}"
INSTALL_RAM_MONITOR="${INSTALL_RAM_MONITOR:-auto}"
INSTALL_SMART_MONITOR="${INSTALL_SMART_MONITOR:-auto}"
INSTALL_BOOT_SERVICES="${INSTALL_BOOT_SERVICES:-auto}"
INSTALL_BASHRC_ALIASES="${INSTALL_BASHRC_ALIASES:-auto}"
INSTALL_FAIL2BAN="${INSTALL_FAIL2BAN:-auto}"
INSTALL_SSH_HARDENING="${INSTALL_SSH_HARDENING:-auto}"
INSTALL_TIMEZONE="${INSTALL_TIMEZONE:-auto}"
INSTALL_PROFTPD="${INSTALL_PROFTPD:-auto}"

# Variabili configurazione (sovrascrivibili via env)
SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_TLS="${SMTP_TLS:-starttls}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_PASSWORD_FILE="${SMTP_PASSWORD_FILE:-}"
POSTFIX_MAILNAME="${POSTFIX_MAILNAME:-}"
POSTFIX_MYORIGIN="${POSTFIX_MYORIGIN:-}"
POSTFIX_LOOPBACK="${POSTFIX_LOOPBACK:-auto}"
SMTP_FROM="${SMTP_FROM:-}"
UFW_SSH_PORT="${UFW_SSH_PORT:-54321}"
UFW_ALLOW_HTTP="${UFW_ALLOW_HTTP:-auto}"
UFW_ALLOW_HTTPS="${UFW_ALLOW_HTTPS:-auto}"
UFW_EXTRA_PORTS="${UFW_EXTRA_PORTS:-}"
UFW_EXTRA_UDP_PORTS="${UFW_EXTRA_UDP_PORTS:-}"
DOCKER_INSTALL_COMPOSE="${DOCKER_INSTALL_COMPOSE:-auto}"
DOCKER_USERS="${DOCKER_USERS:-}"
MONIT_ADMIN_EMAIL="${MONIT_ADMIN_EMAIL:-}"
MONIT_CHECK_INTERVAL="${MONIT_CHECK_INTERVAL:-60}"
MONIT_SERVICES="${MONIT_SERVICES:-auto}"
LOGWATCH_EMAIL="${LOGWATCH_EMAIL:-}"
LOGWATCH_DETAIL="${LOGWATCH_DETAIL:-Med}"
LOGWATCH_RANGE="${LOGWATCH_RANGE:-Yesterday}"
LOGWATCH_SERVICES="${LOGWATCH_SERVICES:-auto}"
LOGWATCH_FORMAT="${LOGWATCH_FORMAT:-text}"
LOGWATCH_CRON_HOUR="${LOGWATCH_CRON_HOUR:-6}"

# Monitoraggio RAM / SMART
MON_SERVER_NAME="${MON_SERVER_NAME:-}"
RAM_MAIL_TO="${RAM_MAIL_TO:-}"
RAM_TELEGRAM_BOT_TOKEN="${RAM_TELEGRAM_BOT_TOKEN:-}"
RAM_TELEGRAM_CHAT_ID="${RAM_TELEGRAM_CHAT_ID:-}"
RAM_GOTIFY_URL="${RAM_GOTIFY_URL:-}"
RAM_GOTIFY_TOKEN="${RAM_GOTIFY_TOKEN:-}"
SMART_EMAIL_TO="${SMART_EMAIL_TO:-}"
SMART_TELEGRAM_BOT_TOKEN="${SMART_TELEGRAM_BOT_TOKEN:-}"
SMART_TELEGRAM_CHAT_ID="${SMART_TELEGRAM_CHAT_ID:-}"
SMART_GOTIFY_URL="${SMART_GOTIFY_URL:-}"
SMART_GOTIFY_TOKEN="${SMART_GOTIFY_TOKEN:-}"
SMART_CRON_HOUR="${SMART_CRON_HOUR:-6}"

# SSH hardening
SSH_PERMIT_ROOT="${SSH_PERMIT_ROOT:-prohibit-password}"
SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-yes}"
SSH_MAX_AUTH_TRIES="${SSH_MAX_AUTH_TRIES:-5}"
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-}"

# Timezone
SYSTEM_TIMEZONE="${SYSTEM_TIMEZONE:-}"

# ProFTPd
PROFTPD_PORT="${PROFTPD_PORT:-21}"
PROFTPD_TLS="${PROFTPD_TLS:-auto}"
PROFTPD_PASSIVE_MIN="${PROFTPD_PASSIVE_MIN:-40000}"
PROFTPD_PASSIVE_MAX="${PROFTPD_PASSIVE_MAX:-40100}"
PROFTPD_USER="${PROFTPD_USER:-}"
PROFTPD_ALLOW_ANONYMOUS="${PROFTPD_ALLOW_ANONYMOUS:-no}"
PROFTPD_CHROOT="${PROFTPD_CHROOT:-yes}"
PROFTPD_MAX_CLIENTS="${PROFTPD_MAX_CLIENTS:-10}"
PROFTPD_MAX_INSTANCES="${PROFTPD_MAX_INSTANCES:-30}"

# Report email finale provisioning
SEND_INSTALL_REPORT="${SEND_INSTALL_REPORT:-auto}"
INSTALL_REPORT_EMAIL="${INSTALL_REPORT_EMAIL:-}"
PROVISION_ACTIVE=false
PROVISION_REPORT_SENT=false
PROVISION_WARN_COUNT=0
PROVISION_ERROR_COUNT=0
PROVISION_ELAPSED=0
PROVISION_EXIT_CODE=0
PROVISION_WARNINGS=()
PROVISION_ERRORS=()
PROVISION_REPORT_MAX_ITEMS=30

# ─── Colori / log ───────────────────────────────────────────────────────────────

RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
if [[ -t 1 && -t 2 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
fi

log() {
  local level="$1"; shift
  local plain
  plain="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  local colored="$plain"
  case "$level" in
    INFO)  colored="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${BLUE}$*${NC}" ;;
    OK)    colored="[$(date '+%Y-%m-%d %H:%M:%S')] [OK]   ${GREEN}$*${NC}" ;;
    WARN)  colored="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${YELLOW}$*${NC}" ;;
    ERROR) colored="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${RED}$*${NC}" ;;
  esac
  echo -e "$colored" >&2
  echo "$plain" >> "$LOG_FILE" 2>/dev/null || true
  case "$level" in
    WARN)
      ((PROVISION_WARN_COUNT++)) || true
      if ((${#PROVISION_WARNINGS[@]} < PROVISION_REPORT_MAX_ITEMS)); then
        PROVISION_WARNINGS+=("$*")
      fi
      ;;
    ERROR)
      ((PROVISION_ERROR_COUNT++)) || true
      if ((${#PROVISION_ERRORS[@]} < PROVISION_REPORT_MAX_ITEMS)); then
        PROVISION_ERRORS+=("$*")
      fi
      ;;
  esac
}

info()    { log "INFO" "$*"; }
success() { log "OK" "$*"; }
warn()    { log "WARN" "$*"; }
error()   { log "ERROR" "$*"; }
die()     { error "$1"; exit "${2:-1}"; }

# ─── Utility interattive ──────────────────────────────────────────────────────

detect_interactive() {
  if [[ "$INTERACTIVE" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]] && [[ "$NON_INTERACTIVE" != true ]]; then
      INTERACTIVE="yes"
    else
      INTERACTIVE="no"
    fi
  fi
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Esegui come root: sudo bash $0"
  fi
}

require_debian() {
  detect_debian_release
}

# Rileva versione/codename Debian e centralizza eccezioni per release.
detect_debian_release() {
  [[ -f /etc/debian_version ]] || die "Supportato solo Debian."
  [[ -f /etc/os-release ]]     || die "File /etc/os-release mancante."

  local id version_id codename debian_version script_version
  script_version="$VERSION"
  set +u
  # shellcheck source=/dev/null
  . /etc/os-release
  set -u
  VERSION="$script_version"

  id="${ID:-}"
  [[ "${id,,}" == "debian" ]] || \
    die "Supportato solo Debian (rilevato: ${id:-sconosciuto})."

  version_id="${VERSION_ID:-}"
  codename="${VERSION_CODENAME:-}"
  debian_version="$(tr -d '[:space:]' < /etc/debian_version)"
  DEBIAN_PRETTY="${PRETTY_NAME:-Debian GNU/Linux}"

  DEBIAN_MAJOR="${version_id%%.*}"
  [[ "$DEBIAN_MAJOR" =~ ^[0-9]+$ ]] || DEBIAN_MAJOR=0

  if [[ -z "$codename" ]]; then
    case "$DEBIAN_MAJOR" in
      13) codename="trixie" ;;
      12) codename="bookworm" ;;
      11) codename="bullseye" ;;
      10) codename="buster" ;;
    esac
  fi
  DEBIAN_CODENAME="${codename,,}"

  if [[ "$DEBIAN_MAJOR" -eq 0 ]]; then
    case "$DEBIAN_CODENAME" in
      trixie|forky)     DEBIAN_MAJOR=13 ;;
      bookworm)         DEBIAN_MAJOR=12 ;;
      bullseye)         DEBIAN_MAJOR=11 ;;
      buster)           DEBIAN_MAJOR=10 ;;
      sid|testing|unstable) DEBIAN_MAJOR=0 ;;
    esac
  fi

  apply_debian_release_profile

  info "Release: ${debian_version} — ${DEBIAN_PRETTY}"
  info "  Codename: ${DEBIAN_CODENAME:-sconosciuto} | Major: ${DEBIAN_MAJOR:-?} | Suite: ${DEBIAN_SUITE}"
  [[ -n "${DOCKER_APT_CODENAME}" && "${DOCKER_APT_CODENAME}" != "$DEBIAN_CODENAME" ]] && \
    info "  Docker repo apt: ${DOCKER_APT_CODENAME} (override per ${DEBIAN_CODENAME})"
}

apply_debian_release_profile() {
  DEBIAN_SUPPORTS_SSH_SOCKET=false
  DOCKER_APT_CODENAME="${DEBIAN_CODENAME}"

  case "$DEBIAN_CODENAME" in
    bookworm)
      DEBIAN_SUITE="stable"
      DEBIAN_SUPPORTS_SSH_SOCKET=true
      ;;
    trixie|forky)
      DEBIAN_SUITE="testing"
      DEBIAN_SUPPORTS_SSH_SOCKET=true
      DOCKER_APT_CODENAME="bookworm"
      warn "Debian Trixie/testing — Docker CE via repo bookworm; fallback docker.io se necessario."
      ;;
    bullseye)
      DEBIAN_SUITE="oldstable"
      info "Debian Bullseye — ssh.socket di solito assente; ssh.service classico."
      ;;
    buster)
      DEBIAN_SUITE="oldoldstable"
      DOCKER_APT_CODENAME="buster"
      ;;
    sid|testing|unstable)
      DEBIAN_SUITE="testing"
      DEBIAN_SUPPORTS_SSH_SOCKET=true
      DOCKER_APT_CODENAME="bookworm"
      warn "Suite sid/testing/unstable — comportamento non garantito."
      ;;
    *)
      DEBIAN_SUITE="unknown"
      warn "Codename '${DEBIAN_CODENAME}' non mappato — uso profilo generico."
      [[ "$DEBIAN_MAJOR" -ge 12 ]] && DEBIAN_SUPPORTS_SSH_SOCKET=true
      ;;
  esac

  if [[ "$DEBIAN_MAJOR" -gt 0 && "$DEBIAN_MAJOR" -lt "$DEBIAN_MIN_MAJOR" ]]; then
    if is_yes "${DEBIAN_ALLOW_OLD:-no}"; then
      warn "Debian ${DEBIAN_MAJOR} sotto il minimo (${DEBIAN_MIN_MAJOR}) — proseguo su tua responsabilità (DEBIAN_ALLOW_OLD=yes)."
    else
      die "Debian ${DEBIAN_MAJOR} (${DEBIAN_CODENAME}) non supportato. Minimo: Debian ${DEBIAN_MIN_MAJOR} (Bullseye). Imposta DEBIAN_ALLOW_OLD=yes per forzare."
    fi
  fi
}

confirm() {
  local question="$1"
  local default="${2:-y}"
  if [[ "$INTERACTIVE" != "yes" ]]; then
    [[ "$default" =~ ^[Yy] ]]
    return
  fi
  local hint="[s/N]"
  [[ "$default" =~ ^[Yy] ]] && hint="[S/n]"
  read -rp "${question} ${hint}: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[SsYy] ]]
}

prompt_var() {
  local var_name="$1"
  local question="$2"
  local default="${3:-}"
  local secret="${4:-no}"
  local current="${!var_name:-}"

  if [[ -n "$current" ]]; then
    return 0
  fi
  if [[ "$INTERACTIVE" != "yes" ]]; then
    [[ -n "$default" ]] || die "Variabile ${var_name} richiesta (modalità non interattiva)."
    printf -v "$var_name" '%s' "$default"
    info "${question} → default: ${default}"
    return 0
  fi
  local input=""
  if [[ "$secret" == "yes" ]]; then
    read -rsp "${question} [${default}]: " input
    echo
  else
    read -rp "${question} [${default}]: " input
  fi
  [[ -z "$input" ]] && input="$default"
  printf -v "$var_name" '%s' "$input"
}

# Sempre chiede in modalità interattiva (per config moduli Monit/Logwatch)
prompt_var_force() {
  local var_name="$1" question="$2" default="$3" secret="${4:-no}"
  if [[ "$INTERACTIVE" == "yes" ]]; then
    local input="" hint="${!var_name:-$default}"
    if [[ "$secret" == "yes" ]]; then
      read -rsp "${question} [${hint}]: " input; echo
    else
      read -rp "${question} [${hint}]: " input
    fi
    [[ -z "$input" ]] && input="$hint"
    printf -v "$var_name" '%s' "$input"
  else
    prompt_var "$var_name" "$question" "$default" "$secret"
  fi
}

prompt_yes_no() {
  local var_name="$1"
  local question="$2"
  local default="${3:-yes}"
  local current="${!var_name:-}"

  if [[ "$current" != "auto" ]]; then
    return 0
  fi
  if [[ "$INTERACTIVE" != "yes" ]]; then
    printf -v "$var_name" '%s' "$default"
    info "${question} → ${default} (non interattivo)"
    return 0
  fi
  if confirm "$question" "$default"; then
    printf -v "$var_name" '%s' "yes"
  else
    printf -v "$var_name" '%s' "no"
  fi
}

is_yes() {
  [[ "${1,,}" == "yes" || "${1,,}" == "y" || "$1" == "1" ]]
}

list_contains() {
  local csv="$1" item="$2" x
  IFS=',' read -ra _lc_arr <<< "$csv"
  for x in "${_lc_arr[@]}"; do
    x="$(echo "$x" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ "$x" == "${item,,}" ]] && return 0
  done
  return 1
}

module_marker_path() {
  echo "${MARKER_DIR}/${1}.done"
}

is_module_done() {
  [[ -f "$(module_marker_path "$1")" ]]
}

mark_module_done() {
  date -Iseconds > "$(module_marker_path "$1")"
}

should_run_module() {
  local mod="$1" var="$2"
  if [[ -n "$ONLY_MODULES" ]]; then
    list_contains "$ONLY_MODULES" "$mod" || return 1
  else
    is_yes "${!var}" || return 1
  fi
  if is_module_done "$mod" && ! is_yes "$MODULE_FORCE"; then
    info "Modulo '${mod}' già completato — skip (MODULE_FORCE=yes per forzare)"
    return 1
  fi
  return 0
}

load_config_file() {
  [[ -n "$CONFIG_FILE" ]] || return 0
  [[ -f "$CONFIG_FILE" ]] || die "CONFIG_FILE non trovato: ${CONFIG_FILE}"
  info "Caricamento config: ${CONFIG_FILE}"
  set -a
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  set +a
}

load_provisioner_state() {
  [[ -n "$CONFIG_FILE" ]] && return 0
  local runtime="${MARKER_DIR}/runtime.env"
  [[ -f "$runtime" ]] || return 0
  info "Stato precedente: ${runtime} (solo variabili ancora 'auto')"
  local v line key val
  for v in INSTALL_BUILD INSTALL_UFW INSTALL_SMTP INSTALL_DOCKER INSTALL_MONIT INSTALL_LOGWATCH \
           INSTALL_CRON INSTALL_RAM_MONITOR INSTALL_SMART_MONITOR INSTALL_BOOT_SERVICES \
           INSTALL_PROFTPD INSTALL_FAIL2BAN INSTALL_SSH_HARDENING INSTALL_TIMEZONE; do
    [[ "${!v}" != "auto" ]] && continue
    line="$(grep -E "^${v}=" "$runtime" 2>/dev/null | tail -1 || true)"
    [[ -z "$line" ]] && continue
    val="${line#*=}"
    [[ -n "$val" ]] && printf -v "$v" '%s' "$val"
  done
  if [[ -n "$ONLY_MODULES" ]]; then
    line="$(grep -E '^UFW_SSH_PORT=' "$runtime" 2>/dev/null | tail -1 || true)"
    [[ -n "$line" ]] && UFW_SSH_PORT="${line#*=}"
  fi
}

load_smtp_password() {
  if [[ -n "${SMTP_PASSWORD_FILE:-}" && -f "$SMTP_PASSWORD_FILE" ]]; then
    SMTP_PASSWORD="$(tr -d '\n\r' < "$SMTP_PASSWORD_FILE")"
    info "Password SMTP letta da ${SMTP_PASSWORD_FILE}"
  fi
}

write_postfix_sasl_passwd() {
  local relayhost="$1" user="$2" pass="$3"
  install -m 600 -o root -g root /dev/null /etc/postfix/sasl_passwd
  printf '%s\t%s:%s\n' "$relayhost" "$user" "$pass" > /etc/postfix/sasl_passwd
  postmap /etc/postfix/sasl_passwd || die "postmap sasl_passwd fallito — verifica password/caratteri speciali"
  chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db 2>/dev/null || true
}

preflight_checks() {
  info "━━━ Preflight ${PROVISIONER_NAME} ━━━"
  local ok=true

  local free_root free_var
  free_root="$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')"
  free_var="$(df -Pm /var 2>/dev/null | awk 'NR==2{print $4}')"
  if [[ "${free_root:-0}" -lt 256 ]]; then
    is_yes "$PREFLIGHT_STRICT" && die "Spazio insufficiente su / (${free_root:-?} MB liberi, min 256 MB)" \
      || { warn "Spazio basso su / (${free_root:-?} MB)"; ok=false; }
  elif [[ "${free_root:-0}" -lt 2048 ]]; then
    warn "Spazio su / limitato (${free_root} MB liberi) — consigliati ≥ 2 GB"
  fi
  [[ -n "${free_var:-}" && "${free_var:-0}" -lt 256 ]] && \
    warn "Spazio basso su /var (${free_var} MB liberi)"

  local mem_kb
  mem_kb="$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}')"
  if [[ "${mem_kb:-0}" -lt 262144 ]]; then
    is_yes "$PREFLIGHT_STRICT" && die "RAM insufficiente (< 256 MB)" \
      || { warn "RAM molto bassa (${mem_kb} kB)"; ok=false; }
  elif [[ "${mem_kb:-0}" -lt 524288 ]]; then
    warn "RAM limitata (< 512 MB) — VPS minima"
  fi

  if ! getent hosts deb.debian.org >/dev/null 2>&1; then
    is_yes "$PREFLIGHT_STRICT" && die "DNS/rete non disponibile (deb.debian.org)" \
      || { warn "Risoluzione DNS deb.debian.org fallita"; ok=false; }
  fi

  if [[ ! -d /run/systemd/system ]] && ! pidof systemd >/dev/null 2>&1; then
    warn "systemd non rilevato — alcuni moduli (ssh.socket, servizi) potrebbero non funzionare"
    ok=false
  fi

  if [[ -n "${SSH_CONNECTION:-}" ]] && is_yes "$INSTALL_UFW"; then
    warn "Sessione SSH attiva: cambio porta/firewall può disconnetterti — apri ${UFW_SSH_PORT} nel cloud prima del reboot"
  fi

  if [[ "$ok" == true ]]; then
    success "Preflight OK"
  else
    warn "Preflight completato con avvisi"
  fi
}

# ─── Rilevamento servizi Monit / Logwatch (auto a cascata) ─────────────────────

dpkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

systemd_unit_exists() {
  local unit="$1"
  [[ "$unit" == *.service ]] || unit="${unit}.service"
  systemctl cat "$unit" &>/dev/null
}

logwatch_script_exists() {
  [[ -f "/usr/share/logwatch/scripts/services/$1" ]]
}

monitoring_component_active() {
  local install_var="$1" module="$2" os_fn="$3"
  [[ -n "$install_var" ]] && is_yes "${!install_var}" && return 0
  [[ -n "$module" ]] && is_module_done "$module" && return 0
  [[ -n "$os_fn" ]] && "$os_fn" && return 0
  return 1
}

os_has_ssh() {
  systemd_unit_exists ssh || systemd_unit_exists sshd || dpkg_installed openssh-server
}

os_has_postfix() {
  systemd_unit_exists postfix || dpkg_installed postfix
}

os_has_docker() {
  systemd_unit_exists docker || dpkg_installed docker-ce || dpkg_installed docker.io
}

os_has_proftpd() {
  systemd_unit_exists proftpd || dpkg_installed proftpd-basic || dpkg_installed proftpd-core || dpkg_installed proftpd
}

os_has_fail2ban() {
  systemd_unit_exists fail2ban || dpkg_installed fail2ban
}

os_has_monit() {
  systemd_unit_exists monit || dpkg_installed monit
}

os_has_nginx() {
  systemd_unit_exists nginx || dpkg_installed nginx
}

add_unique_csv_item() {
  local -n _arr=$1
  local item="$2" x
  for x in "${_arr[@]}"; do
    [[ "$x" == "$item" ]] && return 0
  done
  _arr+=("$item")
}

build_monit_services() {
  local services=()
  if monitoring_component_active INSTALL_UFW ufw os_has_ssh; then
    add_unique_csv_item services ssh
  fi
  if monitoring_component_active INSTALL_DOCKER docker os_has_docker; then
    add_unique_csv_item services docker
  fi
  if monitoring_component_active INSTALL_SMTP smtp os_has_postfix; then
    add_unique_csv_item services postfix
  fi
  if monitoring_component_active INSTALL_PROFTPD proftpd os_has_proftpd; then
    add_unique_csv_item services proftpd
  fi
  if os_has_nginx; then
    add_unique_csv_item services nginx
  fi
  add_unique_csv_item services filesystem
  (IFS=','; echo "${services[*]}")
}

build_logwatch_services() {
  local services=()
  if os_has_ssh && { logwatch_script_exists sshd || logwatch_script_exists ssh; }; then
    if logwatch_script_exists sshd; then
      add_unique_csv_item services sshd
    else
      add_unique_csv_item services ssh
    fi
  elif logwatch_script_exists sshd; then
    add_unique_csv_item services sshd
  fi
  if monitoring_component_active INSTALL_SMTP smtp os_has_postfix && logwatch_script_exists postfix; then
    add_unique_csv_item services postfix
  fi
  if monitoring_component_active INSTALL_FAIL2BAN fail2ban os_has_fail2ban && logwatch_script_exists fail2ban; then
    add_unique_csv_item services fail2ban
  fi
  if monitoring_component_active INSTALL_MONIT monit os_has_monit && logwatch_script_exists monit; then
    add_unique_csv_item services monit
  fi
  if monitoring_component_active INSTALL_PROFTPD proftpd os_has_proftpd && logwatch_script_exists proftpd; then
    add_unique_csv_item services proftpd
  fi
  if monitoring_component_active INSTALL_DOCKER docker os_has_docker && logwatch_script_exists docker; then
    add_unique_csv_item services docker
  fi
  if os_has_nginx && logwatch_script_exists nginx; then
    add_unique_csv_item services nginx
  fi
  ((${#services[@]} == 0)) && services=(sshd)
  (IFS=','; echo "${services[*]}")
}

resolve_monit_services() {
  if [[ "${MONIT_SERVICES,,}" == "auto" || -z "$MONIT_SERVICES" ]]; then
    MONIT_SERVICES="$(build_monit_services)"
    info "Monit servizi (auto: install/marker/OS): ${MONIT_SERVICES}"
  fi
}

resolve_logwatch_services() {
  if [[ "${LOGWATCH_SERVICES,,}" == "auto" || -z "$LOGWATCH_SERVICES" ]]; then
    LOGWATCH_SERVICES="$(build_logwatch_services)"
    info "Logwatch servizi (auto: install/marker/OS): ${LOGWATCH_SERVICES}"
  fi
  normalize_logwatch_services
}

logwatch_wants_all() {
  [[ "${LOGWATCH_SERVICES,,}" == "all" ]]
}

normalize_logwatch_services() {
  local raw="${LOGWATCH_SERVICES// /}"
  if logwatch_wants_all; then
    LOGWATCH_SERVICES="All"
    return 0
  fi
  if [[ "$raw" == *",All,"* || "$raw" == All,* || "$raw" == *,All ]]; then
    warn "LOGWATCH_SERVICES misto All + servizi — uso solo All (in Logwatch non si combinano)"
    LOGWATCH_SERVICES="All"
  fi
}

write_logwatch_conf_file() {
  local conf="/etc/logwatch/conf/logwatch.conf"
  mkdir -p /etc/logwatch/conf /var/cache/logwatch
  # Fragment Debian (es. Service = All) sommati al nostro file causano l'errore
  # "if All selected, only - items are allowed"
  rm -f /etc/logwatch/conf/logwatch.conf.d/*.conf 2>/dev/null || true

  cat > "$conf" <<EOF
# Generato da install.sh — The Provisioner
MailTo = ${LOGWATCH_EMAIL}
MailFrom = ${SMTP_FROM}
Detail = ${LOGWATCH_DETAIL}
Range = ${LOGWATCH_RANGE}
Format = ${LOGWATCH_FORMAT}
EOF

  if logwatch_wants_all || [[ "$LOGWATCH_SERVICES" == "All" ]]; then
    echo "Service = All" >> "$conf"
    echo 'Service = "-zz-network"' >> "$conf"
    echo 'Service = "-zz-sys"' >> "$conf"
  else
    # Reset Service = All ereditato da /usr/share/logwatch/default.conf/logwatch.conf
    echo 'Service = ""' >> "$conf"
    local svc
    IFS=',' read -ra _lw_arr <<< "$LOGWATCH_SERVICES"
    for svc in "${_lw_arr[@]}"; do
      svc="$(echo "$svc" | xargs)"
      [[ -z "$svc" ]] && continue
      [[ "${svc,,}" == "all" ]] && continue
      if [[ "$svc" == -* ]]; then
        echo "Service = \"${svc}\"" >> "$conf"
      else
        echo "Service = ${svc}" >> "$conf"
      fi
    done
    grep -q '^Service =' "$conf" || echo "Service = sshd" >> "$conf"
  fi
}

verify_logwatch_config() {
  local err
  err="$(logwatch --output stdout --range Today --detail Low 2>&1)" || true
  if echo "$err" | grep -qi 'Wrong configuration entry for "Service"'; then
    die "Config Logwatch non valida (Service). Verifica /etc/logwatch/conf/logwatch.conf — non mischiare All con servizi specifici; il default in /usr/share/logwatch/default.conf/ imposta All."
  fi
  if echo "$err" | grep -qi 'error'; then
    warn "Logwatch segnala: $(echo "$err" | head -3 | tr '\n' ' ')"
  fi
}

cloud_firewall_reminder() {
  local ports="TCP/${UFW_SSH_PORT} (SSH)"
  is_yes "$INSTALL_UFW" && is_yes "$UFW_ALLOW_HTTP"  && ports+=", TCP/80"
  is_yes "$INSTALL_UFW" && is_yes "$UFW_ALLOW_HTTPS" && ports+=", TCP/443"
  is_yes "$INSTALL_PROFTPD" && ports+=", TCP/${PROFTPD_PORT}, TCP/${PROFTPD_PASSIVE_MIN}-${PROFTPD_PASSIVE_MAX} (FTP passive)"
  echo
  warn "════════════════════════════════════════════════════════════"
  warn "  FIREWALL CLOUD — apri le stesse porte del server:"
  warn "  ${ports}"
  case "${CLOUD_PROVIDER,,}" in
    aws|ec2)
      warn "  AWS: EC2 → Security Group → Inbound rules"
      ;;
    lightsail)
      warn "  Lightsail: Networking → Firewall → Add rule (TCP ${UFW_SSH_PORT})"
      ;;
    hetzner)
      warn "  Hetzner Cloud: Firewall → Inbound → TCP ${UFW_SSH_PORT}"
      ;;
    ovh)
      warn "  OVH: Network → IP → Firewall"
      ;;
    *)
      warn "  Provider: ${CLOUD_PROVIDER:-generico} — pannello firewall/security group"
      ;;
  esac
  warn "════════════════════════════════════════════════════════════"
  echo
}

prompt_ssh_connectivity_check() {
  is_yes "$INSTALL_UFW" || return 0
  local ip user cmd
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  user="${SSH_ALLOW_USERS:-root}"
  user="${user%%,*}"
  cmd="ssh -p ${UFW_SSH_PORT} ${user}@${ip:-<ip-server>}"
  echo
  warn "════════════════════════════════════════════════════════════"
  warn "  TEST SSH — apri una SECONDA sessione prima del reboot:"
  warn "  ${cmd}"
  warn "════════════════════════════════════════════════════════════"
  echo
  if nc -z 127.0.0.1 "$UFW_SSH_PORT" 2>/dev/null; then
    success "Porta ${UFW_SSH_PORT} in ascolto su localhost"
  else
    warn "Porta ${UFW_SSH_PORT} non raggiungibile su localhost"
  fi
  if [[ "$INTERACTIVE" == "yes" ]]; then
    if confirm "Hai verificato l'accesso SSH su una seconda sessione?" "n"; then
      SSH_PREFLIGHT_CONFIRMED=yes
    else
      SSH_PREFLIGHT_CONFIRMED=no
      warn "Accesso SSH non confermato — il reboot verrà bloccato in modalità interattiva"
    fi
  elif ! is_yes "$SSH_PREFLIGHT_CONFIRMED"; then
    warn "SSH_PREFLIGHT_CONFIRMED=no — reboot sconsigliato finché non testi SSH"
  fi
}

# Estrae blocco tra marker dal file install.sh (script embedded)
write_embedded_file() {
  local marker_start="$1" marker_end="$2" dest="$3" perm="${4:-755}"
  local src="$0"
  [[ -f "$src" ]] || die "Impossibile trovare sorgente embedded: $src"
  mkdir -p "$(dirname "$dest")"
  awk -v s="$marker_start" -v e="$marker_end" '$0==s{f=1;next}$0==e{f=0}f' "$src" > "$dest"
  [[ -s "$dest" ]] || die "Estrazione embedded fallita: ${marker_start} (marker non trovato in $src)"
  head -1 "$dest" | grep -q '^#!/' || die "Script embedded invalido: ${dest}"
  chmod "$perm" "$dest"
  info "Script estratto → ${dest} ($(wc -l < "$dest") righe)"
}

save_runtime_config() {
  mkdir -p "$MARKER_DIR"
  local dest="${MARKER_DIR}/runtime.env"
  {
    echo "# Generato da install.sh il $(date -Iseconds)"
    echo "# The Provisioner — Copyright (c) Carlo Savino — BSD-3-Clause"
    echo "VERSION=${VERSION}"
    echo "DEBIAN_MAJOR=${DEBIAN_MAJOR}"
    echo "DEBIAN_CODENAME=${DEBIAN_CODENAME}"
    echo "DEBIAN_SUITE=${DEBIAN_SUITE}"
    echo "DOCKER_APT_CODENAME=${DOCKER_APT_CODENAME}"
    echo "INSTALL_BUILD=${INSTALL_BUILD}"
    echo "INSTALL_UFW=${INSTALL_UFW}"
    echo "INSTALL_SMTP=${INSTALL_SMTP}"
    echo "INSTALL_DOCKER=${INSTALL_DOCKER}"
    echo "INSTALL_MONIT=${INSTALL_MONIT}"
    echo "INSTALL_LOGWATCH=${INSTALL_LOGWATCH}"
    echo "INSTALL_FAIL2BAN=${INSTALL_FAIL2BAN}"
    echo "INSTALL_SSH_HARDENING=${INSTALL_SSH_HARDENING}"
    echo "INSTALL_TIMEZONE=${INSTALL_TIMEZONE}"
    echo "INSTALL_PROFTPD=${INSTALL_PROFTPD}"
    echo "SYSTEM_TIMEZONE=${SYSTEM_TIMEZONE:-$(timedatectl show -pTimezone --value 2>/dev/null)}"
    echo "SMTP_HOST=${SMTP_HOST}"
    echo "SMTP_PORT=${SMTP_PORT}"
    echo "SMTP_TLS=${SMTP_TLS}"
    echo "SMTP_USER=${SMTP_USER}"
    echo "SMTP_FROM=${SMTP_FROM}"
    echo "POSTFIX_MAILNAME=${POSTFIX_MAILNAME}"
    echo "POSTFIX_LOOPBACK=${POSTFIX_LOOPBACK}"
    echo "UFW_SSH_PORT=${UFW_SSH_PORT}"
    echo "MONIT_ADMIN_EMAIL=${MONIT_ADMIN_EMAIL}"
    echo "LOGWATCH_EMAIL=${LOGWATCH_EMAIL}"
  } > "$dest"
  chmod 600 "$dest"
  info "Config runtime: ${dest}"
}

usage() {
  cat <<EOF
${BOLD}${PROVISIONER_NAME} v${VERSION}${NC}
Singolo file — by ${PROVISIONER_AUTHOR}
${PROVISIONER_EMAIL} — ${PROVISIONER_WEBSITE}
${PROVISIONER_REPO}

${BOLD}install.sh${NC} — debian-provision

${BOLD}USO:${NC}
  sudo bash install.sh
  sudo bash install.sh --non-interactive -y

${BOLD}OPZIONI:${NC}
  -h, --help              Aiuto
  -n, --non-interactive   Nessun prompt (usa env / default)
  -y, --yes               Salta conferma finale
  --only LIST             Solo moduli (es. ufw,smtp,monit,docker,proftpd)
  --skip base             Salta aggiornamento apt base

${BOLD}MODULI (--only):${NC}
  base, build, smtp, ufw, ssh_hardening, fail2ban, docker, timezone,
  proftpd, cron, monit, logwatch, ram_monitor, smart_monitor, boot_services

${BOLD}VARIABILI (esempio):${NC}
  CONFIG_FILE, MODULE_FORCE, PREFLIGHT_STRICT, CLOUD_PROVIDER
  INSTALL_BUILD, INSTALL_UFW, INSTALL_SMTP, INSTALL_DOCKER,
  INSTALL_MONIT, INSTALL_LOGWATCH, INSTALL_FAIL2BAN, INSTALL_SSH_HARDENING,
  INSTALL_TIMEZONE, INSTALL_PROFTPD  (yes/no/auto)
  SMTP_HOST, SMTP_PORT, SMTP_TLS, SMTP_USER, SMTP_PASSWORD, SMTP_PASSWORD_FILE
  SMTP_FROM, POSTFIX_MAILNAME, POSTFIX_LOOPBACK
  UFW_SSH_PORT, UFW_ALLOW_HTTP, UFW_ALLOW_HTTPS, UFW_EXTRA_PORTS, UFW_RULES_FILE
  MONIT_ADMIN_EMAIL, LOGWATCH_EMAIL, DOCKER_USERS
  SYSTEM_TIMEZONE, SSH_PERMIT_ROOT, SSH_PASSWORD_AUTH, SSH_ALLOW_USERS
  PROFTPD_PORT, PROFTPD_TLS, PROFTPD_USER, PROFTPD_PASSIVE_MIN, PROFTPD_PASSIVE_MAX
  PROFTPD_CHROOT, PROFTPD_MAX_CLIENTS, PROFTPD_MAX_INSTANCES
  LOGWATCH_SERVICES (auto — install/marker/OS, All, oppure sshd,postfix,... — una riga Service per servizio)
  MONIT_SERVICES (auto — install/marker/OS, oppure ssh,docker,postfix,...)
  ALLOW_REBOOT (yes/no/auto) — riavvio a fine provisioning
  SEND_INSTALL_REPORT (yes/no/auto) — email report finale (default: auto)
  INSTALL_REPORT_EMAIL — destinatario report (default: Monit/Logwatch/SMTP_FROM)
  SSH_PREFLIGHT_CONFIRMED (yes/no) — conferma test SSH pre-reboot
  DEBIAN_ALLOW_OLD (yes/no) — consente Debian < ${DEBIAN_MIN_MAJOR} (default: no)

${BOLD}DEBIAN SUPPORTATO:${NC}
  Minimo Debian ${DEBIAN_MIN_MAJOR} (Bullseye) — target: Bookworm 12, Trixie 13
  Rilevamento automatico codename, profilo Docker e ssh.socket

EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -n|--non-interactive) NON_INTERACTIVE=true; INTERACTIVE="no"; shift ;;
      -y|--yes) SKIP_CONFIRM=true; shift ;;
      --only)
        [[ $# -ge 2 ]] || die "Uso: --only ufw,smtp,monit,..."
        ONLY_MODULES="$(echo "$2" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
        shift 2
        ;;
      --skip)
        [[ $# -ge 2 ]] || die "Uso: --skip base"
        [[ "${2,,}" == "base" ]] && SKIP_BASE=true
        shift 2
        ;;
      *) die "Opzione sconosciuta: $1" ;;
    esac
  done
  load_config_file
  load_provisioner_state
}

# ─── APT / sistema base ───────────────────────────────────────────────────────

apt_update_system() {
  info "Aggiornamento indice pacchetti..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || die "apt-get update fallito"

  info "upgrade..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" upgrade || die "apt-get upgrade fallito"

  info "full-upgrade..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" full-upgrade || die "apt-get full-upgrade fallito"

  info "dist-upgrade..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" dist-upgrade || die "apt-get dist-upgrade fallito"

  info "Pulizia apt..."
  apt-get -y autoremove --purge || true
  apt-get -y autoclean || true
  apt-get -y clean || true
}

apt_install_core_packages() {
  apt-get -y install \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    wget vim nano less htop unzip zip bzip2 xz-utils jq git rsync \
    cron sudo fail2ban unattended-upgrades apt-listchanges dnsutils \
    tmux tree lsof psmisc software-properties-common bash-completion \
    netcat-openbsd sysstat acl openssl
}

apt_configure_unattended_upgrades() {
  [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] || \
    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true

  cat > /etc/apt/apt.conf.d/50unattended-upgrades-local <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
  systemctl enable unattended-upgrades 2>/dev/null || true
  systemctl restart unattended-upgrades 2>/dev/null || true
}

module_base() {
  mkdir -p "$MARKER_DIR"
  if is_yes "$SKIP_BASE"; then
    info "Skip aggiornamento base (--skip base)"
    return 0
  fi
  if [[ -n "$ONLY_MODULES" ]] && ! list_contains "$ONLY_MODULES" "base"; then
    return 0
  fi

  apt_update_system

  if is_module_done "base" && ! is_yes "$MODULE_FORCE"; then
    info "Pacchetti base già installati — skip reinstall (MODULE_FORCE=yes per forzare)."
    return 0
  fi

  apt_install_core_packages
  apt_configure_unattended_upgrades
  date -Iseconds > "$BASE_DONE_MARKER"
  mark_module_done "base"
  success "Sistema aggiornato e pacchetti base installati."
}

module_build_essential() {
  should_run_module "build" "INSTALL_BUILD" || return 0
  info "Installazione build-essential (gcc, make, ...)..."
  apt-get -y install build-essential pkg-config
  mark_module_done "build"
  success "build-essential installato."
}

# ─── SMTP / Postfix (smarthost relay) ─────────────────────────────────────────

smtp_is_enabled() {
  [[ -n "$SMTP_HOST" && -n "$SMTP_USER" && -n "$SMTP_PASSWORD" ]]
}

smtp_is_configured() {
  [[ -f "$SMTP_MARKER" ]]
}

prompt_smtp_config() {
  info "Configurazione Postfix relay verso smarthost esistente..."
  load_smtp_password
  prompt_var SMTP_HOST          "Server SMTP smarthost (hostname)" "$SMTP_HOST"
  prompt_var SMTP_PORT          "Porta (587=STARTTLS, 465=SSL)"    "${SMTP_PORT:-587}"
  prompt_var SMTP_TLS           "Crittografia (starttls, ssl, none)" "${SMTP_TLS:-starttls}"
  prompt_var SMTP_USER          "Username SMTP (autenticazione)"    "$SMTP_USER"
  prompt_var SMTP_PASSWORD      "Password SMTP"                     "" "yes"
  prompt_var SMTP_FROM          "Email mittente (From)"             "${SMTP_FROM:-$SMTP_USER}"
  prompt_var POSTFIX_MAILNAME   "Nome mail sistema (postfix mailname)" "${POSTFIX_MAILNAME:-$(hostname -f)}"
  prompt_yes_no POSTFIX_LOOPBACK "Postfix solo su localhost? (consigliato, relay-only)" "${POSTFIX_LOOPBACK:-yes}"

  [[ -n "$SMTP_HOST" && -n "$SMTP_USER" && -n "$SMTP_PASSWORD" ]] || \
    die "SMTP_HOST, SMTP_USER e SMTP_PASSWORD sono obbligatori."

  if [[ "$SMTP_PASSWORD" == *:* ]]; then
    warn "La password SMTP contiene ':' — Postfix sasl_passwd potrebbe non funzionare. Cambia password o carattere."
  fi
}

configure_postfix() {
  smtp_is_enabled || return 0
  if smtp_is_configured && ! is_yes "$MODULE_FORCE"; then
    info "Postfix già configurato, skip."
    return 0
  fi

  load_smtp_password
  info "Installazione e configurazione Postfix (relay smarthost)..."
  export DEBIAN_FRONTEND=noninteractive

  local mailname="${POSTFIX_MAILNAME:-$(hostname -f)}"
  local myorigin="${POSTFIX_MYORIGIN:-${SMTP_FROM#*@}}"
  local relayhost="[${SMTP_HOST}]:${SMTP_PORT}"
  local tls_level="encrypt"
  local wrappermode="no"
  local inet_interfaces="loopback-only"

  is_yes "$POSTFIX_LOOPBACK" || inet_interfaces="all"

  case "${SMTP_TLS,,}" in
    ssl)   wrappermode="yes" ;;
    none)  tls_level="none" ;;
  esac

  debconf-set-selections <<EOF
postfix postfix/mailname string ${mailname}
postfix postfix/main_mailer_type string Satellite system
EOF

  apt-get -y remove msmtp msmtp-mta 2>/dev/null || true
  apt-get -y install postfix libsasl2-modules libsasl2-modules-db mailutils

  [[ -f /etc/postfix/main.cf ]] && \
    cp /etc/postfix/main.cf "/etc/postfix/main.cf.bak.$(date +%s)"

  postconf -e "relayhost = ${relayhost}"
  postconf -e "smtp_sasl_auth_enable = yes"
  postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
  postconf -e "smtp_sasl_security_options = noanonymous"
  postconf -e "smtp_tls_security_level = ${tls_level}"
  postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
  postconf -e "smtp_tls_wrappermode = ${wrappermode}"
  postconf -e "inet_interfaces = ${inet_interfaces}"
  postconf -e "mydestination ="
  postconf -e "myhostname = ${mailname}"
  postconf -e "myorigin = ${myorigin}"
  postconf -e "sender_canonical_maps = hash:/etc/postfix/sender_canonical"

  write_postfix_sasl_passwd "$relayhost" "$SMTP_USER" "$SMTP_PASSWORD"

  cat > /etc/postfix/sender_canonical <<EOF
@${mailname}    ${SMTP_FROM}
root@${mailname}    ${SMTP_FROM}
@$(hostname -s)    ${SMTP_FROM}
root@$(hostname -s)    ${SMTP_FROM}
EOF
  postmap /etc/postfix/sender_canonical

  systemctl enable postfix
  systemctl restart postfix

  date -Iseconds > "$SMTP_MARKER"
  mark_module_done "smtp"
  success "Postfix relay → ${relayhost} (From: ${SMTP_FROM})"
  unset SMTP_PASSWORD
}

smtp_ensure_configured() {
  smtp_is_configured && return 0
  if smtp_is_enabled; then
    configure_postfix
    return 0
  fi
  if is_yes "$INSTALL_SMTP"; then
    prompt_smtp_config
    configure_postfix
  elif [[ "$INTERACTIVE" == "yes" ]] && confirm "Configurare Postfix relay (smarthost) per le notifiche?" "y"; then
    INSTALL_SMTP=yes
    prompt_smtp_config
    configure_postfix
  elif { is_yes "$INSTALL_MONIT" || is_yes "$INSTALL_LOGWATCH"; } && ! smtp_is_enabled; then
    warn "Monit/Logwatch senza Postfix relay: le email via localhost non verranno recapitate."
  fi
}

render_monit_mailserver() {
  if smtp_is_enabled || smtp_is_configured; then
    echo "set mailserver localhost port 25"
  else
    echo "set mailserver localhost"
  fi
}

smtp_send_test() {
  smtp_is_configured || smtp_is_enabled || { warn "Postfix relay non configurato."; return 0; }
  local to="${1:-$SMTP_FROM}"
  info "Invio email di test a ${to}..."
  if echo "Test debian-provision da $(hostname -f) — $(date)" \
    | mail -s "Test debian-provision" -r "${SMTP_FROM}" "$to" 2>/dev/null; then
    success "Email di test inviata via Postfix."
  else
    warn "Invio fallito. Controlla: journalctl -u postfix --no-pager -n 30"
  fi
}

module_smtp() {
  should_run_module "smtp" "INSTALL_SMTP" || return 0
  prompt_smtp_config
  configure_postfix
  if [[ "$INTERACTIVE" == "yes" ]] && confirm "Inviare email di test?" "n"; then
    prompt_var SMTP_TEST_EMAIL "Destinatario test" "${SMTP_FROM}"
    smtp_send_test "$SMTP_TEST_EMAIL"
  fi
}

# ─── UFW ──────────────────────────────────────────────────────────────────────

ufw_apply_port_entry() {
  local entry="$1" default_proto="${2:-tcp}" comment="${3:-Custom}"
  entry="$(echo "$entry" | xargs)"
  [[ -z "$entry" ]] && return 0
  [[ "${entry,,}" == "yes" || "${entry,,}" == "no" ]] && return 0

  local port proto
  if [[ "$entry" =~ ^([0-9]+)/(tcp|udp|both)$ ]]; then
    port="${BASH_REMATCH[1]}"; proto="${BASH_REMATCH[2]}"
  elif [[ "$entry" =~ ^([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"; proto="$default_proto"
  else
    warn "Porta non valida: ${entry}"
    return 0
  fi
  case "$proto" in
    tcp) ufw allow "${port}/tcp" comment "$comment" ;;
    udp) ufw allow "${port}/udp" comment "$comment" ;;
    both)
      ufw allow "${port}/tcp" comment "$comment"
      ufw allow "${port}/udp" comment "$comment"
      ;;
  esac
}

ufw_apply_port_list() {
  local port_csv="$1" default_proto="${2:-tcp}" comment="${3:-Custom}"
  [[ -n "$port_csv" ]] || return 0
  IFS=',' read -ra PORTS <<< "$port_csv"
  for p in "${PORTS[@]}"; do ufw_apply_port_entry "$p" "$default_proto" "$comment"; done
}

# Debian Bookworm+ usa ssh.socket (porta 22 via systemd) che ignora Port in sshd_config
# al reboot. Disabilitarlo e usare ssh.service garantisce persistenza della porta custom.
ensure_ssh_service_not_socket() {
  if [[ "$DEBIAN_SUPPORTS_SSH_SOCKET" != true ]]; then
    systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true
    return 0
  fi

  if ! systemctl list-unit-files ssh.socket &>/dev/null 2>&1; then
    systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true
    return 0
  fi

  if systemctl is-enabled ssh.socket &>/dev/null 2>&1; then
    info "Disabilitazione ssh.socket (Debian ${DEBIAN_MAJOR:-12}+ — persistenza porta SSH al reboot)..."
    systemctl disable --now ssh.socket 2>/dev/null || true
    systemctl stop ssh.socket 2>/dev/null || true
  fi

  systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true
}

warn_ssh_nonstandard_port() {
  local port="$1"
  [[ "$port" == "22" ]] && return 0
  echo
  warn "════════════════════════════════════════════════════════════"
  warn "  SSH NON è sulla porta 22 — porta configurata: ${port}"
  warn "  Connettiti con:  ssh -p ${port} utente@<ip-server>"
  warn "  Apri TCP/${port} anche nel firewall cloud (AWS/Lightsail/...)"
  warn "════════════════════════════════════════════════════════════"
  echo
}

sshd_configured_port() {
  local p
  p="$(grep -rhE '^[[:space:]]*Port[[:space:]]+' \
    /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null \
    | awk '{print $2}' | tail -1)"
  echo "${p:-22}"
}

sshd_listening_ports() {
  ss -tlnp 2>/dev/null | grep -E 'sshd|:ssh' | awk '{print $4}' | sed 's/.*://' | sort -un
}

ufw_allows_tcp_port() {
  local port="$1"
  ufw status 2>/dev/null | grep -qE "(^|[[:space:]])${port}/tcp[[:space:]]+ALLOW"
}

restart_sshd_service() {
  if systemctl restart ssh.service 2>/dev/null; then
    return 0
  fi
  if systemctl restart ssh 2>/dev/null; then
    return 0
  fi
  systemctl restart sshd.service 2>/dev/null || systemctl restart sshd 2>/dev/null
}

configure_ssh_port() {
  local port="$1"
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/99-debian-provision-port.conf <<EOF
# Generato da install.sh — ssh.service (non ssh.socket) per persistenza al reboot
Port ${port}
EOF

  if ! sshd -t 2>/dev/null; then
    warn "Validazione sshd fallita — porta non applicata"
    rm -f /etc/ssh/sshd_config.d/99-debian-provision-port.conf
    return 1
  fi

  ensure_ssh_service_not_socket
  restart_sshd_service || die "Impossibile riavviare ssh.service"

  if ! ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
    warn "sshd potrebbe non essere in ascolto su ${port} — verifica: ss -tlnp | grep ssh"
  else
    success "sshd → porta ${port} (ssh.service attivo, ssh.socket disabilitato)"
  fi

  warn_ssh_nonstandard_port "$port"
}

verify_ssh_ufw_alignment() {
  [[ -f /etc/ssh/sshd_config.d/99-debian-provision-port.conf ]] || return 0

  local expected="${UFW_SSH_PORT:-$(sshd_configured_port)}"
  local listening ok=true

  info "━━━ Verifica SSH / UFW (persistenza al reboot) ━━━"

  if systemctl is-enabled ssh.socket &>/dev/null 2>&1; then
    warn "ssh.socket ancora abilitato — correzione in corso..."
    ensure_ssh_service_not_socket
    restart_sshd_service || ok=false
  fi

  if ! systemctl is-enabled ssh.service &>/dev/null 2>&1 && \
     ! systemctl is-enabled sshd.service &>/dev/null 2>&1; then
    warn "ssh.service non abilitato al boot — abilitazione..."
    systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || ok=false
  fi

  listening="$(sshd_listening_ports | tr '\n' ' ' | xargs)"
  if [[ -z "$listening" ]] || ! grep -qw "$expected" <<< "$listening"; then
    warn "sshd non in ascolto su ${expected} (porte attive: ${listening:-nessuna})"
    ok=false
  else
    success "sshd in ascolto su porta ${expected}"
  fi

  if command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -qi "Status: active"; then
      if ufw_allows_tcp_port "$expected"; then
        success "UFW consente TCP/${expected}"
      else
        warn "UFW non consente TCP/${expected} — aggiungo regola..."
        ufw allow "${expected}/tcp" comment 'SSH (verify)' || ok=false
        ufw reload 2>/dev/null || true
      fi
    elif is_yes "$INSTALL_UFW"; then
      warn "UFW installato ma non attivo — esegui: ufw enable"
      ok=false
    fi
  fi

  if [[ "$expected" != "22" ]]; then
    warn_ssh_nonstandard_port "$expected"
  fi

  info "  ssh.service: $(systemctl is-enabled ssh.service 2>/dev/null || systemctl is-enabled sshd.service 2>/dev/null || echo 'unknown')"
  info "  ssh.socket:  $(systemctl is-enabled ssh.socket 2>/dev/null || echo 'disabled/missing')"
  info "  Connessione:   ssh -p ${expected} utente@$(hostname -I 2>/dev/null | awk '{print $1}')"
  warn "  Firewall cloud: apri TCP/${expected} nel Security Group / Lightsail"

  if [[ "$ok" == true ]]; then
    success "SSH pronto per il reboot (porta ${expected})"
  else
    warn "Verifica SSH incompleta — non chiudere questa sessione finché non hai testato la connessione"
  fi
}

# Incolla comandi ufw (es. allow 8080/tcp comment 'App')
ufw_import_paste_commands() {
  info "Incolla comandi ufw (uno per riga). Riga vuota o 'END' per terminare:"
  local line count=0
  while IFS= read -r line; do
    [[ -z "$line" || "${line^^}" == "END" ]] && break
    line="${line#ufw }"
    line="${line#UFW }"
    if [[ "$line" =~ ^(allow|deny|reject|limit|delete)[[:space:]] ]]; then
      if [[ "$line" =~ [\;\|\&\$\(\)\`\\] ]]; then
        warn "Ignorato (caratteri non permessi): ${line}"
        continue
      fi
      info "  → ufw ${line}"
      # shellcheck disable=SC2086
      ufw $line || warn "Comando fallito: ufw ${line}"
      ((count++)) || true
    else
      warn "Ignorato (formato atteso: allow PORTA/proto ...): ${line}"
    fi
  done
  success "${count} regole ufw applicate."
}

# Incolla fragmento iptables per user.rules (prima di ufw enable)
ufw_import_paste_user_rules() {
  local tmp="${MARKER_DIR}/user.rules.import"
  mkdir -p "$MARKER_DIR"
  info "Incolla il fragmento per /etc/ufw/user.rules."
  info "Termina con una riga contenente solo: END"
  : > "$tmp"
  local line
  while IFS= read -r line; do
    [[ "${line^^}" == "END" ]] && break
    echo "$line" >> "$tmp"
  done

  [[ -s "$tmp" ]] || { warn "Nessuna riga incollata."; return 0; }

  if [[ -f /etc/ufw/user.rules ]]; then
    cp -a /etc/ufw/user.rules "/etc/ufw/user.rules.bak.$(date +%s)"
  fi

  warn "Attenzione: sostituire user.rules rimuove le regole ufw appena create (SSH, HTTP, ...)."
  if confirm "Sostituire completamente /etc/ufw/user.rules?" "n"; then
    cp "$tmp" /etc/ufw/user.rules
    info "user.rules sostituito."
  else
    info "Append del fragmento a user.rules..."
    cat "$tmp" >> /etc/ufw/user.rules
  fi
  rm -f "$tmp"
  success "Fragmento user.rules importato."
}

# Import da file locale già presente sulla macchina
ufw_import_from_file() {
  local src=""
  if [[ "$INTERACTIVE" == "yes" ]]; then
    read -rp "Percorso file regole (user.rules o comandi ufw, uno per riga): " src
  else
    src="${UFW_RULES_FILE:-}"
  fi
  [[ -n "$src" && -f "$src" ]] || die "File non trovato: ${src:-<vuoto>}"

  if grep -qE '^\*(filter|nat|mangle)' "$src" 2>/dev/null || \
     grep -qE '^:[A-Z0-9_-]+ ' "$src" 2>/dev/null; then
    cp -a /etc/ufw/user.rules "/etc/ufw/user.rules.bak.$(date +%s)" 2>/dev/null || true
    if confirm "Il file sembra iptables-save. Sostituire user.rules?" "n"; then
      cp "$src" /etc/ufw/user.rules
      success "user.rules importato da ${src}"
    else
      cat "$src" >> /etc/ufw/user.rules
      success "Fragmento append da ${src}"
    fi
  else
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      line="${line#ufw }"; line="${line#UFW }"
      [[ "$line" =~ ^(allow|deny|reject|limit|delete)[[:space:]] ]] && ufw $line || true
    done < "$src"
    success "Comandi ufw importati da ${src}"
  fi
}

ufw_import_custom_rules() {
  # Non interattivo: import automatico se UFW_RULES_FILE è impostato
  if [[ "$INTERACTIVE" != "yes" ]]; then
    [[ -n "${UFW_RULES_FILE:-}" ]] && ufw_import_from_file
    return 0
  fi
  confirm "Importare regole UFW aggiuntive (incolla o file)?" "n" || return 0

  echo
  echo "  1) Incolla comandi ufw (allow/deny/limit ...)"
  echo "  2) Incolla fragmento /etc/ufw/user.rules (iptables-save)"
  echo "  3) Importa da file locale già presente"
  echo "  4) Salta"
  local choice=""
  read -rp "Scelta [4]: " choice
  choice="${choice:-4}"
  case "$choice" in
    1) ufw_import_paste_commands ;;
    2) ufw_import_paste_user_rules ;;
    3) ufw_import_from_file ;;
    *) info "Import regole saltato." ;;
  esac
}

module_ufw() {
  should_run_module "ufw" "INSTALL_UFW" || return 0
  apt-get -y install ufw

  prompt_var UFW_SSH_PORT "Porta SSH" "${UFW_SSH_PORT}"
  prompt_yes_no UFW_ALLOW_HTTP  "Consentire HTTP (80)?" "${UFW_ALLOW_HTTP:-yes}"
  prompt_yes_no UFW_ALLOW_HTTPS "Consentire HTTPS (443)?" "${UFW_ALLOW_HTTPS:-yes}"

  if [[ "$INTERACTIVE" == "yes" && -z "$UFW_EXTRA_PORTS" ]]; then
    read -rp "Porte TCP extra (es. 8080,9000 — Invio per nessuna): " UFW_EXTRA_PORTS
  fi
  if [[ "$INTERACTIVE" == "yes" && -z "$UFW_EXTRA_UDP_PORTS" ]]; then
    read -rp "Porte UDP extra (Invio per nessuna): " UFW_EXTRA_UDP_PORTS
  fi

  configure_ssh_port "$UFW_SSH_PORT"

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${UFW_SSH_PORT}/tcp" comment 'SSH'
  is_yes "$UFW_ALLOW_HTTP"  && ufw allow 80/tcp comment 'HTTP'  || true
  is_yes "$UFW_ALLOW_HTTPS" && ufw allow 443/tcp comment 'HTTPS' || true
  ufw_apply_port_list "$UFW_EXTRA_PORTS" "tcp" "Custom"
  ufw_apply_port_list "$UFW_EXTRA_UDP_PORTS" "udp" "Custom UDP"

  ufw_import_custom_rules

  if confirm "Abilitare UFW ora?" "y"; then
    ufw --force enable
    ufw status verbose
    success "UFW attivo."
  else
    warn "UFW configurato ma non abilitato. Esegui: ufw enable"
  fi

  mark_module_done "ufw"
  cloud_firewall_reminder
}

# ─── SSH hardening ────────────────────────────────────────────────────────────

module_ssh_hardening() {
  should_run_module "ssh_hardening" "INSTALL_SSH_HARDENING" || return 0

  if [[ "$INTERACTIVE" == "yes" ]]; then
    prompt_var SSH_PERMIT_ROOT "PermitRootLogin (no, prohibit-password, yes)" "${SSH_PERMIT_ROOT:-prohibit-password}"
    prompt_yes_no SSH_PASSWORD_AUTH "Consentire autenticazione password?" "${SSH_PASSWORD_AUTH:-yes}"
    prompt_var SSH_MAX_AUTH_TRIES "MaxAuthTries" "${SSH_MAX_AUTH_TRIES:-5}"
    read -rp "AllowUsers (virgola, Invio=nessuno): " SSH_ALLOW_USERS
  fi

  if ! is_yes "$SSH_PASSWORD_AUTH"; then
    local u keyok=false
    for u in root ${SSH_ALLOW_USERS//,/ }; do
      u="$(echo "$u" | xargs)"
      [[ -z "$u" ]] && continue
      [[ -f "/home/${u}/.ssh/authorized_keys" || -f "/root/.ssh/authorized_keys" ]] && keyok=true
      [[ "$u" == "root" && -f /root/.ssh/authorized_keys ]] && keyok=true
    done
    [[ -f /root/.ssh/authorized_keys ]] && keyok=true
    [[ "$keyok" == true ]] || die "PasswordAuthentication=no richiede chiavi SSH in authorized_keys"
  fi

  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/99-debian-provision-hardening.conf <<EOF
# The Provisioner — Copyright (c) Carlo Savino — BSD-3-Clause
PermitRootLogin ${SSH_PERMIT_ROOT}
PasswordAuthentication $(is_yes "$SSH_PASSWORD_AUTH" && echo yes || echo no)
MaxAuthTries ${SSH_MAX_AUTH_TRIES}
EOF
  if [[ -n "$SSH_ALLOW_USERS" ]]; then
    echo "AllowUsers ${SSH_ALLOW_USERS//,/ }" >> /etc/ssh/sshd_config.d/99-debian-provision-hardening.conf
  fi

  sshd -t || die "Config SSH hardening non valida"
  restart_sshd_service || die "Reload sshd fallito dopo hardening"
  mark_module_done "ssh_hardening"
  success "SSH hardening applicato → /etc/ssh/sshd_config.d/99-debian-provision-hardening.conf"
}

# ─── Fail2ban ─────────────────────────────────────────────────────────────────

module_fail2ban() {
  should_run_module "fail2ban" "INSTALL_FAIL2BAN" || return 0

  apt-get -y install fail2ban
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/the-provisioner.local <<EOF
# The Provisioner — Copyright (c) Carlo Savino — BSD-3-Clause
[sshd]
enabled = true
port = ${UFW_SSH_PORT}
maxretry = 5
bantime = 3600
findtime = 600
EOF
  if is_yes "$INSTALL_PROFTPD"; then
    cat >> /etc/fail2ban/jail.d/the-provisioner.local <<EOF

[proftpd]
enabled = true
port = ${PROFTPD_PORT}
maxretry = 5
bantime = 3600
EOF
  fi

  systemctl enable fail2ban
  systemctl restart fail2ban
  mark_module_done "fail2ban"
  success "Fail2ban configurato → /etc/fail2ban/jail.d/the-provisioner.local"
}

# ─── Timezone ─────────────────────────────────────────────────────────────────

module_timezone() {
  should_run_module "timezone" "INSTALL_TIMEZONE" || return 0

  local tz="${SYSTEM_TIMEZONE:-}"
  if [[ -z "$tz" ]]; then
    if [[ "$INTERACTIVE" == "yes" ]]; then
      prompt_var SYSTEM_TIMEZONE "Timezone (IANA, es. Europe/Rome)" "Europe/Rome"
      tz="$SYSTEM_TIMEZONE"
    else
      tz="Europe/Rome"
      SYSTEM_TIMEZONE="$tz"
    fi
  fi

  [[ -f "/usr/share/zoneinfo/${tz}" ]] || die "Timezone non valida: ${tz}"
  timedatectl set-timezone "$tz"
  mark_module_done "timezone"
  success "Timezone → ${tz}"
}

# ─── ProFTPd ──────────────────────────────────────────────────────────────────

prompt_proftpd_config() {
  info "Configurazione ProFTPd (minimo consigliato):"
  prompt_var PROFTPD_PORT "Porta controllo FTP" "${PROFTPD_PORT:-21}"
  prompt_var_force PROFTPD_USER "Utente UNIX dedicato FTP" "${PROFTPD_USER:-ftpuser}"
  prompt_yes_no PROFTPD_CHROOT "Limitare utente alla propria home (DefaultRoot, consigliato)?" "${PROFTPD_CHROOT:-yes}"
  prompt_yes_no PROFTPD_TLS "Abilitare TLS / FTPS esplicito?" "${PROFTPD_TLS:-yes}"
  prompt_var PROFTPD_PASSIVE_MIN "Porta passive min (range dati)" "${PROFTPD_PASSIVE_MIN:-40000}"
  prompt_var PROFTPD_PASSIVE_MAX "Porta passive max (range dati)" "${PROFTPD_PASSIVE_MAX:-40100}"
  prompt_var PROFTPD_MAX_CLIENTS "Max client FTP contemporanei" "${PROFTPD_MAX_CLIENTS:-10}"
  prompt_var PROFTPD_MAX_INSTANCES "Max istanze ProFTPd" "${PROFTPD_MAX_INSTANCES:-30}"
  prompt_yes_no PROFTPD_ALLOW_ANONYMOUS "Consentire FTP anonimo? (sconsigliato)" "no"
  echo
  info "Riepilogo ProFTPd:"
  info "  Utente: ${PROFTPD_USER:-ftpuser} | Porta: ${PROFTPD_PORT} | TLS: ${PROFTPD_TLS}"
  info "  Passive: ${PROFTPD_PASSIVE_MIN}-${PROFTPD_PASSIVE_MAX} | Chroot home: ${PROFTPD_CHROOT}"
  is_yes "$INSTALL_UFW" && info "  UFW: verranno aperti porta ${PROFTPD_PORT} e range passive"
}

module_proftpd() {
  should_run_module "proftpd" "INSTALL_PROFTPD" || return 0

  apt-get -y install proftpd-core proftpd-mod-crypto ssl-cert || \
    apt-get -y install proftpd-basic proftpd-mod-crypto ssl-cert || \
    die "Installazione ProFTPd fallita"

  if [[ "$INTERACTIVE" == "yes" ]]; then
    prompt_proftpd_config
  else
    is_yes "${PROFTPD_TLS:-auto}" && PROFTPD_TLS=yes || true
    [[ -n "$PROFTPD_USER" ]] || PROFTPD_USER="ftpuser"
  fi

  [[ -n "$PROFTPD_USER" ]] || PROFTPD_USER="ftpuser"
  id "$PROFTPD_USER" &>/dev/null || useradd -m -s /usr/sbin/nologin "$PROFTPD_USER"

  local tls_lines="" chroot_line=""
  if is_yes "$PROFTPD_TLS"; then
    tls_lines="
  <IfModule mod_tls.c>
    TLSEngine on
    TLSRequired off
    TLSProtocol TLSv1.2 TLSv1.3
    TLSRSACertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
    TLSRSACertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
  </IfModule>"
  fi
  is_yes "$PROFTPD_CHROOT" && chroot_line="  DefaultRoot ~"

  cat > /etc/proftpd/conf.d/the-provisioner.conf <<EOF
# The Provisioner — Copyright (c) Carlo Savino — BSD-3-Clause
<Global>
  Port ${PROFTPD_PORT}
  PassivePorts ${PROFTPD_PASSIVE_MIN} ${PROFTPD_PASSIVE_MAX}
  MaxClients ${PROFTPD_MAX_CLIENTS}
  MaxInstances ${PROFTPD_MAX_INSTANCES}
${chroot_line}
</Global>
<Limit LOGIN>
  AllowUser ${PROFTPD_USER}
  DenyAll
</Limit>
${tls_lines}
EOF

  proftpd -t 2>/dev/null || proftpd -t -d 5 || warn "Validazione proftpd non disponibile"
  systemctl enable proftpd
  systemctl restart proftpd

  if is_yes "$INSTALL_UFW"; then
    ufw allow "${PROFTPD_PORT}/tcp" comment 'ProFTPd' 2>/dev/null || true
    ufw allow "${PROFTPD_PASSIVE_MIN}:${PROFTPD_PASSIVE_MAX}/tcp" comment 'ProFTPd passive' 2>/dev/null || true
  fi

  mark_module_done "proftpd"
  success "ProFTPd → /etc/proftpd/conf.d/the-provisioner.conf (utente: ${PROFTPD_USER})"
  if [[ "$INTERACTIVE" == "yes" ]] && confirm "Impostare ora la password per ${PROFTPD_USER}?" "y"; then
    passwd "$PROFTPD_USER" || warn "passwd non completato — esegui: passwd ${PROFTPD_USER}"
  else
    warn "Imposta password: passwd ${PROFTPD_USER}"
  fi
  cloud_firewall_reminder
}

# ─── Docker ───────────────────────────────────────────────────────────────────

docker_codename_for_repo() {
  if [[ -n "${DOCKER_APT_CODENAME:-}" ]]; then
    echo "$DOCKER_APT_CODENAME"
    return 0
  fi
  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  case "$codename" in
    trixie|sid|forky|testing|unstable)
      warn "Docker CE ufficiale non supporta '${codename}' — uso repo bookworm."
      echo "bookworm"
      ;;
    *) echo "$codename" ;;
  esac
}

module_docker() {
  should_run_module "docker" "INSTALL_DOCKER" || return 0
  info "Installazione Docker Engine (ecosistema completo)..."
  apt-get -y install gnupg ca-certificates curl apt-transport-https || \
    die "Impossibile installare dipendenze Docker (gnupg, curl, ...)"

  command -v gpg >/dev/null 2>&1 || die "gpg non disponibile dopo installazione gnupg"

  prompt_yes_no DOCKER_INSTALL_COMPOSE "Installare Docker Compose plugin?" "yes"
  prompt_var DOCKER_USERS "Utenti gruppo docker (virgola, vuoto=nessuno)" "${DOCKER_USERS:-}"
  prompt_yes_no INSTALL_BASH_ALIASES "Aggiungere alias bash (ll, dc)?" "yes"

  local docker_codename installed=false
  docker_codename="$(docker_codename_for_repo)"

  apt-get -y remove docker docker-engine docker.io containerd runc 2>/dev/null || true
  install -m 0755 -d /etc/apt/keyrings
  rm -f /etc/apt/keyrings/docker.gpg /etc/apt/sources.list.d/docker.list

  if curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${docker_codename} stable" \
      > /etc/apt/sources.list.d/docker.list

    if apt-get update -qq 2>/dev/null; then
      if apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin; then
        is_yes "$DOCKER_INSTALL_COMPOSE" && apt-get -y install docker-compose-plugin || true
        installed=true
      fi
    fi
  fi

  if [[ "$installed" != true ]]; then
    warn "Repository Docker CE non disponibile — fallback su docker.io (Debian)."
    rm -f /etc/apt/sources.list.d/docker.list
    apt-get update -qq || die "apt-get update fallito (post-Docker)"
    apt-get -y install docker.io || die "Installazione docker.io fallita"
    is_yes "$DOCKER_INSTALL_COMPOSE" && \
      (apt-get -y install docker-compose-plugin 2>/dev/null || \
       apt-get -y install docker-compose-v2 2>/dev/null || \
       apt-get -y install docker-compose 2>/dev/null || \
       warn "Compose non installato — installa manualmente se serve") || true
  fi

  systemctl enable docker 2>/dev/null || die "Unit docker.service non trovata — installazione incompleta"
  systemctl start docker  2>/dev/null || die "Avvio docker.service fallito"
  command -v docker >/dev/null 2>&1 || die "Comando docker non trovato — installazione fallita"

  if [[ -n "$DOCKER_USERS" ]]; then
    IFS=',' read -ra USERS <<< "$DOCKER_USERS"
    for u in "${USERS[@]}"; do
      u="$(echo "$u" | xargs)"
      if id "$u" &>/dev/null; then
        usermod -aG docker "$u"
        info "Utente '${u}' → gruppo docker (riavvia sessione SSH)"
      else
        warn "Utente '${u}' inesistente."
      fi
    done
  fi

  is_yes "$INSTALL_BASH_ALIASES" && configure_bash_aliases yes || true
  docker --version
  mark_module_done "docker"
  success "Docker installato e attivo."
}

configure_bash_aliases() {
  local with_docker="${1:-no}"
  local f="/etc/profile.d/debian-provision-aliases.sh"
  cat > "$f" <<'EOF'
# Alias — generati da install.sh
alias ll='ls -la'
EOF
  if [[ "$with_docker" == "yes" ]] && command -v docker >/dev/null 2>&1; then
    echo "alias dc='docker ps -a'" >> "$f"
  fi
  chmod 644 "$f"

  prompt_yes_no INSTALL_BASHRC_ALIASES "Aggiungere alias a /root/.bashrc (ogni login SSH)?" "yes"
  if is_yes "$INSTALL_BASHRC_ALIASES"; then
    install_bashrc_aliases
  fi

  # shellcheck source=/dev/null
  source "$f" 2>/dev/null || true
  info "Alias attivi in questa sessione (ll$( [[ "$with_docker" == yes ]] && echo ', dc'))"

  if [[ "$with_docker" == "yes" ]]; then
    success "Alias → ${f} + sessione corrente (ll, dc)"
  else
    success "Alias → ${f} + sessione corrente (ll)"
  fi
}

install_bashrc_aliases() {
  local bashrc="/root/.bashrc"
  local marker="# debian-provision aliases"
  [[ -f "$bashrc" ]] || touch "$bashrc"
  if ! grep -qF "$marker" "$bashrc" 2>/dev/null; then
    cat >> "$bashrc" <<'EOF'

# debian-provision aliases
if [[ -f /etc/profile.d/debian-provision-aliases.sh ]]; then
  source /etc/profile.d/debian-provision-aliases.sh
fi
EOF
    success "Alias aggiunti a ${bashrc} (caricati ad ogni login)"
  else
    info "Alias già presenti in ${bashrc}"
  fi
}

module_ensure_boot_services() {
  should_run_module "boot_services" "INSTALL_BOOT_SERVICES" || return 0
  info "Abilitazione servizi al boot..."
  for svc in cron postfix; do
    systemctl enable "$svc" 2>/dev/null || true
    systemctl start  "$svc" 2>/dev/null || true
  done
  is_yes "$INSTALL_MONIT" && systemctl enable monit 2>/dev/null && systemctl start monit 2>/dev/null || true
  is_yes "$INSTALL_FAIL2BAN" && systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null || true
  is_yes "$INSTALL_PROFTPD" && systemctl enable proftpd 2>/dev/null && systemctl start proftpd 2>/dev/null || true
  systemctl is-enabled cron >/dev/null 2>&1 && info "cron: abilitato al boot" || warn "cron: non abilitato"
  is_yes "$INSTALL_MONIT" && systemctl is-enabled monit >/dev/null 2>&1 && info "monit: abilitato al boot" || true
  [[ -f /etc/cron.d/logwatch ]]           && info "logwatch: /etc/cron.d/logwatch"
  [[ -f /etc/cron.d/ram-usage-monitor ]]  && info "ram monitor: cron ogni 5 min"
  [[ -f /etc/cron.d/smart-monitor ]]      && info "smart monitor: cron giornaliero"
  mark_module_done "boot_services"
  success "Servizi monitoraggio → avvio automatico via systemd/cron."
}

verify_postfix_for_mail() {
  smtp_is_configured || die "Postfix non configurato — necessario per email Monit/Logwatch/monitor."
  systemctl is-active postfix >/dev/null 2>&1 || die "Postfix non attivo — esegui: systemctl start postfix"
  command -v sendmail >/dev/null 2>&1 || apt-get -y install mailutils
}

show_mail_architecture() {
  info "Architettura email:"
  info "  Postfix localhost:25 → smarthost ${SMTP_HOST}:${SMTP_PORT}"
  info "  Monit/Logwatch: solo email destinatario (NON smarthost nelle loro config)"
}

test_notification_mail() {
  local to="${1:-${MONIT_ADMIN_EMAIL:-${LOGWATCH_EMAIL:-$SMTP_FROM}}}"
  [[ -n "$to" ]] || return 0
  verify_postfix_for_mail
  info "Test email a ${to}..."
  if echo "Test notifiche da $(hostname -f) — $(date)" \
    | mail -s "[install.sh] Test notifiche" -r "${SMTP_FROM:-$SMTP_USER}" "$to" 2>/dev/null; then
    success "Email di test inviata a ${to}"
  else
    warn "Test email fallito — journalctl -u postfix -n 30"
  fi
}

install_report_recipient() {
  echo "${INSTALL_REPORT_EMAIL:-${MONIT_ADMIN_EMAIL:-${LOGWATCH_EMAIL:-${SMTP_FROM:-}}}}"
}

install_report_should_send() {
  case "${SEND_INSTALL_REPORT,,}" in
    yes|y|1|true)  return 0 ;;
    no|n|0|false)  return 1 ;;
    auto)          smtp_is_configured || smtp_is_enabled ;;
    *)             return 1 ;;
  esac
}

install_report_status_label() {
  local code="${1:-0}"
  if [[ "$code" -ne 0 ]]; then
    echo "INTERROTTO — ERRORI CRITICI"
  elif [[ "$PROVISION_ERROR_COUNT" -gt 0 ]]; then
    echo "COMPLETATO CON ERRORI"
  elif [[ "$PROVISION_WARN_COUNT" -gt 0 ]]; then
    echo "COMPLETATO CON AVVISI"
  else
    echo "SUCCESSO"
  fi
}

build_install_report_body() {
  local code="${1:-0}" status host ip elapsed
  status="$(install_report_status_label "$code")"
  host="$(hostname -f 2>/dev/null || hostname)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  elapsed="${PROVISION_ELAPSED:-0}"

  cat <<EOF
Report provisioning ${PROVISIONER_NAME} v${VERSION}
by ${PROVISIONER_AUTHOR}
${PROVISIONER_EMAIL} — ${PROVISIONER_WEBSITE}
${PROVISIONER_REPO}
==========================================

Stato:       ${status}
Host:        ${host}
IP:          ${ip:-n/d}
Debian:      ${DEBIAN_PRETTY:-Debian} (${DEBIAN_CODENAME:-?})
Durata:      ${elapsed}s
Exit code:   ${code}
Data:        $(date -Iseconds)

Componenti installati
---------------------
  Base apt:        ${INSTALL_BASE}
  build-essential: ${INSTALL_BUILD}
  UFW:             ${INSTALL_UFW}
  Postfix relay:   ${INSTALL_SMTP}
  Docker:          ${INSTALL_DOCKER}
  Cron:            ${INSTALL_CRON}
  Monit:           ${INSTALL_MONIT}
  Logwatch:        ${INSTALL_LOGWATCH}
  Monitor RAM:     ${INSTALL_RAM_MONITOR}
  Monitor SMART:   ${INSTALL_SMART_MONITOR}
  SSH hardening:   ${INSTALL_SSH_HARDENING}
  Fail2ban:        ${INSTALL_FAIL2BAN}
  Timezone:        ${INSTALL_TIMEZONE}${SYSTEM_TIMEZONE:+ (${SYSTEM_TIMEZONE})}
  ProFTPd:         ${INSTALL_PROFTPD}
  Boot services:   ${INSTALL_BOOT_SERVICES}

Riepilogo
---------
  Errori:  ${PROVISION_ERROR_COUNT}
  Avvisi:  ${PROVISION_WARN_COUNT}
EOF

  if ((${#PROVISION_ERRORS[@]} > 0)); then
    echo
    echo "Errori rilevati"
    echo "--------------"
    local i=1 m
    for m in "${PROVISION_ERRORS[@]}"; do
      echo "  ${i}. ${m}"
      ((i++)) || true
    done
    [[ "$PROVISION_ERROR_COUNT" -gt "${#PROVISION_ERRORS[@]}" ]] && \
      echo "  ... e altri $((PROVISION_ERROR_COUNT - ${#PROVISION_ERRORS[@]})) errori (vedi log)"
  fi

  if ((${#PROVISION_WARNINGS[@]} > 0)); then
    echo
    echo "Avvisi rilevati"
    echo "--------------"
    local i=1 m
    for m in "${PROVISION_WARNINGS[@]}"; do
      echo "  ${i}. ${m}"
      ((i++)) || true
    done
    [[ "$PROVISION_WARN_COUNT" -gt "${#PROVISION_WARNINGS[@]}" ]] && \
      echo "  ... e altri $((PROVISION_WARN_COUNT - ${#PROVISION_WARNINGS[@]})) avvisi (vedi log)"
  fi

  cat <<EOF

Riferimenti
-----------
  Log:    ${LOG_FILE}
  Config: ${MARKER_DIR}/runtime.env
EOF

  is_yes "$INSTALL_UFW" && echo "  SSH:    porta ${UFW_SSH_PORT} (ufw + ssh.service)"
  is_yes "$INSTALL_MONIT" && echo "  Monit:  /etc/monit/monitrc"
  is_yes "$INSTALL_LOGWATCH" && echo "  Logwatch: /etc/logwatch/conf/logwatch.conf"
  is_yes "$INSTALL_FAIL2BAN" && echo "  Fail2ban: /etc/fail2ban/jail.d/the-provisioner.local"
  is_yes "$INSTALL_PROFTPD" && echo "  ProFTPd:  /etc/proftpd/conf.d/the-provisioner.conf (utente: ${PROFTPD_USER:-?})"

  echo
  echo "--"
  echo "${PROVISIONER_NAME} by ${PROVISIONER_AUTHOR}"
  echo "${PROVISIONER_EMAIL} — ${PROVISIONER_WEBSITE}"
  echo "${PROVISIONER_REPO}"
  echo "Copyright (c) Carlo Savino — BSD 3-Clause License"
  echo "Generato automaticamente da install.sh"
}

send_install_report() {
  local code="${1:-0}" to subject status body from_addr
  PROVISION_REPORT_SENT=true

  if ! install_report_should_send; then
    info "Report email finale saltato (SEND_INSTALL_REPORT=${SEND_INSTALL_REPORT})"
    return 0
  fi

  to="$(install_report_recipient)"
  [[ -n "$to" ]] || {
    warn "Report email saltato — imposta INSTALL_REPORT_EMAIL o MONIT_ADMIN_EMAIL"
    return 0
  }

  if ! smtp_is_configured && ! smtp_is_enabled; then
    warn "Report email saltato — Postfix non configurato"
    return 0
  fi

  verify_postfix_for_mail 2>/dev/null || {
    warn "Report email saltato — Postfix non attivo"
    return 0
  }

  status="$(install_report_status_label "$code")"
  subject="[install.sh] Provisioning: ${status} — $(hostname -s 2>/dev/null || echo server)"
  body="$(build_install_report_body "$code")"
  from_addr="${SMTP_FROM:-${SMTP_USER:-root@$(hostname -f)}}"

  info "Invio report finale a ${to}..."
  if printf '%s\n' "$body" | mail -s "$subject" -r "$from_addr" "$to" 2>/dev/null; then
    success "Report email inviato a ${to}"
  else
    warn "Invio report email fallito — controlla Postfix: journalctl -u postfix -n 30"
  fi
}

provision_on_exit() {
  local code=$?
  [[ "$PROVISION_ACTIVE" == true ]] || return 0
  PROVISION_EXIT_CODE=$code
  [[ "$PROVISION_REPORT_SENT" == true ]] && return 0
  if [[ "$code" -ne 0 ]]; then
    ((PROVISION_ERROR_COUNT++)) || true
    if ((${#PROVISION_ERRORS[@]} < PROVISION_REPORT_MAX_ITEMS)); then
      PROVISION_ERRORS+=("Script terminato con codice uscita ${code}")
    fi
  fi
  send_install_report "$code"
}

module_cron() {
  should_run_module "cron" "INSTALL_CRON" || return 0
  apt-get -y install cron
  systemctl enable cron
  systemctl start cron
  mark_module_done "cron"
  success "Cron installato e attivo."
}

# Configurazione mail obbligatoria se Monit/Logwatch/monitor attivi
prompt_notifications_mail() {
  info "━━━ Configurazione notifiche email (Postfix smarthost) ━━━"
  if ! smtp_is_configured; then
    if [[ "$INTERACTIVE" == "yes" ]]; then
      confirm "Configurare Postfix relay verso smarthost?" "y" || \
        die "SMTP obbligatorio per Monit/Logwatch/monitor — configura Postfix o annulla."
      prompt_smtp_config
      configure_postfix
    elif ! smtp_is_enabled; then
      die "SMTP richiesto: imposta SMTP_HOST, SMTP_USER, SMTP_PASSWORD e INSTALL_SMTP=yes"
    else
      configure_postfix
    fi
  fi
  prompt_var SMTP_FROM "Email mittente (From) per notifiche" "${SMTP_FROM:-$SMTP_USER}"
  if [[ -z "${MONIT_ADMIN_EMAIL:-}" ]]; then
    prompt_var MONIT_ADMIN_EMAIL "Email destinatario alert (Monit/monitor)" "${SMTP_FROM:-root@localhost}"
  fi
  if [[ -z "${LOGWATCH_EMAIL:-}" ]]; then
    prompt_var LOGWATCH_EMAIL "Email destinatario report Logwatch" "${MONIT_ADMIN_EMAIL:-${SMTP_FROM:-root@localhost}}"
  fi
}

# ─── Monit ────────────────────────────────────────────────────────────────────

module_monit() {
  should_run_module "monit" "INSTALL_MONIT" || return 0
  apt-get -y install monit
  verify_postfix_for_mail
  show_mail_architecture

  resolve_monit_services
  info "Configurazione Monit:"
  info "  (1) email destinatario alert  (2) servizi da monitorare"
  info "  Il mail server è Postfix locale — già configurato con smarthost."
  prompt_var_force MONIT_ADMIN_EMAIL    "Email destinatario notifiche Monit" "${MONIT_ADMIN_EMAIL:-${SMTP_FROM:-root@localhost}}"
  prompt_var_force MONIT_CHECK_INTERVAL "Intervallo controllo (secondi)" "${MONIT_CHECK_INTERVAL:-60}"
  if [[ "$INTERACTIVE" == "yes" && "${MONIT_SERVICES,,}" != "auto" ]]; then
    prompt_var_force MONIT_SERVICES "Servizi (auto calcolato: ${MONIT_SERVICES})" "${MONIT_SERVICES}"
  elif [[ "$INTERACTIVE" == "yes" ]]; then
    info "Servizi Monit proposti: ${MONIT_SERVICES}"
    confirm "Usare questa lista servizi Monit?" "y" || \
      prompt_var_force MONIT_SERVICES "Servizi Monit (virgola)" "${MONIT_SERVICES}"
  fi
  prompt_var_force UFW_SSH_PORT         "Porta SSH per check Monit" "${UFW_SSH_PORT:-22}"

  [[ -f /etc/monit/monitrc ]] && cp /etc/monit/monitrc "/etc/monit/monitrc.bak.$(date +%s)"

  local mail_from="$SMTP_FROM"
  [[ -z "$mail_from" ]] && mail_from="monit@$(hostname -f)"

  cat > /etc/monit/monitrc <<EOF
set daemon ${MONIT_CHECK_INTERVAL}
set logfile /var/log/monit.log
set idfile /var/lib/monit/id
set statefile /var/lib/monit/state

$(render_monit_mailserver)
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
    if failed port ${UFW_SSH_PORT} protocol ssh for 3 cycles then restart
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
      postfix)
        cat > /etc/monit/conf-enabled/postfix <<'PFEOF'
check process postfix with pidfile /var/spool/postfix/pid/master.pid
    start program = "/bin/systemctl start postfix"
    stop program  = "/bin/systemctl stop postfix"
    if 5 restarts within 5 cycles then alert
PFEOF
        ;;
      proftpd)
        cat > /etc/monit/conf-enabled/proftpd <<'PFTPDEOF'
check process proftpd matching "proftpd"
    start program = "/bin/systemctl start proftpd"
    stop program  = "/bin/systemctl stop proftpd"
    if 5 restarts within 5 cycles then alert
PFTPDEOF
        ;;
      filesystem)
        cat > /etc/monit/conf-enabled/filesystem <<'FSEOF'
check filesystem rootfs with path /
    if space usage > 85% for 5 cycles then alert
    if inode usage > 85% for 5 cycles then alert
FSEOF
        ;;
      custom)
        local cn cp cs ct
        prompt_var MONIT_CUSTOM_NAME  "Nome processo custom" "${MONIT_CUSTOM_NAME:-myapp}"
        prompt_var MONIT_CUSTOM_PID   "PID file"             "${MONIT_CUSTOM_PID:-/var/run/myapp.pid}"
        prompt_var MONIT_CUSTOM_START "Comando start"        "${MONIT_CUSTOM_START:-/bin/systemctl start myapp}"
        prompt_var MONIT_CUSTOM_STOP  "Comando stop"         "${MONIT_CUSTOM_STOP:-/bin/systemctl stop myapp}"
        cn="$MONIT_CUSTOM_NAME"; cp="$MONIT_CUSTOM_PID"; cs="$MONIT_CUSTOM_START"; ct="$MONIT_CUSTOM_STOP"
        cat > "/etc/monit/conf-enabled/${cn}" <<CUSTOMEOF
check process ${cn} with pidfile ${cp}
    start program = "${cs}"
    stop program  = "${ct}"
    if 5 restarts within 5 cycles then alert
CUSTOMEOF
        ;;
      *) warn "Servizio Monit sconosciuto: ${svc}" ;;
    esac
  done

  monit -t || die "Configurazione Monit non valida"
  systemctl enable monit
  systemctl restart monit

  info "── Verifica /etc/monit/monitrc ──"
  grep -E '^(set alert|set mailserver)' /etc/monit/monitrc | while read -r l; do info "  $l"; done
  info "  Destinatario: ${MONIT_ADMIN_EMAIL} | From: ${mail_from}"

  if [[ "$INTERACTIVE" == "yes" ]] && confirm "Inviare email di test Monit?" "y"; then
    test_notification_mail "$MONIT_ADMIN_EMAIL"
  fi
  mark_module_done "monit"
  success "Monit → /etc/monit/monitrc"
}

module_logwatch() {
  should_run_module "logwatch" "INSTALL_LOGWATCH" || return 0
  apt-get -y install logwatch
  verify_postfix_for_mail
  show_mail_architecture

  resolve_logwatch_services
  info "Configurazione Logwatch (solo MailTo/MailFrom — Postfix gestisce smarthost):"
  info "  Servizi: elenco separato da virgola (es. sshd,postfix) oppure 'All' per tutti i log."
  info "  Con 'All' si possono usare solo esclusioni (es. -zz-network), non altri servizi insieme."
  prompt_var_force LOGWATCH_EMAIL       "Email destinatario report giornaliero" "${LOGWATCH_EMAIL:-${MONIT_ADMIN_EMAIL:-root@localhost}}"
  prompt_var_force SMTP_FROM            "Email mittente (MailFrom)" "${SMTP_FROM:-$SMTP_USER}"
  prompt_var_force LOGWATCH_DETAIL      "Dettaglio (Low, Med, High)" "${LOGWATCH_DETAIL:-Med}"
  prompt_var_force LOGWATCH_RANGE       "Intervallo (Yesterday, Today, All)" "${LOGWATCH_RANGE:-Yesterday}"
  if [[ "$INTERACTIVE" == "yes" ]]; then
    info "Servizi Logwatch proposti: ${LOGWATCH_SERVICES}"
    confirm "Usare questa lista Logwatch?" "y" || \
      prompt_var_force LOGWATCH_SERVICES "Servizi (virgola) o All" "${LOGWATCH_SERVICES}"
    normalize_logwatch_services
  fi
  prompt_var_force LOGWATCH_FORMAT      "Formato (text, html)" "${LOGWATCH_FORMAT:-text}"
  prompt_var_force LOGWATCH_CRON_HOUR   "Ora invio giornaliero (0-23)" "${LOGWATCH_CRON_HOUR:-6}"

  write_logwatch_conf_file
  verify_logwatch_config

  rm -f /etc/cron.daily/00logwatch /etc/cron.daily/logwatch
  if [[ "$LOGWATCH_CRON_HOUR" =~ ^[0-9]+$ ]]; then
    cat > /etc/cron.d/logwatch <<EOF
# Report Logwatch giornaliero — install.sh
0 ${LOGWATCH_CRON_HOUR} * * * root /usr/sbin/logwatch --output mail --mailto ${LOGWATCH_EMAIL}
EOF
    chmod 644 /etc/cron.d/logwatch
  fi

  info "── Verifica /etc/logwatch/conf/logwatch.conf ──"
  grep -E '^(MailTo|MailFrom|Detail|Service)' /etc/logwatch/conf/logwatch.conf | while read -r l; do info "  $l"; done

  if [[ "$INTERACTIVE" == "yes" ]] && confirm "Anteprima Logwatch su stdout?" "n"; then
    /usr/sbin/logwatch --output stdout --range Today --detail Low 2>/dev/null | head -50 || true
  fi
  if [[ "$INTERACTIVE" == "yes" ]] && confirm "Inviare report Logwatch di test via email?" "y"; then
    /usr/sbin/logwatch --output mail --mailto "${LOGWATCH_EMAIL}" --range Today --detail Low 2>/dev/null \
      && success "Report Logwatch inviato a ${LOGWATCH_EMAIL}" \
      || warn "Invio Logwatch fallito — verifica Postfix"
  fi
  success "Logwatch configurato → /etc/logwatch/conf/logwatch.conf (cron ${LOGWATCH_CRON_HOUR}:00)"
  mark_module_done "logwatch"
}

prompt_ram_monitor_config() {
  prompt_var MON_SERVER_NAME "Nome server (SERVER_NAME)" "${MON_SERVER_NAME:-$(hostname -s)}"
  prompt_var RAM_MAIL_TO "Email alert RAM (vuoto=disabilitata)" "${RAM_MAIL_TO:-${MONIT_ADMIN_EMAIL:-}}"
  prompt_var RAM_TELEGRAM_BOT_TOKEN "Telegram bot token (vuoto=skip)" "${RAM_TELEGRAM_BOT_TOKEN:-}"
  prompt_var RAM_TELEGRAM_CHAT_ID "Telegram chat ID" "${RAM_TELEGRAM_CHAT_ID:-}"
  prompt_var RAM_GOTIFY_URL "Gotify URL (vuoto=skip)" "${RAM_GOTIFY_URL:-}"
  prompt_var RAM_GOTIFY_TOKEN "Gotify token" "${RAM_GOTIFY_TOKEN:-}"
}

module_ram_monitor() {
  should_run_module "ram_monitor" "INSTALL_RAM_MONITOR" || return 0
  apt-get -y install curl
  prompt_ram_monitor_config

  local dir="/opt/monitoring/ram-usage"
  local script_opt="${dir}/ram_usage_monitor.sh"
  local script_bin="/usr/local/bin/ram-usage-monitor.sh"

  mkdir -p "$dir" /var/lib/ram-usage-monitor
  write_embedded_file "__RAM_MONITOR_SCRIPT__" "__END_RAM_MONITOR__" "$script_opt"
  cp -a "$script_opt" "$script_bin"
  chmod 755 "$script_bin"

  cat > "${dir}/ram-check.env" <<EOF
SERVER_NAME=${MON_SERVER_NAME}
MAIL_TO=${RAM_MAIL_TO}
MAIL_FROM=${SMTP_FROM:-monitor@${MON_SERVER_NAME}.local}
TELEGRAM_BOT_TOKEN=${RAM_TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${RAM_TELEGRAM_CHAT_ID}
GOTIFY_URL=${RAM_GOTIFY_URL}
GOTIFY_TOKEN=${RAM_GOTIFY_TOKEN}
STATE_FILE=/var/lib/ram-usage-monitor/state
EOF
  chmod 600 "${dir}/ram-check.env"

  cat > /etc/cron.d/ram-usage-monitor <<EOF
# Monitor RAM — install.sh (ogni 5 minuti)
*/5 * * * * root ${script_bin} >> /var/log/ram_usage_monitor.log 2>&1
EOF
  chmod 644 /etc/cron.d/ram-usage-monitor
  touch /var/log/ram_usage_monitor.log

  info "── Verifica RAM monitor ──"
  info "  Script: ${script_bin}"
  info "  Config: ${dir}/ram-check.env"
  info "  Log:    /var/log/ram_usage_monitor.log"
  "${script_bin}" && success "RAM monitor OK (test eseguito)" || warn "Test RAM monitor con avvisi — controlla log"

  success "RAM monitor installato (cron ogni 5 min, avvio via cron al boot)"
  mark_module_done "ram_monitor"
}

prompt_smart_monitor_config() {
  prompt_var MON_SERVER_NAME "Nome server (SERVER_NAME)" "${MON_SERVER_NAME:-$(hostname -s)}"
  prompt_var SMART_EMAIL_TO "Email alert SMART (vuoto=skip)" "${SMART_EMAIL_TO:-${MONIT_ADMIN_EMAIL:-}}"
  prompt_var SMART_TELEGRAM_BOT_TOKEN "Telegram bot token (vuoto=skip)" "${SMART_TELEGRAM_BOT_TOKEN:-}"
  prompt_var SMART_TELEGRAM_CHAT_ID "Telegram chat ID" "${SMART_TELEGRAM_CHAT_ID:-}"
  prompt_var SMART_GOTIFY_URL "Gotify URL (vuoto=skip)" "${SMART_GOTIFY_URL:-}"
  prompt_var SMART_GOTIFY_TOKEN "Gotify token" "${SMART_GOTIFY_TOKEN:-}"
  prompt_var SMART_CRON_HOUR "Ora check SMART giornaliero (0-23)" "${SMART_CRON_HOUR:-6}"
}

module_smart_monitor() {
  should_run_module "smart_monitor" "INSTALL_SMART_MONITOR" || return 0
  apt-get -y install smartmontools curl gawk
  prompt_smart_monitor_config

  write_embedded_file "__SMART_MONITOR_SCRIPT__" "__END_SMART_MONITOR__" "/usr/local/bin/smart-monitor.sh"

  cat > /etc/smart-monitor.env <<EOF
SERVER_NAME=${MON_SERVER_NAME}
EMAIL_TO=${SMART_EMAIL_TO}
MAIL_FROM=${SMTP_FROM:-monitor@${MON_SERVER_NAME}.local}
TELEGRAM_BOT_TOKEN=${SMART_TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${SMART_TELEGRAM_CHAT_ID}
GOTIFY_URL=${SMART_GOTIFY_URL}
GOTIFY_TOKEN=${SMART_GOTIFY_TOKEN}
LOG_FILE=/var/log/smart_monitor.log
EOF
  chmod 600 /etc/smart-monitor.env

  cat > /etc/cron.d/smart-monitor <<EOF
${SMART_CRON_HOUR} * * * root /usr/local/bin/smart-monitor.sh >> /var/log/smart_monitor.log 2>&1
EOF
  chmod 644 /etc/cron.d/smart-monitor
  touch /var/log/smart_monitor.log
  info "── Verifica SMART monitor ──"
  info "  Script: /usr/local/bin/smart-monitor.sh"
  info "  Config: /etc/smart-monitor.env"
  /usr/local/bin/smart-monitor.sh --test 2>/dev/null && success "SMART monitor test OK" || true
  success "SMART monitor installato (cron ${SMART_CRON_HOUR}:00, avvio via cron al boot)"
  mark_module_done "smart_monitor"
}

# ─── Selezione componenti ─────────────────────────────────────────────────────

show_banner() {
  echo
  echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
  printf "${BOLD}║  %-48s║${NC}\n" "${PROVISIONER_NAME} v${VERSION}"
  printf "${BOLD}║  %-48s║${NC}\n" "by ${PROVISIONER_AUTHOR}"
  printf "${BOLD}║  %-48s║${NC}\n" "${PROVISIONER_EMAIL} — ${PROVISIONER_WEBSITE}"
  printf "${BOLD}║  %-48s║${NC}\n" "Debian provisioning — single file"
  if [[ -n "${DEBIAN_CODENAME:-}" ]]; then
    printf "${BOLD}║  %-48s║${NC}\n" "${DEBIAN_PRETTY} (${DEBIAN_CODENAME})"
  fi
  echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
  echo
}

collect_component_selection() {
  show_banner
  info "Fase 1: aggiornamento sistema (sempre eseguito)"
  echo
  info "Fase 2: selezione componenti opzionali"
  echo

  prompt_yes_no INSTALL_BUILD    "Installare build-essential (gcc, make)?" "yes"
  prompt_yes_no INSTALL_UFW      "Configurare UFW (firewall)?" "yes"
  if is_yes "$INSTALL_UFW"; then
    prompt_yes_no INSTALL_SSH_HARDENING "Applicare hardening SSH (sshd_config.d)?" "yes"
    prompt_yes_no INSTALL_FAIL2BAN      "Installare Fail2ban (sshd + proftpd)?" "yes"
  else
    prompt_yes_no INSTALL_SSH_HARDENING "Applicare hardening SSH?" "no"
    prompt_yes_no INSTALL_FAIL2BAN      "Installare Fail2ban?" "no"
  fi
  prompt_yes_no INSTALL_SMTP     "Installare Postfix relay (smarthost)?" "yes"
  prompt_yes_no INSTALL_DOCKER   "Installare Docker?" "no"
  prompt_yes_no INSTALL_TIMEZONE "Configurare timezone di sistema?" "yes"
  prompt_yes_no INSTALL_PROFTPD  "Installare ProFTPd (FTP/FTPS)?" "no"
  prompt_yes_no INSTALL_MONIT    "Installare Monit?" "no"
  prompt_yes_no INSTALL_LOGWATCH "Installare Logwatch?" "no"
  prompt_yes_no INSTALL_CRON     "Verificare/installare cron?" "yes"
  prompt_yes_no INSTALL_RAM_MONITOR  "Installare monitor RAM (script + cron)?" "no"
  prompt_yes_no INSTALL_SMART_MONITOR "Installare monitor SMART dischi?" "no"
  prompt_yes_no INSTALL_BOOT_SERVICES "Abilitare avvio automatico al boot (cron/monit/postfix)?" "yes"

  echo
  info "Riepilogo selezione:"
  echo "  build-essential : ${INSTALL_BUILD}"
  echo "  UFW             : ${INSTALL_UFW}"
  echo "  SSH hardening   : ${INSTALL_SSH_HARDENING}"
  echo "  Fail2ban        : ${INSTALL_FAIL2BAN}"
  echo "  Postfix relay   : ${INSTALL_SMTP}"
  echo "  Docker          : ${INSTALL_DOCKER}"
  echo "  Timezone        : ${INSTALL_TIMEZONE}"
  echo "  ProFTPd         : ${INSTALL_PROFTPD}"
  echo "  Monit           : ${INSTALL_MONIT}"
  echo "  Logwatch        : ${INSTALL_LOGWATCH}"
  echo "  Cron            : ${INSTALL_CRON}"
  echo "  Monitor RAM     : ${INSTALL_RAM_MONITOR}"
  echo "  Monitor SMART   : ${INSTALL_SMART_MONITOR}"
  echo "  Boot automatico : ${INSTALL_BOOT_SERVICES}"
  echo
}

resolve_auto_selection_noninteractive() {
  local v
  for v in INSTALL_BUILD INSTALL_UFW INSTALL_SMTP INSTALL_DOCKER INSTALL_MONIT INSTALL_LOGWATCH \
           INSTALL_CRON INSTALL_RAM_MONITOR INSTALL_SMART_MONITOR INSTALL_BASH_ALIASES INSTALL_BOOT_SERVICES \
           INSTALL_PROFTPD; do
    [[ "${!v}" == "auto" ]] && printf -v "$v" '%s' "no"
  done
  [[ "${INSTALL_TIMEZONE}" == "auto" ]] && INSTALL_TIMEZONE=yes
  for v in INSTALL_FAIL2BAN INSTALL_SSH_HARDENING; do
    if [[ "${!v}" == "auto" ]]; then
      is_yes "$INSTALL_UFW" && printf -v "$v" '%s' "yes" || printf -v "$v" '%s' "no"
    fi
  done
  # Se monit/logwatch senza smtp esplicito, abilita smtp se credenziali presenti
  if { is_yes "$INSTALL_MONIT" || is_yes "$INSTALL_LOGWATCH"; } && \
     [[ "$INSTALL_SMTP" == "no" ]] && [[ -n "$SMTP_HOST" ]]; then
    INSTALL_SMTP=yes
  fi
}

# ─── Riavvio opzionale ──────────────────────────────────────────────────────────

prompt_reboot() {
  local do_reboot=no

  case "${ALLOW_REBOOT,,}" in
    yes|y|1|true)  do_reboot=yes ;;
    no|n|0|false)  do_reboot=no ;;
    auto)
      if [[ "$INTERACTIVE" == "yes" ]]; then
        if confirm "Riavviare la macchina ora? (consigliato dopo aggiornamento kernel)" "n"; then
          do_reboot=yes
        fi
      fi
      ;;
    *) warn "ALLOW_REBOOT='${ALLOW_REBOOT}' non valido — riavvio saltato." ;;
  esac

  if is_yes "$do_reboot"; then
    if is_yes "$INSTALL_UFW" && [[ "$INTERACTIVE" == "yes" ]] && ! is_yes "$SSH_PREFLIGHT_CONFIRMED"; then
      warn "Reboot annullato — verifica SSH su una seconda sessione prima di riavviare"
      do_reboot=no
    fi
  fi

  if is_yes "$do_reboot"; then
    echo
    warn "Riavvio tra 10 secondi... (Ctrl+C per annullare)"
    sleep 10
    sync
    reboot
  else
    info "Riavvio saltato. Quando pronto: sudo reboot"
  fi
}

# ─── Main ───────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"
  detect_interactive
  require_root
  require_debian

  mkdir -p "$(dirname "$LOG_FILE")" "$MARKER_DIR"
  touch "$LOG_FILE"

  if [[ -n "$ONLY_MODULES" ]]; then
    info "Modalità --only: ${ONLY_MODULES} (MODULE_FORCE=${MODULE_FORCE})"
    show_banner
  elif [[ "$INTERACTIVE" == "yes" ]]; then
    collect_component_selection
  else
    resolve_auto_selection_noninteractive
  fi

  preflight_checks

  local needs_mail=false
  is_yes "$INSTALL_SMTP"        && needs_mail=true || true
  is_yes "$INSTALL_MONIT"       && needs_mail=true || true
  is_yes "$INSTALL_LOGWATCH"    && needs_mail=true || true
  is_yes "$INSTALL_RAM_MONITOR" && needs_mail=true || true
  is_yes "$INSTALL_SMART_MONITOR" && needs_mail=true || true

  if [[ "$SKIP_CONFIRM" != true && "$INTERACTIVE" == "yes" ]]; then
    confirm "Procedere con il provisioning?" "y" || exit 0
  fi

  PROVISION_ACTIVE=true
  trap provision_on_exit EXIT

  local t0
  t0="$(date +%s)"

  info "━━━ Aggiornamento sistema ━━━"
  module_base

  info "━━━ build-essential ━━━"
  module_build_essential

  info "━━━ Postfix relay (smarthost) ━━━"
  module_smtp
  if $needs_mail && ! smtp_is_configured; then
    info "━━━ Postfix (richiesto per notifiche) ━━━"
    prompt_notifications_mail
  fi

  info "━━━ UFW ━━━"
  module_ufw

  info "━━━ SSH hardening ━━━"
  module_ssh_hardening

  info "━━━ Fail2ban ━━━"
  module_fail2ban

  info "━━━ Docker ━━━"
  module_docker

  info "━━━ Timezone ━━━"
  module_timezone

  info "━━━ ProFTPd ━━━"
  module_proftpd

  info "━━━ Cron ━━━"
  module_cron

  local prompt_mail=false
  is_yes "$INSTALL_MONIT" && prompt_mail=true
  is_yes "$INSTALL_LOGWATCH" && prompt_mail=true
  [[ -n "$ONLY_MODULES" ]] && list_contains "$ONLY_MODULES" "monit" && prompt_mail=true
  [[ -n "$ONLY_MODULES" ]] && list_contains "$ONLY_MODULES" "logwatch" && prompt_mail=true

  if $prompt_mail; then
    if ! smtp_is_configured; then
      prompt_notifications_mail
    else
      prompt_var SMTP_FROM "Email mittente (From)" "${SMTP_FROM:-$SMTP_USER}"
      [[ -z "${MONIT_ADMIN_EMAIL:-}" ]] && prompt_var MONIT_ADMIN_EMAIL "Email alert" "${SMTP_FROM:-root@localhost}"
      if is_yes "$INSTALL_LOGWATCH" || list_contains "${ONLY_MODULES:-}" "logwatch"; then
        [[ -z "${LOGWATCH_EMAIL:-}" ]] && \
          prompt_var LOGWATCH_EMAIL "Email Logwatch" "${MONIT_ADMIN_EMAIL:-root@localhost}"
      fi
    fi
  fi

  info "━━━ Monit ━━━"
  module_monit

  info "━━━ Logwatch ━━━"
  module_logwatch

  if is_yes "$INSTALL_RAM_MONITOR" || is_yes "$INSTALL_SMART_MONITOR"; then
    smtp_is_configured || prompt_notifications_mail
  fi

  info "━━━ Monitor RAM ━━━"
  module_ram_monitor

  info "━━━ Monitor SMART ━━━"
  module_smart_monitor

  is_yes "$INSTALL_BASH_ALIASES" && ! is_yes "$INSTALL_DOCKER" && configure_bash_aliases no || true

  info "━━━ Avvio automatico al boot ━━━"
  module_ensure_boot_services

  save_runtime_config

  local elapsed=$(( $(date +%s) - t0 ))
  PROVISION_ELAPSED=$elapsed
  echo
  success "Provisioning completato in ${elapsed}s."
  info "Log: ${LOG_FILE}"
  info "Config: ${MARKER_DIR}/runtime.env"
  echo
  info "Riferimenti config:"
  is_yes "$INSTALL_MONIT"        && info "  Monit:    /etc/monit/monitrc"
  is_yes "$INSTALL_LOGWATCH"     && info "  Logwatch: /etc/logwatch/conf/logwatch.conf"
  is_yes "$INSTALL_RAM_MONITOR"  && info "  RAM:      /usr/local/bin/ram-usage-monitor.sh"
  is_yes "$INSTALL_SMART_MONITOR" && info "  SMART:    /usr/local/bin/smart-monitor.sh"
  is_yes "$INSTALL_FAIL2BAN"     && info "  Fail2ban: /etc/fail2ban/jail.d/the-provisioner.local"
  is_yes "$INSTALL_PROFTPD"      && info "  ProFTPd:  /etc/proftpd/conf.d/the-provisioner.conf"
  is_yes "$INSTALL_SSH_HARDENING" && info "  SSH:      /etc/ssh/sshd_config.d/99-debian-provision-hardening.conf"
  is_yes "$INSTALL_BASH_ALIASES" && info "  Alias:    source /root/.bashrc  (sessione SSH corrente)"

  is_yes "$INSTALL_UFW" && verify_ssh_ufw_alignment

  echo
  send_install_report 0
  prompt_ssh_connectivity_check
  prompt_reboot
}

main "$@"

: <<'EMBEDDED_SCRIPTS'
__RAM_MONITOR_SCRIPT__
#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/ram-check.env"
[[ -f "$ENV_FILE" ]] || { echo "[ERROR] .env mancante: $ENV_FILE"; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"
SERVER_NAME="${SERVER_NAME:-server}"
RAM_WARN_PERCENT="${RAM_WARN_PERCENT:-80}"
RAM_CRIT_PERCENT="${RAM_CRIT_PERCENT:-90}"
SWAP_WARN_PERCENT="${SWAP_WARN_PERCENT:-50}"
SWAP_CRIT_PERCENT="${SWAP_CRIT_PERCENT:-80}"
STATE_FILE="${STATE_FILE:-/var/lib/ram-usage-monitor/state}"
log()  { echo "[$(date '+%F %T')] [INFO ] $*"; }
warn() { echo "[$(date '+%F %T')] [WARN ] $*"; }
send_telegram() { [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS --max-time 15 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=[${SERVER_NAME}] $1" >/dev/null || true; }
send_gotify() { [[ -z "${GOTIFY_URL:-}" || -z "${GOTIFY_TOKEN:-}" ]] && return 0
  curl -sS --max-time 15 "${GOTIFY_URL%/}/message?token=${GOTIFY_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"[${SERVER_NAME}] RAM\",\"message\":\"$1\",\"priority\":5}" >/dev/null || true; }
send_email() { [[ -z "${MAIL_TO:-}" ]] && return 0
  { echo "To: ${MAIL_TO}"; echo "From: ${MAIL_FROM:-monitor@local}"
    echo "Subject: [${SERVER_NAME}] $1"; echo; echo "$2"; } | sendmail -t 2>/dev/null || true; }
notify() { local t="$1" b="$2"; log "$t"; send_telegram "$t - $b"; send_gotify "$b"; send_email "$t" "$b"; }
state_init() { mkdir -p "$(dirname "$STATE_FILE")"; touch "$STATE_FILE"; }
state_get() { grep "^$1=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-; }
state_set() { local k="$1" v="$2" t="${STATE_FILE}.tmp"; grep -v "^${k}=" "$STATE_FILE" 2>/dev/null > "$t" || true; echo "${k}=${v}" >> "$t"; mv "$t" "$STATE_FILE"; }
check_ram() {
  local mt ma st sf; mt=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
  ma=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
  st=$(grep '^SwapTotal:' /proc/meminfo | awk '{print $2}')
  sf=$(grep '^SwapFree:' /proc/meminfo | awk '{print $2}')
  local used=$((mt-ma)) pct=$((used*100/mt))
  log "RAM ${pct}% (${used}kB/${mt}kB usati)"
  if [[ $pct -ge $RAM_CRIT_PERCENT ]]; then notify "RAM CRITICA ${pct}%" "RAM al ${pct}% su ${SERVER_NAME}"
  elif [[ $pct -ge $RAM_WARN_PERCENT ]]; then notify "RAM elevata ${pct}%" "RAM al ${pct}% su ${SERVER_NAME}"; fi
  if [[ ${st:-0} -gt 0 ]]; then local su=$((st-sf)) sp=$((su*100/st))
    log "SWAP ${sp}%"; [[ $sp -ge $SWAP_CRIT_PERCENT ]] && notify "SWAP CRITICA" "Swap ${sp}% su ${SERVER_NAME}"; fi
}
check_oom() {
  command -v journalctl >/dev/null || return 0
  local ev; ev=$(journalctl -k --since "10 min ago" 2>/dev/null | grep -iE "Out of memory|Killed process" | tail -5 || true)
  [[ -n "$ev" ]] && notify "OOM Killer" "$ev"
}
state_init; check_ram; check_oom
__END_RAM_MONITOR__
__SMART_MONITOR_SCRIPT__
#!/usr/bin/env bash
set -uo pipefail
ENV_FILE="/etc/smart-monitor.env"
[[ -f "$ENV_FILE" ]] || { echo "ERRORE: $ENV_FILE mancante" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"
SERVER_NAME="${SERVER_NAME:-$(hostname -s)}"
THRESHOLD_TEMP_NVME="${THRESHOLD_TEMP_NVME:-70}"
THRESHOLD_TEMP_HDD="${THRESHOLD_TEMP_HDD:-50}"
THRESHOLD_PERC_USED="${THRESHOLD_PERC_USED:-80}"
LOG_FILE="${LOG_FILE:-/var/log/smart_monitor.log}"
log() { echo "[$(date '+%F %T')] [INFO ] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date '+%F %T')] [WARN ] $*" | tee -a "$LOG_FILE" >&2; }
send_telegram() { [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -sS --max-time 15 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=$1" >/dev/null || true; }
send_gotify() { [[ -z "${GOTIFY_URL:-}" || -z "${GOTIFY_TOKEN:-}" ]] && return 0
  curl -sS --max-time 15 "${GOTIFY_URL%/}/message?token=${GOTIFY_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"SMART ${SERVER_NAME}\",\"message\":\"$1\",\"priority\":7}" >/dev/null || true; }
send_email() { [[ -z "${EMAIL_TO:-}" ]] && return 0
  { echo "To: ${EMAIL_TO}"; echo "From: ${MAIL_FROM:-monitor@local}"
    echo "Subject: SMART Alert ${SERVER_NAME}"; echo; echo "$1"; } | sendmail -t 2>/dev/null || true; }
send_all() { send_telegram "$1"; send_gotify "$1"; send_email "$1"; }
check_nvme() {
  local dev="$1" out="$2" model="$3" alert="" health perc temp
  health=$(echo "$out" | grep -i "overall-health" | awk '{print $NF}' || true)
  perc_used=$(echo "$out" | grep -i "Percentage Used" | awk '{print $NF}' | tr -d '%' || true)
  temp=$(echo "$out" | grep -iE "^Temperature:" | head -1 | awk '{print $2}' || true)
  [[ "${health:-FAILED}" != "PASSED" ]] && alert+="Health=${health}; "
  [[ "$perc_used" =~ ^[0-9]+$ && $perc_used -ge $THRESHOLD_PERC_USED ]] && alert+="Used=${perc_used}%; "
  [[ "$temp" =~ ^[0-9]+$ && $temp -ge $THRESHOLD_TEMP_NVME ]] && alert+="Temp=${temp}C; "
  if [[ -n "$alert" ]]; then local msg="ALERT NVMe ${dev} (${model}): ${alert}"; log "$msg"; send_all "$msg"
  else log "OK NVMe ${dev} (${model})"; fi
}
check_sata() {
  local dev="$1" out="$2" model="$3" alert="" health temp
  health=$(echo "$out" | grep -i "overall-health" | awk '{print $NF}' || true)
  temp=$(echo "$out" | awk '$1==194 {print $10+0; exit}')
  [[ "${health:-FAILED}" != "PASSED" ]] && alert+="Health=${health}; "
  [[ "$temp" =~ ^[0-9]+$ && $temp -ge $THRESHOLD_TEMP_HDD ]] && alert+="Temp=${temp}C; "
  if [[ -n "$alert" ]]; then local msg="ALERT SATA ${dev} (${model}): ${alert}"; log "$msg"; send_all "$msg"
  else log "OK SATA ${dev} (${model})"; fi
}
[[ "${1:-}" == "--test" ]] && { send_all "[TEST] SMART monitor ${SERVER_NAME}"; exit 0; }
mapfile -t disks < <(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}')
log "SMART monitor - ${SERVER_NAME} - ${#disks[@]} disco/i"
for d in "${disks[@]}"; do
  dev="/dev/${d}"; out=""; ec=0; out=$(smartctl -a "$dev" 2>/dev/null) || ec=$?
  (( ec & 2 )) && { log "SKIP ${dev}: non accessibile"; continue; }
  (( ec & 4 )) && { log "SKIP ${dev}: SMART non supportato"; continue; }
  model=$(echo "$out" | grep -E "^(Device Model|Model Number)" | head -1 | sed 's/^[^:]*: *//' || echo "Sconosciuto")
  if [[ "$d" == nvme* ]]; then check_nvme "$dev" "$out" "$model"; else check_sata "$dev" "$out" "$model"; fi
done
log "Completato"
__END_SMART_MONITOR__
EMBEDDED_SCRIPTS
