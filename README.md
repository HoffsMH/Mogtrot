# Mogtrot

A categorised picker for World of Warcraft transmog outfits, openable anywhere,
that can also link outfits to mounts.

Blizzard's outfit list is flat and only opens at the transmogrifier. If you have
more than a handful of outfits, Mogtrot gives you somewhere to file them.

## Installing

Drop the `Mogtrot` folder into `World of Warcraft/_retail_/Interface/AddOns/`.

Requires no libraries and no other addons.

## Development

Keep the CurseForge `Mogtrot` folder beside a `MogtrotDev` symlink to this
checkout. They use separate SavedVariables; switch with WoW's per-character
addon checkboxes. See `CONTRIBUTING.md` for the development workflow.

`Mogtrot.toc` and `MogtrotDev.toc` must keep identical runtime file lists. Any
change that adds, removes, renames, or reorders a TOC entry must be made in both
files. The test suite rejects mismatches.

## Commands

`/mogtrot` or `/mogt` opens the window. `/mogtrot help` lists the commands below.
There are a few more behind `/mogtrot debug`, for reporting a bug.
 
### Outfit companions

An outfit can link exact battle-pet copies. Mogtrot keeps each
`battlePetGUID`, not just its species, and can summon one automatically only
after a transmog change has settled. Synchronous change events are coalesced
and the active outfit is read on the next frame, so login and intermediate
outfit states do not summon a pet. The pet picker also supports the three
independent pin domains: mounts, battle pets, and hearthstones.

### Hearthstones

The hearthstone picker uses a curated registry of exact toy and inventory item
IDs covering the hearthstone family: the ones that return you to the home you
set at an innkeeper and share the hearth cooldown. Fixed-destination teleports
such as the Garrison and Dalaran hearthstones are deliberately absent. The ones
you have collected sort first; the rest are shown dimmed and cannot be linked.
Ownership, usability, and cooldown are checked at click time, and linked items
plus pinned items are selected by rotation.

The client offers no toy category and no way to ask whether an item is a
hearthstone, so the registry is hand-maintained. `/mogtrot hearthscan` walks
your collected toys and reports anything you own that the registry is missing.
It decides by the first sentence of each Use line, the one naming the home you
set at an innkeeper: a toy bound to a fixed place names somewhere else, so it
cannot match by accident.

Drag the fourth action-bar handle to create the account macro:

```text
#mogtrot:hearth
/click MogtrotHearthstone
```

It chooses and dispatches one usable linked or pinned toy/item through the
secure click path. Hearthstone use is not automatic and has no keybinding.

The hearthstone picker docks the same outfit preview as the mount picker,
showing the outfit being edited. It does not preview a hearthstone's cast
effect: the client exposes no way to map a toy or item to its animation or
visual kit.


## Reporting a bug

`/mogtrot state` prints what Mogtrot can see. Include that, and whatever
BugSack shows, if anything.

(caution) Note that WoW blames whichever addon tainted the execution path, which is not
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
