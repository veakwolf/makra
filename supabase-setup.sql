-- Makrá: Supabase funkcie (stav z 10.11.2026)
-- Tabuľky (existujúce):
--   makra_steps:  id bigint, day date (unique), steps integer, updated_at timestamptz
--   makra_backup: id integer (pk), data jsonb, updated_at timestamptz
-- Tajný kód sa overuje proti SHA-256 hashu priamo vo funkciách.
-- Skratka "Makrá kroky" volá makra_put_steps s p_secret/p_day/p_steps,
-- appka volá makra_get_steps(secret, since), makra_backup_save(secret, data),
-- makra_backup_load(secret).

create unique index if not exists makra_steps_day_idx on makra_steps(day);

-- Kroky ukladá skratka (p_secret, p_day, p_steps)
create or replace function makra_put_steps(p_secret text, p_day text, p_steps integer)
returns void language plpgsql security definer as $$
begin
  if encode(digest(p_secret, 'sha256'), 'hex') <> 'f58ae899ef154c5cb80d46f976e3676e8137821e211216b1c3099ee4db4bf2f0' then
    raise exception 'zly kod';
  end if;
  insert into makra_steps(day, steps, updated_at) values (p_day::date, p_steps, now())
  on conflict (day) do update set steps = excluded.steps, updated_at = now();
end;
$$;

-- Kroky číta appka (secret, since)
create or replace function makra_get_steps(secret text, since text)
returns table(day text, steps integer) language plpgsql security definer as $$
begin
  if encode(digest(secret, 'sha256'), 'hex') <> 'f58ae899ef154c5cb80d46f976e3676e8137821e211216b1c3099ee4db4bf2f0' then
    raise exception 'zly kod';
  end if;
  return query select s.day::text, s.steps from makra_steps s
    where s.day >= since::date order by s.day;
end;
$$;

-- Zálohu ukladá appka (secret, data)
create or replace function makra_backup_save(secret text, data jsonb)
returns void language plpgsql security definer as $$
begin
  if encode(digest(secret, 'sha256'), 'hex') <> 'f58ae899ef154c5cb80d46f976e3676e8137821e211216b1c3099ee4db4bf2f0' then
    raise exception 'zly kod';
  end if;
  insert into makra_backup(id, data, updated_at) values (1, data, now())
  on conflict (id) do update set data = excluded.data, updated_at = now();
end;
$$;

-- Zálohu číta appka (secret)
create or replace function makra_backup_load(secret text)
returns json language plpgsql security definer as $$
declare rec makra_backup%rowtype;
begin
  if encode(digest(secret, 'sha256'), 'hex') <> 'f58ae899ef154c5cb80d46f976e3676e8137821e211216b1c3099ee4db4bf2f0' then
    raise exception 'zly kod';
  end if;
  select * into rec from makra_backup where id = 1;
  if not found then return null; end if;
  return json_build_object('data', rec.data, 'updated_at', rec.updated_at);
end;
$$;

-- Povoliť volanie cez REST API
grant execute on function makra_put_steps(text, text, integer) to anon;
grant execute on function makra_get_steps(text, text) to anon;
grant execute on function makra_backup_save(text, jsonb) to anon;
grant execute on function makra_backup_load(text) to anon;

-- Tabuľky sú prístupné len cez funkcie vyššie (security definer), nie priamo cez API
alter table makra_steps enable row level security;
alter table makra_backup enable row level security;
