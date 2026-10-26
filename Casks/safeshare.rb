cask "safeshare" do
  version "1.1.0"
  sha256 "80ca362a32c023db668fd4c949dc8b50fa73f446ee69fa59656c7869e63abf82"

  url "https://github.com/Alhamou/SafeShare/releases/download/v#{version}/SafeShare-#{version}.dmg"
  name "SafeShare"
  desc "Privacy-preserving hardware-filtered screen sharing utility for macOS"
  homepage "https://github.com/Alhamou/SafeShare"

  depends_on macos: ">= :sonoma"

  app "SafeShare.app"

  zap trash: [
    "~/Library/Application Support/SafeShare",
    "~/Library/Preferences/com.safeshare.app.plist",
  ]
end
