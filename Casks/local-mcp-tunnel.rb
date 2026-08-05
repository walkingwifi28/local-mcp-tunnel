cask "local-mcp-tunnel" do
  version "0.1.13"
  sha256 "31d5c03a278691d2c74186fbb609f6ae5eb66bdf284ec625dfb062f4142ebf4b"

  url "https://github.com/walkingwifi28/local-mcp-tunnel/releases/download/v0.1.13/Local-MCP-Tunnel-0.1.13-arm64.zip"
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
