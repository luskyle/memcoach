#!/usr/bin/env python3
"""JMDict + tanos JLPT 词表 → 记忆教练离线词库 JSON（N5~N4 + 五十音表）。

数据源（均为免费可商用/社区公开）：
- tanos.co.uk JLPT 词表（kanji+reading，分级权威）——
  经 Bluskyo/JLPT_Vocabulary 仓库转存的 CSV：
  https://raw.githubusercontent.com/Bluskyo/JLPT_Vocabulary/main/data/vocab/parsedData/{n5,n4}_vocab_cleaned.csv
- JMDict-simplified（英文释义）：jmdict-eng-*.json（release 附件，v3 格式 words[]）

输出：lib/assets/dictionary/jlpt.json（App 打包为 asset，运行时导入）

用法: python3 scripts/build_dictionary.py <jmdict.json> <n5.csv> <n4.csv>
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JMDICT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/jmdict-eng-3.6.2.json")
N5_CSV = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("/tmp/n5_vocab.csv")
N4_CSV = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/tmp/n4_vocab.csv")
OUT = ROOT / "lib" / "assets" / "dictionary" / "jlpt.json"

KANA = {
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "o", "ん": "n",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
    "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
    "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
    "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
    "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
    "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
    "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
    "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
    "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
    "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
    "ワ": "wa", "ヲ": "o", "ン": "n",
}


def load_jmdict_meanings(path: Path) -> dict:
    """{书写/读音 -> 英文释义}（取首个含义，最多两个译文）。"""
    data = json.load(open(path, encoding="utf-8"))
    words = data["words"] if isinstance(data, dict) else data
    idx: dict[str, str] = {}

    def first_gloss(sense_list) -> str:
        out = []
        for s in sense_list:
            for g in s.get("gloss", []):
                t = g.get("text") if isinstance(g, dict) else str(g)
                if t and t not in out:
                    out.append(t)
                if len(out) >= 2:
                    return "；".join(out)
        return "；".join(out)

    for w in words:
        meaning = first_gloss(w.get("sense", []))
        if not meaning:
            continue
        for k in w.get("kana", []):
            t = k.get("text", "").strip()
            if t:
                idx.setdefault(t, meaning)
        for k in w.get("kanji", []):
            t = k.get("text", "").strip()
            if t:
                idx.setdefault(t, meaning)
    return idx


def read_tanos_csv(path: Path) -> list[tuple[str, str]]:
    out = []
    with open(path, encoding="utf-8") as f:
        for row in csv.reader(f):
            if not row or len(row) < 2:
                continue
            head, reading = row[0].strip(), row[1].strip()
            if head == "Kanji" or not head or not reading:
                continue
            out.append((head, reading))
    return out


def build():
    for p in (JMDICT, N5_CSV, N4_CSV):
        if not p.exists():
            sys.exit(f"未找到输入文件：{p}")
    meanings = load_jmdict_meanings(JMDICT)
    print(f"JMDict 释义索引：{len(meanings)} 条（kana+kanji）")

    entries, seen = [], set()
    for level, csv_path in (("5", N5_CSV), ("4", N4_CSV)):
        for head, reading in read_tanos_csv(csv_path):
            key = (head, reading)
            if key in seen:
                continue
            seen.add(key)
            # 释义：优先汉字书写，其次假名读音
            meaning = meanings.get(head) or meanings.get(reading) or ""
            entries.append({
                "headword": head,
                "reading": reading,
                "meaning": meaning,
                "level": level,
            })

    for kana, romaji in KANA.items():
        entries.append({"headword": kana, "reading": romaji,
                        "meaning": f"五十音：{kana} → {romaji}", "level": "kana"})

    entries.sort(key=lambda e: (e["level"], len(e["headword"]), e["headword"]))
    payload = {
        "version": "2026-09",
        "levels": ["5", "4", "kana"],
        "total": len(entries),
        "entries": entries,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    n5 = sum(1 for e in entries if e["level"] == "5")
    n4 = sum(1 for e in entries if e["level"] == "4")
    ka = sum(1 for e in entries if e["level"] == "kana")
    with_mean = sum(1 for e in entries if e["meaning"])
    print(f"写入 {OUT}")
    print(f"  共 {len(entries)} 条：N5 {n5} / N4 {n4} / 五十音 {ka}")
    print(f"  带释义：{with_mean}（{(with_mean * 100 // max(1, len(entries)))}%）")


if __name__ == "__main__":
    build()