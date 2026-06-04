# 🛠️ Habilidad: Implementación y Testeo de Cifrado LUKS

Esta habilidad reúne todas las **recetas de comandos** necesarias para implementar, verificar y depurar el cifrado de disco completo con LUKS dentro del instalador de Arch Linux, utilizando dispositivos loop para pruebas seguras sin riesgo para el hardware real.

> Consulta siempre la especificación técnica en `.agent/specs/cifrado_luks.md` antes de tocar una línea de `install.sh`.

---

## 🧪 Sección 1: Entorno Virtual de Pruebas LUKS (Loop Device)

Combina esta habilidad con `probar_particionado.md` para crear un disco virtual completo sobre el que probar el ciclo completo de cifrado.

### 1.1 Preparar el disco virtual
```bash
# Crear disco virtual de 20 GiB
dd if=/dev/zero of=test_disk.img bs=1M count=20480

# Asociarlo a un dispositivo loop con detección automática de particiones
losetup -fP test_disk.img

# Verificar el dispositivo asignado (usualmente /dev/loop0)
losetup -a
lsblk | grep loop
```

### 1.2 Particionar el disco virtual (UEFI con swap + home)
```bash
wipefs -af /dev/loop0
sgdisk -Z /dev/loop0
sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  /dev/loop0   # EFI
sgdisk -n 2:0:+2G    -t 2:8200 -c 2:"swap" /dev/loop0   # Swap
sgdisk -n 3:0:+8G    -t 3:8300 -c 3:"root" /dev/loop0   # Root
sgdisk -n 4:0:0      -t 4:8300 -c 4:"home" /dev/loop0   # Home
lsblk /dev/loop0
```

---

## 🔐 Sección 2: Ciclo Completo de Cifrado LUKS (Recetas de Comandos)

### 2.1 Formatear un contenedor LUKS2 (para systemd-boot)
```bash
# Pasar contraseña por stdin (seguro: no aparece en `ps` ni en el historial)
echo -n "mi_contraseña_secreta" | cryptsetup luksFormat \
    --batch-mode \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha256 \
    --iter-time 3000 \
    /dev/loop0p3 -
```

### 2.2 Formatear un contenedor LUKS1 (para GRUB — máxima compatibilidad)
```bash
echo -n "mi_contraseña_secreta" | cryptsetup luksFormat \
    --batch-mode \
    --type luks1 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha256 \
    --iter-time 3000 \
    /dev/loop0p3 -
```
> ⚠️ GRUB no soporta LUKS2 con Argon2id de fábrica. Usar LUKS1 si el bootloader es GRUB.

### 2.3 Abrir el contenedor (crear dispositivo mapeado)
```bash
# Abre el contenedor y lo presenta como /dev/mapper/cryptroot
echo -n "mi_contraseña_secreta" | cryptsetup open /dev/loop0p3 cryptroot -

# Verificar que el mapeador existe
ls -la /dev/mapper/cryptroot
lsblk /dev/loop0
```

### 2.4 Formatear y montar el sistema de archivos DENTRO del contenedor
```bash
# Siempre sobre /dev/mapper/..., NUNCA sobre la partición física
mkfs.ext4 -L "root" -F /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
```

### 2.5 Lo mismo para /home (si existe partición separada)
```bash
echo -n "mi_contraseña_secreta" | cryptsetup luksFormat \
    --batch-mode --type luks2 --cipher aes-xts-plain64 \
    --key-size 512 --hash sha256 --iter-time 3000 \
    /dev/loop0p4 -
echo -n "mi_contraseña_secreta" | cryptsetup open /dev/loop0p4 crypthome -
mkfs.ext4 -L "home" -F /dev/mapper/crypthome
mkdir -p /mnt/home
mount /dev/mapper/crypthome /mnt/home
```

---

## 🔍 Sección 3: Inspección y Depuración de Contenedores LUKS

### 3.1 Ver metadatos de un contenedor (tipo, UUID, algoritmo)
```bash
# Muestra cabecera LUKS completa: tipo (luks1/luks2), UUID, cipher, etc.
cryptsetup luksDump /dev/loop0p3
```

### 3.2 Obtener el UUID del contenedor LUKS (para cryptdevice= del kernel)
```bash
# UUID del contenedor LUKS (no del filesystem interno)
blkid -s UUID -o value /dev/loop0p3

# UUID del filesystem interno (ext4 dentro del mapper)
blkid -s UUID -o value /dev/mapper/cryptroot

# Ver ambos a la vez con contexto
blkid /dev/loop0p3 /dev/mapper/cryptroot
```
> ⚠️ El bootloader necesita el UUID del **contenedor LUKS** (`/dev/loop0p3`), no el del filesystem interno.

### 3.3 Verificar el estado de los mapeadores abiertos
```bash
# Lista todos los dispositivos dm-crypt activos en el sistema
dmsetup ls --target crypt

# Alternativa con más detalle
cryptsetup status cryptroot
cryptsetup status crypthome
```

### 3.4 Comprobar la estructura de bloques completa
```bash
# Vista jerárquica perfecta para verificar la cadena: disco → luks → mapper
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT /dev/loop0
```
La salida esperada debe mostrar algo así:
```
NAME          SIZE TYPE  FSTYPE      MOUNTPOINT
loop0          20G loop
├─loop0p1     512M part  vfat
├─loop0p2       2G part  swap
├─loop0p3       8G part  crypto_LUKS
│ └─cryptroot   8G crypt ext4        /mnt
└─loop0p4     9.5G part  crypto_LUKS
  └─crypthome 9.5G crypt ext4        /mnt/home
```

---

## ⚙️ Sección 4: Configuración del Sistema Final (Recetas para el Chroot)

### 4.1 Modificar hooks de mkinitcpio para incluir `encrypt`
```bash
# El hook 'encrypt' DEBE ir ANTES de 'filesystems'
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
    /etc/mkinitcpio.conf

# Verificar el resultado
grep "^HOOKS=" /etc/mkinitcpio.conf

# Regenerar el initramfs
mkinitcpio -P
```

### 4.2 Obtener UUID del contenedor para el bootloader
```bash
# Ejecutar DENTRO del chroot (arch-chroot /mnt)
LUKS_UUID=$(blkid -s UUID -o value /dev/sda3)   # sustituir sda3 por PART_ROOT real
echo "UUID del contenedor LUKS: $LUKS_UUID"
```

### 4.3 Configurar GRUB con soporte LUKS1
```bash
# Añadir parámetros de kernel para descifrado
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" \
    /etc/default/grub

# Habilitar la opción de LUKS en GRUB
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

# Verificar cambios
grep -E "^GRUB_CMDLINE_LINUX|^GRUB_ENABLE_CRYPTODISK" /etc/default/grub

# Regenerar configuración de GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

### 4.4 Configurar systemd-boot con soporte LUKS2
```bash
# La línea 'options' en /boot/efi/loader/entries/arch.conf
# sustituye 'root=PARTUUID=...' por la cadena de descifrado:
LUKS_UUID=$(blkid -s UUID -o value /dev/sda3)
sed -i "s|^options .*|options cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot rw|" \
    /boot/efi/loader/entries/arch.conf

# Verificar
cat /boot/efi/loader/entries/arch.conf
```

### 4.5 Configurar /etc/crypttab (home y swap)
```bash
# Entrada para /home cifrado (se desbloquea al arranque pidiendo contraseña)
HOME_UUID=$(blkid -s UUID -o value /dev/sda4)   # sustituir sda4 por PART_HOME real
echo "crypthome  UUID=${HOME_UUID}  none  luks" >> /etc/crypttab

# Entrada para swap cifrada EFÍMERA (nueva clave aleatoria en cada arranque)
SWAP_UUID=$(blkid -s UUID -o value /dev/sda2)   # sustituir sda2 por PART_SWAP real
echo "swap  UUID=${SWAP_UUID}  /dev/urandom  swap,cipher=aes-xts-plain64,size=256" >> /etc/crypttab

# Actualizar fstab: eliminar swap sin cifrar e insertar la cifrada
sed -i "/UUID=${SWAP_UUID}/d" /etc/fstab
echo "/dev/mapper/swap  none  swap  defaults  0  0" >> /etc/fstab

# Verificar ambos archivos
cat /etc/crypttab
grep swap /etc/fstab
```

---

## 🧹 Sección 5: Limpieza del Entorno de Pruebas LUKS

Una vez finalizadas las pruebas, hay que cerrar los contenedores LUKS ANTES de desasociar el loop:

```bash
# 1. Desmontar todo
umount -R /mnt 2>/dev/null || true
swapoff /dev/loop0p2 2>/dev/null || true

# 2. Cerrar los contenedores LUKS (en orden inverso al montaje)
cryptsetup close crypthome 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

# 3. Verificar que no queda ningún mapper abierto
dmsetup ls --target crypt

# 4. Desasociar el loop
losetup -d /dev/loop0

# 5. Eliminar el archivo de imagen si ya no es necesario
rm -f test_disk.img
```

---

## 🚨 Sección 6: Errores Frecuentes y Soluciones

| Error | Causa probable | Solución |
|---|---|---|
| `Device /dev/mapper/cryptroot is busy` | El FS sigue montado | `umount /mnt` antes de `cryptsetup close` |
| `Failed to open key file` | Contraseña errónea en stdin | Verificar que `echo -n` no añade `\n` (usar `-n`) |
| `cryptsetup: command not found` en chroot | `cryptsetup` no instalado | Añadir `cryptsetup` al comando `pacstrap` |
| `Kernel panic: cryptdevice not found` | UUID incorrecto en bootloader | Usar `blkid -s UUID` (no PARTUUID) sobre la partición física |
| `WARNING: Possible missing firmware` en mkinitcpio | Firmware no crítico | Ignorable; no afecta al funcionamiento del cifrado |
| GRUB no pide contraseña al arrancar | `GRUB_ENABLE_CRYPTODISK=y` no activado | Verificar `/etc/default/grub` y regenerar con `grub-mkconfig` |
| `/home` no se monta al arrancar | Falta entrada en `/etc/crypttab` | Añadir `crypthome UUID=... none luks` al crypttab |
| `mkfs` falla sobre la partición física | Se intentó formatear sin abrir el contenedor | Siempre formatear sobre `/dev/mapper/...`, nunca sobre la partición física |

---

## 💡 Consejos para el Agente

* **Orden de cierre importa:** Siempre cerrar `crypthome` antes que `cryptroot` si `/home` está sobre LUKS.
* **`--batch-mode` es obligatorio** en scripting no interactivo para que `cryptsetup luksFormat` no pida confirmación de teclado y no falle con `set -e`.
* **Nunca loguear `LUKS_PASS`:** La contraseña de cifrado jamás debe aparecer en ningún `log()`, `info()` ni en el historial del shell. Pasarla siempre vía `echo -n "$LUKS_PASS" | cryptsetup ... -`.
* **UUID vs PARTUUID:** El parámetro `cryptdevice=` del kernel requiere `UUID=` (del filesystem LUKS), NO `PARTUUID=`. systemd-boot sin LUKS puede usar PARTUUID; con LUKS siempre UUID.
* **Probar regresión:** Cada cambio a la Fase 2 de `install.sh` debe probarse también con `LUKS=false` para garantizar que no se rompe el flujo de instalación sin cifrado.
