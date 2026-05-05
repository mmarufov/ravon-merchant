-- Backfill nullable/missing values on public.restaurants and enforce NOT NULL
-- on the columns that the consumer app decodes as non-optional. Without this,
-- a row with NULL rating / is_accepting_orders / restaurant_status causes the
-- consumer to fail with "ошибка загрузки" when decoding the Restaurant model.
--
-- Safe to run once; idempotent on a healthy table.

begin;

-- 1) Add column defaults so future inserts that omit these fields get sane values.
alter table public.restaurants
  alter column rating              set default 0,
  alter column is_accepting_orders set default true,
  alter column restaurant_status   set default 'draft';

-- 2) Backfill any existing NULL/empty rows.
update public.restaurants
   set rating              = coalesce(rating, 0),
       is_accepting_orders = coalesce(is_accepting_orders, true),
       restaurant_status   = coalesce(restaurant_status, 'draft'),
       cuisine_type        = coalesce(nullif(cuisine_type, ''), 'Разное'),
       delivery_time_min   = coalesce(delivery_time_min, 30),
       delivery_fee        = coalesce(delivery_fee, 0),
       min_order_amount    = coalesce(min_order_amount, 0);

-- 3) Lock the columns down so future writes can't reintroduce NULLs.
alter table public.restaurants
  alter column rating              set not null,
  alter column is_accepting_orders set not null,
  alter column restaurant_status   set not null,
  alter column cuisine_type        set not null,
  alter column delivery_time_min   set not null,
  alter column delivery_fee        set not null,
  alter column min_order_amount    set not null;

commit;
