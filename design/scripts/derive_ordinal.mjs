// The conversion funnel (target → registered → captured → verified) is ORDINAL:
// swapping stages changes the meaning, so it takes a one-hue ramp, not
// categorical hues (dataviz color-formula.md § "Categorical or ordinal?").
// Hue = BMD navy #2B3674, the guideline's information-hierarchy colour.

import { validateOrdinal, contrast } from "file:///C:/Users/Asim/AppData/Local/Temp/claude/bundled-skills/2.1.220/a7c1f78d57a83b3cdd58dbe4638386c2/dataviz/scripts/validate_palette.js";

const SURFACE = { light: "#FFFFFF", dark: "#161A2E" };

const CANDIDATES = {
  // light: lightest end must still clear 2:1 on #FFFFFF
  light: [
    ["#97A2DC", "#7382CC", "#5566C4", "#3B4A96", "#2B3674"],
    ["#8E9BD8", "#6E7EC9", "#4F61BE", "#394792", "#293370"],
    ["#A3ADE1", "#7E8CD1", "#5A6BC7", "#3F4E9B", "#2B3674"],
  ],
  // dark: darkest end must still clear 2:1 on #161A2E, so the ramp runs the
  // other way — light steps carry the far end of the sequence.
  dark: [
    ["#C3CAEE", "#A3ADE1", "#7E8CD1", "#5A6BC7", "#4657AE"],
    ["#CDD3F1", "#ADB6E5", "#8894D6", "#6472CB", "#4F5FB8"],
  ],
};

function report(steps, mode) {
  const { report, ok } = validateOrdinal(steps, { mode, surface: SURFACE[mode] });
  const lines = report.map(([name, state, detail]) => {
    const flag = state === true || state === "pass" ? "PASS"
      : state === false || state === "fail" ? "FAIL" : String(state).toUpperCase();
    return `    ${flag.padEnd(7)} ${name}: ${detail}`;
  });
  return { ok, lines };
}

for (const mode of ["light", "dark"]) {
  console.log(`\n=== ${mode} ordinal ramp (surface ${SURFACE[mode]}) ===`);
  let winner = null;
  CANDIDATES[mode].forEach((steps, i) => {
    const { ok, lines } = report(steps, mode);
    console.log(`\n  candidate ${i + 1}: ${steps.join(" ")}  => ${ok ? "OK" : "REJECTED"}`);
    lines.forEach((l) => console.log(l));
    const nearSurface = mode === "light" ? steps[0] : steps[steps.length - 1];
    console.log(`    step nearest surface ${nearSurface}: ${contrast(nearSurface, SURFACE[mode]).toFixed(2)}:1 (need >= 2.0)`);
    if (ok && !winner) winner = steps;
  });
  console.log(`\n  >>> ${mode} winner: ${winner ? winner.join(", ") : "NONE"}`);
}
