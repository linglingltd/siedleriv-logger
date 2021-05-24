import csv
import datetime
import numpy as np
import matplotlib.pyplot as plt
import math
import sys
from matplotlib.ticker import StrMethodFormatter

# plt.style.use('dark_background')

csv.register_dialect('siv', delimiter='\t', quoting=csv.QUOTE_NONE)

n = 0

# Irgendwas mit Plot
if(len(sys.argv) < 2):
    print("NONONONONONONO! Chose file!!");
    exit()
else:
    data = sys.argv[1];

plots = [3,217,["Militärgebäude Aktuell", [96,97,98]],["Krieger Aktuell", [6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]],["Nahrung Aktuell", [115,117,130]],["Nahrung Gesamt", [158,160,173]]]

fig, ax = plt.subplots(len(plots))
fig.set_size_inches(8, len(plots)*2.5+1)

plt.ylabel("")
plt.xlabel("")

#plt.ylim(-60, 0)
with open(data, encoding="utf8") as f:
    reader = csv.reader(f, 'siv')
    contents = list(reader)
arr = np.array(contents[2:])
numplayers = int(max(arr[1:,2]))
playerNames = np.array(contents[0])
numPlayers = int(playerNames[1])
mapName = playerNames[0]

for line in range(0, len(arr)):
    arr[line][1] = (datetime.datetime.strptime(arr[line][0], "%H:%M:%S") - datetime.datetime(1900, 1, 1)).total_seconds()/60
maxTime = math.ceil(float(arr[-1,1]))

for player in range(1,numPlayers+1):  # Create plot for every player we want to know
    arrn = np.array(arr[player-1::numPlayers])
    for p in range(len(plots)):  # Plot each plot we want to know about
        if isinstance(plots[p], list):
            val = np.float_(arrn[:,plots[p][1][0]])
            for el in range(1, len(plots[p][1])):
                val += np.float_(arrn[:,plots[p][1][el]])
            ax[p].plot(np.float_(arrn[:,1]), val, label=playerNames[player+1])
        else:
            ax[p].plot(np.float_(arrn[:,1]), np.float_(arrn[:,plots[p]]), label=playerNames[player+1])

depth = len(contents)-3

for p in range(len(plots)):
    if isinstance(plots[p], list):
        ax[p].set_ylabel(plots[p][0])
    else:
        ax[p].set_ylabel(contents[1][plots[p]].replace(" - ", "\n"))
    ax[p].legend(loc="upper left");
    ax[p].set_xlim(0, maxTime)
    ax[p].xaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))
    ax[p].yaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))
    ax[p].grid(linestyle="--", color="darkgray")

ax[0].set_title(mapName + " (" + arr[-1,0] + "h)")
plt.tight_layout(pad=0.5)
# Plot anzeigen
plt.savefig(data.replace(".csv", ".png"), dpi=150)
# plt.show()
