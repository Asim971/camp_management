#!/bin/sh
# Run one `maestro test` per flow, attempting EVERY flow even after a failure,
# then fail once at the end listing all the red ones. Resets the backend's
# fixtures before each flow, so one flow's writes (a submitted campaign, a
# decided case) can never leak into the next flow's assertions.
#
# Why this is a file rather than inline YAML in ci.yml:
# reactivecircus/android-emulator-runner executes its `script:` input LINE BY
# LINE, each in its own `sh -c`. A multi-line `for`/`if` therefore cannot work
# there — the first run of this job died with
#
#     /usr/bin/sh -c for flow in .maestro/flows/locale_bengali.yaml; do
#     /usr/bin/sh: 1: Syntax error: end of file unexpected (expecting "done")
#
# in all five matrix configs, because `do` and `done` landed in different
# shells. Variables do not survive between lines either, so `failed=""` was
# lost as well. Keeping the loop in one file makes it a single line to invoke.
#
# Stopping at the first red flow would also be wrong: each emulator boot costs
# ~15 minutes, which is far too expensive to spend discovering red flows one at
# a time.
#
# Usage: run_maestro_flows.sh <flow.yaml> [flow.yaml ...]
set -u

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <flow.yaml> [flow.yaml ...]" >&2
  exit 2
fi

# Every flow's `appId:` field reads ${APP_ID} and must be supplied at run time,
# because the dev flavor has its own application id (com.acsl.campaign.dev).
: "${APP_ID:=com.acsl.campaign.dev}"

# The backend behind API_BASE_URL (the emulator reaches it at
# http://10.0.2.2:8080; this script, running on the runner itself, reaches
# the same process at $BACKEND_URL) is started by an earlier CI step, either
# the real campaign_service (default) or tool/mock_server, selected there by
# USE_MOCK — kept as a flag rather than deleted so a red e2e run can be
# bisected against the old, known-good mock harness (spec §9's cut-over
# rule). Only the real service exposes `/__test__/reset`: the mock has no
# such route and stays in-memory across flows the way it always has, so this
# loop only resets when USE_MOCK is not set.
: "${USE_MOCK:=0}"
: "${BACKEND_URL:=http://127.0.0.1:8080}"

failed=""
for flow in "$@"; do
  if [ "$USE_MOCK" != "1" ]; then
    if ! curl -fsS -X POST "$BACKEND_URL/__test__/reset" > /dev/null; then
      echo "FAIL $flow (POST $BACKEND_URL/__test__/reset did not succeed)"
      failed="$failed $flow"
      continue
    fi
  fi

  echo "::group::$flow"
  if maestro test --env "APP_ID=$APP_ID" "$flow"; then
    echo "PASS $flow"
  else
    echo "FAIL $flow"
    failed="$failed $flow"
  fi
  echo "::endgroup::"
done

if [ -n "$failed" ]; then
  echo "FAILED FLOWS:$failed"
  exit 1
fi

echo "All flows passed."
