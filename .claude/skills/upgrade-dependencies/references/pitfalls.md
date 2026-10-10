# Pitfalls recorded from past upgrade cycles

Each entry: what happened, how it was recognized, what to do. Add to this file at the end of a cycle.

## Parent POM

- **JAXB `jakarta.xml.bind-api`**: Maven Central's `<latest>` is a 4.1.0 milestone; 4.0.5 is the
  newest GA. A past bump to "4.0.9" was a typo for a version that does not exist and had to be reverted
  (issue #106). Always read the full version list, not `<latest>`/`<release>`.
- **`jackson-annotations`** has its own property because its versions diverge from the rest of Jackson
  (`2.22` while the others are `2.22.x`). Its `<release>` on Central points at a 3.0 RC; stay on the 2.x
  line that matches `jackson.version`.
- **commons-lang3 / commons-io / commons-codec** in the dependency-tests POM are kept at the versions
  the downstream modules use, not at the latest. Bumping them there alone breaks the alignment.
- **apache-rat-plugin 0.17+** changes multi-module behavior: the aggregator scans submodule sources from
  the root, so child-level `<exclude>` entries stop applying and `mvn -Prat` fails downstream with dozens
  of unapproved files. It also deprecates `<excludes>` in favor of `<inputExclude>`, which the 20+ module
  POMs merge into via `combine.children="append"`. 0.16.1 behaves like 0.13. Moving past it needs a
  coordinated migration of every module's rat profile.
- The dependency-tests module pulls `jackson-datatype-guava`, whose Guava 25.1 has two old advisories.
  Only `bootique-job-consul` uses that artifact, and it excludes Guava and pins 33.x, so the advisory is
  a false positive at the parent level. Report it, don't chase it.

## Tooling

- macOS ships bash 3.2: `declare -A` aborts the script. A driver that pushed the first wave and then
  died this way was the first failure of the last cycle. Keep scripts bash 3.2-compatible and run
  `bash -n` before launching anything long-running.
- Embedding Python f-strings with nested double quotes inside a bash double-quoted string produces a
  syntax error, which an `|| echo` or an empty capture then turns into a false "success". The second
  failure of the last cycle: the driver reported bootique-bom green while its run had failed. Use `jq`
  for JSON in shell, and test the failure branch of any checker with fake failing input before use.
- `gh run list --commit <sha>` returns nothing for the first ~10 seconds after a push; treat "no runs
  yet" as pending, not as success.
- Sonatype OSS Index refuses unauthenticated bulk queries; OSV.dev's `querybatch` API works without a
  key and is what `scripts/osv-scan.sh` uses.
- The first `mvn ... -Prat verify` after bumping a plugin may pass in the parent (few files) and still
  break every module. Test inherited plugin changes against a real multi-module sibling.
