#!/usr/bin/env bash
set -Eeuo pipefail

SYSCTL_FILE="/etc/sysctl.d/99-xray-tune.conf"
MODULES_FILE="/etc/modules-load.d/nf_conntrack.conf"
SYSTEMD_CONF="/etc/systemd/system.conf"
SYSTEMD_USER_CONF="/etc/systemd/user.conf"
BACKUP_SUFFIX=".bak.$(date +%F-%H%M%S)"

log()  { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
err()  { echo -e "[ERR ] $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запусти скрипт от root"
    exit 1
  fi
}

detect_os() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-unknown}"
  else
    err "/etc/os-release не найден"
    exit 1
  fi

  case "${OS_ID}" in
    debian|ubuntu)
      log "Обнаружена система: ${OS_NAME}"
      ;;
    *)
      err "Поддерживаются только Debian/Ubuntu. Найдено: ${OS_NAME}"
      exit 1
      ;;
  esac
}

backup_if_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp -a "$file" "${file}${BACKUP_SUFFIX}"
    log "Бэкап создан: ${file}${BACKUP_SUFFIX}"
  fi
}

ensure_dir() {
  mkdir -p /etc/sysctl.d /etc/modules-load.d
}

load_conntrack_module() {
  if modprobe -n nf_conntrack >/dev/null 2>&1; then
    if lsmod | grep -q '^nf_conntrack'; then
      log "Модуль nf_conntrack уже загружен"
    else
      modprobe nf_conntrack || warn "Не удалось загрузить nf_conntrack прямо сейчас"
    fi
    echo "nf_conntrack" > "$MODULES_FILE"
    log "Автозагрузка nf_conntrack записана в $MODULES_FILE"
  else
    warn "Модуль nf_conntrack недоступен в этой системе/ядре"
  fi
}

write_sysctl_file() {
  backup_if_exists "$SYSCTL_FILE"

  cat > "$SYSCTL_FILE" <<'EOF'
# Xray/Remnawave tuning
# Safe for Debian/Ubuntu, unknown keys are skipped by apply function

# Conntrack
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_buckets = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 1800
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30

# TCP / queues
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_slow_start_after_idle = 0

# Congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Buffers
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 33554432
net.ipv4.tcp_wmem = 4096 1048576 33554432

# File descriptors
fs.file-max = 1048576
fs.nr_open = 1048576
EOF

  log "Создан файл $SYSCTL_FILE"
}

apply_sysctl_safely() {
  local applied=0
  local skipped=0

  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    local key value proc_path
    key="$(echo "$line" | cut -d= -f1 | xargs)"
    value="$(echo "$line" | cut -d= -f2- | xargs)"
    proc_path="/proc/sys/${key//./\/}"

    if [[ -e "$proc_path" ]]; then
      if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
        log "Применено: ${key}=${value}"
        applied=$((applied + 1))
      else
        warn "Не удалось применить: ${key}"
      fi
    else
      warn "Пропущено (нет параметра в ядре): ${key}"
      skipped=$((skipped + 1))
    fi
  done < "$SYSCTL_FILE"

  log "sysctl: применено ${applied}, пропущено ${skipped}"
}

set_systemd_nofile() {
  for file in "$SYSTEMD_CONF" "$SYSTEMD_USER_CONF"; do
    [[ -f "$file" ]] || touch "$file"
    backup_if_exists "$file"

    if grep -Eq '^[#[:space:]]*DefaultLimitNOFILE=' "$file"; then
      sed -i 's/^[#[:space:]]*DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' "$file"
    else
      printf '\nDefaultLimitNOFILE=1048576\n' >> "$file"
    fi
    log "Установлен DefaultLimitNOFILE=1048576 в $file"
  done

  systemctl daemon-reexec || warn "systemctl daemon-reexec завершился с ошибкой"
}

show_result() {
  echo
  log "Проверка итоговых значений:"
  sysctl net.core.somaxconn 2>/dev/null || true
  sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true
  sysctl fs.file-max 2>/dev/null || true
  sysctl fs.nr_open 2>/dev/null || true
  sysctl net.netfilter.nf_conntrack_max 2>/dev/null || true
  systemctl show | grep DefaultLimitNOFILE || true
}

main() {
  require_root
  detect_os
  ensure_dir
  load_conntrack_module
  write_sysctl_file
  apply_sysctl_safely
  set_systemd_nofile
  show_result

  echo
  log "Готово."
}

main "$@"