---
name: plan-feature
description: Convierte una idea o feature grande en un plan técnico investigado y después en una épica con issues y dependencias. No escribe código. Usar con "/plan-feature", "planificá X", "quiero hacer X, ¿cómo lo encaramos?" o antes de cualquier trabajo que no entre en un solo PR.
---

# Planificar una feature

Evita empezar a programar demasiado pronto. Primero se entiende qué hay, después se decide, y recién al final se parte en issues. **Esta skill no toca código.**

## 1. Investigar

Antes de proponer nada, leé:
- `docs/development/architecture.md`, `docs/reference/` (dominio, módulos, superficies) y los ADRs relacionados.
- El código de los módulos que se van a tocar: cómo está hecho hoy, no cómo debería estar.
- `docs/development/roadmap.md` y `horizon.md`: ¿ya estaba pensado? ¿choca con algo?
- Issues abiertos relacionados (`gh issue list --search …`) y `.claude/skills/estado/disponibles.sh`.

Si la idea es vaga en algo que cambia el diseño (quién la usa, qué pasa en los casos límite), preguntá ahora, antes de escribir el plan.

## 2. Plan técnico

Escribilo con estas secciones. Concreto: archivos y módulos reales, no genéricos.

```markdown
## Objetivo
Qué se logra y para quién. Qué queda explícitamente afuera.

## Estado actual
Cómo funciona hoy lo que se va a tocar (con rutas).

## Componentes afectados
Módulos, tablas, endpoints, pantallas. Marcar los sensibles (docs/mapa-agentes.json).

## Decisiones necesarias
Lo que hay que decidir antes de construir, con opciones y recomendación.
Las difíciles de revertir → proponer ADR.

## Riesgos
Qué puede salir mal (datos, dinero, seguridad, rendimiento, usuarios activos) y cómo se mitiga.

## Migraciones
Cambios de schema y su estrategia (skill db-migration). "Ninguna" si no hay.

## Tests
Qué hay que probar y en qué nivel.

## Issues
La división en PRs, en orden, con sus bloqueos.
```

**Mostrá el plan y frená.** Las decisiones de la sección "Decisiones necesarias" las toma el usuario o el equipo, no el agente. Iterá hasta que lo apruebe.

## 3. Partir en issues

Con el plan aprobado:
- Cada issue = un PR que se revisa solo y deja el sistema funcionando. Típicamente 3 a 8.
- Bloqueos solo donde de verdad hay orden (schema → API → pantalla). Lo paralelo, sin bloqueo.
- Si hay decisiones pendientes o un ADR por escribir, son el primer issue y **se cargan como bloqueo** (`bloqueado_por`) de los issues que dependen de esa decisión. Que la épica lo diga en el texto no alcanza: `preparar.sh` solo ve los bloqueos cargados.
- Ningún issue sale con valores sin definir ("una ventana razonable", "un límite adecuado"): o el plan los fija, o el issue lleva una sección **Decisiones abiertas** con la pregunta concreta para el equipo.
- Las migraciones destructivas en dos pasos (expand / contract) son dos issues.

## 4. Crear

El **plan técnico completo va en el cuerpo de la épica**: así queda junto a los issues y lo lee `/implement-issue` al tomar cada uno. No crees un documento aparte en `docs/` salvo que sea un ADR. Se crea con `planificar.py` (en esta carpeta; requiere `python3`):

1. **Escribir el plan** en un JSON temporal (fuera del repo):
   ```json
   {
     "epica": {"titulo": "Migrar cuentas a la tabla nueva", "cuerpo": "## Objetivo\n…", "labels": ["tipo:feature", "area:api"]},
     "issues": [
       {"clave": "schema", "titulo": "Crear la tabla de cuentas", "cuerpo": "…", "labels": ["tipo:task", "area:infra"]},
       {"clave": "api", "titulo": "Exponer las cuentas en la API", "cuerpo": "…", "labels": ["tipo:task", "area:api"],
        "bloqueado_por": ["schema"], "motivo": "necesita la tabla"},
       {"clave": "pantalla", "titulo": "Mostrar las cuentas en el panel", "cuerpo": "…", "labels": ["tipo:feature"],
        "bloqueado_por": ["api", 25], "motivo": "consume el endpoint; #25 define el diseño"}
     ]
   }
   ```
   `bloqueado_por` acepta claves del plan o números de issues existentes. Títulos, labels y cuerpos siguen la convención de la skill `crear-issue` (pasos 3–6).
2. **Validar y mostrar el borrador:**
   ```bash
   .claude/skills/plan-feature/planificar.py <plan.json> --borrador
   ```
   Valida labels contra `labels.yml`, exactamente un `tipo:` por issue, claves y números existentes, y que no haya ciclos. Muestra los issues en el orden en que se pueden hacer. Si falla, corregí el plan; no saltees la validación.
   Mostrale al usuario esa salida y pedí un "sí" explícito.
3. **Crear:**
   ```bash
   .claude/skills/plan-feature/planificar.py <plan.json>
   ```
   Crea la épica, cada issue en orden, los vincula como sub-issues, registra los bloqueos, agrega `estado:bloqueado` y la línea `Bloqueado por #N` donde corresponde. Si falla a mitad de camino, informa qué alcanzó a crear: mostralo y no reintentes el plan entero (duplicaría issues); creá solo lo que falta.

## 5. Entregar

Link a la épica, los issues en orden y qué se puede empezar ya (`.claude/skills/estado/disponibles.sh`). El siguiente paso es `/implement-issue <n>` sobre el primero disponible.
