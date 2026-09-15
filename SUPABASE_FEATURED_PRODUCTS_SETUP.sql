-- DARK SHOP: persistent featured products configuration
-- Run this SQL in Supabase SQL Editor AFTER the existing featured_products table has been created.

create table if not exists public.featured_products (
  product_key text primary key,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- Public read policy (safe because this table contains only product keys/order).
alter table public.featured_products enable row level security;
drop policy if exists "featured_products_public_select" on public.featured_products;
create policy "featured_products_public_select"
on public.featured_products for select
to anon, authenticated
using (true);

-- Read through a SECURITY DEFINER function so the website does not depend on
-- the browser's direct table/RLS behavior.
create or replace function public.get_featured_products_config()
returns table(product_key text, sort_order integer)
language sql
stable
security definer
set search_path = public
as $$
  select fp.product_key, fp.sort_order
  from public.featured_products fp
  order by fp.sort_order asc, fp.product_key asc;
$$;

-- Only logged-in admins may save the configuration. The SECURITY DEFINER
-- function can check profiles.is_admin without being blocked by profiles RLS.
create or replace function public.set_featured_products_config(p_products jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select coalesce(p.is_admin,false)
    into v_is_admin
  from public.profiles p
  where p.id = auth.uid();

  if coalesce(v_is_admin,false) <> true then
    raise exception 'admin access required';
  end if;

  if jsonb_typeof(p_products) <> 'array' then
    raise exception 'p_products must be a JSON array';
  end if;

  if jsonb_array_length(p_products) > 4 then
    raise exception 'maximum 4 featured products';
  end if;

  delete from public.featured_products;

  insert into public.featured_products(product_key, sort_order)
  select
    trim(e.item->>'product_key'),
    e.ord - 1
  from jsonb_array_elements(p_products) with ordinality as e(item, ord)
  where trim(e.item->>'product_key') <> '';


  return true;
end;
$$;

revoke all on function public.get_featured_products_config() from public;
grant execute on function public.get_featured_products_config() to anon, authenticated;

revoke all on function public.set_featured_products_config(jsonb) from public;
grant execute on function public.set_featured_products_config(jsonb) to authenticated;

-- Keep the initial four products if the table is empty.
insert into public.featured_products(product_key, sort_order)
select v.product_key, v.sort_order
from (values
  ('elite:elite',0),
  ('elite:elite_plus',1),
  ('prime:prime',2),
  ('prime:prime_plus',3)
) as v(product_key, sort_order)
where not exists (select 1 from public.featured_products);
