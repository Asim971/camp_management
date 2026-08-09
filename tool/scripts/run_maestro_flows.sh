#!/bin/sh
# Run one `maestro test` per flow, attempting EVERY flow even after a failure,
# then fail once at the end listing all the red ones.
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

failed=""
for flow in "$@"; do
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
