# ControlTower Aider guidance

You are running inside AI ControlTower with Aider and a local Ollama model.

## Method

- Start from the provided context and target files only.
- Use a small BMAD/Superpowers loop: understand, scope, plan briefly, execute, verify, summarize.
- Prefer simple, testable changes over broad rewrites.
- Do not invent files, APIs, commands, routes, fields, ports or facts that are not present in the context.
- Do not create command-like filenames such as `open index.html` or `start index.html`.
- Do not create tree-output filenames such as `|-- app.js`, `+-- README.md` or similar.
- Use UTF-8 clean text only. Avoid emoji and non-ASCII characters unless the existing project clearly requires them.
- Do not output mojibake such as `Ã`, `Â`, `â`, `ð`, replacement characters, or terminal drawing artifacts.
- Keep documentation factual: say what exists, what you changed, what remains uncertain.

## Verification before completion

- Ensure every created or edited file has a purposeful path.
- Ensure README instructions match the generated project.
- If code is generated, provide a simple verification command or test.
- If you cannot verify something, state the limitation instead of claiming success.

## Audit and correction

- For audit reports, every finding must cite a real path and a short exact excerpt from the provided context.
- For fixes, change only editable files passed by ControlTower.
- Never touch secrets, `.env`, virtual environments, caches, databases, executables, archives or Git internals.
