# Instalador Arch Linux 🏹

Instalador interactivo de Arch Linux totalmente automatizado. Sin tocar archivos de configuración, sin comandos manuales, sin dolor de cabeza.  
Arranca la ISO oficial, clona el repositorio, ejecuta el script y responde las preguntas. **En 5–10 minutos tienes un Arch Linux completo.**

---

## Uso rápido

```bash
# 1. Arrancar desde la ISO oficial de Arch Linux

# 2. Conectar a internet por WiFi (si no usas cable)
iwctl station wlan0 connect "TuRed"

# 3. Descargar y ejecutar
curl -sL https://githubusercontent.com -o install.sh && bash install.sh
bash Instalador-Arch-Linux/install.sh
```

> **Nota sobre el WiFi:** Si no sabes el nombre de tu interfaz, usa `ip link` para listarla. El flujo completo de `iwctl` está al final de este documento.

---

## ¿Qué te pregunta el script?

El instalador recorre tres bloques de preguntas antes de tocar nada el disco. Puedes escribir **`<` + Enter** en cualquier momento para volver al paso anterior sin perder lo configurado anteriormente.

### 🖴 Bloque 1 — Sistema base
| Pregunta | Opciones |
|---|---|
| **Disco destino** | Muestra los discos disponibles, su tamaño y modelo |
| **Swap** | Activar/desactivar, tamaño con validación (ej. `8G`, `512M`) |
| **Cifrado LUKS** | Cifrado completo del disco con contraseña |
| **Sistema de archivos** | `ext4` (clásico) · `btrfs` (con subvolúmenes y snapshots) |
| **Partición /home separada** | Solo disponible con ext4, el espacio restante va a /home |
| **Hostname** | Nombre del equipo en la red |
| **Zona horaria** | Con validación automática contra `/usr/share/zoneinfo/` |
| **Idioma** | `es_ES.UTF-8` · `en_US.UTF-8` · `ca_ES.UTF-8` · `fr_FR.UTF-8` · `de_DE.UTF-8` |
| **Teclado (consola)** | `es` · `en` · `us` · `fr` · `de` · `latam` |
| **Kernel** | `linux` · `linux-lts` · `linux-zen` · `linux-hardened` |
| **Bootloader** | `grub` (UEFI + BIOS) · `systemd-boot` (solo UEFI) |

### 👤 Bloque 2 — Usuario y contraseñas
| Pregunta | Detalle |
|---|---|
| **Nombre de usuario** | Se crea con grupos `wheel`, `audio`, `video`, `storage`... |
| **Contraseña de root** | Oculta, con confirmación doble |
| **Contraseña de usuario** | Oculta, con confirmación doble |

### 🖥️ Bloque 3 — Entorno gráfico y extras
| Pregunta | Opciones |
|---|---|
| **Driver de vídeo** | Intel · AMD · NVIDIA · VirtualBox · VMware · Ninguno (servidor) |
| **Entorno de escritorio** | GNOME · KDE Plasma · XFCE · Hyprland · i3-wm · **Todos** · Ninguno |
| **AUR helper** | `paru` · `yay` · ninguno |
| **Dotfiles** | URL de un repositorio git + script de instalación dentro del repositorio |
| **SSH** | Habilitar `sshd` al arranque |

---

## Características principales

### 🔒 Cifrado LUKS completo
- **LUKS2** con Argon2id para `systemd-boot`
- **LUKS1** con SHA-256 para GRUB (compatibilidad del bootloader)
- Cifra tanto la partición raíz (`/`) como la de datos (`/home`) si están separadas
- La swap cifrada usa `PARTUUID` + `timeout=10` para evitar arranques lentos

### 🌲 BTRFS con subvolúmenes
Cuando se elige BTRFS, se crean automáticamente los subvolúmenes:
- `@` → `/` (raíz)
- `@home` → `/home`
- `@pkg` → `/var/cache/pacman/pkg`
- `@log` → `/var/log`
- `@snapshots` → `/.snapshots`

Todos montados con `noatime`, `compress=zstd` y `discard=async`.

### 📁 Particionado personalizado
Si se elige `ext4`, el script pregunta si crear una partición `/home` separada. El tamaño de la raíz se valida dinámicamente para que no se desborde el disco, y el espacio restante se asigna automáticamente a `/home`.

### 🖥️ Entornos de escritorio
| Entorno | Display Manager | Notas |
|---|---|---|
| GNOME | GDM | Escritorio completo con GNOME Tweaks |
| KDE Plasma | SDDM | Plasma meta + Konsole + Dolphin |
| XFCE | LightDM | XFCE4 + xfce4-goodies |
| Hyprland | SDDM | Wayland WM; se copia la config por defecto para evitar el STUB |
| i3-wm | LightDM | X11 WM + i3status + i3lock + dmenu + Alacritty |
| **Todos** | SDDM | Instala todos los entornos. SDDM permite cambiar entre ellos en cada login. |

El teclado X11 se configura automáticamente en `/etc/X11/xorg.conf.d/00-keyboard.conf` para que el Display Manager arranque ya con el layout correcto.

### 🚀 Pantalla de inicio SDDM (Astronaut Theme)
Cuando el Display Manager elegido es SDDM, el instalador descarga e instala automáticamente el tema **sddm-astronaut-theme**, con:
- Idioma de la interfaz sincronizado con el locale del sistema (fecha, "Sesión", "Suspender", etc.)
- Dependencias Qt6 incluidas en la instalación base

### ⚡ Optimizaciones automáticas
- **Mirrors**: `reflector` busca los mirrors más rápidos de España, Francia y Alemania antes de instalar. Se configura un `reflector.timer` para mantenerlos al día tras el reinicio.
- **Pacman**: `Color` y `ParallelDownloads` activados automáticamente.
- **Microcode**: Se detecta el fabricante de la CPU (Intel/AMD) y se instala el paquete de microcódigo correcto.
- **Bootloader adaptativo**: UUID y PARTUUID calculados automáticamente; la ruta del ESP se adapta según el bootloader elegido.

---

## Lo que instala siempre

```
base · base-devel · linux-firmware · kernel elegido · microcode (auto)
networkmanager · git · nvim · vim · sudo · curl · wget
reflector · cryptsetup · man-db · bash-completion · htop · openssh
grub · efibootmgr · os-prober
```

---

## Compatibilidad

| Característica | Soporte |
|---|---|
| Arranque UEFI | ✅ |
| Arranque BIOS / Legacy | ✅ |
| Discos NVMe / eMMC | ✅ (sufijos `p1`, `p2`... calculados automáticamente) |
| CPU Intel | ✅ (`intel-ucode`) |
| CPU AMD | ✅ (`amd-ucode`) |
| VirtualBox | ✅ (`virtualbox-guest-utils` + `vboxservice`) |
| VMware | ✅ (`open-vm-tools` + `vmtoolsd`) |

---

## Seguridad ante todo

El script **exige confirmación explícita** escribiendo `si` antes de tocar el disco. Cualquier operación destructiva está precedida de un aviso en color. Si el AUR helper o los dotfiles fallan, el **sistema base queda intacto**; el instalador lo avisa y continúa sin colapsar.

---

## WiFi desde la ISO

```bash
iwctl
  device list                         # ver interfaces (ej. wlan0)
  station wlan0 get-networks          # listar redes
  station wlan0 connect "NombreRed"   # conectar
  exit

ping archlinux.org                    # verificar conexión
```

---

## Licencia

MIT: Úsalo, modifícalo y compártelo libremente.
