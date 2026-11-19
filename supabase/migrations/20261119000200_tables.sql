-- =============================================================================
-- 02 · Tables
-- Money is numeric(12,2) in rupees. Every table has created_at / updated_at.
-- =============================================================================

-- Shared trigger: keeps updated_at current on every update.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- True when every theme colour key is present as #RRGGBB (isThemeColors in demo-data.ts).
create or replace function public.is_theme_colors(colors jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(colors) = 'object'
     and (select bool_and(colors ? k and (colors ->> k) ~ '^#[0-9A-Fa-f]{6}$')
          from unnest(array['accent','accent2','accentDark','accentLight','accentSoft','accentLine',
                            'ink','ink2','ink3','deep','page']) as k);
$$;

-- -----------------------------------------------------------------------------
-- Store settings (one row): Admin → Store Details, payment methods, delivery
-- rules and the active theme.
-- -----------------------------------------------------------------------------
create table public.themes (
  id          text primary key,                       -- 'default', 'marketplace', … or a custom slug
  name        text not null,
  version     text not null default '1.0',
  tagline     text not null default '',
  layout      public.theme_layout not null default 'signature',
  -- { accent, accent2, accentDark, accentLight, accentSoft, accentLine, ink, ink2, ink3, deep, page } as #RRGGBB
  colors      jsonb not null,
  is_custom   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint themes_colors_valid check (public.is_theme_colors(colors))
);

create table public.store_settings (
  id                   boolean primary key default true check (id),  -- guarantees a single row
  name                 text not null default 'My Store',
  tagline              text not null default '',
  footer_about         text not null default '',
  footer_note          text not null default '',
  logo_url             text not null default '',
  show_name_with_logo  boolean not null default true,
  email                text not null default '',
  phone                text not null default '',
  whatsapp             text not null default '',
  address              text not null default '',
  hours                text not null default '',
  gstin                text not null default '',
  return_policy        text not null default '',
  -- { instagram, facebook, youtube, x }
  social               jsonb not null default '{"instagram":"","facebook":"","youtube":"","x":""}'::jsonb,
  currency             text not null default 'INR',
  -- Delivery: free at or above free_delivery_from (after discount), otherwise delivery_fee.
  free_delivery_from   numeric(12,2) not null default 4999 check (free_delivery_from >= 0),
  delivery_fee         numeric(12,2) not null default 149  check (delivery_fee >= 0),
  -- Stock above this is 'In Stock', 1..this is 'Low Stock'.
  low_stock_threshold  integer not null default 10 check (low_stock_threshold >= 0),
  -- Payment gateway (Razorpay). Only the PUBLIC key id lives here; the secret stays in server env vars.
  razorpay_key_id      text not null default '',
  merchant_name        text not null default '',
  razorpay_enabled     boolean not null default true,
  cod_enabled          boolean not null default true,
  gateway_verified_at  timestamptz,
  active_theme_id      text references public.themes(id) on update cascade on delete set null default 'default',
  updated_at           timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- People
-- -----------------------------------------------------------------------------

-- One row per Supabase Auth user (admin, staff or shopper). Passwords live in auth.users only.
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text not null,
  full_name    text not null default '',
  phone        text not null default '',
  role         public.user_role not null default 'customer',
  -- Sub-admin access (ignored for super_admin, who can do everything).
  permissions  public.admin_module[] not null default '{}',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index profiles_email_key on public.profiles (lower(email));

-- Everyone who has bought or signed up: website shoppers, guests and POS customers.
-- Linked to a profile when the person has a login.
create table public.customers (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid unique references public.profiles(id) on delete set null,
  name           text not null,
  email          text,
  phone          text not null default '',
  notes          text not null default '',
  registered_at  date not null default current_date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint customers_email_lowercase check (email is null or email = lower(btrim(email)))
);
create unique index customers_email_key on public.customers (email) where email is not null;
create index customers_phone_idx on public.customers (phone) where phone <> '';

create table public.customer_addresses (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers(id) on delete cascade,
  label        text not null default 'Home',
  name         text not null,
  phone        text not null default '',
  line         text not null,
  city         text not null,
  state        text not null,
  postal_code  text not null,
  is_default   boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index customer_addresses_customer_idx on public.customer_addresses (customer_id);
create unique index customer_addresses_one_default on public.customer_addresses (customer_id) where is_default;

-- -----------------------------------------------------------------------------
-- Catalog: categories (3 levels), attributes, products, variants
-- -----------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  icon        text not null default '',
  image_url   text not null default '',
  blurb       text not null default '',
  status      public.record_status not null default 'Active',
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index categories_name_key on public.categories (lower(name));

create table public.sub_categories (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid not null references public.categories(id) on delete cascade,
  name         text not null,
  slug         text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status       public.record_status not null default 'Active',
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (category_id, slug)
);
create unique index sub_categories_name_key on public.sub_categories (category_id, lower(name));

create table public.sub_sub_categories (
  id               uuid primary key default gen_random_uuid(),
  sub_category_id  uuid not null references public.sub_categories(id) on delete cascade,
  name             text not null,
  slug             text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status           public.record_status not null default 'Active',
  sort_order       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (sub_category_id, slug)
);
create unique index sub_sub_categories_name_key on public.sub_sub_categories (sub_category_id, lower(name));

-- Admin → Sizes, Colours & Tags
create table public.sizes (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,                 -- 'Ring Size 6'
  code        text not null unique,          -- '6' (what products store)
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.colors (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  hex         text not null check (hex ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index colors_name_key on public.colors (lower(name));

create table public.tags (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index tags_name_key on public.tags (lower(name));

create table public.products (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null,
  slug                 text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description          text not null default '',
  sku                  text not null,
  barcode              text,
  category_id          uuid references public.categories(id) on delete set null,
  sub_category_id      uuid references public.sub_categories(id) on delete set null,
  sub_sub_category_id  uuid references public.sub_sub_categories(id) on delete set null,
  price                numeric(12,2) not null check (price >= 0),
  mrp                  numeric(12,2) check (mrp is null or mrp >= 0),
  cost_price           numeric(12,2) check (cost_price is null or cost_price >= 0),
  -- Size codes / colour names offered. Empty = no choice (stored as 'Standard' in variants).
  sizes                text[] not null default '{}',
  colors               text[] not null default '{}',
  image_url            text not null default '',
  images               text[] not null default '{}',
  -- { "Rose Gold": ["https://…", …] } photos per colour
  color_images         jsonb not null default '{}'::jsonb check (jsonb_typeof(color_images) = 'object'),
  highlights           text[] not null default '{}',
  -- [["Style","Pearl strand"],["Length","18 in"]]
  specs                jsonb not null default '[]'::jsonb check (jsonb_typeof(specs) = 'array'),
  is_new_arrival       boolean not null default false,
  is_featured          boolean not null default false,
  is_live              boolean not null default true,     -- off = hidden from the website, still in admin/POS
  rating               numeric(2,1) not null default 0 check (rating between 0 and 5),
  reviews_count        integer not null default 0 check (reviews_count >= 0),
  -- Total of all variants; maintained by trigger, never written directly.
  stock                integer not null default 0 check (stock >= 0),
  stock_status         public.stock_status not null default 'Out of Stock',
  seo_title            text not null default '',
  seo_description      text not null default '',
  search               tsvector generated always as (
                         setweight(to_tsvector('simple', coalesce(name, '')), 'A') ||
                         setweight(to_tsvector('simple', coalesce(sku, '') || ' ' || coalesce(barcode, '')), 'A') ||
                         setweight(to_tsvector('simple', coalesce(description, '')), 'C')
                       ) stored,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create unique index products_sku_key on public.products (upper(sku));
create unique index products_barcode_key on public.products (barcode) where barcode is not null and barcode <> '';
create index products_category_idx on public.products (category_id);
create index products_sub_category_idx on public.products (sub_category_id);
create index products_sub_sub_category_idx on public.products (sub_sub_category_id);
create index products_live_idx on public.products (is_live, is_featured, is_new_arrival);
create index products_search_idx on public.products using gin (search);

create table public.product_tags (
  product_id  uuid not null references public.products(id) on delete cascade,
  tag_id      uuid not null references public.tags(id) on delete cascade,
  primary key (product_id, tag_id)
);
create index product_tags_tag_idx on public.product_tags (tag_id);

-- Stock per size × colour. 'Standard' stands in when a product has no sizes or no colours.
create table public.product_variants (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products(id) on delete cascade,
  size        text not null default 'Standard',
  color       text not null default 'Standard',
  quantity    integer not null default 0 check (quantity >= 0),
  sku         text,                 -- optional per-variant SKU / barcode
  barcode     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (product_id, size, color)
);

-- -----------------------------------------------------------------------------
-- Coupons
-- -----------------------------------------------------------------------------
create table public.coupons (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique check (code = upper(btrim(code)) and code <> ''),
  description     text not null default '',
  discount_type   public.discount_type not null,
  discount_value  numeric(12,2) not null check (discount_value > 0),
  max_discount    numeric(12,2) check (max_discount is null or max_discount > 0),
  min_purchase    numeric(12,2) not null default 0 check (min_purchase >= 0),
  usage_limit     integer check (usage_limit is null or usage_limit > 0),
  usage_count     integer not null default 0 check (usage_count >= 0),
  valid_from      date,
  valid_till      date,                         -- null = never expires
  show_in_header  boolean not null default false,
  status          public.coupon_status not null default 'Active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint coupons_percentage_max check (discount_type <> 'Percentage' or discount_value <= 100),
  constraint coupons_dates check (valid_from is null or valid_till is null or valid_from <= valid_till)
);

-- -----------------------------------------------------------------------------
-- Orders (website + admin), lines, shipments, emails, status history
-- -----------------------------------------------------------------------------
create sequence public.order_number_seq start 98217;

create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  order_number      text not null unique default ('ORD-' || nextval('public.order_number_seq')),
  customer_id       uuid references public.customers(id) on delete set null,
  -- Snapshot of who ordered and where it goes, as at checkout.
  customer_name     text not null,
  email             text not null default '',
  phone             text not null default '',
  shipping_address  text not null default '',
  city              text not null default '',
  state             text not null default '',
  postal_code       text not null default '',
  placed_at         timestamptz not null default now(),
  subtotal          numeric(12,2) not null default 0 check (subtotal >= 0),
  discount          numeric(12,2) not null default 0 check (discount >= 0),
  delivery_fee      numeric(12,2) not null default 0 check (delivery_fee >= 0),
  total             numeric(12,2) not null default 0 check (total >= 0),
  coupon_code       text not null default '',
  items_count       integer not null default 0 check (items_count >= 0),
  payment_method    public.payment_method not null,
  payment_status    public.payment_status not null default 'Pending',
  payment_id        text,           -- Razorpay payment id (pay_…)
  payment_detail    text,           -- 'UPI · name@okaxis' / 'Visa •••• 1111'
  gateway_order_id  text,           -- Razorpay order id (order_…)
  order_status      public.order_status not null default 'Pending',
  source            public.order_source not null default 'Website',
  notes             text not null default '',
  created_by        uuid references public.profiles(id) on delete set null,
  cancelled_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint orders_total_math check (total = subtotal - discount + delivery_fee)
);
create index orders_customer_idx on public.orders (customer_id);
create index orders_placed_at_idx on public.orders (placed_at desc);
create index orders_status_idx on public.orders (order_status);
create index orders_email_idx on public.orders (lower(email));
create unique index orders_payment_id_key on public.orders (payment_id) where payment_id is not null;

create table public.order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,
  sku         text not null default '',
  size        text not null default 'Standard',
  color       text not null default 'Standard',
  qty         integer not null check (qty > 0),
  price       numeric(12,2) not null check (price >= 0),
  line_total  numeric(12,2) generated always as (price * qty) stored,
  image_url   text not null default '',
  created_at  timestamptz not null default now()
);
create index order_items_order_idx on public.order_items (order_id);
create index order_items_product_idx on public.order_items (product_id);

-- Shiprocket shipments. A cancelled shipment can be replaced, so one order may have several,
-- but only one that is not cancelled.
create table public.shipments (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.orders(id) on delete cascade,
  courier         text not null default '',
  awb             text not null default '',
  pickup_location text not null default '',
  weight_kg       numeric(8,3) check (weight_kg is null or weight_kg > 0),
  length_cm       numeric(8,2),
  width_cm        numeric(8,2),
  height_cm       numeric(8,2),
  status          public.shipment_status not null default 'Created',
  sr_order_id     bigint,           -- Shiprocket ids and raw status text ('PICKUP SCHEDULED')
  sr_shipment_id  bigint,
  remote_status   text,
  delivery_state  text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index shipments_one_active_per_order on public.shipments (order_id) where status <> 'Cancelled';
create index shipments_awb_idx on public.shipments (awb) where awb <> '';

create table public.order_emails (
  id        uuid primary key default gen_random_uuid(),
  order_id  uuid not null references public.orders(id) on delete cascade,
  kind      public.order_email_kind not null,
  sent_at   timestamptz not null default now()
);
create index order_emails_order_idx on public.order_emails (order_id);

create table public.order_status_history (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  from_status  public.order_status,
  to_status    public.order_status not null,
  changed_by   uuid references public.profiles(id) on delete set null,
  changed_at   timestamptz not null default now()
);
create index order_status_history_order_idx on public.order_status_history (order_id, changed_at);

-- -----------------------------------------------------------------------------
-- POS (in-store register) bills, lines and the exact variant stock each line took
-- -----------------------------------------------------------------------------
create sequence public.pos_receipt_seq start 8092;

create table public.pos_transactions (
  id               uuid primary key default gen_random_uuid(),
  receipt_no       text not null unique
                   default ('REC-' || extract(year from now())::int || '-' || nextval('public.pos_receipt_seq')),
  cashier_id       uuid references public.profiles(id) on delete set null,
  cashier_name     text not null default '',
  customer_id      uuid references public.customers(id) on delete set null,
  customer_name    text not null default 'Walk-in Customer',
  customer_phone   text not null default '',
  items_count      integer not null default 0 check (items_count >= 0),
  subtotal         numeric(12,2) not null default 0 check (subtotal >= 0),
  discount         numeric(12,2) not null default 0 check (discount >= 0),
  total            numeric(12,2) not null default 0 check (total >= 0),
  payment_method   public.pos_payment_method not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index pos_transactions_created_idx on public.pos_transactions (created_at desc);

create table public.pos_transaction_items (
  id              uuid primary key default gen_random_uuid(),
  transaction_id  uuid not null references public.pos_transactions(id) on delete cascade,
  product_id      uuid references public.products(id) on delete set null,
  name            text not null,
  qty             integer not null check (qty > 0),
  price           numeric(12,2) not null check (price >= 0),
  line_total      numeric(12,2) generated always as (price * qty) stored,
  -- [{ "size": "7", "color": "Rose Gold", "qty": 1 }] — where the stock came from, so a return goes back there.
  stock_lines     jsonb not null default '[]'::jsonb check (jsonb_typeof(stock_lines) = 'array'),
  returned_at     timestamptz,
  created_at      timestamptz not null default now()
);
create index pos_transaction_items_tx_idx on public.pos_transaction_items (transaction_id);
create index pos_transaction_items_product_idx on public.pos_transaction_items (product_id);

-- -----------------------------------------------------------------------------
-- Storefront content: hero banners, Instagram feed, product videos
-- -----------------------------------------------------------------------------
create table public.hero_banners (
  id                uuid primary key default gen_random_uuid(),
  title             text not null default '',
  subtitle          text not null default '',
  image_url         text not null,
  mobile_image_url  text not null default '',
  cta_text          text not null default '',
  cta_link          text not null default '',
  is_active         boolean not null default true,
  text_align        public.text_align not null default 'left',
  text_color        text not null default '#ffffff' check (text_color ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table public.instagram_posts (
  id          uuid primary key default gen_random_uuid(),
  post_url    text not null,
  image_url   text not null,
  caption     text not null default '',
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.videos (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  product_id    uuid references public.products(id) on delete set null,
  product_name  text not null default '',
  duration      text not null default '',          -- 'mm:ss'
  views         integer not null default 0 check (views >= 0),
  thumbnail     text not null default '',
  video_url     text not null,                     -- file URL or YouTube link
  is_active     boolean not null default true,
  date_added    date not null default current_date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Shopper state (for when a website is attached): bag and wishlist
-- -----------------------------------------------------------------------------
create table public.cart_items (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  size         text not null default 'Standard',
  color        text not null default 'Standard',
  qty          integer not null check (qty > 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (customer_id, product_id, size, color)
);

create table public.wishlist_items (
  customer_id  uuid not null references public.customers(id) on delete cascade,
  product_id   uuid not null references public.products(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (customer_id, product_id)
);

-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'themes','store_settings','profiles','customers','customer_addresses','categories','sub_categories',
    'sub_sub_categories','sizes','colors','tags','products','product_variants','coupons','orders','shipments',
    'pos_transactions','hero_banners','instagram_posts','videos','cart_items'
  ] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
                   t || '_set_updated_at', t);
  end loop;
end $$;
