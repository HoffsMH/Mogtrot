# Mogtrot

Mogtrot files your transmog outfits into categories you can open anywhere,
pairs each outfit with mounts, hearthstones and titles, and keeps an
account-wide library of your own looks and of other players' looks you snap.

## Features

- Your outfits in categories and sub-categories you drag them into; click a row to wear it.
- Hover previews, and a coloured dot showing whether an outfit sets every gear slot.
- Link mounts, hearthstones and titles to an outfit, and pin favourites for outfits with none.
- A summon key and Mount button that call a mount matching your outfit, with a fallback you choose.
- Match target's mount: summon the mount your target is riding, if you own it.
- A sidebar of Snap, Mount, Hearth, Random outfit and Open buttons, each draggable to a bar.
- Random outfit wears one you have worn least; time worn shows in each row's tooltip.
- The library: every outfit from your characters, and snapshots of other players.
- Snap a player you target; a pop-up shows their look before it saves.
- Archive snapshots you are done with; they clear after 30 days unless you change that.
- Original race: library looks shown on the race and sex that wore them.

## Installing

Install from CurseForge, or drop the `Mogtrot` folder into
`World of Warcraft/_retail_/Interface/AddOns/`. No libraries or other addons
are needed.

## Opening it

- Bind "Toggle outfit list" and "Summon a mount for this outfit" under
  Key Bindings, Mogtrot.
- Click the minimap button, or type `/mogtrot` (or `/mogt`).
- `/mogtrot help` lists the other commands. Settings are in the game's
  Options, AddOns, Mogtrot.

## Known limits

- Mounts and hearthstones are used only through Mogtrot's own key, buttons
  and macros; the game's own mount button is left alone.
- Original race needs a player of the other sex to have been nearby this
  session; until then those looks use your own body.
- Outfits cannot be worn in combat.

## Reporting a bug

Include what you did, what you expected, and whatever BugSack shows.

## Licence

MIT, see `LICENSE`.

Mogtrot contains no code from LiteMount or any other addon. Its optional
LiteMount fallback calls LiteMount's public button at runtime. LiteMount is
GPLv2 and belongs to its authors.
