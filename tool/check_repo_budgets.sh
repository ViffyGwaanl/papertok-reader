#!/usr/bin/env bash
# 仓库预算护栏(AGENT_PROTOCOL_zh.md 的强制执行层)。
# 用法: bash tool/check_repo_budgets.sh
# 兼容 macOS 自带 bash 3.2,无外部依赖。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

FAIL=0
DOC_DIR="docs/ai/future_agentic_upgrade"
DOC_BUDGET_BYTES=30720          # 30KB
LIB_MAX_LINES=1500
TEST_MAX_LINES=2500
BASELINE="tool/size_baseline.txt"

note_fail() { echo "FAIL: $1"; FAIL=1; }

# --- 1. 文档字节预算(archive 除外) ---
while IFS= read -r f; do
  sz=$(wc -c < "$f" | tr -d ' ')
  if [ "$sz" -gt "$DOC_BUDGET_BYTES" ]; then
    note_fail "文档超预算 ${sz}B > ${DOC_BUDGET_BYTES}B: $f(请精简或归档,不要追加叙事)"
  fi
done < <(find "$DOC_DIR" -name '*.md' -not -path "*/archive/*" 2>/dev/null)

# --- 2. 禁止进度叙事段落(archive 除外) ---
while IFS= read -r f; do
  if grep -q "^最新进展" "$f" 2>/dev/null; then
    note_fail "出现禁止的'最新进展'叙事段: $f(进度只写 STATUS_zh.md 一行 + commit message)"
  fi
done < <(find "$DOC_DIR" -name '*.md' -not -path "*/archive/*" 2>/dev/null)

# --- 3. 代码文件行数 ratchet ---
# 规则: lib ≤ LIB_MAX_LINES, test ≤ TEST_MAX_LINES;
# 超限文件必须在 baseline 中, 且当前行数 ≤ baseline 记录值(只许变短)。
baseline_limit() { # $1=path -> echo limit or empty
  [ -f "$BASELINE" ] || return 0
  awk -v p="$1" '$1==p {print $2}' "$BASELINE"
}

check_ratchet() { # $1=dir $2=max
  local dir="$1" max="$2"
  while IFS= read -r f; do
    lines=$(wc -l < "$f" | tr -d ' ')
    if [ "$lines" -gt "$max" ]; then
      limit="$(baseline_limit "$f")"
      if [ -z "$limit" ]; then
        note_fail "新超限文件 ${lines} 行 > ${max}: $f(新代码请放新文件;禁止加入 baseline)"
      elif [ "$lines" -gt "$limit" ]; then
        note_fail "ratchet 违例 ${lines} 行 > baseline ${limit}: $f(白名单文件只许变短)"
      fi
    fi
  done < <(find "$dir" -name '*.dart' -not -name '*.g.dart' -not -name '*.freezed.dart' -not -path 'lib/l10n/generated/*' 2>/dev/null)
}

check_ratchet lib "$LIB_MAX_LINES"
check_ratchet test "$TEST_MAX_LINES"

if [ "$FAIL" -eq 0 ]; then
  echo "OK: 文档预算、叙事禁令、行数 ratchet 全部通过。"
fi
exit "$FAIL"
