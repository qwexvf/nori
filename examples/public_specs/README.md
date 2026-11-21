# Real-world specs

Generates Gleam from public OpenAPI specs and compiles the output. The unit
tests use small hand-written specs; these catch the shapes nobody thought to
write one for (nori#62 came from the Kubernetes spec).

```sh
examples/public_specs/check.sh               # every spec marked "pass"
examples/public_specs/check.sh kubernetes    # one spec, skipped or not
```

A spec passes when `generate` succeeds and `gleam build` on the output reports
no errors and no warnings. Generation runs with `--allow-unsupported`, so a spec
that uses something nori does not generate yet (multipart bodies, webhooks)
still has the rest of its output checked. A file in `checks/` named after a spec
becomes that project's `main` and has to run cleanly too; `checks/kubernetes.gleam`
round-trips a Pod through the generated decoders and encoders.

`specs.tsv` lists the specs, pinned to a commit. The second column is `pass` or
the reason the spec is skipped. Downloads and the scratch Gleam projects go to
`.cache/`; delete it to fetch the specs again.

Stripe, GitHub and Cloudflare are 8 to 27 MB each, so a full run takes several
minutes.
