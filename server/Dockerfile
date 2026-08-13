# Build context must be the REPOSITORY ROOT (not server/), because this
# Dockerfile copies the sibling `packages/campaign_contracts` path dependency.
# Build from the repo root with:
#   docker build -f server/Dockerfile -t campaign_service .
# dart:<major.minor> IS the stable channel for that series on Docker Hub —
# there is no dart:3.12-stable tag (verified empirically 2026-08-11: the pull
# 404s; channel names only exist bare, e.g. dart:stable/dart:beta).
FROM dart:3.12 AS build
WORKDIR /app
COPY packages/campaign_contracts /packages/campaign_contracts
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN dart pub get --offline && dart compile exe bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
