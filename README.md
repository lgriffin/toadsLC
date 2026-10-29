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
  tier (or "Your spec is not on the list for this item") and a countdown. Type an optional note
  for the council, then press:
  - **MS** (main spec): rolls 1-100 for you.
  - **OS (99)** (off-spec): rolls 1-99 for you.
  - **Pass**: you are out for this item.
- **No addon, or you closed the window?** Just `/roll` for main spec or `/roll 99` for
  off-spec while the countdown runs. The leader's addon reads the roll from chat.
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

### When something drops

The raid leader (or an assistant) starts the loot, by shift-clicking the item into the command:

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
- `/tlc sim stop` ends it and clears the simulated sessions, for the party too.

Items on your imported list use its priorities; anything else gets a made-up priority over
the fake raid. Simulated loot never reaches group chat, the export or `/tlc history`. In a
party, the others see the windows and their MS / OS buttons roll for real. It
won't run in a raid group or while a real session is taking rolls, and opening a real session
stops it.

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
| `/tlc import` | officers | paste the priority list from the site |
| `/tlc import undo` | officers | go back to the previous list |
| `/tlc begin <password>` | raid leader | set tonight's raid password and lead the council |
| `/tlc join <password>` | officers | join the council with the leader's password |
| `/tlc end` | leader, officers | forget the raid password |
| `/tlc session <item> [seconds]` | leader or assist | open a council session for an item |
| `/tlc roll <item> [seconds]` | leader or assist | plain priority roll in raid chat |
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
check `/tlc tooltip on`. Items not on the list have no Priority block.

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

**`/tlc sim` says "Not in a raid group".**
Simulations only run solo or in a party you lead, so fake loot never reaches a real raid.
Leave the raid group, or practise on an alt.

Still stuck? Type `/tlc status`, take a screenshot and post it in the officer channel.
