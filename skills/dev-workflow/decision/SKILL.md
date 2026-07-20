---
name: decision
description: 'Use when you need to hand a decision back to the user as a plain-language summary plus a choice menu — after finishing work and needing the user to pick how to proceed, when told "waiting for your decision about X", or when the user says "display decision", "what''s the decision on/about X", "show me my options for X", "let me choose", "walk me through the open decisions", "what are my action items", or gives a GitHub issue/PR number or URL to summarize and choose from.'
when_to_use: 'User says: "display decision 141 to me simply and let me choose", "what are my open decisions", "walk me through the action items one by one", "summarize issue #57 and give me options", "let me choose between X and Y" — or an agent has just finished work and needs the user to pick between options before continuing.'
argument-hint: "[decision description, GitHub issue/PR number or URL, or empty to scan the conversation]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - AskUserQuestion
  - Bash
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: dev-workflow
  tags:
    - decision
    - ask-user-question
    - github-issue
    - action-items
  updated-date: "2026-07-20"
---

# Decision

## Why this skill exists

After a long stretch of work — or when reading a GitHub issue full of open questions — the user is handed either a wall of prose ("I did X, Y, Z... let me know what you think about the auth approach") or nothing at all, and has to reconstruct the actual choice themselves. This skill's only job is to close that gap: take whatever decision is pending, strip it down to plain language, and hand it back as an explicit menu via the built-in **AskUserQuestion** tool — never as freeform prose the user has to parse and reply to in kind.

## Resolve the input

1. **Argument looks like a GitHub issue/PR** — a bare number (`57`, `#57`) or a GitHub URL containing `/issues/` or `/pull/`:
   ```bash
   # Infer owner/repo from the URL, or from the current repo if none is given
   gh issue view <number> --json title,body,comments,url -R <owner/repo>
   ```
   If that 404s, or the URL/context says `/pull/`, retry with `gh pr view` instead. If no repo can be inferred (not inside a git checkout, ambiguous), ask the user which repo before fetching.

2. **Argument is non-empty text** — treat it as a topic/description, not a literal ID. Search the current conversation for the decision it best matches. Numbers like "141" in a user's example phrasing are illustrative, not a real numbering scheme to look up — match on content, not on the digits.

3. **No argument** — scan the whole current conversation for every unresolved decision or action item (places where work was completed but a choice was deferred, a question was raised and never answered, or the conversation explicitly says something is "waiting on you").

## Summarize in plain language

Before presenting any menu, write 1–3 sentences with no jargon:
- What needs to be decided.
- Why it matters, in one clause — not a re-explanation of the whole implementation.

Assume the user already saw the work leading up to this point; the summary orients them, it doesn't re-teach them.

## Present the choice — always via AskUserQuestion

Never ask a decision in plain prose and never accept "just reply with your answer" — always call **AskUserQuestion**:

- `question`: the decision framed as a question (e.g. "Which secret backend should we use?").
- `header`: ≤12 chars naming the decision's topic.
- `options`: 2–4 mutually exclusive choices **grounded in what was actually discussed** — in the conversation, or in the issue body/comments. Do not invent options nobody raised. If the conversation's own reasoning points to a clear best choice, put it first and add "(Recommended)" to its label.
- If the decision is genuinely open-ended with no natural short list, offer the smallest sensible set of anchor options — the tool's built-in "Other" already covers anything not listed, so never leave `options` empty to compensate.

## Multiple decisions: walk through one at a time

Triggered by an empty-argument scan that finds more than one item, or an explicit "walk me through" request:

1. First, list what was found — one short line per decision — so the user sees the whole set before diving in.
2. Present each decision with its **own** AskUserQuestion call, in the order it came up in the conversation. Wait for the answer before moving to the next one — never batch several decisions into a single multi-question call when the user asked for a walkthrough.
3. After the last one, recap all choices made in a short list, one line per decision.

## Edge cases

- **Nothing pending** (empty-argument scan finds no open decisions): say so plainly and stop. Don't invent a decision to justify the menu.
- **Ambiguous text match** (the argument could refer to more than one candidate decision): list the candidates briefly and ask which one via AskUserQuestion before proceeding — don't guess which one they meant.
- **`gh` fetch fails**: report the failure plainly (don't retry silently) and fall back to asking the user to paste the decision directly.

## After the answer

State the user's choice back in one line, then continue with whatever the obvious next step is (implementing the chosen option, closing out the loop) if that's clearly part of the same turn. This skill's job ends at capturing an explicit decision — not at re-litigating it.

## Hard rules

- Never fabricate options that weren't grounded in the conversation, the issue body, or its comments.
- Never batch multiple decisions into one AskUserQuestion call during a walkthrough — one at a time, always.
- Never present a bare menu with no plain-language summary first.
- Never swallow a `gh` fetch error — surface it and fall back to asking the user directly.

## Examples

| Input | Behavior |
|---|---|
| `display decision 141 to me simply and let me choose` | "141" isn't a real ID — treat as freeform text, match against the conversation's closest open decision. If none found, say so. |
| *(empty, right after finishing a long task)* `waiting for your decision about X` | Scan the conversation; likely one open decision — summarize and ask immediately. |
| `summarize issue #57 and give me options` | `gh issue view 57`, summarize plainly, build options from the issue body/discussion. |
| `walk me through the open decisions` | Scan conversation for all pending items, list them, then walk through sequentially. |
