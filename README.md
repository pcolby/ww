# Workflow Waterfall

A really basic Bash script for generating [GitHub Actions] workflow runs waterfall charts in
[Mermaid] Gantt charts format.

## Prerequisites

WW requires a working stallation of the `gh` CLI too.

## Usage

Download the `ww.sh` script, and execute as either:

```sh
ww.sh <run-url> > mermaid.txt
```

or 

```sh
ww.sh <owner> <repo> <run_id> [<attempt_number>] > mermaid.txt
```

The resulting `mermaid.txt` can then be rendered by any tool that supports [Mermaid] diagrams.


[GitHub Actions]: https://github.com/features/actions
[Mermaid]:        https://mermaid.js.org/ "Mermaid Diagramming and charting tool"
