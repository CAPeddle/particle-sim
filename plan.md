Research doc updated — COMPARISON_RESEARCH.md now includes Section 9 with 7 transferable aspects prioritised for particle-sim:

High: TOML config system, smoothing kernel function, density/gradient calculation
Medium: Density heatmap visualisation, boundary collision with damping
Low: Factory spawn patterns, vector debug drawing


Three documents created/updated in particle-sim:

docs/fluid-sim-migration.md — The actionable backlog. Contains 7 transferable features with original source code, known bugs (e.g., uninitialized density, pass-by-value), CUDA adaptation snippets, and a recommended implementation order. This is the primary document a future session should read.

docs/fluid-sim-comparison.md — The condensed architectural comparison (architecture, SOLID, patterns, performance, extensibility). Reference material for understanding why decisions were made.

CLAUDE.md — Updated "Current Status" section with a "Predecessor Project" block that points to both documents and summarises what was transferred. Any new session reading CLAUDE.md will immediately see this context.

COMPARISON_RESEARCH.md is a direct copy and should be evaluated for removal or archiving, as its content is now integrated into the above documents. The actionable backlog in fluid-sim-migration.md should be the focus for future development sessions.