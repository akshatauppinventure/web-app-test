# Provisioning both VPS (T20)

**Purpose:** create VPS-A "edge" and VPS-B "core" from `infra/tofu/<provider>` with the first-boot configuration from `infra/host`, establish the WireGuard mesh (A ↔ B over the provider's private network, laptop ↔ both over the public IPs), and record the host baseline. ADRs 0002, 0004, 0014, 0015.

**Prerequisites:** P5 (age key, `infra/secrets/*.sops.yaml`), P6 (`~/.config/upcloud/token` **and the account out of trial mode**: the trial firewall is fixed and drops UDP 51820, so `tofu apply` fails on the rulesets and the tunnel never connects), P7 (`~/.config/wireguard/laptop.key`), `brew install wireguard-tools opentofu sops age jq`, the laptop's SSH key in `~/.ssh/id_ed25519.pub`.

**Last tested:** 2026-09-17 (UpCloud `us-nyc1`, trial account).

**Trial account (UpCloud):** set `WG_PORT=33434` in both vars files, `wireguard_port = 33434` and `manage_provider_firewall = false` in `terraform.tfvars`, and use `port: 33434` endpoints in `peers.yaml`. The fixed trial firewall passes UDP only on 33434 both ways and refuses rule changes (`TRIAL_FIREWALL`). Everything else below is unchanged.

## 1. Render cloud-init with bootstrap WireGuard keys

Cloud-init must bring `wg0` up with *valid* peers at first boot (sshd listens on the WireGuard address only), so the laptop generates a throw-away key pair per host; they are rotated on the hosts in step 5.

```bash
umask 077; mkdir -p .tofu-rendered                     # gitignored
for r in edge core; do wg genkey > .tofu-rendered/$r.bootstrap.key; wg pubkey < .tofu-rendered/$r.bootstrap.key > .tofu-rendered/$r.bootstrap.pub; done
# one vars file per host (see scripts/test/host-vars.example): HOSTNAME, ADMIN_USER=admin, ADMIN_SSH_PUBKEY,
# PUBLIC_HOST, PUBLIC_IF=auto, WG_PRIVATE_KEY=<that host's bootstrap key>, ADMIN_PUBLIC_KEY=<laptop.pub>,
# CORE_PUBLIC_KEY (edge) / EDGE_PUBLIC_KEY (core) = the other host's bootstrap public key
infra/host/scripts/render-cloud-init.sh edge .tofu-rendered/edge.vars .tofu-rendered/edge.yaml
infra/host/scripts/render-cloud-init.sh core .tofu-rendered/core.vars .tofu-rendered/core.yaml
```

The render script refuses placeholders or malformed keys. `PUBLIC_IF=auto` is resolved on the host from the default route before nftables starts.

## 2. Plan and apply

```bash
export UPCLOUD_TOKEN="$(cat ~/.config/upcloud/token)"
cd infra/tofu/upcloud && cp terraform.tfvars.example terraform.tfvars   # admin_ssh_public_key + cloud-init paths
tofu init && tofu plan -out plan.bin
```

Review: exactly 2 servers (`webapptest-edge` 2xCPU-4GB, `webapptest-core` 4xCPU-8GB, Ubuntu 26.04, public IPv4 + private 10.0.0.11/.2 (x.1 is UpCloud's SDN gateway and refused for servers), firewall on, keys-only login, no password), 1 network + 1 router, 2 firewall rulesets (edge 13 rules, core 11; none on a trial account). Then, and only then:

```bash
tofu apply plan.bin      # billing starts
tofu output              # public_ipv4 + private_ipv4
```

## 3. Wait for first boot

Cloud-init takes 2–4 minutes (Docker install). Check from the laptop that UDP 51820 answers nothing (WireGuard is silent) and that nothing else is open:

```bash
nmap -Pn -p 22,80,443 <edge public IP>     # 80/443 closed until Traefik runs (T21/T22), 22 filtered (trial firewall passes 22 but nftables drops it)
nmap -Pn -p 22,80,443 <core public IP>     # all filtered
```

## 4. Laptop tunnel (bootstrap keys)

```bash
cp infra/host/wireguard/peers.yaml .tofu-rendered/peers-bootstrap.yaml
# put the bootstrap public keys and "<public IP>:51820" endpoints into the servers: section of that copy, then
scripts/host/render-laptop-wg.sh .tofu-rendered/peers-bootstrap.yaml ~/.config/wireguard/laptop.key ~/.config/wireguard/webapptest.conf
sudo wg-quick up ~/.config/wireguard/webapptest.conf
sudo wg show                                      # handshakes with both peers within ~30 s
ssh admin@10.10.0.1 'sudo wg show; cat /var/log/cloud-init-summary.log'
ssh admin@10.10.0.2 'sudo wg show; cat /var/log/cloud-init-summary.log'
```

`wg-quick` on macOS creates a `utunN` interface; note its name from `wg show` for the next step.

## 5. Rotate the host keys and rewire the peers

```bash
scripts/host/finalize-wireguard.sh \
  --edge-bootstrap-pub "$(cat .tofu-rendered/edge.bootstrap.pub)" --core-bootstrap-pub "$(cat .tofu-rendered/core.bootstrap.pub)" \
  --laptop-conf ~/.config/wireguard/webapptest.conf --laptop-iface utunN --laptop-pub "$(cat ~/.config/wireguard/laptop.pub)" \
  --edge-endpoint <edge public IP>:51820 --core-endpoint <core public IP>:51820 \
  --peers-out .tofu-rendered/peers-snippet.yaml
```

Each host generates its permanent key locally (`wg-rotate-key.sh`); the laptop and the other host are updated live and in `wg0.conf`; `psk-map` is written with the new keys. Verify `ssh admin@10.10.0.1 sudo wg show` and the same on core show handshakes with *both* peers, then:

```bash
rm -P .tofu-rendered/*.bootstrap.key .tofu-rendered/*.vars .tofu-rendered/*.yaml   # bootstrap keys are dead
```

Copy `.tofu-rendered/peers-snippet.yaml` into `infra/host/wireguard/peers.yaml` (servers section) and open a PR.

## 6. Secrets and pre-shared keys

```bash
make secrets-push HOST=edge && make secrets-push HOST=core        # over the tunnel (docs/runbooks/secrets.md)
ssh admin@10.10.0.1 'sudo systemctl restart wg-quick@wg0'; ssh admin@10.10.0.2 'sudo systemctl restart wg-quick@wg0'
# laptop: add the PSKs
sops -d --extract '["wireguard_psk_owner-laptop"]' infra/secrets/edge.sops.yaml > .tofu-rendered/psk-edge
sops -d --extract '["wireguard_psk_owner-laptop"]' infra/secrets/core.sops.yaml > .tofu-rendered/psk-core
scripts/host/render-laptop-wg.sh infra/host/wireguard/peers.yaml ~/.config/wireguard/laptop.key ~/.config/wireguard/webapptest.conf --psk-edge .tofu-rendered/psk-edge --psk-core .tofu-rendered/psk-core
sudo wg-quick down ~/.config/wireguard/webapptest.conf && sudo wg-quick up ~/.config/wireguard/webapptest.conf && rm -P .tofu-rendered/psk-*
```

## 7. State, baseline, DNS

```bash
cd infra/tofu/upcloud && sops --encrypt terraform.tfstate > terraform.tfstate.sops && sops --encrypt terraform.tfvars > terraform.tfvars.sops   # commit both
```

Record `docs/verification/host-baseline.md` (T20 tests: SSH only over WireGuard, public SSH refused, `wg show` handshakes, `apt update` + `docker pull hello-world`, `nmap -Pn -p-` on both public IPs, Lynis, docker-bench). Then P8: point `test-vinayak.duckdns.org` at the edge public IP (T22).

## Rollback / teardown

`tofu destroy` in `infra/tofu/upcloud` removes both servers, the network, the router and the rulesets (billing stops). Decrypt the state first if it was only committed encrypted. Re-provisioning starts again at step 1 with fresh bootstrap keys.
