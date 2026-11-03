import SwiftUI
import Combine

// MARK: - File kind styling (V5 Lucide Vector Icons)

enum FileKindStyle {
    static func astralIcon(for kind: FileKind) -> String {
        switch kind {
        case .markdown: return AstralIcons.file
        case .text: return AstralIcons.file
        case .code: return AstralIcons.fileCode
        case .pdf: return AstralIcons.file
        case .spreadsheet: return AstralIcons.table
        case .image: return AstralIcons.image
        case .archive: return AstralIcons.package
        case .web: return AstralIcons.browser
        case .other: return AstralIcons.file
        }
    }

    static func icon(for kind: FileKind) -> String {
        switch kind {
        case .markdown: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .pdf: return "doc.fill"
        case .spreadsheet: return "tablecells"
        case .image: return "photo"
        case .archive: return "doc.zipper"
        case .web: return "safari"
        case .other: return "doc"
        }
    }

    static func tint(for kind: FileKind) -> Color {
        switch kind {
        case .markdown: return AstralTheme.auroraCyan
        case .text: return AstralTheme.moonDust
        case .code: return AstralTheme.auroraMagenta
        case .pdf: return AstralTheme.danger
        case .spreadsheet: return AstralTheme.success
        case .image: return AstralTheme.warning
        case .archive: return AstralTheme.nebulaViolet
        case .web: return AstralTheme.auroraCyan
        case .other: return AstralTheme.moonDust
        }
    }
}

// MARK: - Files view (V5 Liquid Glass Workspace)

struct FilesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager

    @StateObject private var observation = WorkspaceObservation()

    @State private var sort: FileSort = .date
    @State private var previewTarget: PreviewTarget?
    @State private var pendingDelete: WorkspaceFile?
    @State private var showingNewProject = false
    @State private var projectName = ""
    @State private var importingFile = false

    enum FileSort: String, CaseIterable, Identifiable {
        case name
        case date
        case size

        var id: String { rawValue }
    }

    struct PreviewTarget: Identifiable {
        let id: String
        let file: WorkspaceFile
        let url: URL
    }

    @State private var selectedProject: String?

    private var sortedFiles: [WorkspaceFile] {
        let base: [WorkspaceFile]
        switch sort {
        case .name:
            base = env.workspace.files.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .date:
            base = env.workspace.files.sorted { $0.modifiedAt > $1.modifiedAt }
        case .size:
            base = env.workspace.files.sorted { $0.size > $1.size }
        }
        guard let project = selectedProject else { return base }
        return base.filter { $0.relativePath.hasPrefix("Projects/\(project)") }
    }

    // MARK: Projects strip

    private var projectsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.workspace.projectFolders, id: \.self) { project in
                    Button {
                        selectedProject = selectedProject == project ? nil : project
                    } label: {
                        HStack(spacing: 6) {
                            AIcon(
                                AstralIcons.folderOpen,
                                size: 13,
                                strokeWidth: 2.1,
                                color: selectedProject == project
                                    ? AstralTheme.textPrimary
                                    : AstralTheme.textSecondary)
                            Text(project)
                                .font(AstralTheme.headline(12.5))
                                .foregroundStyle(selectedProject == project
                                    ? AstralTheme.textPrimary
                                    : AstralTheme.textSecondary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .liquidCapsule(
                            tint: selectedProject == project
                                ? AstralTheme.accent.opacity(0.16)
                                : AstralTheme.textPrimary.opacity(0.05),
                            interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
        }
    }

    // MARK: Project & import actions

    private func createProject() {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = WorkspaceStore.sanitizeFolderName(name)
        _ = try? env.workspace.createFolder(path: "Projects/\(folder)")
        _ = try? env.workspace.write(
            path: "Projects/\(folder)/README.md",
            content: "# \(name)\n\n\(L("files.projectReadme", "Files"))\n")
        projectName = ""
        selectedProject = folder
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let fileManager = FileManager.default
        for url in urls {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let destination = env.workspace.rootURL.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(at: url, to: destination)
        }
        env.workspace.refresh()
    }

    var body: some View {
        VStack(spacing: AstralTheme.Spacings.s) {
            header

            if !env.workspace.projectFolders.isEmpty {
                projectsStrip
            }

            if env.workspace.files.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    titleKey: "files.empty",
                    messageKey: "files.emptyHint",
                    table: "Files")
                    .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
        .onAppear {
            observation.bind(env.workspace)
            env.workspace.refresh()
        }
        .sheet(item: $previewTarget) { target in
            FilePreviewView(file: target.file, url: target.url)
        }
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert(
            L("files.newProjectTitle", "Files"),
            isPresented: $showingNewProject) {
                TextField(
                    L("files.newProjectPlaceholder", "Files"),
                    text: $projectName)
                Button(L("common.create", "Shared")) {
                    createProject()
                }
                Button(L("common.cancel", "Shared"), role: .cancel) {
                    projectName = ""
                }
            } message: {
                Text(L("files.newProjectMessage", "Files"))
            }
        .confirmationDialog(
            L("files.deleteTitle", "Files"),
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible
        ) {
            Button(L("common.delete", "Shared"), role: .destructive) {
                if let target = pendingDelete {
                    delete(target)
                }
                pendingDelete = nil
            }
            Button(L("common.cancel", "Shared"), role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete.map { file in
                L("files.deleteMessage", "Files") + "\n" + file.name
            } ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AstralTheme.Spacings.s) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(icon: "folder", "files.title", table: "Files")
                Text(String(format: L("files.count", "Files"), env.workspace.files.count))
                    .font(AstralTheme.body(11))
                    .foregroundStyle(AstralTheme.moonDust)
            }

            Spacer(minLength: 8)

            newProjectButton
            importButton
            terminalButton
            sortMenu
            refreshButton
        }
        .padding(.horizontal, AstralTheme.Spacings.m)
        .padding(.top, AstralTheme.Spacings.xs)
    }

    private var newProjectButton: some View {
        Button {
            projectName = ""
            showingNewProject = true
        } label: {
            AIcon(
                AstralIcons.folderPlus,
                size: 15,
                strokeWidth: 2.1,
                color: AstralTheme.textPrimary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(L("files.newProjectTitle", "Files")))
    }

    private var importButton: some View {
        Button {
            importingFile = true
        } label: {
            AIcon(
                AstralIcons.upload,
                size: 15,
                strokeWidth: 2.1,
                color: AstralTheme.textPrimary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(L("files.import", "Files")))
    }

    private var terminalButton: some View {
        Button {
            env.showTerminal = true
        } label: {
            AstralComputerIcon(
                size: 15,
                color: AstralTheme.textPrimary,
                accentColor: AstralTheme.orbGreen,
                isActive: true)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(L("sandbox.terminal", "Files")))
    }

    private var sortMenu: some View {
        Menu {
            Picker(L("files.sort", "Files"), selection: $sort) {
                Text(L("files.sort.name", "Files")).tag(FileSort.name)
                Text(L("files.sort.date", "Files")).tag(FileSort.date)
                Text(L("files.sort.size", "Files")).tag(FileSort.size)
            }
        } label: {
            AIcon(
                AstralIcons.chevronsUpDown,
                size: 14,
                strokeWidth: 2.2,
                color: AstralTheme.textPrimary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(L("files.sort", "Files")))
    }

    private var refreshButton: some View {
        Button {
            env.workspace.refresh()
        } label: {
            AIcon(
                AstralIcons.refresh,
                size: 14,
                strokeWidth: 2.2,
                color: AstralTheme.textPrimary)
                .frame(width: 32, height: 32)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel(Text(L("common.refresh", "Shared")))
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sortedFiles) { file in
                    fileRow(file)
                }
            }
            .padding(.horizontal, AstralTheme.Spacings.m)
            .padding(.bottom, AstralTheme.Spacings.m)
        }
    }

    private func fileRow(_ file: WorkspaceFile) -> some View {
        Button {
            openPreview(file)
        } label: {
            HStack(spacing: AstralTheme.Spacings.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(FileKindStyle.tint(for: file.kind).opacity(0.14))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1))

                    AIcon(
                        FileKindStyle.astralIcon(for: file.kind),
                        size: 17,
                        strokeWidth: 2.1,
                        color: FileKindStyle.tint(for: file.kind))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(AstralTheme.headline(15))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)

                    Text(subtitle(for: file))
                        .font(AstralTheme.body(11))
                        .foregroundStyle(AstralTheme.moonDust)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                AIcon(
                    AstralIcons.chevronForward,
                    size: 12,
                    strokeWidth: 2.2,
                    color: AstralTheme.moonDust.opacity(0.75))
                    .scaleEffect(x: language.layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            }
            .padding(AstralTheme.Spacings.s)
            .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let url = previewURL(for: file) {
                ShareLink(item: url) {
                    Label(L("common.share", "Shared"), systemImage: "square.and.arrow.up")
                }
            }
            Button {
                openPreview(file)
            } label: {
                Label(L("files.preview", "Files"), systemImage: "eye")
            }
            Button(role: .destructive) {
                pendingDelete = file
            } label: {
                Label(L("common.delete", "Shared"), systemImage: "trash")
            }
        }
    }

    // MARK: Helpers

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })
    }

    private func subtitle(for file: WorkspaceFile) -> String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.effectiveCode)
        formatter.unitsStyle = .abbreviated
        let modified = formatter.localizedString(for: file.modifiedAt, relativeTo: Date())
        return "\(size) · \(modified)"
    }

    private func previewURL(for file: WorkspaceFile) -> URL? {
        env.workspace.url(for: file.relativePath)
    }

    private func openPreview(_ file: WorkspaceFile) {
        let url = previewURL(for: file)
            ?? env.workspace.rootURL.appendingPathComponent(file.relativePath)
        previewTarget = PreviewTarget(id: file.id, file: file, url: url)
    }

    private func delete(_ file: WorkspaceFile) {
        try? env.workspace.delete(path: file.relativePath)
        env.workspace.refresh()
    }
}

// MARK: - Workspace observation

@MainActor
private final class WorkspaceObservation: ObservableObject {
    private var cancellable: AnyCancellable?

    func bind(_ store: WorkspaceStore) {
        guard cancellable == nil else { return }
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }
}
