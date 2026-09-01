# The Provisioner

**Debian server provisioning in a single file.**

> **The Provisioner** · `install.sh` v1.6.2  
> **Author:** [Carlo Savino](https://github.com/slash3rmast3r) — [info@savinocarlo.it](mailto:info@savinocarlo.it) — [www.savinocarlo.it](https://www.savinocarlo.it)  
> **License:** [BSD 3-Clause](LICENSE) — free to use; keep copyright and license text

---

Script di provisioning **Debian** autocontenuto: nessuna dipendenza da altri file del repository. Aggiorna il sistema, installa componenti opzionali (UFW, Postfix, Docker, Monit, Logwatch, Fail2ban, ProFTPd, monitor RAM/SMART) e chiede solo la personalizzazione necessaria (email, smarthost, porta SSH, timezone, ecc.).

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/slash3rmast3r/the-provisioner/main/install.sh -o install.sh
sudo bash install.sh
```

Oppure, dal clone del repository:

```bash
git clone https://github.com/slash3rmast3r/the-provisioner.git
cd the-provisioner
sudo bash install.sh
```

## Requisiti

- **Debian 11+ (Bullseye)** — rilevamento automatico release e codename
- Target di riferimento: **Bookworm 12**, supporto **Trixie 13** con workaround Docker
- Esecuzione come **root** (`sudo`)
- Connessione di rete per `apt`

Lo script legge `/etc/os-release` e `/etc/debian_version`, imposta un profilo per release (Docker repo, `ssh.socket`, avvisi) e **blocca** Debian &lt; 11 salvo `DEBIAN_ALLOW_OLD=yes`.

| Release | Codename | Note |
|---------|----------|------|
| 13 | Trixie | Docker CE → repo bookworm + fallback `docker.io` |
| 12 | Bookworm | Target ideale; gestione `ssh.socket` |
| 11 | Bullseye | Supportato |
| ≤ 10 | Buster e precedenti | Bloccato (override: `DEBIAN_ALLOW_OLD=yes`) |


## Novità v1.6.2

- **Logwatch (fix definitivo)** — `Service = ""` in `/etc/logwatch/conf/logwatch.conf` resetta `Service = All` ereditato da `/usr/share/logwatch/default.conf/`
- **`--only`** — salta la selezione componenti (Fase 2); esegue solo i moduli indicati
- **Banner versione** — `/etc/os-release` non sovrascrive più la versione script (su Trixie non compare più `v13`)

## Novità v1.6.1

- **Logwatch fix** — servizi scritti come righe `Service = nome` separate (non virgola su una riga); rimossi fragment Debian in conflitto; validazione config a fine modulo
- **ProFTPd** — prompt esteso: chroot home, max client/istanze, riepilogo, opzione `passwd` interattivo

## Novità v1.6.0

- **Preflight** — spazio disco, RAM, DNS, avvisi systemd/SSH
- **Idempotenza** — marker per modulo in `/etc/debian-provision/*.done` (`MODULE_FORCE=yes` per rieseguire)
- **`--only` / `--skip base`** — esegui solo moduli selezionati o salta l'aggiornamento apt
- **`CONFIG_FILE`** — carica variabili da file env prima dell'esecuzione
- **SSH hardening** — `sshd_config.d` (PermitRootLogin, PasswordAuthentication, AllowUsers)
- **Fail2ban** — jail sshd (+ proftpd se abilitato), porta allineata a UFW
- **Timezone** — `timedatectl set-timezone` (default `Europe/Rome`)
- **ProFTPd** — FTP/FTPS, utente dedicato (`ftpuser` default), porte passive, regole UFW
- **Monit/Logwatch auto** — lista servizi derivata dai componenti installati
- **SMTP password file** — `SMTP_PASSWORD_FILE` invece di variabile env
- **Cloud firewall reminder** — promemoria porte per AWS, Lightsail, Hetzner, OVH
- **Test SSH pre-reboot** — blocca il reboot se non confermi l'accesso su seconda sessione
- **CI** — GitHub Actions con `bash -n` e ShellCheck
- **Renovate** — aggiornamenti automatici delle GitHub Actions

## Modalità non interattiva

```bash
sudo SMTP_HOST=smtp.example.com \
     SMTP_USER=admin@example.com \
     SMTP_PASSWORD='secret' \
     SMTP_FROM=admin@example.com \
     INSTALL_UFW=yes \
     INSTALL_SSH_HARDENING=yes \
     INSTALL_FAIL2BAN=yes \
     INSTALL_SMTP=yes \
     INSTALL_DOCKER=yes \
     INSTALL_TIMEZONE=yes \
     SYSTEM_TIMEZONE=Europe/Rome \
     INSTALL_MONIT=yes \
     INSTALL_LOGWATCH=yes \
     ALLOW_REBOOT=no \
     SSH_PREFLIGHT_CONFIRMED=yes \
     bash install.sh --non-interactive -y
```

### Solo alcuni moduli

```bash
sudo bash install.sh --only ufw,ssh_hardening,fail2ban --non-interactive -y \
  INSTALL_UFW=yes INSTALL_SSH_HARDENING=yes INSTALL_FAIL2BAN=yes UFW_SSH_PORT=54321
```

### File di configurazione

```bash
sudo CONFIG_FILE=/root/provisioner.env bash install.sh --non-interactive -y
```

## Componenti (yes / no / auto)

| Variabile | Descrizione |
|-----------|-------------|
| `INSTALL_BASE` | Aggiornamento apt e pacchetti base (default: yes) |
| `INSTALL_BUILD` | build-essential, gcc, make |
| `INSTALL_UFW` | Firewall UFW + porta SSH |
| `INSTALL_SSH_HARDENING` | Hardening sshd (`sshd_config.d`) |
| `INSTALL_FAIL2BAN` | Fail2ban (default yes con UFW in non-interattivo) |
| `INSTALL_SMTP` | Postfix relay verso smarthost |
| `INSTALL_DOCKER` | Docker CE (fallback docker.io su Trixie) |
| `INSTALL_TIMEZONE` | Timezone di sistema |
| `INSTALL_PROFTPD` | Server FTP/FTPS (ProFTPd) |
| `INSTALL_CRON` | Servizio cron |
| `INSTALL_MONIT` | Monit + alert email |
| `INSTALL_LOGWATCH` | Logwatch + cron giornaliero |
| `INSTALL_RAM_MONITOR` | Monitor uso RAM/SWAP |
| `INSTALL_SMART_MONITOR` | Monitor SMART dischi |
| `INSTALL_BASH_ALIASES` | Alias `ll`, `dc` in `/etc/profile.d` |
| `INSTALL_BOOT_SERVICES` | Abilita cron, postfix, monit, fail2ban, proftpd al boot |

Con `auto` (default in interattivo) lo script chiede conferma per ogni componente.

## Email (Postfix relay)

Monit, Logwatch e i monitor usano **Postfix su localhost:25**, configurato come relay verso un smarthost esistente (es. mailcow, provider SMTP).

| Variabile | Descrizione |
|-----------|-------------|
| `SMTP_HOST` | Hostname smarthost |
| `SMTP_PORT` | Porta (587 STARTTLS, 465 SSL) |
| `SMTP_TLS` | `starttls`, `ssl`, `none` |
| `SMTP_USER` / `SMTP_PASSWORD` | Credenziali relay |
| `SMTP_PASSWORD_FILE` | File con password (alternativa a env) |
| `SMTP_FROM` | Mittente canonical |
| `POSTFIX_LOOPBACK` | Solo localhost (consigliato) |

Le password **non** vengono salvate in `/etc/debian-provision/runtime.env`.

## UFW e SSH

- Porta SSH configurabile (`UFW_SSH_PORT`, default **54321**)
- HTTP/HTTPS opzionali
- Import regole custom: incolla comandi, fragment `user.rules`, o file locale (`UFW_RULES_FILE`)

Su Debian recente lo script disabilita `ssh.socket` e abilita `ssh.service`, così la porta in `sshd_config.d` resta valida dopo il reboot. A fine installazione: verifica allineamento sshd ↔ UFW.

Se la porta ≠ 22: `ssh -p PORTA utente@host` + stessa porta nel firewall cloud (`CLOUD_PROVIDER=aws|lightsail|hetzner|ovh`).

## SSH hardening

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `SSH_PERMIT_ROOT` | `prohibit-password` | PermitRootLogin |
| `SSH_PASSWORD_AUTH` | `yes` | PasswordAuthentication |
| `SSH_MAX_AUTH_TRIES` | `5` | MaxAuthTries |
| `SSH_ALLOW_USERS` | — | Lista utenti consentiti (virgola) |

Se `SSH_PASSWORD_AUTH=no`, lo script verifica la presenza di chiavi in `authorized_keys`.

## ProFTPd

In modalità interattiva lo script chiede le opzioni minime consigliate (utente, TLS, chroot, porte passive, limiti client).

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `PROFTPD_USER` | `ftpuser` | Utente UNIX dedicato |
| `PROFTPD_PORT` | `21` | Porta controllo |
| `PROFTPD_TLS` | `yes` | FTPS esplicito (certificato snakeoil) |
| `PROFTPD_CHROOT` | `yes` | `DefaultRoot ~` — utente confinato in home |
| `PROFTPD_PASSIVE_MIN/MAX` | `40000`–`40100` | Range porte passive (aprire anche su UFW/cloud) |
| `PROFTPD_MAX_CLIENTS` | `10` | Client simultanei |
| `PROFTPD_MAX_INSTANCES` | `30` | Istanze server |

Dopo l'installazione: password con `passwd PROFTPD_USER` (o prompt a fine modulo). Fail2ban abilita jail `proftpd` se ProFTPd è installato.

## Logwatch — servizi

| `LOGWATCH_SERVICES` | Comportamento |
|---------------------|---------------|
| `auto` | Lista derivata dai componenti installati |
| `All` | Tutti i log (solo esclusioni `-nome` ammesse oltre ad All) |
| `sshd,postfix,...` | Una riga `Service =` per ogni servizio nel file generato |

**Nota:** Logwatch unisce `/usr/share/logwatch/default.conf/` (default `Service = All`) con `/etc/logwatch/conf/logwatch.conf`. Per servizi specifici lo script scrive prima `Service = ""` per resettare All, poi una riga per servizio. Non mischiare All con servizi named.

File override corretto: **`/etc/logwatch/conf/logwatch.conf`** (non `/usr/share/...`, quello è solo il template Debian).

### Fix manuale su server già provisionato

```bash
sudo nano /etc/logwatch/conf/logwatch.conf
# Reset All (default in /usr/share/logwatch/default.conf/) poi i servizi:
# Service = ""
# Service = sshd
# Service = fail2ban
# Service = monit
sudo rm -f /etc/logwatch/conf/logwatch.conf.d/*.conf
logwatch --output stdout --range Today --detail Low | head
```

Oppure con lo script v1.6.2+:

```bash
sudo MODULE_FORCE=yes bash install.sh --only logwatch --skip base -y
```

## Riavvio

| `ALLOW_REBOOT` | Comportamento |
|----------------|---------------|
| `auto` | Chiede in modalità interattiva (default) |
| `yes` | Riavvia dopo 10 secondi |
| `no` | Salta il reboot |

In modalità interattiva, con UFW attivo, il reboot è **bloccato** finché non confermi il test SSH (`SSH_PREFLIGHT_CONFIRMED=yes` per forzare).

## Report email finale

A fine installazione (prima del reboot) viene inviata un email di riepilogo se Postfix è configurato (`SEND_INSTALL_REPORT=auto`, default).

Stati possibili: **SUCCESSO** · **COMPLETATO CON AVVISI** · **COMPLETATO CON ERRORI** · **INTERROTTO**

| Variabile | Descrizione |
|-----------|-------------|
| `SEND_INSTALL_REPORT` | `auto` (default), `yes`, `no` |
| `INSTALL_REPORT_EMAIL` | Destinatario (default: Monit → Logwatch → SMTP_FROM) |

## File generati sul server

| Percorso | Contenuto |
|----------|-----------|
| `/var/log/debian-provision.log` | Log installazione |
| `/etc/debian-provision/runtime.env` | Config non sensibile (chmod 600) |
| `/etc/debian-provision/*.done` | Marker idempotenza per modulo |
| `/etc/postfix/sasl_passwd` | Credenziali relay (chmod 600) |
| `/etc/ssh/sshd_config.d/99-debian-provision-hardening.conf` | SSH hardening |
| `/etc/fail2ban/jail.d/the-provisioner.local` | Jail Fail2ban |
| `/etc/proftpd/conf.d/the-provisioner.conf` | Config ProFTPd |

## Opzioni CLI

```
-h, --help              Aiuto
-n, --non-interactive   Nessun prompt
-y, --yes               Salta conferma iniziale
--only LIST             Solo moduli (es. ufw,smtp,monit,docker,proftpd)
--skip base             Salta aggiornamento apt base
```

Moduli `--only`: `base`, `build`, `smtp`, `ufw`, `ssh_hardening`, `fail2ban`, `docker`, `timezone`, `proftpd`, `cron`, `monit`, `logwatch`, `ram_monitor`, `smart_monitor`, `boot_services`.

## Variabili utili

| Variabile | Descrizione |
|-----------|-------------|
| `CONFIG_FILE` | File env da caricare all'avvio |
| `MODULE_FORCE` | `yes` — riesegui moduli già completati |
| `PREFLIGHT_STRICT` | `yes` (default) — blocca su disco/RAM/DNS insufficienti |
| `CLOUD_PROVIDER` | `auto`, `aws`, `lightsail`, `hetzner`, `ovh` |
| `MONIT_SERVICES` | `auto` (default) o lista virgola |
| `LOGWATCH_SERVICES` | `auto`, `All`, oppure `sshd,postfix,...` |
| `SYSTEM_TIMEZONE` | Timezone IANA (default prompt: `Europe/Rome`) |


## Riconfigurare moduli

Con --only lo script **salta la selezione componenti** (Fase 2) e va diretto ai moduli richiesti (da v1.6.2).

Per **reinstallare o riconfigurare** uno o più moduli già completati:

```bash
sudo MODULE_FORCE=yes bash install.sh --only NOME_MODULO --skip base -y
```

| Flag | Significato |
|------|-------------|
| `MODULE_FORCE=yes` | Ignora i marker `/etc/debian-provision/*.done` |
| `--only LIST` | Esegue solo i moduli indicati (virgola) |
| `--skip base` | Salta `apt update/upgrade` |
| `-y` | Salta la conferma iniziale |

### Esempi

**Logwatch** (fix config servizi):
```bash
sudo MODULE_FORCE=yes bash install.sh --only logwatch --skip base -y
```

**ProFTPd + timezone**:
```bash
sudo MODULE_FORCE=yes bash install.sh --only proftpd,timezone --skip base -y
```

**Non interattivo** (ProFTPd + timezone):
```bash
sudo MODULE_FORCE=yes \
  SYSTEM_TIMEZONE=Europe/Rome \
  PROFTPD_USER=ftpuser \
  PROFTPD_TLS=yes \
  PROFTPD_CHROOT=yes \
  bash install.sh --only proftpd,timezone --skip base --non-interactive -y
```

Alternativa: rimuovi il marker e rilancia senza `MODULE_FORCE`:
```bash
sudo rm -f /etc/debian-provision/logwatch.done
sudo bash install.sh --only logwatch --skip base -y
```

Moduli con dipendenze: `logwatch` e `monit` richiedono Postfix già configurato.
## Sviluppo e CI

```bash
bash -n install.sh
shellcheck -S warning -x install.sh
```

GitHub Actions esegue entrambi i controlli su ogni push/PR verso `main`. Renovate propone PR per aggiornare le GitHub Actions (`renovate.json`).

## Note operative

- Su **Debian Trixie**, Docker CE può non essere disponibile: lo script prova bookworm e poi `docker.io`.
- Dopo cambio porta SSH, apri la stessa porta nel firewall cloud (AWS Lightsail, EC2 SG, ecc.).
- Non committare password o token: passali via env, `SMTP_PASSWORD_FILE`, o prompt a runtime.
- **Attenzione:** la cronologia git del repository potrebbe ancora contenere segreti da versioni precedenti — pulisci la history prima della pubblicazione pubblica.

---

## Author & credits

**The Provisioner** is developed and maintained by **Carlo Savino**.

- Email: [info@savinocarlo.it](mailto:info@savinocarlo.it)
- Web: [www.savinocarlo.it](https://www.savinocarlo.it)
- GitHub: [slash3rmast3r/the-provisioner](https://github.com/slash3rmast3r/the-provisioner)

You may use, modify, and redistribute `install.sh` under the [BSD 3-Clause License](LICENSE). When you share or republish the script (including modified versions):

1. **Keep the copyright notice and license text** in the source, documentation, or a bundled `LICENSE` file.
2. **Do not use the name Carlo Savino or The Provisioner** to endorse or promote derivative products without prior written permission.

```
The Provisioner — install.sh
Copyright (c) Carlo Savino
info@savinocarlo.it — www.savinocarlo.it
https://github.com/slash3rmast3r/the-provisioner
SPDX-License-Identifier: BSD-3-Clause
```

## License

[BSD 3-Clause License](LICENSE) — Copyright (c) 2025-2026 Carlo Savino.