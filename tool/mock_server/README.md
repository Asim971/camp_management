# ACSL Mock Server

In-memory stub backend so the Flutter app and the Maestro E2E suite run
end-to-end without a real backend. Implements every endpoint the repositories
call; state is per-process (restart to reset). CORS is open, so Flutter **web**
works too.

## Run

```bash
cd tool/mock_server
dart pub get
dart run bin/server.dart          # http://0.0.0.0:8080
```

Variants:
```bash
PORT=9090 dart run bin/server.dart
MOCK_CAMPAIGNS=empty dart run bin/server.dart   # campaign_list empty state
MOCK_CAMPAIGNS=error dart run bin/server.dart   # campaign_list error state
```

## Point the app at it

Because production auth isn't wired yet, run the app in **E2E mode** (fake auth +
`/dev` launcher) for a manual end-to-end demo:

```bash
# Web / desktop
flutter run -d chrome \
  --dart-define=E2E=true \
  --dart-define=API_BASE_URL=http://localhost:8080

# Android emulator (host is 10.0.2.2 from inside the emulator)
flutter run -d emulator-5554 --flavor dev \
  --dart-define=E2E=true \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Land on the `/dev` launcher → open any screen. The campaign list, detail,
wizard, approval, registration, import, capture and CRM case are all backed by
this server.

## Endpoints

| Method | Path | Used by |
|--------|------|---------|
| GET | `/campaigns` | campaign list (honors `MOCK_CAMPAIGNS`) |
| POST/PUT | `/campaigns`, `/campaigns/{id}` | wizard create/update draft |
| POST | `/campaigns/{id}/submit`, `/{id}/decision` | submit / approval |
| GET | `/campaigns/{id}` | campaign detail |
| GET | `/campaigns/{id}/sessions`; POST `/sessions/{id}/{start\|close\|pause}` | detail session ops |
| GET | `/carpenters?q=` | registration master search |
| POST | `/campaigns/{id}/registrations`, `/{id}/profile-requests` | register / new-profile |
| GET | `/sessions/{id}/registrations` | field roster cache warm |
| GET | `/verification/queue`, `/verification/cases/{id}` | CRM |
| POST | `/verification/cases/{id}/decision` | CRM decision (`CASE_CONFLICT` → 409) |
| POST | `/campaigns/{id}/imports/dry-run`; `/imports/{jobId}/commit` | bulk import |
| POST | `/media/presign`; PUT `/media/upload/{id}`; POST `/attendance/{id}/confirm` | offline attendance sync |
| GET | `/media/fixtures/face.png` | CRM evidence image |

## Maestro E2E

Build the E2E app against the mock, then run flows (Android for offline):
```bash
flutter build apk --flavor dev --debug \
  --dart-define=E2E=true --dart-define=LOCALE=en \
  --dart-define=API_BASE_URL=http://10.0.2.2:8080
maestro test --env APP_ID=com.acsl.campaign.dev .maestro/
```
