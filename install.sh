#!/usr/bin/env bash
# =============================================================================
#  install.sh — Instalador interactivo de Arch Linux
#  Uso: bash install.sh
# =============================================================================
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
#  COLORES Y HELPERS
# ══════════════════════════════════════════════════════════════════════════════
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "${GREEN}  ✔  ${NC}$*"; }
info()   { echo -e "${CYAN}  →  ${NC}$*"; }
warn()   { echo -e "${YELLOW}  !  ${NC}$*"; }
error()  { echo -e "${RED}  ✘  ${NC}$*" >&2; exit 1; }
dim()    { echo -e "${DIM}     $*${NC}"; }
step()   { echo -e "\n${BOLD}${MAGENTA}[$1]${NC}${BOLD} $2${NC}"; echo -e "${DIM}$(printf '─%.0s' {1..50})${NC}"; }

# Pregunta con valor por defecto: ask "Pregunta" "default" → $REPLY
ask() {
    local prompt="$1" default="${2:-}"
    local hint=""
    if [[ -n "$default" ]]; then hint="${DIM} [${default}]${NC}"; fi
    echo -ne "\n${BOLD}${BLUE}  ?  ${NC}${BOLD}${prompt}${NC}${hint}: "
    read -r REPLY || true
    REPLY="$(echo -e "${REPLY}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "$REPLY" ]]; then REPLY="$default"; fi
}

# Pregunta sí/no: ask_yn "Pregunta" "s|n" → $YN
ask_yn() {
    local prompt="$1" default="${2:-s}"
    local opts
    if [[ "$default" == "s" ]]; then opts="${BOLD}S${NC}/n"; else opts="s/${BOLD}N${NC}"; fi
    echo -ne "\n${BOLD}${BLUE}  ?  ${NC}${BOLD}${prompt}${NC} ${DIM}[${opts}]${NC}: "
    read -r YN || true
    if [[ -z "$YN" ]]; then YN="$default"; fi
    if [[ "$YN" =~ ^[sySY]$ ]]; then YN="s"; else YN="n"; fi
}

# Menú de selección numerado: pick "Título" op1 op2 ... → $PICKED
pick() {
    local title="$1"; shift
    local options=("$@")
    echo -e "\n${BOLD}${BLUE}  ?  ${NC}${BOLD}${title}${NC}"
    for i in "${!options[@]}"; do
        echo -e "     ${DIM}$((i+1)))${NC} ${options[$i]}"
    done
    while true; do
        echo -ne "     ${DIM}Elige [1-${#options[@]}]:${NC} "
        read -r SEL
        if [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#options[@]} )); then
            PICKED="${options[$((SEL-1))]}"; break
        fi
        echo -e "     ${RED}Opción inválida.${NC}"
    done
}

# Contraseña (oculta, confirmada): ask_pass "Prompt" → $PASS
ask_pass() {
    local prompt="$1"
    while true; do
        echo -ne "\n${BOLD}${BLUE}  ?  ${NC}${BOLD}${prompt}${NC}: "
        read -rs P1; echo
        echo -ne "     ${DIM}Confirma:${NC} "
        read -rs P2; echo
        if [[ "$P1" == "$P2" ]]; then PASS="$P1"; break
        else echo -e "     ${RED}No coinciden, inténtalo de nuevo.${NC}"; fi
    done
}

clear
cat << 'EOF'
   ___   _ __             ___           __       __      
  / _ | (_) /____  ____  / _ \___  ____/ /____ _/ /__ ___
 / __ |/ / __/ _ \/ __/ / ___/ _ \/ __/ __/ _ `/ / -_|_-<
/_/ |_/_/\__/\___/_/   /_/   \___/_/  \__/\_,_/_/\__/___/

  Instalador automático de Arch Linux; responde las preguntas y siéntate.
EOF
echo -e "${DIM}$(printf '═%.0s' {1..54})${NC}\n"

# ── Checks previos ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]]          || error "Ejecuta como root."
ping -c1 -W3 archlinux.org &>/dev/null || error "Sin conexión a internet."
ls /sys/firmware/efi/efivars &>/dev/null && UEFI=true || UEFI=false

echo -e "  ${GREEN}✔${NC} Conexión a internet detectada."
echo -e "  ${GREEN}✔${NC} Modo arranque: ${BOLD}$($UEFI && echo 'UEFI' || echo 'BIOS/Legacy')${NC}"


# ══════════════════════════════════════════════════════════════════════════════
#  FASE 1 — PREGUNTAS
# ══════════════════════════════════════════════════════════════════════════════

step "1/3" "Configuración del sistema"

# ── Disco ──────────────────────────────────────────────────────────────────────
echo -e "\n${DIM}  Discos disponibles:${NC}"
lsblk -dpno NAME,SIZE,MODEL | grep -v 'loop\|sr0' | while read -r line; do
    echo -e "     ${CYAN}${line}${NC}"
done
ask "Disco destino" "/dev/sda"
DISK="$REPLY"
[[ -b "$DISK" ]] || error "El disco '$DISK' no existe."

ask_yn "¿Activar swap?" "s"
if [[ "$YN" == "s" ]]; then
    ask "Tamaño de swap" "8G"
    SWAP_SIZE="$REPLY"
else
    SWAP_SIZE="0"
fi

ask_yn "¿Crear una partición separada para /home?" "n"
SEPARATE_HOME="$YN"
ROOT_SIZE="0"
if [[ "$SEPARATE_HOME" == "s" ]]; then
    DISK_SIZE_BYTES=$(lsblk -b -no SIZE "$DISK" | head -n1)
    DISK_SIZE_GB=$(( DISK_SIZE_BYTES / 1024 / 1024 / 1024 ))
    dim "  El espacio sobrante tras la raíz se asignará a /home automáticamente."
    dim "  Tamaño total detectado del disco: ${DISK_SIZE_GB} GB"
    
    # Calcular tamaño sugerido de raíz dinámicamente (60% del espacio útil, máx 40G, mín 10G)
    swap_gb_temp=$(( $(convertir_a_mb "$SWAP_SIZE") / 1024 ))
    usable_gb_temp=$(( DISK_SIZE_GB - swap_gb_temp - 1 ))
    suggested_root_gb=$(( usable_gb_temp * 60 / 100 ))
    if (( suggested_root_gb > 40 )); then
        suggested_root_gb=40
    elif (( suggested_root_gb < 10 )); then
        suggested_root_gb=10
    fi
    
    while true; do
        ask "Tamaño de la partición raíz (/)" "${suggested_root_gb}G"
        ROOT_SIZE="$REPLY"
        
        # Validar si los tamaños solicitados caben físicamente en el disco
        swap_mb=$(convertir_a_mb "$SWAP_SIZE")
        root_mb=$(convertir_a_mb "$ROOT_SIZE")
        efi_mb=512
        total_req_mb=$(( swap_mb + root_mb + efi_mb ))
        total_req_gb=$(( (total_req_mb + 1023) / 1024 )) # Redondeo hacia arriba en GB
        
        if (( total_req_gb >= DISK_SIZE_GB )); then
            warn "El tamaño solicitado para Raíz ($ROOT_SIZE) + Swap ($SWAP_SIZE) + EFI ($efi_mb MB) = $total_req_gb GB supera el tamaño real del disco ($DISK_SIZE_GB GB)."
            max_root_mb=$(( (DISK_SIZE_GB * 1024) - swap_mb - efi_mb - 2048 )) # Deja un margen de seguridad de 2GB
            if (( max_root_mb <= 0 )); then
                error "El disco es demasiado pequeño ($DISK_SIZE_GB GB) para la Swap asignada ($SWAP_SIZE). Reduce la Swap o desactívala."
            else
                info "Por favor, elige un tamaño menor para la raíz (máximo recomendado: $(( max_root_mb / 1024 ))G)."
            fi
        else
            break
        fi
    done
fi

# ── Sistema ────────────────────────────────────────────────────────────────────
ask "Hostname" "archbox"
HOSTNAME="$REPLY"

echo -e "\n${DIM}  Ejemplos: Europe/Madrid, America/New_York, Asia/Tokyo${NC}"
ask "Zona horaria" "Europe/Madrid"
TIMEZONE="$REPLY"

pick "Idioma del sistema" "es_ES.UTF-8" "en_US.UTF-8" "ca_ES.UTF-8" "fr_FR.UTF-8" "de_DE.UTF-8"
LOCALE="$PICKED"

pick "Mapa de teclado (consola)" "es" "en" "us" "fr" "de" "latam"
KEYMAP="$PICKED"

pick "Kernel" "linux" "linux-lts" "linux-zen" "linux-hardened"
KERNEL="$PICKED"

if $UEFI; then
    pick "Bootloader" "grub" "systemd-boot"
else
    pick "Bootloader" "grub"
fi
BOOTLOADER="$PICKED"

step "2/3" "Usuario y contraseñas"

ask "Nombre de usuario" "user"
USERNAME="$REPLY"

ask_pass "Contraseña para root"
ROOT_PASSWORD="$PASS"

ask_pass "Contraseña para $USERNAME"
USER_PASSWORD="$PASS"

step "3/3" "Extras (opcionales)"

pick "AUR helper" "paru" "yay" "ninguno"
AUR_HELPER="$PICKED"
[[ "$AUR_HELPER" == "ninguno" ]] && AUR_HELPER=""

ask_yn "¿Instalar dotfiles desde un repositorio git?" "n"
DOTFILES_REPO=""
DOTFILES_SCRIPT="install.sh"
if [[ "$YN" == "s" ]]; then
    ask "URL del repositorio" ""
    DOTFILES_REPO="$REPLY"
    ask "Script de instalación dentro del repo" "install.sh"
    DOTFILES_SCRIPT="$REPLY"
fi

ask_yn "¿Habilitar SSH?" "n"
ENABLE_SSH="$YN"

# ── Resumen ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             RESUMEN DE INSTALACIÓN                  ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
echo -e "  ${DIM}Disco:${NC}       ${BOLD}$DISK${NC}   ${RED}(se borrará todo el contenido)${NC}"
echo -e "  ${DIM}Swap:${NC}        $( [[ "$SWAP_SIZE" == "0" ]] && echo "desactivada" || echo "$SWAP_SIZE" )"
if [[ "$SEPARATE_HOME" == "s" ]]; then
    echo -e "  ${DIM}Raíz (/):${NC}    $ROOT_SIZE"
    echo -e "  ${DIM}Home (/home):${NC}${GREEN} separada ${NC}${DIM}(resto del disco)${NC}"
else
    echo -e "  ${DIM}Raíz (/):${NC}    todo el disco  ${DIM}(sin /home separado)${NC}"
fi
echo -e "  ${DIM}Hostname:${NC}    $HOSTNAME"
echo -e "  ${DIM}Timezone:${NC}    $TIMEZONE"
echo -e "  ${DIM}Locale:${NC}      $LOCALE   teclado: $KEYMAP"
echo -e "  ${DIM}Kernel:${NC}      $KERNEL"
echo -e "  ${DIM}Bootloader:${NC}  $BOOTLOADER   $( $UEFI && echo '[UEFI]' || echo '[BIOS]' )"
echo -e "  ${DIM}Usuario:${NC}     $USERNAME"
echo -e "  ${DIM}AUR helper:${NC}  $( [[ -n "$AUR_HELPER" ]] && echo "$AUR_HELPER" || echo "ninguno" )"
echo -e "  ${DIM}SSH:${NC}         $( [[ "$ENABLE_SSH" == "s" ]] && echo "habilitado" || echo "deshabilitado" )"
[[ -n "$DOTFILES_REPO" ]] && echo -e "  ${DIM}Dotfiles:${NC}    $DOTFILES_REPO"
echo ""

warn "¡Esta operación DESTRUIRÁ todos los datos de ${BOLD}${DISK}${NC}${YELLOW}!"
echo -ne "\n${BOLD}  Escribe 'si' para iniciar la instalación: ${NC}"
read -r CONFIRM
[[ "$CONFIRM" == "si" ]] || { info "Instalación cancelada."; exit 0; }

# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS INTERNOS
# ══════════════════════════════════════════════════════════════════════════════
convertir_a_mb() {
    local v="${1//[GgMm]/}"
    if [[ "$1" == *[Gg] ]]; then
        echo $(( v * 1024 ))
    else
        echo "$v"
    fi
}

part() {
    local disk="$1" num="$2"
    if [[ "$disk" == *nvme* ]] || [[ "$disk" == *mmcblk* ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}


# ══════════════════════════════════════════════════════════════════════════════
#  FASE 2 — INSTALACIÓN AUTOMÁTICA
# ══════════════════════════════════════════════════════════════════════════════

# ── Particionado ───────────────────────────────────────────────────────────────
step "·" "Particionando $DISK"
wipefs -af "$DISK" &>/dev/null
sgdisk -Z "$DISK" &>/dev/null

if $UEFI; then
    sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
    if [[ "$SWAP_SIZE" != "0" ]]; then
        sgdisk -n 2:0:+"$SWAP_SIZE" -t 2:8200 -c 2:"swap" "$DISK"
        if [[ "$SEPARATE_HOME" == "s" ]]; then
            sgdisk -n 3:0:+"$ROOT_SIZE" -t 3:8300 -c 3:"root" "$DISK"
            sgdisk -n 4:0:0             -t 4:8300 -c 4:"home" "$DISK"
            PART_EFI=$(part "$DISK" 1); PART_SWAP=$(part "$DISK" 2); PART_ROOT=$(part "$DISK" 3); PART_HOME=$(part "$DISK" 4)
        else
            sgdisk -n 3:0:0 -t 3:8300 -c 3:"root" "$DISK"
            PART_EFI=$(part "$DISK" 1); PART_SWAP=$(part "$DISK" 2); PART_ROOT=$(part "$DISK" 3); PART_HOME=""
        fi
    else
        if [[ "$SEPARATE_HOME" == "s" ]]; then
            sgdisk -n 2:0:+"$ROOT_SIZE" -t 2:8300 -c 2:"root" "$DISK"
            sgdisk -n 3:0:0             -t 3:8300 -c 3:"home" "$DISK"
            PART_EFI=$(part "$DISK" 1); PART_SWAP=""; PART_ROOT=$(part "$DISK" 2); PART_HOME=$(part "$DISK" 3)
        else
            sgdisk -n 2:0:0 -t 2:8300 -c 2:"root" "$DISK"
            PART_EFI=$(part "$DISK" 1); PART_SWAP=""; PART_ROOT=$(part "$DISK" 2); PART_HOME=""
        fi
    fi
else
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary 1MiB 3MiB
    if [[ "$SWAP_SIZE" != "0" ]]; then
        swap_mb=$(convertir_a_mb "$SWAP_SIZE")
        parted -s "$DISK" mkpart primary linux-swap 3MiB "$((3 + swap_mb))MiB"
        if [[ "$SEPARATE_HOME" == "s" ]]; then
            root_mb=$(convertir_a_mb "$ROOT_SIZE")
            parted -s "$DISK" mkpart primary ext4 "$((3 + swap_mb))MiB" "$((3 + swap_mb + root_mb))MiB"
            parted -s "$DISK" mkpart primary ext4 "$((3 + swap_mb + root_mb))MiB" 100%
            PART_SWAP=$(part "$DISK" 2); PART_ROOT=$(part "$DISK" 3); PART_HOME=$(part "$DISK" 4)
        else
            parted -s "$DISK" mkpart primary ext4 "$((3 + swap_mb))MiB" 100%
            PART_SWAP=$(part "$DISK" 2); PART_ROOT=$(part "$DISK" 3); PART_HOME=""
        fi
    else
        if [[ "$SEPARATE_HOME" == "s" ]]; then
            root_mb=$(convertir_a_mb "$ROOT_SIZE")
            parted -s "$DISK" mkpart primary ext4 3MiB "$((3 + root_mb))MiB"
            parted -s "$DISK" mkpart primary ext4 "$((3 + root_mb))MiB" 100%
            PART_SWAP=""; PART_ROOT=$(part "$DISK" 2); PART_HOME=$(part "$DISK" 3)
        else
            parted -s "$DISK" mkpart primary ext4 3MiB 100%
            PART_SWAP=""; PART_ROOT=$(part "$DISK" 2); PART_HOME=""
        fi
    fi
    PART_EFI=""
fi
log "Particionado completo."

# ── Formato ────────────────────────────────────────────────────────────────────
step "·" "Formateando particiones"
sleep 1
$UEFI && { info "FAT32 → $PART_EFI"; mkfs.fat -F32 -n "EFI" "$PART_EFI"; }
if [[ -n "$PART_SWAP" ]]; then
    info "swap → $PART_SWAP"
    mkswap -L "swap" "$PART_SWAP"
    swapon "$PART_SWAP"
fi
info "ext4 → $PART_ROOT"
mkfs.ext4 -L "root" -F "$PART_ROOT"
if [[ -n "$PART_HOME" ]]; then
    info "ext4 → $PART_HOME"
    mkfs.ext4 -L "home" -F "$PART_HOME"
fi
log "Formato completo."

# ── Montaje ────────────────────────────────────────────────────────────────────
mount "$PART_ROOT" /mnt
if [[ -n "$PART_HOME" ]]; then
    mkdir -p /mnt/home
    mount "$PART_HOME" /mnt/home
fi
if $UEFI; then
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi

# ── Mirrors ────────────────────────────────────────────────────────────────────
step "·" "Actualizando mirrors"
reflector --verbose --country Spain,France,Germany --age 12 --protocol https \
          --sort rate --save /etc/pacman.d/mirrorlist \
    && log "Mirrors actualizados." || warn "reflector falló, usando mirrors existentes."

# ── Microcode ──────────────────────────────────────────────────────────────────
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
[[ "$CPU_VENDOR" == "GenuineIntel" ]] && MICROCODE="intel-ucode" || MICROCODE="amd-ucode"
info "Microcode detectado: $MICROCODE"

# ── pacstrap ───────────────────────────────────────────────────────────────────
step "·" "Instalando sistema base (esto tarda un poco)"
pacstrap -K /mnt \
    base "$KERNEL" "${KERNEL}-headers" linux-firmware base-devel \
    "$MICROCODE" \
    networkmanager git nvim vim sudo curl wget reflector \
    man-db man-pages bash-completion htop openssh \
    grub efibootmgr os-prober
log "Sistema base instalado."

# ── fstab ──────────────────────────────────────────────────────────────────────
genfstab -U /mnt >> /mnt/etc/fstab

# ══════════════════════════════════════════════════════════════════════════════
#  FASE 3 — CHROOT (generamos el script al vuelo y lo ejecutamos)
# ══════════════════════════════════════════════════════════════════════════════
step "·" "Configurando el sistema (chroot)"

cat > /mnt/root/_chroot.sh << CHROOT
#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "\${GREEN}  ✔  \${NC}\$*"; }
info() { echo -e "\${CYAN}  →  \${NC}\$*"; }

# Variables inyectadas desde el script padre
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
LANG_EXTRA="en_US.UTF-8"
USERNAME="$USERNAME"
ROOT_PASSWORD="$ROOT_PASSWORD"
USER_PASSWORD="$USER_PASSWORD"
USER_GROUPS="wheel,audio,video,storage,optical,network,input"
KERNEL="$KERNEL"
MICROCODE="$MICROCODE"
BOOTLOADER="$BOOTLOADER"
UEFI=$UEFI
DISK="$DISK"
PART_EFI="${PART_EFI:-}"
PART_ROOT="$PART_ROOT"
PART_HOME="${PART_HOME:-}"
AUR_HELPER="$AUR_HELPER"
DOTFILES_REPO="$DOTFILES_REPO"
DOTFILES_SCRIPT="$DOTFILES_SCRIPT"
ENABLE_SSH="$ENABLE_SSH"

# Timezone
info "Zona horaria: \$TIMEZONE"
ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale
info "Locale: \$LOCALE"
sed -i "s/#\${LOCALE}/\${LOCALE}/" /etc/locale.gen
sed -i "s/#\${LANG_EXTRA}/\${LANG_EXTRA}/" /etc/locale.gen
locale-gen
echo "LANG=\$LOCALE"  > /etc/locale.conf
echo "KEYMAP=\$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain  \${HOSTNAME}
EOF

# pacman — color + descargas paralelas
sed -i 's/^#Color/Color/'                         /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/'  /etc/pacman.conf

# Red
systemctl enable NetworkManager

# SSH
[[ "\$ENABLE_SSH" == "s" ]] && systemctl enable sshd

# Contraseñas
echo "root:\${ROOT_PASSWORD}" | chpasswd

# Usuario
useradd -m -G "\$USER_GROUPS" -s /bin/bash "\$USERNAME"
echo "\${USERNAME}:\${USER_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# initramfs
info "Generando initramfs…"
mkinitcpio -P

# Bootloader
info "Instalando bootloader: \$BOOTLOADER"
if [[ "\$BOOTLOADER" == "grub" ]]; then
    if \$UEFI; then
        grub-install --target=x86_64-efi \
                     --efi-directory=/boot/efi \
                     --bootloader-id=GRUB --recheck
    else
        grub-install --target=i386-pc --recheck "\$DISK"
    fi
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
else
    bootctl install
    ROOT_UUID=\$(blkid -s PARTUUID -o value "\$PART_ROOT")
    mkdir -p /boot/loader/entries
    cat > /boot/loader/loader.conf <<EOF
default  arch.conf
timeout  3
console-mode max
editor   no
EOF
    cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-\${KERNEL}
initrd  /\${MICROCODE}.img
initrd  /initramfs-\${KERNEL}.img
options root=PARTUUID=\${ROOT_UUID} rw quiet
EOF
fi
log "Bootloader instalado."

# Reflector timer
cat > /etc/xdg/reflector/reflector.conf <<EOF
--country Spain,France,Germany
--age 12
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
EOF
systemctl enable reflector.timer

# AUR helper
if [[ -n "\$AUR_HELPER" ]]; then
    info "Compilando \$AUR_HELPER…"
    sudo -u "\$USERNAME" bash -c "
        cd /tmp
        git clone https://aur.archlinux.org/\${AUR_HELPER}-bin.git
        cd \${AUR_HELPER}-bin
        makepkg -si --noconfirm
        rm -rf /tmp/\${AUR_HELPER}-bin
    " && log "\$AUR_HELPER instalado." || echo "  !  AUR helper falló. Instálalo luego manualmente."
fi

# Dotfiles
if [[ -n "\$DOTFILES_REPO" ]]; then
    info "Clonando dotfiles…"
    sudo -u "\$USERNAME" bash -c "
        git clone '\$DOTFILES_REPO' /home/\${USERNAME}/.dotfiles
        cd /home/\${USERNAME}/.dotfiles
        [[ -f '\$DOTFILES_SCRIPT' ]] && bash '\$DOTFILES_SCRIPT' || true
    " && log "Dotfiles instalados." || echo "  !  Dotfiles fallaron. Instálalos luego manualmente."
fi

log "Chroot completado."
CHROOT

chmod +x /mnt/root/_chroot.sh
arch-chroot /mnt /bin/bash /root/_chroot.sh
rm -f /mnt/root/_chroot.sh

# ── Desmontaje ─────────────────────────────────────────────────────────────────
step "·" "Desmontando"
umount -R /mnt
[[ -n "${PART_SWAP:-}" ]] && swapoff "$PART_SWAP" 2>/dev/null || true

# ── Fin ────────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${GREEN}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════╗
  ║       ✔  Instalación completada con éxito       ║
  ╚══════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo -e "  ${DIM}Sistema instalado en:${NC} ${BOLD}$DISK${NC}"
echo -e "  ${DIM}Usuario creado:${NC}       ${BOLD}$USERNAME${NC}"
echo -e "  ${DIM}Hostname:${NC}             ${BOLD}$HOSTNAME${NC}"
echo ""
echo -e "  ${CYAN}Extrae el medio de instalación y reinicia:${NC}"
echo -e "  ${BOLD}  reboot${NC}"
echo ""