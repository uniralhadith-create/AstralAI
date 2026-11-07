import SwiftUI
import WebKit
import AVKit

// MARK: - Linux Desktop Window Manager & Controller

enum LinuxDesktopApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case fileManager = "Files"
    case codeStudio = "Code IDE"
    case browser = "Browser"
    case systemMonitor = "System & ISO"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "xterm — root@astra-os"
        case .fileManager: return "Thunar File Manager"
        case .codeStudio: return "Astra Code Studio"
        case .browser: return "Falkon X11 Web Browser"
        case .systemMonitor: return "Kernel & 265 MB ISO Center"
        }
    }

    var shortLabel: String {
        switch self {
        case .terminal: return "Terminal"
        case .fileManager: return "Files"
        case .codeStudio: return "Code"
        case .browser: return "Web"
        case .systemMonitor: return "ISO / Sys"
        }
    }

    var iconName: String {
        switch self {
        case .terminal: return AstralIcons.terminal
        case .fileManager: return AstralIcons.folder
        case .codeStudio: return AstralIcons.fileCode
        case .browser: return AstralIcons.compass
        case .systemMonitor: return AstralIcons.cpu
        }
    }

    var accentColor: Color {
        switch self {
        case .terminal: return AstralTheme.orbGreen
        case .fileManager: return Color(red: 0.35, green: 0.68, blue: 0.98)
        case .codeStudio: return Color(red: 0.72, green: 0.52, blue: 0.98)
        case .browser: return Color(red: 0.28, green: 0.82, blue: 0.88)
        case .systemMonitor: return Color(red: 0.98, green: 0.65, blue: 0.28)
        }
    }
}

@MainActor
final class LinuxDesktopController: ObservableObject {

    static let shared = LinuxDesktopController()

    @Published var activeApp: LinuxDesktopApp? = .systemMonitor
    @Published var openApps: Set<LinuxDesktopApp> = [.terminal, .fileManager, .systemMonitor]
    @Published var showAppLauncher: Bool = false

    // File Manager state
    @Published var currentDirectoryPath: String = "/home/astral"
    @Published var previewFileTitle: String?
    @Published var previewFileContent: String?

    // Code Studio state
    @Published var editorFileName: String = "main.py"
    @Published var editorCode: String = """
    import platform, os

    print("=== Astral AI · Linux Alpha Desktop Python 3.12 ===")
    print("Working directory:", os.getcwd())
    with open("desktop_output.txt", "w") as f:
        f.write("Generated from Linux Alpha Desktop IDE!\\n")
    print("Saved desktop_output.txt to Workspace.")
    """
    @Published var editorOutput: String = ""
    @Published var editorRunning: Bool = false

    // Browser state
    @Published var browserURLString: String = "https://alphalinux.org/wiki/status"

    private init() {}

    func launch(_ app: LinuxDesktopApp) {
        openApps.insert(app)
        activeApp = app
        showAppLauncher = false
    }

    func close(_ app: LinuxDesktopApp) {
        openApps.remove(app)
        if activeApp == app {
            activeApp = openApps.first
        }
    }

    func openFileInEditor(name: String, content: String) {
        editorFileName = name
        editorCode = content
        launch(.codeStudio)
    }

    func openURLInBrowser(_ url: String) {
        browserURLString = url
        launch(.browser)
    }
}

// MARK: - Complete Interactive Linux Alpha Desktop Environment

struct LinuxDesktopView: View {
    @ObservedObject private var desktop = LinuxDesktopController.shared
    @ObservedObject private var shell = SandboxShell.shared
    @ObservedObject private var alpha = AlphaLinuxSubsystem.shared
    @ObservedObject private var isoManager = AlphaFullISOManager.shared

    @State private var shellCommandDraft: String = ""

    var body: some View {
        ZStack(alignment: .top) {
            desktopWallpaper

            VStack(spacing: 0) {
                topSystemPanel

                ZStack {
                    desktopShortcutsGrid
                        .padding(14)

                    if let active = desktop.activeApp {
                        desktopWindowContainer(for: active)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    if desktop.showAppLauncher {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.smooth(duration: 0.18)) {
                                    desktop.showAppLauncher = false
                                }
                            }

                        VStack {
                            HStack {
                                appLauncherMenu
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(.top, 6)
                        .padding(.leading, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomDockBar
            }
        }
        .onAppear {
            isoManager.refreshISOState()
        }
    }

    // MARK: - Wallpaper

    private var desktopWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.11),
                    Color(red: 0.06, green: 0.10, blue: 0.16),
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            Circle()
                .fill(AstralTheme.orbGreen.opacity(0.11))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -90, y: -110)

            Circle()
                .fill(Color(red: 0.32, green: 0.58, blue: 0.96).opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 55)
                .offset(x: 110, y: 90)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top X11/Wayland System Bar

    private var topSystemPanel: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                    desktop.showAppLauncher.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    AstralComputerIcon(
                        size: 13,
                        color: .white,
                        accentColor: AstralTheme.orbGreen,
                        isActive: true)
                    Text("Astra-Alpha")
                        .font(AstralTheme.headline(11.5))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(desktop.showAppLauncher ? AstralTheme.orbGreen.opacity(0.28) : Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            Text("X.Org :0 · \(AlphaLinuxSubsystem.kernelRelease)")
                .font(AstralTheme.mono(10))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                desktop.launch(.systemMonitor)
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(isoManager.fullISOReady ? AstralTheme.orbGreen : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isoManager.isDownloading
                         ? String(format: "ISO %.0f%%", isoManager.downloadProgress * 100)
                         : (isoManager.fullISOReady ? "252.7M ISO Mounted" : "252.7M ISO"))
                        .font(AstralTheme.mono(9.5).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(AstralTheme.mono(10.5).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
    }

    // MARK: - Applications Menu

    private var appLauncherMenu: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AstralComputerIcon(size: 16, color: .white, accentColor: AstralTheme.orbGreen, isActive: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Linux Alpha Desktop")
                        .font(AstralTheme.headline(12.5))
                        .foregroundStyle(.white)
                    Text("Gentoo Alpha · \(AlphaLinuxSubsystem.kernelRelease)")
                        .font(AstralTheme.mono(9.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().overlay(Color.white.opacity(0.1))

            ForEach(LinuxDesktopApp.allCases) { app in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        desktop.launch(app)
                    }
                } label: {
                    HStack(spacing: 10) {
                        AIcon(app.iconName, size: 14, strokeWidth: 2.1, color: app.accentColor)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6).fill(app.accentColor.opacity(0.16)))
                        Text(app.title)
                            .font(AstralTheme.body(12.5))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }

    // MARK: - Desktop Icons Grid

    private var desktopShortcutsGrid: some View {
        let columns = [
            GridItem(.adaptive(minimum: 78, maximum: 96), spacing: 14)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                desktopShortcut(title: "Home\n/home/astral", icon: AstralIcons.folder, tint: Color(red: 0.35, green: 0.68, blue: 0.98)) {
                    desktop.currentDirectoryPath = "/home/astral"
                    desktop.launch(.fileManager)
                }
                desktopShortcut(title: "Kernel\n/boot", icon: AstralIcons.cpu, tint: AstralTheme.orbGreen) {
                    desktop.currentDirectoryPath = "/boot"
                    desktop.launch(.fileManager)
                }
                desktopShortcut(title: "ISO Mount\n/mnt/cdrom", icon: AstralIcons.sparkles, tint: .orange) {
                    desktop.currentDirectoryPath = "/mnt/cdrom"
                    desktop.launch(.fileManager)
                }
                desktopShortcut(title: "Terminal\nxterm", icon: AstralIcons.terminal, tint: AstralTheme.orbGreen) {
                    desktop.launch(.terminal)
                }
                desktopShortcut(title: "Code IDE\nPython/C", icon: AstralIcons.fileCode, tint: Color(red: 0.72, green: 0.52, blue: 0.98)) {
                    desktop.launch(.codeStudio)
                }
                desktopShortcut(title: "Web Browser\nFalkon", icon: AstralIcons.compass, tint: Color(red: 0.28, green: 0.82, blue: 0.88)) {
                    desktop.launch(.browser)
                }
                desktopShortcut(title: "265 MB ISO\n& Kernel", icon: AstralIcons.zap, tint: Color(red: 0.98, green: 0.65, blue: 0.28)) {
                    desktop.launch(.systemMonitor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func desktopShortcut(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(tint.opacity(0.45), lineWidth: 1))
                    AIcon(icon, size: 20, strokeWidth: 2.1, color: tint)
                }
                Text(title)
                    .font(AstralTheme.mono(10))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 82)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Window Container

    private func desktopWindowContainer(for app: LinuxDesktopApp) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        desktop.close(app)
                    }
                } label: {
                    Circle().fill(Color(red: 0.96, green: 0.36, blue: 0.34)).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        desktop.activeApp = nil
                    }
                } label: {
                    Circle().fill(Color(red: 0.96, green: 0.74, blue: 0.24)).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)

                Circle().fill(AstralTheme.orbGreen).frame(width: 12, height: 12)

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    AIcon(app.iconName, size: 12, strokeWidth: 2.2, color: app.accentColor)
                    Text(app.title)
                        .font(AstralTheme.mono(11.5).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        desktop.activeApp = nil
                    }
                } label: {
                    Text("Desktop")
                        .font(AstralTheme.mono(9.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.09, green: 0.11, blue: 0.16))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
            }

            Group {
                switch app {
                case .terminal:
                    terminalWindowBody
                case .fileManager:
                    fileManagerWindowBody
                case .codeStudio:
                    codeStudioWindowBody
                case .browser:
                    browserWindowBody
                case .systemMonitor:
                    systemMonitorWindowBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.055, green: 0.068, blue: 0.098))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
    }

    // MARK: - Window 1: Desktop Terminal (`xterm`)

    private var terminalWindowBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Gentoo Linux Alpha (\(AlphaLinuxSubsystem.isoFileName)) · Kernel \(AlphaLinuxSubsystem.kernelRelease)")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(AstralTheme.orbGreen)

                    ForEach(shell.history) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("root@astra-os:\(shell.cwd)# \(entry.command)")
                                .font(AstralTheme.mono(11.5).weight(.semibold))
                                .foregroundStyle(AstralTheme.orbGreen)
                            if !entry.output.isEmpty {
                                Text(entry.output)
                                    .font(AstralTheme.mono(11))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(12)
            }

            HStack(spacing: 8) {
                Text("root@astra-os:#")
                    .font(AstralTheme.mono(11.5).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)

                TextField("Run Linux command (e.g. dmesg, ls -la /boot, emerge --info)...", text: $shellCommandDraft)
                    .font(AstralTheme.mono(12))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(runDesktopTerminalCommand)

                Button("Run", action: runDesktopTerminalCommand)
                    .font(AstralTheme.mono(11).weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                    .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.black.opacity(0.35))
        }
    }

    private func runDesktopTerminalCommand() {
        let cmd = shellCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        shellCommandDraft = ""
        Task {
            _ = await shell.run(cmd)
        }
    }

    // MARK: - Window 2: Desktop File Manager (`Thunar` over `/`, `/boot`, `/mnt/cdrom`, `/etc`, `/home/astral`)

    private var fileManagerWindowBody: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["/home/astral", "/boot", "/mnt/cdrom", "/etc", "/"], id: \.self) { path in
                        Button {
                            desktop.currentDirectoryPath = path
                            desktop.previewFileContent = nil
                        } label: {
                            HStack(spacing: 4) {
                                AIcon(AstralIcons.folder, size: 11, strokeWidth: 2, color: desktop.currentDirectoryPath == path ? .black : .white)
                                Text(path)
                                    .font(AstralTheme.mono(10.5).weight(.semibold))
                                    .foregroundStyle(desktop.currentDirectoryPath == path ? .black : .white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(
                                    desktop.currentDirectoryPath == path
                                        ? Color(red: 0.35, green: 0.68, blue: 0.98)
                                        : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .background(Color.black.opacity(0.28))

            if let previewTitle = desktop.previewFileTitle,
               let previewContent = desktop.previewFileContent {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(previewTitle)
                            .font(AstralTheme.mono(11.5).weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Edit in Code IDE") {
                            desktop.openFileInEditor(name: previewTitle, content: previewContent)
                        }
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AstralTheme.orbGreen))
                        .buttonStyle(.plain)

                        Button("Close") {
                            desktop.previewFileContent = nil
                            desktop.previewFileTitle = nil
                        }
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .buttonStyle(.plain)
                    }
                    ScrollView {
                        Text(previewContent)
                            .font(AstralTheme.mono(11))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(directoryEntries(for: desktop.currentDirectoryPath), id: \.name) { item in
                            Button {
                                handleFileItemTap(item)
                            } label: {
                                HStack(spacing: 10) {
                                    AIcon(
                                        item.isDirectory ? AstralIcons.folder : AstralIcons.fileCode,
                                        size: 15,
                                        strokeWidth: 2,
                                        color: item.isDirectory
                                            ? Color(red: 0.35, green: 0.68, blue: 0.98)
                                            : AstralTheme.orbGreen)
                                    Text(item.name)
                                        .font(AstralTheme.mono(12).weight(.medium))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(item.detail)
                                        .font(AstralTheme.mono(10))
                                        .foregroundStyle(Color.white.opacity(0.5))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private struct DesktopFileItem {
        var name: String
        var fullURL: URL?
        var virtualPath: String
        var isDirectory: Bool
        var detail: String
    }

    private func directoryEntries(for path: String) -> [DesktopFileItem] {
        let fm = FileManager.default
        if path == "/" {
            return [
                DesktopFileItem(name: "boot", fullURL: nil, virtualPath: "/boot", isDirectory: true, detail: "Linux Alpha Kernel"),
                DesktopFileItem(name: "etc", fullURL: nil, virtualPath: "/etc", isDirectory: true, detail: "aboot.conf & System Config"),
                DesktopFileItem(name: "home/astral", fullURL: nil, virtualPath: "/home/astral", isDirectory: true, detail: "User Workspace"),
                DesktopFileItem(name: "mnt/cdrom", fullURL: nil, virtualPath: "/mnt/cdrom", isDirectory: true, detail: "Mounted 252.7M ISO"),
            ]
        }

        let targetURL: URL
        switch path {
        case "/boot":
            targetURL = isoManager.supportBaseURL.appendingPathComponent("boot", isDirectory: true)
        case "/mnt/cdrom":
            targetURL = isoManager.supportBaseURL.appendingPathComponent("mnt/cdrom", isDirectory: true)
        case "/etc":
            targetURL = isoManager.supportBaseURL.appendingPathComponent("etc", isDirectory: true)
        default:
            if path.hasPrefix("/home/astral") {
                let rel = String(path.dropFirst("/home/astral".count))
                targetURL = rel.isEmpty ? isoManager.homeURL : isoManager.homeURL.appendingPathComponent(rel)
            } else {
                targetURL = isoManager.supportBaseURL.appendingPathComponent(String(path.dropFirst()))
            }
        }

        guard let urls = try? fm.contentsOfDirectory(
            at: targetURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            return []
        }

        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = vals?.isDirectory ?? false
            let size = vals?.fileSize ?? 0
            let nextPath = (path == "/" ? "" : path) + "/" + url.lastPathComponent
            let detail = isDir
                ? "dir"
                : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return DesktopFileItem(
                name: url.lastPathComponent,
                fullURL: url,
                virtualPath: nextPath,
                isDirectory: isDir,
                detail: detail)
        }
    }

    private func handleFileItemTap(_ item: DesktopFileItem) {
        if item.isDirectory {
            desktop.currentDirectoryPath = item.virtualPath
            return
        }
        guard let url = item.fullURL else { return }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            desktop.previewFileTitle = item.name
            desktop.previewFileContent = text
        } else if let data = try? Data(contentsOf: url) {
            let hexPreview = data.prefix(256).map { String(format: "%02x", $0) }.joined(separator: " ")
            let asciiBanner = String(decoding: data.dropFirst(64).prefix(512), as: UTF8.self)
            desktop.previewFileTitle = "\(item.name) (Binary / ELF64-alpha)"
            desktop.previewFileContent = "Size: \(data.count) bytes\n\nHex Header:\n\(hexPreview)\n\nEmbedded Strings:\n\(asciiBanner)"
        }
    }

    // MARK: - Window 3: Desktop Code & Script Studio (`Astra Code IDE`)

    private var codeStudioWindowBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("filename.py", text: $desktop.editorFileName)
                    .font(AstralTheme.mono(11.5).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .frame(maxWidth: 160)

                Spacer()

                Button {
                    saveEditorFile()
                } label: {
                    Text("Save")
                        .font(AstralTheme.mono(10.5).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Button {
                    runEditorFile()
                } label: {
                    HStack(spacing: 4) {
                        if desktop.editorRunning {
                            ProgressView().controlSize(.mini)
                        }
                        Text("▶ Run on Linux")
                            .font(AstralTheme.mono(10.5).weight(.bold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                }
                .buttonStyle(.plain)
                .disabled(desktop.editorRunning)
            }
            .padding(8)
            .background(Color.black.opacity(0.32))

            TextEditor(text: $desktop.editorCode)
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color(red: 0.04, green: 0.05, blue: 0.08))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !desktop.editorOutput.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Console Output")
                            .font(AstralTheme.mono(10).weight(.bold))
                            .foregroundStyle(AstralTheme.orbGreen)
                        Spacer()
                        Button("Clear") { desktop.editorOutput = "" }
                            .font(AstralTheme.mono(9.5))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .buttonStyle(.plain)
                    }
                    ScrollView {
                        Text(desktop.editorOutput)
                            .font(AstralTheme.mono(11))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 95)
                }
                .padding(8)
                .background(Color.black.opacity(0.5))
            }
        }
    }

    private func saveEditorFile() {
        let name = desktop.editorFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        try? WorkspaceStore.shared.write(path: name, content: desktop.editorCode)
        desktop.editorOutput = "Saved /home/astral/\(name)"
    }

    private func runEditorFile() {
        saveEditorFile()
        let name = desktop.editorFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (name as NSString).pathExtension.lowercased()
        let cmd: String
        switch ext {
        case "py": cmd = "python3 \(name)"
        case "js": cmd = "node \(name)"
        case "c": cmd = "gcc \(name) -o app.out && bash app.out"
        default: cmd = "bash \(name)"
        }
        desktop.editorRunning = true
        Task {
            defer { desktop.editorRunning = false }
            let res = await shell.run(cmd)
            desktop.editorOutput = res.stdout.isEmpty ? "(exit code \(res.exitCode))" : res.stdout
        }
    }

    // MARK: - Window 4: Desktop Web Browser (`Falkon X11`)

    private var browserWindowBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AIcon(AstralIcons.compass, size: 13, strokeWidth: 2, color: Color(red: 0.28, green: 0.82, blue: 0.88))
                TextField("https://...", text: $desktop.browserURLString)
                    .font(AstralTheme.mono(11.5))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    let target = desktop.browserURLString
                    Task {
                        _ = await shell.run("wget -O downloaded_page.html \(target)")
                    }
                } label: {
                    Text("Save HTML")
                        .font(AstralTheme.mono(10).weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 0.28, green: 0.82, blue: 0.88)))
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.black.opacity(0.35))

            DesktopEmbeddedWebView(urlString: desktop.browserURLString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Window 5: System Monitor & Full 265 MB ISO Center

    private var systemMonitorWindowBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        AIcon(AstralIcons.sparkles, size: 14, strokeWidth: 2.2, color: AstralTheme.orbGreen)
                        Text("Full 265 MB Linux Alpha ISO Engine")
                            .font(AstralTheme.headline(13))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(isoManager.fullISOReady ? "READY" : "STREAMABLE")
                            .font(AstralTheme.mono(9.5).weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(AstralTheme.orbGreen))
                    }

                    Text("ISO: \(AlphaLinuxSubsystem.isoFileName) (264,960,000 bytes / 252.7 MiB)")
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(Color.white.opacity(0.8))

                    Text(isoManager.statusText)
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.orbGreen)

                    if isoManager.isDownloading {
                        ProgressView(value: isoManager.downloadProgress)
                            .tint(AstralTheme.orbGreen)
                    }

                    HStack(spacing: 8) {
                        Button {
                            if isoManager.isDownloading {
                                isoManager.cancelDownload()
                            } else {
                                isoManager.downloadAndMountFullISO()
                            }
                        } label: {
                            Text(isoManager.isDownloading
                                 ? "Cancel Stream"
                                 : (isoManager.fullISOReady ? "Re-Verify Full 265 MB ISO" : "Download & Mount Full 265 MB ISO"))
                                .font(AstralTheme.headline(11))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(AstralTheme.orbGreen))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                _ = await shell.run("alpha-iso extract-kernel")
                                desktop.currentDirectoryPath = "/home/astral/alpha-kernel-6.18.52"
                                desktop.launch(.fileManager)
                            }
                        } label: {
                            Text("Extract Kernel to /home/astral")
                                .font(AstralTheme.headline(11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("SRM Console \(AlphaLinuxSubsystem.srmFirmwareVersion) · aboot Kernel Slots")
                        .font(AstralTheme.headline(12.5))
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Button {
                            _ = alpha.runAboot(["boot", "0"])
                        } label: {
                            Text("Slot 0: /boot/gentoo (LSA)")
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(alpha.activeBootSlot < 3 ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(alpha.activeBootSlot < 3 ? AstralTheme.orbGreen : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            _ = alpha.runAboot(["boot", "3"])
                        } label: {
                            Text("Slot 3: /boot/gentoo_nolsa")
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(alpha.activeBootSlot >= 3 ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(alpha.activeBootSlot >= 3 ? AstralTheme.orbGreen : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenRC 0.55.1 Services (rc-status)")
                        .font(AstralTheme.headline(12.5))
                        .foregroundStyle(.white)

                    ForEach(alpha.openRCServices.prefix(8)) { svc in
                        HStack {
                            Text(svc.name)
                                .font(AstralTheme.mono(11).weight(.semibold))
                                .foregroundStyle(.white)
                            Text("(\(svc.runlevel))")
                                .font(AstralTheme.mono(10))
                                .foregroundStyle(Color.white.opacity(0.5))
                            Spacer()
                            Button {
                                let nextAction = svc.status == "started" ? "stop" : "start"
                                _ = alpha.runOpenRC(command: "rc-service", args: [svc.name, nextAction])
                            } label: {
                                Text(svc.status.uppercased())
                                    .font(AstralTheme.mono(9.5).weight(.bold))
                                    .foregroundStyle(svc.status == "started" ? .black : .white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(
                                            svc.status == "started"
                                                ? AstralTheme.orbGreen
                                                : Color.red.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kernel Ring Buffer (dmesg — \(AlphaLinuxSubsystem.kernelRelease))")
                        .font(AstralTheme.headline(12.5))
                        .foregroundStyle(.white)

                    Text(alpha.dmesgBuffer.suffix(12).joined(separator: "\n"))
                        .font(AstralTheme.mono(10))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }
            .padding(12)
        }
    }

    // MARK: - Bottom Linux Dock / Taskbar

    private var bottomDockBar: some View {
        HStack(spacing: 8) {
            ForEach(LinuxDesktopApp.allCases) { app in
                let isSelected = desktop.activeApp == app
                let isOpen = desktop.openApps.contains(app)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        if isSelected {
                            desktop.activeApp = nil
                        } else {
                            desktop.launch(app)
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            AIcon(app.iconName, size: 13, strokeWidth: 2.1, color: isSelected ? .black : app.accentColor)
                            Text(app.shortLabel)
                                .font(AstralTheme.headline(11))
                                .foregroundStyle(isSelected ? .black : .white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? app.accentColor : Color.white.opacity(0.08)))

                        Circle()
                            .fill(isOpen ? app.accentColor : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.62))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
    }
}

// MARK: - Embedded WebKit View for Desktop Browser

private struct DesktopEmbeddedWebView: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        var clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.hasPrefix("http://") && !clean.hasPrefix("https://") {
            clean = "https://" + clean
        }
        guard let url = URL(string: clean) else { return }
        if webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }
}
