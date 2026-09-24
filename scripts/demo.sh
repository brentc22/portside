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

# serve <dir> <tool> <port> — runs a python static server disguised as
# node_modules/.bin/<tool>, so Portside labels it like the real thing. The path
# contains ".portside-demo", which is how `stop` finds it.
serve() {
  local bin="$1/node_modules/.bin/$2"
  mkdir -p "$(dirname "$bin")"
  printf '#!/usr/bin/env python3\nimport runpy, sys\nsys.argv = ["http.server", sys.argv[1], "--bind", "127.0.0.1"]\nrunpy.run_module("http.server", run_name="__main__")\n' > "$bin"
  (cd "$1" && exec python3 "$bin" "$3" >/dev/null 2>&1 &)
}

repo storefront
git -C "$DEMO/storefront" worktree add -q -b feat/checkout-v2 "$DEMO/storefront-checkout-v2"
repo api

serve "$DEMO/storefront" vite 5173
serve "$DEMO/storefront" storybook 6006
serve "$DEMO/storefront-checkout-v2" vite 5174
serve "$DEMO/api" wrangler 8787
serve "$DEMO/api" supabase 54321

echo "demo running on :5173 :5174 :6006 :8787 :54321 — scripts/demo.sh stop to clean up"
