#!/usr/bin/env python3
"""
elts-audit.py — which Freexian ELTS fixes does OUR patched tree still lack?

Freexian's ELTS (Debian extended LTS) is the second, CloudLinux-independent
source of backports (README "Plan B"); tools/check-deps.py watches it. This
tool answers the follow-up question objectively, without trusting names: it
builds this repo's patched tree for a minor (pristine tarball + series +
patches-local, through build.sh's own functions), takes every ELTS patch that
names a CVE our series never mentions (with --all: every ELTS patch, since our
series naming a CVE does not mean it carries every upstream commit of it), drops
its tests, and dry-runs it:

    PRESENT    applies in REVERSE, or most of the lines it adds are already in
               the files it touches: the fix is in our tree
    MISSING    applies forward cleanly and its added lines are not there yet:
               we lack it, and it would go in as is
    LOOK       neither: the code differs (fixed another way, partly, or the
               patch needs adapting); read it, and port it with fuzz + review
    tests-only nothing but tests once tests are dropped

The forward check never uses patch -N: -N silently skips hunks that look
already applied and still exits 0, which would report an applied fix as MISSING.

    ./tools/elts-audit.py --minor 73               # 7.3 against ELTS php7.3
    ./tools/elts-audit.py --minor 72 --from 73     # 7.2 tree vs ELTS php7.3
    ./tools/elts-audit.py --minor 53 --from 56     # 5.3 tree vs ELTS php5 (5.6)
    ./tools/elts-audit.py --minor 73 --tree DIR    # reuse an already patched tree
    ./tools/elts-audit.py --minor 73 --all         # also CVEs our series names

Read-only: it prints a table and touches nothing in the repo. Adoption is a
separate, reviewed step. Needs network (php.net tarball, deb.freexian.com) and
the patch(1) CLI. Stdlib only.
"""
import argparse, glob, io, os, re, subprocess, sys, tarfile, tempfile, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_tsv(path):
    return dict(ln.rstrip("\n").split("\t", 1) for ln in open(path, encoding="utf-8") if "\t" in ln)


def our_cves(minor):
    out = set()
    for d in (os.path.join(ROOT, "patches", minor), os.path.join(ROOT, "patches-local", minor)):
        for f in os.listdir(d) if os.path.isdir(d) else []:
            out |= {c.upper() for c in re.findall(r"CVE-\d{4}-\d+", f, re.I)}
            if f.endswith(".patch"):
                txt = open(os.path.join(d, f), encoding="utf-8", errors="replace").read()
                out |= {c.upper() for c in re.findall(r"CVE-\d{4}-\d+", txt, re.I)}
    return out


def patched_tree(minor):
    """Pristine tarball + our series + patches-local, via build.sh's own functions."""
    root = tempfile.mkdtemp(prefix=f"elts-audit-{minor}-")
    dotted = minor[0] + "." + minor[1:]
    env = dict(os.environ, PHP_MINOR=dotted, BUILD_ROOT=root)
    subprocess.run(["bash", "-c", "source ./build.sh; fetch_php_source; apply_patches"],
                   cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
    trees = glob.glob(os.path.join(root, "php-*/"))
    if len(trees) != 1:
        sys.exit(f"expected one php-* tree under {root}, found {trees}")
    return trees[0]


def strip_tests(txt):
    out = []
    for block in re.split(r"(?m)^(?=diff --git |Index: |--- a/)", txt):
        m = re.search(r"(?m)^\+\+\+ b/(\S+)", block)
        if m and ("/tests/" in m.group(1) or m.group(1).startswith("tests/")):
            continue
        out.append(block)
    return "".join(out)


def added_lines_present(pf, tree):
    """Share of the (non-trivial) lines a patch adds that its target files already contain."""
    tot = found = 0
    for block in re.split(r"(?m)^(?=diff --git |Index: |--- a/)", open(pf, encoding="utf-8").read()):
        m = re.search(r"(?m)^\+\+\+ b/(\S+)", block)
        if not m:
            continue
        p = os.path.join(tree, m.group(1))
        src = open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""
        for ln in re.findall(r"(?m)^\+(?!\+\+)(.*)$", block):
            t = ln.strip()
            if len(t) < 10 or t.startswith(("/*", "*", "//")):
                continue
            tot += 1
            found += t in src
    return found / tot if tot else 0.0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--minor", required=True, help="our minor whose tree is checked (53, 56, 70 … 73)")
    ap.add_argument("--from", dest="src", help="minor whose elts/<nn>/ELTS names the ELTS package (default: --minor)")
    ap.add_argument("--tree", help="an already patched tree to check instead of building one")
    ap.add_argument("--all", action="store_true", help="also check ELTS patches whose CVE our series already names")
    args = ap.parse_args()
    src = args.src or args.minor
    elts = os.path.join(ROOT, "elts", src, "ELTS")
    if not os.path.exists(elts):
        sys.exit(f"no {os.path.relpath(elts, ROOT)}; ELTS covers 56/70/73, use --from for the others")
    f = read_tsv(elts)
    pkg, ver, pool = f["package"], f["version"], f["pool_url"]
    tree = args.tree or patched_tree(args.minor)
    ours = our_cves(args.minor)

    data = urllib.request.urlopen(pool + f"{pkg}_{urllib.parse.quote(ver)}.debian.tar.xz", timeout=180).read()
    tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:*")
    series = [ln.split()[0] for ln in tf.extractfile("debian/patches/series").read().decode().splitlines()
              if ln.strip() and not ln.lstrip().startswith("#")]
    work = tempfile.mkdtemp(prefix="elts-audit-patches-")
    print(f"# our {args.minor} tree vs ELTS {pkg} {ver} ({tree})")
    counts = {}
    for name in series:
        cves = {c.upper() for c in re.findall(r"CVE-\d{4}-\d+", name, re.I)}
        if not cves or (cves <= ours and not args.all):
            continue
        raw = tf.extractfile("debian/patches/" + name).read().decode("utf-8", "replace")
        m = re.search(r"(?mi)^Subject:\s*(?:\[PATCH[^]]*\]\s*)?(.*)", raw)
        subj = m.group(1)[:72] if m else ""
        body = strip_tests(raw)
        if "+++ " not in body:
            state = "tests-only"
        else:
            pf = os.path.join(work, name.replace("/", "_"))
            open(pf, "w", encoding="utf-8").write(body)

            def dry(*extra):
                return subprocess.run(["patch", "-p1", "--dry-run", "-s", "-f", *extra, "-i", pf],
                                      cwd=tree, capture_output=True, text=True).returncode == 0

            have = added_lines_present(pf, tree)
            if dry("-R") or have >= 0.8:
                state = "PRESENT"
            elif dry() and have < 0.5:
                state = "MISSING"
            else:
                state = "LOOK"
        counts[state] = counts.get(state, 0) + 1
        print(f"{state:10} {name:50} {subj}")
    print("# " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())) if counts else "# nothing to check: every ELTS CVE is named in our series")
    return 0


if __name__ == "__main__":
    sys.exit(main())
