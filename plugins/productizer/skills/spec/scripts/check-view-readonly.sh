#!/usr/bin/env bash
# check-view-readonly.sh [--root DIR] [--builder PATH] [--fixture DIR]
#                       [--version] [--help]
#
# Asserts R4: EVERY PUBLISHED VIEW SHALL BE READ-ONLY WITH RESPECT TO THE SPEC.
# It also asserts the page-side half of R30 and of R31; see THE R31 BOUNDARY
# below, which is the one place this check must not be read as more than it is.
#
# Read-only has two halves and they fail in different places, so one check
# covers both rather than one of them being asserted and the other assumed.
#
#   HALF ONE - THE GENERATOR WRITES NOTHING BACK. The view builder is run
#   against this repository with its output pointed at a temporary directory,
#   and every file in the work tree is hashed before and after. Content AND
#   modification time, because a rewrite with identical bytes is still a write
#   and a build that touches a file it was only supposed to read will be
#   noticed the next time something else compares timestamps. An added file, a
#   removed file and a changed file are three findings, not one.
#
#   HALF TWO - WHAT THE PAGE DECLARES. The generated page is read and every
#   capability it reaches for is classified. `downloads` is OUTPUT: the page
#   hands the viewer a file built from its own bytes and reads nothing back,
#   which is exactly what R30 requires of a view that hands over its evidence.
#   A capability that publishes new versions of the page is not output - it
#   makes the page a second source of truth that can disagree with the repo,
#   and the provenance line under every panel, the sentence saying every figure
#   was read from the repository at generation time, stops being true the
#   moment it can. See references/views.md.
#
# WHY 3.0 EXISTS, AND WHAT 2.0 COULD NOT SEE. 1.0 matched one literal source
# pattern, `claude.use("<name>")`, and an audit defeated it in a single line -
# `window.claude["use"]("artifact")` reached the same capability and 1.0
# reported `capability declarations read: 0` and passed clean. 2.0 answered
# that by reading the page for WHAT IT REACHES rather than how it is spelled,
# resolving the receiver, the property and the binding across whitespace,
# brackets, quotes and optional chaining.
#
# 2.0 still read BYTES. Its own header admitted the hole and named the case:
# a request assembled at run time was reported as UNREADABLE rather than
# resolved, and it was caught at all only when the split happened to leave a
# contiguous fragment. Measured on the corpus, not argued: the page
#
#     window["ev" + "al"]("window.cla" + "ude.u" + "se('artifact')")
#
# splits every fragment so that no contiguous run of characters spells the
# receiver, the property or the evaluator - and 2.0 reported ZERO findings and
# passed it CLEAN. Same for a name decoded at run time. That is the 1.0 failure
# shape returning through a different door: the check answered "nothing here"
# when the truthful answer was "this page assembles a request I cannot read".
#
# WHAT 3.0 PARSES, EXACTLY. It stops guessing at JavaScript and tokenizes it.
#
#   REGIONS. The parts of the file a browser hands to the JavaScript engine:
#   every `<script>` body, every inline `on...=` event-handler attribute, and
#   every `javascript:` URL. These are what the folder and the evaluator net
#   read. The BYTE-LEVEL nets below still run over the WHOLE file, so nothing
#   2.0 caught is lost when a region is missed or unparsable - `unparsable-
#   region` in the corpus is a page whose string never closes, and the request
#   after it is still found and still named. A page that breaks the parser must
#   not become a page that declares nothing.
#
#   THE TOKENIZER. String literals with their escapes decoded, template
#   literals including nested `${}` substitutions, regular-expression literals
#   told from division by the token before them, line and block comments,
#   numbers, identifiers and punctuation. A comment cannot execute, so a
#   comment is skipped; a string is a string, so `eval` inside one is text and
#   not a call - which is exactly why the real page, which embeds 35KB of prose
#   inside one string literal, does not trip the evaluator net.
#
#   THE CONSTANT FOLDER. Wherever a capability name or a property key is
#   wanted, the expression there is folded rather than pattern-matched:
#     - a string literal, with `\xNN`, `\uNNNN` and `\u{...}` decoded
#     - a template literal, including one whose substitutions fold
#     - `+` concatenation of anything that folds, to any depth
#     - a parenthesised expression of the above
#     - an identifier bound ONCE in the file's JavaScript to something that
#       folds. Once, and this check counts writes to find out: declarations,
#       function and class names, every parameter list, `catch` bindings,
#       destructuring patterns, every assignment operator and every `++`/`--`.
#       Two writes and the name does not fold, because the value at the call
#       site depends on which one ran.
#
#   THE EVALUATOR NET. `eval`, `Function`, `execScript`, and `setTimeout` or
#   `setInterval` given a string - reached bare, or through `window`, `self`,
#   `globalThis`, `top`, `parent` or `frames` by a property that folds. An
#   evaluator call is a FINDING on its own: what a page decides to ask for at
#   run time is not in the page. When its text folds, that text is scanned as
#   source, to a depth of four, and what IT reaches is named too.
#
#   A timer handed a FUNCTION is not an evaluator and is not reported. That is
#   not a softening for convenience: the shipped page schedules a callback with
#   `setTimeout`, and a check that flagged it would fail the real dashboard on
#   the first run. `settimeout-callback` in the corpus holds that line, and
#   `settimeout` with a string is `folded` and loud.
#
# WHAT THE FOLDER IS NOT ALLOWED TO DO: CERTIFY. A name written as a plain
# string literal AT THE CALL SITE may be clean. A name this check had to
# ASSEMBLE - out of a concatenation, a template, a binding, a string escape,
# an evaluated string - is REPORTED WITH THE NAME and is a finding whatever the
# name turns out to be, `downloads` included. The fold is a static
# approximation of a run-time value; a check that certifies what it inferred is
# a check that will one day certify something wrong. Naming what was reached is
# the whole point of 3.0. Calling it safe is not. A view that means `downloads`
# writes `downloads` at the call site, and the shipped page does.
#
# WHAT DEFEATS IT, WRITTEN DOWN RATHER THAN HIDDEN. An evaluator is
# undecidable and this is where the line is drawn:
#
#   - a name built by anything that is not `+` on foldable parts: `atob`,
#     `String.fromCharCode`, `["u","s","e"].join("")`, arithmetic, a fetch, a
#     property of an object, a function's return value. Reported as a finding
#     that says it could not be folded. `opaque-eval` and `computed-key` in the
#     corpus sit on this side of the line on purpose
#   - a name whose binding is written more than once anywhere in the file
#   - scope. The binding table is flat: a name is folded only when the WHOLE
#     file writes it exactly once, so shadowing makes it unfoldable rather than
#     mis-resolved. That is the conservative direction, and it costs folds
#   - source built by an evaluator out of text this check cannot fold, or
#     nested deeper than four evaluators
#   - a write shape not in the list above would be missed, and a missed write
#     is the one error that could resolve a name WRONGLY rather than not at all.
#     Every assignment form this file could name is counted; `reassigned-name`
#     in the corpus exists to keep that counting honest
#
# THE BYTE-LEVEL NETS, KEPT FROM 2.0 SO NOTHING REGRESSES. Three, over the
# whole file, and the second is deliberately the louder one.
#
#   NET ONE, ANCHORED ON THE RECEIVER. The identifier `claude`, optionally
#   written `window.claude`, followed by a property access. The access and the
#   call are then read from TOKENS: a dotted name as written, a bracketed key
#   folded, whitespace, newlines and optional chaining all crossed. When the
#   property is `use` and it is called, the first argument is folded.
#
#   NET TWO, ANCHORED ON THE PROPERTY. Any `.use(...)` or `["use"](...)` that
#   net one did not already claim, on ANY receiver. This is what catches an
#   alias: `var c = window.claude; c.use("artifact")` never names the
#   capability object at the call site. Net two cannot tell that receiver from
#   an unrelated object and does not pretend to.
#
#   NET THREE, ANCHORED ON THE BINDING. `var {use} = window.claude` binds the
#   request to a bare name, after which neither receiver nor property appears
#   anywhere. Anchored on braces, the bound name and the assignment.
#
#   NET SIX, THE OBJECT ITSELF ASSEMBLED. `window["cla" + "ude"]` does not
#   contain the seven letters of the receiver, so nothing anchored on that
#   identifier sees it; reach its property reflectively as well and the
#   property net has nothing to match either, and 2.0 passed such a page clean.
#   A global indexed by a key that FOLDS to the receiver's name IS the
#   receiver, and what follows is read exactly as net one reads it.
#
#   NET FIVE, THE OBJECT TAKEN AS A VALUE. A reference to the capability object
#   with NO property access after it, in code. `Reflect.get(window.claude, "u"
#   + "se")("artifact")` reaches the request without writing the property
#   anywhere, and nets one to three all walk past it - 2.0 passed that page
#   clean. Tokens only, inside JavaScript only: the byte nets read the whole
#   file because HTML prose cannot be tokenized, and this net would fire on the
#   words `window.claude` in a paragraph. A truthiness test is still not a
#   declaration - the shipped page guards both of its references, and this net
#   reports a note on them rather than a finding.
#
# WHAT IS DELIBERATELY NOT MATCHED, SO THIS DOES NOT CRY WOLF. This runs
# against a half-megabyte generated page carrying prose, JSON, file listings
# and code, and a check that fires on discussion of capabilities gets switched
# off within a week. So NONE of the following is matched: the words
# `capability`, `downloads`, `artifact` or `publish` in text; `use` as an
# English word; `{use: 1}` as an object key; `.claude/...` and `.claude-plugin`
# as path text, of which the real page carries over a hundred. Only the CALL
# SYNTAX on a property named `use`, and a call to an evaluator IN CODE
# POSITION, match. Measured, not assumed: on the real generated page the nets
# match exactly two places - both the one `downloads` request the builder emits
# - the tokenizer covers all 63KB of its JavaScript with no gap, and the one
# `setTimeout` in it takes a function, so the evaluator net stays silent.
#
#   THE PRICE OF NET TWO, WRITTEN DOWN. A page that embeds unrelated
#   JavaScript spelling `.use(` - middleware, a plug-in registry, an object of
#   its own with a `use` member - is a false positive, and it is a loud one
#   that names what it found. That is the trade: an alias of the capability
#   object and an unrelated object are the same bytes without an evaluator.
#   The other price is the same one in prose: the byte nets run over the whole
#   file, so a page that QUOTES the call syntax in its text or its comments,
#   rather than executing it, is a finding too. Suppressing that would mean
#   trusting the tokenizer to decide what never runs, and a string can still
#   be written into the document by something this check does not model.
#
# THE RULE THAT MATTERS: AN UNREADABLE DECLARATION IS NEVER COUNTED AS AN
# ABSENT ONE. Every outcome below is a finding for the same reason, and it is
# the reason 1.0 failed: silence is what let the bracket form through.
#
#   an output capability          `downloads`, written as a literal at the
#                                 call site - reported, not a finding
#   a self-publishing capability  a finding, named
#   any other readable name       a finding. An unrecognised name is not
#                                 evidence of safety
#   a FOLDED name, any name       a finding, and the name is printed
#   a key or name that will not   a finding - what the page reached cannot be
#   fold                          read out of the file
#   a call to an evaluator        a finding, plus whatever the evaluated
#                                 source reaches
#   `use` taken as a value        a finding, unless it sits in a truthiness
#                                 test (`!window.claude.use`, `typeof`, an
#                                 `if (...)` head), which declares nothing.
#                                 The shipped page uses that guard, and a
#                                 check that fails the real dashboard is
#                                 useless
#   any other property reached    a finding. This check classifies the
#   on the capability object      capability request and nothing else
#
# THE R31 BOUNDARY, AND THIS CHECK DOES NOT CLOSE IT. R31's obligation is that
# THE LIFECYCLE REFUSES TO PUBLISH. That refusal is asserted by
# check-view-publish-refused.sh, which drives the real hook and watches it
# decline. What this check asserts is the earlier and weaker half: the page
# does not ASK. 3.0 strengthens that half again - it now resolves requests 2.0
# could only call unreadable, and catches two it passed clean - and it moves
# R31's verdict not at all on its own.
#
# THE SAME BOUNDARY FOR R30. R30 says the lifecycle SHALL USE a capability that
# writes only to the viewer's device. This reads what the page asks for and
# accepts only a literal `downloads`. It does not observe the file arriving on
# the viewer's device, and it cannot see a capability GRANTED IN THE PUBLISH
# CALL and never requested by the page - that surface belongs to the publish
# gate.
#
# THIS CHECK WRITES NOTHING INTO THE REPOSITORY IT IS CHECKING. A check that
# mutates what it is checking is the bug it exists to catch. The page is
# generated into a temporary directory that is removed on exit, and the
# repository is opened read-only.
#
# THE FIXTURE CORPUS, AND WHY THE CLASSIFIER IS NOT TRUSTED ON THE REAL PAGE
# ALONE. The real page is clean, and a classifier that matched nothing at all
# would also call it clean. So the same classifier is run over a corpus of
# small pages under fixtures/view-readonly, each one declaring something known,
# and the corpus carries both directions: pages that MUST be flagged, spelled
# every way the audit and this file could think of, and pages that MUST NOT be,
# including one that discusses capabilities at length and declares none and one
# written to be as hard to tokenize as this file could make it.
#
# EACH CASE ALSO NAMES WHAT MUST BE RESOLVED. cases.tsv carries six fields, and
# the fifth is the set of capability names the classifier must come back with -
# or the word `none`. `finding` alone is too weak an expectation for 3.0: the
# whole point of the folder is that `window.claude.use("art" + "ifact")` is
# reported as `artifact` and not as "something I could not read", and only an
# expected-NAME field can tell those two apart. `none` is an assertion in its
# own right, and the sharper one: a check that invents a name it did not read
# is worse than one that reads nothing.
#
# SEVEN ASSERTIONS, COUNTED SEPARATELY. A single `ok` flag reported above six
# lines of evidence is how a check in this repo printed `upheld: 0` while
# holding six things; each group below carries its own case count and its own
# upheld count, and a group is upheld only when every case in it is.
#
#   A1  the generator moved no repository file
#   A2  the real generated page declares nothing beyond output
#   A3  an evasive SPELLING of the capability request is still classified -
#       bracket, quote, whitespace, newline, optional chaining, alias
#   A4  a declaration this check CANNOT READ is a finding, never an absence,
#       and it resolves NO name
#   A5  a readable capability name that is not output-only is a finding
#   A6  a page that declares nothing forbidden is NOT flagged. A gate that
#       flags every page is as broken as one that flags none, and it is
#       switched off just as fast
#   A7  a request ASSEMBLED at run time is folded to the name it asks for, and
#       reported by that name. This is the assertion 2.0 could not make
#
# THE PREMISE IS GUARDED. If the fixture corpus is missing, or holds no case
# for one of A3-A7, or if the classifier read no capability name anywhere in
# it, or if no case anywhere asserts a resolved NAME, then it swept an empty
# set and this run asserts nothing about it - exit 2, unmeasured, never a pass.
# An assertion with no positive case has already shipped in this repo once and
# sat green for weeks.
#
# KNOWN LIMITATION, WRITTEN DOWN RATHER THAN HIDDEN. The grant is made when the
# page is published, not inside the page. This check reads the page's bytes, so
# it sees what the page ASKS FOR. A capability granted at publish time and
# never used by the page leaves no trace in the file and is out of reach here;
# check-view-publish-refused.sh reaches that surface.
#
# THE OTHER KNOWN LIMITATION. The two hashes bracket the generator's run, so
# anything else that writes to the tree inside that window is attributed to the
# generator. That is the honest reading - the check cannot tell one writer from
# another - and it is a false positive when an editor saves, or a second agent
# works in the same tree, while this is running. A finding here names the file,
# so the first thing to do with one is look at whether that file has anything
# to do with building a view.
#
# AND ONE MORE. Nothing here defeats an evaluator in general. The folder
# follows text into `eval` while the text folds; one `atob` and it stops, loud.
# A page can always compute what it asks for in a way no reader can follow, and
# the only sound answer to that is the one this check gives: a finding that
# says the request could not be read, never a zero.
#
# EXIT CODES ARE THE CONTRACT.
#
#   0  every file hashed, nothing changed, no capability beyond output, and
#      every fixture case reached the classification and the resolved names it
#      must
#   1  findings - a repository file moved, the page declared something it may
#      not, or the classifier called a case wrong
#   2  could not run - bad usage, no work tree, no builder, no fixture corpus,
#      an unreadable file, an unexercised assertion, or a page that could not
#      be generated at all. A page that was never built has an UNKNOWN number
#      of capability declarations, never a measured zero.
#
# WHAT IT PRINTS. One BARE PATH per line for every repository file examined,
# repo-relative, which is what the runner parses as coverage. Findings and
# notes are INDENTED. Nothing absolute is ever printed: this output is tailed
# into a committed result file, and an absolute path there is somebody's home
# directory published to everyone who clones the repo.
#
# PORTABILITY. Developed on macOS/BSD and must hold on GNU. No GNU-only and no
# BSD-only behaviour: no `stat` flags, no `mapfile`, no `grep -P`, no in-place
# `sed`. This repo once shipped a `stat -f %m` that SUCCEEDS on GNU meaning
# something else, so CI was red while macOS was green. Everything that reads a
# file here is python3 through a quoted here-doc. Nothing suppresses stderr.
set -euo pipefail

VERSION="check-view-readonly 3.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT=""
BUILDER=""
FIXTURE=""
MODE="measure"

die_unmeasured() { printf 'check-view-readonly: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) awk 'NR>1 && !/^#/{exit} NR>1' "$0"; exit 0 ;;
    # `--self-test` is an alias, not a second flag: this repository spells the
    # same obligation both ways and a tool that answers only one spelling reads
    # as carrying no self-test to whichever scanner is looking for the other.
    --selftest|--self-test) MODE="selftest"; shift ;;
    --root)      [ "$#" -ge 2 ] || die_unmeasured "--root needs a path";    ROOT="$2";    shift 2 ;;
    --root=*)    ROOT="${1#--root=}";       shift ;;
    --builder)   [ "$#" -ge 2 ] || die_unmeasured "--builder needs a path"; BUILDER="$2"; shift 2 ;;
    --builder=*) BUILDER="${1#--builder=}"; shift ;;
    --fixture)   [ "$#" -ge 2 ] || die_unmeasured "--fixture needs a path"; FIXTURE="$2"; shift 2 ;;
    --fixture=*) FIXTURE="${1#--fixture=}"; shift ;;
    --) shift; break ;;
    -*) die_unmeasured "unknown option: $1. Run with --help for the contract." ;;
    *)  die_unmeasured "takes no positional arguments; got: $1. The tree to check is named with --root." ;;
  esac
done
[ "$#" -eq 0 ] || die_unmeasured "takes no positional arguments; got: $1. The tree to check is named with --root."

# The work tree, never the working directory. Running this from a subdirectory
# must check the same tree it checks from the root, or the answer depends on
# where the person stood when they asked.
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel)" \
    || die_unmeasured "no git work tree here, and --root was not given. The tree to hash could not be identified; unmeasured, not clean."
fi
[ -d "$ROOT" ] || die_unmeasured "--root $ROOT is not a directory"
ROOT="$(cd "$ROOT" && pwd -P)"

[ -n "$BUILDER" ] || BUILDER="$HERE/build-view.sh"
[ -f "$BUILDER" ] || die_unmeasured "no view builder at the path given; there is nothing to run, so read-only is unmeasured"

[ -n "$FIXTURE" ] || FIXTURE="$HERE/../fixtures/view-readonly"
[ -d "$FIXTURE" ] \
  || die_unmeasured "no fixture corpus at the path given. The classifier would run only against a page that is clean, and a classifier that matched nothing would call that page clean too. Unmeasured, not a pass"
FIXTURE="$(cd "$FIXTURE" && pwd -P)"
CASES="$FIXTURE/cases.tsv"
[ -f "$CASES" ] && [ -r "$CASES" ] \
  || die_unmeasured "no readable cases.tsv in the fixture corpus; there is nothing to hold the classifier to"

command -v python3 >/dev/null 2>&1 || die_unmeasured "python3 is not installed; the tree could not be hashed"  # stderr-ok: this is a presence probe and nothing else - `command -v` prints the path it found on stdout and a diagnosis on stderr, both of which answer the same question, and the absent case is reported by die_unmeasured on the next breath rather than swallowed

# The case file's shape is checked BEFORE any case is judged. `read` pads
# missing fields with empty strings, so a short row would otherwise arrive
# looking like a case with an empty expectation and be judged rather than
# refused.
#
# `|| :` is load-bearing and is not tolerance of an unknown failure: awk exits 1
# exactly when it found a bad row, which is the condition being detected, and
# under `set -e` with `pipefail` that status would kill the script here - right
# exit code, and no reason printed at all.
#
# EMPTY fields are refused here too, and that is not tidiness. Tab is an IFS
# WHITESPACE character, so `read` with IFS=tab collapses a run of tabs into one
# delimiter: a row with an empty fifth field is read with the NOTE sitting in
# the names variable and every later field shifted, and it looks like a case
# with a strange expectation rather than a malformed row. awk counts fields
# without collapsing anything, so the refusal happens here, before any case is
# judged, rather than becoming a wrong verdict later.
_badrow="$(awk -F'\t' '/^#/ || NF == 0 { next }
                       NF != 6 { printf "%d ", NR; bad = 1; next }
                       { for (i = 1; i <= 6; i++) if ($i == "") { printf "%d ", NR; bad = 1; break } }
                       END { exit bad ? 1 : 0 }' "$CASES" || :)"
[ -z "$_badrow" ] || die_unmeasured "cases.tsv has rows that are not six non-empty tab-separated fields (line(s): $_badrow). A case file this check cannot read is not one it may guess at"

# ---------------------------------------------------------------------------
# --selftest - R39: THIS TOOL REACHES EACH EXIT CODE IT CAN RETURN, ON PURPOSE.
#
# Four cases, one per way the contract above can be reached, each driven
# through THIS script so the argument handling and the premise guards are on
# the path too. No case is asserted by reading source: the exit code is read
# off a real run.
#
#   clean          the committed corpus and the committed builder       -> 0
#   wrong-name     one corpus row's expected capability NAME changed to
#                  a name that page never asks for, so the classifier
#                  and the corpus disagree                              -> 1
#   no-corpus      a fixture directory holding no cases.tsv             -> 2
#   bad-usage      an option the parser does not take                   -> 2
#
# THE CLEAN CASE GUARDS THE OTHERS' PREMISE. If the committed corpus does not
# exit 0, every case below would be red for that reason rather than its own -
# exit 2 for the whole self-test, never a pass on the three that followed.
#
# THE MUTATED CORPUS IS A COPY UNDER mktemp AND THE REPOSITORY IS NOT TOUCHED.
# A1 hashes every tracked file before and after the builder runs; a self-test
# that wrote a corpus file into the tree would make A1 report the builder
# moving a repository file, which is the exact false positive this check's own
# limitations block warns about.
#
# WHAT THIS SELF-TEST DOES NOT ASSERT, printed rather than passed silently: it
# reads the exit CODE and never the wording of a finding, so a case that went
# red for the wrong reason is invisible here.
# ---------------------------------------------------------------------------
if [ "$MODE" = "selftest" ]; then
  SB="$(mktemp -d "${TMPDIR:-/tmp}/check-view-readonly-selftest.XXXXXX")" \
    || die_unmeasured "cannot create a temporary directory to build the self-test's corpus in; nothing was driven"
  trap 'rm -rf "$SB"' EXIT HUP INT TERM

  mkdir -p "$SB/no-corpus"
  cp -R "$FIXTURE" "$SB/mutated" \
    || die_unmeasured "the fixture corpus could not be copied, so the case that must go red was never built. Unmeasured, not a pass"

  # ONE ROW, ONE FIELD. The `names` column of the first spelling case is the
  # set of capability names the classifier must come back with; pointing it at
  # a name that page never asks for is the smallest possible disagreement
  # between the corpus and the classifier, and it is the only difference
  # between this case and the clean one - so the exit code moving from 0 to 1
  # is attributable to it and to nothing else.
  #
  # awk writes a new file rather than editing in place: `sed -i` takes an
  # argument on BSD and none on GNU, and this repository has shipped that
  # difference as a CI-only failure before.
  awk -F'\t' 'BEGIN { OFS = "\t" }
              $1 == "bracket-double-quote" { $5 = "a-capability-this-page-never-asks-for" }
              { print }' \
      "$FIXTURE/cases.tsv" > "$SB/mutated/cases.tsv" \
    || die_unmeasured "the corpus copy could not be rewritten, so the case that must go red was never built. Unmeasured, not a pass"
  if cmp -s "$FIXTURE/cases.tsv" "$SB/mutated/cases.tsv"; then
    die_unmeasured "rewriting the corpus copy changed nothing, so the wrong-name case is identical to the clean one and would prove only that the clean case passes twice. Unmeasured, not a pass"
  fi

  SELF_CASES=0
  SELF_FAILED=0
  # R39.b: the reached half of the declaration below is ACCUMULATED here,
  # one entry per case as it ran. A literal list would satisfy the reader
  # and prove nothing.
  CODES=""

  # $1 case, $2 expected exit, $3 what the case is, then the argv to drive.
  #
  # `|| _rc=$?` on the SAME LINE as the command. Three of the four cases exit
  # non-zero on purpose, `set -e` would end the run at the first one, and a
  # `$(...)` or a pipeline between the command and the read of `$?` resets it -
  # which is how a self-test reports four passes having measured none.
  self_drive() {
    _name="$1"; _want="$2"; _why="$3"
    shift 3
    _rc=0
    bash "$0" "$@" > "$SB/$_name.out" 2> "$SB/$_name.err" || _rc=$?
    SELF_CASES=$((SELF_CASES + 1))
    CODES="$CODES$_rc
"
    if [ "$_rc" = "$_want" ]; then
      printf '  held:    case %-12s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
    else
      printf '  FINDING: case %-12s expected %s  observed %s  %s\n' "$_name" "$_want" "$_rc" "$_why"
      SELF_FAILED=$((SELF_FAILED + 1))
    fi
  }

  SELF_RC=0
  bash "$0" --root "$ROOT" --builder "$BUILDER" --fixture "$FIXTURE" \
    > "$SB/clean.out" 2> "$SB/clean.err" || SELF_RC=$?
  if [ "$SELF_RC" -ne 0 ]; then
    printf '  the clean case exited %d, not 0.\n' "$SELF_RC"
    die_unmeasured "the committed corpus did not produce a clean run, so every failing case below would be red for that reason instead of its own. Unmeasured, not a corpus that held"
  fi
  SELF_CASES=1
  CODES="$CODES$SELF_RC
"
  printf '  held:    case %-12s expected %s  observed %s  %s\n' "clean" "0" "0" \
    "the committed corpus and the committed builder: nothing moved, and every case reached the classification and the names it declares"

  self_drive wrong-name 1 \
    "one corpus row expects a capability name the page never asks for, so the classifier and the corpus disagree and the disagreement is a finding" \
    --root "$ROOT" --builder "$BUILDER" --fixture "$SB/mutated"
  self_drive no-corpus 2 \
    "a fixture directory with no cases.tsv: the classifier would run against the real page alone, and one that matched nothing would call that page clean too - unmeasured, never a pass" \
    --root "$ROOT" --builder "$BUILDER" --fixture "$SB/no-corpus"
  self_drive bad-usage 2 \
    "an option this parser does not take: bad usage is refused rather than ignored" \
    --root "$ROOT" --no-such-option

  printf '  self-test cases driven: %d. Cases that did not hold: %d\n' \
    "$SELF_CASES" "$SELF_FAILED"

  # The R39.b declaration. The reached half is computed from the cases
  # above; the documented half is the contract in this file's header.
  REACHED="$(printf '%s' "$CODES" | sort -u | tr '\n' ' ' | sed 's/  *$//')"
  MISSING=""
  for want in 0 1 2; do
    printf '%s' "$CODES" | grep -qx "$want" || MISSING="$MISSING $want"
  done
  printf '    exit codes reached: %s   documented: 0 1 2\n' "$REACHED"
  printf '  NOT ASSERTED: the wording of any finding. Each case reads the exit CODE, so a case that went red for the wrong reason is invisible here and is read off the case output by hand.\n'
  if [ "$SELF_FAILED" -ne 0 ]; then
    printf 'check-view-readonly: %d self-test case(s) did not produce the exit code the contract declares for them.\n' "$SELF_FAILED" >&2
    exit 1
  fi
  if [ -n "$MISSING" ]; then
    printf 'check-view-readonly: documented exit code(s) no self-test case reached:%s\n' "$MISSING" >&2
    exit 1
  fi
  printf '  R39 for this tool: the self-test exists and reaches 0, 1 and 2 by driving the real check, not by reading its source.\n'
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Paths are printed repo-relative. An absolute path in this output is somebody's
# home directory in a committed file.
rel() { case "$1" in "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;; *) printf '%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" ;; esac; }

cat > "$TMP/snap.py" <<'PY'
"""Hash one work tree. stdout: sha256<TAB>mtime_ns<TAB>relpath, sorted.

A file that is listed and cannot be opened is recorded as `unreadable`, which
compares equal to itself and unequal to any content - an unreadable file is
never silently dropped out of the denominator.
"""
import hashlib
import os
import sys

root, listing = sys.argv[1], sys.argv[2]
with open(listing, errors="replace") as fh:
    rels = [ln.rstrip("\n") for ln in fh if ln.strip()]

rows = []
for rel in sorted(set(rels)):
    p = os.path.join(root, rel)
    try:
        st = os.lstat(p)
    except OSError:
        rows.append(("absent", "absent", rel))
        continue
    if os.path.islink(p):
        rows.append(("symlink:" + os.readlink(p), str(st.st_mtime_ns), rel))
        continue
    if not os.path.isfile(p):
        rows.append(("not-a-file", str(st.st_mtime_ns), rel))
        continue
    h = hashlib.sha256()
    try:
        with open(p, "rb") as fh:
            for blk in iter(lambda: fh.read(1 << 20), b""):
                h.update(blk)
    except OSError:
        rows.append(("unreadable", str(st.st_mtime_ns), rel))
        continue
    rows.append((h.hexdigest(), str(st.st_mtime_ns), rel))

out = sys.stdout
for row in rows:
    out.write("\t".join(row) + "\n")
PY

cat > "$TMP/cmp.py" <<'PY'
"""Compare two snapshots.

stdout is ONE BARE PATH per examined file and nothing else - the caller prints
it straight through as coverage, so a summary line loose in this stream would
be read as a file path. Counts and findings go to the report file named as
argv[3], as `hashed<TAB>n`, `moved<TAB>n` and `finding<TAB>text`.

Content and mtime are separate findings. A rewrite with identical bytes is
still a write, and a build that touches a file it was only supposed to read is
a build that will make something else's timestamp comparison wrong later.
"""
import sys


def load(path):
    rows = {}
    with open(path, errors="replace") as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            if not ln:
                continue
            digest, mtime, rel = ln.split("\t", 2)
            rows[rel] = (digest, mtime)
    return rows


before, after = load(sys.argv[1]), load(sys.argv[2])
findings = []
out = sys.stdout
for rel in sorted(set(before) | set(after)):
    out.write(rel + "\n")
    b, a = before.get(rel), after.get(rel)
    # `absent` is the recorded state of a path that was listed and was not
    # there. It is a state, not a hash: a file that appears during the run is
    # a file the generator CREATED, and reporting that as "contents changed"
    # would describe the wrong event.
    b_absent = b is None or b[0] == "absent"
    a_absent = a is None or a[0] == "absent"
    if b_absent and a_absent:
        continue
    if b_absent:
        findings.append("%s: created by the generator; it was not in the tree before the run" % rel)
        continue
    if a_absent:
        findings.append("%s: removed by the generator" % rel)
        continue
    if b[0] != a[0]:
        findings.append("%s: contents changed across the generator run" % rel)
    elif b[1] != a[1]:
        findings.append("%s: modification time changed across the generator run; "
                        "the bytes are the same, so this is a rewrite, not an edit" % rel)

with open(sys.argv[3], "w") as rep:
    rep.write("hashed\t%d\n" % len(set(before) | set(after)))
    rep.write("moved\t%d\n" % len(findings))
    for f in findings:
        rep.write("finding\t%s\n" % f)
PY

cat > "$TMP/caps.py" <<'PY'
"""Read what a page REACHES FOR, by parsing its JavaScript rather than its bytes.

Called with PATH DISPLAY pairs; emits one block per file:

    file<TAB>DISPLAY
    bytes<TAB>n | jsbytes<TAB>n | readable<TAB>n | name<TAB>capability
    note<TAB>text | finding<TAB>text | findings<TAB>n
    end

or `unreadable<TAB>reason` in place of the counts.
"""
import re
import sys

OUTPUT_ONLY = {"downloads"}
SELF_PUBLISHING = {
    "artifact": "publishes new versions of the page itself",
    "self": "publishes new versions of the page itself",
}
EVALUATORS = {"eval", "Function", "execScript"}
DEFERRED_EVALUATORS = {"setTimeout", "setInterval"}
GLOBALS = {"window", "self", "globalThis", "top", "parent", "frames"}

MAXDEPTH = 4
WINDOW = 8192

# ---------------------------------------------------------------- tokenizer

PUNCT = sorted([
    ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=",
    "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=",
    "*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>",
    "{", "}", "(", ")", "[", "]", ";", ",", "<", ">", "+", "-", "*", "/", "%",
    "&", "|", "^", "!", "~", "?", ":", "=", ".", "#", "@",
], key=len, reverse=True)

ASSIGN_OPS = {"=", "+=", "-=", "*=", "/=", "%=", "**=", "<<=", ">>=", ">>>=",
              "&=", "|=", "^=", "&&=", "||=", "??="}
REGEX_OK_AFTER_WORD = {
    "return", "typeof", "instanceof", "in", "of", "new", "delete", "void",
    "throw", "case", "do", "else", "yield", "await",
}
KEYWORDS = {
    "var", "let", "const", "function", "class", "return", "if", "else", "for",
    "while", "do", "switch", "case", "default", "break", "continue", "new",
    "delete", "typeof", "instanceof", "in", "of", "void", "throw", "try",
    "catch", "finally", "yield", "await", "async", "this", "null", "true",
    "false", "undefined", "extends", "super", "import", "export", "with",
}

WS_CHARS = " \t\r\n\v\f\u00a0\u2028\u2029\ufeff"
LINE_END = "\n\r\u2028\u2029"

IDSTART = re.compile(r"[A-Za-z_$]")
IDCHAR = re.compile(r"[A-Za-z0-9_$]")
NUM = re.compile(r"(?:0[xXbBoO][0-9a-fA-F_]+|(?:[0-9][0-9_]*)?\.?[0-9][0-9_]*(?:[eE][+-]?[0-9]+)?)n?")


class Unterminated(Exception):
    pass


class Tok(object):
    __slots__ = ("kind", "start", "end", "text", "value", "parts", "esc")

    def __init__(self, kind, start, end, text, value=None, parts=None, esc=False):
        self.kind = kind
        self.start = start
        self.end = end
        self.text = text
        self.value = value
        self.parts = parts
        self.esc = esc

    def is_p(self, s):
        return self.kind == "punct" and self.text == s


SIMPLE_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v",
              "0": "\0", "\\": "\\", "'": "'", '"': '"', "`": "`", "\n": "",
              "\r": "", "/": "/"}


def decode(raw):
    """Decode a JS string body. -> (text, had_escape)."""
    if "\\" not in raw:
        return raw, False
    out = []
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= n:
            break
        e = raw[i]
        if e == "x" and i + 2 < n:
            try:
                out.append(chr(int(raw[i + 1:i + 3], 16)))
                i += 3
                continue
            except ValueError:
                pass
        if e == "u":
            if i + 1 < n and raw[i + 1] == "{":
                close = raw.find("}", i + 2)
                if close > 0:
                    try:
                        out.append(chr(int(raw[i + 2:close], 16)))
                        i = close + 1
                        continue
                    except ValueError:
                        pass
            elif i + 4 < n:
                try:
                    out.append(chr(int(raw[i + 1:i + 5], 16)))
                    i += 5
                    continue
                except ValueError:
                    pass
        if e in SIMPLE_ESC:
            out.append(SIMPLE_ESC[e])
        else:
            out.append(e)
        i += 1
    return "".join(out), True


def _skip_trivia(src, i, stop):
    """Whitespace and comments. A comment cannot execute, so it is skipped."""
    while i < stop:
        c = src[i]
        if c in WS_CHARS:
            i += 1
            continue
        if c == "/" and i + 1 < stop:
            if src[i + 1] == "/":
                j = i + 2
                while j < stop and src[j] not in LINE_END:
                    j += 1
                i = j
                continue
            if src[i + 1] == "*":
                j = src.find("*/", i + 2)
                if j < 0 or j >= stop:
                    raise Unterminated("a /* block comment is never closed")
                i = j + 2
                continue
        return i
    return i


def _scan_quoted(src, i, stop, q):
    j = i + 1
    while j < stop:
        c = src[j]
        if c == "\\":
            j += 2
            continue
        if c == q:
            return j + 1
        if c in "\n\r" and q != "`":
            raise Unterminated("a %s quoted string runs past the end of its line" % q)
        j += 1
    raise Unterminated("a %s quoted string is never closed" % q)


def tokenize(src, start, stop, max_tokens=0):
    """Significant tokens of src[start:stop]. Trivia is dropped, offsets kept."""
    toks = []
    i = start
    prev = None
    while True:
        i = _skip_trivia(src, i, stop)
        if i >= stop:
            return toks
        c = src[i]
        if c in "\"'":
            end = _scan_quoted(src, i, stop, c)
            val, esc = decode(src[i + 1:end - 1])
            t = Tok("str", i, end, src[i:end], val, esc=esc)
        elif c == "`":
            end, parts, esc = _scan_template(src, i, stop)
            t = Tok("tmpl", i, end, src[i:end], None, parts, esc)
        elif IDSTART.match(c):
            j = i + 1
            while j < stop and IDCHAR.match(src[j]):
                j += 1
            t = Tok("name", i, j, src[i:j])
        elif c.isdigit() or (c == "." and i + 1 < stop and src[i + 1].isdigit()):
            m = NUM.match(src, i)
            j = m.end() if m else i + 1
            t = Tok("num", i, j, src[i:j])
        elif c == "/" and _regex_here(prev):
            end = _scan_regex(src, i, stop)
            t = Tok("regex", i, end, src[i:end])
        else:
            for p in PUNCT:
                if src.startswith(p, i) and i + len(p) <= stop:
                    t = Tok("punct", i, i + len(p), p)
                    break
            else:
                t = Tok("punct", i, i + 1, c)
        toks.append(t)
        prev = t
        i = t.end
        if max_tokens and len(toks) >= max_tokens:
            return toks


def _regex_here(prev):
    if prev is None:
        return True
    if prev.kind in ("num", "str", "tmpl", "regex"):
        return False
    if prev.kind == "name":
        return prev.text in REGEX_OK_AFTER_WORD
    return prev.text not in (")", "]", "}", "++", "--")


def _scan_regex(src, i, stop):
    j = i + 1
    inclass = False
    while j < stop:
        c = src[j]
        if c == "\\":
            j += 2
            continue
        if c == "[":
            inclass = True
        elif c == "]":
            inclass = False
        elif c == "/" and not inclass:
            j += 1
            while j < stop and IDCHAR.match(src[j]):
                j += 1
            return j
        elif c in "\n\r":
            raise Unterminated("a / regular expression runs past the end of its line")
        j += 1
    raise Unterminated("a / regular expression is never closed")


def _scan_template(src, i, stop):
    """-> (end, parts, had_escape). parts: ('s', text) or ('e', start, end)."""
    parts = []
    chunk = []
    esc = False
    j = i + 1
    while j < stop:
        c = src[j]
        if c == "\\":
            chunk.append(src[j:j + 2])
            esc = True
            j += 2
            continue
        if c == "`":
            text, had = decode("".join(chunk))
            parts.append(("s", text))
            return j + 1, parts, esc or had
        if c == "$" and j + 1 < stop and src[j + 1] == "{":
            text, had = decode("".join(chunk))
            esc = esc or had
            parts.append(("s", text))
            chunk = []
            k = _match_brace(src, j + 1, stop)
            parts.append(("e", j + 2, k - 1))
            j = k
            continue
        chunk.append(c)
        j += 1
    raise Unterminated("a ` template literal is never closed")


def _match_brace(src, i, stop):
    """i is at `{`; -> index just past the matching `}`."""
    depth = 0
    j = i
    prev = None
    while j < stop:
        j = _skip_trivia(src, j, stop)
        if j >= stop:
            break
        c = src[j]
        if c in "\"'":
            j = _scan_quoted(src, j, stop, c)
            prev = Tok("str", 0, 0, "")
            continue
        if c == "`":
            j, _p, _e = _scan_template(src, j, stop)
            prev = Tok("tmpl", 0, 0, "")
            continue
        if c == "/" and _regex_here(prev):
            j = _scan_regex(src, j, stop)
            prev = Tok("regex", 0, 0, "")
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        prev = Tok("punct", 0, 0, c)
        j += 1
    raise Unterminated("a ${ substitution is never closed")


# ------------------------------------------------------- JavaScript regions

SCRIPT_OPEN = re.compile(r"<script\b[^>]*>", re.I)
SCRIPT_CLOSE = re.compile(r"</script", re.I)
ON_ATTR = re.compile(r"""(?<![A-Za-z0-9_-])on[a-zA-Z]{2,16}\s*=\s*(?:"([^"]*)"|'([^']*)')""")
JS_URL = re.compile(r"""(?:href|src|action)\s*=\s*(?:"javascript:([^"]*)"|'javascript:([^']*)')""", re.I)


def js_regions(src):
    """Spans of src that a browser hands to the JavaScript engine."""
    out = []
    for m in SCRIPT_OPEN.finditer(src):
        c = SCRIPT_CLOSE.search(src, m.end())
        out.append((m.end(), c.start() if c else len(src), "a <script> body"))
    for m in ON_ATTR.finditer(src):
        g = 1 if m.group(1) is not None else 2
        out.append((m.start(g), m.end(g), "an inline event-handler attribute"))
    for m in JS_URL.finditer(src):
        g = 1 if m.group(1) is not None else 2
        out.append((m.start(g), m.end(g), "a javascript: URL"))
    return out


def match_close(T, i):
    """i is at an opening bracket token; -> index just past its partner."""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opens = set(pairs)
    closes = set(pairs.values())
    depth = 0
    j = i
    while j < len(T):
        if T[j].kind == "punct":
            if T[j].text in opens:
                depth += 1
            elif T[j].text in closes:
                depth -= 1
                if depth == 0:
                    return j + 1
        j += 1
    return len(T)


# ------------------------------------------------------- the constant folder

def fold_primary(src, T, i, env, depth):
    """-> (ok, value, next_index, tags, why_not)."""
    if i >= len(T):
        return (False, None, i, set(), "the expression ends before it names anything")
    t = T[i]
    if t.kind == "str":
        return (True, t.value, i + 1, {"a string escape"} if t.esc else set(), None)
    if t.kind == "tmpl":
        tags = {"a template literal"}
        if t.esc:
            tags.add("a string escape")
        out = []
        for p in t.parts:
            if p[0] == "s":
                out.append(p[1])
                continue
            sub = safe_tokens(src, p[1], p[2])
            ok, val, j, tg, why = fold_expr(src, sub, 0, env, depth)
            if not ok or j != len(sub):
                return (False, None, i + 1, tags,
                        why or "a template substitution this check cannot fold")
            out.append(val)
            tags |= tg | {"a template substitution"}
        return (True, "".join(out), i + 1, tags, None)
    if t.kind == "name":
        if t.text in env:
            return (True, env[t.text][0], i + 1, {"the binding `%s`" % t.text} | env[t.text][1], None)
        return (False, None, i + 1, set(),
                "the name `%s` is not bound to a string this check can read" % t.text)
    if t.is_p("("):
        k = match_close(T, i)
        ok, val, j, tags, why = fold_expr(src, T, i + 1, env, depth)
        if not ok or j != k - 1:
            return (False, None, k, tags, why or "a parenthesised expression this check cannot fold")
        return (True, val, k, tags, None)
    return (False, None, i + 1, set(), "a value this check cannot fold to a string")


def fold_expr(src, T, i, env, depth):
    """`a` + `b` + ... , and nothing else. Any other operator is unfoldable."""
    ok, val, j, tags, why = fold_primary(src, T, i, env, depth)
    if not ok:
        return (False, None, j, tags, why)
    while j < len(T) and T[j].is_p("+"):
        ok2, v2, j2, tg2, why2 = fold_primary(src, T, j + 1, env, depth)
        if not ok2:
            return (False, None, j2, tags, why2)
        val += v2
        tags = tags | tg2 | {"a concatenation"}
        j = j2
    return (True, val, j, tags, None)


def fold_arg(src, T, i, env, depth):
    """First argument of the call whose `(` is token i."""
    if i + 1 < len(T) and T[i + 1].is_p(")"):
        return (False, None, set(), "the call names nothing at all")
    ok, val, j, tags, why = fold_expr(src, T, i + 1, env, depth)
    if not ok:
        return (False, None, tags, why)
    if j >= len(T) or not (T[j].is_p(",") or T[j].is_p(")")):
        return (False, None, tags, "the first argument runs into an operator this check cannot fold")
    return (True, val, tags, None)


def safe_tokens(src, start, stop):
    """Tokens, giving up quietly at an unterminated construct rather than raising.

    The byte-level nets have already matched at `start`; a tail this cannot
    tokenize costs a fold, and a fold that does not happen is a finding.
    """
    try:
        return tokenize(src, start, stop)
    except Unterminated:
        pass
    lo, hi = start, stop
    best = []
    for _ in range(14):
        if hi <= lo:
            break
        mid = (lo + hi) // 2
        try:
            best = tokenize(src, start, mid)
            lo = mid + 1
        except Unterminated:
            hi = mid
    return best


# ------------------------------------------------ bindings, single-assignment
#
# A name folds only when this file can see EXACTLY ONE write to it. Every
# shape below is counted as a write, including the ones that carry no value -
# a second write of any kind makes the name unfoldable, and unfoldable is a
# finding wherever a capability name was wanted. A write shape not listed here
# would be missed, which is the acknowledged hole; the safe direction is that
# missing a DECLARATION costs a fold, and missing a RE-assignment is the one
# that could resolve a name wrongly, so every assignment operator, every
# increment, every parameter list and every destructuring pattern is counted.

def _mark(writes, name):
    writes[name] = writes.get(name, 0) + 1


def _mark_names(T, a, b, writes):
    for k in range(a, min(b, len(T))):
        if T[k].kind == "name" and T[k].text not in KEYWORDS:
            if k > 0 and T[k - 1].is_p("."):
                continue
            if k + 1 < len(T) and T[k + 1].is_p(":"):
                continue
            _mark(writes, T[k].text)


def _declarators(src, T, ridx, i, writes, decls):
    """After `var`/`let`/`const`. Records each bound name and its initializer."""
    while i < len(T):
        t = T[i]
        if t.kind == "punct" and t.text in "{[":
            k = match_close(T, i)
            _mark_names(T, i + 1, k - 1, writes)
            i = k
        elif t.kind == "name" and t.text not in KEYWORDS:
            _mark(writes, t.text)
            if i + 1 < len(T) and T[i + 1].is_p("="):
                decls.setdefault(t.text, []).append((ridx, i + 2))
            i += 1
        else:
            return i
        # Skip the initializer, if any, to the comma that ends this declarator.
        depth = 0
        while i < len(T):
            tt = T[i]
            if tt.kind == "punct":
                if tt.text in "([{":
                    depth += 1
                elif tt.text in ")]}":
                    if depth == 0:
                        return i
                    depth -= 1
                elif tt.text == "," and depth == 0:
                    break
                elif tt.text == ";" and depth == 0:
                    return i
            i += 1
        if i < len(T) and T[i].is_p(","):
            i += 1
            continue
        return i
    return i


def collect_writes(src, T, ridx, writes, decls):
    i = 0
    while i < len(T):
        t = T[i]
        if t.kind == "name":
            if t.text in ("var", "let", "const"):
                i = _declarators(src, T, ridx, i + 1, writes, decls)
                continue
            if t.text in ("function", "class"):
                j = i + 1
                if j < len(T) and T[j].kind == "name" and T[j].text not in KEYWORDS:
                    _mark(writes, T[j].text)
                    j += 1
                if j < len(T) and T[j].is_p("("):
                    k = match_close(T, j)
                    _mark_names(T, j + 1, k - 1, writes)
                    i = k
                    continue
                i = j
                continue
            if t.text == "catch" and i + 1 < len(T) and T[i + 1].is_p("("):
                k = match_close(T, i + 1)
                _mark_names(T, i + 2, k - 1, writes)
                i = k
                continue
            prevdot = i > 0 and T[i - 1].is_p(".")
            if not prevdot and t.text not in KEYWORDS:
                nx = T[i + 1] if i + 1 < len(T) else None
                pv = T[i - 1] if i > 0 else None
                if nx is not None and nx.kind == "punct" and (
                        nx.text in ASSIGN_OPS or nx.text in ("++", "--") or nx.text == "=>"):
                    _mark(writes, t.text)
                elif nx is not None and nx.kind == "name" and nx.text in ("of", "in") \
                        and pv is not None and (pv.is_p("(") or pv.kind == "name"
                                                and pv.text in ("var", "let", "const")):
                    _mark(writes, t.text)
                elif pv is not None and pv.kind == "punct" and pv.text in ("++", "--"):
                    _mark(writes, t.text)
        elif t.kind == "punct" and t.text == "(":
            k = match_close(T, i)
            if k < len(T) and T[k].is_p("=>"):
                _mark_names(T, i + 1, k - 1, writes)
        elif t.kind == "punct" and t.text in "{[":
            k = match_close(T, i)
            if k < len(T) and T[k].kind == "punct" and T[k].text in ASSIGN_OPS:
                _mark_names(T, i + 1, k - 1, writes)
        i += 1


def build_env(src, regions, inherited):
    """-> (env, unparsed, jsbytes). env: name -> (value, tags)."""
    writes = {}
    decls = {}
    unparsed = []
    jsbytes = 0
    toklists = []
    for a, b, label in regions:
        jsbytes += max(0, b - a)
        try:
            T = tokenize(src, a, b)
        except Unterminated as exc:
            unparsed.append("%s could not be parsed as JavaScript: %s" % (label, exc))
            continue
        collect_writes(src, T, len(toklists), writes, decls)
        toklists.append((T, label))
    env = dict(inherited)
    for _ in range(3):
        changed = False
        for name, positions in decls.items():
            if name in env or writes.get(name, 0) != 1 or len(positions) != 1:
                continue
            ridx, tokidx = positions[0]
            if ridx >= len(toklists):
                continue
            T = toklists[ridx][0]
            ok, val, _j, tags, _why = fold_expr(src, T, tokidx, env, 0)
            if ok:
                env[name] = (val, tags)
                changed = True
        if not changed:
            break
    return env, unparsed, jsbytes, toklists


# ------------------------------------------------------------------- the nets

# `claude` as a whole identifier, not the `.claude/...` path text the real page
# carries over a hundred times.
RECV = re.compile(r"(?<![A-Za-z0-9_$])(?:window\s*(?:\?\s*)?\.\s*)?claude(?![A-Za-z0-9_$])")
PROP = re.compile(r"""\.\s*use(?![A-Za-z0-9_$])|\[\s*(['"])use\1\s*\]""")
GUARD = re.compile(r"""(?:!|&&|\|\||typeof|\bif\s*\(|\bwhile\s*\()\s*$""")
DESTRUCT = re.compile(r"\{[^{}]*(?<![A-Za-z0-9_$])use(?![A-Za-z0-9_$])[^{}]*\}\s*=\s*$")


class Acc(object):
    def __init__(self):
        self.findings = []
        self.notes = []
        self.names = []
        self.readable = 0


def describe(tags):
    return ", ".join(sorted(tags))


def classify(acc, name, tags, how):
    """The verdict on one resolved capability name.

    A name written as a plain string literal AT THE CALL SITE may be clean. A
    name this check had to ASSEMBLE - out of a concatenation, a template, a
    binding, a string escape - is reported with the name and is a finding
    whatever the name turns out to be. The fold is a static approximation of a
    run-time value, and a check that certifies what it inferred is a check
    that will one day certify something wrong. Naming it is the point; calling
    it safe is not.
    """
    acc.names.append(name)
    acc.readable += 1
    if tags:
        acc.findings.append(
            "asks for `%s`, a capability name this check had to assemble out of %s rather "
            "than read at the call site. The name is reported because it folded, and it is "
            "still a finding: a folded name is this check's inference about a run-time "
            "value, and an inference is not a demonstration that the page asks only for "
            "output (%s)" % (name, describe(tags), how))
        return
    if name in SELF_PUBLISHING:
        acc.findings.append(
            "declares `%s`, which %s. A view is output; a page that saves over itself is a "
            "second source of truth that can disagree with the repository (%s)"
            % (name, SELF_PUBLISHING[name], how))
        return
    if name in OUTPUT_ONLY:
        acc.notes.append(
            "declares `%s` - output: it hands the viewer a file and reads nothing back (%s)"
            % (name, how))
        return
    acc.findings.append(
        "declares `%s`, which this check cannot classify. An unrecognised capability has not "
        "been shown to be output-only; classify it here or stop declaring it (%s)" % (name, how))


def stop_for(off, regions, src):
    for a, b, _l in regions:
        if a <= off < b:
            return b
    return min(len(src), off + WINDOW)


def read_access(src, T, i, env, depth):
    """Resolve the property reached at token i. -> (kind, name, tags, next_i)."""
    if i >= len(T):
        return ("none", None, set(), i)
    t = T[i]
    if t.is_p("?."):
        i += 1
        if i >= len(T):
            return ("none", None, set(), i)
        t = T[i]
        if t.kind == "name":
            return ("name", t.text, set(), i + 1)
        if not t.is_p("["):
            return ("none", None, set(), i)
    elif t.is_p("."):
        i += 1
        if i < len(T) and T[i].kind == "name":
            return ("name", T[i].text, set(), i + 1)
        return ("unreadable", None, set(), i)
    if i < len(T) and T[i].is_p("["):
        e = match_close(T, i)
        ok, val, j, tags, _why = fold_expr(src, T, i + 1, env, depth)
        if ok and j == e - 1 and isinstance(val, str):
            return ("name", val, tags, e)
        return ("unreadable", None, tags, e)
    return ("none", None, set(), i)


def read_call(T, i):
    """Token index of the `(` of a call at i, or -1."""
    if i < len(T) and T[i].is_p("?."):
        i += 1
    if i < len(T) and T[i].is_p("("):
        return i
    return -1


def call_verdict(src, T, callidx, env, depth, acc, how, extra_tags):
    ok, val, tags, why = fold_arg(src, T, callidx, env, depth)
    if ok and isinstance(val, str):
        classify(acc, val, tags | extra_tags, how)
        return True
    acc.findings.append(
        "reaches the capability with a name this check cannot read out of the page: %s. A "
        "name that is not in the file has not been shown to be output-only, and unreadable "
        "is never counted as absent (%s)" % (why or "it does not fold to a string", how))
    return False


def scan_reaches(src, regions, env, depth, acc):
    claimed = []
    for m in RECV.finditer(src):
        stop = stop_for(m.end(), regions, src)
        T = safe_tokens(src, m.end(), stop)
        kind, name, tags, ni = read_access(src, T, 0, env, depth)
        if kind == "none":
            if DESTRUCT.search(src[max(0, m.start() - 160):m.start()]):
                acc.findings.append(
                    "binds the capability request off the capability object by destructuring, "
                    "so the call site names neither the object nor the property. What it goes "
                    "on to ask for cannot be read from this line, and unknown is not none")
            continue
        claimed.append((m.end(), T[ni - 1].end if 0 < ni <= len(T) else m.end()))
        if kind == "unreadable":
            acc.findings.append(
                "reaches a property of the capability object whose name this check cannot fold "
                "out of the file. Unreadable is never counted as absent")
            continue
        if name != "use":
            acc.findings.append(
                "reaches `%s` on the capability object. This check classifies the capability "
                "request only; a page reaching anything else on that object has not been shown "
                "to be read-only" % name)
            continue
        ci = read_call(T, ni)
        if ci < 0:
            if GUARD.search(src[max(0, m.start() - 24):m.start()]):
                acc.notes.append("names the capability request in a truthiness test without "
                                 "calling it; a test declares nothing")
            else:
                acc.findings.append(
                    "takes the capability request as a value without calling it here. Where it "
                    "is called cannot be read from this line, so what it asks for is unknown - "
                    "and unknown is not none")
            continue
        call_verdict(src, T, ci, env, depth, acc, "named on the capability object", tags)
    for m in PROP.finditer(src):
        if any(a <= m.start() < b for a, b in claimed):
            continue
        stop = stop_for(m.end(), regions, src)
        T = safe_tokens(src, m.end(), stop)
        ci = read_call(T, 0)
        if ci < 0:
            if GUARD.search(src[max(0, m.start() - 24):m.start()]):
                acc.notes.append("a property named `use` read on a receiver this check cannot "
                                 "resolve, inside a truthiness test")
                continue
            acc.findings.append(
                "a property named `use` taken as a value on a receiver this check cannot "
                "resolve to the capability object. If that receiver is the capability object, "
                "this is a request whose name never appears here")
            continue
        sub = Acc()
        how = "called as `use` on a receiver this check cannot resolve to the capability object"
        call_verdict(src, T, ci, env, depth, sub, how, set())
        acc.names.extend(sub.names)
        acc.readable += sub.readable
        # Even an output-only name is a finding here: the NAME is readable and
        # the RECEIVER is not, and an alias of the capability object is the
        # same bytes as an unrelated one. Loud, and it says which it is.
        acc.findings.extend(sub.findings)
        for n in sub.notes:
            acc.findings.append("calls `use` with an output-only name on a receiver this check "
                                "cannot resolve to the capability object. The name is readable "
                                "and the receiver is not (%s)" % n)


GLOBAL_RECV = {"window", "self", "globalThis", "top", "parent", "frames"}


def _guarded_at(T, start):
    """Is the expression starting at token `start` only being tested for?"""
    if start <= 0:
        return False
    pv = T[start - 1]
    if pv.kind == "punct" and pv.text in ("!", "&&", "||"):
        return True
    if pv.kind == "name" and pv.text == "typeof":
        return True
    if pv.is_p("(") and start > 1 and T[start - 2].kind == "name" \
            and T[start - 2].text in ("if", "while"):
        return True
    return False


def scan_computed_receiver(src, toklists, env, depth, acc):
    """Net six. The capability OBJECT itself named by an expression.

    Every net above needs the seven letters of the receiver to appear in the
    file. `window["cla" + "ude"]` does not contain them, so nothing anchored on
    that identifier can see it, and if the property is then reached
    reflectively - `Reflect.get(window["cla" + "ude"], "use")` - the property
    net has nothing to match either. Both nets look past a page that reaches
    the capability twice.

    So: a global object indexed by a key that FOLDS to the receiver's name is
    the receiver, and what happens after it is read exactly as net one reads
    it - the same access resolution, the same call, the same verdict on the
    name. A reference with no access after it is a finding, as in net five.
    """
    for T, label in toklists:
        for i, t in enumerate(T):
            if t.kind != "name" or t.text not in GLOBAL_RECV:
                continue
            if i > 0 and (T[i - 1].is_p(".") or T[i - 1].is_p("?.")):
                continue
            k = i + 1
            if k < len(T) and T[k].is_p("?."):
                k += 1
            if k >= len(T) or not T[k].is_p("["):
                continue
            e = match_close(T, k)
            ok, val, j, ktags, _why = fold_expr(src, T, k + 1, env, depth)
            if not (ok and j == e - 1 and val == "claude"):
                continue
            how = ("named on a capability object this check had to assemble out of %s, in %s"
                   % (describe(ktags) or "a string literal", label))
            kind, name, tags, ni = read_access(src, T, e, env, depth)
            if kind == "none":
                acc.findings.append(
                    "builds the capability object out of %s and takes it as a value without "
                    "reaching into it here, in %s. Where it is handed to, and what is asked of "
                    "it there, cannot be read from this line - and unknown is not none"
                    % (describe(ktags) or "a string literal", label))
                continue
            if kind == "unreadable":
                acc.findings.append(
                    "reaches a property of an assembled capability object whose name this check "
                    "cannot fold out of the file (%s). Unreadable is never counted as absent"
                    % how)
                continue
            if name != "use":
                acc.findings.append(
                    "reaches `%s` on an assembled capability object. This check classifies the "
                    "capability request only; a page reaching anything else on that object has "
                    "not been shown to be read-only (%s)" % (name, how))
                continue
            ci = read_call(T, ni)
            if ci < 0:
                acc.findings.append(
                    "takes the capability request off an assembled capability object without "
                    "calling it here (%s). Where it is called cannot be read from this line" % how)
                continue
            call_verdict(src, T, ci, env, depth, acc, how, tags | ktags)


def scan_bare_receiver(src, toklists, acc):
    """Net five. The capability object taken as a VALUE, in code.

    `Reflect.get(window.claude, "u" + "se")("artifact")` reaches the request
    without ever writing a property access after `claude`, so nets one to three
    all walk past it - net one resolves no access and stops, and the property
    never appears as text anywhere. So a reference to the capability object
    that is NOT followed by an access is a finding in its own right: where it
    goes cannot be read from that line.

    Only inside JavaScript, and only on tokens. The byte nets read the whole
    file because HTML prose cannot be tokenized, but this one would fire on the
    words `window.claude` in a paragraph, and the corpus has a page that writes
    exactly that on purpose. A truthiness test is still not a declaration; the
    shipped page guards both of its references and this must stay quiet on it.
    """
    for T, label in toklists:
        for i, t in enumerate(T):
            if t.kind != "name" or t.text != "claude":
                continue
            start = i
            if i > 0 and (T[i - 1].is_p(".") or T[i - 1].is_p("?.")):
                if not (i > 1 and T[i - 2].kind == "name" and T[i - 2].text in GLOBAL_RECV):
                    # Somebody else's `.claude` property, not the global one.
                    continue
                start = i - 2
            j = i + 1
            if j < len(T) and (T[j].is_p(".") or T[j].is_p("?.") or T[j].is_p("[")):
                continue  # an access: nets one to three already read it
            if _guarded_at(T, start):
                acc.notes.append("names the capability object in a truthiness test without "
                                 "reaching into it; a test declares nothing (in %s)" % label)
                continue
            acc.findings.append(
                "takes the capability object as a value without reaching into it here, in %s. "
                "Where it is handed to, and what is asked of it there, cannot be read from this "
                "line - and unknown is not none" % label)


def scan_evaluators(src, toklists, env, depth, acc):
    """Net four. Text turned into code, inside JavaScript only.

    An evaluator is a finding in its own right on a view: what a page decides
    to ask for at run time is not in the page. When the text folds, it is
    scanned as source and what it reaches is named too - that is the whole
    reason the folder exists.
    """
    for T, label in toklists:
        for i, t in enumerate(T):
            if t.kind != "name" or (i > 0 and T[i - 1].is_p(".")):
                continue
            cand, ci, tags = None, i, set()
            if t.text in GLOBALS:
                kind, name, tg, ni = read_access(src, T, i + 1, env, depth)
                if kind != "name":
                    continue
                cand, ci, tags = name, ni - 1, tg
            elif t.text not in KEYWORDS:
                cand = t.text
            if cand is None:
                continue
            if cand not in EVALUATORS and cand not in DEFERRED_EVALUATORS:
                continue
            ci = read_call(T, ci + 1)
            if ci < 0:
                continue
            ok, val, atags, why = fold_arg(src, T, ci, env, depth)
            if cand in DEFERRED_EVALUATORS and not (ok and isinstance(val, str)):
                # `setTimeout(fn, 0)` schedules a function; only a STRING is
                # source, and a first argument that does not fold to one is an
                # ordinary callback, not an evaluator.
                continue
            how = "%s, in %s" % (cand, label)
            if not (ok and isinstance(val, str)):
                acc.findings.append(
                    "calls `%s`, which turns text into code, on text this check cannot fold: "
                    "%s. What the page goes on to ask for is decided at run time and is not in "
                    "the file at all (%s)" % (cand, why or "it does not fold to a string", how))
                continue
            acc.findings.append(
                "calls `%s`, which turns text into code. The text folded out of %s, so what it "
                "runs is reported below; a page that assembles its own source is not read-only "
                "by inspection (%s)" % (cand, describe(atags) or "a string literal", how))
            if depth >= MAXDEPTH:
                acc.findings.append(
                    "the evaluated text evaluates further text, deeper than this check follows. "
                    "Below this depth nothing is claimed")
                continue
            sub = Acc()
            scan_source(val, "the text passed to `%s`" % cand, env, depth + 1, sub)
            acc.readable += sub.readable
            acc.names.extend(sub.names)
            for f in sub.findings:
                acc.findings.append("inside the text passed to `%s`: %s" % (cand, f))
            for n in sub.notes:
                acc.findings.append("inside the text passed to `%s`, the evaluated source %s. "
                                    "Source built at run time is not a declaration this page "
                                    "makes; it is one it computes" % (cand, n))


def scan_source(src, label, inherited_env, depth, acc):
    if depth == 0:
        regions = js_regions(src)
    else:
        regions = [(0, len(src), label)]
    env, unparsed, jsbytes, toklists = build_env(src, regions, inherited_env)
    for u in unparsed:
        acc.notes.append("%s. The byte-level nets still read it; only the folding did not run"
                         % u)
    scan_reaches(src, regions, env, depth, acc)
    scan_bare_receiver(src, toklists, acc)
    scan_computed_receiver(src, toklists, env, depth, acc)
    scan_evaluators(src, toklists, env, depth, acc)
    return jsbytes


def emit(path, display):
    out = sys.stdout
    out.write("file\t%s\n" % display)
    try:
        with open(path, errors="replace") as fh:
            src = fh.read()
    except OSError as exc:
        out.write("unreadable\t%s\n" % (exc.strerror or "could not be opened"))
        out.write("end\n")
        return
    if not src.strip():
        out.write("unreadable\tthe file is empty\n")
        out.write("end\n")
        return
    acc = Acc()
    try:
        jsbytes = scan_source(src, display, {}, 0, acc)
    except RecursionError:
        out.write("unreadable\tthe page nests deeper than this parser follows\n")
        out.write("end\n")
        return
    out.write("bytes\t%d\n" % len(src))
    out.write("jsbytes\t%d\n" % jsbytes)
    out.write("readable\t%d\n" % acc.readable)
    for n in sorted(set(acc.names)):
        out.write("name\t%s\n" % n)
    for n in acc.notes:
        out.write("note\t%s\n" % n)
    for f in acc.findings:
        out.write("finding\t%s\n" % f)
    out.write("findings\t%d\n" % len(acc.findings))
    out.write("end\n")


args = sys.argv[1:]
if not args or len(args) % 2:
    sys.stderr.write("caps.py: expects PATH DISPLAY pairs\n")
    sys.exit(2)
for a in range(0, len(args), 2):
    emit(args[a], args[a + 1])
PY

# The listing is git's, so the .git directory is out of it by construction and
# an index refresh is never mistaken for a repository file moving. Ignored
# files are IN: a generator writing into a gitignored path has still written
# into the tree, and --exclude-standard would have hidden exactly that.
git -C "$ROOT" ls-files -co > "$TMP/filelist" \
  || die_unmeasured "could not list the work tree; the tree was not hashed, which is unmeasured and not clean"
[ -s "$TMP/filelist" ] || die_unmeasured "the work tree lists no files. Nothing was hashed; a run that examined nothing is not a clean run"

python3 "$TMP/snap.py" "$ROOT" "$TMP/filelist" > "$TMP/before" \
  || die_unmeasured "the work tree could not be hashed before the generator ran"

PAGE="$TMP/page.html"
BRC=0
bash "$BUILDER" "$ROOT" --out "$PAGE" > "$TMP/builder.out" 2> "$TMP/builder.err" || BRC=$?

# The tree is re-listed rather than reused: a file the generator CREATED is a
# finding, and reusing the first listing is how it would go unnoticed.
git -C "$ROOT" ls-files -co > "$TMP/filelist2" \
  || die_unmeasured "could not list the work tree after the generator ran"
cat "$TMP/filelist" "$TMP/filelist2" > "$TMP/filelist_union"
python3 "$TMP/snap.py" "$ROOT" "$TMP/filelist_union" > "$TMP/after" \
  || die_unmeasured "the work tree could not be hashed after the generator ran"
# `before` was taken over the first listing only. Widening it to the union
# without re-hashing would invent a value for a file that did not exist yet, so
# the widening is done by absence: anything in the union and not in `before` is
# recorded as having been absent.
python3 - "$TMP/before" "$TMP/filelist_union" > "$TMP/before_union" <<'PY'
import sys
seen = {}
with open(sys.argv[1], errors="replace") as fh:
    for ln in fh:
        ln = ln.rstrip("\n")
        if ln:
            seen[ln.split("\t", 2)[2]] = ln
with open(sys.argv[2], errors="replace") as fh:
    rels = sorted({ln.strip() for ln in fh if ln.strip()})
out = sys.stdout
for rel in rels:
    out.write(seen.get(rel, "absent\tabsent\t" + rel) + "\n")
PY

python3 "$TMP/cmp.py" "$TMP/before_union" "$TMP/after" "$TMP/tree.report" > "$TMP/tree.paths" \
  || die_unmeasured "the before/after comparison did not complete"

# --- coverage ---------------------------------------------------------------
#
# The tree listing already names every repository file, fixtures included, so a
# fixture path is printed only when it is NOT in that listing - a duplicate
# would claim the same file twice. `grep -q` exits 1 on no-match, which is the
# answer being asked for and not an error, so it is asked inside an `if` and
# never left to `set -e` to act on.
cat "$TMP/tree.paths"
print_if_unlisted() {
  local r; r="$(rel "$1")"
  if grep -qxF "$r" "$TMP/tree.paths"; then return 0; fi
  printf '%s\n' "$r"
}
print_if_unlisted "$CASES"

# --- A1: the generator moved no repository file -----------------------------
A1_N="$(awk -F'\t' '$1 == "hashed" { print $2 }' "$TMP/tree.report")"
A1_MOVED="$(awk -F'\t' '$1 == "moved" { print $2 }' "$TMP/tree.report")"
A1_OK=$((A1_N - A1_MOVED))
awk -F'\t' '$1 == "finding" { printf "  FINDING: %s\n", $2 }' "$TMP/tree.report"

# --- the page, and the corpus that holds the classifier to its job ----------
if [ "$BRC" -ne 0 ]; then
  printf '  the view generator exited %s. Its output is not reproduced here: it can carry an absolute path, and this text is tailed into a committed result file.\n' "$BRC"
  printf '  capability declarations read: unknown\n'
  printf '  REFUSED: the page could not be generated, so the number of capabilities it declares is unknown. Unknown is not zero.\n'
  if [ "$A1_MOVED" -ne 0 ]; then printf '  the tree comparison above still stands and found something.\n'; fi
  exit 2
fi

# One python invocation for the real page and the whole corpus. Sixteen
# interpreter starts for sixteen tiny files is the kind of cost that gets a
# check moved out of the default run.
set -- "$PAGE" "generated-page"
while IFS=$'\t' read -r _id _expect _group page _names _note; do
  case "${_id:-}" in ''|'#'*) continue ;; esac
  fp="$FIXTURE/pages/$page"
  [ -f "$fp" ] && [ -r "$fp" ] \
    || die_unmeasured "case '$_id' names a page that is not there or cannot be read. A corpus this check cannot read is not one that passed"
  print_if_unlisted "$fp"
  set -- "$@" "$fp" "$page"
done < "$CASES"

python3 "$TMP/caps.py" "$@" > "$TMP/caps.tsv" \
  || die_unmeasured "the classifier did not complete, so what the page and the corpus declare is unknown"

blockfield() {
  # $1 display name, $2 field. Empty when the block carries no such field.
  awk -F'\t' -v want="$1" -v key="$2" \
    '$1 == "file" { cur = ($2 == want); next }
     cur && $1 == key { print $2; exit }' "$TMP/caps.tsv"
}

# Every capability name the classifier RESOLVED on one page, sorted and joined
# with ';' so it can be compared to the case file's fifth field as one string.
# The classifier already emits them sorted and deduplicated; sorting again here
# means the comparison does not depend on that staying true. `none` is printed
# for an empty set, because an empty variable and an unread block look the same
# in shell and only one of them is an answer.
blocknames() {
  awk -F'\t' -v want="$1" \
    '$1 == "file" { cur = ($2 == want); next }
     cur && $1 == "name" { print $2 }' "$TMP/caps.tsv" | LC_ALL=C sort -u \
    | awk 'BEGIN { ORS = "" } { printf "%s%s", (NR > 1 ? ";" : ""), $0 } END { print (NR ? "\n" : "none\n") }'
}

# --- A2: the real generated page declares nothing beyond output -------------
A2_N=1
A2_OK=0
PAGE_UNREADABLE="$(blockfield generated-page unreadable)"
if [ -n "$PAGE_UNREADABLE" ]; then
  printf '  the generated page could not be read: %s\n' "$PAGE_UNREADABLE"
  printf '  capability declarations read: unknown\n'
  printf '  REFUSED: the page could not be read, so the number of capabilities it declares is unknown. Unknown is not zero.\n'
  if [ "$A1_MOVED" -ne 0 ]; then printf '  the tree comparison above still stands and found something.\n'; fi
  exit 2
fi
PAGE_BYTES="$(blockfield generated-page bytes)"
PAGE_JSBYTES="$(blockfield generated-page jsbytes)"
PAGE_READABLE="$(blockfield generated-page readable)"
PAGE_NAMES="$(blocknames generated-page)"
PAGE_FINDINGS="$(blockfield generated-page findings)"
printf '  page bytes read: %s\n' "$PAGE_BYTES"
printf '  page bytes tokenized as JavaScript: %s\n' "$PAGE_JSBYTES"
printf '  capability declarations read on the generated page: %s\n' "$PAGE_READABLE"
printf '  capability names resolved on the generated page: %s\n' "$PAGE_NAMES"
awk -F'\t' '$1 == "file" { cur = ($2 == "generated-page"); next }
            cur && $1 == "note" { printf "  the generated page %s\n", $2 }
            cur && $1 == "finding" { printf "  FINDING: the generated page %s\n", $2 }' "$TMP/caps.tsv"
if [ "$PAGE_FINDINGS" -eq 0 ]; then A2_OK=1; fi

# --- A3-A6: the corpus ------------------------------------------------------
#
# Per-assertion tallies. Never one flag: a group is upheld only when its own
# count of upheld cases equals its own count of cases.
A3_N=0; A3_OK=0     # an evasive spelling is still classified
A4_N=0; A4_OK=0     # a declaration that cannot be read is a finding
A5_N=0; A5_OK=0     # a readable name that is not output-only is a finding
A6_N=0; A6_OK=0     # a page declaring nothing forbidden is not flagged
A7_N=0; A7_OK=0     # a request assembled at run time is folded to its name
CORPUS_READABLE=0
NAMED_CASES=0       # cases that demand a resolved NAME, not just a verdict
CASE_FINDINGS=0
CASE_LINES="$TMP/caselines"
: > "$CASE_LINES"

while IFS=$'\t' read -r id expect group page names _note; do
  case "${id:-}" in ''|'#'*) continue ;; esac
  un="$(blockfield "$page" unreadable)"
  if [ -n "$un" ]; then
    die_unmeasured "case '$id' named a page the classifier could not read. A corpus case that was never classified is unmeasured, not a pass"
  fi
  n="$(blockfield "$page" findings)"
  r="$(blockfield "$page" readable)"
  CORPUS_READABLE=$((CORPUS_READABLE + r))

  got=clean
  if [ "$n" -gt 0 ]; then got=finding; fi
  ok=0
  case "$expect" in
    finding) if [ "$got" = finding ]; then ok=1; fi ;;
    clean)   if [ "$got" = clean ];   then ok=1; fi ;;
    *) die_unmeasured "case '$id' expects '$expect', which is not one of finding, clean. An expectation this check cannot read is not one it may skip" ;;
  esac

  # The verdict is half the expectation. The other half is WHICH capability the
  # classifier came back with, and it is the half 2.0 could not state: a page
  # that folds to `artifact` and one the check merely could not read are both
  # `finding`, and telling them apart is the entire reason 3.0 exists. `none`
  # is the sharper direction of the two - a check that invents a name it never
  # read has failed differently and worse than one that reads nothing.
  gotnames="$(blocknames "$page")"
  case "$names" in
    # The shape guard above already refused an empty field, because `read`
    # would have shifted it out of existence before this line ever saw it.
    # This arm is the second lock on the same door: if the field ever does
    # arrive empty, the run stops instead of judging a case with no expectation.
    '') die_unmeasured "case '$id' names no expectation for the capability names to be resolved. Use 'none' to assert that no name is resolved; an empty field is not an assertion" ;;
    none) : ;;
    *) NAMED_CASES=$((NAMED_CASES + 1)) ;;
  esac
  namesok=1
  if [ "$gotnames" != "$names" ]; then namesok=0; ok=0; fi

  case "$group" in
    spelling)   A3_N=$((A3_N + 1)); if [ "$ok" = 1 ]; then A3_OK=$((A3_OK + 1)); fi ;;
    unreadable) A4_N=$((A4_N + 1)); if [ "$ok" = 1 ]; then A4_OK=$((A4_OK + 1)); fi ;;
    forbidden)  A5_N=$((A5_N + 1)); if [ "$ok" = 1 ]; then A5_OK=$((A5_OK + 1)); fi ;;
    clean)      A6_N=$((A6_N + 1)); if [ "$ok" = 1 ]; then A6_OK=$((A6_OK + 1)); fi ;;
    folded)     A7_N=$((A7_N + 1)); if [ "$ok" = 1 ]; then A7_OK=$((A7_OK + 1)); fi ;;
    *) die_unmeasured "case '$id' names group '$group', which this check cannot count. A case counted under nothing is a case that asserts nothing" ;;
  esac

  if [ "$ok" = 1 ]; then
    printf '  case %s (%s): expected %s naming %s, got %s naming %s\n' \
      "$id" "$group" "$expect" "$names" "$got" "$gotnames" >> "$CASE_LINES"
  else
    printf '  case %s (%s): expected %s naming %s, GOT %s naming %s\n' \
      "$id" "$group" "$expect" "$names" "$got" "$gotnames" >> "$CASE_LINES"
    CASE_FINDINGS=$((CASE_FINDINGS + 1))
    if [ "$got" != "$expect" ] && [ "$expect" = finding ]; then
      printf '  FINDING: %s: a page that reaches the capability was classified clean. This is the 1.0 hole exactly: a declaration the check cannot see is reported as a declaration that is not there\n' "$id" >> "$CASE_LINES"
    elif [ "$got" != "$expect" ]; then
      printf '  FINDING: %s: a page that declares nothing forbidden was flagged. A check that cries wolf on the real dashboard gets switched off, and then nothing is asserted at all\n' "$id" >> "$CASE_LINES"
    fi
    if [ "$namesok" = 0 ] && [ "$names" = none ]; then
      printf '  FINDING: %s: the classifier resolved %s on a page where it must read no name at all. A name it did not read is a name it invented, and an invented name is how a page gets certified for something it never asked for\n' "$id" "$gotnames" >> "$CASE_LINES"
    elif [ "$namesok" = 0 ]; then
      printf '  FINDING: %s: the request had to be folded to %s and the classifier came back with %s. A finding that cannot say what the page asked for is the 2.0 answer, and it is the gap 3.0 exists to close\n' "$id" "$names" "$gotnames" >> "$CASE_LINES"
    fi
  fi
done < "$CASES"

cat "$CASE_LINES"

# --- the premises, guarded --------------------------------------------------
#
# Each of these is a classification that was never exercised. A group with no
# case in it holds vacuously forever, which is the shape of a check that passes
# for months without once seeing the thing it looks for.
[ "$((A3_N + A4_N + A5_N + A6_N + A7_N))" -gt 0 ] \
  || die_unmeasured "the corpus held no case at all. The classifier was run against a clean page and nothing else, and a classifier that matched nothing would call that page clean too. Unmeasured, not a pass"
[ "$A3_N" -gt 0 ] || die_unmeasured "no corpus case spells the capability request any way but the plain one, so the evasion that defeated the 1.0 check was never exercised. Unmeasured, not a pass"
[ "$A4_N" -gt 0 ] || die_unmeasured "no corpus case declares something this check cannot read, so whether an unreadable declaration is treated as an absent one was never exercised. Unmeasured, not a pass"
[ "$A5_N" -gt 0 ] || die_unmeasured "no corpus case names a capability that is not output-only, so the classification this check exists for was never exercised. Unmeasured, not a pass"
[ "$A6_N" -gt 0 ] || die_unmeasured "no corpus case must come back CLEAN, so this run cannot tell a classifier that reads from one that flags everything. Unmeasured, not a pass"
[ "$A7_N" -gt 0 ] || die_unmeasured "no corpus case assembles its capability request at run time, so the constant folder - the whole of what 3.0 added - was never exercised. A folder that never folded anything would pass this run. Unmeasured, not a pass"
[ "$CORPUS_READABLE" -gt 0 ] \
  || die_unmeasured "the classifier read no capability name anywhere in the corpus. Every finding it reported could have come from a pattern that matches nothing and refuses everything, and no positive case proves otherwise. Unmeasured, not a pass"
[ "$NAMED_CASES" -gt 0 ] \
  || die_unmeasured "no corpus case demands a resolved capability NAME; every case would hold against a classifier that reports a finding and never says what it read. Unmeasured, not a pass"

groups_ok=0
report() { printf '  %s: cases %s, upheld %s\n' "$2" "$1" "$3"; }
for g in \
  "$A1_N|A1 the generator moved no repository file|$A1_OK" \
  "$A2_N|A2 the real generated page declares nothing beyond output|$A2_OK" \
  "$A3_N|A3 an evasive spelling of the capability request is still classified|$A3_OK" \
  "$A4_N|A4 a declaration this check cannot read is a finding, never an absence|$A4_OK" \
  "$A5_N|A5 a capability name that is not output-only is a finding|$A5_OK" \
  "$A6_N|A6 a page that declares nothing forbidden is not flagged|$A6_OK" \
  "$A7_N|A7 a request assembled at run time is folded to the name it asks for|$A7_OK"
do
  n="${g%%|*}"; restg="${g#*|}"; label="${restg%%|*}"; okn="${restg##*|}"
  report "$n" "$label" "$okn"
  # An `if`, not `[ ... ] && ...`: an AND-list whose test fails is the last
  # command of this loop body, and that is the `set -e` shape that has killed
  # scripts in this repo mid-branch - right exit code, no reason printed.
  if [ "$n" = "$okn" ]; then groups_ok=$((groups_ok + 1)); fi
done
printf '  capability names read across the corpus: %d\n' "$CORPUS_READABLE"
printf '  corpus cases that demand a resolved name: %d\n' "$NAMED_CASES"
printf '  assertion groups: 7, upheld: %d\n' "$groups_ok"

if [ "$A1_MOVED" -ne 0 ] || [ "$PAGE_FINDINGS" -ne 0 ] || [ "$CASE_FINDINGS" -ne 0 ] || [ "$groups_ok" -ne 7 ]; then
  printf '  R4 not satisfied: see the findings above.\n'
  exit 1
fi
printf '  R4 satisfied: the generator moved no repository file, the page declares nothing beyond output, and the classifier that says so was held to a corpus that spells the same request every other way this file could find - including the ones that assemble it at run time, which it folded and named rather than passing over.\n'
exit 0
