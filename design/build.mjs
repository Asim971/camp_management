/* ==========================================================================
   Design-system bundle builder.

   Assembles each specimen page from src/pages/<file> plus the shared token,
   component and documentation CSS, and emits a self-contained HTML document
   into dist/. Self-contained is a hard requirement: the Design System pane
   renders each page in isolation under a strict CSP, so there can be no
   external stylesheet, script, font or image request.

   Run:  node design/build.mjs
   ========================================================================== */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const SRC = join(ROOT, "src");
const PAGES = join(SRC, "pages");
const DIST = join(ROOT, "dist");

/* --------------------------------------------------------------------------
   The card index. `group` drives the Design System pane's sectioning, so the
   groups follow the guideline's own page map (§12.1) rather than inventing a
   second taxonomy.
   -------------------------------------------------------------------------- */
export const CARDS = [
  // ---- 01 Foundations ----------------------------------------------------
  { file: "color.html", out: "foundations/color.html", group: "Foundations",
    name: "Colour", subtitle: "Brand, surface, semantic state, data series",
    id: "F-01", refs: "Guideline §4.1–4.2",
    title: "Colour system",
    lede: "Brand red and navy are the identity; the semantic quartet carries operational state so risk never wears the brand. Data-series slots are machine-validated, not picked by eye." },

  { file: "type.html", out: "foundations/type.html", group: "Foundations",
    name: "Typography", subtitle: "Inter + Noto Sans Bengali, 8 roles, bilingual",
    id: "F-02", refs: "Guideline §4.3, §10.1",
    title: "Typography",
    lede: "One family across both scripts, eight roles, and two figure treatments — tabular where columns must align, proportional where a number is a headline." },

  { file: "space.html", out: "foundations/space.html", group: "Foundations",
    name: "Space, radius & elevation", subtitle: "8px rhythm, 5 radii, 4 elevations",
    id: "F-03", refs: "Guideline §4.4, §3.1",
    title: "Space, radius, elevation and grid",
    lede: "An 8px rhythm with 4px reserved for tightly-bound metadata, five radii mapped to surface class, and four elevations that never stack." },

  { file: "status.html", out: "foundations/status.html", group: "Foundations",
    name: "Status vocabulary", subtitle: "5 families, controlled values, one renderer",
    id: "F-04", refs: "Guideline §5.4, Appendix B",
    title: "Controlled status vocabulary",
    lede: "Five status families with fixed values. The same word appears on web, mobile, CRM and analytics — a record that reads “Pending sync” on a phone reads “Pending sync” in the dashboard." },

  { file: "accessibility.html", out: "foundations/accessibility.html", group: "Foundations",
    name: "Accessibility & privacy", subtitle: "WCAG 2.2 AA, masking, sensitive evidence",
    id: "F-05", refs: "Guideline §10, NFR-11–13",
    title: "Accessibility, privacy and sensitive evidence",
    lede: "The rules that outrank visual preference: contrast floors, never colour alone, masked identifiers, and evidence that stays veiled until an authorised case is open." },

  // ---- 02 Components ----------------------------------------------------
  { file: "lineage.html", out: "components/lineage-rail.html", group: "Components",
    name: "Lineage rail", subtitle: "Chain of custody — the system's signature component",
    id: "C-00", refs: "Guideline §2, §8.11, §8.13",
    title: "The lineage rail",
    lede: "An attendance record moves through an irreversible chain. This is the one component that renders that chain, identically, everywhere the record appears." },

  { file: "buttons.html", out: "components/buttons.html", group: "Components",
    name: "Buttons & actions", subtitle: "6 variants, states, field sizing",
    id: "C-01", refs: "Guideline §5.1",
    title: "Buttons and actions",
    lede: "One filled primary action per page or step. Everything else is tonal, outlined or text — and destructive actions wear semantic error, never brand red." },

  { file: "forms.html", out: "components/forms.html", group: "Components",
    name: "Form controls", subtitle: "Outlined fields, validation, masked reveal",
    id: "C-02", refs: "Guideline §5.2",
    title: "Form controls",
    lede: "Outlined and dense for enterprise configuration, with persistent labels, specific inline validation, and masked values that reveal only under permission." },

  { file: "chips.html", out: "components/status-chips.html", group: "Components",
    name: "Status & filter chips", subtitle: "Icon + text always; colour never alone",
    id: "C-03", refs: "Guideline §5.4, §10.1",
    title: "Status and filter chips",
    lede: "Two different objects that look superficially similar: a status chip reports state and is never clickable; a filter chip is a control and always is." },

  { file: "data.html", out: "components/tables-and-cards.html", group: "Components",
    name: "Tables, cards & KPIs", subtitle: "Sticky headers, KPI anatomy, exception cards",
    id: "C-04", refs: "Guideline §5.5, §6.3",
    title: "Tables, cards and KPI anatomy",
    lede: "Operational tables lead with status, owner and SLA age. Every KPI carries its denominator, definition, source and freshness — there are no bare numbers in this system." },

  { file: "filters.html", out: "components/filters.html", group: "Components",
    name: "Search, filters & views", subtitle: "Scoped search, active-filter chips, saved views",
    id: "C-05", refs: "Guideline §5.3",
    title: "Search, filters and saved views",
    lede: "Search always shows its scope. Three to five filters stay inline and the rest move to a side sheet, with the active set visible and individually removable." },

  { file: "overlays.html", out: "components/overlays.html", group: "Components",
    name: "Dialogs & sheets", subtitle: "Dialog, right sheet, bottom sheet, full page",
    id: "C-06", refs: "Guideline §5.6",
    title: "Dialogs, sheets and confirmation",
    lede: "Four containers with non-overlapping jobs. Choosing the wrong one is the most common way an enterprise workflow starts to feel unpredictable." },

  { file: "evidence.html", out: "components/evidence.html", group: "Components",
    name: "Evidence & machine advisory", subtitle: "Veiled media, comparison, advisory block",
    id: "C-07", refs: "Guideline §8.13, §10.2",
    title: "Evidence and the machine advisory",
    lede: "Sensitive media is veiled by default and logged on view. The machine result is a visibly separate object from the human decision, and never shows a raw score." },

  { file: "states.html", out: "components/states.html", group: "Components",
    name: "Empty, loading & failure", subtitle: "8 designed states incl. permission & delayed data",
    id: "C-08", refs: "Guideline §9.4, §13.2",
    title: "Empty, loading and failure states",
    lede: "Every state is designed. An error explains the correction and preserves the user's work; an empty screen says whether the record is missing, out of scope, or creatable." },

  { file: "charts.html", out: "components/charts.html", group: "Components",
    name: "Chart patterns", subtitle: "Funnel, trend, ranked, 100% stacked, stat tile",
    id: "C-09", refs: "Guideline §6.1–6.3",
    title: "Chart patterns",
    lede: "Five forms, each answering one question. Colour is assigned by the job it does — identity, order, or state — and validated against both surfaces before it ships." },

  { file: "shell.html", out: "components/shell.html", group: "Components",
    name: "Application shell", subtitle: "Drawer, app bar, mobile field shell",
    id: "C-10", refs: "Guideline §3.1–3.3",
    title: "Application shell and navigation",
    lede: "The existing Sales Ecosystem shell with Campaign Management added as a parent module. The field shell is a different animal: four destinations, no territory switcher on the capture path." },

  // ---- 03 Web · Campaign ------------------------------------------------
  { file: "w01-dashboard.html", out: "screens/web/w-01-campaign-dashboard.html", group: "Web · Campaign",
    name: "W-01 Campaign dashboard", subtitle: "Exception-first; activity separated from outcome",
    id: "W-01", refs: "CM-FR-080…087", viewport: { width: 1600, height: 1400 },
    title: "Campaign dashboard",
    lede: "Opens on the action backlog, not on totals. Verified attendance and commercial outcome are separated so activity is never mistaken for sales impact." },

  { file: "w02-list.html", out: "screens/web/w-02-campaign-list.html", group: "Web · Campaign",
    name: "W-02 Campaign list", subtitle: "Scoped discovery; exception-first sort",
    id: "W-02", refs: "CM-FR-001…007", viewport: { width: 1600, height: 1150 },
    title: "Campaign list",
    lede: "Default sort is active exception then upcoming date — never alphabetical. Returned and unapproved campaigns are the ones you must not have to hunt for." },

  { file: "w03-wizard.html", out: "screens/web/w-03-campaign-wizard.html", group: "Web · Campaign",
    name: "W-03 Create/edit wizard", subtitle: "5 steps, draft-safe, validation summary",
    id: "W-03", refs: "CM-FR-001…014", viewport: { width: 1600, height: 1300 },
    title: "Create / edit campaign wizard",
    lede: "Five steps that refuse to let an incomplete schedule, audience, target or session configuration reach an approver." },

  { file: "w04-approval.html", out: "screens/web/w-04-campaign-approval.html", group: "Web · Campaign",
    name: "W-04 Campaign approval", subtitle: "Two-column; SoD; acknowledge-to-enable",
    id: "W-04", refs: "CM-FR-003…006", viewport: { width: 1600, height: 1250 },
    title: "Campaign approval",
    lede: "The plan on the left, the decision on the right. Approve stays disabled until the reviewer acknowledges every critical warning, and returning requires a reason." },

  { file: "w05-detail.html", out: "screens/web/w-05-campaign-detail.html", group: "Web · Campaign",
    name: "W-05 Detail & sessions", subtitle: "6 tabs, session cards, readiness panel",
    id: "W-05", refs: "CM-FR-010…014", viewport: { width: 1600, height: 1350 },
    title: "Campaign detail and session operations",
    lede: "One operational source for the campaign. Session cards carry the counts that matter — registered, pending sync, in review, approved — and readiness is checked before activation." },

  { file: "w06-registration.html", out: "screens/web/w-06-registration.html", group: "Web · Campaign",
    name: "W-06 Registration workspace", subtitle: "Master search → basket; no shadow records",
    id: "W-06", refs: "CM-FR-020…026", viewport: { width: 1600, height: 1300 },
    title: "Registration workspace",
    lede: "Every participant resolves to one Sales Eco carpenter identity. There is no free-text path to a registration, and no local shadow master." },

  { file: "w07-import.html", out: "screens/web/w-07-bulk-import.html", group: "Web · Campaign",
    name: "W-07 Bulk import", subtitle: "Upload → dry run → row detail → commit",
    id: "W-07", refs: "CM-FR-030…036", viewport: { width: 1600, height: 1350 },
    title: "Bulk import job and results",
    lede: "Large imports are safe, explainable and idempotent. There is no generic “upload failed” — every row has a stable ID, an outcome and a corrective action." },

  // ---- 04 Mobile · Field -----------------------------------------------
  { file: "m01-readiness.html", out: "screens/mobile/m-01-session-readiness.html", group: "Mobile · Field",
    name: "M-01 Session readiness", subtitle: "Pre-flight checks; blocking vs optional",
    id: "M-01", refs: "CM-FR-010…013, NFR-04/13", viewport: { width: 1320, height: 1000 },
    title: "Session readiness and mobile overview",
    lede: "Confirms the user, device and session before capture begins — and distinguishes a warning you may proceed past from a block you may not." },

  { file: "m02-search.html", out: "screens/mobile/m-02-carpenter-search.html", group: "Mobile · Field",
    name: "M-02 Carpenter search", subtitle: "Search, similar-name guard, confirmation card",
    id: "M-02", refs: "CM-FR-020, 021, 040", viewport: { width: 1320, height: 1000 },
    title: "Carpenter search and selection",
    lede: "Selecting the wrong carpenter is the most expensive mistake in the field. Similar names demand a second identity cue, and the photo is only ever one cue." },

  { file: "m03-capture.html", out: "screens/mobile/m-03-notice-and-capture.html", group: "Mobile · Field",
    name: "M-03 Notice & capture", subtitle: "Bilingual notice → framing → quality → submit",
    id: "M-03", refs: "CM-FR-041…046", viewport: { width: 1600, height: 1050 },
    title: "Purpose notice and camera capture",
    lede: "The participant is told what is being collected and why, in their language, before the camera opens. Framing guidance stays neutral; red means a real failure." },

  { file: "m04-queue.html", out: "screens/mobile/m-04-offline-queue.html", group: "Mobile · Field",
    name: "M-04 Offline queue", subtitle: "Capture success ≠ upload success",
    id: "M-04", refs: "CM-FR-044, NFR-04/09", viewport: { width: 1320, height: 1050 },
    title: "Offline queue and capture status",
    lede: "The screen that protects the field user's work. Nothing here suggests recapturing something that is merely waiting to upload." },

  // ---- 05 CRM -----------------------------------------------------------
  { file: "c01-queue.html", out: "screens/crm/c-01-verification-queue.html", group: "CRM · Verification",
    name: "C-01 Verification queue", subtitle: "SLA/risk sort; bulk assign, never bulk approve",
    id: "C-01", refs: "CM-FR-060, 067", viewport: { width: 1600, height: 1250 },
    title: "CRM verification queue",
    lede: "Sorted by SLA and risk, not by arrival. Cases can be assigned in bulk because assignment is reversible; they can never be approved in bulk because a decision is not." },

  { file: "c02-case.html", out: "screens/crm/c-02-verification-case.html", group: "CRM · Verification",
    name: "C-02 Verification case", subtitle: "Evidence | context | decision; advisory separated",
    id: "C-02", refs: "CM-FR-061…066", viewport: { width: 1600, height: 1300 },
    title: "CRM verification case",
    lede: "Three zones, one decision. Both images share a crop and scale so the comparison is fair, and the machine's opinion sits visibly outside the decision panel." },

  // ---- 06 Analytics -----------------------------------------------------
  { file: "a01-carpenter360.html", out: "screens/analytics/a-01-carpenter-360.html", group: "Analytics",
    name: "A-01 Carpenter 360", subtitle: "Identity, campaigns, attendance, canonical orders",
    id: "A-01", refs: "CM-FR-070…076", viewport: { width: 1600, height: 1300 },
    title: "Carpenter 360",
    lede: "One role-scoped profile. All orders and campaign-attributed orders are separate summaries, and pieces are the canonical unit — MT and RFT are secondary conversions." },

  { file: "a02-analytics.html", out: "screens/analytics/a-02-campaign-analytics.html", group: "Analytics",
    name: "A-02 Analytics & ROI", subtitle: "Funnel, verification mix, attribution, cost",
    id: "A-02", refs: "CM-FR-080…087", viewport: { width: 1600, height: 1500 },
    title: "Campaign analytics and ROI",
    lede: "Campaign-linked contribution is labelled as exactly that, and kept apart from incremental uplift and ROI. One canonical order ID, counted once." },

  { file: "a03-integrity.html", out: "screens/analytics/a-03-integrity-operations.html", group: "Analytics",
    name: "A-03 Integrity & operations", subtitle: "Explainable signals; no composite fraud score",
    id: "A-03", refs: "CM-FR-087, 090…095", viewport: { width: 1600, height: 1300 },
    title: "Integrity and operations dashboard",
    lede: "Surfaces suspicious patterns as explainable raw facts. There is no composite fraud score, and no automated accusation — only evidence a human can act on." },

  // ---- 07 Administration ------------------------------------------------
  { file: "ad01-config.html", out: "screens/admin/ad-01-configuration-audit.html", group: "Administration",
    name: "AD-01 Configuration & audit", subtitle: "Versioned config, effective dating, before/after audit",
    id: "AD-01", refs: "CM-FR-090…095", viewport: { width: 1600, height: 1300 },
    title: "Configuration, audit and support",
    lede: "Campaign behaviour is configurable and every material change is traceable — with reason, approval, effective date and a before/after audit row." },
];

/* -------------------------------------------------------------------------- */

const css = ["tokens.css", "system.css", "docs.css"]
  .map((f) => readFileSync(join(SRC, f), "utf8"))
  .join("\n");

function head(card) {
  return `    <header class="ds-head">
      <div class="ds-head__eyebrow">
        <span class="ds-head__id">${card.id}</span>
        <span class="ds-head__ref">${card.refs}</span>
      </div>
      <h1 class="ds-head__title">${card.title}</h1>
      <p class="ds-head__lede">${card.lede}</p>
    </header>`;
}

function document_(card, body) {
  const vp = card.viewport ?? { width: 1280, height: 900 };
  return `<!-- @dsCard group="${card.group}" name="${card.name}" subtitle="${card.subtitle}" viewport="${vp.width}x${vp.height}" -->
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${card.name} — BMD / ACSL Campaign Management</title>
<style>
${css}
</style>
</head>
<body>
  <main class="ds-page">
${head(card)}
${body}
  </main>
</body>
</html>
`;
}

/* --- partials -------------------------------------------------------------
   `<!--@include partials/name.html-->` splices in a shared fragment, keeping a
   single copy of the shell markup across every screen specimen. The current
   navigation item is chosen declaratively via data-nav on the shell, so the
   partial itself needs no parameters. One level of nesting is resolved.
   -------------------------------------------------------------------------- */
function expandIncludes(html, depth = 0) {
  if (depth > 2) return html;
  return html.replace(/^([ \t]*)<!--@include\s+([^\s>]+?)\s*-->[ \t]*$/gm, (m, indent, rel) => {
    const p = join(SRC, rel);
    if (!existsSync(p)) { problems.push(`missing partial ${rel}`); return m; }
    const part = readFileSync(p, "utf8").trimEnd();
    const indented = part.split("\n").map((l) => (l.trim() ? indent + l : l)).join("\n");
    return expandIncludes(indented, depth + 1);
  });
}

/* --- self-check ----------------------------------------------------------- */
const problems = [];
const warnings = [];

function selfCheck(card, out, html) {
  const first = html.split("\n", 1)[0];
  if (!first.startsWith("<!-- @dsCard ")) problems.push(`${out}: first line is not a @dsCard marker`);
  if (!/group="[^"]+"/.test(first)) problems.push(`${out}: @dsCard marker has no group`);

  // CSP: nothing may reach off-page.
  const ext = html.match(/(?:src|href)\s*=\s*"(?!#)(https?:)?\/\/[^"]*"/gi);
  if (ext) problems.push(`${out}: external reference(s) ${ext.slice(0, 3).join(", ")}`);
  if (/<script/i.test(html)) warnings.push(`${out}: contains a <script> tag`);

  // Every colour must come from a token, so no raw hex may be *used* as a value.
  // Hex printed as text is fine — the colour spec sheet has to show the values.
  const body = html.slice(html.indexOf("</style>"));
  const styleAttrs = body.match(/style\s*=\s*"[^"]*"/gi) ?? [];
  const hex = styleAttrs.join(";").match(/#[0-9a-fA-F]{3,8}\b/g);
  if (hex) {
    const uniq = [...new Set(hex.map((h) => h.toUpperCase()))];
    warnings.push(`${out}: raw hex used as a value in a style attribute (${uniq.slice(0, 4).join(", ")}) — reference a token instead`);
  }

  const open = (html.match(/<div\b/g) ?? []).length;
  const close = (html.match(/<\/div>/g) ?? []).length;
  if (open !== close) problems.push(`${out}: unbalanced <div> — ${open} open vs ${close} close`);

  const bodyBytes = Buffer.byteLength(body, "utf8");
  if (bodyBytes < 1200) warnings.push(`${out}: thin specimen (${bodyBytes} B of markup)`);
  return bodyBytes;
}

/* --- build --------------------------------------------------------------- */
let built = 0;
const rows = [];

for (const card of CARDS) {
  const srcPath = join(PAGES, card.file);
  if (!existsSync(srcPath)) { problems.push(`${card.out}: missing source src/pages/${card.file}`); continue; }
  const body = expandIncludes(readFileSync(srcPath, "utf8").trimEnd());
  const html = document_(card, body);
  const outPath = join(DIST, card.out);
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, html, "utf8");
  const bytes = selfCheck(card, card.out, html);
  rows.push({ card: card.name, group: card.group, out: card.out, markup: bytes });
  built++;
}

/* An index page so the bundle can be reviewed in a browser as one system. */
const byGroup = new Map();
for (const c of CARDS) {
  if (!byGroup.has(c.group)) byGroup.set(c.group, []);
  byGroup.get(c.group).push(c);
}
const indexBody = [...byGroup.entries()].map(([group, cards]) => `
    <section class="ds-block">
      <div class="ds-block__head"><h2 class="ds-block__title">${group}</h2>
        <span class="ds-block__note">${cards.length} specimen${cards.length === 1 ? "" : "s"}</span></div>
      <div class="ds-swatches">
${cards.map((c) => `        <a class="card" style="padding:var(--space-4);text-decoration:none;display:flex;flex-direction:column;gap:var(--space-1)" href="${"../".repeat(0)}${c.out}">
          <span class="t-micro">${c.id}</span>
          <span class="t-card">${c.name}</span>
          <span class="t-caption">${c.subtitle}</span>
        </a>`).join("\n")}
      </div>
    </section>`).join("\n");

writeFileSync(join(DIST, "index.html"), `<!-- @dsCard group="Overview" name="Index" subtitle="Every specimen in the bundle" viewport="1280x900" -->
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>BMD / ACSL Campaign Management — design system</title>
<style>
${css}
</style></head>
<body><main class="ds-page">
  <header class="ds-head">
    <div class="ds-head__eyebrow"><span class="ds-head__id">v1.0</span>
      <span class="ds-head__ref">BMD Sales Ecosystem · ACSL Carpenter Campaign Management</span></div>
    <h1 class="ds-head__title">Design system</h1>
    <p class="ds-head__lede">Foundations, components and the full screen inventory, built on the BMD brand layer with Material 3 as the interaction foundation.</p>
  </header>
${indexBody}
</main></body></html>
`, "utf8");

/* --- report -------------------------------------------------------------- */
console.log(`built ${built}/${CARDS.length} specimens → design/dist\n`);
const widest = Math.max(...rows.map((r) => r.out.length), 4);
for (const [group, cards] of byGroup) {
  console.log(`  ${group}`);
  for (const c of cards) {
    const r = rows.find((x) => x.out === c.out);
    if (r) console.log(`    ${r.out.padEnd(widest)}  ${String(r.markup).padStart(6)} B`);
  }
}
if (warnings.length) {
  console.log(`\nwarnings (${warnings.length}):`);
  for (const w of warnings) console.log(`  ! ${w}`);
}
if (problems.length) {
  console.log(`\nPROBLEMS (${problems.length}):`);
  for (const p of problems) console.log(`  x ${p}`);
  process.exitCode = 1;
} else {
  console.log(`\nself-check passed: markers present, no external references, balanced markup.`);
}
