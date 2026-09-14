#!/usr/bin/env bash
# list-commands.sh --plugin DIR
# list-commands.sh --selftest | --version | --help
#
# The list `/productizer:help` prints, read from the plugin tree at run time.
#
# TWO SOURCES, BECAUSE THE PLUGIN HAS TWO. A plugin reaches the slash menu from
# `skills/<name>/SKILL.md` AND from `commands/<name>.md`. This list used to walk
# only the first, so the plugin's first `commands/` entry - `upgrade` - was
# installed, typeable, and absent from the one page that claims to list
# everything. Each row now says which source it came from, `skill` or `command`,
# because the two are different files with different frontmatter dialects and a
# reader looking for the file behind a row needs to know where to look.
#
# Nothing is hand-listed. A command's row is built from its own frontmatter -
# `description` and `argument-hint` - and its name is its file name, which is
# how the host names it. A hand-listed row is how the next command goes missing.
#
# Frontmatter is read from the leading `---` block only, so a body line that
# happens to begin `description:` is never mistaken for the real one.
#
# Exit: 0 listed, every entry read
#       2 usage
#       3 neither skills/ nor commands/ under --plugin - nothing was listed, and
#         an empty list from a wrong path is not a plugin with no commands
#       4 listed, but at least one entry could not be read; it is printed as
#         unreadable rather than skipped
#
# --selftest drives all four over fixture plugin trees under `mktemp -d`,
# asserts a tree holding one skill AND one command lists both, each under its
# own label, and asserts the codes reached are the codes documented. Its own
# exits: 0 every case held, 1 one did not, 2 it could not run.
set -euo pipefail

SELF="$(cd -P "$(dirname "$0")" && pwd -P)/$(basename "$0")"
VERSION="list-commands 1.0"

usage() {
  sed -n '2,3p' "$SELF" | sed 's/^# //'
}

PLUGIN=""
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)     PLUGIN="${2:-}"; [ -n "$PLUGIN" ] || { echo "list-commands: --plugin needs a directory" >&2; exit 2; }; shift 2 ;;
    --plugin=*)   PLUGIN="${1#--plugin=}"; shift ;;
    --selftest|--self-test) SELFTEST=1; shift ;;
    --version)    printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "list-commands: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  SCRATCH="$(mktemp -d)" || { echo "list-commands: cannot create a temporary directory, so no case was driven" >&2; exit 2; }
  trap 'rm -rf "$SCRATCH"' EXIT HUP INT TERM

  CASES=0; UPHELD=0; CODES=""; REPORT=""
  record() { # record <id> <held:0|1> <what>
    CASES=$((CASES + 1))
    if [ "$2" -eq 1 ]; then UPHELD=$((UPHELD + 1)); v="held"; else v="NOT HELD"; fi
    REPORT="$REPORT$(printf '    %-36s %s: %s' "$1" "$v" "$3")"$'\n'
  }
  drive() { # drive <id> <want-code> <what> <args...>  -> output in $OUT
    local id="$1" want="$2" what="$3" got=0; shift 3
    OUT="$(bash "$SELF" "$@" 2>&1)" || got=$?
    CODES="$CODES$got"$'\n'
    if [ "$got" -eq "$want" ]; then record "$id" 1 "$what (exit $got)"; else record "$id" 0 "$what (wanted exit $want, got $got)"; fi
  }
  has_line() { printf '%s\n' "$OUT" | grep -Eq "$1"; }

  BOTH="$SCRATCH/both"
  mkdir -p "$BOTH/skills/alpha" "$BOTH/commands"
  printf -- '---\nname: alpha\ndescription: "Alpha skill does a thing. More prose."\nargument-hint: "[a]"\ndisable-model-invocation: true\n---\n\n# body\n' > "$BOTH/skills/alpha/SKILL.md"
  printf -- '---\ndescription: "Beta command reports a thing. Applies nothing."\nargument-hint: "[--b]"\n---\n' > "$BOTH/commands/beta.md"
  printf -- '---\nargument-hint: ""\n---\n\ndescription: "a body line that must not be read"\n' > "$BOTH/commands/body-only.md"
  drive both-sources-listed 0 "a tree with one skill and one command exits 0" --plugin "$BOTH"
  if has_line '^  skill +/productizer:alpha +\[a\]$'; then record skill-row-labelled-skill 1 "the skill's row carries the skill label and its own argument-hint"; else record skill-row-labelled-skill 0 "the skill's row carries the skill label and its own argument-hint"; fi
  if has_line '^  command +/productizer:beta +\[--b\] +\[auto\]$'; then record command-row-labelled-command 1 "the command's row carries the command label, its file name and its own argument-hint"; else record command-row-labelled-command 0 "the command's row carries the command label, its file name and its own argument-hint"; fi
  if has_line '^      Beta command reports a thing\.$' && ! has_line 'must not be read' && printf '%s\n' "$OUT" | grep -A1 -E '^  command +/productizer:body-only' | grep -q '(no description)'; then record command-description-from-frontmatter 1 "the command's description comes from its frontmatter block, not its body"; else record command-description-from-frontmatter 0 "the command's description comes from its frontmatter block, not its body"; fi
  if has_line 'command +/productizer:alpha' || has_line 'skill +/productizer:beta'; then record no-cross-labelling 0 "neither row carries the other source's label"; else record no-cross-labelling 1 "neither row carries the other source's label"; fi
  if has_line '^  1 skill\(s\) from .*, 2 command\(s\) from '; then record summary-counts-both 1 "the summary counts each source separately"; else record summary-counts-both 0 "the summary counts each source separately"; fi

  drive usage-refused 2 "an unknown argument is refused" --bogus
  mkdir -p "$SCRATCH/empty"
  drive no-plugin-tree 3 "a directory with neither skills/ nor commands/ lists nothing and says so" --plugin "$SCRATCH/empty"

  BAD="$SCRATCH/unreadable"
  mkdir -p "$BAD/skills/gamma" "$BAD/commands/delta.md"
  printf -- '---\nname: gamma\ndescription: "Gamma."\n---\n' > "$BAD/skills/gamma/SKILL.md"
  drive unreadable-entry 4 "an entry that cannot be read is listed as unreadable, not skipped" --plugin "$BAD"
  if has_line '^  command +/productizer:delta' && has_line 'could not be read'; then record unreadable-still-listed 1 "the unreadable command still has a row"; else record unreadable-still-listed 0 "the unreadable command still has a row"; fi

  printf '    selftest cases driven: %d\n' "$CASES"
  printf '%s' "$REPORT"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  MISSING=""
  for want in 0 2 3 4; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 2 3 4\n' "$REACHED"
  [ -z "$MISSING" ] || echo "list-commands: documented exit code(s) never reached by any case:$MISSING" >&2
  printf '    NOT ASSERTED: the self-test own exit 2 - no temporary directory - is a guard no case drives. Only the installed layout skills/<name>/SKILL.md and commands/<name>.md is read; nested commands/ subdirectories are not.\n'
  [ "$CASES" = "$UPHELD" ] || exit 1
  [ -z "$MISSING" ] || exit 1
  exit 0
fi

[ -n "$PLUGIN" ] || { echo "list-commands: --plugin DIR is required" >&2; usage >&2; exit 2; }

python3 - "$PLUGIN" <<'PY'
import io, os, re, sys
root = sys.argv[1]
sd, cd = os.path.join(root, 'skills'), os.path.join(root, 'commands')
if not os.path.isdir(sd) and not os.path.isdir(cd):
    print('  no skills/ or commands/ under %s - nothing was listed, and that is not the same as a plugin with no commands.' % root)
    sys.exit(3)

def front(path):
    head = io.open(path, encoding='utf-8', errors='replace').read(8000)
    m = re.match(r'---\s*\n(.*?)\n---\s*(\n|$)', head, re.S)
    return m.group(1) if m else ''

def row(kind, fallback, path):
    try:
        fm = front(path)
    except (IOError, OSError):
        return (kind, fallback, '', False, '(could not be read - present, but unreadable)', True)
    nm = re.search(r'^name:\s*(\S+)\s*$', fm, re.M)
    ds = re.search(r'^description:\s*"(.*?)"\s*$', fm, re.M | re.S)
    hint = re.search(r'^argument-hint:\s*"(.*?)"\s*$', fm, re.M)
    auto = not re.search(r'^disable-model-invocation:\s*true\s*$', fm, re.M)
    first = (ds.group(1).split('. ')[0].rstrip('.') + '.') if ds else '(no description)'
    name = nm.group(1) if (nm and kind == 'skill') else fallback
    return (kind, name, hint.group(1) if hint else '', auto, first, False)

rows = []
if os.path.isdir(sd):
    for n in sorted(os.listdir(sd)):
        f = os.path.join(sd, n, 'SKILL.md')
        if os.path.lexists(f):
            rows.append(row('skill', n, f))
if os.path.isdir(cd):
    for n in sorted(os.listdir(cd)):
        if n.endswith('.md'):
            rows.append(row('command', n[:-3], os.path.join(cd, n)))

for kind, name, hint, auto, first, _ in rows:
    line = '  %-8s /productizer:%-10s %s%s' % (kind, name, hint, '   [auto]' if auto else '')
    print(line.rstrip())
    print('      %s' % first)
print('')
ns = sum(1 for r in rows if r[0] == 'skill')
nc = len(rows) - ns
print('  %d skill(s) from %s, %d command(s) from %s' % (
    ns, sd if os.path.isdir(sd) else '(no skills/ directory)',
    nc, cd if os.path.isdir(cd) else '(no commands/ directory)'))
sys.exit(4 if any(r[5] for r in rows) else 0)
PY
