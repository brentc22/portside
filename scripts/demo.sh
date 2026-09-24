#!/usr/bin/env bash
# Starts a few throwaway "dev servers" in fake git repos, for screenshots and
# for trying Portside without touching real projects.
#   scripts/demo.sh        start
#   scripts/demo.sh stop   stop them and remove the repos
set -euo pipefail

DEMO="$HOME/.portside-demo"

if [[ "${1:-}" == "stop" ]]; then
  pkill -f "portside-demo" || true
  rm -rf "$DEMO"
  echo "demo stopped"
  exit 0
fi

rm -rf "$DEMO"
mkdir -p "$DEMO"

repo() {  # repo <name>
  git -C "$DEMO" init -q -b main "$1"
  git -C "$DEMO/$1" -c user.name=demo -c user.email=demo@example.com commit -q --allow-empty -m init
}

serve() {  # serve <dir> <port> — python keeps "portside-demo" in its argv so stop can find it
  (cd "$1" && exec -a "portside-demo" python3 -m http.server "$2" --bind 127.0.0.1 >/dev/null 2>&1 &)
}

repo storefront
git -C "$DEMO/storefront" worktree add -q -b feat/checkout-v2 "$DEMO/storefront-checkout-v2"
repo api

serve "$DEMO/storefront" 5173
serve "$DEMO/storefront-checkout-v2" 5174
serve "$DEMO/api" 8787
serve "$DEMO/api" 54321

echo "demo running on :5173 :5174 :8787 :54321 — scripts/demo.sh stop to clean up"
