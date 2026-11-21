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

failed=()
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

  project="$cache/$name"
  rm -rf "$project/src"
  mkdir -p "$project/src"
  sed "s/__NAME__/$name/" "$here/gleam.toml.template" >"$project/gleam.toml"
  # A runtime check for this spec, if there is one, becomes the project's main.
  [[ -f "$here/checks/$name.gleam" ]] && cp "$here/checks/$name.gleam" "$project/src/$name.gleam"

  # Unsupported features (multipart bodies, webhooks) are reported, not fatal:
  # the point is that what nori does generate compiles.
  if ! (cd "$root" && gleam run -m nori/cli -- generate --spec="$spec" \
    --target=gleam --output="$project/src/generated" \
    --allow-unsupported=true --quiet=true) >"$project/generate.log" 2>&1; then
    echo "[$name] FAIL generate (see $project/generate.log)"
    failed+=("$name")
    continue
  fi

  if ! (cd "$project" && gleam build) >"$project/build.log" 2>&1; then
    echo "[$name] FAIL build: $(grep -c '^error' "$project/build.log") errors (see $project/build.log)"
    failed+=("$name")
    continue
  fi
  warnings=$(grep -c '^warning' "$project/build.log" || true)
  if [[ "$warnings" != 0 ]]; then
    echo "[$name] FAIL build: $warnings warnings (see $project/build.log)"
    failed+=("$name")
    continue
  fi

  if [[ -f "$project/src/$name.gleam" ]]; then
    if ! (cd "$project" && gleam run -m "$name") >"$project/run.log" 2>&1; then
      echo "[$name] FAIL runtime check (see $project/run.log)"
      failed+=("$name")
      continue
    fi
  fi
  echo "[$name] ok"
done <"$here/specs.tsv"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
