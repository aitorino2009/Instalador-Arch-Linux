#!/usr/bin/env bash
# =============================================================================
#  config.sh — Edita este fichero antes de instalar
# =============================================================================

# ── Disco ─────────────────────────────────────────────────────────────────────
DISK="/dev/sda"            # Cambia a /dev/nvme0n1, /dev/vda, etc.
SWAP_SIZE="8G"             # Tamaño de swap (0 para desactivar)
ROOT_SIZE="0"              # 0 = resto del disco para /

# ── Sistema ───────────────────────────────────────────────────────────────────
HOSTNAME="archbox"
TIMEZONE="Europe/Madrid"
LOCALE="es_ES.UTF-8"
KEYMAP="es"
LANG_EXTRA="en_US.UTF-8"   # Locale extra (inglés recomendado como fallback)

# ── Usuario ───────────────────────────────────────────────────────────────────
USERNAME="user"
# Contraseñas en texto plano aquí solo durante la instalación.
# Se usan openssl passwd internamente — no quedan en el sistema final.
ROOT_PASSWORD="changeme"
USER_PASSWORD="changeme"
USER_GROUPS="wheel,audio,video,storage,optical,network,input"

# ── Paquetes base extra ───────────────────────────────────────────────────────
# Siempre se instalan: base base-devel linux linux-firmware
BASE_PACKAGES=(
    networkmanager
    git
    vim
    sudo
    curl
    wget
    reflector
    man-db
    man-pages
    bash-completion
    htop
    openssh
)

# ── Bootloader ────────────────────────────────────────────────────────────────
# Opciones: "grub" | "systemd-boot"
BOOTLOADER="grub"

# ── Dotfiles / post-install ───────────────────────────────────────────────────
# Si tienes un repo de dotfiles, ponlo aquí. Deja vacío para omitir.
DOTFILES_REPO=""           # ej: "https://github.com/tuusuario/dotfiles"
DOTFILES_SCRIPT="install.sh" # Script dentro del repo que los instala

# ── AUR helper ───────────────────────────────────────────────────────────────
# Opciones: "paru" | "yay" | "" (para omitir)
AUR_HELPER="paru"

# ── Paquetes AUR (solo si AUR_HELPER != "") ───────────────────────────────────
AUR_PACKAGES=(
    # paru-bin
)

# ── Kernel ────────────────────────────────────────────────────────────────────
# Opciones: "linux" | "linux-lts" | "linux-zen" | "linux-hardened"
KERNEL="linux"

# ── CPU microcode (se detecta automáticamente, pero puedes forzarlo) ──────────
# "auto" | "intel-ucode" | "amd-ucode" | "none"
MICROCODE="auto"
