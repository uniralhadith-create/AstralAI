import SwiftUI

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
                // Command line
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

                // Output
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

            Text("astra-os 5.0")
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

// MARK: - Live terminal (Agent activity + Shell — V5.0.0)

/// The user's window into the astra-os 5.0 machine, with two/three tabs:
/// - **Agent** — the live feed of everything the AI is doing right now.
/// - **Shell** — a real, tappable Linux terminal over `/home/astral`.
/// - **Cloud** — dedicated E2B Ubuntu Linux console when configured.
struct TerminalView: View {
    private enum Tab {
        case agent
        case shell
        case cloud
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var shell = SandboxShell.shared
    @ObservedObject private var activity = AgentActivityLog.shared
    @ObservedObject private var cloud = E2BComputer.shared
    @ObservedObject private var modeController = ComputerModeController.shared
    @EnvironmentObject private var language: LocalizationManager

    @State private var tab: Tab = .agent
    @State private var draft = ""
    @State private var cloudDraft = ""
    @State private var cloudRunning = false
    @Namespace private var tabThumb
    @FocusState private var focused: Bool
    @FocusState private var cloudFocused: Bool

    private let prompt = "root@astra-os"

    private let quickCommands = [
        "ls -la", "neofetch", "ps aux", "df -h", "git status", "uname -a", "help"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker

                switch tab {
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
    }

    private var subtitleText: String {
        switch tab {
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
                id: .agent,
                icon: AstralIcons.sparkles,
                label: L("sandbox.tab.agent", "Files"))
            tabButton(
                id: .shell,
                icon: AstralIcons.terminal,
                label: shellTabTitle)
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

    /// The V5 empty state — features the large custom `AstralComputerIcon`
    /// workstation display instead of raw rectangles.
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
            Text("astra-os 5.0.0 — \(SandboxShell.osName)")
                .font(AstralTheme.mono(12).weight(.semibold))
                .foregroundStyle(AstralTheme.orbGreen)
            Text(L("sandbox.welcome", "Files"))
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(Color.white.opacity(0.55))
            Text("Type `help` or `neofetch` to inspect your Linux system.")
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
            Text("Astral Cloud Linux V5 — Ubuntu (E2B microVM · Root Enabled)")
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
