cask "sanebar" do
  version "1.0.0"
  sha256 "23c43ee078654e5cf2a72f1d040c1d85f2ea5c320764ae0094fd84cc8f3e2e7a"

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
