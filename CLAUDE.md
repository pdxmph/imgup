# imgup

Personal Sinatra app: upload photos to SmugMug from a web GUI or CLI, get back markdown/HTML/org snippets for blog posts.

Single user (Mike). No onboarding, no marketing-page energy, no second user to design for.

## Design Context

### Users

Single user: Mike. Photographer who blogs (indie-web, omg.lol-adjacent) and uses imgup as a private workshop for getting images out of his camera and into posts. Comfortable in terminals, writes in Markdown and Org-mode, uses Emacs daily.

**Context of use:** at his desk, mid-post, needs an image hosted *now* and the embed snippet on his clipboard with minimum friction.

**Jobs to be done (in priority order):**
1. Upload a photo → SmugMug → get back a copy-pasteable markdown/HTML/org snippet.
2. Browse recent uploads to grab the snippet for an image already uploaded.
3. Authenticate with SmugMug once and forget about it.

There is no second user. No onboarding flow needs to exist. No marketing-page energy.

### Brand Personality

**Three words: darkroom, terminal, personal.**

- **Voice:** terse, knowing, first-person. Speaks to Mike, not to a user base. No "Welcome to imgup!" copy. No empty exclamation points.
- **Emotional target:** focus, craftsmanship, "this is mine." The feeling of stepping into a private workspace, not opening a SaaS dashboard.
- **Not:** productivity tool, hosted service, generic admin panel, "cool dark theme."

### Aesthetic Direction

**Concept: photographic darkroom × terminal.** A personal photographer's workshop rendered as a proper, opinionated terminal — not the generic Catppuccin dev-tool look that's currently doing the work. The red accent isn't decoration; it's a *safelight* reference. Light mode is the inverse: a warm-paper printing log, deep ink on cream, like a contact-sheet annotated by hand.

**Both themes are first-class.** Dark = darkroom under safelight. Light = print on warm paper. Toggleable. System preference respected on first load.

**Typography:**
- **Pair a distinctive monospace with an editorial serif.** Examples to choose from: Berkeley Mono, MD IO, Departure Mono, IBM Plex Mono, JetBrains Mono Variable for the mono side; Newsreader, Fraunces, ET Book, or a kept-and-tuned Neuton for the serif. The current Fira Mono is fine but unremarkable — upgrade if a better-character mono is available.
- **Avoid:** Inter, Roboto, Open Sans, Arial, system-default sans, generic Google-Fonts pairings.

**Color:**
- **Warm-tinted neutrals across the board.** No cool grays. No Catppuccin Mocha-as-shipped.
- **Dark mode:** deep red-black background, amber/warm-red type at low brightness, oxblood-red as the single accent (the safelight). Tinted-warm "neutrals" for surfaces.
- **Light mode:** warm cream/paper background, deep iron-ink type, oxblood-red accent. Should look like an actual printed page, not a flipped-bit version of the dark theme.
- **One signature accent.** No rainbow palette. No gradients on text.

**Layout:**
- Asymmetric, generous space. Photos are the punctuation, not the wallpaper.
- The current 75/20 column split on the post-image page is the right idea (snippet block left, thumbnail right) but the execution is float-based and crude. Modernize without losing the structure.
- Snippet blocks (markdown, org, html) are first-class objects — they should feel like terminal output, not afterthought textareas.

**Permitted flourishes (only when they earn it):**
- Contact-sheet sequence numbers on recent uploads.
- Crop-mark corners on photo frames.
- Hairline rules drawn like printer's marks.

**Anti-references / explicit don'ts:**
- Catppuccin Mocha as currently shipped (generic dev aesthetic).
- Glassmorphism, blurred panels, glowing borders.
- Gradient text or "impact" gradients on metrics/headings.
- Cyan-on-dark / purple-blue-gradient AI palette.
- Identical card grids; rounded-rect-with-drop-shadow card spam.
- Hero metric layouts (big number, small label, sparkline).
- FontAwesome used as decoration above headings rather than as functional iconography.
- Marketing-page copy of any kind.

### Design Principles

1. **Terminal precision, photographic warmth.** Density, monospace, sharp edges — but warmed with paper / ink / safelight, not cool blue dev-mode dark.
2. **The photo is the subject. The chrome disappears.** Anything that competes with the thumbnail or the copy-able snippet block is a bug.
3. **Personal tool = personal voice.** Speak in shorthand to one user. No third-person product copy. No "Welcome." No marketing.
4. **Dark and light are equally first-class.** Both are intentional, distinct looks — not "default" plus "afterthought."
5. **Earn every flourish.** A crop-mark, a contact-sheet number, a frame border — only when it expresses something. No decoration for decoration's sake.
