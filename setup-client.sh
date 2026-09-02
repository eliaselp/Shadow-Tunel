#!/bin/bash
# ================================================================
#  VPN PERSONAL - SETUP CLIENTE LINUX (Zorin/Ubuntu/Debian)
#
#  Configura el dispositivo y lo deja COMPLETAMENTE listo:
#    - Dependencias (wireguard-tools, openresolv, qrencode, ...)
#    - Config en /etc/wireguard (modo CLI wg-quick)
#    - Conexion grafica en NetworkManager (estilo ProtonVPN:
#      DNS prioritario, ignora DNS del WiFi, IPv6 off, MTU 1280)
#    - AmneziaVPN opcional (descarga con wget -c y progreso visible)
#    - Verificacion completa (handshake, DNS, IP publica)
#
#  USO:  sudo bash setup-client.sh [dispositivo]
#    dispositivo: laptop (default) | movil | pc
#
#  NOTA: no se oculta nada del output: quieres ver el proceso completo.
# ================================================================
set -euo pipefail

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENTES_DIR="$PROYECTO/clientes"
DISPOSITIVO="${1:-laptop}"
CONF="$CLIENTES_DIR/$DISPOSITIVO.conf"
# IP del servidor derivada del Endpoint de la config (para verificacion)
VPS_IP="$(awk '/^Endpoint/{split($3,a,":"); print a[1]}' "$CONF")"
[ -n "$VPS_IP" ] || VPS_IP="TU_IP_DEL_VPS"

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# ---------- limpiar configuracion previa de este dispositivo ----------
limpiar_existente() {
  info "Limpiando configuracion previa de '$DISPOSITIVO' (si existe)..."
  # Interfaz grafica: conexion en NetworkManager
  if nmcli connection show "$DISPOSITIVO"; then
    nmcli connection delete "$DISPOSITIVO"
    ok "Conexion NetworkManager '$DISPOSITIVO' eliminada"
  fi
  # Perfil residual en system-connections (por si queda)
  rm -f "/etc/NetworkManager/system-connections/${DISPOSITIVO}.nmconnection"
  # Modo CLI
  rm -f "/etc/wireguard/${DISPOSITIVO}.conf"
  # Interfaz residual
  if ip link show "$DISPOSITIVO"; then
    ip link del "$DISPOSITIVO" || true
    ok "Interfaz '$DISPOSITIVO' residual eliminada"
  fi
  ok "Limpieza de '$DISPOSITIVO' completada"
}

echo "=========================================================="
echo "  VPN PERSONAL - Setup de Cliente Linux (Zorin/Ubuntu)"
echo "  Dispositivo: $DISPOSITIVO | Servidor: $VPS_IP (Dallas)"
echo "=========================================================="

[ "$(id -u)" = "0" ] || fail "Ejecuta con sudo:  sudo bash setup-client.sh $DISPOSITIVO"
[ -f "$CONF" ] || fail "No existe $CONF. Generalo con setup-server.sh o copialo a clientes/."

limpiar_existente

if ! grep -q '^MTU' "$CONF"; then
  warn "Agregando MTU = 1280 (necesario en redes celulares/hotspot)..."
  sed -i '0,/^\[Interface\]/a MTU = 1280' "$CONF"
fi

# ---------- 1) dependencias (output completo, nada oculto) ----------
info "Verificando/instalando dependencias (wireguard-tools, openresolv, qrencode, curl, wget, dnsutils)..."
apt-get update
apt-get install -y wireguard-tools openresolv qrencode curl wget dnsutils || \
  apt-get install -y wireguard-tools openresolv qrencode curl wget bind9-dnsutils || \
  apt-get install -y wireguard-tools openresolv qrencode curl wget
ok "Dependencias listas"

# ---------- 2) config CLI ----------
info "Instalando config $DISPOSITIVO en /etc/wireguard/ (para wg-quick CLI)..."
install -m 600 "$CONF" "/etc/wireguard/$DISPOSITIVO.conf"
ok "Config copiada: /etc/wireguard/$DISPOSITIVO.conf"

# ---------- 3) interfaz grafica NetworkManager (estilo ProtonVPN) ----------
info "Configurando interfaz grafica (NetworkManager / applet del panel)..."
nmcli connection import type wireguard file "$CONF"
nmcli connection modify "$DISPOSITIVO" \
  connection.autoconnect no \
  ipv4.dns 10.66.66.1 \
  ipv4.dns-search "~" \
  ipv4.dns-priority -1500 \
  ipv4.ignore-auto-dns yes \
  ipv6.method disabled \
  wireguard.mtu 1280
ok "Conexion '$DISPOSITIVO' configurada (MTU 1280, DNS prioritario, sin IPv6)"

info "Activando VPN ahora..."
nmcli connection up "$DISPOSITIVO"
ok "VPN activa. La veras en: Icono de red -> VPN -> $DISPOSITIVO"

# ---------- 4) AmneziaVPN opcional (wget -c, progreso visible) ----------
read -rp "¿Instalar AmneziaVPN (app visual con boton Conectar)? [s/N]: " ans
if [[ "$ans" =~ ^[sSyY]$ ]]; then
  instalar_amneziavpn
else
  info "Omitiendo AmneziaVPN. Puedes conectarte desde el icono de red -> VPN -> $DISPOSITIVO"
fi

# ---------- 5) verificacion completa ----------
verificar_conexion

# ================================================================
instalar_amneziavpn() {
  info "AmneziaVPN (app dedicada con GUI, open source)..."
  local BIN=""
  for c in "$HOME/AmneziaVPN/AmneziaVPN" "/opt/AmneziaVPN/AmneziaVPN" "$HOME/.local/bin/amneziavpn"; do
    [ -x "$c" ] && BIN="$c" && break
  done
  if [ -n "$BIN" ]; then
    ok "AmneziaVPN ya esta instalado: $BIN"
    return 0
  fi

  local TAG URL ARCHIVO
  TAG=$(curl --max-time 30 https://api.github.com/repos/amnezia-vpn/amnezia-client/releases/latest \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['tag_name'])" || true)
  [ -n "$TAG" ] || { warn "No se pudo obtener la ultima version; usando 5.0.1.5"; TAG="5.0.1.5"; }

  URL="https://github.com/amnezia-vpn/amnezia-client/releases/download/${TAG}/AmneziaVPN_${TAG}_linux_x64.run"
  if ! wget --spider "$URL"; then
    warn "URL directa no disponible para $TAG; descubriendo asset desde la API..."
    URL=$(curl --max-time 30 "https://api.github.com/repos/amnezia-vpn/amnezia-client/releases/latest" \
          | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('assets',[]):
    n=a['name'].lower()
    if 'linux' in n and 'x64' in n and n.endswith('.run'):
        print(a['browser_download_url']); sys.exit()
" || true)
  fi
  [ -n "$URL" ] || fail "No se encontro instalador Linux para AmneziaVPN. Descargalo manualmente desde https://github.com/amnezia-vpn/amnezia-client/releases"

  ARCHIVO="/tmp/opencode/amneziavpn_${TAG}.run"
  if [ ! -s "$ARCHIVO" ]; then
    info "Descargando con wget -c (reanudable, con progreso):"
    echo "    $URL"
    wget -c --tries=3 --timeout=30 -O "$ARCHIVO" "$URL"
  else
    ok "Archivo ya descargado: $ARCHIVO"
  fi
  chmod +x "$ARCHIVO"

  info "Instalando dependencias xcb requeridas por AmneziaVPN..."
  apt-get install -y libxcb-cursor0 libxcb-xinerama0 libxcb-icccm4 libxcb-keysyms1 libopengl0 libxkbcommon-x11-0 || true

  info "Ejecutando el instalador de AmneziaVPN (silencioso)..."
  "$ARCHIVO" --accept-licenses yes --default-answer yes --confirm-command yes --root "$HOME/AmneziaVPN" \
    || warn "La instalacion pudo requerir interaccion. Si no quedo instalado, ejecuta: $ARCHIVO"

  BIN=""
  for c in "$HOME/AmneziaVPN/AmneziaVPN" "$HOME/AmneziaVPN/amneziavpn"; do
    [ -x "$c" ] && BIN="$c" && break
  done
  if [ -n "$BIN" ]; then
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/AmneziaVPN.desktop" <<EOF
[Desktop Entry]
Name=AmneziaVPN
Comment=VPN personal (WireGuard) - VPS Dallas
Exec=$BIN
Type=Application
Categories=Network;VPN;
Terminal=false
EOF
    ok "AmneziaVPN instalado: $BIN (buscalo en el menu de aplicaciones)"
  else
    warn "No se pudo detectar el binario de AmneziaVPN. Buscalo en el menu o ejecuta: $ARCHIVO"
  fi
}

# ================================================================
verificar_conexion() {
  info "===== VERIFICACION DE CONEXION ====="
  sleep 3
  echo "--- Estado del tunel ($DISPOSITIVO) ---"
  ip -4 addr show "$DISPOSITIVO" || true
  echo ""
  echo "--- Handshake y transferencia ---"
  wg show "$DISPOSITIVO" || true
  echo ""
  echo "--- DNS del tunel ---"
  resolvectl status "$DISPOSITIVO" || true
  echo ""
  echo "--- Ping 8.8.8.8 ---"
  ping -c 2 -W 2 8.8.8.8 2>&1 | tail -2 || true
  echo "--- MTU grande (debe pasar con -s 1200) ---"
  ping -M do -c 2 -W 2 -s 1200 8.8.8.8 2>&1 | tail -2 || true
  echo "--- DNS del tunel: dig @10.66.66.1 google.com ---"
  timeout 6 dig @10.66.66.1 google.com A +short 2>&1 || true
  echo "--- IP publica (debe ser $VPS_IP = Dallas) ---"
  IP_PUB=$(timeout 10 curl https://api.ipify.org || echo "??")
  echo "IP publica: $IP_PUB"
  echo ""
  if [ "$IP_PUB" = "$VPS_IP" ]; then
    ok "CONEXION EXITOSA: todo tu trafico sale por $VPS_IP (Dallas)."
  else
    warn "La IP publica no coincide con el VPS. Revisa el estado de la conexion."
  fi
}