# Input matrix

| Backend | Text `:char` | Scroll | Modifiers | Mouse coordinates |
|---|---|---|---|---|
| Cocoa | yes | `:scroll` with `dx`/`dy` | yes | top-left after backend conversion |
| X11 | backend key symbol | backend dependent | backend dependent | top-left |
| Wayland | backend key symbol | `:mouse_scroll` raw event | key modifiers | top-left |
| Termvas | printable byte | SGR wheel as `:scroll` | CSI/SGR bits | terminal cell coordinates |

Twiddle accepts `:char` when available and reconstructs basic ASCII for key
symbols. Backends that do not provide a common event shape should be adapted
by their backend connector before reaching the widget layer.
