import SwiftUI
import PhotosUI
import UIKit

// MARK: - Composer

/// The V3.1 Liquid Glass composer: one roomy glass surface with
/// - an attachment strip (photo thumbnails + file chips, removable),
/// - the auto-growing input (17pt, up to 7 lines, 56pt minimum height),
/// - a control row of liquid-capsule chips: photo picker, plus menu,
///   agent-mode chip, skills chip — with the circular send control at the
///   trailing end of that same row, level with the chips,
/// - the "/" slash skill overlay above the composer.
///
/// Typing "/" as the first character reveals the skill picker; tapping a
/// skill arms it (enables the skill, clears the "/query" text and shows a
/// dismissible chip).
struct ComposerView: View {
    let isStreaming: Bool
    var onSend: (String, [MessageImage], [MessageAttachment]) -> Void
    var onStop: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var skillStore = SkillStore.shared
    @FocusState private var focused: Bool

    @State private var draft = ""
    /// Images staged for the next message.
    @State private var pendingImages: [MessageImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingImages = false
    /// Files staged for the next message (extracted text travels along).
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var showingFilePicker = false

    /// Skill armed through the "/" overlay — chip label + id used to
    /// disable it again when the chip is dismissed.
    @State private var armedSkillName: String?
    @State private var armedSkillID: UUID?

    /// The V3.5 action panel (replaces the Menu-based plus menu, whose
    /// actions could be silently swallowed while the menu dismissed).
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

    /// The query after a leading "/" — nil when the draft doesn't start
    /// with a slash (which also hides the overlay).
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
                    // Sheet-on-sheet: give the panel a beat to dismiss.
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

    // MARK: Composer surface

    private var composerSurface: some View {
        VStack(spacing: 0) {
            if !pendingImages.isEmpty || !pendingAttachments.isEmpty {
                attachmentStrip
            }
            inputRow
            Divider()
                .overlay(AstralTheme.separator)
                .padding(.horizontal, 14)
            controlRow
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: 30, style: .continuous),
            tint: focused ? AstralTheme.actionFill.opacity(0.06) : .clear,
            interactive: true)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    focused ? AstralTheme.accent.opacity(0.45) : Color.clear,
                    lineWidth: 1.5))
        .animation(.smooth(duration: 0.25), value: pendingImages.isEmpty)
        .animation(.smooth(duration: 0.25), value: pendingAttachments.isEmpty)
        .animation(.smooth(duration: 0.2), value: focused)
    }

    // MARK: Attachment strip

    /// Thumbnails of staged images and chips of staged files, all removable.
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
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AstralTheme.surfaceSecondary))
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
            .padding(.vertical, 15)
            .frame(minHeight: 56, alignment: .bottom)
    }

    // MARK: Control row

    /// The action row: chips on the leading side, the send/stop control at
    /// the trailing side — all vertically centered, exactly level.
    private var controlRow: some View {
        HStack(spacing: 10) {
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
        .padding(.vertical, 8)
    }

    // MARK: Send / stop control

    @ViewBuilder
    private var sendControl: some View {
        Group {
            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AstralTheme.actionForeground)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(AstralTheme.actionFill.opacity(0.55)))
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(L("common.stop", "Shared")))
            } else {
                Button(action: sendDraft) {
                    AIcon(
                        AstralIcons.arrowUp,
                        size: 17,
                        strokeWidth: 2.6,
                        color: AstralTheme.actionForeground)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(AstralTheme.actionFill))
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.4)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text(L("chat.send", "Chat")))
            }
        }
        .buttonStyle(PressableIconButtonStyle())
        .animation(.smooth(duration: 0.22), value: isStreaming)
        .animation(.smooth(duration: 0.2), value: canSend)
    }

    // MARK: Chips

    /// The "skill armed" capsule: shows the skill armed via the "/" overlay,
    /// dismissible with an xmark that also disables the skill again.
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
            .padding(.vertical, 8)
            .liquidCapsule(tint: AstralTheme.accent.opacity(0.12))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L("chat.skillArmed", "Chat")))
        .accessibilityValue(Text(name))
    }

    /// The V3 image attach chip (PhotosPicker — no library permission
    /// needed, the system picker runs out of process).
    private var photoPicker: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: maxImages,
            matching: .images) {
            AIcon(
                AstralIcons.image,
                size: 17,
                strokeWidth: 2,
                color: AstralTheme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .disabled(isStreaming || pendingImages.count >= maxImages)
        .opacity(pendingImages.count >= maxImages ? 0.35 : 1)
        .accessibilityLabel(Text(L("chat.attachments.add", "Chat")))
        .onChange(of: photoItems) { _, items in
            importPhotos(items)
        }
    }

    /// The V3.5 plus control — a plain button opening the action panel
    /// (Menus can silently drop actions during dismissal on iOS 26;
    /// a presented sheet never does).
    private var plusMenu: some View {
        Button {
            showingActionPanel = true
        } label: {
            AIcon(
                AstralIcons.plus,
                size: 17,
                strokeWidth: 2.2,
                color: AstralTheme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableIconButtonStyle())
        .accessibilityLabel(Text(L("chat.composer.menu", "Chat")))
    }

    /// Chat ↔ Agent mode switch. Chat streams a direct answer; Agent runs
    /// the full plan + parallel sub-agent pipeline. The label swaps without
    /// a layout animation — animating the width change made the chip glitch
    /// in RTL Arabic (text overlapping the icon mid-transition).
    ///
    /// V4.6.0: the chat glyph is the true Lucide `message-circle` speech
    /// bubble (the SVG arc-correction fix makes it render exactly like the
    /// web original), and it sits in an 18pt box with a soft capsule tint
    /// in both states — the bubble now reads as a real message mark that
    /// stays inside the button's border instead of crowding it.
    private var agentModeChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            agentMode.toggle()
        } label: {
            HStack(spacing: 5) {
                // V4.7.0: the glyph swap is a true crossfade with a soft
                // scale — the chip feels alive instead of flickering.
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
                    ? AstralTheme.accent.opacity(0.15)
                    : AstralTheme.textPrimary.opacity(0.06),
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

    /// Live chip showing enabled skills; tapping opens a quick toggle menu.
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
            .padding(.vertical, 8)
            .liquidCapsule(
                tint: enabled.isEmpty ? .clear : AstralTheme.accent.opacity(0.12),
                interactive: true)
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text(L("skills.manage", "Skills")))
    }

    // MARK: Slash overlay

    /// Liquid Glass skill picker shown above the composer while the draft
    /// starts with "/". Empty query lists every installed skill (capped);
    /// otherwise skills whose name or slug contains the query.
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
                Image(systemName: skill.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .frame(width: 28, height: 28)

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

    /// Loads picked photos through the media store (normalization,
    /// downscale, JPEG) and stages them for the next message.
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

    /// Extracts text from picked files and stages them as attachments.
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

    /// Arms a skill picked from the "/" overlay: enables it, replaces any
    /// previously armed skill, clears the slash draft and shows the chip.
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

    /// Dismisses the armed-skill chip and disables the skill again.
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
            // The chip is transient; the skill itself stays enabled so the
            // outgoing turn picks it up when its prompt is built.
            armedSkillName = nil
            armedSkillID = nil
        }
        onSend(text, images, files)
    }
}

// MARK: - Action panel

/// The V3.5 composer action panel — a Liquid Glass bottom sheet that
/// replaces the old plus `Menu`. Presented as a real sheet, so every
/// action fires reliably (no menu-dismissal race, no swallowed taps).
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
                    icon: AstralIcons.terminal,
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
                        language.layoutDirection == .rightToLeft
                            ? "arrow-left" : AstralIcons.chevronForward,
                        size: 13,
                        strokeWidth: 2.2,
                        color: AstralTheme.textSecondary)
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
            Text("astra-os · /home/astral")
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
                    size: 18,
                    strokeWidth: 2,
                    color: AstralTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(AstralTheme.actionFill.opacity(0.08)))

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

/// One staged file: document icon, name, remove button — a capsule chip
/// sized to match the photo thumbnails' height.
struct FileAttachmentChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AstralTheme.textPrimary)

            Text(name)
                .font(AstralTheme.headline(12))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AstralTheme.textSecondary)
            }
            .accessibilityLabel(Text(L("chat.attachments.remove", "Chat")))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .liquidCapsule()
        .overlay(Capsule().stroke(AstralTheme.separator, lineWidth: 1))
    }

    private var icon: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "json", "plist": return "curlybraces.square"
        case "csv", "tsv", "xlsx": return "tablecells"
        case "md", "markdown", "txt", "rtf": return "doc.plaintext"
        case "zip": return "doc.zipper"
        default: return "doc"
        }
    }
}

// MARK: - Attachment thumbnail

/// One staged image: rounded thumbnail plus a remove button.
private struct AttachmentThumbnail: View {
    let image: MessageImage
    let onRemove: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(AstralTheme.surfaceSecondary)
                        .shimmer()
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AstralTheme.separator, lineWidth: 1))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .background(Circle().fill(AstralTheme.surface))
            }
            .offset(x: 6, y: -6)
        }
        .task {
            thumbnail = MediaStore.uiImage(image, thumbnailMax: 160)
        }
    }
}

// MARK: - Press feedback

/// Small scale-down press feedback for icon-sized buttons.
private struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}
