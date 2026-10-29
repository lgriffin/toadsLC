# Testing in a 5-man dungeon

A run through the loot list, the whole pool at once (**Start all**) and trading the winners,
with five players in a dungeon instead of a 25-man raid. Allow about an hour: a normal or
heroic run plus a few minutes after each boss.

Everything here works in a party except one thing: the addon only records corpses on the
loot list **in a raid group**. In a party, turn that on with `/tlc loot party on` (step 3).
It records rare (blue) and up, because normal dungeon bosses rarely drop epics. Converting the
party to a raid instead doesn't help: TBC keeps raid groups out of 5-man dungeons.

## Who does what

| Player | Needs | Does |
| --- | --- | --- |
| **Leader** | party lead, the priority list imported | records the loot, starts items, awards, trades the winners |
| **Officer** | the priority list imported, named on its council | votes in the council frame |
| **Raider 1, 2** | the addon | answers with MS / OS / Pass |
| **Raider 3** (optional) | no addon, or the addon turned off | answers with `/roll` and `/roll 99` |

Write down which item went to whom as you go; you check the trades against it at the end.

## Before you zone in

1. **Everyone:** install the build you're testing, `/reload`, and check `/tlc status` says
   the same version on every client.
2. **Leader and Officer: import a list whose council is your party.** In a party there are
   no assistants, so the only council members are the session leader and the names on the
   list's `council`. The test list's council is Poohtank, Hadur, Anasazi and Gally; unless
   those are your characters, your officer can't vote. Open
   [fixtures/priority.test.json](../fixtures/priority.test.json), change
   `"council": [ ... ]` near the top to the Leader's and Officer's character names, then
   `/tlc import`, paste, **Import**. `/tlc status` should show about a thousand items.
   (Dungeon blues aren't on the test list, so they're ranked by roll only. That is fine for
   this test.)
3. **Leader:** `/tlc loot auto on` (in case it was ever turned off), then `/tlc loot party on`.
   The addon says it records party drops too, rare and up. `/tlc loot clear` empties
   anything left from a raid.
4. **Leader:** `/tlc begin <password>`; **Officer:** `/tlc join <password>`. The Officer is
   told the password matches. Optional, but it's how a raid night runs.
5. **Leader:** set the loot method to **Master Looter**, yourself as looter, threshold
   **Rare** (right-click your portrait, Loot Method). Then the blues stay on the corpse
   until you take them, nobody's Need roll takes them first, and you end up holding them
   to trade. Dungeon drops are soulbound, so they have to be traded within two hours of
   looting.

## After each boss: record the drops

6. **Leader:** open the corpse. Chat says *Added to the loot list: [item], ...*. Loot the
   items to yourself, close the window, and pull the next pack.
   - Opening the same corpse again adds nothing new.
   - Raiders and the Officer opening the corpse add nothing: only the leader records.
7. **Officer and raiders:** `/tlc loot`. You see the same list as the Leader, every row
   *waiting*. That shows the list reaches the party.
8. **Leader:** after two or three bosses, `/tlc loot announce`. Party chat gets the numbered
   list.

If nothing was added: check `/tlc loot party` is on (step 3), that you're party leader,
and that the drop was blue or better. `/tlc loot add [item]` puts an item on by hand, so
you can carry on and report it.

## One at a time

9. **Leader:** `/tlc loot 1` (or **Session** on row 1). Party chat announces it with a
   countdown; the row says *rolling*.
10. **Raiders 1 and 2:** the loot window pops up. One presses **MS**, the other **OS (99)**,
    and one of them adds a note. Each button press rolls for you.
11. **Raider 3** (no addon): types `/roll` in party chat before the countdown ends.
12. **Officer:** the council frame lists all three. Check the MS roll is ranked above the
    OS roll, then left-click a row to vote.
13. **Leader:** when the countdown ends, award (the vote leader, or **list says**). Party
    chat names the winner; on `/tlc loot` the row says *to Name*.
14. **Leader:** `/tlc undo`, then award to someone else with a reason, to check undo and
    an override. The row follows each change.
15. **Leader:** `/tlc loot roll 2` for a plain roll: no council frame this time, just
    `/roll` in chat and the winner posted when it closes. `/tlc award` records it.

## The whole pool at once

Have at least three items waiting. Loot another boss, or `/tlc loot add [item]` a few
things from your bags.

16. **Leader:** **Start all** on the loot list (or `/tlc loot all 120`). Party chat gets one
    warning and the numbered list; every waiting row says *rolling*.
17. **Raiders 1 and 2:** one loot window, a row per item. Answer each row differently (MS on
    one, OS on another, Pass on a third). Answered rows drop off; the window closes once
    everything is answered or the time runs out.
18. **Raider 3** (no addon): type `/roll` once. It should **not** count for any item while
    several are open (it can't tell which one it's for). Check the council frame.
19. **Officer:** step through the items with **<** and **>**. Each shows only the answers
    given for that item, with the right roll next to each name.
20. **Leader:** award each item on its own. Award at least two items to **the same raider**
    and one to someone else; you need that for the trade test.

## Handing out: trades

21. **Leader:** `/tlc trade`. It lists what you owe each winner, and flags anything not in
    your bags.
22. **Leader:** open a trade with the raider who won two items. Both go into the trade
    window by themselves. Check them against your notes, then both press **Trade**.
23. **Leader:** `/tlc trade` again: that raider is gone from the list. Opening another
    trade with them puts nothing in.
24. **Leader:** with the other winner, cancel the first trade, then trade again. The item
    goes in both times; it only counts as handed over once a trade completes.
25. **Leader:** `/reload`, then `/tlc trade`: what's still owed survives the reload.
26. **Leader:** `/tlc trade done <name>` for anyone you handed something to some other way,
    and `/tlc trade off` / `on` to check a trade stays empty while it's off.

## Officer reloads mid-run

27. **Officer:** `/reload` while an item is open, or between bosses. Within about 20 seconds
    `/tlc loot` shows the whole list again with its marks (the Leader sends it), and an open
    session comes back in the council frame.

## When you're done

28. **Leader:** `/tlc trade`, and `/tlc trade done <name>` for every winner still listed.
    Otherwise, for the next 12 hours, a trade with one of them puts the test item in by
    itself if it's still in your bags.
29. **Leader:** `/tlc loot party off`, `/tlc loot clear`, then `/tlc export clear` (or
    `/tlc export` first, if you want the JSON for the bug report). The test awards are real
    sessions as far as the addon knows; clearing them keeps them out of the next raid's
    export.
30. **Leader and Officer:** import the real priority list from the site again before the raid.

## Without a party: /tlc sim

`/tlc sim` runs in a party you lead (never in a raid group), with a fake raid of twelve
answering. Use it to warm up before the dungeon, or with fewer than five people:

- `/tlc sim drop`, two or three times, then **Start all** on `/tlc loot`: the fake raid
  answers every row, and the party's own buttons roll for real.
- Sim items are never shared, saved or traded: `/tlc trade` ignores them. The trade test
  needs real awards, as above.
- `/tlc sim stop` clears it.

## What to report

For anything that goes wrong: the step number, who saw it, and what chat said. `/tlc status`
from the Leader, and any Lua error (turn on **Display Lua Errors** under Interface > Help, or
use BugSack). Things not yet checked in the game, worth watching for:

- whether the corpse's boss name shows on the loot list rows (it relies on
  `GetLootSourceInfo`, which isn't confirmed on the TBC client),
- whether items go into the trade window on the first try (they're added 0.2 s apart),
- whether a soulbound dungeon drop can be traded at all after Master Looter gives it to you.
