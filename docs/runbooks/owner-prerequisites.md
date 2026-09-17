# Runbook: owner prerequisites and how to unblock each one

**Purpose:** everything only the owner can do to unblock the remaining PLAN tasks, in the order that unblocks the most. Each item says what to click, what to run, where the value goes, how to verify, and which task it unblocks. Nothing here is committed in clear: values marked **secret** go into SOPS files or a password manager.
**Prerequisites:** a laptop with `gh`, `docker`, `make`, `jq`, `openssl`, `age`, `sops`, `wireguard-tools` (`brew install gh age sops jq wireguard-tools`).
**Last updated:** 2026-09-16 (T11 merged and green; T12 next; T13 needs P3 + P4; T20+ blocked on P5–P7).

## Checklist (do in this order)

| # | Item | Unblocks | Effort |
|---|---|---|---|
| P14 | `gh` token `workflow` scope — **done** | T11 CI, then T12, T13 | — |
| P13 | Install the Renovate GitHub App | T10 completion (dependency PRs) | 3 min |
| P12 | Decide: GitHub Pro (enforced ruleset) or process-only protection | ADR-0017 §1 | 5 min |
| P4 | Deploy GitHub App + repo secrets — **done** (`web-app-test-deploy[bot]` opens deploy PRs) | T13 | — |
| P3 | GHCR packages private — **done** (CI enforces it on every publish) | ADR-0017 §5, T13 | — |
| P2 | Google OAuth client "local" | Google sign-in on the local stack (T09) | 10 min |
| P5 | Generate the admin age key, encrypt the secrets files — **done** (5 owner values still `CHANGE_ME`: P9, P10, CrowdSec enrollment) | T19 completion, T20–T22 | — |
| P7 | WireGuard key pair on the laptop — **done** (public key in `peers.yaml`) | T20 | — |
| P6 | UpCloud account, payment method, API token — **done** (token in `~/.config/upcloud/token`, mode 600) | T18 plan, T20 apply (billing starts) | — |
| P8 | DuckDNS record → VPS-A public IP | T22 | 2 min (after T20) |
| P9 | Google OAuth client "poc" | T22 | 5 min |
| P10 | UpCloud Managed Object Storage bucket + key | T23 | 10 min |
| P11 | (Optional) external uptime monitor | T24 | 5 min |
| P15 | OVHcloud US account, Public Cloud project with vRack, OpenStack user `openrc` — only when the OVH POC starts | OVH repeat of T20 (`infra/tofu/ovh`) | 20 min |

---

## P14 · `workflow` scope for the `gh` token (blocks T11, T12, T13)

The token created by `gh auth login` has scopes `gist, read:org, repo`; GitHub refuses to accept pushes that create or change `.github/workflows/*` without the `workflow` scope.

1. In the Claude Code session (or any terminal), run:
   ```bash
   gh auth refresh -h github.com -s workflow
   ```
   A one-time code is printed; press Enter, paste it at https://github.com/login/device, approve. Make sure the **akshatauppinventure** account is the active one (`gh auth status` shows `Active account: true` for it).
2. Verify: `gh auth status` now lists `workflow` among the token scopes.
3. Then the T11 branch can be pushed and merged (ask Claude: "push and merge the T11 CI branch, then run the three negative PRs"). What happens next:
   - `task/T11-ci-workflow` is pushed, PR opened, the workflow runs on the PR itself; merge when green.
   - Three throwaway PRs prove the gates fail as intended (unlisted `ports:` entry, `next` downgrade, fake secret); they are closed without merging.
   - T12 (`build-publish.yml`) and T13 (deploy-PR bot) follow; T13 also needs P4.

## P13 · Renovate GitHub App (completes T10)

1. Open https://github.com/apps/renovate → **Configure** (or **Install**).
2. Select **Only select repositories** → `akshatauppinventure/web-app-test` → **Install**.
3. Within a few minutes Renovate opens an onboarding PR ("Configure Renovate"). It only confirms the existing `renovate.json`; merge it.
4. Verify: an issue titled *Dependency dashboard (Renovate)* appears and lists managers `dockerfile`, `docker-compose`, `github-actions`, `npm`, `pep621`, `regex`.
5. Leave Dependabot **security updates** off (alerts are already on); Renovate is the only bot opening PRs.

## P12 · Branch protection on a private Free-plan repository (ADR-0017 §1)

Rulesets are refused on this private repo: `403 Upgrade to GitHub Pro or make this repository public`. Choose one:

- **Option A (recommended, about $4/month):** https://github.com/settings/billing → upgrade to **GitHub Pro**. Then run the ruleset command in `docs/runbooks/github-settings.md` §1 (it creates `main-protection`: PR required, no force push, no deletion, linear history; required status checks are added after T11 is green). Verify with `gh api repos/akshatauppinventure/web-app-test/rulesets --jq '.[].name'`.
- **Option B (free):** accept process-only protection for the POC. Everything still goes through PRs by convention; `main` is technically pushable. Record the decision by editing the "Owner decision needed (P12)" paragraph in `docs/runbooks/github-settings.md`.

Secret scanning / push protection also need a paid plan (GitHub Secret Protection); `gitleaks` in CI is the compensating control either way.

## P3 · GHCR package visibility — **done 2026-09-16** (all six private; run 35065230791 green)

Why they were public: GitHub links a package pushed with `GITHUB_TOKEN` to the repository and the package *inherits the repository's access permissions*, but the *visibility* flag is set at creation and GitHub set it to public for packages first created from Actions in this personal namespace. The publish workflow now fails the run while any package answers anonymous requests, so a regression (or a new component) is caught on the first push.

T12's first publish (2026-09-16) created the six packages `ghcr.io/akshatauppinventure/{frontend,backend,keycloak,traefik,crowdsec,postgres}`. Checked anonymously: `https://ghcr.io/v2/akshatauppinventure/backend/tags/list` answers **200** with the tag list to a client without any token, so GitHub created them as **public** even though the repository is private. Container package visibility cannot be changed through the API; it takes six clicks in the UI. Nothing secret is in the images (they are built from the repo), but ADR-0017 §5 requires private packages and T13's pull credentials assume it.

1. https://github.com/akshatauppinventure?tab=packages → the six packages are listed now.
2. For **each** package: open it → **Package settings** (right side) → **Danger Zone → Change visibility** → **Private** → type the package name → confirm.
3. While there, under **Manage Actions access** confirm `web-app-test` is listed with role **Write** (it is added automatically when the workflow pushes) — the next publish must still be able to push.
4. Verify from any terminal (no token): every line must print `401` (or `403`), never `200`:
   ```bash
   for c in frontend backend keycloak traefik crowdsec postgres; do
     tok=$(curl -s "https://ghcr.io/token?scope=repository:akshatauppinventure/$c:pull" | jq -r .token)
     printf '%-9s ' $c; curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $tok" "https://ghcr.io/v2/akshatauppinventure/$c/tags/list"
   done
   ```
   The same check runs at the end of every `build-publish` run and fails the run while any package is public.
5. Optional cleanup (needs `delete:packages` on a token): the six digests from run 35063445754 were pushed before a failed step and are unsigned; they are never referenced and can be deleted from each package's **Versions** page.

## P4 · GitHub App for deploy PRs (blocks T13)

The deploy bot must open PRs with an **installation token** so required checks run (PRs created with `GITHUB_TOKEN` don't trigger workflows).

1. https://github.com/settings/apps/new
   - GitHub App name: `web-app-test-deploy` (must be globally unique; add a suffix if taken).
   - Homepage URL: `https://github.com/akshatauppinventure/web-app-test`.
   - Webhook: **untick Active**.
   - Repository permissions: **Contents: Read and write**, **Pull requests: Read and write**, **Metadata: Read-only** (auto). Nothing else.
   - Where can this app be installed: **Only on this account** → **Create GitHub App**.
2. On the app page note the **App ID** (a number).
3. **Private keys → Generate a private key** → a `.pem` downloads. Keep it in the password manager; it is the bot's identity.
4. **Install App** (left menu) → your account → **Only select repositories** → `web-app-test` → Install.
5. Store the two values as repository secrets (**secret**; never commit the pem):
   ```bash
   gh secret set DEPLOY_APP_ID --repo akshatauppinventure/web-app-test --body "<App ID>"
   gh secret set DEPLOY_APP_KEY --repo akshatauppinventure/web-app-test < ~/Downloads/web-app-test-deploy.*.private-key.pem
   ```
6. Verify: `gh secret list --repo akshatauppinventure/web-app-test` shows both names. Delete the downloaded `.pem` afterwards (it is in the password manager).

## P2 · Google OAuth client "local" (Google sign-in on `make dev-up`)

1. https://console.cloud.google.com → create/select a project (e.g. `web-app-test`).
2. **APIs & Services → OAuth consent screen** (now "Google Auth Platform → Branding/Audience"): User type **External**, app name `web-app-test (local)`, your email as support and developer contact. Under **Audience** keep **Testing** and add your Google account as a **test user**.
3. **Credentials → Create credentials → OAuth client ID**: Application type **Web application**, name `local`.
   - Authorized JavaScript origins: leave empty.
   - Authorized redirect URI: `http://localhost:8080/auth/realms/app/broker/google/endpoint`
   → **Create**. Copy the **Client ID** (public) and **Client secret** (**secret**).
4. In the repo (both files are gitignored):
   ```bash
   cd <repo>
   sed -i '' 's/^GOOGLE_CLIENT_ID=.*/GOOGLE_CLIENT_ID=<client id>.apps.googleusercontent.com/' .env
   printf '%s' '<client secret>' > .dev-secrets/app_google_client_secret
   make dev-reset && make dev-up
   ```
   (`dev-reset` is needed once: the client id is substituted into the realm at first import; a later secret change only needs `docker compose -f compose.dev.yaml restart keycloak`.)
5. Verify: open http://localhost:3000 → **Sign in with Google** → consent → `/hello` shows the visit message; a second visit increments the count. `make dev-smoke` still passes with the local user.

## P5 · Admin age key and the encrypted secrets files — **done 2026-09-16** (recipient in `.sops.yaml`, `infra/secrets/{edge,core}.sops.yaml` committed)

1. Generate the key (**secret**):
   ```bash
   mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
   grep 'public key' ~/.config/sops/age/keys.txt      # age1...
   ```
   Put the whole `keys.txt` content in the password manager **and** keep an offline copy (print it). Without it every secret and every backup is unrecoverable.
2. Put the public key into `.sops.yaml`: replace the three `age1REPLACE_WITH_OWNER_PUBLIC_KEY_P5` occurrences with your `age1...` value. Commit (`git checkout -b chore/sops-recipient`, PR, merge).
3. Generate and encrypt the secrets (plaintext only in a private temp dir):
   ```bash
   make secrets-gen                 # prints the temp dir
   $EDITOR <tmp>/core.yaml          # fill CHANGE_ME: app_google_client_secret (P9), restic_* (P10) — or leave CHANGE_ME until those exist
   $EDITOR <tmp>/edge.yaml          # crowdsec_enroll_key: enrollment key from https://app.crowdsec.net (Security Engines → Add) or "unset"
   make secrets-encrypt SRC=<tmp>   # writes infra/secrets/{edge,core}.sops.yaml, shreds the plaintext
   git add infra/secrets/*.sops.yaml && git commit -m "secrets: initial encrypted values" && git push
   ```
   Copy `restic_password` and `portainer_admin_password` from the files into the password manager (`sops -d --extract '["restic_password"]' infra/secrets/core.sops.yaml`).
4. Verify: `sops -d infra/secrets/core.sops.yaml | head -3` decrypts on your laptop (on macOS sops looks in `~/Library/Application Support/sops/age/keys.txt`, so either move the file there or `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt` in your shell profile); `make secrets-check` passes; `git grep -n 'ENC\[AES256_GCM' infra/secrets | head -1` shows encrypted values.
5. Values you fill later (P9, P10, CrowdSec enrollment): `sops infra/secrets/core.sops.yaml` opens the file decrypted in `$EDITOR` and re-encrypts on save.

## P7 · WireGuard key pair on the laptop — **done 2026-09-16** (`owner-laptop` in `infra/host/wireguard/peers.yaml`)

1. `brew install wireguard-tools` (CLI) and optionally the **WireGuard** app from the Mac App Store (GUI).
2. Generate keys (**private key is secret, stays on the laptop**):
   ```bash
   umask 077 && mkdir -p ~/.config/wireguard && cd ~/.config/wireguard
   wg genkey | tee laptop.key | wg pubkey > laptop.pub && cat laptop.pub
   ```
3. Put the **public** key into `infra/host/wireguard/peers.yaml` under `admins: - name: owner-laptop` (replace `REPLACE_WITH_ADMIN_PUBLIC_KEY`). Commit via PR.
4. The laptop config is created in T20 once the servers' public keys exist (template: two peers, `AllowedIPs = 10.10.0.1/32` and `10.10.0.2/32`, `PersistentKeepalive = 25`, plus the pre-shared keys from `infra/secrets`).
5. Verify: `wg pubkey < laptop.key` prints the same key as `laptop.pub`.

## P6 · UpCloud account and API token — **done 2026-09-17**, plus the trial exit (deposit) needed by T20

**Owner decision 2026-09-17: stay in trial mode for the POC.** Consequences: WireGuard runs on UDP 33434 (the only UDP port the fixed firewall passes both ways), the provider firewall layer is the fixed trial rule set (`manage_provider_firewall = false`), and the trial ends after 30 days unless a deposit is made (resources are then removed). To leave trial mode later: make the deposit, set `manage_provider_firewall = true`, `tofu apply` (adds the rulesets; the port can stay 33434 or move back to 51820 with a re-provision).

**Background.** Until a one-time deposit of at least $10 is made (Hub → Billing → Add funds, card verified with a $0/$1 authorization), the account is a *trial*: every server gets a fixed provider firewall that cannot be edited (`tofu apply` fails with `TRIAL_FIREWALL`) and that drops inbound UDP 51820, so the WireGuard tunnel from the laptop can never connect. Servers can be created in trial mode (2 cores / 4 GB total limit is not enforced on this account), but nothing can be administered. Make the deposit, then re-run `tofu apply` in `infra/tofu/upcloud` to create the rulesets.

1. https://signup.upcloud.com → create the account, verify email, add a **payment method** (Hub → Billing) **and make the minimum $10 deposit** — that deposit is what ends the trial mode (fixed firewall, no UDP 51820 inbound). Enable **two-factor authentication** on the account (Hub → Account → Security).
2. Create an API credential with the least access the module needs (servers, networks, storages):
   - Hub → **Account → API tokens** (or **People → API tokens**, naming varies) → **Create token**, name `web-app-test-tofu`, expiry ≤ 90 days. If the dialog offers permission scopes, allow only Servers, Networks, Storages and IP addresses. If tokens are not offered, create a **sub-account** (Hub → People → Add) with **API access** enabled, restricted to your laptop's public IP, and use its username/password instead.
   - Copy the token (**secret**) to the password manager.
3. Store it in a private file outside the repository (never in the repo, never pasted into chat or shell history; copy the token to the clipboard first):
   ```bash
   mkdir -p ~/.config/upcloud && chmod 700 ~/.config/upcloud
   pbpaste > ~/.config/upcloud/token && chmod 600 ~/.config/upcloud/token
   ```
   Load it per shell with `export UPCLOUD_TOKEN="$(cat ~/.config/upcloud/token)"`; the provisioning steps read the file the same way. A token that was ever displayed or pasted anywhere is revoked in the Hub (Account → API Tokens → Delete) and re-created.
4. Verify without creating anything:
   ```bash
   curl -s -H "Authorization: Bearer $UPCLOUD_TOKEN" https://api.upcloud.com/1.3/account | jq .account.username
   curl -s -H "Authorization: Bearer $UPCLOUD_TOKEN" https://api.upcloud.com/1.3/zone | jq -r '.zones.zone[] | select(.id=="us-nyc1") .description'
   ```
5. Then T20 can run `tofu plan` (steps in `infra/tofu/upcloud/README.md`); review that the plan shows exactly 2 servers, 1 network, 1 router, 2 firewall rulesets before `tofu apply`.

## P8 · DuckDNS record (after T20 gives VPS-A's public IP)

1. Log in at https://www.duckdns.org (via the identity provider you used; keep **MFA enabled on that Google/GitHub account**, DuckDNS itself has no separate MFA).
2. In the **domains** section find `test-vinayak` → set **current ip** to the value of `tofu output public_ipv4` for `edge` → **update ip**.
3. Verify: `dig +short test-vinayak.duckdns.org` returns that IP (propagation is usually under a minute). No AAAA record is created (IPv6 stays off, ADR-0022).
4. Optional API form (from the laptop, never from a server): `curl "https://www.duckdns.org/update?domains=test-vinayak&token=<DuckDNS token>&ip=<VPS-A IP>&verbose=true"` → `OK` `UPDATED`.

## P9 · Google OAuth client "poc" (T22)

1. Same Google Cloud project as P2 → **Credentials → Create credentials → OAuth client ID** → Web application, name `poc`.
   - Authorized redirect URI: `https://test-vinayak.duckdns.org/auth/realms/app/broker/google/endpoint`
2. **Client ID** (public) → the `core` stack's environment variable `GOOGLE_CLIENT_ID` in Portainer (T21 runbook) — not a secret.
3. **Client secret** (**secret**) → `sops infra/secrets/core.sops.yaml` → `app_google_client_secret`. Commit, then `make secrets-push HOST=core` and restart Keycloak (Portainer → core stack → keycloak → restart). Keycloak reads it from the file vault on use, so no re-import is needed.
4. Before leaving **Testing** status: add the test users you need under Audience; **Publish** only when you want anyone with a Google account to sign in.
5. Verify (T22): https://test-vinayak.duckdns.org → Sign in with Google → `/hello`.

## P10 · UpCloud Managed Object Storage bucket for backups (T23)

1. Hub → **Object Storage → Create** → region **US-1 (Chicago)** (different site from us-nyc1 by design), name `web-app-test-backups`. Note the endpoint (looks like `https://<id>.upcloudobjects.com`).
2. Inside the service: **Buckets → Create** `restic`. If offered, enable **versioning** and note whether object lock is available (record the answer in `docs/runbooks/backup-restore.md`, T23).
3. **Users / Access keys → Create** a user `restic` with access **only to this bucket** (S3 policy limited to `restic`), generate an access key + secret key (**secret**).
4. Put the values into `sops infra/secrets/core.sops.yaml`:
   - `restic_repository`: `s3:https://<id>.upcloudobjects.com/restic`
   - `restic_s3_access_key`, `restic_s3_secret_key`: from step 3
   - `restic_password`: already generated by P5 (keep the password-manager copy current)
5. `make secrets-push HOST=core`, then on VPS-B (T23): `sudo systemctl start pg-backup.service && sudo journalctl -u pg-backup -n 5`.
6. Verify: `restic snapshots` (with the same env as `infra/host/scripts/pg-backup.sh`) lists the snapshot; `infra/host/scripts/restore-drill.sh` prints a log row with matching row counts.

## P11 · External uptime monitor (optional, T24)

1. Create a free account at an uptime service (for example UptimeRobot or Better Stack free tier).
2. Add an **HTTPS** monitor for `https://test-vinayak.duckdns.org/` with a 5-minute interval, expecting HTTP 200 and the text `web-app-test`.
3. Point its alert channel at your email or the same ntfy topic used by the host health check (`NOTIFY_WEBHOOK_URL` in `/etc/app/host.env`, set in T20/T21).
4. Verify: pause the monitor and resume it, or stop the frontend briefly during T24 and confirm the alert arrives.

## P15 · OVHcloud US account, Public Cloud project and OpenStack user (OVH POC, after UpCloud)

Only needed when you repeat the POC on OVHcloud (ADR-0025). Vint Hill, VA is served by **OVHcloud US**, a separate company from OVHcloud EU/CA: the account, control panel and billing are at `us.ovhcloud.com`.

1. https://us.ovhcloud.com → create the account, verify email, add a payment method, enable two-factor authentication (Account → Security).
2. Control panel → **Public Cloud** → **Create a project** (name `web-app-test`). New projects come with a **vRack**; check Public Cloud → Network → **Private network** shows no "activate vRack" prompt (if it does, activate it: free).
3. Create the OpenStack user: Public Cloud → Project Management → **Users & Roles** → **Add user** (description `web-app-test-tofu`, role **Compute Operator** + **Network Operator**). Save the generated password in the password manager (**secret**). Then **Download OpenStack's RC file** for region `US-EAST-VA-1` (`openrc.sh`).
   - Alternative with no user password: Users & Roles → the user → **Generate an application credential**, and export `OS_AUTH_TYPE=v3applicationcredential`, `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET` instead of username/password.
4. Keep `openrc.sh` outside the repository (e.g. `~/.config/openstack/web-app-test-us-east.sh`) and load it only in the shell that runs OpenTofu:
   ```bash
   source ~/.config/openstack/web-app-test-us-east.sh     # prompts for the password; OS_AUTH_URL=https://auth.cloud.ovh.us/v3
   ```
5. Verify without creating anything (`brew install openstackclient` or `uvx --from python-openstackclient openstack`):
   ```bash
   openstack region list
   openstack image list --public | grep -i ubuntu          # 26.04 present? else set template_name in terraform.tfvars
   openstack flavor list | grep -E 'd2-4|d2-8|b3-8|b3-16'   # d2-4/d2-8 available in US-EAST-VA-1?
   openstack network list                                    # Ext-Net present
   ```
6. Then the OVH repeat of T20 runs `tofu plan` in `infra/tofu/ovh` (steps in its README); review that the plan shows exactly 2 instances, 1 keypair, 1 network, 1 subnet, 2 security groups and 10 rules before `tofu apply`.

## P1 · Repository (done)

`akshatauppinventure/web-app-test` exists, is private, and holds 19 commits on `main` (17 merged PRs). Nothing to do.

---

## After the prerequisites: what runs next

| When | Task | Who | Trigger |
|---|---|---|---|
| P14 done | T11 CI (push branch, PR, negative PRs) | Claude | "push and merge T11" |
| P14 | T12 build-publish (six images to GHCR, signed) | Claude | after T11 |
| T12 + P3 + P4 | T13 deploy-PR bot + digest verification | Claude | after T12 |
| P5 + P6 + P7 | T20 provision both VPS (`tofu apply`, WireGuard, baselines) — **billing starts** | owner runs `tofu apply`; Claude prepares vars/plan | after T13 preferably (real digests in the stacks) |
| T20 + T13 | T21 Portainer bootstrap and Git stacks | owner over WireGuard; Claude drafts the runbook | after T20 |
| T21 + P8 + P9 | T22 DNS, TLS, first end-to-end deployment | both | after T21 |
| T22 + P10 | T23 backups live, first restore drill | both | after T22 |
| T23 (+ P11) | T24 security verification and report; T25 close-out | Claude, owner review | after T23 |
| after the UpCloud POC + P15 | OVH repeat of T20–T23 with `infra/tofu/ovh` (ADR-0025) | owner runs `tofu apply`; Claude prepares vars/plan | "start OVH POC" |
