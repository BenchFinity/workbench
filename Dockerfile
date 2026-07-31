# glibc Node toolchain (Chainguard node:latest-dev: npm + shell, glibc, nonroot
# uid 65532). Matches ADR 0001; replaces node:22-alpine (musl). Provides Node >=22
# (currently 26.x) per package.json engines. Digest-pinned; refresh via Dependabot.
FROM cgr.dev/chainguard/node:latest-dev@sha256:5f539ca9ce7ed8b858059b3316640232bcb1ae7d3513ae67bb95527533bf1fba AS deps
# /app is the image's default WORKDIR and is owned/writable by the nonroot user.
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

FROM cgr.dev/chainguard/node:latest-dev@sha256:5f539ca9ce7ed8b858059b3316640232bcb1ae7d3513ae67bb95527533bf1fba AS builder
WORKDIR /app

# --chown so the nonroot build user can write into node_modules (tsc emits
# .tmp/*.tsbuildinfo there); cross-stage COPY otherwise lands read-only for it.
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node . .

RUN npm run build

# Distroless Chainguard nginx: nonroot (uid 65532), no shell, no package
# manager, daily-rebuilt with near-zero CVEs. See docs/adr/0001-distroless-base-images.md.
# Digest-pinned for reproducibility; refresh via Dependabot/Renovate or manually
# (docker buildx imagetools inspect cgr.dev/chainguard/nginx:latest).
FROM cgr.dev/chainguard/nginx:latest@sha256:e4ff957080737c90a9ecfeaa40e3d19ea9d687e9cacda2f2a031c75ffcdd72b7

# Chainguard nginx mirrors the stock layout: nginx.conf includes
# /etc/nginx/conf.d/*.conf, listens on 8080, and serves /usr/share/nginx/html.
# Overwrite the base's default site (nginx.default.conf, also :8080) so only our
# SPA server block is active and there is no duplicate default_server.
COPY docker/nginx.conf /etc/nginx/conf.d/nginx.default.conf
COPY docker/security-headers.inc /etc/nginx/conf.d/security-headers.inc
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

# No HEALTHCHECK: distroless has no shell/wget. Container health is handled by
# orchestrator probes (Helm uses httpGet; compose has no healthcheck).
