# Contributing

Thanks for taking a look! Portside is small on purpose, and it should stay that way:
fast, dependency-free, no permissions to grant.

## Getting started

You only need the Xcode Command Line Tools.

```sh
make test           # unit tests
make run            # build, install to /Applications, launch
scripts/demo.sh     # fake repos + dev servers to test against; `stop` cleans up
```

## Where things live

- `Sources/PortsideCore/`: scanning, argv parsing, git resolution, grouping. No AppKit.
  Logic goes here, and it gets a test in `Sources/PortsideTests/`.
- `Sources/Portside/`: the AppKit menu bar app. Keep it thin.

## Guidelines

- **No new dependencies** and no subprocesses per listener. One `lsof` per scan is the budget;
  everything else is syscalls and file reads.
- **A new dev tool to detect?** Add it to `ToolDetector.knownTools`, with a test.
- **Something big?** Open an issue first so we can agree on the approach before you write it.
- Commit messages follow `type: description` (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`).
