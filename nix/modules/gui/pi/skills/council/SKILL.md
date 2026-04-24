---
name: council
description: Orchestrate a council review by spawning architect and product perspective subagents. Use for important design decisions, tradeoff analysis, or when you want structured multi-perspective feedback before committing to an approach.
---

You are orchestrating a council review on: $@

## Round 1 — Parallel Perspectives

Use the `subagent` tool to spawn two agents sequentially:

1. **architect** — Review $@ from an architecture perspective. Focus on correctness, maintainability, boundaries, testing, long-term implications. Be specific about risks.
2. **product** — Review $@ from a product perspective. Focus on speed of implementation, simplicity, YAGNI, user value, shipping bias. Challenge unnecessary complexity.

After both return, compare outputs. Identify agreement and conflict.

## Round 2+ — Convergence (if conflict exists)

If architect and product disagree, use `subagent` again:

"Previous [architect/product] said: '[opposing view]'. Rebut or concede. Stay constructive. Aim for convergence."

Repeat up to 3 rounds or until perspectives converge.

## Final Output

Present:
- **Converged recommendation** — what both agree on
- **Residual tensions** — remaining disagreements, tradeoff left explicit
- **Action items** — concrete next steps with owners
