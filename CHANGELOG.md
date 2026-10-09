# Changelog

Cambios de la plantilla por versión. `scripts/actualizar.py` muestra las secciones nuevas al actualizar un proyecto. Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones: [SemVer](https://semver.org/lang/es/). Este archivo es de la plantilla: el init lo borra.

**Publicar una versión** (lo hace una persona): un PR que sube `VERSION` y agrega su sección acá; después del merge, `git tag vX.Y.Z` sobre ese commit y `git push origin vX.Y.Z`. Así `VERSION` en `main` coincide con el último tag.

## 0.9.0

Primera versión con número: desde acá, un proyecto puede traer las siguientes con `python3 scripts/actualizar.py`.

- Reglas para agentes (`AGENTS.md`), autonomía y rutas sensibles.
- Skills de issue a PR con TDD, revisión, épicas, bloqueos y retros.
- Orquestador con subagentes por modelo y asignación automática al equipo.
- Modo chico y `crecer.py` para pasar al completo.
