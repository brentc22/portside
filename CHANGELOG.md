# Changelog

## 0.3.0 — 2026-11-09

- Docker and OrbStack containers show up by name. Published ports used to collapse into a
  single `docker` row under *Other listeners*; now every container gets its own row (#5)
- A container from a Compose or Supabase project inside a git checkout sits under that repo;
  other containers get a new **Containers** section
- **Stop** and **Kill** on a container run `docker stop` / `docker kill` instead of signalling
  the VM's port proxy, which took every container down with it

## 0.2.0 — 2026-09-24

- Update check: once a day, Portside looks for a new release on GitHub and offers to install it
  (Install and Relaunch / Later / Skip This Version). Toggle it with **Automatically Check for
  Updates**, or use **Check for Updates…** in the menu
- Colorful new app icon

## 0.1.0 — 2026-09-24

First release.

- Menu bar list of listening TCP servers, grouped by repository and git worktree
- Tool detection (vite, next, wrangler, astro, …) from process arguments
- Uptime per server
- Open in browser, copy URL, stop, force quit, stop all servers in a checkout
- Open checkout in the installed editor or terminal, reveal in Finder
- Launch at login
