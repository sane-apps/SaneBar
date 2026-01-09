cask "sanebar" do
  version "1.0.1"
  sha256 "c0b826de8cb94fe0f55c4ba6519798111dd1d31fe7d297162ad3fdf8b6e08fa0"

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
