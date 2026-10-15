# Portico: an SSH client for iPhone and iPad

Native SwiftUI app. Supports **iOS 16 and later**, iPhone and iPad.

- Real terminal: xterm-256color, colors, mouse, tmux, vim, htop (SwiftTerm)
- Password, Ed25519 and RSA key authentication; encrypted keys with passphrase
- Generate Ed25519 keys on the device, or import OpenSSH keys from Files or the clipboard
- Passwords, private keys and passphrases live in the iOS Keychain (this-device-only)
- Host key verification on first use, with a loud warning if a key ever changes
- Multiple sessions as tabs, with reconnect
- SFTP file browser: browse, upload, download and share, rename, delete, new folder
- Snippets: saved commands you can send to any session
- 7 themes, 3 fonts, adjustable size, keep-screen-awake
- Optional Face ID / passcode lock

## Build the IPA (no Mac needed)

GitHub builds it for you on a macOS runner.

1. Create a new GitHub repository and push this folder to it.
2. Open the **Actions** tab, choose **Build IPA (unsigned)** and click **Run workflow**
   (it also runs on every push). It takes about 10 minutes.
3. Download the **Portico-unsigned-ipa** artifact and unzip it. Inside is `Portico-unsigned.ipa`.

### Install it on your device

An unsigned IPA must be signed with your own Apple ID or certificate first:

| Tool | Notes |
|------|-------|
| AltStore or SideStore | Free Apple ID, re-signs every 7 days, can refresh automatically |
| Sideloadly | Windows or Mac, free Apple ID, re-sign every 7 days |
| TrollStore | Only on supported iOS versions; installs permanently |
| Your own certificate | Use the **Build IPA (signed)** workflow below |

### Signed builds (paid Apple Developer account)

Add these repository secrets, then run **Build IPA (signed)**:
`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `BUILD_PROVISION_PROFILE_BASE64`,
`KEYCHAIN_PASSWORD`, `TEAM_ID`. The bundle id input must match your provisioning profile.

### Build on a Mac instead

```bash
brew install xcodegen
xcodegen generate
open Portico.xcodeproj    # pick your team under Signing, then Run
```

## How it is put together

```
project.yml                  XcodeGen description (iOS 16 target, packages)
Packages/Citadel             Vendored Citadel 0.12.1 (see below)
Portico/
  Services/                  Keychain, key tools, known hosts, SSH session, stores
  Views/                     Hosts, Terminal, Keys, SFTP, Snippets, Settings
  Support/                   Themes, helpers, iOS 16 compatibility views
```

Dependencies: [Citadel](https://github.com/orlandos-nl/Citadel) (SSH, MIT),
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.20.0 (terminal, MIT),
swift-nio, swift-nio-ssh, swift-crypto.

### Why Citadel is vendored

Upstream Citadel requires iOS 17. `Packages/Citadel` is Citadel 0.12.1 with three changes
so it works on iOS 16: the platform is lowered to iOS 16, `withDiscardingTaskGroup` (iOS 17)
is replaced by `withTaskGroup`, and `AsyncStream.makeStream` is replaced by an equivalent
helper (`StreamCompat.swift`). Its MIT license is included.

## Limits to know about

- iOS suspends apps in the background, so SSH sessions drop shortly after you leave the app.
  Use `tmux` or `screen` on the server and tap **Reconnect**. This is an iOS rule for every SSH app.
- Key formats: OpenSSH private keys (Ed25519, RSA). ECDSA and old PEM-style keys are not
  supported yet. Convert with `ssh-keygen -p -o -f keyfile`.
- No SSH agent forwarding, port forwarding UI, or Mosh yet.

## Honest status

This source was written without access to a Swift compiler, so the first CI run may report
compile errors. Open the failed run, download the **build-log** artifact, and fix the
reported lines; they should be small.
