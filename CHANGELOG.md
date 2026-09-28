# Mogtrot

## 12.1.0-4

A library of looks, hearthstones that follow your outfit, and a tidier main
window.

### Added

- Library. One account-wide wall of looks: every outfit and custom set from
  every character you log in on ("My characters"), and snapshots of other
  players you liked. Filter by race, class and armour, pick characters, and
  drag a card up or down to zoom the whole wall. Left-click a card for its
  details and to transfer pieces at a transmogrifier.
- Snapshots. Target a player and press Snap (or type `/mogtrot snap`) to keep
  their look. A pop-up shows it on their own body and saves it after 3
  seconds unless you press Cancel. In quiet mode or in combat it saves
  straight away.
- Looks on the right body. The library can show each look on the race and
  sex that wore it, once someone of that sex has been nearby; until then it
  uses your own body and says so.
- Archive. The X on a snapshot moves it to the archive, where you can restore
  it or delete it for good. Archived snapshots are cleared after 30 days;
  change that in Settings (0 keeps them forever).
- Hearthstones. Link hearthstone toys and items to an outfit. The Hearth
  button uses one that matches what you are wearing, reaching for a toy
  before the Hearthstone in your bags. With nothing linked it uses a pinned
  one by default; Settings can make that any one you own, or nothing.
- One pairing window for mounts and hearthstones, with a preview of the
  outfit docked beside it.
- Sidebar. Snap, Mount, Hearth, Random outfit and Open sit down the left of
  the main window. Click to use, or drag to an action bar. The bar icons
  follow the mount and hearthstone your outfit is linked to.
- Random outfit wears one of the outfits you have worn least.
- The outfit menu can copy hearthstones to other outfits, like mounts and
  titles, and can clear an outfit's mounts, titles or hearthstones.
- Settings are in sections, with Quiet mode and a switch for the sidebar's
  setup icons.

### Changed

- "Match target's mount" is now on by default. If you had turned it off, it
  stays off.
- The first login after updating re-reads your outfits once, in the
  background and never in an instance, so the library and the slot check are
  exact. It may take a minute.
- Unused outfit slots no longer fill the list with rows called "Outfit".
- The X on the main window is greyed out in combat, when the game will not
  let it close; the key binding still closes it.

### Fixed

- The summon key summons once per press, not on both press and release.
- Outfits read before the game had loaded them are no longer stored with
  pieces missing.
- A split shoulder with one side hidden now draws that side bare.
- Typing in the search box, ticking "Hide empty categories" or an outfit
  change while the window is open in combat no longer causes "Interface
  action failed because of an AddOn".
- Shift-click announcing works with the game's deprecated-API fallbacks off.

### Removed

- The mount type filter in the mount picker.
- The "Show time worn in list" option and its bar. Time worn is still
  tracked, and each row's tooltip shows it.
- The chat commands `/mogtrot wear`, `capture`, `slots scan`, `slots wipe`,
  `macro` and `state`.
