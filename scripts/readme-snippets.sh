#!/usr/bin/env bash
# Copy code from tested example files into an SDK's README, so README examples
# can't drift from code that CI compiles and runs.
#
#   scripts/readme-snippets.sh <sdk-dir>
#
# In README.md:
#
#   <!-- phasetwo:snippet quickstart examples/quickstart.py -->
#   ```python
#   (replaced on every run)
#   ```
#   <!-- /phasetwo:snippet -->
#
# In the example file (any comment style: //, #, --):
#
#   # snippet:start quickstart
#   ...code shown in the README...
#   # snippet:end quickstart
#
# The region is dedented. The code-fence language comes from the file extension.
# generate.sh runs this, so the SDK's drift check fails if a README snippet
# doesn't match its example file. Missing files or regions are errors.
set -euo pipefail

sdk=${1:?usage: readme-snippets.sh <sdk-dir>}
readme="$sdk/README.md"
[ -f "$readme" ] || exit 0
grep -q '<!-- phasetwo:snippet ' "$readme" || exit 0

python3 -I - "$sdk" <<'PY'
import os, re, sys, textwrap

sdk = sys.argv[1]
readme = os.path.join(sdk, "README.md")
LANG = {".java": "java", ".ts": "ts", ".js": "js", ".py": "python", ".go": "go",
        ".kts": "kotlin", ".gradle": "groovy", ".xml": "xml", ".sh": "sh"}
block = re.compile(
    r"(<!-- phasetwo:snippet (?P<name>[\w.-]+) (?P<path>[^ ]+) -->\n)(?P<body>.*?)(<!-- /phasetwo:snippet -->)",
    re.S)

def region(path, name):
    full = os.path.join(sdk, path)
    if not os.path.isfile(full):
        sys.exit(f"readme-snippets: {path} not found (snippet {name})")
    lines = open(full, encoding="utf-8").read().splitlines()
    start = re.compile(r"^\s*(//|#|--)\s*snippet:start\s+%s\s*$" % re.escape(name))
    end = re.compile(r"^\s*(//|#|--)\s*snippet:end\s+%s\s*$" % re.escape(name))
    try:
        i = next(n for n, l in enumerate(lines) if start.match(l))
        j = next(n for n in range(i + 1, len(lines)) if end.match(lines[n]))
    except StopIteration:
        sys.exit(f"readme-snippets: no 'snippet:start/end {name}' region in {path}")
    return textwrap.dedent("\n".join(lines[i + 1:j])).strip("\n")

def render(m):
    name, path = m["name"], m["path"]
    lang = LANG.get(os.path.splitext(path)[1], "")
    return f"{m.group(1)}```{lang}\n{region(path, name)}\n```\n{m.group(5)}"

text = open(readme, encoding="utf-8").read()
new = block.sub(render, text)
if new != text:
    open(readme, "w", encoding="utf-8").write(new)
    print(f"readme-snippets: updated {readme}")
PY
