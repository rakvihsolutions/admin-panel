# Supabase database for the admin panel

Everything the admin panel needs in Supabase: tables, business rules, security, storage buckets, reports and the same demo data the panel ships with.

## Quick start: new client project

1. Create a new project at supabase.com.
2. Open **SQL Editor**, paste all of [`full_setup.sql`](full_setup.sql) and click **Run**.
   The store starts **empty**: no products, categories, orders or customers, and order numbers start at `ORD-1001`.
3. Sign in with the one-click demo logins: admin `demo.admin@example.com` / `shop123`, shopper `demo.shopper@example.com` / `demo1234`.
4. When the client goes live:
   - create the owner in **Authentication → Add user**;
   - run `select public.make_super_admin('owner@client.com');`;
   - remove the demo logins with `delete from auth.users where email in ('demo.admin@example.com', 'demo.shopper@example.com');`.

To show a client a store full of sample jewellery, run [`seed.sql`](seed.sql) (optional). [`clear_demo_data.sql`](clear_demo_data.sql) removes it again.
5. In **Project Settings → API**, copy the URL and keys into the app's `.env.local`:
   ```
   NEXT_PUBLIC_SUPABASE_URL=...
   NEXT_PUBLIC_SUPABASE_ANON_KEY=...
   SUPABASE_SERVICE_ROLE_KEY=...      # server only, never in the browser
   ```

If you use the Supabase CLI instead, note that `supabase db reset` runs `migrations/` and then `seed.sql`, which loads the sample data. Delete or rename `seed.sql` if you want an empty store, and run `demo_logins.sql` separately.

## What's in this folder

| File | What it does |
|---|---|
| `migrations/…100_types.sql` | Enums. Their values match the strings the app already uses (`'In Stock'`, `'Cash on Delivery'`, …). |
| `migrations/…200_tables.sql` | 27 tables (listed below). |
| `migrations/…300_functions.sql` | Business rules: stock, coupons, checkout, POS, cancellations, staff. |
| `migrations/…400_security.sql` | Row Level Security on every table. |
| `migrations/…500_storage.sql` | Storage buckets and who can upload to them. |
| `migrations/…600_views.sql` | Views for the dashboard, reports, customers, inventory and catalog. |
| `migrations/…700_defaults.sql` | The `store_settings` row and the 8 built-in themes. These are app defaults, not demo data. |
| `demo_logins.sql` | One-click demo admin and shopper accounts. |
| `full_setup.sql` | All migrations plus the demo logins in one file, giving an empty store. It is generated, so don't edit it by hand. |
| `seed.sql` | **Optional** sample data from `app/adminpanel/demo-data.ts`. Not included in `full_setup.sql`. |
| `clear_demo_data.sql` | Removes the sample data again. Logins, themes and settings stay. |
| `tests/` | Automated tests that build the whole database and check it works. |

### Tables

- **Settings:** `store_settings` (one row: store details, delivery fee rules, Razorpay public key, COD on/off, active theme), `themes`
- **People:** `profiles` (one per login, with role and sub-admin permissions), `customers`, `customer_addresses`
- **Catalog:** `categories` → `sub_categories` → `sub_sub_categories`, `sizes`, `colors`, `tags`, `products`, `product_tags`, `product_variants` (stock per size × colour)
- **Sales:** `coupons`, `orders`, `order_items`, `shipments` (Shiprocket), `order_emails`, `order_status_history`
- **POS:** `pos_transactions`, `pos_transaction_items`
- **Storefront:** `hero_banners`, `instagram_posts`, `videos`
- **Shopper:** `cart_items`, `wishlist_items` (ready for when a website is added)

## Rules the database enforces

- **Stock:** `products.stock` and `stock_status` are always the sum of the variant cells. Stock is never edited directly.
- **Checkout:** use `place_order(jsonb)`. It locks stock, refuses out-of-stock lines and takes prices from the database (never the browser). It also applies the coupon and the free-delivery rule, adds or updates the customer and counts the coupon as used. If any line fails, nothing is saved.
- **Payments:** an order is only marked **Paid** when the server places it (with the service-role key, after checking the Razorpay signature) or an admin does. If a browser calls `place_order` directly, the order stays `Pending`.
- **Cancelling** an order puts its stock back, cancels its shipment and logs the change. A cancelled order cannot be reopened.
- **POS:** `pos_create_sale` takes stock from whichever cells still have it and records which ones. `pos_return_items` puts it back in those exact cells, and each line can only be returned once.
- **Staff:** a super admin can do everything. A sub admin can only use the modules ticked for them. Nobody can give themselves more access, Admin Security (`settings`) is super-admin only, and the last super admin cannot be removed.

### Functions the app calls (`supabase.rpc(...)`)

| Function | Used by |
|---|---|
| `place_order(p_order)` | Website checkout, admin "new order" |
| `validate_coupon(code, subtotal)` | Checkout "Apply" button (safe for visitors) |
| `calculate_totals(subtotal, code)` | Bag and checkout totals |
| `set_product_variants(id, sizes, colors, stock)` | Add/Edit product, Inventory (saves the whole size × colour grid) |
| `refresh_order_totals(order_id)` | After an admin edits order lines |
| `pos_create_sale(p_sale)` / `pos_return_items(tx_id, item_ids)` | POS register and POS history |
| `set_staff_access(user_id, role, permissions)` | Admin Security → staff logins |
| `activate_theme(theme_id)` | Theme Setup |
| `record_video_view(video_id)` | Storefront video plays |
| `make_super_admin(email)` | SQL Editor only, to set up the first owner |

The input format for each function is documented in a comment above it in `migrations/…300_functions.sql`.

### Views

`dashboard_summary`, `sales_daily`, `top_products`, `customer_stats`, `inventory_view`, `coupon_overview` and `product_catalog`. Every view applies the caller's access rules, so a sub admin without access gets no rows.

### Storage buckets

All four buckets are publicly readable. Only admins with the related module can upload to them:

- `product-images`: product and category photos
- `banners`: hero banners and Instagram images
- `videos`: product videos and thumbnails
- `store-assets`: logo, icons and theme images

## Testing

```bash
cd supabase/tests
npm install
npm test       # builds the whole database on a local Postgres 17 and runs 38 checks
npm run build  # rebuilds full_setup.sql after you edit a migration
```

The tests run on PGlite (Postgres compiled to WebAssembly), so they need no Docker and no Supabase account. `tests/supabase-stub.sql` stands in for the parts Supabase provides itself (`auth`, `storage`, roles).

## Notes

- The Razorpay **secret** never goes in the database. Keep it in the server's environment variables. `store_settings.razorpay_key_id` only holds the public key.
- The admin panel itself still saves to the browser (localStorage). Connecting each screen to these tables is the next step.
- To generate TypeScript types once the project exists, run `npx supabase gen types typescript --project-id <id> > types/supabase.ts`.
- Times are stored in UTC (`timestamptz`). Reports group days by India time (`Asia/Kolkata`).
