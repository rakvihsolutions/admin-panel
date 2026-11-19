-- =============================================================================
-- 03 · Functions & triggers
-- The business rules from demo-data.ts, enforced inside the database so the
-- admin panel, the POS and any future website all behave the same way.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Who is calling
-- -----------------------------------------------------------------------------

-- True for the server (service_role key) and for direct DB connections / SQL editor
-- (no JWT at all). False for anon and signed-in browser users.
create or replace function public.is_trusted_caller()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', 'service_role') = 'service_role';
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active and role in ('super_admin', 'sub_admin')
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active and role = 'super_admin'
  );
$$;

-- Super admin: always. Sub admin: only for modules ticked in Admin Security.
create or replace function public.has_permission(module public.admin_module)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active
      and (role = 'super_admin' or (role = 'sub_admin' and module = any (permissions)))
  );
$$;

-- Any of several modules (e.g. orders OR pos-terminal may read customers).
create or replace function public.has_any_permission(modules public.admin_module[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and is_active
      and (role = 'super_admin' or (role = 'sub_admin' and permissions && modules))
  );
$$;

-- The customers row of the signed-in shopper (null for guests / admins without one).
create or replace function public.current_customer_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.customers where profile_id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- Small helpers
-- -----------------------------------------------------------------------------

-- 'Mira Rose Gold Drop Earrings' → 'mira-rose-gold-drop-earrings'
create or replace function public.slugify(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(nullif(btrim(regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', '-', 'g'), '-'), ''), 'item');
$$;

create or replace function public.stock_status_for(qty integer)
returns public.stock_status
language sql
stable
set search_path = ''
as $$
  select case
    when qty > coalesce((select low_stock_threshold from public.store_settings limit 1), 10) then 'In Stock'::public.stock_status
    when qty > 0 then 'Low Stock'::public.stock_status
    else 'Out of Stock'::public.stock_status
  end;
$$;

-- Normalise codes / emails before constraints check them.
create or replace function public.normalize_coupon()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.code := upper(btrim(new.code));
  return new;
end $$;
create trigger coupons_normalize before insert or update of code on public.coupons
for each row execute function public.normalize_coupon();

create or replace function public.normalize_customer()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.email := nullif(lower(btrim(new.email)), '');
  new.name := btrim(new.name);
  new.phone := btrim(coalesce(new.phone, ''));
  return new;
end $$;
create trigger customers_normalize before insert or update on public.customers
for each row execute function public.normalize_customer();

-- Fill a slug from the name when the admin leaves it blank.
create or replace function public.fill_slug()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.slug is null or btrim(new.slug) = '' then
    new.slug := public.slugify(new.name);
  else
    new.slug := public.slugify(new.slug);
  end if;
  return new;
end $$;
create trigger categories_fill_slug         before insert or update on public.categories         for each row execute function public.fill_slug();
create trigger sub_categories_fill_slug     before insert or update on public.sub_categories     for each row execute function public.fill_slug();
create trigger sub_sub_categories_fill_slug before insert or update on public.sub_sub_categories for each row execute function public.fill_slug();
create trigger products_fill_slug           before insert or update on public.products           for each row execute function public.fill_slug();

-- -----------------------------------------------------------------------------
-- New sign-ups → profile + customer
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name  text := coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1), '');
  v_phone text := coalesce(new.raw_user_meta_data ->> 'phone', new.phone, '');
  v_email text := lower(btrim(coalesce(new.email, '')));
begin
  insert into public.profiles (id, email, full_name, phone)
  values (new.id, v_email, v_name, v_phone)
  on conflict (id) do nothing;

  -- registerShopper(): reuse the customer the admin already knows by email, otherwise add one.
  if v_email <> '' then
    update public.customers
       set profile_id = new.id,
           name  = case when v_name <> '' then v_name else name end,
           phone = case when v_phone <> '' then v_phone else phone end
     where email = v_email and profile_id is null;
    if not found and not exists (select 1 from public.customers where email = v_email) then
      insert into public.customers (profile_id, name, email, phone)
      values (new.id, v_name, v_email, v_phone);
    end if;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Keep profile email in step when a user changes it in Auth.
create or replace function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = lower(btrim(new.email)) where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
after update of email on auth.users
for each row when (old.email is distinct from new.email)
execute function public.handle_user_email_change();

-- Only a super admin (or the backend) may change role, permissions or active flag,
-- and the last active super admin can never be removed.
create or replace function public.protect_profile_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role, new.permissions, new.is_active) is distinct from (old.role, old.permissions, old.is_active) then
    if not (public.is_trusted_caller() or public.is_super_admin()) then
      raise exception 'Only a super admin can change roles and permissions.' using errcode = '42501';
    end if;
    if old.role = 'super_admin' and old.is_active and (new.role <> 'super_admin' or not new.is_active)
       and not exists (select 1 from public.profiles
                       where role = 'super_admin' and is_active and id <> old.id) then
      raise exception 'You cannot remove the last super admin.' using errcode = 'P0001';
    end if;
  end if;
  if new.role <> 'sub_admin' then
    new.permissions := '{}';
  end if;
  new.email := lower(btrim(new.email));
  return new;
end;
$$;

create trigger profiles_protect_access
before update on public.profiles
for each row execute function public.protect_profile_access();

-- -----------------------------------------------------------------------------
-- Catalog integrity
-- -----------------------------------------------------------------------------

-- A product's sub category must belong to its category, and its sub-sub to its sub.
-- Picking only a sub (sub) category fills in the parents.
create or replace function public.check_product_categories()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  if new.sub_sub_category_id is not null then
    select sub_category_id into v_parent from public.sub_sub_categories where id = new.sub_sub_category_id;
    if new.sub_category_id is null then
      new.sub_category_id := v_parent;
    elsif new.sub_category_id <> v_parent then
      raise exception 'The sub sub category does not belong to the chosen sub category.' using errcode = '23514';
    end if;
  end if;

  if new.sub_category_id is not null then
    select category_id into v_parent from public.sub_categories where id = new.sub_category_id;
    if new.category_id is null then
      new.category_id := v_parent;
    elsif new.category_id <> v_parent then
      raise exception 'The sub category does not belong to the chosen category.' using errcode = '23514';
    end if;
  end if;

  if new.image_url = '' and cardinality(new.images) > 0 then
    new.image_url := new.images[1];
  end if;
  return new;
end;
$$;

create trigger products_check_categories
before insert or update of category_id, sub_category_id, sub_sub_category_id, images, image_url on public.products
for each row execute function public.check_product_categories();

-- products.stock / stock_status always equal the sum of their variants.
create or replace function public.refresh_product_stock(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total integer;
begin
  select coalesce(sum(quantity), 0) into v_total from public.product_variants where product_id = p_product_id;
  update public.products
     set stock = v_total, stock_status = public.stock_status_for(v_total)
   where id = p_product_id
     and (stock, stock_status) is distinct from (v_total, public.stock_status_for(v_total));
end;
$$;

create or replace function public.product_variants_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.refresh_product_stock(old.product_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and (tg_op = 'INSERT' or new.product_id <> old.product_id or new.quantity <> old.quantity) then
    perform public.refresh_product_stock(new.product_id);
  end if;
  return null;
end;
$$;

create trigger product_variants_refresh_stock
after insert or update or delete on public.product_variants
for each row execute function public.product_variants_changed();

-- Moves stock on one size/colour cell. Negative delta never goes below 0 (like adjustStock()).
-- A return to a cell that no longer exists recreates it.
create or replace function public.adjust_variant_stock(p_product_id uuid, p_size text, p_color text, p_delta integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_product_id is null or p_delta = 0 then
    return;
  end if;
  insert into public.product_variants (product_id, size, color, quantity)
  values (p_product_id, coalesce(p_size, 'Standard'), coalesce(p_color, 'Standard'), greatest(p_delta, 0))
  on conflict (product_id, size, color)
  do update set quantity = greatest(0, public.product_variants.quantity + p_delta);
end;
$$;

-- Admin → Add/Edit product & Inventory: save the whole size × colour grid at once
-- (buildVariantStock). p_stock = {"7": {"Rose Gold": 3}, "Standard": {"Pearl": 10}}.
-- Cells for sizes/colours no longer offered are removed; missing cells count as 0.
create or replace function public.set_product_variants(p_product_id uuid, p_sizes text[], p_colors text[], p_stock jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sizes  text[] := case when cardinality(coalesce(p_sizes, '{}')) = 0 then array['Standard'] else p_sizes end;
  v_colors text[] := case when cardinality(coalesce(p_colors, '{}')) = 0 then array['Standard'] else p_colors end;
  v_total  integer;
begin
  if not (public.is_trusted_caller() or public.has_any_permission(array['add-product', 'inventory']::public.admin_module[])) then
    raise exception 'Not allowed to edit stock.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.products where id = p_product_id) then
    raise exception 'Product not found.' using errcode = 'P0002';
  end if;

  update public.products set sizes = coalesce(p_sizes, '{}'), colors = coalesce(p_colors, '{}') where id = p_product_id;

  delete from public.product_variants
   where product_id = p_product_id and (size <> all (v_sizes) or color <> all (v_colors));

  insert into public.product_variants (product_id, size, color, quantity)
  select p_product_id, s, c, greatest(0, coalesce((p_stock -> s ->> c)::integer, 0))
    from unnest(v_sizes) as s cross join unnest(v_colors) as c
  on conflict (product_id, size, color) do update set quantity = excluded.quantity;

  select stock into v_total from public.products where id = p_product_id;
  return v_total;
end;
$$;

-- -----------------------------------------------------------------------------
-- Coupons & totals (couponState / couponProblem / couponDiscount / calculateTotals)
-- -----------------------------------------------------------------------------
create or replace function public.coupon_state(c public.coupons, on_date date default current_date)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when c.status <> 'Active' then 'Paused'
    when c.valid_from is not null and on_date < c.valid_from then 'Scheduled'
    when c.valid_till is not null and on_date > c.valid_till then 'Ended'
    when c.usage_limit is not null and c.usage_count >= c.usage_limit then 'Used up'
    else 'Live'
  end;
$$;

create or replace function public.coupon_discount(c public.coupons, subtotal numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select least(
    subtotal,
    case
      when c.discount_type = 'Percentage' then
        least(round(subtotal * c.discount_value / 100), coalesce(c.max_discount, round(subtotal * c.discount_value / 100)))
      else least(c.discount_value, coalesce(c.max_discount, c.discount_value))
    end
  );
$$;

-- Why a code can't be used on this subtotal, or null when it can.
create or replace function public.coupon_problem(p_code text, p_subtotal numeric)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.coupons;
  v_state text;
begin
  select * into c from public.coupons where code = upper(btrim(coalesce(p_code, '')));
  if not found then
    return 'That code is not valid.';
  end if;
  v_state := public.coupon_state(c);
  if v_state = 'Scheduled' then return c.code || ' starts on ' || c.valid_from || '.'; end if;
  if v_state in ('Ended', 'Paused') then return c.code || ' has expired.'; end if;
  if v_state = 'Used up' then return c.code || ' has been fully redeemed.'; end if;
  if p_subtotal < c.min_purchase then
    return c.code || ' needs a bag of at least ₹' || to_char(c.min_purchase, 'FM99,99,99,999') || '.';
  end if;
  return null;
end;
$$;

-- Subtotal → discount, delivery and total, exactly like calculateTotals().
create or replace function public.calculate_totals(p_subtotal numeric, p_code text default '')
returns table (subtotal numeric, discount numeric, delivery numeric, total numeric, coupon_code text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.coupons;
  s public.store_settings;
  v_discount numeric := 0;
  v_code text := '';
begin
  select * into s from public.store_settings limit 1;
  if coalesce(btrim(p_code), '') <> '' and public.coupon_problem(p_code, p_subtotal) is null then
    select * into c from public.coupons where code = upper(btrim(p_code));
    v_discount := public.coupon_discount(c, p_subtotal);
    v_code := c.code;
  end if;
  subtotal := p_subtotal;
  discount := v_discount;
  delivery := case
    when p_subtotal = 0 or p_subtotal - v_discount >= coalesce(s.free_delivery_from, 4999) then 0
    else coalesce(s.delivery_fee, 149)
  end;
  total := p_subtotal - v_discount + delivery;
  coupon_code := case when v_discount > 0 then v_code else '' end;
  return next;
end;
$$;

-- Checkout "Apply" button. Safe for anonymous visitors.
create or replace function public.validate_coupon(p_code text, p_subtotal numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_problem text := public.coupon_problem(p_code, p_subtotal);
  t record;
begin
  if v_problem is not null then
    return jsonb_build_object('valid', false, 'message', v_problem);
  end if;
  select * into t from public.calculate_totals(p_subtotal, p_code);
  return jsonb_build_object('valid', true, 'code', t.coupon_code, 'discount', t.discount,
                            'delivery', t.delivery, 'total', t.total);
end;
$$;

-- -----------------------------------------------------------------------------
-- Orders
-- -----------------------------------------------------------------------------

-- placeWebsiteOrder(): checks and takes the exact size/colour from stock, prices from the
-- database (never the browser), applies the coupon, adds or updates the customer, files the order.
--
-- p_order = {
--   "lines":   [{"product_id": "…", "size": "7", "color": "Rose Gold", "qty": 1}],
--   "coupon_code": "WELCOME500",
--   "payment_method": "Razorpay" | "Cash on Delivery" | "UPI" | …,
--   "address": {"name","phone","email","line","city","state","pin"},
--   "receipt": {"payment_id","gateway_order_id","detail"},       -- prepaid only
--   "source": "Website" | "Admin", "payment_status": "Paid", "notes": ""   -- admin/backend only
-- }
--
-- Prepaid orders are only marked Paid when placed by the backend (service_role, after verifying the
-- Razorpay signature) or by an admin. A browser calling this directly gets payment_status 'Pending'.
create or replace function public.place_order(p_order jsonb)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trusted   boolean := public.is_trusted_caller();
  v_admin     boolean := public.has_permission('orders');
  v_addr      jsonb   := coalesce(p_order -> 'address', '{}'::jsonb);
  v_receipt   jsonb   := p_order -> 'receipt';
  v_method    public.payment_method := coalesce(p_order ->> 'payment_method', 'Cash on Delivery')::public.payment_method;
  v_source    public.order_source;
  v_pstatus   public.payment_status;
  v_email     text := lower(btrim(coalesce(v_addr ->> 'email', '')));
  v_name      text := btrim(coalesce(v_addr ->> 'name', ''));
  v_phone     text := btrim(coalesce(v_addr ->> 'phone', ''));
  v_line      jsonb;
  v_product   public.products;
  v_have      integer;
  v_qty       integer;
  v_size      text;
  v_color     text;
  v_subtotal  numeric := 0;
  v_count     integer := 0;
  v_totals    record;
  v_customer  uuid;
  v_order     public.orders;
  s           public.store_settings;
begin
  if jsonb_typeof(p_order -> 'lines') <> 'array' or jsonb_array_length(p_order -> 'lines') = 0 then
    raise exception 'Your bag is empty.' using errcode = '22023';
  end if;
  if v_name = '' then
    raise exception 'Please enter the customer name.' using errcode = '22023';
  end if;

  v_source := case when (v_trusted or v_admin) then coalesce(p_order ->> 'source', 'Website') else 'Website' end::public.order_source;

  select * into s from public.store_settings limit 1;
  if v_source = 'Website' and not (v_trusted or v_admin) then
    if v_method = 'Cash on Delivery' and not coalesce(s.cod_enabled, true) then
      raise exception 'Cash on Delivery is not available.' using errcode = '22023';
    end if;
    if v_method <> 'Cash on Delivery' and not coalesce(s.razorpay_enabled, true) then
      raise exception 'Online payment is not available.' using errcode = '22023';
    end if;
  end if;

  if v_method <> 'Cash on Delivery' and v_source = 'Website' and coalesce(v_receipt ->> 'payment_id', '') = '' then
    raise exception 'Payment has not been verified by Razorpay.' using errcode = '22023';
  end if;

  v_pstatus := case
    when (v_trusted or v_admin) and p_order ? 'payment_status' then (p_order ->> 'payment_status')::public.payment_status
    when v_method = 'Cash on Delivery' then 'Pending'
    when v_trusted or v_admin then 'Paid'
    else 'Pending'
  end;

  -- Lock and check every variant first, so nothing changes unless all lines fit.
  for v_line in select * from jsonb_array_elements(p_order -> 'lines') loop
    v_qty   := (v_line ->> 'qty')::integer;
    v_size  := coalesce(nullif(v_line ->> 'size', ''), 'Standard');
    v_color := coalesce(nullif(v_line ->> 'color', ''), 'Standard');
    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantity must be at least 1.' using errcode = '22023';
    end if;

    select * into v_product from public.products where id = (v_line ->> 'product_id')::uuid;
    if not found or (v_source = 'Website' and not v_product.is_live) then
      raise exception 'A product in your bag is no longer available.' using errcode = 'P0002';
    end if;

    select quantity into v_have from public.product_variants
     where product_id = v_product.id and size = v_size and color = v_color
     for update;
    if coalesce(v_have, 0) < v_qty then
      raise exception 'Only % of % (%) left.', coalesce(v_have, 0), v_product.name,
        coalesce(nullif(array_to_string(array_remove(array[nullif(v_size, 'Standard'), nullif(v_color, 'Standard')], null), ', '), ''), 'this option')
        using errcode = 'P0001';
    end if;

    v_subtotal := v_subtotal + v_product.price * v_qty;
    v_count    := v_count + v_qty;
  end loop;

  select * into v_totals from public.calculate_totals(v_subtotal, coalesce(p_order ->> 'coupon_code', ''));

  -- Add or update the customer (by email), linking the signed-in shopper.
  if v_email <> '' then
    insert into public.customers (name, email, phone, profile_id)
    values (v_name, v_email, v_phone,
            case when auth.uid() is not null and not exists (select 1 from public.customers where profile_id = auth.uid())
                 then auth.uid() end)
    on conflict (email) where email is not null
    do update set name = excluded.name,
                  phone = case when excluded.phone <> '' then excluded.phone else public.customers.phone end
    returning id into v_customer;
  else
    v_customer := public.current_customer_id();
  end if;

  insert into public.orders (
    customer_id, customer_name, email, phone, shipping_address, city, state, postal_code,
    subtotal, discount, delivery_fee, total, coupon_code, items_count,
    payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
    source, notes, created_by
  ) values (
    v_customer, v_name, v_email, v_phone,
    btrim(coalesce(v_addr ->> 'line', '')), btrim(coalesce(v_addr ->> 'city', '')),
    btrim(coalesce(v_addr ->> 'state', '')), btrim(coalesce(v_addr ->> 'pin', '')),
    v_totals.subtotal, v_totals.discount, v_totals.delivery, v_totals.total, v_totals.coupon_code, v_count,
    v_method, v_pstatus,
    case when v_method = 'Cash on Delivery' then null else nullif(v_receipt ->> 'payment_id', '') end,
    nullif(v_receipt ->> 'detail', ''), nullif(v_receipt ->> 'gateway_order_id', ''),
    v_source, coalesce(p_order ->> 'notes', ''),
    case when v_admin then auth.uid() end
  ) returning * into v_order;

  for v_line in select * from jsonb_array_elements(p_order -> 'lines') loop
    v_qty   := (v_line ->> 'qty')::integer;
    v_size  := coalesce(nullif(v_line ->> 'size', ''), 'Standard');
    v_color := coalesce(nullif(v_line ->> 'color', ''), 'Standard');
    select * into v_product from public.products where id = (v_line ->> 'product_id')::uuid;

    insert into public.order_items (order_id, product_id, name, sku, size, color, qty, price, image_url)
    values (v_order.id, v_product.id, v_product.name, v_product.sku, v_size, v_color, v_qty, v_product.price,
            coalesce(v_product.color_images -> v_color ->> 0, nullif(v_product.images[1], ''), v_product.image_url));

    perform public.adjust_variant_stock(v_product.id, v_size, v_color, -v_qty);
  end loop;

  if v_order.coupon_code <> '' then
    update public.coupons set usage_count = usage_count + 1 where code = v_order.coupon_code;
  end if;

  return v_order;
end;
$$;

-- Order status rules: Cancelled is final and puts the stock back; history is kept.
create or replace function public.orders_before_status_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.order_status = 'Cancelled' and new.order_status <> 'Cancelled' then
    raise exception 'Cancelled orders are closed; their stock was already returned.' using errcode = 'P0001';
  end if;
  if new.order_status = 'Cancelled' and old.order_status <> 'Cancelled' then
    new.cancelled_at := now();
  end if;
  return new;
end;
$$;

create trigger orders_before_status_change
before update of order_status on public.orders
for each row execute function public.orders_before_status_change();

create or replace function public.orders_after_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, null, new.order_status, auth.uid());
    return null;
  end if;

  if new.order_status is distinct from old.order_status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, old.order_status, new.order_status, auth.uid());

    if new.order_status = 'Cancelled' then
      -- restockOrder()
      for r in select product_id, size, color, qty from public.order_items where order_id = new.id loop
        perform public.adjust_variant_stock(r.product_id, r.size, r.color, r.qty);
      end loop;
      update public.shipments set status = 'Cancelled' where order_id = new.id and status in ('Created', 'In Transit');
    end if;
  end if;
  return null;
end;
$$;

create trigger orders_after_status_change
after insert or update of order_status on public.orders
for each row execute function public.orders_after_status_change();

-- Line totals are the source of truth for subtotal/items_count when admins edit lines.
create or replace function public.refresh_order_totals(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders;
  v_subtotal numeric;
  v_count integer;
  t record;
begin
  if not (public.is_trusted_caller() or public.has_permission('orders')) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  select coalesce(sum(line_total), 0), coalesce(sum(qty), 0) into v_subtotal, v_count
    from public.order_items where order_id = p_order_id;
  select coupon_code into v_order.coupon_code from public.orders where id = p_order_id;
  select * into t from public.calculate_totals(v_subtotal, v_order.coupon_code);
  update public.orders
     set subtotal = t.subtotal, discount = t.discount, delivery_fee = t.delivery, total = t.total,
         items_count = v_count
   where id = p_order_id
  returning * into v_order;
  return v_order;
end;
$$;

-- -----------------------------------------------------------------------------
-- POS register
-- -----------------------------------------------------------------------------

-- sellInStore(): takes each line from whichever sizes/colours still have stock and records exactly
-- where it came from, so returns go back to the same cell.
-- p_sale = {"items":[{"product_id":"…","qty":2,"price":4799}], "customer_name":"", "customer_phone":"",
--           "payment_method":"UPI", "discount": 0, "cashier_name": "Reg #01"}
create or replace function public.pos_create_sale(p_sale jsonb)
returns public.pos_transactions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item     jsonb;
  v_product  public.products;
  v_variant  record;
  v_left     integer;
  v_take     integer;
  v_lines    jsonb;
  v_price    numeric;
  v_subtotal numeric := 0;
  v_count    integer := 0;
  v_discount numeric := greatest(0, coalesce((p_sale ->> 'discount')::numeric, 0));
  v_tx       public.pos_transactions;
  v_customer uuid;
  v_cname    text := coalesce(nullif(btrim(p_sale ->> 'customer_name'), ''), 'Walk-in Customer');
  v_cphone   text := btrim(coalesce(p_sale ->> 'customer_phone', ''));
  v_cashier  text;
begin
  if not (public.is_trusted_caller() or public.has_permission('pos-terminal')) then
    raise exception 'Not allowed to use the POS register.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_sale -> 'items') <> 'array' or jsonb_array_length(p_sale -> 'items') = 0 then
    raise exception 'The bill is empty.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p_sale ->> 'cashier_name'), ''), nullif(full_name, ''), email, 'Cashier')
    into v_cashier from public.profiles where id = auth.uid();

  -- Known customer by phone; a named customer with a phone is added to Customers.
  if v_cphone <> '' then
    select id into v_customer from public.customers where phone = v_cphone order by created_at limit 1;
    if v_customer is null and v_cname <> 'Walk-in Customer' then
      insert into public.customers (name, phone) values (v_cname, v_cphone) returning id into v_customer;
    end if;
  end if;

  insert into public.pos_transactions (cashier_id, cashier_name, customer_id, customer_name, customer_phone, payment_method)
  values (auth.uid(), coalesce(v_cashier, coalesce(nullif(btrim(p_sale ->> 'cashier_name'), ''), 'Cashier')),
          v_customer, v_cname, v_cphone, (p_sale ->> 'payment_method')::public.pos_payment_method)
  returning * into v_tx;

  for v_item in select * from jsonb_array_elements(p_sale -> 'items') loop
    select * into v_product from public.products where id = (v_item ->> 'product_id')::uuid;
    if not found then
      raise exception 'A product in this bill no longer exists.' using errcode = 'P0002';
    end if;
    v_left := (v_item ->> 'qty')::integer;
    if v_left is null or v_left <= 0 then
      raise exception 'Quantity must be at least 1.' using errcode = '22023';
    end if;
    v_price := coalesce((v_item ->> 'price')::numeric, v_product.price);
    v_lines := '[]'::jsonb;

    for v_variant in
      select id, size, color, quantity from public.product_variants
       where product_id = v_product.id and quantity > 0
       order by created_at, size, color
       for update
    loop
      exit when v_left = 0;
      v_take := least(v_left, v_variant.quantity);
      update public.product_variants set quantity = quantity - v_take where id = v_variant.id;
      v_lines := v_lines || jsonb_build_object('size', v_variant.size, 'color', v_variant.color, 'qty', v_take);
      v_left := v_left - v_take;
    end loop;

    if v_left > 0 then
      raise exception 'Only % of % left in stock.', (v_item ->> 'qty')::integer - v_left, v_product.name using errcode = 'P0001';
    end if;

    insert into public.pos_transaction_items (transaction_id, product_id, name, qty, price, stock_lines)
    values (v_tx.id, v_product.id, v_product.name, (v_item ->> 'qty')::integer, v_price, v_lines);

    v_subtotal := v_subtotal + v_price * (v_item ->> 'qty')::integer;
    v_count    := v_count + (v_item ->> 'qty')::integer;
  end loop;

  update public.pos_transactions
     set items_count = v_count, subtotal = v_subtotal,
         discount = least(v_discount, v_subtotal), total = v_subtotal - least(v_discount, v_subtotal)
   where id = v_tx.id
  returning * into v_tx;
  return v_tx;
end;
$$;

-- POS returns / exchanges: puts the chosen lines back exactly where they came from. Returns items restocked.
create or replace function public.pos_return_items(p_transaction_id uuid, p_item_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  l jsonb;
  v_size text;
  v_color text;
  v_count integer := 0;
begin
  if not (public.is_trusted_caller() or public.has_any_permission(array['pos-terminal', 'pos-history']::public.admin_module[])) then
    raise exception 'Not allowed to process returns.' using errcode = '42501';
  end if;

  for r in
    select id, product_id, qty, stock_lines from public.pos_transaction_items
     where transaction_id = p_transaction_id and id = any (p_item_ids) and returned_at is null
     for update
  loop
    if jsonb_array_length(r.stock_lines) > 0 then
      for l in select * from jsonb_array_elements(r.stock_lines) loop
        perform public.adjust_variant_stock(r.product_id, l ->> 'size', l ->> 'color', (l ->> 'qty')::integer);
      end loop;
    else
      -- Older bills without stock lines go back to the product's first variant (as the app does).
      select size, color into v_size, v_color from public.product_variants
       where product_id = r.product_id order by created_at, size, color limit 1;
      perform public.adjust_variant_stock(r.product_id, coalesce(v_size, 'Standard'), coalesce(v_color, 'Standard'), r.qty);
    end if;
    update public.pos_transaction_items set returned_at = now() where id = r.id;
    v_count := v_count + r.qty;
  end loop;
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- Staff & misc
-- -----------------------------------------------------------------------------

-- Staff logins are not shoppers: drop the customer row the sign-up trigger made (if it has no orders).
create or replace function public.drop_staff_customer(p_user_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.customers c
   where c.profile_id = p_user_id
     and not exists (select 1 from public.orders o where o.customer_id = c.id)
     and not exists (select 1 from public.pos_transactions t where t.customer_id = c.id);
$$;

-- Admin Security → staff logins. Create the login first (Dashboard → Auth, or auth.admin.createUser
-- from the server), then give it a role and modules here.
create or replace function public.set_staff_access(p_user_id uuid, p_role public.user_role, p_permissions public.admin_module[] default '{}')
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  if not (public.is_trusted_caller() or public.is_super_admin()) then
    raise exception 'Only a super admin can manage staff.' using errcode = '42501';
  end if;
  update public.profiles
     set role = p_role,
         permissions = case when p_role = 'sub_admin' then array_remove(coalesce(p_permissions, '{}'), 'settings') else '{}' end
   where id = p_user_id
  returning * into v_profile;
  if not found then
    raise exception 'No user with that id.' using errcode = 'P0002';
  end if;
  if p_role <> 'customer' then
    perform public.drop_staff_customer(p_user_id);
  end if;
  return v_profile;
end;
$$;

-- SQL editor only: make the first owner. Usage:  select public.make_super_admin('owner@shop.com');
create or replace function public.make_super_admin(p_email text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles;
begin
  update public.profiles set role = 'super_admin', permissions = '{}', is_active = true
   where email = lower(btrim(p_email))
  returning * into v_profile;
  if not found then
    raise exception 'No signed-up user with email %. Create the user in Authentication first.', p_email using errcode = 'P0002';
  end if;
  perform public.drop_staff_customer(v_profile.id);
  return v_profile;
end;
$$;

-- Storefront video plays (recordVideoView). Safe for anonymous visitors.
create or replace function public.record_video_view(p_video_id uuid)
returns integer
language sql
security definer
set search_path = ''
as $$
  update public.videos set views = views + 1 where id = p_video_id and is_active returning views;
$$;

-- Only one theme is active; activating also checks the theme exists.
create or replace function public.activate_theme(p_theme_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (public.is_trusted_caller() or public.has_permission('themes')) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.themes where id = p_theme_id) then
    raise exception 'Theme % not found.', p_theme_id using errcode = 'P0002';
  end if;
  update public.store_settings set active_theme_id = p_theme_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Function privileges: internal helpers are not callable over the API.
-- -----------------------------------------------------------------------------
revoke execute on function public.make_super_admin(text) from public, anon, authenticated;
revoke execute on function public.adjust_variant_stock(uuid, text, text, integer) from public, anon, authenticated;
revoke execute on function public.refresh_product_stock(uuid) from public, anon, authenticated;
revoke execute on function public.drop_staff_customer(uuid) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_user_email_change() from public, anon, authenticated;
