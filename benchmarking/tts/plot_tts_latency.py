import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import re

from g4dn import *
from g5 import *
from g6 import *

# data_series = {
#     "Short (1-2 sentences)": latency_short_g5,
#     "Medium (3-7 sentences)": latency_medium_g5,
#     "Long (9-30 sentences)": latency_long_g5,
#     "All (1-30 sentences)": latency_all_g5,
# }

data_series = {
    "g4dn / T4": latency_medium_g4dn,
    "g5 / A10G": latency_medium_g5,
    "g6 / L4": latency_medium_g6,
}

def parse_data(data_series):
    results = {}
    for data in data_series:
        vus = []
        min_values = []
        avg_values = []
        p95_values = []
        lines = data_series[data].strip().split("\n")
        for line in lines:
            match = re.search(r'scenario_latency_(\d\d)VU..........: avg=(\d+\.\d+)\s+min=(\d+\.\d+)\s+med=\d+\.\d+\s+max=\d+\.\d+\s+p\(90\)=\d+\.\d+\s+p\(95\)=(\d+\.\d+)', line)
            if match:
                vus.append(int(match.group(1)))
                avg_values.append(float(match.group(2)))
                min_values.append(float(match.group(3)))
                p95_values.append(float(match.group(4)))
        results[data] = {'vus': vus, 'min': min_values, 'avg': avg_values, 'p95': p95_values}
    return results

parsed_data = parse_data(data_series)

colors = ['red', 'blue', 'green', 'c']

for i, key in enumerate(parsed_data.keys()):
    vus = parsed_data[key]['vus']
    min_values = parsed_data[key]['min']
    avg_values = parsed_data[key]['avg']
    p95_values = parsed_data[key]['p95']
    plt.plot(vus, min_values, marker='o', linestyle=':', color=colors[i % len(colors)], label=key + ': min')
    plt.plot(vus, avg_values, marker='v', linestyle='-', color=colors[i % len(colors)], label=key + ': avg')
    plt.plot(vus, p95_values, marker='s', linestyle='--', color=colors[i % len(colors)], label=key + ': p95')

# Optional horizontal line at 200 ms
plt.axhline(y=200, color='black')
plt.axhline(y=300, color='black')
plt.axhline(y=400, color='black')
plt.axhline(y=500, color='black')

# Set minimum y-axis to 0
plt.ylim(bottom=0)

# x-axis whole numbers only
plt.gca().xaxis.set_major_locator(ticker.MaxNLocator(integer=True))

plt.xlabel('Number of Concurrent Requests', fontsize = 14)
plt.ylabel('Latency (Milliseconds)', fontsize = 14)
plt.title('TTS Latency by Request Concurrency and GPU - medium inputs (3-7 sentences)', fontsize = 16) #  - G6 instance (L4 GPU) G5 instance (A10 GPU)
plt.legend()

# Place and title the legend
plt.legend(bbox_to_anchor=(0.15, 0.5), title='Instance / GPU: metric') # Input text length: metric

# Change the y-axis format
# plt.gca().yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, pos: '{:,.2f}'.format(x)))

plt.show()
