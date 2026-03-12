# OpenClaw — Installation & gog setup

## Install Homebrew (macOS)
Run in macOS Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Follow the script instructions to add brew to your PATH
brew --version
```

## Install gog via Homebrew

```bash
brew tap steipete/tap
brew install steipete/tap/gogcli
gog --version
```

## Configure gog (OAuth flow)
1. Create OAuth client in Google Cloud Console:
   - Go to https://console.cloud.google.com/apis/credentials
   - Create Credentials → OAuth client ID → Desktop app
   - Download JSON (client_secret.json)
2. Copy JSON to server or local path:
   - Local: `~/Library/Application Support/gogcli/credentials.json`
   - Server: `/tmp/client_secret.json`
3. On server (or local where gog is installed):

```bash
gog auth credentials /tmp/client_secret.json
# then
gog auth add you@example.com --services gmail,calendar,drive,contacts,sheets,docs
```

If redirect uses localhost, create SSH tunnel from your machine to server:
```bash
ssh -N -L 39155:127.0.0.1:39155 -i ~/.ssh/hetzner_ed25519 root@89.167.116.249
# then open the URL provided by gog in your browser
```

## Testing

```bash
gog auth list
gog gmail search 'newer_than:7d' --max 1 --no-input --json
gog calendar events primary --from "$(date -I -d 'now -7 days')" --to "$(date -I)" --max 3 --json
```

## Security notes
- Revoke or rotate client secrets after setup if they were shared temporarily.
- Store GOG_KEYRING_PASSWORD securely (do not leave defaults). Use environment variable or secret manager.

