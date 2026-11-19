-- =============================================================================
-- 07 · Built-in defaults (not demo data — the app needs these to work)
--   • the single store_settings row
--   • the 8 storefront themes offered in Admin → Theme Setup
-- =============================================================================

insert into public.themes (id, name, version, tagline, layout, colors) values
  ('default', 'Default Theme', '3.0', 'A polished photo hero, bento collections and soft product cards', 'signature',
   '{"accent":"#A47A22","accent2":"#D9B865","accentDark":"#86631A","accentLight":"#E9D29A","accentSoft":"#F3EBDA","accentLine":"#E2D3B0","ink":"#0F2A24","ink2":"#16372F","ink3":"#24493F","deep":"#081A15","page":"#F6F2EA"}'::jsonb),
  ('marketplace', 'Theme Marketplace', '3.1', 'Big search bar, category sidebar, flash deals and dense grids', 'marketplace',
   '{"accent":"#F2611D","accent2":"#FF8A3D","accentDark":"#D44E0E","accentLight":"#FFC29B","accentSoft":"#FFF1E8","accentLine":"#FFD8C2","ink":"#1B2230","ink2":"#252E3F","ink3":"#364257","deep":"#131925","page":"#F2F4F7"}'::jsonb),
  ('lifestyle', 'Lifestyle Theme', '1.8', 'Colourful collage hero, rounded tiles and playful cards', 'lifestyle',
   '{"accent":"#7B5CFA","accent2":"#FF6FB5","accentDark":"#6243E0","accentLight":"#CDBEFF","accentSoft":"#F2EEFF","accentLine":"#DCD2FF","ink":"#221A3D","ink2":"#2E2450","ink3":"#41366A","deep":"#170F2E","page":"#FAF8FF"}'::jsonb),
  ('boutique', 'Boutique Theme', '1.5', 'Centred logo, serif headlines, sharp edges and a lookbook', 'boutique',
   '{"accent":"#8C6A43","accent2":"#B8956A","accentDark":"#6F5233","accentLight":"#E2C9A6","accentSoft":"#F3ECE2","accentLine":"#E4D6C3","ink":"#1C1A17","ink2":"#272420","ink3":"#3A352F","deep":"#12110F","page":"#F8F5F0"}'::jsonb),
  ('volt', 'Volt Theme', '1.2', 'Loud type, thick outlines, offset shadows and stickers', 'volt',
   '{"accent":"#FF4D00","accent2":"#FF7A2E","accentDark":"#D93F00","accentLight":"#D4FF3A","accentSoft":"#FFE9DC","accentLine":"#FFC9AD","ink":"#111111","ink2":"#1C1C1C","ink3":"#2E2E2E","deep":"#0A0A0A","page":"#F2EFE6"}'::jsonb),
  ('aster', 'Aster Theme', '1.0', 'Quiet Nordic minimal: thin lines, light type, lots of air', 'aster',
   '{"accent":"#3F6B5A","accent2":"#6F9C89","accentDark":"#2F5446","accentLight":"#B5D3C6","accentSoft":"#EDF3F0","accentLine":"#D3E2DB","ink":"#1F2421","ink2":"#2A302C","ink3":"#3B433E","deep":"#151917","page":"#FAFAF8"}'::jsonb),
  ('atelier', 'Atelier Theme', '2.0', 'Midnight sapphire and champagne: a night-boutique home with art-deco patterns', 'atelier',
   '{"accent":"#2B4A9B","accent2":"#5A79CF","accentDark":"#1D3577","accentLight":"#E3CC9C","accentSoft":"#EEF1F8","accentLine":"#D6DDEE","ink":"#0B1532","ink2":"#121E45","ink3":"#1C2C5E","deep":"#060B1F","page":"#F8F6F1"}'::jsonb),
  ('aurora', 'Aurora Theme', '1.0', 'Aurora-glow hero, floating navbar, bento grid and glass cards', 'aurora',
   '{"accent":"#0EA5A4","accent2":"#6366F1","accentDark":"#0B8584","accentLight":"#7DE3E1","accentSoft":"#E6F8F8","accentLine":"#BDEDEC","ink":"#0B1220","ink2":"#141C30","ink3":"#232C45","deep":"#070B16","page":"#F6F8FC"}'::jsonb)
on conflict (id) do update
  set name = excluded.name, version = excluded.version, tagline = excluded.tagline,
      layout = excluded.layout, colors = excluded.colors;

insert into public.store_settings (id, active_theme_id) values (true, 'default')
on conflict (id) do nothing;
