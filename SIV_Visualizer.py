import csv
import datetime
import numpy as np
import matplotlib.pyplot as plt
import math
import sys
from matplotlib.ticker import StrMethodFormatter

darkmode = False
plots = []
''' 
    Kombination von mehreren Werten in einem Plot:
    [["Name des neuen Graphen"], [liste aller zu kombinierenden Werte]]
    z.B.: 
    ["Militärgebäude Aktuell", [97,98,99]]   
    Kombiniert kl. Türme, mt. Türme und Burgen aktuell zu "Militärgebäude aktuell"
'''
plots = [4,     # Anzahl freier Siedler aktuell
         218,   # insgesamt besiegte Einheiten
         ["Militärgebäude Aktuell", [97,98,99]],
         ["Krieger Aktuell", [7,8,9,10,11,12,13,14,15,16,17,18,19,20,21]],
         ["Nahrung Aktuell", [116,118,131]],
         ["Nahrung Gesamt", [159,161,174]]
        ]
if darkmode == True:
    plt.style.use('dark_background')

csv.register_dialect('siv', delimiter=';', quoting=csv.QUOTE_NONE)

# Irgendwas mit Plot
if(len(sys.argv) < 2):
    print("NONONONONONONO! Chose file!!");
    data = "statlog_kevin_20-01-2021_00-27-06.csv"
else:
    data = sys.argv[1];

playerLines = [["Names", 0],
                ["Races", 1],
                ["Colors", 2],
                ["Teams", 3]]

playerData = {}

with open(data, encoding="utf8") as f:
    reader = csv.reader(f, 'siv')
    contents = list(reader)

numPlayers = int(contents[0][1])
playerBlock = np.array(contents[1:1+numPlayers])
mapName = contents[0][0]
for el in playerLines:
    playerData[el[0]] = playerBlock[:,el[1]]
arr = np.array(contents[2+numPlayers:])

i = 0
for el in contents[numPlayers+1]:
    print(str(i) + "\t" + el)
    i += 1

playerData["Display"] = []
for player in range(0,numPlayers):
    playerData["Display"] += [playerData["Teams"][player] + " (" + playerData["Races"][player][0] + ") " + playerData["Names"][player]]

# White color from game can not be seen in white Graph - make graphs grey(t) again!
playerData["Colors"] = ["#CACACA" if x == "E6FFFF" and not darkmode == True else "#"+x for x in playerData["Colors"]]

if len(plots) == 0:
    for i in range(3, len(contents[1+numPlayers])-1):
        if(min(arr[:,i]) != max(arr[:,i])):
            plots += [i]

for line in range(0, len(arr)):
    arr[line][1] = (datetime.datetime.strptime(arr[line][0], "%H:%M:%S") - datetime.datetime(1900, 1, 1)).total_seconds()/60
maxTime = math.ceil(float(arr[-1,1]))

# Init Plot-Stuff
y = math.ceil(math.sqrt(len(plots)/8))
x = math.ceil(len(plots) / y)

fig, ax = plt.subplots(x,y)
fig.set_size_inches(8*y, x*2.5+1)

plt.ylabel("")
plt.xlabel("")

for player in range(0,numPlayers):  # Create plot for every player we want to know
    arrn = np.array(arr[player::numPlayers])
    for p in range(len(plots)):  # Plot each plot we want to know about
        graphy = math.floor(p%y)
        graphx = math.floor(p/y)
        graph = 0
        if y > 1:
            graph = ax[graphx][graphy]
        else:
            graph = ax[graphx]
        if isinstance(plots[p], list):
            val = np.float_(arrn[:,plots[p][1][0]])
            for el in range(1, len(plots[p][1])):
                val += np.float_(arrn[:,plots[p][1][el]])
            graph.plot(np.float_(arrn[:,1]), val, color=playerData["Colors"][player], label=playerData["Display"][player])
        else:
            graph.plot(np.float_(arrn[:,1]), np.float_(arrn[:,plots[p]]), color=playerData["Colors"][player], label=playerData["Display"][player])

for p in range(len(plots)):
    graphy = math.floor(p%y)
    graphx = math.floor(p/y)
    graph = 0
    if y > 1:
        graph = ax[graphx][graphy]
    else:
        graph = ax[graphx]

    if isinstance(plots[p], list):
        graph.set_ylabel(plots[p][0])
    else:
        graph.set_ylabel(contents[1+numPlayers][plots[p]].replace(" - ", "\n"))
    graph.legend(loc="upper left");
    graph.set_xlim(0, maxTime)
    graph.xaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))
    graph.yaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))
    graph.grid(linestyle="--", color="darkgray")

# Set title of graph depending on winner
heading = mapName + " (" + arr[-1,0] + "h)"
# Ermittle ob/wann ein Gewinner bekannt ist/war
teams = [int(playerData["Teams"][x]) for x in range(numPlayers)]
romans = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
i = 0
for el in arr:
    if(teams[i] > 0):
        if(int(el[3]) == 0):
            teams[i] = 0
            t = 0
            for t in teams:
                if(t == 0 and t != int(el[3])):
                    t = int(el[3])
                elif(t != int(el[3])):
                    # At least two teams alive!
                    continue
                else:
                    # Only one team is alife
                    heading = mapName + " (Team " + romans[max(teams)-1] + " hat gewonnen, " + el[0] + "h)"
                    break
    i = (i+1) % numPlayers

if y > 1:
    ax[0][0].set_title(heading)
else:
    ax[0].set_title(heading)
    
plt.tight_layout(pad=0.5)
plt.savefig(data.replace(".csv", ".png"), dpi=150)
