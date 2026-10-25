# Khipro Installer

This repo provides a single interactive installer that supports both variants of the Khipro keyboard layout.

Usage:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/KhiproTeam/khipro-installer/main/installer.sh)"
```

The script starts by asking the user to choose one of these options:

1. Khipro Dark
2. Khipro Classic

It then installs the selected variant while preserving the behavior of the original installers, including:

- root vs user installation paths
- Git detection and package installation guidance
- IBus/Fcitx5 availability checks
- m17n package validation
- uninstallation support
- stable branch / tag / custom branch selection
- icon and layout installation

You can also run it directly after downloading:

```bash
chmod +x installer.sh
./installer.sh
```
