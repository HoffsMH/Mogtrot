# Developing Mogtrot

Use a CurseForge install for release checks and the repository as
`MogtrotDev`. The two addon names keep their SavedVariables separate.

Inspect the installation or back up both SavedVariable buckets:

```sh
scripts/dev status
scripts/dev backup
```

Keep the CurseForge `Mogtrot` folder installed and link this repository as
`AddOns/MogtrotDev`. Switch with WoW's per-character addon checkboxes. The
startup guard prevents both copies from running together. Close WoW before
backing up.

`Mogtrot.toc` and `MogtrotDev.toc` must keep identical runtime file lists. Edit
both whenever adding, deleting, renaming, or reordering a loaded file. Their
metadata intentionally differs so development and release data stay separate.

If both addons are enabled, they refuse to start and offer a choice in game.

Run the suite from the repository root:

```sh
lua5.1 /usr/lib/luarocks/rocks-5.1/busted/2.3.0-1/bin/busted
```

The user owns commits, tags, and releases. `scripts/release` verifies a clean,
synchronized `master` before publishing the next annotated release tag.
