import Foundation
import CryptoKit

// MARK: - Ubuntu Base 24.04.2 LTS (Noble Numbat · ARM64 / aarch64) Subsystem

/// Represents the integrated Ubuntu Base 24.04.2 LTS (Noble Numbat) ARM64
/// root filesystem (`ubuntu-base-24.04.2-base-arm64.tar.gz`), Linux kernel
/// (`6.12.0-28-generic-arm64`), `systemd` / service manager, `dpkg` + `apt`
/// package database, and FHS hierarchy inside `AstralLinuxRoot`.
@MainActor
final class AlphaLinuxSubsystem: ObservableObject {

    static let shared = AlphaLinuxSubsystem()

    // MARK: - Canonical Ubuntu Base 24.04 LTS ARM64 Constants

    static let isoFileName = "ubuntu-base-24.04.2-base-arm64.tar.gz"
    static let isoExactSizeBytes: Int64 = 31_457_280 // ~30.0 MiB compressed arm64 rootfs
    static let isoSectorCount: Int = 15_360
    static let isoSectorSize: Int = 2048
    static let driveFileID = "ubuntu-base-24.04.2-arm64"
    static let driveViewURL = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/"
    static let driveDirectDownloadURL = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.4-base-arm64.tar.gz"
    static let officialMirrorURL = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-arm64.tar.gz"
    static let fallbackCoreURL = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.2-base-arm64.tar.gz"

    static let distroName = "Ubuntu 24.04.2 LTS (Noble Numbat)"
    static let kernelRelease = "6.12.0-28-generic-arm64"
    static let kernelVersionString = "#28-Ubuntu SMP PREEMPT_DYNAMIC aarch64 GNU/Linux"
    static let srmFirmwareVersion = "systemd 255.4-1ubuntu8"
    static let abootVersion = "GRUB 2.12-1ubuntu7 (arm64-efi)"
    static let targetTriplet = "aarch64-linux-gnu"
    static let squashfsSizeBytes: Int64 = 118_489_088

    // MARK: - Published Runtime State

    @Published private(set) var activeKernelImage: String = "/boot/vmlinuz-6.12.0-28-generic"
    @Published private(set) var activeInitramfs: String = "/boot/initrd.img-6.12.0-28-generic"
    @Published private(set) var activeBootSlot: Int = 0
    @Published private(set) var isMounted: Bool = false
    @Published private(set) var isoProbeStatus: String = "Ubuntu Base 24.04.2 LTS (arm64) Mounted at /"
    @Published private(set) var loadedModules: [KernelModule] = AlphaLinuxSubsystem.defaultModules
    @Published private(set) var sysctlParameters: [String: String] = AlphaLinuxSubsystem.defaultSysctl
    @Published private(set) var openRCServices: [OpenRCService] = AlphaLinuxSubsystem.defaultServices
    @Published private(set) var dmesgBuffer: [String] = []
    @Published private(set) var ufwEnabled: Bool = true
    @Published private(set) var ufwRules: [String] = ["22/tcp ALLOW IN Anywhere", "80/tcp ALLOW IN Anywhere", "443/tcp ALLOW IN Anywhere"]

    struct KernelModule: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let size: Int
        let usedByCount: Int
        let usedBy: String
        let description: String
    }

    struct OpenRCService: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let runlevel: String
        var status: String // "started" / "active", "stopped"
    }

    private let fileManager = FileManager.default
    private let bootTimestamp = Date()

    private init() {
        resetDmesgBuffer()
    }

    // MARK: - Default Kernel Modules, Sysctl & Systemd Services

    static let defaultModules: [KernelModule] = [
        KernelModule(name: "ubuntu_arm64_bridge", size: 65536, usedByCount: 4, usedBy: "overlay,ext4,virtio_net,AstralAI", description: "Ubuntu 24.04 LTS arm64 Native Execution & VFS Bridge on Apple Silicon"),
        KernelModule(name: "overlay", size: 147456, usedByCount: 1, usedBy: "-", description: "OverlayFS Writable Union Mount (/home/astral over Ubuntu Base RootFS)"),
        KernelModule(name: "squashfs", size: 73728, usedByCount: 1, usedBy: "overlay", description: "SquashFS 4.0 Compressed Root Image Support"),
        KernelModule(name: "ext4", size: 983040, usedByCount: 2, usedBy: "-", description: "Fourth Extended Journaling Filesystem"),
        KernelModule(name: "btrfs", size: 1638400, usedByCount: 0, usedBy: "-", description: "B-Tree Filesystem Module"),
        KernelModule(name: "loop", size: 40960, usedByCount: 2, usedBy: "squashfs", description: "Loopback Block Device Driver"),
        KernelModule(name: "virtio_blk", size: 32768, usedByCount: 2, usedBy: "ext4", description: "VirtIO Paravirtualized Block Storage Driver"),
        KernelModule(name: "virtio_net", size: 69632, usedByCount: 1, usedBy: "-", description: "VirtIO Network Interface Driver (eth0)"),
        KernelModule(name: "nf_tables", size: 286720, usedByCount: 3, usedBy: "ufw,ip_tables", description: "Netfilter nftables Packet Filtering Engine (UFW)"),
        KernelModule(name: "tls", size: 114688, usedByCount: 2, usedBy: "openssl", description: "Kernel Transport Layer Security (kTLS) Hardware Offload"),
    ]

    static let defaultSysctl: [String: String] = [
        "kernel.ostype": "Linux",
        "kernel.osrelease": "6.12.0-28-generic-arm64",
        "kernel.version": "#28-Ubuntu SMP PREEMPT_DYNAMIC aarch64",
        "kernel.hostname": "astra-os",
        "kernel.domainname": "ubuntu.local",
        "kernel.arch": "aarch64",
        "kernel.pid_max": "4194304",
        "kernel.threads-max": "65536",
        "kernel.randomize_va_space": "2",
        "vm.swappiness": "30",
        "vm.overcommit_memory": "1",
        "fs.file-max": "524288",
        "fs.inotify.max_user_watches": "524288",
        "net.ipv4.ip_forward": "1",
        "net.core.somaxconn": "4096",
        "net.ipv4.tcp_congestion_control": "bbr",
    ]

    static let defaultServices: [OpenRCService] = [
        OpenRCService(name: "systemd-journald", runlevel: "system", status: "started"),
        OpenRCService(name: "systemd-udevd", runlevel: "system", status: "started"),
        OpenRCService(name: "systemd-networkd", runlevel: "system", status: "started"),
        OpenRCService(name: "systemd-resolved", runlevel: "system", status: "started"),
        OpenRCService(name: "dbus", runlevel: "default", status: "started"),
        OpenRCService(name: "cron", runlevel: "default", status: "started"),
        OpenRCService(name: "ssh", runlevel: "default", status: "started"),
        OpenRCService(name: "ufw", runlevel: "default", status: "started"),
        OpenRCService(name: "astral-agentd", runlevel: "default", status: "started"),
        OpenRCService(name: "ubuntu-desktop-x11", runlevel: "graphical", status: "started"),
    ]

    // MARK: - Boot Ring Buffer (`dmesg`)

    func resetDmesgBuffer() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        dmesgBuffer = [
            "[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x610f0280] (Apple Silicon ARMv8.6-A / aarch64)",
            "[    0.000000] Linux version 6.12.0-28-generic-arm64 (buildd@bos03-arm64-042) (aarch64-linux-gnu-gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0, GNU ld (GNU Binutils for Ubuntu) 2.42) #28-Ubuntu SMP PREEMPT_DYNAMIC",
            "[    0.000000] Machine model: Apple iPhone / Astra-OS 8.0 Ubuntu 24.04.2 LTS (Noble Numbat) arm64 Workstation",
            "[    0.000000] Command line: BOOT_IMAGE=/boot/vmlinuz-6.12.0-28-generic root=UUID=ubuntu-2404-noble-arm64 rw quiet splash console=ttyAMA0",
            "[    0.001240] efi: EFI v2.10 by Canonical GRUB 2.12-1ubuntu7 (arm64-efi)",
            "[    0.004820] Memory: 8192000K/8388608K available (16384K kernel code, 2840K rwdata, 5120K rodata, 2048K init, 196608K reserved)",
            "[    0.014200] smp: Bringing up secondary CPUs ... Brought up 1 node, \(cores) CPUs (aarch64 Little-Endian)",
            "[    0.032100] CPU features: detected: GIC system register CPU interface,LSE atomic instructions,AES,SHA256,CRC32,FP16,DotProd",
            "[    0.088400] Trying to unpack rootfs image as initramfs (/boot/initrd.img-6.12.0-28-generic)...",
            "[    0.164000] Freeing initrd memory: 28672K",
            "[    0.212000] EXT4-fs (vda1): mounted filesystem with ordered data mode (ubuntu-base-24.04.2-base-arm64.tar.gz)",
            "[    0.258000] overlayfs: mounted writable workspace union on /home/astral",
            "[    0.312000] systemd[1]: systemd 255.4-1ubuntu8.6 running in system mode (+PAM +AUDIT +SELINUX +APPARMOR +IMA +SMACK +SECCOMP +GCRYPT -GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBFDISK +PCRE2 +PWQUALITY +P11KIT +QRENCODE +TPM2 +BZIP2 +LZ4 +XZ +ZLIB +ZSTD)",
            "[    0.348000] systemd[1]: Detected architecture arm64.",
            "[    0.395000] Welcome to Ubuntu 24.04.2 LTS (Noble Numbat)!",
            "[    0.442000] systemd[1]: Set hostname to <astra-os>.",
            "[    0.498000] virtio_net virtio0 eth0: link up (10000 Mbps full-duplex)",
            "[    0.540000] astral-agentd[512]: Astral AI V8.0 Ubuntu Base 24.04 ARM64 engine & live desktop screen ready at /home/astral",
        ]
    }

    func appendKernelLog(_ message: String) {
        let elapsed = Date().timeIntervalSince(bootTimestamp)
        let formatted = String(format: "[%12.6f] %@", elapsed + 0.58, message)
        dmesgBuffer.append(formatted)
    }

    // MARK: - Materialize Ubuntu Base 24.04 LTS ARM64 Filesystem on Disk

    func mountFullSystem(supportBaseURL: URL, homeURL: URL) {
        let bootURL = supportBaseURL.appendingPathComponent("boot", isDirectory: true)
        let etcURL = supportBaseURL.appendingPathComponent("etc", isDirectory: true)
        let aptURL = etcURL.appendingPathComponent("apt", isDirectory: true)
        let dpkgURL = supportBaseURL.appendingPathComponent("var/lib/dpkg", isDirectory: true)
        let mntCdromURL = supportBaseURL.appendingPathComponent("mnt/cdrom", isDirectory: true)
        let mntCdromBootURL = mntCdromURL.appendingPathComponent("boot", isDirectory: true)
        let mntCdromEtcURL = mntCdromURL.appendingPathComponent("etc", isDirectory: true)

        for dir in [bootURL, etcURL, aptURL, dpkgURL, mntCdromURL, mntCdromBootURL, mntCdromEtcURL] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // 1. Write ELF64 ARM64/Hybrid kernel images in /boot
        writeELF64BinaryIfNeeded(
            at: bootURL.appendingPathComponent("vmlinuz-6.12.0-28-generic"),
            machine: 0x00B7, // EM_AARCH64 (183)
            entryPoint: 0xffff_8000_8000_0000,
            banner: "Linux version 6.12.0-28-generic-arm64 (Ubuntu 24.04.2 LTS Noble Numbat aarch64)")

        writeELF64BinaryIfNeeded(
            at: bootURL.appendingPathComponent("gentoo"),
            machine: 0x9026,
            entryPoint: 0xffff_fc00_0031_0000,
            banner: "Linux version 6.12.0-28-generic-arm64 / 6.18.52-gentoo-alpha compatibility image")

        writeELF64BinaryIfNeeded(
            at: bootURL.appendingPathComponent("gentoo_nolsa"),
            machine: 0x9026,
            entryPoint: 0xffff_fc00_0101_0000,
            banner: "Linux version 6.12.0-28-generic-arm64 nolsa compatibility image")

        writeELF64BinaryIfNeeded(
            at: bootURL.appendingPathComponent("bootlx"),
            machine: 0x00B7,
            entryPoint: 0x0000_0000_2000_0000,
            banner: "GRUB 2.12-1ubuntu7 arm64-efi / aboot compatibility loader")

        // 2. Write initrd & System.map & config
        let initrdManifest = """
        ZSTD INITRAMFS ARCHIVE (initrd.img-6.12.0-28-generic - Ubuntu 24.04.2 LTS arm64)
        ROOTFS=ubuntu-base-24.04.2-base-arm64.tar.gz
        ARCH=aarch64-linux-gnu
        MODULES=overlay.ko ext4.ko squashfs.ko virtio_blk.ko virtio_net.ko nf_tables.ko tls.ko
        """
        writeTextIfNeeded(initrdManifest, to: bootURL.appendingPathComponent("initrd.img-6.12.0-28-generic"))
        writeTextIfNeeded(initrdManifest, to: bootURL.appendingPathComponent("gentoo.igz"))

        let systemMap = """
        ffff800080000000 T _text
        ffff800080000000 T _stext
        ffff800080010000 T vectors
        ffff800080140000 T __arm64_sys_execve
        ffff800080420000 T schedule
        ffff800080780000 R sys_call_table
        ffff800080b20000 T start_kernel
        ffff800081400000 B __bss_start
        ffff800081680000 B _end
        """
        writeTextIfNeeded(systemMap, to: bootURL.appendingPathComponent("System.map-6.12.0-28-generic"))
        writeTextIfNeeded(systemMap, to: bootURL.appendingPathComponent("System.map-6.18.52-gentoo-alpha"))

        // 3. Write /etc/lsb-release, /etc/debian_version, /etc/apt/sources.list, /var/lib/dpkg/status
        let lsbRelease = """
        DISTRIB_ID=Ubuntu
        DISTRIB_RELEASE=24.04
        DISTRIB_CODENAME=noble
        DISTRIB_DESCRIPTION="Ubuntu 24.04.2 LTS"
        """
        writeTextIfNeeded(lsbRelease, to: etcURL.appendingPathComponent("lsb-release"))
        writeTextIfNeeded("trixie/sid\n", to: etcURL.appendingPathComponent("debian_version"))

        let sourcesList = """
        # Ubuntu 24.04.2 LTS (Noble Numbat) — Official ARM64 Ports Repositories
        deb http://ports.ubuntu.com/ubuntu-ports/ noble main restricted universe multiverse
        deb http://ports.ubuntu.com/ubuntu-ports/ noble-updates main restricted universe multiverse
        deb http://ports.ubuntu.com/ubuntu-ports/ noble-backports main restricted universe multiverse
        deb http://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
        """
        writeTextIfNeeded(sourcesList, to: aptURL.appendingPathComponent("sources.list"))

        let dpkgStatus = """
        Package: base-files
        Status: install ok installed
        Priority: required
        Section: admin
        Architecture: arm64
        Version: 13ubuntu10.2
        Description: Debian/Ubuntu base system miscellaneous files

        Package: bash
        Status: install ok installed
        Priority: required
        Architecture: arm64
        Version: 5.2.21-2ubuntu4
        Description: GNU Bourne Again SHell

        Package: libc6
        Status: install ok installed
        Priority: required
        Architecture: arm64
        Version: 2.39-0ubuntu8.3
        Description: GNU C Library: Shared libraries for arm64

        Package: apt
        Status: install ok installed
        Priority: important
        Architecture: arm64
        Version: 2.7.14build2
        Description: commandline package manager

        Package: python3
        Status: install ok installed
        Priority: important
        Architecture: arm64
        Version: 3.12.3-0ubuntu2
        Description: interactive high-level object-oriented language

        Package: nodejs
        Status: install ok installed
        Priority: optional
        Architecture: arm64
        Version: 20.18.0-1ubuntu1
        Description: evented I/O for V8 javascript

        Package: sqlite3
        Status: install ok installed
        Priority: optional
        Architecture: arm64
        Version: 3.45.1-1ubuntu2
        Description: Command line interface for SQLite 3

        Package: ffmpeg
        Status: install ok installed
        Priority: optional
        Architecture: arm64
        Version: 6.1.1-3ubuntu5
        Description: Tools for transcoding, streaming and playing of multimedia files
        """
        writeTextIfNeeded(dpkgStatus, to: dpkgURL.appendingPathComponent("status"))

        // Keep /etc/aboot.conf and /mnt/cdrom/image.squashfs for backward compatibility with existing tests
        let abootConf = """
        # Bootloader Configuration (Ubuntu 24.04.2 LTS arm64 + Legacy Compatibility)
        0:boot/vmlinuz-6.12.0-28-generic initrd=/boot/initrd.img-6.12.0-28-generic root=/dev/vda1 rw quiet
        1:boot/gentoo initrd=/boot/gentoo.igz root=/dev/ram0 init=/linuxrc looptype=squashfs loop=/image.squashfs cdroot
        3:boot/gentoo_nolsa initrd=/boot/gentoo_nolsa.igz root=/dev/ram0 init=/linuxrc looptype=squashfs loop=/image.squashfs cdroot
        """
        writeTextIfNeeded(abootConf, to: etcURL.appendingPathComponent("aboot.conf"))
        writeTextIfNeeded(abootConf, to: mntCdromEtcURL.appendingPathComponent("aboot.conf"))
        writeSquashFSSuperblockIfNeeded(at: mntCdromURL.appendingPathComponent("image.squashfs"))

        isMounted = true
    }

    private func writeELF64BinaryIfNeeded(at url: URL, machine: UInt16, entryPoint: UInt64, banner: String) {
        var data = Data()
        data.append(contentsOf: [0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let mLo = UInt8(machine & 0xFF)
        let mHi = UInt8((machine >> 8) & 0xFF)
        data.append(contentsOf: [0x02, 0x00, mLo, mHi])
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00])
        var ep = entryPoint.littleEndian
        withUnsafeBytes(of: &ep) { data.append(contentsOf: $0) }
        var phoff: UInt64 = 64
        var shoff: UInt64 = 0
        withUnsafeBytes(of: &phoff) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &shoff) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00,
                                 0x40, 0x00, 0x38, 0x00,
                                 0x01, 0x00, 0x40, 0x00,
                                 0x00, 0x00, 0x00, 0x00])
        if let bannerBytes = ("\n" + banner + "\n").data(using: .utf8) {
            data.append(bannerBytes)
        }
        try? data.write(to: url, options: .atomic)
    }

    private func writeSquashFSSuperblockIfNeeded(at url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        var data = Data([0x68, 0x73, 0x71, 0x73, 0x10, 0x48, 0x00, 0x00])
        let manifest = "\nUBUNTU BASE 24.04.2 LTS (NOBLE NUMBAT) ARM64 ROOTFS IMAGE\n"
        if let bytes = manifest.data(using: .utf8) { data.append(bytes) }
        try? data.write(to: url, options: .atomic)
    }

    private func writeTextIfNeeded(_ text: String, to url: URL) {
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - Rich Virtual `/proc/*` Files for Ubuntu 24.04 ARM64

    func virtualProcContent(for normalizedPath: String) -> String? {
        switch normalizedPath {
        case "/proc/version":
            return "Linux version 6.12.0-28-generic-arm64 (buildd@bos03-arm64-042) (aarch64-linux-gnu-gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0, GNU ld (GNU Binutils for Ubuntu) 2.42) #28-Ubuntu SMP PREEMPT_DYNAMIC [6.18.52-gentoo-alpha compat]"
        case "/proc/cmdline":
            return "BOOT_IMAGE=\(activeKernelImage) initrd=\(activeInitramfs) root=UUID=ubuntu-2404-noble-arm64 rw quiet splash"
        case "/proc/cpuinfo":
            let cores = ProcessInfo.processInfo.activeProcessorCount
            return (0..<cores).map { i in
                """
                processor\t: \(i)
                Model name\t: Apple Silicon ARMv8.6-A (Ubuntu 24.04 LTS arm64)
                BogoMIPS\t: 48.00
                Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm jscvt fcma lrcpc dcpop sha3 asimddp sha512 asimdfhm dit uscat ilrcpc flagm sb paca pacg dcpodp flagm2 frint
                CPU implementer\t: 0x61
                CPU architecture: 8
                CPU variant\t: 0x2
                CPU part\t: 0x028
                CPU revision\t: 0
                """
            }.joined(separator: "\n\n")
        case "/proc/mounts":
            return """
            /dev/vda1 / ext4 rw,relatime,errors=remount-ro 0 0
            overlay /home/astral overlay rw,relatime,lowerdir=/,upperdir=/home/astral 0 0
            proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0
            sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
            devtmpfs /dev devtmpfs rw,nosuid,size=4096000k,nr_inodes=512000,mode=755 0 0
            tmpfs /tmp tmpfs rw,nosuid,nodev 0 0
            """
        case "/proc/filesystems":
            return "nodev\tsysfs\nnodev\ttmpfs\nnodev\tproc\nnodev\toverlay\n\text4\n\txfs\n\tsquashfs\n\tiso9660"
        case "/proc/modules":
            return loadedModules.map {
                "\($0.name) \($0.size) \($0.usedByCount) \($0.usedBy) Live 0xffff800080c00000"
            }.joined(separator: "\n")
        default:
            return nil
        }
    }

    // MARK: - Ubuntu & Kernel Commands

    func runDmesg(_ args: [String]) -> SandboxResult {
        if args.contains("-c") || args.contains("-C") {
            resetDmesgBuffer()
            return .ok()
        }
        return .ok(dmesgBuffer.joined(separator: "\n"))
    }

    func runLsbRelease(_ args: [String]) -> SandboxResult {
        if args.contains("-cs") || args.contains("-c") {
            return .ok("noble")
        }
        if args.contains("-rs") || args.contains("-r") {
            return .ok("24.04")
        }
        if args.contains("-ds") || args.contains("-d") {
            return .ok("Ubuntu 24.04.2 LTS")
        }
        return .ok(
            """
            No LSB modules are available.
            Distributor ID:\tUbuntu
            Description:\tUbuntu 24.04.2 LTS
            Release:\t24.04
            Codename:\tnoble
            Architecture:\tarm64 (aarch64)
            """)
    }

    func runDpkg(_ args: [String], installedPackages: inout Set<String>) -> SandboxResult {
        if args.contains("--print-architecture") {
            return .ok("arm64")
        }
        if args.contains("-l") || args.isEmpty {
            let sorted = installedPackages.sorted()
            var lines = [
                "Desired=Unknown/Install/Remove/Purge/Hold",
                "| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend",
                "|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)",
                "||/ Name                  Version               Architecture Description",
                "+++-=====================-=====================-============-============================================="
            ]
            for pkg in sorted {
                let nameCol = pkg.padding(toLength: 21, withPad: " ", startingAt: 0)
                lines.append("ii  \(nameCol) 24.04-1ubuntu1        arm64        Ubuntu 24.04 LTS arm64 package (\(pkg))")
            }
            return .ok(lines.joined(separator: "\n"))
        }
        if args.contains("-i") || args.contains("--install") {
            let pkg = args.last(where: { !$0.hasPrefix("-") }) ?? "package.deb"
            let clean = ((pkg as NSString).lastPathComponent as NSString).deletingPathExtension
            installedPackages.insert(clean)
            appendKernelLog("dpkg: installed \(clean) (arm64)")
            return .ok("Selecting previously unselected package \(clean).\nUnpacking \(clean) ...\nSetting up \(clean) ...")
        }
        if args.contains("-s") || args.contains("--status") {
            let pkg = args.last(where: { !$0.hasPrefix("-") }) ?? "base-files"
            return .ok(
                """
                Package: \(pkg)
                Status: install ok installed
                Priority: important
                Architecture: arm64
                Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
                Version: 24.04.2-1ubuntu1
                """)
        }
        return .ok("Debian 'dpkg' package management program version 1.22.6 (arm64).")
    }

    func runAptCache(_ args: [String], installedPackages: Set<String>) -> SandboxResult {
        let sub = args.first?.lowercased() ?? "search"
        let query = args.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? "ubuntu"
        if sub == "show" || sub == "policy" {
            let isInst = installedPackages.contains(query)
            return .ok(
                """
                Package: \(query)
                Architecture: arm64
                Version: 24.04.2-1ubuntu1
                Priority: optional
                Section: universe/utils
                Origin: Ubuntu
                Installed: \(isInst ? "24.04.2-1ubuntu1" : "(none)")
                Candidate: 24.04.2-1ubuntu1
                Version table:
                   24.04.2-1ubuntu1 500
                      500 http://ports.ubuntu.com/ubuntu-ports noble/main arm64 Packages
                """)
        }
        return .ok(
            """
            \(query) - Ubuntu 24.04 LTS (Noble Numbat) arm64 package for \(query)
            lib\(query)-dev - Development headers and static libraries for \(query) (arm64)
            python3-\(query) - Python 3 bindings for \(query)
            """)
    }

    func runUfw(_ args: [String]) -> SandboxResult {
        let sub = args.first?.lowercased() ?? "status"
        switch sub {
        case "enable":
            ufwEnabled = true
            appendKernelLog("ufw: firewall enabled (nf_tables arm64)")
            return .ok("Firewall is active and enabled on system startup")
        case "disable":
            ufwEnabled = false
            appendKernelLog("ufw: firewall disabled")
            return .ok("Firewall stopped and disabled on system startup")
        case "allow":
            let rule = args.dropFirst().joined(separator: " ")
            if !rule.isEmpty { ufwRules.append("\(rule) ALLOW IN Anywhere") }
            return .ok("Rule added\nRule added (v6)")
        default:
            if !ufwEnabled { return .ok("Status: inactive") }
            var out = ["Status: active", "", "To                         Action      From", "--                         ------      ----"]
            out.append(contentsOf: ufwRules)
            return .ok(out.joined(separator: "\n"))
        }
    }

    func runJournalctl(_ args: [String]) -> SandboxResult {
        let lines = dmesgBuffer.suffix(20).map { line -> String in
            "Nov 07 05:15:00 astra-os kernel: \(line)"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    func runLsmod() -> SandboxResult {
        var lines = ["Module                  Size  Used by"]
        for m in loadedModules {
            let paddedName = m.name.padding(toLength: 23, withPad: " ", startingAt: 0)
            let paddedSize = String(m.size).leftPadding(toLength: 6)
            lines.append("\(paddedName) \(paddedSize)  \(m.usedByCount) \(m.usedBy == "-" ? "" : m.usedBy)")
        }
        return .ok(lines.joined(separator: "\n"))
    }

    func runModprobe(_ args: [String]) -> SandboxResult {
        let remove = args.contains("-r")
        let names = args.filter { !$0.hasPrefix("-") }
        guard let name = names.first else {
            return .error("usage: modprobe [-r] <module_name>")
        }
        let clean = name.replacingOccurrences(of: ".ko", with: "").replacingOccurrences(of: "-", with: "_")
        if remove {
            loadedModules.removeAll { $0.name == clean }
            appendKernelLog("modprobe: unloaded module '\(clean)'")
            return .ok("modprobe: removed module \(clean)")
        }
        if !loadedModules.contains(where: { $0.name == clean }) {
            loadedModules.insert(
                KernelModule(
                    name: clean,
                    size: 49152,
                    usedByCount: 0,
                    usedBy: "-",
                    description: "Dynamically loaded Ubuntu 24.04 arm64 kernel module (\(clean).ko)"),
                at: 0)
            appendKernelLog("\(clean): module loaded into kernel \(Self.kernelRelease)")
        }
        return .ok()
    }

    func runSysctl(_ args: [String]) -> SandboxResult {
        if args.contains("-a") || args.isEmpty {
            let sorted = sysctlParameters.keys.sorted().map { "\($0) = \(sysctlParameters[$0] ?? "")" }
            return .ok(sorted.joined(separator: "\n"))
        }
        let writeMode = args.contains("-w")
        let operands = args.filter { !$0.hasPrefix("-") }
        var out: [String] = []
        for op in operands {
            if let eq = op.firstIndex(of: "=") {
                let key = String(op[..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(op[op.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                sysctlParameters[key] = val
                appendKernelLog("sysctl: set \(key)=\(val)")
                out.append("\(key) = \(val)")
            } else if writeMode {
                return .error("sysctl: '\(op)' must be of form key=value")
            } else if let val = sysctlParameters[op] {
                out.append("\(op) = \(val)")
            } else {
                return .error("sysctl: cannot stat /proc/sys/\(op.replacingOccurrences(of: ".", with: "/")): No such file or directory")
            }
        }
        return .ok(out.joined(separator: "\n"))
    }

    func runAboot(_ args: [String]) -> SandboxResult {
        let sub = args.first ?? "status"
        switch sub {
        case "status", "list", "-l":
            return .ok(
                """
                GRUB 2.12-1ubuntu7 (arm64-efi) — Ubuntu 24.04.2 LTS (Noble Numbat) Boot Manager
                RootFS Archive : \(Self.isoFileName) (\(Self.isoExactSizeBytes) bytes)
                Active Slot    : \(activeBootSlot)
                Active Kernel  : \(activeKernelImage) (\(Self.kernelRelease))
                Active Initrd  : \(activeInitramfs)
                Boot Entries:
                  [0] Ubuntu 24.04.2 LTS (6.12.0-28-generic-arm64 — Default Native ARM64)
                  [3] Ubuntu 24.04.2 LTS (Recovery / High-Memory Server Mode)
                """)
        case "boot", "select":
            let slot = args.dropFirst().first.flatMap { Int($0) } ?? 0
            activeBootSlot = slot
            if slot >= 3 {
                activeKernelImage = "/boot/vmlinuz-6.12.0-28-generic-recovery"
            } else {
                activeKernelImage = "/boot/vmlinuz-6.12.0-28-generic"
            }
            appendKernelLog("grub-boot: switched active kernel to \(activeKernelImage) (slot \(slot))")
            return .ok("grub-boot: selected slot \(slot) -> \(activeKernelImage)")
        default:
            return .ok("usage: aboot [status | list | boot <0..5>]")
        }
    }

    func runOpenRC(command: String, args: [String]) -> SandboxResult {
        switch command {
        case "rc-status":
            let grouped = Dictionary(grouping: openRCServices, by: { $0.runlevel })
            var out: [String] = []
            for level in ["system", "default", "graphical"] {
                out.append("Target: \(level)")
                for svc in grouped[level] ?? [] {
                    let padded = svc.name.padding(toLength: 24, withPad: " ", startingAt: 0)
                    out.append("  \(padded) [  \(svc.status)  ]")
                }
            }
            return .ok(out.joined(separator: "\n"))
        case "rc-service":
            guard args.count >= 2 else {
                return .error("usage: rc-service <service> <start|stop|restart|status>")
            }
            let svcName = args[0]
            let action = args[1]
            if let idx = openRCServices.firstIndex(where: { $0.name == svcName }) {
                switch action {
                case "start", "restart":
                    openRCServices[idx].status = "started"
                    appendKernelLog("systemd: service '\(svcName)' started")
                    return .ok(" * Starting \(svcName) ... [ ok ]")
                case "stop":
                    openRCServices[idx].status = "stopped"
                    appendKernelLog("systemd: service '\(svcName)' stopped")
                    return .ok(" * Stopping \(svcName) ... [ ok ]")
                default:
                    return .ok(" * status: \(openRCServices[idx].status)")
                }
            } else {
                openRCServices.append(OpenRCService(name: svcName, runlevel: "default", status: "started"))
                return .ok(" * Starting \(svcName) ... [ ok ]")
            }
        default:
            return .ok(" * service \(args.first ?? "astral-agentd") enabled")
        }
    }

    func runEmerge(_ args: [String], installedPackages: inout Set<String>) -> SandboxResult {
        if args.contains("--info") || args.contains("--version") {
            return .ok(
                """
                Ubuntu Base 24.04.2 LTS (Noble Numbat) — APT 2.7.14 (arm64) + Portage Compatibility Layer
                System uname: Linux-6.12.0-28-generic-arm64-aarch64-with-glibc2.39
                Target Triplet: aarch64-linux-gnu (compat: alpha-unknown-linux-gnu)
                Compiler: gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0
                glibc: 2.39-0ubuntu8.3
                Python: 3.12.3
                """)
        }
        let pkgs = args.filter { !$0.hasPrefix("-") }
        for pkg in pkgs {
            let clean = pkg.components(separatedBy: "/").last ?? pkg
            installedPackages.insert(clean)
        }
        return .ok("Installed \(pkgs.joined(separator: ", ")) into Ubuntu 24.04 LTS (arm64).")
    }

    func runLsblk() -> SandboxResult {
        return .ok(
            """
            NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
            vda    254:0    0    64G  0 disk 
            ├─vda1 254:1    0   512M  0 part /boot/efi
            ├─vda2 254:2    0    16G  0 part /
            └─vda3 254:3    0  47.5G  0 part /home/astral
            loop0    7:0    0    30M  1 loop /mnt/cdrom
            """)
    }

    func runBlkid() -> SandboxResult {
        return .ok(
            """
            /dev/vda1: LABEL="EFI" UUID="2404-ABCD" BLOCK_SIZE="512" TYPE="vfat"
            /dev/vda2: LABEL="ubuntu-base-24.04" UUID="a4f21b90-2404-4e92-8812-001122334455" BLOCK_SIZE="4096" TYPE="ext4"
            /dev/vda3: LABEL="astral-workspace" UUID="f9e8d7c6-b5a4-4321-9876-543210fedcba" BLOCK_SIZE="4096" TYPE="ext4"
            """)
    }

    func runReadelf(_ args: [String], resolvedURL: (String) -> URL?) -> SandboxResult {
        let target = args.last(where: { !$0.hasPrefix("-") }) ?? "/boot/vmlinuz-6.12.0-28-generic"
        let isAlphaCompat = target.contains("gentoo")
        let machineLabel = isAlphaCompat ? "Alpha (0x9026) / AArch64 Hybrid" : "AArch64 (0xb7) [Alpha (0x9026) compat]"
        return .ok(
            """
            ELF Header (\(target)):
              Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
              Class:                             ELF64
              Data:                              2's complement, little endian
              Version:                           1 (current)
              OS/ABI:                            UNIX - GNU
              Type:                              EXEC (Executable file)
              Machine:                           \(machineLabel)
              Entry point address:               0xffff800080000000
              Start of program headers:          64 (bytes into file)
              Size of this header:               64 (bytes)
            """)
    }

    func runUnsquashfs(_ args: [String], homeURL: URL, supportBaseURL: URL) -> SandboxResult {
        if args.contains("-l") || args.contains("-ll") {
            return .ok(
                """
                Ubuntu Base 24.04.2 LTS (Noble Numbat) arm64 RootFS Contents:
                /bin/bash
                /bin/ls
                /boot/vmlinuz-6.12.0-28-generic
                /etc/os-release
                /etc/lsb-release
                /etc/apt/sources.list
                /lib/aarch64-linux-gnu/libc.so.6
                /usr/bin/apt
                /usr/bin/dpkg
                /usr/bin/python3.12
                /var/lib/dpkg/status
                """)
        }
        return .ok("Extracted Ubuntu Base 24.04.2 LTS arm64 rootfs files into Workspace.")
    }

    func runIsoinfo(_ args: [String]) -> SandboxResult {
        return .ok(
            """
            Ubuntu Base 24.04.2 LTS (Noble Numbat) Official ARM64 RootFS Archive
            Archive Name : \(Self.isoFileName)
            Architecture : arm64 (aarch64-linux-gnu)
            Publisher    : Canonical Ltd.
            Kernel       : \(Self.kernelRelease)
            """)
    }

    func setProbeStatus(_ status: String) {
        isoProbeStatus = status
    }
}

private extension String {
    func leftPadding(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
