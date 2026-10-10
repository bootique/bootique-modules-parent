#!/usr/bin/env python3
"""Compute the push order (topological waves) for a set of Bootique module checkouts.

    wave-order.py <checkout-root> <repo-dir-name>...

Reads every pom.xml (ignoring target/) in the given repos, maps each repo to the io.bootique* group ids
it owns, then builds the inter-repo dependency graph from <dependency> entries with those group ids
(all scopes: a test dependency still needs the other repo's snapshot deployed first). Prints waves as
text and, with --json, as {"deps": {...}, "waves": [[...], ...]}.
"""
import json, pathlib, re, sys

def poms(d):
    return [p for p in d.rglob("pom.xml") if "target" not in p.parts]

def main(argv):
    as_json = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    root = pathlib.Path(argv[1])
    repos = [root / r for r in argv[2:]]
    own = {}
    for r in repos:
        gids = set()
        for p in poms(r):
            s = p.read_text()
            s = re.sub(r"<parent>.*?</parent>", "", s, flags=re.S)
            s = re.sub(r"<dependenc(y|ies)>.*?</dependenc(y|ies)>", "", s, flags=re.S)
            s = re.sub(r"<build>.*?</build>", "", s, flags=re.S)
            m = re.search(r"<groupId>(io\.bootique[^<]*)</groupId>", s)
            if m:
                gids.add(m.group(1))
        own[r.name] = gids
    gid2repo = {}
    for repo, gids in own.items():
        for g in gids:
            if g in gid2repo and gid2repo[g] != repo:
                print(f"WARN group id {g} claimed by both {gid2repo[g]} and {repo}", file=sys.stderr)
            gid2repo[g] = repo
    deps = {}
    for r in repos:
        ds = set()
        for p in poms(r):
            for m in re.finditer(r"<dependency>(.*?)</dependency>", p.read_text(), flags=re.S):
                g = re.search(r"<groupId>([^<]+)</groupId>", m.group(1))
                if not g or not g.group(1).startswith("io.bootique"):
                    continue
                if g.group(1) == "io.bootique.modules.parent":
                    continue
                tgt = gid2repo.get(g.group(1))
                if tgt is None:
                    # e.g. io.bootique.tools build helpers that live outside the module family
                    continue
                if tgt != r.name:
                    ds.add(tgt)
        deps[r.name] = sorted(ds)
    done, remaining, waves = set(), set(deps), []
    while remaining:
        ready = sorted(x for x in remaining if all(d in done for d in deps[x]))
        if not ready:
            print(f"ERROR dependency cycle among {sorted(remaining)}", file=sys.stderr)
            sys.exit(1)
        waves.append(ready)
        done |= set(ready)
        remaining -= set(ready)
    if as_json:
        print(json.dumps({"deps": deps, "waves": waves}, indent=1))
    else:
        for i, w in enumerate(waves):
            print(f"wave {i}: {' '.join(w)}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    main(sys.argv)
