# Toads LC

Loot council for the Toads raid on Spineshatter EU (TBC Classic).

Toads LC puts the guild's agreed class priorities on item tooltips and hands out loot **by
priority tier first, roll second**. Raiders answer each drop with MS (main spec), OS (off-spec) or Pass;
officers see everyone ranked in a council frame and vote; the raid leader awards. Every roll,
vote and award is kept, and exported after the raid for the Toads site.

This guide is for players and officers. If you want to change the addon itself, see
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

- [Install](#install)
- [What raiders do](#what-raiders-do)
- [Raid night for the leader and officers](#raid-night-for-the-leader-and-officers)
- [The raid password](#the-raid-password)
- [Practice with /tlc sim](#practice-with-tlc-sim)
- [How the winner is decided](#how-the-winner-is-decided)
- [All commands](#all-commands)
- [Troubleshooting](#troubleshooting)

## Install

1. Download `ToadsLC-<version>.zip` from the
   [Releases page](https://github.com/lgriffin/toadsLC/releases) (an officer can also give it
   to you).
2. Close World of Warcraft, or at least log out to the character screen.
3. Unzip it into your TBC Classic AddOns folder. On Windows that is usually
   `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\`
   (older installs use `_classic_` instead of `_anniversary_`).
4. Check the folder looks like this. The `ToadsLC` folder must sit directly in `AddOns`,
   with `ToadsLC.toc` inside it:

   ```
   Interface/
     AddOns/
       ToadsLC/
         ToadsLC.toc
         Init.lua
         core/ ...
         adapters/ ...
         data/ ...
   ```

5. Start the game. On the character screen, open **AddOns** and make sure **Toads LC** is
   ticked. In game, `/tlc help` lists the commands.

Do not use GitHub's green **Code > Download ZIP** button: that zip is the developer source,
and its folder is named `toadsLC-main`, which the game will not load. Use the release zip.

To update, delete the old `ToadsLC` folder and unzip the new one in its place. Your settings,
imported priorities and unexported loot records are kept (they live in the game's
SavedVariables, not in the addon folder).

Toads LC runs alongside Gargul, RCLootCouncil and other loot addons; each adds its own
tooltip lines. It only loads on the TBC Classic client.

## What raiders do

Everyone in the raid should have the addon installed, but only the leader and officers need
to do anything beyond answering loot.

- **Hover any raid item** to see the **Priority (Toads LC)** block on its tooltip: each
  priority tier in class colours, with your own tier marked `>`. This works in bags, on the
  loot window, on chat links and on comparison tooltips. `/tlc tooltip off` hides it.
- **When the raid leader opens a loot session,** a small window pops up with the item, your
  tier (or "Your spec is not on the list for this item") and a countdown. When the leader opens
  the whole loot pool at once, the window has a row per item: answer each one. Type an
  optional note for the council (it goes with your next answer), then press:
  - **MS** (main spec): rolls 1-100 for you.
  - **OS (99)** (off-spec): rolls 1-99 for you.
  - **Pass**: you are out for this item.
- **No addon, or you closed the window?** Just `/roll` for main spec or `/roll 99` for
  off-spec while the countdown runs. The leader's addon reads the roll from chat. This only works
  while a single item is open: with several open at once, answer in the window.
- **For a plain roll** (`/tlc roll`, used for less contested items) there is no window: the
  leader announces the item in raid chat, you `/roll` or `/roll 99`, and the result is posted
  when the timer ends.

Only your first roll counts. Rolls outside 1-100 or 1-99 are ignored.

## Raid night for the leader and officers

### Before the raid

1. On the Toads site, export the priority list (the `toads-loot-priority` JSON).
2. In game, every officer and the raid leader types `/tlc import`, pastes the JSON into the
   box (Ctrl+V) and presses **Import**.
3. `/tlc status` should show the item count and the list's date. If the import was a
   mistake, `/tlc import undo` puts the previous list back.
4. Set the raid password (below): the leader types `/tlc begin <password>`, each officer
   `/tlc join <password>`.

Raiders don't need to import anything; the tooltip only shows on clients that have the list,
but the loot window works for everyone.

### Loot now, hand out later: the loot list

You don't have to stop after every boss. When the raid leader or an assistant opens a corpse
in a raid (as master looter, say), Toads LC puts its drops on the **loot list**: everything
epic and up, plus anything on the priority list, but not Badges of Justice, Nether Vortexes
or Sunmotes. Looting the same corpse twice adds nothing new. Loot the corpse, bank the items,
and move on.

Whenever the council is ready (after a few trash packs, before the next boss, at the end of
the night), the leader types `/tlc loot`. A window lists every item with its number, the boss
it came from, and where it stands: *waiting*, *rolling*, *council deciding*, *to Name* or
*not awarded*. Press **Session** or **Roll** on a row to start it: the item is announced in
raid chat (with a raid warning) exactly as `/tlc session` or `/tlc roll` would, and the row
follows it to the award. **Start next** opens the first item still waiting, and **Announce
list** posts the waiting items to raid chat so raiders know what's coming.

From chat:

- `/tlc loot 3` opens a council session for item 3 (`/tlc loot 3 45` for 45 seconds);
  `/tlc loot roll 3` a plain roll; `/tlc loot next` the first item still waiting.
- `/tlc loot all` opens **every item still to hand out at once** (up to 20), as RCLootCouncil
  does; see below. `/tlc loot all 180` sets the time.
- `/tlc loot announce` posts what's still waiting; `/tlc loot list` prints the list to you.
- `/tlc loot add [item]` adds something by hand (an item that came from somewhere the addon
  didn't see); `/tlc loot remove 3` takes item 3 off.
- `/tlc loot clear` empties the list. It also empties itself 12 hours after the last change.
- `/tlc loot auto off` stops recording corpses (`on` starts again).
- `/tlc loot party on` records in a party you lead too (rare and up), to practise in a 5-man;
  see [docs/TESTING-5MAN.md](docs/TESTING-5MAN.md). `off` goes back to raids only.

One item at a time, or the whole pool at once: while anything is taking rolls, nothing else can
start until it closes. An item nobody was awarded can be started again.

**The whole pool at once.** **Start all** (or `/tlc loot all`) opens a council session for every
waiting item together and posts one raid warning plus the numbered list, instead of a line per
item. Raiders get one loot window with a row per item and MS / OS / Pass on each; answered
items drop off the window. The window stays open 60 seconds plus 15 per item (up to 10
minutes). Each button press also rolls, and the leader's addon matches a raider's rolls to the
items they pressed, in order. A bare `/roll` doesn't count while several items are open (it
can't tell which item it's for), so raiders without the addon have to wait for items started
one at a time. The council frame steps through the items with **<** and **>**, and each is
awarded on its own. Typing `/tlc session [item]` for an item that is on
the list marks it too.

The list is shared: officers see the same list and the same marks, and an officer who logs in
or reloads mid-raid gets it from the leader. Only the raid leader's and assistants' lists are
taken; once a raid password is set, only theirs signed with it.

### When something drops

To hand an item out straight away, the raid leader (or an assistant) starts it by
shift-clicking the item into the command:

- `/tlc session [item] [seconds]` opens a **council session**. Raiders get the loot window;
  officers get the **council frame**, which lists everyone who answered, ranked by priority
  tier, then roll, with their spec, roll and note.
  - **Left-click a row** to vote for that player. **Right-click** it for more: propose them
    with a reason, set their spec if the addon doesn't know it, or (leader) award to them.
  - When the countdown ends (or the leader presses **Close responses** / types `/tlc close`),
    the leader awards with one of the buttons: the **vote leader**, the **proposal**, **list
    says** (the addon's pick), the **highest roll**, **Award to…** (anyone, with a reason) or
    **No award**. `/tlc award` does the same as "list says" from chat.
  - If the top rolls tie, press **Re-roll tied** or type `/tlc reroll`: only the tied players
    roll again, for 15 seconds.
  - `/tlc undo` reopens the last award if it went to the wrong person.
  - `/tlc council` brings the council frame back if you closed it.
- `/tlc roll [item] [seconds]` is a **plain roll** in raid chat: no council frame, no
  votes. When it closes, the addon posts the winner in one line; `/tlc award` records it, or
  `/tlc award <name> <reason>` records an override.

Without `[seconds]`, a session stays open for the time set on the site (normally 30 s) and a
plain roll for 30 s.

### Handing over what was won: trades

Whoever ends up holding the loot (the raid leader, or the assist who looted the corpse) hands
it out by trading. Open a trade with a winner and Toads LC puts the items they were awarded
tonight straight into the trade window, as long as they are in your bags. Check the window and
press **Trade** as usual; once the trade goes through, those items are marked as handed over
and are not offered again. Six items fit in one trade; the addon tells you when there are more.

When an item is awarded and it's in your bags, the addon reminds you who to trade it to.

- `/tlc trade` lists what is still to trade, by winner, and flags anything that isn't in your
  bags (still on another officer, say).
- `/tlc trade done <name>` marks everything owed to that player as handed over, when it went
  some other way (master loot, the mail).
- `/tlc trade off` stops putting items into trades (`on` starts again).

Stacks are never put in for you, so a stack of several of the same item has to be split first.
Soulbound raid drops can only be traded for two hours after they were looted; the game refuses
the trade after that.

### Raid chat announcements

So everyone can see where the loot went, two lines go to raid chat by themselves:

- **When an item is awarded**, from the session leader (also as a raid warning with assist):
  `[ToadsLC] [Dragonspine Trophy] awarded to Anasazi (Rogue, tier 1, rolled 41).`
- **When it is traded to the winner**, from whoever traded it, one line per item:
  `[ToadsLC] [Dragonspine Trophy] traded to Anasazi.`

The loot master can reword either one. Type `/tlc announce` to see both, with an example, and
change them with your own text and any of these placeholders:

| Placeholder | Becomes |
|---|---|
| `{item}` | the item link |
| `{name}` | the winner |
| `{details}` | spec, tier and roll, as in the default line (`Rogue, tier 1, rolled 41`) |
| `{response}` | what they pressed: BiS, Upgrade or OffSpec |
| `{spec}`, `{tier}`, `{roll}` | each on its own |
| `{by}` | who traded it (trade line only) |

```
/tlc announce award Grats {name} on {item} ({response}, rolled {roll})!
/tlc announce trade {item} handed to {name} by {by}.
/tlc announce award off        (or on; trade works the same)
/tlc announce award reset      (back to the default wording)
```

A placeholder with nothing to fill it (no roll on a hand-picked award, say) is left out, along
with any brackets around it. The wording is saved with your settings.

### After the raid

1. The raid leader types `/tlc export`. A window opens with the night's loot as JSON,
   already selected: press Ctrl+C.
2. Paste it into **Import session** on the Toads site.
3. Once the site has accepted it, type `/tlc export clear` so the same sessions are not
   exported again next week. (`/tlc export all` shows everything ever recorded, exported or
   not, if you need to send something again.)

`/tlc history` lists tonight's awards at any time.

## The raid password

The password stops anyone outside the council from reading votes and notes, and stops a
tampered client from voting as an officer. Set it each raid night:

- **Raid leader:** `/tlc begin <password>`. At least 6 characters; spaces are fine.
- **Officers:** `/tlc join <password>`. You'll be told *"Raid password matches
  <leader>'s"*, or that it doesn't match, in which case check it and join again.
- Share it in officer chat or Discord, **never in raid chat**.
- `/tlc status` shows a **fingerprint**: every officer should see the same one as the leader.
- It is forgotten after 12 hours, or straight away with `/tlc end`. Only a scrambled key is
  saved, never the password itself.

Raiders never need the password: they still get the loot window and see the award. An
officer who forgot to join sees sessions as a viewer only, their votes are ignored, and the
addon reminds them to `/tlc join`.

## Practice with /tlc sim

**No priority list yet?** Import the test list to see priorities on every raid item's
tooltip: open [priority.test.json](https://raw.githubusercontent.com/lgriffin/toadsLC/main/fixtures/priority.test.json),
select all and copy, then `/tlc import`, paste and press **Import**. Its priorities are
made up from each item's stats and armour type, **not the guild's**, so import the real list
from the site before a raid.

`/tlc sim` fakes a boss kill so you can try the whole flow outside a raid, solo or in a
party you lead. It opens a council session for each of the boss's drops in turn (two for
Karazhan and Zul'Aman bosses, three elsewhere). A fake raid of twelve answers with buttons,
notes, `/roll` lines and passes, and a fake officer, Toadmaster, votes once responses close.
You answer in the loot window and run the council frame, `/tlc award`, `/tlc reroll` and
`/tlc undo` as on a raid night.

- `/tlc sim` picks a random boss (from the raid you're standing in, if any).
- `/tlc sim Gruul the Dragonkiller`, `/tlc sim black temple` or
  `/tlc sim [Dragonspine Trophy] 20` narrow it down; the number is how many seconds
  responses stay open (5 to 600, default 30).
- `/tlc sim drop [boss | raid | item]` records the kill's drops on the loot list instead of
  opening them, to practise the loot list: run it for a few bosses, then start each item from
  `/tlc loot` and the fake raid answers it.
- `/tlc sim stop` ends it and clears the simulated sessions and loot list items, for the
  party too.

Items on your imported list use its priorities; anything else gets a made-up priority over
the fake raid. Simulated loot never reaches group chat, the export or `/tlc history`. In a
party, the others see the windows and their MS / OS buttons roll for real. It
won't run in a raid group or while a real session is taking rolls, and opening a real session
stops it.

To test the real thing with five players in a dungeon, follow
[docs/TESTING-5MAN.md](docs/TESTING-5MAN.md).

## How the winner is decided

- A main-spec roll (1-100) always beats an off-spec roll (1-99).
- Among main-spec rolls: **lower tier first, then higher roll.** A tier 1 rogue rolling 41
  beats a tier 2 warrior rolling 97.
- Among off-spec rolls, or for an item that isn't on the list: highest roll.
- When every roll is off-spec, the council frame offers both the priority pick and the
  highest roll and awards neither until the council chooses (the site can switch this to
  always-priority or always-highest).
- Duplicate rolls and rolls outside 1-100 / 1-99 are ignored but kept in the record.
- Awarding anyone other than what the list says is recorded as an override, with its reason.

## All commands

`/toadslc` works anywhere `/tlc` does.

| Command | Who | What it does |
| --- | --- | --- |
| `/tlc help` | anyone | list the commands |
| `/tlc status` | anyone | imported list and its date, sessions waiting for export, raid password fingerprint |
| `/tlc tooltip on` / `off` | anyone | show or hide the Priority block on tooltips |
| `/tlc debug [item]` | anyone | client build, tooltip hooks, the list, and why the last item you hovered did or didn't get a Priority block |
| `/tlc import` | officers | paste the priority list from the site |
| `/tlc import undo` | officers | go back to the previous list |
| `/tlc begin <password>` | raid leader | set tonight's raid password and lead the council |
| `/tlc join <password>` | officers | join the council with the leader's password |
| `/tlc end` | leader, officers | forget the raid password |
| `/tlc session <item> [seconds]` | leader or assist | open a council session for an item |
| `/tlc roll <item> [seconds]` | leader or assist | plain priority roll in raid chat |
| `/tlc loot` | anyone | the loot list: what dropped tonight and how each item went |
| `/tlc loot <n> [seconds]` / `next` | leader or assist | open a council session for item n, or the next waiting item |
| `/tlc loot all [seconds]` | leader or assist | open every waiting item at once, answered in one window |
| `/tlc loot roll <n> [seconds]` | leader or assist | plain priority roll for item n |
| `/tlc loot announce` / `list` | leader or assist / anyone | post the waiting items to raid chat / print the list to you |
| `/tlc loot add <item>` / `remove <n>` / `clear` | leader or assist | change the list by hand |
| `/tlc loot auto on` / `off` | leader or assist | record corpses you loot in a raid, or not |
| `/tlc loot party on` / `off` | party leader | record corpses in a party too, rare and up, for a 5-man test run |
| `/tlc trade` | whoever holds the loot | what is still to trade to the winners; opening a trade with one puts their items in |
| `/tlc trade done <name>` / `on` / `off` | whoever holds the loot | mark a winner's items handed over; turn the trade filling on or off |
| `/tlc announce` | leader / whoever holds the loot | show the award and trade lines posted to raid chat |
| `/tlc announce award` / `trade` `<text>` / `on` / `off` / `reset` | leader / whoever holds the loot | reword a line with placeholders, turn it on or off, or go back to the default |
| `/tlc close` | leader | close responses on the last session early |
| `/tlc award` | leader | award the last session to who the list says |
| `/tlc award <name> [reason]` | leader | award to someone else, recorded as an override |
| `/tlc reroll` | leader | re-roll the tied players only (15 s) |
| `/tlc undo` | leader | reopen the last award |
| `/tlc council` | officers | show the council frame again |
| `/tlc history` | anyone | tonight's awards |
| `/tlc export` | leader | the night's loot as JSON for the site |
| `/tlc export all` | leader | every recorded session, exported or not |
| `/tlc export clear` | leader | mark the exported sessions as sent |
| `/tlc sim [boss \| raid \| item] [seconds]` | anyone, solo or party lead | practice with a fake boss kill |
| `/tlc sim drop [boss \| raid \| item]` | anyone, solo or party lead | a fake kill whose drops only go on the loot list |
| `/tlc sim stop` | anyone | end the practice |

## Troubleshooting

**Toads LC isn't in the AddOns list, or `/tlc` does nothing.**
The folder is in the wrong place or has the wrong name. It must be
`Interface/AddOns/ToadsLC/ToadsLC.toc`, not `AddOns/ToadsLC/ToadsLC/...` (unzipped twice) and
not `AddOns/toadsLC-main/...` (the source download). Fix the folder and restart the game.

**It's listed as "Out of date" and won't load.**
Tick **Load out of date AddOns** on the AddOns screen, and tell an officer: the addon needs
the new client version number added. You can find it with `/dump select(4, GetBuildInfo())`.

**"This version runs on the TBC Classic client only".**
You're on a different game client (Era, Wrath or retail). Toads LC v1 is TBC only.

**The tooltip shows no priorities.**
Only clients that imported the list show it: `/tlc status` says whether you have one. Also
check `/tlc tooltip on`. Items not on the list have no Priority block. Still nothing? Hover
the item, then type `/tlc debug` (or `/tlc debug <item link>`): it says which tooltips the
addon hooked and why that item got no block. Paste its output when you report the problem.

**"Import failed: ..."**
The message names the field that's wrong, for example
`items[0].priority[1][0].spec "Shamans" is not a known token`. Fix it on the site and export
again. Your previous list is kept until an import succeeds. Make sure you copied the whole
JSON, from the first `{` to the last `}`.

**No loot window popped up.**
Check the addon is enabled, and that you didn't close it: you can still `/roll` or `/roll 99`
before the countdown ends. If you joined the raid or reloaded mid-session, the addon asks the
leader for the open session within about 20 seconds.

**"You need raid lead or assist to start a session."**
Only the raid leader and assistants can open sessions and rolls.

**Officer: the council frame is empty, or "uses a raid password, type /tlc join".**
You haven't joined with tonight's password. `/tlc join <password>`; once it matches, the
leader sends you the open sessions.

**"Your raid password doesn't match", or fingerprints differ in `/tlc status`.**
Someone typed it differently (it is case-sensitive, spaces count). Agree on it in officer chat,
then `/tlc join` again. The leader can `/tlc begin` again to change it for everyone.

**Officer votes don't count.**
The leader sees *"<name> is on the council but hasn't joined with the raid password"*. That
officer needs to `/tlc join`. The council is the list on the site; without one, it is the raid
leader and assistants.

**A raider's spec shows as just the class (or a druid shows as Druid).**
The addon reads specs from talents when it can inspect the player, or from the member list on
the site. Feral druids can't be told apart by talents, so add their spec on the site.

**The leader disconnected or reloaded mid-session.**
The leader's addon picks up its unfinished session for up to two hours after a reload, and
says so in chat; the leader can then carry on with `/tlc close` and `/tlc award`.

**Nothing goes on the loot list when I loot.**
Only the raid leader and assistants record, only in a raid group, and only items that are epic
or on the priority list. Check `/tlc loot auto on`. An item looted some other way can go on
with `/tlc loot add [item]`.

**Opening a trade with a winner puts nothing in.**
Type `/tlc trade`: the item has to be awarded (not just rolled), in your bags and not in a
stack, and `/tlc trade on`. An item the game says can't be traded any more (soulbound past its
two hours) has to go to a GM ticket.

**Officer: my loot list is empty or behind the leader's.**
Join with the raid password if one is set (`/tlc join`), then `/reload`: the addon asks the
leader for the list as it logs in.

**`/tlc sim` says "Not in a raid group".**
Simulations only run solo or in a party you lead, so fake loot never reaches a real raid.
Leave the raid group, or practise on an alt.

Still stuck? Type `/tlc status`, take a screenshot and post it in the officer channel.
