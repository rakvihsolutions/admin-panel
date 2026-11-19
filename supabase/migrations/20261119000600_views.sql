-- =============================================================================
-- 06 · Reporting views (Dashboard, Reports, Customers, Inventory)
-- security_invoker = on → each view respects the caller's RLS, so a visitor or
-- a sub admin without access simply gets no rows.
-- Cancelled orders and returned POS lines never count as revenue.
-- =============================================================================

-- One row of headline numbers for the dashboard cards.
create view public.dashboard_summary with (security_invoker = on) as
select
  (select coalesce(sum(total), 0) from public.orders where order_status <> 'Cancelled')                      as website_revenue,
  (select coalesce(sum(i.line_total), 0) from public.pos_transaction_items i where i.returned_at is null)
    - (select coalesce(sum(discount), 0) from public.pos_transactions)                                         as pos_revenue,
  (select count(*) from public.orders)                                                                         as total_orders,
  (select count(*) from public.orders where order_status not in ('Delivered', 'Cancelled'))                    as active_orders,
  (select count(*) from public.orders where order_status in ('Pending', 'Processing'))                         as awaiting_dispatch,
  (select count(*) from public.orders where order_status = 'Delivered')                                        as delivered_orders,
  (select count(*) from public.orders where order_status = 'Cancelled')                                        as cancelled_orders,
  (select count(*) from public.orders where payment_status = 'Pending' and order_status <> 'Cancelled')        as unpaid_orders,
  (select count(*) from public.pos_transactions)                                                               as pos_bills,
  (select count(*) from public.customers)                                                                      as customers,
  (select count(*) from public.products)                                                                       as products,
  (select count(*) from public.products where stock_status = 'Low Stock')                                      as low_stock_products,
  (select count(*) from public.products where stock_status = 'Out of Stock')                                   as out_of_stock_products,
  (select coalesce(sum(stock * price), 0) from public.products)                                                as inventory_value;

-- Revenue per day per channel (Website / Admin / POS), for charts and date filters.
create view public.sales_daily with (security_invoker = on) as
select day, channel, count(*)::integer as bills, sum(items)::integer as items, sum(revenue)::numeric(12,2) as revenue
from (
  select (o.placed_at at time zone 'Asia/Kolkata')::date as day, o.source::text as channel,
         o.items_count as items, o.total as revenue
    from public.orders o
   where o.order_status <> 'Cancelled'
  union all
  select (t.created_at at time zone 'Asia/Kolkata')::date, 'POS',
         coalesce(sum(i.qty) filter (where i.returned_at is null), 0),
         coalesce(sum(i.line_total) filter (where i.returned_at is null), 0) - t.discount
    from public.pos_transactions t
    left join public.pos_transaction_items i on i.transaction_id = t.id
   group by t.id
) s
group by day, channel;

-- Best sellers across website and POS.
create view public.top_products with (security_invoker = on) as
select product_id, max(name) as name, sum(qty)::integer as units_sold, sum(amount)::numeric(12,2) as revenue
from (
  select oi.product_id, oi.name, oi.qty, oi.line_total as amount
    from public.order_items oi join public.orders o on o.id = oi.order_id
   where o.order_status <> 'Cancelled'
  union all
  select pi.product_id, pi.name, pi.qty, pi.line_total
    from public.pos_transaction_items pi
   where pi.returned_at is null
) s
group by product_id;

-- Customers page: orders, spend and last order per customer.
create view public.customer_stats with (security_invoker = on) as
select c.id, c.name, c.email, c.phone, c.registered_at, c.profile_id is not null as has_account,
       count(o.id)::integer                                                    as orders_count,
       coalesce(sum(o.total) filter (where o.order_status <> 'Cancelled'), 0)  as total_spent,
       max(o.placed_at)                                                        as last_order_at
  from public.customers c
  left join public.orders o on o.customer_id = c.id
 group by c.id;

-- Inventory page: every size/colour cell with its product.
create view public.inventory_view with (security_invoker = on) as
select v.id as variant_id, p.id as product_id, p.name, p.sku, p.barcode, p.image_url, p.price, p.is_live,
       c.name as category, v.size, v.color, v.quantity, p.stock as product_stock, p.stock_status
  from public.product_variants v
  join public.products p on p.id = v.product_id
  left join public.categories c on c.id = p.category_id;

-- Coupons list with today's state (Live / Paused / Scheduled / Ended / Used up).
create view public.coupon_overview with (security_invoker = on) as
select c.*, public.coupon_state(c) as state
  from public.coupons c;

-- Product cards / product page in one query: category names and tag names included.
create view public.product_catalog with (security_invoker = on) as
select p.*,
       c.name  as category_name,  c.slug as category_slug,
       sc.name as sub_category_name,
       ssc.name as sub_sub_category_name,
       coalesce((select array_agg(t.name order by t.name) from public.product_tags pt join public.tags t on t.id = pt.tag_id
                  where pt.product_id = p.id), '{}') as tag_names,
       case when p.mrp is not null and p.mrp > p.price then round((p.mrp - p.price) / p.mrp * 100)::integer else 0 end as percent_off
  from public.products p
  left join public.categories c on c.id = p.category_id
  left join public.sub_categories sc on sc.id = p.sub_category_id
  left join public.sub_sub_categories ssc on ssc.id = p.sub_sub_category_id;

-- Admin-only reports are not exposed to anonymous visitors at all.
revoke all on public.dashboard_summary, public.sales_daily, public.top_products, public.customer_stats,
              public.inventory_view, public.coupon_overview
  from anon;
grant select on public.dashboard_summary, public.sales_daily, public.top_products, public.customer_stats,
                public.inventory_view, public.coupon_overview
  to authenticated, service_role;
grant select on public.product_catalog to anon, authenticated, service_role;
