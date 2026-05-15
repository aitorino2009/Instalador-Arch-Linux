#!/usr/bin/env bash
# =============================================================================
#  install.sh — Instalador automático de Arch Linux
#  Uso: bash install.sh [--config ruta/config.sh]
# =============================================================================
set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $*"; }
info()   { echo -e "${CYAN}[→]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }
title()  { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════${NC}"; \
           echo -e "${BOLD}${BLUE}  $*${NC}"; \
           echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}\n"; }

# ── Argumentos ────────────────────────────────────────────────────────────────
CONFIG_FILE="$(dirname "$0")/config.sh"
while [[ $# -gt 0 ]]; do
    case $1 in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        *) error "Argumento desconocido: $1" ;;
    esac
done

[[ -f "$CONFIG_FILE" ]] || error "No se encuentra config.sh en: $CONFIG_FILE"
# shellcheck source=config.sh
source "$CONFIG_FILE"

# ── Validaciones previas ──────────────────────────────────────────────────────
title "Arch Linux Installer"

[[ $EUID -eq 0 ]] || error "Ejecuta el script como root."
[[ -b "$DISK" ]] || error "El disco '$DISK' no existe. Edita DISK en config.sh."
ping -c1 -W3 archlinux.org &>/dev/null || error "Sin conexión a internet."
ls /sys/firmware/efi/efivars &>/dev/null && UEFI=true || UEFI=false
info "Modo arranque: $( $UEFI && echo 'UEFI' || echo 'BIOS/Legacy')"
info "Disco destino: $DISK"

# ── Confirmación ──────────────────────────────────────────────────────────────
warn "¡ATENCIÓN! Se BORRARÁ TODO el contenido de ${BOLD}$DISK${NC}"
read -rp "$(echo -e "${YELLOW}Escribe 'si' para continuar: ${NC}")" CONFIRM
[[ "$CONFIRM" == "si" ]] || { info "Instalación cancelada."; exit 0; }

# ── Helpers ───────────────────────────────────────────────────────────────────
# Devuelve la partición correcta: /dev/sda1, /dev/nvme0n1p1, etc.
part() {
    local disk="$1" num="$2"
    if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# ── 1. Particionado ───────────────────────────────────────────────────────────
title "1/8 · Particionado del disco"
info "Limpiando firmas previas…"
wipefs -af "$DISK" &>/dev/null
sgdisk -Z "$DISK" &>/dev/null

if $UEFI; then
    info "Creando tabla GPT (EFI + swap + root)…"
    sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
    if [[ "$SWAP_SIZE" != "0" ]]; then
        sgdisk -n 2:0:+"$SWAP_SIZE" -t 2:8200 -c 2:"swap" "$DISK"
        sgdisk -n 3:0:0            -t 3:8300 -c 3:"root" "$DISK"
        PART_EFI=$(part "$DISK" 1)
        PART_SWAP=$(part "$DISK" 2)
        PART_ROOT=$(part "$DISK" 3)
    else
        sgdisk -n 2:0:0 -t 2:8300 -c 2:"root" "$DISK"
        PART_EFI=$(part "$DISK" 1)
        PART_SWAP=""
        PART_ROOT=$(part "$DISK" 2)
    fi
else
    info "Creando tabla MBR (BIOS boot + swap + root)…"
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary 1MiB 3MiB      # BIOS boot
    parted -s "$DISK" set 1 bios_grub on
    if [[ "$SWAP_SIZE" != "0" ]]; then
        parted -s "$DISK" mkpart primary linux-swap 3MiB "$((3 + ${SWAP_SIZE//G/} * 1024))MiB"
        parted -s "$DISK" mkpart primary ext4 "$((3 + ${SWAP_SIZE//G/} * 1024))MiB" 100%
        PART_SWAP=$(part "$DISK" 2)
        PART_ROOT=$(part "$DISK" 3)
    else
        parted -s "$DISK" mkpart primary ext4 3MiB 100%
        PART_SWAP=""
        PART_ROOT=$(part "$DISK" 2)
    fi
    PART_EFI=""
fi
log "Particionado completado."

# ── 2. Formato ────────────────────────────────────────────────────────────────
title "2/8 · Formateando particiones"
sleep 1  # esperar a que el kernel registre las nuevas particiones

if $UEFI; then
    info "Formateando EFI (FAT32)…"
    mkfs.fat -F32 -n "EFI" "$PART_EFI"
fi
if [[ -n "$PART_SWAP" ]]; then
    info "Inicializando swap…"
    mkswap -L "swap" "$PART_SWAP"
    swapon "$PART_SWAP"
fi
info "Formateando root (ext4)…"
mkfs.ext4 -L "root" -F "$PART_ROOT"
log "Formato completado."

# ── 3. Montaje ────────────────────────────────────────────────────────────────
title "3/8 · Montando particiones"
mount "$PART_ROOT" /mnt
if $UEFI; then
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi
log "Montaje completado."

# ── 4. Mirrors + pacstrap ─────────────────────────────────────────────────────
title "4/8 · Instalando sistema base"
info "Actualizando mirrors (reflector)…"
reflector --country Spain,France,Germany \
          --age 12 --protocol https \
          --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null \
    || warn "reflector falló, usando mirrors existentes."

# Detectar microcode
if [[ "$MICROCODE" == "auto" ]]; then
    CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    [[ "$CPU_VENDOR" == "GenuineIntel" ]] && MICROCODE="intel-ucode" \
        || MICROCODE="amd-ucode"
fi
[[ "$MICROCODE" == "none" ]] && MICROCODE=""

info "Instalando base ($KERNEL + ${MICROCODE:-sin microcode})…"
PACSTRAP_PKGS=(base "$KERNEL" "${KERNEL}-headers" linux-firmware base-devel)
[[ -n "$MICROCODE" ]] && PACSTRAP_PKGS+=("$MICROCODE")
PACSTRAP_PKGS+=("${BASE_PACKAGES[@]}")

pacstrap -K /mnt "${PACSTRAP_PKGS[@]}"
log "Sistema base instalado."

# ── 5. fstab ──────────────────────────────────────────────────────────────────
title "5/8 · Generando fstab"
genfstab -U /mnt >> /mnt/etc/fstab
log "fstab generado."

# ── 6. Copiar scripts al chroot ───────────────────────────────────────────────
cp "$(dirname "$0")/chroot.sh" /mnt/root/chroot.sh
cp "$CONFIG_FILE" /mnt/root/config.sh
chmod +x /mnt/root/chroot.sh

# Exportar variables de entorno extra al chroot
cat > /mnt/root/env.sh <<EOF
export UEFI=$UEFI
export DISK="$DISK"
export PART_EFI="${PART_EFI:-}"
export PART_ROOT="$PART_ROOT"
export BOOTLOADER="$BOOTLOADER"
EOF

# ── 7. Chroot ─────────────────────────────────────────────────────────────────
title "6/8 · Configurando sistema (chroot)"
arch-chroot /mnt /bin/bash /root/chroot.sh
log "Configuración en chroot completada."

# ── 8. Limpieza y desmontaje ──────────────────────────────────────────────────
title "7/8 · Limpiando"
rm -f /mnt/root/{chroot.sh,config.sh,env.sh}
umount -R /mnt
[[ -n "$PART_SWAP" ]] && swapoff "$PART_SWAP" 2>/dev/null || true
log "Desmontado limpiamente."

# ── Fin ───────────────────────────────────────────────────────────────────────
title "8/8 · ¡Instalación completada!"
echo -e "${GREEN}${BOLD}Arch Linux instalado correctamente en $DISK${NC}"
echo -e "${CYAN}Extrae el medio de instalación y reinicia:${NC}"
echo -e "  ${BOLD}reboot${NC}\n"
