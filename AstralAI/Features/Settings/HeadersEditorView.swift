import SwiftUI

// MARK: - Headers editor

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
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AstralTheme.danger)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                rows.append(HeaderRow(id: UUID(), key: "", value: ""))
            } label: {
                Label(L("settings.addHeader", "Settings"), systemImage: "plus.circle")
                    .font(AstralTheme.body(13))
                    .foregroundStyle(AstralTheme.auroraCyan)
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
