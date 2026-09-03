#!/bin/sh
# SessionEnd hook：为约束复盘留一条会话记录。
#
# 只记指针，不解析 transcript——复盘时由 agent 去读，避免依赖未公开的
# transcript JSONL 结构。
#
# 无论如何都 exit 0：这个 hook 绝不能影响会话正常结束。

umask 077
LOG="${CLAUDE_CONSTRAINTS_LOG:-$HOME/.claude/constraint-review.log}"

if ! LOG_DIR=$(dirname "$LOG"); then
    printf '%s\n' 'agent-constraints: cannot determine log directory' >&2
    exit 0
fi
if ! mkdir -p "$LOG_DIR"; then
    printf '%s\n' 'agent-constraints: cannot create log directory' >&2
    exit 0
fi
if ! touch "$LOG"; then
    printf '%s\n' 'agent-constraints: cannot create session log' >&2
    exit 0
fi
if ! chmod 600 "$LOG"; then
    printf '%s\n' 'agent-constraints: cannot secure session log' >&2
    exit 0
fi

if ! python3 -c '
import datetime
import json
import sys

def field(value):
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )

try:
    event = json.load(sys.stdin)
except Exception:
    print("agent-constraints: invalid SessionEnd JSON", file=sys.stderr)
    sys.exit(1)

print("\t".join([
    field(datetime.datetime.now().isoformat(timespec="seconds")),
    field(event.get("cwd", "?")),
    field(event.get("reason", "?")),
    field(event.get("session_id", "?")),
    field(event.get("transcript_path", "?")),
]))
' >> "$LOG"; then
    printf '%s\n' 'agent-constraints: cannot write session log' >&2
fi

exit 0
