// Derive a BMD categorical chart palette by enumeration (dataviz skill,
// color-formula.md § "Deriving an order when a system has no theme yet").
//
// Constraints from the ACSL UI/UX guideline §4.2:
//   * slot 1 is brand red #E71E25 ("one principal chart series")
//   * semantic status hues are reserved and must not be impersonated by a series
// Surfaces are BMD's own: cards #FFFFFF (light) / #161A2E (dark).

import { validate, contrast } from "file:///C:/Users/Asim/AppData/Local/Temp/claude/bundled-skills/2.1.220/a7c1f78d57a83b3cdd58dbe4638386c2/dataviz/scripts/validate_palette.js";

const SURFACE = { light: "#FFFFFF", dark: "#161A2E" };

// Hue families. Slot 1 is pinned. Steps per family are lightness variations
// holding hue — "snap-to-passing" step 1. Brand hues first, then hues chosen to
// sit clear of semantic success/warning/error/info.
const FAMILIES = {
  brandRed: ["#E71E25", "#F0474D", "#D41B21"],
  navy:     ["#3B4A96", "#4657AE", "#5566C4"], // brand navy #2B3674 lifted into band
  teal:     ["#0F766E", "#12897F", "#159C90"],
  violet:   ["#6D28D9", "#7C3AED", "#8B5CF6"],
  ochre:    ["#A16207", "#B87309", "#CA8A04"],
  magenta:  ["#BE185D", "#DB2777", "#E85D95"],
  olive:    ["#4D7C0F", "#5C930F", "#65A30D"],
};

const REST = Object.keys(FAMILIES).filter((f) => f !== "brandRed");
const SLOTS = 6; // 1 pinned + 5 chosen

// --- helpers ---------------------------------------------------------------
const memo = new Map();
function score(palette, mode) {
  const key = mode + palette.join();
  if (memo.has(key)) return memo.get(key);
  const { report, ok } = validate(palette, { mode, surface: SURFACE[mode] });
  const get = (name) => report.find((r) => r[0] === name);
  const cvd = get("CVD separation");
  const nor = get("Normal-vision floor");
  const band = get("Lightness band");
  const chroma = get("Chroma floor");
  const out = {
    ok,
    cvdState: cvd[1],
    cvdDelta: parseFloat(/ΔE ([\d.]+)/.exec(cvd[2])?.[1] ?? "0"),
    norOk: nor[1] === "pass",
    norDelta: parseFloat(/ΔE ([\d.]+)/.exec(nor[2])?.[1] ?? "0"),
    bandOk: band[1] === true,
    chromaOk: chroma[1] === true,
    relief: get("Contrast vs surface")[1] === "relief",
    reliefDetail: get("Contrast vs surface")[2],
  };
  memo.set(key, out);
  return out;
}

function* combinations(arr, k, start = 0, acc = []) {
  if (acc.length === k) { yield [...acc]; return; }
  for (let i = start; i < arr.length; i++) {
    acc.push(arr[i]);
    yield* combinations(arr, k, i + 1, acc);
    acc.pop();
  }
}
function* permutations(arr) {
  if (arr.length <= 1) { yield [...arr]; return; }
  for (let i = 0; i < arr.length; i++) {
    const rest = [...arr.slice(0, i), ...arr.slice(i + 1)];
    for (const p of permutations(rest)) yield [arr[i], ...p];
  }
}
// cartesian product of step choices for a family ordering
function* stepChoices(order) {
  const lists = order.map((f) => FAMILIES[f]);
  const idx = new Array(lists.length).fill(0);
  while (true) {
    yield idx.map((v, i) => lists[i][v]);
    let k = lists.length - 1;
    while (k >= 0 && ++idx[k] >= lists[k].length) { idx[k] = 0; k--; }
    if (k < 0) return;
  }
}

// --- search ----------------------------------------------------------------
// A single ordering of hue FAMILIES must pass in both modes; the hex STEPS are
// chosen per mode (light column / dark column), exactly as palette.md does.
let best = null;

for (const chosen of combinations(REST, SLOTS - 1)) {
  for (const perm of permutations(chosen)) {
    const order = ["brandRed", ...perm];
    const per = {};
    let viable = true;

    for (const mode of ["light", "dark"]) {
      let bestMode = null;
      for (const steps of stepChoices(order)) {
        const s = score(steps, mode);
        if (!s.bandOk || !s.chromaOk || !s.norOk || s.cvdState === "fail") continue;
        // maximize the weakest adjacent CVD pair, then the normal-vision pair
        const rank = [s.cvdDelta, s.norDelta];
        if (!bestMode || rank[0] > bestMode.rank[0] ||
            (rank[0] === bestMode.rank[0] && rank[1] > bestMode.rank[1])) {
          bestMode = { steps, ...s, rank };
        }
      }
      if (!bestMode) { viable = false; break; }
      per[mode] = bestMode;
    }
    if (!viable) continue;

    const weakest = Math.min(per.light.cvdDelta, per.dark.cvdDelta);
    const weakestNor = Math.min(per.light.norDelta, per.dark.norDelta);
    if (!best || weakest > best.weakest ||
        (weakest === best.weakest && weakestNor > best.weakestNor)) {
      best = { order, per, weakest, weakestNor };
    }
  }
}

if (!best) {
  console.log("No ordering passed every gate in both modes.");
  process.exit(1);
}

console.log("WINNING HUE ORDER:", best.order.join(" → "));
console.log(`worst adjacent CVD ΔE  : ${best.per.light.cvdDelta.toFixed(1)} light / ${best.per.dark.cvdDelta.toFixed(1)} dark  (target >= 8)`);
console.log(`worst adjacent normal ΔE: ${best.per.light.norDelta.toFixed(1)} light / ${best.per.dark.norDelta.toFixed(1)} dark  (floor >= 15)`);
console.log();
console.log("| Slot | Hue | Light | Dark |");
console.log("|------|-----|-------|------|");
best.order.forEach((f, i) => {
  console.log(`| ${i + 1} | ${f} | \`${best.per.light.steps[i]}\` | \`${best.per.dark.steps[i]}\` |`);
});
console.log();
for (const mode of ["light", "dark"]) {
  console.log(`--- ${mode} (surface ${SURFACE[mode]}) ---`);
  const { report } = validate(best.per[mode].steps, { mode, surface: SURFACE[mode] });
  for (const [name, state, detail] of report) {
    const flag = state === true || state === "pass" ? "PASS" : state === false || state === "fail" ? "FAIL" : String(state).toUpperCase();
    console.log(`  ${flag.padEnd(7)} ${name}: ${detail}`);
  }
}

// Does any series hue collide with a reserved semantic status hue?
console.log("\n--- series vs reserved semantic hues (guideline §4.2) ---");
const STATUS = { success: "#1F7A4D", warning: "#B54708", error: "#B42318", info: "#175CD3" };
for (const [role, hex] of Object.entries(STATUS)) {
  console.log(`  ${role.padEnd(8)} ${hex}  text-contrast on #FFFFFF: ${contrast(hex, "#FFFFFF").toFixed(2)}:1`);
}
