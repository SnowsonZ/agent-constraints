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
    # 文档里的 json fence 必须是真 JSON。带注释或省略号的示例会在这里炸，
    # 那是有意的：读者会照抄这些块。
    value = json.loads(block)
    if value.get("decision") == "block" and value.get("reason"):
        break
else:
    raise SystemExit(1)
PY
then
  fail 'Stop hook must document a parseable decision:block JSON object'
fi

# 四层表存在三份（根 README、skill README、SKILL.md），性质列措辞各有取舍，
# 但「机制」列必须字字一致——它就是这个技能的结论本身，分叉等于发布两套说法。
if ! python3 - "$ROOT/README.md" "$SKILL/README.md" "$SKILL/SKILL.md" <<'PY'
import re
import sys

LAYERS = ("1 执行层", "2 常驻层", "3 按需层", "4 会话层")
seen = {}
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    for layer in LAYERS:
        match = re.search(
            r"^\|\s*\*\*" + re.escape(layer) + r"\*\*\s*\|([^|]*)\|", text, re.M
        )
        if not match:
            print(f"{path}: no row for {layer}", file=sys.stderr)
            raise SystemExit(1)
        seen.setdefault(layer, {})[path] = match.group(1).strip()

status = 0
for layer, by_path in seen.items():
    if len(set(by_path.values())) > 1:
        status = 1
        print(f"{layer} 机制列分叉:", file=sys.stderr)
        for path, cell in by_path.items():
            print(f"  {path}: {cell}", file=sys.stderr)
raise SystemExit(status)
PY
then
  fail 'the four-layer table must agree across all three copies'
fi

# SKILL.md 重载语义在三处文件里各说一次，v0.1.4 曾经改了两处漏一处，两套说法并存。
# 实测结论是「一律新开会话」：正文走异步缓存，比磁盘落后一拍。
# 这里既正向要求三处都说新会话，也反向禁掉那个被实测推翻的说法。
if ! python3 - "$SKILL/README.md" "$SKILL/SKILL.md" "$SKILL/LAYER3-ONDEMAND.md" <<'PY'
import sys

DISPROVEN = ("重新调用即可", "重新调用可加载", "当前会话重新调用")
status = 0
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    if "新会话" not in text and "新开会话" not in text and "新开一个会话" not in text:
        print(f"{path}: 没有要求新会话验证 Skill 改动", file=sys.stderr)
        status = 1
    for phrase in DISPROVEN:
        if phrase in text:
            print(f"{path}: 含被实测推翻的说法 {phrase!r}", file=sys.stderr)
            status = 1
raise SystemExit(status)
PY
then
  fail 'skill reload semantics must say "new session" in all three files'
fi

# evals.json 由 skill-creator 的 grader 消费，字段名写错就是静默不生效。
if ! python3 - "$SKILL/evals/evals.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["skill_name"] == "agent-constraints", data.get("skill_name")
assert data["evals"], "evals must not be empty"
ids = []
for eval_case in data["evals"]:
    assert set(eval_case) == {
        "id", "prompt", "expected_output", "files", "expectations"
    }, sorted(eval_case)
    assert eval_case["expectations"], f"eval {eval_case['id']} has no expectations"
    ids.append(eval_case["id"])
assert len(set(ids)) == len(ids), f"duplicate eval ids: {ids}"
PY
then
  fail 'evals/evals.json must match the skill-creator schema'
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

: > "$TMP/existing.log"
chmod 644 "$TMP/existing.log"
CLAUDE_CONSTRAINTS_LOG="$TMP/existing.log" "$HOOK" <<'EOF'
{"cwd":"/tmp/project","reason":"logout","session_id":"existing","transcript_path":"/tmp/session.jsonl"}
EOF
if MODE=$(stat -f '%OLp' "$TMP/existing.log" 2>/dev/null); then
  :
else
  MODE=$(stat -c '%a' "$TMP/existing.log")
fi
[ "$MODE" = 600 ] || fail "existing log mode must be 600, got $MODE"
[ "$(wc -l < "$TMP/existing.log" | tr -d ' ')" = 1 ] ||
  fail 'existing log must gain one valid row'

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
