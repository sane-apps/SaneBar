import SaneUI
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject private var licenseService = LicenseService.shared

    var body: some View {
        SaneAboutView(
            appName: "SaneBar",
            githubRepo: "SaneBar",
            diagnosticsService: .shared,
            licenses: licenseEntries,
            feedbackExtraAttachments: [
                ("menubar.rectangle", "Menu bar state snapshot (separator positions and counts)")
            ]
        )
    }

    private var licenseEntries: [SaneAboutView.LicenseEntry] {
        var entries = [
            SaneAboutView.LicenseEntry(
                name: "KeyboardShortcuts",
                url: "https://github.com/sindresorhus/KeyboardShortcuts",
                text: """
                MIT License (third-party dependency)

                Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

                Permission is hereby granted, free of charge, to any person obtaining a copy
                of this software and associated documentation files (the "Software"), to deal
                in the Software without restriction, including without limitation the rights
                to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
                copies of the Software, and to permit persons to whom the Software is
                furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all
                copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
                FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
                AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
                LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
                OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
                SOFTWARE.
                """
            )
        ]

        if licenseService.distributionChannel.supportsInAppUpdates {
            entries.append(
                SaneAboutView.LicenseEntry(
                    name: "Sparkle",
                    url: "https://sparkle-project.org",
                    text: """
                    Copyright (c) 2006-2013 Andy Matuschak.
                    Copyright (c) 2009-2013 Elgato Systems GmbH.
                    Copyright (c) 2011-2014 Kornel Lesiński.
                    Copyright (c) 2015-2017 Mayur Pawashe.
                    Copyright (c) 2014 C.W. Betts.
                    Copyright (c) 2014 Petroules Corporation.
                    Copyright (c) 2014 Big Nerd Ranch.
                    All rights reserved.

                    Permission is hereby granted, free of charge, to any person obtaining a copy of
                    this software and associated documentation files (the "Software"), to deal in
                    the Software without restriction, including without limitation the rights to
                    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
                    of the Software, and to permit persons to whom the Software is furnished to do
                    so, subject to the following conditions:

                    The above copyright notice and this permission notice shall be included in all
                    copies or substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
                    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
                    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
                    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
                    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
                    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                    """
                )
            )
        }

        return entries
    }
}
