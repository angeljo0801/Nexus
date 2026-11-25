#!/usr/bin/env python3
"""Prepare private Origen AI conversation data for external LoRA SFT.

Standard library only. Never uploads or opens network connections.
"""
import argparse
import json
import random
import re
from pathlib import Path


def read_rows(path: Path):
    seen = set()
    with path.open(encoding="utf-8") as file:
        for num, line in enumerate(file, start=1):
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
                msgs = obj["messages"]
                assert isinstance(msgs, list) and len(msgs) == 2
                assert msgs[0]["role"] == "user" and msgs[1]["role"] == "assistant"
                q, a = (m["content"].strip() for m in msgs)
                assert q and a and len(q) <= 3500 and len(a) <= 3500
                key = (re.sub(r"\s+", " ", q).casefold(), re.sub(r"\s+", " ", a).casefold())
                if key in seen:
                    continue
                seen.add(key)
                yield {"messages": [{"role": "user", "content": q},
                                    {"role": "assistant", "content": a}]}
            except (AssertionError, KeyError, ValueError, TypeError, AttributeError) as exc:
                raise ValueError(f"Ejemplo inválido en línea {num}") from exc


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dataset", type=Path)
    ap.add_argument("--output-dir", type=Path, default=Path("origen-lora-dataset"))
    ap.add_argument("--validation", type=float, default=0.15, help="Fracción de validación (0.05 a 0.4)")
    ap.add_argument("--seed", type=int, default=3407)
    args = ap.parse_args()
    if not 0.05 <= args.validation <= 0.4:
        ap.error("--validation debe estar entre 0.05 y 0.4")
    rows = list(read_rows(args.dataset))
    if len(rows) < 10:
        ap.error("Se requieren al menos 10 conversaciones válidas y únicas")
    random.Random(args.seed).shuffle(rows)
    val_count = max(1, round(len(rows) * args.validation))
    splits = {"validation.jsonl": rows[:val_count], "train.jsonl": rows[val_count:]}
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, data in splits.items():
        with (args.output_dir / name).open("w", encoding="utf-8") as output:
            for item in data:
                output.write(json.dumps(item, ensure_ascii=False) + "\n")
    print(f"Ejemplos únicos: {len(rows)}; entrenar: {len(splits['train.jsonl'])}; "
          f"evaluación retenida: {len(splits['validation.jsonl'])}")
    print("Solo se prepararon datos locales; no se modificaron pesos neuronales.")


if __name__ == "__main__":
    main()
