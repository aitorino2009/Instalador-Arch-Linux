# arch-installer 🏹

Esto es un instalador automático de Arch Linux. Sin GUI, sin instaladores, sin ventanitas molestas.  
Arranca la ISO, clona este repositorio y en **5–10 minutos** tienes tu Arch limpio.

---

## Uso

```bash
# 1. Arranca la ISO de Arch Linux y conéctate a internet
iwctl station wlan0 connect "TuRed"   # Si vas por WiFi

# 2. Clona el repo
pacman -Sy --noconfirm git
git clone https://github.com/TUUSUARIO/arch-installer
cd arch-installer

# 3. Edita la configuración
nano config.sh   # Cambia al menos: DISK, HOSTNAME, USERNAME, contraseñas

# 4. Instala
bash install.sh
```

> Escribe `si` cuando te lo pida y siéntate a ver cómo se instala solo.

---

## Estructura

```
arch-installer/
├── install.sh     # Script principal — no tocar salvo que sepas lo que haces
├── chroot.sh      # Configuración dentro del chroot — idem
├── config.sh      # ← AQUÍ editas todo lo tuyo
└── README.md
```

---

## config.sh — opciones principales

| Variable        | Descripción                        | Ejemplo                    |
| --------------- | ---------------------------------- | -------------------------- |
| `DISK`          | Disco destino                      | `/dev/sda`, `/dev/nvme0n1` |
| `SWAP_SIZE`     | Tamaño swap (`0` = sin swap)       | `8G`, `4G`                 |
| `HOSTNAME`      | Nombre del equipo                  | `archbox`                  |
| `TIMEZONE`      | Zona horaria                       | `Europe/Madrid`            |
| `LOCALE`        | Locale principal                   | `es_ES.UTF-8`              |
| `KEYMAP`        | Mapa de teclado                    | `es`                       |
| `USERNAME`      | Tu usuario                         | `maria`                    |
| `ROOT_PASSWORD` | Contraseña root                    | `changeme`                 |
| `USER_PASSWORD` | Contraseña usuario                 | `changeme`                 |
| `BASE_PACKAGES` | Paquetes extra en pacstrap         | Array bash                 |
| `BOOTLOADER`    | `grub` o `systemd-boot`            | `grub`                     |
| `KERNEL`        | `linux`, `linux-lts`, `linux-zen`… | `linux`                    |
| `MICROCODE`     | `auto`, `intel-ucode`, `amd-ucode` | `auto`                     |
| `AUR_HELPER`    | `paru`, `yay` o vacío              | `paru`                     |
| `DOTFILES_REPO` | URL de tu repo de dotfiles         | `https://github.com/...`   |

---

## Qué hace el instalador

1. **Particiona** el disco (GPT+EFI en UEFI, MBR en BIOS) con EFI / swap / root
2. **Formatea** ext4 el root y FAT32 el EFI
3. **Actualiza espejos** con reflector (España, Francia, Alemania)
4. **pacstrap** — instala el sistema base + tus paquetes
5. **Chroot** — zona horaria, locale, hostname, hosts, red
6. **Usuarios** — root y tu usuario con grupos y sudo
7. **Bootloader** — GRUB o systemd-boot automáticamente según UEFI/BIOS
8. **AUR helper** — paru o yay compilado como tu usuario
9. **Dotfiles** — clona tu repo y ejecuta tu script de instalación

---

## Requisitos

- Conexión a internet en la ISO
- Boot en modo correcto (UEFI o BIOS), se detecta automáticamente
- El disco destino debe ser el correcto (hace wipefs al inicio)

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

## Post-instalación sugerida

Tras reiniciar, con tu usuario:

```bash
# Entorno gráfico (ej. Hyprland)
paru -S hyprland waybar wofi alacritty

# Fonts
paru -S ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

# Pipewire (audio)
sudo pacman -S pipewire pipewire-pulse wireplumber
```

---

## Notas

- Las contraseñas en `config.sh` solo se usan durante la instalación con `chpasswd` y no quedan en el sistema final.
- Si algo falla en el AUR helper o en los dotfiles, el script avisa pero **no aborta**. el sistema base siempre queda instalado.
