#!/bin/sh
# cpubench.sh — Pythonなしでも動く軽量CPUベンチマーク（POSIXシェルのみ）
#
# 依存: POSIXシェル(sh/dash/bash/ash/busybox sh 等)と date, awk, mktemp のみ
#       Python不要。Linux / macOS / BSD / Androidのtermux / 組み込み機器などで動作想定
#
# 使い方:
#   sh cpubench.sh                  通常実行
#   sh cpubench.sh --duration 5     1テストあたり5秒に延長（精度アップ）
#   sh cpubench.sh --json           JSON文字列で出力
#   sh cpubench.sh --calibrate      このマシンを新しい基準(10.0点)として保存
#
# スコアの基準（10.0点 = Core i3-13100想定）:
#   single_ops_per_sec = 33825.6
#   multi_ops_per_sec  = 128829.6
# ※ この基準値は実測キャリブレーション値です。--calibrate で上書き可能です。

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REF_FILE="$SCRIPT_DIR/reference.conf"

DURATION=2.5
WORKERS=""
JSON=0
CALIBRATE=0

# --- 引数処理 -----------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --duration=*) DURATION="${1#*=}"; shift ;;
    --workers) WORKERS="$2"; shift 2 ;;
    --workers=*) WORKERS="${1#*=}"; shift ;;
    --json) JSON=1; shift ;;
    --calibrate) CALIBRATE=1; shift ;;
    --help|-h)
      echo "使い方: sh cpubench.sh [--duration 秒] [--workers 数] [--json] [--calibrate]"
      exit 0 ;;
    *) echo "不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# --- コア数の検出（複数手段でフォールバック） ----------------------------
detect_cores() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v getconf >/dev/null 2>&1 && getconf _NPROCESSORS_ONLN >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  elif command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 1
  fi
}
[ -n "$WORKERS" ] || WORKERS=$(detect_cores)

# --- ナノ秒時刻取得（GNU date は %N 対応 / 非対応なら秒精度にフォールバック） ---
now_ns() {
  t=$(date +%s%N 2>/dev/null || echo "")
  case "$t" in
    ''|*[!0-9]*) t=$(( $(date +%s) * 1000000000 )) ;;
  esac
  echo "$t"
}

# --- ワークロード本体 -----------------------------------------------------
# 奇数を対象に試し割りで素数判定を繰り返し、指定秒数内に処理できた件数を
# 標準出力に1行で出す（シェル組み込み算術のみ使用、外部コマンド呼び出しなし）
workload() {
  duration_ns=$1
  seed=$2
  start=$(now_ns)
  end=$((start + duration_ns))
  n=$((3 + seed * 100000))
  count=0
  while :; do
    i=0
    while [ $i -lt 500 ]; do
      is_prime=1
      d=3
      while [ $((d * d)) -le $n ]; do
        if [ $((n % d)) -eq 0 ]; then
          is_prime=0
          break
        fi
        d=$((d + 2))
      done
      [ $is_prime -eq 1 ] && count=$((count + 1))
      n=$((n + 2))
      i=$((i + 1))
    done
    now=$(now_ns)
    [ "$now" -ge "$end" ] && break
  done
  echo "$count"
}

to_ns() {
  # "2.5" のような秒指定をナノ秒(整数)に変換（POSIX awkのみ使用）
  awk -v s="$1" 'BEGIN{printf "%d", s*1000000000}'
}

DURATION_NS=$(to_ns "$DURATION")

# --- シングルコア計測 -----------------------------------------------------
[ "$JSON" -eq 1 ] || { echo "=================================================="; \
  echo "  CPUベンチマーク（20点満点式・シェル版）"; \
  echo "=================================================="; \
  echo "論理コア数 : $WORKERS"; \
  echo "テスト時間 : シングル/マルチ 各${DURATION}秒"; \
  echo ""; \
  echo "シングルコア計測中..."; }

single_count=$(workload "$DURATION_NS" 0)
single_ops=$(awk -v c="$single_count" -v d="$DURATION" 'BEGIN{printf "%.2f", c/d}')

[ "$JSON" -eq 1 ] || echo "  -> ${single_ops} 回/秒"

# --- マルチコア計測（バックグラウンドプロセスで並列実行し、tmpファイルに集計） ---
[ "$JSON" -eq 1 ] || echo "マルチコア計測中..."

TMPDIR_BENCH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BENCH"' EXIT INT TERM

w=1
while [ "$w" -le "$WORKERS" ]; do
  ( workload "$DURATION_NS" "$w" > "$TMPDIR_BENCH/$w.out" ) &
  w=$((w + 1))
done
wait

multi_count=0
w=1
while [ "$w" -le "$WORKERS" ]; do
  c=$(cat "$TMPDIR_BENCH/$w.out" 2>/dev/null || echo 0)
  multi_count=$((multi_count + c))
  w=$((w + 1))
done
multi_ops=$(awk -v c="$multi_count" -v d="$DURATION" 'BEGIN{printf "%.2f", c/d}')

[ "$JSON" -eq 1 ] || echo "  -> ${multi_ops} 回/秒（${WORKERS}プロセス合計）"

# --- 基準値の読み込み／保存 -----------------------------------------------
DEFAULT_REF_NAME="Core i3-13100 (calibrated baseline)"
DEFAULT_REF_SINGLE=33825.6
DEFAULT_REF_MULTI=128829.6

if [ "$CALIBRATE" -eq 1 ]; then
  {
    echo "REF_NAME=\"this machine (user calibrated)\""
    echo "REF_SINGLE=$single_ops"
    echo "REF_MULTI=$multi_ops"
  } > "$REF_FILE"
  REF_NAME="this machine (user calibrated)"
  REF_SINGLE="$single_ops"
  REF_MULTI="$multi_ops"
  if [ "$JSON" -ne 1 ]; then
    echo ""
    echo "[calibrate] 新しい基準値を保存しました: $REF_FILE"
  fi
elif [ -f "$REF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$REF_FILE"
  REF_NAME="$REF_NAME"
  REF_SINGLE="$REF_SINGLE"
  REF_MULTI="$REF_MULTI"
else
  REF_NAME="$DEFAULT_REF_NAME"
  REF_SINGLE="$DEFAULT_REF_SINGLE"
  REF_MULTI="$DEFAULT_REF_MULTI"
fi

# --- スコア計算（シングル35% : マルチ65%、20点満点でクリップ） -----------
result=$(awk -v so="$single_ops" -v mo="$multi_ops" -v rs="$REF_SINGLE" -v rm="$REF_MULTI" '
BEGIN {
  sr = so / rs
  mr = mo / rm
  score = 10.0 * (0.35 * sr + 0.65 * mr)
  if (score < 0) score = 0
  if (score > 20) score = 20
  printf "%.4f %.4f %.1f", sr, mr, score
}')

single_ratio=$(echo "$result" | awk '{print $1}')
multi_ratio=$(echo "$result" | awk '{print $2}')
score=$(echo "$result" | awk '{print $3}')

if [ "$JSON" -eq 1 ]; then
  cat <<EOF
{
  "logical_cores": $WORKERS,
  "single_ops_per_sec": $single_ops,
  "multi_ops_per_sec": $multi_ops,
  "reference_name": "$REF_NAME",
  "reference_single_ops_per_sec": $REF_SINGLE,
  "reference_multi_ops_per_sec": $REF_MULTI,
  "single_ratio_vs_reference": $single_ratio,
  "multi_ratio_vs_reference": $multi_ratio,
  "score": $score,
  "score_max": 20
}
EOF
else
  echo "--------------------------------------------------"
  echo "基準       : $REF_NAME"
  printf "シングル比 : %s%%（対 基準）\n" "$(awk -v r="$single_ratio" 'BEGIN{printf "%.1f", r*100}')"
  printf "マルチ比   : %s%%（対 基準）\n" "$(awk -v r="$multi_ratio" 'BEGIN{printf "%.1f", r*100}')"
  echo "--------------------------------------------------"
  echo "総合スコア : ${score} / 20 点"
  echo "--------------------------------------------------"
fi
