# Local MCP Tunnel App

`tunnel-client`と`local-mcp`をSwiftUIから操作するmacOSアプリです。

- 対応CPU: Apple Silicon（arm64）のみ
- 対応OS: macOS 14 Sonoma以降

## 対応コマンド

```bash
tunnel-client init --sample sample_mcp_stdio_local --profile <profile> --tunnel-id <tunnel-id> --mcp-command "$HOME/.local/bin/local-mcp mcp" --force
tunnel-client run --profile <profile>
local-mcp start <session-id>
```

local-mcp起動後、以下を標準入力へ送信できます。

```text
/permission ask
/permission yolo
/permission allow <directory>
/permission revoke <directory>
/permission list
/permission status
```

## 設定保存

- Profile、Tunnel ID、Session IDなど: `UserDefaults`
- `CONTROL_PLANE_API_KEY`: macOS Keychain
- App Sandbox: 無効（任意のCLIとディレクトリへアクセスするため）
- Hardened Runtime: 有効

## 開発

```bash
open LocalMCPTunnelApp.xcodeproj
```

### ビルド確認

```bash
./Scripts/verify-build.sh
```

XcodeのCommand Line Toolsだけが選択されている場合は、Xcode本体を選択してください。

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Homebrew Cask配布

GUIアプリのため、Homebrew FormulaではなくHomebrew Caskとして配布します。

### 1. Apple Silicon用リリースZIPを作る

```bash
./Scripts/build-release.sh 1.0.0
```

以下が生成されます。

```text
dist/Local-MCP-Tunnel-1.0.0-arm64.zip
dist/Local-MCP-Tunnel-1.0.0-arm64.zip.sha256
```

スクリプトは実行ファイルが`arm64`のみであることも検証します。

### 2. ローカルでHomebrewインストールを確認する

`build-release.sh`の最後に表示されるSHA-256を使い、ローカル用Caskを生成します。

```bash
SHA256="$(shasum -a 256 dist/Local-MCP-Tunnel-1.0.0-arm64.zip | awk '{print $1}')"

./Scripts/generate-cask.sh \
  1.0.0 \
  "$SHA256" \
  "file://$(pwd)/dist/Local-MCP-Tunnel-1.0.0-arm64.zip" \
  dist/local-mcp-tunnel.rb \
  "https://github.com/OWNER/REPO"

brew install --cask "$(pwd)/dist/local-mcp-tunnel.rb"
```

アンインストールは次のとおりです。

```bash
brew uninstall --cask local-mcp-tunnel
```

### 3. GitHub ReleaseへZIPを公開する

GitHub Releaseのタグを`v1.0.0`、添付ファイル名を次の名前にします。

```text
Local-MCP-Tunnel-1.0.0-arm64.zip
```

公開URLの形式は次のようになります。

```text
https://github.com/OWNER/REPO/releases/download/v1.0.0/Local-MCP-Tunnel-1.0.0-arm64.zip
```

### 4. 公開用Caskを生成する

```bash
SHA256="$(shasum -a 256 dist/Local-MCP-Tunnel-1.0.0-arm64.zip | awk '{print $1}')"

./Scripts/generate-cask.sh \
  1.0.0 \
  "$SHA256" \
  "https://github.com/OWNER/REPO/releases/download/v1.0.0/Local-MCP-Tunnel-1.0.0-arm64.zip" \
  Casks/local-mcp-tunnel.rb \
  "https://github.com/OWNER/REPO"
```

生成された`Casks/local-mcp-tunnel.rb`を、`homebrew-tap`リポジトリの`Casks`ディレクトリへ配置します。

```text
homebrew-tap/
└── Casks/
    └── local-mcp-tunnel.rb
```

利用者は次の2コマンドでインストールできます。

```bash
brew tap OWNER/tap
brew install --cask local-mcp-tunnel
```

または1コマンドでインストールできます。

```bash
brew install --cask OWNER/tap/local-mcp-tunnel
```

## 署名・公証付きリリース

一般公開する場合は、Developer ID Application証明書で署名し、Appleの公証を通すことを推奨します。

まず、`notarytool`用の資格情報をKeychainへ保存します。

```bash
xcrun notarytool store-credentials local-mcp-tunnel-notary \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

次に、環境変数を指定してリリースを作成します。

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: COMPANY NAME (TEAM_ID)" \
NOTARYTOOL_PROFILE="local-mcp-tunnel-notary" \
./Scripts/build-release.sh 1.0.0
```

署名だけを行い、公証を省略する場合は`NOTARYTOOL_PROFILE`を指定しません。
