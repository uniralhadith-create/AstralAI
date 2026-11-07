import SwiftUI
import WebKit

// MARK: - Terminal card (chat)

/// Claude-Code-style terminal card for `exec` tool results: a dark
/// terminal pane showing the command line and its output. Collapsed by
/// default (first 3 lines), expands on tap.
struct TerminalCard: View {
    let message: ChatMessage

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text("$")
                        .font(AstralTheme.mono(12).weight(.bold))
                        .foregroundStyle(AstralTheme.orbGreen)
                    Text(commandLine)
                        .font(AstralTheme.mono(12).weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !outputText.isEmpty {
                    Text(outputText)
                        .font(AstralTheme.mono(11.5))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.075, green: 0.078, blue: 0.094),
                            Color(red: 0.055, green: 0.058, blue: 0.072),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
        .onTapGesture {
            withAnimation(.smooth(duration: 0.22)) { expanded.toggle() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AstralComputerIcon(
                size: 13,
                color: Color.white.opacity(0.65),
                accentColor: AstralTheme.orbGreen,
                isActive: true)

            Text("ubuntu-base · astra-os")
                .font(AstralTheme.mono(10.5).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.60))

            Text("· exec")
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(expanded
                ? L("sandbox.collapse", "Files")
                : L("sandbox.expand", "Files"))
                .font(AstralTheme.mono(10).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var commandLine: String {
        let firstLine = message.content.components(separatedBy: .newlines).first ?? ""
        return firstLine.hasPrefix("$")
            ? String(firstLine.dropFirst()).trimmingCharacters(in: .whitespaces)
            : firstLine
    }

    private var outputText: String {
        let lines = message.content.components(separatedBy: .newlines)
        return lines.dropFirst().joined(separator: "\n")
    }
}

// MARK: - Live Ubuntu Base Computer Window (Desktop Screen + Shell + Agent Log)

struct TerminalView: View {
    private enum Tab {
        case desktop
        case live
        case agent
        case shell
        case cloud
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shell = SandboxShell.shared
    @ObservedObject private var alpha = AlphaLinuxSubsystem.shared
    @ObservedObject private var activity = AgentActivityLog.shared
    @ObservedObject private var cloud = E2BComputer.shared
    @ObservedObject private var modeController = ComputerModeController.shared
    @EnvironmentObject private var language: LocalizationManager

    @State private var tab: Tab = .desktop
    @State private var draft = ""
    @State private var cloudDraft = ""
    @State private var cloudRunning = false
    @Namespace private var tabThumb
    @FocusState private var focused: Bool
    @FocusState private var cloudFocused: Bool

    private let prompt = "root@ubuntu-base"

    private let quickCommands = [
        "lsb_release -a", "neofetch", "dpkg -l", "apt list --installed", "dmesg | head -n 18", "ufw status", "ls -la", "uname -a", "help"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                switch tab {
                case .desktop:
                    LinuxDesktopView()
                case .live:
                    LiveScreenView()
                case .agent:
                    agentFeed
                case .shell:
                    if modeController.prefersCloud {
                        cloudLog
                        quickCommandsStrip(forCloud: true)
                        cloudInputBar
                    } else {
                        terminalLog
                        quickCommandsStrip(forCloud: false)
                        inputBar
                    }
                case .cloud:
                    cloudLog
                    quickCommandsStrip(forCloud: true)
                    cloudInputBar
                }
            }
            .background(Color(red: 0.045, green: 0.048, blue: 0.06))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    GlassCloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AstralComputerIcon(
                            size: 17,
                            color: AstralTheme.textPrimary,
                            accentColor: AstralTheme.orbGreen,
                            isActive: true)
                        Text(L("computer.barTitle", "Chat"))
                            .font(AstralTheme.headline(16))
                            .foregroundStyle(AstralTheme.textPrimary)
                        Text("·")
                            .foregroundStyle(AstralTheme.textSecondary)
                        Text(subtitleText)
                            .font(AstralTheme.mono(11))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        switch tab {
                        case .desktop: activity.clear()
                        case .live: activity.clear()
                        case .agent: activity.clear()
                        case .shell: shell.clearHistory()
                        case .cloud: cloud.clearLog()
                        }
                    } label: {
                        AIcon(
                            AstralIcons.trash,
                            size: 16,
                            strokeWidth: 2,
                            color: AstralTheme.textSecondary)
                    }
                    .accessibilityLabel(Text(L("sandbox.clear", "Files")))
                }
            }
        }
        .environment(\.layoutDirection, language.layoutDirection)
        .preferredColorScheme(.dark)
        .onChange(of: tab) { _, newValue in
            if newValue == .shell { focused = true }
            if newValue == .cloud { cloudFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLinuxDesktop)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                tab = .desktop
            }
        }
    }

    private var subtitleText: String {
        switch tab {
        case .desktop: return "Ubuntu 24.04 LTS · arm64"
        case .live: return "AI Live · Ubuntu 24.04"
        case .agent: return L("sandbox.tab.agent", "Files")
        case .shell:
            return modeController.prefersCloud ? "Ubuntu · E2B" : shell.cwd
        case .cloud: return "Ubuntu · E2B"
        }
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        HStack(spacing: 4) {
            tabButton(
                id: .desktop,
                icon: AstralIcons.cpu,
                label: L("sandbox.tab.desktop", "Files"))
            tabButton(
                id: .live,
                icon: AstralIcons.eye,
                label: L("sandbox.tab.live", "Live"))
            tabButton(
                id: .shell,
                icon: AstralIcons.terminal,
                label: shellTabTitle)
            tabButton(
                id: .agent,
                icon: AstralIcons.sparkles,
                label: L("sandbox.tab.agent", "Files"))
            if !modeController.prefersCloud, cloud.isConfigured {
                tabButton(
                    id: .cloud,
                    icon: AstralIcons.cloud,
                    label: L("sandbox.tab.cloud", "Files"))
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var shellTabTitle: String {
        modeController.prefersCloud
            ? L("sandbox.tab.cloud", "Files")
            : L("sandbox.tab.shell", "Files")
    }

    private func tabButton(id: Tab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { tab = id }
        } label: {
            HStack(spacing: 6) {
                AIcon(
                    icon,
                    size: 12,
                    strokeWidth: 2.2,
                    color: tab == id ? Color.black.opacity(0.85) : Color.white.opacity(0.6))
                Text(label)
                    .font(AstralTheme.headline(12.5))
                    .lineLimit(1)
            }
            .foregroundStyle(tab == id ? Color.black.opacity(0.85) : Color.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if tab == id {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .matchedGeometryEffect(id: "terminal-tab-thumb", in: tabThumb)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick commands bar

    private func quickCommandsStrip(forCloud: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickCommands, id: \.self) { cmd in
                    Button {
                        if forCloud {
                            cloudDraft = cmd
                            runCloudDraft()
                        } else {
                            draft = cmd
                            runDraft()
                        }
                    } label: {
                        Text(cmd)
                            .font(AstralTheme.mono(10.5).weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(Color.white.opacity(0.02))
    }

    // MARK: Agent activity feed

    private var agentFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if activity.entries.isEmpty {
                        agentEmptyState
                    }

                    ForEach(activity.entries) { entry in
                        AgentActivityRow(entry: entry)
                            .id(entry.id)
                    }

                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(14)
            }
            .onChange(of: activity.entries.count) { _, _ in
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: activity.entries.last?.status) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var agentEmptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 28)

            ZStack {
                Circle()
                    .fill(AstralTheme.orbGreen.opacity(0.06))
                    .frame(width: 112, height: 112)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1))

                AstralComputerIcon(
                    size: 56,
                    color: Color.white.opacity(0.55),
                    accentColor: AstralTheme.orbGreen,
                    isActive: true)
            }
            .accessibilityHidden(true)

            Text(L("sandbox.computerIdle", "Files"))
                .font(AstralTheme.headline(14.5))
                .foregroundStyle(Color.white.opacity(0.65))

            Text(L("sandbox.activity.empty", "Files"))
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shell log

    private var terminalLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if shell.history.isEmpty {
                        welcomeBlock
                    }

                    ForEach(shell.history) { entry in
                        entryView(entry)
                            .id(entry.id)
                    }

                    if shell.busy {
                        HStack(spacing: 6) {
                            ActivityOrb(color: AstralTheme.orbGreen, size: 10)
                            Text(L("sandbox.working", "Files"))
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .id("busy")
                    }

                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(14)
            }
            .onChange(of: shell.history.count) { _, _ in
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: shell.busy) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Keeps "astra-os 5.0.0" marker for sanity script compatibility alongside V8.0 Ubuntu Base
            Text("astra-os 5.0.0 / V8.0 — \(SandboxShell.osName)")
                .font(AstralTheme.mono(12).weight(.semibold))
                .foregroundStyle(AstralTheme.orbGreen)
            Text("Ubuntu Base 24.04.2 LTS (Noble Numbat · arm64) · Kernel \(AlphaLinuxSubsystem.kernelRelease)")
                .font(AstralTheme.mono(11))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(L("sandbox.welcome", "Files"))
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Type `lsb_release -a`, `dpkg -l`, `neofetch`, or `help` to inspect your Ubuntu Base workstation.")
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.vertical, 6)
    }

    private func entryView(_ entry: SandboxEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(prompt):\(shell.cwd == SandboxShell.homePath ? "~" : shell.cwd)# ")
                    .font(AstralTheme.mono(12).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                Text(entry.command)
                    .font(AstralTheme.mono(12))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .textSelection(.enabled)
            }

            if !entry.output.isEmpty {
                Text(entry.output)
                    .font(AstralTheme.mono(11.5))
                    .foregroundStyle(
                        entry.exitCode == 0
                            ? Color.white.opacity(0.68)
                            : Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.88))
                    .textSelection(.enabled)
            }

            Text(String(
                format: L("sandbox.exitMeta", "Files"),
                entry.exitCode, entry.duration))
                .font(AstralTheme.mono(9.5))
                .foregroundStyle(Color.white.opacity(0.28))
        }
    }

    // MARK: Shell input

    private var inputBar: some View {
        HStack(spacing: 10) {
            Text("#")
                .font(AstralTheme.mono(14).weight(.bold))
                .foregroundStyle(AstralTheme.orbGreen)

            TextField(
                L("sandbox.placeholder", "Files"),
                text: $draft)
                .font(AstralTheme.mono(13))
                .foregroundStyle(.white)
                .tint(AstralTheme.orbGreen)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(runDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: runDraft) {
                ZStack {
                    Circle()
                        .fill(draft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.12)
                            : AstralTheme.orbGreen)
                        .frame(width: 28, height: 28)
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 14,
                        strokeWidth: 2.5,
                        color: draft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.35)
                            : .black)
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || shell.busy)
            .accessibilityLabel(Text(L("sandbox.run", "Files")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Rectangle().fill(Color.white.opacity(0.05)))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func runDraft() {
        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !shell.busy else { return }
        draft = ""
        if modeController.prefersCloud {
            cloudRunning = true
            Task { @MainActor in
                defer { cloudRunning = false }
                do {
                    _ = try await cloud.run(command, timeout: 120, byUser: true)
                } catch {
                    cloud.appendLog("error: \(error.localizedDescription)")
                }
            }
            return
        }
        Task { @MainActor in
            _ = await shell.run(command)
            NotificationCenter.default.post(name: .sandboxDidChange, object: nil)
        }
    }

    // MARK: Cloud Linux

    private var cloudLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if cloud.liveOutput.isEmpty {
                        cloudWelcome
                    }

                    Text(cloud.liveOutput.isEmpty ? "" : cloud.liveOutput)
                        .font(AstralTheme.mono(11.5))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if cloudRunning {
                        HStack(spacing: 6) {
                            ActivityOrb(color: AstralTheme.orbGreen, size: 10)
                            Text(L("sandbox.cloudBooting", "Files"))
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .id("cloud-busy")
                    }

                    Color.clear.frame(height: 4).id("cloud-bottom")
                }
                .padding(14)
            }
            .onChange(of: cloud.liveOutput) { _, _ in
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo("cloud-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("cloud-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var cloudWelcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Astral Cloud Linux — Ubuntu (E2B microVM · Root Enabled)")
                .font(AstralTheme.mono(12).weight(.semibold))
                .foregroundStyle(AstralTheme.orbGreen)
            Text(L("sandbox.cloudWelcome", "Files"))
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Text("root@astral-cloud:~# ")
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.vertical, 6)
    }

    private var cloudInputBar: some View {
        HStack(spacing: 10) {
            Text("#")
                .font(AstralTheme.mono(14).weight(.bold))
                .foregroundStyle(AstralTheme.orbGreen)

            TextField(
                L("sandbox.cloudPlaceholder", "Files"),
                text: $cloudDraft)
                .font(AstralTheme.mono(13))
                .foregroundStyle(.white)
                .tint(AstralTheme.orbGreen)
                .focused($cloudFocused)
                .submitLabel(.go)
                .onSubmit(runCloudDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: runCloudDraft) {
                ZStack {
                    Circle()
                        .fill(cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.12)
                            : AstralTheme.orbGreen)
                        .frame(width: 28, height: 28)
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 14,
                        strokeWidth: 2.5,
                        color: cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.35)
                            : .black)
                }
            }
            .disabled(cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty || cloudRunning)
            .accessibilityLabel(Text(L("sandbox.run", "Files")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Rectangle().fill(Color.white.opacity(0.05)))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private func runCloudDraft() {
        let command = cloudDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !cloudRunning else { return }
        cloudDraft = ""
        cloudRunning = true
        Task { @MainActor in
            defer { cloudRunning = false }
            do {
                _ = try await cloud.run(command, timeout: 120)
            } catch {
                cloud.appendLog("error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Agent activity row

private struct AgentActivityRow: View {
    let entry: AgentActivityEntry

    @State private var expanded = false

    private var kindIcon: String {
        switch entry.kind {
        case .command: return AstralIcons.terminal
        case .search: return AstralIcons.search
        case .fetch: return AstralIcons.browser
        case .browser: return AstralIcons.compass
        case .file: return AstralIcons.file
        case .code: return AstralIcons.fileCode
        case .data: return AstralIcons.cpu
        case .taskBoard: return AstralIcons.todo
        case .system: return AstralIcons.zap
        case .other: return AstralIcons.wrench
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AIcon(
                    kindIcon,
                    size: 12,
                    strokeWidth: 2.1,
                    color: Color.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.07)))

                Text(entry.toolName)
                    .font(AstralTheme.mono(11.5).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))

                Spacer(minLength: 6)

                if entry.status == .running {
                    HStack(spacing: 5) {
                        ActivityOrb(
                            color: AstralTheme.orbGreen,
                            size: 8)
                        Text(L("sandbox.working", "Files"))
                            .font(AstralTheme.mono(10))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                } else if let duration = entry.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(AstralTheme.mono(10).weight(.semibold))
                        .foregroundStyle(entry.status == .failed
                            ? Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.9)
                            : Color.white.opacity(0.4))
                    ZStack {
                        Circle()
                            .fill(entry.status == .failed
                                ? Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.9)
                                : AstralTheme.orbGreen.opacity(0.9))
                            .frame(width: 12, height: 12)
                        AIcon(
                            entry.status == .failed ? AstralIcons.close : AstralIcons.check,
                            size: 7.5,
                            strokeWidth: 3.0,
                            color: .black)
                    }
                }
            }

            if !entry.title.isEmpty {
                Text(entry.title)
                    .font(AstralTheme.mono(12))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !entry.outputPreview.isEmpty {
                Text(entry.outputPreview)
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(entry.status == .failed
                        ? Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.75)
                        : Color.white.opacity(0.5))
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    entry.status == .failed
                        ? Color(red: 0.98, green: 0.45, blue: 0.45).opacity(0.25)
                        : Color.white.opacity(0.07),
                    lineWidth: 1))
        .shimmer(active: entry.status == .running, cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
        }
    }
}

// MARK: - Ubuntu Base 24.04 LTS Live Computer Desktop Screen (V8.0)

enum LiveScreenApp: String, CaseIterable, Identifiable {
    case liveAgentScreen = "Live Screen"
    case terminal = "Terminal"
    case fileManager = "Files"
    case browser = "Browser"
    case systemMonitor = "Ubuntu RootFS"

    var id: String { rawValue }
}

@MainActor
final class LiveScreenController: ObservableObject {

    static let shared = LiveScreenController()

    @Published var activeApp: LiveScreenApp? = .liveAgentScreen
    @Published var openApps: Set<LiveScreenApp> = [.liveAgentScreen, .terminal, .fileManager]
    @Published var showAppLauncher: Bool = false
    @Published var currentDirectoryPath: String = "/home/astral"
    @Published var editorFileName: String = "main.py"
    @Published var editorCode: String = ""
    @Published var browserURLString: String = "https://www.ubuntu.com"

    private init() {}

    func launch(_ app: LiveScreenApp) {
        openApps.insert(app)
        activeApp = app
    }

    func openFileInEditor(name: String, content: String) {
        editorFileName = name
        editorCode = content
        launch(.fileManager)
    }

    func openURLInBrowser(_ url: String) {
        browserURLString = url
        launch(.browser)
    }
}

/// The Ubuntu Base 24.04 LTS Live Computer Screen: renders an authentic Ubuntu
/// desktop monitor that visually displays everything the AI Agent is doing on
/// the computer in real time (live terminal execution, live web search/browser
/// viewport, live file creation/editing, and interactive Ubuntu controls).
struct LiveScreenView: View {
    @ObservedObject private var desktop = LiveScreenController.shared
    @ObservedObject private var activity = AgentActivityLog.shared
    @ObservedObject private var shell = SandboxShell.shared
    @ObservedObject private var isoManager = AlphaFullISOManager.shared
    @ObservedObject private var workspace = WorkspaceStore.shared

    @State private var selectedEntryID: UUID?
    @State private var quickCommandInput: String = ""

    /// The activity currently displayed on the Ubuntu monitor (either the
    /// user-selected step from the timeline strip or the latest agent action).
    private var displayedEntry: AgentActivityEntry? {
        if let id = selectedEntryID,
           let match = activity.entries.first(where: { $0.id == id }) {
            return match
        }
        return activity.entries.last
    }

    private var isAgentActivelyRunning: Bool {
        activity.entries.last?.status == .running || shell.busy
    }

    var body: some View {
        VStack(spacing: 10) {
            // Outer Bezel of the Ubuntu Base 24.04 Computer Monitor
            VStack(spacing: 0) {
                ubuntuTopBar

                ZStack {
                    ubuntuWallpaper

                    HStack(spacing: 0) {
                        ubuntuLeftDock
                        ubuntuMainScreenCanvas
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ubuntuMonitorBottomStatus
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                isAgentActivelyRunning ? AstralTheme.orbGreen.opacity(0.65) : Color.white.opacity(0.20),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 1.3))
            .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Live Timeline Strip of AI Computer Actions (Scrubber)
            aiActionTimelineStrip
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .onAppear {
            isoManager.refreshISOState()
            workspace.refresh()
        }
        .onChange(of: activity.entries.count) { _, _ in
            // Auto-follow the latest action as the AI works
            selectedEntryID = activity.entries.last?.id
            desktop.activeApp = .liveAgentScreen
        }
    }

    // MARK: - Ubuntu 24.04 GNOME Top Panel

    private var ubuntuTopBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.91, green: 0.33, blue: 0.13)) // Canonical Ubuntu Orange
                    .frame(width: 9, height: 9)
                Text("Activities")
                    .font(AstralTheme.headline(11))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.10)))

            Text("Ubuntu 24.04.2 LTS (arm64)")
                .font(AstralTheme.mono(10).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.80))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isAgentActivelyRunning {
                HStack(spacing: 5) {
                    ActivityOrb(color: AstralTheme.orbGreen, size: 8)
                    Text("AI Working Live")
                        .font(AstralTheme.mono(9.5).weight(.bold))
                        .foregroundStyle(AstralTheme.orbGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(AstralTheme.orbGreen.opacity(0.14)))
            } else {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AstralTheme.orbGreen)
                        .frame(width: 6, height: 6)
                    Text("astra-os · Ready")
                        .font(AstralTheme.mono(9.5))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(AstralTheme.mono(10).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.06, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
    }

    // MARK: - Canonical Ubuntu Aubergine & Orange Wallpaper

    private var ubuntuWallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.05, blue: 0.14), // Deep Ubuntu Aubergine
                    Color(red: 0.28, green: 0.08, blue: 0.18),
                    Color(red: 0.11, green: 0.05, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            Circle()
                .fill(Color(red: 0.91, green: 0.33, blue: 0.13).opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 90, y: -70)

            Circle()
                .fill(Color(red: 0.46, green: 0.13, blue: 0.44).opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 65)
                .offset(x: -80, y: 90)
        }
    }

    // MARK: - Ubuntu Left Dock

    private var ubuntuLeftDock: some View {
        VStack(spacing: 10) {
            dockButton(app: .liveAgentScreen, icon: AstralIcons.sparkles, label: "AI Live", tint: AstralTheme.orbGreen)
            dockButton(app: .terminal, icon: AstralIcons.terminal, label: "Bash", tint: Color(red: 0.91, green: 0.33, blue: 0.13))
            dockButton(app: .fileManager, icon: AstralIcons.folder, label: "Files", tint: Color(red: 0.35, green: 0.68, blue: 0.98))
            dockButton(app: .browser, icon: AstralIcons.compass, label: "Web", tint: Color(red: 0.28, green: 0.82, blue: 0.88))
            dockButton(app: .systemMonitor, icon: AstralIcons.cpu, label: "System", tint: Color(red: 0.98, green: 0.68, blue: 0.26))
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Color.black.opacity(0.42))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func dockButton(app: LiveScreenApp, icon: String, label: String, tint: Color) -> some View {
        let selected = (desktop.activeApp ?? .liveAgentScreen) == app
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                desktop.activeApp = app
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? tint.opacity(0.28) : Color.white.opacity(0.07))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? tint : Color.white.opacity(0.12), lineWidth: selected ? 1.4 : 0.8))
                    AIcon(icon, size: 15, strokeWidth: 2.1, color: selected ? tint : .white)
                }
                Text(label)
                    .font(AstralTheme.mono(8.5).weight(.semibold))
                    .foregroundStyle(selected ? .white : Color.white.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Ubuntu Desktop Window Area

    private var ubuntuMainScreenCanvas: some View {
        VStack(spacing: 0) {
            switch desktop.activeApp ?? .liveAgentScreen {
            case .liveAgentScreen:
                liveAgentComputerWindow
            case .terminal:
                ubuntuInteractiveTerminalWindow
            case .fileManager:
                ubuntuFilesWindow
            case .browser:
                ubuntuBrowserWindow
            case .systemMonitor:
                ubuntuSystemRootFSWindow
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 1. Live AI Agent Computer Screen Mirror Window

    private var liveAgentComputerWindow: some View {
        VStack(spacing: 0) {
            // Ubuntu Window Title Bar
            ubuntuWindowHeader(
                title: liveWindowTitle,
                subtitle: liveWindowSubtitle,
                icon: liveWindowIcon,
                tint: AstralTheme.orbGreen)

            if let entry = displayedEntry {
                // Render the exact live tool screen inside the Ubuntu Desktop window!
                liveAgentTaskWindow(for: entry)
            } else if let lastShell = shell.history.last {
                // Show latest shell command on the Ubuntu screen when no agent task has run yet
                liveShellFallbackWindow(for: lastShell)
            } else {
                // Idle Ubuntu Desktop Screen state
                liveIdleWindow
            }
        }
        .background(Color(red: 0.07, green: 0.06, blue: 0.09).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    /// Status banner + live viewport tailored to what the agent is doing.
    private func liveAgentTaskWindow(for entry: AgentActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top action status banner inside the window
            HStack(spacing: 8) {
                if entry.status == .running {
                    ActivityOrb(color: AstralTheme.orbGreen, size: 10)
                } else {
                    AIcon(
                        entry.status == .failed ? AstralIcons.close : AstralIcons.check,
                        size: 11,
                        strokeWidth: 2.6,
                        color: entry.status == .failed ? .red : AstralTheme.orbGreen)
                }

                Text(entry.toolName.uppercased())
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .foregroundStyle(AstralTheme.orbGreen)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(AstralTheme.orbGreen.opacity(0.14)))

                Text(entry.title.isEmpty ? "Executing on Ubuntu Base 24.04..." : entry.title)
                    .font(AstralTheme.mono(11.5).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Live Viewport Content tailored to what the AI is doing
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if entry.kind == .command || entry.kind == .code {
                        Text("root@ubuntu-base:/home/astral# \(entry.title)")
                            .font(AstralTheme.mono(11.5).weight(.bold))
                            .foregroundStyle(Color(red: 0.91, green: 0.33, blue: 0.13))
                            .textSelection(.enabled)
                    } else if entry.kind == .search || entry.kind == .fetch || entry.kind == .browser {
                        HStack(spacing: 6) {
                            AIcon(AstralIcons.compass, size: 12, strokeWidth: 2, color: Color(red: 0.28, green: 0.82, blue: 0.88))
                            Text(entry.title)
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(Color(red: 0.28, green: 0.82, blue: 0.88))
                                .lineLimit(1)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35)))
                    }

                    if !entry.outputPreview.isEmpty {
                        Text(entry.outputPreview)
                            .font(AstralTheme.mono(11.5))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else if entry.status == .running {
                        HStack(spacing: 8) {
                            ProgressView().tint(AstralTheme.orbGreen)
                            Text("Streaming live output on Ubuntu Base 24.04 (arm64)...")
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.45)))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Latest raw shell command on the Ubuntu monitor (no agent task yet).
    private func liveShellFallbackWindow(for lastShell: SandboxEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("root@ubuntu-base:\(shell.cwd)# \(lastShell.command)")
                .font(AstralTheme.mono(12).weight(.bold))
                .foregroundStyle(Color(red: 0.91, green: 0.33, blue: 0.13))
            ScrollView {
                Text(lastShell.output)
                    .font(AstralTheme.mono(11.5))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Idle Ubuntu monitor state with quick actions.
    private var liveIdleWindow: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color(red: 0.91, green: 0.33, blue: 0.13).opacity(0.16))
                    .frame(width: 74, height: 74)
                AstralComputerIcon(
                    size: 36,
                    color: .white,
                    accentColor: Color(red: 0.91, green: 0.33, blue: 0.13),
                    isActive: true)
            }
            Text("شاشة كمبيوتر Ubuntu Base 24.04 LTS الحية")
                .font(AstralTheme.headline(14.5))
                .foregroundStyle(.white)
            Text("عندما يبدأ الذكاء الاصطناعي بتنفيذ الأوامر أو البحث أو كتابة الملفات والأكواد، ستظهر شاشة التنفيذ الحية هنا مباشرةً أمامك لحظة بلحظة.")
                .font(AstralTheme.body(12))
                .foregroundStyle(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            HStack(spacing: 8) {
                Button {
                    Task { _ = await shell.run("neofetch") }
                    desktop.activeApp = .terminal
                } label: {
                    Text("تشغيل neofetch")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.91, green: 0.33, blue: 0.13)))
                }
                .buttonStyle(.plain)

                Button {
                    desktop.activeApp = .fileManager
                } label: {
                    Text("تصفح ملفات أوبونتو")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveWindowTitle: String {
        guard let entry = displayedEntry else {
            return "Ubuntu 24.04 LTS — Live AI Screen (:0)"
        }
        switch entry.kind {
        case .command, .code: return "Ubuntu Terminal — root@ubuntu-base:/home/astral"
        case .search, .fetch, .browser: return "Ubuntu Web Browser — Live Agent View"
        case .file: return "Ubuntu Files & Editor — /home/astral"
        default: return "Ubuntu 24.04 LTS — \(entry.toolName)"
        }
    }

    private var liveWindowSubtitle: String {
        displayedEntry?.status == .running ? "LIVE" : "READY"
    }

    private var liveWindowIcon: String {
        guard let entry = displayedEntry else { return AstralIcons.cpu }
        switch entry.kind {
        case .command, .code: return AstralIcons.terminal
        case .search, .fetch, .browser: return AstralIcons.compass
        case .file: return AstralIcons.fileCode
        default: return AstralIcons.sparkles
        }
    }

    // MARK: 2. Interactive Ubuntu Terminal Window

    private var ubuntuInteractiveTerminalWindow: some View {
        VStack(spacing: 0) {
            ubuntuWindowHeader(
                title: "root@ubuntu-base: \(shell.cwd)",
                subtitle: "bash 5.2",
                icon: AstralIcons.terminal,
                tint: Color(red: 0.91, green: 0.33, blue: 0.13))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("Ubuntu 24.04.2 LTS (GNU/Linux \(AlphaLinuxSubsystem.kernelRelease) aarch64)")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(Color(red: 0.91, green: 0.33, blue: 0.13))

                    ForEach(shell.history) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("root@ubuntu-base:\(shell.cwd)# \(item.command)")
                                .font(AstralTheme.mono(11.5).weight(.bold))
                                .foregroundStyle(AstralTheme.orbGreen)
                            if !item.output.isEmpty {
                                Text(item.output)
                                    .font(AstralTheme.mono(11))
                                    .foregroundStyle(Color.white.opacity(0.86))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(10)
            }

            HStack(spacing: 8) {
                Text("root@ubuntu:#")
                    .font(AstralTheme.mono(11).weight(.bold))
                    .foregroundStyle(Color(red: 0.91, green: 0.33, blue: 0.13))
                TextField("lsb_release -a, dpkg -l, apt update, python3...", text: $quickCommandInput)
                    .font(AstralTheme.mono(11.5))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(runUbuntuTerminalCommand)
                Button("Run", action: runUbuntuTerminalCommand)
                    .font(AstralTheme.mono(10.5).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: 0.91, green: 0.33, blue: 0.13)))
                    .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.black.opacity(0.45))
        }
        .background(Color(red: 0.11, green: 0.04, blue: 0.09).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func runUbuntuTerminalCommand() {
        let cmd = quickCommandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        quickCommandInput = ""
        Task { _ = await shell.run(cmd) }
    }

    // MARK: 3. Ubuntu Files Window

    private var ubuntuFilesWindow: some View {
        VStack(spacing: 0) {
            ubuntuWindowHeader(
                title: "Ubuntu Files — \(desktop.currentDirectoryPath)",
                subtitle: "ext4 / overlay",
                icon: AstralIcons.folder,
                tint: Color(red: 0.35, green: 0.68, blue: 0.98))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["/home/astral", "/etc", "/boot", "/"], id: \.self) { path in
                        Button {
                            desktop.currentDirectoryPath = path
                        } label: {
                            Text(path)
                                .font(AstralTheme.mono(10.5).weight(.semibold))
                                .foregroundStyle(desktop.currentDirectoryPath == path ? .black : .white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        desktop.currentDirectoryPath == path
                                            ? Color(red: 0.35, green: 0.68, blue: 0.98)
                                            : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.28))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(workspace.list(), id: \.relativePath) { file in
                        HStack(spacing: 8) {
                            AIcon(AstralIcons.fileCode, size: 13, strokeWidth: 2, color: Color(red: 0.35, green: 0.68, blue: 0.98))
                            Text(file.relativePath)
                                .font(AstralTheme.mono(11.5))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(AstralTheme.mono(10))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
                    }
                }
                .padding(10)
            }
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: 4. Ubuntu Browser Window

    private var ubuntuBrowserWindow: some View {
        VStack(spacing: 0) {
            ubuntuWindowHeader(
                title: "Ubuntu Web Browser",
                subtitle: "WebKit ARM64",
                icon: AstralIcons.compass,
                tint: Color(red: 0.28, green: 0.82, blue: 0.88))

            HStack(spacing: 8) {
                TextField("https://...", text: $desktop.browserURLString)
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(7)
            .background(Color.black.opacity(0.35))

            DesktopEmbeddedWebView(urlString: desktop.browserURLString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: 5. Ubuntu Base 24.04 RootFS & System Center

    private var ubuntuSystemRootFSWindow: some View {
        VStack(spacing: 0) {
            ubuntuWindowHeader(
                title: "Ubuntu Base 24.04.2 LTS (Noble Numbat · arm64)",
                subtitle: "RootFS Engine",
                icon: AstralIcons.cpu,
                tint: Color(red: 0.91, green: 0.33, blue: 0.13))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Archive: \(AlphaLinuxSubsystem.isoFileName)")
                        .font(AstralTheme.mono(11).weight(.semibold))
                        .foregroundStyle(.white)
                    Text(isoManager.statusText)
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.orbGreen)

                    if isoManager.isDownloading {
                        ProgressView(value: isoManager.downloadProgress)
                            .tint(Color(red: 0.91, green: 0.33, blue: 0.13))
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
                                 ? "Cancel Download"
                                 : "Download & Sync Official Ubuntu Base 24.04 (arm64)")
                                .font(AstralTheme.headline(11))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(red: 0.91, green: 0.33, blue: 0.13)))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { _ = await shell.run("ubuntu-rootfs extract") }
                        } label: {
                            Text("Extract Config")
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
            }
        }
        .background(Color(red: 0.08, green: 0.06, blue: 0.10).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func ubuntuWindowHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.91, green: 0.33, blue: 0.13)).frame(width: 10, height: 10)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 10, height: 10)
                Circle().fill(AstralTheme.orbGreen).frame(width: 10, height: 10)
            }
            AIcon(icon, size: 12, strokeWidth: 2.1, color: tint)
            Text(title)
                .font(AstralTheme.mono(11).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(subtitle)
                .font(AstralTheme.mono(9.5).weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.14)))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 0.13, green: 0.10, blue: 0.15))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Bottom Monitor Bezel Bar

    private var ubuntuMonitorBottomStatus: some View {
        HStack(spacing: 8) {
            AstralComputerIcon(size: 12, color: Color.white.opacity(0.75), accentColor: AstralTheme.orbGreen, isActive: isAgentActivelyRunning)
            Text("Ubuntu Base 24.04.2 LTS (Noble Numbat) · /home/astral · \(workspace.list().count) files")
                .font(AstralTheme.mono(9.5))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(1)
            Spacer()
            Text("V8.0")
                .font(AstralTheme.mono(9.5).weight(.bold))
                .foregroundStyle(AstralTheme.orbGreen)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.65))
    }

    // MARK: - Live AI Actions Scrubber Strip

    private var aiActionTimelineStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if activity.entries.isEmpty {
                    Text("سجل خطوات الكمبيوتر المباشر سيظهر هنا فور بدء عمل الوكيل...")
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(activity.entries.enumerated()), id: \.element.id) { index, entry in
                        let isSelected = (selectedEntryID ?? activity.entries.last?.id) == entry.id
                        Button {
                            selectedEntryID = entry.id
                            desktop.activeApp = .liveAgentScreen
                        } label: {
                            HStack(spacing: 5) {
                                Text("#\(index + 1)")
                                    .font(AstralTheme.mono(9.5).weight(.bold))
                                    .foregroundStyle(isSelected ? .black : AstralTheme.orbGreen)
                                Text(entry.toolName)
                                    .font(AstralTheme.mono(10.5).weight(.semibold))
                                    .foregroundStyle(isSelected ? .black : .white)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? AstralTheme.orbGreen : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

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
