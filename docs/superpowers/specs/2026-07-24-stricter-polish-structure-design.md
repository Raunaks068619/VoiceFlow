# Stricter Polish Structure

## Goal

Make **Add structure for readability** an enforceable output contract rather
than a weak suggestion. When it is enabled, Vordi should infer useful
formatting from natural speech even when the speaker never asks for a list.

## Current failure

The Polish pipeline contains contradictory rules:

- The enabled Polish rule asks the model to use paragraph breaks, bullets, and
  numbered lists when useful.
- The shared cleanup contract tells the model not to output bullets.
- The hallucination guard rejects bullet and numbered-list output in Dictation
  (Polish) mode.

As a result, the model is discouraged from producing structure and can have a
correctly structured result rejected after generation.

## Output contract

When **Add structure for readability** is enabled:

- Three or more distinct requests, tasks, commitments, or list items must be
  rendered as a hyphen-bulleted list, even if the speaker only repeats natural
  phrases such as "I want to" or "I need to."
- Two clearly distinct items may be rendered as bullets when doing so is easier
  to scan than a sentence.
- Explicit sequences such as "first," "second," "step one," or chronological
  instructions must be rendered as a numbered list.
- Topic changes in longer dictation must receive paragraph breaks.
- A single continuous thought must remain a normal paragraph.
- A short lead-in ending in a colon may precede a list when it comes naturally
  from the dictated meaning.
- The model must preserve the speaker's meaning, tone, domain vocabulary, names,
  identifiers, and ordering unless the separately enabled reorder rule permits
  limited reordering.
- The model must not invent tasks, headings, conclusions, explanations, or
  answers.

When **Add structure for readability** is disabled:

- Polish may still fix punctuation, grammar, clarity, concision, and ordering
  according to the other enabled rules.
- It must not introduce bullets, numbered lists, headings, or extra paragraph
  structure that the speaker did not explicitly dictate.

## Prompt changes

- Remove the shared absolute prohibition on bullets.
- Keep the hard requirements to output only the transformed transcript and to
  reject commentary, conversational answers, code fences, and prompt echo.
- Replace the structure rule's optional wording with explicit detection rules
  for natural enumerations, task lists, sequences, and topic changes.
- Make the formatting policy conditional on the current
  `addStructureForReadability` setting across every Polish text-to-text path,
  including English cleanup/translation and bilingual normalization.
- Rewrite mode continues to permit proportional list formatting independently
  of the Polish toggle because it has its own stronger transformation contract.

## Guard changes

- In Dictation (Polish) mode, bullet and numbered-list output is valid only when
  `addStructureForReadability` is enabled.
- When that rule is disabled, list-shaped output remains a hallucination signal.
- Markdown headings, code fences, answer scaffolding, prompt echo, excessive
  length divergence, and other existing hallucination checks remain protected.
- The guard must receive the formatting policy explicitly rather than infer it
  from the processing-mode name alone.

## Example

Input:

> This is a test for formatting using Vordi. I am going to list a bunch of
> things that I want to do. So, format this properly. I want to create a plan
> for my gym day-to-day exercises. I want to log the exercises I do each day. I
> want to post one video per week on X. I want to create a UGC ad for the
> application that I'm making.

Acceptable output:

> This is a test of Vordi's formatting. I want to:
>
> - Create a day-to-day gym exercise plan.
> - Log the exercises I complete each day.
> - Post one video per week on X.
> - Create a UGC ad for the application I'm building.

The exact wording may vary according to the other enabled Polish rules, but the
four tasks must remain distinct and structured.

## Regression coverage

Add deterministic coverage for:

1. Natural repeated requests becoming bullets when structure is enabled.
2. Explicit ordered steps becoming a numbered list.
3. A single thought remaining a paragraph.
4. Structured output passing the hallucination guard when structure is enabled.
5. The same unsolicited structured output being rejected when structure is
   disabled.
6. Markdown headings, code fences, and chatbot-answer scaffolding continuing to
   fail the guard.
7. The generated system prompt containing no contradictory bullet prohibition.

Run the original reported transcript through the configured Polish backend and
confirm that the installed app injects a readable list in Polish mode.

## Scope

This change is limited to Polish prompt construction, formatting-policy
plumbing, hallucination validation, and targeted regression coverage. It does
not change transcription providers, model selection, unrelated Polish rules, or
the settings UI.
