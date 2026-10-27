import AppKit
import SaneUI
import SwiftUI

struct AppPickerView: View {
    @Binding var selectedBundleIDs: [String]
    let title: String

    @State private var showingPicker = false
    @State private var availableApps: [AppInfo] = []
    @State private var searchText = ""

    struct AppInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let icon: NSImage?
    }

    var body: some View {
        CompactRow("If these apps open") {
            HStack(spacing: 8) {
                if selectedBundleIDs.isEmpty {
                    Text("None selected")
                        .font(SaneTypography.body)
                        .foregroundStyle(SaneTypography.text)
                        .lineLimit(1)
                }
                Button("Add App…") {
                    loadApps()
                    showingPicker = true
                }
                .buttonStyle(SaneActionButtonStyle())
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .sheet(isPresented: $showingPicker) {
            appPickerSheet
        }

        ForEach(selectedBundleIDs, id: \.self) { bundleID in
            CompactDivider()
            CompactRow(appName(for: bundleID)) {
                Button {
                    selectedBundleIDs.removeAll { $0 == bundleID }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Remove this app")
            }
        }
    }

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingPicker = false
                }
                .buttonStyle(SaneActionButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            TextField("Search apps…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                Button {
                    toggleApp(app)
                } label: {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app")
                                .frame(width: 24, height: 24)
                        }
                        Text(app.name)
                        Spacer()
                        if selectedBundleIDs.contains(app.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .listStyle(.plain)
        }
        .frame(width: 350, height: 400)
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return availableApps }
        return availableApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func toggleApp(_ app: AppInfo) {
        if selectedBundleIDs.contains(app.id) {
            selectedBundleIDs.removeAll { $0 == app.id }
        } else {
            selectedBundleIDs.append(app.id)
        }
    }

    private func loadApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
            .compactMap { app -> AppInfo? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppInfo(id: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }

        var seen = Set<String>()
        availableApps = running.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func appName(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName {
            return name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
