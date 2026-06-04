# Especificación Técnica: Soporte de BTRFS y Subvolúmenes

## 1. Visión General
El objetivo es permitir a los usuarios elegir entre el tradicional `ext4` y el avanzado `btrfs` como sistema de archivos principal durante el proceso de instalación interactivo. Si se elige BTRFS, el instalador configurará automáticamente el esquema óptimo de subvolúmenes compatible con herramientas de instantáneas como Timeshift.

## 2. Máquina de Estados (Fase 1)
Se introducirá una nueva pregunta en la Máquina de Estados:
- **Paso:** Elección de Sistema de Archivos (`ext4` o `btrfs`).
- **Comportamiento:** Si el usuario elige BTRFS, la gestión de `/home` pasará a ser lógica (por subvolumen) en lugar de física.

## 3. Esquema de Subvolúmenes Recomendado (Estilo Ubuntu/Timeshift)
Para maximizar la compatibilidad con Timeshift y la integridad de datos tras restaurar un snapshot, se crearán los siguientes subvolúmenes dentro de la partición raíz:
* `@` montado en `/` (Raíz del sistema operativo)
* `@home` montado en `/home` (Archivos de usuario)
* `@pkg` montado en `/var/cache/pacman/pkg` (Caché de paquetes pacman; evita que un downgrade al restaurar un snapshot borre la caché descargada)
* `@log` montado en `/var/log` (Registros del sistema; evita que restaurar un snapshot elimine los logs que podrían explicar un crasheo)
* `@snapshots` montado en `/.snapshots` (Punto de montaje reservado para instantáneas futuras)

## 4. Opciones de Montaje Optimizadas
Se utilizarán banderas de montaje modernas para maximizar el rendimiento y la vida útil de los SSDs:
* `noatime`: Evita escrituras en disco cada vez que se lee un archivo.
* `compress=zstd`: Compresión transparente ultrarrápida (ahorra espacio y acelera las lecturas).
* `space_cache=v2`: Gestión de espacio libre optimizada.
* `discard=async`: Soporte TRIM en segundo plano para evitar degradación de rendimiento.

## 5. Implementación en Fase 2 (Formateo y Montaje)
El flujo para BTRFS será:
1. **Formateo:** `mkfs.btrfs -L "arch" -f /dev/sdxY` (o en `/dev/mapper/cryptroot` si LUKS está activo).
2. **Montaje Temporal:** Montar el volumen plano en `/mnt`.
3. **Creación de Subvolúmenes:** Ejecutar `btrfs subvolume create /mnt/@`, `@home`, `@pkg`, `@log`, `@snapshots`.
4. **Desmontaje:** Desmontar el volumen plano (`umount /mnt`).
5. **Montaje Definitivo:** Montar `@` en `/mnt` usando los *mount flags* optimizados.
6. **Estructura de Directorios:** Crear los puntos de montaje base `mkdir -p /mnt/{home,var/cache/pacman/pkg,var/log,.snapshots}`.
7. **Montaje de Subvolúmenes:** Montar el resto de subvolúmenes en sus respectivos directorios con las mismas banderas.

## 6. Dependencias Adicionales
Se añadirá de forma dinámica el paquete `btrfs-progs` a la orden de `pacstrap` si el usuario ha escogido btrfs, necesario para interactuar con el sistema de archivos desde la instalación final.

## 7. Compatibilidad con Cifrado LUKS
La implementación debe ser agnóstica a LUKS. Si el usuario seleccionó cifrado, BTRFS se instalará sin problemas dentro de `/dev/mapper/cryptroot`. La abstracción actual del script permite que esto funcione de inmediato sin código extra.
