#!/usr/bin/env python3
"""Summarize PRIVATE decoded perf data using symbols only, never addresses."""
import argparse
from collections import Counter
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from checklag_native import sample_stacks

def summarize(path):
    leaf, inclusive, paths = Counter(), Counter(), Counter()
    samples = 0
    with Path(path).open() as stream:
        for _, stack in sample_stacks(stream):
            if not stack:
                continue
            samples += 1
            leaf[stack[0]] += 1
            inclusive.update(set(stack))
            if any('MakePageWritable' in symbol for symbol in stack):
                paths[stack[:24]] += 1
    return {'samples': samples,
            'leaf': leaf.most_common(15),
            'inclusive': inclusive.most_common(35),
            'page_write_stacks': [{'count': n, 'stack': s} for s, n in paths.most_common(5)]}

if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('decoded_private_file')
    args = parser.parse_args()
    print(json.dumps(summarize(args.decoded_private_file), indent=2))
