#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_PATH="${SCRIPT_DIR}/installer.env"
DEFAULT_SECRETS_PATH="${SCRIPT_DIR}/secrets.env"

MODE=""
INTERACTIVE="false"
FROM_STEP=""
RESET_STATE="false"
DRY_RUN="false"

CONFIG_PATH="${DEFAULT_CONFIG_PATH}"
SECRETS_PATH="${DEFAULT_SECRETS_PATH}"

# Defaults for config values.
INSTALL_ROOT="/opt/tt-installer"
TT_DATA_DIR="/opt/trusttunnel"
TT_CONTAINER_NAME="trusttunnel"
TT_IMAGE="ghcr.io/example/trusttunnel-endpoint:stable"
TT_ENDPOINT_FQDN=""
TT_LISTEN_PORT="443"
TT_ENABLE_HTTP3="true"
TT_NETWORK_MODE="host"
TT_LOG_LEVEL="debug"
TT_DOMAIN_IP_EXPECTED=""
TT_CONFIG_SOURCE_DIR=""
TT_SETUP_MODE="wizard"

TLS_MODE="letsencrypt-http01"
LE_EMAIL=""
LE_DOMAIN=""
LE_CHALLENGE="http01"
LE_DNS_PROVIDER=""
EXISTING_CERT_PATH=""
EXISTING_KEY_PATH=""

UFW_ENABLE="true"
UFW_ALLOW_SSH_PORT="22"
UFW_ALLOW_HTTP80="true"
UFW_ALLOW_HTTPS443="true"

F2B_ENABLE="true"
F2B_SSHD_MAXRETRY="5"
F2B_BANTIME="1h"

BOT_ENABLE="true"
BOT_CONTAINER_NAME="trusttunnel-admin-bot"
BOT_IMAGE="ghcr.io/example/tt_admin_bot:latest"
BOT_ENV_FILE="/opt/trusttunnel-admin-bot/.env"
BOT_TT_DATA_DIR="/opt/trusttunnel"

RESUME_ON_ERROR="true"
STATE_PATH=""
REPORT_PATH=""

# Secrets (loaded from secrets.env).
TELEGRAM_BOT_TOKEN=""
TELEGRAM_ALLOWED_USER_IDS=""
TT_BOOTSTRAP_USERNAME=""
TT_BOOTSTRAP_PASSWORD=""
LE_DNS_API_TOKEN=""

CURRENT_STEP=""
RUN_ID=""
TT_NEEDS_BOOTSTRAP="false"

readonly ALL_STEPS=(
  "s00_plan_summary"
  "s01_preflight_system"
  "s02_preflight_dns"
  "s03_preflight_ports"
  "s04_collect_or_load_config"
  "s05_write_runtime_files"
  "s06_backup_snapshot"
  "s07_setup_ssh_safe"
  "s08_setup_ufw"
  "s09_setup_fail2ban"
  "s10_setup_docker"
  "s11_prepare_tt_dirs"
  "s12_prepare_tls"
  "s13_render_tt_configs"
  "s14_deploy_trusttunnel"
  "s15_verify_trusttunnel"
  "s16_deploy_admin_bot"
  "s17_verify_admin_bot"
  "s18_generate_client_link_sample"
  "s19_finalize_report"
)

readonly PLAN_STEPS=(
  "s00_plan_summary"
  "s01_preflight_system"
  "s02_preflight_dns"
  "s03_preflight_ports"
  "s04_collect_or_load_config"
  "s19_finalize_report"
)

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf "[%s] %s\n" "$(timestamp_utc)" "$*"
}

warn() {
  printf "[%s] WARN: %s\n" "$(timestamp_utc)" "$*" >&2
}

die() {
  printf "[%s] ERROR: %s\n" "$(timestamp_utc)" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
TrustTunnel Installer (bash)

Usage:
  ./tt-installer.sh <command> [options]

Commands:
  plan       Run readiness checks and show required inputs
  apply      Apply installation steps
  resume     Continue a previous failed run from state file
  verify     Run verification checks only
  rollback   Print rollback hints from report/state

Options:
  --config <path>      Path to installer.env
  --secrets <path>     Path to secrets.env
  --state <path>       Override state.json path
  --report <path>      Override report.md path
  --interactive        Ask for missing inputs
  --from-step <id>     Start execution from step id
  --reset-state        Reset state before running
  --dry-run            Print commands but do not apply changes
  -h, --help           Show this help

Examples:
  ./tt-installer.sh plan --config ./installer.env --interactive
  ./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
  ./tt-installer.sh resume --state /opt/tt-installer/state.json
EOF
}

parse_args() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  MODE="$1"
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        CONFIG_PATH="$2"
        shift 2
        ;;
      --secrets)
        SECRETS_PATH="$2"
        shift 2
        ;;
      --state)
        STATE_PATH="$2"
        shift 2
        ;;
      --report)
        REPORT_PATH="$2"
        shift 2
        ;;
      --interactive)
        INTERACTIVE="true"
        shift
        ;;
      --from-step)
        FROM_STEP="$2"
        shift 2
        ;;
      --reset-state)
        RESET_STATE="true"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  case "$MODE" in
    plan|apply|resume|verify|rollback) ;;
    *) die "Unknown command: $MODE" ;;
  esac
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] $*"
    return 0
  fi
  "$@"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

load_env_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 0
  fi

  # shellcheck disable=SC1090
  set -a
  source "$path"
  set +a
}

ensure_paths() {
  if [[ -z "$STATE_PATH" ]]; then
    STATE_PATH="${INSTALL_ROOT}/state.json"
  fi
  if [[ -z "$REPORT_PATH" ]]; then
    REPORT_PATH="${INSTALL_ROOT}/report.md"
  fi
}

ensure_runtime_dirs() {
  run_cmd sudo mkdir -p "$INSTALL_ROOT"
  run_cmd sudo chown -R "$(id -u)":"$(id -g)" "$INSTALL_ROOT"
}

state_tmp_path() {
  echo "${STATE_PATH}.tmp"
}

write_state() {
  local tmp
  tmp="$(state_tmp_path)"
  run_cmd sudo mkdir -p "$(dirname "$STATE_PATH")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] write state -> ${STATE_PATH}"
    return 0
  fi
  cat > "$tmp"
  mv "$tmp" "$STATE_PATH"
}

init_state() {
  RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
  local now
  now="$(timestamp_utc)"
  local steps_json="[]"
  local step
  for step in "${ALL_STEPS[@]}"; do
    steps_json="$(jq -c --arg id "$step" '. + [{id:$id,status:"pending",started_at:null,finished_at:null,error_message:null}]' <<<"$steps_json")"
  done

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg created_at "$now" \
    --arg updated_at "$now" \
    --arg mode "$MODE" \
    --arg current_step "" \
    --arg resume_hint "./tt-installer.sh resume --state $STATE_PATH" \
    --arg report_path "$REPORT_PATH" \
    --arg state_path "$STATE_PATH" \
    --argjson steps "$steps_json" \
    '{
      run_id: $run_id,
      created_at: $created_at,
      updated_at: $updated_at,
      mode: $mode,
      current_step: $current_step,
      steps: $steps,
      resume_hint: $resume_hint,
      artifacts: {
        report_path: $report_path,
        state_path: $state_path
      },
      last_error: null
    }' | write_state
}

state_update() {
  local jq_filter="$1"
  local now
  now="$(timestamp_utc)"
  if [[ ! -f "$STATE_PATH" ]]; then
    init_state
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] state update: ${jq_filter}"
    return 0
  fi
  jq --arg now "$now" "$jq_filter" "$STATE_PATH" | write_state
}

step_status() {
  local step_id="$1"
  if [[ ! -f "$STATE_PATH" ]]; then
    echo "pending"
    return 0
  fi
  jq -r --arg id "$step_id" '.steps[] | select(.id==$id) | .status' "$STATE_PATH"
}

state_mark_step() {
  local step_id="$1"
  local status="$2"
  local err_msg="${3:-}"
  local now
  now="$(timestamp_utc)"

  local filter='(.updated_at=$now) | (.current_step=$id) | (.steps |= map(if .id==$id then .status=$status | .error_message=$msg | (if $status=="running" then .started_at=$now else . end) | (if ($status=="done" or $status=="failed" or $status=="skipped") then .finished_at=$now else . end) else . end))'
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] mark ${step_id} -> ${status}"
    return 0
  fi
  jq --arg id "$step_id" --arg status "$status" --arg msg "$err_msg" --arg now "$now" "$filter" "$STATE_PATH" | write_state
}

state_set_error() {
  local msg="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  jq --arg msg "$msg" --arg now "$(timestamp_utc)" '.updated_at=$now | .last_error=$msg' "$STATE_PATH" | write_state
}

report_init() {
  run_cmd sudo mkdir -p "$(dirname "$REPORT_PATH")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] init report ${REPORT_PATH}"
    return 0
  fi

  cat > "$REPORT_PATH" <<EOF
# TrustTunnel Installer Report

- Run ID: ${RUN_ID:-unknown}
- Mode: ${MODE}
- Started (UTC): $(timestamp_utc)

## Step Results
EOF
}

report_step() {
  local step_id="$1"
  local status="$2"
  local note="${3:-}"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] report step ${step_id}: ${status}"
    return 0
  fi
  {
    echo "- ${step_id}: ${status}"
    if [[ -n "$note" ]]; then
      echo "  - ${note}"
    fi
  } >> "$REPORT_PATH"
}

report_finalize() {
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  {
    echo
    echo "## Resume"
    echo
    echo "- To continue: ./tt-installer.sh resume --state ${STATE_PATH}"
    echo
    echo "## Artifacts"
    echo
    echo "- State: ${STATE_PATH}"
    echo "- Report: ${REPORT_PATH}"
  } >> "$REPORT_PATH"
}

ask_if_missing() {
  local var_name="$1"
  local prompt="$2"
  local secret="${3:-false}"
  local current
  current="${!var_name:-}"
  if [[ -n "$current" ]]; then
    return 0
  fi
  if [[ "$INTERACTIVE" != "true" ]]; then
    return 0
  fi

  local value
  if [[ "$secret" == "true" ]]; then
    read -r -s -p "$prompt: " value
    echo
  else
    read -r -p "$prompt: " value
  fi
  printf -v "$var_name" '%s' "$value"
}

validate_required() {
  local missing=0

  [[ -n "$TT_ENDPOINT_FQDN" ]] || { warn "Missing TT_ENDPOINT_FQDN"; missing=1; }
  [[ -n "$TT_IMAGE" ]] || { warn "Missing TT_IMAGE"; missing=1; }
  [[ "$TT_SETUP_MODE" == "wizard" || "$TT_SETUP_MODE" == "non-interactive" ]] || {
    warn "Invalid TT_SETUP_MODE: $TT_SETUP_MODE (allowed: wizard, non-interactive)"; missing=1;
  }

  case "$TLS_MODE" in
    letsencrypt-http01)
      if [[ "$TT_SETUP_MODE" == "non-interactive" ]]; then
        [[ -n "$LE_EMAIL" ]] || { warn "Missing LE_EMAIL for ${TLS_MODE} in non-interactive mode"; missing=1; }
        [[ -n "$LE_DOMAIN" ]] || { warn "Missing LE_DOMAIN for ${TLS_MODE} in non-interactive mode"; missing=1; }
      fi
      ;;
    letsencrypt-dns01)
      if [[ "$TT_SETUP_MODE" == "non-interactive" ]]; then
        [[ -n "$LE_DOMAIN" ]] || { warn "Missing LE_DOMAIN for ${TLS_MODE} in non-interactive mode"; missing=1; }
      fi
      ;;
    existing-cert)
      [[ -n "$EXISTING_CERT_PATH" ]] || { warn "Missing EXISTING_CERT_PATH"; missing=1; }
      [[ -n "$EXISTING_KEY_PATH" ]] || { warn "Missing EXISTING_KEY_PATH"; missing=1; }
      ;;
    self-signed)
      ;;
    *)
      warn "Invalid TLS_MODE: $TLS_MODE"
      missing=1
      ;;
  esac

  if [[ "$BOT_ENABLE" == "true" ]]; then
    [[ -n "$BOT_IMAGE" ]] || { warn "Missing BOT_IMAGE"; missing=1; }
    [[ -n "$TELEGRAM_BOT_TOKEN" ]] || { warn "Missing TELEGRAM_BOT_TOKEN"; missing=1; }
    [[ -n "$TELEGRAM_ALLOWED_USER_IDS" ]] || { warn "Missing TELEGRAM_ALLOWED_USER_IDS"; missing=1; }
  fi

  [[ "$missing" -eq 0 ]] || die "Required values are missing"
}

command_in_step() {
  local description="$1"
  shift
  log "$description"
  run_cmd "$@"
}

print_check() {
  local label="$1"
  local status="$2"
  local details="${3:-}"
  printf -- "- [%s] %s" "$status" "$label"
  if [[ -n "$details" ]]; then
    printf " (%s)" "$details"
  fi
  printf "\n"
}

resolve_ipv4() {
  local host="$1"
  if [[ -z "$host" ]]; then
    return 1
  fi
  if ! command -v getent >/dev/null 2>&1; then
    return 1
  fi
  getent ahostsv4 "$host" | awk 'NR==1 {print $1}'
}

s00_plan_summary() {
  log "Preflight summary"
  local tt_dns_ip=""
  local le_dns_ip=""
  local dns_ok="no"
  local le_ok="n/a"
  local port80_needed="no"
  local port80_free="n/a"
  local bootstrap_needed="yes"
  local bootstrap_ready="no"

  tt_dns_ip="$(resolve_ipv4 "$TT_ENDPOINT_FQDN" || true)"
  if [[ -n "$tt_dns_ip" ]]; then
    dns_ok="yes"
  fi

  if [[ "$TLS_MODE" == "letsencrypt-http01" || "$TLS_MODE" == "letsencrypt-dns01" ]]; then
    le_dns_ip="$(resolve_ipv4 "$LE_DOMAIN" || true)"
    if [[ -n "$le_dns_ip" ]]; then
      le_ok="yes"
    else
      le_ok="no"
    fi
  fi

  if [[ "$TLS_MODE" == "letsencrypt-http01" ]]; then
    port80_needed="yes"
    if command -v ss >/dev/null 2>&1; then
      if ss -tuln | grep -q ':80 '; then
        port80_free="no"
      else
        port80_free="yes"
      fi
    else
      port80_free="unknown"
    fi
  fi

  if [[ -f "${TT_DATA_DIR}/vpn.toml" && -f "${TT_DATA_DIR}/hosts.toml" && -f "${TT_DATA_DIR}/credentials.toml" ]]; then
    bootstrap_needed="no"
    bootstrap_ready="n/a"
  elif [[ -n "$TT_BOOTSTRAP_USERNAME" && -n "$TT_BOOTSTRAP_PASSWORD" ]]; then
    bootstrap_ready="yes"
  fi

  cat <<EOF
Prepare before apply:
- FQDN: ${TT_ENDPOINT_FQDN:-<not-set>}
- Setup mode: ${TT_SETUP_MODE}
- Domain validation mode: ${TLS_MODE}
- Public image for TrustTunnel: ${TT_IMAGE}
- Public image for admin bot: ${BOT_IMAGE}
- Ensure DNS points to your VPS and required ports are reachable.

Wizard prerequisites:
EOF

  if [[ "$dns_ok" == "yes" ]]; then
    print_check "DNS A record for TT_ENDPOINT_FQDN" "OK" "${TT_ENDPOINT_FQDN} -> ${tt_dns_ip}"
  else
    print_check "DNS A record for TT_ENDPOINT_FQDN" "FAIL" "${TT_ENDPOINT_FQDN:-not set}"
  fi

  if [[ "$le_ok" == "n/a" ]]; then
    print_check "DNS A record for LE_DOMAIN" "SKIP" "not required for ${TLS_MODE}"
  elif [[ "$le_ok" == "yes" ]]; then
    print_check "DNS A record for LE_DOMAIN" "OK" "${LE_DOMAIN} -> ${le_dns_ip}"
  else
    print_check "DNS A record for LE_DOMAIN" "FAIL" "${LE_DOMAIN:-not set}"
  fi

  if [[ "$port80_needed" == "yes" ]]; then
    if [[ "$port80_free" == "yes" ]]; then
      print_check "Port 80 free for ACME HTTP-01" "OK"
    elif [[ "$port80_free" == "no" ]]; then
      print_check "Port 80 free for ACME HTTP-01" "WARN" "port 80 is currently in use"
    else
      print_check "Port 80 free for ACME HTTP-01" "WARN" "unable to verify locally"
    fi
  else
    print_check "Port 80 free for ACME HTTP-01" "SKIP" "not required for ${TLS_MODE}"
  fi

  if [[ "$bootstrap_needed" == "no" ]]; then
    print_check "Bootstrap credentials for setup_wizard" "SKIP" "existing configs detected"
  elif [[ "$bootstrap_ready" == "yes" ]]; then
    print_check "Bootstrap credentials for setup_wizard" "OK" "TT_BOOTSTRAP_USERNAME/TT_BOOTSTRAP_PASSWORD set"
  else
    print_check "Bootstrap credentials for setup_wizard" "FAIL" "set TT_BOOTSTRAP_USERNAME and TT_BOOTSTRAP_PASSWORD"
  fi
}

s01_preflight_system() {
  require_cmd bash
  require_cmd jq
  require_cmd awk
  require_cmd grep
  require_cmd sed
  require_cmd curl
  require_cmd sudo

  [[ "$(uname -s)" == "Linux" ]] || die "This installer supports Linux only"

  if [[ -z "${SSH_CONNECTION:-}" ]]; then
    warn "SSH_CONNECTION is empty. Continue carefully if not using SSH."
  fi

  log "System preflight passed"
}

s02_preflight_dns() {
  [[ -n "$TT_ENDPOINT_FQDN" ]] || { warn "TT_ENDPOINT_FQDN not set; skipping DNS check"; return 0; }
  require_cmd getent

  local resolved_ip
  resolved_ip="$(getent ahostsv4 "$TT_ENDPOINT_FQDN" | awk 'NR==1 {print $1}')"
  [[ -n "$resolved_ip" ]] || die "Could not resolve ${TT_ENDPOINT_FQDN}"

  log "Resolved ${TT_ENDPOINT_FQDN} -> ${resolved_ip}"
  if [[ -n "$TT_DOMAIN_IP_EXPECTED" && "$TT_DOMAIN_IP_EXPECTED" != "$resolved_ip" ]]; then
    die "Domain IP mismatch: expected ${TT_DOMAIN_IP_EXPECTED}, got ${resolved_ip}"
  fi

  if [[ -n "$LE_DOMAIN" ]]; then
    local le_resolved_ip
    le_resolved_ip="$(getent ahostsv4 "$LE_DOMAIN" | awk 'NR==1 {print $1}')"
    [[ -n "$le_resolved_ip" ]] || die "Could not resolve LE_DOMAIN: ${LE_DOMAIN}"
    log "Resolved ${LE_DOMAIN} -> ${le_resolved_ip}"
  fi
}

s03_preflight_ports() {
  require_cmd ss

  if [[ "$TLS_MODE" == "letsencrypt-http01" ]]; then
    if ss -tuln | grep -q ':80 '; then
      warn "Port 80 is already in use. Certbot standalone may fail."
    fi
  fi

  if ss -tuln | grep -q ":${TT_LISTEN_PORT} "; then
    warn "Port ${TT_LISTEN_PORT} is already in use. Ensure this is expected."
  fi

  log "Port preflight complete"
}

s04_collect_or_load_config() {
  ask_if_missing "TT_ENDPOINT_FQDN" "TrustTunnel domain (FQDN)"
  if [[ "$TT_SETUP_MODE" == "non-interactive" ]]; then
    ask_if_missing "LE_EMAIL" "Let's Encrypt email"
  fi
  if [[ "$TT_SETUP_MODE" == "non-interactive" && ( "$TLS_MODE" == "letsencrypt-http01" || "$TLS_MODE" == "letsencrypt-dns01" ) ]]; then
    ask_if_missing "LE_DOMAIN" "Let's Encrypt domain"
  fi

  if [[ "$BOT_ENABLE" == "true" ]]; then
    ask_if_missing "TELEGRAM_BOT_TOKEN" "Telegram bot token" "true"
    ask_if_missing "TELEGRAM_ALLOWED_USER_IDS" "Telegram allowed user ids (comma separated)"
  fi

  validate_required
  log "Config validation complete"
}

s05_write_runtime_files() {
  run_cmd sudo mkdir -p "$INSTALL_ROOT"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  cat > "${INSTALL_ROOT}/resolved.env" <<EOF
TT_DATA_DIR=${TT_DATA_DIR}
TT_CONTAINER_NAME=${TT_CONTAINER_NAME}
TT_IMAGE=${TT_IMAGE}
TT_ENDPOINT_FQDN=${TT_ENDPOINT_FQDN}
TT_LISTEN_PORT=${TT_LISTEN_PORT}
TT_ENABLE_HTTP3=${TT_ENABLE_HTTP3}
TT_NETWORK_MODE=${TT_NETWORK_MODE}
TT_LOG_LEVEL=${TT_LOG_LEVEL}
TLS_MODE=${TLS_MODE}
LE_EMAIL=${LE_EMAIL}
LE_DOMAIN=${LE_DOMAIN}
UFW_ENABLE=${UFW_ENABLE}
F2B_ENABLE=${F2B_ENABLE}
BOT_ENABLE=${BOT_ENABLE}
BOT_CONTAINER_NAME=${BOT_CONTAINER_NAME}
BOT_IMAGE=${BOT_IMAGE}
BOT_ENV_FILE=${BOT_ENV_FILE}
EOF
}

s06_backup_snapshot() {
  local backup_dir
  backup_dir="${INSTALL_ROOT}/backup-$(date +%Y%m%d-%H%M%S)"
  run_cmd sudo mkdir -p "$backup_dir"

  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  [[ -f /etc/ssh/sshd_config ]] && sudo cp /etc/ssh/sshd_config "$backup_dir/sshd_config.bak" || true
  [[ -d "$TT_DATA_DIR" ]] && sudo cp -a "$TT_DATA_DIR" "$backup_dir/trusttunnel-data.bak" || true
  command -v ufw >/dev/null 2>&1 && sudo ufw status verbose > "$backup_dir/ufw-status.txt" || true
  command -v docker >/dev/null 2>&1 && sudo docker ps -a > "$backup_dir/docker-ps.txt" || true

  report_step "s06_backup_snapshot" "done" "Backup stored at ${backup_dir}"
}

s07_setup_ssh_safe() {
  warn "SSH hardening is intentionally conservative in v1. No automatic edits applied."
  warn "Apply manual SSH hardening only after verifying key access."
}

s08_setup_ufw() {
  if [[ "$UFW_ENABLE" != "true" ]]; then
    log "UFW is disabled by config"
    return 0
  fi

  require_cmd ufw
  command_in_step "Allow SSH port ${UFW_ALLOW_SSH_PORT}/tcp" sudo ufw allow "${UFW_ALLOW_SSH_PORT}/tcp"

  if [[ "$UFW_ALLOW_HTTP80" == "true" ]]; then
    command_in_step "Allow 80/tcp" sudo ufw allow 80/tcp
  fi
  if [[ "$UFW_ALLOW_HTTPS443" == "true" ]]; then
    command_in_step "Allow 443/tcp" sudo ufw allow 443/tcp
  fi

  command_in_step "Enable UFW" sudo ufw --force enable
}

s09_setup_fail2ban() {
  if [[ "$F2B_ENABLE" != "true" ]]; then
    log "Fail2ban is disabled by config"
    return 0
  fi

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    command_in_step "Install fail2ban" sudo apt-get update
    command_in_step "Install fail2ban package" sudo apt-get install -y fail2ban
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    sudo mkdir -p /etc/fail2ban/jail.d
    cat <<EOF | sudo tee /etc/fail2ban/jail.d/tt-installer.local >/dev/null
[sshd]
enabled = true
maxretry = ${F2B_SSHD_MAXRETRY}
bantime = ${F2B_BANTIME}
EOF
  fi

  command_in_step "Enable fail2ban" sudo systemctl enable --now fail2ban
}

s10_setup_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    command_in_step "Install Docker packages" sudo apt-get update
    command_in_step "Install docker.io and compose plugin" sudo apt-get install -y docker.io docker-compose-plugin
  fi
  command_in_step "Enable docker service" sudo systemctl enable --now docker
}

s11_prepare_tt_dirs() {
  command_in_step "Create TrustTunnel data dir" sudo mkdir -p "$TT_DATA_DIR"
  command_in_step "Set TrustTunnel data dir ownership" sudo chown -R root:root "$TT_DATA_DIR"
}

s12_prepare_tls() {
  case "$TLS_MODE" in
    letsencrypt-http01)
      log "TLS will be handled by TrustTunnel setup_wizard inside the container (ACME HTTP-01)."
      ;;
    letsencrypt-dns01)
      warn "setup_wizard non-interactive supports ACME HTTP-01 only."
      warn "For DNS-01, prepare certificates manually, then use TLS_MODE=existing-cert."
      ;;
    existing-cert)
      [[ -f "$EXISTING_CERT_PATH" ]] || die "Certificate file not found: $EXISTING_CERT_PATH"
      [[ -f "$EXISTING_KEY_PATH" ]] || die "Key file not found: $EXISTING_KEY_PATH"
      ;;
    self-signed)
      log "TLS will be handled by setup_wizard inside container (self-signed cert mode)."
      warn "Self-signed certificates are not suitable for TrustTunnel Flutter client."
      ;;
    *)
      die "Unsupported TLS_MODE: $TLS_MODE"
      ;;
  esac
}

require_tt_core_files() {
  local missing=0
  local name
  for name in vpn.toml hosts.toml credentials.toml; do
    if [[ ! -f "${TT_DATA_DIR}/${name}" ]]; then
      warn "Missing required file after setup: ${TT_DATA_DIR}/${name}"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || die "TrustTunnel setup did not produce required files"
}

run_setup_wizard_interactive() {
  [[ -t 0 && -t 1 ]] || die "TT_SETUP_MODE=wizard requires an interactive TTY session"

  warn "Starting interactive setup_wizard for initial TrustTunnel configuration"
  warn "In wizard, choose certificate method and save TLS hosts to hosts.toml"

  sudo docker run --rm -it \
    --network "$TT_NETWORK_MODE" \
    --cap-add=NET_ADMIN \
    --device=/dev/net/tun \
    -v "$TT_DATA_DIR:/trusttunnel_endpoint" \
    -v /etc/letsencrypt:/etc/letsencrypt:ro \
    -w /trusttunnel_endpoint \
    --entrypoint /bin/setup_wizard \
    "$TT_IMAGE"
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [[ -f "$src" ]]; then
    command_in_step "Copy $(basename "$src")" sudo cp "$src" "$dst"
    return 0
  fi
  return 1
}

s13_render_tt_configs() {
  local required=("vpn.toml" "hosts.toml" "credentials.toml" "rules.toml")
  local bootstrap_required=("vpn.toml" "hosts.toml" "credentials.toml")
  local name
  local missing=0

  for name in "${required[@]}"; do
    if [[ -f "${TT_DATA_DIR}/${name}" ]]; then
      continue
    fi
    if [[ -n "$TT_CONFIG_SOURCE_DIR" ]]; then
      copy_if_exists "${TT_CONFIG_SOURCE_DIR}/${name}" "${TT_DATA_DIR}/${name}" || true
    fi
  done

  for name in "${bootstrap_required[@]}"; do
    if [[ ! -f "${TT_DATA_DIR}/${name}" ]]; then
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    TT_NEEDS_BOOTSTRAP="false"
    log "Found existing TrustTunnel config set in ${TT_DATA_DIR}"
    if [[ ! -f "${TT_DATA_DIR}/rules.toml" ]]; then
      warn "rules.toml not found in ${TT_DATA_DIR}. Continue only if vpn.toml does not require it."
    fi
    return 0
  fi

  TT_NEEDS_BOOTSTRAP="true"
  if [[ "$TT_SETUP_MODE" == "non-interactive" ]]; then
    [[ -n "$TT_BOOTSTRAP_USERNAME" ]] || die "Config files are missing. Set TT_BOOTSTRAP_USERNAME for first-time non-interactive setup."
    [[ -n "$TT_BOOTSTRAP_PASSWORD" ]] || die "Config files are missing. Set TT_BOOTSTRAP_PASSWORD for first-time non-interactive setup."
  fi

  if [[ "$TLS_MODE" == "letsencrypt-http01" && "$TT_SETUP_MODE" == "non-interactive" ]]; then
    [[ -n "$LE_EMAIL" ]] || die "LE_EMAIL is required for letsencrypt-http01 setup"
  fi

  if [[ "$TLS_MODE" == "letsencrypt-dns01" ]]; then
    die "First-time non-interactive setup with DNS-01 is not supported. Use existing-cert after manual certificate issuance."
  fi
}

s14_deploy_trusttunnel() {
  command_in_step "Pull TrustTunnel image" sudo docker pull "$TT_IMAGE"

  if [[ "$TT_NEEDS_BOOTSTRAP" == "true" && "$TT_SETUP_MODE" == "wizard" ]]; then
    command_in_step "Run TrustTunnel setup_wizard interactively" run_setup_wizard_interactive
    require_tt_core_files
    TT_NEEDS_BOOTSTRAP="false"
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    local cert_type="self-signed"
    local cert_chain_path=""
    local cert_key_path=""

    case "$TLS_MODE" in
      letsencrypt-http01)
        cert_type="letsencrypt"
        ;;
      existing-cert)
        cert_type="provided"
        cert_chain_path="$EXISTING_CERT_PATH"
        cert_key_path="$EXISTING_KEY_PATH"
        if [[ "$cert_chain_path" == "${TT_DATA_DIR}"/* ]]; then
          cert_chain_path="/trusttunnel_endpoint/${cert_chain_path#"${TT_DATA_DIR}/"}"
        fi
        if [[ "$cert_key_path" == "${TT_DATA_DIR}"/* ]]; then
          cert_key_path="/trusttunnel_endpoint/${cert_key_path#"${TT_DATA_DIR}/"}"
        fi
        ;;
      self-signed)
        cert_type="self-signed"
        ;;
    esac

    cat > "${INSTALL_ROOT}/trusttunnel.env" <<EOF
TT_LISTEN_ADDRESS=0.0.0.0:${TT_LISTEN_PORT}
TT_HOSTNAME=${TT_ENDPOINT_FQDN}
TT_CERT_TYPE=${cert_type}
EOF

    if [[ "$cert_type" == "letsencrypt" ]]; then
        cat >> "${INSTALL_ROOT}/trusttunnel.env" <<EOF
TT_ACME_EMAIL=${LE_EMAIL}
EOF
    fi

    if [[ "$cert_type" == "provided" ]]; then
        cat >> "${INSTALL_ROOT}/trusttunnel.env" <<EOF
TT_CERT_PROVIDED_CHAIN_PATH=${cert_chain_path}
TT_CERT_PROVIDED_KEY_PATH=${cert_key_path}
EOF
    fi

    if [[ "$TT_NEEDS_BOOTSTRAP" == "true" && "$TT_SETUP_MODE" == "non-interactive" ]]; then
      cat >> "${INSTALL_ROOT}/trusttunnel.env" <<EOF
TT_CREDENTIALS=${TT_BOOTSTRAP_USERNAME}:${TT_BOOTSTRAP_PASSWORD}
EOF
    fi

    chmod 600 "${INSTALL_ROOT}/trusttunnel.env"

    cat > "${INSTALL_ROOT}/tt-up" <<EOF
#!/usr/bin/env bash
set -euo pipefail
sudo docker rm -f ${TT_CONTAINER_NAME} 2>/dev/null || true
sudo docker run -d \
  --name ${TT_CONTAINER_NAME} \
  --restart unless-stopped \
  --network ${TT_NETWORK_MODE} \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --env-file ${INSTALL_ROOT}/trusttunnel.env \
  -v ${TT_DATA_DIR}:/trusttunnel_endpoint \
  ${TT_IMAGE}
EOF
    chmod +x "${INSTALL_ROOT}/tt-up"

    cat > "${INSTALL_ROOT}/tt-down" <<EOF
#!/usr/bin/env bash
set -euo pipefail
sudo docker rm -f ${TT_CONTAINER_NAME} 2>/dev/null || true
EOF
    chmod +x "${INSTALL_ROOT}/tt-down"
  fi

  command_in_step "Start TrustTunnel container" "${INSTALL_ROOT}/tt-up"
}

s15_verify_trusttunnel() {
  command_in_step "Check TrustTunnel container is running" sudo docker ps --filter "name=${TT_CONTAINER_NAME}"
  command_in_step "Show recent TrustTunnel logs" sudo docker logs --tail=50 "$TT_CONTAINER_NAME"
  if [[ "$TT_NEEDS_BOOTSTRAP" == "true" ]]; then
    log "Initial setup_wizard run expected on first start (missing configs were detected)."
  fi
  [[ -f "${TT_DATA_DIR}/hosts.toml" ]] || die "hosts.toml is missing after TrustTunnel deployment"
}

s16_deploy_admin_bot() {
  if [[ "$BOT_ENABLE" != "true" ]]; then
    log "Admin bot is disabled by config"
    return 0
  fi

  [[ -n "$TELEGRAM_BOT_TOKEN" ]] || die "TELEGRAM_BOT_TOKEN is required when BOT_ENABLE=true"
  [[ -n "$TELEGRAM_ALLOWED_USER_IDS" ]] || die "TELEGRAM_ALLOWED_USER_IDS is required when BOT_ENABLE=true"

  command_in_step "Pull bot image" sudo docker pull "$BOT_IMAGE"

  if [[ "$DRY_RUN" != "true" ]]; then
    sudo mkdir -p "$(dirname "$BOT_ENV_FILE")"
    cat <<EOF | sudo tee "$BOT_ENV_FILE" >/dev/null
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_ALLOWED_USER_IDS=${TELEGRAM_ALLOWED_USER_IDS}
TT_CONTAINER_NAME=${TT_CONTAINER_NAME}
TT_ENDPOINT_ADDRESS=${TT_ENDPOINT_FQDN}:${TT_LISTEN_PORT}
TT_CREDENTIALS_PATH=${BOT_TT_DATA_DIR}/credentials.toml
TT_VPN_CONFIG_PATH_IN_CONTAINER=/trusttunnel_endpoint/vpn.toml
TT_HOSTS_CONFIG_PATH_IN_CONTAINER=/trusttunnel_endpoint/hosts.toml
EOF
    sudo chmod 600 "$BOT_ENV_FILE"
  fi

  command_in_step "Stop old bot container if exists" bash -lc "sudo docker rm -f '${BOT_CONTAINER_NAME}' >/dev/null 2>&1 || true"
  command_in_step "Run bot container" sudo docker run -d --name "$BOT_CONTAINER_NAME" --restart unless-stopped --env-file "$BOT_ENV_FILE" -v "$BOT_TT_DATA_DIR:/opt/trusttunnel" -v /var/run/docker.sock:/var/run/docker.sock "$BOT_IMAGE"
}

s17_verify_admin_bot() {
  if [[ "$BOT_ENABLE" != "true" ]]; then
    return 0
  fi
  command_in_step "Check bot container is running" sudo docker ps --filter "name=${BOT_CONTAINER_NAME}"
  command_in_step "Show recent bot logs" sudo docker logs --tail=40 "$BOT_CONTAINER_NAME"
}

s18_generate_client_link_sample() {
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  if [[ ! -f "${TT_DATA_DIR}/hosts.toml" ]]; then
    warn "hosts.toml is missing; skip sample link generation"
    return 0
  fi
  if ! sudo docker ps --format '{{.Names}}' | grep -qx "$TT_CONTAINER_NAME"; then
    warn "TrustTunnel container is not running; skip sample link generation"
    return 0
  fi

  local sample_user
  sample_user="$(sudo awk -F'"' '/^[[:space:]]*username[[:space:]]*=/{print $2; exit}' "${TT_DATA_DIR}/credentials.toml" || true)"
  if [[ -z "$sample_user" ]]; then
    warn "No user found in credentials.toml; skip sample link generation"
    return 0
  fi

  local endpoint_addr
  endpoint_addr="${TT_ENDPOINT_FQDN}:${TT_LISTEN_PORT}"
  local sample
  sample="$(sudo docker exec "$TT_CONTAINER_NAME" /bin/trusttunnel_endpoint /trusttunnel_endpoint/vpn.toml /trusttunnel_endpoint/hosts.toml -c "$sample_user" -a "$endpoint_addr" || true)"
  if [[ -n "$sample" ]]; then
    report_step "s18_generate_client_link_sample" "done" "Generated sample client link for ${sample_user}"
  else
    warn "Could not generate sample link"
  fi
}

s19_finalize_report() {
  report_finalize
  log "Report written to ${REPORT_PATH}"
}

run_single_step() {
  local step_id="$1"
  local step_func="$step_id"

  if [[ -n "$FROM_STEP" ]]; then
    local ordered
    ordered="$(printf '%s\n' "${ALL_STEPS[@]}" | awk -v f="$FROM_STEP" 'BEGIN{keep=0} {if($0==f) keep=1; if(keep) print $0}')"
    if ! grep -qx "$step_id" <<<"$ordered"; then
      state_mark_step "$step_id" "skipped" "Skipped due to --from-step ${FROM_STEP}"
      report_step "$step_id" "skipped" "Skipped due to --from-step ${FROM_STEP}"
      return 0
    fi
  fi

  local prev_status
  prev_status="$(step_status "$step_id")"
  if [[ "$MODE" == "resume" && "$prev_status" == "done" ]]; then
    log "Skipping done step: ${step_id}"
    return 0
  fi
  if [[ "$MODE" == "apply" && "$prev_status" == "done" ]]; then
    log "Already done: ${step_id}"
    return 0
  fi

  CURRENT_STEP="$step_id"
  state_mark_step "$step_id" "running"
  log "Running ${step_id}"
  if "$step_func"; then
    state_mark_step "$step_id" "done"
    report_step "$step_id" "done"
    CURRENT_STEP=""
    return 0
  fi

  state_mark_step "$step_id" "failed" "Step failed"
  report_step "$step_id" "failed"
  CURRENT_STEP=""
  return 1
}

handle_error() {
  local exit_code="$1"
  local line_no="$2"
  local message="Step ${CURRENT_STEP:-unknown} failed at line ${line_no}"
  warn "$message"
  if [[ -n "$CURRENT_STEP" && -f "$STATE_PATH" ]]; then
    state_mark_step "$CURRENT_STEP" "failed" "$message"
    state_set_error "$message"
    report_step "$CURRENT_STEP" "failed" "$message"
  fi
  if [[ "$RESUME_ON_ERROR" == "true" ]]; then
    warn "Resume with: ./tt-installer.sh resume --state ${STATE_PATH}"
  fi
  exit "$exit_code"
}

run_steps() {
  local -a steps_to_run
  case "$MODE" in
    plan)
      steps_to_run=("${PLAN_STEPS[@]}")
      ;;
    apply|resume)
      steps_to_run=("${ALL_STEPS[@]}")
      ;;
    verify)
      steps_to_run=("s15_verify_trusttunnel" "s17_verify_admin_bot" "s19_finalize_report")
      ;;
    rollback)
      steps_to_run=("s19_finalize_report")
      warn "Rollback automation is not implemented in v1. Use backup artifacts and report hints."
      ;;
    *)
      die "Unsupported mode: ${MODE}"
      ;;
  esac

  local step
  for step in "${steps_to_run[@]}"; do
    run_single_step "$step"
  done
}

prepare_resume_state() {
  [[ -f "$STATE_PATH" ]] || die "State file not found: $STATE_PATH"
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  jq '.steps |= map(if .status=="failed" or .status=="running" then .status="pending" | .error_message=null else . end)' "$STATE_PATH" | write_state
}

main() {
  parse_args "$@"

  require_cmd bash
  require_cmd jq

  load_env_file "$CONFIG_PATH"
  load_env_file "$SECRETS_PATH"
  ensure_paths

  if [[ "$RESET_STATE" == "true" && -f "$STATE_PATH" ]]; then
    run_cmd rm -f "$STATE_PATH"
  fi

  ensure_runtime_dirs

  if [[ "$MODE" == "resume" ]]; then
    prepare_resume_state
  fi

  if [[ ! -f "$STATE_PATH" || "$MODE" == "apply" || "$MODE" == "plan" || "$MODE" == "verify" ]]; then
    init_state
  fi

  report_init

  trap 'handle_error $? $LINENO' ERR

  run_steps

  log "Completed mode: ${MODE}"
  log "State: ${STATE_PATH}"
  log "Report: ${REPORT_PATH}"
}

main "$@"
