# Toads LC

Loot council for the Toads raid on Spineshatter EU (TBC Classic).

Toads LC puts the guild's agreed class priorities on item tooltips and hands out loot **by
priority tier first, then the council's vote**. There are no rolls. Each drop opens as it's
looted, raiders answer BiS, Main, OS or Pass whenever they have a moment during the raid, the
council clicks the names they want and watches the tally like a poll, and the raid leader who
began the raid awards. Every answer, vote and award is kept, and exported after the raid for the
Toads site.

This guide is for players and officers. If you want to change the addon itself, see
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

- [Install](#install)
- [The Toads LC window](#the-toads-lc-window)
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
   ticked. In game, type `/tlc` (or click the minimap button) to open the Toads LC window;
   `/tlc help` lists the slash commands.

Do not use GitHub's green **Code > Download ZIP** button: that zip is the developer source,
and its folder is named `toadsLC-main`, which the game will not load. Use the release zip.

To update, delete the old `ToadsLC` folder and unzip the new one in its place. Your settings,
imported priorities and unexported loot records are kept (they live in the game's
SavedVariables, not in the addon folder).

Toads LC runs alongside Gargul, RCLootCouncil and other loot addons; each adds its own
tooltip lines. It only loads on the TBC Classic client.

## The Toads LC window

`/tlc` on its own, or the minimap button, opens one window with its pages down the left side.
Everything the slash commands do has a button there; the commands still work as shortcuts.

- **Raider** (everyone): **Tonight's loot** (`/tlc loot`) lists every item open for answers,
  with BiS / Main / OS / Pass buttons on each row, what you answered and a **Change** button to
  change your mind while the item is still open. The small answer window also pops up when new
  items open (never during combat: it waits until the fight ends).
- **Loot council**: the council pages appear once this character has begun or joined tonight's
  raid. On the **Join council** page the raid leader types a password and a raid name and
  presses **Begin raid**; officers type the same password and press **Join council** (the
  same as `/tlc begin` and `/tlc join`). Each character joins for itself, alts included.
  **Raid & council** then shows the raid's name and every officer as *in*, *not joined* or
  *wrong password*, the same list for the leader and every officer.
  - **Loot**, the main page: every item tonight with its boss, when it dropped, the two hours
    it can be traded counting down, and its status, the same for every officer: *waiting to
    open*, *taking answers* (how many have answered and how many votes are in), *council
    deciding* (who is proposed, who still has to vote) and *awarded to Name*. **Open** on a row
    opens that item; **Open all** opens every waiting item. Right-click a row for **Details**,
    **Reset** (back to waiting: an open item closes with no award, an award is undone) and
    **Remove**. Click an item for its live poll: every raider who answered, main spec and BiS
    first, with their tier, answer and note, and beside each name the officers who voted for
    them. Click a name to vote for them (click another to move your vote). The raid leader
    awards with the **Award** button on a row.
  - **Trades**, **Raid & council** (password fingerprint, council, items by hand, the last item
    you led), **Raid chat lines** (award and trade wording), **Import / export** and
    **History**.
- **Practice** (`/tlc sim`) and **Settings**: tooltip priorities, the minimap button, lock
  window positions, an opacity slider and a size slider for every Toads LC window.

## What raiders do

Everyone in the raid should have the addon installed, but only the leader and officers need
to do anything beyond answering loot.

- **Hover any raid item** to see the **Priority (Toads LC)** block on its tooltip: each
  priority tier in class colours, with your own tier marked `>`. This works in bags, on the
  loot window, on chat links and on comparison tooltips. `/tlc tooltip off` hides it.
- **Drops open for answers as they're looted.** Type `/tlc loot` (or open **Tonight's loot**)
  any time during the raid, between pulls or on the run back, and answer each item. A small
  answer window also pops up at the top right when new items open, but never mid-fight: it waits
  for the end of combat. Your tier shows green when you're top priority and grey when your spec
  is not on the list. Type an optional note for the council (it goes with your next answer),
  then press:
  - **BiS**: main spec, best in slot. The council sees it flagged in orange.
  - **Main**: a main-spec upgrade.
  - **OS**: off spec.
  - **Pass**: you are out for this item. You get a line in chat saying so, and you no longer show
    as *still to answer*.
- **Changed your mind?** Press **Change** on the item and pick again, as long as the item is
  still taking answers.
- Your answers are kept through a `/reload` or a disconnect, so items you answered aren't asked
  again.
- There is nothing to `/roll`. The council looks at your tier and answer and votes.

**Window too big or too small for your screen?** Windows open side by side at a sensible size
(the answer window top right, the main window on the left, the council frame on the right), and
this update resets window sizes saved by older versions once. Every Toads LC window (the loot window, the
council frame, the raid loot list and the import/export window) moves by dragging its title and
resizes by dragging its bottom-right corner; the lists show as many rows as fit and scroll with
the mouse wheel. `/tlc scale 0.8` (anything from 0.5 to 2) makes them all smaller or bigger, and
`/tlc scale reset` puts every window back to its default size, place and scale. Sizes, places and
scale are kept per character.

## Raid night for the leader and officers

### Before the raid

1. On the Toads site, export the priority list (the `toads-loot-priority` JSON).
2. In game, every officer and the raid leader types `/tlc import`, pastes the JSON into the
   box (Ctrl+V) and presses **Import**.
3. `/tlc status` should show the item count and the list's date. If the import was a
   mistake, `/tlc import undo` puts the previous list back.
4. Set the raid password (below): the leader types `/tlc begin <password>`, each officer
   `/tlc join <password>`.
5. Once the raid has formed, `/tlc version` checks who has the addon. After about five
   seconds it lists how many have Toads LC, who is on an older version, who didn't answer
   (no addon, or a version from before this check existed) and who is offline. Raiders on an
   older version also get a line telling them a newer one is out.

Raiders don't need to import anything; the tooltip only shows on clients that have the list,
but the loot window works for everyone.

### Loot now, hand out later: the loot list

You don't have to stop after every boss. When the raid leader who began the raid (or, with no
raid password, the raid leader or an assistant) opens a corpse, Toads LC puts its drops on the
**loot list**: everything epic and up, plus anything on the priority list, but not Badges of
Justice, Nether Vortexes or Sunmotes. Looting the same corpse twice adds nothing new.

**Each new drop opens for answers straight away**, with no timer, and one line goes to raid
chat: `[ToadsLC] Open for answers: [item], [item]. Answer BiS / Main / OS / Pass in /tlc loot.`
Answers and council votes build up while the raid carries on, so by the time you hand the loot
out the council has already decided. `/tlc loot drops off` (or the checkbox on the Loot page)
goes back to opening items by hand.

How an item goes:

1. **Item available**: it drops and opens for answers.
2. **People answer**: raiders press BiS / Main / OS / Pass in `/tlc loot`.
3. **Council deciding**: the council opens the item and clicks the names it wants. Everyone on
   the council sees the same tally, and who still has to vote. **Close answers (10 s)** closes
   it to new answers.
4. **Council decides**: the raid leader who began the raid presses **Award** on the winner's
   row. Nobody else can award, so the result can't be changed behind the council's back.
5. **Announce**: the award goes to raid chat and the winner gets a whisper.

The **Loot** page (or `/tlc loot window`, the small list) shows every item with its number,
boss and status. From chat:

- `/tlc loot 3` opens item 3 (`/tlc loot 3 45` with a 45 second timer); `/tlc loot next` the
  first item still waiting; `/tlc loot all` every item still waiting (up to 20), with no timer.
- `/tlc loot reset 3` puts item 3 back to waiting: an open item closes with no award, an award
  is undone. Right-clicking the row does the same.
- `/tlc loot announce` posts what's still waiting; `/tlc loot list` prints the list to you.
- `/tlc loot add [item]` adds something by hand (an item that came from somewhere the addon
  didn't see); `/tlc loot remove 3` takes item 3 off.
- `/tlc loot clear` empties the list. It also empties itself 12 hours after the last change.
- `/tlc loot auto off` stops recording corpses (`on` starts again).
- `/tlc loot party on` records in a party you lead too (rare and up), to practise in a 5-man;
  see [docs/TESTING-5MAN.md](docs/TESTING-5MAN.md). `off` goes back to raids only.

Raiders can't open, reset or remove items, only answer them. Items opened without a timer don't
stop you opening another; an item opened with a timer has to close before the next timed one.

The list is shared: officers see the same list, the same statuses and each other's votes, and
an officer or raider who logs in or reloads mid-raid gets it, and every open item, from the
leader. Once a raid password is set, only the raid leader's list signed with it is taken, and
every officer who joined with the password is on the council for every item, including items
opened before they joined.

### When something drops

To hand an item out on its own, the raid leader shift-clicks it into the command:

- `/tlc session [item] [seconds]` opens it for answers. Officers get the **council frame**,
  which lists everyone who answered, main spec and BiS first, by priority tier, with their
  answer, note and the officers who voted for them.
  - **Left-click a row** to vote for that player. **Right-click** it for more: propose them
    with a reason, set their spec if the addon doesn't know it, or (leader) award to them.
  - One item takes answers for 15 seconds. Officers change that under **Answer time** on the
    Raid & council page, or with `/tlc timer <10-120>`; a number after the item overrides it.
  - Answers close when the countdown ends, or as soon as everyone in the group has answered.
    To close early, the leader presses **Last call (10 s)** or types `/tlc close`.
  - The leader awards with one of the buttons: the **vote leader**, the **proposal**, **list
    says** (the addon's pick), **Award to…** (anyone, with a reason) or **No award**.
    `/tlc award` does the same as "list says" from chat.
  - `/tlc undo` reopens the last award if it went to the wrong person.
  - `/tlc council` brings the council frame back if you closed it.
- `/tlc roll [item] [seconds]` is still there from chat for an old-style **plain roll** in raid
  chat (`/roll` or `/roll 99`), with no council at all. The Toads LC window doesn't use it.

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

### Greens and blues: the loot mule

With master loot on, **the items the council hands out come straight to the master looter**
when they open a corpse: epics and anything on the priority list go into your bags, and chat
says *Looted for the council: ...*, so nobody else can pick them up and you can trade them to the
winners. Greens and blues stay on the corpse unless a mule is named.

The master looter can also name one player (a bank alt, an enchanter) who gets
every green and blue off each corpse, so nobody clicks through the trash drops. When the master
looter opens a corpse, those items go straight to the mule; council items never go to the mule.
Quest items are left alone.

- `/tlc mule <name>` (or `/tlc mule target`, `/tlc mule me`) names the mule; `/tlc mule` shows
  who it is and what they get; `/tlc mule off` stops.
- `/tlc mule quality green blue` picks the rarities (any of `green`, `blue`, `epic`; green
  and blue by default).

Master loot only hands out items at or above the group's loot threshold, so with the threshold
on rare, greens are free for all and can't be muled. If the mule is out of range or wasn't on
the kill, the items stay on the corpse and the addon says so.

### Raid chat announcements and the winner's whisper

So everyone can see where the loot went, two lines go to raid chat by themselves, and the
winner gets a whisper:

- **When an item is awarded**, from the session leader (also as a raid warning with assist):
  `[ToadsLC] [Dragonspine Trophy] awarded to Anasazi (BiS, Rogue, tier 1).`
- **When it is traded to the winner**, from whoever traded it, one line per item:
  `[ToadsLC] [Dragonspine Trophy] traded to Anasazi.`
- **A whisper to the winner** when the item is awarded, from the session leader:
  `[ToadsLC] You won [Dragonspine Trophy] (BiS, Rogue, tier 1). Grats!`

The loot master can reword any of them. Type `/tlc announce` to see all three, with an example, and
change them with your own text and any of these placeholders:

| Placeholder | Becomes |
|---|---|
| `{item}` | the item link |
| `{name}` | the winner |
| `{details}` | answer, spec and tier, as in the default line (`BiS, Rogue, tier 1`) |
| `{response}` | what they pressed: BiS, Main or OS |
| `{spec}`, `{tier}` | each on its own (`{roll}` is only filled for a plain roll) |
| `{by}` | who awarded it (award line and whisper) or who traded it (trade line) |

```
/tlc announce award Grats {name} on {item} ({response}, {spec})!
/tlc announce trade {item} handed to {name} by {by}.
/tlc announce whisper Grats on {item}! Trade {by} when you're free.
/tlc announce award off        (or on; trade and whisper work the same)
/tlc announce award reset      (back to the default wording)
```

A placeholder with nothing to fill it (no answer on a hand-picked award, say) is left out. Inside
brackets, the whole comma-separated part goes with it: `({response}, {spec})` reads `(Fury)` when
there is no answer, and the brackets go too if nothing is left. The wording is saved with your settings.

### After the raid

1. The raid leader types `/tlc export`. A window opens with tonight's raid as JSON, named after
   the raid you began, already selected: press Ctrl+C. Practice and test items from before
   the raid began are left out (the window says how many).
2. Paste it into **Import session** on the Toads site.
3. Once the site has accepted it, type `/tlc export clear` so the same sessions are not
   exported again next week. (`/tlc export all` shows everything ever recorded, exported or
   not, if you need to send something again.)

`/tlc history` (or the **History** page) lists tonight's awards at any time, from any officer,
with a tick once each item is traded. Hover an item anywhere (bags, chat, the loot window) to see
who it was awarded to tonight; on the council, the tooltip also shows the item's votes while it
is open.

## The raid password

The password stops anyone outside the council from reading votes and notes, and stops a
tampered client from voting as an officer. Set it each raid night:

- **Raid leader:** **Begin raid** with a password and a raid name, or `/tlc begin <password>`
  then `/tlc name <raid name>`. At least 6 characters; spaces are fine. Only one character
  begins: everyone else joins, even assists.
- **Officers:** **Join council**, or `/tlc join <password>`. You'll be told *"Welcome to
  <raid name>!"*, and the leader sees *"<you> joined the council"*. If it doesn't match, both
  of you are told: check it, **End raid**, and join again.
- **Check who's in** on Raid & council (or `/tlc who`) asks every officer's addon to check in
  again; officers who joined before the leader began are picked up when the leader begins.
- Share it in officer chat or Discord, **never in raid chat**.
- `/tlc status` shows a **fingerprint**: every officer should see the same one as the leader.
- It is forgotten after 12 hours, or straight away with `/tlc end`. Only a scrambled key is
  saved, never the password itself, and only for the character that typed it.

Raiders never need the password: they still get the loot window and see the award. Everyone
who joins with the password is on the council: they get every answer, vote and proposal, even
for items opened before they joined. An officer who forgot to join sees sessions as a viewer
only, their votes are ignored, and the addon reminds them to `/tlc join`.

## Practice with /tlc sim

**No priority list yet?** Import the test list to see priorities on every raid item's
tooltip: open [priority.test.json](https://raw.githubusercontent.com/lgriffin/toadsLC/main/fixtures/priority.test.json),
select all and copy, then `/tlc import`, paste and press **Import**. Its priorities are
made up from each item's stats and armour type, **not the guild's**, so import the real list
from the site before a raid.

`/tlc sim` fakes a boss kill so you can try the whole flow outside a raid, solo or in a
party you lead. It opens a council session for each of the boss's drops in turn (two for
Karazhan and Zul'Aman bosses, three elsewhere). A fake raid of twelve answers with buttons,
notes and passes (now and then one changes their mind), and a fake officer, Toadmaster, votes
once responses close. You answer in the loot window and run the council frame, `/tlc award` and
`/tlc undo` as on a raid night.

- `/tlc sim` picks a random boss (from the raid you're standing in, if any).
- `/tlc sim Gruul the Dragonkiller`, `/tlc sim black temple` or
  `/tlc sim [Dragonspine Trophy] 20` narrow it down; the number is how many seconds
  responses stay open (5 to 600, default 30).
- `/tlc sim drop [boss | raid | item]` records the kill's drops on the loot list instead of
  opening them, to practise the loot list: run it for a few bosses, then start each item from
  `/tlc loot` and the fake raid answers it.
- `/tlc sim raider [boss | raid | item] [seconds]` (**Practise as a raider** on the
  Practice page) shows only what a raider sees: answer each item as it opens with BiS,
  Main, OS or Pass. There's no council window; Toadmaster votes and hands each item out.
- `/tlc sim officer [boss | raid | item]` (**Practise as LC officer**) puts the kill's drops on
  the council **Loot** page, which opens without a raid password while the practice runs.
  Announce them, give a last call, vote and award while the fake raid answers.
- `/tlc sim stop` ends it and clears the simulated sessions and loot list items, for the
  party too.

Items on your imported list use its priorities; anything else gets a made-up priority over
the fake raid. Simulated loot never reaches group chat, the export or `/tlc history`. In a
party, the others see the windows and answer for real. It won't run in a raid group or while a
real session is taking answers, and opening a real session stops it.

To test the real thing with five players in a dungeon, follow
[docs/TESTING-5MAN.md](docs/TESTING-5MAN.md).

## How the winner is decided

The addon ranks everyone who answered; the council votes; the raid leader awards.

- Main spec (BiS or Main) always comes before OS.
- Among main-spec answers: **lower tier first, then BiS over Main.** A tier 1 rogue who pressed
  Main is above a tier 2 warrior who pressed BiS; two tier 2 warriors, one BiS and one Main, put
  the BiS one first.
- Players on the same tier with the same answer are a tie: the council's votes settle it. For an
  item that isn't on the list, everyone on main spec ties and the council picks.
- The council frame and the item's live poll show the ranking and, beside each name, who voted
  for them. The award buttons offer the vote leader, the proposal and what the list says.
- Awarding anyone other than what the list says is recorded as an override, with its reason.
- For an old-style plain roll (`/tlc roll`) the roll still breaks ties: a main-spec roll (1-100)
  beats an off-spec roll (1-99), then lower tier, then BiS, then the higher roll.

## All commands

`/toadslc` works anywhere `/tlc` does.

| Command | Who | What it does |
| --- | --- | --- |
| `/tlc help` | anyone | list the commands |
| `/tlc version` | anyone | ask the group which Toads LC version each member has; lists newest, older, no answer and offline |
| `/tlc status` | anyone | imported list and its date, sessions waiting for export, raid password fingerprint |
| `/tlc tooltip on` / `off` | anyone | show or hide the Priority block on tooltips |
| `/tlc debug [item]` | anyone | client build, tooltip hooks, the list, and why the last item you hovered did or didn't get a Priority block |
| `/tlc import` | officers | paste the priority list from the site |
| `/tlc import undo` | officers | go back to the previous list |
| `/tlc begin <password>` | raid leader | set tonight's raid password and lead the council |
| `/tlc join <password>` | officers | join the council with the leader's password |
| `/tlc name <raid name>` | raid leader | name tonight's raid; officers see it when they join |
| `/tlc who` | leader, officers | check who has joined the council |
| `/tlc end` | leader, officers | forget the raid password |
| `/tlc session <item> [seconds]` | raid leader | open a council session for an item |
| `/tlc roll <item> [seconds]` | leader or assist | plain priority roll in raid chat |
| `/tlc loot` | anyone | tonight's loot: answer BiS / Main / OS / Pass, or change an answer (raiders); the council's Loot page once you've joined |
| `/tlc loot <n> [seconds]` / `next` | raid leader | open item n, or the next waiting item |
| `/tlc loot all` | raid leader | open every waiting item at once, with no timer |
| `/tlc loot reset <n>` | raid leader | put item n back to waiting (closes it with no award, or undoes the award) |
| `/tlc loot drops on` / `off` | raid leader | open each drop for answers as it's looted (on by default) |
| `/tlc loot window` | anyone | the small loot list window |
| `/tlc loot announce` / `list` | leader or assist / anyone | post the waiting items to raid chat / print the list to you |
| `/tlc loot add <item>` / `remove <n>` / `clear` | leader or assist | change the list by hand |
| `/tlc loot auto on` / `off` | leader or assist | record corpses you loot in a raid, or not |
| `/tlc loot party on` / `off` | party leader | record corpses in a party too, rare and up, for a 5-man test run |
| `/tlc trade` | whoever holds the loot | what is still to trade to the winners; opening a trade with one puts their items in |
| `/tlc trade done <name>` / `on` / `off` | whoever holds the loot | mark a winner's items handed over; turn the trade filling on or off |
| `/tlc announce` | leader / whoever holds the loot | show the award and trade lines and the winner's whisper |
| `/tlc announce award` / `trade` / `whisper` `<text>` / `on` / `off` / `reset` | leader / whoever holds the loot | reword a line with placeholders, turn it on or off, or go back to the default |
| `/tlc close` | leader | last call on the last session: answers close in 10 s (again: close now) |
| `/tlc award` | leader | award the last session to who the list says |
| `/tlc award <name> [reason]` | leader | award to someone else, recorded as an override |
| `/tlc undo` | leader | reopen the last award |
| `/tlc council` | officers | show the council frame again |
| `/tlc history` | anyone | tonight's awards |
| `/tlc export` | leader | tonight's raid as JSON for the site, named after the raid |
| `/tlc export all` | leader | every recorded session, exported or not |
| `/tlc export clear` | leader | mark the exported sessions as sent |
| `/tlc sim [boss \| raid \| item] [seconds]` | anyone, solo or party lead | practice with a fake boss kill |
| `/tlc sim drop [boss \| raid \| item]` | anyone, solo or party lead | a fake kill whose drops only go on the loot list |
| `/tlc sim raider [boss \| raid \| item] [seconds]` | anyone, solo or party lead | practise as a raider: answer each item |
| `/tlc sim officer [boss \| raid \| item]` | anyone, solo or party lead | practise as an LC officer from the Loot page |
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
Check the addon is enabled. The window waits until combat ends, and you can always answer from
`/tlc loot`. If you joined the raid or reloaded mid-raid, the addon asks the leader for the open
items within about 20 seconds.

**"Only the raid leader who began tonight's raid can start loot."**
Once a raid password is set, only the character that began the raid opens, resets and awards
items. Officers vote; raiders answer.

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
Only the raid leader who began the raid records (without a password: the raid leader and
assistants), only in a raid group, and only items that are epic or on the priority list. Check `/tlc loot auto on`. An item looted some other way can go on
with `/tlc loot add [item]`.

**Opening a trade with a winner puts nothing in.**
Type `/tlc trade`: the item has to be awarded (not just open), in your bags and not in a
stack, and `/tlc trade on`. An item the game says can't be traded any more (soulbound past its
two hours) has to go to a GM ticket.

**Officer: my loot list is empty or behind the leader's.**
Join with the raid password if one is set (`/tlc join`), then `/reload`: the addon asks the
leader for the list as it logs in.

**`/tlc sim` says "Not in a raid group".**
Simulations only run solo or in a party you lead, so fake loot never reaches a real raid.
Leave the raid group, or practise on an alt.

Still stuck? Type `/tlc status`, take a screenshot and post it in the officer channel.
