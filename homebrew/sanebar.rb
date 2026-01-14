cask "sanebar" do
  version "1.0.5"
  sha256 "c731e815698d7388acf2e0ca59def7a5c3b5209faab8f26fc4b941436ffa15cc"

  url "https://github.com/stephanjoseph/SaneBar/releases/download/v#{version}/SaneBar-#{version}.dmg"
  name "SaneBar"
  desc "Privacy-focused menu bar manager for macOS"
  homepage "https://github.com/stephanjoseph/SaneBar"

  depends_on macos: ">= :sequoia"

  app "SaneBar.app"

  zap trash: [
    "~/Library/Preferences/com.sanebar.app.plist",
    "~/Library/Application Support/SaneBar",
  ]
end
