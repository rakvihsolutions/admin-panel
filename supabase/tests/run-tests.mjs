// Runs the whole Supabase setup on a throwaway local Postgres 17 (PGlite) and checks that it works:
// schema, demo data, stock/coupon/order/POS rules, and who-can-see-what (RLS).
//   cd supabase/tests && npm install && npm test
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'node:fs';
import { buildFullSetup, fullSetupParts } from './build-full-setup.mjs';

const read = (f) => fs.readFileSync(new URL(f, import.meta.url), 'utf8');
let passed = 0;
let failed = 0;

async function freshDb({ combined = false } = {}) {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(read('./supabase-stub.sql'));
  if (combined) await db.exec(buildFullSetup());
  else for (const [, sql] of fullSetupParts()) await db.exec(sql);
  return db;
}

async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    console.log(`  ✗ ${name}\n      ${e.message}`);
  }
}

function eq(actual, expected, what = '') {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what} expected ${b}, got ${a}`);
}

async function throws(promise, match) {
  try {
    await promise;
  } catch (e) {
    if (match && !String(e.message).match(match)) throw new Error(`wrong error: ${e.message}`);
    return;
  }
  throw new Error(`expected an error${match ? ` matching ${match}` : ''}`);
}

// Act as a Supabase API caller: 'anon', 'authenticated' (with user id) or 'service_role'. null = SQL editor.
async function as(db, who, fn) {
  await db.exec('reset role');
  if (who) {
    const claims = JSON.stringify(who.sub ? { role: who.role, sub: who.sub } : { role: who.role });
    await db.query(`select set_config('request.jwt.claims', $1, false), set_config('request.jwt.claim.sub', $2, false)`, [claims, who.sub ?? '']);
    await db.exec(`set role ${who.role}`);
  }
  try {
    return await fn();
  } finally {
    await db.exec(`reset role; select set_config('request.jwt.claims', '', false), set_config('request.jwt.claim.sub', '', false);`);
  }
}

const one = async (db, sql, params) => (await db.query(sql, params)).rows[0];
const all = async (db, sql, params) => (await db.query(sql, params)).rows;
const num = (v) => Number(v);

async function createUser(db, email, fullName) {
  const id = crypto.randomUUID();
  await db.query(`insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, $3)`, [id, email, { full_name: fullName }]);
  return id;
}

// =============================================================================
console.log('\nSetup');
const db = await freshDb();
const ANON = { role: 'anon' };
const SERVICE = { role: 'service_role' };
const adminId = (await one(db, `select id from public.profiles where email = 'demo.admin@example.com'`)).id;
const shopperId = (await one(db, `select id from public.profiles where email = 'demo.shopper@example.com'`)).id;
const ADMIN = { role: 'authenticated', sub: adminId };
const SHOPPER = { role: 'authenticated', sub: shopperId };

await test('all migrations, seed and demo logins apply on a fresh database', async () => {});

await test('full_setup.sql (one-paste version) also applies cleanly', async () => {
  const db2 = await freshDb({ combined: true });
  eq(num((await one(db2, 'select count(*) from public.products')).count), 16, 'products');
  await db2.close();
});

// =============================================================================
console.log('\nDemo data matches the admin panel');
await test('row counts', async () => {
  const r = await one(db, `select
    (select count(*) from public.products) products, (select count(*) from public.categories) categories,
    (select count(*) from public.sub_categories) subs, (select count(*) from public.sub_sub_categories) subsubs,
    (select count(*) from public.sizes) sizes, (select count(*) from public.colors) colors, (select count(*) from public.tags) tags,
    (select count(*) from public.coupons) coupons, (select count(*) from public.customers) customers,
    (select count(*) from public.orders) orders, (select count(*) from public.order_items) order_items,
    (select count(*) from public.shipments) shipments, (select count(*) from public.pos_transactions) pos,
    (select count(*) from public.hero_banners) banners, (select count(*) from public.instagram_posts) insta,
    (select count(*) from public.videos) videos, (select count(*) from public.themes) themes`);
  eq(Object.fromEntries(Object.entries(r).map(([k, v]) => [k, num(v)])), {
    products: 16, categories: 5, subs: 10, subsubs: 4, sizes: 6, colors: 8, tags: 6, coupons: 3,
    customers: 8, orders: 6, order_items: 7, shipments: 2, pos: 3, banners: 4, insta: 6, videos: 3, themes: 8,
  });
});

await test('product stock equals the sum of its size × colour cells, with the right status', async () => {
  const data = JSON.parse(fs.readFileSync(new URL('./fixtures/app-products.json', import.meta.url), 'utf8'));
  const rows = await all(db, `select sku, stock, stock_status::text from public.products`);
  for (const p of data) {
    const row = rows.find((r) => r.sku === p.sku);
    if (!row) throw new Error(`missing ${p.sku}`);
    eq([row.stock, row.stock_status], [p.stock, p.status], p.sku);
  }
  const bad = await one(db, `select count(*) from public.products p
    where p.stock <> (select coalesce(sum(quantity), 0) from public.product_variants v where v.product_id = p.id)`);
  eq(num(bad.count), 0, 'mismatched products');
});

await test('order totals and links are consistent', async () => {
  const r = await one(db, `select count(*) filter (where customer_id is null) unlinked,
    count(*) filter (where subtotal <> (select sum(line_total) from public.order_items i where i.order_id = o.id)) bad_subtotal
    from public.orders o`);
  eq([num(r.unlinked), num(r.bad_subtotal)], [0, 0]);
  eq((await one(db, `select total from public.orders where order_number = 'ORD-98216'`)).total, '7499.00', 'ORD-98216 total');
});

await test('demo admin is super admin; demo shopper is a customer', async () => {
  eq((await one(db, `select role from public.profiles where id = $1`, [adminId])).role, 'super_admin');
  eq((await one(db, `select count(*) from public.customers where profile_id = $1`, [shopperId])).count, 1, 'shopper customer');
  eq((await one(db, `select count(*) from public.customers where profile_id = $1`, [adminId])).count, 0, 'admin customer');
  const ok = await one(db, `select encrypted_password = extensions.crypt('shop123', encrypted_password) ok from auth.users where id = $1`, [adminId]);
  eq(ok.ok, true, 'password hash');
});

// =============================================================================
console.log('\nWebsite visitor (anon)');
await test('sees the live catalog, active categories, banners, themes and settings', async () => {
  await as(db, ANON, async () => {
    eq(num((await one(db, 'select count(*) from public.products')).count), 16, 'products');
    eq(num((await one(db, 'select count(*) from public.product_catalog')).count), 16, 'catalog view');
    eq(num((await one(db, 'select count(*) from public.categories')).count), 5, 'categories');
    eq(num((await one(db, 'select count(*) from public.hero_banners')).count), 3, 'active banners only');
    eq((await one(db, 'select name from public.store_settings')).name, 'Demo Jewellery');
  });
});

await test('hidden products disappear from the website but stay in admin', async () => {
  await db.exec(`update public.products set is_live = false where sku = 'MEH-ER-10'`);
  await as(db, ANON, async () => eq(num((await one(db, 'select count(*) from public.products')).count), 15));
  await as(db, ADMIN, async () => eq(num((await one(db, 'select count(*) from public.products')).count), 16));
  await db.exec(`update public.products set is_live = true where sku = 'MEH-ER-10'`);
});

await test('cannot see orders, customers, POS, profiles or reports', async () => {
  await as(db, ANON, async () => {
    for (const t of ['orders', 'order_items', 'customers', 'pos_transactions', 'profiles', 'shipments']) {
      eq(num((await one(db, `select count(*) from public.${t}`)).count), 0, t);
    }
    await throws(db.query('select * from public.dashboard_summary'), /permission denied/);
  });
});

await test('only sees live header coupons', async () => {
  await as(db, ANON, async () => {
    eq((await all(db, 'select code from public.coupons order by code')).map((r) => r.code), ['MEGAFEST20', 'WELCOME500']);
  });
});

await test('cannot write to the catalog', async () => {
  await as(db, ANON, async () => {
    await throws(db.query(`insert into public.tags (name) values ('Hacked')`), /row-level security/);
    const r = await db.query(`update public.products set price = 1`);
    eq(r.affectedRows, 0, 'updated rows');
    await throws(db.query(`select public.make_super_admin('demo.shopper@example.com')`), /permission denied/);
  });
});

// =============================================================================
console.log('\nCoupons & totals (same maths as calculateTotals)');
await test('WELCOME500 on ₹3,000 → ₹500 off + ₹149 delivery', async () => {
  const r = await as(db, ANON, () => one(db, `select public.validate_coupon('welcome500', 3000) v`));
  eq(r.v, { code: 'WELCOME500', total: 2649, valid: true, delivery: 149, discount: 500 });
});
await test('MEGAFEST20 on ₹20,000 → 20% capped at ₹3,000, free delivery', async () => {
  const r = await as(db, ANON, () => one(db, `select public.validate_coupon('MEGAFEST20', 20000) v`));
  eq([r.v.discount, r.v.delivery, r.v.total], [3000, 0, 17000]);
});
await test('expired / unknown / below-minimum codes give the app\'s messages', async () => {
  eq((await one(db, `select public.validate_coupon('EARLYBIRD', 5000) v`)).v.message, 'EARLYBIRD has expired.');
  eq((await one(db, `select public.validate_coupon('NOPE', 5000) v`)).v.message, 'That code is not valid.');
  eq((await one(db, `select public.validate_coupon('WELCOME500', 1000) v`)).v.message, 'WELCOME500 needs a bag of at least ₹2,500.');
});

// =============================================================================
console.log('\nCheckout (place_order)');
const ringId = (await one(db, `select id from public.products where sku = 'GUL-RG-03'`)).id;
const bangleId = (await one(db, `select id from public.products where sku = 'IRA-BG-04'`)).id;
const cell = async (id, size, color) => (await one(db, `select quantity from public.product_variants where product_id = $1 and size = $2 and color = $3`, [id, size, color])).quantity;
const stockOf = async (id) => (await one(db, `select stock from public.products where id = $1`, [id])).stock;

let codOrder;
await test('guest COD order: takes exact size/colour stock, applies coupon, adds customer, numbers ORD-98217', async () => {
  const before = await cell(ringId, '7', 'Rose Gold');
  const coupon = num((await one(db, `select usage_count from public.coupons where code = 'WELCOME500'`)).usage_count);
  codOrder = await as(db, ANON, () => one(db, `select * from public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '7', color: 'Rose Gold', qty: 1 }],
    coupon_code: 'WELCOME500', payment_method: 'Cash on Delivery',
    address: { name: 'New Buyer', phone: '+91 90000 00000', email: 'New.Buyer@Example.com', line: '1 MG Road', city: 'Bengaluru', state: 'Karnataka', pin: '560001' },
  }]));
  eq([codOrder.order_number, codOrder.subtotal, codOrder.discount, codOrder.delivery_fee, codOrder.total, codOrder.payment_status],
     ['ORD-98217', '11999.00', '500.00', '0.00', '11499.00', 'Pending']);
  eq(await cell(ringId, '7', 'Rose Gold'), before - 1, 'variant stock');
  eq(num((await one(db, `select usage_count from public.coupons where code = 'WELCOME500'`)).usage_count), coupon + 1, 'coupon usage');
  eq((await one(db, `select email from public.customers where id = $1`, [codOrder.customer_id])).email, 'new.buyer@example.com');
});

await test('prices come from the database, not the browser', async () => {
  const o = await as(db, ANON, () => one(db, `select * from public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '6', color: 'Rose Gold', qty: 1, price: 1 }],
    payment_method: 'Cash on Delivery', address: { name: 'Cheeky', email: 'cheeky@example.com' },
  }]));
  eq(o.subtotal, '11999.00');
});

await test('out-of-stock variant is refused and nothing changes', async () => {
  const ordersBefore = num((await one(db, 'select count(*) from public.orders')).count);
  await throws(as(db, ANON, () => db.query(`select public.place_order($1)`, [{
    lines: [{ product_id: bangleId, size: '2.6', color: 'Yellow Gold', qty: 1 }],
    payment_method: 'Cash on Delivery', address: { name: 'X', email: 'x@example.com' },
  }])), /Only 0 of Ira Textured Gold Bangles \(2\.6, Yellow Gold\) left/);
  eq(num((await one(db, 'select count(*) from public.orders')).count), ordersBefore);
});

await test('prepaid order needs a Razorpay receipt; a browser can never mark it Paid', async () => {
  await throws(as(db, ANON, () => db.query(`select public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '8', color: 'Rose Gold', qty: 1 }], payment_method: 'Razorpay', address: { name: 'P', email: 'p@example.com' },
  }])), /not been verified/);
  const fake = await as(db, ANON, () => one(db, `select * from public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '8', color: 'Rose Gold', qty: 1 }], payment_method: 'Razorpay',
    receipt: { payment_id: 'pay_FAKE', gateway_order_id: 'order_FAKE' }, address: { name: 'P', email: 'p@example.com' },
  }]));
  eq(fake.payment_status, 'Pending', 'anon');
  const real = await as(db, SERVICE, () => one(db, `select * from public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '8', color: 'Yellow Gold', qty: 1 }], payment_method: 'Razorpay',
    receipt: { payment_id: 'pay_REAL1', gateway_order_id: 'order_REAL1', detail: 'UPI · demo@okaxis' }, address: { name: 'P', email: 'p@example.com' },
  }]));
  eq(real.payment_status, 'Paid', 'server');
});

await test('signed-in shopper order links to their account and only they see it', async () => {
  const o = await as(db, SHOPPER, () => one(db, `select * from public.place_order($1)`, [{
    lines: [{ product_id: ringId, size: '6', color: 'Yellow Gold', qty: 1 }], payment_method: 'Cash on Delivery',
    address: { name: 'Demo Shopper', email: 'demo.shopper@example.com', line: 'x', city: 'y', state: 'z', pin: '1' },
  }]));
  const mine = await as(db, SHOPPER, () => all(db, 'select order_number from public.orders'));
  eq(mine.map((r) => r.order_number), [o.order_number]);
  const items = await as(db, SHOPPER, () => all(db, 'select name from public.order_items'));
  eq(items.length, 1, 'own items');
});

// =============================================================================
console.log('\nOrder management');
await test('cancelling returns stock, logs history, cancels shipment; cancelled orders stay closed', async () => {
  const before = await cell(ringId, '7', 'Rose Gold');
  await as(db, ADMIN, () => db.query(`update public.orders set order_status = 'Processing' where id = $1`, [codOrder.id]));
  await as(db, ADMIN, () => db.query(`insert into public.shipments (order_id, courier, awb, status) values ($1, 'Delhivery', '123', 'Created')`, [codOrder.id]));
  await as(db, ADMIN, () => db.query(`update public.orders set order_status = 'Cancelled' where id = $1`, [codOrder.id]));
  eq(await cell(ringId, '7', 'Rose Gold'), before + 1, 'restocked');
  eq((await all(db, `select to_status from public.order_status_history where order_id = $1 order by changed_at, to_status desc`, [codOrder.id])).map((r) => r.to_status),
     ['Pending', 'Processing', 'Cancelled']);
  eq((await one(db, `select status from public.shipments where order_id = $1`, [codOrder.id])).status, 'Cancelled');
  await throws(as(db, ADMIN, () => db.query(`update public.orders set order_status = 'Pending' where id = $1`, [codOrder.id])), /Cancelled orders are closed/);
});

await test('dashboard numbers ignore cancelled orders', async () => {
  const s = await as(db, ADMIN, () => one(db, 'select * from public.dashboard_summary'));
  const expect = await one(db, `select sum(total) t from public.orders where order_status <> 'Cancelled'`);
  eq(s.website_revenue, expect.t);
  eq(num(s.cancelled_orders), 1);
  const daily = await as(db, ADMIN, () => all(db, `select channel from public.sales_daily group by channel order by channel`));
  eq(daily.map((r) => r.channel), ['POS', 'Website']);
});

// =============================================================================
console.log('\nPOS register');
const pearlId = (await one(db, `select id from public.products where sku = 'MEH-NK-01'`)).id;
let posTx;
await test('POS sale takes stock from available cells and records where from', async () => {
  // 30 Pearl + 15 Yellow Gold → selling 32 must take 30 + 2
  const total = await stockOf(pearlId);
  posTx = await as(db, ADMIN, () => one(db, `select * from public.pos_create_sale($1)`, [{
    items: [{ product_id: pearlId, qty: 32 }], customer_name: 'Walk-in Customer', payment_method: 'UPI',
  }]));
  eq(posTx.receipt_no, 'REC-2026-8092');
  eq([posTx.items_count, posTx.total], [32, '799968.00']);
  eq(await stockOf(pearlId), total - 32);
  const lines = (await one(db, `select stock_lines from public.pos_transaction_items where transaction_id = $1`, [posTx.id])).stock_lines;
  eq(lines.reduce((s, l) => s + l.qty, 0), 32, 'stock lines');
});

await test('POS refuses selling more than is in stock', async () => {
  await throws(as(db, ADMIN, () => db.query(`select public.pos_create_sale($1)`, [{
    items: [{ product_id: bangleId, qty: 1 }], payment_method: 'Cash',
  }])), /Only 0 of Ira Textured Gold Bangles left/);
});

await test('POS return puts stock back exactly once', async () => {
  const before = await stockOf(pearlId);
  const item = (await one(db, `select id from public.pos_transaction_items where transaction_id = $1`, [posTx.id])).id;
  const n = await as(db, ADMIN, () => one(db, `select public.pos_return_items($1, $2) n`, [posTx.id, [item]]));
  eq(n.n, 32);
  eq(await stockOf(pearlId), before + 32);
  const again = await as(db, ADMIN, () => one(db, `select public.pos_return_items($1, $2) n`, [posTx.id, [item]]));
  eq(again.n, 0, 'second return');
});

await test('old seeded POS bill returns to the product\'s variant (no phantom "Standard" cell)', async () => {
  const tx = await one(db, `select t.id, i.id item from public.pos_transactions t join public.pos_transaction_items i on i.transaction_id = t.id
                            where t.receipt_no = 'REC-2026-8090'`);
  await as(db, ADMIN, () => db.query(`select public.pos_return_items($1, $2)`, [tx.id, [tx.item]]));
  eq(num((await one(db, `select count(*) from public.product_variants where size = 'Standard' and color = 'Standard'`)).count), 0);
});

// =============================================================================
console.log('\nCatalog rules');
await test('saving the size × colour grid rebuilds variants and totals', async () => {
  const total = await as(db, ADMIN, () => one(db, `select public.set_product_variants($1, $2, $3, $4) t`,
    [bangleId, ['2.4', '2.6'], ['Yellow Gold', 'Rose Gold'], { '2.4': { 'Yellow Gold': 5, 'Rose Gold': 3 }, '2.6': { 'Yellow Gold': 4 } }]));
  eq(total.t, 12);
  eq(num((await one(db, `select count(*) from public.product_variants where product_id = $1`, [bangleId])).count), 4, 'cells');
  eq((await one(db, `select stock_status from public.products where id = $1`, [bangleId])).stock_status, 'In Stock');
});

await test('sub category must belong to the product\'s category', async () => {
  await throws(as(db, ADMIN, () => db.query(`update public.products set sub_category_id = (select id from public.sub_categories where name = 'Bangles')
    where sku = 'MEH-NK-01'`)), /does not belong/);
});

await test('slugs, coupon codes and emails are normalised', async () => {
  const c = await as(db, ADMIN, () => one(db, `insert into public.categories (name) values ('Anklets & Toe Rings') returning slug`));
  eq(c.slug, 'anklets-toe-rings');
  const k = await as(db, ADMIN, () => one(db, `insert into public.coupons (code, discount_type, discount_value) values (' diwali10 ', 'Percentage', 10) returning code`));
  eq(k.code, 'DIWALI10');
  await throws(as(db, ADMIN, () => db.query(`insert into public.coupons (code, discount_type, discount_value) values ('BAD', 'Percentage', 150)`)), /coupons_percentage_max/);
});

// =============================================================================
console.log('\nStaff (sub admins) & security');
const staffId = await createUser(db, 'cashier@example.com', 'Store Cashier');
const STAFF = { role: 'authenticated', sub: staffId };

await test('super admin grants modules; "settings" can never be given to staff', async () => {
  const p = await as(db, ADMIN, () => one(db, `select * from public.set_staff_access($1, 'sub_admin', $2)`, [staffId, '{orders,pos-terminal,settings}']));
  eq(p.permissions, '{orders,pos-terminal}');
});

await test('staff sees only their modules', async () => {
  await as(db, STAFF, async () => {
    if (num((await one(db, 'select count(*) from public.orders')).count) < 6) throw new Error('cannot read orders');
    eq((await db.query(`update public.products set price = 1 where sku = 'MEH-NK-01'`)).affectedRows, 0, 'product edit');
    await throws(db.query(`insert into public.hero_banners (image_url) values ('x')`), /row-level security/);
    eq((await db.query(`update public.store_settings set razorpay_key_id = 'rzp_live_x'`)).affectedRows, 0, 'settings edit');
    const sale = await one(db, `select * from public.pos_create_sale($1)`, [{ items: [{ product_id: ringId, qty: 1 }], payment_method: 'Cash' }]);
    eq(sale.cashier_name, 'Store Cashier', 'cashier name');
  });
});

await test('staff and shoppers cannot promote themselves', async () => {
  await throws(as(db, STAFF, () => db.query(`update public.profiles set role = 'super_admin' where id = $1`, [staffId])), /Only a super admin/);
  await throws(as(db, SHOPPER, () => db.query(`update public.profiles set permissions = '{orders}' where id = $1`, [shopperId])), /Only a super admin/);
  const ok = await as(db, SHOPPER, () => db.query(`update public.profiles set full_name = 'Renamed' where id = $1`, [shopperId]));
  eq(ok.affectedRows, 1, 'own name change');
});

await test('deactivated staff lose access immediately', async () => {
  await as(db, ADMIN, () => db.query(`update public.profiles set is_active = false where id = $1`, [staffId]));
  await as(db, STAFF, async () => eq(num((await one(db, 'select count(*) from public.orders')).count), 0));
});

await test('the last super admin cannot be demoted', async () => {
  await throws(as(db, ADMIN, () => db.query(`update public.profiles set role = 'sub_admin' where id = $1`, [adminId])), /last super admin/);
});

await test('store settings: payment keys only for super admin', async () => {
  await as(db, ADMIN, () => db.query(`update public.store_settings set razorpay_key_id = 'rzp_test_123', name = 'Demo Jewellery'`));
  eq((await one(db, 'select razorpay_key_id from public.store_settings')).razorpay_key_id, 'rzp_test_123');
});

await test('storage: visitors read, only admins upload', async () => {
  await throws(as(db, ANON, () => db.query(`insert into storage.objects (bucket_id, name) values ('product-images', 'x.jpg')`)), /row-level security/);
  await as(db, ADMIN, () => db.query(`insert into storage.objects (bucket_id, name) values ('product-images', 'x.jpg')`));
  await as(db, ANON, async () => eq(num((await one(db, `select count(*) from storage.objects`)).count), 1));
  eq(num((await one(db, `select count(*) from storage.buckets`)).count), 4, 'buckets');
});

await test('video views can be counted by visitors', async () => {
  const v = (await one(db, `select id, views from public.videos order by date_added limit 1`));
  const r = await as(db, ANON, () => one(db, `select public.record_video_view($1) n`, [v.id]));
  eq(r.n, v.views + 1);
});

// =============================================================================
console.log('\nHand-over to a real client');
await test('clear_demo_data.sql empties the store but keeps logins, themes and settings row', async () => {
  await db.exec(read('../clear_demo_data.sql'));
  const r = await one(db, `select (select count(*) from public.products) p, (select count(*) from public.orders) o,
    (select count(*) from public.customers) c, (select count(*) from public.profiles) pr, (select count(*) from public.themes) t,
    (select name from public.store_settings) s`);
  eq([num(r.p), num(r.o), num(r.c), num(r.pr), num(r.t), r.s], [0, 0, 1, 3, 8, 'My Store']);
});

await test('first real order after clearing is ORD-1001, and the demo can be re-seeded', async () => {
  await db.exec(`insert into public.products (name, sku, price) values ('Test', 'T-1', 100)`);
  const id = (await one(db, `select id from public.products where sku = 'T-1'`)).id;
  await db.query(`select public.set_product_variants($1, '{}', '{}', '{"Standard":{"Standard":5}}')`, [id]);
  const o = await one(db, `select order_number from public.place_order($1)`, [{ lines: [{ product_id: id, qty: 1 }], payment_method: 'Cash on Delivery', address: { name: 'A', email: 'a@example.com' } }]);
  eq(o.order_number, 'ORD-1001');
  await db.exec(read('../clear_demo_data.sql'));
  await db.exec(read('../seed.sql'));
  eq(num((await one(db, 'select count(*) from public.products')).count), 16);
});

await db.close();
console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed ? 1 : 0);
