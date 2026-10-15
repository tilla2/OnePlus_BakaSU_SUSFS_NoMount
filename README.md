<div align="center">

# ChimeraKernel

**OnePlus · BakaSU + SUSFS + NoMount kernels**

[![KernelSU](https://img.shields.io/badge/KernelSU-Supported-green)](https://kernelsu.org/)
[![BakaSU](https://img.shields.io/badge/BakaSU-Supported-green)](https://github.com/Baka-SU/BakaSU)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-orange)](https://gitlab.com/simonpunk/susfs4ksu)
[![OnePlusOSS Tracking Status](https://img.shields.io/badge/OnePlusOSS--Tracker-active-green)](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS/blob/status-page/README.md)

[![Download Releases](https://img.shields.io/badge/Download_Releases-0969da?style=for-the-badge&logo=github&logoColor=white)](https://github.com/tilla2/OnePlus_BakaSU_SUSFS_NoMount/releases)

</div>

---

## Project Credits

<div align="center">

**ChimeraKernel** — maintained and published by [tilla2](https://github.com/tilla2)

Project maintainer and release publisher

| Upstream contributors |
|:---:|
| [Nostalgic (@RealS3S)](https://t.me/RealS3S) · [magi (@maxsteeel)](https://t.me/maxsteeel) · [萧少 (@huangdihd)](https://t.me/huangdihd) · [fatalcoder524](https://t.me/fatalcoder524) · [The Wild James (@TheWildJames)](https://t.me/TheWildJames) |

</div>

This project builds on their work and on the upstream projects credited below.

---

## ⚠️ Disclaimer

Flashing this kernel will not void your warranty, but there is always a risk of bricking your device. Please make sure to:
- 💾 Back up your data
- 🧠 Understand the risks before proceeding

- I am **not responsible** for bricked devices, damaged hardware, or any issues that arise from using this kernel.

- **Please** do thorough research and fully understand the features added in this kernel before flashing it!

- By flashing this kernel, **YOU** are choosing to make these modifications. If something goes wrong, **do not blame me**!

<div align="center">

# **🚨 Proceed at your own risk!**

</div>

---

## 🔧 Device Support

<div align="center">

| Device family | Availability | Status |
|---------------|--------------|--------|
| 📱 **OnePlus** | Kernel packages in this repository | ✅ Available now |
| 📱 **Oppo / Realme** | Planned | Submit your PR |
| 🏖️ **GKI / other devices** | Planned | Submit your PR |
| 📱 **Samsung** | Planned | Submit your PR |
</div>

---

## 🔗 Additional Resources

- 🧩 [Kernel Patches](https://github.com/WildKernels/kernel_patches)
- ⚡ [Kernel Flasher](https://github.com/fatalcoder524/KernelFlasher)

---

## 📱 Device Compatibility

- Please verify the device compatibility before flashing here: [Compatibility_Info](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS/blob/main/compatibility.md). 

---

## 📱 OnePlusOSS Repositories Tracking

- 📊 **Live Dashboard**: [OnePlus Repos Tracking & Changes](https://github.com/WildKernels/OnePlus_KernelSU_SUSFS/blob/status-page/README.md)
- ⏱️ **Update Frequency**: Every 2 hours (Automated)
---

## ✨ Features

> **Release build profile:** the workflow defaults to Clang **O2** optimization. A **clean build** only disables the CI compiler cache; it is an optional build-runner setting, not a kernel feature or a quality indicator.

### Root, hiding, and module capabilities

- 🔐 **BakaSU**: Kernel-based Android root integration.
- 🕵️ **SUSFS**: Root-hiding filesystem patches and userspace support.
- 🚫 **NoMount**: MaxSteel NoMount kernel integration, paired with the matching flashable metamodule.
- 🧹 **Module intercept and overlay mechanism**: Supports the supplied device-specific module overlay components.
- 🛡️ **Baseband Guard (BBG)**: LSM-based protection for critical baseband-related partitions.
- ⚡ **TMPFS XATTR and POSIX ACL**: Extended TMPFS support for metamodules and compatible tools.

### Networking and container support

- 🖥️ **BBR with FQ/FQ-CoDel**: Modern TCP congestion-control and queueing support.
- 🌐 **TTL / hop-limit targets**: IPv4 TTL and IPv6 hop-limit Netfilter targets.
- 🧱 **IPSet and IPv6 NAT**: IPSet match/set support plus IPv6 masquerading and NAT.
- 🖥️ **Droidspaces / LXC prerequisites**: IPC, PID, user namespace, POSIX message queue, and related container support.
- 🔌 **USB DWC3 / OTG**: Dual-role USB gadget and Type-C configuration, with Qualcomm or MediaTek PHY support selected per device.

### Compatibility and platform enhancements

- 🔃 **NTSync**: Windows NT synchronization primitives for compatible userspace.
- </> **Unicode bypass fix**: Protection against non-printable Unicode path handling issues.
- 🧰 **GKI ptrace compatibility**: Applied where required by older kernel families.
- 🦀 **Rust Binder support**: Included in the Android 16 / kernel 6.12 packages.
- 📄 **config.gz compatibility layer**: Keeps selected added capabilities visible to configuration readers.

### Performance, storage, and responsiveness tuning

- 🚀 **Clang O2 by default**: O3 remains an explicit workflow option; it is never silently selected.
- 🔗 **Per-device LTO configuration**: Thin LTO is enabled where the device configuration supports it; affected Android 16 packages correctly use LTO disabled.
- 🧠 **Memory tuning**: Optimized memory operations, `memcmp`, `clear_page` where compatible, memory prefetching, file-structure alignment, and lower cache pressure.
- ⚙️ **Scheduler and CPU-frequency tuning**: Wakeup-time reduction, CPU scan-order adjustment, minimum-frequency handling, reduced idle wake attempts, and cpufreq branch optimization where compatible.
- 💾 **Storage and I/O tuning**: F2FS congestion and fsync tuning, a longer ext4 commit interval, and lower GC-thread sleep time.
- 📡 **Network and system responsiveness**: TCP no-delay behavior, larger socket packet limits, fewer PCI PME wakeups, timeout-wakelock handling, and reduced IRQ/system log spam.

---

## 📋 Installation Instructions

- **KernelSU**: Developed by [tiann](https://github.com/tiann/KernelSU).
- **BakaSU**: Developed by [Baka-SU](https://github.com/Baka-SU/BakaSU)
- **Magic-KSU**: Developed by [5ec1cff](https://github.com/5ec1cff/KernelSU).  
- **SUSFS**: Developed by [simonpunk](https://gitlab.com/simonpunk/susfs4ksu.git).
- **SUSFS Module**: Developed by [sidex15](https://github.com/sidex15).
- **Sultan Kernels**: Developed by [kerneltoast](https://github.com/kerneltoast).
For GKI installation, please follow the official guide:

📖 **[KernelSU Installation Guide](https://kernelsu.org/guide/installation.html)**

You can also find Installation instructions in the release notes.

---

## 📦 Recommended Modules

<div align="center">

| 🧩 **Module** | 👨‍💻 **Developer** | 🔗 **Link** |
|:---------------:|:----------------:|:-----------:|
| **NoMount** — bundled in this repo's release artifacts; always flash the bundled copy, do not update separately | maxsteeel | [![GitHub](https://img.shields.io/badge/GitHub-maxsteeel-blue?style=flat-square&logo=github)](https://github.com/maxsteeel/nomount) |
| **BRENE** (at upstream) | rrr333nnn333 | [![GitHub](https://img.shields.io/badge/GitHub-rrr333nnn333-blue?style=flat-square&logo=github)](https://github.com/rrr333nnn333/BRENE) |
| **TCP Optimiser** (BBRv3) | fatalcoder524 | [![GitHub](https://img.shields.io/badge/GitHub-fatalcoder524-blue?style=flat-square&logo=github)](https://github.com/fatalcoder524/TCP_Optimiser_Module) |
| **Bootloop Protector** (AshLooper) | AshReXcue | [![GitHub](https://img.shields.io/badge/GitHub-AshLooper-blue?style=flat-square&logo=github)](https://github.com/RipperHybrid/AshLooper) |
| **Play Integrity Fork** | osm0sis | [![GitHub](https://img.shields.io/badge/GitHub-osm0sis-blue?style=flat-square&logo=github)](https://github.com/osm0sis/PlayIntegrityFork) |
| **PIF--Inject** | KOWX712 | [![GitHub](https://img.shields.io/badge/GitHub-KOWX712-blue?style=flat-square&logo=github)](https://github.com/KOWX712/PlayIntegrityFix) |
| **TEESimulator** | JingMatrix | [![GitHub](https://img.shields.io/badge/GitHub-JingMatrix-blue?style=flat-square&logo=github)](https://github.com/JingMatrix/TEESimulator) |
| **OhMyKeymint** | qwq233 | [![GitHub](https://img.shields.io/badge/GitHub-qwq233-blue?style=flat-square&logo=github)](https://github.com/qwq233/OhMyKeymint) |
| **TrickyStoreOSS** | beakthoven | [![GitHub](https://img.shields.io/badge/GitHub-beakthoven-blue?style=flat-square&logo=github)](https://github.com/beakthoven/TrickyStoreOSS) |
| **HMA-OSS** | frknkrc44 | [![GitHub](https://img.shields.io/badge/GitHub-frknkrc44-blue?style=flat-square&logo=github)](https://github.com/frknkrc44/HMA-OSS) |
| **Vector** | JingMatrix | [![GitHub](https://img.shields.io/badge/GitHub-JingMatrix-blue?style=flat-square&logo=github)](https://github.com/JingMatrix/Vector) |

</div>

*Every module belongs to its respective developer — flash from their official releases unless noted otherwise.*

**Honourable mentions:**

<div align="center">

[![GitHub](https://img.shields.io/badge/GitHub-Specter--by--dpejoh-blue?style=flat-square&logo=github)](https://github.com/dpejoh/specter)
[![Telegram](https://img.shields.io/badge/Telegram-Vector--by--danmagisk-blue?logo=telegram)](https://t.me/danmgk)

</div>

---

## 🌟 Special Thanks

**These amazing people help make this project possible! ❤️**

<div align="center">


| 🔧 **Project** | 👨‍💻 **Developer** | 🔗 **Link** |
|:---------------:|:----------------:|:-----------:|
| **KernelSU** | tiann | [![GitHub](https://img.shields.io/badge/GitHub-tiann-blue?style=flat-square&logo=github)](https://github.com/tiann/KernelSU) |
| **BakaSU** | Baka-SU | [![GitHub](https://img.shields.io/badge/GitHub-Baka--SU-blue?style=flat-square&logo=github)](https://github.com/Baka-SU/BakaSU) |
| **Magic-KSU** | 5ec1cff | [![GitHub](https://img.shields.io/badge/GitHub-5ec1cff-blue?style=flat-square&logo=github)](https://github.com/5ec1cff/KernelSU) |
| **SUSFS** | simonpunk | [![GitLab](https://img.shields.io/badge/GitLab-simonpunk-orange?style=flat-square&logo=gitlab)](https://gitlab.com/simonpunk/susfs4ksu.git) |
| **SUSFS Module** | sidex15 | [![GitHub](https://img.shields.io/badge/GitHub-sidex15-blue?style=flat-square&logo=github)](https://github.com/sidex15) |
| **NoMount** | maxsteeel | [![GitHub](https://img.shields.io/badge/GitHub-maxsteeel-blue?style=flat-square&logo=github)](https://github.com/maxsteeel/nomount) |
| **Sultan Kernels** | kerneltoast | [![GitHub](https://img.shields.io/badge/GitHub-kerneltoast-blue?style=flat-square&logo=github)](https://github.com/kerneltoast) |
| **Baseband Guard** | vc-teahouse | [![GitHub](https://img.shields.io/badge/GitHub-vc--teahouse-blue?style=flat-square&logo=github)](https://github.com/vc-teahouse/Baseband-guard.git) |
| **Droidspaces** | ravindu644 | [![GitHub](https://img.shields.io/badge/GitHub-ravindu644-blue?style=flat-square&logo=github)](https://github.com/ravindu644/Droidspaces-OSS.git) |
| **Oplus patchsets** (zstd & rtmutex zram, CVE fix) | cctv18 | [![GitHub](https://img.shields.io/badge/GitHub-cctv18-blue?style=flat-square&logo=github)](https://github.com/cctv18/oppo_oplus_realme_sm8850) |
| **Adiós patches & device manifests** | Bouteillepleine | [![GitHub](https://img.shields.io/badge/GitHub-Bouteillepleine-blue?style=flat-square&logo=github)](https://github.com/Bouteillepleine/kernel_patches) |

</div>

*If you have contributed and are not listed here, please remind me!* 🙏

---

## 💬 Support

If you encounter any issues or need help, feel free to:
- 🐛 Open an issue in this repository
- 💬 Reach out to me directly

---

## 📱 Connect

<div align="center">

TBD — to be determined.

</div>

---

## 💖 Donations

<div align="center">

TBD — to be determined.
