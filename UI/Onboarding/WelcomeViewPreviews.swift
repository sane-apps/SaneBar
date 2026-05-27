import AppKit
import SaneUI
import SwiftUI

#Preview("Page 0 - Welcome") {
    WelcomeView(onComplete: {})
}

#Preview("Page 3 - Core Workflow") {
    BrowseIconsPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 4 - Advanced Workflow") {
    ZoneGuidePage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 5 - Sane Philosophy") {
    SanePromisePage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 6 - Permissions") {
    PermissionPage()
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 7 - Plan / Upgrade") {
    FreeVsProPage(selectedTier: .constant(.pro))
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
}

#Preview("Page 5 - Early Adopter") {
    FreeVsProPage(selectedTier: .constant(.pro))
        .frame(width: 700, height: 520)
        .background(OnboardingBackground())
        .onAppear { LicenseService.shared.grantEarlyAdopterPro() }
}
