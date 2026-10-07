## Summary

<!-- What changed, and why. -->

## Checks

Generated files under `.github/agents/`, `.claude-plugin/`, and `.cursor-plugin/`
are never edited by hand. Edit `skills/<name>/SKILL.md`, then regenerate.

- [ ] `node scripts/package.mjs --check`
- [ ] `python scripts/validate_contracts.py`
- [ ] `python scripts/tests/test_verify.py`
- [ ] `python scripts/tests/test_validate_contracts.py`
- [ ] `node hooks/scripts/session-start.test.mjs`
- [ ] `scripts/leak_scan.sh` (no catalog, table, domain, or zone name in `skills/` or `assets/`)
- [ ] `cd examples/support-desk && python seed.py --check`
- [ ] `CHANGELOG.md` updated, if behavior changed
