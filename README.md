# i3score20

**Core i3-13100 を「10.0点」の基準にした、20点満点のCPUベンチマーク。**
非力なマシンでも動き、移植しやすく、いろいろな機種で使えることを目指しています。

```
総合スコア : 9.8 / 20 点
```

## 特徴

- **20点満点**でスコアを表示（Core i3-13100 = 10.0点が基準）
- 依存ライブラリなし。しょぼい機種でも動く
- 2種類の実装を同梱。環境に合わせて選べる
  - `cpubench.py` … Python版（Python 3.6以上があればどこでも）
  - `cpubench.sh` … シェル版（**Pythonが入っていない機種向け**。sh/bash/dashのみで動作）
- スコア基準値は実測に基づき**補正済み**

## ファイル構成

| ファイル | 説明 | 必要なもの |
|---|---|---|
| `cpubench.py` | Python版本体 | Python 3.6+（標準ライブラリのみ） |
| `cpubench.sh` | シェル版本体 | sh / bash / dash など + date, awk, mktemp |
| `reference.json` / `reference.conf` | 基準値を保存するファイル（`--calibrate`実行時に自動生成） | - |

同じアルゴリズム（試し割りで素数判定を固定秒数繰り返す）で計測しますが、
言語ごとに実行速度が異なります。

## 使い方

### Pythonが使える機種

```bash
python3 cpubench.py
```

### Pythonが入っていない機種（シェル版）

```bash
sh cpubench.sh
# もしくは
bash cpubench.sh
```

### 共通オプション

| オプション | 説明 |
|---|---|
| `--duration 秒数` | 1テストあたりの計測時間（デフォルト2.5秒） |
| `--json` | 結果をJSON形式で出力 |
| `--workers 数` | マルチコアテストで使うプロセス数を手動指定 |
| `--calibrate` | 今のマシンを新しい基準（10.0点）として保存 |

## スコアの計算方法

1. 素数判定ループを**固定秒数**だけ実行し、処理できた件数（秒間スループット）を測定
2. シングルコア版・マルチコア版（全論理コア使用）をそれぞれ計測
3. 基準CPU（Core i3-13100）との比率を計算
4. 以下の式でスコアを算出（0〜20点にクリップ）

```
スコア = 10 × (シングル比 × 0.35 + マルチ比 × 0.65)
```

## 移植性

- **cpubench.py**: Windows / macOS / Linux で動作。1ファイルコピーするだけ
- **cpubench.sh**: Python不要。Linux / macOS / BSD / Android(Termux) / 組み込み機器などで動作。
  Windowsではそのままは動かないため、WSLやGit Bash等が必要

## 他のマシンで基準を合わせ直したいとき

基準にしたい別のマシンで一度だけ実行します。

```bash
python3 cpubench.py --calibrate   # Python版
sh cpubench.sh --calibrate        # シェル版
```

同じフォルダに `reference.json` / `reference.conf` が生成され、以降はその値が基準として使われます。
このファイルを他のマシンにコピーすれば、基準を共有できます。
