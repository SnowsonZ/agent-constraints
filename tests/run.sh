#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d /tmp/agent-constraints-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

SKILL="$ROOT/skills/agent-constraints"
HOOK="$SKILL/hooks/log-session.sh"

sh -n "$HOOK"

if ! python3 - "$SKILL/LAYER1-ENFORCEMENT.md" <<'PY'
import json
import re
import sys

document = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"```json\s*\n(\{.*?\})\s*\n```", document, re.DOTALL)
for block in blocks:
    value = json.loads(block)
    if value.get("decision") == "block" and value.get("reason"):
        break
else:
    raise SystemExit(1)
PY
then
  fail 'Stop hook must document a parseable decision:block JSON object'
fi

CLAUDE_CONSTRAINTS_LOG="$TMP/valid.log" "$HOOK" <<'EOF'
{"cwd":"/tmp/project","reason":"logout","session_id":"abc","transcript_path":"/tmp/session.jsonl"}
EOF
[ "$(wc -l < "$TMP/valid.log" | tr -d ' ')" = 1 ] ||
  fail 'valid event must create one row'
FIELDS=$(awk -F '\t' 'NR == 1 { print NF }' "$TMP/valid.log")
[ "$FIELDS" = 5 ] || fail 'valid row must have five fields'
if MODE=$(stat -f '%OLp' "$TMP/valid.log" 2>/dev/null); then
  :
else
  MODE=$(stat -c '%a' "$TMP/valid.log")
fi
[ "$MODE" = 600 ] || fail "log mode must be 600, got $MODE"

CLAUDE_CONSTRAINTS_LOG="$TMP/invalid.log" "$HOOK" \
  2>"$TMP/invalid.err" <<'EOF'
not-json
EOF
grep -Fq 'agent-constraints: invalid SessionEnd JSON' "$TMP/invalid.err" ||
  fail 'invalid JSON must emit a diagnostic'

CLAUDE_CONSTRAINTS_LOG="$TMP/special.log" "$HOOK" <<'EOF'
{"cwd":"/tmp/a\nsecond","reason":"logout","session_id":"abc\tdef","transcript_path":"/tmp/session.jsonl"}
EOF
[ "$(wc -l < "$TMP/special.log" | tr -d ' ')" = 1 ] ||
  fail 'escaped values must stay on one row'
FIELDS=$(awk -F '\t' 'NR == 1 { print NF }' "$TMP/special.log")
[ "$FIELDS" = 5 ] || fail 'escaped row must keep five fields'
grep -Fq '\n' "$TMP/special.log" || fail 'newline must be escaped'
grep -Fq '\t' "$TMP/special.log" || fail 'tab must be escaped'

printf 'PASS: local skill contracts\n'
