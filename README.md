# Toads LC

A World of Warcraft addon for the Toads raid on Spineshatter EU. It puts the guild's
agreed class priorities on item tooltips and resolves loot **by priority tier first,
roll second**, with an RCLootCouncil-style council frame for voting and proposals. Every
response, roll, vote and award is recorded and exported as JSON for the Toads site.

v1 targets the **TBC Classic** client (Karazhan to Black Temple). It refuses to load on
any other client. When the WoW Forever API is published, only `ToadsLC/adapters/` is
ported; the core, the JSON documents and the site stay the same.

## Install

Copy the `ToadsLC/` folder into `World of Warcraft/_classic_/Interface/AddOns/`.
Gargul can stay installed; both addons add their own tooltip lines.

## Raid night

| When | What |
| --- | --- |
| Before the raid | On the site, export the priorities JSON. In game: `/tlc import`, paste, press Import. `/tlc status` shows the item count and the list's date. |
| Item drops | Hover it: the **Priority (Toads LC)** block lists each tier in class colour, your own tier marked `>`. |
| Council loot | `/tlc session [item] [seconds]`. Raiders answer Main spec / Off-spec / Pass with a note, or just `/roll` (main) or `/roll 99` (off-spec). Officers see the council frame ranked by priority, click a row to vote, right-click to propose. The leader awards from the vote leader, the proposal, *list says*, the highest roll, or *Award to…*. |
| Plain roll | `/tlc roll [item] [seconds]`. The result is announced in one line when it closes; `/tlc award` records it (or `/tlc award <name> <reason>` for an override). |
| After the raid | `/tlc export`, Ctrl+C, paste into the site's Import session. Once the site accepts it, `/tlc export clear`. |

Other commands: `/tlc close`, `/tlc reroll` (tied rolls, 15 s, tied names only),
`/tlc undo` (reopen the last award), `/tlc council`, `/tlc history`,
`/tlc import undo`, `/tlc export all`, `/tlc tooltip on|off`.

### Rules the resolver applies

- A main-spec roll (1-100) always beats an off-spec roll (1-99).
- Among main-spec rolls: lower tier first, then higher roll. A tier 1 rogue rolling 41
  beats a tier 2 warrior rolling 97.
- When every roll is off-spec, the frame offers both the priority pick and the highest
  roll and awards neither until the council chooses (`rules.allOffspecMode` on the site
  can switch this to always-priority or always-highest).
- Duplicate rolls and rolls outside 1-100 / 1-99 are ignored but kept in the record.
- Awarding anyone other than what the list says is recorded as an override with its reason.

## Layout

Everything that decides who wins is in `ToadsLC/core/` and runs under plain Lua 5.1;
everything that touches the WoW API is one file in `ToadsLC/adapters/`.

| File | Holds |
| --- | --- |
| `core/Codec.lua` | JSON encode/decode, schema checks with field paths, chunked wire format for addon messages |
| `core/Priority.lua` | spec/role tokens, tier matching (`Rogue:*`, `ROLE:Healer`, `ANY`, named players), sheet wording parser, tooltip labels |
| `core/Resolver.lua` | main spec, then tier, then roll; ties and all-off-spec flagged |
| `core/Session.lua` | session state machine and the message registry (open, responses, votes, proposals, close, re-roll, award, late-join state) |
| `adapters/Tooltip.lua` | Priority block on GameTooltip, ItemRefTooltip and comparison tooltips |
| `adapters/RollParser.lua` | roll lines from `CHAT_MSG_SYSTEM`, built from the client's own `RANDOM_ROLL_RESULT` |
| `adapters/CouncilComms.lua` | `ToadsLC` addon-message prefix, throttled send queue, chunk reassembly |
| `adapters/Frames.lua` | candidate, council and import/export frames |
| `adapters/Roster.lua` | class and spec (talents, inspect, imported `members[]`), council membership |
| `adapters/Chat.lua`, `Store.lua`, `Commands.lua` | raid chat, `ToadsLCDB` SavedVariables, `/tlc` |
| `Init.lua` | client check and event wiring |

## Loot tables

`data/tbc-raid-loot.json` lists every Rare-or-better raid drop from Karazhan to Sunwell
Plateau (1037 items) with `itemId`, `name`, `quality`, `slot`, `itemLevel`, `zone`, `boss` and
`phase`, in the same field names the priority JSON uses. Tier tokens and quest items carry
`rewards` (the pieces they buy) and each piece carries `tokens`, so a priority on Helm of the
Fallen Hero can be shown on Voidheart Crown and back again, the way Gargul links them.

- `python3 tools/resolve_items.py priorities.json` fills `itemId`, `zone`, `boss` and `phase` on a
  priority list from the item names, and lists names it cannot place. The CSV converter should run
  its output through this.
- `python3 tools/build_loot.py` rebuilds the file from the `wow-classic-items` npm package (MIT,
  scraped from Wowhead) plus the hand-checked fixes in `data/loot/overrides.json`. Edit the
  overrides, never the generated file; CI fails if the two disagree.
- Boss names are the in-game encounter names (`Gruul the Dragonkiller`, `Opera Hall`,
  `Reliquary of Souls`), which is what the addon records from `ENCOUNTER_END`. Trash drops have
  `boss: "Trash"`.
- **Gaps:** 133 Sunwell Plateau items (mostly Eredar Twins, M'uru and trash loot, plus the T6
  bracer/belt/boots tokens and their pieces) have `boss: null` because the scrape does not say who drops them.
  Zul'Aman's timed-chest rewards are not in the file. Both are fixed by adding entries to the overrides.

The JSON contract lives in `schemas/` (`toads-loot-priority` v1 and `toads-loot-session`
v1) with the sample documents from the design doc in `fixtures/`.

## Tests

```sh
luacheck .
lua5.1 "$(command -v busted)"   # core, plus the whole addon loaded in a fake client (spec/wow_mock.lua)
python3 tools/contract.py        # fixtures, loot tables and a real addon export against the JSON Schemas
python3 tools/build_loot.py --check  # loot tables are up to date with data/loot/overrides.json
```

CI runs all of these on every push (`.github/workflows/test.yml`).

## Not done yet

- **Golden priority list.** The CSV converter and the first `toads-loot-priority.json`
  built from the 172-item sheet are not in this repo yet; add the file to `fixtures/` and
  it becomes the golden sample for both repos.
- **Interface number.** The `.toc` uses `20505`; check it against the live TBC Classic
  client (`/dump select(4, GetBuildInfo())`) before the first raid.
- **In-game checklist.** Everything above runs in tests against a fake client; it still
  needs the two-person Karazhan run from the design doc (loot frame, bag, chat-link and
  comparison tooltips, roll timing, export select-all).
- **Privacy.** Council traffic goes over the RAID addon channel as the design says, and
  non-council clients discard it. Raider responses are whispered to the session leader
  only. Anyone reading raw addon traffic could still see votes and notes.
- **Druid ferals.** Talents cannot tell bear from cat, so an uninspected feral is matched
  on `Druid:*` until the site's `members[]` names the spec or the LC sets it from the frame.
- Open questions from the design doc (token set, bare "Priest", tier tokens, who may start
  a roll, multi-item tabs) are unchanged; the code follows the doc's current assumptions.
