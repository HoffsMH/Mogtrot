# Mogtrot

A categorised picker for World of Warcraft transmog outfits, openable anywhere,
that can also link outfits to mounts.

Blizzard's outfit list is flat and only opens at the transmogrifier. If you have
more than a handful of outfits, Mogtrot gives you somewhere to file them.

## What it does

**Nested categories over your outfits.** Drag and drop, inline rename, search
across both outfit and category names, and a resizable list. Filing is keyed by
outfit ID rather than by name, so renaming an outfit never loses its place.

**Click to wear, anywhere.** No transmogrifier needed. Shift-click announces the
change in `/say`, if you like that sort of thing.

**Hover preview.** Shows your character in that outfit, rendered from a snapshot
taken the last time you wore it. An outfit you have never worn has nothing to
show yet - wear it once and it appears.

**Mount linking.** Pick mounts for an outfit from a grid of live 3D models.
Right-click a mount to summon it without closing the window. The filter dropdown
narrows by type, favourites, and whether a mount is already on this outfit.

**Title linking.** Click the scroll beside an outfit to link any number of known
titles. Clicking an outfit in Mogtrot cycles through its least recently used linked
titles. The Settings page chooses a random, clear, or pinned title when none is linked.

**A key that summons a mount for what you are wearing.** Bind *Summon a mount for
this outfit* under Key Bindings, Mogtrot. It picks at random from the mounts you
linked to the outfit you have on, skipping any the game will not let you use
where you are standing, and dismounts if you are already up. No other addon
needed.

**And it still works before you have set anything up.** With no outfit on, or an
outfit you have not linked mounts to yet, the key falls back rather than doing
nothing: a random favourite - the same thing Blizzard's own mount key does - or,
if you have not starred any, a random mount from your collection. Either way it
says in chat why it did. It only refuses once the character owns no mount at all.

The mount picker also manages account-wide pins. Each pin has its own expiration,
and newly acquired mounts are pinned for the default duration. Every outfit can
choose whether its linked-mount shuffle includes pins. Pins can also serve as the
fallback when an outfit has no linked mounts.

**At-a-glance slot completeness.** Mogtrot checks which outfits still have empty
slots and marks them in Blizzard's list. An optional circle can show the same
state in Mogtrot's list.

**Wear time.** Mogtrot records how long you spend in each outfit. An optional
blue bar on each row compares it with your most-worn outfit. Hover a row for the
exact figure, its share of the total, and when you last had it on. `/mogtrot wear`
prints the ranking.

Only time with Mogtrot loaded is counted, never time spent logged out, and the
count is per character. Tracking is always on. Both list indicators are off by
default and can be enabled separately in Mogtrot's panel under Blizzard's Options,
Addons.

**Match a targeted player's mount.** Enable *Match target's mount* in Mogtrot's
Options panel. The general summon key, macro, and `/mogtrot summon` then try the
same Mount Journal mount when you own it and can use it. Restricted targets,
unowned mounts, vehicles, forms, and unidentified effects use the normal outfit
and fallback choices. Random appearance variants cannot be copied exactly.

**Category labels in Blizzard's own outfit window**, so while you are at the
transmogrifier you can see at a glance which outfits are still unfiled.

**Two buttons for your action bar.** Beside the search box are two small icons.
Drag either onto a bar and it makes one general macro:

- the right-hand one **opens Mogtrot**. Unlike clicking, a macro works in combat,
  so the window is still reachable mid-fight.
- the left-hand one **summons a mount** for the outfit you are wearing - the same
  thing the keybinding does, fallbacks and all.

Every drag after the first hands you the same macro rather than making another,
and Mogtrot says in chat when it takes a macro slot. `/mogtrot macro` prints what
is actually stored in both, which is what a bug report about them needs. The
summon macro always clicks Mogtrot's dispatcher once; changing fallback settings
does not rewrite it.

## Installing

Drop the `Mogtrot` folder into `World of Warcraft/_retail_/Interface/AddOns/`.

Requires no libraries and no other addons.

## Commands

`/mogtrot` or `/mogt` opens the window. `/mogtrot help` lists the commands below.
There are a few more behind `/mogtrot debug`, for reporting a bug.

| Command | |
|---|---|
| `preview` | hover preview on or off |
| `say` | shift-click announcements on or off |
| `quiet` | silence Mogtrot's chat output |
| `summon` | summon a mount linked to the outfit you are wearing |
| `fallback` | what that key does when the outfit has no mounts |
| `fallback random` / `pinned` / `litemount` / `off` | a random mount, a pinned mount, LiteMount, or nothing |
| `wear` | how long each outfit has been worn, longest first |
| `capture` | re-snapshot the outfit you are wearing |
| `slots scan` | check every outfit again, including ones already checked |
| `slots wipe` | forget every measurement, so the next scan redoes it |
| `macro` | print what is stored in both action bar macros |
| `state` | print diagnostics, useful in a bug report |

## LiteMount fallback

If you have [LiteMount](https://www.curseforge.com/wow/addons/litemount)
installed, the summon fallback setting can delegate to LiteMount when the active
outfit has no mounts linked. Outfits with linked mounts stay on Mogtrot's path.
Mogtrot uses LiteMount's published compatibility button and does not write new
LiteMount groups or rules. The keybinding and action-bar macro can securely
delegate through Mogtrot's dispatcher. `/mogtrot summon` cannot manufacture that
hardware click and tells you to use one of those routes when LiteMount is needed.

## Known limitations

These are limits of what the game exposes to addons, not oversights:

- **Outfits cannot be deleted or renamed** from here, and Blizzard's own list has
  no reorder. Mogtrot orders outfits within its own categories instead, which is
  what the drag handles do.
- **Locking an outfit's appearance** only works from Blizzard's list. The button
  in Mogtrot's title bar opens it for you, from anywhere.
- **An outfit's appearances cannot be read** away from the transmogrifier, which
  is why the preview relies on a snapshot taken when you wear it. Which slots an
  outfit *fills* can be read, which is what the slot check reports.
- **Wearing an outfit does not work in combat.** Mogtrot's window stays usable,
  but the game refuses the change.

## Reporting a bug

`/mogtrot state` prints what Mogtrot can see. Include that, and whatever
BugSack shows, if anything.

⚠️ Note that WoW blames whichever addon tainted the execution path, which is not
always the addon at fault - an error naming Mogtrot may belong to something else,
and the reverse happens too. The stack trace is more informative than the name.

## Licence

MIT, see `LICENSE`.

Mogtrot contains no code from LiteMount. Fallback calls LiteMount's public
compatibility button at runtime, and retirement cleanup calls its settings API
only to remove exact records from older Mogtrot versions. Nothing has been
copied or adapted from it. LiteMount is GPLv2 and belongs to its authors.

Nor does it contain code from any other addon. Where another addon settled a
question about Blizzard's API, that is recorded as a citation in the notes and the
implementation was written from scratch.
