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
    if [[ "$REPLY" == "<" ]]; then return 99; fi
    if [[ -z "$REPLY" ]]; then REPLY="$default"; fi
}

# Pregunta sí/no: ask_yn "Pregunta" "s|n" → $YN
ask_yn() {
    local prompt="$1" default="${2:-s}"
    local opts
    if [[ "$default" == "s" ]]; then opts="${BOLD}S${NC}/n"; else opts="s/${BOLD}N${NC}"; fi
    echo -ne "\n${BOLD}${BLUE}  ?  ${NC}${BOLD}${prompt}${NC} ${DIM}[${opts}]${NC}: "
    read -r YN || true
    if [[ "$YN" == "<" ]]; then return 99; fi
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
        if [[ "$SEL" == "<" ]]; then return 99; fi
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
        if [[ "$P1" == "<" ]]; then return 99; fi
        echo -ne "     ${DIM}Confirma:${NC} "
        read -rs P2; echo
        if [[ "$P2" == "<" ]]; then return 99; fi
        if [[ "$P1" == "$P2" ]]; then PASS="$P1"; break
        else echo -e "     ${RED}No coinciden, inténtalo de nuevo.${NC}"; fi
    done
}

# Convierte un tamaño con sufijo (ej. 8G, 512M) a megabytes enteros
convertir_a_mb() {
    local input="$1"
    local val="${input//[GgMm]/}"
    if [[ "$input" == *[Gg] ]]; then
        echo $(( val * 1024 ))
    else
        echo "$val"
    fi
}

# Valida que el tamaño tenga formato correcto: número seguido de G o M (ej. 8G, 512M)
# Devuelve 0 si es válido, 1 si no lo es (imprime un aviso en caso de error)
validar_tamano() {
    local input="$1" etiqueta="${2:-tamaño}"
    if [[ ! "$input" =~ ^[0-9]+[GgMm]$ ]]; then
        warn "Formato inválido: '${input}'. Debes indicar un número seguido de la unidad G o M."
        info "Ejemplos válidos: ${BOLD}8G${NC}${CYAN}  (8 gigabytes)${NC}   ${BOLD}512M${NC}${CYAN}  (512 megabytes)${NC}"
        return 1
    fi
    return 0
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

info "Puedes escribir ${BOLD}<${NC} y pulsar Enter en cualquier pregunta para volver atrás."

HISTORIAL=()
PASO=1

while true; do
    case "$PASO" in
        1)
            step "1/3" "Configuración del sistema"
            echo -e "\n${DIM}  Discos disponibles:${NC}"
            lsblk -dpno NAME,SIZE,MODEL | grep -v 'loop\|sr0' | while read -r line; do
                echo -e "     ${CYAN}${line}${NC}"
            done
            ask "Disco destino" "${DISK:-/dev/sda}" || { echo -e "  ${YELLOW}Ya estás en el primer paso.${NC}"; continue; }
            DISK="$REPLY"
            if [[ ! -b "$DISK" ]]; then
                warn "El disco '$DISK' no existe."
                continue
            fi
            DISK_SIZE_BYTES=$(lsblk -b -no SIZE "$DISK" | head -n1)
            DISK_SIZE_GB=$(( DISK_SIZE_BYTES / 1024 / 1024 / 1024 ))
            HISTORIAL+=("$PASO")
            PASO=2
            ;;
        2)
            ask_yn "¿Activar swap?" "${ACTIVATE_SWAP:-s}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            ACTIVATE_SWAP="$YN"
            HISTORIAL+=("$PASO")
            if [[ "$ACTIVATE_SWAP" == "s" ]]; then PASO=3; else SWAP_SIZE="0"; PASO="3_luks"; fi
            ;;
        3)
            ask "Tamaño de swap" "${SWAP_SIZE_OK:-8G}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            SWAP_SIZE="$REPLY"
            if ! validar_tamano "$SWAP_SIZE"; then SWAP_SIZE=""; continue; fi
            
            swap_mb=$(convertir_a_mb "$SWAP_SIZE")
            swap_gb=$(( swap_mb / 1024 ))
            min_required_gb=10
            
            if (( swap_gb >= DISK_SIZE_GB - min_required_gb )); then
                warn "La partición de Swap de $SWAP_SIZE es demasiado grande para tu disco de $DISK_SIZE_GB GB."
                max_swap_gb=$(( DISK_SIZE_GB - min_required_gb ))
                if (( max_swap_gb <= 0 )); then
                    warn "Tu disco de $DISK_SIZE_GB GB es demasiado pequeño para soportar Swap. Se desactivará automáticamente."
                    SWAP_SIZE="0"
                    HISTORIAL+=("$PASO")
                    PASO=4
                else
                    info "Por favor, elige un tamaño de Swap menor (máximo recomendado: ${max_swap_gb}G)."
                    SWAP_SIZE=""  # limpiar para que el default no muestre el valor inválido
                fi
                continue
            fi
            SWAP_SIZE_OK="$SWAP_SIZE"  # valor confirmado como válido
            HISTORIAL+=("$PASO")
            PASO="3_luks"
            ;;
        "3_luks")
            ask_yn "¿Cifrar el disco con LUKS?" "${LUKS:-n}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            LUKS="$YN"
            HISTORIAL+=("$PASO")
            if [[ "$LUKS" == "s" ]]; then PASO="3_luks_pass"; else LUKS_PASS=""; PASO=4; fi
            ;;
        "3_luks_pass")
            ask_pass "Contraseña de cifrado LUKS" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            LUKS_PASS="$PASS"
            warn "Si olvidas esta contraseña, tus datos serán irrecuperables."
            echo -ne "     ${BOLD}Escribe 'si' para confirmar que lo entiendes:${NC} "
            read -r CONFIRM_LUKS
            if [[ "$CONFIRM_LUKS" != "si" ]]; then LUKS_PASS=""; continue; fi
            HISTORIAL+=("$PASO")
            PASO=4
            ;;
        4)
            ask_yn "¿Crear una partición separada para /home?" "${SEPARATE_HOME:-n}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            SEPARATE_HOME="$YN"
            HISTORIAL+=("$PASO")
            if [[ "$SEPARATE_HOME" == "s" ]]; then PASO=5; else ROOT_SIZE="0"; PASO=6; fi
            ;;
        5)
            dim "  El espacio sobrante tras la raíz se asignará a /home automáticamente."
            dim "  Tamaño total detectado del disco: ${DISK_SIZE_GB} GB"
            
            swap_gb_temp=$(( $(convertir_a_mb "$SWAP_SIZE") / 1024 ))
            usable_gb_temp=$(( DISK_SIZE_GB - swap_gb_temp - 1 ))
            suggested_root_gb=$(( usable_gb_temp * 60 / 100 ))
            if (( suggested_root_gb > 40 )); then suggested_root_gb=40
            elif (( suggested_root_gb < 10 )); then suggested_root_gb=10; fi
            
            if (( suggested_root_gb >= usable_gb_temp )); then
                suggested_root_gb=$(( usable_gb_temp - 2 ))
                if (( suggested_root_gb < 10 )); then suggested_root_gb=10; fi
            fi
            
            ask "Tamaño de la partición raíz (/)" "${ROOT_SIZE_OK:-${suggested_root_gb}G}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            ROOT_SIZE="$REPLY"
            
            if ! validar_tamano "$ROOT_SIZE"; then ROOT_SIZE=""; continue; fi
            
            swap_mb=$(convertir_a_mb "$SWAP_SIZE")
            root_mb=$(convertir_a_mb "$ROOT_SIZE")
            efi_mb=512
            total_req_mb=$(( swap_mb + root_mb + efi_mb ))
            total_req_gb=$(( (total_req_mb + 1023) / 1024 ))
            max_allowed_root_mb=$(( (DISK_SIZE_GB * 1024) - swap_mb - efi_mb - 2048 ))
            
            if (( root_mb < 10240 )); then
                warn "El tamaño solicitado de raíz ($ROOT_SIZE) es inferior al mínimo recomendado (10 GB)."
                info "Por favor, elige un tamaño de al menos 10G."
                ROOT_SIZE=""; continue
            elif (( total_req_gb >= DISK_SIZE_GB )); then
                warn "Raíz ($ROOT_SIZE) + Swap ($SWAP_SIZE) + EFI = $total_req_gb GB supera el disco ($DISK_SIZE_GB GB)."
                if (( max_allowed_root_mb <= 0 )); then
                    warn "Disco demasiado pequeño. Escribe '<' para volver atrás y reducir la Swap."
                else
                    info "Elige un tamaño menor para la raíz (máximo recomendado: $(( max_allowed_root_mb / 1024 ))G)."
                fi
                ROOT_SIZE=""; continue
            elif (( root_mb > max_allowed_root_mb )); then
                warn "Raíz ($ROOT_SIZE) no deja espacio útil para /home (mínimo 2 GB)."
                info "Tamaño máximo de raíz permitido: $(( max_allowed_root_mb / 1024 ))G."
                ROOT_SIZE=""; continue
            fi
            ROOT_SIZE_OK="$ROOT_SIZE"  # valor confirmado como válido
            HISTORIAL+=("$PASO")
            PASO=6
            ;;
        6)
            ask "Hostname" "${HOSTNAME:-archbox}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            HOSTNAME="$REPLY"
            HISTORIAL+=("$PASO")
            PASO=7
            ;;
        7)
            echo -e "\n${DIM}  Ejemplos: Europe/Madrid, America/New_York, Asia/Tokyo${NC}"
            ask "Zona horaria" "${TIMEZONE_OK:-Europe/Madrid}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            TIMEZONE="$REPLY"
            if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
                warn "La zona horaria '$TIMEZONE' no es válida o no existe."
                TIMEZONE=""
                continue
            fi
            TIMEZONE_OK="$TIMEZONE"
            HISTORIAL+=("$PASO")
            PASO=8
            ;;
        8)
            pick "Idioma del sistema" "es_ES.UTF-8" "en_US.UTF-8" "ca_ES.UTF-8" "fr_FR.UTF-8" "de_DE.UTF-8" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            LOCALE="$PICKED"
            HISTORIAL+=("$PASO")
            PASO=9
            ;;
        9)
            pick "Mapa de teclado (consola)" "es" "en" "us" "fr" "de" "latam" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            KEYMAP="$PICKED"
            HISTORIAL+=("$PASO")
            PASO=10
            ;;
        10)
            pick "Kernel" "linux" "linux-lts" "linux-zen" "linux-hardened" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            KERNEL="$PICKED"
            HISTORIAL+=("$PASO")
            PASO=11
            ;;
        11)
            if $UEFI; then
                pick "Bootloader" "grub" "systemd-boot" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            else
                pick "Bootloader" "grub" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            fi
            BOOTLOADER="$PICKED"
            if [[ "$LUKS" == "s" && "$BOOTLOADER" == "grub" ]]; then
                info "Has activado LUKS y GRUB. Se usará LUKS1 por compatibilidad."
                sleep 2
            fi
            HISTORIAL+=("$PASO")
            PASO=12
            ;;
        12)
            step "2/3" "Usuario y contraseñas"
            ask "Nombre de usuario" "${USERNAME:-user}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            USERNAME="$REPLY"
            HISTORIAL+=("$PASO")
            PASO=13
            ;;
        13)
            ask_pass "Contraseña para root" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            ROOT_PASSWORD="$PASS"
            HISTORIAL+=("$PASO")
            PASO=14
            ;;
        14)
            ask_pass "Contraseña para $USERNAME" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            USER_PASSWORD="$PASS"
            HISTORIAL+=("$PASO")
            PASO=15
            ;;
        15)
            step "3/3" "Extras (opcionales)"
            pick "AUR helper" "paru" "yay" "ninguno" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            AUR_HELPER="$PICKED"
            [[ "$AUR_HELPER" == "ninguno" ]] && AUR_HELPER=""
            HISTORIAL+=("$PASO")
            PASO=16
            ;;
        16)
            ask_yn "¿Instalar dotfiles desde un repositorio git?" "${INSTALL_DOTFILES:-n}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            INSTALL_DOTFILES="$YN"
            HISTORIAL+=("$PASO")
            if [[ "$INSTALL_DOTFILES" == "s" ]]; then PASO=17; else DOTFILES_REPO=""; DOTFILES_SCRIPT="install.sh"; PASO=19; fi
            ;;
        17)
            ask "URL del repositorio" "${DOTFILES_REPO:-}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            DOTFILES_REPO="$REPLY"
            HISTORIAL+=("$PASO")
            PASO=18
            ;;
        18)
            ask "Script de instalación dentro del repo" "${DOTFILES_SCRIPT:-install.sh}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            DOTFILES_SCRIPT="$REPLY"
            HISTORIAL+=("$PASO")
            PASO=19
            ;;
        19)
            ask_yn "¿Habilitar SSH?" "${ENABLE_SSH:-n}" || { PASO="${HISTORIAL[-1]}"; unset 'HISTORIAL[-1]'; continue; }
            ENABLE_SSH="$YN"
            break # Terminamos la fase 1 exitosamente
            ;;
    esac
done

# ── Resumen ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             RESUMEN DE INSTALACIÓN                  ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
echo -e "  ${DIM}Disco:${NC}       ${BOLD}$DISK${NC}   ${RED}(se borrará todo el contenido)${NC}"
echo -e "  ${DIM}Swap:${NC}        $( [[ "$SWAP_SIZE" == "0" ]] && echo "desactivada" || echo "$SWAP_SIZE" )"
echo -e "  ${DIM}Cifrado LUKS:${NC} $( [[ "${LUKS:-n}" == "s" ]] && echo -e "${GREEN}activado${NC}" || echo "desactivado" )"
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

# ── Comprobación de montajes previos ──────────────────────────────────────────
_NEEDS_CLEANUP=false
if mountpoint -q /mnt 2>/dev/null || grep -q '^[^ ]* /mnt' /proc/mounts 2>/dev/null; then
    _NEEDS_CLEANUP=true
fi
if lsblk "$DISK" 2>/dev/null | grep -q "crypt"; then
    _NEEDS_CLEANUP=true
fi

if $_NEEDS_CLEANUP; then
    echo ""
    warn "Se han detectado particiones montadas o contenedores LUKS abiertos en el disco destino."
    echo -ne "\n${BOLD}  ¿Desmontar y cerrar todo para continuar? (s/n):${NC} "
    read -r _UMOUNT_CONFIRM
    if [[ "$_UMOUNT_CONFIRM" =~ ^[sS]$ ]]; then
        info "Limpiando montajes y contenedores..."
        swapoff -a 2>/dev/null || true
        umount -R /mnt 2>/dev/null || true
        cryptsetup close crypthome 2>/dev/null || true
        cryptsetup close cryptroot 2>/dev/null || true
        log "Limpieza completada. Continuando con la instalación."
    else
        info "Instalación cancelada por el usuario."
        exit 0
    fi
fi

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
info "Recargando tabla de particiones (partprobe)..."
partprobe "$DISK" 2>/dev/null || true
sleep 2
log "Particionado completo."

# ── Formato ────────────────────────────────────────────────────────────────────
step "·" "Formateando particiones"
sleep 1
$UEFI && { info "FAT32 → $PART_EFI"; mkfs.fat -F32 -n "EFI" "$PART_EFI"; }

if [[ "${LUKS:-n}" == "s" ]]; then
    info "luksFormat → $PART_ROOT"
    if [[ "$BOOTLOADER" == "grub" ]]; then
        echo -n "$LUKS_PASS" | cryptsetup luksFormat --batch-mode --type luks1 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --iter-time 3000 "$PART_ROOT" -
    else
        echo -n "$LUKS_PASS" | cryptsetup luksFormat --batch-mode --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --iter-time 3000 "$PART_ROOT" -
    fi
    info "luksOpen → cryptroot"
    echo -n "$LUKS_PASS" | cryptsetup open "$PART_ROOT" cryptroot -
    
    info "ext4 → /dev/mapper/cryptroot"
    mkfs.ext4 -L "root" -F /dev/mapper/cryptroot
    
    if [[ -n "$PART_HOME" ]]; then
        info "luksFormat → $PART_HOME"
        echo -n "$LUKS_PASS" | cryptsetup luksFormat --batch-mode --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --iter-time 3000 "$PART_HOME" -
        info "luksOpen → crypthome"
        echo -n "$LUKS_PASS" | cryptsetup open "$PART_HOME" crypthome -
        
        info "ext4 → /dev/mapper/crypthome"
        mkfs.ext4 -L "home" -F /dev/mapper/crypthome
    fi
    
    if [[ -n "$PART_SWAP" ]]; then
        info "swap → $PART_SWAP"
        mkswap -L "swap" "$PART_SWAP"
        swapon "$PART_SWAP"
    fi
else
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
fi
log "Formato completo."

# ── Montaje ────────────────────────────────────────────────────────────────────
if [[ "${LUKS:-n}" == "s" ]]; then
    mount /dev/mapper/cryptroot /mnt
    if [[ -n "$PART_HOME" ]]; then
        mkdir -p /mnt/home
        mount /dev/mapper/crypthome /mnt/home
    fi
else
    mount "$PART_ROOT" /mnt
    if [[ -n "$PART_HOME" ]]; then
        mkdir -p /mnt/home
        mount "$PART_HOME" /mnt/home
    fi
fi
if $UEFI; then
    if [[ "$BOOTLOADER" == "systemd-boot" ]]; then
        ESP_DIR="/boot"
    else
        ESP_DIR="/boot/efi"
    fi
    mkdir -p "/mnt${ESP_DIR}"
    # umask=0077 previene la advertencia de 'world accessible' en systemd-boot
    mount -o umask=0077 "$PART_EFI" "/mnt${ESP_DIR}"
else
    ESP_DIR=""
fi

# ── Mirrors ────────────────────────────────────────────────────────────────────
step "·" "Actualizando mirrors"
info "(Ctrl+C para omitir y usar los mirrors actuales)"
_MIRRORS_OK=false
trap '_MIRRORS_OK=interrupted' INT
reflector --verbose --country Spain,France,Germany --age 12 --protocol https \
          --sort rate --save /etc/pacman.d/mirrorlist && _MIRRORS_OK=true || true
trap - INT
if [[ "$_MIRRORS_OK" == "true" ]]; then
    log "Mirrors actualizados."
elif [[ "$_MIRRORS_OK" == "interrupted" ]]; then
    echo ""
    warn "Actualización de mirrors cancelada. Usando los mirrors que ya tiene la ISO."
else
    warn "reflector falló. Usando los mirrors que ya tiene la ISO."
fi

# ── Microcode ──────────────────────────────────────────────────────────────────
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
[[ "$CPU_VENDOR" == "GenuineIntel" ]] && MICROCODE="intel-ucode" || MICROCODE="amd-ucode"
info "Microcode detectado: $MICROCODE"

# ── pacstrap ───────────────────────────────────────────────────────────────────
step "·" "Instalando sistema base (esto tarda un poco)"
pacstrap -K /mnt \
    base "$KERNEL" "${KERNEL}-headers" linux-firmware base-devel \
    "$MICROCODE" \
    networkmanager git nvim vim sudo curl wget reflector cryptsetup \
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
ESP_DIR="${ESP_DIR:-}"
PART_ROOT="$PART_ROOT"
PART_HOME="${PART_HOME:-}"
PART_SWAP="${PART_SWAP:-}"
LUKS="${LUKS:-n}"
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
if [[ "$LUKS" == "s" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Bootloader
info "Instalando bootloader: \$BOOTLOADER"
if [[ "\$BOOTLOADER" == "grub" ]]; then
    sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    if [[ "\$LUKS" == "s" ]]; then
        LUKS_UUID=\$(blkid -s UUID -o value "\$PART_ROOT")
        sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
        sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
    fi

    if \$UEFI; then
        grub-install --target=x86_64-efi \
                     --efi-directory=\$ESP_DIR \
                     --bootloader-id=GRUB --recheck
    else
        grub-install --target=i386-pc --recheck "\$DISK"
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
else
    bootctl --esp-path=\$ESP_DIR install
    mkdir -p \${ESP_DIR}/loader/entries
    cat > \${ESP_DIR}/loader/loader.conf <<EOF
default  arch.conf
timeout  3
console-mode max
editor   no
EOF
    if [[ "\$LUKS" == "s" ]]; then
        LUKS_UUID=\$(blkid -s UUID -o value "\$PART_ROOT")
        ROOT_OPT="cryptdevice=UUID=\${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot rw"
    else
        ROOT_UUID=\$(blkid -s PARTUUID -o value "\$PART_ROOT")
        ROOT_OPT="root=PARTUUID=\${ROOT_UUID} rw quiet"
    fi
    cat > \${ESP_DIR}/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-\${KERNEL}
initrd  /\${MICROCODE}.img
initrd  /initramfs-\${KERNEL}.img
options \${ROOT_OPT}
EOF
fi

if [[ "\$LUKS" == "s" ]]; then
    if [[ -n "\$PART_HOME" ]]; then
        HOME_UUID=\$(blkid -s UUID -o value "\$PART_HOME")
        echo "crypthome  UUID=\${HOME_UUID}  none  luks" >> /etc/crypttab
    fi
    if [[ -n "\$PART_SWAP" ]]; then
        SWAP_UUID=\$(blkid -s UUID -o value "\$PART_SWAP")
        echo "swap  UUID=\${SWAP_UUID}  /dev/urandom  swap,cipher=aes-xts-plain64,size=256" >> /etc/crypttab
        sed -i "/UUID=\${SWAP_UUID}/d" /etc/fstab
        echo "/dev/mapper/swap  none  swap  defaults  0  0" >> /etc/fstab
    fi
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
if [[ "${LUKS:-n}" == "s" ]]; then
    cryptsetup close crypthome 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
fi

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