import SwiftUI

// MARK: - Connectors, Plugins & MCP Hub View

struct ConnectorsView: View {
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var store = ConnectorStore.shared
    @ObservedObject private var telegram = TelegramAgentService.shared

    @State private var selectedCategory: ConnectorCategory? = nil
    @State private var searchText: String = ""
    @State private var editingConnector: ConnectorKind? = nil
    @State private var showAddMCPSheet: Bool = false
    @State private var showTelegramConsole: Bool = false

    // Add MCP form state
    @State private var newMCPName: String = ""
    @State private var newMCPURL: String = ""
    @State private var newMCPToken: String = ""

    private var isArabic: Bool {
        language.effectiveCode == "ar"
    }

    private var filteredConnectors: [ConnectorKind] {
        ConnectorKind.allCases.filter { kind in
            if let cat = selectedCategory, kind.category != cat { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return kind.displayName.localizedCaseInsensitiveContains(q)
                || kind.localizedSubtitle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero Status Strip
                headerSummaryCard

                // Live Telegram Bot Agent Quick Control Card
                telegramAgentControlCard

                // MCP Servers Quick Section
                mcpServersCard

                // Search & Category Filter
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        AIcon(AstralIcons.search, size: 14, strokeWidth: 2, color: AstralTheme.textSecondary)
                        TextField(isArabic ? "ابحث في الموصلات والإضافات..." : "Search plugins & connectors...", text: $searchText)
                            .font(AstralTheme.body(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            categoryChip(title: isArabic ? "الكل" : "All", category: nil)
                            ForEach(ConnectorCategory.allCases) { cat in
                                categoryChip(title: cat.title, category: cat)
                            }
                        }
                    }
                }

                // Connectors List with Branded Icons
                LazyVStack(spacing: 10) {
                    ForEach(filteredConnectors) { kind in
                        connectorRow(kind)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(AstralTheme.background.ignoresSafeArea())
        .sheet(item: $editingConnector) { kind in
            ConnectorConfigSheet(kind: kind)
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
        }
        .sheet(isPresented: $showAddMCPSheet) {
            addMCPServerSheet
                .environment(\.layoutDirection, language.layoutDirection)
        }
        .sheet(isPresented: $showTelegramConsole) {
            TelegramConsoleSheet()
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
        }
    }

    // MARK: - Header Summary

    private var headerSummaryCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AstralTheme.orbGreen.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AstralTheme.orbGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(isArabic ? "الموصلات، الإضافات و MCP" : "Connectors, Plugins & MCP")
                    .font(AstralTheme.headline(16))
                    .foregroundStyle(AstralTheme.textPrimary)
                Text(isArabic
                     ? "\(store.activeCount) موصّل نشط · متاحة للوكيل تلقائياً"
                     : "\(store.activeCount) active connectors · available to Agent")
                    .font(AstralTheme.body(12))
                    .foregroundStyle(AstralTheme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(cornerRadius: 20, depth: .panel)
    }

    // MARK: - Telegram Bot Agent Card

    private var telegramAgentControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ConnectorBrandIcon(kind: .telegram, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isArabic ? "وكيل تليجرام الذكي" : "Telegram AI Agent")
                            .font(AstralTheme.headline(14.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                        if telegram.isPolling {
                            Text(isArabic ? "يعمل الآن" : "LIVE")
                                .font(AstralTheme.mono(9.5).weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AstralTheme.orbGreen))
                        }
                    }
                    Text(telegram.botInfo.map { "@\($0.username)" }
                         ?? (isArabic ? "جاهز للربط والرد التلقائي على رسائل تليجرام" : "Ready to connect & auto-reply on Telegram"))
                        .font(AstralTheme.mono(11))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    if telegram.isPolling {
                        telegram.stopAgentPolling()
                    } else {
                        telegram.startAgentPolling()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: telegram.isPolling ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(telegram.isPolling
                             ? (isArabic ? "إيقاف الرد التلقائي" : "Stop Auto-Reply")
                             : (isArabic ? "تشغيل وكيل تليجرام" : "Start Telegram Agent"))
                            .font(AstralTheme.headline(12))
                    }
                    .foregroundStyle(telegram.isPolling ? AstralTheme.danger : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(telegram.isPolling ? AstralTheme.danger.opacity(0.15) : AstralTheme.orbGreen))
                }
                .buttonStyle(.plain)

                Button {
                    showTelegramConsole = true
                } label: {
                    Text(isArabic ? "السجل والتحكم" : "Console")
                        .font(AstralTheme.headline(12))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let err = telegram.lastError {
                Text(err)
                    .font(AstralTheme.mono(10.5))
                    .foregroundStyle(AstralTheme.danger)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 20, depth: .panel)
    }

    // MARK: - MCP Servers Card

    private var mcpServersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ConnectorBrandIcon(kind: .mcp, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isArabic ? "خوادم MCP (Model Context Protocol)" : "MCP Servers")
                        .font(AstralTheme.headline(14))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Text(isArabic ? "\(store.mcpServers.count) خادم مضاف" : "\(store.mcpServers.count) configured servers")
                        .font(AstralTheme.mono(10.5))
                        .foregroundStyle(AstralTheme.textSecondary)
                }
                Spacer()
                Button {
                    showAddMCPSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(isArabic ? "إضافة MCP" : "Add MCP")
                            .font(AstralTheme.headline(11.5))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(AstralTheme.orbGreen))
                }
                .buttonStyle(.plain)
            }

            ForEach(store.mcpServers) { server in
                HStack(spacing: 10) {
                    Circle()
                        .fill(server.isEnabled ? AstralTheme.orbGreen : AstralTheme.moonDust)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(AstralTheme.headline(12.5))
                            .foregroundStyle(AstralTheme.textPrimary)
                        Text("\(server.endpointURL) · \(server.discoveredTools.count) tools")
                            .font(AstralTheme.mono(10))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { _ = await store.refreshMCPTools(for: server.id) }
                    } label: {
                        AIcon(AstralIcons.refresh, size: 13, strokeWidth: 2, color: AstralTheme.accent)
                            .padding(6)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.deleteMCPServer(server.id)
                    } label: {
                        AIcon(AstralIcons.trash, size: 13, strokeWidth: 2, color: AstralTheme.danger)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AstralTheme.actionFill.opacity(0.04)))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 20, depth: .panel)
    }

    private func categoryChip(title: String, category: ConnectorCategory?) -> some View {
        let active = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedCategory = category
            }
        } label: {
            Text(title)
                .font(AstralTheme.headline(11.5))
                .foregroundStyle(active ? .black : AstralTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(active ? AstralTheme.orbGreen : AstralTheme.actionFill.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func connectorRow(_ kind: ConnectorKind) -> some View {
        let active = store.isActive(kind)
        return Button {
            editingConnector = kind
        } label: {
            HStack(spacing: 12) {
                ConnectorBrandIcon(kind: kind, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(kind.displayName)
                            .font(AstralTheme.headline(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                        if active {
                            Text(isArabic ? "متصل" : "ACTIVE")
                                .font(AstralTheme.mono(9).weight(.bold))
                                .foregroundStyle(AstralTheme.orbGreen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AstralTheme.orbGreen.opacity(0.15)))
                        }
                    }
                    Text(kind.localizedSubtitle)
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                AIcon(AstralIcons.chevronForward, size: 12, strokeWidth: 2.2, color: AstralTheme.textSecondary)
                    .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            }
            .padding(12)
            .glassCard(cornerRadius: 18, depth: .panel)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add MCP Server Sheet

    private var addMCPServerSheet: some View {
        NavigationStack {
            Form {
                Section(isArabic ? "بيانات خادم MCP" : "MCP Server Details") {
                    TextField(isArabic ? "اسم الخادم (مثال: GitHub MCP)" : "Server Name (e.g. GitHub MCP)", text: $newMCPName)
                    TextField("https://your-mcp-server.com/mcp", text: $newMCPURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(isArabic ? "Bearer Token (اختياري)" : "Bearer Token (optional)", text: $newMCPToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(isArabic ? "إضافة خادم MCP" : "Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel", "Shared")) { showAddMCPSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save", "Shared")) {
                        store.addMCPServer(name: newMCPName, endpointURL: newMCPURL, bearerToken: newMCPToken)
                        newMCPName = ""
                        newMCPURL = ""
                        newMCPToken = ""
                        showAddMCPSheet = false
                    }
                    .disabled(newMCPURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Connector Configuration Sheet

private struct ConnectorConfigSheet: View {
    let kind: ConnectorKind
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var store = ConnectorStore.shared

    @State private var tokenInput: String = ""
    @State private var secondaryInput: String = ""
    @State private var isEnabled: Bool = false
    @State private var testing: Bool = false
    @State private var testFeedback: (ok: Bool, message: String)?

    private var isArabic: Bool { language.effectiveCode == "ar" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        ConnectorBrandIcon(kind: kind, size: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.displayName)
                                .font(AstralTheme.headline(17))
                                .foregroundStyle(AstralTheme.textPrimary)
                            Text(kind.localizedSubtitle)
                                .font(AstralTheme.body(12.5))
                                .foregroundStyle(AstralTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 20, depth: .panel)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $isEnabled) {
                            Text(isArabic ? "تفعيل للوكيل الذكي" : "Enable for AI Agent")
                                .font(AstralTheme.headline(14))
                                .foregroundStyle(AstralTheme.textPrimary)
                        }
                        .tint(AstralTheme.orbGreen)

                        if let secLabel = kind.secondaryLabel {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(secLabel)
                                    .font(AstralTheme.mono(11).weight(.semibold))
                                    .foregroundStyle(AstralTheme.textSecondary)
                                TextField("https://...", text: $secondaryInput)
                                    .font(AstralTheme.mono(12.5))
                                    .textFieldStyle(GlassTextFieldStyle())
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(kind.tokenLabel)
                                .font(AstralTheme.mono(11).weight(.semibold))
                                .foregroundStyle(AstralTheme.textSecondary)
                            SecureField("••••••••••••", text: $tokenInput)
                                .font(AstralTheme.mono(12.5))
                                .textFieldStyle(GlassTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        HStack(spacing: 10) {
                            Button {
                                saveFields()
                                testing = true
                                Task {
                                    let res = await store.testConnection(for: kind)
                                    testing = false
                                    testFeedback = res
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if testing { ProgressView().controlSize(.mini) }
                                    Text(isArabic ? "اختبار الاتصال" : "Test Connection")
                                        .font(AstralTheme.headline(13))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                saveFields()
                                dismiss()
                            } label: {
                                Text(L("common.save", "Shared"))
                                    .font(AstralTheme.headline(13))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AstralTheme.orbGreen))
                            }
                            .buttonStyle(.plain)
                        }

                        if let feedback = testFeedback {
                            Text(feedback.message)
                                .font(AstralTheme.body(12))
                                .foregroundStyle(feedback.ok ? AstralTheme.orbGreen : AstralTheme.danger)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill((feedback.ok ? AstralTheme.orbGreen : AstralTheme.danger).opacity(0.12)))
                        }

                        if let url = URL(string: kind.docsURL) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    AIcon(AstralIcons.externalLink, size: 12, strokeWidth: 2, color: AstralTheme.accent)
                                    Text(isArabic ? "الحصول على المفتاح / التوثيق الرسمي" : "Get API Key / Official Docs")
                                        .font(AstralTheme.body(12.5))
                                        .foregroundStyle(AstralTheme.accent)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 20, depth: .panel)
                }
                .padding(14)
            }
            .background(AstralTheme.background.ignoresSafeArea())
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.done", "Shared")) { dismiss() }
                }
            }
            .onAppear {
                tokenInput = store.token(for: kind)
                secondaryInput = store.secondaryValue(for: kind)
                isEnabled = store.isEnabled(kind)
            }
        }
    }

    private func saveFields() {
        store.setToken(tokenInput, for: kind)
        store.setSecondaryValue(secondaryInput, for: kind)
        store.setEnabled(isEnabled, for: kind)
    }
}

// MARK: - Telegram Bot Live Console Sheet

private struct TelegramConsoleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var telegram = TelegramAgentService.shared

    @State private var manualChatID: String = ""
    @State private var manualMessage: String = ""

    private var isArabic: Bool { language.effectiveCode == "ar" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $telegram.autoReplyEnabled) {
                            Text(isArabic ? "الرد التلقائي بالذكاء الاصطناعي" : "AI Auto-Reply to Incoming Messages")
                                .font(AstralTheme.headline(13.5))
                        }
                        .tint(AstralTheme.orbGreen)

                        TextField(
                            isArabic ? "Chat IDs المسموح لها (اتركه فارغاً للجميع)" : "Allowed Chat IDs (comma-separated, blank = all)",
                            text: $telegram.allowedChatIDsText)
                            .font(AstralTheme.mono(12))
                            .textFieldStyle(GlassTextFieldStyle())
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 18, depth: .panel)

                    // Manual Send Box
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isArabic ? "إرسال رسالة يدوية عبر البوت" : "Send Manual Bot Message")
                            .font(AstralTheme.headline(13))
                        TextField("Chat ID", text: $manualChatID)
                            .font(AstralTheme.mono(12))
                            .textFieldStyle(GlassTextFieldStyle())
                            .keyboardType(.numbersAndPunctuation)
                        HStack(spacing: 8) {
                            TextField(isArabic ? "نص الرسالة..." : "Message...", text: $manualMessage)
                                .font(AstralTheme.body(13))
                                .textFieldStyle(GlassTextFieldStyle())
                            Button(isArabic ? "إرسال" : "Send") {
                                guard let cid = Int64(manualChatID.trimmingCharacters(in: .whitespacesAndNewlines)),
                                      !manualMessage.isEmpty else { return }
                                let txt = manualMessage
                                manualMessage = ""
                                Task { try? await telegram.sendMessage(chatID: cid, text: txt) }
                            }
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(AstralTheme.orbGreen))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 18, depth: .panel)

                    // Live Activity Log
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isArabic ? "سجل رسائل تليجرام المباشر" : "Live Telegram Message Log")
                                .font(AstralTheme.headline(13.5))
                            Spacer()
                            if !telegram.logs.isEmpty {
                                Button(isArabic ? "مسح" : "Clear") { telegram.clearLogs() }
                                    .font(AstralTheme.mono(11))
                                    .foregroundStyle(AstralTheme.textSecondary)
                            }
                        }

                        if telegram.logs.isEmpty {
                            Text(isArabic
                                 ? "ابدأ تشغيل وكيل تليجرام وأرسل رسالة للبوت في تليجرام لتظهر هنا فوراً."
                                 : "Start the Telegram agent and message your bot in Telegram to see live replies here.")
                                .font(AstralTheme.body(12))
                                .foregroundStyle(AstralTheme.textSecondary)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(telegram.logs) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(entry.senderName)
                                            .font(AstralTheme.headline(12))
                                            .foregroundStyle(AstralTheme.textPrimary)
                                        Spacer()
                                        Text("ID: \(entry.chatID)")
                                            .font(AstralTheme.mono(10))
                                            .foregroundStyle(AstralTheme.textSecondary)
                                    }
                                    Text(entry.incomingText)
                                        .font(AstralTheme.body(12.5))
                                        .foregroundStyle(AstralTheme.textPrimary)
                                    if let reply = entry.replyText {
                                        Text("↳ \(reply)")
                                            .font(AstralTheme.body(12))
                                            .foregroundStyle(entry.isError ? AstralTheme.danger : AstralTheme.orbGreen)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AstralTheme.actionFill.opacity(0.05)))
                            }
                        }
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 18, depth: .panel)
                }
                .padding(14)
            }
            .background(AstralTheme.background.ignoresSafeArea())
            .navigationTitle(isArabic ? "تحكم وكيل تليجرام" : "Telegram Agent Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.done", "Shared")) { dismiss() }
                }
            }
        }
    }
}
