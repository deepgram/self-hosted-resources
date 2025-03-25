import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import re
import numpy as np

from g4dn import *
from g5 import *
from g6 import *

# data_series = {
#     "Short (1-2 sentences)": throughput_short,
#     "Medium (3-7 sentences)": throughput_medium,
#     "Long (9-30 sentences)": throughput_long,
#     "All (1-30 sentences)": throughput_all,
# }

data_series = {
    "g4dn / T4: short input (1-2 sentences)": throughput_short_g4dn,
    "g4dn / T4: medium input (3-7 sentences)": throughput_medium_g4dn,
    "g4dn / T4: long input (9-30 sentences)": throughput_long_g4dn,
    "g5 / A10G: short input (1-2 sentences)": throughput_short_g5,
    "g5 / A10G: medium input (3-7 sentences)": throughput_medium_g5,
    "g5 / A10G: long input (9-30 sentences)": throughput_long_g5,
    "g6 / L4: short input (1-2 sentences)": throughput_short_g6,
    "g6 / L4: medium input (3-7 sentences)": throughput_medium_g6,
    "g6 / L4: long input (9-30 sentences)": throughput_long_g6,
}

def parse_data(data_series):
    results = {}
    for series_name in data_series.keys():
        data = data_series[series_name]
        vus = []
        cps = []
        lines = data.strip().split("\n")
        for line in lines:
            match = re.search(r'scenario_characters_(\d\d)VU.*: (\d+)', line)
            if match:
                vus.append(int(match.group(1)))
                cps.append(int(match.group(2)))
        results[series_name] = (vus, cps)
    return results

parsed_data = parse_data(data_series)

colors = ['red', 'blue', 'green', 'c', 'm', 'y', 'k']

colors_by_instance = {
    'g4dn': 'red',
    'g5': 'blue',
    'g6': 'green',
}

for i, key in enumerate(parsed_data.keys()):
    vus, cps = parsed_data[key]
    color = colors_by_instance[key.split()[0]]
    linestyle = ':'
    marker = 'o'
    if 'short' in key:
        linestyle = ':'
        marker = 'o'
    elif 'medium' in key:
        linestyle = '-'
        marker = 'v'
    elif 'long' in key:
        linestyle = '--'
        marker = 's'
    # plt.plot(vus, cps, marker='o', linestyle='-', color=colors[i % len(colors)], label=key)
    plt.plot(vus, cps, marker=marker, linestyle=linestyle, color=color, label=key)

plt.xlabel('Number of Concurrent Requests', fontsize = 14)
plt.ylabel('Throughput (Characters per Second)', fontsize = 14)
plt.title('TTS Throughput by Request Concurrency, GPU, and Input Length', fontsize = 16)
plt.legend()

# Place and title the legend
plt.legend(bbox_to_anchor=(0.65, 0.25), title='Instance / GPU: input length', fontsize=8) # Input Text Length

plt.xticks(range(1, 33))

# Change the y-axis format
# plt.gca().yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, pos: '{:,.0f}K'.format(x*1e-3)))

plt.show()
