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
* [ ] **Cifrado de Disco (LUKS):** Implementar cifrado completo de disco con LUKS para usuarios que requieran máxima seguridad en equipos portátiles.
* [ ] **Instalación de Entornos de Escritorio (DE):** Menú interactivo opcional para instalar entornos de escritorio (GNOME, KDE Plasma, XFCE) o gestores de ventanas (i3, Hyprland) con sus correspondientes drivers gráficos.
* [x] **Esquema de Particionado Personalizado:** Implementado. Rama `particionado_personalizado` lista para merge.

