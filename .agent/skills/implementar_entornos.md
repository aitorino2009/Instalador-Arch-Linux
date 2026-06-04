# 🛠️ Habilidad: Implementación y Testeo de Entornos de Escritorio

Esta habilidad reúne las **recetas de comandos** para aislar, probar y verificar la instalación de Entornos de Escritorio (DE) y Drivers Gráficos, asegurando que los paquetes seleccionados se resuelven correctamente y que los gestores de sesión se habilitan de forma impecable en el chroot.

> Consulta siempre la especificación técnica en `.agent/specs/entornos_escritorio.md` antes de tocar una línea de `install.sh`.

> ⚠️ **ATENCIÓN (Entorno Windows):** Como estás programando desde Windows, **no puedes ejecutar estos comandos en tu terminal local**. Todas las recetas de esta Skill están diseñadas para ejecutarse **dentro de tu Máquina Virtual** arrancada con la ISO de Arch Linux.

---

## 🧪 Sección 1: Simulación de Resolución de Paquetes (`pacstrap`)

Antes de lanzar una instalación completa, podemos probar si el conjunto de paquetes que hemos calculado en nuestra variable `GUI_PKGS` existe y no tiene conflictos, sin necesidad de instalarlos realmente.

### 1.1 Preparar un chroot falso (Dry-run)
Podemos usar `pacman` con el flag `--print` o usar un directorio vacío temporal.

```bash
# Crear directorio de test
mkdir -p /tmp/test-arch-root
mkdir -p /tmp/test-arch-root/var/lib/pacman

# Inicializar DB pacman vacía
pacman -r /tmp/test-arch-root -Sy
```

### 1.2 Testear inyección de paquetes (Ejemplo: AMD + KDE)
```bash
GUI_PKGS="xorg-server xorg-xinit mesa xf86-video-amdgpu vulkan-radeon plasma-meta konsole dolphin sddm"

# Simular la descarga/resolución (si no da error, el array es válido)
pacman -r /tmp/test-arch-root -S --print $GUI_PKGS
```

---

## ⚙️ Sección 2: Testeo de Gestores de Sesión en Chroot

El comando `systemctl enable` crea enlaces simbólicos (`symlinks`) dentro de `/etc/systemd/system/`. Podemos probar esta lógica creando una estructura falsa para verificar que nuestro código bash hace lo correcto.

### 2.1 Simulación del Chroot
```bash
# Crear estructura falsa
mkdir -p /tmp/fake-chroot/etc/systemd/system
mkdir -p /tmp/fake-chroot/usr/lib/systemd/system

# Crear archivos de servicio falsos simulando la instalación de paquetes
touch /tmp/fake-chroot/usr/lib/systemd/system/gdm.service
touch /tmp/fake-chroot/usr/lib/systemd/system/sddm.service
touch /tmp/fake-chroot/usr/lib/systemd/system/lightdm.service
```

### 2.2 Ejecutar la lógica de enlace
```bash
# Entramos a la jaula
chroot /tmp/fake-chroot /bin/bash

# --- DENTRO DEL CHROOT ---
DM_SERVICE="sddm"

if [[ -n "$DM_SERVICE" ]]; then
    # systemctl en un chroot sin systemd corriendo a veces se queja, 
    # pero el comando enable funciona offline desde systemd 232+
    systemctl enable "$DM_SERVICE"
fi

# Verificar que el enlace simbólico default.target o display-manager.service se creó
ls -l /etc/systemd/system/display-manager.service
# Debería apuntar a /usr/lib/systemd/system/sddm.service
exit
```

---

## 👁️ Sección 3: Verificación de Drivers Post-Instalación

Una vez el sistema ha reiniciado, si el entorno gráfico no arranca, estos son los comandos de diagnóstico vitales a utilizar desde la TTY.

### 3.1 Verificación de Hardware y Drivers Cargados
```bash
# Comprobar qué gráfica detecta el Kernel y qué módulo (driver) está usando
lspci -nnk | grep -i vga -A3

# Comprobar si Xorg levantó sin errores (EE)
grep "(EE)" /var/log/Xorg.0.log
```

### 3.2 Verificación de Wayland (Hyprland)
```bash
# Comprobar si la sesión actual usa Wayland
echo $XDG_SESSION_TYPE

# Lanzar Hyprland manualmente para ver el output de errores si falla sddm
Hyprland
```

### 3.3 Verificación del Servicio de Display Manager
```bash
# Revisar el log del servicio sddm/gdm/lightdm si la pantalla se queda en negro
journalctl -u sddm.service -e

# Comprobar estado
systemctl status sddm.service
```

---

## 🧹 Sección 4: Limpieza del Entorno de Pruebas

```bash
rm -rf /tmp/test-arch-root
rm -rf /tmp/fake-chroot
```
