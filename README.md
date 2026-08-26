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
