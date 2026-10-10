#!/usr/bin/env bash
# Waits for every GitHub Actions run of one commit and reports the conclusions.
#
#   wait-runs.sh <repo-name> <sha> [timeout-seconds]      (repo under the bootique org)
#
# Exit 0 when all runs completed with conclusion "success", 1 when any run ended otherwise, 2 on
# timeout. Conclusions are read with jq from the API; nothing here infers success from silence.
# "No runs yet" (the first seconds after a push) counts as pending. bash 3.2 compatible.
set -u
REPO=${1:?repo}; SHA=${2:?sha}; TIMEOUT=${3:-2700}
deadline=$((SECONDS+TIMEOUT))
while [ $SECONDS -lt $deadline ]; do
  json=$(gh run list -R "bootique/$REPO" --commit "$SHA" --json status,conclusion,workflowName,databaseId 2>/dev/null || echo '[]')
  n=$(printf '%s' "$json" | jq 'length')
  pending=$(printf '%s' "$json" | jq '[.[] | select(.status!="completed")] | length')
  if [ "$n" -gt 0 ] && [ "$pending" = "0" ]; then
    printf '%s' "$json" | jq -r --arg r "$REPO" '.[] | "\($r) \(.workflowName): \(.status)/\(.conclusion) run \(.databaseId)"'
    bad=$(printf '%s' "$json" | jq '[.[] | select(.conclusion!="success")] | length')
    [ "$bad" = "0" ] && exit 0 || exit 1
  fi
  sleep 30
done
echo "$REPO ${SHA:0:7}: timeout after ${TIMEOUT}s" >&2
exit 2
