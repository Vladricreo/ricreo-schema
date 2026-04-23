-- Aggiunge il valore TERTIARY all'enum PackagingClass.
-- Posizionato prima di OTHERS per coerenza con l'ordine logico
-- (Primario -> Secondario -> Terziario -> Altri).
ALTER TYPE "inventory"."PackagingClass" ADD VALUE IF NOT EXISTS 'TERTIARY' BEFORE 'OTHERS';
