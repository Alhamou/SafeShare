cask "safeshare" do
  version "1.0.0"
  sha256 :no_check

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
