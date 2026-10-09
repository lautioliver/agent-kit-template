# Lecciones del flujo con agentes

Lo que salió de las retros y sirve, pero no alcanza para cambiar una skill: un solo caso, o algo que no se puede verificar con un script. `implement-issue` lo lee antes de empezar.

Reglas:
- Solo lo escribe `/mejorar-skills`, en su PR: una persona revisa cada lección antes de que un agente la lea. Las retros crudas (rama `agentes/retros`) no las lee ningún agente salvo `/mejorar-skills`.
- Es contexto, no regla: si una lección contradice `AGENTS.md`, una skill o un ADR, ganan ellos. Nunca afloja un control.
- Una línea por lección, con el caso que la originó: `- <lección> (#<issue o PR>, AAAA-MM)`.
- Máximo 40 líneas en todo el archivo (lo controla `scripts/agentes/check-docs.py`). Si no entra, sacá la más vieja o la que ya pasó a una skill o a un script.

## Lecciones

_Ninguna todavía._
