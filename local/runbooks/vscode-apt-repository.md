# Infrastructure Configuration: Native VS Code APT Repository Integration

**Date:** June 14, 2026  
**Status:** Implemented & Verified  

## 1. Problem Statement
When VS Code is installed via a loose `.deb` package, the binary resides in system directories owned by `root`. The standard user cannot overwrite files here, preventing the app from updating natively inside the UI and redirecting users to manual downloads.

## 2. Solution: Automated Repository Provisioning
The official Microsoft package distribution stream was registered explicitly inside `apt`.

```bash
# 1. Ensure system prerequisites are present
sudo apt install wget gpg

# 2. Securely download and de-armor Microsoft's trusted public GPG signing key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/vscode.gpg

# 3. Inject a pristine repository source configuration linked specifically to the custom keyring
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/vscode.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list

# 4. Re-index local package caches and seamlessly overlay the tracking update stream over the existing binary
sudo apt update
sudo apt install code

