# arch-installer 🏹

Instalador interactivo de Arch Linux. Sin tocar archivos, sin configuración previa.  
Arranca la ISO, clona el repo, ejecuta el script y responde las preguntas.

---

## Uso

```bash
# 1. Arrancar la ISO de Arch Linux

# 2. Conectar a internet (WiFi)
iwctl station wlan0 connect "TuRed"

# 3. Clonar y ejecutar
pacman -Sy --noconfirm git
git clone https://github.com/TUUSUARIO/arch-installer
bash arch-installer/install.sh
```

El script te preguntará:

- Disco destino (muestra los disponibles)
- Swap (tamaño o desactivar)
- Hostname, zona horaria, idioma, teclado
- Kernel (`linux`, `linux-lts`, `linux-zen`…)
- Bootloader (`grub` o `systemd-boot`)
- Nombre de usuario y contraseñas (ocultas, con confirmación)
- AUR helper (`paru`, `yay` o ninguno)
- Dotfiles desde un repo git (opcional)
- SSH habilitado (opcional)

Tras confirmar, **corre solo**. En 5–10 min tienes Arch instalado.

---

## WiFi desde la ISO

```bash
iwctl
  device list
  station wlan0 scan
  station wlan0 get-networks
  station wlan0 connect "NombreRed"
  exit
```

---

## Lo que instala siempre

`base` · `base-devel` · kernel elegido · `linux-firmware` · microcode (auto) · `networkmanager` · `git` · `vim` · `sudo` · `curl` · `wget` · `reflector` · `man-db` · `bash-completion` · `htop` · `openssh`

---

## Notas

- Detecta UEFI/BIOS automáticamente.
- Detecta microcode Intel/AMD automáticamente.
- Si el AUR helper o los dotfiles fallan, el sistema base queda intacto — se avisa y se continúa.
- `reflector.timer` se habilita para mantener mirrors actualizados.
