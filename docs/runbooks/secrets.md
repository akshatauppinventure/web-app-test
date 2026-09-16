# Runbook: secrets (ADR-0016)

**Purpose:** create, encrypt, deliver and rotate deployment secrets with SOPS + age. Servers never hold age keys; values never enter git in clear, Portainer, or CI.
**Prerequisites:** `sops`, `age`, `jq`, `openssl`, `wireguard-tools` (`brew install sops age jq wireguard-tools`), WireGuard access to the hosts (T20).
**Last tested:** 2026-09-15 (round trip with a throwaway key, `make secrets-check`).

## 1. One-time: admin age key (owner prerequisite P5)

```bash
age-keygen -o ~/.config/sops/age/keys.txt      # prints "Public key: age1..."
chmod 600 ~/.config/sops/age/keys.txt
```
Store the private key in the password manager **and** keep an offline copy (printed, in a safe): without it every secret and every backup is unrecoverable. Put the public key into `.sops.yaml` (replace `age1REPLACE_WITH_OWNER_PUBLIC_KEY_P5`, three places) and commit.

## 2. First generation (once per host)

```bash
make secrets-gen            # writes plaintext to a private temp dir and prints the path
$EDITOR <tmp>/core.yaml     # replace every CHANGE_ME (Google poc client secret P9, restic S3 keys/bucket P10)
$EDITOR <tmp>/edge.yaml     # CrowdSec enrollment key (console) or leave "unset"
make secrets-encrypt SRC=<tmp>   # sops --encrypt -> infra/secrets/{edge,core}.sops.yaml, then shreds the plaintext
git add infra/secrets/*.sops.yaml && git commit -m "secrets: initial encrypted values"
```
`gen-secrets.sh` keeps the values that both hosts must share identical (`web_bff_client_secret`, `portainer_agent_secret`, the A↔B WireGuard PSK). Copy `restic_password` and `portainer_admin_password` into the password manager.

## 3. Delivery

```bash
make secrets-push HOST=core       # sops -d -> ssh admin@10.10.0.2 -> /etc/app/secrets/<name> (0400, container UID)
make secrets-push HOST=edge       # WireGuard PSKs go to /etc/wireguard/psk-<peer> (0600 root)
make secrets-push HOST=core DRY=1 # prints destinations only
```
Then restart what consumes the changed secret (`docker compose ... up -d` from Portainer, or `wg syncconf` for PSKs). `scripts/secrets/audit-hosts.sh` (T21) verifies owners and modes on the hosts.

## 4. Editing and rotation

- Edit in place: `sops infra/secrets/core.sops.yaml` (decrypts in `$EDITOR`, re-encrypts on save). Never `sops -d > file` inside the repo.
- Rotation cadence is in `infra/secrets/SCHEMA.md` (6 months for high-value secrets; immediately on suspected compromise). Procedure: edit with `sops` → commit → `make secrets-push HOST=…` → restart the consumer → for database passwords also `ALTER ROLE … PASSWORD` (the initdb scripts run only once) → for `web_bff_client_secret` update the client in the Keycloak admin console **and** push to both hosts.
- Adding an admin: append their age public key to each `.sops.yaml` rule, run `sops updateKeys infra/secrets/*.sops.yaml`, commit.
- Adding a secret: add a row to `SCHEMA.md`, a line to `gen-secrets.sh`, a destination rule in `secrets-push.sh`, and the Compose `secrets:` entry; `make secrets-check` enforces consistency.

## 5. Recovery

Lost age key with the offline copy intact → import it (`keys.txt`) and continue. Lost entirely → generate a new key, re-generate all secrets (`make secrets-gen`), rotate everything on the hosts, re-initialise the restic repository (old backups are unreadable) — which is why the offline copy exists.
