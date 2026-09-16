# syntax=docker/dockerfile:1.7
# Frontend image (ADR-0007 §2, ADR-0005, ADR-0020): pnpm frozen install, next build (standalone),
# runtime = standalone server + static assets only, non-root `node` user, read-only friendly.
# Build: docker build -t frontend:dev --build-arg GIT_SHA=$(git rev-parse HEAD) frontend/

ARG NODE_IMAGE=node:24.21.0-alpine@sha256:be80f76cf40ec8e42b9bec49f60a55e0660f30af58d3e5a25530785b30ea67e2

# --- deps: exact pnpm, frozen lockfile ------------------------------------------------------
FROM ${NODE_IMAGE} AS deps
# renovate: datasource=npm depName=pnpm
ARG PNPM_VERSION=12.4.2
ENV PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH \
    CI=true
RUN npm install -g "pnpm@${PNPM_VERSION}" && npm cache clean --force
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# --- build ------------------------------------------------------------------------------------
FROM deps AS build
ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production
COPY . .
RUN pnpm check:next-version && pnpm build

# --- runtime ----------------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="web-app-test frontend" \
      org.opencontainers.image.description="Next.js BFF frontend for the secure 2-VPS web app POC" \
      org.opencontainers.image.source="https://github.com/akshatauppinventure/web-app-test" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="akshatauppinventure"

# Nothing installs at runtime: drop npm, npx, yarn and corepack from the base image.
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /usr/local/bin/corepack /opt/yarn* \
    && mkdir -p /app/.next/cache && chown -R node:node /app

WORKDIR /app
COPY --from=build --chown=root:root /app/public ./public
COPY --from=build --chown=root:root /app/.next/standalone ./
COPY --from=build --chown=root:root /app/.next/static ./.next/static

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

USER 1000:1000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:3000/api/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

# .next/cache must be a tmpfs when the root filesystem is read-only.
CMD ["node", "server.js"]
