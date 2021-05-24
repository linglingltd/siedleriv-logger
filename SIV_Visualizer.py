import csv
import numpy as np
import matplotlib.pyplot as plt
import math
import sys

#plt.style.use('dark_background')

csv.register_dialect('siv', delimiter='\t', quoting=csv.QUOTE_NONE)

n = 0

# Irgendwas mit Plot
if(len(sys.argv) < 2):
    print("NONONONONONONO! Chose file!!");
    datas = ["statlog_kevin_11-12-2020_18-09-31.csv"]
else:
    datas = [sys.argv[1]];

plots = [3,113,138]

fig, ax = plt.subplots(len(plots))
fig.set_size_inches(8, len(plots)*2+1)

plt.ylabel("")
plt.xlabel("")

i = 0
for data in datas:
    with open(data, encoding="utf8") as f:
        reader = csv.reader(f, 'siv')
        contents = list(reader)
    arr = np.array(contents[1:-1])
    numplayers = int(max(arr[1:,2]))
    for player in range(1,numplayers+1):  # Create plot for every player we want to know
        arrn = np.array(contents[player:-1:numplayers])
        for p in range(len(plots)):  # Plot each plot we want to know about
            ax[p].plot(np.float_(arrn[:,1])/12/numplayers, np.float_(arrn[:,plots[p]]), label="Player " + str(player))
    i += 1

i = 0
depth = len(contents)-3
print(depth)
for i in range(len(contents[0])-1):
    # if(arr[depth][i] != arr[0][i]):  # only show if there are changes to see
    print(str(i) + "\t" + contents[0][i])

for p in range(len(plots)):
    ax[p].set_ylabel(contents[0][plots[p]].replace(" - ", "\n"))
    ax[p].legend(loc="upper left");
    ax[p].grid(color='gray', linestyle="--")

    
plt.tight_layout(pad=0.5)
# Plot anzeigen
plt.savefig(datas[0].replace(".csv", ".png"), dpi=150)
# plt.show()
