import SwiftUI

/// Sheet shown when a free user tries a Pro action. Contextual to the feature they tapped.
struct ProUpsellView: View {
    let feature: ProFeature
    /// Optional explicit close action (used when presented in a standalone window).
    /// When nil, falls back to SwiftUI's `dismiss` environment action (sheets).
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var licenseService = LicenseService.shared
    @State private var showingLicenseEntry = false

    private func closeView() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Close button
            HStack {
                Spacer()
                Button { closeView() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            // Feature they tried
            VStack(spacing: 8) {
                Image(systemName: feature.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.teal)

                Text(feature.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.horizontal, 20)

            // Value props
            VStack(alignment: .leading, spacing: 6) {
                proPoint(icon: "star.fill", text: "All Pro features unlocked")
                proPoint(icon: "infinity", text: "Lifetime updates — no subscription")
                proPoint(icon: "lock.shield", text: "100% on-device, no account required")
                proPoint(icon: "heart.fill", text: "Support independent development")
            }
            .padding(.horizontal, 10)

            // Price + CTA
            VStack(spacing: 8) {
                Text("$6.99")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.teal)

                Text("One-time purchase")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))

                Button {
                    NSWorkspace.shared.open(LicenseService.checkoutURL)
                } label: {
                    Text("Unlock Pro")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .controlSize(.large)
            }

            // Already purchased
            Button("I already purchased") {
                showingLicenseEntry = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.teal)
            .font(.system(size: 13))
        }
        .padding(24)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand { closeView() }
        .onKeyPress(.escape) { closeView(); return .handled }
        .sheet(isPresented: $showingLicenseEntry) {
            LicenseEntryView()
        }
        .onChange(of: licenseService.isPro) { _, newValue in
            if newValue { closeView() }
        }
    }

    private func proPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Standalone Window Presenter

/// Presents ProUpsellView in its own titled window.
/// Used when the trigger comes from a borderless panel (Second Menu Bar)
/// where `.sheet()` can't render properly.
@MainActor
enum ProUpsellWindow {
    private static var window: NSWindow?

    static func show(feature: ProFeature) {
        // Close existing if visible
        if let window, window.isVisible {
            window.close()
        }

        let upsellView = ProUpsellView(feature: feature, onClose: { close() })
        let hostingView = NSHostingView(rootView: upsellView)
        hostingView.setContentHuggingPriority(.required, for: .vertical)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.title = "Unlock Pro"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        // Esc closes the panel (NSPanel standard behavior with .cancelAction)
        panel.becomesKeyOnlyIfNeeded = false

        // Hide traffic light buttons — the SwiftUI X (top-right) is the close mechanism
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Size to fit SwiftUI content
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = panel
    }

    static func close() {
        window?.close()
        window = nil
    }
}

// MARK: - License Entry View

/// Simple form for entering a license key. Shown from ProUpsellView or Settings.
struct LicenseEntryView: View {
    @ObservedObject private var licenseService = LicenseService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            Text("Enter License Key")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Paste the license key from your purchase confirmation email.")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", text: $licenseKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

            if let error = licenseService.validationError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 13))

                Button("Activate") {
                    Task {
                        await licenseService.activate(key: licenseKey)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .font(.system(size: 13))
                .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licenseService.isValidating)

                if licenseService.isValidating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: licenseService.isPro) { _, newValue in
            if newValue { dismiss() }
        }
    }
}

#Preview("Upsell") {
    ProUpsellView(feature: .iconActivation)
}

#Preview("License Entry") {
    LicenseEntryView()
}
