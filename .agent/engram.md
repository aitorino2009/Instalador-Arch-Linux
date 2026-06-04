# 🧠 .agent/engram.md — Memoria del Agente (Engram)

Este archivo almacena la memoria persistente del Agente para asegurar la coherencia del desarrollo a lo largo de las múltiples sesiones de trabajo. **No debe ser borrado ni alterado de forma destructiva.**

---

## 🚨 Reglas Críticas e Innegociables
Estas reglas han sido indicadas por el usuario y son de obligado cumplimiento bajo cualquier circunstancia:

1. **Protocolo de Inicio de Sesión:** Al iniciar cualquier tarea o sesión, el agente debe:
   * Leer **SIEMPRE** el archivo `agent.md` en la raíz.
   * Sigue estrictamente los protocolos de Memoria (Engram) y Skills definidos allí.
   * Respetar e integrar las especificaciones técnicas guardadas en `.agent/specs/`.
2. **Localización y Estilo:** Hablar siempre en **castellano** y mantener el estilo técnico, ameno, riguroso y divertido.
3. **Seguridad y Confirmación:** Al tratarse de un script que altera particiones de discos y formatea sistemas de archivos, cualquier modificación sobre la lógica de escritura en disco debe ser analizada minuciosamente y requerirá confirmación explícita antes de cualquier test destructivo.
4. **Resiliencia Base:** El sistema base debe quedar 100% intacto y funcional aunque los módulos extras (como AUR helper o dotfiles) fallen. El script debe reportar el error pero continuar sin colapsar.
5. **Nombrado de Archivos en Castellano:** Cualquier archivo nuevo creado en el repositorio (especificaciones, habilidades, planes, etc.) debe tener obligatoriamente su nombre de archivo escrito en castellano (ej. `particionado_personalizado.md` en lugar de `custom_partitioning.md`).

---

## 💡 Aprendizajes Recientes del Proyecto
* **Mecánica del Chroot Jail:** La instalación de Arch Linux se realiza mediante el comando `pacstrap`. Para configurar el entorno final (como contraseñas, usuarios, idioma, etc.), el script principal escribe dinámicamente un archivo secundario temporal en `/mnt/root/_chroot.sh`, inyectando las variables de la sesión, entra en el entorno mediante `arch-chroot` para ejecutarlo y finalmente lo elimina. Esta arquitectura es sumamente limpia y previene errores de variables del shell padre.
* **Soporte NVMe/eMMC:** La función de ayuda `part()` calcula dinámicamente el sufijo de la partición (ej. `/dev/nvme0n1p1` para NVMe frente a `/dev/sda1` para SATA), lo que evita fallos de montaje catastróficos en discos modernos.
* **Optimización de Mirrors:** El uso de `reflector` filtrando por España, Francia y Alemania al vuelo garantiza velocidades óptimas durante la instalación, y se programa un `reflector.timer` persistente en el sistema final para mantener los mirrors al día de forma automática.
* **Flexibilidad de Arranque:** El script posee lógica adaptativa para arrancar con el tradicional **GRUB** (tanto en modo UEFI como BIOS legacy) y con el moderno **systemd-boot** (solo UEFI), calculando el UUID de la partición Root de forma automática para configurar el cargador.
* **Particionado Personalizado (/home separado):** Implementado en la rama `particionado_personalizado`. El script pregunta si se desea separar `/home` y cuál será el tamaño de la raíz (`/`). El espacio restante va a `/home` automáticamente. La lógica maneja los 4 escenarios posibles (con/sin swap × con/sin `/home`) tanto en UEFI (`sgdisk`) como en BIOS (`parted`).
* **Validación de Espacio Físico (Evitar desbordamientos en sgdisk):** Si el tamaño acumulado de EFI (512MB) + Swap + Raíz supera la capacidad real en GB del disco físico (`lsblk -b -no SIZE`), `sgdisk` o `parted` fallarán. Se solucionó implementando un bucle interactivo de validación en la Fase 1 que calcula la capacidad del disco y sugiere de forma dinámica el tamaño de raíz máximo recomendado si el usuario se excede, impidiéndole continuar hasta que elija un tamaño válido.
* **⚠️ REGLA CRÍTICA — Orden de funciones en Bash:** En Bash, una función DEBE estar definida ANTES de ser llamada. Si se añade una función auxiliar (ej. `convertir_a_mb`) a una sección del script que se ejecuta cronológicamente DESPUÉS de donde se llama (ej. `HELPERS INTERNOS` que va después de `FASE 1 — PREGUNTAS`), el script abortará con `command not found`. La solución permanente es añadir helpers de uso global en el bloque `COLORES Y HELPERS` al inicio del script (líneas ~8-85), garantizando disponibilidad desde el primer instante de ejecución.
* **⚠️ BUG CRÍTICO — Rutas de systemd-boot con ESP en /boot/efi:** Cuando el ESP (partición EFI) se monta en `/boot/efi` (no en `/boot` directamente), los archivos de configuración de `systemd-boot` deben escribirse en `/boot/efi/loader/loader.conf` and `/boot/efi/loader/entries/arch.conf`, NO en `/boot/loader/`. Adicionalmente, `bootctl` debe invocarse con `bootctl --esp-path=/boot/efi install` para ser explícito. Si se usan rutas incorrectas, `bootctl` instala el binario EFI pero los archivos de configuración se pierden y el sistema no arranca, mostrando únicamente el UEFI Boot Manager sin entradas válidas.
* **Sufijo estricto de unidades en tamaño de particiones (Evitar sectores brutos en sgdisk):** Si el usuario ingresa un número puro sin sufijo (ej. `15` en vez de `15G`), herramientas como `sgdisk` lo interpretarán como sectores de disco absolutos (512 bytes), creando particiones minúsculas (ej. ~7.5 KiB) que causarán fallos catastróficos al formatear como swap (`mkswap`) o ext4. Se solucionó con la función `validar_tamano` que obliga a ingresar unidades `G` o `M` y asiste interactivamente al usuario si introduce un formato incorrecto.
* **Máquina de Estados para Fase 1 (Navegación Hacia Atrás):** Para permitir al usuario volver a preguntas anteriores si se equivoca, la Fase 1 dejó de ser una ejecución secuencial lineal y se refactorizó en un bucle `while true` + `case "$PASO" in` (Máquina de Estados). Las funciones `ask` devuelven el código 99 si el usuario escribe `<`. El script mantiene un array `HISTORIAL=()` que actúa como pila (stack) registrando la ruta exacta de pasos visitados, permitiendo que al retroceder se ignoren correctamente las ramas condicionales no visitadas (ej. saltar el tamaño de la Swap si se había desactivado).
* **⚠️ BUG — Default sucio en preguntas de tamaño tras validación fallida:** Cuando `SWAP_SIZE` o `ROOT_SIZE` reciben un valor inválido (ej. `40G` demasiado grande), el valor incorrecto quedaba almacenado en la variable y al reintentar la pregunta se mostraba como `[40G]`. La solución es usar variables espejo `SWAP_SIZE_OK` / `ROOT_SIZE_OK` que solo se actualizan cuando el valor pasa todas las validaciones, y limpiar la variable de trabajo con `SWAP_SIZE=""` cuando falla.
* **⚠️ BUG — Zona horaria sin validar:** El usuario podía introducir cualquier palabra en la pregunta de zona horaria (ej. "ai"), fallando silenciosamente en la fase chroot y dejando la variable espejo corrupta al usar `<` para retroceder. Solucionado añadiendo validación estricta contra el directorio `/usr/share/zoneinfo/` y replicando la lógica de `TIMEZONE_OK`.
* **⚠️ BUG — Ctrl+C durante reflector rompe el script:** Con `set -euo pipefail` activo, una señal `SIGINT` (Ctrl+C) lanzada sobre `reflector` propagaba el error al shell padre y abortaba el instalador. La solución es usar `trap '_MIRRORS_OK=interrupted' INT` justo antes del comando y `trap - INT` justo después, evaluando el resultado mediante una variable de estado sin dejar que el error escape al contexto padre. Se avisa al usuario con `info "(Ctrl+C para omitir)"`.
* **⚠️ BUG — Formateo falla si /mnt ya tiene particiones montadas (reinstalación):** Si se ejecuta el instalador sobre un sistema que ya intentó instalarse, `mkfs.fat` falla con "contains a mounted filesystem". La solución es comprobar con `mountpoint -q /mnt` antes de iniciar la Fase 2 y, si hay algo montado, ofrecer al usuario la opción de desmontar todo (`swapoff -a && umount -R /mnt`) o cancelar de forma controlada.
* **⚠️ BUG CRÍTICO — Contenedores LUKS abiertos bloquean el particionado:** En instalaciones iterativas fallidas, los mapeadores dm-crypt (`cryptroot`, `crypthome`) quedan abiertos. Al ejecutar `sgdisk`, el kernel lanza un warning de "device in use" y se niega a recargar la tabla de particiones, provocando que el comando subsiguiente `cryptsetup luksFormat` colapse al no poder acceder al dispositivo en exclusividad. Solucionado añadiendo limpieza forzada de contenedores LUKS y ejecutando `partprobe` explícito tras `sgdisk`.
* **⚠️ BUG CRÍTICO — Orden de configuración de GRUB con LUKS:** `grub-install` falla con el error `attempt to install to encrypted disk without cryptodisk enabled` si se intenta instalar antes de añadir `GRUB_ENABLE_CRYPTODISK=y` en `/etc/default/grub`. La solución implementada es modificar el archivo de configuración de GRUB **antes** de invocar a `grub-install`.
* **⚠️ BUG CRÍTICO — systemd-boot inarrancable en partición ext4/LUKS:** `systemd-boot` solo puede leer kernels desde particiones FAT32 (la ESP). Si montamos la ESP en `/boot/efi` y la raíz en `/dev/mapper/cryptroot`, `pacstrap` deja el kernel en la raíz cifrada y `systemd-boot` no puede cargarlo, mostrando una pantalla vacía. La solución implementada es asignar dinámicamente el punto de montaje de la ESP a `/boot` si el gestor elegido es `systemd-boot` (asegurando que kernel y microcode acaban en FAT32) y dejarlo en `/boot/efi` para GRUB.
* **⚠️ BUG — Aviso de seguridad "random seed world accessible" en systemd-boot:** Por defecto, vfat monta el ESP con lectura para todos. Añadir la opción `umask=0077` en el comando `mount` durante el formateo/montaje en Fase 2 soluciona este problema e inyecta la opción en `/etc/fstab` automáticamente a través de `genfstab`.

* **Spec de Cifrado LUKS:** Especificación técnica completa escrita en `.agent/specs/cifrado_luks.md`. Cubre la estrategia de cifrado de root y home con LUKS2 (systemd-boot) y LUKS1 (GRUB por compatibilidad), la integración en la Máquina de Estados de Fase 1, los hooks de mkinitcpio, los parámetros de kernel para ambos bootloaders y la gestión de swap cifrada efímera vía `/etc/crypttab`. Pendiente de implementación en `install.sh`.

---

## 📊 Estado Actual del Proyecto
* **Versión actual:** Script `install.sh` estable y completamente funcional para instalaciones estándar de Arch Linux (UEFI y BIOS). Rama `particionado_personalizado` con soporte de `/home` separado lista para revisión y merge.
* **Compatibilidad de CPU:** Detección dinámica de microcódigo Intel/AMD activa y funcionando.
* **Kernels Soportados:** `linux`, `linux-lts`, `linux-zen` y `linux-hardened`.
* **AUR Helpers:** `yay` y `paru` integrados de forma opcional mediante compilación limpia sin permisos de root en el directorio `/tmp`.
* **Dotfiles:** Clonación y ejecución automatizada de scripts post-instalación integrada.

---

## 🗺️ Roadmap de Mejoras Sugeridas (Futuros Pasos)
Si deseas expandir el proyecto, aquí hay ideas altamente recomendadas que se pueden abordar en las siguientes sesiones:
* [ ] **Soporte para BTRFS:** Añadir la opción de formatear en BTRFS con soporte de subvolúmenes (`@`, `@home`, `@snapshots`) para facilitar instantáneas del sistema con Timeshift.
* [x] **Cifrado de Disco (LUKS):** Implementado cifrado completo de disco con LUKS (LUKS2 con Argon2id por defecto, fallback a LUKS1 para GRUB). Implementación exitosa en `install.sh`.
* [ ] **Instalación de Entornos de Escritorio (DE):** Menú interactivo opcional para instalar entornos de escritorio (GNOME, KDE Plasma, XFCE) o gestores de ventanas (i3, Hyprland) con sus correspondientes drivers gráficos.
* [x] **Esquema de Particionado Personalizado:** Implementado. Rama `particionado_personalizado` lista para merge.
