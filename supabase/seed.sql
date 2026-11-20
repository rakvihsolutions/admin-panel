-- =============================================================================
-- Demo data — the same sample store the admin panel ships with (demo-data.ts):
-- Demo Jewellery, 5 categories, 16 products with size × colour stock, 3 coupons,
-- 7 customers, 6 website orders (2 with Shiprocket shipments), 3 POS bills,
-- 4 hero banners, 6 Instagram posts, 3 videos and 8 storefront themes.
--
-- OPTIONAL — not part of full_setup.sql. Run it only if you want sample data to show
-- a client. Remove it again with clear_demo_data.sql.
-- =============================================================================
begin;

-- Store details, delivery rules and payment options
update public.store_settings set
  name = 'Demo Jewellery', tagline = 'Hand-finished jewellery, made for every day and every occasion', footer_about = 'Thoughtfully selected necklaces, earrings, rings and bracelets, finished with care and made to be treasured.', footer_note = 'A demo store: products and prices are samples, and no real payments are processed.',
  logo_url = '', show_name_with_logo = true, email = 'demo.support@example.com', phone = '+91 00000 00000', whatsapp = '+91 00000 00000',
  address = '3rd Floor, 100 Feet Road, Indiranagar, Bengaluru, Karnataka 560038', hours = 'Mon–Sun, 9am–9pm', gstin = '29ABCDE1234F1Z5',
  return_policy = 'Unused jewellery in its original packaging can be returned within 7 days of delivery. Please keep each piece away from water, perfume and harsh chemicals.',
  social = '{"instagram":"https://instagram.com/demojewellery","facebook":"","youtube":"","x":""}'::jsonb, free_delivery_from = 4999, delivery_fee = 149, low_stock_threshold = 10,
  razorpay_key_id = '', merchant_name = 'Demo Jewellery',
  razorpay_enabled = true, cod_enabled = true, active_theme_id = 'default';

-- Sizes, colours, tags
insert into public.sizes (name, code, sort_order) values
  ('Ring Size 6', '6', 0),
  ('Ring Size 7', '7', 1),
  ('Ring Size 8', '8', 2),
  ('Bangle Size 2.4', '2.4', 3),
  ('Bangle Size 2.6', '2.6', 4),
  ('Bangle Size 2.8', '2.8', 5);
insert into public.colors (name, hex, sort_order) values
  ('Yellow Gold', '#C9A44C', 0),
  ('Rose Gold', '#B76E79', 1),
  ('Silver', '#C7C7CC', 2),
  ('Antique Gold', '#927443', 3),
  ('White Gold', '#E6E4DF', 4),
  ('Pearl', '#F3EBDD', 5),
  ('Emerald', '#28745B', 6),
  ('Ruby', '#9B263B', 7);
insert into public.tags (name) values
  ('Bestseller'),
  ('New Launch'),
  ('Premium'),
  ('Handcrafted'),
  ('Gifting'),
  ('Bridal');

-- Categories (3 levels)
insert into public.categories (name, slug, icon, image_url, blurb, status, sort_order) values
  ('Necklaces', 'necklaces', '📿', 'https://images.unsplash.com/photo-1599459183200-59c7687a0275?auto=format&fit=crop&q=80&w=800', 'Delicate chains, statement pendants and heirloom-inspired designs', 'Active', 0),
  ('Earrings', 'earrings', '✨', 'https://images.unsplash.com/photo-1608508644127-ba99d7732fee?auto=format&fit=crop&q=80&w=800', 'Everyday studs, graceful drops and festive jhumkas', 'Active', 1),
  ('Rings', 'rings', '💍', 'https://images.unsplash.com/photo-1543294001-f7cd5d7fb516?auto=format&fit=crop&q=80&w=800', 'Solitaire, halo and keepsake rings in considered sizes', 'Active', 2),
  ('Bracelets & Bangles', 'bracelets', '◉', 'https://images.unsplash.com/photo-1596944924616-7b38e7cfac36?auto=format&fit=crop&q=80&w=800', 'Polished cuffs, delicate links and traditional bangles', 'Active', 3),
  ('Bridal & Occasion', 'bridal', '✿', 'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=80&w=800', 'Jewellery for celebrations, ceremonies and gifting', 'Active', 4);
insert into public.sub_categories (category_id, name, slug, status, sort_order)
select c.id, v.name, v.slug, v.status::public.record_status, v.sort_order
from (values
  ('Necklaces', 'Chains & Pendants', 'chains-pendants', 'Active', 0),
  ('Necklaces', 'Statement Necklaces', 'statement-necklaces', 'Active', 1),
  ('Earrings', 'Stud Earrings', 'stud-earrings', 'Active', 2),
  ('Earrings', 'Drops & Jhumkas', 'drops-jhumkas', 'Active', 3),
  ('Rings', 'Solitaire Rings', 'solitaire-rings', 'Active', 4),
  ('Rings', 'Statement Rings', 'statement-rings', 'Active', 5),
  ('Bracelets & Bangles', 'Bracelets', 'bracelets', 'Active', 6),
  ('Bracelets & Bangles', 'Bangles', 'bangles', 'Active', 7),
  ('Bridal & Occasion', 'Bridal Sets', 'bridal-sets', 'Active', 8),
  ('Bridal & Occasion', 'Festive Jewellery', 'festive-jewellery', 'Active', 9)
) as v(category, name, slug, status, sort_order)
join public.categories c on c.name = v.category;
insert into public.sub_sub_categories (sub_category_id, name, slug, status, sort_order)
select sc.id, v.name, v.slug, v.status::public.record_status, v.sort_order
from (values
  ('Necklaces', 'Statement Necklaces', 'Temple & Heritage', 'temple-heritage', 'Active', 0),
  ('Earrings', 'Stud Earrings', 'Pearl & Kundan', 'pearl-kundan', 'Active', 1),
  ('Rings', 'Solitaire Rings', 'Halo & Solitaire', 'halo-solitaire', 'Active', 2),
  ('Bridal & Occasion', 'Bridal Sets', 'Traditional Sets', 'traditional-sets', 'Active', 3)
) as v(category, sub_category, name, slug, status, sort_order)
join public.categories c on c.name = v.category
join public.sub_categories sc on sc.category_id = c.id and sc.name = v.sub_category;

-- Products (stock is filled in from the variants below by trigger)
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Mehr Pearl Strand Necklace', 'mehr-pearl-strand-necklace', 'A single strand of lustrous pearls finished with a slim gold clasp, made to be worn every day.', 'MEH-NK-01', '8901234567890',
  c.id, sc.id, null,
  24999, 29999, '{}'::text[], array['Pearl', 'Yellow Gold'], 'https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1611085583191-a3b181a88401?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Hand-knotted freshwater pearls', 'Lightweight for all-day wear', 'Slim gold box clasp', 'Presented in a keepsake box'],
  '[["Style","Pearl strand"],["Pearl","Freshwater, 7–8 mm"],["Length","18 in"],["Care","Wipe with a soft cloth"]]'::jsonb, false, true, true, 4.8, 1284
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Necklaces' and sc.name = 'Chains & Pendants';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Nila Sapphire Drop Earrings', 'nila-sapphire-drop-earrings', 'Deep blue sapphire-hued stones framed in sparkling halos, made for evenings and celebrations.', 'MIR-ER-02', '8901234567891',
  c.id, sc.id, null,
  9499, 12999, '{}'::text[], array['White Gold', 'Yellow Gold'], 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Sapphire-hued centre stones', 'Hypoallergenic posts', 'Secure push-back fastening', 'Gift-ready presentation'],
  '[["Style","Statement drop"],["Stone","Lab-created sapphire"],["Closure","Push back"],["Pair","Sold as a pair"]]'::jsonb, true, true, true, 4.7, 612
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Earrings' and sc.name = 'Drops & Jhumkas';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Gulab Pink Stone Ring', 'gulab-pink-stone-ring', 'A soft pink oval stone held in a fine gold setting on a comfortable polished band.', 'GUL-RG-03', '8901234567892',
  c.id, sc.id, null,
  11999, 14999, array['6', '7', '8'], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1603561591411-07134e71a2a9?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1603561591411-07134e71a2a9?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1608042314453-ae338d80c427?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Pink oval centre stone', 'Comfort-fit band', 'Available in sizes 6, 7 and 8', 'Polished keepsake box'],
  '[["Style","Cocktail ring"],["Finish","Gold tone"],["Stone","Pink quartz"],["Care","Store separately"]]'::jsonb, false, true, true, 4.6, 402
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Rings' and sc.name = 'Statement Rings';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Ira Textured Gold Bangles', 'ira-textured-gold-bangles', 'A polished pair of bangles with subtle engraved texture and a secure clasp.', 'IRA-BG-04', '8901234567893',
  c.id, sc.id, null,
  8999, 11999, array['2.4', '2.6', '2.8'], array['Yellow Gold'], 'https://images.unsplash.com/photo-1611107683227-e9060eccd846?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1611107683227-e9060eccd846?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Matching pair', 'Textured polished finish', 'Traditional sizes', 'Keepsake pouch included'],
  '[["Style","Bangle pair"],["Finish","Gold tone"],["Sizes","2.4, 2.6 and 2.8"],["Closure","Hinged clasp"]]'::jsonb, false, false, true, 4.5, 318
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Bracelets & Bangles' and sc.name = 'Bangles';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Heritage Gold Necklace', 'heritage-gold-necklace', 'Hand-linked 22K gold-plated chain with a soft, warm lustre.', 'HER-NK-05', '8904100000000',
  c.id, sc.id, null,
  28999, 34999, '{}'::text[], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1601821765780-754fa98637c1?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1601821765780-754fa98637c1?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1633810542706-90e5ff7557be?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['22K gold-plated finish', 'Hand-linked by artisans', 'Lightweight for all-day wear', 'Presented in a keepsake box'],
  '[["Style","Link necklace"],["Finish","Polished gold"],["Closure","Secure lobster clasp"],["Care","Store in a dry pouch"]]'::jsonb, false, true, true, 4.9, 612
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Necklaces' and sc.name = 'Statement Necklaces';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Mira Rose Gold Drop Earrings', 'mira-rose-gold-drop-earrings', 'Slender rose gold drops that catch the light as you move.', 'MIR-ER-06', '8904100007919',
  c.id, sc.id, null,
  7499, 9999, '{}'::text[], array['Rose Gold', 'Yellow Gold'], 'https://images.unsplash.com/photo-1629224316810-9d8805b95e76?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1629224316810-9d8805b95e76?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Rose gold finish', 'Hypoallergenic posts', 'Secure push-back fastening', 'Gift-ready presentation'],
  '[["Style","Drop earrings"],["Finish","18K rose gold plated"],["Length","4 cm"],["Pair","Sold as a pair"]]'::jsonb, false, true, true, 4.8, 3410
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Earrings' and sc.name = 'Drops & Jhumkas';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Ziya Polki Choker Set', 'ziya-polki-choker-set', 'A statement choker with matching earrings for celebration dressing.', 'ZIY-BR-07', '8904100015838',
  c.id, sc.id, (select ssc.id from public.sub_sub_categories ssc where ssc.sub_category_id = sc.id and ssc.name = 'Traditional Sets'),
  18999, 24999, '{}'::text[], array['Yellow Gold', 'Antique Gold'], 'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Polki-inspired stone setting', 'Adjustable necklace chain', 'Matching earrings included', 'Designed for festive occasions'],
  '[["Set includes","Necklace and earrings"],["Finish","Antique gold"],["Stone","Polki-style glass"],["Closure","Adjustable dori"]]'::jsonb, true, false, true, 4.7, 874
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Bridal & Occasion' and sc.name = 'Bridal Sets';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Saanvi Gold Link Bracelet', 'saanvi-gold-link-bracelet', 'Polished gold links with an easy, everyday drape.', 'SAA-BR-08', '8904100023757',
  c.id, sc.id, null,
  6299, 8499, '{}'::text[], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1602173574767-37ac01994b2a?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1602173574767-37ac01994b2a?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1596944924616-7b38e7cfac36?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Polished curb links', 'Comfortable everyday weight', 'Pairs beautifully with a watch', 'Gift-ready presentation'],
  '[["Style","Link bracelet"],["Finish","Gold tone"],["Length","7 in"],["Care","Avoid water and perfume"]]'::jsonb, false, false, true, 4.7, 298
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Bracelets & Bangles' and sc.name = 'Bracelets';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Aurelia Solitaire Ring', 'aurelia-solitaire-ring', 'A single brilliant stone on a slim, polished gold band.', 'AUR-RG-09', '8904100031676',
  c.id, sc.id, (select ssc.id from public.sub_sub_categories ssc where ssc.sub_category_id = sc.id and ssc.name = 'Halo & Solitaire'),
  15999, 19999, array['6', '7', '8'], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1598560917807-1bae44bd2be8?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1598560917807-1bae44bd2be8?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1543294001-f7cd5d7fb516?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Cubic zirconia centre stone', 'Comfort-fit band', 'Available in sizes 6, 7 and 8', 'Polished keepsake box'],
  '[["Style","Solitaire"],["Finish","18K gold plated"],["Stone","Cubic zirconia"],["Band","Comfort fit"]]'::jsonb, false, true, true, 4.8, 1520
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Rings' and sc.name = 'Solitaire Rings';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Meher Gold Knot Earrings', 'meher-gold-knot-earrings', 'Sculpted gold knots with a soft, brushed glow.', 'MEH-ER-10', '8904100039595',
  c.id, sc.id, null,
  4299, 5999, '{}'::text[], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1603974372039-adc49044b6bd?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1603974372039-adc49044b6bd?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1617038260897-41a1f14a8ca0?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Sculpted knot silhouette', 'Lightweight for all-day wear', 'Comfortable push-back closure', 'Made for everyday styling'],
  '[["Style","Knot stud"],["Finish","Brushed gold"],["Closure","Push back"],["Pair","Sold as a pair"]]'::jsonb, false, false, true, 4.6, 945
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Earrings' and sc.name = 'Stud Earrings';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Tara Silver Pendant Necklace', 'tara-silver-pendant-necklace', 'A sparkling cushion pendant on a fine sterling silver chain.', 'TAR-NK-11', '8904100047514',
  c.id, sc.id, null,
  5499, 6999, '{}'::text[], array['Silver', 'White Gold'], 'https://images.unsplash.com/photo-1589128777073-263566ae5e4d?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1589128777073-263566ae5e4d?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1588444837495-c6cfeb53f32d?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['925 sterling silver', 'Cushion-cut sparkling stone', 'Adjustable extender chain', 'Easy to layer'],
  '[["Metal","925 sterling silver"],["Length","16 in + 2 in extender"],["Closure","Lobster clasp"],["Care","Store in a dry pouch"]]'::jsonb, true, false, true, 4.6, 402
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Necklaces' and sc.name = 'Chains & Pendants';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Kavya Kundan Stud Earrings', 'kavya-kundan-stud-earrings', 'A refined kundan-inspired stud with a luminous finish.', 'KAV-ER-12', '8904100055433',
  c.id, sc.id, (select ssc.id from public.sub_sub_categories ssc where ssc.sub_category_id = sc.id and ssc.name = 'Pearl & Kundan'),
  3299, 4499, '{}'::text[], array['Yellow Gold', 'Pearl'], 'https://images.unsplash.com/photo-1626784215021-2e39ccf971cd?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1626784215021-2e39ccf971cd?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Kundan-inspired stonework', 'Lightweight stud profile', 'Secure push-back fastening', 'Ideal for everyday occasions'],
  '[["Style","Kundan stud"],["Finish","Gold tone"],["Stone","Glass kundan"],["Pair","Sold as a pair"]]'::jsonb, false, false, true, 4.5, 511
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Earrings' and sc.name = 'Stud Earrings';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Ruhani Rose Gold Pendant', 'ruhani-rose-gold-pendant', 'A delicate everyday pendant on a fine matching chain.', 'RUH-NK-13', '8904100063352',
  c.id, sc.id, null,
  3999, 5499, '{}'::text[], array['Rose Gold'], 'https://images.unsplash.com/photo-1610694955371-d4a3e0ce4b52?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1610694955371-d4a3e0ce4b52?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1620656798579-1984d9e87df7?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Minimal floral pendant', 'Rose gold finish', 'Matching chain included', 'Gift-ready presentation'],
  '[["Style","Pendant necklace"],["Finish","Rose gold tone"],["Chain","18 in"],["Closure","Lobster clasp"]]'::jsonb, false, false, true, 4.4, 239
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Necklaces' and sc.name = 'Chains & Pendants';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Leela Diamond Tennis Bracelet', 'leela-diamond-tennis-bracelet', 'A continuous line of brilliant stones in a white gold setting.', 'LEE-BR-14', '8904100071271',
  c.id, sc.id, null,
  8999, 11999, '{}'::text[], array['White Gold'], 'https://images.unsplash.com/photo-1573408301185-9146fe634ad0?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1573408301185-9146fe634ad0?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Line of brilliant stones', 'Flexible, comfortable setting', 'Box clasp with safety catch', 'Polished presentation box'],
  '[["Style","Tennis bracelet"],["Finish","White gold tone"],["Stone","Cubic zirconia"],["Closure","Box clasp"]]'::jsonb, false, false, true, 4.6, 418
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Bracelets & Bangles' and sc.name = 'Bracelets';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Noor Diamond Halo Ring', 'noor-diamond-halo-ring', 'A delicate halo ring with a bright, elegant sparkle.', 'NOO-RG-15', '8904100079190',
  c.id, sc.id, (select ssc.id from public.sub_sub_categories ssc where ssc.sub_category_id = sc.id and ssc.name = 'Halo & Solitaire'),
  12999, 16999, array['6', '7', '8'], array['White Gold'], 'https://images.unsplash.com/photo-1605100804763-247f67b3557e?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1605100804763-247f67b3557e?auto=format&fit=crop&q=80&w=800', 'https://images.unsplash.com/photo-1631982690223-8aa4be0a2497?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Halo-inspired setting', 'Brilliant clear centre stone', 'Available in sizes 6, 7 and 8', 'Polished presentation box'],
  '[["Style","Halo ring"],["Finish","White gold tone"],["Stone","Cubic zirconia"],["Sizes","6, 7 and 8"]]'::jsonb, false, false, true, 4.7, 284
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Rings' and sc.name = 'Solitaire Rings';
insert into public.products (name, slug, description, sku, barcode, category_id, sub_category_id, sub_sub_category_id, price, mrp,
  sizes, colors, image_url, images, color_images, highlights, specs, is_new_arrival, is_featured, is_live, rating, reviews_count)
select 'Anika Floral Bracelet', 'anika-floral-bracelet', 'A delicate floral bracelet with a graceful adjustable fit.', 'ANI-BR-16', '8904100087109',
  c.id, sc.id, null,
  4799, 6499, '{}'::text[], array['Yellow Gold', 'Rose Gold'], 'https://images.unsplash.com/photo-1611591437281-460bfbe1220a?auto=format&fit=crop&q=80&w=800',
  array['https://images.unsplash.com/photo-1611591437281-460bfbe1220a?auto=format&fit=crop&q=80&w=800'],
  '{}'::jsonb, array['Floral link detailing', 'Lightweight everyday wear', 'Adjustable extender chain', 'Gift-ready presentation'],
  '[["Style","Chain bracelet"],["Finish","Gold tone"],["Length","6.5 in + extender"],["Closure","Lobster clasp"]]'::jsonb, false, false, true, 4.5, 176
from public.categories c join public.sub_categories sc on sc.category_id = c.id
where c.name = 'Bracelets & Bangles' and sc.name = 'Bracelets';

-- Stock per size × colour
insert into public.product_variants (product_id, size, color, quantity)
select p.id, v.size, v.color, v.qty
from (values
  ('MEH-NK-01', 'Standard', 'Pearl', 30),
  ('MEH-NK-01', 'Standard', 'Yellow Gold', 15),
  ('MIR-ER-02', 'Standard', 'White Gold', 10),
  ('MIR-ER-02', 'Standard', 'Yellow Gold', 8),
  ('GUL-RG-03', '6', 'Yellow Gold', 2),
  ('GUL-RG-03', '6', 'Rose Gold', 2),
  ('GUL-RG-03', '7', 'Yellow Gold', 2),
  ('GUL-RG-03', '7', 'Rose Gold', 2),
  ('GUL-RG-03', '8', 'Yellow Gold', 2),
  ('GUL-RG-03', '8', 'Rose Gold', 2),
  ('IRA-BG-04', '2.4', 'Yellow Gold', 0),
  ('IRA-BG-04', '2.6', 'Yellow Gold', 0),
  ('IRA-BG-04', '2.8', 'Yellow Gold', 0),
  ('HER-NK-05', 'Standard', 'Yellow Gold', 9),
  ('HER-NK-05', 'Standard', 'Rose Gold', 9),
  ('MIR-ER-06', 'Standard', 'Rose Gold', 60),
  ('MIR-ER-06', 'Standard', 'Yellow Gold', 60),
  ('ZIY-BR-07', 'Standard', 'Yellow Gold', 32),
  ('ZIY-BR-07', 'Standard', 'Antique Gold', 32),
  ('SAA-BR-08', 'Standard', 'Yellow Gold', 22),
  ('SAA-BR-08', 'Standard', 'Rose Gold', 22),
  ('AUR-RG-09', '6', 'Yellow Gold', 6),
  ('AUR-RG-09', '6', 'Rose Gold', 6),
  ('AUR-RG-09', '7', 'Yellow Gold', 5),
  ('AUR-RG-09', '7', 'Rose Gold', 5),
  ('AUR-RG-09', '8', 'Yellow Gold', 5),
  ('AUR-RG-09', '8', 'Rose Gold', 5),
  ('MEH-ER-10', 'Standard', 'Yellow Gold', 19),
  ('MEH-ER-10', 'Standard', 'Rose Gold', 18),
  ('TAR-NK-11', 'Standard', 'Silver', 11),
  ('TAR-NK-11', 'Standard', 'White Gold', 11),
  ('KAV-ER-12', 'Standard', 'Yellow Gold', 26),
  ('KAV-ER-12', 'Standard', 'Pearl', 26),
  ('RUH-NK-13', 'Standard', 'Rose Gold', 29),
  ('LEE-BR-14', 'Standard', 'White Gold', 26),
  ('NOO-RG-15', '6', 'White Gold', 6),
  ('NOO-RG-15', '7', 'White Gold', 5),
  ('NOO-RG-15', '8', 'White Gold', 5),
  ('ANI-BR-16', 'Standard', 'Yellow Gold', 17),
  ('ANI-BR-16', 'Standard', 'Rose Gold', 17)
) as v(sku, size, color, qty)
join public.products p on p.sku = v.sku;

-- Product tags
insert into public.product_tags (product_id, tag_id)
select p.id, t.id
from (values
  ('MEH-NK-01', 'Bestseller'),
  ('MEH-NK-01', 'Premium'),
  ('MIR-ER-02', 'Bestseller'),
  ('MIR-ER-02', 'Gifting'),
  ('GUL-RG-03', 'Premium'),
  ('GUL-RG-03', 'Gifting'),
  ('IRA-BG-04', 'Gifting'),
  ('HER-NK-05', 'Bestseller'),
  ('MIR-ER-06', 'Bestseller'),
  ('ZIY-BR-07', 'New Launch'),
  ('SAA-BR-08', 'Gifting'),
  ('AUR-RG-09', 'Bestseller'),
  ('MEH-ER-10', 'Gifting'),
  ('TAR-NK-11', 'New Launch'),
  ('TAR-NK-11', 'Gifting'),
  ('KAV-ER-12', 'Gifting'),
  ('RUH-NK-13', 'Gifting'),
  ('ANI-BR-16', 'Gifting')
) as v(sku, tag)
join public.products p on p.sku = v.sku
join public.tags t on t.name = v.tag;

-- Coupons
insert into public.coupons (code, description, discount_type, discount_value, max_discount, min_purchase, usage_limit,
  usage_count, valid_from, valid_till, show_in_header, status) values
  ('MEGAFEST20', 'Festive Jewellery Edit — 20% off selected pieces', 'Percentage', 20, 3000, 1999, 500,
   142, '2026-10-01', '2026-12-31', true, 'Active'),
  ('WELCOME500', 'Flat ₹500 off on your first order', 'Fixed', 500, null, 2500, null,
   389, '2026-01-01', '2027-03-31', true, 'Active'),
  ('EARLYBIRD', 'Early bird offer on new launches', 'Percentage', 15, 1500, 999, 100,
   65, '2026-07-15', '2026-08-15', false, 'Expired');

-- Customers
insert into public.customers (name, email, phone, registered_at) values
  ('Demo Customer 01', 'demo.customer01@example.com', '+91 00000 00001', '2026-11-03'),
  ('Demo Customer 02', 'demo.customer02@example.com', '+91 00000 00002', '2026-10-20'),
  ('Demo Customer 03', 'demo.customer03@example.com', '+91 00000 00003', '2026-09-14'),
  ('Demo Customer 04', 'demo.customer04@example.com', '+91 00000 00004', '2026-08-02'),
  ('Demo Customer 05', 'demo.customer05@example.com', '+91 00000 00005', '2026-10-11'),
  ('Demo Customer 06', 'demo.customer06@example.com', '+91 00000 00006', '2026-07-23'),
  ('Demo Customer 07', 'demo.customer07@example.com', '', '2026-10-25');

-- Website orders (inserted as history: the stock above already reflects them)
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98211', (select id from public.customers where email = 'demo.customer06@example.com'), 'Demo Customer 06', 'demo.customer06@example.com', '+91 00000 00006',
  'Demo House 06, Demo Layout', 'Kolkata', 'West Bengal', '700045', '2026-10-28T18:30:00+05:30',
  9499, 0, 0, 9499, '', 1, 'Net Banking', 'Paid',
  'pay_QX2pR6dZs1Ve', null, null, 'Delivered', 'Website');
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98212', (select id from public.customers where email = 'demo.customer05@example.com'), 'Demo Customer 05', 'demo.customer05@example.com', '+91 00000 00005',
  'Demo House 05, Demo Layout', 'Pune', 'Maharashtra', '411005', '2026-10-30T13:48:00+05:30',
  8999, 0, 0, 8999, '', 1, 'Cash on Delivery', 'Pending',
  null, null, null, 'Processing', 'Website');
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98213', (select id from public.customers where email = 'demo.customer04@example.com'), 'Demo Customer 04', 'demo.customer04@example.com', '+91 00000 00004',
  'Demo House 04, Demo Layout', 'Chennai', 'Tamil Nadu', '600017', '2026-10-31T10:12:00+05:30',
  36998, 0, 0, 36998, '', 2, 'Credit Card', 'Paid',
  'pay_QX5tY4bWm8Kc', null, null, 'Shipped', 'Website');
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98214', (select id from public.customers where email = 'demo.customer03@example.com'), 'Demo Customer 03', 'demo.customer03@example.com', '+91 00000 00003',
  'Demo House 03, Demo Layout', 'Mumbai', 'Maharashtra', '400050', '2026-11-01T16:20:00+05:30',
  24999, 0, 0, 24999, '', 1, 'UPI', 'Paid',
  'pay_QX7a9Hc3Np2D', null, null, 'Processing', 'Website');
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98215', (select id from public.customers where email = 'demo.customer02@example.com'), 'Demo Customer 02', 'demo.customer02@example.com', '+91 00000 00002',
  'Demo House 02, Demo Layout', 'Bengaluru', 'Karnataka', '560038', '2026-11-02T11:05:00+05:30',
  11999, 0, 0, 11999, '', 1, 'UPI', 'Paid',
  'pay_QX81mK2vLr7T', null, null, 'Pending', 'Website');
insert into public.orders (order_number, customer_id, customer_name, email, phone, shipping_address, city, state, postal_code, placed_at,
  subtotal, discount, delivery_fee, total, coupon_code, items_count, payment_method, payment_status, payment_id, payment_detail, gateway_order_id,
  order_status, source)
values ('ORD-98216', (select id from public.customers where email = 'demo.customer01@example.com'), 'Demo Customer 01', 'demo.customer01@example.com', '+91 00000 00001',
  'Demo House 01, Demo Layout', 'Bengaluru', 'Karnataka', '560066', '2026-11-03T19:42:00+05:30',
  7499, 0, 0, 7499, '', 1, 'Credit Card', 'Pending',
  null, null, null, 'Pending', 'Website');

insert into public.order_items (order_id, product_id, name, sku, size, color, qty, price, image_url)
select o.id, p.id, v.name, v.sku, v.size, v.color, v.qty, v.price, v.image
from (values
  ('ORD-98216', 'Mira Rose Gold Drop Earrings', 'MIR-ER-06', 'Standard', 'Rose Gold', 1, 7499, 'https://images.unsplash.com/photo-1629224316810-9d8805b95e76?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98215', 'Gulab Pink Stone Ring', 'GUL-RG-03', '7', 'Yellow Gold', 1, 11999, 'https://images.unsplash.com/photo-1603561591411-07134e71a2a9?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98214', 'Mehr Pearl Strand Necklace', 'MEH-NK-01', 'Standard', 'Pearl', 1, 24999, 'https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98213', 'Mehr Pearl Strand Necklace', 'MEH-NK-01', 'Standard', 'Pearl', 1, 24999, 'https://images.unsplash.com/photo-1515562141207-7a88fb7ce338?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98213', 'Gulab Pink Stone Ring', 'GUL-RG-03', '8', 'Rose Gold', 1, 11999, 'https://images.unsplash.com/photo-1603561591411-07134e71a2a9?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98212', 'Ira Textured Gold Bangles', 'IRA-BG-04', '2.6', 'Yellow Gold', 1, 8999, 'https://images.unsplash.com/photo-1611107683227-e9060eccd846?auto=format&fit=crop&q=80&w=800'),
  ('ORD-98211', 'Nila Sapphire Drop Earrings', 'MIR-ER-02', 'Standard', 'White Gold', 1, 9499, 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&q=80&w=800')
) as v(order_number, name, sku, size, color, qty, price, image)
join public.orders o on o.order_number = v.order_number
left join public.products p on p.sku = v.sku;

-- Shiprocket shipments
insert into public.shipments (order_id, courier, awb, pickup_location, weight_kg, length_cm, width_cm, height_cm, status,
  sr_order_id, sr_shipment_id, remote_status, delivery_state, created_at)
select id, 'Delhivery', '1490223655213', 'Bengaluru Warehouse', 1.4, 30, 25, 12, 'In Transit',
  734120558, 731998204, 'IN TRANSIT', 'Tamil Nadu', '2026-11-01T09:30:00+05:30'
from public.orders where order_number = 'ORD-98213';
insert into public.shipments (order_id, courier, awb, pickup_location, weight_kg, length_cm, width_cm, height_cm, status,
  sr_order_id, sr_shipment_id, remote_status, delivery_state, created_at)
select id, 'Blue Dart', '7730091846521', 'Bengaluru Warehouse', 0.6, 18, 12, 9, 'Delivered',
  733870412, 731745690, 'DELIVERED', 'West Bengal', '2026-10-29T10:00:00+05:30'
from public.orders where order_number = 'ORD-98211';
-- Hero banners
insert into public.hero_banners (title, subtitle, image_url, mobile_image_url, cta_text, cta_link, is_active, text_align, text_color, sort_order) values
  ('Made to be treasured.', 'Hand-finished gold jewellery for every day and every occasion.', 'https://images.unsplash.com/photo-1611652022419-a9419f74343d?auto=format&fit=crop&q=80&w=1800',
   'https://images.unsplash.com/photo-1611652022419-a9419f74343d?auto=format&fit=crop&q=85&w=900&h=1200', 'Explore Necklaces', '#/shop?cat=necklaces', true, 'left', '#ffffff', 0),
  ('A little light, always.', 'Sculpted hoops and handcrafted earrings with thoughtful detail.', 'https://images.unsplash.com/photo-1617038260897-41a1f14a8ca0?auto=format&fit=crop&q=80&w=1800',
   'https://images.unsplash.com/photo-1617038260897-41a1f14a8ca0?auto=format&fit=crop&q=85&w=900&h=1200', 'Shop Earrings', '#/shop?cat=earrings', true, 'center', '#ffffff', 1),
  ('Mark the moment.', 'Rings and keepsakes designed for the stories you carry.', 'https://images.unsplash.com/photo-1622398925373-3f91b1e275f5?auto=format&fit=crop&q=80&w=1800',
   'https://images.unsplash.com/photo-1622398925373-3f91b1e275f5?auto=format&fit=crop&q=85&w=900&h=1200', 'Discover Rings', '#/shop?cat=rings', true, 'right', '#ffffff', 2),
  ('For every celebration.', 'Heirloom-inspired pieces for your most memorable days.', 'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=80&w=1800',
   'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=85&w=900&h=1200', 'Explore Bridal', '#/shop?cat=bridal', false, 'left', '#ffffff', 3);

-- Instagram feed
insert into public.instagram_posts (post_url, image_url, caption, sort_order) values
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1600721391689-2564bb8055de?auto=format&fit=crop&q=80&w=600', 'A little heritage, made for today. #DemoJewellery', 0),
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1584302179602-e4c3d3fd629d?auto=format&fit=crop&q=80&w=600', 'Gold hoops for all your lovely little moments. #Jewellery', 1),
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1631982690223-8aa4be0a2497?auto=format&fit=crop&q=80&w=600', 'A keepsake made to last. #Rings', 2),
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1543295204-2ae345412549?auto=format&fit=crop&q=80&w=600', 'Something blue, forever. #Bridal', 3),
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1617038220319-276d3cfab638?auto=format&fit=crop&q=80&w=600', 'Everyday gold, styled simply. #Earrings', 4),
  ('https://instagram.com/demojewellery', 'https://images.unsplash.com/photo-1608042314453-ae338d80c427?auto=format&fit=crop&q=80&w=600', 'Colour that catches the light. #Rings', 5);

-- Product videos
insert into public.videos (title, product_id, product_name, duration, views, thumbnail, video_url, date_added)
select v.title, p.id, v.product_name, v.duration, v.views, v.thumbnail, v.video_url, v.date_added::date
from (values
  ('Ziya Polki Choker: Craft & Detail', 'Ziya Polki Choker Set', '01:45', 12450, 'https://images.unsplash.com/photo-1601121141461-9d6647bca1ed?auto=format&fit=crop&q=80&w=400', 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', '2026-08-20'),
  ('Rose Gold Care Guide', 'Mira Rose Gold Drop Earrings', '00:58', 8930, 'https://images.unsplash.com/photo-1629224316810-9d8805b95e76?auto=format&fit=crop&q=80&w=400', 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', '2026-08-18'),
  ('How We Set Every Solitaire', 'Aurelia Solitaire Ring', '02:15', 24100, 'https://images.unsplash.com/photo-1598560917807-1bae44bd2be8?auto=format&fit=crop&q=80&w=400', 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4', '2026-08-10')
) as v(title, product_name, duration, views, thumbnail, video_url, date_added)
left join public.products p on p.name = v.product_name;

-- POS bills (in-store register history)
insert into public.pos_transactions (receipt_no, cashier_name, customer_name, items_count, subtotal, total, payment_method, created_at)
values ('REC-2026-8089', 'John Cashier (Reg #01)', 'Rahul Nair', 1, 4799, 4799, 'Cash', '2026-08-25T18:20:00+05:30');
insert into public.pos_transactions (receipt_no, cashier_name, customer_name, items_count, subtotal, total, payment_method, created_at)
values ('REC-2026-8090', 'Sarah Jenkins (Reg #02)', 'Walk-in Customer', 1, 9499, 9499, 'Card', '2026-08-26T13:15:00+05:30');
insert into public.pos_transactions (receipt_no, cashier_name, customer_name, items_count, subtotal, total, payment_method, created_at)
values ('REC-2026-8091', 'John Cashier (Reg #01)', 'Siddharth Rao', 2, 36998, 36998, 'UPI', '2026-08-26T15:45:00+05:30');
insert into public.pos_transaction_items (transaction_id, product_id, name, qty, price, stock_lines)
select t.id, p.id, v.name, v.qty, v.price, jsonb_build_array(jsonb_build_object('size', v.size, 'color', v.color, 'qty', v.qty))
from (values
  ('REC-2026-8091', 'Mehr Pearl Strand Necklace', 1, 24999, 'Standard', 'Pearl'),
  ('REC-2026-8091', 'Gulab Pink Stone Ring', 1, 11999, '6', 'Yellow Gold'),
  ('REC-2026-8090', 'Nila Sapphire Drop Earrings', 1, 9499, 'Standard', 'White Gold'),
  ('REC-2026-8089', 'Anika Floral Bracelet', 1, 4799, 'Standard', 'Yellow Gold')
) as v(receipt_no, name, qty, price, size, color)
join public.pos_transactions t on t.receipt_no = v.receipt_no
left join public.products p on p.name = v.name;

commit;
