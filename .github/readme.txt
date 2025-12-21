## Prisma Schema Submodule (`prisma/schema`) — Comandi utili & troubleshooting

Questa cartella **non è una cartella normale**: è un **Git submodule** che punta al repository `ricreo-schema`.
Nel repo principale (Ricreo-Inventory `client`) viene salvato **solo il puntatore** a un commit specifico del submodule.

---

## Workflow standard (cosa fare di solito)

### 1) Modificare e pushare lo schema (nel submodule)

Da root del repo `client`:

```bash
git -C prisma/schema status
git -C prisma/schema checkout main
git -C prisma/schema pull --ff-only

# ... fai le modifiche ai file .prisma / migrations ...
git -C prisma/schema add -A
git -C prisma/schema commit -m "descrizione breve"
git -C prisma/schema push origin main
```

### 2) Aggiornare il repo principale (puntatore del submodule)

Sempre da root del repo `client`:

```bash
git add prisma/schema
git commit -m "chore(prisma): aggiorna submodule schema"
git push
```

---

## Comandi rapidi di diagnostica

### Stato submodule + repo principale

```bash
git status
git submodule status
git -C prisma/schema status
git -C prisma/schema rev-parse --abbrev-ref HEAD
git -C prisma/schema log --oneline -5
```

### Vedere “cos’è cambiato” nel submodule (dal repo principale)

```bash
git diff --submodule
```

---

## Casi strani comuni (e come risolverli)

### Caso A — “cannot push detached HEAD” nel submodule

**Causa**: sei dentro `prisma/schema` in **detached HEAD** (non su un branch), quindi `git push` non sa quale branch aggiornare.

**Fix (sicuro se vuoi pushare su `main`)**:

```bash
git -C prisma/schema fetch origin
git -C prisma/schema checkout main
git -C prisma/schema pull --ff-only

# se hai un commit in detached HEAD che vuoi mantenere, sostituisci <SHA> con il commit
git -C prisma/schema merge --ff-only <SHA>
git -C prisma/schema push origin main
```

Se ti serve “salvare” il commit prima di cambiare branch:

```bash
git -C prisma/schema branch wip/<nome> <SHA>
```

### Caso B — Il repo principale dice: `modified: prisma/schema (new commits)`

**Significa**: il submodule è a un commit diverso rispetto a quello “registrato” nel repo principale.

**Soluzione**: dopo aver pushato lo schema (submodule), fai commit del puntatore nel repo principale:

```bash
git add prisma/schema
git commit -m "chore(prisma): aggiorna submodule schema"
git push
```

### Caso C — Ho clonato/pullato il repo principale e il submodule è “vuoto” o non aggiornato

```bash
git submodule update --init --recursive
```

### Caso D — Riallineare il `client` ai commit del submodule (portare il puntatore all’ultimo `origin/main`)

Se vuoi che il repo principale punti **all’ultimo commit disponibile** del submodule su `origin/main`:

```bash
git submodule update --init --recursive
git submodule update --remote --merge prisma/schema

git add prisma/schema
git commit -m "chore(prisma): bump submodule prisma/schema"
git push
```

> Nota: questo non “crea” commit nel submodule, aggiorna solo il puntatore del repo principale al commit già esistente su `origin/main` del submodule.

### Caso E — Il submodule locale è stato modificato ma non vuoi tenere nulla

```bash
git -C prisma/schema reset --hard
git -C prisma/schema clean -fd
git submodule update --init --recursive
```

---

## Regola d’oro

- **Prima**: commit/push nel submodule (`prisma/schema` → `ricreo-schema`)
- **Poi**: commit/push nel repo principale (`client`) per aggiornare il puntatore del submodule


