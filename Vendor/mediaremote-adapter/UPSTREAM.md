# mediaremote-adapter (vendored)

- Upstream: https://github.com/ungive/mediaremote-adapter
- Commit: `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`
- Licence: BSD-3-Clause (`LICENSE`, shipped in the app as
  `Contents/Resources/MediaRemoteAdapter-LICENSE.txt`)

The files here are **copied unmodified** from that commit:

- `LICENSE`
- `include/MediaRemoteAdapter.h`
- `bin/mediaremote-adapter.pl` (executable bit kept)
- `src/adapter/*.h`, `src/adapter/*.m`
- `src/private/MediaRemote.{h,m}`
- `src/utility/{Debounce,helpers}.{h,m}`
- `src/test/NowPlayingTest.h` (header only; `test.m` imports it)

Deliberately **not** copied: the CMake files, `Makefile`, `README.md`, `src/test/main.m`,
`src/test/NowPlayingTest.m`, `scripts/` and CI. `scripts/build-app.sh` builds the framework
directly with `xcrun clang` (`build_adapter`).

## Re-clone (when the scratch clone is gone)

```
git clone https://github.com/ungive/mediaremote-adapter /projects/sandbox/.design-scratch/mra
git -C /projects/sandbox/.design-scratch/mra checkout e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6
```

## Check the copy is unmodified (run from the repo root; prints `VENDOR OK`)

```
M=/projects/sandbox/.design-scratch/mra; V=Vendor/mediaremote-adapter; diff -r "$M/include" "$V/include" && diff -r "$M/src/adapter" "$V/src/adapter" && diff -r "$M/src/private" "$V/src/private" && diff -r "$M/src/utility" "$V/src/utility" && diff "$M/src/test/NowPlayingTest.h" "$V/src/test/NowPlayingTest.h" && diff "$M/bin/mediaremote-adapter.pl" "$V/bin/mediaremote-adapter.pl" && diff "$M/LICENSE" "$V/LICENSE" && test -x "$V/bin/mediaremote-adapter.pl" && [ "$(ls -A "$V/src/test")" = "NowPlayingTest.h" ] && echo VENDOR OK
```

## Updating

Re-clone at the new commit, re-copy the same file list, re-run the check above, and bump the
commit hash here. `Package.swift` needs no change: its target path `Sources/AgoyNotch` does not
see `Vendor/`.
