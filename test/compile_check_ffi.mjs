import { execSync } from "node:child_process";

export function shell(cmd) {
  try {
    return execSync(cmd, { encoding: "utf8", shell: "/bin/sh" });
  } catch (e) {
    return (e.stdout ?? "") + (e.stderr ?? "");
  }
}
