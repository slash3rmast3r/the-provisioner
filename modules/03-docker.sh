#!/usr/bin/env bash
# Modulo: Docker Engine (repository ufficiale)

module_docker() {
  prompt_var DOCKER_INSTALL_COMPOSE "Installare anche Docker Compose plugin? (yes/no)" "${DOCKER_INSTALL_COMPOSE:-yes}"
  prompt_var DOCKER_USERS            "Utenti da aggiungere al gruppo docker (separati da virgola)" "${DOCKER_USERS:-}"

  # Rimuovi versioni obsolete se presenti
  apt-get -y remove docker docker-engine docker.io containerd runc 2>/dev/null || true

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin

  if [[ "$DOCKER_INSTALL_COMPOSE" =~ ^[Yy] ]]; then
    apt-get -y install docker-compose-plugin
  fi

  systemctl enable docker
  systemctl start docker

  if [[ -n "$DOCKER_USERS" ]]; then
    IFS=',' read -ra USERS <<< "$DOCKER_USERS"
    for u in "${USERS[@]}"; do
      u="$(echo "$u" | xargs)"
      if id "$u" &>/dev/null; then
        usermod -aG docker "$u"
        info "Utente '${u}' aggiunto al gruppo docker (riavvia sessione SSH)."
      else
        warn "Utente '${u}' non esiste, saltato."
      fi
    done
  fi

  docker --version
  success "Docker installato e avviato."
}

module_docker
