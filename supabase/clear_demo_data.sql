-- =============================================================================
-- Clear demo data → empty store, ready for a real client.
--
-- Removes: products, categories, attributes, coupons, orders, shipments, POS
--          bills, banners, Instagram posts, videos, guest customers, bags.
-- Keeps:   logins (auth users + profiles + their customer rows), the 8 built-in
--          themes, custom themes, and the store_settings row (reset to blank).
--
-- Files already uploaded to Storage are not touched (delete them in Dashboard → Storage).
-- To load the demo again later, run seed.sql.
-- =============================================================================
begin;

truncate table
  public.cart_items, public.wishlist_items,
  public.order_status_history, public.order_emails, public.shipments, public.order_items, public.orders,
  public.pos_transaction_items, public.pos_transactions,
  public.product_tags, public.product_variants, public.videos, public.products,
  public.sub_sub_categories, public.sub_categories, public.categories,
  public.sizes, public.colors, public.tags, public.coupons,
  public.hero_banners, public.instagram_posts;

delete from public.customer_addresses where customer_id in (select id from public.customers where profile_id is null);
delete from public.customers where profile_id is null;

alter sequence public.order_number_seq restart with 1001;   -- first real order: ORD-1001
alter sequence public.pos_receipt_seq  restart with 1001;   -- first real bill:  REC-<year>-1001

update public.store_settings set
  name = 'My Store', tagline = '', footer_about = '', footer_note = '', logo_url = '',
  show_name_with_logo = true, email = '', phone = '', whatsapp = '', address = '', hours = '',
  gstin = '', return_policy = '',
  social = '{"instagram":"","facebook":"","youtube":"","x":""}'::jsonb,
  razorpay_key_id = '', merchant_name = '', gateway_verified_at = null,
  active_theme_id = 'default';

-- Optional: also remove the demo logins created by demo_logins.sql
-- delete from auth.users where email in ('demo.admin@example.com', 'demo.shopper@example.com');

commit;
