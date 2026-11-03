import SwiftUI
import WebKit

// MARK: - BrowserView (V5 Liquid Glass Browser)

struct BrowserView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        BrowserContent(browser: env.browser)
    }
}

// MARK: - BrowserContent

private struct BrowserContent: View {
    @ObservedObject var browser: BrowserController
    @EnvironmentObject private var language: LocalizationManager

    @State private var urlField: String = ""
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        VStack(spacing: AstralTheme.Spacings.s) {
            toolbar

            if browser.isLoading {
                loadingBar
            }

            contentArea
        }
        .onAppear {
            if urlField.isEmpty {
                urlField = browser.urlText
            }
        }
        .onChange(of: browser.urlText) { _, newValue in
            if !urlFieldFocused {
                urlField = newValue
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            navButton(
                icon: AstralIcons.back,
                enabled: browser.canGoBack,
                accessibilityKey: "browser.nav.back") {
                browser.userBack()
            }

            navButton(
                icon: AstralIcons.forward,
                enabled: browser.canGoForward,
                accessibilityKey: "browser.nav.forward") {
                browser.userForward()
            }

            navButton(
                icon: AstralIcons.refresh,
                enabled: true,
                accessibilityKey: "browser.nav.reload") {
                browser.userReload()
            }

            HStack(spacing: 7) {
                AIcon(
                    AstralIcons.browser,
                    size: 13.5,
                    strokeWidth: 2.1,
                    color: AstralTheme.textSecondary)
                TextField(L("browser.urlPlaceholder", "Browser"), text: $urlField)
                    .font(AstralTheme.body(14))
                    .foregroundStyle(AstralTheme.textPrimary)
                    .focused($urlFieldFocused)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        urlFieldFocused = false
                        browser.loadUserURL(urlField)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule(), interactive: true)

            if browser.agentMode {
                agentIndicator
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(
            cornerRadius: AstralTheme.Radius.large,
            depth: .panel,
            tint: AstralTheme.nebulaViolet)
        .padding(.horizontal, AstralTheme.Spacings.m)
        .padding(.top, AstralTheme.Spacings.xxs)
    }

    private func navButton(
        icon: String,
        enabled: Bool,
        accessibilityKey: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AIcon(
                icon,
                size: 15,
                strokeWidth: 2.2,
                color: enabled
                    ? AstralTheme.textPrimary
                    : AstralTheme.textSecondary.opacity(0.35))
                .frame(width: 34, height: 34)
                .liquidGlass(in: Circle(), interactive: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(L(accessibilityKey, "Browser"))
    }

    private var agentIndicator: some View {
        HStack(spacing: AstralTheme.Spacings.xxs) {
            ActivityOrb(size: 14)
            Text(L("browser.agentDriving", "Browser"))
                .font(AstralTheme.headline(11))
                .foregroundStyle(AstralTheme.textPrimary)
        }
        .padding(.horizontal, AstralTheme.Spacings.s)
        .padding(.vertical, AstralTheme.Spacings.xxs)
        .glassPill(tint: AstralTheme.nebulaViolet)
        .accessibilityLabel(L("browser.takeover", "Browser"))
    }

    // MARK: Progress

    private var loadingBar: some View {
        Capsule()
            .fill(AstralTheme.auroraWide)
            .frame(height: 3)
            .shimmer(active: true, cornerRadius: 1.5)
            .clipShape(Capsule())
            .padding(.horizontal, AstralTheme.Spacings.l)
            .accessibilityLabel(L("browser.loading", "Browser"))
    }

    // MARK: Web content

    private var contentArea: some View {
        WebViewBridge(webView: browser.webView)
            .clipShape(
                RoundedRectangle(cornerRadius: AstralTheme.Radius.large, style: .continuous))
            .padding(.horizontal, AstralTheme.Spacings.xxs)
            .overlay(alignment: .bottom) {
                if browser.agentMode && !browser.lastAgentAction.isEmpty {
                    agentChip
                        .padding(.bottom, AstralTheme.Spacings.m)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
    }

    private var agentChip: some View {
        HStack(spacing: AstralTheme.Spacings.xs) {
            ActivityOrb(size: 16)
            Text(browser.lastAgentAction)
                .font(AstralTheme.body(12))
                .foregroundStyle(AstralTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, AstralTheme.Spacings.m)
        .padding(.vertical, AstralTheme.Spacings.xs)
        .glassPill(tint: AstralTheme.nebulaViolet)
    }
}

// MARK: - WebViewBridge

struct WebViewBridge: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
