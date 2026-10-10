#!/usr/bin/env python3
"""Build MouseGestures plugins into signed, zipped bundles and regenerate library.json.

  python3 build.py [--sdk DIR] [--only slug ...] [--identity "Developer ID..."]

--sdk: folder containing MouseGestures.swiftmodule (a Release build's Products dir).
Needs Xcode's swiftc. Bundles are ad-hoc signed unless --identity is given.
Plugins link against the app's own symbols at load time (-undefined dynamic_lookup).
"""
import re, argparse, hashlib, json, os, plistlib, shutil, subprocess, sys, glob

ROOT = os.path.dirname(os.path.abspath(__file__))
DEV = os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")

def sh(*a, **k):
    r = subprocess.run(a, capture_output=True, text=True, **k)
    if r.returncode:
        sys.exit(f"FAILED: {' '.join(a)}\n{r.stdout}{r.stderr}")
    return r.stdout

def default_sdk():
    c = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/MouseGestures-*/Build/Products/Release"))
    return max(c, key=os.path.getmtime) if c else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk", default=default_sdk())
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--identity", default="-")
    ap.add_argument("--min-macos", default="13.0")
    args = ap.parse_args()
    if not args.sdk or not os.path.isdir(os.path.join(args.sdk, "MouseGestures.swiftmodule")):
        sys.exit("pass --sdk <dir containing MouseGestures.swiftmodule>")

    dist = os.path.join(ROOT, "dist"); build = os.path.join(ROOT, ".build")
    os.makedirs(dist, exist_ok=True)
    manifest_path = os.path.join(ROOT, "library.json")
    lib = json.load(open(os.path.join(ROOT, "library-info.json")))
    entries = []
    for pj in sorted(glob.glob(os.path.join(ROOT, "plugins", "*", "plugin.json"))):
        d = os.path.dirname(pj); slug = os.path.basename(d)
        meta = json.load(open(pj))
        if args.only and slug not in args.only:
            old = next((p for p in json.load(open(manifest_path))["plugins"] if p["id"] == meta["id"]), None) if os.path.exists(manifest_path) else None
            if old: entries.append(old)
            continue
        print(f"== {meta['name']} {meta['version']}")
        # Per-version class names: a loaded bundle can't be unmapped, so an update with the
        # same ObjC class names would run stale code and force an app restart. Unique names
        # let MouseGestures swap the new version in live.
        vtag = meta["version"].replace(".", "_")
        exe = f"{meta['principalClass']}_v{vtag}"
        bundle = os.path.join(build, slug, f"{meta['id']}.plugin")
        shutil.rmtree(os.path.join(build, slug), ignore_errors=True)
        os.makedirs(os.path.join(bundle, "Contents", "MacOS"))
        srcs = []
        sdir = os.path.join(build, slug, "src"); os.makedirs(sdir)
        for f in sorted(glob.glob(os.path.join(d, "Sources", "*.swift"))):
            text = re.sub(r"@objc\((\w+)\)", lambda m: f"@objc({m.group(1)}_v{vtag})" if m.group(1) == meta["principalClass"] else m.group(0), open(f).read())
            out = os.path.join(sdir, os.path.basename(f)); open(out, "w").write(text); srcs.append(out)
        # Files listed in plugin.json "shared" (relative to the Plugins/shared folder) are compiled into the bundle too.
        for name in meta.get("shared", []):
            out = os.path.join(sdir, name); shutil.copy(os.path.join(ROOT, "shared", name), out); srcs.append(out)
        sh("xcrun", "swiftc", "-O", "-swift-version", "5", "-parse-as-library", "-module-name", exe,
           "-target", f"arm64-apple-macosx{args.min_macos}", "-I", args.sdk,
           # SwiftUI's @State/@Observable are macros; plugins that use SwiftUI need the SDK's macro plugins
           "-plugin-path", os.path.join(DEV, "Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"),
           "-Xlinker", "-bundle", "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
           "-emit-library", "-o", os.path.join(bundle, "Contents", "MacOS", exe), *srcs)
        plistlib.dump({
            "CFBundleExecutable": exe, "CFBundleIdentifier": meta["id"], "CFBundleName": meta["name"],
            "CFBundlePackageType": "BNDL", "CFBundleVersion": meta["version"],
            "CFBundleShortVersionString": meta["version"], "NSPrincipalClass": exe,
            "LSMinimumSystemVersion": args.min_macos, "MGPluginKind": meta["kind"],
        }, open(os.path.join(bundle, "Contents", "Info.plist"), "wb"))
        sh("codesign", "--force", "-s", args.identity, bundle)
        sh("codesign", "--verify", "--deep", "--strict", bundle)
        zip_name = f"{meta['id']}-{meta['version']}.zip"
        zip_path = os.path.join(dist, zip_name)
        for old in glob.glob(os.path.join(dist, f"{meta['id']}-*.zip")): os.remove(old)
        sh("ditto", "-c", "-k", "--keepParent", bundle, zip_path)
        digest = hashlib.sha256(open(zip_path, "rb").read()).hexdigest()
        e = {k: meta[k] for k in ("id", "name", "kind", "version", "author", "description") if k in meta}
        if meta.get("permissions"): e["permissions"] = meta["permissions"]
        if meta.get("requires"): e["requires"] = meta["requires"]
        if meta.get("recommended"): e["recommended"] = True
        e["minAppVersion"] = meta.get("minAppVersion", "1.1.0")
        e["download"] = f"dist/{zip_name}"; e["sha256"] = digest
        entries.append(e)
    json.dump({"schemaVersion": 1, **lib, "plugins": entries}, open(manifest_path, "w"), indent=2)
    open(manifest_path, "a").write("\n")
    print(f"library.json: {len(entries)} plugins")

main()
