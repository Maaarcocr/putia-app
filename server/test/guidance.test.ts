import { readFileSync } from "node:fs";
import { expect, it } from "vitest";
// @ts-expect-error: a plain JavaScript script, run with node.
import { guidanceSource } from "../scripts/sync-guidance.mjs";

it("src/guidance.ts matches docs/styling (run `npm run sync-guidance` after editing them)", () => {
  const current = readFileSync(new URL("../src/guidance.ts", import.meta.url), "utf8").replace(/\r\n/g, "\n");
  expect(current).toBe(guidanceSource());
});
