cask "sanebar" do
  version "1.0.0"
  sha256 "b1a6b36d26ee8b4e45cab2f883161dce3f1605d9d4d12f1ca111fb85ab1150df"

  url "https://github.com/stephanjoseph/SaneBar/releases/download/v#{version}/SaneBar-#{version}.dmg"
  name "SaneBar"
  desc "Privacy-focused menu bar manager for macOS"
  homepage "https://github.com/stephanjoseph/SaneBar"

  depends_on macos: ">= :sequoia"

  app "SaneBar.app"

  zap trash: [
    "~/Library/Preferences/com.sanevideo.SaneBar.plist",
    "~/Library/Application Support/SaneBar",
  ]
end
