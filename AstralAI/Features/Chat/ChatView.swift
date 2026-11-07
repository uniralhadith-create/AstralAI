import SwiftUI
import Combine

// MARK: - Chat view

/// The Liquid Glass chat experience — and the app's only permanent
/// screen. A compact floating glass header carrying the in-chat model
/// switcher, a live turn-status strip with smooth capsule-clipped shimmer,
/// a date-separated timeline, the composer with "/" skill invocation,
/// and a drawer (date-grouped sessions + a compact 2×2 section
/// grid with custom vector icons).
struct ChatView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @EnvironmentObject private var providerStore: ProviderStore

    @StateObject private var observation = ChatSessionObservation()
    @ObservedObject private var taskBoard = AgentTaskBoard.shared

    @State private var showSidebar = false
    @State private var sidebarSearch = ""

    @State private var cachedModels: [String] = []
    @State private var modelsFailed = false

    // MARK: Suggestions

    private struct Suggestion: Identifiable {
        let id: String
        let icon: String
        let titleKey: String
        let prompt: String
    }

    private static let suggestions: [Suggestion] = [
        Suggestion(
            id: "news",
            icon: AstralIcons.search,
            titleKey: "chat.suggestions.news.title",
            prompt: "Research the latest AI news and give me a briefing with sources"),
        Suggestion(
            id: "trip",
            icon: AstralIcons.map,
            titleKey: "chat.suggestions.trip.title",
            prompt: "Plan a 3-day trip with a full itinerary and budget table"),
        Suggestion(
            id: "script",
            icon: AstralIcons.braces,
            titleKey: "chat.suggestions.script.title",
            prompt: "Write a Python script that renames files by date and save it"),
        Suggestion(
            id: "compare",
            icon: AstralIcons.table,
            titleKey: "chat.suggestions.compare.title",
            prompt: "Compare the top 3 flagship phones this year in a table"),
    ]

    // MARK: Body

    var body: some View {
        ZStack {
            AstralTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                if let session = env.sessionStore.activeSession,
                   session.isBusy || !session.messages.isEmpty || !session.streamingText.isEmpty {
                    conversationView(for: session)
                } else {
                    emptyStateView
                }
            }

            sessionsSidebar
        }
        .onAppear {
            observation.bind(env.sessionStore)
        }
        .task(id: providerStore.activeProviderID) {
            await refreshModels()
        }
    }

    // MARK: Header

    private var headerView: some View {
        HStack(spacing: 8) {
            // Orb 1 — conversation history.
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    showSidebar = true
                }
            } label: {
                AIcon(
                    AstralIcons.sidebar,
                    size: 17,
                    strokeWidth: 2.1,
                    color: AstralTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .liquidGlass(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableOrbStyle())
            .accessibilityLabel(Text(L("chat.sessions", "Chat")))

            // Center bar — the in-chat model switcher.
            modelSelectorPill
                .frame(maxWidth: .infinity)
                .frame(height: 38)

            // Orb 2 — start a new chat.
            Button(action: startNewSession) {
                AIcon(
                    AstralIcons.newChat,
                    size: 17,
                    strokeWidth: 2.1,
                    color: AstralTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .liquidGlass(in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableOrbStyle())
            .accessibilityLabel(Text(L("chat.newChat", "Chat")))
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.top, 5)
    }

    @ViewBuilder
    private var modelSelectorPill: some View {
        let providers = providerStore.providers
        let active = providerStore.active

        if providers.isEmpty {
            Button {
                env.presentSection(.settings)
            } label: {
                HStack(spacing: 6) {
                    AIcon(
                        AstralIcons.plug,
                        size: 13,
                        strokeWidth: 2.2,
                        color: AstralTheme.warning)
                    Text(L("chat.addProvider", "Chat"))
                        .font(AstralTheme.headline(13))
                        .lineLimit(1)
                }
                .foregroundStyle(AstralTheme.warning)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: Capsule(), tint: AstralTheme.warning.opacity(0.08), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                modelMenuContent(providers: providers, active: active)
            } label: {
                HStack(spacing: 7) {
                    if active != nil {
                        if let session = env.sessionStore.activeSession, session.isBusy {
                            ActivityOrb(color: AstralTheme.orbGreen, size: 13)
                        } else {
                            Circle()
                                .fill(AstralTheme.orbGreen)
                                .frame(width: 6.5, height: 6.5)
                        }
                    }

                    Text(modelPillTitle(active))
                        .font(AstralTheme.headline(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)

                    AIcon(
                        AstralIcons.chevronsUpDown,
                        size: 11.5,
                        strokeWidth: 2.3,
                        color: AstralTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7.5)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func modelMenuContent(providers: [ProviderConfig], active: ProviderConfig?) -> some View {
        ForEach(providers) { provider in
            Button {
                env.providerStore.setActive(provider.id)
            } label: {
                if provider.id == active?.id {
                    Label(provider.name, systemImage: "checkmark")
                } else {
                    Text(provider.name)
                }
            }
        }

        Divider()

        Section(L("chat.models", "Chat")) {
            if !cachedModels.isEmpty {
                ForEach(cachedModels, id: \.self) { modelID in
                    Button {
                        selectModel(modelID)
                    } label: {
                        if modelID == active?.mainModel {
                            Label(modelID, systemImage: "checkmark")
                        } else {
                            Text(modelID)
                        }
                    }
                }
            } else if modelsFailed {
                Button {
                    Task { await refreshModels() }
                } label: {
                    Label(L("chat.refreshModels", "Chat"), systemImage: "arrow.clockwise")
                }
            }
        }

        Divider()

        Button {
            env.presentSection(.settings)
        } label: {
            Label(L("chat.manageProviders", "Chat"), systemImage: "gearshape")
        }
    }

    private func modelPillTitle(_ provider: ProviderConfig?) -> String {
        guard let provider else { return "" }
        let model = provider.mainModel
        if model.isEmpty {
            return provider.name
        }
        let parts = model.split(separator: ".")
        if parts.count > 2, model.count > 22 {
            return "\(parts[0]).….\(parts[parts.count - 1])"
        }
        return model.count > 24 ? String(model.prefix(22)) + "…" : model
    }

    private func selectModel(_ modelID: String) {
        guard var config = providerStore.active else { return }
        config.mainModel = modelID
        providerStore.update(config)
    }

    private func refreshModels() async {
        guard let active = providerStore.active else {
            cachedModels = []
            modelsFailed = false
            return
        }
        do {
            let models = try await providerStore.discoverModels(for: active.id)
            cachedModels = models.map(\.id).sorted()
            modelsFailed = false
        } catch {
            cachedModels = []
            modelsFailed = true
        }
    }

    // MARK: Conversation

    private func conversationView(for session: AgentSession) -> some View {
        VStack(spacing: 0) {
            if let status = session.turnStatus {
                TurnStatusStrip(status: status)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let warning = session.toolsWarning {
                ToolsDroppedBanner(message: warning)
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.top, AstralTheme.Spacings.xs)
                    .transition(.opacity)
            }

            if !taskBoard.tasks.isEmpty {
                TaskBoardStrip(board: taskBoard)
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.top, AstralTheme.Spacings.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = session.lastError {
                ErrorBanner(message: error) {
                    session.retry()
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.top, AstralTheme.Spacings.xs)
                .transition(.opacity)
            }

            if let plan = session.plan {
                PlanTrackerView(
                    plan: plan,
                    currentStepIndex: session.currentStepIndex,
                    progress: session.progress)
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.top, AstralTheme.Spacings.xs)
                    .transition(.opacity)
            }

            if !session.subAgents.isEmpty {
                SubAgentBar(agents: session.subAgents)
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.top, AstralTheme.Spacings.xs)
                    .transition(.opacity)
            }

            timelineView(for: session)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: session.turnStatus)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: session.plan == nil)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: session.subAgents.isEmpty)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: session.lastError)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: session.toolsWarning)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: taskBoard.tasks)
    }

    // MARK: Timeline

    private struct TimelineEntry: Identifiable {
        let id: String
        let message: ChatMessage?
        let separatorTitle: String?
        let thinkingGroup: TurnThinkingGroup?

        static func separator(_ title: String, before messageID: UUID) -> TimelineEntry {
            TimelineEntry(id: "sep-\(messageID.uuidString)", message: nil, separatorTitle: title, thinkingGroup: nil)
        }

        static func message(_ message: ChatMessage) -> TimelineEntry {
            TimelineEntry(id: message.id.uuidString, message: message, separatorTitle: nil, thinkingGroup: nil)
        }

        static func thinking(_ group: TurnThinkingGroup) -> TimelineEntry {
            TimelineEntry(id: "think-\(group.id)", message: nil, separatorTitle: nil, thinkingGroup: group)
        }
    }

    private static func stepDetail(for call: ToolCall) -> String {
        let args = call.parsedArguments
        for key in ["query", "command", "url", "path", "title", "name", "code"] {
            if let val = args[key]?.stringValue, !val.isEmpty {
                let flat = val.replacingOccurrences(of: "\n", with: " ")
                return flat.count > 80 ? String(flat.prefix(80)) + "…" : flat
            }
        }
        return ""
    }

    private static func timelineEntries(for messages: [ChatMessage]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        var previousDate: Date?
        let calendar = Calendar.current

        var pendingThoughts: [String] = []
        var pendingSteps: [TurnStepItem] = []
        var seenCallIDs: Set<String> = []
        var currentGroupAnchorID: String = UUID().uuidString

        func flushPendingGroup() {
            guard !pendingThoughts.isEmpty || !pendingSteps.isEmpty else { return }
            let group = TurnThinkingGroup(
                id: currentGroupAnchorID,
                thoughts: pendingThoughts,
                steps: pendingSteps)
            entries.append(.thinking(group))
            pendingThoughts = []
            pendingSteps = []
            seenCallIDs = []
            currentGroupAnchorID = UUID().uuidString
        }

        for index in messages.indices {
            let message = messages[index]

            switch message.role {
            case .system:
                continue

            case .user:
                flushPendingGroup()
                if let previous = previousDate,
                   calendar.isDate(previous, inSameDayAs: message.createdAt) {
                    // Same day
                } else {
                    entries.append(.separator(dayTitle(for: message.createdAt), before: message.id))
                }
                previousDate = message.createdAt
                currentGroupAnchorID = message.id.uuidString
                entries.append(.message(message))

            case .tool:
                let hasMedia = !(message.videos ?? []).isEmpty
                    || (message.name == BrowserScreenshotTool.toolName && !(message.images ?? []).isEmpty)
                if hasMedia {
                    entries.append(.message(message))
                }
                let callID = message.toolCallId ?? message.id.uuidString
                if !seenCallIDs.contains(callID) {
                    seenCallIDs.insert(callID)
                    pendingSteps.append(TurnStepItem(
                        id: callID,
                        toolName: message.name ?? "tool",
                        detail: ""))
                }

            case .assistant:
                let extractedBlocks = TextToolProtocol.extractThinkingBlocks(in: message.content)
                for block in extractedBlocks where !pendingThoughts.contains(block) {
                    pendingThoughts.append(block)
                }

                let explicitCalls = message.toolCalls ?? []
                let embeddedCalls = TextToolProtocol.extractEmbeddedToolCalls(in: message.content)
                let allCalls = explicitCalls + embeddedCalls

                var hasLaterAssistantInTurn = false
                if index + 1 < messages.count {
                    for lookahead in (index + 1)..<messages.count {
                        let nextRole = messages[lookahead].role
                        if nextRole == .user { break }
                        if nextRole == .assistant {
                            let nextClean = TextToolProtocol.cleanVisibleText(messages[lookahead].content)
                            if !nextClean.isEmpty || !(messages[lookahead].toolCalls ?? []).isEmpty {
                                hasLaterAssistantInTurn = true
                                break
                            }
                        }
                    }
                }

                let cleaned = TextToolProtocol.cleanVisibleText(message.content)
                let isIntermediateTurn = !allCalls.isEmpty || hasLaterAssistantInTurn

                if isIntermediateTurn {
                    if !cleaned.isEmpty, !pendingThoughts.contains(cleaned) {
                        pendingThoughts.append(cleaned)
                    }
                    for call in allCalls {
                        if !seenCallIDs.contains(call.id) {
                            seenCallIDs.insert(call.id)
                            pendingSteps.append(TurnStepItem(
                                id: call.id,
                                toolName: call.name,
                                detail: stepDetail(for: call)))
                        }
                    }
                } else {
                    flushPendingGroup()
                    if !cleaned.isEmpty {
                        if let previous = previousDate,
                           calendar.isDate(previous, inSameDayAs: message.createdAt) {
                            // Same day
                        } else {
                            entries.append(.separator(dayTitle(for: message.createdAt), before: message.id))
                        }
                        previousDate = message.createdAt
                        entries.append(.message(message))
                    }
                }
            }
        }

        flushPendingGroup()
        return entries
    }

    private static func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L("chat.today", "Chat") }
        if calendar.isDateInYesterday(date) { return L("chat.yesterday", "Chat") }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: LocalizationManager.shared.effectiveCode == "ar" ? "ar" : "en")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func daySeparator(_ title: String) -> some View {
        Text(title)
            .font(AstralTheme.body(11).weight(.medium))
            .foregroundStyle(AstralTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4.5)
            .liquidCapsule()
            .frame(maxWidth: .infinity)
    }

    private func timelineView(for session: AgentSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    let entries = Self.timelineEntries(for: session.messages)
                    ForEach(entries) { entry in
                        Group {
                            if let group = entry.thinkingGroup {
                                ThinkingStepsDrawer(group: group)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            } else if let message = entry.message {
                                MessageRow(message)
                                    .transition(
                                        .asymmetric(
                                            insertion: .opacity
                                                .combined(with: .move(edge: .bottom)),
                                            removal: .opacity))
                            } else if let title = entry.separatorTitle {
                                daySeparator(title)
                                    .transition(.opacity)
                            }
                        }
                    }

                    if session.isBusy && session.streamingText.isEmpty {
                        StreamingCard(text: "")
                            .transition(
                                .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                    } else if !session.streamingText.isEmpty {
                        StreamingCard(text: session.streamingText)
                            .transition(
                                .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                    }

                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.top, AstralTheme.Spacings.s)
                .padding(.bottom, AstralTheme.Spacings.s)
                .animation(.smooth(duration: 0.32), value: session.messages.count)
                .animation(.smooth(duration: 0.26), value: session.isBusy)
                .animation(.smooth(duration: 0.26), value: session.streamingText.isEmpty)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.messages.count) { _, _ in
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.streamingText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 7) {
                    AstraComputerBar()
                    ComposerView(
                        isStreaming: session.isBusy,
                        onSend: { text, images, videos, attachments in
                            session.send(text, images: images, videos: videos, attachments: attachments)
                        },
                        onStop: { session.cancel() })
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.top, AstralTheme.Spacings.xs)
                .padding(.bottom, AstralTheme.Spacings.xs)
            }
        }
    }

    // MARK: Empty state

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AstralTheme.Spacings.l) {
                    Spacer(minLength: 14)

                    ZStack {
                        Circle()
                            .fill(AstralTheme.actionFill.opacity(0.05))
                            .frame(width: 82, height: 82)
                            .liquidGlass(in: Circle(), interactive: true)

                        Image("AstralMark")
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 54, height: 54)
                            .accessibilityHidden(true)
                    }
                    .shadow(color: Color.black.opacity(0.10), radius: 14, y: 6)

                    Text(L("chat.emptyTitle", "Chat"))
                        .font(AstralTheme.display(31, weight: .semibold))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(L("chat.tagline", "Chat"))
                        .font(AstralTheme.body(15))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, AstralTheme.Spacings.xl)

                    // Live environment pill with custom computer vector icon.
                    HStack(spacing: 7) {
                        Circle()
                            .fill(AstralTheme.orbGreen)
                            .frame(width: 6, height: 6)
                        AstralComputerIcon(
                            size: 13,
                            color: AstralTheme.textSecondary,
                            accentColor: AstralTheme.orbGreen,
                            isActive: true)
                        Text("astra-os · /home/astral · root + web")
                            .font(AstralTheme.mono(10.5))
                            .foregroundStyle(AstralTheme.textSecondary)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .liquidCapsule(interactive: true)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 12) {
                        ForEach(Self.suggestions) { suggestion in
                            suggestionChip(suggestion)
                        }
                    }
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.top, AstralTheme.Spacings.xs)
                }
                .padding(.vertical, AstralTheme.Spacings.m)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 7) {
                AstraComputerBar()
                ComposerView(
                    isStreaming: false,
                    onSend: { text, images, videos, attachments in
                        if let session = env.sessionStore.activeSession, !session.isBusy {
                            session.send(text, images: images, videos: videos, attachments: attachments)
                        } else {
                            startSession(with: text, images: images, videos: videos, attachments: attachments)
                        }
                    },
                    onStop: {})
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.top, AstralTheme.Spacings.xs)
            .padding(.bottom, AstralTheme.Spacings.s)
        }
    }

    private func suggestionChip(_ suggestion: Suggestion) -> some View {
        Button {
            startSession(with: suggestion.prompt, images: [], videos: [], attachments: [])
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AstralTheme.actionFill.opacity(0.08))
                        .frame(width: 30, height: 30)
                    AIcon(
                        suggestion.icon,
                        size: 15,
                        strokeWidth: 2.1,
                        color: AstralTheme.accent)
                }

                Text(L(suggestion.titleKey, "Chat"))
                    .font(AstralTheme.body(13).weight(.medium))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableOrbStyle())
    }

    // MARK: Sessions sidebar

    @ViewBuilder
    private var sessionsSidebar: some View {
        if showSidebar {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            showSidebar = false
                        }
                    }
                    .transition(.opacity)

                sidebarPanel
                    .padding(.horizontal, 10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandRow
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.top, AstralTheme.Spacings.s)
                .padding(.bottom, AstralTheme.Spacings.s)

            // New chat
            Button {
                startNewSession()
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    showSidebar = false
                }
            } label: {
                HStack(spacing: 8) {
                    AIcon(
                        AstralIcons.newChat,
                        size: 15,
                        strokeWidth: 2.2,
                        color: AstralTheme.actionForeground)
                    Text(L("chat.newChat", "Chat"))
                        .font(AstralTheme.headline(14))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassProminentButtonStyle())
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.bottom, AstralTheme.Spacings.s)

            // Search
            HStack(spacing: 8) {
                AIcon(
                    AstralIcons.search,
                    size: 14,
                    strokeWidth: 2.1,
                    color: AstralTheme.textSecondary)
                TextField(
                    L("chat.searchSessions", "Chat"),
                    text: $sidebarSearch)
                    .font(AstralTheme.body(14))
                    .foregroundStyle(AstralTheme.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.bottom, AstralTheme.Spacings.s)

            // Sessions grouped by date
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
                    let groups = groupedSessions
                    if groups.isEmpty {
                        Text(L("chat.noSessions", "Chat"))
                            .font(AstralTheme.body(13))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .padding(.top, AstralTheme.Spacings.l)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(groups, id: \.title) { group in
                            Text(group.title)
                                .font(AstralTheme.mono(10).weight(.semibold))
                                .foregroundStyle(AstralTheme.textSecondary)
                                .padding(.horizontal, 6)
                            ForEach(group.sessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
                .padding(.horizontal, AstralTheme.Spacings.s)
                .padding(.vertical, AstralTheme.Spacings.xs)
            }

            // Sections — the compact 2×2 footer grid with custom Lucide icons
            sectionsGrid
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.top, AstralTheme.Spacings.s)
                .padding(.bottom, AstralTheme.Spacings.s)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AstralTheme.separator)
                        .frame(height: 1)
                }
        }
        .frame(width: 320, alignment: .leading)
        .frame(maxHeight: .infinity)
        .glassCard(cornerRadius: 28, depth: .panel)
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image("AstralMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)

            Text(AppIdentity.appName)
                .font(AstralTheme.headline(15))
                .foregroundStyle(AstralTheme.textPrimary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    showSidebar = false
                }
            } label: {
                AIcon(
                    AstralIcons.sidebar,
                    size: 14,
                    strokeWidth: 2.1,
                    color: AstralTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel(Text(L("chat.sessions", "Chat")))
        }
    }

    private struct SessionGroup {
        let title: String
        let sessions: [AgentSession]
    }

    private var groupedSessions: [SessionGroup] {
        let calendar = Calendar.current
        var today: [AgentSession] = []
        var yesterday: [AgentSession] = []
        var thisWeek: [AgentSession] = []
        var earlier: [AgentSession] = []

        for session in filteredSessions {
            if calendar.isDateInToday(session.createdAt) {
                today.append(session)
            } else if calendar.isDateInYesterday(session.createdAt) {
                yesterday.append(session)
            } else {
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: session.createdAt),
                    to: calendar.startOfDay(for: Date())).day ?? -1
                if days >= 0, days < 7 {
                    thisWeek.append(session)
                } else {
                    earlier.append(session)
                }
            }
        }

        var groups: [SessionGroup] = []
        if !today.isEmpty {
            groups.append(SessionGroup(title: L("chat.history.today", "Chat"), sessions: today))
        }
        if !yesterday.isEmpty {
            groups.append(SessionGroup(title: L("chat.history.yesterday", "Chat"), sessions: yesterday))
        }
        if !thisWeek.isEmpty {
            groups.append(SessionGroup(title: L("chat.history.thisWeek", "Chat"), sessions: thisWeek))
        }
        if !earlier.isEmpty {
            groups.append(SessionGroup(title: L("chat.history.earlier", "Chat"), sessions: earlier))
        }
        return groups
    }

    private var filteredSessions: [AgentSession] {
        let sessions = env.sessionStore.sessions
        guard !sidebarSearch.trimmingCharacters(in: .whitespaces).isEmpty else {
            return sessions
        }
        let query = sidebarSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return sessions.filter { $0.title.lowercased().contains(query) }
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        let isActive = session.id == env.sessionStore.activeSession?.id
        return Button {
            env.sessionStore.select(session)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showSidebar = false
            }
        } label: {
            sessionRowLabel(session, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sessionRowLabel(_ session: AgentSession, isActive: Bool) -> some View {
        if isActive {
            sessionRowContent(session, isActive: true)
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous),
                    tint: AstralTheme.actionFill.opacity(0.12))
        } else {
            sessionRowContent(session, isActive: false)
        }
    }

    private func sessionRowContent(_ session: AgentSession, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title.isEmpty ? L("chat.untitled", "Chat") : session.title)
                    .font(AstralTheme.body(14).weight(isActive ? .semibold : .regular))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)

                Text(Self.relativeDate(session.createdAt))
                    .font(AstralTheme.body(11))
                    .foregroundStyle(AstralTheme.textSecondary)
            }

            Spacer(minLength: 4)

            if session.isBusy {
                ActivityOrb(color: AstralTheme.orbGreen, size: 12)
            }

            Button(role: .destructive) {
                env.sessionStore.delete(session)
            } label: {
                AIcon(
                    AstralIcons.trash,
                    size: 13,
                    strokeWidth: 2.0,
                    color: AstralTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(String(format: L("chat.deleteChat", "Chat"), session.title)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sectionsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8) {
            ForEach([AppTab.skills, .browser, .files, .settings]) { section in
                sectionTile(section)
            }
        }
    }

    private func sectionAstralIcon(for section: AppTab) -> String {
        switch section {
        case .chat: return AstralIcons.chat
        case .skills: return AstralIcons.puzzle
        case .browser: return AstralIcons.browser
        case .files: return AstralIcons.folder
        case .settings: return AstralIcons.settings
        }
    }

    private func sectionTile(_ section: AppTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                showSidebar = false
            }
            env.presentSection(section)
        } label: {
            VStack(spacing: 6) {
                AIcon(
                    sectionAstralIcon(for: section),
                    size: 16,
                    strokeWidth: 2.1,
                    color: AstralTheme.textPrimary)

                Text(section.localizedTitle)
                    .font(AstralTheme.headline(11))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .liquidGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableOrbStyle())
        .accessibilityLabel(Text(section.localizedTitle))
    }

    // MARK: Actions

    private func startNewSession() {
        let session = env.sessionStore.newSession()
        env.sessionStore.select(session)
    }

    private func startSession(
        with prompt: String,
        images: [MessageImage],
        videos: [MessageVideo] = [],
        attachments: [MessageAttachment]
    ) {
        let session = env.sessionStore.newSession()
        env.sessionStore.select(session)
        session.send(prompt, images: images, videos: videos, attachments: attachments)
    }

    private static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Turn status strip

private struct TurnStatusStrip: View {
    let status: TurnStatus

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                StatusOrb()
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(status.label)
                        .font(AstralTheme.headline(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                        .contentTransition(.numericText())

                    if !status.detail.isEmpty {
                        Text(status.detail)
                            .font(AstralTheme.body(11))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AstralTheme.Spacings.s)

                Text(percentText)
                    .font(AstralTheme.mono(12).weight(.bold))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            GlassProgressView(progress: status.progress, height: 4.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: AstralTheme.actionFill.opacity(0.05),
            interactive: true)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: status)
    }

    private var percentText: String {
        "\(Int((min(max(status.progress, 0), 1)) * 100))%"
    }
}

/// The status orb — a monochrome sphere with a slow orbiting highlight.
private struct StatusOrb: View {
    @State private var orbit = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AstralTheme.actionFill,
                            AstralTheme.actionFill.opacity(0.35),
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 9))

            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 5)
                .offset(x: orbit ? 4.5 : -4.5, y: orbit ? -3 : 3)
                .blur(radius: 0.8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                orbit = true
            }
        }
    }
}

// MARK: - Task board strip

private struct TaskBoardStrip: View {
    @ObservedObject var board: AgentTaskBoard

    @State private var collapsed = false

    private var progress: Double {
        guard !board.tasks.isEmpty else { return 0 }
        return Double(board.completedCount) / Double(board.tasks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    collapsed.toggle()
                }
            } label: {
                VStack(spacing: 9) {
                    HStack(spacing: 10) {
                        Text("\(board.completedCount)/\(board.tasks.count)")
                            .font(AstralTheme.mono(11).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AstralTheme.textPrimary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .liquidCapsule(
                                tint: AstralTheme.actionFill.opacity(0.16),
                                interactive: true)

                        AIcon(
                            AstralIcons.todo,
                            size: 13.5,
                            strokeWidth: 2.2,
                            color: AstralTheme.textSecondary)

                        Text(L("chat.tasks", "Chat"))
                            .font(AstralTheme.headline(13.5))
                            .foregroundStyle(AstralTheme.textPrimary)

                        Spacer(minLength: 4)

                        AIcon(
                            AstralIcons.chevronDown,
                            size: 12,
                            strokeWidth: 2.3,
                            color: AstralTheme.textSecondary)
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }

                    if !collapsed {
                        GlassProgressView(progress: progress, height: 5)
                            .padding(.top, 2)
                    }
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(board.tasks) { task in
                        taskRow(task)
                    }
                }
                .transition(
                    .opacity.combined(
                        with: .move(edge: .top).combined(with: .scale(scale: 0.98, anchor: .top))))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: AstralTheme.actionFill.opacity(0.06),
            interactive: true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: board.tasks)
    }

    @ViewBuilder
    private func taskRow(_ task: AgentTask) -> some View {
        let inProgress = task.status == .inProgress
        let done = task.status == .completed

        HStack(alignment: .top, spacing: 10) {
            Group {
                if inProgress {
                    ActivityOrb(color: AstralTheme.orbGreen, size: 14)
                } else if done {
                    ZStack {
                        Circle()
                            .fill(AstralTheme.success)
                            .frame(width: 14, height: 14)
                        AIcon(AstralIcons.check, size: 8.5, strokeWidth: 3.0, color: .white)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(AstralTheme.moonDust.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.top, 1.5)

            Text(task.title)
                .font(AstralTheme.headline(13.5))
                .foregroundStyle(inProgress
                    ? AstralTheme.textPrimary
                    : AstralTheme.textSecondary)
                .strikethrough(done)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(inProgress ? AstralTheme.actionFill.opacity(0.06) : Color.clear))
        .shimmer(active: inProgress, cornerRadius: 11)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: task.status)
    }
}

// MARK: - Tools dropped banner

private struct ToolsDroppedBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.28))

            Text(message)
                .font(AstralTheme.body(12.5))
                .foregroundStyle(AstralTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Session observation

@MainActor
private final class ChatSessionObservation: ObservableObject {
    private var storeCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?
    private var currentSessionID: UUID?

    func bind(_ store: SessionStore) {
        guard storeCancellable == nil else {
            sync(with: store)
            return
        }
        storeCancellable = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sync(with: store)
            }
        sync(with: store)
    }

    private func sync(with store: SessionStore) {
        let session = store.activeSession
        guard session?.id != currentSessionID else {
            objectWillChange.send()
            return
        }
        currentSessionID = session?.id
        sessionCancellable = session?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }
}
