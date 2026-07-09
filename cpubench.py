#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cpubench.py — どんなマシンでも動く軽量CPUベンチマーク

- Python標準ライブラリのみ使用（pipインストール不要）
- Windows / macOS / Linux で動作
- 非力なマシンでも一定時間（デフォルト各2.5秒）で終わる「時間固定式」計測
- スコアは20点満点。Core i3-13100 が 10.0点になるよう調整済み

使い方:
    python3 cpubench.py                # 通常実行
    python3 cpubench.py --duration 5   # 1テストあたり5秒に延長（精度アップ）
    python3 cpubench.py --json         # JSON出力（他スクリプトから使う場合）
    python3 cpubench.py --calibrate    # 今のマシンを新しい基準(10.0点)として保存
"""

import argparse
import json
import multiprocessing
import os
import platform
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REFERENCE_FILE = os.path.join(SCRIPT_DIR, "reference.json")

# --- 初期基準値（Core i3-13100 相当の見積もり） -----------------------
# single: 1コアあたりの秒間処理数
# multi : 全論理コア合計の秒間処理数
DEFAULT_REFERENCE = {
    "cpu_name": "Intel Core i3-13100",
    "single_ops_per_sec": 33825.6,
    "multi_ops_per_sec": 128829.6,
    "note": "実機で更新済み",
}

# 1つのテストで固定秒数だけ回すワークロード。
# 試し割りで素数判定を繰り返すだけの純Python処理（外部ライブラリ不要）。
CHUNK = 1000  # 時間チェックの間隔（この回数ごとにtime.perf_counter()を呼ぶ）


def _workload(duration, start_n=3, _return_dict=None, _key=None):
    """duration秒間、素数判定ループを回して処理件数を返す。"""
    end = time.perf_counter() + duration
    n = start_n
    count = 0
    while True:
        for _ in range(CHUNK):
            is_prime = True
            i = 2
            while i * i <= n:
                if n % i == 0:
                    is_prime = False
                    break
                i += 1
            if is_prime:
                count += 1
            n += 2  # 奇数だけ調べる
        if time.perf_counter() >= end:
            break
    result = count / duration
    if _return_dict is not None:
        _return_dict[_key] = result
    return result


def _worker(args):
    duration, seed_offset = args
    # 各プロセスで少し違う開始地点にして、キャッシュ状況を揃える
    return _workload(duration, start_n=3 + seed_offset * 100000)


def run_single_core_test(duration):
    return _workload(duration)


def run_multi_core_test(duration, workers):
    if workers <= 1:
        return run_single_core_test(duration), 1
    with multiprocessing.Pool(processes=workers) as pool:
        results = pool.map(_worker, [(duration, i) for i in range(workers)])
    return sum(results), workers


def load_reference():
    if os.path.exists(REFERENCE_FILE):
        try:
            with open(REFERENCE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return DEFAULT_REFERENCE


def save_reference(data):
    with open(REFERENCE_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def get_cpu_name():
    name = platform.processor()
    if not name and platform.system() == "Linux":
        try:
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if line.lower().startswith("model name"):
                        name = line.split(":", 1)[1].strip()
                        break
        except OSError:
            pass
    return name or platform.machine() or "unknown"


def compute_score(single_ops, multi_ops, reference):
    ref_single = reference["single_ops_per_sec"]
    ref_multi = reference["multi_ops_per_sec"]
    single_ratio = single_ops / ref_single
    multi_ratio = multi_ops / ref_multi
    # シングル35% : マルチ65% の重み付け（体感速度とスループットのバランス）
    raw_score = 10.0 * (0.35 * single_ratio + 0.65 * multi_ratio)
    score = max(0.0, min(20.0, raw_score))
    return score, single_ratio, multi_ratio


def main():
    parser = argparse.ArgumentParser(description="軽量CPUベンチマーク（Core i3-13100=10.0点基準）")
    parser.add_argument("--duration", type=float, default=2.5,
                         help="1テストあたりの計測秒数（デフォルト: 2.5秒）")
    parser.add_argument("--workers", type=int, default=None,
                         help="マルチコアテストで使うプロセス数（デフォルト: 論理コア数）")
    parser.add_argument("--json", action="store_true", help="結果をJSONで出力する")
    parser.add_argument("--calibrate", action="store_true",
                         help="このマシンの実測値を新しい基準(10.0点=このマシン)として保存する")
    args = parser.parse_args()

    workers = args.workers or multiprocessing.cpu_count()
    cpu_name = get_cpu_name()

    if not args.json:
        print("=" * 50)
        print("  i3score20（Python式）")
        print("=" * 50)
        print(f"CPU        : {cpu_name}")
        print(f"論理コア数 : {workers}")
        print(f"テスト時間 : シングル/マルチ 各{args.duration}秒")
        print()
        print("シングルコア計測中...", flush=True)

    single_ops = run_single_core_test(args.duration)

    if not args.json:
        print(f"  -> {single_ops:,.0f} 回/秒")
        print("マルチコア計測中...", flush=True)

    multi_ops, used_workers = run_multi_core_test(args.duration, workers)

    if not args.json:
        print(f"  -> {multi_ops:,.0f} 回/秒（{used_workers}プロセス合計）")
        print()

    if args.calibrate:
        new_ref = {
            "cpu_name": cpu_name,
            "single_ops_per_sec": round(single_ops, 2),
            "multi_ops_per_sec": round(multi_ops, 2),
            "note": "ユーザーが --calibrate で保存した基準値（このCPU = 10.0点）",
        }
        save_reference(new_ref)
        if not args.json:
            print(f"[calibrate] 新しい基準値を保存しました: {REFERENCE_FILE}")
            print(f"            基準CPU: {cpu_name}")
        reference = new_ref
    else:
        reference = load_reference()

    score, single_ratio, multi_ratio = compute_score(single_ops, multi_ops, reference)

    result = {
        "cpu_name": cpu_name,
        "logical_cores": workers,
        "single_ops_per_sec": round(single_ops, 2),
        "multi_ops_per_sec": round(multi_ops, 2),
        "reference_cpu": reference.get("cpu_name"),
        "reference_single_ops_per_sec": reference.get("single_ops_per_sec"),
        "reference_multi_ops_per_sec": reference.get("multi_ops_per_sec"),
        "single_ratio_vs_reference": round(single_ratio, 4),
        "multi_ratio_vs_reference": round(multi_ratio, 4),
        "score": round(score, 1),
        "score_max": 20,
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("-" * 50)
        print(f"基準CPU     : {reference.get('cpu_name')}")
        print(f"シングル比  : {single_ratio * 100:5.1f}%（対 基準CPU）")
        print(f"マルチ比    : {multi_ratio * 100:5.1f}%（対 基準CPU）")
        print("-" * 50)
        print(f"総合スコア  : {score:.1f} / 20 点")
        print("-" * 50)
        if reference is DEFAULT_REFERENCE:
            print("※ 基準値はCore i3-13100の推定値です。")
            print("  実機のi3-13100があれば --calibrate で正確な基準に更新できます。")


if __name__ == "__main__":
    main()
