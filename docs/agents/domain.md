# Domain Docs

How the engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- `GLOSSARY.md` at the repo root, if it exists.
- `.claude/architecture/README.md`, its "Decisions so far" table (D1, D2, …) and
  "Open questions". Then the plan file for the area you're in (`02-daemon.md`,
  `03-protocol.md`, `04-frontends.md`, `05-visuals.md`, `08-design.md`, …).
- `CLAUDE.md`: the hard rules (responsiveness, theme, keyboard) outrank any proposal.

If `GLOSSARY.md` doesn't exist, proceed silently. `/domain-modeling` creates it
when a term actually gets resolved.

## Layout

Single-context:

```
/
├── GLOSSARY.md                    (created lazily)
├── CLAUDE.md                      rules
└── .claude/architecture/
    ├── README.md                  decisions table (D1…D16) + open questions
    └── 0N-*.md                    plan per area
```

There is no `docs/adr/`. Record a new decision as the next D-number row in
the README's table (decision | why), and when it changes a rule, update
`CLAUDE.md` in the same change.

## Use the glossary's vocabulary

Name domain concepts as `GLOSSARY.md` and the architecture docs do (specimen,
lens, tide pool, organism, compact player, …). Don't drift to synonyms. A
concept that isn't there yet either means you're inventing language, or it's
a gap to note for `/domain-modeling`.

## Flag decision conflicts

If your output contradicts a decision, say so explicitly instead of quietly
overriding it:

> _Contradicts D11 (no dependency on the public Web API), but worth reopening because…_
