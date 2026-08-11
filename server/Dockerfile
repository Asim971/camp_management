# Build context must be the REPOSITORY ROOT (not server/), because this
# Dockerfile copies the sibling `packages/campaign_contracts` path dependency.
# Build from the repo root with:
#   docker build -f server/Dockerfile -t campaign_service .
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
