# 📝 Espec: Esquema de Particionado Personalizado (Separar `/home`)

Esta especificación detalla la implementación de una partición separada para `/home` en el instalador de Arch Linux. Esto permite a los usuarios mantener sus datos y configuraciones personales independientes del sistema operativo base, facilitando futuras actualizaciones o reinstalaciones.

---

## 🎯 Requisitos y UX (Fase 1: Preguntas)

Actualmente, el script pregunta por el disco destino y el tamaño de la swap, asignando automáticamente el resto del disco a la partición Root (`/`).

Para implementar `/home` separado, añadiremos las siguientes preguntas en la Fase 1:
1. **¿Separar `/home`?**
   * Pregunta: `¿Crear una partición separada para /home?` (Sí/No, por defecto `n`).
2. **Tamaño de Root (`/`):**
   * Si responde "sí", se le solicitará el tamaño deseado para la partición Root `/` (por defecto `40G`).
   * *Razón de diseño:* Es mucho más fácil y a prueba de fallos pedir el tamaño del sistema operativo base (que suele ser predecible, entre 30GB y 50GB) y asignar automáticamente **todo el espacio restante** del disco a `/home`.

---

## 🛠️ Lógica de Particionado (Fase 2: Preparación del Disco)

Dependiendo del modo de arranque detectado (UEFI o BIOS), los comandos de particionado cambiarán dinámicamente si el usuario decide separar `/home`.

### A. Escenario UEFI (`sgdisk`)
Calculamos los números de las particiones físicas secuencialmente según la selección del usuario.

#### Con Swap y Con `/home` separado:
* Partición 1: EFI (512 MiB, tipo `ef00`)
* Partición 2: Swap (tamaño personalizado, tipo `8200`)
* Partición 3: Root `/` (tamaño personalizado, tipo `8300`)
* Partición 4: Home `/home` (todo el resto del disco `0`, tipo `8300`)

```bash
sgdisk -n 1:0:+512M          -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:+"$SWAP_SIZE"  -t 2:8200 -c 2:"swap" "$DISK"
sgdisk -n 3:0:+"$ROOT_SIZE"  -t 3:8300 -c 3:"root" "$DISK"
sgdisk -n 4:0:0              -t 4:8300 -c 4:"home" "$DISK"
```

#### Sin Swap y Con `/home` separado:
* Partición 1: EFI (512 MiB, tipo `ef00`)
* Partición 2: Root `/` (tamaño personalizado, tipo `8300`)
* Partición 3: Home `/home` (todo el resto del disco `0`, tipo `8300`)

```bash
sgdisk -n 1:0:+512M          -t 1:ef00 -c 1:"EFI"  "$DISK"
sgdisk -n 2:0:+"$ROOT_SIZE"  -t 2:8300 -c 2:"root" "$DISK"
sgdisk -n 3:0:0              -t 3:8300 -c 3:"home" "$DISK"
```

---

### B. Escenario BIOS/Legacy (`parted`)
Utilizamos matemática simple para calcular los límites de cilindros en megabytes.

#### Con Swap y Con `/home` separado:
```bash
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary 1MiB 3MiB # Spacer de arranque

# 1. Swap
swap_mb=$(convertir_a_mb "$SWAP_SIZE")
parted -s "$DISK" mkpart primary linux-swap 3MiB "$((3 + swap_mb))MiB"

# 2. Root
root_mb=$(convertir_a_mb "$ROOT_SIZE")
parted -s "$DISK" mkpart primary ext4 "$((3 + swap_mb))MiB" "$((3 + swap_mb + root_mb))MiB"

# 3. Home
parted -s "$DISK" mkpart primary ext4 "$((3 + swap_mb + root_mb))MiB" 100%
```

---

## 💾 Formateo y Flujo de Montaje

1. **Formateo de `/home`:**
   * Tras formatear la raíz en `ext4`, formateamos la nueva partición Home:
     ```bash
     info "ext4 → $PART_HOME"
     mkfs.ext4 -L "home" -F "$PART_HOME"
     ```

2. **Secuencia de Montaje (¡Orden Crítico!):**
   * El montaje debe ser jerárquico. Primero se monta la raíz, luego se crean los puntos de montaje internos y finalmente se montan las demás particiones:
     ```bash
     # 1. Montar raíz
     mount "$PART_ROOT" /mnt

     # 2. Crear directorios internos
     mkdir -p /mnt/home
     if $UEFI; then mkdir -p /mnt/boot/efi; fi

     # 3. Montar subparticiones
     mount "$PART_HOME" /mnt/home
     if $UEFI; then mount "$PART_EFI" /mnt/boot/efi; fi
     ```

3. **Persistencia (FSTAB):**
   * El comando actual `genfstab -U /mnt >> /mnt/etc/fstab` es completamente recursivo y detectará `/mnt/home` de forma nativa, añadiéndolo con su UUID al archivo `fstab` definitivo sin necesidad de cambios adicionales. ¡Fabuloso!

---

## 🧪 Plan de Verificación

* **Pruebas Unitarias Visuales:** Asegurar que el resumen de instalación muestra correctamente si `/home` está activo y su partición asignada.
* **Prueba de Particionado Virtual:** Utilizar la habilidad de particionado virtual con dispositivos `loop` para certificar que la tabla de particiones generada es válida y no genera solapamientos.
