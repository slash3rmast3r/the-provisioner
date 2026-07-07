#!/usr/bin/env bash
# Funzioni condivise per debian-provision

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"
CONFIG_FILE="${CONFIG_FILE:-}"
LOG_FILE="${LOG_FILE:-/var/log/debian-provision.log}"
INTERACTIVE="${INTERACTIVE:-auto}"

# Colori ANSI ($'...' per ESC reale; disabilitati se non TTY / TERM=dumb / NO_COLOR)
RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
if [[ -t 1 && -t 2 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'
  CYAN=$'\033[0;36m'
  BOLD=$'\033[1m'
  NC=$'\033[0m'
fi

log() {
  local level="$1"; shift
  local plain="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  local colored="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  case "$level" in
    INFO)  colored="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] ${BLUE}$*${NC}" ;;
    OK)    colored="[$(date '+%Y-%m-%d %H:%M:%S')] [OK]   ${GREEN}$*${NC}" ;;
    WARN)  colored="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] ${YELLOW}$*${NC}" ;;
    ERROR) colored="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] ${RED}$*${NC}" ;;
  esac
  echo -e "$colored"
  echo "$plain" >> "$LOG_FILE" 2>/dev/null || true
}

info()    { log "INFO" "$*"; }
success() { log "OK" "$*"; }
warn()    { log "WARN" "$*"; }
error()   { log "ERROR" "$*"; }

die() { error "$1"; exit "${2:-1}"; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Esegui come root: sudo $0 $*"
  fi
}

require_debian() {
  if [[ ! -f /etc/debian_version ]]; then
    die "Questo script supporta solo Debian."
  fi
  local ver
  ver="$(cat /etc/debian_version)"
  info "Debian rilevato: ${ver} ($(. /etc/os-release && echo "${PRETTY_NAME}"))"
}

detect_interactive() {
  if [[ "$INTERACTIVE" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      INTERACTIVE="yes"
    else
      INTERACTIVE="no"
    fi
  fi
}

BASE_DONE_MARKER="/etc/debian-provision/base.done"

# Aggiornamento completo: update, upgrade, dist-upgrade, pulizia cache
apt_update_system() {
  info "Aggiornamento indice pacchetti..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  info "Aggiornamento distribuzione e patch di sicurezza (full-upgrade)..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    full-upgrade

  info "Dist-upgrade per eventuali cambi di dipendenze..."
  apt-get -y -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    dist-upgrade

  info "Pulizia pacchetti obsoleti e cache apt..."
  apt-get -y autoremove --purge
  apt-get -y autoclean
  apt-get -y clean
}

# Toolchain e utilità comuni su server Debian
apt_install_base_packages() {
  info "Installazione pacchetti base..."
  apt-get -y install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    build-essential \
    pkg-config \
    wget \
    vim \
    nano \
    less \
    htop \
    unzip \
    zip \
    bzip2 \
    xz-utils \
    jq \
    git \
    rsync \
    cron \
    sudo \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    dnsutils \
    tmux \
    tree \
    lsof \
    psmisc \
    software-properties-common \
    bash-completion \
    netcat-openbsd \
    sysstat \
    acl \
    openssl
}

apt_configure_unattended_upgrades() {
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
}

# Bootstrap completo sistema (usato da modules/00-base.sh e aws-user-data)
apt_bootstrap_system() {
  if [[ -f "$BASE_DONE_MARKER" ]]; then
    info "Bootstrap base già eseguito (${BASE_DONE_MARKER}), skip."
    return 0
  fi

  mkdir -p "$(dirname "$BASE_DONE_MARKER")"
  apt_update_system
  apt_install_base_packages
  apt_configure_unattended_upgrades
  touch "$BASE_DONE_MARKER"
}

# Legge variabile da config/env o chiede all'utente
# Uso: prompt_var NOME_VAR "Domanda" "default" [segreto]
prompt_var() {
  local var_name="$1"
  local question="$2"
  local default="${3:-}"
  local secret="${4:-no}"
  local current="${!var_name:-}"

  # Già impostata (env o config caricato)
  if [[ -n "$current" ]]; then
    export "$var_name=$current"
    return 0
  fi

  if [[ "$INTERACTIVE" != "yes" ]]; then
    if [[ -n "$default" ]]; then
      export "$var_name=$default"
      info "${question} → default: ${default} (modalità non interattiva)"
      return 0
    fi
    die "Variabile ${var_name} richiesta ma non impostata (modalità non interattiva). Usa --config o variabili d'ambiente."
  fi

  local input=""
  if [[ "$secret" == "yes" ]]; then
    read -rsp "${question} [${default}]: " input
    echo
  else
    read -rp "${question} [${default}]: " input
  fi

  if [[ -z "$input" ]]; then
    input="$default"
  fi
  export "$var_name=$input"
}

# Conferma sì/no
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

# Sì/no con variabile già impostata da config o prompt confirm
prompt_yes_no() {
  local var_name="$1"
  local question="$2"
  local default="${3:-yes}"
  local current="${!var_name:-}"

  if [[ -n "$current" ]]; then
    export "$var_name=$current"
    return 0
  fi

  if [[ "$INTERACTIVE" != "yes" ]]; then
    export "$var_name=$default"
    info "${question} → ${default} (modalità non interattiva)"
    return 0
  fi

  if confirm "$question" "$default"; then
    export "$var_name=yes"
  else
    export "$var_name=no"
  fi
}

load_config() {
  local file="$1"
  [[ -f "$file" ]] || die "File di configurazione non trovato: $file"
  # shellcheck disable=SC1090
  source "$file"
  info "Configurazione caricata da: $file"
}

save_runtime_config() {
  local dest="${1:-/etc/debian-provision/runtime.env}"
  mkdir -p "$(dirname "$dest")"
  {
    echo "# Generato da debian-provision il $(date -Iseconds)"
    env | grep -E '^(PROVISION_|MONIT_|LOGWATCH_|UFW_|DOCKER_|SMTP_)' | grep -v '^SMTP_PASSWORD=' | sort
  } > "$dest"
  chmod 600 "$dest"
  info "Configurazione runtime salvata in: $dest"
}

run_module() {
  local module="$1"
  local path="${MODULES_DIR}/${module}"
  [[ -f "$path" ]] || die "Modulo non trovato: $module"
  info "━━━ Esecuzione modulo: ${module} ━━━"
  # shellcheck disable=SC1090
  source "$path"
  success "Modulo completato: ${module}"
}

list_modules() {
  find "$MODULES_DIR" -maxdepth 1 -name '*.sh' -type f | sort
}

module_name_from_path() {
  basename "$1" .sh
}

# shellcheck source=smtp.sh
source "${SCRIPT_DIR}/lib/smtp.sh"
