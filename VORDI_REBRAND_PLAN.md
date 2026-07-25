# Vordi Rebrand Plan
> Vordi → Vordi + Landing page separation
> Run Codex and Claude tracks IN PARALLEL — they touch different things and won't conflict.

---

## CODEX TRACK — File content changes (mechanical, no GitHub API)

**Paste this prompt into Codex:**

```
You are working in the repo at /Users/raunaksingh/Documents/Vordi

The app is being rebranded from "Vordi" to "Vordi". Do all of the following in order:

---

### TASK 1 — Swift source files: replace brand name

In these files, replace every display-facing occurrence of "Vordi" with "Vordi".
DO NOT change bundle IDs, scheme names, binary names, or com.vordi.app — those must stay as-is.

Files to change:
- Sources/Views/DesignSystem.swift           → AppBrand.name value "Vordi" → "Vordi"
- Sources/Services/GitHubService.swift       → repoName "Vordi" → "Vordi", repoHTMLURL comment if any
- Sources/App/VordiApp.swift             → any UI-facing "Vordi" string only
- Sources/Views/MainDashboardView.swift      → any UI-facing "Vordi" string only
- Sources/Views/SettingsView.swift           → any UI-facing "Vordi" string only
- Sources/Views/MenuBarView.swift            → any UI-facing "Vordi" string only
- Sources/Services/LLMService.swift          → any "Vordi" in user-agent or display strings only
- Sources/Services/TextInjector.swift        → same rule
- Sources/Services/TransformerRouter.swift   → same rule
- Sources/Services/AudioRecorder.swift       → same rule
- Sources/Services/WhisperService.swift      → same rule
- Sources/Models/MagicWord.swift             → same rule
- Sources/Models/RunModel.swift              → same rule
- Sources/Models/TransformerProfile.swift    → same rule
- Sources/Services/HallucinationGuard.swift  → same rule
- Sources/Services/UserVocabulary.swift      → same rule
- Sources/Services/VoiceNoteStore.swift      → same rule
- Sources/Services/Memory/IndexerService.swift → same rule
- Sources/Services/Memory/MemoryStore.swift    → same rule
- Sources/Views/AccessibilityGuideView.swift   → same rule
- Sources/Views/DevModeSettingsView.swift      → same rule
- Sources/Views/InputMonitoringGuideView.swift → same rule
- Sources/Views/InsightsView.swift             → same rule
- Sources/Views/NotesWorkspaceView.swift       → same rule
- Sources/Services/Profiles/PromptEngineerProfile.swift → same rule

---

### TASK 2 — Markdown docs: full text replacement

In every .md file in the repo root and docs/ folder, replace:
- "Vordi" → "Vordi" (all occurrences, prose and headings)
- "vordi" → "vordi" (lowercase, in URLs and brew paths)
- GitHub URLs: github.com/Raunaks068619/Vordi → github.com/Raunaks068619/Vordi
- brew install path: raunaks068619/vordi/vordi → raunaks068619/vordi/vordi

Files:
- README.md
- INSTALL.md
- PERMISSIONS.md
- CONTEXT.md
- DESIGN.md
- FEATURES.md
- ONBOARDING_PLAN.md
- docs/run-log-feature-plan.md
- docs/future-agent-memory-app.md
- docs/notch-pill-impl.md
- homebrew-vordi/README.md

---

### TASK 3 — Rename VORDI_CONTEXT.md → VORDI_CONTEXT.md

Run: mv VORDI_CONTEXT.md VORDI_CONTEXT.md
Then inside the file replace all "Vordi" → "Vordi" and "vordi" → "vordi"

---

### TASK 4 — bump_cask.sh

In bump_cask.sh:
- Change CASK path from: homebrew-vordi/Casks/vordi.rb → homebrew-vordi/Casks/vordi.rb
- Change gh release --repo flag from: raunaksingh/vordi → Raunaks068619/Vordi
- Change brew install command: raunaks068619/vordi/vordi → raunaks068619/vordi/vordi
- Change release title: "Vordi $VERSION" → "Vordi $VERSION"
- Change release notes install hint: brew install --cask raunaks068619/vordi/vordi

---

### TASK 5 — Homebrew cask file rename + update

Run: mv homebrew-vordi/Casks/vordi.rb homebrew-vordi/Casks/vordi.rb

Then in homebrew-vordi/Casks/vordi.rb update:
- cask name: "vordi" → "vordi"
- name "Vordi" → "Vordi"
- homepage → https://github.com/Raunaks068619/Vordi
- url pattern: any github.com/Raunaks068619/Vordi → github.com/Raunaks068619/Vordi
  (keep the DMG filename Vordi-Beta.dmg unchanged — binary artifact)
  (keep app bundle "Vordi.app" unchanged — binary artifact)
  (keep bundle ID "com.vordi.app" unchanged — binary artifact)

---

### TASK 6 — web/ landing page: rename Vordi → Vordi in source files

In these web/ files, replace display-facing "Vordi" → "Vordi":
- web/src/app/layout.tsx
- web/src/app/page.tsx
- web/src/components/vordi/cta.tsx
- web/src/components/vordi/floating-chip.tsx
- web/src/components/vordi/macbook-scene.tsx
- web/src/components/vordi/notes-window.tsx
- web/src/components/vordi/obsidian-graph.tsx
- web/src/components/vordi/output-transforms.tsx
- web/src/remotion/vordi-demo.tsx

Also rename the component folder:
  mv web/src/components/vordi web/src/components/vordi

Update all import paths in web/src/ that referenced components/vordi/ → components/vordi/

---

### TASK 7 — scripts/ folder

In these scripts, replace any "Vordi" display strings and GitHub repo references:
- scripts/build-and-install.sh
- scripts/dev-run.sh
- scripts/release_dmg.sh
- scripts/release_dmg_unsigned.sh
- scripts/ship.sh
- scripts/verify_build.sh

Keep: Vordi.app, Vordi-Beta.dmg, com.vordi.app, Vordi scheme — unchanged.
Change: any "Vordi" in echo/print statements, --repo flags, release titles.

---

### TASK 8 — project.yml

In project.yml, replace any display-facing "Vordi" string.
Do NOT change: PRODUCT_NAME, scheme name, bundle ID, app target name — these stay as Vordi/com.vordi.app.

---

After all tasks are done, run:
  grep -r "Vordi\|vordi" --include="*.swift" --include="*.md" --include="*.sh" --include="*.rb" --include="*.yml" --include="*.tsx" --include="*.ts" . | grep -v ".git" | grep -v "node_modules" | grep -v ".next"

Show me any remaining hits so we can verify nothing was missed.
```

---

## CLAUDE TRACK — GitHub operations + repo separation (judgment + git)

**Paste this prompt into a new Claude Code session in /Users/raunaksingh/Documents/Vordi:**

```
You are working in the repo at /Users/raunaksingh/Documents/Vordi
The app is being rebranded from "Vordi" to "Vordi".

Do the following tasks IN ORDER (each depends on the previous):

---

### TASK A — Rename GitHub repo Vordi → Vordi

Run:
  gh repo rename Vordi --repo Raunaks068619/Vordi --yes

Then update the local git remote to match:
  git remote set-url origin https://github.com/Raunaks068619/Vordi.git

Verify:
  git remote -v

---

### TASK B — Create new repo for the landing page

Run:
  gh repo create Raunaks068619/vordi-web --public --description "Landing page for Vordi — vordi.site"

---

### TASK C — Extract web/ directory into its own repo with git history

Run these commands in order:

  cd /Users/raunaksingh/Documents/Vordi

  # Extract the web/ subtree history into a separate branch
  git subtree split --prefix=web -b vordi-web-split

  # Create a temp directory and clone the split branch into it
  mkdir -p /tmp/vordi-web-extract
  cd /tmp/vordi-web-extract
  git init
  git pull /Users/raunaksingh/Documents/Vordi vordi-web-split

  # Push to the new GitHub repo
  git remote add origin https://github.com/Raunaks068619/vordi-web.git
  git push -u origin main

  # Clean up
  cd /Users/raunaksingh/Documents/Vordi
  git branch -D vordi-web-split

---

### TASK D — Remove web/ from the main app repo

After TASK C is confirmed pushed:

  cd /Users/raunaksingh/Documents/Vordi
  git rm -r web/
  git commit -m "chore: extract landing page to vordi-web repo"

---

### TASK E — Verify and report

Run:
  git remote -v
  git log --oneline -5
  gh repo view Raunaks068619/Vordi --json name,url
  gh repo view Raunaks068619/vordi-web --json name,url

Report back what each returned so we can confirm both repos exist and local remote is correct.

---

### TASK F — Add vordi-web repo as a git submodule (optional, skip if unsure)

SKIP this task unless the user explicitly says to do it.
A submodule would let the main repo reference the web repo at a specific commit.
This is optional — the two repos can stay fully independent.
```

---

## Sync point (after both tracks complete)

Once Codex and Claude both finish, do this final step in the main Claude session:

1. Stage all file changes from Codex track:
   ```
   git add Sources/ README.md INSTALL.md PERMISSIONS.md CONTEXT.md DESIGN.md FEATURES.md \
           ONBOARDING_PLAN.md VORDI_CONTEXT.md bump_cask.sh \
           homebrew-vordi/ docs/ scripts/ project.yml
   git commit -m "rebrand: Vordi → Vordi across all source files and docs"
   git push
   ```

2. Confirm GitHub repo is now at: https://github.com/Raunaks068619/Vordi
3. Confirm landing page repo is at: https://github.com/Raunaks068619/vordi-web
4. Point vordi.site DNS to Vercel/Netlify where vordi-web is deployed

---

## What stays unchanged (DO NOT touch)

| Thing | Why |
|---|---|
| `Vordi.app` binary name | Would break existing installs |
| `com.vordi.app` bundle ID | macOS permissions + Keychain tied to this |
| `Vordi` Xcode scheme | Build system reference |
| `Vordi-Beta.dmg` filename | Release artifact, Homebrew cask points here |
| `.claude/worktrees/` | Old worktrees, ignore entirely |
