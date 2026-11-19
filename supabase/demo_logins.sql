-- =============================================================================
-- Demo logins (optional) — same accounts the admin panel demo uses:
--   Super admin : demo.admin@example.com    / shop123
--   Shopper     : demo.shopper@example.com  / demo1234
--
-- Creates the users straight in Supabase Auth (confirmed, can sign in with
-- email + password). Skips any email that already exists.
-- ⚠ Demo only. For a real client, create the owner in Dashboard → Authentication
--   and run:  select public.make_super_admin('owner@client.com');
-- =============================================================================
do $$
declare
  u record;
  v_id uuid;
begin
  for u in
    select * from (values
      ('demo.admin@example.com',   'shop123',  'Demo Admin'),
      ('demo.shopper@example.com', 'demo1234', 'Demo Shopper')
    ) as t(email, password, full_name)
  loop
    if exists (select 1 from auth.users where email = u.email) then
      continue;
    end if;
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, email_change, email_change_token_new, recovery_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', u.email,
      extensions.crypt(u.password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', u.full_name), now(), now(),
      '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_id, v_id::text,
            jsonb_build_object('sub', v_id::text, 'email', u.email, 'email_verified', true),
            'email', now(), now(), now());
  end loop;
end $$;

-- Promote the admin (this also removes the customer row sign-up created for them).
select public.make_super_admin('demo.admin@example.com');
