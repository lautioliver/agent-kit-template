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
- Issues abiertos relacionados (`gh issue list --search …`) y `.claude/skills/crear-issue/disponibles.sh`.

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
- Si hay decisiones pendientes o un ADR por escribir, son el primer issue y bloquean al resto.
- Las migraciones destructivas en dos pasos (expand / contract) son dos issues.

## 4. Crear

Usá `planificar.py` de la skill `crear-issue` (sección "Planificar un trabajo grande"). El **plan técnico completo va en el cuerpo de la épica**: así queda junto a los issues y lo lee `/implement-issue` al tomar cada uno. No crees un documento aparte en `docs/` salvo que sea un ADR.

```bash
.claude/skills/crear-issue/planificar.py <plan.json> --borrador   # validar y mostrar
.claude/skills/crear-issue/planificar.py <plan.json>              # crear, tras el "sí"
```

## 5. Entregar

Link a la épica, los issues en orden y qué se puede empezar ya (`disponibles.sh`). El siguiente paso es `/implement-issue <n>` sobre el primero disponible.
