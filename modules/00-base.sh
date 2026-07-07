#!/usr/bin/env bash
# Modulo: aggiornamento sistema e pacchetti base

module_base() {
  apt_bootstrap_system
  success "Sistema aggiornato e pacchetti base installati."
}

module_base
