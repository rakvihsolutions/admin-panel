-- =============================================================================
-- 04 · Row Level Security
--   anon (website visitor)  → reads the live catalog and storefront content only
--   customer (signed in)    → also their own profile, orders, bag and wishlist
--   sub_admin               → only the admin modules ticked for them
--   super_admin             → everything
--   service_role (server)   → bypasses RLS (keep that key on the server only)
-- =============================================================================

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

-- Re-apply the lock-downs from 03 after the blanket grant above.
revoke execute on function public.make_super_admin(text) from anon, authenticated;
revoke execute on function public.adjust_variant_stock(uuid, text, text, integer) from anon, authenticated;
revoke execute on function public.refresh_product_stock(uuid) from anon, authenticated;
revoke execute on function public.drop_staff_customer(uuid) from anon, authenticated;
revoke execute on function public.handle_new_user() from anon, authenticated;
revoke execute on function public.handle_user_email_change() from anon, authenticated;

-- Store settings: payment fields are super-admin only (Admin Security), theme is Theme Setup,
-- the rest is Store Details.
create or replace function public.guard_store_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.is_trusted_caller() then
    return new;
  end if;
  if (new.razorpay_key_id, new.merchant_name, new.razorpay_enabled, new.cod_enabled, new.gateway_verified_at)
     is distinct from (old.razorpay_key_id, old.merchant_name, old.razorpay_enabled, old.cod_enabled, old.gateway_verified_at)
     and not public.has_permission('settings') then
    raise exception 'Only a super admin can change payment settings.' using errcode = '42501';
  end if;
  if new.active_theme_id is distinct from old.active_theme_id and not public.has_permission('themes') then
    raise exception 'Not allowed to change the theme.' using errcode = '42501';
  end if;
  if (to_jsonb(new) - array['razorpay_key_id','merchant_name','razorpay_enabled','cod_enabled','gateway_verified_at','active_theme_id','updated_at'])
     is distinct from
     (to_jsonb(old) - array['razorpay_key_id','merchant_name','razorpay_enabled','cod_enabled','gateway_verified_at','active_theme_id','updated_at'])
     and not public.has_permission('store-details') then
    raise exception 'Not allowed to change store details.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger store_settings_guard
before update on public.store_settings
for each row execute function public.guard_store_settings();

-- -----------------------------------------------------------------------------
-- Enable RLS everywhere
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Settings & themes
-- -----------------------------------------------------------------------------
create policy "store settings are public" on public.store_settings for select using (true);
create policy "admins update store settings" on public.store_settings for update to authenticated
  using (public.has_any_permission(array['store-details','themes','settings']::public.admin_module[]))
  with check (public.has_any_permission(array['store-details','themes','settings']::public.admin_module[]));

create policy "themes are public" on public.themes for select using (true);
create policy "theme admins write themes" on public.themes for all to authenticated
  using (public.has_permission('themes')) with check (public.has_permission('themes'));

-- -----------------------------------------------------------------------------
-- People
-- -----------------------------------------------------------------------------
create policy "read own profile or super admin" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_super_admin());
create policy "update own profile or super admin" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_super_admin())
  with check (id = auth.uid() or public.is_super_admin());
create policy "super admin deletes profiles" on public.profiles for delete to authenticated
  using (public.is_super_admin() and id <> auth.uid());

create policy "read own customer or staff" on public.customers for select to authenticated
  using (profile_id = auth.uid()
         or public.has_any_permission(array['customers','orders','pos-terminal','pos-history','dashboard','reports']::public.admin_module[]));
create policy "customer admins insert" on public.customers for insert to authenticated
  with check (public.has_any_permission(array['customers','orders','pos-terminal']::public.admin_module[]));
create policy "update own customer or customer admins" on public.customers for update to authenticated
  using (profile_id = auth.uid() or public.has_permission('customers'))
  with check (profile_id = auth.uid() or public.has_permission('customers'));
create policy "customer admins delete" on public.customers for delete to authenticated
  using (public.has_permission('customers'));

create policy "own addresses or staff" on public.customer_addresses for all to authenticated
  using (customer_id = public.current_customer_id()
         or public.has_any_permission(array['customers','orders']::public.admin_module[]))
  with check (customer_id = public.current_customer_id()
         or public.has_any_permission(array['customers','orders']::public.admin_module[]));

-- -----------------------------------------------------------------------------
-- Catalog
-- -----------------------------------------------------------------------------
create policy "active categories are public" on public.categories for select
  using (status = 'Active' or public.is_admin());
create policy "category admins write" on public.categories for all to authenticated
  using (public.has_permission('category')) with check (public.has_permission('category'));

create policy "active sub categories are public" on public.sub_categories for select
  using (status = 'Active' or public.is_admin());
create policy "sub category admins write" on public.sub_categories for all to authenticated
  using (public.has_permission('sub-category')) with check (public.has_permission('sub-category'));

create policy "active sub sub categories are public" on public.sub_sub_categories for select
  using (status = 'Active' or public.is_admin());
create policy "sub sub category admins write" on public.sub_sub_categories for all to authenticated
  using (public.has_permission('sub-sub-category')) with check (public.has_permission('sub-sub-category'));

create policy "sizes are public" on public.sizes for select using (true);
create policy "attribute admins write sizes" on public.sizes for all to authenticated
  using (public.has_permission('attributes')) with check (public.has_permission('attributes'));
create policy "colors are public" on public.colors for select using (true);
create policy "attribute admins write colors" on public.colors for all to authenticated
  using (public.has_permission('attributes')) with check (public.has_permission('attributes'));
create policy "tags are public" on public.tags for select using (true);
create policy "attribute admins write tags" on public.tags for all to authenticated
  using (public.has_permission('attributes')) with check (public.has_permission('attributes'));

create policy "live products are public" on public.products for select
  using (is_live or public.is_admin());
create policy "product admins write" on public.products for all to authenticated
  using (public.has_any_permission(array['add-product','product-list','inventory']::public.admin_module[]))
  with check (public.has_any_permission(array['add-product','product-list','inventory']::public.admin_module[]));

create policy "tags of visible products are public" on public.product_tags for select
  using (exists (select 1 from public.products p where p.id = product_id));
create policy "product admins write product tags" on public.product_tags for all to authenticated
  using (public.has_any_permission(array['add-product','product-list']::public.admin_module[]))
  with check (public.has_any_permission(array['add-product','product-list']::public.admin_module[]));

create policy "variants of visible products are public" on public.product_variants for select
  using (exists (select 1 from public.products p where p.id = product_id));
create policy "stock admins write variants" on public.product_variants for all to authenticated
  using (public.has_any_permission(array['add-product','inventory']::public.admin_module[]))
  with check (public.has_any_permission(array['add-product','inventory']::public.admin_module[]));

-- -----------------------------------------------------------------------------
-- Coupons: visitors only see the live header offers; checkout uses validate_coupon().
-- -----------------------------------------------------------------------------
create policy "header coupons are public" on public.coupons for select
  using ((show_in_header and status = 'Active'
          and (valid_from is null or valid_from <= current_date)
          and (valid_till is null or valid_till >= current_date))
         or public.has_permission('coupons'));
create policy "coupon admins write" on public.coupons for all to authenticated
  using (public.has_permission('coupons')) with check (public.has_permission('coupons'));

-- -----------------------------------------------------------------------------
-- Orders: shoppers read their own; checkout goes through place_order().
-- -----------------------------------------------------------------------------
create policy "own orders or order staff" on public.orders for select to authenticated
  using (customer_id = public.current_customer_id()
         or public.has_any_permission(array['orders','customers','dashboard','reports']::public.admin_module[]));
create policy "order admins insert" on public.orders for insert to authenticated
  with check (public.has_permission('orders'));
create policy "order admins update" on public.orders for update to authenticated
  using (public.has_permission('orders')) with check (public.has_permission('orders'));
create policy "super admin deletes orders" on public.orders for delete to authenticated
  using (public.is_super_admin());

create policy "items of readable orders" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
create policy "order admins write items" on public.order_items for all to authenticated
  using (public.has_permission('orders')) with check (public.has_permission('orders'));

create policy "shipments of readable orders" on public.shipments for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
create policy "order admins write shipments" on public.shipments for all to authenticated
  using (public.has_permission('orders')) with check (public.has_permission('orders'));

create policy "emails of readable orders" on public.order_emails for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
create policy "order admins log emails" on public.order_emails for insert to authenticated
  with check (public.has_permission('orders'));

create policy "history of readable orders" on public.order_status_history for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));

-- -----------------------------------------------------------------------------
-- POS: written only through pos_create_sale() / pos_return_items().
-- -----------------------------------------------------------------------------
create policy "pos staff read bills" on public.pos_transactions for select to authenticated
  using (public.has_any_permission(array['pos-terminal','pos-history','dashboard','reports']::public.admin_module[]));
create policy "super admin deletes bills" on public.pos_transactions for delete to authenticated
  using (public.is_super_admin());

create policy "pos staff read bill lines" on public.pos_transaction_items for select to authenticated
  using (public.has_any_permission(array['pos-terminal','pos-history','dashboard','reports']::public.admin_module[]));

-- -----------------------------------------------------------------------------
-- Storefront content
-- -----------------------------------------------------------------------------
create policy "active banners are public" on public.hero_banners for select
  using (is_active or public.is_admin());
create policy "banner admins write" on public.hero_banners for all to authenticated
  using (public.has_permission('banners')) with check (public.has_permission('banners'));

create policy "instagram posts are public" on public.instagram_posts for select using (true);
create policy "instagram admins write" on public.instagram_posts for all to authenticated
  using (public.has_permission('instagram')) with check (public.has_permission('instagram'));

create policy "active videos are public" on public.videos for select
  using (is_active or public.is_admin());
create policy "video admins write" on public.videos for all to authenticated
  using (public.has_permission('videos')) with check (public.has_permission('videos'));

-- -----------------------------------------------------------------------------
-- Shopper bag & wishlist
-- -----------------------------------------------------------------------------
create policy "own bag" on public.cart_items for all to authenticated
  using (customer_id = public.current_customer_id() or public.has_permission('customers'))
  with check (customer_id = public.current_customer_id());
create policy "own wishlist" on public.wishlist_items for all to authenticated
  using (customer_id = public.current_customer_id() or public.has_permission('customers'))
  with check (customer_id = public.current_customer_id());
