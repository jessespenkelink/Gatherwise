# CurseForge texts for Gatherwise: Nodes & Routes

Copy these into the CurseForge project page. Project name: **Gatherwise: Nodes & Routes**
(the addon is called "Gatherwise" in game; its folder is `GatherwiseForever`).

## Summary (one line, shown in search results)

Mining and herb nodes on your map and minimap, filtered by your skill, with the shortest gathering route and a guide arrow.

## Description (project page, Markdown)

---

**Gatherwise** shows every mining vein and herb on your world map and minimap, only the ones you can actually gather, and walks you past them in the shortest loop through your zone.

Built for **World of Warcraft: Forever**. Not related to the GatherWise addon for TBC Classic.

### What it does

- **17,000+ known spawn points** for every vein and herb, from Copper Vein to Black Lotus. Every node you gather yourself is added as well.
- **Only what's relevant to you.** Nodes above your Mining or Herbalism skill are hidden. Optionally, grey nodes (no skill points any more) are hidden too.
- **World map and minimap icons,** with on/off switches in the world map's filter menu (the funnel at the top right).
- **One key for a route.** Press **Alt+R** and Gatherwise plans the shortest loop past every node you can gather in your zone. Where it can, the loop avoids climbing up and down hills.
- **A guide arrow** at the top of your screen points to the next node and shows the distance. It moves on by itself when you arrive or gather. When a stop on the route is much closer than the next one, it goes there first.

### Made to work with Find Minerals and Find Herbs

- Spawn points turn into **faint rings**, so Blizzard's yellow dots stand out.
- **Hover a yellow dot** on your minimap and the route goes there first if it's close.
- **No dot at the target?** Hover the target ring, or press **Alt+S**, and the route moves on.
- Visited and empty spots are skipped for 10 minutes on later laps.
- **Optional close-range detection** uses the game's soft-targeting to recognise a node right in front of you, and lets you gather it with your Interact key.

### Commands

- `/gw`: settings
- `/gw route`: start or stop routing (default key **Alt+R**)
- `/gw skip`: skip the current node (default key **Alt+S**)
- `/gw mine`, `/gw herb`: show or hide mining nodes or herbs
- `/gw stats`: how many nodes are known

You can change the keys in *Esc > Options > Keybindings > AddOns > Gatherwise*.

### Good to know

- The game doesn't tell addons where the yellow Find Minerals / Find Herbs dots are. Gatherwise only learns about a dot when you hover it on the minimap.
- Spawn points are places where a node *can* appear. Nodes move between them, so not every spot has one at any moment.
- The arrow points in a straight line. It doesn't know about walls and cliffs.
- Gatherwise only shows information. You still walk and gather everything yourself.

### Credits

Spawn point data is generated from the [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0). Gatherwise is free and open source under the GPL-3.0 licence: [source on GitHub](https://github.com/jessespenkelink/Gatherwise). Bug reports and ideas are welcome there.
