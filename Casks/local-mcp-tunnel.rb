cask "local-mcp-tunnel" do
  version "0.1.1"
  sha256 "edc89142bb3dd2cf069f98717b754dd6500adb48d54379c494a7d0b7d8e85453"

  url "https://github.com/walkingwifi28/local-mcp-tunnel/releases/download/v0.1.1/Local-MCP-Tunnel-0.1.1-arm64.zip"
  name "Local MCP Tunnel"
  desc "GUI for controlling tunnel-client and local-mcp"
  homepage "https://github.com/walkingwifi28/local-mcp-tunnel"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Local MCP Tunnel.app"

  caveats <<~EOS
    This build is ad hoc signed but is not Apple notarized.
    If macOS blocks the app on first launch, run:
      xattr -dr com.apple.quarantine /Applications/Local\ MCP\ Tunnel.app
  EOS

  zap trash: [
    "~/Library/Preferences/jp.co.walkingwifi.LocalMCPTunnel.plist",
    "~/Library/Saved Application State/jp.co.walkingwifi.LocalMCPTunnel.savedState",
    "~/Library/Preferences/jp.co.varista.LocalMCPTunnelApp.plist",
    "~/Library/Saved Application State/jp.co.varista.LocalMCPTunnelApp.savedState",
  ]
end
