# 🛠️ Habilidad: Testeo Seguro de Particionado (Loop Devices)

Esta habilidad enseña cómo crear y utilizar un disco virtual (dispositivo loop) en Linux para simular, testear y depurar de forma 100% segura las rutinas de particionado, formateo y montaje de `install.sh` sin riesgo de alterar los discos reales del sistema anfitrión.

---

## 💻 Concepto Teórico: Dispositivo Loop
Un **dispositivo loop** es un módulo del kernel de Linux que permite montar un archivo regular como si fuera un dispositivo de bloque (un disco duro físico). Esto nos permite realizar operaciones como `wipefs`, `sgdisk`, `parted`, `mkfs.ext4` y `mount` directamente sobre un archivo `.img`.

---

## 🛠️ Paso a Paso: Creación del Entorno Virtual de Pruebas

Para simular un disco duro de 20GB, ejecuta los siguientes comandos en una terminal con permisos de superusuario:

### 1. Crear un Archivo Vacío (Reserva de Espacio)
Creamos un archivo lleno de ceros que actuará como nuestro "disco duro físico virtual":
```bash
# dd if=/dev/zero of=test_disk.img bs=1M count=20480
```
*(Esto creará un archivo de 20 GiB llamado `test_disk.img` en el directorio actual).*

### 2. Asociar el Archivo a un Dispositivo Loop
Buscamos el primer dispositivo loop libre y le asociamos nuestro archivo virtual, pidiéndole al kernel que escanee las particiones internas automáticamente (`-P`):
```bash
# losetup -fP test_disk.img
```

### 3. Verificar el Dispositivo Loop Asignado
Para saber cuál dispositivo loop nos asignó el sistema (generalmente `/dev/loop0`, `/dev/loop1`, etc.):
```bash
# losetup -a
```
También puedes verlo con `lsblk`:
```bash
# lsblk | grep loop
```

---

## 🧪 Ejecución de Pruebas de Particionado

Una vez tengas tu dispositivo loop (supongamos que es `/dev/loop0`), puedes correr comandos de particionado simulados de forma idéntica a un disco físico:

### A. Simular Limpieza y Particionado UEFI con `sgdisk`
```bash
# 1. Limpieza
wipefs -af /dev/loop0
sgdisk -Z /dev/loop0

# 2. Creación de particiones (EFI + Swap + Root + Home)
sgdisk -n 1:0:+512M          -t 1:ef00 -c 1:"EFI"  /dev/loop0
sgdisk -n 2:0:+4G            -t 2:8200 -c 2:"swap" /dev/loop0
sgdisk -n 3:0:+8G            -t 3:8300 -c 3:"root" /dev/loop0
sgdisk -n 4:0:0              -t 4:8300 -c 4:"home" /dev/loop0
```

### B. Verificar la Tabla de Particiones Generada
Una vez creadas, el parámetro `-P` de `losetup` hará que aparezcan como `/dev/loop0p1`, `/dev/loop0p2`, `/dev/loop0p3` y `/dev/loop0p4`.
Compruébalo con:
```bash
# parted /dev/loop0 print
# lsblk /dev/loop0
```

---

## 🧹 Limpieza y Desmontaje del Entorno de Pruebas

Una vez terminadas tus pruebas, debes limpiar el sistema de la siguiente manera:

1. **Desmontar particiones activas** (si llegaste a montarlas):
   ```bash
   # umount -R /mnt 2>/dev/null || true
   # swapoff /dev/loop0p2 2>/dev/null || true
   ```
2. **Desasociar el dispositivo loop del kernel:**
   ```bash
   # losetup -d /dev/loop0
   ```
3. **Eliminar el archivo virtual si ya no lo necesitas:**
   ```bash
   # rm -f test_disk.img
   ```

---

## 💡 Consejos para la IA/Agente
* Utiliza esta habilidad para validar que la matemática de los cilindros y sectores de `sgdisk` o `parted` no genere errores del tipo "Partition overlaps" o "Sector out of range" al realizar modificaciones a la rutina del script.
