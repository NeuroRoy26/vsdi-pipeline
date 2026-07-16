#!/usr/bin/env python3
"""
BLK Log Parser Utility

Standalone script to parse BLK acquisition logs and generate
structured JSON metadata for each trial (reference + signal).

Usage:
  python blk_log_parser.py --log_file "converted__1000/log_E0.txt" --output "converted__1000/log_E0.json"
  python blk_log_parser.py --log_file "converted__500/log_E0.txt" --output "converted__500/log_E0.json"
"""
import re
import json
from datetime import datetime
from pathlib import Path
import argparse


def parse_log_file(log_path: Path):
    # Read and clean lines
    with log_path.open('r', encoding='utf-8', errors='ignore') as f:
        raw = [l.strip() for l in f if l.strip()]

    # Patterns
    patterns = {
        'timestamp': re.compile(r"^(\d{2}:\d{2}:\d{2}):"),
        'block': re.compile(r"Block No\.=\s*(\d+)"),
        'trial': re.compile(r"Trial No\.=\s*(\d+)"),
        'stim': re.compile(r"Stim ID\s*=\s*(\d+)"),
        'frames': re.compile(r"Stim took (\d+(?:\.\d+)?) (?:mSecs|Secs) \((\d+) frames grabbed\)"),
        'rate': re.compile(r"Frame rate of (\d+\.?\d*) frames/sec"),
        'write': re.compile(r"Writing stim \((\d+\.?\d*) MPixels\) to block file .+?/(.+?\.BLK)"),
        'perf': re.compile(r"Wrote (\d+\.?\d*) MBytes in (\d+\.?\d*) Secs"),
        'summary': re.compile(r"Number of (\w+) (\w+)\s*=\s*(\d+)")
    }

    sessions = []
    summary = {}
    current = {}

    for line in raw:
        # start new session on Block
        m = patterns['block'].search(line)
        if m:
            # save previous
            if current:
                sessions.append(current)
            current = {'block': int(m.group(1))}
            continue

        if not current:
            # collecting summary
            m = patterns['summary'].search(line)
            if m:
                key = f"{m.group(2).lower()}_{m.group(1).lower()}"
                summary[key] = int(m.group(3))
            continue

        # within session
        if 'trial' not in current:
            m = patterns['trial'].search(line)
            if m:
                current['trial'] = int(m.group(1))
            continue

        if 'stim' not in current:
            m = patterns['stim'].search(line)
            if m:
                current['stim'] = int(m.group(1))
            continue

        if 'frames' not in current:
            m = patterns['frames'].search(line)
            if m:
                dur = float(m.group(1))
                if 'mSecs' in line:
                    dur /= 1000.0
                current['duration_s'] = dur
                current['frames'] = int(m.group(2))
            continue

        if 'rate' not in current:
            m = patterns['rate'].search(line)
            if m:
                current['fps'] = float(m.group(1))
            continue

        if 'filename' not in current:
            m = patterns['write'].search(line)
            if m:
                current['megapixels'] = float(m.group(1))
                current['filename'] = m.group(2)
            continue

        if 'size_mb' not in current:
            m = patterns['perf'].search(line)
            if m:
                current['size_mb'] = float(m.group(1))
                current['write_s'] = float(m.group(2))
            continue

    # append last
    if current:
        sessions.append(current)

    # group by block into trials
    trials = {}
    for sess in sessions:
        b = sess['block']
        trials.setdefault(b, {})[sess['stim']] = sess

    return {'parsed_at': datetime.now().isoformat(), 'trials': trials, 'summary': summary}


def main():
    p = argparse.ArgumentParser(description="Parse BLK log into trial metadata JSON")
    p.add_argument('--log_file', required=True, help='Path to BLK log file')
    p.add_argument('--output', required=True, help='Output JSON metadata file')
    args = p.parse_args()

    log_path = Path(args.log_file)
    out_path = Path(args.output)

    if not log_path.exists():
        print(f"Error: log file {log_path} not found.")
        return 1

    meta = parse_log_file(log_path)
    with out_path.open('w') as f:
        json.dump(meta, f, indent=2)
    print(f"Metadata written to {out_path}")
    return 0


if __name__ == '__main__':
    exit(main())
