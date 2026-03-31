---
name: omk-stitch
triggers: "stitch|design.?to.?code|UI.?design|visual.?compare|screen.*code|figma.*stitch|设计稿|设计.*代码|视觉.*对比|design.?md|design.?system|shadcn.*stitch|redesign"
description: >
  Google Stitch design-to-code workflow with design system management.
  Trigger when user mentions Stitch, design-to-code, UI design, visual comparison,
  design.md, design system, ShadCN conversion, redesign from screenshot, or wants
  to pull designs from Stitch into local code. Also trigger when user says
  '做个页面', 'build a landing page', '用 Stitch 设计', 'convert design',
  'export from Stitch', '设计系统', or uploads wireframes/screenshots for UI generation.
metadata:
  pattern: tool-wrapper
  domain: design
---

## Trigger Examples
- "Pull my Stitch designs into code"
- "用 Stitch 做个落地页"
- "把这个截图的风格用到我的网站上"
- "Export design.md from my Stitch project"
- "Convert Stitch design to ShadCN components"

# Google Stitch Integration Skill

## Core Concept: design.md

Stitch's design system is captured in a `design.md` file — colors, fonts, themes, component styles. This file is:
- **Agent-optimized** — uses targeted language agents understand better than raw CSS
- **Transferable** — give it to Claude Code, Cursor, or any agent and they reproduce the style perfectly
- **Auto-created** — Stitch generates one for every project, even if you don't ask

**Default workflow**: Always start by establishing a design.md, then build pages on top of it.

## MCP Server

Community package: [davideast/stitch-mcp](https://github.com/davideast/stitch-mcp)
npm: `@_davideast/stitch-mcp`

## Setup

### Prerequisites
- Google Cloud CLI (`gcloud`) installed
- A GCP project with Stitch API enabled

### Authentication (OAuth — API Key is NOT supported)

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <YOUR_PROJECT_ID>
gcloud auth application-default set-quota-project <YOUR_PROJECT_ID>
gcloud beta services mcp enable stitch.googleapis.com --project=<YOUR_PROJECT_ID>
```

### MCP Config

Add to your MCP client config (e.g. `.kiro/settings/mcp.json`):
```json
{
  "stitch": {
    "command": "npx",
    "args": ["@_davideast/stitch-mcp", "proxy"],
    "env": {
      "STITCH_USE_SYSTEM_GCLOUD": "1",
      "GOOGLE_CLOUD_PROJECT": "<YOUR_PROJECT_ID>"
    }
  }
}
```

CRITICAL: Must use `proxy` mode + `STITCH_USE_SYSTEM_GCLOUD=1`. Direct serverUrl mode is unstable.

### Verify Setup

```bash
npx @_davideast/stitch-mcp doctor
```

If `doctor` times out on API test, verify directly:
```bash
ACCESS_TOKEN=$(gcloud auth application-default print-access-token)
curl -s -w "\nHTTP:%{http_code}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-goog-user-project: <YOUR_PROJECT_ID>" \
  "https://stitch.googleapis.com/v1/projects"
```

## MCP Tools

| Tool | Purpose |
|------|---------|
| `list_projects` | List all Stitch projects |
| `get_screen_code` | Get HTML/CSS for a screen |
| `get_screen_image` | Get screen screenshot (base64) |
| `build_site` | Map screens to routes, generate Astro project |

## CLI Tools (non-MCP)

```bash
npx @_davideast/stitch-mcp view --projects          # Browse projects
npx @_davideast/stitch-mcp serve -p <project-id>    # Local preview
npx @_davideast/stitch-mcp site -p <project-id>     # Generate Astro site
```

## Workflows

### Path A: Design from Scratch (Default)

1. **Establish design system** — Create or provide a `design.md` in Stitch (auto-created if not specified)
2. **Generate screens** — Prompt Stitch with your requirements; it builds on the design system
3. **Pull to local** — `get_screen_code` → HTML/CSS, `get_screen_image` → screenshot
4. **Implement** — Convert to target framework (Next.js/Astro/React)
5. **Verify** — Visual comparison (see Phase: Verification below)

### Path B: Redesign from Reference

Use when you have an existing site/screenshot whose style you want to adopt (not copy):

1. **Capture reference** — Full-page screenshot of the site you like (use GoFullPage or similar)
2. **Redesign in Stitch** — Upload screenshot; Stitch extracts design language, component patterns, and layout — then applies them to YOUR content
3. **Alternative: Import via URL** — In Stitch's design system panel, import from any website URL. Stitch crawls it and extracts typography + colors as a design.md
4. **Refine** — Upload wireframes or annotate specific sections to adjust

### Path C: Agent-Integrated Build (Claude Code + Stitch)

For autonomous end-to-end builds using Google's official Stitch skills:

1. **Enhanced Prompt** — Converts vague user prompts into Stitch-optimized prompts (Stitch relies on adjectives for mood, not exact descriptions)
2. **Stitch Loop** — Autonomous build loop using Chrome DevTools, maintains prompt tracking across stages
3. **React Components** — Converts Stitch's monolithic HTML export into modular React components with validation

Workflow order in `claude.md`:
```
Enhanced Prompt → Stitch Loop → React Component conversion
```

Requires Stitch MCP connected. See [Google's Stitch skills repo](https://github.com/nicepkg/stitch-skills) for installation.

### Path D: ShadCN UI Conversion

Bare React/HTML from Stitch lacks interactions. Use ShadCN for production-quality components:

1. Connect ShadCN MCP
2. Use Google's ShadCN UI skill to convert Stitch designs into ShadCN components
3. Extend with registries (e.g. glassmorphism, motion-primitives) for premium feel
4. Specify registries in `claude.md` so conversion is automatic

## Phase: Verification (inspired by gstack design-review)

After implementation, run a multi-layer verification. The goal: catch what human eyes miss.

### Layer 1: Multi-Viewport Screenshots

Take screenshots at 3 breakpoints to catch responsive issues:

```bash
npx playwright screenshot --viewport-size=375,812 http://localhost:3000 impl-mobile.png
npx playwright screenshot --viewport-size=768,1024 http://localhost:3000 impl-tablet.png
npx playwright screenshot --viewport-size=1440,900 http://localhost:3000 impl-desktop.png
```

Check for: text overflow, layout collapse, elements overlapping, content not adapting.

### Layer 2: Design System Consistency Check

Extract actual rendered values from the implementation and compare against design.md:

```bash
# Extract fonts actually used (run in browser console or Playwright)
npx playwright evaluate http://localhost:3000 \
  "JSON.stringify([...new Set([...document.querySelectorAll('*')].slice(0,500).map(e => getComputedStyle(e).fontFamily))])"

# Extract color palette in use
npx playwright evaluate http://localhost:3000 \
  "JSON.stringify([...new Set([...document.querySelectorAll('*')].slice(0,500).flatMap(e => [getComputedStyle(e).color, getComputedStyle(e).backgroundColor]).filter(c => c !== 'rgba(0, 0, 0, 0)'))])"
```

Compare extracted values against design.md tokens. Flag deviations.

### Layer 3: Pixel Diff vs Design

```bash
npx pixelmatch design.png impl-desktop.png diff.png 0.1
```

### Layer 4: AI Slop Detection

Check the implementation for these 10 AI-generated patterns (from gstack's blacklist):

1. Purple/violet gradient backgrounds as default
2. 3-column feature grid with icon-in-circle + title + description
3. Icons in colored circles as section decoration
4. `text-align: center` on everything
5. Uniform bubbly border-radius on all elements
6. Decorative blobs, wavy SVG dividers
7. Emoji as design elements
8. Colored left-border on cards
9. Generic hero copy ("Welcome to X", "Unlock the power of...")
10. Cookie-cutter section rhythm (hero → features → testimonials → pricing → CTA)

If ≥3 patterns detected, flag as "AI slop risk" and suggest specific fixes.

### Layer 5: AI Visual Diff

Feed both design.png and impl-desktop.png to the LLM for comparison. Ask specifically:
- Does the hierarchy match?
- Are spacing proportions preserved?
- Any missing sections or elements?

### Refinement Loop

After verification, iterate:
1. Show user the screenshots + diff results
2. User provides feedback
3. Apply surgical edits (don't regenerate entire files)
4. Re-verify
5. Repeat until "done" (max 10 rounds)

## design.md Tips

- **Template**: Get the agent-optimized template from Google's official skills repo
- **Transfer**: Give design.md to any agent (Claude Code, Cursor) for consistent styling
- **Extract**: Use Google's "design MD skill" to extract design.md from existing Stitch projects
- **Custom**: Create your own design.md with colors/fonts/themes, paste into Stitch's design system panel

## Known Issues

1. **API Key auth broken** — Stitch API rejects API keys, must use OAuth (confirmed 2026-02 by community)
2. **`doctor` fetch timeout** — Network-dependent; direct curl test is more reliable
3. **Billing not required** — Stitch API works on projects without billing enabled
4. **Experimental mode no Figma export** — Only Standard mode supports Figma export
