#!/usr/bin/env bash
# Runtime tests: the parts of the image that grep cannot check.
#
#   scripts/test-runtime.sh
#
# Four subjects, no Docker and no root:
#   * finish-policy.sh  — crash counting, trimming, escalation
#   * s6-nginx-run      — signal forwarding and the no-orphan guarantee
#   * image-ref.sh      — the image ref derived from the Dockerfile ARG
#   * version-tag.sh    — tag naming, including the rebuild suffix
#   * Dockerfile        — the invariants a build would catch, without a build
#
# Wired into the lint workflow, so it gates every push and PR.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
dummy=''
cleanup() {
  # Never decide the verdict: a temp dir that will not go away must not turn a
  # green run red.
  [ -z "$dummy" ] || kill "$dummy" 2>/dev/null || true
  rm -rf "$work" 2>/dev/null || true
}
trap cleanup EXIT

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; fails=$((fails + 1)); }
chk() { if [ "$1" = ok ]; then pass "$2"; else fail "$2${3:+ ($3)}"; fi; }

# --- 1. crash policy --------------------------------------------------------
mkdir -p "$work/bin"
cat > "$work/bin/s6-svscanctl" <<'EOF'
#!/bin/sh
: > "${FAKE_SVSCANCTL_MARK:-/dev/null}"
EOF
cat > "$work/bin/pidof" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_PIDOF:-}"
EOF
cat > "$work/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$work/bin/s6-svscanctl" "$work/bin/pidof" "$work/bin/sleep"
real_sleep=$(command -v sleep)
PATH="$work/bin:$PATH"
export PATH

policy="$here/runtime/finish-policy.sh"
run_policy() { sh "$policy" "$@"; }
export OPENGYM_CRASH_DIR="$work/crash"
export FAKE_SVSCANCTL_MARK="$work/svscanctl-called"

stamps() {
  local f="$OPENGYM_CRASH_DIR/api/stamps"
  if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi
}

run_policy api 0 15 >/dev/null 2>&1 || true
chk "$([ -e "$OPENGYM_CRASH_DIR/api/stamps" ] && echo bad || echo ok)" "SIGTERM is not counted"

run_policy api 143 0 >/dev/null 2>&1 || true
chk "$([ -e "$OPENGYM_CRASH_DIR/api/stamps" ] && echo bad || echo ok)" "exit 143 is not counted"

FAKE_PIDOF="$$" run_policy api 1 0 >/dev/null 2>&1 || true
chk "$([ "$(stamps)" = 1 ] && echo ok || echo bad)" "a real death is counted" "got $(stamps)"
chk "$([ -e "$OPENGYM_CRASH_DIR/nginx/stamps" ] && echo bad || echo ok)" "deaths are counted per service"

now=$(date +%s)
printf '%s\n%s\n' "$((now - 120))" "$((now - 90))" > "$OPENGYM_CRASH_DIR/api/stamps"
FAKE_PIDOF="$$" run_policy api 1 0 >/dev/null 2>&1 || true
chk "$([ "$(stamps)" = 1 ] && echo ok || echo bad)" "stamps older than 60 s are dropped" "got $(stamps)"

rm -f "$FAKE_SVSCANCTL_MARK"
rm -rf "$OPENGYM_CRASH_DIR/api"
out=''
for _ in 1 2 3 4 5; do out=$(FAKE_PIDOF='' run_policy api 1 0 2>&1 || true); done
case "$out" in *"crash loop"*) chk ok "the fifth death escalates" ;; *) chk bad "the fifth death escalates" ;; esac
case "$out" in *"no s6-pause"*) chk ok "a missing CMD is detected and named" ;; *) chk bad "a missing CMD is detected and named" ;; esac
chk "$([ -e "$FAKE_SVSCANCTL_MARK" ] && echo ok || echo bad)" "svscan is terminated when the CMD is gone"

# A real, expendable pid: the policy TERMs whatever pidof returns.
rm -f "$FAKE_SVSCANCTL_MARK"
rm -rf "$OPENGYM_CRASH_DIR/api"
"$real_sleep" 300 &
dummy=$!
out=''
for _ in 1 2 3 4 5; do out=$(FAKE_PIDOF="$dummy" run_policy api 1 0 2>&1 || true); done
case "$out" in *"crash loop"*) chk ok "it escalates with the CMD present" ;; *) chk bad "it escalates with the CMD present" ;; esac
case "$out" in *"no s6-pause"*) chk bad "it does not claim a missing CMD" ;; *) chk ok "it does not claim a missing CMD" ;; esac

# --- 2. nginx run script: signals and orphans -------------------------------
mkdir -p "$work/nginx"
cat > "$work/nginx/s6-setuidgid" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
cat > "$work/nginx/nginx" <<EOF
#!/bin/sh
echo \$\$ > "$work/nginx/pid"
: > "$work/nginx/started"
trap ': > "$work/nginx/termed"; exit 0' TERM
while :; do sleep 0.1; done
EOF
chmod 755 "$work/nginx/s6-setuidgid" "$work/nginx/nginx"

# Sets RC and ORPHAN for the caller.
drive() {  # $1 = wait for the child to start (yes | no)
  rm -f "$work/nginx/pid" "$work/nginx/started" "$work/nginx/termed"
  PATH="$work/nginx:/usr/bin:/bin" sh "$here/runtime/s6-nginx-run" >/dev/null 2>&1 &
  runner=$!
  if [ "$1" = yes ]; then
    for _ in $(seq 1 100); do [ -e "$work/nginx/started" ] && break; sleep 0.05; done
  fi
  sleep 0.1
  kill -TERM "$runner" 2>/dev/null || true
  RC=0
  wait "$runner" 2>/dev/null || RC=$?
  sleep 0.3
  ORPHAN=no
  if [ -f "$work/nginx/pid" ] && kill -0 "$(cat "$work/nginx/pid")" 2>/dev/null; then ORPHAN=yes; fi
}

drive yes
# A deliberate stop must look like death by SIGTERM (143 here), not a clean 0.
chk "$([ "$RC" = 143 ] && echo ok || echo bad)" "a forwarded stop exits 143" "got $RC"
chk "$([ "$ORPHAN" = no ] && echo ok || echo bad)" "a forwarded stop leaves no orphan"
chk "$([ -e "$work/nginx/termed" ] && echo ok || echo bad)" "the child received the TERM"

drive no
chk "$([ "$RC" = 143 ] && echo ok || echo bad)" "a TERM during startup exits 143" "got $RC"
chk "$([ "$ORPHAN" = no ] && echo ok || echo bad)" "a TERM during startup leaves no orphan"

# --- 3. image-ref ----------------------------------------------------------
expected=$(sed -n 's/^ARG OPENGYM_API_REPO=//p' "$here/Dockerfile" | head -1)
pinned=$(sed -n 's/^ARG UPSTREAM_VERSION=//p' "$here/Dockerfile" | head -1)
got=$(bash "$here/scripts/image-ref.sh" OPENGYM_API_REPO)
chk "$([ "$got" = "$expected:$pinned" ] && echo ok || echo bad)" "image-ref.sh resolves the pinned version" "got $got"
got=$(bash "$here/scripts/image-ref.sh" OPENGYM_API_REPO 0.0.1)
chk "$([ "$got" = "$expected:0.0.1" ] && echo ok || echo bad)" "image-ref.sh honours an explicit version" "got $got"

# --- 4. tag naming ---------------------------------------------------------
tag() { printf '%s\n' "$@" | bash "$here/scripts/version-tag.sh" "${TAG_VERSION:-1.4.4}"; }

got=$(tag v1.4.4)
chk "$([ "$got" = "v1.4.4" ] && echo ok || echo bad)" "the bare tag matches itself" "got '$got'"
got=$(tag v1.4.4 v1.4.4-1 v1.4.4-2)
chk "$([ "$got" = "v1.4.4-2" ] && echo ok || echo bad)" "the highest rebuild wins" "got '$got'"
got=$(tag v1.4.4 v1.4.4-2 v1.4.4-10)
chk "$([ "$got" = "v1.4.4-10" ] && echo ok || echo bad)" "rebuild numbers sort numerically, not as text" "got '$got'"
got=$(tag v1.4.40 v1.4.4-beta v1.5.0 v1.4.4x)
chk "$([ -z "$got" ] && echo ok || echo bad)" "lookalikes are rejected" "got '$got'"
# The prefix is gone from the scheme; a tag still carrying it must not match, or a
# leftover from the monorepo era would be counted as this repo's build history.
got=$(tag opengym-v1.4.4 opengym-v1.4.4-1)
chk "$([ -z "$got" ] && echo ok || echo bad)" "the retired opengym- prefix no longer matches" "got '$got'"
got=$(printf '' | bash "$here/scripts/version-tag.sh" 1.4.4; echo "rc=$?")
chk "$([ "$got" = "rc=0" ] && echo ok || echo bad)" "empty input exits 0" "got '$got'"

# --- 5. Dockerfile invariants ----------------------------------------------
# No daemon in most places this runs, so a real build is often impossible. These
# are the failures a build would report late: a COPY source that is not there, a
# COPY source excluded by .dockerignore, a variable expanded but never declared.
df="$here/Dockerfile"
known='FROM RUN CMD LABEL MAINTAINER EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL'
unknown=$(awk -v known="$known" '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ || /^[[:space:](]/ { next }
  { if (index(" " known " ", " " toupper($1) " ") == 0) print NR": "$1 }
' "$df")
chk "$([ -z "$unknown" ] && echo ok || echo bad)" "every instruction is one Docker knows" "$unknown"

used=$(grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' "$df" | tr -d '${}' | sort -u)
undeclared=''
for v in $used; do
  case "$v" in GITHUB_SERVER_URL) continue ;; esac
  grep -qE "^(ARG|ENV)[[:space:]]+$v|^[[:space:]]+$v=" "$df" || undeclared="$undeclared $v"
done
chk "$([ -z "$undeclared" ] && echo ok || echo bad)" "every expanded variable is declared" "$undeclared"

# Build-context sources only. A `COPY --from=` reads the other stage's
# filesystem, which does not exist on this machine, so checking it here would
# report four permanent false positives. Every argument before the destination
# is a source; flags are skipped.
ctx_sources() {
  awk '$1 != "COPY" || $2 ~ /^--from=/ { next }
       { for (i = 2; i < NF; i++) if ($i !~ /^--/) print $i }' "$df"
}

chk "$([ -n "$(ctx_sources)" ] && echo ok || echo bad)" "the build copies from the context at all"

missing=''
for src in $(ctx_sources); do
  [ -e "$here/$src" ] || missing="$missing $src"
done
chk "$([ -z "$missing" ] && echo ok || echo bad)" "every context COPY source exists" "$missing"

excluded=''
for src in $(ctx_sources); do
  grep -qxF -- "${src%/}" "$here/.dockerignore" && excluded="$excluded $src"
done
chk "$([ -z "$excluded" ] && echo ok || echo bad)" "no context COPY source is dockerignored" "$excluded"

# No USER line, deliberately. s6-overlay must start as PID 1 with root, and each
# service then drops privileges with s6-setuidgid — the two run scripts above
# assert that drop. A USER line here either duplicates it (USER root) or breaks
# the init (USER opengym), so its presence is the signal, whatever the value.
chk "$(grep -qE '^USER' "$df" && echo bad || echo ok)" "no USER instruction (s6 is PID 1 and drops per service)"

# Exclusive, not merely present: SECURITY.md states the API is reachable only
# through nginx on loopback, so a second EXPOSE would publish it to the host.
# `|| true` is load-bearing: the script runs with pipefail, so a Dockerfile with
# no EXPOSE line would abort the whole run here instead of reporting a failure.
exposed=$(grep -E '^EXPOSE ' "$df" | awk '{for (i = 2; i <= NF; i++) print $i}' | sort -u | tr '\n' ' ' || true)
chk "$([ "$exposed" = "80 " ] && echo ok || echo bad)" "exposes port 80 and nothing else" "$exposed"
chk "$(grep -q 'org.opencontainers.image.base.digest' "$df" && echo ok || echo bad)" "records the base digest"

printf '\nruntime tests: %d failure(s)\n' "$fails"
[ "$fails" -eq 0 ]
