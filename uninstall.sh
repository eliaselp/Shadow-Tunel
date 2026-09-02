#!/bin/bash
# ================================================================
#  VPN PERSONAL - DESINSTALADOR
#
#  USO:
#    sudo bash uninstall.sh --server   # limpia el VPS (usa .env)
#    sudo bash uninstall.sh --client   # limpia este equipo (cliente)
#    sudo bash uninstall.sh --all      # ambos
#
#  Solo elimina lo que se toco (WireGuard, AdGuard/dnsmasq, reglas
#  ufw, sysctl, paquetes VPN). NO afecta otros servicios ni usuarios
#  (ssh, fail2ban, cron, snapd, root, etc.).
#
#  El servidor usa las credenciales de .env (user, ip-server, password)
#  o variables VPS_IP / SSH_USER / SSH_PASS / SSH_KEY.
# ================================================================
set -euo pipefail

MODE="${1:-}"
[ -n "$MODE" ] || { echo "Uso: sudo bash uninstall.sh --server | --client | --all"; exit 1; }

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ================================================================
#  UNINSTALL CLIENTE (este equipo)
# ================================================================
uninstall_cliente() {
  [ "$(id -u)" = "0" ] || fail "--client requiere sudo"
  echo "=========================================================="
  echo "  Desinstalando VPN PERSONAL del cliente (este equipo)"
  echo "=========================================================="

  info "Eliminando conexiones NetworkManager tipo WireGuard (interfaz grafica)..."
  mapfile -t WG_CONNS < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wireguard"{print $1}')
  if [ "${#WG_CONNS[@]}" -gt 0 ]; then
    for conn in "${WG_CONNS[@]}"; do
      nmcli connection delete "$conn" && ok "Conexion eliminada: $conn"
    done
  else
    ok "No habia conexiones WireGuard en NetworkManager"
  fi

  info "Eliminando perfiles WireGuard residuales en system-connections..."
  for f in /etc/NetworkManager/system-connections/*.nmconnection; do
    [ -f "$f" ] || continue
    if grep -q '^type=wireguard' "$f"; then
      rm -f "$f" && ok "Perfil eliminado: $(basename "$f")"
    fi
  done

  info "Eliminando configs CLI y directorio /etc/wireguard..."
  [ -d /etc/wireguard ] && rm -rf /etc/wireguard && ok "/etc/wireguard eliminado" || ok "/etc/wireguard no existia"

  info "Eliminando interfaces residuales (laptop/wg0)..."
  for iface in laptop wg0; do
    if ip link show "$iface"; then
      ip link del "$iface" && ok "Interfaz $iface eliminada" || true
    fi
  done

  info "Eliminando claves SSH del administrador VPN (vps_dallas)..."
  for f in /home/*/.ssh/vps_dallas /home/*/.ssh/vps_dallas.pub /root/.ssh/vps_dallas /root/.ssh/vps_dallas.pub; do
    [ -f "$f" ] && rm -f "$f" && ok "Eliminada: $f"
  done

  info "Eliminando logs locales de diagnostico/reparacion..."
  rm -f /home/*/Desktop/dev-agent/Proyectos/VPN-Personal/reparar-vpn.log || true

  ok "CLIENTE LIMPIO."
}

# ================================================================
#  UNINSTALL SERVIDOR (VPS via SSH con .env)
# ================================================================
uninstall_servidor() {
  VPS_IP="${VPS_IP:-}"; SSH_USER="${SSH_USER:-}"; SSH_PASS="${SSH_PASS:-}"; SSH_KEY="${SSH_KEY:-}"
  ENV_FILE="$PROYECTO/.env"
  if [ -f "$ENV_FILE" ]; then
    info "Leyendo credenciales desde $ENV_FILE"
    while IFS='=' read -r k v; do
      k="${k%%[[:space:]]*}"; v="${v#\"}"; v="${v%\"}"
      [ -z "$k" ] || [ "${k#\#}" != "$k" ] && continue
      case "$k" in
        user)        [ -z "$SSH_USER" ] && SSH_USER="$v";;
        ip-server|ip_server|ip) [ -z "$VPS_IP" ] && VPS_IP="$v";;
        password)    [ -z "$SSH_PASS" ] && SSH_PASS="$v";;
        ssh-key|ssh_key) [ -z "$SSH_KEY" ] && SSH_KEY="$v";;
      esac
    done < "$ENV_FILE"
  fi
  [ -n "$VPS_IP" ]   || read -rp "IP del VPS: " VPS_IP
  [ -n "$SSH_USER" ] || read -rp "Usuario SSH [root]: " SSH_USER; SSH_USER="${SSH_USER:-root}"
  if [ -z "$SSH_KEY" ] && [ -z "$SSH_PASS" ]; then
    read -rsp "Contrasena SSH: " SSH_PASS; echo ""
  fi

  SSHPASS_BIN=""
  for c in "$(command -v sshpass || true)" "$HOME/.local/bin/sshpass" "/usr/local/bin/sshpass" "/usr/bin/sshpass" /home/*/.local/bin/sshpass; do
    [ -n "$c" ] && [ -x "$c" ] && SSHPASS_BIN="$c" && break
  done
  if [ -n "$SSH_PASS" ] && [ -z "$SSHPASS_BIN" ]; then
    APT_INSTALL="apt-get"; [ "$(id -u)" != "0" ] && APT_INSTALL="sudo apt-get"
    info "Instalando sshpass localmente..."
    $APT_INSTALL update || true
    $APT_INSTALL install -y sshpass || warn "No se pudo instalar sshpass; usa clave SSH."
    for c in "$(command -v sshpass || true)" /home/*/.local/bin/sshpass; do
      [ -n "$c" ] && [ -x "$c" ] && SSHPASS_BIN="$c" && break
    done
    [ -n "$SSHPASS_BIN" ] || warn "sshpass no disponible; se usara SSH interactivo."
  fi

  SSH_BASE=(-o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new)
  ssh_run() {
    if [ -n "$SSH_PASS" ] && [ -n "$SSHPASS_BIN" ]; then
      "$SSHPASS_BIN" -p "$SSH_PASS" ssh "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
    elif [ -n "$SSH_KEY" ]; then
      ssh -i "$SSH_KEY" "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
    else
      ssh "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
    fi
  }

  echo "=========================================================="
  echo "  Desinstalando VPN PERSONAL del servidor $VPS_IP"
  echo "=========================================================="
  # Limpiar conexiones SSH multiplexadas previas (evita colgarse con sockets obsoletos)
  pkill -f "ssh: /tmp/ssh-uninstall-" 2>/dev/null || true
  pkill -f "ssh: /tmp/ssh-vpn-" 2>/dev/null || true
  rm -f /tmp/ssh-uninstall-* /tmp/ssh-vpn-* 2>/dev/null || true

  info "Probando conexion SSH a ${SSH_USER}@${VPS_IP}..."
  REMOTE_UID=$(ssh_run 'id -u' | tr -d '\r')
  [ -n "$REMOTE_UID" ] || fail "No se pudo conectar por SSH."
  RUN_AS_SUDO=""
  [ "$REMOTE_UID" != "0" ] && RUN_AS_SUDO="sudo"

  REMOTE="/tmp/opencode/uninstall-server-$$.sh"
  cat > "$REMOTE" <<'REMOTETPL'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==== [1/7] Deteniendo servicios de la VPN ===="
systemctl stop wg-quick@wg0 || true
systemctl disable wg-quick@wg0 || true
systemctl stop AdGuardHome || true
systemctl disable AdGuardHome || true
systemctl stop dnsmasq || true
systemctl disable dnsmasq || true

echo "==== [2/7] Eliminando reglas ufw de la VPN (se mantiene SSH) ===="
ufw --force delete allow in on wg0 || true
ufw --force delete allow 51820/udp || true
ufw reload || true

echo "==== [3/7] Eliminando archivos de la VPN ===="
rm -rf /etc/wireguard
rm -rf /opt/AdGuardHome
rm -f /etc/systemd/system/AdGuardHome.service
rm -f /etc/dnsmasq.d/wireguard.conf
rm -f /etc/sysctl.d/99-wireguard.conf
rm -f /usr/local/bin/wg-add-peer.sh /usr/local/bin/wg-healthcheck.sh
rm -f /etc/cron.d/wg-healthcheck
systemctl daemon-reload || true

echo "==== [4/7] Restaurando sysctl y limpiando iptables ===="
sysctl -w net.ipv4.ip_forward=0 || true
DEF_IF=$(ip route | awk '/^default/{print $5; exit}'); DEF_IF=${DEF_IF:-eth0}
iptables -t nat -D POSTROUTING -o "$DEF_IF" -j MASQUERADE || true
iptables -D FORWARD -i wg0 -j ACCEPT || true
iptables -D FORWARD -o wg0 -j ACCEPT || true
iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true
iptables -D INPUT -i wg0 -j ACCEPT || true

echo "==== [5/7] Desinstalando paquetes instalados por la VPN ===="
apt-get purge -y wireguard wireguard-tools openresolv dnsmasq qrencode dnsmasq-base dns-root-data libqrencode4 || true
apt-get autoremove -y || true

echo "==== [6/7] VERIFICACION ===="
echo "-- wg0 --";        ip link show wg0 2>&1 | head -1 || true
echo "-- servicios VPN --"; systemctl is-active wg-quick@wg0 AdGuardHome dnsmasq 2>&1 || true
echo "-- ufw --";        ufw status verbose 2>&1 | head -10
echo "-- /etc/wireguard --"; ls -d /etc/wireguard 2>&1 || echo "OK: no existe"
echo "-- /opt/AdGuardHome --"; ls -d /opt/AdGuardHome 2>&1 || echo "OK: no existe"
echo "-- sysctl --";     sysctl net.ipv4.ip_forward 2>&1
echo "-- paquetes --";   dpkg -l | grep -iE "wireguard|adguard|dnsmasq" || echo "OK: sin paquetes VPN"
echo "-- iptables nat --"; iptables -t nat -L POSTROUTING -n 2>&1 | head -4
echo "-- iptables mangle --"; iptables -t mangle -L FORWARD -n 2>&1 | head -3

echo "==== [7/7] Servicios ajenos siguen activos ===="
for s in ssh fail2ban cron unattended-upgrades snapd qemu-guest-agent; do
  printf "%-22s %s\n" "$s" "$(systemctl is-active $s 2>&1)"
done
echo "UNINSTALL_SERVER_DONE=1"
REMOTETPL

  info "Ejecutando desinstalacion en el servidor..."
  ssh_run $RUN_AS_SUDO bash -s < "$REMOTE" || fail "La desinstalacion remota fallo."
  rm -f "$REMOTE"
  ok "SERVIDOR LIMPIO."
}

# ================================================================
case "$MODE" in
  --client) uninstall_cliente ;;
  --server) uninstall_servidor ;;
  --all)    uninstall_cliente; uninstall_servidor ;;
  *) echo "Uso: sudo bash uninstall.sh --server | --client | --all"; exit 1 ;;
esac