-- `authenticated` non ha USAGE su `public` (tabelle app non esposte alla Data API):
-- l'helper RLS vive in uno schema dedicato, non esposto, accessibile solo per EXECUTE.
CREATE SCHEMA IF NOT EXISTS app_auth;

REVOKE ALL ON SCHEMA app_auth FROM PUBLIC;
GRANT USAGE ON SCHEMA app_auth TO authenticated, service_role;

CREATE OR REPLACE FUNCTION app_auth.has_role(p_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public."User" u
    JOIN public."UserRole" ur ON ur."userId" = u.id
    JOIN public."Role" r ON r.id = ur."roleId"
    WHERE u."authUserId" = (SELECT auth.uid())
      AND u."isActive"
      AND r.name = p_role
  );
$$;

REVOKE ALL ON FUNCTION app_auth.has_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION app_auth.has_role(text) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.app_user_has_role(text);
