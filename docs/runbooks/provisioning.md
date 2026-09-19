# Provisioning both VPS (T20)

**Purpose:** create VPS-A "edge" and VPS-B "core" from `infra/tofu/<provider>` with the first-boot configuration from `infra/host`, reach both over key-only SSH, and record the host baseline. ADRs 0002, 0004, 0014, 0026. Adding a VPN back is item 1 of [`docs/production-hardening.md`](../production-hardening.md).

**Prerequisites:** P5 (age key, `infra/secrets/*.sops.yaml`), P6 (`~/.config/upcloud/token` **and the account out of trial mode**: the trial firewall is fixed and stateless, so `apt` hangs and cloud-init never finishes), `brew install opentofu sops age jq`, the laptop's SSH key in `~/.ssh/id_ed25519.pub`.

**Last tested:** 2026-09-17 with the pre-ADR-0026 design (UpCloud `us-nyc1`). The ADR-0026 design is rendered and planned but not yet applied.

## 0. Servers created before ADR-0026 (2026-09-17)

The two servers created on 2026-09-17 accept SSH only on a tunnel address that no longer exists in this repository. OpenTofu ignores `user_data` changes, so a plain `tofu apply` would only update their firewall rules. Destroy them first, then continue with step 1:

```bash
export UPCLOUD_TOKEN="$(cat ~/.config/upcloud/token)"
cd infra/tofu/upcloud && tofu destroy     # review: 2 servers, network, router, rulesets; billing stops
rm -P ../../../.tofu-rendered/*.bootstrap.key 2>/dev/null; rm -f ../../../.tofu-rendered/*   # old bootstrap keys and renders
```

Laptop leftovers from that design (`~/.config/wireguard/`) are unused and can be deleted.

## 1. Render cloud-init

```bash
umask 077; mkdir -p .tofu-rendered                     # gitignored
cp scripts/test/host-vars.example .tofu-rendered/edge.vars
cp scripts/test/host-vars.example .tofu-rendered/core.vars
# edit both: HOSTNAME (webapptest-edge / webapptest-core), ADMIN_SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)",
# PUBLIC_IF=auto, and ADMIN_SSH_CIDRS: your address as a.b.c.d/32 (curl -4 -s https://ifconfig.me) or keep 0.0.0.0/0
infra/host/scripts/render-cloud-init.sh edge .tofu-rendered/edge.vars .tofu-rendered/edge.yaml
infra/host/scripts/render-cloud-init.sh core .tofu-rendered/core.vars .tofu-rendered/core.yaml
```

The render script refuses malformed addresses or CIDRs and any placeholder left in the output. `PUBLIC_IF=auto` is resolved on the host from the default route before nftables starts. `EDGE_PRIVATE_IP`/`CORE_PRIVATE_IP` default to the module defaults (`10.0.0.11`/`10.0.0.2`).

## 2. Plan and apply

```bash
export UPCLOUD_TOKEN="$(cat ~/.config/upcloud/token)"
cd infra/tofu/upcloud && cp terraform.tfvars.example terraform.tfvars   # admin_ssh_public_key + cloud-init paths
# set admin_ssh_cidrs to the same list as ADMIN_SSH_CIDRS (default ["0.0.0.0/0"])
tofu init && tofu plan -out plan.bin
```

Review: exactly 2 servers (`webapptest-edge` 2xCPU-4GB, `webapptest-core` 4xCPU-8GB, Ubuntu 26.04, public IPv4 + private 10.0.0.11/.2 (x.1 is UpCloud's SDN gateway and refused for servers), firewall on, keys-only login, no password), 1 network + 1 router, 2 firewall rulesets (edge 13 rules, core 11 with one SSH CIDR). Then, and only then:

```bash
tofu apply plan.bin      # billing starts
tofu output              # public_ipv4 + private_ipv4
```

## 3. SSH config and first boot

Cloud-init takes 2–4 minutes (Docker install). Add both hosts to `~/.ssh/config` once; `make secrets-push` and the runbooks use these aliases:

```
Host webapptest-edge
  HostName <edge public IP>
  User admin
Host webapptest-core
  HostName <core public IP>
  User admin
```

```bash
ssh webapptest-edge 'cloud-init status --wait; cat /var/log/cloud-init-summary.log; sudo nft list chain inet filter input'
ssh webapptest-core 'cloud-init status --wait; cat /var/log/cloud-init-summary.log; ping -c1 10.0.0.11'
ssh webapptest-edge 'ping -c1 10.0.0.2'
```

If SSH does not answer, the boot report on the provider's web console (tty1, refreshed every 2 minutes until cloud-init is done) shows cloud-init status, failed units, addresses, nftables and sshd state.

## 4. Secrets

```bash
make secrets-push HOST=edge && make secrets-push HOST=core        # docs/runbooks/secrets.md
```

## 5. State, baseline, DNS

```bash
cd infra/tofu/upcloud && sops --encrypt terraform.tfstate > terraform.tfstate.sops && sops --encrypt terraform.tfvars > terraform.tfvars.sops   # commit both
```

Record `docs/verification/host-baseline.md` (T20 tests: SSH works with the key and is refused with a password, SSH from outside `ADMIN_SSH_CIDRS` times out when it is narrowed, `ping` between the private addresses, `apt update` + `docker pull hello-world`, `nmap -Pn -p-` on both public IPs, Lynis, docker-bench). Then P8: point `test-vinayak.duckdns.org` at the edge public IP (T22).

## Admin UIs (T21, T22)

Nothing but SSH is public for administration. Forward the ports through SSH:

```bash
ssh -N -L 9443:127.0.0.1:9443 webapptest-core     # Portainer: https://localhost:9443
ssh -N -L 8080:10.0.0.2:8080 webapptest-core      # Keycloak admin console: http://localhost:8080/auth/admin
```

## Rollback / teardown

`tofu destroy` in `infra/tofu/upcloud` removes both servers, the network, the router and the rulesets (billing stops). Decrypt the state first if it was only committed encrypted. Re-provisioning starts again at step 1.
