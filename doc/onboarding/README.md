# Developer Onboarding — NetDEF CI GitHub App

Technical documentation for new developers. Diagrams use [Mermaid](https://mermaid.js.org/),
which GitHub and most Markdown editors render natively.

| Document | Contents |
|----------|----------|
| [01-overview.md](01-overview.md) | What the system does, stack, repository layout, domain concepts |
| [02-environment-and-operations.md](02-environment-and-operations.md) | Local setup, configuration, running processes, logs, metrics, tests |
| [03-class-diagrams.md](03-class-diagrams.md) | Class diagrams (models, services, workers) and the database ER diagram |
| [04-flowcharts.md](04-flowcharts.md) | Flowcharts and sequence diagrams of the main flows |
| [05-contributing-guide.md](05-contributing-guide.md) | Conventions, how to add features, debugging, known pitfalls |

Suggested reading order: 01 → 04 (the "pull request opened" flow) → 03 → 02 → 05.

Related existing documents:

- [`doc/ci/ci.md`](../ci/ci.md) — possible check states and the state machine.
- [`doc/general/console.md`](../general/console.md) — using the console (`bin/console`).
- [`AGENTS.md`](../../AGENTS.md) — conventions for AI agents (useful for humans too).
- [`PERFORMANCE.md`](../../PERFORMANCE.md) — performance notes.
