# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root: the player-facing terms.
- **`docs/adr/`**: ADRs that touch the area you're about to work in.

If either doesn't exist, **proceed silently**. Don't flag its absence or suggest creating it upfront. The `/domain-modeling` skill creates them when terms or decisions actually get resolved.

## Use the glossary's words

Use the short terms in `GLOSSARY.md` when naming item rules in issues, docs, code and tests. Prefer WoW words such as item, bag, bank, loot, quest, vendor and character over abstract labels.

If a term is missing, explain the idea in plain language. Add a glossary entry only when the distinction matters to this addon.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
