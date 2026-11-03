import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Skills tab (V5.0.0 — System-Adaptive iOS 27 Liquid Glass)

/// The Skills library: installed skills with live toggles, the built-in
/// catalog, download-from-URL and import-from-file flows (`.skill.skill`,
/// `.skill` or JSON), per-skill export, plus a manual skill creator — rendered
/// in 100% system-adaptive iOS 27 Liquid Glass.
struct SkillsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var language: LocalizationManager

    @ObservedObject private var store = SkillStore.shared

    @State private var urlString = ""
    @State private var downloading = false
    @State private var message: String?
    @State private var messageIsError = false

    @State private var showingImporter = false
    @State private var showingCreator = false
    @State private var detailSkill: Skill?

    /// File extensions accepted by the importer.
    private static let allowedExtensions = [".skill.skill", ".skill", ".json"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AstralTheme.Spacings.m) {
                    headerSummary

                    activeSection

                    if !store.librarySkills.isEmpty {
                        librarySection
                    }

                    addSection

                    if let message {
                        resultBanner(message)
                    }
                }
                .padding(.horizontal, AstralTheme.Spacings.m)
                .padding(.vertical, AstralTheme.Spacings.m)
            }
            .background(AstralTheme.background)
            .navigationTitle(L("skills.title", "Skills"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingCreator = true
                        } label: {
                            Label(L("skills.create", "Skills"), systemImage: "square.and.pencil")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label(L("skills.importFile", "Skills"), systemImage: "folder")
                        }
                    } label: {
                        AIcon(
                            AstralIcons.plus,
                            size: 16,
                            strokeWidth: 2.2,
                            color: AstralTheme.textPrimary)
                            .frame(width: 34, height: 34)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                }
            }
            .sheet(item: $detailSkill) { skill in
                SkillDetailView(skill: skill)
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingCreator) {
                SkillCreatorView()
                    .environmentObject(language)
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPickerSheet { urls in
                    handleImportURLs(urls)
                }
                .environmentObject(language)
                .environment(\.layoutDirection, language.layoutDirection)
            }
        }
    }

    // MARK: Header summary

    private var headerSummary: some View {
        HStack(spacing: AstralTheme.Spacings.m) {
            ZStack {
                Circle()
                    .frame(width: 46, height: 46)
                    .liquidGlass(in: Circle(), interactive: true)
                Image("AstralMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(
                    format: L("skills.activeCount", "Skills"),
                    store.enabledSkills.count))
                    .font(AstralTheme.headline(15))
                    .foregroundStyle(AstralTheme.textPrimary)
                Text(L("skills.subtitle", "Skills"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(AstralTheme.Spacings.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
    }

    // MARK: Active

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "checkmark.circle", "skills.installed", table: "Skills")

            if store.installed.isEmpty {
                Text(L("skills.empty", "Skills"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AstralTheme.Spacings.m)
                    .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
            } else {
                VStack(spacing: AstralTheme.Spacings.xs) {
                    ForEach(store.installed) { skill in
                        SkillRow(skill: skill) {
                            detailSkill = skill
                        }
                    }
                }
            }
        }
    }

    // MARK: Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "square.grid.2x2", "skills.library", table: "Skills")

            VStack(spacing: AstralTheme.Spacings.xs) {
                ForEach(store.librarySkills) { skill in
                    LibrarySkillRow(skill: skill) {
                        detailSkill = skill
                    } onAdd: {
                        store.install(skill)
                        showResult(String(format: L("skills.added", "Skills"), skill.displayName), error: false)
                    }
                }
            }
        }
    }

    // MARK: Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "arrow.down.circle", "skills.add", table: "Skills")

            VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                Text(L("skills.addHint", "Skills"))
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.textSecondary)

                Text(L("skills.import.hint", "Skills"))
                    .font(AstralTheme.body(11))
                    .foregroundStyle(AstralTheme.textSecondary)

                HStack(spacing: AstralTheme.Spacings.xs) {
                    TextField(
                        "https://example.com/skill.json",
                        text: $urlString)
                        .font(AstralTheme.mono(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        downloadSkill()
                    } label: {
                        Group {
                            if downloading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AstralTheme.actionForeground)
                            } else {
                                AIcon(
                                    AstralIcons.download,
                                    size: 16,
                                    strokeWidth: 2.3,
                                    color: AstralTheme.actionForeground)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AstralTheme.actionFill))
                    }
                    .disabled(downloading || urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(AstralTheme.Spacings.m)
            .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
        }
    }

    private func resultBanner(_ text: String) -> some View {
        HStack(spacing: AstralTheme.Spacings.s) {
            AIcon(
                messageIsError ? AstralIcons.shield : AstralIcons.checkCircle,
                size: 15,
                strokeWidth: 2.2,
                color: messageIsError ? AstralTheme.danger : AstralTheme.success)
            Text(text)
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
            Button {
                message = nil
            } label: {
                AIcon(
                    AstralIcons.close,
                    size: 12,
                    strokeWidth: 2.3,
                    color: AstralTheme.textSecondary)
            }
        }
        .padding(AstralTheme.Spacings.m)
        .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
    }

    // MARK: Actions

    private func downloadSkill() {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !downloading else { return }
        downloading = true
        message = nil

        Task { @MainActor in
            defer { downloading = false }
            do {
                let skills = try await SkillStore.shared.importFromURL(url)
                showResult(String(
                    format: L("skills.downloaded", "Skills"),
                    skills.count), error: false)
                urlString = ""
            } catch {
                showResult(error.localizedDescription, error: true)
            }
        }
    }

    private func handleImportURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }

        let filename = url.lastPathComponent.lowercased()
        guard Self.allowedExtensions.contains(where: { filename.hasSuffix($0) }) else {
            showResult(L("skills.import.hint", "Skills"), error: true)
            return
        }

        do {
            let skills = try SkillStore.shared.importSkillFile(at: url)
            showResult(String(
                format: L("skills.imported", "Skills"),
                skills.count), error: false)
        } catch {
            showResult(error.localizedDescription, error: true)
        }
    }

    private func showResult(_ text: String, error: Bool) {
        withAnimation(.smooth(duration: 0.25)) {
            message = text
            messageIsError = error
        }
    }
}

// MARK: - Skill icon resolver (maps skill SF symbols to SVG vector icons)

private func resolvedSkillVectorIcon(_ symbol: String) -> String {
    switch symbol {
    case "globe", "safari", "network": return AstralIcons.browser
    case "magnifyingglass", "doc.text.magnifyingglass": return AstralIcons.search
    case "terminal", "apple.terminal": return AstralIcons.terminal
    case "chevron.left.forwardslash.chevron.right", "curlybraces": return AstralIcons.braces
    case "doc.text", "doc.richtext", "doc": return AstralIcons.file
    case "tablecells", "chart.bar": return AstralIcons.table
    case "sparkles", "wand.and.stars": return AstralIcons.sparkles
    case "cpu", "memorychip": return AstralIcons.cpu
    case "bolt", "bolt.fill": return AstralIcons.zap
    case "folder": return AstralIcons.folder
    default: return AstralIcons.puzzle
    }
}

// MARK: - Skill row

/// Installed skill row: vector icon in Liquid Glass circle, localized name/summary, enable toggle.
struct SkillRow: View {
    let skill: Skill
    var onOpen: () -> Void

    @ObservedObject private var store = SkillStore.shared

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AstralTheme.Spacings.s) {
                AIcon(
                    resolvedSkillVectorIcon(skill.icon),
                    size: 16,
                    strokeWidth: 2.1,
                    color: skill.isEnabled ? AstralTheme.accent : AstralTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .liquidGlass(
                        in: Circle(),
                        tint: skill.isEnabled ? AstralTheme.accent.opacity(0.12) : .clear)

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.displayName)
                        .font(AstralTheme.headline(14))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                    Text(skill.displaySummary)
                        .font(AstralTheme.body(12))
                        .foregroundStyle(AstralTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { _ in store.toggle(skill.id) }))
                    .labelsHidden()
                    .tint(AstralTheme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library row

/// Catalog row for a not-yet-installed skill with an Add button.
struct LibrarySkillRow: View {
    let skill: Skill
    var onOpen: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: AstralTheme.Spacings.s) {
            Button(action: onOpen) {
                HStack(spacing: AstralTheme.Spacings.s) {
                    AIcon(
                        resolvedSkillVectorIcon(skill.icon),
                        size: 16,
                        strokeWidth: 2.1,
                        color: AstralTheme.textSecondary)
                        .frame(width: 38, height: 38)
                        .liquidGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.displayName)
                            .font(AstralTheme.headline(14))
                            .foregroundStyle(AstralTheme.textPrimary)
                            .lineLimit(1)
                        Text(skill.displaySummary)
                            .font(AstralTheme.body(12))
                            .foregroundStyle(AstralTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                AIcon(
                    AstralIcons.plus,
                    size: 15,
                    strokeWidth: 2.4,
                    color: AstralTheme.accent)
                    .frame(width: 32, height: 32)
                    .liquidGlass(in: Circle(), tint: AstralTheme.accent.opacity(0.12), interactive: true)
            }
            .accessibilityLabel(Text(String(format: L("skills.addLabel", "Skills"), skill.displayName)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: AstralTheme.Radius.medium, depth: .raised)
    }
}

// MARK: - Detail

/// Full skill detail: description, tools, version, enable toggle, export
/// (`.skill.skill` share file), and uninstall.
struct SkillDetailView: View {
    @EnvironmentObject private var language: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    let skill: Skill
    @ObservedObject private var store = SkillStore.shared

    /// The exported file presented through the share sheet.
    @State private var exportedFile: ExportedSkillFile?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
                    HStack(spacing: AstralTheme.Spacings.m) {
                        AIcon(
                            resolvedSkillVectorIcon(skill.icon),
                            size: 24,
                            strokeWidth: 2.1,
                            color: AstralTheme.accent)
                            .frame(width: 56, height: 56)
                            .liquidGlass(in: Circle(), tint: AstralTheme.accent.opacity(0.12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.displayName)
                                .font(AstralTheme.headline(18))
                                .foregroundStyle(AstralTheme.textPrimary)
                            Text("v\(skill.version) · \(skill.author)")
                                .font(AstralTheme.body(12))
                                .foregroundStyle(AstralTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(skill.displaySummary.isEmpty ? skill.summary : skill.displaySummary)
                        .font(AstralTheme.body(14))
                        .foregroundStyle(AstralTheme.textPrimary)

                    if !skill.tools.isEmpty {
                        VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                            Text(L("skills.tools", "Skills"))
                                .font(AstralTheme.headline(13))
                                .foregroundStyle(AstralTheme.textSecondary)
                            FlowChips(labels: skill.tools)
                        }
                    }

                    VStack(alignment: .leading, spacing: AstralTheme.Spacings.xs) {
                        Text(L("skills.instructions", "Skills"))
                            .font(AstralTheme.headline(13))
                            .foregroundStyle(AstralTheme.textSecondary)
                        Text(skill.instructions)
                            .font(AstralTheme.mono(12))
                            .foregroundStyle(AstralTheme.textPrimary)
                            .textSelection(.enabled)
                            .padding(AstralTheme.Spacings.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: AstralTheme.Radius.small, style: .continuous))
                    }

                    HStack(spacing: AstralTheme.Spacings.s) {
                        Toggle(L("skills.enabled", "Skills"), isOn: Binding(
                            get: { skill.isEnabled },
                            set: { store.setEnabled(skill.id, $0) }))
                            .tint(AstralTheme.accent)

                        Spacer()

                        Button {
                            exportSkill()
                        } label: {
                            HStack(spacing: 6) {
                                AIcon(AstralIcons.share, size: 13, strokeWidth: 2.2, color: AstralTheme.accent)
                                Text(L("common.share", "Shared"))
                                    .font(AstralTheme.headline(13))
                                    .foregroundStyle(AstralTheme.accent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .liquidCapsule(interactive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(L("common.share", "Shared")))

                        if skill.source != .builtin {
                            Button(role: .destructive) {
                                store.uninstall(id: skill.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    AIcon(AstralIcons.trash, size: 13, strokeWidth: 2.2, color: AstralTheme.danger)
                                    Text(L("skills.uninstall", "Skills"))
                                        .font(AstralTheme.headline(13))
                                        .foregroundStyle(AstralTheme.danger)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .liquidCapsule(tint: AstralTheme.danger.opacity(0.08), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AstralTheme.Spacings.m)
            }
            .background(AstralTheme.background)
            .navigationTitle(skill.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.done", "Shared")) { dismiss() }
                }
            }
            .sheet(item: $exportedFile) { file in
                SkillShareSheet(url: file.url)
                    .environment(\.layoutDirection, language.layoutDirection)
            }
        }
    }

    /// Writes the `.skill.skill` file and presents the system share sheet.
    private func exportSkill() {
        do {
            exportedFile = ExportedSkillFile(
                url: try SkillStore.shared.exportFileURL(for: skill.id))
        } catch {
            // Export is best-effort; a failure simply doesn't present a sheet.
        }
    }
}

// MARK: - Export helpers

/// Identity wrapper so a file URL can drive `.sheet(item:)`.
private struct ExportedSkillFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin bridge to the system share sheet for an exported skill file.
private struct SkillShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Creator

/// Manual skill creation: name, summary, instructions.
struct SkillCreatorView: View {
    @EnvironmentObject private var language: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AstralTheme.Spacings.m) {
                    Text(L("skills.createHint", "Skills"))
                        .font(AstralTheme.body(13))
                        .foregroundStyle(AstralTheme.textSecondary)

                    VStack(alignment: .leading, spacing: AstralTheme.Spacings.xxs) {
                        Text(L("skills.name", "Skills"))
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textSecondary)
                        TextField(L("skills.namePlaceholder", "Skills"), text: $name)
                            .font(AstralTheme.body(15))
                            .textFieldStyle(GlassTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: AstralTheme.Spacings.xxs) {
                        Text(L("skills.summaryField", "Skills"))
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textSecondary)
                        TextField(L("skills.summaryPlaceholder", "Skills"), text: $summary)
                            .font(AstralTheme.body(15))
                            .textFieldStyle(GlassTextFieldStyle())
                    }

                    VStack(alignment: .leading, spacing: AstralTheme.Spacings.xxs) {
                        Text(L("skills.instructions", "Skills"))
                            .font(AstralTheme.headline(12))
                            .foregroundStyle(AstralTheme.textSecondary)
                        TextEditor(text: $instructions)
                            .font(AstralTheme.mono(13))
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: AstralTheme.Radius.medium, style: .continuous))
                    }

                    if let error {
                        Text(error)
                            .font(AstralTheme.body(12))
                            .foregroundStyle(AstralTheme.danger)
                    }
                }
                .padding(AstralTheme.Spacings.m)
            }
            .background(AstralTheme.background)
            .navigationTitle(L("skills.create", "Skills"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("settings.cancel", "Settings")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("settings.save", "Settings")) { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            error = L("skills.error.name", "Skills")
            return
        }
        guard !trimmedInstructions.isEmpty else {
            error = L("skills.error.instructions", "Skills")
            return
        }
        _ = try? SkillStore.shared.createManual(
            name: trimmedName,
            summary: summary,
            instructions: trimmedInstructions)
        dismiss()
    }
}

// MARK: - Flow chips

/// Wrapping row of small label chips (used for tool names).
struct FlowChips: View {
    let labels: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
            alignment: .leading,
            spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(AstralTheme.mono(11))
                    .foregroundStyle(AstralTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .liquidCapsule()
            }
        }
    }
}
