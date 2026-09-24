# Historical export fixtures

Real exports written by the app's own `DataExportService.buildJsonExport`
at each database schema version this repository has shipped. They stand in
for backups and export files users already have, so
`test/unit/export_schema_upgrade_test.dart` can prove those still restore
after the schema moves on (ADR-7, amendment of 2026-09-24).

| File | Schema | Written by commit |
|---|---|---|
| `export_schema_5.json` | 5 | `951836b` (Initial commit) |
| `export_schema_7.json` | 7 | `56c5411` (Supabase auth, user profile) |
| `export_schema_9.json` | 9 | `ba4377a` (progress analytics phases 2 and 3) |

Schemas 6, 8 and 10 were never the version of any commit, so no build could
have written them. Schema 11 is covered by exporting from the current code.

**Never regenerate these to make a test pass.** They are only useful because
old code wrote them. Add a new fixture when a new schema version ships.

## How they were made

`generate_fixture.dart.txt` (kept as `.txt` so the analyzer and test runner
ignore it) was copied into `test/` of a `git worktree` at each commit above
and run with `FIXTURE_OUT=<path> flutter test`, after `flutter pub get` and
`dart run build_runner build`. Before the rename to Ironyx, the package was
called `fittrack`, so the imports need that name at those commits.

It inserts one row into every table, following foreign keys, and adds a
custom exercise (`seed_version = 0`, plus `is_custom = 1` once that column
exists at schema 8) that a workout uses.
