-- Spedizioni FBA "manuali": consente AssemblyBox senza AssemblyOrder
-- e raggruppa più righe in un unico carton fisico (multi-SKU per scatola).

ALTER TABLE inventory."AssemblyBox"
  ALTER COLUMN "assemblyOrderId" DROP NOT NULL;

ALTER TABLE inventory."AssemblyBox"
  ADD COLUMN "isManual" BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN "manualGroupId" UUID;

CREATE INDEX "AssemblyBox_manualGroupId_idx"
  ON inventory."AssemblyBox"("manualGroupId");
