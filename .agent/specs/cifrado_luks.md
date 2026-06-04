# 📝 Espec: Cifrado de Disco Completo con LUKS

Esta especificación detalla la implementación del cifrado de disco completo (**Full Disk Encryption**, FDE) mediante **LUKS2** en el instalador interactivo de Arch Linux. El objetivo es que cualquier usuario, desde el novato que teclea por primera vez hasta el paranoico de las APT que ya usa Arch por amor al arte, pueda cifrar su disco con una sola pregunta durante la instalación.

---

## 🎯 Alcance y Decisiones de Diseño

### ¿Qué se cifra?
Se implementará cifrado de la **partición raíz (`/`)** y, si existe, la partición **`/home` separada**. La partición EFI (ESP) **no se cifra** (es técnicamente imposible; los bootloaders UEFI necesitan acceder a ella antes de que exista ningún contexto de descifrado). La swap, si existe como partición dedicada, **sí se cifrará**.

### Estándar elegido: LUKS2
Se usará **LUKS2** (no LUKS1) por sus ventajas críticas:
- **Cabecera duplicada:** Resistencia ante corrupción del primer sector del disco.
- **Argon2id:** Derivación de clave moderna, resistente a ataques de fuerza bruta con GPU.
- **Compatible con `systemd-cryptsetup`** para futuros flujos de desbloqueo automático vía TPM o fichero de clave.

> **⚠️ Excepción conocida — GRUB y LUKS2 con Argon2id:**
> GRUB tiene soporte **experimental e incompleto** de LUKS2. Concretamente, su módulo `grub-luks2` **no soporta Argon2id** de fábrica (requiere compilar GRUB con soporte de gcrypt especial). Para evitar bloquear a usuarios con GRUB, se usará la siguiente estrategia:
>
> - **Si el usuario elige `systemd-boot`:** LUKS2 con Argon2id. Sin restricciones.
> - **Si el usuario elige `GRUB`:** Se forzará **LUKS1** (con PBKDF2, compatible 100% con GRUB) y se advertirá al usuario de esta limitación.

### Algoritmo de cifrado
- Algoritmo: **AES-XTS-PLAIN64**, con clave de **512 bits** (efectiva de 256 bits para XTS).
- Comando de apertura: `cryptsetup luksFormat` con los parámetros adecuados según LUKS1/LUKS2.

---

## 🗣️ UX — Fase 1: Preguntas (Nueva Pregunta)

Se añadirá una sola pregunta en la Fase 1, justo **después de la selección del disco y tamaño de swap**, pero **antes de la selección del bootloader**:

```
¿Cifrar el disco con LUKS? [s/N]:
```

- Si el usuario responde **`n`** (por defecto): el flujo es idéntico al actual. **Cero cambios.**
- Si el usuario responde **`s`**:
  1. Se solicita la **contraseña de cifrado** dos veces (con `ask_pass`) para verificación.
  2. Se muestra un **aviso explícito** en color amarillo (`warn`) recordando al usuario que si olvida la contraseña, **los datos son irrecuperables**. Se le pide confirmación escribiendo `"si"` para continuar (igual al resumen de borrado de disco).
  3. Si el usuario tiene seleccionado **GRUB** como bootloader, se muestra un aviso adicional indicando que se usará LUKS1 por compatibilidad.

Variables nuevas que se almacenarán:
```bash
LUKS=false          # true si el usuario activa el cifrado
LUKS_PASS=""        # Contraseña de cifrado (no se loguea nunca)
```

---

## 🛠️ Lógica de Cifrado — Fase 2: Preparación del Disco

El cifrado LUKS se aplica **después del particionado físico** (sgdisk/parted) y **antes del formateo** del sistema de archivos. El orden de operaciones es:

```
Particionar disco → Cifrar partición(es) → Abrir contenedor(es) → Formatear en /dev/mapper/... → Montar
```

### A. Partición Root (`/`)

**1. Formatear el contenedor LUKS:**
```bash
# LUKS2 (para systemd-boot)
echo -n "$LUKS_PASS" | cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha256 \
    --iter-time 3000 \
    "$PART_ROOT" -

# LUKS1 (para GRUB — compatibilidad garantizada)
echo -n "$LUKS_PASS" | cryptsetup luksFormat \
    --type luks1 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha256 \
    --iter-time 3000 \
    "$PART_ROOT" -
```
> *Usamos `echo -n ... | cryptsetup ... -` para pasar la contraseña por stdin sin que aparezca en la historia del shell ni en `ps`. El `-` al final indica stdin como fuente de clave.*

**2. Abrir el contenedor:**
```bash
echo -n "$LUKS_PASS" | cryptsetup open "$PART_ROOT" cryptroot -
```
Esto crea el dispositivo virtual `/dev/mapper/cryptroot`.

**3. Formatear el sistema de archivos sobre el mapeador:**
```bash
mkfs.ext4 -L "root" -F /dev/mapper/cryptroot
```

**4. Montar el mapeador (no la partición física):**
```bash
mount /dev/mapper/cryptroot /mnt
```

---

### B. Partición Home (`/home`) — Si existe

Si el usuario ha separado `/home` (combinación con la spec `particionado_personalizado`), también se cifra:

```bash
echo -n "$LUKS_PASS" | cryptsetup luksFormat --type luks2 "$PART_HOME" -
echo -n "$LUKS_PASS" | cryptsetup open "$PART_HOME" crypthome -
mkfs.ext4 -L "home" -F /dev/mapper/crypthome
mount /dev/mapper/crypthome /mnt/home
```

---

### C. Partición Swap — Si existe

La swap cifrada **no requiere LUKS completo** (no necesita persistir entre reinicios). Se configura en el sistema final usando swap cifrada efímera vía `/etc/crypttab`:

```
# Entrada en /etc/crypttab (generada en el chroot)
swap  <UUID_PART_SWAP>  /dev/urandom  swap,cipher=aes-xts-plain64,size=256
```
Y en `/etc/fstab`:
```
/dev/mapper/swap  none  swap  defaults  0  0
```

---

## ⚙️ Configuración del Chroot — Fase 4

Dentro del script `_chroot.sh` generado dinámicamente, se deben inyectar las siguientes configuraciones si `LUKS=true`:

### 1. Hooks de `mkinitcpio.conf`
Se añade el hook `encrypt` (o `sd-encrypt` si se usa `systemd-boot` con systemd en initramfs) **antes** del hook `filesystems`:

```bash
# Reemplazar la línea de HOOKS en /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
    /etc/mkinitcpio.conf

# Regenerar el initramfs
mkinitcpio -P
```

> ⚠️ Si se usa `sd-encrypt` (variante systemd), la sintaxis de los parámetros de kernel es diferente. Para simplificar y maximizar compatibilidad, se usará el hook clásico `encrypt` en esta primera implementación.

### 2. Parámetros del Kernel (Bootloader)

El bootloader necesita saber **dónde está el contenedor LUKS** para pedirle la contraseña al arrancar. Se pasa el UUID de la partición Root física (¡no del mapeador!) como parámetro del kernel.

**Obtención del UUID (en el chroot):**
```bash
LUKS_UUID=$(blkid -s UUID -o value "$PART_ROOT")
```

#### Para GRUB (`/etc/default/grub`):
```bash
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot\"|" \
    /etc/default/grub

# Habilitar soporte LUKS en GRUB
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub

# Regenerar GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

#### Para `systemd-boot` (`/boot/efi/loader/entries/arch.conf`):
```bash
# La línea 'options' del archivo de entrada de systemd-boot debe incluir:
# options cryptdevice=UUID=<UUID>:cryptroot root=/dev/mapper/cryptroot rw
sed -i "s|^options .*|options cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot rw|" \
    /boot/efi/loader/entries/arch.conf
```

### 3. `/etc/crypttab` (Para automontaje de Home cifrado)

Si `/home` está en un contenedor LUKS separado, se añade una entrada en `/etc/crypttab` para que el sistema pida la contraseña al arrancar:

```bash
HOME_UUID=$(blkid -s UUID -o value "$PART_HOME")
echo "crypthome  UUID=${HOME_UUID}  none  luks" >> /etc/crypttab
```
> **Nota de UX:** Si home y root comparten la misma contraseña, se puede usar un **fichero de clave** (`keyfile`) para que `/home` se desbloquee automáticamente tras introducir la contraseña de root. Esta optimización queda fuera del alcance de esta spec y se documentará en una iteración futura.

---

## 🔀 Integración con la Máquina de Estados (Fase 1)

La nueva pregunta de LUKS se insertará como un paso nuevo en el `case "$PASO" in` de la Fase 1. El estado propuesto es `"luks"`, que se sitúa lógicamente entre `"swap"` y `"hostname"` en el flujo:

```
disco → swap → luks (NUEVO) → home → root_size → hostname → ...
```

El historial de navegación hacia atrás (`HISTORIAL=()`) ya gestiona este flujo de forma nativa, por lo que no es necesario modificar la lógica de retroceso.

---

## 💾 Resumen de Variables del Script

| Variable     | Tipo    | Descripción                                          |
|--------------|---------|------------------------------------------------------|
| `LUKS`       | boolean | `true` si el usuario activa el cifrado LUKS.         |
| `LUKS_PASS`  | string  | Contraseña de cifrado. Nunca se loguea ni persiste.  |
| `LUKS_UUID`  | string  | UUID de la partición root física (calculado en chroot). |
| `HOME_UUID`  | string  | UUID de la partición home física (si aplica).        |

---

## 🧩 Compatibilidad con Otras Features

| Combinación                          | Estado   | Notas                                                                 |
|--------------------------------------|----------|-----------------------------------------------------------------------|
| LUKS + UEFI + systemd-boot           | ✅ Plena  | Ruta recomendada. LUKS2 + Argon2id.                                   |
| LUKS + UEFI + GRUB                   | ✅ Plena  | Usa LUKS1 con aviso al usuario.                                       |
| LUKS + BIOS/Legacy + GRUB            | ✅ Plena  | Usa LUKS1. `sgdisk` se sustituye por `parted`. Ruta legacy completa.  |
| LUKS + `/home` separado              | ✅ Plena  | Ambas particiones se cifran de forma independiente.                   |
| LUKS + BTRFS (futura)                | 🔲 Pendiente | Requerirá spec propia por la complejidad de los subvolúmenes.       |

---

## 🧪 Plan de Verificación

- **Prueba 1 — Sin cifrado:** Ejecutar el instalador con `LUKS=false` y verificar que el flujo es 100% idéntico al actual (regresión cero).
- **Prueba 2 — Máquina Virtual con UEFI + systemd-boot:** Instalar con cifrado activo en una VM UEFI. Verificar que el sistema pide la contraseña en el arranque y monta correctamente.
- **Prueba 3 — Máquina Virtual con BIOS + GRUB:** Instalar con cifrado LUKS1 en una VM BIOS legacy. Verificar el arranque con petición de passphrase.
- **Prueba 4 — `/home` cifrado separado:** Verificar que ambos contenedores se abren al arranque y que `lsblk` muestra la estructura correcta: `sda3 → luks → cryptroot` y `sda4 → luks → crypthome`.
- **Prueba 5 — Contraseña incorrecta:** Simular contraseña errónea en el arranque y verificar que el sistema ofrece reintentos y no corrompe datos.
