---
name: "Espec: Entornos de Escritorio y Controladores"
description: "Especificación técnica para la instalación opcional de entornos gráficos (GNOME, KDE, XFCE, Hyprland, i3) y drivers en Arch Linux."
---

# 🖥️ Espec: Entornos de Escritorio (DE) y Controladores Gráficos

Esta especificación detalla la implementación de un menú interactivo para instalar entornos gráficos y gestores de ventanas en el instalador interactivo de Arch Linux. El objetivo es que el usuario salga del script con una experiencia visual completa sin necesidad de instalar los drivers y paquetes a mano tras el primer reinicio.

---

## 🎯 Alcance y Decisiones de Diseño

### Filosofía KISS (Keep It Simple, Stupid)
- **Desktop Environments (DE)**: Se instalarán los metapaquetes oficiales completos para GNOME, KDE Plasma y XFCE, proporcionando una experiencia lista para usar con sus respectivos gestores de sesión (`gdm`, `sddm`, `lightdm`).
- **Window Managers (WM)**: Para Hyprland e i3, se instalará el mínimo absoluto (`kitty`/`alacritty`, `waybar`/`i3status`, `wofi`/`dmenu`) y el gestor de sesión. La personalización visual recae enteramente en el usuario (a través del sistema de dotfiles ya integrado en el instalador).

### Controladores Gráficos
No se puede asumir un controlador universal (nouveau vs nvidia propietario, intel vs amd). Se exigirá al usuario seleccionar explícitamente su infraestructura de hardware para inyectar los paquetes `mesa` y `vulkan` correctos.

---

## 🗣️ UX — Fase 1: Preguntas (Nuevas Opciones)

Se añadirán dos preguntas consecutivas usando la función `pick` en la Fase 1, justo antes de preguntar por el AUR helper (pasos 15 y 16 propuestos).

**1. Drivers de Vídeo:**
```text
  ?  Driver de Vídeo
     1) Intel
     2) AMD
     3) NVIDIA
     4) VirtualBox/VMware
     5) Ninguno (Servidor)
     Elige [1-5]:
```

**2. Entorno de Escritorio:**
```text
  ?  Entorno de Escritorio
     1) GNOME
     2) KDE Plasma
     3) XFCE
     4) Hyprland (Wayland)
     5) i3-wm (X11)
     6) Ninguno
     Elige [1-6]:
```

### Variables de Estado Nuevas
```bash
VIDEO_DRIVER=""   # Guarda el driver escogido (ej. "Intel", "AMD")
DESKTOP_ENV=""    # Guarda el DE escogido (ej. "GNOME", "Hyprland")
```

---

## 📦 Paquetes y Dependencias (Fase 2)

Antes de invocar a `pacstrap`, se construirá dinámicamente la variable `GUI_PKGS` y se definirá el `DM_SERVICE` basándose en las elecciones del usuario. 
Si el usuario no elige "Ninguno" en DE o Driver, la base gráfica inamovible será: `xorg-server xorg-xinit mesa`.

### A. Capa de Hardware (Drivers)
| Elección | Paquetes Inyectados | Servicio VM (`VM_SERVICE`) |
| :--- | :--- | :--- |
| **Intel** | `vulkan-intel intel-media-driver` *(modesetting built-in en Xorg)* | *(vacío)* |
| **AMD** | `xf86-video-amdgpu vulkan-radeon` | *(vacío)* |
| **NVIDIA** | `nvidia nvidia-utils` | *(vacío)* |
| **VirtualBox** | `virtualbox-guest-utils` *(incluye vboxvideo)* | `vboxservice` |
| **VMware** | `open-vm-tools` | `vmtoolsd` |
| **Ninguno** | *(vacío)* | *(vacío)* |

### B. Capa de Software (Entornos)
| Elección | Paquetes Inyectados | Display Manager (`DM_SERVICE`) |
| :--- | :--- | :--- |
| **GNOME** | `gnome gnome-tweaks gdm` | `gdm` |
| **KDE Plasma**| `plasma-meta konsole dolphin sddm` | `sddm` |
| **XFCE** | `xfce4 xfce4-goodies lightdm lightdm-gtk-greeter` | `lightdm` |
| **Hyprland** | `hyprland kitty waybar wofi sddm` | `sddm` |
| **i3-wm** | `i3-wm i3status i3lock dmenu alacritty lightdm lightdm-gtk-greeter` | `lightdm` |
| **Ninguno** | *(vacío)* | *(vacío)* |

> **Nota sobre Wayland:** Hyprland es nativo de Wayland y no necesita estrictamente `xorg-server` para funcionar en solitario, pero se incluye en `GUI_PKGS` por compatibilidad con XWayland, indispensable hoy en día.

---

## ⚙️ Configuración del Chroot — Fase 3

En el archivo `/mnt/root/_chroot.sh` generado dinámicamente, se deben inyectar las variables:
```bash
DM_SERVICE="$DM_SERVICE"   # Gestor de sesión gráfica (gdm, sddm, lightdm)
VM_SERVICE="$VM_SERVICE"   # Servicio de integración de VM (vboxservice, vmtoolsd)
```

Una vez inyectadas, los servicios se habilitan de forma condicional:

```bash
# Display Manager
[[ -n "$DM_SERVICE" ]] && systemctl enable "$DM_SERVICE"

# Servicios de Máquina Virtual (VirtualBox / VMware)
[[ -n "$VM_SERVICE" ]] && systemctl enable "$VM_SERVICE"
```

---

## 🔀 Integración con la Máquina de Estados (Fase 1)

Los nuevos pasos se insertarán desplazando los existentes (AUR, Dotfiles, SSH). 
La secuencia de la Máquina de Estados pasará a ser:

```
... → usuario/contraseñas (12-14) → drivers de vídeo (15) → escritorio (16) → aur (17) → dotfiles (18-20) → ssh (21)
```

La navegación hacia atrás (`<`) en `pick` ya está soportada nativamente, por lo que el usuario podrá retroceder libremente desde la selección del entorno hasta la de contraseñas y particiones sin que se corrompa el historial.

---

## 💾 Resumen de Variables del Script

| Variable       | Tipo    | Descripción                                                |
|----------------|---------|------------------------------------------------------------|
| `VIDEO_DRIVER` | string  | String amigable seleccionado en el picker de driver.       |
| `DESKTOP_ENV`  | string  | String amigable seleccionado en el picker de entorno.      |
| `GUI_PKGS`     | string  | Concatenación de paquetes a inyectar en pacstrap.          |
| `DM_SERVICE`   | string  | Nombre del servicio a habilitar (ej. "gdm", "sddm").       |

---

## 🧪 Plan de Verificación

- **Prueba 1 (Regresión de Consola)**: Instalar seleccionando `Ninguno` en ambas opciones. Verificar que el sistema arranca en modo TTY y que no hay paquetes de Xorg instalados por accidente.
- **Prueba 2 (VM + KDE Plasma)**: Instalar en VirtualBox eligiendo `VirtualBox/VMware` y `KDE Plasma`. Verificar resolución adaptable al cambiar tamaño de la ventana de VM (gracias a `virtualbox-guest-utils`) y auto-arranque de la pantalla de login de SDDM.
- **Prueba 3 (Navegación UI)**: Probar intensivamente el flujo de la Fase 1. Avanzar hasta la pregunta de Entorno de Escritorio, pulsar `<` para volver a Video Drivers, cambiarlo, y avanzar. Verificar que el estado del script no se corrompe.
