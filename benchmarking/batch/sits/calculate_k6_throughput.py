from collections import Counter
import os
import re

filename = os.getenv('OUTPUT_FILE')
ASSUMED_AUDIO_DURATION_SECS = int(re.search(r'-(\d+)m-', filename).group(1)) * 60

with open(filename, 'r') as f:
    file_data = f.read()
in_data = file_data.split("count_")[-1]

concurrency_regex = r"concurrent_([0-9]+).*VUs[ ]+([0-9]*m)?([0-9\.]+)s/.* ([0-9]+)/[0-9]+ shared iters"

matches = re.findall(concurrency_regex, in_data)

speedups = []

for m in matches:
    num_concurrent, mins, secs, iters = [float(i.strip("m")) if i else 0. for i in m]
    duration_secs = mins * 60 + secs
    speedup = round(ASSUMED_AUDIO_DURATION_SECS * iters / duration_secs)
    print(f"{num_concurrent}: {ASSUMED_AUDIO_DURATION_SECS} * {iters} / {duration_secs} = {speedup}")
    speedups.append(speedup)

# Find highest value that appears at least twice when rounded down to nearest 5
rounded = [value - (value % 5) for value in speedups]
counts = Counter(rounded)
stable_values = [value for value, count in counts.items() if count >= 2]
stable_max = max(stable_values) if stable_values else 0
print(f"Stable maximum speedup: {stable_max}")
