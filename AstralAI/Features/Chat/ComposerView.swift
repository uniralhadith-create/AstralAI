import SwiftUI
import PhotosUI
import UIKit

// MARK: - Composer (V5.0.0 — Pure System-Adaptive iOS 27 Liquid Glass)

/// The V5 Liquid Glass composer: every element — the main composer bar,
/// the photo and plus controls, the agent-mode and skills capsules, the
/// send/stop button, and the "/" slash skill overlay — uses native
/// system-adaptive iOS 26/27 `liquidGlass` so it blends and refracts with
/// the system appearance.
struct ComposerView: View {
    let isStreaming: Bool
    var onSend: (String, [MessageImage], [MessageAttachment]) -> Void
    var onStop: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var skillStore = SkillStore.shared
    @FocusState private var focused: Bool

    @State private var draft = ""
    @State private var pendingImages: [MessageImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingImages = false
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var showingFilePicker = false

    @State private var armedSkillName: String?
    @State private var armedSkillID: UUID?

    @State private var showingActionPanel = false

    @AppStorage("astral.agentMode") private var agentMode = false

    private let maxImages = 4
    private let maxFiles = 4
    private let maxSlashRows = 8

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        (!trimmedDraft.isEmpty || !pendingImages.isEmpty || !pendingAttachments.isEmpty)
            && !isStreaming
            && !importingImages
    }

    private var slashQuery: String? {
        guard draft.hasPrefix("/") else { return nil }
        return String(draft.dropFirst())
    }

    private var showsSlashOverlay: Bool {
        slashQuery != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if showsSlashOverlay {
                slashOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composerSurface
        }
        .animation(.smooth(duration: 0.2), value: showsSlashOverlay)
        .sheet(isPresented: $showingFilePicker) {
            DocumentPickerSheet { urls in
                importFiles(urls)
            }
            .environmentObject(language)
            .environment(\.layoutDirection, language.layoutDirection)
        }
        .sheet(isPresented: $showingActionPanel) {
            ComposerActionPanel(
                onNewChat: {
                    showingActionPanel = false
                    let session = env.sessionStore.newSession()
                    env.sessionStore.select(session)
                },
                onAttachFile: {
                    showingActionPanel = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        showingFilePicker = true
                    }
                },
                onOpenSection: { section in
                    showingActionPanel = false
                    env.presentSection(section)
                },
                onOpenTerminal: {
                    showingActionPanel = false
                    env.showTerminal = true
                })
                .environmentObject(env)
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Composer surface (Pure System-Adaptive iOS 27 Liquid Glass)

    private var composerSurface: some View {
        VStack(spacing: 0) {
            if !pendingImages.isEmpty || !pendingAttachments.isEmpty {
                attachmentStrip
            }
            inputRow
            controlRow
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            tint: focused ? AstralTheme.actionFill.opacity(0.04) : .clear,
            interactive: true)
        .animation(.smooth(duration: 0.25), value: pendingImages.isEmpty)
        .animation(.smooth(duration: 0.25), value: pendingAttachments.isEmpty)
        .animation(.smooth(duration: 0.2), value: focused)
    }

    // MARK: Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { file in
                    FileAttachmentChip(name: file.name) {
                        withAnimation(.smooth(duration: 0.22)) {
                            pendingAttachments.removeAll { $0.id == file.id }
                        }
                    }
                }

                ForEach(pendingImages) { image in
                    AttachmentThumbnail(image: image) {
                        withAnimation(.smooth(duration: 0.22)) {
                            pendingImages.removeAll { $0.id == image.id }
                        }
                    }
                }

                if importingImages {
                    ProgressView()
                        .frame(width: 64, height: 64)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: Input row

    private var inputRow: some View {
        TextField(
            L("chat.composerPlaceholder", "Chat"),
            text: $draft,
            axis: .vertical)
            .font(AstralTheme.body(17))
            .foregroundStyle(AstralTheme.textPrimary)
            .lineLimit(1...7)
            .focused($focused)
            .submitLabel(.send)
            .onSubmit { sendDraft() }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(minHeight: 50, alignment: .bottom)
    }

    // MARK: Control row

    private var controlRow: some View {
        HStack(spacing: 8) {
            if let armedSkillName {
                armedSkillChip(named: armedSkillName)
            }

            photoPicker

            plusMenu

            agentModeChip

            if armedSkillName == nil {
                skillsChip
            }

            Spacer(minLength: 8)

            sendControl
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: Send / stop control (System-Adaptive Liquid Glass Orb)

    @ViewBuilder
    private var sendControl: some View {
        Group {
            if isStreaming {
                Button(action: onStop) {
                    AIcon(
                        AstralIcons.stop,
                        size: 14,
                        strokeWidth: 2.5,
                        color: AstralTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .liquidGlass(
                            in: Circle(),
                            tint: AstralTheme.danger.opacity(0.18),
                            interactive: true)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(L("common.stop", "Shared")))
            } else {
                Button(action: sendDraft) {
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 16.5,
                        strokeWidth: 2.5,
                        color: canSend ? AstralTheme.actionForeground : AstralTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background {
                            if canSend {
                                Circle().fill(AstralTheme.actionFill)
                            }
                        }
                        .liquidGlass(
                            in: Circle(),
                            tint: canSend ? AstralTheme.actionFill.opacity(0.2) : .clear,
                            interactive: true)
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.55)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(L("chat.send", "Chat")))
            }
        }
        .buttonStyle(PressableIconButtonStyle())
        .animation(.smooth(duration: 0.22), value: isStreaming)
        .animation(.smooth(duration: 0.2), value: canSend)
    }

    // MARK: Chips (All Native System-Adaptive Liquid Glass)

    private func armedSkillChip(named name: String) -> some View {
        Button(action: disarmSkill) {
            HStack(spacing: 5) {
                AIcon(
                    AstralIcons.sparkles,
                    size: 12,
                    strokeWidth: 2.2,
                    color: AstralTheme.accent)
                Text(name)
                    .font(AstralTheme.headline(12))
                    .foregroundStyle(AstralTheme.accent)
                    .lineLimit(1)
                AIcon(
                    AstralIcons.close,
                    size: 11,
                    strokeWidth: 2.4,
                    color: AstralTheme.accent.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .liquidCapsule(tint: AstralTheme.accent.opacity(0.12), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L("chat.skillArmed", "Chat")))
        .accessibilityValue(Text(name))
    }

    private var photoPicker: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: maxImages,
            matching: .images) {
            AIcon(
                AstralIcons.image,
                size: 15.5,
                strokeWidth: 2.0,
                color: AstralTheme.textSecondary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .disabled(isStreaming || pendingImages.count >= maxImages)
        .opacity(pendingImages.count >= maxImages ? 0.35 : 1)
        .accessibilityLabel(Text(L("chat.attachments.add", "Chat")))
        .onChange(of: photoItems) { _, items in
            importPhotos(items)
        }
    }

    private var plusMenu: some View {
        Button {
            showingActionPanel = true
        } label: {
            AIcon(
                AstralIcons.plus,
                size: 15.5,
                strokeWidth: 2.2,
                color: AstralTheme.textSecondary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PressableIconButtonStyle())
        .accessibilityLabel(Text(L("chat.composer.menu", "Chat")))
    }

    private var agentModeChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            agentMode.toggle()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    if agentMode {
                        AIcon(
                            AstralIcons.sparkles,
                            size: 14,
                            strokeWidth: 2.1,
                            color: AstralTheme.accent)
                            .transition(.scale(scale: 0.55).combined(with: .opacity))
                    } else {
                        AIcon(
                            AstralIcons.chat,
                            size: 14,
                            strokeWidth: 2.1,
                            color: AstralTheme.textSecondary)
                            .transition(.scale(scale: 0.55).combined(with: .opacity))
                    }
                }
                .frame(width: 18, height: 18)
                .animation(.smooth(duration: 0.3), value: agentMode)
                Text(agentMode
                    ? L("chat.composer.agentMode", "Chat")
                    : L("chat.composer.chatMode", "Chat"))
                    .font(AstralTheme.headline(12))
                    .lineLimit(1)
            }
            .foregroundStyle(agentMode ? AstralTheme.accent : AstralTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .liquidCapsule(
                tint: agentMode
                    ? AstralTheme.accent.opacity(0.14)
                    : .clear,
                interactive: true)
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(PressableIconButtonStyle())
        .accessibilityLabel(Text(L("chat.composer.agentMode.a11y", "Chat")))
        .accessibilityValue(Text(agentMode
            ? L("chat.composer.agentMode", "Chat")
            : L("chat.composer.chatMode", "Chat")))
    }

    @ViewBuilder
    private var skillsChip: some View {
        let enabled = skillStore.enabledSkills
        Menu {
            if enabled.isEmpty {
                Text(L("skills.composer.none", "Skills"))
            } else {
                ForEach(enabled.prefix(8)) { skill in
                    Button {
                        skillStore.toggle(skill.id)
                    } label: {
                        Label(
                            skill.displayName,
                            systemImage: skill.isEnabled ? "checkmark.circle.fill" : "circle")
                    }
                }
            }

            Divider()

            Button {
                env.presentSection(.skills)
            } label: {
                Label(L("skills.manage", "Skills"), systemImage: "puzzlepiece.extension")
            }
        } label: {
            HStack(spacing: 5) {
                AIcon(
                    AstralIcons.puzzle,
                    size: 13,
                    strokeWidth: 2.2,
                    color: enabled.isEmpty ? AstralTheme.textSecondary : AstralTheme.accent)
                Text(enabled.isEmpty
                    ? L("skills.composer.none", "Skills")
                    : String(
                        format: L("skills.composer.count", "Skills"),
                        enabled.count))
                    .font(AstralTheme.headline(12))
                    .lineLimit(1)
            }
            .foregroundStyle(
                enabled.isEmpty ? AstralTheme.textSecondary : AstralTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .liquidCapsule(
                tint: enabled.isEmpty ? .clear : AstralTheme.accent.opacity(0.12),
                interactive: true)
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text(L("skills.manage", "Skills")))
    }

    // MARK: Slash overlay

    private var slashMatches: [Skill] {
        let query = (slashQuery ?? "").lowercased()
        let installed = skillStore.installed
        let filtered = query.isEmpty
            ? installed
            : installed.filter { skill in
                skill.displayName.localizedCaseInsensitiveContains(query)
                    || skill.slug.localizedCaseInsensitiveContains(query)
            }
        return Array(filtered.prefix(maxSlashRows))
    }

    private var slashOverlay: some View {
        ScrollView {
            VStack(spacing: 2) {
                let matches = slashMatches
                if matches.isEmpty {
                    Text(L("chat.slash.none", "Chat"))
                        .font(AstralTheme.body(13))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    ForEach(matches) { skill in
                        slashRow(skill)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 260)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func slashRow(_ skill: Skill) -> some View {
        Button {
            armSkill(skill)
        } label: {
            HStack(spacing: 10) {
                AIcon(
                    AstralIcons.puzzle,
                    size: 14,
                    strokeWidth: 2.1,
                    color: AstralTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .liquidGlass(in: Circle(), interactive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.displayName)
                        .font(AstralTheme.headline(14))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                    if !skill.displaySummary.isEmpty {
                        Text(skill.displaySummary)
                            .font(AstralTheme.body(12))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(skill.displayName))
    }

    // MARK: Photo import

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        importingImages = true

        let remaining = maxImages - pendingImages.count
        let limited = Array(items.prefix(max(remaining, 0)))

        Task {
            var staged: [MessageImage] = []
            for item in limited {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    continue
                }
                if let image = MediaStore.save(imageData: data) {
                    staged.append(image)
                }
            }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.25)) {
                    pendingImages.append(contentsOf: staged)
                    importingImages = false
                }
            }
        }
    }

    // MARK: File import

    private func importFiles(_ urls: [URL]) {
        let remaining = maxFiles - pendingAttachments.count
        guard remaining > 0 else { return }

        Task { @MainActor in
            var staged: [MessageAttachment] = []
            for url in urls.prefix(remaining) {
                staged.append(AttachmentExtractor.extract(from: url))
            }
            withAnimation(.smooth(duration: 0.25)) {
                pendingAttachments.append(contentsOf: staged)
            }
        }
    }

    // MARK: Actions

    private func armSkill(_ skill: Skill) {
        if let previous = armedSkillID, previous != skill.id {
            skillStore.setEnabled(previous, false)
        }
        withAnimation(.smooth(duration: 0.2)) {
            draft = ""
            armedSkillName = skill.displayName
            armedSkillID = skill.id
        }
        skillStore.setEnabled(skill.id, true)
    }

    private func disarmSkill() {
        if let id = armedSkillID {
            skillStore.setEnabled(id, false)
        }
        withAnimation(.smooth(duration: 0.2)) {
            armedSkillName = nil
            armedSkillID = nil
        }
    }

    private func sendDraft() {
        guard canSend else { return }
        let text = trimmedDraft
        let images = pendingImages
        let files = pendingAttachments
        draft = ""
        withAnimation(.smooth(duration: 0.2)) {
            pendingImages = []
            pendingAttachments = []
            armedSkillName = nil
            armedSkillID = nil
        }
        onSend(text, images, files)
    }
}

// MARK: - Action panel (System-Adaptive Liquid Glass)

struct ComposerActionPanel: View {
    var onNewChat: () -> Void
    var onAttachFile: () -> Void
    var onOpenSection: (AppTab) -> Void
    var onOpenTerminal: () -> Void

    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var shell = SandboxShell.shared

    var body: some View {
        VStack(spacing: 14) {
            header

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10) {
                actionTile(
                    title: L("chat.newChat", "Chat"),
                    icon: AstralIcons.newChat,
                    action: onNewChat)
                actionTile(
                    title: L("chat.attachFile", "Chat"),
                    icon: AstralIcons.filePlus,
                    action: onAttachFile)
                actionTile(
                    title: L("sandbox.terminal", "Chat"),
                    icon: AstralIcons.computer,
                    caption: shell.cwd,
                    action: onOpenTerminal)
                actionTile(
                    title: L("skills.manage", "Skills"),
                    icon: AstralIcons.puzzle,
                    action: { onOpenSection(.skills) })
                actionTile(
                    title: L("tab.browser", "Shared"),
                    icon: AstralIcons.browser,
                    action: { onOpenSection(.browser) })
                actionTile(
                    title: L("tab.files", "Shared"),
                    icon: AstralIcons.folder,
                    action: { onOpenSection(.files) })
            }
            .padding(.horizontal, 16)

            Button(action: { onOpenSection(.settings) }) {
                HStack(spacing: 10) {
                    AIcon(
                        AstralIcons.settings,
                        size: 16,
                        strokeWidth: 2.1,
                        color: AstralTheme.textPrimary)
                    Text(L("tab.settings", "Shared"))
                        .font(AstralTheme.headline(14))
                        .foregroundStyle(AstralTheme.textPrimary)
                    Spacer(minLength: 0)
                    AIcon(
                        AstralIcons.chevronForward,
                        size: 13,
                        strokeWidth: 2.2,
                        color: AstralTheme.textSecondary)
                        .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .liquidGlass(
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                    interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AstralTheme.background.ignoresSafeArea())
        .environment(\.layoutDirection, language.layoutDirection)
    }

    private var header: some View {
        VStack(spacing: 3) {
            Text(L("chat.composer.menu", "Chat"))
                .font(AstralTheme.headline(15))
                .foregroundStyle(AstralTheme.textPrimary)
            Text("astra-os 5.0 · /home/astral")
                .font(AstralTheme.mono(10.5))
                .foregroundStyle(AstralTheme.textSecondary)
        }
        .padding(.top, 4)
    }

    private func actionTile(
        title: String,
        icon: String,
        caption: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                AIcon(
                    icon,
                    size: 17,
                    strokeWidth: 2.0,
                    color: AstralTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .liquidGlass(in: Circle(), interactive: true)

                Text(title)
                    .font(AstralTheme.headline(12))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .lineLimit(1)

                if let caption {
                    Text(caption)
                        .font(AstralTheme.mono(9))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: caption == nil ? 86 : 96)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - File attachment chip

struct FileAttachmentChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AIcon(
                AstralIcons.file,
                size: 13,
                strokeWidth: 2.1,
                color: AstralTheme.textPrimary)

            Text(name)
                .font(AstralTheme.headline(12))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(1)

            Button(action: onRemove) {
                AIcon(
                    AstralIcons.close,
                    size: 11,
                    strokeWidth: 2.4,
                    color: AstralTheme.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .accessibilityLabel(Text(L("chat.attachments.remove", "Chat")))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .liquidCapsule(interactive: true)
    }
}

// MARK: - Thumbnail

struct AttachmentThumbnail: View {
    let image: MessageImage
    let onRemove: () -> Void

    @State private var ui: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let ui {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(AstralTheme.separator)
                        .shimmer(cornerRadius: 14)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onRemove) {
                AIcon(
                    AstralIcons.close,
                    size: 10,
                    strokeWidth: 2.6,
                    color: AstralTheme.textPrimary)
                    .frame(width: 22, height: 22)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .offset(x: 4, y: -4)
            .accessibilityLabel(Text(L("chat.attachments.remove", "Chat")))
        }
        .task {
            ui = MediaStore.uiImage(image, thumbnailMax: 160)
        }
    }
}

// MARK: - Button press feedback

struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
