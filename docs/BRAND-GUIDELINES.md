# Loupe Brand Guidelines

Loupe 2.0 brand: **coral on ink**. This document is the source of truth for how Loupe looks and sounds in the app, on the website (loupemac.app), in the README and in release notes. When the code and this document disagree, fix one of them; don't let them drift.

---

## Brand essence

### What Loupe is
A free, open-source Mac app for people building Mac apps with coding agents. You point at a button, label or menu in a running Mac app, write what you want changed, and your agent gets a note that says exactly which element you meant. With Agent Link, the agent reads your notes directly, asks when it isn't sure, and tells you when it's done, right in Loupe.

### Name
"Loupe" is the jeweler's magnifier used for close, careful work. In 2.0 the metaphor is literal and friendly: the icon *is* a jeweler's loupe, seen from above, with a coral rim.

### Headline
> **Point at your Mac app. Your agent fixes it.**

Use it on the website hero, the README, the page title and social cards. It replaces the 1.x tagline "Target elements, not screenshots."

### What it does for people
- Point at any element in any running Mac app and leave a note on it.
- Give your coding agent the exact element, its place in the app, and words to search for in the code.
- With Agent Link, skip copying and pasting: the agent reads your notes, asks questions, and reports back in Loupe.
- Agents can look at the app you picked but can never click or type in it.

---

## Personality and voice

**A builder talking to builders.** First person, plain and honest. Brent made this for himself and shares it.

| Do | Don't |
|----|-------|
| "Loupe is a free Mac app I built for working with coding agents." | "Loupe leverages advanced accessibility APIs to facilitate AI-driven workflows." |
| "Point at a button and write what you want changed." | "Unlock precision element targeting." |
| "Your agent can look, but it can never click or type." | "Enterprise-grade safety guarantees." |

### Traits
- **Practical:** does one job well.
- **Honest:** says what it can't do as clearly as what it can.
- **Precise:** the whole point is the exact element, so the words are exact too.
- **Approachable:** no setup jargon; every step says what you'll see.
- **Humble:** a tool, not a platform.

### What we're not
- Not an ecosystem or a platform play.
- Not monetized, no lock-in.
- Not loud: one accent colour, used with restraint.

### Copy rules
- **No em dashes in anything a user sees**: the app, website, README, release notes, onboarding, notifications. Use periods, commas, colons or parentheses. (Internal docs like this one may use them, but prefer not to.)
- **Plain language over technical terms.** Say "the app you picked", not "the target process". When a technical word is unavoidable, explain it in the same sentence.
- **Name the permission as macOS names it:** "Device Control and Data Access" on macOS 27 and later, "Accessibility" on earlier versions.
- **Agent safety, said plainly:** agents can look but never click or type. Agent Link is off until you turn it on.
- **Name agents by product:** Claude Code, Codex, Cursor, Xcode. "Your coding agent" when it could be any of them.
- **Buttons say what happens:** "Copy setup command", "Add to Cursor", "Send", "Reopen".

### Naming
- "Loupe" (capitalised, no article). "the Loupe app" only when needed for clarity.
- "Agent Link" (both words capitalised) for the connection between Loupe and coding agents.
- "note" for what a person leaves on an element (not "annotation" in user-facing copy).
- Don't write "LOUPE", "The Loupe", "loupe" in headings, or "Loupe.app" in copy.

---

## Audience

**Primary:** solo developers and designers building Mac apps with coding agents (Claude Code, Codex, Cursor, Xcode's built-in agents).
**Secondary:** small teams doing the same.

They already use AI tools, are tired of describing UI in screenshots, and want something that works without setup friction. They appreciate open source.

---

## Colour

One accent (coral) on warm neutrals (ink and paper). Coral marks what matters: the element you're pointing at, your notes, and anything that needs you.

### Core palette

| Name | Hex | Use |
|------|-----|-----|
| **Coral** | `#ff5b3a` | The brand colour. Shapes, outlines, icons, the hover outline, the icon's rim, the menu bar dot. Never for small text. |
| **Coral, strong** | `#d63d1f` | Behind white text: note badges, numbered steps, prominent buttons. White on it is 4.6:1. Also the app's accent colour. |
| **Ink** | `#14161b` | The icon background and dark surfaces. The dark-mode page background. |
| **Paper** | `#f6f3ee` | The light-mode page background on the website. |

### Coral for text
Coral text must stay readable, so it shifts with the mode:

| Where | Light mode | Dark mode |
|-------|-----------|-----------|
| App (`loupeAccentText`) | `#d63d1f` | `#ff7a5c` |
| Website (`--coral-text`) | `#c5391b` | `#ff7a5c` |

The app and website use slightly different light-mode text corals; both pass 4.5:1 on their backgrounds. If you touch either, align them on one value.

### Status colours
Status colour tells you what a note needs. Keep these distinct from coral so "your turn" never looks like "waiting".

| Status | App | Website (light / dark) |
|--------|-----|------------------------|
| Waiting, agent working | coral text | coral text |
| Question for you, agent replied | system blue | `#3f6fd8` / `#7aa7ff` |
| Done | system green | `#1a8f5e` / `#3ccf8e` |
| Dismissed | secondary grey | grey |

### Neutrals
- **App:** use system colours and materials (Liquid Glass, `.secondary` text). Don't hard-code greys.
- **Website:** `--card #fffdf9`, `--muted #625e57`, `--line #ded8cd` in light; `--card #1c1f26`, `--muted #a9a59e`, `--line #30343d` in dark. See `docs/index.html`.

### Contrast rules
- Body and caption text on glass or paper uses **primary or secondary** emphasis, never tertiary or quaternary (they disappear on light glass).
- White text only on **Coral, strong** (`#d63d1f`), never on brand coral (`#ff5b3a` is 3.1:1 with white).
- Controls that show state (switches, segmented choices) keep their selected colour even when the window isn't focused, since Loupe's panels often aren't.

---

## Iconography

### App icon
A jeweler's loupe seen from above: a graphite barrel with a ridged grip and a **coral rim** around a dark glass lens, on an **ink** background.

- Built as a layered Icon Composer file: `Loupe/AppIcon.icon` (layers: barrel, rim, glass, glint). macOS renders it as Liquid Glass and handles the Dark, Clear and Tinted modes. Xcode generates flat versions for older macOS.
- Coral appears **only on the rim**. Don't add coral glows, coral glass or a coral barrel.
- Must read at 16 px: the coral ring is the part that survives.
- Web copy of the icon: `docs/icon.svg`.

### Menu bar icon
The lens seen head-on: a ring with a small glint, drawn as a one-colour **template image** so it follows the menu bar's colour (`Views/MenuBarIcon.swift`).

- When an agent has asked a question the person hasn't answered, a **coral dot** sits in a gap at the top right. The dot is the only colour in the menu bar, and it means "a note needs you".
- Don't use the side view of the barrel in the menu bar. It reads as a "database" icon at 16 pt.

### Floating button
When the toolbar is tucked away, it shows just the loupe on glass (`Views/LoupeMark.swift`), not the full app icon. The open-note count sits on the window's corner in **Coral, strong** and fades in after the icon settles.

### Other assets
- Social card: `docs/social-preview.png` (1200 × 630).
- Favicon and README icon: `docs/icon.svg`.
- Earlier explorations, kept for reference only: `docs/brand-2.0-directions.html`, `docs/brand-2.0-icons.html`, `docs/brand-2.0-icons-r2.html` (round two chose shape V4, "seen from above").

---

## In the app

### Inspection highlight
Coral (`loupeHighlight`), drawn as a solid 2 pt outline with a soft coral glow (8 pt at 30%, 5 pt at 50%) and an 8% coral fill, corner radius 6.

### Note badges
20 pt circles on the noted element with a white number and a white outline (3 pt when hovered).
- Open notes: **Coral, strong**.
- Done: green with a white check.
- Dismissed: grey.

### Motion
- The toolbar is one glass shape that grows out of the icon and shrinks back into it, always anchored to the icon's corner, with one lively spring for both directions.
- Respect the macOS Reduce Motion setting in new work: fade between states instead of moving them. (The toolbar doesn't do this yet.)
- Nothing should jump, pop in from an edge, or ride another element's spring (badges fade in once things have settled).

### Typography
System fonts only (SF Pro), sized with text styles so Dynamic Type and accessibility settings work.

---

## Website

- **Address:** https://loupemac.app, served by GitHub Pages from `docs/` on `main`. The domain is verified on Brent's GitHub account. The old address (`britchie4.github.io/Loupe`) redirects there and must keep working, because Loupe 1.2.1 checks for updates at `…/Loupe/appcast.xml`.
- **Structure:** hero (headline, a coded animation of Loupe in use), "Try it yourself" (an in-browser practice), how it works, what your agent can and can't do (Agent Link), get Loupe. The footer name links to brentritchie.dev.
- **Typography:** system fonts throughout (SF Pro for headings and body, SF Mono for code), matching the app. Bricolage Grotesque was dropped in November 2026 because it had become a common sign of AI-built sites.
- **Light and dark:** paper in light, ink in dark, following the visitor's setting.

---

## Code references

- App colours: `LoupePackage/Sources/LoupeFeature/Theme/LoupeColors.swift` (`loupeAccent`, `loupeAccentStrong`, `loupeAccentText`, `loupeAccentDim`, `loupeInk`, plus the aliases `loupeHighlight`, `loupeBadge`, `loupeSuccess`, `loupeActiveIcon`).
- App accent colour asset: `Loupe/Assets.xcassets/AccentColor.colorset` (Coral, strong).
- Website tokens: the `:root` block at the top of `docs/index.html`.

---

## Summary

| Element | Decision |
|---------|----------|
| Headline | Point at your Mac app. Your agent fixes it. |
| Voice | A builder talking to builders: first person, plain, honest |
| Accent | Coral `#ff5b3a`; Coral, strong `#d63d1f` behind white text |
| Base | Ink `#14161b`, Paper `#f6f3ee` |
| App icon | Jeweler's loupe seen from above, coral rim, ink background, layered for Liquid Glass |
| Menu bar | One-colour lens; coral dot when a note needs you |
| Type | System fonts (SF Pro) in the app and on the website |
| Copy | No em dashes in user-facing text; plain language |
| Website | loupemac.app on GitHub Pages |

*Last updated: November 2026 (Loupe 2.0)*
