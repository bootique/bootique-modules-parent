---
name: bootique-dev-upgrade-dependencies
description: >-
  Run a dependency upgrade cycle for the Bootique 4.x module family, starting from bootique-modules-parent.
  Use this whenever the user asks to check for newer dependency versions, address CVEs or security advisories,
  bump Jackson/Jetty/Jersey/JUnit/SLF4J/testcontainers/Maven plugins in the parent POM, roll a new
  bootique-modules-parent release out to the bootique-* module repos, or "upgrade all modules" after a parent
  release. Also use it when a dependency-related GitHub Actions failure appears in a module after a parent bump
  (enforcer convergence errors in bootique-bom, test regressions from a library upgrade). The flow has explicit
  human gates: proposed upgrades, the parent release, and any compatibility fixes are reviewed by a person
  before they are committed or pushed.
---

# Upgrade dependencies across Bootique

`bootique-modules-parent` pins the shared library and plugin versions for every `bootique-*` module repo in
the `bootique` GitHub organization. An upgrade cycle therefore has two halves: change the parent, release
it, then roll the new parent out to every module that uses it, in dependency order, watching CI as you go.

The person running this owns three decisions and the skill stops for each of them:

| Gate | When | What the human decides |
|---|---|---|
| **G1 Review upgrades** | after the audit, before touching the parent POM | which upgrades go in, which are deferred |
| **G2 Release the parent** | after the parent commit is pushed and green | the release itself is a manual `maven-release-plugin` run by the maintainer |
| **G3 Review compatibility fixes** | after modules are bumped and verified locally, before anything is committed | any code or POM change beyond the parent version bump |

Everything else (audits, builds, commits whose content was approved at a gate, pushes in dependency
order, issue bookkeeping) runs without asking. Never file issues in repositories outside the `bootique`
organization, and never rewrite pushed history.

Read `references/conventions.md` before writing any commit, issue, milestone or release-note entry. Read
`references/pitfalls.md` before proposing plugin upgrades and before diagnosing a CI failure; it records
what has already gone wrong in past cycles so it isn't rediscovered.

## Preconditions

- `gh` authenticated for the `bootique` org, `jq`, `python3`, `curl`, Maven, a JDK matching
  `maven.compiler.release` or newer, and Docker (several module test suites use testcontainers).
- Module repos cloned as siblings under one root directory (the parent lives there too). The user's
  checkout root is the parent's parent directory unless told otherwise. `scripts/discover-modules.sh`
  reports which candidate repos are missing locally; clone them before bumping.
- Shell scripts in `scripts/` are written for the macOS default bash 3.2. Don't introduce bash 4
  features (associative arrays, `${var,,}`) into them.

## Phase 1: audit the parent

1. Read `pom.xml`: the `<properties>` block holds one `*.version` property per managed library, and
   `<pluginManagement>` holds the plugin versions. `bootique-modules-parent-dependency-tests/pom.xml`
   declares one dependency per managed artifact so the build fails on a version that doesn't exist.
2. Run `scripts/central-latest.sh pom.xml` for the latest released versions of every managed library and
   plugin. It filters milestones and release candidates; treat anything it filtered as not eligible.
3. Run `scripts/osv-scan.sh bootique-modules-parent-dependency-tests` for known vulnerabilities in the
   fully resolved tree. It prints each advisory with its CVE alias, severity and the first fixed version.
   Advisories on artifacts that no module actually ships (check with `grep` across the sibling repos
   for the artifact, and look for exclusions) are findings to report, not upgrades to make.
4. Read `RELEASE-NOTES.md` and `git log` for context: a version that was recently downgraded, or a
   property deliberately kept aligned with downstream modules (the commons-* versions in the
   dependency-tests POM are an example), should not be re-bumped without saying so.
5. For every plugin bump beyond a patch version, check the plugin's release notes for behavior changes.
   Two already bit this project: RAT 0.17+ and failsafe 3.6.0 (see pitfalls).

**Stop at G1.** Present one table: current version, proposed version, reason (CVE ids, routine update), and
anything deliberately left alone with the reason. Wait for the decision.

## Phase 2: change, verify and ship the parent

1. Apply the approved versions in `pom.xml` (and the dependency-tests POM where it owns the property).
2. Verify: `mvn -B -U -Prat verify` from the parent root. This resolves every new version through the
   dependency-tests module and exercises the upgraded plugins. Re-run `scripts/osv-scan.sh` and confirm the
   advisories that motivated the change are gone.
3. If a plugin upgrade changes behavior for downstream modules (it is inherited by all of them), test it
   against one or two multi-module repos before keeping it, for example
   `mvn -Prat org.apache.rat:apache-rat-plugin:<new>:check` in a sibling repo.
4. Bookkeeping, following `references/conventions.md`: a milestone named after the next parent version,
   one issue per upgrade in `bootique/bootique-modules-parent`, a release-notes section listing them.
5. Commit on `master` and push. The commit message carries `Fixes #n` lines so the parent issues close on
   push (this is the one place where closing on push is fine: the parent has no CI gate of its own that
   matters for the release).

**Stop at G2.** Tell the maintainer the parent is ready to release and which version it will be. The release
is done by them. When they say it is released, poll Maven Central for the parent POM once a minute (it
typically appears within ten minutes):
`https://repo1.maven.org/maven2/io/bootique/modules/parent/bootique-modules-parent/<ver>/bootique-modules-parent-<ver>.pom`
Nothing downstream can start before that returns 200, because the modules resolve the parent from Central.

## Phase 3: bump the modules and find what breaks

1. Discover candidates with `scripts/discover-modules.sh <line>` (for example `4.0`). It lists every
   non-archived repo in the org whose default-branch `pom.xml` names `bootique-modules-parent` with a
   version on that line, and flags repos missing from the local checkout root. Do not hardcode a module
   list anywhere; the set changes between cycles.
2. `git pull --ff-only` every candidate. Refuse to continue on a repo with local modifications.
3. Compute the push order with `scripts/wave-order.py <root> <repo>...`. It reads the repos' POMs, maps
   `io.bootique*` group ids to repos, and prints topological waves (core first, the BOM last). The waves
   are recomputed every cycle for the same reason the module list is.
4. Bump the parent version in each candidate's root POM.
5. Verify locally before any push, because CI runs module by module and a convergence problem only shows
   up in `bootique-bom` at the very end:
   - Install the modules locally without tests, in wave order: `mvn -B -o -DskipTests install` (use
     `-U` once on the first repo to refresh the parent). This gives the BOM tests the new snapshots.
   - Run the BOM enforcer offline: `mvn -B -o -fae -DskipTests validate` in `bootique-bom`. Its test
     modules use `requireUpperBoundDeps` plus `dependencyConvergence`, so every path in the tree must
     agree on a version.
   - Run the full test suite (`mvn -B verify`) of every module whose main dependency changed (Jetty for
     bootique-jetty, Jersey for bootique-jersey, and so on) and of any module the BOM check implicated.
6. For each failure, find the cause before proposing a fix: compare the failing version with the previous
   one by overriding the property on the command line (`-Djetty.version=12.1.13`), read the upstream
   change log, and reproduce locally. Fixes follow the patterns in `references/conventions.md`
   ("exclude and declare" for convergence conflicts, alignment bumps of transitive pins, relocating a
   handler when an upstream fast path changed). Keep each fix in its own module and leave the parent as is.
7. Bookkeeping for modules: a dedicated issue, against the modules' next milestone, only for a module
   whose own headline dependency changed (see the ownership rules in conventions), plus one per
   compatibility fix that changes code. Alignment-only POM changes get no issue. Add release-note entries
   where an issue was filed.

**Stop at G3.** Report, per module: what changed beyond the parent bump, why, how it was verified, and the
issues filed. Include the computed wave order. Nothing is committed yet at this point; the human may
reject or reshape a fix.

## Phase 4: commit and push in waves

1. Commit each repo with the message rules from conventions: the issue title plus number when a dedicated
   issue exists, otherwise the plain `bootique-modules-parent <ver>` line. Never add closing keywords here;
   module issues close only after their CI run passes. Never add AI attribution trailers.
2. Push one wave at a time and wait for every run in the wave with `scripts/wait-runs.sh <repo> <sha>`
   before pushing the next. A module's CI deploys the snapshot its dependents build against, which is the
   whole reason for the ordering.
3. Verify conclusions with `jq` on `gh run list --json` output, exactly as `wait-runs.sh` does, and spot
   check the first wave by hand. A previous cycle's driver script misclassified failures as successes
   because of a quoting bug and the BOM failure was missed until the user pointed at it. A wrapper script
   is a convenience; the run conclusion from the API is the fact.
4. On a failure: read `gh run view --log-failed`. If only one matrix job failed on a timeout-flavored test
   and the same test passes locally and on the other JDK, re-run the failed jobs once with
   `gh run rerun <id> --failed`. Anything else is a real problem: fix at the source module (which may
   mean going back to G3), push that module, wait, then re-run the dependent's workflow.
5. Close each dedicated issue right after its repo's run is green. Print the push sequence as you go so
   the user can follow from the terminal.

## Phase 5: wrap up

- Report pushes to repos that surfaced Dependabot alerts (the `git push` output prints them). Alerts on
  test-only pins are fixed in a separate pass with a plain commit and no issue.
- Upstream bugs discovered on the way (a library regression, not a Bootique problem) are reported only
  when the maintainer asks; offer a drafted issue with the reproduction.
- Save anything non-obvious learned this cycle into `references/pitfalls.md` so the next cycle starts
  from it, and update `references/conventions.md` if a convention changed.
