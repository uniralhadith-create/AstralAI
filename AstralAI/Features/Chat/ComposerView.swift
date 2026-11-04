import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Composer

/// The Liquid Glass composer: one roomy glass surface with
/// - an attachment strip (photo thumbnails, video thumbnails saved in Workspace, + file chips, removable),
/// - the auto-growing input (17pt, up to 7 lines, 56pt minimum height),
/// - a control row of liquid-capsule chips: photo/video picker, plus menu,
///   agent-mode chip, skills chip — with the circular send control at the
///   trailing end of that same row, level with the chips,
/// - the "/" slash skill overlay above the composer.
struct ComposerView: View {
    let isStreaming: Bool
    var onSend: (String, [MessageImage], [MessageVideo], [MessageAttachment]) -> Void
    var onStop: () -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager
    @ObservedObject private var skillStore = SkillStore.shared
    @FocusState private var focused: Bool

    @State private var draft = ""
    /// Images staged for the next message.
    @State private var pendingImages: [MessageImage] = []
    /// Videos staged for the next message (saved in Workspace under `Videos/`).
    @State private var pendingVideos: [MessageVideo] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importingImages = false
    /// Files staged for the next message (extracted text travels along).
    @State private var pendingAttachments: [MessageAttachment] = []
    @State private var showingFilePicker = false

    /// Skill armed through the "/" overlay — chip label + id used to
    /// disable it again when the chip is dismissed.
    @State private var armedSkillName: String?
    @State private var armedSkillID: UUID?

    /// The action panel sheet.
    @State private var showingActionPanel = false

    @AppStorage("astral.agentMode") private var agentMode = false

    private let maxImages = 4
    private let maxFiles = 4
    private let maxSlashRows = 8

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        (!trimmedDraft.isEmpty || !pendingImages.isEmpty || !pendingVideos.isEmpty || !pendingAttachments.isEmpty)
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

    // MARK: Composer surface

    private var composerSurface: some View {
        VStack(spacing: 0) {
            if !pendingImages.isEmpty || !pendingVideos.isEmpty || !pendingAttachments.isEmpty || importingImages {
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
        .animation(.smooth(duration: 0.25), value: pendingVideos.isEmpty)
        .animation(.smooth(duration: 0.25), value: pendingAttachments.isEmpty)
        .animation(.smooth(duration: 0.2), value: focused)
    }

    // MARK: Attachment strip

    /// Thumbnails of staged images, videos saved in Workspace, and chips of staged files.
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

                ForEach(pendingVideos) { video in
                    VideoAttachmentThumbnail(video: video) {
                        withAnimation(.smooth(duration: 0.22)) {
                            pendingVideos.removeAll { $0.id == video.id }
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

    /// Photo & Video attach chip (PhotosPicker supporting both `.images` and `.videos`).
    /// Picked videos are saved automatically into the Workspace (`Videos/...`).
    private var photoPicker: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: maxImages,
            matching: .any(of: [.images, .videos])) {
            AIcon(
                AstralIcons.image,
                size: 17,
                strokeWidth: 2,
                color: AstralTheme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .disabled(isStreaming || (pendingImages.count + pendingVideos.count) >= maxImages)
        .opacity((pendingImages.count + pendingVideos.count) >= maxImages ? 0.35 : 1)
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
                size: 17,
                strokeWidth: 2.2,
                color: AstralTheme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
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

    // MARK: Photo & Video import

    /// Loads picked photos and videos:
    /// - Photos are normalized and stored via `MediaStore.save(imageData:)`.
    /// - Videos are saved directly into the Workspace (`Videos/<name>.mp4`) via
    ///   `MediaStore.saveVideo(...)` so they live in the Workspace and ride
    ///   along with the message.
    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        importingImages = true

        let remaining = maxImages - (pendingImages.count + pendingVideos.count)
        let limited = Array(items.prefix(max(remaining, 0)))

        Task {
            var stagedImages: [MessageImage] = []
            var stagedVideos: [MessageVideo] = []
            for item in limited {
                let isMovie = item.supportedContentTypes.contains { type in
                    type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .mpeg4Movie) || type.conforms(to: .quickTimeMovie)
                }
                guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    continue
                }
                if isMovie {
                    let ext = item.supportedContentTypes.first(where: { $0.conforms(to: .quickTimeMovie) }) != nil ? "mov" : "mp4"
                    if let savedVideo = await MainActor.run(body: {
                        MediaStore.saveVideo(
                            data: data,
                            preferredName: "video-\(Int(Date().timeIntervalSince1970)).\(ext)",
                            workspaceFolder: "Videos")
                    }) {
                        stagedVideos.append(savedVideo)
                    }
                } else if let image = MediaStore.save(imageData: data) {
                    stagedImages.append(image)
                } else if let savedVideo = await MainActor.run(body: {
                    MediaStore.saveVideo(data: data, workspaceFolder: "Videos")
                }) {
                    stagedVideos.append(savedVideo)
                }
            }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.25)) {
                    pendingImages.append(contentsOf: stagedImages)
                    pendingVideos.append(contentsOf: stagedVideos)
                    importingImages = false
                }
            }
        }
    }

    // MARK: File & Video import from DocumentPicker

    /// Extracts text from picked files, and if a picked file is a video
    /// (`.mp4`, `.mov`, `.m4v`, `.webm`, `.mkv`, `.avi`), saves the video
    /// directly into the Workspace (`Videos/...`) and stages it as a video!
    private func importFiles(_ urls: [URL]) {
        let remaining = maxFiles - pendingAttachments.count
        guard remaining > 0 else { return }

        Task { @MainActor in
            var stagedAttachments: [MessageAttachment] = []
            var stagedVideos: [MessageVideo] = []
            for url in urls.prefix(remaining) {
                if MediaStore.isVideoFileName(url.lastPathComponent),
                   let savedVideo = MediaStore.saveVideo(at: url, preferredName: url.lastPathComponent, workspaceFolder: "Videos") {
                    stagedVideos.append(savedVideo)
                } else {
                    // Also copy raw file bytes to uploads/<name> in Workspace
                    let safeName = WorkspaceStore.sanitizeFolderName(
                        (url.lastPathComponent as NSString).deletingPathExtension)
                    let ext = url.pathExtension
                    let destName = ext.isEmpty ? safeName : "\(safeName).\(ext)"
                    if let data = try? Data(contentsOf: url) {
                        _ = try? WorkspaceStore.shared.writeData(path: "uploads/\(destName)", data: data)
                    }
                    stagedAttachments.append(AttachmentExtractor.extract(from: url))
                }
            }
            withAnimation(.smooth(duration: 0.25)) {
                pendingVideos.append(contentsOf: stagedVideos)
                pendingAttachments.append(contentsOf: stagedAttachments)
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
        let videos = pendingVideos
        let files = pendingAttachments
        draft = ""
        withAnimation(.smooth(duration: 0.2)) {
            pendingImages = []
            pendingVideos = []
            pendingAttachments = []
            armedSkillName = nil
            armedSkillID = nil
        }
        onSend(text, images, videos, files)
    }
}

// MARK: - Action panel

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
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": return "video.fill"
        case "zip": return "doc.zipper"
        default: return "doc"
        }
    }
}

// MARK: - Video attachment thumbnail

private struct VideoAttachmentThumbnail: View {
    let video: MessageVideo
    let onRemove: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(AstralTheme.surfaceSecondary)
                }
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 26, height: 26)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
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
            if let url = MediaStore.videoURL(for: video) {
                thumbnail = MediaStore.videoThumbnail(for: url, maxDimension: 160)
            }
        }
    }
}

// MARK: - Attachment thumbnail

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

private struct PressableIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}
