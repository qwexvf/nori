export function halt(code) {
  if (typeof process !== "undefined" && typeof process.exit === "function") {
    process.exit(code);
  }
  throw new Error("nori: halt(" + code + ")");
}
