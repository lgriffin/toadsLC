# Testing in a 5-man dungeon

A run through the loot list, drops opening for answers as they're looted, the council's vote and trading the winners,
with five players in a dungeon instead of a 25-man raid. Allow about an hour: a normal or
heroic run plus a few minutes after each boss.

Everything here works in a party except one thing: the addon only records corpses on the
loot list **in a raid group**. In a party, turn that on with `/tlc loot party on` (step 3).
It records rare (blue) and up, because normal dungeon bosses rarely drop epics. Converting the
party to a raid instead doesn't help: TBC keeps raid groups out of 5-man dungeons.

## Who does what

| Player | Needs | Does |
| --- | --- | --- |
| **Leader** | party lead, the priority list imported, begins the raid | records the loot, awards, trades the winners |
| **Officer** | the priority list imported, joined with the password | votes in the item's live poll |
| **Raider 1, 2, 3** | the addon | answers with BiS / Main / OS / Pass in `/tlc loot` |

Write down which item went to whom as you go; you check the trades against it at the end.

## Before you zone in

1. **Everyone:** install the build you're testing, `/reload`, and check `/tlc status` says
   the same version on every client.
2. **Leader and Officer:** import [fixtures/priority.test.json](../fixtures/priority.test.json)
   (`/tlc import`, paste, **Import**). `/tlc status` should show about a thousand items.
   Dungeon blues aren't on the test list, so everyone on main spec ties and the council picks.
   That is fine for this test. You don't need to edit the list's `council`: joining with the
   raid password (step 4) puts the Officer on the council.
3. **Leader:** `/tlc loot auto on` (in case it was ever turned off), then `/tlc loot party on`.
   The addon says it records party drops too, rare and up. `/tlc loot clear` empties
   anything left from a raid.
4. **Leader:** `/tlc begin <password>`; **Officer:** `/tlc join <password>`. The Officer is
   told the password matches. This is what makes the Officer council, so don't skip it.
5. **Leader:** set the loot method to **Master Looter**, yourself as looter, threshold
   **Rare** (right-click your portrait, Loot Method). The council's items then come straight
   into your bags when you open the corpse (chat says *Looted for the council: ...*), so you
   end up holding them to trade. Dungeon drops are soulbound, so they have to be traded within two hours of
   looting.

## After each boss: record the drops

6. **Leader:** open the corpse. Chat says *Added to the loot list: [item], ...* and *Looted for
   the council: ...*, and party chat gets *Open for answers: [item] ...*. Close the window and
   pull the next pack.
   - Opening the same corpse again adds nothing new.
   - Raiders and the Officer opening the corpse add nothing: only the leader records.
   - Raiders can't open, reset or remove items from `/tlc loot`: check one tries.
7. **Raiders:** the small answer window pops up (if you're in combat, only once it ends).
   Between pulls, type `/tlc loot`: each item has BiS / Main / OS / Pass. Answer each one
   differently (BiS, Main, OS, Pass). Pass prints a line in chat. Press **Change** on one and
   pick another answer.
8. **Officer:** `/tlc loot`, then click an item. The live poll lists every raider who answered,
   main spec and BiS first, and on the Loot page the status reads *taking answers: x of y*,
   the same as the Leader's. Click a name to vote; the Leader sees your name beside it. Hover
   the item: the tooltip shows the votes.

If nothing was added: check `/tlc loot party` is on (step 3), that you're party leader,
and that the drop was blue or better. `/tlc loot add [item]` puts an item on by hand, so
you can carry on and report it.

## Award

9. **Leader:** after a boss or two, open an item from the Loot page and vote too. The status
   reads *council deciding*. Press **Award** on the winner's row. Party chat names the winner;
   the row and the Officer's row both say *awarded to Name*, and hovering the item shows who
   it went to.
10. **Officer:** try to award: you can't, only the Leader can.
11. **Leader:** right-click the awarded row and **Reset…**: it goes back to *waiting to open*.
    Open and award it again, this time to someone the list doesn't pick, with a reason.
12. **Leader:** award at least two items to **the same raider** and one to someone else; you
    need that for the trade test.

## Handing out: trades

13. **Leader:** `/tlc trade`. It lists what you owe each winner, and flags anything not in
    your bags.
14. **Leader:** open a trade with the raider who won two items. Both go into the trade
    window by themselves. Check them against your notes, then both press **Trade**.
15. **Leader:** `/tlc trade` again: that raider is gone from the list. Opening another
    trade with them puts nothing in.
16. **Leader:** with the other winner, cancel the first trade, then trade again. The item
    goes in both times; it only counts as handed over once a trade completes.
17. **Leader:** `/reload`, then `/tlc trade`: what's still owed survives the reload.
18. **Leader:** `/tlc trade done <name>` for anyone you handed something to some other way,
    and `/tlc trade off` / `on` to check a trade stays empty while it's off.

## Officer reloads mid-run

19. **Officer and a raider:** `/reload` while an item is open. Within about 20 seconds
    `/tlc loot` shows the whole list again with its statuses (the Leader sends it). The
    raider's answer is still there and they aren't asked again.

## When you're done

20. **Leader:** `/tlc trade`, and `/tlc trade done <name>` for every winner still listed.
    Otherwise, for the next 12 hours, a trade with one of them puts the test item in by
    itself if it's still in your bags.
21. **Leader:** `/tlc loot party off`, `/tlc loot clear`, then `/tlc export clear` (or
    `/tlc export` first, if you want the JSON for the bug report). The test awards are real
    sessions as far as the addon knows; clearing them keeps them out of the next raid's
    export.
22. **Leader and Officer:** import the real priority list from the site again before the raid.

## Without a party: /tlc sim

`/tlc sim` runs in a party you lead (never in a raid group), with a fake raid of twelve
answering. Use it to warm up before the dungeon, or with fewer than five people:

- `/tlc sim drop`, two or three times, then **Open all** on the Loot page: the fake raid
  answers every row, and the party answers for real.
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
