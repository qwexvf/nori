import { readFileSync } from "node:fs";

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
