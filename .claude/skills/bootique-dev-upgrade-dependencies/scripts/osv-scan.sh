#!/usr/bin/env bash
# Queries OSV.dev for known vulnerabilities in a Maven module's resolved runtime dependency tree.
#
#   osv-scan.sh <module-dir>          e.g. osv-scan.sh bootique-modules-parent-dependency-tests
#
# Prints one block per vulnerable artifact: advisory id, CVE aliases, severity, summary and the first
# fixed version for the affected version range. Exit 0 when nothing was found, 1 otherwise.
set -eu
MOD=${1:?module dir}
TMP=$(mktemp -d)
( cd "$MOD" && mvn -B -q dependency:list -DincludeScope=runtime -Dsort=true -DoutputFile="$TMP/deps.txt" >/dev/null )
grep -E '^\s+[a-zA-Z]' "$TMP/deps.txt" | sed -E 's/^\s+//; s/ -- .*//' | awk -F: '{print $1":"$2":"$4}' | sort -u > "$TMP/gav.txt"
python3 -I - "$TMP/gav.txt" <<'PY'
import json, sys, urllib.request
gavs=[l.strip() for l in open(sys.argv[1]) if l.strip()]
queries=[{"package":{"name":g.rsplit(":",1)[0],"ecosystem":"Maven"},"version":g.rsplit(":",1)[1]} for g in gavs]
hits=[]
for i in range(0,len(queries),100):
    chunk=queries[i:i+100]
    req=urllib.request.Request("https://api.osv.dev/v1/querybatch",data=json.dumps({"queries":chunk}).encode(),
                               headers={"Content-Type":"application/json"})
    for q,r in zip(chunk,json.load(urllib.request.urlopen(req,timeout=60))["results"]):
        for v in r.get("vulns") or []:
            hits.append((q["package"]["name"],q["version"],v["id"]))
print(f"{len(gavs)} artifacts checked, {len(hits)} advisory hits")
for name,ver,vid in hits:
    v=json.load(urllib.request.urlopen(f"https://api.osv.dev/v1/vulns/{vid}",timeout=60))
    sev=v.get("database_specific",{}).get("severity") or ",".join(s.get("score","") for s in v.get("severity",[]))
    fixed=[]
    for a in v.get("affected",[]):
        if a["package"]["name"]!=name: continue
        for rng in a.get("ranges",[]):
            ev=rng.get("events",[])
            intro=[e["introduced"] for e in ev if "introduced" in e]
            fix=[e["fixed"] for e in ev if "fixed" in e]
            fixed.append(f"{intro[0] if intro else '?'} -> fixed {fix[0] if fix else 'none'}")
    print(f"\n{name}:{ver}\n  {vid}  aliases={','.join(v.get('aliases',[])) or '-'}  severity={sev}\n  {v.get('summary','')}\n  ranges: {'; '.join(fixed)}")
sys.exit(1 if hits else 0)
PY
