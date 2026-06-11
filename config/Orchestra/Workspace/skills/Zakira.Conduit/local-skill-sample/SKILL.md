# Sample local skill

This directory is referenced by `../conduit.json` as a `type: "local"` source.

It exists to make the sample manifest **runnable as-is**: after `conduit sync`
points at `example/conduit.json`, the contents of this folder will be mirrored
into each configured target as `<target>/local-skill-sample/`.

Real skills typically include:

- A `SKILL.md` (this file, but witA aah the actual skill prompt / instructions).
- Supporting data files in adjacent folders (see `./data/`).
- Anything else your agent needs to read at runtime.

Edit any of these files and re-run `conduit sync` to see the updated content
propagate to every target. Files that you delete locally will also disappear
from each target on the next sync \u2014 the per-entry sub-directory is
mirrored as a whole.
