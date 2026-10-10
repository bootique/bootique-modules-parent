#!/usr/bin/env bash
# Prints the newest released versions on Maven Central for the libraries and plugins managed by a
# bootique-modules-parent pom.xml.
#
#   central-latest.sh <path-to-parent-pom.xml>
#
# Libraries: every "<name>.version" property is looked up through a representative artifact (see the
# table below; extend it when a property is added). Plugins: every <plugin> in <pluginManagement>.
# Pre-releases (alpha, beta, rc, milestones, snapshots) are filtered out; the last five remaining
# versions are shown so that a newer line (e.g. a 3.0 next to a 2.22.x) is visible rather than hidden
# behind a single "latest". Compare by eye against the current value printed in the first column.
set -eu
POM=${1:?parent pom.xml}
lookup() { # groupId artifactId -> last 5 GA versions
  curl -s --max-time 20 "https://repo1.maven.org/maven2/$(echo "$1" | tr . /)/$2/maven-metadata.xml" |
    grep -oE '<version>[^<]+</version>' | sed 's/<[^>]*>//g' |
    grep -viE 'alpha|beta|-rc|\.rc|M[0-9]+$|-M[0-9]|snapshot|pr[0-9]|-ea' | tail -5 | tr '\n' ' '
}
prop() { grep -oE "<$1>[^<]+" "$POM" | sed "s/<$1>//" | head -1; }
echo "== libraries =="
while read -r p g a; do
  printf '%-30s %-12s %s\n' "$p" "$(prop "$p")" "$(lookup "$g" "$a")"
done <<'TABLE'
activation2.version jakarta.activation jakarta.activation-api
jaxb.version jakarta.xml.bind jakarta.xml.bind-api
jackson.version com.fasterxml.jackson.core jackson-core
jackson.annotations.version com.fasterxml.jackson.core jackson-annotations
jackson.databind.version com.fasterxml.jackson.core jackson-databind
junit.version org.junit.jupiter junit-jupiter-engine
slf4j.version org.slf4j slf4j-api
jetty.version org.eclipse.jetty jetty-server
jaxrs.version jakarta.ws.rs jakarta.ws.rs-api
jersey.version org.glassfish.jersey.core jersey-common
testcontainers.version org.testcontainers testcontainers
central.publishing.maven.plugin.version org.sonatype.central central-publishing-maven-plugin
TABLE
echo; echo "== plugins (pluginManagement) =="
python3 -I - "$POM" <<'PY' | while read -r g a v; do printf '%-45s %-10s %s\n' "$g:$a" "$v" "$(lookup "$g" "$a")"; done
import re,sys
s=open(sys.argv[1]).read()
pm=re.search(r"<pluginManagement>(.*?)</pluginManagement>",s,re.S)
for m in re.finditer(r"<plugin>(.*?)</plugin>",pm.group(1) if pm else "",re.S):
    b=m.group(1)
    g=re.search(r"<groupId>([^<]+)",b); a=re.search(r"<artifactId>([^<]+)",b); v=re.search(r"<version>([^<]+)",b)
    if a and v and not v.group(1).startswith("${"):
        print(g.group(1) if g else "org.apache.maven.plugins", a.group(1), v.group(1))
PY
