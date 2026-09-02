#!/bin/bash
# ================================================================
#  VPN PERSONAL - SETUP SERVIDOR (VPS)
#
#  Despliega en un VPS el servidor completo de la VPN:
#    - WireGuard (wg0) con TODAS las claves necesarias
#    - NAT / firewall NO INVASIVO (no afecta otros servicios ni
#      usuarios; no enciende ufw si estaba apagado)
#    - DNS del tunel: AdGuard Home (bloqueo de anuncios) o dnsmasq
#    - Genera las configs de clientes (laptop/movil/pc) + QR
#
#  CREDENCIALES: lee el archivo .env (misma carpeta):
#      user=root
#      ip-server=TU_IP_DEL_VPS
#      password=TU_CONTRASENA
#    (o variables de entorno VPS_IP / SSH_USER / SSH_PASS / SSH_KEY)
#    Si no hay .env, pregunta de forma interactiva.
#
#  USO:  bash setup-server.sh
#  Requisitos: ssh, sshpass (si usas contrasena), wireguard-tools
#              (wg), qrencode, curl
# ================================================================
set -euo pipefail

# ---------- utilidades ----------
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $*"; }
warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENTES_DIR="$PROYECTO/clientes"
if [ ! -d "$CLIENTES_DIR" ]; then
  info "Creando carpeta clientes/ ..."
  mkdir -p "$CLIENTES_DIR"
  ok "Carpeta creada: $CLIENTES_DIR"
fi

WG_SUBNET="10.66.66.0/24"
WG_SERVER_IP="10.66.66.1"
WG_PORT="51820"
declare -A DEV_IPS=( [laptop]="10.66.66.3" [movil]="10.66.66.2" [pc]="10.66.66.4" )
DEVICES=(laptop movil pc)

echo "=========================================================="
echo "  VPN PERSONAL - SETUP SERVIDOR (WireGuard + DNS)"
echo "=========================================================="

# ---------- credenciales del VPS ----------
VPS_IP="${VPS_IP:-}"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"
SSH_PASS="${SSH_PASS:-}"

# Cargar credenciales desde .env si existe
ENV_FILE="$PROYECTO/.env"
if [ -f "$ENV_FILE" ]; then
  info "Leyendo credenciales desde $ENV_FILE"
  while IFS='=' read -r k v; do
    k="${k%%[[:space:]]*}"
    v="${v#\"}"; v="${v%\"}"
    [ -z "$k" ] || [ "${k#\#}" != "$k" ] && continue
    case "$k" in
      user)        [ -z "$SSH_USER" ] && SSH_USER="$v";;
      ip-server|ip_server|ip) [ -z "$VPS_IP" ] && VPS_IP="$v";;
      password)    [ -z "$SSH_PASS" ] && SSH_PASS="$v";;
      ssh-key|ssh_key) [ -z "$SSH_KEY" ] && SSH_KEY="$v";;
    esac
  done < "$ENV_FILE"
  ok "Credenciales cargadas desde .env (user=$SSH_USER, ip-server=$VPS_IP)"
else
  warn "No existe $ENV_FILE; se usaran prompts interactivos. Crea un .env con: user=..., ip-server=..., password=..."
fi

# Completar lo que falte de forma interactiva
[ -n "$VPS_IP" ]   || read -rp "IP del VPS [TU_IP_DEL_VPS]: " VPS_IP
VPS_IP="${VPS_IP:-TU_IP_DEL_VPS}"
[ -n "$SSH_USER" ] || read -rp "Usuario SSH [root]: " SSH_USER
SSH_USER="${SSH_USER:-root}"
if [ -z "$SSH_KEY" ] && [ -z "$SSH_PASS" ]; then
  read -rp "Clave SSH privada (ruta) o Enter para usar contrasena: " SSH_KEY
fi
if [ -z "$SSH_PASS" ] && [ -z "$SSH_KEY" ]; then
  read -rsp "Contrasena SSH (se usara para conectar): " SSH_PASS
  echo ""
fi

SSH_BASE=(-o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
  -o ControlMaster=auto -o ControlPath="/tmp/ssh-vpn-%r@%h:%p" -o ControlPersist=300)
ssh_run() {
  if [ -n "$SSH_PASS" ] && [ -n "$SSHPASS_BIN" ]; then
    "$SSHPASS_BIN" -p "$SSH_PASS" ssh "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
  elif [ -n "$SSH_KEY" ]; then
    ssh -i "$SSH_KEY" "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
  else
    ssh "${SSH_BASE[@]}" "${SSH_USER}@${VPS_IP}" "$@"
  fi
}

# ---------- herramientas locales (se instalan si faltan) ----------
APT_INSTALL="apt-get"
[ "$(id -u)" != "0" ] && APT_INSTALL="sudo apt-get"

paquete_local() {  # $1=paquete, $2=binario
  local pkg="$1" bin="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    info "Falta '$bin'; instalando $pkg automaticamente..."
    $APT_INSTALL update
    $APT_INSTALL install -y "$pkg"
  fi
  command -v "$bin" >/dev/null 2>&1 || fail "No se pudo instalar $pkg. Instalalo manualmente o revisa los repositorios."
  ok "$pkg disponible ($bin)"
}

paquete_local wireguard-tools wg
paquete_local qrencode qrencode

# Localizar sshpass (puede estar en ~/.local/bin del usuario aunque el
# script se ejecute con sudo, donde el PATH es el de root).
SSHPASS_BIN=""
for c in "$(command -v sshpass 2>/dev/null || true)" \
         "$HOME/.local/bin/sshpass" \
         "/usr/local/bin/sshpass" \
         "/usr/bin/sshpass" \
         /home/*/.local/bin/sshpass; do
  if [ -n "$c" ] && [ -x "$c" ]; then SSHPASS_BIN="$c"; break; fi
done
if [ -n "$SSH_PASS" ] && [ -z "$SSHPASS_BIN" ]; then
  info "Falta 'sshpass'; instalando automaticamente..."
  $APT_INSTALL update
  $APT_INSTALL install -y sshpass
  for c in "$(command -v sshpass 2>/dev/null || true)" \
           "$HOME/.local/bin/sshpass" \
           "/usr/local/bin/sshpass" \
           "/usr/bin/sshpass" \
           /home/*/.local/bin/sshpass; do
    if [ -n "$c" ] && [ -x "$c" ]; then SSHPASS_BIN="$c"; break; fi
  done
  if [ -n "$SSHPASS_BIN" ]; then
    ok "sshpass instalado y localizado: $SSHPASS_BIN"
  else
    fail "No se pudo instalar sshpass. Instalalo manualmente o usa una clave SSH en .env."
  fi
else
  ok "sshpass localizado: ${SSHPASS_BIN:-no necesario}"
fi

info "Probando conexion SSH a ${SSH_USER}@${VPS_IP}..."
REMOTE_UID=$(ssh_run 'id -u' | tr -d '\r')
[ -n "$REMOTE_UID" ] || fail "No se pudo conectar por SSH."
RUN_AS_SUDO=""
if [ "$REMOTE_UID" != "0" ]; then
  RUN_AS_SUDO="sudo"
  warn "El usuario no es root; se usara 'sudo' en el servidor."
fi
ok "Conexion SSH establecida (uid=$REMOTE_UID)."

# ---------- claves de dispositivos ----------
REUSE="no"
if ls "$CLIENTES_DIR"/*.conf >/dev/null 2>&1; then
  read -rp "Existen configs en clientes/. ¿Reutilizar sus claves? (s=no romper dispositivos actuales) [s/N]: " ans
  [[ "$ans" =~ ^[sSyY]$ ]] && REUSE="yes"
fi

declare -A DEV_PRIV DEV_PUB DEV_PSK
SRV_PRIV=""
SRV_PUB=""

if [ "$REUSE" = "yes" ]; then
  if [ -f "$CLIENTES_DIR/laptop.conf" ]; then
    SRV_PUB=$(awk '/^\[Peer\]/{f=1} f && /^PublicKey/{print $3; exit}' "$CLIENTES_DIR/laptop.conf")
  fi
  if [ -z "$SRV_PUB" ]; then
    warn "No se pudo extraer la clave publica del servidor de clientes/laptop.conf; se generara todo nuevo."
    REUSE="no"
  fi
fi

for dev in "${DEVICES[@]}"; do
  if [ "$REUSE" = "yes" ] && [ -f "$CLIENTES_DIR/$dev.conf" ]; then
    priv=$(awk '/^PrivateKey/{print $3}' "$CLIENTES_DIR/$dev.conf")
    psk=$(awk '/^PresharedKey/{print $3}' "$CLIENTES_DIR/$dev.conf")
    if [ -z "$priv" ] || [ -z "$psk" ]; then
      fail "La config clientes/$dev.conf esta incompleta. Borrala o regenera."
    fi
    ok "Reutilizando claves de $dev (${DEV_IPS[$dev]})"
  else
    info "Generando claves para $dev (${DEV_IPS[$dev]})..."
    priv=$(wg genkey)
    psk=$(wg genpsk)
    ok "Claves generadas para $dev"
  fi
  pub=$(printf '%s' "$priv" | wg pubkey)
  DEV_PRIV[$dev]="$priv"; DEV_PUB[$dev]="$pub"; DEV_PSK[$dev]="$psk"
done

if [ "$REUSE" != "yes" ]; then
  info "Generando par de claves del servidor..."
  SRV_PRIV=$(wg genkey)
  SRV_PUB=$(printf '%s' "$SRV_PRIV" | wg pubkey)
  ok "Clave publica del servidor: $SRV_PUB"
else
  warn "Se reutilizara la clave privada del servidor ya existente en /etc/wireguard/wg0.conf."
fi

# ---------- DNS del tunel ----------
read -rp "¿Instalar AdGuard Home (DNS + bloqueo de anuncios)? [S/n]: " ans
INSTALL_ADGUARD="yes"
[[ "$ans" =~ ^[nN]$ ]] && INSTALL_ADGUARD="no"

# ---------- script remoto ----------
OUTPUT="/tmp/opencode/setup-server-output-$$.log"
REMOTE="/tmp/opencode/setup-server-remote-$$.sh"
cat > "$REMOTE" <<'REMOTETPL'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==== [1/6] Instalando dependencias del sistema ===="
apt-get update
apt-get install -y wireguard wireguard-tools qrencode openresolv ufw curl openssl python3

echo "==== [2/6] Habilitando forwarding IPv4 ===="
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo "==== [3/6] Configurando firewall (NO INVASIVO) ===="
# NO se enciende ufw ni se cambia su politica. Si ufw ya estaba activo se
# anaden SOLO las reglas minimas de la VPN. Si no, las reglas se aplican
# via iptables scoped a wg0 (PostUp) sin afectar a otros servicios.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  echo "ufw ya activo: anadiendo reglas minimas (51820/udp, wg0) sin tocar la politica."
  ufw allow 51820/udp >/dev/null 2>&1 || true
  ufw allow in on wg0 >/dev/null 2>&1 || true
  ufw reload >/dev/null 2>&1 || true
else
  echo "ufw inactivo/ausente: NO se toca la politica de firewall global."
  echo "Las reglas de la VPN se aplican via iptables en PostUp de wg0."
fi

echo "==== [4/6] Escribiendo /etc/wireguard/wg0.conf ===="
DEF_IF=$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')
DEF_IF=${DEF_IF:-eth0}
echo "Interfaz de salida detectada: $DEF_IF"

SRV_PRIV='__SRV_PRIV__'
if [ -z "$SRV_PRIV" ] && [ -f /etc/wireguard/wg0.conf ] && grep -q '^PrivateKey' /etc/wireguard/wg0.conf; then
  SRV_PRIV=$(awk '/^PrivateKey/{print $3}' /etc/wireguard/wg0.conf | head -1)
  echo "[INFO] Reutilizando clave privada del servidor existente."
fi
[ -n "$SRV_PRIV" ] || { echo "[ERROR] No hay clave privada de servidor disponible."; exit 1; }

mkdir -p /etc/wireguard
umask 077
cat > /etc/wireguard/wg0.conf <<WGEOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = ${SRV_PRIV}
PostUp = iptables -t nat -A POSTROUTING -o ${DEF_IF} -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; iptables -A INPUT -i wg0 -j ACCEPT
PreDown = iptables -t nat -D POSTROUTING -o ${DEF_IF} -j MASQUERADE || true; iptables -D FORWARD -i wg0 -j ACCEPT || true; iptables -D FORWARD -o wg0 -j ACCEPT || true; iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu || true; iptables -D INPUT -i wg0 -j ACCEPT || true

[Peer]
PublicKey = __LAPTOP_PUB__
PresharedKey = __LAPTOP_PSK__
AllowedIPs = 10.66.66.3/32

[Peer]
PublicKey = __MOVIL_PUB__
PresharedKey = __MOVIL_PSK__
AllowedIPs = 10.66.66.2/32

[Peer]
PublicKey = __PC_PUB__
PresharedKey = __PC_PSK__
AllowedIPs = 10.66.66.4/32
WGEOF
echo "[ OK ] wg0.conf escrito"

echo "==== [5/6] Arrancando WireGuard (primero, para que exista 10.66.66.1) ===="
systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
systemctl restart wg-quick@wg0
sleep 3
wg show wg0 || true

echo "==== [6/6] DNS del tunel ===="
install_dnsmasq() {
  echo "Instalando dnsmasq (DNS simple del tunel)..."
  apt-get install -y dnsmasq || { echo "[AVISO] fallo al instalar dnsmasq"; return 0; }
  systemctl stop dnsmasq >/dev/null 2>&1 || true  # silenciar autostart fallido del paquete
  cat > /etc/dnsmasq.d/wireguard.conf <<DMS
interface=wg0
listen-address=10.66.66.1
bind-interfaces
no-resolv
server=1.1.1.1
server=8.8.8.8
DMS
  systemctl enable dnsmasq >/dev/null 2>&1 || true
  systemctl restart dnsmasq || true
}
if [ "__INSTALL_ADGUARD__" = "yes" ]; then
  echo "Instalando AdGuard Home (DNS + bloqueo de anuncios)..."
  AG_OK=0
  AG_VER=$(curl -s --max-time 20 https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('tag_name','v0.107.0'))" 2>/dev/null || echo v0.107.0)
  AG_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AG_VER}/AdGuardHome_linux_amd64.tar.gz"
  echo "Descargando AdGuardHome ${AG_VER} (con progreso, reanudable)..."
  cd /tmp
  if curl -fSL --retry 5 --retry-delay 2 --max-time 120 -C - -o ag.tar.gz "$AG_URL" && [ -s ag.tar.gz ]; then
    mkdir -p /opt/AdGuardHome
    if tar -xzf ag.tar.gz -C /opt; then
      chmod +x /opt/AdGuardHome/AdGuardHome
      ADM_PASS="Adm$(openssl rand -hex 6)"
      HASH=$(/opt/AdGuardHome/AdGuardHome --hash-password "$ADM_PASS" 2>/dev/null | tr -d '\r' | tail -n1)
      if [ -n "$HASH" ]; then
        cat > /opt/AdGuardHome/AdGuardHome.yaml <<AGEOF
schema_version: 34
http:
  pprof:
    port: 6060
    enabled: false
  address: 10.66.66.1:3000
  session_ttl: 720h
users:
  - name: admin
    password: ${HASH}
dns:
  bind_hosts:
    - 10.66.66.1
  port: 53
  anonymize_client_ip: false
  ratelimit: 20
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  refuse_any: true
  upstream_dns:
    - https://1.1.1.1/dns-query
    - https://dns.google/dns-query
  bootstrap_dns:
    - 1.1.1.1
    - 8.8.8.8
  fallback_dns:
    - 1.1.1.1
    - 8.8.8.8
  upstream_mode: load_balance
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdGuard DNS filter (mobile)
    id: 2
AGEOF
        cat > /etc/systemd/system/AdGuardHome.service <<SVC
[Unit]
Description=AdGuard Home
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/opt/AdGuardHome
ExecStart=/opt/AdGuardHome/AdGuardHome -c /opt/AdGuardHome/AdGuardHome.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
        systemctl daemon-reload
        systemctl enable AdGuardHome >/dev/null 2>&1 || true
        systemctl restart AdGuardHome || true
        sleep 4
        if ss -lunp 2>/dev/null | grep -q '10.66.66.1:53'; then
          AG_OK=1
          echo "ADGUARD_PASS=${ADM_PASS}"
          echo "${ADM_PASS}" > /etc/wireguard/.adguard_admin_pw
          chmod 600 /etc/wireguard/.adguard_admin_pw
        else
          echo "AdGuard no escucha en 10.66.66.1:53. Log:"
          journalctl -u AdGuardHome --no-pager -n 10 2>/dev/null | tail -10 || true
        fi
      fi
    fi
  else
    echo "[AVISO] No se pudo descargar AdGuardHome ${AG_VER}."
  fi
  if [ "$AG_OK" != "1" ]; then
    echo "ADGUARD_OK=0 (cayendo a dnsmasq)"
    install_dnsmasq
  else
    echo "ADGUARD_OK=1"
  fi
else
  install_dnsmasq
fi
echo "SETUP_SERVER_DONE=1"
REMOTETPL

# Sustituir claves en el script remoto
sed -i "s|__SRV_PRIV__|${SRV_PRIV}|g"            "$REMOTE"
sed -i "s|__LAPTOP_PUB__|${DEV_PUB[laptop]}|g"   "$REMOTE"
sed -i "s|__LAPTOP_PSK__|${DEV_PSK[laptop]}|g"   "$REMOTE"
sed -i "s|__MOVIL_PUB__|${DEV_PUB[movil]}|g"     "$REMOTE"
sed -i "s|__MOVIL_PSK__|${DEV_PSK[movil]}|g"     "$REMOTE"
sed -i "s|__PC_PUB__|${DEV_PUB[pc]}|g"           "$REMOTE"
sed -i "s|__PC_PSK__|${DEV_PSK[pc]}|g"           "$REMOTE"
sed -i "s|__INSTALL_ADGUARD__|${INSTALL_ADGUARD}|g" "$REMOTE"

info "Desplegando en el VPS (instalacion de paquetes puede tardar unos minutos)..."
ssh_run $RUN_AS_SUDO bash -s < "$REMOTE" | tee "$OUTPUT"
rm -f "$REMOTE"

# ---------- capturar resultados ----------
ADGUARD_OK=$(grep -oP 'ADGUARD_OK=\K[01]' "$OUTPUT" 2>/dev/null | tail -1 || echo 0)
ADGUARD_PASS=$(grep -oP 'ADGUARD_PASS=\K.*' "$OUTPUT" 2>/dev/null | tail -1 || true)

SRV_PUB_ACTUAL=$(ssh_run $RUN_AS_SUDO 'wg show wg0 public-key 2>/dev/null || true' | tr -d '\r')
if [ -n "$SRV_PUB_ACTUAL" ]; then
  if [ -n "$SRV_PUB" ] && [ "$SRV_PUB" != "$SRV_PUB_ACTUAL" ]; then
    warn "La clave publica real del servidor difiere de la local; usando la real."
  fi
  SRV_PUB="$SRV_PUB_ACTUAL"
fi
[ -n "$SRV_PUB" ] || fail "No se pudo obtener la clave publica del servidor."

# ---------- generar configs de clientes ----------
info "Generando configs de clientes en clientes/ ..."
for dev in "${DEVICES[@]}"; do
  ip=${DEV_IPS[$dev]}
  cat > "$CLIENTES_DIR/$dev.conf" <<EOF
[Interface]
MTU = 1280
Address = $ip/32
PrivateKey = ${DEV_PRIV[$dev]}
DNS = 10.66.66.1

[Peer]
PublicKey = $SRV_PUB
PresharedKey = ${DEV_PSK[$dev]}
Endpoint = $VPS_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
  chmod 600 "$CLIENTES_DIR/$dev.conf"
  qrencode -t PNG -o "$CLIENTES_DIR/$dev.png" < "$CLIENTES_DIR/$dev.conf"
  ok "Config generada: clientes/$dev.conf (+ QR)"
done

# Si se ejecuto con sudo, devolver la propiedad de clientes/ al usuario real
if [ -n "${SUDO_USER:-}" ]; then
  chown -R "$SUDO_USER":"$SUDO_USER" "$CLIENTES_DIR" 2>/dev/null || true
  ok "Propiedad de clientes/ devuelta a $SUDO_USER"
fi

# ---------- resumen ----------
echo ""
echo "=============================================================="
echo "  RESUMEN DEL SETUP SERVIDOR"
echo "=============================================================="
echo "  Servidor:      $VPS_IP (WireGuard puerto $WG_PORT)"
echo "  Red interna:   $WG_SUBNET  (servidor $WG_SERVER_IP)"
echo "  Clave pub srv: $SRV_PUB"
echo "  DNS del tunel: 10.66.66.1 (AdGuard Home)" 
if [ "$INSTALL_ADGUARD" = "yes" ] && [ "$ADGUARD_OK" = "1" ]; then
  echo "  AdGuard admin: admin / $ADGUARD_PASS  (panel: http://10.66.66.1:3000 via tunel)"
elif [ "$INSTALL_ADGUARD" = "yes" ]; then
  warn "  AdGuard no quedo activo; se instalo dnsmasq como DNS simple."
else
  echo "  DNS:           dnsmasq (replicador a 1.1.1.1 / 8.8.8.8)"
fi
echo "  Dispositivos:"
for dev in "${DEVICES[@]}"; do
  echo "    - $dev  ${DEV_IPS[$dev]}  ->  clientes/$dev.conf (+ QR)"
done
echo "=============================================================="
echo ""
info "PASO SIGUIENTE en este equipo:  sudo bash setup-client.sh ${DEVICES[0]}"
info "Para otro dispositivo: copia clientes/<dispositivo>.conf y ejecuta setup-client.sh alli."