---
name: implement-issue
description: Implementa un issue de GitHub de punta a punta, del issue al PR listo para revisar. Toma el issue, crea la rama, escribe código y tests, se autorevisa, actualiza los docs y abre el PR. No mergea. Usar con "/implement-issue #43", "implementá el #43", "tomá el siguiente issue" o similar.
---

# Implementar issue

Lleva un issue a un PR listo para que lo revise una persona. Cada paso deja algo en GitHub (asignación, rama, PR), así otra sesión puede retomar sin depender de esta conversación.

**Límite:** el agente llega hasta el PR con el CI en verde. **Nunca mergea**, ni a `<RAMA_BASE>` ni a `main`. El merge es el punto donde una persona del equipo mira el cambio entero.

Si no te dieron un número ("tomá el siguiente"), corré `.claude/skills/estado/disponibles.sh`, proponé el primero de "Se pueden empezar ya" y esperá confirmación.

## 1. Tomar el issue

```bash
.claude/skills/implement-issue/preparar.sh <n>
```

Valida que el issue esté abierto, que no sea una épica, que no esté bloqueado, que no lo tenga asignado otra persona y que no haya cambios sin commitear. Si pasa, lo asigna a quien corre el comando, crea la rama `claude/<n>-<descripcion>` desde `<RAMA_BASE>` (o retoma la que ya existe) e imprime el issue con sus comentarios, su épica y lo que desbloquea.

Si falla, **no fuerces nada**: contale al usuario por qué y, si sirve, proponé el siguiente disponible. Para leer un issue sin tomarlo: `preparar.sh <n> --revisar`.

## 2. Entender antes de tocar

- Leé lo que el issue enlaza: ADRs, auditorías, docs, archivos.
- Leé `AGENTS.md` (convenciones de código y comandos) y lo que corresponda de `docs/development/architecture.md` y `docs/reference/`.
- Si el issue tiene criterios de aceptación ("Listo cuando", "Criterios de aceptación"), son la definición de terminado.
- Si el issue es ambiguo en algo que cambia el resultado, o contradice un ADR o el código, **preguntá antes de escribir código**. Si el usuario no está, comentá la duda en el issue (`gh issue comment`) y frená.
- Si el cambio toca una regla ya definida (ADR, auditoría, plan), el PR va a llevar `logica-negocio`: anotalo desde ahora.
- Revisá la sección **Autonomía** de `AGENTS.md`. Si el issue exige algo de "tiene que consultar" (schema, dependencias, API pública, auth, infra, reglas de negocio) y en el issue no consta la aprobación, consultá antes de empezar.

## 3. Implementar

Según el tipo de trabajo:
- **Bug** (`tipo:bug`) → seguí la skill `debug`: reproducir y encontrar la causa raíz antes de escribir el arreglo.
- **Cambio de schema o migraciones** → seguí la skill `db-migration`: el plan con rollback va antes del código.
- Lo demás, directo.

- Seguí las convenciones de `AGENTS.md` y el estilo del código que rodea al cambio.
- Hacé solo lo que pide el issue. Lo que encuentres fuera de alcance va a un issue nuevo (skill `crear-issue`), no a este PR.
- Commits chicos con Conventional Commits (`docs/convencion-nombres-github.md` §2); en el último o en el cuerpo del PR, `Closes #<n>`.

## 4. Tests

- Agregá o ajustá tests que cubran el cambio: el bug reproducido antes del arreglo, o los criterios de aceptación de la feature.
- Corré los comandos de test, typecheck y lint de `AGENTS.md`. Si algo falla, arreglalo; no lo saltees ni lo desactives.
- Si un test fallaba antes de tu cambio, verificalo en `<RAMA_BASE>` y decilo en el PR en vez de taparlo.

## 5. Autorevisión

Revisá el diff completo contra `<RAMA_BASE>` antes de abrir el PR:

- Si está disponible el comando `/code-review`, corrélo sobre la rama y resolvé lo que encuentre.
- Si no, revisá vos: bugs, casos borde, código muerto, secretos, archivos que no deberían estar.

Además:
```bash
python3 scripts/agentes/mapa.py
```
Si dice que tocaste **rutas sensibles**, corré `/security-review` (si está disponible) o revisá a mano auth, permisos, inputs, secretos y exposición de datos, y confirmá que la aprobación de Autonomía consta.

Lo que decidas no corregir, explicalo en el PR.

## 6. Docs

Seguí la skill `update-docs` (modo 1): `mapa.py` te dice qué docs revisar, y `check-docs.py` valida que no queden links ni rutas rotas. Los docs van **en el mismo PR** que el código: si se dejan para después, el próximo agente lee algo falso. Si no hace falta tocar docs, decí por qué en el PR.

## 7. Abrir el PR

```bash
git push -u origin HEAD
gh pr create --base <RAMA_BASE> --title "<tipo>(<scope>): <descripcion>" --body-file <archivo> \
  --label "tipo:..." --label "area:..."
```

- Título: Conventional Commits, ≤ 72 caracteres (lo valida `pr-title.yml`).
- Cuerpo: `.github/pull_request_template.md` completo. En "Cómo probarlo", los comandos que corriste y su resultado.
- Labels: exactamente un `tipo:` (copialo del issue), 1–2 `area:`, ningún `prioridad:`, más `logica-negocio` o `breaking-change` si corresponden.
- `Closes #<n>` en el cuerpo.

## 8. Esperar el CI y entregar

Mirá los checks del PR (`gh pr checks <pr> --watch`). Si alguno falla por tu cambio, corregilo y pusheá de nuevo. Si falla por algo ajeno, decilo.

Respondé con:
- Link al PR y estado del CI.
- Qué cambió, en dos o tres líneas.
- Qué decisiones tomaste que el revisor tiene que mirar.
- Qué issues se van a desbloquear al mergear (lo imprimió `preparar.sh` en "Bloquea a").

Sugerí el paso siguiente: revisar el PR con `/review-pr <n>`, idealmente desde **otra sesión** (quien implementó tiende a leer lo que quiso escribir).

Y frená. El merge lo hace una persona.

## Si hay que soltar el issue

Si no podés terminar (bloqueo nuevo, decisión pendiente, alcance mucho mayor del que dice el issue): comentá en el issue qué hiciste y qué falta, pusheá la rama si tiene algo útil y desasignate (`gh issue edit <n> --remove-assignee @me`). Así `disponibles.sh` lo vuelve a mostrar.
