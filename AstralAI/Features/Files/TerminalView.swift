import SwiftUI

// MARK: - Terminal card (chat — System-Adaptive iOS 27 Liquid Glass)

/// System-adaptive iOS 27 Liquid Glass terminal card for `exec` tool results:
/// shows the command line and its output inside a native `.liquidGlass` surface.
/// Collapsed by default, expands on tap.
struct TerminalCard: View {
    let message: ChatMessage

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(AstralTheme.separator)

            VStack(alignment: .leading, spacing: 6) {
                // Command line
                HStack(alignment: .top, spacing: 6) {
                    Text("$")
                        .font(AstralTheme.mono(12).weight(.bold))
                        .foregroundStyle(AstralTheme.orbGreen)
                    Text(commandLine)
                        .font(AstralTheme.mono(12).weight(.medium))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Output
                if !outputText.isEmpty {
                    Text(outputText)
                        .font(AstralTheme.mono(11.5))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .liquidGlass(in: RoundedRectangle(cornerRadius: 15, style: .continuous), interactive: true)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture {
            withAnimation(.smooth(duration: 0.22)) { expanded.toggle() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AIcon(
                AstralIcons.computer,
                size: 13,
                strokeWidth: 2.0,
                color: AstralTheme.textSecondary)

            Text("astra-os 5.0")
                .font(AstralTheme.mono(10.5).weight(.semibold))
                .foregroundStyle(AstralTheme.textSecondary)

            Text("· exec")
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.moonDust)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(expanded
                ? L("sandbox.collapse", "Files")
                : L("sandbox.expand", "Files"))
                .font(AstralTheme.mono(10).weight(.semibold))
                .foregroundStyle(AstralTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AstralTheme.actionFill.opacity(0.04))
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

// MARK: - Live terminal (Agent activity + Shell — V5.0.0 System-Adaptive iOS 27 Liquid Glass)

/// The user's window into the astra-os 5.0 machine, rendered in 100%
/// system-adaptive iOS 27 Liquid Glass with three tabs:
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
            .background(AstralTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    GlassCloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        AIcon(
                            AstralIcons.computer,
                            size: 16,
                            strokeWidth: 2.0,
                            color: AstralTheme.textPrimary)
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
                            .frame(width: 34, height: 34)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .accessibilityLabel(Text(L("sandbox.clear", "Files")))
                }
            }
        }
        .environment(\.layoutDirection, language.layoutDirection)
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
        .liquidCapsule(interactive: true)
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
        let isSelected = tab == id
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { tab = id }
        } label: {
            HStack(spacing: 6) {
                AIcon(
                    icon,
                    size: 12,
                    strokeWidth: 2.2,
                    color: isSelected ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                Text(label)
                    .font(AstralTheme.headline(12.5))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AstralTheme.actionForeground : AstralTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(AstralTheme.actionFill)
                        .matchedGeometryEffect(id: "terminal-tab-thumb", in: tabThumb)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick commands bar

    private func quickCommandsStrip(forCloud: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
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
                            .foregroundStyle(AstralTheme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                            .liquidCapsule(interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
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

    /// The V5 empty state — features the system-adaptive `AIcon(AstralIcons.computer)`
    /// inside an iOS 27 Liquid Glass circle.
    private var agentEmptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 28)

            ZStack {
                Circle()
                    .frame(width: 108, height: 108)
                    .liquidGlass(in: Circle(), tint: AstralTheme.orbGreen.opacity(0.08), interactive: true)

                AIcon(
                    AstralIcons.computer,
                    size: 46,
                    strokeWidth: 1.9,
                    color: AstralTheme.textPrimary)
            }
            .accessibilityHidden(true)

            Text(L("sandbox.computerIdle", "Files"))
                .font(AstralTheme.headline(14.5))
                .foregroundStyle(AstralTheme.textPrimary)

            Text(L("sandbox.activity.empty", "Files"))
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.textSecondary)
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
                                .foregroundStyle(AstralTheme.textSecondary)
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
                .foregroundStyle(AstralTheme.textSecondary)
            Text("Type `help` or `neofetch` to inspect your Linux system.")
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(AstralTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func entryView(_ entry: SandboxEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(prompt):\(shell.cwd == SandboxShell.homePath ? "~" : shell.cwd)# ")
                    .font(AstralTheme.mono(12).weight(.semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
                Text(entry.command)
                    .font(AstralTheme.mono(12))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .textSelection(.enabled)
            }

            if !entry.output.isEmpty {
                Text(entry.output)
                    .font(AstralTheme.mono(11.5))
                    .foregroundStyle(
                        entry.exitCode == 0
                            ? AstralTheme.textSecondary
                            : AstralTheme.danger)
                    .textSelection(.enabled)
            }

            Text(String(
                format: L("sandbox.exitMeta", "Files"),
                entry.exitCode, entry.duration))
                .font(AstralTheme.mono(9.5))
                .foregroundStyle(AstralTheme.moonDust)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                .foregroundStyle(AstralTheme.textPrimary)
                .tint(AstralTheme.orbGreen)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(runDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: runDraft) {
                ZStack {
                    if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Circle()
                            .frame(width: 28, height: 28)
                            .liquidGlass(in: Circle(), interactive: true)
                    } else {
                        Circle()
                            .fill(AstralTheme.orbGreen)
                            .frame(width: 28, height: 28)
                    }
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 14,
                        strokeWidth: 2.5,
                        color: draft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AstralTheme.textSecondary
                            : .black)
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || shell.busy)
            .accessibilityLabel(Text(L("sandbox.run", "Files")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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

                    if !cloud.liveOutput.isEmpty {
                        Text(cloud.liveOutput)
                            .font(AstralTheme.mono(11.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if cloudRunning {
                        HStack(spacing: 6) {
                            ActivityOrb(color: AstralTheme.orbGreen, size: 10)
                            Text(L("sandbox.cloudBooting", "Files"))
                                .font(AstralTheme.mono(11))
                                .foregroundStyle(AstralTheme.textSecondary)
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
                .foregroundStyle(AstralTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("root@astral-cloud:~# ")
                .font(AstralTheme.mono(11.5))
                .foregroundStyle(AstralTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .foregroundStyle(AstralTheme.textPrimary)
                .tint(AstralTheme.orbGreen)
                .focused($cloudFocused)
                .submitLabel(.go)
                .onSubmit(runCloudDraft)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button(action: runCloudDraft) {
                ZStack {
                    if cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Circle()
                            .frame(width: 28, height: 28)
                            .liquidGlass(in: Circle(), interactive: true)
                    } else {
                        Circle()
                            .fill(AstralTheme.orbGreen)
                            .frame(width: 28, height: 28)
                    }
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 14,
                        strokeWidth: 2.5,
                        color: cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AstralTheme.textSecondary
                            : .black)
                }
            }
            .disabled(cloudDraft.trimmingCharacters(in: .whitespaces).isEmpty || cloudRunning)
            .accessibilityLabel(Text(L("sandbox.run", "Files")))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(in: Capsule(), interactive: true)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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

// MARK: - Agent activity row (System-Adaptive iOS 27 Liquid Glass)

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
                    color: AstralTheme.textPrimary)
                    .frame(width: 24, height: 24)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(entry.toolName)
                    .font(AstralTheme.mono(11.5).weight(.semibold))
                    .foregroundStyle(AstralTheme.textPrimary)

                Spacer(minLength: 6)

                if entry.status == .running {
                    HStack(spacing: 5) {
                        ActivityOrb(
                            color: AstralTheme.orbGreen,
                            size: 8)
                        Text(L("sandbox.working", "Files"))
                            .font(AstralTheme.mono(10))
                            .foregroundStyle(AstralTheme.textSecondary)
                    }
                } else if let duration = entry.duration {
                    Text(String(format: "%.1fs", duration))
                        .font(AstralTheme.mono(10).weight(.semibold))
                        .foregroundStyle(entry.status == .failed
                            ? AstralTheme.danger
                            : AstralTheme.textSecondary)
                    ZStack {
                        Circle()
                            .fill(entry.status == .failed
                                ? AstralTheme.danger
                                : AstralTheme.orbGreen)
                            .frame(width: 13, height: 13)
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
                    .foregroundStyle(AstralTheme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !entry.outputPreview.isEmpty {
                Text(entry.outputPreview)
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(entry.status == .failed
                        ? AstralTheme.danger
                        : AstralTheme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 13, style: .continuous),
            tint: entry.status == .failed ? AstralTheme.danger.opacity(0.08) : .clear,
            interactive: true)
        .shimmer(active: entry.status == .running, cornerRadius: 13)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture {
            withAnimation(.smooth(duration: 0.2)) { expanded.toggle() }
        }
    }
}
