import SwiftUI

// MARK: - Linux Desktop controller (X.Org :0 — Linux Alpha)

/// Drives the X.Org-style Linux Alpha desktop shown in the Terminal's
/// Desktop tab. Shell commands (`startx`, `xdg-open`, the `desktop`
/// command family...) route through this controller: they pick the
/// "launched app", remember targets (URL / file / directory) and post
/// `.openLinuxDesktop` so the Terminal view switches to the Desktop tab.
@MainActor
final class LinuxDesktopController: ObservableObject {

    static let shared = LinuxDesktopController()

    /// The X "applications" launchable on the Linux Alpha desktop.
    enum DesktopApp: String, CaseIterable, Identifiable {
        case terminal
        case fileManager
        case codeStudio
        case browser
        case systemMonitor

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .terminal: return "Terminal"
            case .fileManager: return "Files"
            case .codeStudio: return "Code"
            case .browser: return "Browser"
            case .systemMonitor: return "System"
            }
        }

        var iconName: String {
            switch self {
            case .terminal: return AstralIcons.terminal
            case .fileManager: return AstralIcons.folder
            case .codeStudio: return AstralIcons.fileCode
            case .browser: return AstralIcons.globe
            case .systemMonitor: return AstralIcons.cpu
            }
        }
    }

    /// The app currently shown inside the desktop window area.
    @Published private(set) var activeApp: DesktopApp = .terminal
    /// Whether `startx` has booted the X server (desktop session active).
    @Published private(set) var sessionActive = false
    /// Directory the Files window is browsing (`xdg-open <dir>`); the shell
    /// keeps this in sync with its working directory.
    @Published var currentDirectoryPath = "/home/astral"
    /// URL the Browser window should show (`xdg-open <url>`).
    @Published private(set) var browserTargetURL: String?
    /// File open in the Code window (`xdg-open <file>`).
    @Published private(set) var openFileName: String?
    /// Text content of the file open in the Code window.
    @Published private(set) var openFileContent: String?

    private init() {}

    /// Boots the X server if needed, switches to `app` and posts
    /// `.openLinuxDesktop` so the Terminal jumps to the Desktop tab.
    func launch(_ app: DesktopApp) {
        activeApp = app
        sessionActive = true
        AlphaLinuxSubsystem.shared.appendKernelLog(
            "Xorg: window \(app.rawValue) mapped on :0 (Linux Alpha desktop session)")
        NotificationCenter.default.post(name: .openLinuxDesktop, object: nil)
    }

    /// Shuts the X session down (`startx` exit / logout).
    func endSession() {
        sessionActive = false
        AlphaLinuxSubsystem.shared.appendKernelLog(
            "Xorg: session closed, returning to SRM console")
    }

    /// Opens a directory in the Files window.
    func openDirectory(_ path: String) {
        currentDirectoryPath = path
        launch(.fileManager)
    }

    /// Opens a URL in the desktop Browser window.
    func openURLInBrowser(_ urlString: String) {
        browserTargetURL = urlString
        launch(.browser)
    }

    /// Opens a file in the desktop Code window.
    func openFileInEditor(name: String, content: String) {
        openFileName = name
        openFileContent = content
        launch(.codeStudio)
    }
}

// MARK: - Linux Desktop view (X.Org :0 — Linux Alpha)

/// The X.Org-style Linux Alpha desktop: a window manager bar, an app dock
/// of X clients (Terminal, Files, Code, Browser, System) and a window area
/// that renders whichever client `startx` / `xdg-open` launched. Data comes
/// straight from `AlphaLinuxSubsystem` (kernel modules, OpenRC services,
/// dmesg ring buffer) so the desktop always mirrors the live kernel state.
struct LinuxDesktopView: View {

    @ObservedObject private var controller = LinuxDesktopController.shared
    @ObservedObject private var alpha = AlphaLinuxSubsystem.shared
    @State private var clock = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        ZStack {
            // Desktop wallpaper — deep space with a subtle Alpha grid.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.10),
                    Color(red: 0.07, green: 0.09, blue: 0.18),
                    Color(red: 0.04, green: 0.05, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            if controller.sessionActive {
                VStack(spacing: 0) {
                    windowManagerBar
                    windowArea
                    dockStrip
                }
            } else {
                loggedOutView
            }
        }
        .onReceive(timer) { date in
            clock = date
        }
    }

    // MARK: Window manager bar

    private var windowManagerBar: some View {
        HStack(spacing: 10) {
            AIcon(
                AstralIcons.terminal,
                size: 13,
                strokeWidth: 2.1,
                color: AstralTheme.orbGreen)
            Text("X.Org :0 · Linux Alpha")
                .font(AstralTheme.mono(11).weight(.semibold))
                .foregroundStyle(AstralTheme.textPrimary)

            Spacer()

            Text(alpha.kernelRelease)
                .font(AstralTheme.mono(10))
                .foregroundStyle(AstralTheme.textSecondary)

            Text(clock, style: .time)
                .font(AstralTheme.mono(10))
                .foregroundStyle(AstralTheme.textSecondary)

            Button {
                controller.endSession()
            } label: {
                Text("Logout")
                    .font(AstralTheme.mono(10).weight(.semibold))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidCapsule()
            }
            .buttonStyle(PressableOrbStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: Logged-out (SRM console) state

    private var loggedOutView: some View {
        VStack(spacing: 14) {
            AIcon(
                AstralIcons.cpu,
                size: 40,
                strokeWidth: 1.6,
                color: AstralTheme.orbGreen)
            Text("SRM Console · X server not running")
                .font(AstralTheme.mono(13).weight(.semibold))
                .foregroundStyle(AstralTheme.textPrimary)
            Text("Type `startx` in the shell to boot the Linux Alpha desktop.")
                .font(AstralTheme.mono(11))
                .foregroundStyle(AstralTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                controller.launch(.terminal)
            } label: {
                HStack(spacing: 8) {
                    AIcon(
                        AstralIcons.terminal,
                        size: 14,
                        strokeWidth: 2,
                        color: .white)
                    Text("startx")
                        .font(AstralTheme.mono(12).weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .liquidGlass(
                    in: Capsule(),
                    tint: AstralTheme.orbGreen.opacity(0.35),
                    interactive: true)
            }
            .buttonStyle(PressableOrbStyle())
        }
        .padding(24)
    }

    // MARK: Window area

    private var windowArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Client title bar.
            HStack(spacing: 8) {
                Text(controller.activeApp.displayName)
                    .font(AstralTheme.mono(11).weight(.semibold))
                    .foregroundStyle(AstralTheme.textPrimary)
                Spacer()
                AIcon(
                    AstralIcons.cpu,
                    size: 11,
                    strokeWidth: 2,
                    color: AstralTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AstralTheme.actionFill.opacity(0.6))

            Divider()

            // Client content.
            Group {
                switch controller.activeApp {
                case .terminal: terminalClient
                case .fileManager: filesClient
                case .codeStudio: codeClient
                case .browser: browserClient
                case .systemMonitor: systemClient
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    // MARK: X clients

    private var terminalClient: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("root@astra-os:~# uname -a")
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(AstralTheme.textSecondary)
                Text("Linux astra-os \(alpha.kernelRelease) \(alpha.kernelVersionString) alpha EV68CB (21264C) / aarch64 GNU/Linux")
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .textSelection(.enabled)

                Divider().padding(.vertical, 6)

                ForEach(Array(alpha.dmesgBuffer.suffix(18).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(AstralTheme.mono(10))
                        .foregroundStyle(AstralTheme.textSecondary.opacity(0.85))
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private var filesClient: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.currentDirectoryPath)
                    .font(AstralTheme.mono(11).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .padding(.bottom, 8)

                ForEach(fhsEntries, id: \.path) { entry in
                    HStack(spacing: 10) {
                        AIcon(
                            entry.isDirectory ? AstralIcons.folder : AstralIcons.file,
                            size: 14,
                            strokeWidth: 1.9,
                            color: entry.isDirectory ? AstralTheme.accent : AstralTheme.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(AstralTheme.mono(11).weight(.medium))
                                .foregroundStyle(AstralTheme.textPrimary)
                            Text(entry.detail)
                                .font(AstralTheme.mono(9.5))
                                .foregroundStyle(AstralTheme.textSecondary)
                        }
                        Spacer()
                        Text(entry.perms)
                            .font(AstralTheme.mono(9.5))
                            .foregroundStyle(AstralTheme.textSecondary.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .liquidCapsule()
                }
            }
            .padding(12)
        }
    }

    private var codeClient: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(controller.openFileName ?? "untitled")
                    .font(AstralTheme.mono(11).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                Text(controller.openFileContent ?? "// No file open — use `xdg-open <file>` in the shell")
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    private var browserClient: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                AIcon(
                    AstralIcons.globe,
                    size: 14,
                    strokeWidth: 2,
                    color: AstralTheme.accent)
                Text(controller.browserTargetURL ?? "about:blank")
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidCapsule()

            if let target = normalizedBrowserURL {
                Link(destination: target) {
                    Label {
                        Text("Open in Astral Browser")
                            .font(AstralTheme.mono(11).weight(.semibold))
                    } icon: {
                        AIcon(
                            AstralIcons.globe,
                            size: 13,
                            strokeWidth: 2,
                            color: .white)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .liquidGlass(
                        in: Capsule(),
                        tint: AstralTheme.accent.opacity(0.35),
                        interactive: true)
                }
                .buttonStyle(PressableOrbStyle())
            } else {
                Text("xdg-open <url> from the shell loads pages here.")
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.textSecondary)
            }

            Spacer()
        }
        .padding(12)
    }

    private var systemClient: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                statRow("Kernel", "\(alpha.kernelRelease) \(alpha.kernelVersionString)")
                statRow("SRM firmware", alpha.srmFirmwareVersion)
                statRow("Boot image", alpha.activeKernelImage)
                statRow("ISO", AlphaLinuxSubsystem.isoFileName)
                statRow("Status", alpha.isoProbeStatus)
                statRow("Modules loaded", "\(alpha.loadedModules.count) kernel modules")
                statRow("OpenRC services", "\(alpha.openRCServices.filter { $0.status == "started" }.count) started / \(alpha.openRCServices.count) total")

                Divider()

                Text("dmesg | tail")
                    .font(AstralTheme.mono(10.5).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                ForEach(Array(alpha.dmesgBuffer.suffix(10).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(AstralTheme.mono(9.5))
                        .foregroundStyle(AstralTheme.textSecondary.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    // MARK: Dock strip

    private var dockStrip: some View {
        HStack(spacing: 10) {
            ForEach(LinuxDesktopController.DesktopApp.allCases) { app in
                Button {
                    controller.launch(app)
                } label: {
                    VStack(spacing: 4) {
                        AIcon(
                            app.iconName,
                            size: 18,
                            strokeWidth: 1.9,
                            color: controller.activeApp == app
                                ? AstralTheme.orbGreen
                                : AstralTheme.textSecondary)
                        Text(app.displayName)
                            .font(AstralTheme.mono(8.5))
                            .foregroundStyle(
                                controller.activeApp == app
                                    ? AstralTheme.textPrimary
                                    : AstralTheme.textSecondary)
                    }
                    .frame(width: 62)
                    .padding(.vertical, 8)
                    .liquidGlass(
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tint: controller.activeApp == app
                            ? AstralTheme.orbGreen.opacity(0.22)
                            : .clear,
                        interactive: true)
                }
                .buttonStyle(PressableOrbStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Helpers

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.textPrimary.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private var normalizedBrowserURL: URL? {
        guard var target = controller.browserTargetURL, !target.isEmpty else { return nil }
        if !target.hasPrefix("http://") && !target.hasPrefix("https://") {
            target = "https://" + target
        }
        return URL(string: target)
    }

    /// The virtual FHS layout shown by the Files client.
    private struct FHSEntry {
        let path: String
        let name: String
        let detail: String
        let perms: String
        var isDirectory: Bool { !perms.hasPrefix("-") }
    }

    private var fhsEntries: [FHSEntry] {
        [
            FHSEntry(path: "/boot", name: "boot", detail: "gentoo kernel + initramfs + aboot.conf", perms: "drwxr-xr-x"),
            FHSEntry(path: "/etc", name: "etc", detail: "portage, aboot.conf, inittab, fstab", perms: "drwxr-xr-x"),
            FHSEntry(path: "/home", name: "home", detail: "astral — the persistent workspace", perms: "drwxr-xr-x"),
            FHSEntry(path: "/mnt/cdrom", name: "mnt/cdrom", detail: "image.squashfs (ISO-9660, read-only)", perms: "dr-xr-xr-x"),
            FHSEntry(path: "/proc", name: "proc", detail: "kernel virtual filesystem", perms: "dr-xr-xr-x"),
            FHSEntry(path: "/sys", name: "sys", detail: "sysfs device tree", perms: "dr-xr-xr-x"),
            FHSEntry(path: "/usr", name: "usr", detail: "userland + alpha-unknown-linux-gnu toolchain", perms: "drwxr-xr-x"),
            FHSEntry(path: "/var", name: "var", detail: "db/pkg — the Portage database", perms: "drwxr-xr-x"),
            FHSEntry(path: "/boot/gentoo", name: "gentoo", detail: "kernel image (\(alpha.kernelRelease))", perms: "-rw-r--r--"),
            FHSEntry(path: "/boot/gentoo.igz", name: "gentoo.igz", detail: "initramfs (gzip cpio archive)", perms: "-rw-r--r--")
        ]
    }
}
