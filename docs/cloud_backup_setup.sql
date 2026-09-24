-- Account backup — one-time Supabase setup.
--
-- TEMPORARY, while the app is in testing. This is backup/restore, not the
-- cloud sync in TODO.md Roadmap Phase 5: one slot per account, last write wins,
-- and restoring replaces the device. Phase 5 replaces it with real
-- per-table sync and amends ADR-8 properly.
--
-- Run once, in the Supabase dashboard: SQL Editor -> New query -> paste ->
-- Run. Safe to re-run; every statement is idempotent.
--
-- Until this exists, the app degrades rather than breaking: Settings shows
-- "Backup isn't set up on the server yet" instead of an error.

create table if not exists public.backups (
  user_id           uuid        primary key
                    references auth.users (id) on delete cascade,

  -- The ADR-7 export envelope: gzipped, then base64 encoded, by the client
  -- before upload. A year of hard training is ~1.4MB of JSON and ~40KB
  -- compressed, so this stays small enough to back up on mobile data.
  payload           text        not null,

  -- Denormalised so the "last backup" line in Settings can be shown
  -- without downloading the payload itself.
  size_bytes        integer     not null default 0,
  app_version       text        not null default 'unknown',

  -- A restore into a different database schema is refused by the client,
  -- so store what this backup was written against and surface it early.
  db_schema_version integer     not null default 0,

  updated_at        timestamptz not null default now()
);

-- Caps what one account can store. Sign-up is open and the anon key ships
-- in the APK, so without this anyone can create accounts and fill the
-- project's storage with arbitrarily large rows. 5 MiB of encoded payload is
-- decades of training (~40KB compressed per year). The app checks the same
-- number (`kMaxBackupPayloadBytes` in cloud_backup_service.dart) so an
-- oversized backup fails before upload; this constraint is the real limit.
-- Change both together. The payload is base64, so its octets are its chars.
alter table public.backups
  drop constraint if exists backups_payload_size;
alter table public.backups
  add constraint backups_payload_size
  check (octet_length(payload) <= 5242880);

-- Row-level security is the only thing standing between one tester's
-- training log and another's: the anon key is public by design and ships
-- inside the APK, so without this every user could read every backup.
alter table public.backups enable row level security;

-- Single FOR ALL policy rather than four. The rule is genuinely the same
-- in every direction — you may touch your own row and no other — and
-- splitting it into select/insert/update/delete invites them to drift
-- apart. USING covers reads and the pre-image of writes; WITH CHECK covers
-- the post-image, which is what stops a user rewriting user_id to somebody
-- else's id on the way in.
drop policy if exists "Users manage their own backup" on public.backups;
create policy "Users manage their own backup"
  on public.backups
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Account deletion is intentionally server-side. The mobile app only holds the
-- public anon key, which must never be granted permission to delete rows from
-- auth.users directly. The function runs as its owner, but remains scoped to
-- the caller's auth.uid() and cannot be invoked by anonymous clients.
--
-- `search_path = ''` means every name inside must be schema-qualified (they
-- are). A security-definer function that resolves names through a search
-- path can be tricked into calling an attacker's same-named object instead;
-- an empty path removes that option entirely. Supabase's database linter
-- flags anything else.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.backups where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- The statements above are DDL, so a successful run reports
-- "Success. No rows returned". That is what you want, but it looks
-- identical to a no-op — run this to actually confirm the table exists and
-- RLS is switched on. Expect one row showing rowsecurity = true, and one
-- policy row.
--
--   select tablename, rowsecurity
--     from pg_tables
--    where schemaname = 'public' and tablename = 'backups';
--
--   select policyname, cmd, roles
--     from pg_policies
--    where schemaname = 'public' and tablename = 'backups';
--
-- Once testers start backing up, this lists what is stored. Run it as the
-- dashboard owner; a signed-in user would only ever see their own row.
--
--   select user_id, size_bytes, app_version, db_schema_version, updated_at
--     from public.backups order by updated_at desc;
