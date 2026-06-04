---
name: "Implementar BTRFS (Testing Loop)"
description: "Receta para crear y probar un entorno de subvolúmenes BTRFS de forma segura usando un dispositivo de bucle (loop device) en lugar de formatear un disco físico."
---

# 🛡️ Implementación y Testeo de BTRFS con Subvolúmenes

Para probar la lógica de BTRFS de `install.sh` sin arriesgar un disco real, podemos simular un disco duro entero en un archivo de 2GB usando `fallocate` y `losetup`.

## 1. Crear el Entorno de Pruebas Virtual

Crea un archivo vacío de 2 GB y móntalo como disco virtual:
```bash
fallocate -l 2G /tmp/test-btrfs.img
sudo losetup -f --show /tmp/test-btrfs.img
```
*(El comando devolverá algo como `/dev/loop0`. Usa ese dispositivo en los siguientes pasos).*

## 2. Formatear y Crear Subvolúmenes

Este es el proceso exacto que usa `install.sh` en la Fase 2:

```bash
LOOP_DEV="/dev/loop0"  # Cambia esto por el tuyo

# 1. Formatear la partición plana
sudo mkfs.btrfs -L "arch" -f "$LOOP_DEV"

# 2. Montarla temporalmente para inyectar subvolúmenes
sudo mkdir -p /mnt/btrfs-test
sudo mount "$LOOP_DEV" /mnt/btrfs-test

# 3. Crear el árbol estilo Ubuntu/Timeshift
sudo btrfs subvolume create /mnt/btrfs-test/@
sudo btrfs subvolume create /mnt/btrfs-test/@home
sudo btrfs subvolume create /mnt/btrfs-test/@pkg
sudo btrfs subvolume create /mnt/btrfs-test/@log
sudo btrfs subvolume create /mnt/btrfs-test/@snapshots

# 4. Desmontar la partición plana
sudo umount /mnt/btrfs-test
```

## 3. Montaje Definitivo con Banderas de Optimización

Montamos `@` como la raíz y los demás en sus carpetas respectivas. Fíjate en los flags mágicos: `noatime,compress=zstd,space_cache=v2,discard=async`.

```bash
# Raíz (/)
sudo mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@ "$LOOP_DEV" /mnt/btrfs-test

# Crear directorios
sudo mkdir -p /mnt/btrfs-test/{home,var/cache/pacman/pkg,var/log,.snapshots}

# Montar resto de hijos
sudo mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@home "$LOOP_DEV" /mnt/btrfs-test/home
sudo mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@pkg "$LOOP_DEV" /mnt/btrfs-test/var/cache/pacman/pkg
sudo mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@log "$LOOP_DEV" /mnt/btrfs-test/var/log
sudo mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@snapshots "$LOOP_DEV" /mnt/btrfs-test/.snapshots
```

## 4. Verificar y Limpiar

Puedes usar `findmnt` para comprobar la compresión y la jerarquía.
```bash
findmnt | grep btrfs-test
```

Una vez finalices el testeo:
```bash
sudo umount -R /mnt/btrfs-test
sudo losetup -d "$LOOP_DEV"
rm /tmp/test-btrfs.img
rmdir /mnt/btrfs-test
```
