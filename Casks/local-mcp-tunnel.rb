cask "local-mcp-tunnel" do
  version "0.1.11"
  sha256 "2c95216b0d6105ff3260cbd42f3342d075b8a995d1f67559dda7c65b46cb771a"

  url "https://github.com/walkingwifi28/local-mcp-tunnel/releases/download/v0.1.11/Local-MCP-Tunnel-0.1.11-arm64.zip"
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
