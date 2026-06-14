# Incident Report & Resolution: Intel e1000e NIC Boot Stall and Kernel Panic

**Date:** June 10, 2026  
**Status:** Resolved  

## 1. Root Cause Analysis (RCA)

### Issue A: NetworkManager Stall & Ethernet Driver Crash
* **Symptom:** Boot stalled at `Job NetworkManager-wait-online.service/start running`. Once past login, there was no internet.
* **Log Error:** `e1000e 0000:00:19.0 eno1: NETDEV WATCHDOG: transmit queue 0 timed out`
* **Mechanism:** The Linux Kernel (v7.0) aggressive PCIe Active State Power Management (ASPM) conflicted with the Intel network card using the `e1000e` driver, causing the transmitter queue to freeze.

### Issue B: Secondary Boot Failure (Kernel Panic)
* **Symptom:** Core system kernel panic on boot.
* **Mechanism:** Manual creation of `/etc/default/grub` from scratch without local block-device UUID hooks broke the `update-grub` mapping sequence, leaving the kernel unable to locate or mount the root filesystem (`/`).

## 2. Runbook: How to Reapply This Fix
```bash
# 1. Restore standard upstream GRUB layout configuration template
sudo cp /usr/share/grub/default/grub /etc/default/grub

# 2. Append the ASPM kernel parameter to disable hardware-level power throttling
# Locate GRUB_CMDLINE_LINUX_DEFAULT and append "pcie_aspm=off"
sudo nano /etc/default/grub

# 3. Completely clear and recreate a fresh initial ramdisk for the target kernel
sudo update-initramfs -c -k $(uname -r)

# 4. Regenerate the active bootloader runtime configurations
sudo update-grub
