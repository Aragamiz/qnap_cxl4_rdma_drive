# Mellanox ConnectX-4 Lx RoCEv2 / RDMA Driver for QuTS hero

[![License: GPL-2.0](https://img.shields.io/badge/License-GPLv2-blue.svg)](LICENSE)
[![Platform: QuTS hero](https://img.shields.io/badge/Platform-QuTS%20hero%206.0.x%20%7C%206.1.x-orange.svg)]()
[![Hardware: ConnectX-4 Lx](https://img.shields.io/badge/Hardware-Mellanox%20ConnectX--4%20Lx%2025GbE-green.svg)]()
[![Build: QDK 2.5.3](https://img.shields.io/badge/Build-QDK%202.5.3-brightgreen.svg)]()

An automated and standalone community driver package (**QPKG**) that brings **Mellanox ConnectX-4 Lx (25GbE/50GbE) RoCEv2 RDMA** and **NFS-over-RDMA** high-speed transport capabilities to **QuTS hero** storage environments.

---

> ### ⚠️ Disclaimer
> **This is an unofficial community build.**  
> Test thoroughly before using in production. Always back up your critical data before installing third-party kernel modules.  
> **QNAP**, **QTS**, and **QuTS hero** are registered trademarks of QNAP Systems, Inc. **Mellanox** and **ConnectX** are registered trademarks of NVIDIA Corporation / Mellanox Technologies.  
> This open-source project is an independent community effort and is **not affiliated with, endorsed by, or sponsored by QNAP Systems, Inc. or NVIDIA Corporation**.

---

## 🚀 Key Features

* **Crash-Safe Isolation**: Never unloads or tampers with the baseline vendor `mlx5_core.ko`. The Ethernet physical interface and baseline TCP/IP networking remain 100% stable and operational.
* **Progressive Module Loading**: Safely loads RDMA stack modules in strict topological dependency order (`ib_uverbs` $	o$ `mlx5_ib` $	o$ `rdma_ucm` $	o$ `rpcrdma`).
* **Auto-Rollback on Failure**: If any module fails sanity checks or symbol resolution, the installer rolls back cleanly without leaving orphaned symlinks or triggering kernel panics.
* **Hardware Capability Profile**: Declares ConnectX-4 Lx physical functions (`15b3:1015`) and SR-IOV virtual functions (`15b3:1016`) in system network capability tables (`/etc/nic_caps.conf`), activating `rdma_status = 0` (Active) in the hardware abstraction layer (HAL).
* **NFS over RDMA End-to-End**: Binds kernel NFS services to high-speed RDMA listening ports (`20049`), enabling microsecond-tier latency and CPU-offloaded throughput.
* **Standard QDK Packaging**: Packaged strictly compliant with QNAP Development Kit (QDK 2.5.3) standards with self-signed CMS verification and standard application privilege (`SYS_APP=0`) for native Web UI stop and removal.

---

## 📊 Benchmark Results (25GbE Optical Direct Connect)

> **Client**: Linux (Ubuntu 22.04, `mlx5_ib`, `rpcrdma`, MTU 9000)  
> **Server**: QuTS hero 6.0.2 with `CX4L_RDMA` driver  
> **Benchmark Tool**: FIO 3.28 (`direct=1`, bypassing page cache for bare physical I/O)

| Benchmark Metric (FIO direct=1) | NFS over RDMA (25G, port 20049) | SMB 3.1.1 (25G, CIFS) | RDMA Advantage |
|---|---|---|---|
| **Sequential Write (1MB, 2GB file)** | **193 MiB/s (203 MB/s)** | 138 MiB/s (145 MB/s) | **+39.9% 🚀 (Latency -28.7%)** |
| **Sequential Read (1MB, 2GB file)** | **190 MiB/s (199 MB/s)** | 175 MiB/s (183 MB/s) | **+8.6%** |
| **4K Random Read IOPS (iodepth=16)** | **22,500 IOPS (88.1 MiB/s)** | 20,300 IOPS (79.2 MiB/s) | **+10.8% (+2,200 IOPS)** |
| **4K Random Write IOPS (iodepth=16)** | **4,800 IOPS (18.8 MiB/s)** | 4,173 IOPS (16.3 MiB/s) | **+15.0% (+627 IOPS)** |

---

## 📦 Repository Layout

```text
qnap_cxl4_rdma_drive/
├── build/
│   ├── qnap_cxl4_rdma_drive_v1.0.qpkg         # Pre-compiled self-signed release package
│   └── qnap_cxl4_rdma_drive_v1.0.qpkg.md5     # MD5 checksum file
├── cert/
│   └── cert.pem                               # Public X.509 self-signing certificate
├── scripts/
│   └── build_driver.sh                        # Kernel module source compilation script
├── src/
│   ├── qpkg.cfg                               # QDK package metadata (Package name: CX4L_RDMA)
│   ├── package_routines                       # Lifecycle hook routines
│   ├── icons/                                 # Original neutral vector/pixel icons
│   └── x86_64/
│       ├── CX4L_RDMA.sh                       # Service management & crash-safe daemon script
│       └── driver/                            # Kernel 6.6.32 Dual BSD/GPL driver modules
│           ├── ib_uverbs.ko
│           ├── mlx5_ib.ko
│           ├── ib_umad.ko
│           ├── ib_ucm.ko
│           ├── rdma_ucm.ko
│           └── rpcrdma.ko
├── build_qpkg.sh                              # Standalone QDK build and self-signing script
├── LICENSE                                    # GNU General Public License v2.0
└── README.md                                  # Documentation
```

---

## 🛠️ Installation Guide

### Method A: App Center (GUI - Recommended)

1. Download `qnap_cxl4_rdma_drive_v1.0.qpkg` from the `build/` directory or GitHub Releases.
2. Open **App Center** on your NAS Web Desktop.
3. Click **Settings (gear icon)** in the top right $	o$ **General**, and check **"Allow installation of applications without a valid digital signature"**. Click **Apply**.
4. In App Center, click the **Manual Install (+ icon)** at the top right.
5. Browse and upload the `.qpkg` file.
6. Once installation completes, the driver service starts automatically and persists across system reboots.

### Method B: SSH Command Line

Upload the package to `/tmp` via SCP/SFTP, then execute:

```bash
sudo /sbin/qpkg_cli -m /tmp/qnap_cxl4_rdma_drive_v1.0.qpkg -A
```

---

## 🔍 Verification & Health Check

Verify proper module initialization via SSH:

### 1. Verify Kernel Module Checksum & Version Matching
```bash
# Verify loaded mlx5_ib module
cat /sys/module/mlx5_ib/srcversion

# Verify QPKG module binary srcversion (should match)
QPKG_PATH=$(/sbin/getcfg "CX4L_RDMA" Install_Path -f /etc/config/qpkg.conf)
strings "$QPKG_PATH/driver/mlx5_ib.ko" | grep "^srcversion="
```

### 2. Verify Hardware Abstraction Layer (HAL) RoCE State
```bash
/sbin/hal_app --nic_get_info obj_index=-1 | grep -E "(^\[eth|capability|rdma_)"
```
*Expected Output:*
```text
[eth0]
capability = 0x003c
rdma_status = 0          # 0 indicates RDMA is Active
rdma_device = mlx5_0
```

### 3. Verify RDMA Verbs Device Node
```bash
cat /sys/class/infiniband_verbs/uverbs0/ibdev
# Expected output: mlx5_0
```

### 4. Verify NFS over RDMA Listening Port
```bash
cat /proc/fs/nfsd/portlist | grep rdma
# Expected output contains: rdma 20049
```

---

## 💻 Client Mounting (NFS over RDMA)

On a Linux client with RDMA support enabled (`mlx5_ib`, `rpcrdma`, and `nfs-common` loaded):

```bash
# Create mountpoint
sudo mkdir -p /mnt/hero_rdma

# Mount with RDMA transport (replace <NAS_IP> with target IP and Data with shared folder)
sudo mount -t nfs -o rdma,port=20049,nfsvers=3 <NAS_IP>:/share/Data /mnt/hero_rdma

# Confirm active mount protocol
mount | grep hero_rdma
# Output will confirm: proto=rdma,port=20049
```

---

## 🗑️ Uninstallation

* **Via Web UI**: Open App Center, navigate to **My Apps** $	o$ **Mellanox ConnectX-4 Lx RDMA Driver**, click the dropdown menu and select **Stop**. Once stopped, click **Remove** to completely uninstall.
* **Via SSH Command Line**:
  ```bash
  sudo /sbin/qpkg_cli -R CX4L_RDMA
  ```

The uninstaller automatically removes kernel modules from memory in safe reverse order, deletes symlinks, and cleans all service definitions cleanly.

---

## 🔨 Rebuilding from Source (GPL Compliance)

The kernel modules in this package are built from official open-source distributions:
* **Linux Kernel Source**: Version `6.6.32`
* **Mellanox OFED Source**: `MLNX_OFED_SRC-23.10-3.2.2.0`
* **Module License**: `Dual BSD/GPL`

To package and sign locally on any Linux environment with QDK installed:

```bash
chmod +x build_qpkg.sh
./build_qpkg.sh
```

---

## 📄 License

This QPKG wrapper project and deployment scripts are licensed under the [GNU General Public License v2.0 (GPL-2.0)](LICENSE). Included kernel modules are licensed under Dual BSD/GPL.
