# Runbooks

Operational procedures for the POC. Each runbook states its purpose, prerequisites, steps, verification and a "last tested" date.

| Runbook | Purpose | Added in |
|---|---|---|
| [github-settings.md](github-settings.md) | Repository rulesets, security settings, apps | T00 |
| [ci-images.md](ci-images.md) | How images are built, gated, signed and verified | T12 |
| [deploy-and-rollback.md](deploy-and-rollback.md) | Deploy PR bot, digest verification, rollback | T13 |
| [secrets.md](secrets.md) | Generate, encrypt (SOPS + age), deliver and rotate secrets | T19 |
| [owner-prerequisites.md](owner-prerequisites.md) | Step-by-step unblocking of every owner prerequisite (P1–P15) and what each unlocks | — |
| [provisioning.md](provisioning.md) | Render cloud-init, `tofu apply`, SSH config, secrets, state, re-provisioning | T20 |

Planned (see `PLAN.md`): `portainer.md` (T21), `first-deploy.md` and `keycloak-realm-export.md` (T22), `backup-restore.md` and `restore-drill-log.md` (T23), `rollback.md`, `secrets-rotation.md`, `keycloak-upgrade.md`, `break-glass.md`, `upgrade-portainer.md` (T25).
