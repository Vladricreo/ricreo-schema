-- Fix 20260930180000: PL/pgSQL risolve entrambi i rami del CASE, quindi su `User` falliva
-- l'accesso a NEW."userId" (bloccando gli UPDATE di name/username). Rami separati con IF.
CREATE OR REPLACE FUNCTION app_auth.sync_user_metadata_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'Profile' THEN
    PERFORM app_auth.sync_user_metadata(NEW."userId");
  ELSE
    PERFORM app_auth.sync_user_metadata(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
