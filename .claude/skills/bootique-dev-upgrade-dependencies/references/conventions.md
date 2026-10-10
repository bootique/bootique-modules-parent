# Bootique conventions for an upgrade cycle

These are the house rules observed across the `bootique/*` repositories. Following them keeps the
history, issues and release notes readable by the maintainers, who use them to write release
announcements. When a repo's own recent history contradicts something here, the repo wins.

## Commit messages

- Issue-backed change: the issue title followed by the number, e.g.
  `Upgrade Jackson to 2.22.3 #390`. Several issues in one commit go on separate lines.
- Parent bump in a module with no dedicated issue: `bootique-modules-parent 4.0.9`.
- Transitive-version alignment without an issue:
  `aligning jboss-logging version with the rest of Bootique`.
- Test-only dependency fixes (for example a JDBC driver used by testcontainers tests):
  `Upgrade PostgreSQL driver to 42.7.14 (tests only)`, no issue.
- No `Fixes #n` keywords in module commits: module issues are closed by hand after the CI run passes,
  so a green build is the record. The parent repo is the exception (its push has no downstream gate).
- No `Co-Authored-By` or other AI attribution lines, ever. The maintainer has asked for this explicitly.

## Issues

- Title `Upgrade <Library> to <version>`; body says why (CVE list for security bumps) and, for modules,
  "Via bootique-modules-parent <ver> (bootique/bootique-modules-parent#<n>)".
- Parent: one issue per upgrade, milestone named after the parent version (`4.0.9`). Create the
  milestone if missing.
- Modules: a dedicated issue only in the module that owns the upgraded library (see ownership), against
  the modules' next shared milestone. All modules are released in lockstep; find the next milestone
  name from the latest tag of any module (`git describe --tags --abbrev=0` gives e.g. `4.0-M6`, so the
  next is `4.0-M7`), and create it per repo if missing. Existing milestone names tell you the format.
- Compatibility fixes that change code get their own issue in that module, same milestone, with the
  diagnosis in the body (what upstream change caused it, how it was verified).
- Alignment-only POM changes, exclusions and test-only pins get no issue.

## Library ownership (who gets the release-note line)

The module whose published artifact ships the library at compile scope, and which has historically
carried that upgrade in its `RELEASE-NOTES.md`:

| Library | Module |
|---|---|
| Jackson, JUnit | `bootique` (core) |
| Jetty | `bootique-jetty` |
| Jersey, JAX-RS API | `bootique-jersey` |
| SLF4J | `bootique-logback` (core only uses `slf4j-simple` at test scope and excludes SLF4J elsewhere) |
| JAXB, Jakarta Activation | whichever module declares them at compile scope; check with `grep` |
| testcontainers | no module; it is test scope everywhere |

When unsure, `grep -c` the artifact in the module's POMs and look at scope; precedent in the module's
release notes settles it.

## Release notes

`RELEASE-NOTES.md` in every repo, newest section first:

```
## 4.0-M7

* #390 Upgrade Jackson to 2.22.3
* #391 Upgrade JUnit to 6.1.3
```

One line per issue, `* #<n> <issue title>`. The parent's notes may add the CVE list in parentheses on
the Jackson line. A module with no issue this cycle gets no new section.

## Fix patterns for dependency conflicts

`bootique-bom`'s test modules enforce `requireUpperBoundDeps` and `dependencyConvergence`, so a
single transitive path carrying an older version fails the whole BOM build. Fix at the module that
introduces the path, never in the BOM tests, so that users of the module get the same tree:

- **Exclude and declare.** In the module's root `dependencyManagement`, add an `<exclusion>` for the
  offending transitive under the dependency that brings it, with a one-line comment saying why
  (`<!-- agrest-engine pins an older SLF4J than Bootique declares -->`). Then declare the artifact
  directly in the module POM that needs it, with the comment
  `<!-- Fix the version of the "<dep>" transitive dependency -->`, version managed from the root POM.
  Managing a version in the module's own `dependencyManagement` is not enough: consumers don't inherit
  it, so the transitive path still shows the old version in their trees.
- **Alignment bump.** When the module itself pins the lower version (`<jboss.logging.version>`), bump
  the property to the version the other path wants.
- When two external libraries disagree and neither is pinned by Bootique (javassist from Jersey HK2 vs
  swagger-core), exclude it from the one that is "less authoritative" for the artifact and declare it
  at the other's version, with a comment saying which upstream it must track.

## Verification habits

- Every claim of "green" comes from `gh run list --json status,conclusion` filtered with `jq`, not from
  a wrapper script's summary.
- A flaky test is one that fails on one JDK of the matrix, passes on the other, and passes locally
  several times in a row. Re-run the failed jobs once. If it fails again it is not flaky.
- Local test runs of modules use `-o` after the first `-U` so that the snapshots installed from sibling
  checkouts are the ones under test.
