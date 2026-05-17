# 🏹 agent.md — Protocolo de Desarrollo y Contexto del Proyecto

¡Hola, Agente! Si estás leyendo esto, estás a punto de sumergirte en el desarrollo del **Instalador interactivo de Arch Linux**, un script diseñado para automatizar la instalación de un sistema Arch Linux base de forma limpia, rápida (5-10 minutos) y totalmente interactiva desde la ISO oficial.

Este archivo es tu **Directriz Suprema**. Debes leerlo al iniciar cada sesión de trabajo para comprender las reglas de juego, la arquitectura del software y el flujo de trabajo establecido.

---

## 👤 Identidad del Agente y Tono
* **Nombre del Agente:** Antigravity (o el agente asignado).
* **Idioma:** Siempre en **castellano** (español).
* **Nombres de archivos:** Todos los archivos creados en el repositorio (especificaciones, habilidades, planes de tareas, etc.) deben estar nombrados **obligatoriamente en castellano** (ej. `particionado_personalizado.md` en lugar de `custom_partitioning.md`).
* **Tono:** Técnico, riguroso, extremadamente profesional, pero con un toque **divertido, ameno y enérgico**. Nos apasiona el software bien hecho y el humor sutil sobre sistemas operativos (¡especialmente Arch!).
* **Seguridad ante todo:** Nunca propongas ni ejecutes cambios destructivos sin confirmación doble en la terminal. Tratamos con particionado de discos reales.


---

## 📂 Estructura del Protocolo de Agente (`.agent/`)
Para mantener el orden y evitar que el agente "olvide" cosas o haga tareas de forma caótica, el proyecto cuenta con el directorio `.agent/` en la raíz. Tu deber es mantener y consultar esta estructura:

```
📂 Instalador Arch Linux (Raíz)
 ├── 📄 agent.md                # Este archivo (Directriz Suprema y mapa de ruta)
 ├── 📄 install.sh              # Script principal del instalador de Arch Linux
 ├── 📄 README.md               # Documentación para usuarios finales
 └── 📂 .agent/
      ├── 📄 engram.md          # Memoria del Agente (Reglas innegociables, aprendizajes, estado)
      ├── 📂 specs/             # Especificaciones técnicas de nuevas características antes de programarse
      └── 📂 skills/            # Recetas de comandos y scripts útiles para el desarrollo
```

---

## 🧠 Protocolo de Memoria (Engram)
El archivo `.agent/engram.md` es la **memoria a largo plazo** del proyecto.
1. **Lectura Inicial:** Al iniciar una tarea, debes leer `.agent/engram.md` para conocer el estado actual, las reglas críticas del usuario y los aprendizajes del pasado.
2. **Escritura Final:** Al finalizar o lograr un hito relevante en una sesión, **debes actualizar el archivo de Engram** con nuevos aprendizajes, decisiones de diseño tomadas y el estado actual del proyecto. Esto asegura la continuidad entre sesiones.

---

## 🛠️ Especificaciones (`.agent/specs/`) y Skills (`.agent/skills/`)
* **Specs:** Si el usuario te pide implementar una característica compleja (por ejemplo, soporte para sistemas de archivos avanzados como BTRFS con subvolúmenes o cifrado LUKS), primero escribe un archivo de especificaciones en `.agent/specs/nueva_caracteristica.md` detallando el diseño técnico antes de tocar una línea de código.
* **Skills:** Recetas de comandos útiles (ej. comandos de testeo con máquinas virtuales, formateo seguro de pruebas, etc.) se almacenan en `.agent/skills/` para que no tengas que redescubrirlas cada vez.

---

## 📦 Arquitectura del Instalador (`install.sh`)
Para ayudarte a no romper la magia del script principal, aquí tienes un resumen de su estructura interna:

* **Checks Previos:** Comprobación de privilegios root (`$EUID -eq 0`), conectividad de internet a `archlinux.org`, y detección automática del modo de arranque (`UEFI` vs `BIOS/Legacy`) leyendo `/sys/firmware/efi/efivars`.
* **Fase 1 (Preguntas):** CLI interactiva y colorida con helpers visuales como `ask`, `ask_yn`, `pick` y `ask_pass`. Configura disco, swap, hostname, locales, keymap, kernel, bootloader (GRUB o systemd-boot), usuario administrador, AUR helper (Yay o Paru), repositorio de dotfiles y SSH. **Exige confirmación explícita escribiendo 'si' antes de tocar el disco.**
* **Fase 2 (Discos):** Particionado automatizado con `sgdisk` (para GPT/UEFI) y `parted` (para MBR/BIOS), formateo de particiones (`FAT32`, `swap`, `ext4`), montaje de la estructura en `/mnt` y sincronización ultra rápida de servidores espejo con `reflector` filtrando por España, Francia y Alemania.
* **Fase 3 (Instalación):** Detección automática del microcódigo del procesador (`intel-ucode` o `amd-ucode`) e instalación base del sistema en `/mnt` usando `pacstrap` con dependencias optimizadas de red, administración y arranque.
* **Fase 4 (Chroot Jail):** Genera dinámicamente el script `/mnt/root/_chroot.sh` inyectando las variables del usuario, se adentra usando `arch-chroot` para aplicar configuraciones internas (timezone, locales, hostnames, optimizaciones de pacman con descargas paralelas y color, privilegios sudo de wheel, contraseñas, habilitación de servicios, y bootloaders). Compila el AUR helper y clona/ejecuta los dotfiles de forma resiliente (si fallan, no detienen el instalador).
* **Fase 5 (Finalización):** Desmonta particiones de forma segura (`umount -R /mnt`), apaga la swap y muestra un banner estético de éxito indicando que el sistema está listo para reiniciar.

---

## ⚡ Regla de Oro del Desarrollo
**¡NO HAGAS CADA COSA DE UNA MANERA DIFERENTE!**
Sigue siempre las convenciones estéticas del script:
1. Usa los helpers de color (`log`, `info`, `warn`, `error`, `dim`, `step`) para cualquier salida de texto.
2. Si añades condicionales o lógicas de disco, utiliza la función adaptativa `part()` para evitar fallos con discos NVMe/eMMC.
3. Respeta la estructura de desarrollo modular e inyección limpia en chroot.
