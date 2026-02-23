"""Run from the Python razdel repo root: python bench/bench_python.py"""

import time
from razdel import sentenize, tokenize

with open("razdel/tests/data/sents.txt") as f:
    sent_lines = [l.rstrip("\n") for l in f if l.strip()]
with open("razdel/tests/data/tokens.txt") as f:
    tok_lines = [l.rstrip("\n") for l in f if l.strip()]

sent_texts = ["".join(l.split("|")) for l in sent_lines]
tok_texts = ["".join(l.split("|")) for l in tok_lines]

print(f"Loaded {len(sent_texts)} sentence texts, {len(tok_texts)} token texts\n")

for t in sent_texts[:100]:
    list(sentenize(t))
for t in tok_texts[:100]:
    list(tokenize(t))

for run in range(1, 4):
    start = time.perf_counter()
    for t in sent_texts:
        list(sentenize(t))
    st = time.perf_counter() - start

    start = time.perf_counter()
    for t in tok_texts:
        list(tokenize(t))
    tt = time.perf_counter() - start

    print(
        f"Run {run}: sentenize {st:.3f}s ({len(sent_texts)/st:.0f}/s) | tokenize {tt:.3f}s ({len(tok_texts)/tt:.0f}/s)"
    )
