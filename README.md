<p align="center">
  <img src="docs/icon.png" width="128" alt="Portside icon">
</p>

<h1 align="center">Portside</h1>

<p align="center">
  <b>Every dev server on your Mac, grouped by repo and git worktree — in the menu bar.</b><br>
  See what's running on which port, which branch started it, and stop it in one click.
</p>

<p align="center">
  <a href="https://github.com/brentc22/portside/releases/latest"><img src="https://img.shields.io/github/v/release/brentc22/portside?style=flat-square&label=release&color=4c6ef5" alt="Latest release"></a>
  <a href="https://github.com/brentc22/portside/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/brentc22/portside/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/brentc22/portside?style=flat-square&color=2f9e44" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://github.com/brentc22/portside/releases/latest/download/Portside.zip"><b>Download Portside.zip</b></a>
  &nbsp;·&nbsp;
  <a href="#build-from-source">Build from source</a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <img src="docs/menu.png" width="392" alt="Portside menu: an api repo running wrangler and supabase, a storefront repo running vite and storybook, and a feat/checkout-v2 worktree running a second vite">
</p>

---

## Why

`lsof -iTCP -sTCP:LISTEN` tells you *node* is on `:5174`. It doesn't tell you that it's the
Vite server you started three days ago in a worktree you already merged.

If you work in several repos or git worktrees at once, ports pile up: `5173`, `5174`,
`5175`, `8080`, `8787`… Portside answers "what is this, and can I kill it?" without
opening a terminal.

## Features

|  |  |
| --- | --- |
| 🗂️ **Grouped by repo → checkout → server** | Linked git worktrees sit under their main repository, labelled with their branch. |
| 🔎 **Knows the tool, not just the binary** | `node` becomes `vite`, `next`, `wrangler`, `astro`, `storybook`… by reading the process's arguments. |
| ⏱️ **Uptime per server** | Spot the ones you forgot about. |
| ⚡ **One-click actions** | Open `localhost:<port>`, copy the URL, stop (SIGTERM) or force quit (SIGKILL), or stop every server in a worktree at once. |
| 🧑‍💻 **Jump to the code** | Open the checkout in your editor (Cursor, VS Code, Zed, Windsurf, Sublime, Xcode) or terminal (Ghostty, iTerm, Warp, kitty, WezTerm, Terminal), whichever you have installed. |
| 🧹 **Everything else stays out of the way** | AirPlay, Spotify, Docker and other listeners that weren't started from a git checkout go under *Other listeners*. |
| 🔄 **Updates itself** | Checks GitHub once a day and offers new versions with their release notes: *Install and Relaunch*, *Later* or *Skip This Version*. Turn it off under **Automatically Check for Updates**. |
| 🪶 **Light** | No Dock icon, no permissions to grant, no dependencies. The only network call is that daily update check. A scan takes ~50–100 ms. |

## Install

1. Download [`Portside.zip`](https://github.com/brentc22/portside/releases/latest/download/Portside.zip)
   from the latest release.
2. Unzip it and move `Portside.app` to `/Applications`.
3. Open it. The icon appears in your menu bar; turn on **Launch at Login** from the menu
   if you want it there every time.

> [!NOTE]
> Portside isn't notarized yet, so macOS blocks the first launch. Right-click the app →
> **Open**, or clear the quarantine flag:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Portside.app
> ```

Requires macOS 14 Sonoma or later. Universal binary (Apple silicon + Intel).

Portside keeps itself up to date from then on. You can also pick **Check for Updates…** from the menu.

### Build from source

You only need the Xcode Command Line Tools, not the full Xcode.

```sh
git clone https://github.com/brentc22/portside.git
cd portside
make run        # builds, installs to /Applications and launches
```

## How it works

| Question | Answer | How |
| --- | --- | --- |
| What's listening? | pid + ports | one `lsof -nP -iTCP -sTCP:LISTEN -F pcn` call |
| Where was it started? | working directory | `proc_pidinfo(PROC_PIDVNODEPATHINFO)`, straight from the kernel |
| What is it? | `vite`, `next`, … | argv via `sysctl(KERN_PROCARGS2)`, matched against `node_modules/.bin/*` |
| Which repo and branch? | repo, worktree, branch | walks up to `.git`, follows `gitdir:` and `commondir` for worktrees, reads `HEAD` |

Updates come from GitHub's `releases/latest` API. Before swapping anything in, Portside checks that the
downloaded app has the same bundle id, the promised version and a valid code signature. The swap
happens after Portside quits, and if moving the new copy fails, the old one is put back.

No `git` subprocesses and no `ps` call per process: one `lsof`, and the rest is syscalls
and a few small file reads. Portside only sees your own processes, so it doesn't need admin
rights.

## Development

```sh
make test           # unit tests (swift run PortsideTests)
make bundle         # Portside.app in the repo root
scripts/demo.sh     # fake repos + servers (vite, wrangler, …) to play with
scripts/demo.sh stop
```

Tests are a plain executable with a tiny harness instead of XCTest, so they run with just
the Command Line Tools. Exit code 0 means green.

Launch arguments for screenshots and debugging:

- `--show-menu` opens the menu right after launch
- `--only-under <path>` only shows repos below that path

```sh
open Portside.app --args --show-menu --only-under ~/.portside-demo
```

### Layout

```
Sources/
  PortsideCore/     scanning, parsing, git resolution, grouping — no AppKit, fully tested
  Portside/         the menu bar app (AppKit)
  PortsideTests/    tests
```

## Roadmap

- [ ] Notification when a server has been running for longer than N days
- [ ] Custom links per repo (e.g. preview deployments per branch)
- [ ] Docker/OrbStack: map published ports back to their compose project
- [ ] Global hotkey
- [ ] Notarized builds and a Homebrew cask
- [ ] EdDSA-signed updates (Sparkle-style), so an update is verified by more than HTTPS and GitHub

## Contributing

Ideas, bug reports and PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). For
anything big, open an issue first so we can agree on the approach.

## License

[MIT](LICENSE) © Brent Ceulemans
