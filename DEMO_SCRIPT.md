# Vordi — Demo Shooting Script (A/B: without → with)

_~55s · caption + optional TTS voiceover · arc = you speak everywhere → AI is blind → connect Vordi → AI reads it all_

## The one-line story
**You say things all day — Slack, chats, out loud. Your AI can't see any of it. Vordi captures
it and lets your agent read it.** The demo does the capture **once**, shows Codex **blind**
without Vordi, then **connects Vordi** (the hero moment) and asks the *same question* — now it
answers. Same actions, one connection, opposite result.

## Two audio tracks (pick per beat)
- **Dictation = YOUR real voice.** The pricing line + the Hindi line must be spoken by you —
  that's the product transcribing you live. No way around it (it's ~2 short sentences).
- **Narration = optional.** Either go **silent + captions**, or drop a **TTS voiceover** over
  the captions (see the VO track below + the TTS section at the end). You record the screen;
  the VO is added in editing.

---

## Pre-flight checklist
- [ ] Ran `./scripts/build-and-install.sh` (latest build + bundled helper)
- [ ] **Codex is currently DISCONNECTED from Vordi** (the §3 "without" beat needs this) — start a fresh `codex` session now, disconnected
- [ ] Do NOT pre-dictate the pricing line — it must be spoken live in §1
- [ ] Vordi running · Slack + WhatsApp + a `codex` terminal all open and arranged
- [ ] Big fonts, clean windows, dock hidden, notch visible, quiet room, mic tested
- [ ] Screen record with ⌘⇧5 (one continuous take; trim later)

> **Single-take flow:** speak into Slack → speak into WhatsApp → ask disconnected Codex (fails)
> → open Vordi, Connect Codex → **restart the codex session** (MCP loads at launch; ~3s, trimmed
> in edit) → ask the same question (answers). All honest — the only thing that changed is the
> connection.

---

## SECTION 1 — Capture · Slack (0–12s)
**Screen:** Slack, a channel or DM. Cursor in the message box.
**You speak (hold Vordi hotkey):**
> "For the launch, let's make annual pricing the default and keep monthly as the backup — it should help retention."
**On screen:** Text appears fast, clean, punctuated.
**Caption (0s):** `Just talk. Vordi types it — anywhere.`
**VO (0s):** *"You talk all day — Slack, chats, notes. Vordi types every word for you."*
**Settings:** Output style = **Polish**.

---

## SECTION 2 — Capture · WhatsApp, multilingual (12–22s)
**Screen:** Switch to WhatsApp, a chat with a friend.
**You speak (in Hindi / Hinglish):**
> "Yaar kal dinner 8 baje rakhte hain, main woh restaurant book kar deta hoon."
**On screen:** Vordi types a clean, natural message.
**Caption (12s):** `Any app. Any language.`
**VO (12s):** *"In any app. Even in another language."*
**Settings:** Output style = **English output** (clean Hinglish) or **Translate** (bigger wow).

---

## SECTION 3 — WITHOUT Vordi · the pain (22–32s)
**Screen:** Your `codex` terminal — **not connected to Vordi.** You ask:
**You type:** `What did I decide about launch pricing?`
**Codex replies (genuinely):** *"I don't have access to that — nothing here about launch pricing."*
**Caption (22s):** `But your AI can't see any of it.`
**Caption (27s):** `Your AI can't remember what you said — anywhere else.`
**VO (22s):** *"But your AI assistant can't see any of it. Ask Codex what you decided, and it draws a blank."*
**Note:** You already confirmed the disconnected reply is clean — this is the honest "before."

---

## SECTION 4 — THE TURN · connect Vordi (32–41s)  ·  the hero moment
**Screen:** Open Vordi → **Settings → Connect Agents → Connect** on **Codex** → ✓ appears.
Then a quick **restart of the codex session** (trim the wait in edit).
**Caption (32s):** `One click changes that.`
**VO (32s):** *"Until you connect Vordi. One click."*
**Note:** In this A/B the connect **is** the pivot — it's what causes the payoff. It also shows
the real product feature. Earn it here (unlike a tacked-on end CTA).

---

## SECTION 5 — WITH Vordi · the payoff (41–53s)  ·  THE MOAT
**Screen:** Same `codex` session, now connected. Ask the **same question from §3**.

**Query A (closes the loop):**
`Using vordi, what did I decide about launch pricing?`
→ *"You chose **annual as the default**, monthly as the backup, to help retention."*

**Query B (breadth — any app, any language):**
`Using vordi, what dinner plans did I mention?`
→ *"Dinner at 8 — and you'd book the restaurant."* _(the Hindi line from §2)_

**On screen:** Let the `vordi_search_transcripts` tool call flash — proof it's real.
**Caption (41s):** `Now ask again —`
**Caption (47s):** `— and it reads back everything you said. Even the Hindi.`
**VO (41s):** *"Now ask again — and it reads back everything you said. Even the message you sent in Hindi."*

---

## SECTION 6 — End card (53–58s)
**Screen:** Hold on the answer, cut to end card (logo + tagline).
**End card line 1:** `Vordi — the memory layer for everything you say.`
**End card line 2 (small):** `Works with Claude, Cursor & Codex. Connect in one click.`
**VO (53s):** *"Vordi — the memory layer for everything you say."*

---

## Caption master list (for the edit)
| In | Caption |
|---|---|
| 0s | Just talk. Vordi types it — anywhere. |
| 12s | Any app. Any language. |
| 22s | But your AI can't see any of it. |
| 27s | Your AI can't remember what you said — anywhere else. |
| 32s | One click changes that. |
| 41s | Now ask again — |
| 47s | — and it reads back everything you said. Even the Hindi. |
| 53s | Vordi — the memory layer for everything you say. |
| 56s | Works with Claude, Cursor & Codex. Connect in one click. |

## Voiceover master list (for TTS — one file per line, or one continuous read)
1. "You talk all day — Slack, chats, notes. Vordi types every word for you."
2. "In any app. Even in another language."
3. "But your AI assistant can't see any of it. Ask Codex what you decided, and it draws a blank."
4. "Until you connect Vordi. One click."
5. "Now ask again — and it reads back everything you said. Even the message you sent in Hindi."
6. "Vordi. The memory layer for everything you say."

## Recall anchors (keep one distinctive word per question)
- **"pricing"** / **"annual"** → the launch-pricing decision (§1)
- **"dinner"** → the WhatsApp Hindi line (§2)
⚠️ FTS ANDs every word — but you ask Codex in plain English and Codex picks the keywords, so it's a non-issue on camera.

## Shot tips
- Bump editor / Slack / Codex font sizes for small-screen legibility.
- Keep the mouse still during dictation — eyes on the text appearing.
- Record 1080p+ ; a fixed region beats full-screen.
- Capture raw in one go; hand me the file and I'll cut to these timings with captions (+ VO if you generate it).
