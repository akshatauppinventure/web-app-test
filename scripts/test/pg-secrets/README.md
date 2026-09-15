# Test-only Postgres credentials

These values are **not secrets**. They are used only by `compose.test.yaml`, which binds Postgres to `127.0.0.1:55432` on a developer machine or CI runner and is destroyed after the run. Real credentials are generated per environment (`scripts/dev/gen-dev-secrets.sh`, T09) or SOPS-encrypted (`infra/secrets/`, T19).
