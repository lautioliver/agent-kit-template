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
- Si el issue es parte de una épica (`preparar.sh` la muestra), leé la épica entera, sobre todo **Lógica de negocio afectada** y los ADRs pendientes que menciona. Un bloqueo puede estar escrito en el texto sin estar cargado como dependencia: si la épica dice que algo requiere un ADR o una decisión que todavía no existe, decidí con el usuario si este issue cae adentro antes de empezar.
- Leé `AGENTS.md` (convenciones de código y comandos), `docs/agentes/lecciones.md` (lo aprendido en corridas anteriores) y lo que corresponda de `docs/development/architecture.md` y `docs/reference/`.
- Si el issue tiene criterios de aceptación ("Listo cuando", "Criterios de aceptación"), son la definición de terminado.
- Si el issue es ambiguo en algo que cambia el resultado, o contradice un ADR o el código, **preguntá antes de escribir código**. Si el usuario no está, comentá la duda en el issue (`gh issue comment`) y frená.
- Si el cambio toca una regla ya definida (ADR, auditoría, plan), el PR va a llevar `logica-negocio`: anotalo desde ahora.
- Revisá la sección **Autonomía** de `AGENTS.md`. Si el issue exige algo de "tiene que consultar" (schema, dependencias, API pública, auth, infra, reglas de negocio) y en el issue no consta la aprobación, consultá antes de empezar **en un solo mensaje**: qué rutas sensibles toca (`python3 scripts/agentes/mapa.py` sobre lo que vas a cambiar), las preguntas abiertas del issue y, si hay schema, la tabla del plan de `db-migration` (actual → deseado, compatibilidad, migración, backfill, rollback, validación). Una aprobación clara, no tres.

## 3. Tests primero (rojo)

TDD: los tests salen de los **criterios de aceptación** del issue, no del código que vas a escribir. Uno o más por criterio.

- **Bug** (`tipo:bug`) → skill `debug`: el test rojo reproduce el bug. **Schema** → skill `db-migration`: el plan con rollback va antes.
- Si el test necesita algo que no existe (una función, un campo), agregá lo mínimo para que cargue: la firma o un stub que devuelva algo incorrecto. Nada de lógica.
- Corrélos y confirmá que fallan **por la razón correcta**:
  ```bash
  .claude/skills/implement-issue/rojo.sh -- <comando de test, el de `AGENTS.md`, acotado a lo que probás>
  ```
  Si pasan, no prueban nada: reescribilos. Si fallan por un import o un símbolo inexistente, no cuenta: completá el stub. Cada falla tiene que ser una aserción de un criterio.
- **Commiteá los tests en rojo** antes de implementar (`test(<scope>): …`), así el revisor puede volver a ese commit y verlos fallar. Guardá el bloque que deja `rojo.sh` para el PR.
- Sin comportamiento que probar (docs, config) o con una parte que no se puede probar acá (concurrencia real, un proveedor externo): decilo en el PR como **sin test**, con el motivo.

## 4. Implementar (verde)

- Lo mínimo para que los tests pasen, con las convenciones de `AGENTS.md` y el estilo del código que rodea al cambio. Después refactorizá con los tests en verde.
- Hacé solo lo que pide el issue. Lo que encuentres fuera de alcance va a un issue nuevo (skill `crear-issue`).
- Commits chicos con Conventional Commits; `Closes #<n>` en el cuerpo del PR.
- Si un test fallaba antes de tu cambio (no uno de los tuyos), verificalo en `<RAMA_BASE>` y decilo en el PR.

## 5. Autorevisión

Revisá el diff completo contra `<RAMA_BASE>` antes de abrir el PR:

- Si está disponible el comando `/code-review`, corrélo sobre la rama y resolvé lo que encuentre.
- Cada hallazgo que corrijas sigue el mismo ciclo: test que reproduce el hallazgo, `rojo.sh` contra el código actual, arreglo, verde.
- Si no, revisá vos: bugs, casos borde, código muerto, secretos, archivos que no deberían estar.

Además:
```bash
python3 scripts/agentes/mapa.py
```
Si dice que tocaste **rutas sensibles**, corré `/security-review` (si está disponible) o revisá a mano auth, permisos, inputs, secretos y exposición de datos, y confirmá que la aprobación de Autonomía consta. Además revisá a mano las **invariantes de los ADRs** que toca el cambio (lo que no puede pasar nunca: dos ingresos con la misma entrada, un doble cobro…): una revisión de seguridad genérica no las conoce, y es donde suelen estar los errores graves.

Lo que decidas no corregir, explicalo en el PR.

## 6. Docs

Seguí la skill `update-docs` (modo 1): `mapa.py` te dice qué docs revisar, y `check-docs.py` valida que no queden links ni rutas rotas. Los docs van **en el mismo PR** que el código: si se dejan para después, el próximo agente lee algo falso. Si no hace falta tocar docs, decí por qué en el PR.

## 7. Verificar

Última guardia antes del PR, con todo commiteado:

```bash
python3 scripts/agentes/verificar.py
```

Según los archivos cambiados, corre lo configurado en `docs/mapa-agentes.json` (`verificar`): lint, typecheck, tests afectados, drift de migraciones, docs… Si algo falla, arreglalo y volvé a correrlo; nunca desactives una verificación ni la saques del mapa para que pase. Si `verificar.py` o la sección `verificar` del mapa todavía no existen en la rama base (por ejemplo, porque el PR que los agrega no se mergeó), corré a mano lint, typecheck, tests y los controles de `AGENTS.md`, y decilo en el PR. Si avisa que alguna está **sin configurar**, decilo en el PR: ese aspecto no quedó verificado. En "Cómo probarlo" va su resumen.

## 8. Abrir el PR

```bash
git push -u origin HEAD
gh pr create --base <RAMA_BASE> --title "<tipo>(<scope>): <descripcion>" --body-file <archivo> \
  --label "tipo:..." --label "area:..."
```

- Título: Conventional Commits, ≤ 72 caracteres (lo valida `pr-title.yml`).
- Cuerpo: `.github/pull_request_template.md` completo. En "Cómo probarlo", los comandos que corriste y su resultado. En "Cómo probarlo", el bloque **rojo** de `rojo.sh` y el commit de los tests en rojo: sin eso, el revisor no puede comprobar que los tests prueban algo.
- Labels: exactamente un `tipo:` (copialo del issue), 1–2 `area:`, ningún `prioridad:`, más `logica-negocio` o `breaking-change` si corresponden.
- `Closes #<n>` en el cuerpo.

## 9. Esperar el CI y entregar

Mirá los checks del PR (`gh pr checks <pr> --watch`). Si alguno falla por tu cambio, corregilo y pusheá de nuevo. Si falla por algo ajeno, decilo.

Respondé con:
- Link al PR y estado del CI.
- Qué cambió, en dos o tres líneas.
- Qué decisiones tomaste que el revisor tiene que mirar.
- Qué issues se van a desbloquear al mergear (lo imprimió `preparar.sh` en "Bloquea a").

Sugerí el paso siguiente: revisar el PR con `/review-pr <n>`, idealmente desde **otra sesión** (quien implementó tiende a leer lo que quiso escribir).

Y frená. El merge lo hace una persona.

## Retro

Al terminar, guardá una retro corta: formato en `.claude/skills/mejorar-skills/plantilla-retro.md` (o `retro.sh` sin argumentos), con el frontmatter completo, y después `.claude/skills/mejorar-skills/retro.sh <archivo.md>` (la guarda en la rama `agentes/retros`; no toca tu rama). Sé concreto y honesto: una retro que dice "todo bien" cuando hubo desvíos le quita a `/mejorar-skills` la única señal que tiene.

## Si hay que soltar el issue

Si no podés terminar (bloqueo nuevo, decisión pendiente, alcance mucho mayor del que dice el issue): comentá en el issue qué hiciste y qué falta, pusheá la rama si tiene algo útil y desasignate (`gh issue edit <n> --remove-assignee @me`). Así `disponibles.sh` lo vuelve a mostrar.
