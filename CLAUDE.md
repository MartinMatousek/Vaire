# Vaire

## Release flow — standing authorization

`scripts/release.sh` runs the full release end to end: version bump, commit,
push, xcodegen, archive, ad-hoc sign, zip, `gh release create`, cask bump in
the sibling `homebrew-vaire` checkout, commit, push, `brew upgrade`.

When the user asks to "release", "cut a release", "ship it", or similar for
Vaire, run `scripts/release.sh` directly — no per-step confirmation needed
for its git commits, git pushes (Vaire and homebrew-vaire), `gh release
create`, or `brew upgrade`/`brew reinstall`. This authorization is scoped to
that script's own actions on this repo and `~/projects/homebrew-vaire` only
— it does not extend to any other commit, push, or destructive git command.

Pass a specific version or notes if the user gives them:
`scripts/release.sh 1.4.0 "notes here"`. Otherwise it patch-bumps and
generates notes from commits since the last tag.
