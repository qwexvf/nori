#!/usr/bin/env bash
# Regenerates the committed example output with the nori in this repository.
#
# petstore and realworld are run from their own directories, through erl,
# because nori loads TypeScript templates from ./templates when it exists and
# the repository root has an editable copy of them. wisp_app depends on nori,
# so it runs the CLI as its README says.
#
# CI runs this and fails if the result differs from what is committed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$root" && gleam build >/dev/null)

paths=()
for ebin in "$root"/build/dev/erlang/*/ebin; do
  paths+=(-pa "$ebin")
done

for example in petstore realworld; do
  (cd "$root/examples/$example" &&
    erl -noshell "${paths[@]}" -eval 'nori@cli:main(), erlang:halt(0).' \
      -extra generate --quiet=true)
done

(cd "$root/examples/wisp_app" && gleam run -m nori/cli -- generate --quiet=true)
