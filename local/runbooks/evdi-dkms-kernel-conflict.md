# Incident Report: EVDI Kernel Module Build Failure (Ubuntu 26.04 Upgrade)

**Date:** June 14, 2026  
**Status:** Open / Pending Action  

## 1. Incident Overview
During package upgrades, compilation failures were triggered across the DKMS layer. The automated build subsystem threw an error code (1) when attempting to generate core kernel hooks for the `7.0.0` kernel block.

## 2. Root Cause Analysis (RCA)
The system contains legacy `evdi` (Extended Virtual Display Interface) source modules (v1.14.11) used for DisplayLink hardware or USB-to-video adapters. This version contains legacy functions incompatible with the refactored structures of the new Linux v7.0 kernel, causing the compilation to crash and blocking `apt` configuration.

## 3. Remediations & Resolution Playbooks

### Path A: Purge the Module (If DisplayLink Docks/USB hardware are NOT in use)
`bash
sudo apt purge evdi-dkms
sudo apt install -f
`

### Path B: Drop Build Target (If DisplayLink Docks/USB hardware ARE active)
`bash
sudo dkms remove evdi/1.14.11 --all
sudo apt install -f
`