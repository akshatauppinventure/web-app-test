# CrowdSec (ADR-0013)

Security engine on VPS-A: parses Traefik's access log and the host sshd log, runs the AppSec (WAF)
listener for the Traefik bouncer plugin, and serves decisions to the plugin over the `edge` network.

| Path | Purpose |
|---|---|
| `Dockerfile` | `crowdsecurity/crowdsec:v1.8.1` (digest-pinned) with every file below copied into `/staging/etc/crowdsec/…`, which the upstream entrypoint rsyncs into `/etc/crowdsec` at start — no bind mounts needed (Portainer CE cannot mount repo files) |
| `collections.txt` | The six hub collections (also the `COLLECTIONS` env in compose) |
| `acquis.d/traefik.yaml` | Traefik JSON access log (read-only volume from the traefik container) |
| `acquis.d/sshd.yaml` | Host `/var/log/host/auth.log` (bind-mounted by the edge stack, T16/T17) |
| `acquis.d/appsec.yaml` | AppSec listener `0.0.0.0:7422` (edge network only) using `poc/appsec-detect` |
| `appsec/poc-appsec-detect.yaml` | **Phase 1:** all vpatch + generic rules in-band with `default_remediation: allow` → matches are counted/logged, nothing is blocked. **Phase 2 (T25):** `default_remediation: ban` |
| `config/profiles.yaml` | 4 h bans, doubling per repeat offence |
| `parsers/allowlist.yaml` | Parser whitelist for `10.10.0.0/24` (WireGuard admin peers + core host) so no decision can ever target them |
| `scripts/bootstrap-bouncer.sh` | Generates the shared bouncer API key secret file |

## How the bouncer is wired

One secret value, two names: CrowdSec's image auto-registers a bouncer for every
`/run/secrets/bouncer_key_<name>` file (here `bouncer_key_traefik`), and the Traefik plugin reads the
same value from `/run/secrets/crowdsec_bouncer_key` (`crowdsecLapiKeyFile`). No runtime `cscli bouncers add` is needed.
The plugin runs in **stream** mode (decisions pulled every 60 s) and is **fail-open**
(`updateMaxFailure: -1`, AppSec failures/unreachable do not block) for the POC.

Configuration changes are image changes (rebuild; the entrypoint re-syncs into the `crowdsec-config` volume on start). Keep `/etc/crowdsec` and `/var/lib/crowdsec/data` as named volumes.

## Console enrollment (owner, T22)

Enrolling shares attacking IPs and scenario names, and returns community blocklists (ADR-0013 §5).
Create an enrollment key at https://app.crowdsec.net and pass it as the `ENROLL_KEY` **secret** (never in git);
the compose file for the edge stack reads it from `/run/secrets/crowdsec_enroll_key` via `ENROLL_KEY_FILE` (T16). Tests run with `DISABLE_ONLINE_API=true`.

## Testing

```bash
make traefik-test     # starts traefik + crowdsec + stubs and runs the Traefik route checks
make crowdsec-test    # bouncer registered, collections, AppSec config, ban -> 403, detect-only, fail-open
docker compose -f compose.traefik-test.yaml down -v
```
