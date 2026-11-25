#!/usr/bin/env python3
"""Build examples/notebook.ipynb and execute it for real, so its outputs are genuine.

The notebook covers what MD Buddy's notebook preview has to handle: Markdown with math and an
attached image, a pandas table, a styled table, PNG and SVG figures, stdout and stderr, an
exception, Markdown / LaTeX / JSON outputs, an output that only works with JavaScript, and a
raw cell.

Needs: nbformat, nbclient, ipykernel, numpy, pandas, matplotlib, jinja2 (scripts/requirements.txt).
Usage: python scripts/make_example_notebook.py
"""
import base64
import io
import sys
from pathlib import Path

import nbformat
from nbclient import NotebookClient
from nbformat.v4 import new_code_cell, new_markdown_cell, new_notebook, new_raw_cell

OUT = Path(__file__).resolve().parent.parent / "examples" / "notebook.ipynb"


def attachment_png() -> str:
    """A small bar-chart icon, drawn with matplotlib, as base64 PNG."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(1.6, 1.0), dpi=100)
    ax.bar(["a", "b", "c"], [3, 5, 2], color=["#0969da", "#1a7f37", "#bf8700"])
    ax.set_axis_off()
    buffer = io.BytesIO()
    fig.savefig(buffer, format="png", bbox_inches="tight", transparent=True)
    plt.close(fig)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


INTRO = r"""# A small analysis

This notebook is MD Buddy's example for **Jupyter notebook previews**. Every output below was
produced by running the notebook (`scripts/make_example_notebook.py`).

The sample mean is $\bar{x} = \frac{1}{n}\sum_{i=1}^{n} x_i$, and prices like $5 and $10 are
left alone. A display equation:

$$
\hat{\beta} = (X^\top X)^{-1} X^\top y
$$

Jupyter also typesets a LaTeX environment written without dollar signs:

\begin{align}
y_i &= \beta_0 + \beta_1 x_i + \varepsilon_i \\
\varepsilon_i &\sim \mathcal{N}(0, \sigma^2)
\end{align}

| Cell type | Shown as |
|:--|:--|
| Markdown | formatted text |
| Code | highlighted source and its outputs |
"""

ATTACHED = """## An attached image

Images pasted into a cell are stored inside the notebook: ![a small bar chart](attachment:bars.png)
"""

CELLS = [
    """import sys
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

rng = np.random.default_rng(7)
x = np.linspace(0, 10, 60)
y = 1.5 + 0.8 * x + rng.normal(0, 1.2, x.size)
df = pd.DataFrame({"x": x, "y": y, "group": np.where(x < 5, "low", "high")})
print(f"{len(df)} observations")""",
    "df.head()",
    """summary = df.groupby("group")[["x", "y"]].agg(["mean", "std"]).round(2)
summary.style.background_gradient(cmap="Blues").format("{:.2f}")""",
    """slope, intercept = np.polyfit(df.x, df.y, 1)
fig, ax = plt.subplots(figsize=(6, 3.2))
ax.scatter(df.x, df.y, s=14, alpha=0.7, label="data")
ax.plot(df.x, intercept + slope * df.x, color="crimson", label=f"fit: y = {intercept:.2f} + {slope:.2f}x")
ax.set(xlabel="x", ylabel="y", title="Least-squares fit")
ax.legend()
plt.show()""",
    """%config InlineBackend.figure_formats = ['svg']
fig, ax = plt.subplots(figsize=(4, 2.2))
ax.hist(df.y - (intercept + slope * df.x), bins=12, color="#0969da")
ax.set_title("Residuals (SVG output)")
plt.show()
%config InlineBackend.figure_formats = ['png']""",
    """print("written to stdout")
print("a warning written to stderr", file=sys.stderr)""",
    """from IPython.display import JSON, Markdown, Math, display

display(Markdown(f"The fitted slope is **{slope:.3f}**, so $\\\\hat{{y}} = {intercept:.2f} + {slope:.2f}x$."))
display(Math(r"R^2 = 1 - \\frac{\\sum_i (y_i - \\hat{y}_i)^2}{\\sum_i (y_i - \\bar{y})^2}"))
display({"application/json": {"slope": round(float(slope), 3), "intercept": round(float(intercept), 3), "n": len(df)}}, raw=True)""",
    """import base64, io

buffer = io.BytesIO()
fig, ax = plt.subplots(figsize=(4, 1.6))
ax.plot(df.x, np.sin(df.x), color="#8250df")
ax.set_title("Static fallback of an interactive output")
fig.savefig(buffer, format="png", bbox_inches="tight")
plt.close(fig)

# What an interactive plotting library emits: HTML that draws only if its script runs,
# plus a static image for viewers that cannot run scripts.
display({
    "text/html": '<div id="interactive-plot"></div><script>drawInteractivePlot("interactive-plot")</script>',
    "image/png": base64.b64encode(buffer.getvalue()).decode("ascii"),
}, raw=True)""",
    """def fit(values):
    return np.polyfit(values, df.y, 1)

fit(df.x[:10])  # ten x values against sixty y values""",
]

RAW = "A raw cell: shown exactly as typed, with no *formatting* and no $math$."


def main() -> None:
    notebook = new_notebook()
    notebook.metadata["kernelspec"] = {"display_name": "Python 3", "language": "python", "name": "python3"}
    intro = new_markdown_cell(INTRO)
    attached = new_markdown_cell(ATTACHED)
    attached["attachments"] = {"bars.png": {"image/png": attachment_png()}}
    notebook.cells = [intro, attached] + [new_code_cell(source) for source in CELLS] + [new_raw_cell(RAW)]

    # The last code cell raises on purpose; keep going so the traceback is recorded.
    client = NotebookClient(notebook, timeout=120, kernel_name="python3", allow_errors=True)
    client.execute()

    for cell in notebook.cells:
        cell.pop("id", None)
        cell.metadata.pop("execution", None)
    notebook.nbformat_minor = 4
    nbformat.validate(notebook)
    OUT.write_text(nbformat.writes(notebook) + "\n", encoding="utf-8")

    kinds = sorted({output.output_type for cell in notebook.cells if cell.cell_type == "code" for output in cell.outputs})
    print(f"{OUT}: {OUT.stat().st_size / 1024:.0f} KB, {len(notebook.cells)} cells, outputs: {', '.join(kinds)}")
    if "error" not in kinds:
        sys.exit("expected the last code cell to raise")


if __name__ == "__main__":
    main()
