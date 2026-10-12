#!/usr/bin/env bash
# .claude/hooks/publish-gate.sh — PreToolUse hook on the Bash tool.
#
# Stage 8 is agent-driven: the agent writes the post, writes the release email,
# captures the screenshots from the released build, and runs the pre-publish
# checks. This hook is the human gate on the last step — the one that puts any
# of it in front of people.
#
# Register it exactly as production-gate.sh is registered, matched to Bash:
#
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command",
#                   "command": ".claude/hooks/publish-gate.sh" }]
#     }]
#   }
#
# Exit codes are the contract:
#   2  BLOCKED. The command does not run; stderr goes back to the agent.
#   0  allowed.
# Every failure path exits 2, including this script's own bugs — a missing jq,
# an unexpected payload, an empty command. Claude Code runs the command anyway
# on any other non-zero status, so a gate that crashes with 1 or 127 is a gate
# that published. The EXIT trap rewrites anything that is not 0 or 2 into 2.
#
# ---------------------------------------------------------------------------
# THIS IS A TEMPLATE. AN UNEDITED COPY GATES THE WRONG COMMANDS.
#
# The deny list below describes an imaginary team's publishing commands. Before
# it is worth committing:
#   1. Run the commands that actually publish for you past it, and watch them
#      exit 2.
#   2. Run drafting, screenshotting and preview commands past it, and watch
#      them exit 0. The agent must be able to do all of its own work.
#   3. Delete what does not apply and add what does.
# A gate never seen blocking a real publish is decoration.
#
# Why publishing is gated when the drafting is not: a post is indexed and
# forwarded within minutes, and mail cannot be recalled. Every other artifact
# in this lifecycle is a commit someone can revert. This one is not, and it
# carries claims about the product to people outside the team.
# ---------------------------------------------------------------------------
set -euo pipefail

_rc=2
trap '[ "$_rc" = 0 ] && exit 0; exit 2' EXIT

command -v jq >/dev/null 2>&1 || {
  echo "publish-gate: jq is not installed, so this gate cannot read the command it is meant to check. Blocking." >&2
  exit 2
}

payload="$(cat)" || { echo "publish-gate: could not read the hook payload. Blocking." >&2; exit 2; }

# Every branch here is a shape this script does not understand; it refuses
# rather than guesses. The .tool_name check matters: registered on the wrong
# matcher this hook would be reading someone else's payload shape and
# approving publishes by accident.
cmd="$(printf '%s' "$payload" | jq -er '
  if type != "object" then
    error("payload is not a JSON object")
  elif ((.tool_name // "Bash") != "Bash") then
    error("fired on tool \(.tool_name) — register this hook on the Bash matcher only")
  elif ((.tool_input | type) != "object") then
    error("payload has no .tool_input object")
  elif ((.tool_input.command | type) != "string") then
    error(".tool_input.command is not a string")
  else .tool_input.command end' 2>&1)" || {
  echo "publish-gate: the hook payload was not the shape this gate expects (${cmd:-jq failed and said nothing}). Blocking." >&2; exit 2; }

# The session's permission mode, needed to decide whether a human can be asked
# at all. Absent or unreadable reads as empty, which the asker treats as "not
# known to be interactive" and therefore refuses.
pmode="$(printf '%s' "$payload" | jq -r '.permission_mode // ""' 2>/dev/null || printf '')"  # stderr-ok: asking whether the payload carries a mode; jq's complaint IS the answer, and an unreadable mode is treated as unknown and refused below

[ -n "$(printf '%s' "$cmd" | tr -d '[:space:]')" ] && [ "$cmd" != "null" ] || {
  echo "publish-gate: empty command. Blocking, because a gate that cannot see what it is judging has not judged it." >&2; exit 2; }

# --- normalising the command ----------------------------------------------
#
# The deny patterns are matched against a NORMALISED form of the command,
# never against the raw text. Raw-text matching is defeated by ordinary shell
# spellings - `npm "publish"`, `/usr/bin/npm publish`, `sh -c "npm publish"` -
# which are not attacks, just how commands get written. An agent emits the
# quoted form by accident. A gate that passes its own acceptance test and then
# fails on a pair of quotation marks is worse than no gate, because it is
# trusted.
#
# What the normaliser does, in order:
#   * splits the command on ; && || | & ( ) and newlines and judges EVERY
#     segment on its own, so `echo hi; ./deploy.sh prod` is judged twice;
#   * removes quoting and backslash escapes: `npm "publish"` -> `npm publish`;
#   * reduces argv[0] to its basename: /usr/bin/npm -> npm, ./deploy.sh -> deploy.sh;
#   * drops leading VAR=value assignments and interposer commands (sudo, env,
#     time, nohup, command, exec, xargs, stdbuf, nice, ionice, doas, setsid)
#     together with their own options, then judges what follows. `npx` and
#     `timeout <duration>` are treated the same way;
#   * unwraps `eval`, which is `sh -c` spelled shorter, and re-normalises what
#     it would have re-parsed;
#   * unwraps sh -c / bash -c / zsh -c and re-runs the whole normalisation on
#     the inner string, to GATE_MAX_DEPTH levels, BLOCKING if that is reached
#     rather than allowing;
#   * skips git's global options (-C dir, -c k=v, --git-dir=..., --no-pager,
#     ...) so that `git -C . push origin v1.2.3` reaches the push subcommand;
#   * flags a segment whose command word is a sensitive binary AND whose words
#     still contain a $expansion or a backtick. Variable indirection
#     (`p=publish; npm $p`) cannot be resolved without running the shell, so
#     the gate refuses instead of guessing. Failing closed on ambiguity is the
#     correct behaviour for a gate.
#
# Outputs (globals):
#   GATE_LINES      newline-separated canonical command lines, one per segment
#   GATE_AMBIG      1 when a sensitive command word carried an unresolved word
#   GATE_AMBIG_CMD  the canonical line that caused it
#   GATE_DEEP       1 when wrapper nesting hit GATE_MAX_DEPTH

GATE_MAX_DEPTH=3
GATE_TS=$'\001'        # separates tokens inside a segment
GATE_SS=$'\002'        # separates segments
GATE_LINES=''
GATE_AMBIG=0
GATE_AMBIG_CMD=''
GATE_DEEP=0
T_OUT=''

GATE_INTERPOSERS=' sudo doas env time timeout nohup command exec xargs stdbuf nice ionice setsid npx '
GATE_SHELLS=' sh bash zsh dash ksh ash busybox '
GATE_SENSITIVE=' npm git gh terraform helm kubectl aws docker make twine cargo netlify vercel wrangler mail sendmail msmtp curl '
# Tools that do many things, only some of which publish or deploy. For these
# the subcommand decides whether an unresolved expansion is ambiguous.
GATE_MULTIPURPOSE=' git make docker curl npm cargo '

# tokenize <string> -> T_OUT
# Each segment is prefixed by GATE_SS; each token inside it by GATE_TS and a
# single flag character, 1 when that token contained an unresolved expansion.
gate_tokenize() {
  local s=$1
  local n=${#s} i=0 ch cur='' started=0 exp=0 seg='' out='' in_s=0 in_d=0
  while [ "$i" -lt "$n" ]; do
    ch=${s:i:1}
    i=$((i+1))
    if [ "$in_s" = 1 ]; then
      if [ "$ch" = "'" ]; then in_s=0; else cur=$cur$ch; fi
      started=1
      continue
    fi
    case "$ch" in
      '\')
        if [ "$i" -lt "$n" ]; then cur=$cur${s:i:1}; i=$((i+1)); fi
        started=1
        continue ;;
      '"')
        if [ "$in_d" = 1 ]; then in_d=0; else in_d=1; fi
        started=1
        continue ;;
      "'")
        if [ "$in_d" = 1 ]; then cur=$cur$ch; else in_s=1; fi
        started=1
        continue ;;
      '$'|'`')
        cur=$cur$ch; exp=1; started=1
        continue ;;
    esac
    if [ "$in_d" = 1 ]; then cur=$cur$ch; started=1; continue; fi
    case "$ch" in
      ' '|$'\t')
        if [ "$started" = 1 ]; then
          seg=$seg$GATE_TS$exp$cur; cur=''; started=0; exp=0
        fi ;;
      ';'|'&'|'|'|'('|')'|$'\n')
        if [ "$started" = 1 ]; then
          seg=$seg$GATE_TS$exp$cur; cur=''; started=0; exp=0
        fi
        if [ -n "$seg" ]; then out=$out$GATE_SS$seg; fi
        seg='' ;;
      *)
        cur=$cur$ch; started=1 ;;
    esac
  done
  if [ "$started" = 1 ]; then seg=$seg$GATE_TS$exp$cur; fi
  if [ -n "$seg" ]; then out=$out$GATE_SS$seg; fi
  T_OUT=$out
}

# Drop the first token of $L. Relies on bash's dynamic scoping: $L is the
# caller's local list.
gate_pop() {
  if [ "$L" = "${L#*"$GATE_TS"}" ]; then L=''; else L=${L#*"$GATE_TS"}; fi
}

# Does <interposer> <option> consume the following word as its value?
gate_optarg() {
  case "$1:$2" in
    sudo:-u|sudo:-g|sudo:-p|sudo:-C|sudo:-h|sudo:-r|sudo:-t|sudo:-T|sudo:-U) return 0 ;;
    doas:-u|doas:-C) return 0 ;;
    env:-u|env:-C|env:-S) return 0 ;;
    xargs:-I|xargs:-i|xargs:-L|xargs:-n|xargs:-P|xargs:-s|xargs:-E|xargs:-d|xargs:-a) return 0 ;;
    nice:-n) return 0 ;;
    npx:-p|npx:-c|npx:--package|npx:--call) return 0 ;;
    timeout:-k|timeout:-s|timeout:--kill-after|timeout:--signal) return 0 ;;
    ionice:-c|ionice:-n|ionice:-p|ionice:-t) return 0 ;;
    stdbuf:-i|stdbuf:-o|stdbuf:-e) return 0 ;;
  esac
  return 1
}

# Is $1 a bare duration, as `timeout 30 cmd` and `timeout 1.5h cmd` spell it?
gate_is_duration() {
  case "$1" in
    ''|*[!0-9smhd.]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Is $1 a shell variable assignment (FOO=bar), i.e. not part of argv?
gate_is_assign() {
  case "$1" in
    [A-Za-z_]*=*)
      case "${1%%=*}" in
        *[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
      esac ;;
  esac
  return 1
}

gate_segment() {
  local blob=$1 depth=$2
  local L head flag text base cw line hasexp=0 guard=0 have=0 inner opt first
  L=${blob#"$GATE_TS"}

  while [ -n "$L" ]; do
    guard=$((guard+1))
    if [ "$guard" -gt 64 ]; then GATE_DEEP=1; return 0; fi
    head=${L%%"$GATE_TS"*}
    flag=${head:0:1}
    text=${head:1}
    base=${text##*/}

    if [ -z "$text" ]; then gate_pop; continue; fi
    if gate_is_assign "$text"; then gate_pop; continue; fi

    # `eval` is `sh -c` by another name: it re-parses its arguments as a
    # command. Join what follows back into one string and run the whole
    # normalisation on it, exactly as the shell would.
    if [ "$base" = eval ]; then
      gate_pop
      inner=''
      first=1
      while [ -n "$L" ]; do
        head=${L%%"$GATE_TS"*}
        if [ "$first" = 1 ]; then inner=${head:1}; first=0; else inner="$inner ${head:1}"; fi
        gate_pop
      done
      if [ -n "$inner" ]; then gate_walk "$inner" "$((depth + 1))"; fi
      return 0
    fi

    case "$GATE_INTERPOSERS" in
      *" $base "*)
        gate_pop
        while [ -n "$L" ]; do
          head=${L%%"$GATE_TS"*}
          opt=${head:1}
          case "$opt" in
            -*)
              gate_pop
              if gate_optarg "$base" "$opt"; then gate_pop; fi ;;
            *)
              if gate_is_assign "$opt"; then
                gate_pop
              elif [ "$base" = timeout ] && gate_is_duration "$opt"; then
                gate_pop
              else
                break
              fi ;;
          esac
        done
        continue ;;
    esac

    case "$GATE_SHELLS" in
      *" $base "*)
        gate_pop
        while [ -n "$L" ]; do
          head=${L%%"$GATE_TS"*}
          opt=${head:1}
          case "$opt" in
            --*) gate_pop ;;
            -*)
              case "${opt#-}" in
                *[!A-Za-z]*) gate_pop ;;
                *c*)
                  gate_pop
                  if [ -n "$L" ]; then
                    head=${L%%"$GATE_TS"*}
                    inner=${head:1}
                    gate_walk "$inner" "$((depth + 1))"
                  fi
                  return 0 ;;
                *) gate_pop ;;
              esac ;;
            *) break ;;
          esac
        done
        continue ;;
    esac

    have=1
    break
  done

  if [ "$have" = 0 ]; then return 0; fi

  cw=$base
  if [ "$flag" = 1 ]; then hasexp=1; fi
  gate_pop

  if [ "$cw" = git ]; then
    while [ -n "$L" ]; do
      head=${L%%"$GATE_TS"*}
      opt=${head:1}
      case "$opt" in
        -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)
          gate_pop; gate_pop ;;
        --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--config-env=*)
          gate_pop ;;
        -p|-P|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks)
          gate_pop ;;
        *) break ;;
      esac
    done
  fi

  line=$cw
  while [ -n "$L" ]; do
    head=${L%%"$GATE_TS"*}
    if [ "${head:0:1}" = 1 ]; then hasexp=1; fi
    text=${head:1}
    line="$line ${text//$'\n'/ }"
    gate_pop
  done

  # Unresolved $ or backtick on a sensitive command word means the gate cannot
  # see what will actually run, and a gate that cannot see fails closed.
  #
  # But the command WORD is too coarse for the multi-purpose tools. Blocking
  # every `git commit -m "$msg"` - a spelling agents emit constantly - is how a
  # gate gets switched off within a day, and a gate that is off protects
  # nothing. So for those, the SUBCOMMAND decides: `git push origin $TAG` is
  # ambiguous and blocks; `git commit -m "$msg"` is not and does not.
  local ambig=0
  case "$GATE_SENSITIVE" in
    *" $cw "*) ambig=1 ;;
  esac
  case "$GATE_MULTIPURPOSE" in
    *" $cw "*)
      ambig=0
      # If the SUBCOMMAND is itself the unresolved part - `npm $p`, `git $op` -
      # the gate cannot know which subcommand this is, so it fails closed. That
      # is different from `git commit -m "$msg"`, where the subcommand is known
      # and only an argument is opaque.
      local _sub
      # shellcheck disable=SC2086  # deliberate word-splitting of a normalised line
      set -- $line
      _sub=${2:-}
      case "$_sub" in
        *'$'*|*'`'*) ambig=1 ;;
      esac
      case " $line " in
        *" git push "*|*" git tag "*|*" npm publish "*|*" npm pack "*\
        |*" cargo publish "*|*" docker push "*|*" make release "*\
        |*" make deploy "*|*" make publish "*|*" curl "*"-X POST"*\
        |*" curl "*"--upload-file"*|*" curl "*"-T "*) ambig=1 ;;
      esac ;;
  esac
  if [ "$ambig" = 1 ] && [ "$hasexp" = 1 ]; then
    GATE_AMBIG=1; GATE_AMBIG_CMD=$line
  fi

  GATE_LINES=$GATE_LINES$line'
'
}

gate_walk() {
  local depth=$2 blob rest seg
  if [ "$depth" -gt "$GATE_MAX_DEPTH" ]; then GATE_DEEP=1; return 0; fi
  gate_tokenize "$1"
  blob=$T_OUT
  rest=$blob
  while [ -n "$rest" ]; do
    rest=${rest#"$GATE_SS"}
    seg=${rest%%"$GATE_SS"*}
    if [ "$seg" = "$rest" ]; then rest=''; else rest=${rest#*"$GATE_SS"}; fi
    if [ -n "$seg" ]; then gate_segment "$seg" "$depth"; fi
  done
}

gate_normalise() {
  GATE_LINES=''
  GATE_AMBIG=0
  GATE_AMBIG_CMD=''
  GATE_DEEP=0
  gate_walk "$1" 0
}

# --- the deny list --------------------------------------------------------
#
# Each entry is an extended regular expression anchored to the START of a
# normalised segment, so `^npm[[:space:]]+publish` means the segment's command
# word is npm — `echo npm publish` is not a publish, and neither is
# `cat npm-publish.md`. Each must match a command that actually reaches an
# audience, not one that prepares something for you to read.
deny=(
  '^gh([[:space:]]+[^[:space:]]+)*[[:space:]]+release[[:space:]]+(create|edit|upload)([[:space:]]|$)'
  # The intervening-argument group matters: `npm -w pkg publish` and
  # `npm --loglevel=silly publish` are ordinary spellings, and a pattern that
  # demands `publish` in argv[1] lets both of them through.
  '^npm([[:space:]]+[^[:space:]]+)*[[:space:]]+publish([[:space:]]|$)'
  '^(twine|cargo)([[:space:]]+[^[:space:]]+)*[[:space:]]+publish([[:space:]]|$)'
  '^git[[:space:]]+push([[:space:]].*)?[[:space:]]--tags([[:space:]]|$)'
  # A tag pushed by name is the same act as --tags and the commoner spelling:
  # `git push origin v3.6.0`. Installing this gate on a real repo showed the
  # --tags pattern alone let every release of that day straight through.
  '^git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+v[0-9]'
  '^git[[:space:]]+push([[:space:]].*)?refs/tags/'
  '^claude[[:space:]]+plugin[[:space:]]+(tag|publish)([[:space:]]|$)'
  '^(mail|sendmail|mailx|msmtp)([[:space:]]|$)'
  '^curl[[:space:]].*(api\.mailgun|api\.sendgrid|api\.postmarkapp|api\.buttondown|api\.twitter|api\.x\.com|graph\.facebook|api\.linkedin|hooks\.slack)'
  '^(hugo|jekyll|eleventy|next)([[:space:]]+[^[:space:]]+)*[[:space:]]+deploy([[:space:]]|$)'
  '^(netlify|vercel|wrangler)([[:space:]]+[^[:space:]]+)*[[:space:]]+(deploy|publish)([[:space:]]|$)'
  '^aws[[:space:]]+s3[[:space:]]+(cp|sync)[[:space:]].*s3://'
)

# --- the verdict ----------------------------------------------------------

refuse() {
  cat >&2 <<MSG
BLOCKED by publish-gate.

  $cmd

$1

Stage 8 drafts, a person decides, and then the agent runs it. This command
puts something in front of people, and neither a post nor an email can be
recalled - so the decision is a person's. The typing is not.

Before you ask, the pre-publish checklist has to actually pass:
  - every claim traces to a merged PR or a requirement id
  - every number was measured, and the measurement is stated
  - every screenshot came from THIS version's build
  - the version named is live and installable, and that was verified
  - no customer, repo, internal hostname or employer name appears anywhere,
    including in the screenshots
  - names and bylines of anyone credited are correct

Show the draft and the checklist results, say plainly which checks you could
not verify yourself, and ASK. On an explicit yes from the person - not an
inferred one, not silence, not a yes to some earlier question - run the command.
They should not have to retype a command they did not compose; making them do
that is how the approval turns into a chore and the chore turns into a rubber
stamp.
MSG
  exit 2
}

# --- asking a person, which is the half of R17 that did not exist -----------
#
# R17: "If a command would publish or deploy, then the gate shall block it
# UNTIL A PERSON DECIDES." Until now only the blocking half was built. There
# was no way to decide - not an env var, not a marker file, nothing - so the
# one remaining route was retyping the command in another shell, which the
# refusal text above argues against in its own words. It described the failure
# it caused.
#
# `permissionDecision: "ask"` routes to Claude Code's own permission prompt.
# That prompt is drawn by the harness and answered by a keystroke, so the agent
# this gate exists to constrain cannot draw it, answer it, or skip it. And the
# person approves the command already written rather than retyping it.
#
# THIS IS ONLY REACHED FOR A COMMAND THE GATE UNDERSTOOD. A command it could
# not parse or unwrap still hard-refuses above: asking a person to approve
# something nobody can read is not a decision, it is a signature on a blank
# page.
#
# TWO THINGS ARE DOCUMENTED AND ONE IS NOT, so this fails closed on the third.
#
#   Documented: "A hook that returns permissionDecision: \"deny\" blocks the
#   tool even in bypassPermissions mode or with --dangerously-skip-permissions."
#   That sentence names `deny`. It does NOT say the same of `ask`.
#
#   Documented: background subagents cannot show a prompt in non-interactive
#   mode.
#
#   NOT documented: what `ask` does under bypassPermissions, or in a plain `-p`
#   run. Nobody wrote it down, so this gate does not rely on it: anything other
#   than a mode known to prompt gets the hard refusal it got before. The gate
#   loses nothing it had; it only gains a path where one is known to work.
#
# `auto` IS ON THE LIST, AND NOT BECAUSE THE DOCS SAY SO. It is not in the
# documented set, and this gate refused in it five times in a row - correctly,
# since an undocumented mode is one whose prompting nobody had established. The
# maintainer, who is the person the prompt is shown to, confirmed that it does
# show. That is a better source than the documentation for this particular
# question: it is a report from the only party who can observe the answer.
#
# It is recorded here as what it is - a stated observation, not a citation - so
# that anyone who later finds `auto` behaving differently knows exactly which
# claim to go back to. `bypassPermissions` stays refused, explicitly and by the
# same instruction: the point of that mode is to stop asking, so a gate that
# asked in it would be asking nobody.
GATE_CHECKLIST="${GATE_CHECKLIST:-.claude/productizer/publish-checklist.md}"
GATE_CHECKLIST_MAX_AGE="${GATE_CHECKLIST_MAX_AGE:-900}"

ask_or_refuse() {
  # Only modes that are known to show a prompt. `bypassPermissions`, an empty
  # mode and anything unrecognised all fall through to the refusal.
  case "$pmode" in
    default|acceptEdits|plan|auto) ;;
    *) refuse "$1

This session's permission mode is '${pmode:-unknown}', which is not one this gate
will ask in. A prompt is only trusted where the documentation says one is shown;
under bypassPermissions, in a plain -p run, or in a background subagent, whether
an ask reaches a person is undocumented, so this refuses instead of assuming." ;;
  esac

  # THE CHECKLIST IS NOT A SECURITY BOUNDARY AND IS NOT PRETENDING TO BE ONE.
  # The agent writes it, so an agent determined to lie can write a lie. What it
  # stops is the careless case, and what it BUYS is that the person's prompt
  # shows what was actually checked rather than a bare "allow?". A prompt with
  # nothing in it is how approval becomes a reflex.
  if [ ! -f "$GATE_CHECKLIST" ]; then
    refuse "$1

No pre-publish checklist at $GATE_CHECKLIST, so there is nothing to show the
person being asked. Write it - the command on a \`Command:\` line, then each item
below with what you actually found and what you could NOT verify - and run this
again. A prompt that shows nothing is how approval becomes a reflex."
  fi

  # COMPARED AGAINST THE MATCHED SEGMENT, NOT THE WHOLE COMMAND LINE.
  #
  # This used to test the checklist against `$cmd`, which is everything the
  # shell was asked to run - `cd somewhere && git push ... 2>&1 | tail -3`. A
  # checklist naming the push alone could never equal that, so the gate refused
  # every time and printed "the checklist is for a different command" directly
  # above the identical command. A refusal whose reason contradicts its own
  # evidence is worse than no reason.
  #
  # `$seg` is the publishing command this gate already isolated and matched, so
  # it is the thing the person is actually approving. A PREFIX test, because the
  # segment can carry a trailing redirection that is not part of what publishes.
  # Still specific: the checklist must name this version, so it cannot approve a
  # different tag or a second publish hiding in the same line.
  _ck_cmd="$(sed -n 's/^Command: //p' "$GATE_CHECKLIST")"; _ck_cmd="$(head -n 1 <<<"$_ck_cmd")"
  case "$seg" in
    "$_ck_cmd"*) _ck_ok=1 ;;
    *)           _ck_ok=0 ;;
  esac
  if [ "$_ck_ok" -ne 1 ]; then
    refuse "$1

The checklist at $GATE_CHECKLIST is for a different command. It names:

  ${_ck_cmd:-<no Command: line>}

A checklist that does not name THIS command is a blanket approval, which is the
rubber stamp this gate exists to prevent."
  fi

  # Staleness is measured, not assumed. An old checklist describes a state that
  # has since moved - a version that was live, a scrape that was clean.
  #
  # NOT `stat`. This used to try BSD `stat -f %m` and fall back to GNU
  # `stat -c %Y`, which is wrong in the one way a fallback cannot catch: on GNU
  # coreutils `-f` means FILESYSTEM status and SUCCEEDS, printing block counts
  # rather than a timestamp. The fallback never fired, the age arithmetic got a
  # non-number, and `set -e` killed the gate mid-decision. It was green on macOS
  # and red in CI, which is exactly the shape of bug a portability fallback is
  # supposed to prevent. Measured against a GNU-behaving shim, not reasoned.
  #
  # `find -mmin` is in both userlands and answers the only question being asked:
  # is this file younger than the limit. Minutes, so a sub-minute limit rounds
  # up to one rather than to zero - a limit of zero would refuse everything.
  _max_min=$(( GATE_CHECKLIST_MAX_AGE / 60 ))
  [ "$_max_min" -ge 1 ] || _max_min=1
  _fresh="$(find "$GATE_CHECKLIST" -mmin -"$_max_min" 2>/dev/null || printf '')"  # stderr-ok: asking whether the file is younger than the limit; find's complaint about an unreadable path IS the answer, and an empty result is refused as unknown below
  if [ -z "$_fresh" ]; then
    refuse "$1

The checklist at $GATE_CHECKLIST is older than ${_max_min} minute(s), or its age could
not be read. Either way it describes a state that has since moved. Re-run the
checks and rewrite it."
  fi

  # jq -Rs builds the JSON string, so a checklist containing quotes, newlines or
  # backslashes cannot break out of the field and forge a decision.
  jq -n --arg reason "A command that publishes is waiting on your decision.

  $cmd

$1

The agent's pre-publish checklist follows. It was written by the agent, so read
it as its account rather than as proof:

$(cat "$GATE_CHECKLIST")" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  _rc=0
  exit 0
}


gate_normalise "$cmd"

if [ "$GATE_DEEP" = 1 ]; then
  refuse "Shell wrappers are nested deeper than this gate unwraps (${GATE_MAX_DEPTH}), so it
cannot see what is finally run. It refuses rather than guesses. Run the inner
command directly."
fi

if [ "$GATE_AMBIG" = 1 ]; then
  refuse "This command could not be statically resolved:

  $GATE_AMBIG_CMD

A \$expansion or a backtick decides what a publishing binary is asked to do,
and that is only known once the shell runs it. The gate cannot read it, so it
does not approve it - failing closed on ambiguity is the point of a gate.
Write the command out literally and it will be judged on what it says."
fi

shopt -s nocasematch
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  for pat in "${deny[@]}"; do
    if [[ $seg =~ $pat ]]; then
      ask_or_refuse "The segment that matched, after normalising away quoting, paths and wrappers:

  $seg"
    fi
  done
done <<< "$GATE_LINES"

_rc=0
exit 0
