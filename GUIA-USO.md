# 🛡️ VPN PERSONAL — Guía de Uso y Administración

**Servidor:** `TU_IP_DEL_VPS` (Dallas, EE.UU.) · **Protocolo:** WireGuard · **Puerto UDP:** 51820
**Red interna:** `10.66.66.0/24` (servidor `.1`, movil `.2`, laptop `.3`, pc `.4`)
**DNS / Bloqueo de anuncios:** AdGuard Home en `10.66.66.1:53` (túnel)

---

## 0. Requisitos previos

- Linux (Zorin / Ubuntu / Debian) en el equipo cliente.
- En el cliente se instalan automáticamente: `wireguard-tools`, `qrencode`, `sshpass` (si faltan).
- Archivo **`.env`** (en la carpeta del proyecto) con las credenciales del VPS:

```bash
user=root
ip-server=TU_IP_DEL_VPS
password=TU_CONTRASENA
```

> Alternativa sin `.env`: variables `VPS_IP=... SSH_USER=... SSH_KEY=... SSH_PASS=...`

---

## 1. Desplegar el servidor (una vez por VPS)

```bash
cd Proyectos/VPN-Personal
bash setup-server.sh
```

El script:
1. Lee `.env` y conecta por **SSH** con esas credenciales (`sshpass`)
2. Instala en el VPS: **WireGuard**, forwarding IPv4
3. **Genera TODAS las claves**: servidor + cada dispositivo (laptop, movil, pc) con su preshared key
4. Configura **NAT + TCPMSS + DNS del túnel** (AdGuard Home o dnsmasq) de forma **NO invasiva**: no enciende ufw si estaba apagado, no toca otros servicios ni usuarios
5. Genera las configs de clientes en `clientes/` (`.conf` + **QR**) listas para usar

> 🔁 Si ya existen configs en `clientes/`, pregunta si **reutilizar las claves**
> (no romper los dispositivos actuales) o generar todo de nuevo.

---

## 2. Configurar el cliente (deja el equipo listo)

```bash
sudo bash setup-client.sh laptop        # o: movil / pc
```

El script:
- **Limpia automáticamente** la configuración previa de ese dispositivo (conexión NetworkManager, `/etc/wireguard`, interfaz residual) — no borra configs de otros dispositivos
- Instala dependencias (`wireguard-tools`, `openresolv`, `qrencode`, `curl`, `wget`)
- Copia la config a `/etc/wireguard/` (modo CLI `wg-quick`)
- Crea la **interfaz gráfica** en NetworkManager (icono de red → VPN → `laptop`)
- **AmneziaVPN** opcional (app con botón Conectar, descarga con `wget -c` y progreso visible)
- Verifica: handshake, DNS del túnel, MTU, IP pública

> 💡 **Configuración optimizada (estilo ProtonVPN):**
> `MTU = 1280` (funciona en redes celulares/hotspot), DNS prioritario
> (`ipv4.dns-priority -1500`, ignora DNS del WiFi), IPv6 desactivado y
> **todo el tráfico** (incluido DNS) por el túnel → `10.66.66.1` (AdGuard).

---

## 3. Conectar desde la interfaz gráfica

### Opción A — Applet nativo (recomendada)
1. Clic en el **icono de red** (arriba a la derecha).
2. Menú **VPN** → clic en **laptop**.
3. Listo: tu tráfico sale por Dallas.

### Opción B — AmneziaVPN (app dedicada)
1. Abre **AmneziaVPN** desde el menú de aplicaciones.
2. **Añadir servidor → Importar configuración** → `clientes/laptop.conf`.
3. Presiona **CONECTAR**.

> ⚠️ No uses ambas a la vez (conflicto de rutas). Elige una.

---

## 4. Conectar tu móvil (Android / iOS)

1. Instala la app **WireGuard** (Play Store / App Store) — open source.
2. **+ → Escanear código QR** → escanea `clientes/movil.png` (o el de tu dispositivo).
3. Activa el túnel. Opcional: **VPN siempre activa** y kill switch.

También puedes importar el archivo `.conf` directamente desde `clientes/`.

---

## 5. Conectar Windows / macOS

1. App oficial **WireGuard** → **Import tunnel(s) from file** → el `.conf`.
2. O **AmneziaVPN** → Importar configuración.

---

## 6. Añadir un nuevo dispositivo

`setup-server.sh` prepara 3 dispositivos (laptop, movil, pc). Para añadir otro:

**Opción A (recomendada):** edita en `setup-server.sh` la lista `DEVICES` (y su IP en `DEV_IPS`) y vuelve a ejecutar eligiendo **reutilizar claves**.

**Opción B (manual, en el servidor):**
```bash
ssh root@TU_IP_DEL_VPS
# generar claves del nuevo dispositivo
wg genkey > /etc/wireguard/nuevo.priv
wg pubkey < /etc/wireguard/nuevo.priv
wg genpsk
# añadir peer al túnel (public_key y psk generados arriba)
wg set wg0 peer <PUBLIC_KEY> preshared-key <PSK> allowed-ips 10.66.66.5/32
wg-quick save wg0
```

La autenticación es por **clave pública/privada**: puedes conectarte desde **cualquier IP y cualquier red**.

---

## 7. Verificaciones rápidas

```bash
curl ifconfig.me          # debe imprimir TU_IP_DEL_VPS
sudo wg show laptop       # handshake reciente = conexión activa
resolvectl status laptop  # DNS Servers: 10.66.66.1, DNS Domain: ~.
nmcli connection show laptop
```

Prueba de fuga DNS: https://dnsleaktest.com (todo debe resolver vía el túnel).
Bloqueo de anuncios: revisa el Query Log de AdGuard Home (sección 8).

---

## 8. Administrar el bloqueo de anuncios (AdGuard Home)

Con la VPN conectada, abre en el navegador: **`http://10.66.66.1:3000`**

- **Usuario:** `admin`
- **Contraseña:** `ssh root@TU_IP_DEL_VPS 'cat /etc/wireguard/.adguard_admin_pw'`
  (o mírala en el resumen final de `setup-server.sh`)

Ahí ves: estadísticas, query log, filtros (AdGuard DNS / Tracking / Mobile Ads) y puedes añadir listas personalizadas.

---

## 9. Administración del servidor

| Acción | Comando (en el VPS, como root) |
|---|---|
| Estado del túnel | `wg show wg0` |
| Reiniciar túnel | `systemctl restart wg-quick@wg0` |
| Logs del túnel | `journalctl -u wg-quick@wg0 -f` |
| Logs de AdGuard | `journalctl -u AdGuardHome -f` |
| Firewall | `ufw status verbose` (22/tcp limit + 51820/udp) |
| Contraseña panel AdGuard | `cat /etc/wireguard/.adguard_admin_pw` |
| Actualizaciones | automáticas (unattended-upgrades) |

**Acceso SSH:** `root` (con la contraseña configurada en `.env`).

---

## 10. Desinstalar

```bash
sudo bash uninstall.sh --server   # limpia el VPS (usa .env)
sudo bash uninstall.sh --client   # limpia este equipo
sudo bash uninstall.sh --all      # ambos
```

Elimina **solo lo que se tocó** (WireGuard, AdGuard/dnsmasq, reglas ufw, sysctl, paquetes VPN)
**sin afectar** otros servicios ni usuarios (ssh, fail2ban, cron, snapd, root).

---

## 11. Solución de problemas

| Síntoma | Causa / Solución |
|---|---|
| No conecta desde una red WiFi | NAT agresivo → `PersistentKeepalive = 25` (ya incluido) |
| Conecta pero no navega | **MTU 1280** (ya incluido). El camino celular/hotspot suele ser MTU 1420 y el overhead de WireGuard (~60 B) rompe los paquetes grandes. Verifica con `ping -M do -s 1200 8.8.8.8` |
| Solo funciona `ping 8.8.8.8`, nada más | DNS del túnel bloqueado por el firewall del servidor. `setup-server.sh` ya aplica `ufw allow in on wg0` (permite UDP 53 → AdGuard). Revisa `systemctl status AdGuardHome` |
| DNS no resuelve | `resolvectl status laptop` debe mostrar `DNS Servers: 10.66.66.1` y `DNS Domain: ~.` |
| IP pública no cambia al conectar | El túnel no está activo: `nmcli connection up laptop` |
| Cambió la IP del VPS | `wg set wg0 peer <PUB> endpoint NUEVA_IP:51820 && wg-quick save wg0` |
| Quieres ofuscación (redes que bloquean VPN) | Opcional: AmneziaWG vía AmneziaVPN |

---

## 12. Seguridad

- Claves privadas del cliente SOLO en tus dispositivos y en `clientes/` (permisos `600`).
- Clave privada del servidor **nunca** sale del VPS.
- Rotación recomendada cada 6–12 meses: regenera con `setup-server.sh` eligiendo **no reutilizar** y vuelve a configurar cada dispositivo.
- `fail2ban` protege SSH (banea IPs de fuerza bruta automáticamente).
- Usa contraseñas fuertes en el VPS y en el `.env` (no lo subas a GitHub).