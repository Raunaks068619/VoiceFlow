# VoiceFlow Signing & Notarization Guide

This guide walks you from zero → distributing a properly signed + notarized DMG that end users can open without Gatekeeper warnings.

**Time investment:** ~1 hour for first-time setup, then ~5 minutes per release.
**Cost:** $99/year (Apple Developer Program).

---

## Why bother?

Without Developer ID + notarization:
- Gatekeeper shows scary "app cannot be opened" warnings
- Input Monitoring permission prompts are flaky (ad-hoc signatures break TCC trust)
- Users have to right-click → Open or run `xattr -dr com.apple.quarantine` manually
- macOS periodically revalidates and may invalidate TCC grants on version upgrades

With notarization:
- DMG opens cleanly with a standard "Drag to Applications" UX
- All permission prompts fire reliably
- Homebrew Cask installs work without `postflight` hacks
- Users trust the app more (rightly so)

---

## Prerequisites

- An Apple ID with 2FA enabled
- $99 for Apple Developer Program annual fee
- macOS machine with Xcode installed

---

## Step 1: Enroll in the Apple Developer Program

1. Go to https://developer.apple.com/programs/
2. Click **Enroll** → sign in with your Apple ID
3. Choose **Individual** (or **Organization** if you have a business)
4. Pay the $99 fee (annual)
5. Wait for approval email (usually <24 hours for individuals, up to 2 weeks for orgs)

Once approved, you'll have access to the **Developer Portal**.

---

## Step 2: Generate a Developer ID Application certificate

This is the cert that signs the app itself.

1. Open **Xcode** → Settings → Accounts
2. Add your Apple ID if not already
3. Select your team → click **Manage Certificates**
4. Click the **+** → choose **Developer ID Application**
5. Certificate is auto-installed in your Keychain

Verify it's in Keychain:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

You should see something like:
```
1) ABCDEF1234567890ABCDEF1234567890ABCDEF12 "Developer ID Application: Your Name (TEAM_ID)"
```

Copy the full quoted string — this is your `DEVELOPER_ID`.

---

## Step 3: Create an app-specific password for notarization

Notarization requires a non-personal password to be safe in shell env vars.

1. Go to https://appleid.apple.com → Sign In
2. Under **Sign-In and Security** → **App-Specific Passwords**
3. Click **+** → name it `voiceflow-notarize`
4. Copy the generated password (looks like `abcd-efgh-ijkl-mnop`)

---

## Step 4: Find your Team ID

1. Go to https://developer.apple.com/account
2. Click **Membership details** (top right)
3. Your **Team ID** is a 10-character alphanumeric string

---

## Step 5: Configure credentials

You have two options. **Keychain profile is recommended** — it avoids passing passwords as env vars.

### Option A: Keychain profile (recommended)

```bash
xcrun notarytool store-credentials "voiceflow-notarize" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID" \
  --password "abcd-efgh-ijkl-mnop"
```

Then export just two env vars in your shell rc file:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (YOURTEAMID)"
export NOTARIZE_KEYCHAIN_PROFILE="voiceflow-notarize"
```

### Option B: Plain env vars (less secure)

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (YOURTEAMID)"
export NOTARIZE_APPLE_ID="you@example.com"
export NOTARIZE_TEAM_ID="YOURTEAMID"
export NOTARIZE_PASSWORD="abcd-efgh-ijkl-mnop"
```

**⚠️ Never commit these to git.** Put them in `~/.zshrc` or a `.env` file that's in `.gitignore`.

---

## Step 6: Enable hardened runtime in project.yml

Already configured. The current `project.yml` has:

```yaml
ENABLE_HARDENED_RUNTIME: YES
CODE_SIGN_IDENTITY: "-"    # overridden by the build script
```

The build script will use `DEVELOPER_ID` from env when signing.

---

## Step 7: Build a notarized DMG

```bash
cd /path/to/VoiceFlow
./scripts/release_dmg.sh --version v1.0.7
```

The script auto-detects your env vars and:
1. Builds Release
2. Signs with Developer ID + hardened runtime + secure timestamp
3. Creates DMG
4. Signs DMG
5. Submits to Apple's notary service (takes 1-5 min)
6. Staples the ticket onto the DMG
7. Verifies everything

Output:
```
================================================================
  Build complete
  Mode:     notarized
  DMG:      dist/VoiceFlow-v1.0.7.dmg
  SHA-256:  abc123...
================================================================
READY FOR DISTRIBUTION. End users can download and open directly.
```

---

## Step 8: Distribute

### Direct DMG
Upload the DMG anywhere (GitHub Releases, S3, your website). Users can now:
1. Download
2. Open
3. Drag to Applications
4. Launch — no Gatekeeper warnings, all permission prompts work

### Homebrew Cask
Your existing cask manifest can now drop the `postflight` hacks:

```ruby
cask "voiceflow" do
  version "1.0.7"
  sha256 "abc123..."
  url "https://your-url/VoiceFlow-#{version}.dmg"
  name "VoiceFlow"
  desc "Hold-to-dictate voice typing app"
  homepage "https://github.com/you/VoiceFlow"

  app "VoiceFlow.app"
  # Notarized builds don't need postflight xattr or codesign calls.
end
```

---

## Troubleshooting

### `errSecInternalComponent` during codesign
- Unlock your login keychain: `security unlock-keychain ~/Library/Keychains/login.keychain-db`
- Make sure you're not signing over SSH (you need a GUI session for keychain access)

### Notarization fails with "missing hardened runtime"
- Check `project.yml` has `ENABLE_HARDENED_RUNTIME: YES`
- Regenerate project: `xcodegen generate`
- Rebuild

### Notarization fails with "The signature of the binary is invalid"
- Usually means a nested binary wasn't signed. The build script uses `--deep` to handle this, but custom frameworks may need manual signing first.

### `spctl --assess` fails after stapling
- Run with `--type open --context context:primary-signature` (already in the script)
- For unstapled DMGs, network access is required for Gatekeeper to verify

### Notarization is slow (>10 min)
- Apple's service is occasionally backed up. Retry later.
- Check status: `xcrun notarytool log <submission-id> --keychain-profile voiceflow-notarize`

---

## Maintenance

### Yearly renewal
When your Developer Program membership lapses, existing signatures remain valid (they were timestamped at signing time). But you can't sign *new* releases until you renew.

### Certificate expiry
Developer ID certs last 5 years. When yours expires:
1. Generate a new one in Xcode (same steps as above)
2. Update your `DEVELOPER_ID` env var with the new name

### Revocation
If your private key leaks, immediately revoke the cert at https://developer.apple.com/account/resources/certificates. Apple will stop trusting any binary signed with it going forward. Older timestamped binaries remain valid.

---

## Mental model 🧠

Think of it like a **three-layer trust chain**:

1. **Apple** trusts you because you paid $99 and verified your identity.
2. **Your certificate** lives in your Keychain, proving *you* are the signer.
3. **Your signature** on the app proves *this specific binary* was built by you, at this specific time, with these specific entitlements.

Notarization adds a fourth layer:
4. **Apple's scan** confirms the binary contains no known malware, and issues a "ticket" you staple onto the DMG.

Gatekeeper verifies all four layers before letting users open the app without warning. Skip any one layer and you're back to `xattr` workarounds.
