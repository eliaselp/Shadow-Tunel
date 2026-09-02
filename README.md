<div align="center">

# 🛡️ VPN Personal — WireGuard + AdGuard Home

**Tu propia VPN privada, desplegada en tu VPS en minutos, con DNS y bloqueo de anuncios.**

![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![AdGuard](https://img.shields.io/badge/AdGuard%20Home-68BC71?style=for-the-badge&logo=adguard&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

*Sustituye a las VPN comerciales gratuitas: tráfico completo cifrado, sin límites, sin logs de terceros y con bloqueo de publicidad integrado.*

</div>

---

## ✨ Características

| | |
|---|---|
| 🚀 **Despliegue automático** | Un script configura el servidor completo en tu VPS (claves, NAT, firewall, DNS) |
| 🔐 **100% privado** | Todo el tráfico sale por **tu** servidor. Sin proveedores, sin logs |
| 🛡️ **Bloqueo de anuncios** | DNS con **AdGuard Home**: publicidad, rastreadores y malware bloqueados en todos tus dispositivos |
| 📱 **Multi-dispositivo** | Configs + **QR** para laptop, móvil (Android/iOS) y PC (Linux/Windows/macOS) |
| 🖥️ **Interfaz gráfica** | Conexión nativa en NetworkManager + app **AmneziaVPN** opcional |
| ⚙️ **No invasivo** | No enciende firewalls ajenos, no toca otros servicios ni usuarios del VPS |
| 🧹 **Desinstalador** | `uninstall.sh` borra solo lo que se tocó, en el servidor y en el cliente |

---

## 🏗️ Arquitectura

```
                        ┌─────────────────────────────────────────────┐
                        │               TU VPS (servidor)             │
   📱 móvil ───────────▶│                                             │
   💻 laptop ──────────▶│  WireGuard (wg0)  ──►  NAT  ──►  INTERNET   │
   🖥️  pc ─────────────▶│  10.66.66.1/24        │                     │
                        │          │            │                     │
                        │          ▼            ▼                     │
                        │   AdGuard Home   (todo el tráfico sale      │
                        │   10.66.66.1:53   por tu IP pública)        │
                        └─────────────────────────────────────────────┘
```

---

## 🚀 Inicio rápido

### 1. Clona el proyecto y crea tus credenciales

```bash
git clone https://github.com/TU_USUARIO/vpn-personal.git
cd vpn-personal
cp .env.example .env     # edita con tus credenciales del VPS
```

```env
user=root
ip-server=TU_IP_DEL_VPS
password=TU_CONTRASENA
```

### 2. Despliega el servidor

```bash
bash setup-server.sh
```

Genera **todas las claves** (servidor + laptop/movil/pc), configura NAT, firewall y DNS, y deja las configs listas en `clientes/`.

### 3. Configura el cliente

```bash
sudo bash setup-client.sh laptop   # o: movil / pc
```

Limpia la config previa, crea la **interfaz gráfica** (icono de red → VPN → laptop) y se conecta automáticamente. Verifica que tu IP pública sea la del VPS:

```bash
curl ifconfig.me
```

### 4. Conecta tus otros dispositivos

Escanea el QR correspondiente con la app **WireGuard**:

```
clientes/laptop.png · clientes/movil.png · clientes/pc.png
```

---

## 📦 Scripts

| Script | Uso | Qué hace |
|---|---|---|
| `setup-server.sh` | `bash setup-server.sh` | Despliega el servidor completo (WireGuard + claves + NAT + DNS AdGuard) usando credenciales de `.env` |
| `setup-client.sh` | `sudo bash setup-client.sh laptop` | Configura el cliente listo para usar (GUI + CLI + verificación) |
| `uninstall.sh` | `sudo bash uninstall.sh --server\|--client\|--all` | Elimina solo lo que se tocó, sin afectar otros servicios |

---

## 🛡️ Seguridad

- Claves privadas de clientes solo en tus dispositivos (permisos `600`); la del servidor nunca sale del VPS.
- Autenticación por **clave pública/privada** (WireGuard) — puedes conectarte desde cualquier IP.
- `fail2ban` protege SSH contra fuerza bruta.
- El `.env` con la contraseña **no debe subirse a GitHub** (usa `.env.example` como plantilla).

---

## 📄 Documentación

Guía completa de uso y administración: **[GUIA-USO.md](GUIA-USO.md)**

---

## 📜 Licencia

MIT — úsalo, modifícalo y compártelo libremente.

---

<div align="center">

*Hecho con ❤️ y WireGuard · AdBlocking DNS con AdGuard Home*

</div>