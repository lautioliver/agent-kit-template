---
skill: implement-issue
issue: 50
pr: 57
area: docs, infra
rutas: .gitignore, scripts/test-init.sh, scripts/agentes/check-docs.py, .github/workflows/docs.yml, .claude/skills/mejorar-skills/retro.sh
fecha: 2026-10-09
skill_sha: e2b89e006cb208ba7104111766f746c35aa91cea
---
**Desvíos:** un PR para dos issues (#50 y #52), como pedía la revisión; preparar.sh solo toma uno, el segundo se asignó a mano.
**Decisiones no cubiertas:** el repro del issue (`GIT_CONFIG_GLOBAL=/dev/null`) no reproducía en macOS porque la config del sistema de las Command Line Tools fija init.defaultBranch=main; hizo falta `GIT_CONFIG_NOSYSTEM=1`. Al sumar el paso de tests al CI aparecieron tests que solo valen para la plantilla sin inicializar (test-base.sh, el aviso de test-preparar.sh) y que rompían el CI de cualquier proyecto nuevo: se saltean cuando el init ya reemplazó <RAMA_BASE>. `__pycache__/` con barra no lo ignora `git check-ignore` si la carpeta no existe; quedó sin barra. `"${arr[@]}"` vacío con set -u falla en el bash 3.2 de macOS.
**Lo que encontró la revisión:** /code-review (low): nada.
**Propuesta:** que los test-*.sh se prueben también en un proyecto recién inicializado (completo y chico), no solo en la plantilla: test-init.sh ya arma ese escenario.
