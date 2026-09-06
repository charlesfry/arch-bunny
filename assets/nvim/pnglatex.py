"""bunny's pnglatex - replaces the abandoned PyPI pnglatex package (broken on
Python >= 3.13) with a minimal, owned implementation.

Installed into the Neovim provider venv's site-packages by
install/45-nvim-notebook.sh; it is deliberately NOT pip-installed, because the
PyPI package of this name is the broken one it replaces.

molten-nvim renders text/latex output chunks via `from pnglatex import
pnglatex`; this module keeps that one-function interface. Output is themed
for a dark terminal — transparent background, light foreground — via
dvipng, the same mechanism the reference setup (dubrayn's molten fork)
uses. Failures are raised as ValueError because that is the exception
molten's _from_latex catches; anything else would crash MoltenTick.
"""
import subprocess
import tempfile
from pathlib import Path

_TEMPLATE = r"""\documentclass{article}
\usepackage{amsmath,amssymb}
\pagestyle{empty}
\begin{document}
%s
\end{document}
"""

# Matches kitty's default light-on-dark foreground. Transparent background so
# the terminal theme shows through.
_FG = "rgb 0.87 0.87 0.87"


def pnglatex(tex, output_path):
    with tempfile.TemporaryDirectory() as tmp:
        Path(tmp, "eq.tex").write_text(_TEMPLATE % tex)
        try:
            subprocess.run(
                ["latex", "-interaction=nonstopmode", "-halt-on-error", "eq.tex"],
                cwd=tmp, capture_output=True, check=True)
            subprocess.run(
                ["dvipng", "-D", "200", "-T", "tight",
                 "-bg", "Transparent", "-fg", _FG,
                 "-o", str(output_path), "eq.dvi"],
                cwd=tmp, capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            raise ValueError(f"latex render failed: {e}") from e
    return output_path
