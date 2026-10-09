---
skill: implement-issue
issue: 87
pr: sin PR
area: docs
rutas: prueba-sensible/LEEME.md
skill_sha: 1da16c8487540d9f07bdfe696e319bf138ca3d67
fecha: 2026-10-09
modelo: haiku
rol: implementador-liviano
agente_sha: baeed63244b476905bb4aa29877d709c541a48e5
---
**Desvíos:** escalé por la regla 1 (ruta sensible). El issue es tipo:docs, pero el único LEEME de pruebas de la raíz es `prueba-sensible/LEEME.md`, y `prueba-sensible/**` es categoría `prueba` en `docs/mapa-agentes.json`. Edité antes de correr `mapa.py` sobre el destino: sin cambios, `mapa.py` no mira el archivo y da "ninguna". Lo verifiqué después del cambio. Commiteé la línea en WIP y no abrí PR.
**Decisiones no cubiertas:** "carpeta de pruebas de la raíz" no decía qué carpeta; la resolví por lo que había en el repo. Sin decisión humana, no la confirmé.
**Lo que encontró la revisión:** no corrí `/code-review` porque escalé antes del PR.
**Propuesta:** antes de editar, cruzar las rutas que nombra el issue con `docs/mapa-agentes.json` (no solo con el tipo del issue). La plantilla de la retro no tiene `agente_sha` ni `skill_sha`, que el contrato pide; los agregué a mano.
