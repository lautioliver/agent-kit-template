"""Tests de las barandas: qué comandos frena el hook antes de que el agente los corra (#92)."""
import json
import os
import subprocess
import sys
import unittest

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from barandas import motivo  # noqa: E402


TAGS = {"v1.0.0", "1.0.0", "2024.10"}


def frena(comando, rama="claude/1-x"):
    return motivo(comando, rama_actual=lambda cwd: rama, es_tag=lambda nombre, cwd: nombre in TAGS)


class Bloquea(unittest.TestCase):
    def assertFrena(self, comando, **kw):
        self.assertIsNotNone(frena(comando, **kw), f"debería frenar: {comando}")

    def test_mergear_un_pr(self):
        self.assertFrena("gh pr merge 12 --merge")
        self.assertFrena("gh pr merge --squash --auto")
        self.assertFrena("gh -R a/b pr merge 3")

    def test_mergear_por_la_api(self):
        self.assertFrena("gh api -X PUT repos/a/b/pulls/12/merge")
        self.assertFrena("gh api repos/{owner}/{repo}/pulls/12/merge -f merge_method=squash")
        self.assertFrena("gh api repos/a/b/merges -f base=main -f head=x")
        self.assertFrena("gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'")
        self.assertFrena("gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'")

    def test_aprobar_un_pr(self):
        self.assertFrena("gh pr review 12 --approve")
        self.assertFrena("gh pr review 12 -a -b ok")

    def test_push_a_una_rama_troncal(self):
        for c in ("git push origin main", "git push origin HEAD:main", "git push origin x:refs/heads/main",
                  "git push -f origin develop", "git push origin +HEAD:master", "git push origin --delete main",
                  "git push origin :main", "git -C ../otro push origin main"):
            self.assertFrena(c)

    def test_push_de_la_rama_actual_si_es_troncal(self):
        self.assertFrena("git push", rama="main")
        self.assertFrena("git push origin HEAD", rama="main")
        self.assertFrena("git push -u origin develop", rama="develop")

    def test_push_masivo(self):
        for c in ("git push --all origin", "git push --mirror origin", "git push --tags", "git push --follow-tags origin x"):
            self.assertFrena(c)

    def test_tags(self):
        self.assertFrena("git tag v1.0.0")
        self.assertFrena("git tag -a v1.0.0 -m 'versión'")
        self.assertFrena("git tag -d v1.0.0")
        self.assertFrena("git push origin refs/tags/v1.0.0")
        self.assertFrena("gh api repos/a/b/git/refs -f ref=refs/tags/v1 -f sha=abc")

    def test_releases(self):
        self.assertFrena("gh release create v1.0.0 --notes x")
        self.assertFrena("gh release delete v1.0.0")
        self.assertFrena("gh release edit v1.0.0 --draft=false")
        self.assertFrena("gh api -X POST repos/a/b/releases -f tag_name=v1")

    def test_saltear_checks(self):
        self.assertFrena("git commit --no-verify -m x")
        self.assertFrena("git commit -n -m x")
        self.assertFrena("git push --no-verify origin claude/1-x")

    def test_tocar_la_proteccion_de_ramas(self):
        self.assertFrena("gh api -X DELETE repos/a/b/branches/main/protection")
        self.assertFrena("gh api -X PUT repos/a/b/branches/main/protection --input p.json")
        self.assertFrena("gh api -X DELETE repos/a/b/rulesets/4")

    def test_dentro_de_comandos_compuestos(self):
        for c in ("git status && gh pr merge 1", "true; gh pr merge 1", "false || gh pr merge 1",
                  "echo 1 | xargs gh pr merge", "echo $(gh pr merge 1)", 'echo "$(gh pr merge 1)"',
                  "echo `gh pr merge 1`", "bash -c 'gh pr merge 1'", "sh -c \"git push origin main\"",
                  "eval 'gh pr merge 1'", "GH_TOKEN=x gh pr merge 1", "env A=1 gh pr merge 1",
                  "command gh pr merge 1", "(cd x && gh pr merge 1)", "gh pr merge 1 &", "x\ngh pr merge 1"):
            self.assertFrena(c)

    def test_cd_cambia_la_rama_que_mira(self):
        visto = []

        def rama(cwd):
            visto.append(cwd)
            return "main" if cwd and cwd.endswith("principal") else "claude/1-x"
        self.assertIsNotNone(motivo("cd /r/principal && git push", rama_actual=rama, cwd="/r/wt"))
        self.assertIsNone(motivo("git push", rama_actual=rama, cwd="/r/wt"))


class CasosDeLaRevision(unittest.TestCase):
    """Hallazgos de /code-review: lo que se escapaba y lo que frenaba de más."""

    def test_un_apostrofo_no_desactiva_el_hook(self):
        for c in ("gh pr merge 5 # it's ready", "# let's merge\ngh pr merge 5", "echo $'a\\'b'; gh pr merge 1",
                  "echo \"it's\"; gh pr merge 1"):
            self.assertIsNotNone(frena(c), c)

    def test_un_cd_a_un_directorio_que_no_existe_no_rompe_el_hook(self):
        def rama(cwd):
            if cwd and not __import__("os").path.isdir(cwd):
                raise FileNotFoundError(cwd)
            return "main"
        self.assertIsNotNone(motivo('cd "$CLAUDE_PROJECT_DIR" && git push origin HEAD', rama_actual=rama, cwd="/tmp"))
        self.assertIsNotNone(motivo("mkdir w && cd w && git push", rama_actual=rama, cwd="/tmp"))

    def test_continuacion_de_linea(self):
        self.assertIsNotNone(frena("git push origin \\\n  main"))

    def test_shells_y_envoltorios_con_opciones(self):
        for c in ("bash -lc 'gh pr merge 1'", "timeout 60 git push origin main", "nice -n 10 git push origin main",
                  "echo 1 | xargs -n 1 gh pr merge", "sudo -u x git push origin main", "env -u VAR gh pr merge 1"):
            self.assertIsNotNone(frena(c), c)

    def test_metodo_pegado_a_la_opcion(self):
        self.assertIsNotNone(frena("gh api -XPUT repos/a/b/pulls/1/merge"))
        self.assertIsNotNone(frena("gh api -XDELETE repos/a/b/branches/main/protection"))

    def test_mover_una_rama_troncal_por_la_api(self):
        self.assertIsNotNone(frena("gh api -X PATCH repos/a/b/git/refs/heads/main -f sha=abc -F force=true"))
        self.assertIsNone(frena("gh api -X PATCH repos/a/b/git/refs/heads/claude/1-x -f sha=abc"))

    def test_tags_con_cualquier_nombre(self):
        self.assertIsNotNone(frena("git push origin 1.0.0"))
        self.assertIsNotNone(frena("git push origin tag 2024.10"))
        self.assertIsNone(frena("git push origin v2-docs"))

    def test_no_verify_abreviado_o_por_config(self):
        for c in ("git commit --no-verif -m x", "git push --no-veri origin x", "git -c core.hooksPath=/dev/null commit -m x"):
            self.assertIsNotNone(frena(c), c)
        for c in ("git commit -uno -m x", "git log --grep=x -- --no-verify", "git grep -- --no-verify",
                  "git commit -am 'sin -n'", "git tag --sort version:refname"):
            self.assertIsNone(frena(c), c)

    def test_here_string_y_heredoc_con_guion(self):
        self.assertIsNotNone(frena('cat <<< "x"\ngh pr merge 1'))
        self.assertIsNone(frena("cat > b.md <<'END-MSG'\ngit push origin main\nEND-MSG"))

    def test_opciones_con_valor_y_comentarios_en_el_push(self):
        self.assertIsNotNone(frena("git push -o ci.skip origin", rama="main"))
        self.assertIsNotNone(frena("git push origin $(git branch --show-current)", rama="main"))
        self.assertIsNone(frena("git push origin feat # not main"))


class Permite(unittest.TestCase):
    def assertPermite(self, comando, **kw):
        self.assertIsNone(frena(comando, **kw), f"no debería frenar: {comando}")

    def test_lo_de_todos_los_dias(self):
        for c in ("git status", "git push origin HEAD", "git push -u origin HEAD", "git push",
                  "git push origin claude/92-x", "git push --force-with-lease origin claude/1-x",
                  "git push origin --delete claude/15-x", "git branch -D claude/15-x && git push origin --delete claude/15-x",
                  "git push -q origin abc123:refs/heads/agentes/retros", "git fetch origin main", "git merge origin/main",
                  "git commit -m 'no usar gh pr merge'", "gh pr view 12", "gh pr create --base main --body-file b.md",
                  "gh pr checks 12 --watch", "gh pr review 12 --comment -b ok", "gh pr review 12 --request-changes -b x",
                  "gh api repos/a/b/pulls/12/merge", "gh api repos/a/b/branches/main/protection",
                  "gh api repos/a/b/releases", "gh release view v1", "gh release list",
                  "git tag", "git tag -l", "git tag --sort=-v:refname", "git tag --list 'v*'", "git tag --contains abc", "git log --oneline",
                  "gh issue comment 3 --body 'no corras gh pr merge'", "grep -rn 'gh pr merge' .",
                  "echo 'git push origin main'", "rg \"git tag v1\""):
            self.assertPermite(c)

    def test_texto_de_un_heredoc(self):
        self.assertPermite("cat > b.md <<'EOF'\ngh pr merge 1\ngit push origin main\nEOF\ngh pr create --body-file b.md")

    def test_comando_vacio_o_raro(self):
        self.assertPermite("")
        self.assertPermite("echo 'sin cerrar")


class Hook(unittest.TestCase):
    """El script como lo corre Claude Code: JSON por stdin, exit 2 y stderr si frena."""

    def correr(self, entrada):
        return subprocess.run([sys.executable, os.path.join(AQUI, "barandas.py")], input=json.dumps(entrada),
                              capture_output=True, text=True)

    def test_frena_con_exit_2_y_dice_que_hacer(self):
        r = self.correr({"tool_name": "Bash", "tool_input": {"command": "gh pr merge 1"}, "cwd": AQUI})
        self.assertEqual(r.returncode, 2)
        self.assertIn("! gh pr merge 1", r.stderr)
        self.assertIn("AGENTS.md", r.stderr)

    def test_deja_pasar_con_exit_0(self):
        r = self.correr({"tool_name": "Bash", "tool_input": {"command": "gh pr view 1"}, "cwd": AQUI})
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_otra_herramienta_pasa(self):
        r = self.correr({"tool_name": "Read", "tool_input": {"file_path": "x"}})
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_entrada_rota_no_traba_al_agente(self):
        r = subprocess.run([sys.executable, os.path.join(AQUI, "barandas.py")], input="no es json",
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


class Config(unittest.TestCase):
    def test_settings_registra_el_hook_para_bash(self):
        raiz = os.path.dirname(os.path.dirname(AQUI))
        with open(os.path.join(raiz, ".claude", "settings.json"), encoding="utf-8") as f:
            cfg = json.load(f)
        hooks = [h for g in cfg["hooks"]["PreToolUse"] if g["matcher"] == "Bash" for h in g["hooks"]]
        self.assertTrue(any("scripts/agentes/barandas.py" in h["command"] for h in hooks))


if __name__ == "__main__":
    unittest.main()
