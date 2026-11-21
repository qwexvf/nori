#!/usr/bin/env bash
# Generates Gleam from real-world specs and compiles it.
#
#   examples/public_specs/check.sh               every spec marked "pass"
#   examples/public_specs/check.sh stripe box    just these (skipped ones too)
#
# Specs and scratch projects go to examples/public_specs/.cache, which is
# ignored. Needs curl, gleam, and network for the first run.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cache="$here/.cache"
mkdir -p "$cache/specs"

(cd "$root" && gleam build >/dev/null)
# The CLI is run through erl, not `gleam run`, so that specs can generate at
# the same time without waiting on the project's build lock.
paths=()
for ebin in "$root"/build/dev/erlang/*/ebin; do
  paths+=(-pa "$ebin")
done

# Generates and compiles one spec; prints one line and exits non-zero on failure.
check() {
  local name="$1" spec="$2"
  local project="$cache/$name"
  rm -rf "$project/src"
  mkdir -p "$project/src"
  sed "s/__NAME__/$name/" "$here/gleam.toml.template" >"$project/gleam.toml"
  # A runtime check for this spec, if there is one, becomes the project's main.
  [[ -f "$here/checks/$name.gleam" ]] && cp "$here/checks/$name.gleam" "$project/src/$name.gleam"

  # Unsupported features (multipart bodies, webhooks) are reported, not fatal:
  # the point is that what nori does generate compiles. The output only has to
  # compile, so it is not formatted.
  if ! erl -noshell "${paths[@]}" -eval 'nori@cli:main(), erlang:halt(0).' \
    -extra generate --spec="$spec" --target=gleam \
    --output="$project/src/generated" --allow-unsupported=true --quiet=true \
    --no-format=true >"$project/generate.log" 2>&1; then
    echo "[$name] FAIL generate (see $project/generate.log)"
    return 1
  fi

  if ! (cd "$project" && gleam build) >"$project/build.log" 2>&1; then
    echo "[$name] FAIL build: $(grep -c '^error' "$project/build.log") errors (see $project/build.log)"
    return 1
  fi
  local warnings
  warnings=$(grep -c '^warning' "$project/build.log" || true)
  if [[ "$warnings" != 0 ]]; then
    echo "[$name] FAIL build: $warnings warnings (see $project/build.log)"
    return 1
  fi

  if [[ -f "$project/src/$name.gleam" ]]; then
    if ! (cd "$project" && gleam run -m "$name") >"$project/run.log" 2>&1; then
      echo "[$name] FAIL runtime check (see $project/run.log)"
      return 1
    fi
  fi
  echo "[$name] ok"
}

# Each spec is its own Gleam project, so they build in parallel; the run takes
# as long as the slowest (Cloudflare) instead of the sum.
names=()
pids=()
while IFS=$'\t' read -r name expect url; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if [[ $# -gt 0 ]]; then
    [[ " $* " == *" $name "* ]] || continue
  elif [[ "$expect" != pass ]]; then
    echo "[$name] skipped: $expect"
    continue
  fi
  spec="$cache/specs/$name.${url##*.}"
  [[ -s "$spec" ]] || curl -fsSL -o "$spec" "$url"
  check "$name" "$spec" &
  names+=("$name")
  pids+=($!)
done <"$here/specs.tsv"

failed=()
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || failed+=("${names[$i]}")
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
