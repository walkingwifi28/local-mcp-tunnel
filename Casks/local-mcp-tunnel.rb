cask "local-mcp-tunnel" do
  version "0.1.0"
  sha256 "01589e7918006b6c93e8e85e6bb46bf0250638dd7d243c1fae1e399d3865f729"

  url "https://github.com/walkingwifi28/local-mcp-tunnel/releases/download/v0.1.0/Local-MCP-Tunnel-0.1.0-arm64.zip"
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

  app "LocalMCPTunnelApp.app"

  caveats <<~EOS
    This build is ad hoc signed but is not Apple notarized.
    If macOS blocks the app on first launch, run:
      xattr -dr com.apple.quarantine /Applications/LocalMCPTunnelApp.app
  EOS

  zap trash: [
    "~/Library/Preferences/jp.co.varista.LocalMCPTunnelApp.plist",
    "~/Library/Saved Application State/jp.co.varista.LocalMCPTunnelApp.savedState",
  ]
end
