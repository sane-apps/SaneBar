import AppKit
import SaneUI
import SwiftUI

// MARK: - Page 1: Welcome + Import Detection

struct WelcomeActionPage: View {
    @State private var isHidden = false
    @State private var detectedCompetitor: String?
    @State private var detectedCompetitorPlistURL: URL?
    @State private var importResult: String?

    var body: some View {
        VStack(spacing: 20) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to SaneBar")
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(.white)

            (Text("One click to ") + Text("hide").foregroundColor(saneAccentSoft) + Text(". One click to ") + Text("reveal").foregroundColor(saneAccentSoft) + Text("."))
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.9))

            // Menu bar simulation — bar stays same size, icons fade in/out
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Icons + divider — fade only, no size change
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                        Image(systemName: "bubble.left.fill")
                        Image(systemName: "headphones")
                        Image(systemName: "cloud.fill")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .opacity(isHidden ? 0 : 1)

                    Text("/")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .opacity(isHidden ? 0 : 1)

                    // SaneBar button — always visible
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { isHidden.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 14, weight: .semibold))
                            Text("CLICK!")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(saneAccentSoft)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(navyBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Control Center — always visible
                    Image(systemName: "switch.2")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                .animation(.easeInOut(duration: 0.3), value: isHidden)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.85))
                )

                Group {
                    if isHidden {
                        Text("Hidden! Click again to reveal.")
                            .foregroundStyle(.white)
                    } else {
                        Text("Tip").foregroundColor(saneAccentSoft).bold() + Text(": ⌘ + drag icons in your menu bar to rearrange").foregroundColor(.white)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .frame(height: 18)
            }

            // Import detection banner
            if let competitor = detectedCompetitor {
                importBanner(competitor)
            }
        }
        .padding(32)
        .onAppear { detectCompetitor() }
    }

    @ViewBuilder
    private func importBanner(_ competitor: String) -> some View {
        if let result = importResult {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(result)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 20)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.arrow.left.circle.fill")
                        .foregroundStyle(saneAccent)
                    Text("Switching from \(competitor)?")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                    Button(competitor == "Bartender" ? "Import Layout" : "Import Settings") {
                        performImport(competitor)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(saneAccent)
                    .controlSize(.small)
                }

                if competitor == "Ice" {
                    Text("SaneBar can import your Ice settings here, but Ice does not store icon positions.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("SaneBar can import your Bartender layout and matching settings from the detected plist.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(saneAccentDeep.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(saneAccent.opacity(0.28), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
        }
    }

    private func detectCompetitor() {
        let fm = FileManager.default
        let prefs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        let bartenderPlists = [
            "com.surteesstudios.Bartender-setapp.plist",
            "com.surteesstudios.Bartender-4.plist",
            "com.surteesstudios.Bartender.plist"
        ]
        for plist in bartenderPlists where fm.fileExists(atPath: prefs.appendingPathComponent(plist).path) {
            detectedCompetitor = "Bartender"
            detectedCompetitorPlistURL = prefs.appendingPathComponent(plist)
            return
        }
        if fm.fileExists(atPath: prefs.appendingPathComponent("com.jordanbaird.Ice.plist").path) {
            detectedCompetitor = "Ice"
            detectedCompetitorPlistURL = prefs.appendingPathComponent("com.jordanbaird.Ice.plist")
        }
    }

    private func performImport(_ competitor: String) {
        let manager = MenuBarManager.shared

        if competitor == "Ice" {
            guard let url = detectedCompetitorPlistURL else {
                importResult = "Import available in Settings → General → Data"
                return
            }
            do {
                let summary = try IceImportService.importSettings(from: url, menuBarManager: manager)
                importResult = "Imported \(summary.applied.count) settings from Ice"
            } catch {
                importResult = "Import available in Settings → General → Data"
            }
        } else {
            guard let url = detectedCompetitorPlistURL else {
                importResult = "Import available in Settings → General → Data"
                return
            }
            Task { @MainActor in
                do {
                    let summary = try await BartenderImportService.importSettings(from: url, menuBarManager: manager)
                    importResult = "Imported Bartender layout (\(summary.totalMoved) icons moved)"
                } catch {
                    importResult = "Import available in Settings → General → Data"
                }
            }
        }
    }
}
