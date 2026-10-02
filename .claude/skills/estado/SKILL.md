---
name: estado
description: Resume en segundos el estado actual del proyecto (versión, flujo de ramas, trabajo en curso, épicas, PRs, deuda, decisiones recientes, migraciones pendientes), generado en el momento desde git, GitHub y los docs. Usar con "/estado", "¿en qué estado está el proyecto?", "poneme al día" o al empezar una sesión nueva.
---

# Estado del proyecto

```bash
.claude/skills/estado/estado.sh
```

Genera el resumen en el momento desde las fuentes (git, issues, PRs, ADRs, `docs/mapa-agentes.json`). **No se guarda en un archivo a propósito**: un resumen commiteado envejece apenas nadie lo regenera y pasa a decir algo falso con aspecto oficial.

Al responder:
- Mostrá la salida y, si el usuario quiere más, profundizá con las fuentes que cita (`architecture.md`, la épica, el ADR).
- Si algo se ve raro (un PR viejo abierto, un crítico sin asignar, una release abierta hace semanas), mencionalo en una línea.
- Para "¿qué hago ahora?", seguí con `.claude/skills/crear-issue/disponibles.sh`.
