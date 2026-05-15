#!/usr/bin/env bash
# =============================================================================
#  chroot.sh — Configuración dentro del chroot
#  No ejecutes esto directamente, lo llama install.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $*"; }
info() { echo -e "${CYAN}[→]${NC} $*"; }
warn() { echo -e "\033[1;33m[!]${NC} $*"; }

# Cargar configuración
source /root/config.sh
source /root/env.sh

# ── Zona horaria ──────────────────────────────────────────────────────────────
info "Configurando zona horaria: $TIMEZONE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
log "Zona horaria lista."

# ── Locale ────────────────────────────────────────────────────────────────────
info "Generando locales…"
sed -i "s/#${LOCALE}/${LOCALE}/" /etc/locale.gen
if [[ -n "$LANG_EXTRA" ]]; then
    sed -i "s/#${LANG_EXTRA}/${LANG_EXTRA}/" /etc/locale.gen
fi
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
log "Locale configurado."

# ── Hostname ──────────────────────────────────────────────────────────────────
info "Hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain  ${HOSTNAME}
EOF
log "Hostname configurado."

# ── Red ───────────────────────────────────────────────────────────────────────
info "Habilitando NetworkManager…"
systemctl enable NetworkManager
log "NetworkManager habilitado."

# ── SSH (opcional) ────────────────────────────────────────────────────────────
if pacman -Qi openssh &>/dev/null; then
    systemctl enable sshd
    log "sshd habilitado."
fi

# ── Contraseña root ───────────────────────────────────────────────────────────
info "Configurando contraseña root…"
echo "root:${ROOT_PASSWORD}" | chpasswd
log "Contraseña root establecida."

# ── Usuario ───────────────────────────────────────────────────────────────────
info "Creando usuario: $USERNAME"
useradd -m -G "$USER_GROUPS" -s /bin/bash "$USERNAME"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# sudo sin contraseña para wheel (puedes endurecer esto después)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
log "Usuario $USERNAME creado."

# ── Pacman: habilitar multilib y color ────────────────────────────────────────
info "Optimizando pacman…"
sed -i 's/^#Color/Color/'                     /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
# Multilib
sed -i '/\[multilib\]/{n;s/^#Include/Include/}' /etc/pacman.conf
sed -i 's/^#\[multilib\]/[multilib]/'           /etc/pacman.conf
pacman -Sy --noconfirm 2>/dev/null || true
log "pacman optimizado."

# ── mkinitcpio ────────────────────────────────────────────────────────────────
info "Generando initramfs…"
mkinitcpio -P
log "initramfs generado."

# ── Bootloader ────────────────────────────────────────────────────────────────
info "Instalando bootloader: $BOOTLOADER"
if [[ "$BOOTLOADER" == "grub" ]]; then
    pacman -S --noconfirm grub efibootmgr os-prober
    if $UEFI; then
        grub-install --target=x86_64-efi \
                     --efi-directory=/boot/efi \
                     --bootloader-id=GRUB \
                     --recheck
    else
        grub-install --target=i386-pc \
                     --recheck \
                     "$DISK"
    fi
    # Habilitar os-prober para detectar otros SO
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg

elif [[ "$BOOTLOADER" == "systemd-boot" ]]; then
    bootctl install
    # Obtener PARTUUID de root
    ROOT_UUID=$(blkid -s PARTUUID -o value "$PART_ROOT")
    mkdir -p /boot/loader/entries
    cat > /boot/loader/loader.conf <<EOF
default  arch.conf
timeout  3
console-mode max
editor   no
EOF
    cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-${KERNEL}
$( [[ -n "${MICROCODE:-}" ]] && echo "initrd  /${MICROCODE}.img" )
initrd  /initramfs-${KERNEL}.img
options root=PARTUUID=${ROOT_UUID} rw quiet
EOF
fi
log "Bootloader instalado."

# ── AUR helper ────────────────────────────────────────────────────────────────
if [[ -n "$AUR_HELPER" ]]; then
    info "Instalando $AUR_HELPER…"
    # Clonar y compilar como el usuario creado (no como root)
    sudo -u "$USERNAME" bash -c "
        cd /tmp
        git clone https://aur.archlinux.org/${AUR_HELPER}-bin.git
        cd ${AUR_HELPER}-bin
        makepkg -si --noconfirm
        rm -rf /tmp/${AUR_HELPER}-bin
    " && log "$AUR_HELPER instalado." || warn "No se pudo instalar $AUR_HELPER. Hazlo manualmente."
fi

# ── Paquetes AUR ──────────────────────────────────────────────────────────────
if [[ -n "$AUR_HELPER" ]] && [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
    info "Instalando paquetes AUR…"
    sudo -u "$USERNAME" "$AUR_HELPER" -S --noconfirm "${AUR_PACKAGES[@]}" \
        && log "Paquetes AUR instalados." \
        || warn "Algunos paquetes AUR fallaron."
fi

# ── Dotfiles ──────────────────────────────────────────────────────────────────
if [[ -n "$DOTFILES_REPO" ]]; then
    info "Clonando dotfiles desde $DOTFILES_REPO…"
    sudo -u "$USERNAME" bash -c "
        git clone '$DOTFILES_REPO' /home/${USERNAME}/.dotfiles
        cd /home/${USERNAME}/.dotfiles
        [[ -f '$DOTFILES_SCRIPT' ]] && bash '$DOTFILES_SCRIPT' || true
    " && log "Dotfiles instalados." || warn "Dotfiles fallaron. Instálalos manualmente."
fi

# ── Reflector al arranque ─────────────────────────────────────────────────────
if pacman -Qi reflector &>/dev/null; then
    cat > /etc/xdg/reflector/reflector.conf <<EOF
--country Spain,France,Germany
--age 12
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
EOF
    systemctl enable reflector.timer
    log "reflector.timer habilitado."
fi

log "Configuración chroot completada."
