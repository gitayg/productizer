#!/usr/bin/env bash
# check-sigpipe.sh [--version] [--help] [--selftest] <file>...
#
# Refuses shell that pipes into a reader which can stop reading early, in a file
# that runs under `set -o pipefail`. B131.
#
# THE DEFECT. `grep -q` exits on its first match; `grep -m N`, `grep -l` and
# `head` exit once they have what they came for. Whatever is still writing into
# the pipe then takes SIGPIPE and exits 141, and pipefail makes 141 the status
# of the whole pipeline. So
#
#     printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
#
# reports a code that WAS reached as missing, and `x="$(cmd | head -1)"` under
# `set -e` ends the script with no message. It is a race on scheduling, not on
# content: bash writes a printf of several lines one line per write, so even 80
# bytes can lose it. Measured 2026-10-12 on this machine: an 80-byte, 40-line
# list, 12 copies in parallel, 1000 runs each - 148 false misses in 12000 through
# the pipe, 0 in 12000 through a here-string. With a 200000-line tail after the
# match it is 20 false misses in 20. It was seen once for real, in
# `build-guide.sh --selftest` under parallel load: `exit codes reached: 0 1 2 3`
# printed, then `documented exit code(s) no case reached: 1`.
#
# THE IDIOM THIS CHECK PUSHES TOWARD. Never let an early reader sit downstream
# of a pipe. Hand it a file, or a here-string of a value already captured:
#
#     grep -qx "$want" <<<"$CODES"
#     out="$(cmd)"; first="$(head -n 1 <<<"$out")"
#     grep -qF -- "$s" "$out_file" "$err_file"
#
# bash writes the whole here-string before the reader starts, so there is no
# writer left to signal. A here-string ends in a newline whether or not the
# value did, which is why it also matches a last line that had none.
#
# WHAT IT REFUSES. In a file with a non-comment `set ... pipefail` line, a `|`
# (or `|&`) whose next command, after any `NAME=value` prefixes and `command`,
# is `head`, or is `grep`/`egrep`/`fgrep` carrying -q, -m, -l or -L (in any
# short-option cluster) or --quiet, --silent, --max-count, --files-with-matches
# or --files-without-match. The pipe may end the previous line, start this one,
# or sit before a backslash-newline; the line reported is the reader's.
#
# WHERE THE STATUS MATTERS. Under `set -e` (any `set` cluster with e, `set -o
# errexit`, or `-e` on the shebang) every such pipeline counts: a bare one ends
# the script, an assignment from one ends it too. Without errexit a status that
# nobody tests is harmless - import-survey.sh caps its sections with `head` on
# purpose, and killing the writer early is how the cap saves work - so there a
# reader counts only when its statement opens with if, elif, while, until or
# `!`, or when an && or || follows it in the same statement. A `$(`, `(` or `{`
# opens a new statement, so `[ "$(a | head -1)" = x ]` does not count.
#
# WHAT IS NOT SHELL HERE, AND IS SKIPPED. Comments; the inside of single-quoted
# and $'...' strings (a fixture that QUOTES the shape, or an `sh -c '...'` run by
# a shell this file's pipefail does not reach); the literal text of double-
# quoted strings (a `$( ... )` inside one is code and is read); here-document
# bodies. A file with no pipefail line is read and passes: without pipefail the
# pipeline's status is the reader's, and the reader's answer is right.
#
# NOT ASSERTED - out of reach statically, and not pretended:
#   - pipefail switched on in ANOTHER file (sourced, or inherited); the line is
#     looked for in each file scanned
#   - a reader reached through a function, alias or variable: `cmd | first`
#     where first() runs head
#   - other early readers: `sed q`, `awk '... exit'`, `read`, `cmp`, python
#   - shell outside a .sh file: a workflow `run:` block, a Markdown fence; this
#     check reads the files it is given as shell end to end
#   - a `$( ... )` inside an unquoted here-document body, which is code; the
#     body is skipped as text
#   - backtick command substitution, which is read as plain code
#   - in a file WITHOUT errexit: a function whose last pipeline ends in a reader
#     and whose caller tests it, and `if x="$(a | head -1)"`, where the test
#     sits outside the substitution that opened a new statement, and a group
#     or subshell tested from outside: `{ a | head -1; } || x`, `( ... ) || x`
#
# HOW TO EXEMPT A LINE, AND WHY IT COSTS A SENTENCE. When the status genuinely
# does not matter, put a marker on the reader's line:
#
#     ... | head -n 3   # sigpipe-ok: <reason>
#
# The reason is everything after the colon and must be at least MIN_REASON
# characters; a shorter one is exit 2, refused rather than exempted.
#
# THIS FILE IS SCANNED LIKE EVERY OTHER, with no self-exemption. Its own scanner
# lives in a here-document and its fixtures are assembled from single-quoted
# printf formats, both of which are skipped as text.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file read, no early reader on a pipe under pipefail
#   1  at least one found - reported by file and line
#   2  COULD NOT MEASURE. An unreadable file, no file at all, or an exemption
#      with no reason. Never confused with 0.
#
# Under --selftest (--self-test is accepted too) the same three mean: every
# case produced the exit code it declares and said what it was supposed to say
# (0), at least one did not (1), and the corpus could not be driven at all (2).
set -euo pipefail

VERSION="check-sigpipe 1.0"
MIN_REASON=12
MODE="scan"

usage() { printf 'usage: check-sigpipe.sh [--version] [--help] [--selftest] <file>...\n' >&2; }
die_usage() { printf 'check-sigpipe: %s\n' "$1" >&2; usage; exit 2; }

FILES=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
    --selftest|--self-test) MODE="selftest"; shift ;;
    --) shift; while [ "$#" -gt 0 ]; do FILES+=("$1"); shift; done ;;
    -*) die_usage "unknown option $1" ;;
    *) FILES+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# The scanner. Python, stdlib, isolated. It lexes each file once: single- and
# double-quoted text, comments and here-document bodies are masked, `$( ... )`
# reopens code inside double quotes, and what is left is joined across
# backslash-newlines and trailing pipes before the readers are looked for.
# ---------------------------------------------------------------------------
scan() {
  python3 -I - "$MIN_REASON" "$@" <<'PY'
import re, sys

min_reason = int(sys.argv[1])
files = sys.argv[2:]

READER = re.compile(r'\|&?[ \t\n]*((?:[A-Za-z_][A-Za-z0-9_]*=[^ \t\n]*[ \t]+)*)(?:command[ \t]+)?(head|grep|egrep|fgrep)(?![A-Za-z0-9_.-])([^|;&)\n]*)')
PIPEFAIL = re.compile(r'(^|[;&|{(]|\bthen\b|\bdo\b)[ \t]*set[ \t]+[^\n]*\bpipefail\b', re.M)
ERREXIT = re.compile(r'(^|[;&|{(]|\bthen\b|\bdo\b)[ \t]*set[ \t]+(-[A-Za-z]*e[A-Za-z]*\b|[^\n]*-o[ \t]+errexit\b)', re.M)
SHEBANG_E = re.compile(r'\A#![^\n]*[ \t]-[A-Za-z]*e')
CONDITION_START = re.compile(r'[ \t]*(?:(?:if|elif|while|until)\b|!)')
MARK = re.compile(r'sigpipe-ok:(.*)$')
LONG_EARLY = ('--quiet', '--silent', '--max-count', '--files-with-matches', '--files-without-match')
ARG_TAKING = set('efABCdDm')


def mask(text):
    """Return (masked, comments): masked keeps code characters and newlines and
    blanks every quoted or here-document character; comments maps a line index
    to that line's comment text."""
    out = []
    comments = {}
    line = 0
    stack = ['code']
    pending = []          # here-documents opened on this line: (delim, strip_tabs)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        top = stack[-1]
        if c == '\n':
            out.append('\n')
            line += 1
            i += 1
            if pending and top in ('code', 'sub'):
                for delim, strip in pending:
                    while i < n:
                        j = text.find('\n', i)
                        j = n if j < 0 else j
                        body = text[i:j]
                        out.append(' ' * len(body))
                        if j < n:
                            out.append('\n')
                        line += 1
                        i = j + 1
                        if (body.lstrip('\t') if strip else body) == delim:
                            break
                pending = []
            continue
        if top == 'sq':
            if c == "'":
                stack.pop(); out.append(c)
            else:
                out.append(' ')
            i += 1
            continue
        if top == 'ansi':
            if c == '\\' and i + 1 < n and text[i + 1] != '\n':
                out.append('  '); i += 2; continue
            if c == "'":
                stack.pop(); out.append(c)
            else:
                out.append(' ')
            i += 1
            continue
        if top == 'dq':
            if c == '\\' and i + 1 < n and text[i + 1] != '\n':
                out.append('  '); i += 2; continue
            if c == '"':
                stack.pop(); out.append(c); i += 1; continue
            if text.startswith('$(', i) and not text.startswith('$((', i):
                stack.append('sub'); out.append('$('); i += 2; continue
            out.append(' ')
            i += 1
            continue
        # code or sub
        if c == '\\' and i + 1 < n:
            if text[i + 1] == '\n':
                out.append('\\'); i += 1; continue
            out.append('  '); i += 2; continue
        if c == "'":
            stack.append('sq'); out.append(c); i += 1; continue
        if text.startswith("$'", i):
            stack.append('ansi'); out.append("$'"); i += 2; continue
        if c == '"':
            stack.append('dq'); out.append(c); i += 1; continue
        if text.startswith('$(', i) and not text.startswith('$((', i):
            stack.append('sub'); out.append('$('); i += 2; continue
        if c == ')' and top == 'sub':
            stack.pop(); out.append(c); i += 1; continue
        if c == '#' and (i == 0 or text[i - 1] in ' \t\n;&|(){}'):
            j = text.find('\n', i)
            j = n if j < 0 else j
            comments[line] = text[i:j]
            out.append(' ' * (j - i))
            i = j
            continue
        if text.startswith('<<<', i):
            out.append('<<<'); i += 3; continue
        if text.startswith('<<', i):
            m = re.match(r'<<(-?)[ \t]*(?:\'([^\'\n]*)\'|"([^"\n]*)"|\\?([A-Za-z_][A-Za-z0-9_]*))', text[i:])
            if m:
                delim = m.group(2) if m.group(2) is not None else (m.group(3) if m.group(3) is not None else m.group(4))
                pending.append((delim, m.group(1) == '-'))
                out.append(m.group(0))
                i += len(m.group(0))
                continue
        out.append(c)
        i += 1
    return ''.join(out), comments


def grep_stops_early(args):
    toks = args.split()
    k = 0
    while k < len(toks):
        tok = toks[k]
        k += 1
        if tok == '--':
            return False
        if tok.startswith('--'):
            if tok.split('=', 1)[0] in LONG_EARLY:
                return True
            continue
        if tok.startswith('-') and len(tok) > 1:
            for at, ch in enumerate(tok[1:], 1):
                if ch in 'qlLm':
                    return True
                if ch in ARG_TAKING:
                    if at == len(tok) - 1:
                        k += 1        # its argument is the next word
                    break
    return False


def tested(flat, start, end):
    """Without errexit a pipeline's status matters only where it is tested:
    the statement opens with if/elif/while/until/!, or an && or || follows the
    reader before the statement ends. A $( ) or a brace group opens a new
    statement, so `[ "$(a | head -1)" = x ]` is not a test of the pipeline."""
    k = start
    while k > 0 and flat[k - 1] not in '\n;{(':
        k -= 1
    if CONDITION_START.match(flat, k):
        return True
    e = end
    while e < len(flat) and flat[e] not in '\n;)':
        e += 1
    return bool(re.search(r'&&|\|\|', flat[end:e]))


rc = 0
for path in files:
    try:
        with open(path, encoding='utf-8', errors='surrogateescape') as fh:
            text = fh.read()
    except OSError as e:
        print(f'check-sigpipe: cannot read {path}: {e.strerror}. Unmeasured, not clean.', file=sys.stderr)
        sys.exit(2)
    masked, comments = mask(text)
    nlines = text.count('\n') + (0 if text.endswith('\n') or not text else 1)
    if not PIPEFAIL.search(masked):
        print(f'{path}: {nlines} line(s) read; no pipefail line, so a pipeline reports its reader\'s status and nothing here is at stake.')
        continue
    errexit = bool(ERREXIT.search(masked) or SHEBANG_E.search(text))
    # FLAT has every continuation folded to spaces, one character for one, so
    # an offset into it is an offset into JOINED: it is where a statement's
    # start and end are looked for. JOINED keeps the newlines for line numbers.
    flat = re.sub(r'\\\n', '  ', masked)
    flat = re.sub(r'\|&?[ \t]*\n', lambda m: m.group(0)[:-1] + ' ', flat)
    # A backslash-newline is blanked so the reader pattern, which already
    # crosses newlines after a pipe, reaches the next line. Every newline is
    # kept, so an offset still maps back to its own line.
    joined = re.sub(r'\\\n', ' \n', masked)
    findings = 0
    for m in READER.finditer(joined):
        start = m.start()
        if start > 0 and joined[start - 1] == '|':
            continue
        name, args = m.group(2), m.group(3)
        if name != 'head' and not grep_stops_early(args):
            continue
        if not errexit and not tested(flat, m.start(), m.end()):
            continue
        lineno = joined.count('\n', 0, m.start(2))
        mk = MARK.search(comments.get(lineno, ''))
        if mk:
            reason = mk.group(1).strip()
            if len(reason) < min_reason:
                print(f'check-sigpipe: {path}:{lineno + 1}: a sigpipe-ok marker carries a reason of {len(reason)} character(s); a reason must be at least {min_reason}. Refused, not exempted.', file=sys.stderr)
                sys.exit(2)
            continue
        src = text.split('\n')[lineno].strip()
        what = 'head' if name == 'head' else f'{name} that stops at its first match'
        print(f'{path}:{lineno + 1}: early reader on a pipe under pipefail ({what}): {src}')
        findings += 1
    if findings:
        rc = 1
    else:
        print(f'{path}: {nlines} line(s) read under pipefail; no early reader on a pipe.')
if rc:
    print('Hand the reader a file or a here-string of a captured value (grep -q P <<<"$v"); a pipe lets SIGPIPE turn a match into 141.')
sys.exit(rc)
PY
}

# ---------------------------------------------------------------------------
# --selftest. One case per exit code, each built in a sandbox. Every case
# asserts its own sentence as well as its exit code. Fixtures are written from
# single-quoted printf formats, which this scanner reads as text, so this file
# carries the shapes without carrying the defect.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  [ "${#FILES[@]}" -eq 0 ] || die_usage "--selftest drives its own sandbox and takes no files; got ${FILES[0]}"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-sigpipe-selftest.XXXXXX")" ||
    { printf 'check-sigpipe: could not create a sandbox, so no case was driven. Unmeasured.\n' >&2; exit 2; }
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  H='#!/usr/bin/env bash\nset -euo pipefail\n'
  printf "$H"'grep -qx "$want" <<<"$CODES" || echo missing\nfirst="$(head -n 1 <<<"$out")"\ngrep -q x a.txt b.txt\n' > "$SB/clean.sh"
  printf "$H"'printf "%%s" "$CODES" | grep -qx "$want" || echo missing\n' > "$SB/grep-q.sh"
  printf "$H"'x="$(sed -n s/a/b/p f | head -1)"\n' > "$SB/head-in-sub.sh"
  printf "$H"'git log --format=%%B |\n  grep -m1 Req\n' > "$SB/pipe-eol.sh"
  printf "$H"'cat a b \\\n  | LC_ALL=C grep -Fxq -- "$s" && echo hit\n' > "$SB/pipe-bol.sh"
  printf "$H"'read -r a b <<< "$x"\nif ! cmd | grep --quiet x; then :; fi\n' > "$SB/long-opt.sh"
  printf "$H"'w="$(printf "%%s\\n" "$1" | sed -n p | head -n 1)"\n' > "$SB/dq-sub.sh"
  printf "$H"'cmd | grep -c x\ncmd | grep -e -q\ncmd || grep -q x f\necho "a | head -1"\n' > "$SB/not-early.sh"
  printf "$H"'# cmd | grep -q x\nprintf %s\n' "'a | head -1\n'" > "$SB/quoted.sh"
  printf "$H"'python3 - <<EOF\nprint("a | head -1")\nEOF\nsh -c '"'"'git log | grep -q x'"'"'\n' > "$SB/heredoc.sh"
  printf '#!/usr/bin/env bash\nset -uo pipefail\nx | head -n 3 > list\n[ -s f ] && { y | head -n 60; }\nfiles() { z | head -n "$1"; }\n[ "$(v | head -1)" = a ] || :\n' > "$SB/no-errexit.sh"
  printf '#!/usr/bin/env bash\nset -uo pipefail\nx | head -n 3 > list\nif w | grep -q x; then :; fi\nu | grep -m1 y || echo none\n' > "$SB/no-errexit-test.sh"
  printf '#!/usr/bin/env bash\nset -eu\nprintf "%%s" "$CODES" | grep -qx 1 || echo missing\n' > "$SB/no-pipefail.sh"
  printf "$H"'cmd | head -n 3   # sigpipe-ok: the status is discarded by the caller below\n' > "$SB/marked.sh"
  printf "$H"'cmd | head -n 3   # sigpipe-ok: short\n' > "$SB/short-marker.sh"

  FAILED=0
  DRIVEN=0
  CODES=""

  drive() {
    # $1 case name, $2 expected exit, $3 expected sentence, $4.. argv
    local case_name="$1" want="$2" marker="$3"
    shift 3
    local rc=0
    bash "$0" "$@" > "$SB/$case_name.out" 2> "$SB/$case_name.err" || rc=$?
    DRIVEN=$((DRIVEN + 1))
    CODES="$CODES$rc
"
    local why=""
    [ "$rc" -eq "$want" ] || why="exit $rc, expected $want"
    if ! grep -qF -- "$marker" "$SB/$case_name.out" "$SB/$case_name.err"; then
      [ -n "$why" ] && why="$why; "
      why="${why}its output does not say what it was supposed to say"
    fi
    if [ -z "$why" ]; then
      printf '  held: case %-16s exit %d, and said so - %s\n' "$case_name" "$rc" "$marker"
      return 0
    fi
    printf '  FINDING: case %-16s %s - expected: %s\n' "$case_name" "$why" "$marker"
    FAILED=$((FAILED + 1))
    return 0
  }

  drive clean          0 'clean.sh: 5 line(s) read under pipefail; no early reader'  "$SB/clean.sh"
  drive grep-q         1 'grep-q.sh:3: early reader on a pipe under pipefail (grep that stops'  "$SB/grep-q.sh"
  drive head-in-sub    1 'head-in-sub.sh:3: early reader on a pipe under pipefail (head)'  "$SB/head-in-sub.sh"
  drive pipe-eol       1 'pipe-eol.sh:4: early reader on a pipe under pipefail (grep'  "$SB/pipe-eol.sh"
  drive pipe-bol       1 'pipe-bol.sh:4: early reader on a pipe under pipefail (grep'  "$SB/pipe-bol.sh"
  drive long-opt       1 'long-opt.sh:4: early reader on a pipe under pipefail (grep'  "$SB/long-opt.sh"
  drive dq-sub         1 'dq-sub.sh:3: early reader on a pipe under pipefail (head)'  "$SB/dq-sub.sh"
  drive not-early      0 'not-early.sh: 6 line(s) read under pipefail; no early reader'  "$SB/not-early.sh"
  drive quoted         0 'quoted.sh: 4 line(s) read under pipefail; no early reader'  "$SB/quoted.sh"
  drive heredoc        0 'heredoc.sh: 6 line(s) read under pipefail; no early reader'  "$SB/heredoc.sh"
  drive no-errexit     0 'no-errexit.sh: 6 line(s) read under pipefail; no early reader'  "$SB/no-errexit.sh"
  drive no-errexit-if  1 'no-errexit-test.sh:4: early reader on a pipe under pipefail (grep'  "$SB/no-errexit-test.sh"
  drive no-errexit-or  1 'no-errexit-test.sh:5: early reader on a pipe under pipefail (grep'  "$SB/no-errexit-test.sh"
  drive no-pipefail    0 'no-pipefail.sh: 3 line(s) read; no pipefail line'  "$SB/no-pipefail.sh"
  drive marked         0 'marked.sh: 3 line(s) read under pipefail; no early reader'  "$SB/marked.sh"
  drive short-marker   2 'Refused, not exempted'  "$SB/short-marker.sh"
  drive unreadable     2 'Unmeasured, not clean'  "$SB/no-such-file.sh"
  drive no-files       2 'Nothing scanned is not a clean scan'

  printf '  cases driven: %d. Cases that did not hold: %d\n' "$DRIVEN" "$FAILED"
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    grep -qx "$want" <<<"$CODES" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  if [ "$FAILED" -ne 0 ]; then
    printf 'FAIL: %d selftest case(s) did not produce the exit code and the sentence they declare.\n' "$FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'FAIL: documented exit code(s) no case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  NOT ASSERTED: pipefail set in another file, a reader behind a function, alias or variable, readers other than head and grep (sed q, awk exit, read), shell in a workflow run: block or a Markdown fence, $( ) inside an unquoted here-document, backtick substitution; without errexit, a function tested by its caller, and a test outside the $( ), ( ) or { } holding the reader.\n'
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  printf 'check-sigpipe: no files given. Nothing scanned is not a clean scan.\n' >&2
  usage
  exit 2
fi

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    printf 'check-sigpipe: cannot read %s. Unmeasured, not clean.\n' "$f" >&2
    exit 2
  fi
done

scan "${FILES[@]}"
