#!/usr/bin/env python3
"""check-plan-page.py [--root DIR] [--builder PATH] [--fixture DIR] [--selftest] [--version] [--help]

Builds plan pages with the real builder (build-plan-page.sh) and reads them
for what a plan page may never hold. The plan page is not a view
(references/plan-page.md): it requests no capability at all, not even
`downloads`, loads nothing and sends nothing, and its only script is the
template's. A page that could not be built is unmeasured - exit 2 - and never
a page with zero capabilities.

PAGES BUILT. Every plan under <fixture>/plans, placed at docs/sdlc/<name>/
plan.md in a temporary root, and every docs/sdlc/*/plan.md under --root (the
git top level by default), each into a temporary directory; the hostile
fixture plan also with <fixture>/plans/hostile.css as its stylesheet; and the
shipped templates/plan.md. Nothing is written under --root.

WHAT IS ASSERTED, each a separate group:
  built       the builder wrote a page (exit 0). A plan whose open questions
              are malformed is the builder's exit 1 and is reported, not read
  capability  the capability object's name appears nowhere in the bytes, and
              no script region calls `use` (dotted or bracketed) or reaches
              an evaluator: eval, Function, execScript, or a timer handed a
              string
  network     no element that loads or sends (script with src, link, img,
              iframe, frame, object, embed, audio, video, source, track,
              base, form, portal, meta refresh, svg image or use), no
              address attribute (href, src, srcset, action, formaction,
              poster, background, data, ping, manifest, xlink:href) whose
              value is not a `#fragment`, no `url(`, `@import`, `image-set(`,
              `@font-face` or backslash in a style element or attribute, and
              no network or navigation API in a script region: fetch,
              XMLHttpRequest, WebSocket, EventSource, sendBeacon, Worker,
              importScripts, import(), RTCPeerConnection, window.open,
              location, postMessage, http: or https:
  script      no inline `on...=` handler and no javascript: URL; no script
              region writes markup (innerHTML, outerHTML, insertAdjacentHTML,
              document.write, srcdoc) or keeps state (localStorage,
              sessionStorage, indexedDB, cookie); and on a BUILT page every
              script region is the template's script, byte for byte
  text        each line of <fixture>/plans/<name>.expect appears in the page's
              text outside script and style, decoded - the hostile plan's
              markup, script and links are shown, not run

THE CORPUS. The same reading runs over <fixture>/pages, hand-made pages each
holding one forbidden thing or none, against <fixture>/cases.tsv: each
`finding` page must be flagged under its group and each `clean` page not at
all. If the corpus is missing, or a group has no case that must be flagged,
the run asserted nothing about that group - exit 2.

WHAT IT DOES NOT SEE. It reads bytes and the HTML parse; it does not run the
page. A capability granted in the publish call leaves nothing in the page
(the artifact gate reaches that surface). Its lists are lists: an API it does
not name is not seen, which is why a built page is also held to the
template's script byte for byte.

Exit codes:
  0  every page was built and held every group, and every corpus case was
     classified as declared
  1  findings: a built page held something it may not, or the corpus was
     misclassified
  2  could not run: bad usage, no builder or template, a page that could not
     be built, a missing corpus, or a group no corpus case exercises
--selftest drives each exit code with stub builders and exits 0 when every
case held, 1 otherwise.
"""
import html.parser
import os
import re
import shutil
import subprocess
import sys
import tempfile

VERSION = "check-plan-page 1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
USAGE = "usage: check-plan-page.py [--root DIR] [--builder PATH] [--fixture DIR] | --selftest | --version\n"
GROUPS = ("capability", "network", "script")

CAP_NAME = re.compile(r"(?<![A-Za-z0-9_$])claude(?![A-Za-z0-9_$])")
USE_CALL = re.compile(r"""(?:\.\s*use|\[\s*["'`]use["'`]\s*\])\s*\(""")
EVALUATOR = re.compile(r"""\b(?:eval|Function|execScript)\s*\(|\bnew\s+Function\b|\bset(?:Timeout|Interval)\s*\(\s*["'`]""")
NET_API = re.compile(r"""\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|SharedWorker|Worker|importScripts|"""
                     r"""RTCPeerConnection|postMessage|location)\b|\bimport\s*\(|\bwindow\s*\.\s*open\b|https?:""")
MARKUP_API = re.compile(r"\b(?:innerHTML|outerHTML|insertAdjacentHTML|srcdoc)\b|\bdocument\s*\.\s*write")
STATE_API = re.compile(r"\b(?:localStorage|sessionStorage|indexedDB|cookie)\b")
CSS_BAD = re.compile(r"url\s*\(|@import|image-set\s*\(|@font-face|\\", re.I)
LOADING_TAGS = {"link", "img", "iframe", "frame", "object", "embed", "audio", "video", "source", "track", "base",
                "form", "portal", "image", "use", "applet"}
ADDRESS_ATTRS = {"href", "src", "srcset", "action", "formaction", "poster", "background", "data", "ping",
                 "manifest", "xlink:href", "codebase", "longdesc", "cite"}


class Reader(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.findings, self.scripts, self.text, self.stack = [], [], [], []

    def add(self, group, msg):
        self.findings.append((group, msg))

    def handle_starttag(self, tag, attrs):
        self.visit(tag, attrs)
        if tag in ("script", "style"):
            self.stack.append([tag, []])

    def handle_startendtag(self, tag, attrs):
        self.visit(tag, attrs)

    def visit(self, tag, attrs):
        a = dict((k.lower(), v or "") for k, v in attrs)
        if tag in LOADING_TAGS:
            self.add("network", "a <%s> element loads or sends" % tag)
        if tag == "script" and "src" in a:
            self.add("network", "a <script> loads %s" % a["src"][:60])
        if tag == "meta" and a.get("http-equiv", "").lower() == "refresh":
            self.add("network", "a meta refresh")
        for k, v in a.items():
            if k.startswith("on"):
                self.add("script", "an inline %s= handler on <%s>" % (k, tag))
            if k in ADDRESS_ATTRS and not v.startswith("#"):
                group = "network"
                if re.sub(r"[\x00-\x20]", "", v).lower().startswith("javascript:"):
                    self.add("script", "a javascript: URL in %s=" % k)
                self.add(group, "%s=%r on <%s> is not a #fragment" % (k, v[:60], tag))
            if k == "style" and CSS_BAD.search(v):
                self.add("network", "a style attribute holds %r" % CSS_BAD.search(v).group(0))

    def handle_endtag(self, tag):
        if self.stack and self.stack[-1][0] == tag:
            kind, parts = self.stack.pop()
            body = "".join(parts)
            if kind == "script":
                self.scripts.append(body)
            elif CSS_BAD.search(re.sub(r"/\*.*?\*/", "", body, flags=re.S)):
                self.add("network", "a style element holds %r" % CSS_BAD.search(body).group(0))

    def handle_data(self, data):
        if self.stack:
            self.stack[-1][1].append(data)
        else:
            self.text.append(data)


def read_page(raw, template_script=None):
    """[(group, message)] and the page's text outside script and style."""
    r = Reader()
    r.feed(raw)
    r.close()
    if r.stack:
        r.add("script", "a <%s> element is never closed" % r.stack[-1][0])
    if CAP_NAME.search(raw):
        r.add("capability", "the capability object's name appears verbatim")
    for n, body in enumerate(r.scripts, 1):
        for group, rx, what in (("capability", USE_CALL, "a use() call"), ("capability", EVALUATOR, "an evaluator"),
                                ("network", NET_API, "a network or navigation API"),
                                ("script", MARKUP_API, "markup written from text"),
                                ("script", STATE_API, "browser storage")):
            m = rx.search(body)
            if m:
                r.add(group, "script %d holds %s: %r" % (n, what, m.group(0)))
    if template_script is not None and r.scripts != [template_script]:
        r.add("script", "the page's script regions are not the template's script alone (%d region(s))"
              % len(r.scripts))
    return r.findings, " ".join("".join(r.text).split())


def template_script():
    with open(os.path.join(SKILL, "templates", "plan-page.html"), encoding="utf-8") as fh:
        r = Reader()
        r.feed(fh.read())
    if len(r.scripts) != 1:
        raise OSError("the template holds %d script regions" % len(r.scripts))
    return r.scripts[0]


def build(builder, root, rel, out, extra=()):
    proc = subprocess.run(["bash", builder, rel, "--root", root, "--out", out] + list(extra),
                          capture_output=True, text=True, check=False)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def run(root, builder, fixture):
    out, findings = ["check-plan-page: builder %s" % shown(builder)], 0
    if not os.path.isfile(builder):
        return 2, out + ["check-plan-page: no builder at %s" % shown(builder)]
    try:
        tpl = template_script()
    except OSError as exc:
        return 2, out + ["check-plan-page: cannot read the template's script: %s" % exc]
    cases_path, pages_dir, plans_dir = (os.path.join(fixture, p) for p in ("cases.tsv", "pages", "plans"))
    try:
        with open(cases_path, encoding="utf-8") as fh:
            cases = [line.rstrip("\n").split("\t") for line in fh if line.strip() and not line.startswith("#")]
        plans = sorted(f[:-3] for f in os.listdir(plans_dir) if f.endswith(".md"))
    except OSError as exc:
        return 2, out + ["check-plan-page: no corpus at %s: %s" % (shown(fixture), exc.__class__.__name__)]
    positive = set(c[2] for c in cases if len(c) >= 3 and c[1] == "finding")
    unexercised = [g for g in GROUPS if g not in positive]
    if not plans or unexercised:
        return 2, out + ["check-plan-page: the corpus exercises no %s; this run asserts nothing about it"
                         % (", ".join(unexercised) or "plan")]
    held, total = 0, 0
    with tempfile.TemporaryDirectory() as tmp:
        work, pages = os.path.join(tmp, "root"), []
        for name in plans:
            os.makedirs(os.path.join(work, "docs/sdlc", name))
            shutil.copy(os.path.join(plans_dir, name + ".md"), os.path.join(work, "docs/sdlc", name, "plan.md"))
            pages.append(("fixture %s" % name, work, "docs/sdlc/%s/plan.md" % name, (), name))
            if os.path.isfile(os.path.join(plans_dir, name + ".css")):
                shutil.copy(os.path.join(plans_dir, name + ".css"), os.path.join(work, name + ".css"))
                pages.append(("fixture %s, its stylesheet" % name, work, "docs/sdlc/%s/plan.md" % name,
                              ("--stylesheet", name + ".css"), name))
        os.makedirs(os.path.join(work, "docs/sdlc/template"))
        shutil.copy(os.path.join(SKILL, "templates", "plan.md"), os.path.join(work, "docs/sdlc/template/plan.md"))
        pages.append(("the shipped templates/plan.md", work, "docs/sdlc/template/plan.md", (), None))
        sdlc = os.path.join(root, "docs", "sdlc")
        for d in sorted(os.listdir(sdlc)) if os.path.isdir(sdlc) else []:
            if os.path.isfile(os.path.join(sdlc, d, "plan.md")):
                pages.append(("docs/sdlc/%s/plan.md" % d, root, "docs/sdlc/%s/plan.md" % d, (), None))
        for n, (label, proot, rel, extra, name) in enumerate(pages):
            total += 1
            page = os.path.join(tmp, "page-%d.html" % n)
            rc, said = build(builder, proot, rel, page, extra)
            if rc == 1:
                out.append("FINDING built: %s: its open questions are malformed: %s" % (label, said[-160:]))
                findings += 1
                continue
            if rc != 0 or not os.path.isfile(page):
                return 2, out + ["check-plan-page: the builder could not build %s (exit %d): %s; its capabilities "
                                 "are unknown, not zero" % (label, rc, said[-200:])]
            with open(page, encoding="utf-8") as fh:
                got, text = read_page(fh.read(), tpl)
            if name and os.path.isfile(os.path.join(plans_dir, name + ".expect")):
                with open(os.path.join(plans_dir, name + ".expect"), encoding="utf-8") as fh:
                    for line in (line.rstrip("\n") for line in fh):
                        if line and " ".join(line.split()) not in text:
                            got.append(("text", "the plan's text %r is not shown as text" % line[:60]))
            for group, msg in got:
                out.append("FINDING %s: %s: %s" % (group, label, msg))
            findings += len(got)
            held += not got
            out.append("  page %s: %s" % (label, "held every group" if not got else "%d finding(s)" % len(got)))
        for c in cases:
            total += 1
            try:
                with open(os.path.join(pages_dir, c[0] + ".html"), encoding="utf-8") as fh:
                    got, _ = read_page(fh.read())
            except (OSError, IndexError) as exc:
                return 2, out + ["check-plan-page: corpus case %r cannot be read: %s" % (c[:1], exc.__class__.__name__)]
            groups = set(g for g, _ in got)
            ok = (not got) if c[1] == "clean" else (c[2] in groups)
            held += ok
            if not ok:
                findings += 1
                out.append("FINDING corpus: %s wanted %s%s, got %s" % (
                    c[0], c[1], "" if c[1] == "clean" else " under " + c[2],
                    "; ".join("%s: %s" % g for g in got) or "nothing"))
    out.append("check-plan-page: %d of %d cases held" % (held, total))
    return (1 if findings else 0), out


def shown(path):
    cwd = os.getcwd() + os.sep
    return path[len(cwd):] if path.startswith(cwd) else os.path.basename(path)


def selftest():
    fixture = os.path.join(SKILL, "fixtures", "plan-page")
    builder = os.path.join(HERE, "build-plan-page.sh")
    held, total, codes = 0, 0, set()
    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "repo")
        os.makedirs(root)
        def stub_builder(body):
            stub = os.path.join(tmp, "stub-%d.sh" % len(os.listdir(tmp)))
            with open(stub, "w") as fh:
                fh.write("#!/usr/bin/env bash\nset -eu\nwhile [ $# -gt 0 ]; do case \"$1\" in --out) o=\"$2\"; "
                         "shift 2 ;; *) shift ;; esac; done\n" + body + "\n")
            return stub
        tpl = open(os.path.join(SKILL, "templates", "plan-page.html"), encoding="utf-8").read()
        clean_page = os.path.join(tmp, "clean.html")
        with open(clean_page, "w") as fh:
            fh.write(re.sub(r"@@(TITLE|THEME|BODY)@@", "", tpl))
        no_groups = os.path.join(tmp, "nogroups")
        shutil.copytree(fixture, no_groups)
        with open(os.path.join(no_groups, "cases.tsv"), "w") as fh:
            fh.write("clean\tclean\tnone\tx\n")
        cases = [
            ("real-builder", builder, fixture, 0, "cases held"),
            ("page-fetches", stub_builder("sed 's#</body>#<img src=\"https://example.invalid/p.png\"></body>#' %s "
                                          "> \"$o\"" % shq(clean_page)), fixture, 1, "FINDING network"),
            ("page-asks", stub_builder("sed 's#</body>#<script>window.claude.use(\"artifact\")</script></body>#' %s "
                                       "> \"$o\"" % shq(clean_page)), fixture, 1, "FINDING capability"),
            ("page-other-script", stub_builder("sed 's#refresh();#refresh(); window.x = 1;#' %s > \"$o\""
                                               % shq(clean_page)), fixture, 1, "not the template's script"),
            ("builder-fails", stub_builder("exit 2"), fixture, 2, "unknown, not zero"),
            ("builder-writes-nothing", stub_builder("exit 0"), fixture, 2, "could not build"),
            ("no-builder", os.path.join(tmp, "none.sh"), fixture, 2, "no builder"),
            ("no-corpus", builder, os.path.join(tmp, "none"), 2, "no corpus"),
            ("group-unexercised", builder, no_groups, 2, "exercises no capability, network, script"),
        ]
        for name, b, fx, want_rc, want_text in cases:
            total += 1
            rc, out = run(root, b, fx)
            codes.add(rc)
            text = "\n".join(out)
            if rc == want_rc and want_text in text:
                held += 1
                print("  ok   %s (exit %d)" % (name, rc))
            else:
                print("  FAIL %s: exit %d, wanted %d with %r\n%s" % (name, rc, want_rc, want_text, text[-1500:]))
        total += 1
        proc = subprocess.run([sys.executable, os.path.abspath(__file__), "--bogus"], capture_output=True, text=True,
                              check=False)
        codes.add(proc.returncode)
        if proc.returncode == 2 and "usage" in proc.stderr:
            held += 1
            print("  ok   bad-option (exit 2)")
        else:
            print("  FAIL bad-option: exit %d" % proc.returncode)
    documented = [int(m.group(1)) for m in re.finditer(r"^  (\d) ", __doc__.split("Exit codes:", 1)[1], re.M)]
    print("    exit codes reached: %s   documented: %s" % (" ".join(str(c) for c in sorted(codes)),
                                                          " ".join(str(c) for c in documented)))
    print("    NOT ASSERTED: the page run in a browser; a capability granted in the publish call; an API the lists"
          " do not name, beyond the template-script identity")
    print("check-plan-page selftest: %d of %d cases held" % (held, total))
    return 0 if held == total and codes == set(documented) else 1


def shq(s):
    return "'" + s.replace("'", "'\\''") + "'"


def main(argv):
    args = argv[1:]
    if args == ["--version"]:
        print(VERSION)
        return 0
    if args in (["--help"], ["-h"]):
        print(__doc__)
        return 0
    if args in (["--selftest"], ["--self-test"]):
        return selftest()
    root, builder, fixture = None, os.path.join(HERE, "build-plan-page.sh"), os.path.join(SKILL, "fixtures", "plan-page")
    while args:
        a = args.pop(0)
        if a in ("--root", "--builder", "--fixture") and args:
            v = args.pop(0)
            if a == "--root":
                root = v
            elif a == "--builder":
                builder = v
            else:
                fixture = v
        else:
            sys.stderr.write(USAGE)
            return 2
    if root is None:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False)
        root = top.stdout.strip() if top.returncode == 0 else os.getcwd()
    root = os.path.abspath(root)
    builder = builder if os.path.isabs(builder) else os.path.join(root, builder)
    fixture = fixture if os.path.isabs(fixture) else os.path.join(root, fixture)
    rc, out = run(root, builder, fixture)
    stream = sys.stderr if rc == 2 else sys.stdout
    for line in out:
        stream.write(line + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
