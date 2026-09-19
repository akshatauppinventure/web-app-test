# ADR-0004: Host OS: Ubuntu Server 26.04 LTS

- **Status:** Accepted (2026-09-15); WireGuard references superseded by [ADR-0026](0026-remove-wireguard-public-ssh-private-network.md)
- **Date:** 2026-09-14
- **Deciders:** Project owner
- **Related:** ADR-0005, ADR-0014, ADR-0020

## Context

Both VPS need a free, widely adopted, long-term-supported Linux distribution that:
- has first-class Docker Engine support,
- ships a recent kernel with in-kernel WireGuard, nftables and AppArmor,
- is available as an image at UpCloud (and ideally at OVHcloud, for portability).

Status as of 2026-09-14:
- **Ubuntu 26.04 LTS** ("Resolute Raccoon") was released on 2026-04-23. UpCloud offers the template. OVH said in May 2026 that VPS images were "coming in weeks".
- **Ubuntu 24.04 LTS** is mature and available everywhere.
- **Debian 13 (trixie)** is stable. Our container base images are also Debian trixie-based.

## Decision

We will run **Ubuntu Server 26.04 LTS (minimal/cloud image)** on both VPS.

**Fallback:** Ubuntu Server 24.04 LTS if, at provisioning time, Docker's official apt repository doesn't yet publish packages for 26.04, or the target provider lacks the image.

**Baseline host configuration** (applied by cloud-init and checked in under `infra/host/`):
- **Packages:** install Docker Engine from **Docker's official apt repository** (not the distro's `docker.io` package), plus `wireguard-tools`, `nftables`, `unattended-upgrades`, `auditd`, `apparmor` and `restic` (VPS-B).
- **Automatic updates:** `unattended-upgrades` applies security updates daily, with an automatic reboot window at 04:00 America/New_York when a reboot is required. Docker's `live-restore` keeps containers running across daemon restarts.
- **Accounts and SSH:**
  - One non-root admin user with sudo, SSH keys only.
  - `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`.
  - `AllowUsers <admin>`.
  - `ListenAddress` set to the WireGuard IP only (ADR-0015).
- **Other settings:**
  - Time sync: `systemd-timesyncd`.
  - Timezone: UTC.
  - Unused services removed or disabled.
  - Kernel/sysctl hardening: `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `net.ipv4.conf.all.rp_filter=1`, `net.ipv4.conf.all.accept_redirects=0`, `net.ipv4.conf.all.send_redirects=0`, `net.ipv4.tcp_syncookies=1`.
- **Audit baselines:** run **Lynis** and **docker-bench-security** after provisioning and record the scores.

## Alternatives considered

| Option | Why not chosen |
|---|---|
| Ubuntu 24.04 LTS | Fully viable; kept as the fallback. 26.04 is the newest LTS, with support until 2031 and a newer kernel. |
| Debian 13 | Excellent and FOSS-pure, but Ubuntu has broader provider images, clearer security-update automation and more hardening guides |
| AlmaLinux / Rocky Linux 10 | Viable, but Docker on RHEL-family systems needs more firewalld/SELinux work; less common for Docker VPS guides |
| Container-optimized OS (Flatcar, Talos) | Great for Kubernetes fleets; overkill and poorly suited to a Compose + Portainer POC |

## Consequences

**Positive**
- The longest remaining support window, a modern kernel, and broad documentation and community support.

**Negative / risks**
- The first months of an LTS release can have rough edges. The fallback (24.04) is documented.
- Automatic reboots cause brief downtime (acceptable for the POC).

**Follow-ups**
- Production: consider a CIS Level 1 benchmark profile (e.g. Ubuntu Security Guide) and live kernel patching.

## References

- https://documentation.ubuntu.com/release-notes/26.04/
- https://upcloud.com/global/resources/tutorials/install-code-server-ubuntu/
- https://community.ovhcloud.com/t/ubuntu-26-04-lts-availability-for-ovhcloud-vps-installation-image/53090
