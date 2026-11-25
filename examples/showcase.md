---
title: MD Buddy feature showcase
author: Contextual Dynamics Lab
tags: [markdown, quicklook, demo]
---

# MD Buddy Feature Showcase

A tour of everything the Quick Look preview renders. Press <kbd>Space</kbd> on this file in Finder.

## Text styling

Plain text, **bold**, *italic*, ***bold italic***, ~~strikethrough~~, `inline code`,
<u>underline</u>, <mark>highlight</mark>, H<sub>2</sub>O, E = mc<sup>2</sup>, and a
<abbr title="HyperText Markup Language">HTML</abbr> abbreviation.

Autolinks work too: https://commonmark.org and <https://github.github.com/gfm/>.
Jump to [the tables section](#tables) or read a footnote.[^1]

> Blockquotes can contain **formatting**,
> `code`, and
>
> > nested quotes.

---

## Lists

1. First ordered item
2. Second item
   - Nested bullet
   - Another one
     1. Deeper still
3. Third item

- [x] Write the renderer
- [x] Add syntax highlighting
- [ ] Take over the world

## Tables

| Feature        | Supported | Notes                          |
|:---------------|:---------:|-------------------------------:|
| GFM tables     | ✅        | with column alignment          |
| Task lists     | ✅        | rendered as checkboxes         |
| Raw HTML       | ✅        | scripts are blocked            |
| Footnotes      | ✅        | see the bottom of the page     |

## Code

```python
from dataclasses import dataclass

@dataclass
class Preview:
    path: str
    size: int = 0

    def describe(self) -> str:
        """Return a human-readable summary."""
        return f"{self.path} ({self.size:,} bytes)"
```

```swift
struct Greeting {
    let name: String
    func render() -> String { "Hello, \(name)!" }
}
```

```bash
make install   # build, install, and register the extension
qlmanage -r    # reset Quick Look
```

```
A fenced block with no language stays plain.
```

## Images

![A local PNG](images/landscape.png)

<p align="center"><img src="images/diagram.svg" alt="An SVG diagram" width="360"></p>

Remote images can't load inside Quick Look (macOS gives previews no network access), so they
appear as a labelled placeholder: ![Markdown logo](https://raw.githubusercontent.com/github/explore/main/topics/markdown/markdown.png)

## Alerts

> [!NOTE]
> Useful information that users should know.

> [!TIP]
> Press <kbd>⌘</kbd> <kbd>+</kbd> in Quick Look to zoom.

> [!WARNING]
> Scripts inside Markdown never run.

## Math

Inline math such as $e^{i\pi} + 1 = 0$ and $\hat{\beta} = (X^\top X)^{-1} X^\top y$ sits in the
text. Prices like $5 and $10 are left alone, and so is code: `$PATH`.

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
\qquad
\sum_{k=1}^{n} k = \frac{n(n+1)}{2}
$$

$$
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\
\nabla \times \mathbf{B} &= \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{aligned}
$$

## HTML blocks

<details>
<summary>Click to expand</summary>

Hidden content with **Markdown** inside.

</details>

<dl>
  <dt>Definition list</dt>
  <dd>Rendered from raw HTML.</dd>
</dl>

<script>document.body.innerHTML = "script ran (this should never appear)";</script>

### Heading level 3
#### Heading level 4
##### Heading level 5
###### Heading level 6

[^1]: Footnotes are collected at the end of the document.
