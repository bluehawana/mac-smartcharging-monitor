cask "smartcharging" do
  version "1.0.0"
  sha256 "a43f0c1b17dc63c3df4076a519a3a74038f8aed3a3945f10e9392a9059ec8368"

  url "https://github.com/bluehawana/mac-smartcharging-monitor/releases/download/v#{version}/SmartCharging-#{version}.dmg",
      verified: "github.com/bluehawana/mac-smartcharging-monitor/"
  name "Smart Charging"
  desc "Menu bar monitor showing what your charger actually delivers"
  homepage "https://github.com/bluehawana/mac-smartcharging-monitor"

  depends_on macos: :sonoma

  app "SmartCharging.app"

  zap trash: [
    "~/Library/Application Support/SmartCharging",
    "~/Library/Preferences/com.bluehawana.smartcharging.plist",
  ]
end
