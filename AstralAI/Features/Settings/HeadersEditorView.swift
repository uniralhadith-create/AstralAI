import SwiftUI

// MARK: - Headers editor (V5 System-Adaptive iOS 27 Liquid Glass)

/// Edits the extra HTTP headers sent with custom-protocol requests. Rows
/// are mirrored from the dictionary binding on appear and written back on
/// every change; rows with an empty key are dropped.
struct HeadersEditorView: View {
    @Binding var headers: [String: String]

    @State private var rows: [HeaderRow] = []

    private struct HeaderRow: Identifiable, Equatable {
        let id: UUID
        var key: String
        var value: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AstralTheme.Spacings.s) {
            SectionHeader(icon: "arrow.up.and.down.text.horizontal", "settings.headers", table: "Settings")

            ForEach($rows) { $row in
                HStack(spacing: AstralTheme.Spacings.xs) {
                    TextField(L("settings.headerKey", "Settings"), text: $row.key)
                        .font(AstralTheme.mono(12))
                        .textFieldStyle(GlassTextFieldStyle())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(L("settings.headerValue", "Settings"), text: $row.value)
                        .font(AstralTheme.mono(12))
                        .textFieldStyle(GlassTextFieldStyle())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        AIcon(
                            AstralIcons.trash,
                            size: 14,
                            strokeWidth: 2.1,
                            color: AstralTheme.danger)
                            .frame(width: 34, height: 34)
                            .liquidGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                rows.append(HeaderRow(id: UUID(), key: "", value: ""))
            } label: {
                HStack(spacing: 6) {
                    AIcon(
                        AstralIcons.plus,
                        size: 13,
                        strokeWidth: 2.3,
                        color: AstralTheme.auroraCyan)
                    Text(L("settings.addHeader", "Settings"))
                        .font(AstralTheme.headline(13))
                        .foregroundStyle(AstralTheme.auroraCyan)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .liquidCapsule(interactive: true)
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            rows = headers
                .sorted { $0.key < $1.key }
                .map { HeaderRow(id: UUID(), key: $0.key, value: $0.value) }
        }
        .onChange(of: rows) { _, newRows in
            // Last row wins on duplicate keys; empty keys are dropped.
            var merged: [String: String] = [:]
            for row in newRows where !row.key.isEmpty {
                merged[row.key] = row.value
            }
            headers = merged
        }
    }
}
