-- =============================================================================
-- 01 · Types
-- Enum values match the strings the admin panel already uses (demo-data.ts),
-- so the frontend can switch from localStorage to Supabase without remapping.
-- =============================================================================

-- Who is signed in. Super admin = full access; sub admin = only the modules
-- listed in profiles.permissions; customer = storefront shopper.
create type public.user_role as enum ('super_admin', 'sub_admin', 'customer');

-- One value per admin page (AdminTab in page.tsx). Used for sub-admin permissions.
create type public.admin_module as enum (
  'dashboard', 'reports',
  'add-product', 'product-list', 'inventory', 'attributes',
  'category', 'sub-category', 'sub-sub-category',
  'orders', 'customers', 'coupons',
  'pos-terminal', 'pos-history',
  'banners', 'instagram', 'videos', 'themes', 'store-details',
  'settings'
);

create type public.record_status     as enum ('Active', 'Inactive');
create type public.stock_status      as enum ('In Stock', 'Low Stock', 'Out of Stock');
create type public.discount_type     as enum ('Percentage', 'Fixed');
create type public.coupon_status     as enum ('Active', 'Expired');
create type public.order_status      as enum ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled');
create type public.payment_status    as enum ('Paid', 'Pending', 'Failed', 'Refunded');
create type public.payment_method    as enum ('Credit Card', 'UPI', 'Net Banking', 'Razorpay', 'Cash on Delivery');
create type public.order_source      as enum ('Website', 'Admin');
create type public.shipment_status   as enum ('Created', 'In Transit', 'Delivered', 'Cancelled');
create type public.order_email_kind  as enum ('Status update', 'Invoice');
create type public.pos_payment_method as enum ('Cash', 'Card', 'UPI', 'COD');
create type public.text_align        as enum ('left', 'center', 'right');
create type public.theme_layout      as enum ('signature', 'marketplace', 'lifestyle', 'boutique', 'volt', 'aster', 'atelier', 'aurora');
