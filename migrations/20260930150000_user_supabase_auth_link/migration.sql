-- Migrazione login verso Supabase Auth.
-- `User.id` (Int) resta la chiave usata da tutte le FK; `authUserId` collega la riga a `auth.users.id`.
-- Nessuna FK verso `auth.users`: lo schema `auth` non è gestito da Prisma.
ALTER TABLE "public"."User" ADD COLUMN "authUserId" UUID;

CREATE UNIQUE INDEX "User_authUserId_key" ON "public"."User"("authUserId");

-- Ruolo che abilita l'accesso ai dati dello schema `finance` (policy RLS in Ricreo-Finance).
INSERT INTO "public"."Role" ("id", "name", "description")
VALUES (gen_random_uuid(), 'Finance', 'Accesso all''app Ricreo Finance (schema finance)')
ON CONFLICT ("name") DO NOTHING;

-- Helper RLS: true se l'utente Supabase della richiesta è un `User` attivo con quel ruolo.
CREATE OR REPLACE FUNCTION public.app_user_has_role(p_role text)
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

REVOKE ALL ON FUNCTION public.app_user_has_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.app_user_has_role(text) TO authenticated, service_role;

-- Transizione: finché PF/Inventory verificano `User.password` con bcrypt, le due copie
-- dell'hash restano allineate in entrambe le direzioni (GoTrue usa bcrypt `$2a$`).

-- auth.users -> User: password cambiata da Supabase (recupero via email, updateUser).
CREATE OR REPLACE FUNCTION public.sync_auth_password_to_app_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public."User"
  SET "password" = NEW.encrypted_password
  WHERE "authUserId" = NEW.id
    AND "password" IS DISTINCT FROM NEW.encrypted_password;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_password_to_app_user
AFTER UPDATE OF encrypted_password ON auth.users
FOR EACH ROW
WHEN (
  NEW.encrypted_password IS DISTINCT FROM OLD.encrypted_password
  AND NEW.encrypted_password ~ '^\$2[aby]\$'
)
EXECUTE FUNCTION public.sync_auth_password_to_app_user();

-- User -> auth.users: password cambiata dalle app legacy, e disattivazione utente
-- (un `User` non attivo non deve poter ottenere un JWT Supabase).
CREATE OR REPLACE FUNCTION public.sync_app_user_to_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW."authUserId" IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE auth.users
  SET encrypted_password = NEW."password", updated_at = now()
  WHERE id = NEW."authUserId"
    AND NEW."password" ~ '^\$2[aby]\$'
    AND encrypted_password IS DISTINCT FROM NEW."password";

  UPDATE auth.users
  SET banned_until = CASE WHEN NEW."isActive" THEN NULL ELSE '2999-01-01'::timestamptz END,
      updated_at = now()
  WHERE id = NEW."authUserId"
    AND (banned_until IS NULL) IS DISTINCT FROM NEW."isActive";

  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_app_user_to_auth
AFTER UPDATE OF "password", "isActive", "authUserId" ON "public"."User"
FOR EACH ROW
EXECUTE FUNCTION public.sync_app_user_to_auth();

REVOKE ALL ON FUNCTION public.sync_auth_password_to_app_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_app_user_to_auth() FROM PUBLIC, anon, authenticated;
