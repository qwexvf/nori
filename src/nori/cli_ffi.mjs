import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { Ok, Error } from "../gleam.mjs";

export function halt(code) {
  if (typeof process !== "undefined" && typeof process.exit === "function") {
    process.exit(code);
  }
  throw new Error("nori: halt(" + code + ")");
}

export function read_stdin() {
  try {
    // fd 0 is stdin; read it synchronously to the end
    return readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

// Run an executable found on PATH with the given arguments, without a shell.
// Error(undefined) when it cannot be started (not on PATH).
export function run_executable(name, args) {
  const result = spawnSync(name, args.toArray(), { encoding: "utf8" });
  if (result.error) return new Error(undefined);
  return new Ok([result.status ?? 1, (result.stdout ?? "") + (result.stderr ?? "")]);
}
