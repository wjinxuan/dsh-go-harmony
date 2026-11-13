#!/usr/bin/env python3
"""Check the page-class inventory against the pinned DSH Go source tree."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys


VERSION = "v1.0.15"
COMMIT = "a9877420ab9aee121134faf01b6a92a39ce0b05b"
UI = Path("app/lib/ui")
INVENTORY = Path(__file__).resolve().parents[1] / "docs/parity/ui-pages.json"
TOKEN = re.compile(
    r"//[^\n]*|/\*"
    r"|(?:\br)?(?:'''|\"\"\")"
    r"|(?:\br)?['\"]"
)
BLOCK_TOKEN = re.compile(r"/\*|\*/")
PAGE = re.compile(
    r"^[ \t]*(?:(?:base|final|interface)\s+)?class\s+"
    r"([A-Z][A-Za-z0-9_]*(?:Page|Screen))\s+extends\s+"
    r"(?:StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|HookConsumerWidget)\b",
    re.MULTILINE,
)


def block_comment_end(source, start):
    depth = 1
    for token in BLOCK_TOKEN.finditer(source, start):
        depth += 1 if token[0] == "/*" else -1
        if depth == 0:
            return token.end()
    return len(source)


def dart_code(source):
    # Preserve offsets and line breaks so reported locations refer to the original blob.
    parts = []
    offset = 0
    while token := TOKEN.search(source, offset):
        parts.append(source[offset:token.start()])
        delimiter = token[0]
        if delimiter.startswith("//"):
            end = token.end()
        elif delimiter == "/*":
            end = block_comment_end(source, token.end())
        else:
            raw = delimiter.startswith("r")
            quote = delimiter.removeprefix("r")
            if raw:
                closing = source.find(quote, token.end())
                end = len(source) if closing < 0 else closing + len(quote)
            else:
                closing = re.compile(r"\\[\s\S]|" + re.escape(quote))
                end = len(source)
                for match in closing.finditer(source, token.end()):
                    if match[0] == quote:
                        end = match.end()
                        break
        parts.append(re.sub(r"[^\n]", " ", source[token.start():end]))
        offset = end
    parts.append(source[offset:])
    return "".join(parts)


def page_classes(path, source):
    group = path.relative_to(UI).parts[0]
    return [
        {"group": group, "name": match[1], "path": path.as_posix(),
         "line": source.count("\n", 0, match.start(1)) + 1}
        for match in PAGE.finditer(dart_code(source))
    ]


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args], encoding="utf-8")


def read_inventory(source):
    if git(source, "rev-parse", "HEAD").strip() != COMMIT:
        raise ValueError(f"Source HEAD must be DSH Go {VERSION} ({COMMIT}).")
    paths = git(source, "ls-tree", "-r", "-z", "--name-only", COMMIT, "--", str(UI)).split("\0")
    pages = [
        page
        for path in sorted(paths) if path.endswith(".dart")
        for page in page_classes(Path(path), git(source, "show", f"{COMMIT}:{path}"))
    ]
    return {
        "schemaVersion": 1,
        "upstream": {"repository": "https://github.com/ccch1mneyyy/dsh-Go", "version": VERSION, "commitSha": COMMIT},
        "scope": {
            "directory": UI.as_posix(),
            "selection": "Public Flutter widget class names ending in Page or Screen",
            "classCount": len(pages),
            "fileCount": len({page["path"] for page in pages}),
            "isRouteInventory": False,
            "notes": (
                "Includes nested or reusable page bodies and excludes navigation entries implemented as "
                "differently named widgets, sheets, dialogs, and dynamic routes."
            ),
        },
        "countsByGroup": dict(sorted(Counter(page["group"] for page in pages).items())),
        "pages": pages,
    }


def self_test():
    source = """// class IgnoredPage extends StatelessWidget {}
/*
class AlsoIgnoredPage extends StatelessWidget {}
/* Nested comment */
*/
final text = r'''
class StringPage extends StatelessWidget {}
''';
class _PrivateScreen extends StatelessWidget {}
class HelperPage extends ConsumerState {}
class FirstPage extends StatelessWidget {}
  final class SecondScreen
    extends ConsumerStatefulWidget {}
"""
    pages = page_classes(UI / "fixture" / "multi.dart", source)
    assert [(page["name"], page["line"]) for page in pages] == [("FirstPage", 11), ("SecondScreen", 12)]
    print("Inventory parser self-test passed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Checkout of the pinned upstream source")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--output", type=Path, help="Write inventory to this path instead of checking the tracked copy")
    action.add_argument("--self-test", action="store_true", help="Run the parser fixture")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.source is None:
        parser.error("--source is required unless running --self-test")

    try:
        inventory = read_inventory(args.source)
        if args.output:
            args.output.write_text(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        elif inventory != json.loads(INVENTORY.read_text(encoding="utf-8")):
            print(f"{INVENTORY} differs from the pinned source; regenerate with --output.", file=sys.stderr)
            return 1
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    print(f"{inventory['scope']['classCount']} public page/screen classes. Independent routes require separate review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
