#!/usr/bin/env bash
# Lists bootique org repositories whose default-branch pom.xml uses bootique-modules-parent on a given
# version line, and whether each is checked out under a local root.
#
#   discover-modules.sh <version-line> [checkout-root]
#   discover-modules.sh 4.0 /Users/me/work/bootique-4.x
#
# Output, one line per candidate:  <repo> <default-branch> <parent-version> <local|MISSING>
# Archived repos and repos without a root pom.xml are skipped. bash 3.2 compatible.
set -eu
LINE=${1:?version line, e.g. 4.0}
ROOT=${2:-$(cd "$(dirname "$0")/../../../../.." && pwd)}

gh repo list bootique --limit 500 --json name,isArchived,defaultBranchRef \
  --jq '.[] | select(.isArchived|not) | "\(.name) \(.defaultBranchRef.name)"' |
while read -r name branch; do
  content=$(gh api "repos/bootique/$name/contents/pom.xml?ref=$branch" --jq .content 2>/dev/null) || continue
  ver=$(printf '%s' "$content" | base64 -d 2>/dev/null | python3 -I -c '
import re,sys
s=sys.stdin.read()
m=re.search(r"<parent>(.*?)</parent>", s, re.S)
if m and "bootique-modules-parent" in m.group(1):
    v=re.search(r"<version>([^<]+)</version>", m.group(1))
    print(v.group(1) if v else "")
')
  [ -n "$ver" ] || continue
  case "$ver" in "$LINE".*|"$LINE"-*) ;; *) continue;; esac
  if [ -d "$ROOT/$name/.git" ]; then where=local; else where=MISSING; fi
  printf '%-28s %-8s %-14s %s\n' "$name" "$branch" "$ver" "$where"
done
