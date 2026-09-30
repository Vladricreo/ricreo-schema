-- Profilo app -> `auth.users.raw_user_meta_data` (name, username, avatar_path), così le app che
-- usano Supabase Auth mostrano nome e avatar senza leggere `public`.
-- `avatar_path` è il path nel bucket Storage `inventory` (Profile.avatarUrl senza il prefisso `/files/`).
CREATE OR REPLACE FUNCTION app_auth.sync_user_metadata(p_user_id integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE auth.users a
  SET raw_user_meta_data = coalesce(a.raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object(
             'name', u.name,
             'username', u.username,
             'avatar_path', nullif(regexp_replace(coalesce(p."avatarUrl", ''), '^/files/', ''), '')
           ),
      updated_at = now()
  FROM public."User" u
  LEFT JOIN public."Profile" p ON p."userId" = u.id
  WHERE u.id = p_user_id
    AND a.id = u."authUserId";
$$;

REVOKE ALL ON FUNCTION app_auth.sync_user_metadata(integer) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app_auth.sync_user_metadata_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM app_auth.sync_user_metadata(
    CASE WHEN TG_TABLE_NAME = 'Profile' THEN NEW."userId" ELSE NEW.id END
  );
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION app_auth.sync_user_metadata_trigger() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER sync_user_metadata_to_auth
AFTER UPDATE OF "name", "username", "authUserId" ON "public"."User"
FOR EACH ROW
EXECUTE FUNCTION app_auth.sync_user_metadata_trigger();

CREATE TRIGGER sync_profile_metadata_to_auth
AFTER INSERT OR UPDATE OF "avatarUrl" ON "public"."Profile"
FOR EACH ROW
EXECUTE FUNCTION app_auth.sync_user_metadata_trigger();

-- Backfill degli utenti già collegati.
SELECT app_auth.sync_user_metadata(id) FROM public."User" WHERE "authUserId" IS NOT NULL;
