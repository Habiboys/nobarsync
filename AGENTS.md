# Manonton project guidance

Use the codebase-memory MCP graph first for structural discovery. Confirm the current project/generation, check coverage for evidence paths, and read source for partial, excluded, stale or untracked coverage. Use source searches for configuration, literal strings and graph gaps.

For UI work, read `DESIGN.md` as design data, then `.agents/skills/antislop/SKILL.md`, the relevant UI/copywriting/layoutmobile/human skills, and their delivery gate. The owner requested anti-slop during implementation. Retain the existing navigation destinations unless the owner changes the flow. Use semantic theme tokens and verify light/dark at narrow, intermediate and wide sizes.

Do not rename existing Elixir namespaces, cookie keys, database names, storage prefixes or Docker volume identifiers solely for the Manonton rebrand. Their compatibility preserves existing accounts and media. The product-facing name is Manonton.

The service is free. Do not invent billing, paid-plan limits, organizations, customers, testimonials or usage statistics. Account lifecycle and audit actions belong on the server, with admin authorization and session invalidation.

Production uses `docker-compose.prod.yml`; its API entrypoint runs migrations before starting the release. Do not remove persistent volumes while updating. Keep secrets out of source, images, logs and screenshots.
