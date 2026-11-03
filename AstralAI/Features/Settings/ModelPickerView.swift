import SwiftUI

// MARK: - Searchable model picker (V5 Liquid Glass)

struct ModelPickerView: View {
    let models: [ModelInfo]
    let currentSelection: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ModelInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return models }
        return models.filter { model in
            model.id.lowercased().contains(trimmed)
                || (model.name?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, AstralTheme.Spacings.m)
                    .padding(.vertical, AstralTheme.Spacings.s)

                if filtered.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: AstralTheme.Spacings.xs) {
                            ForEach(filtered) { model in
                                row(model)
                            }
                        }
                        .padding(.horizontal, AstralTheme.Spacings.m)
                        .padding(.vertical, AstralTheme.Spacings.s)
                    }
                }
            }
            .background(AstralTheme.background.ignoresSafeArea())
            .navigationTitle(L("settings.models", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("settings.cancel", "Settings")) { dismiss() }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AstralTheme.Spacings.xs) {
            AIcon(
                AstralIcons.search,
                size: 14,
                strokeWidth: 2.2,
                color: AstralTheme.moonDust)
            TextField(L("settings.searchModels", "Settings"), text: $query)
                .font(AstralTheme.body(15))
                .foregroundStyle(AstralTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, AstralTheme.Spacings.m)
        .padding(.vertical, AstralTheme.Spacings.s)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: AstralTheme.Spacings.s) {
            AIcon(
                AstralIcons.search,
                size: 28,
                strokeWidth: 1.8,
                color: AstralTheme.moonDust)
            Text(L("settings.noModels", "Settings"))
                .font(AstralTheme.body(13))
                .foregroundStyle(AstralTheme.textSecondary)
        }
    }

    private func row(_ model: ModelInfo) -> some View {
        let isSelected = model.id == currentSelection
        return Button {
            onSelect(model.id)
            dismiss()
        } label: {
            HStack(spacing: AstralTheme.Spacings.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.id)
                        .font(AstralTheme.mono(13))
                        .foregroundStyle(AstralTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        if let ownedBy = model.ownedBy, !ownedBy.isEmpty {
                            Text(ownedBy)
                                .font(AstralTheme.body(11))
                                .foregroundStyle(AstralTheme.moonDust)
                                .lineLimit(1)
                        }
                        if let supportsTools = model.supportsTools {
                            HStack(spacing: 4) {
                                AIcon(
                                    supportsTools ? AstralIcons.wrench : AstralIcons.file,
                                    size: 9.5,
                                    strokeWidth: 2.3,
                                    color: supportsTools ? AstralTheme.orbGreen : AstralTheme.textSecondary)
                                Text(supportsTools
                                    ? L("settings.toolsNative", "Settings")
                                    : L("settings.toolsText", "Settings"))
                                    .font(AstralTheme.mono(9.5).weight(.semibold))
                                    .foregroundStyle(
                                        supportsTools
                                            ? AstralTheme.textPrimary
                                            : AstralTheme.textSecondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(
                                    AstralTheme.actionFill.opacity(
                                        supportsTools ? 0.16 : 0.08)))
                            .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(AstralTheme.orbGreen)
                            .frame(width: 18, height: 18)
                        AIcon(AstralIcons.check, size: 10, strokeWidth: 3.0, color: .black)
                    }
                }
            }
            .padding(AstralTheme.Spacings.m)
            .glassCard(
                cornerRadius: AstralTheme.Radius.medium,
                depth: .raised,
                tint: isSelected ? AstralTheme.auroraCyan : .white)
        }
        .buttonStyle(.plain)
    }
}
