#!/usr/bin/env python3
"""
build.py - Convert a TSV of parsed exam questions into question-bank CSV format.

Cross-platform port of build.ps1 (Windows PowerShell). Byte-for-byte compatible
output. Runs on any host with Python 3.7+, so the skill works under Claude Code,
OpenAI Codex and Gemini CLI on Windows, macOS and Linux alike.

Pipeline contract:
  - The agent parses the source document into questions and writes a TSV file.
  - This script applies the 27-column question-bank template header + CSV
    escaping, and writes the final CSV as UTF-8 (no BOM).
  - This script is intentionally ASCII-only so its own encoding is never an
    issue; all CJK content lives in the TSV and header.csv (read as UTF-8).

TSV format (one question per line, fields separated by a literal TAB):
  [0] type       1=true/false 2=single 3=multiple 4=fill-in 5=essay
  [1] question   question text
  [2] answer     T/F -> 1(yes) or 2(no)
                 single -> option number (e.g. 2)
                 multiple -> comma-joined numbers, e.g. 1,2,4 (script quotes it)
                 fill-in -> leave EMPTY; embed answers inline as [*answer*]
                 essay -> reference answer text
  [3] explanation  optional
  [4] difficulty   1=easy 2=medium 3=hard
  [5] option1    choices: option 1 text; fill-in: 1=ignore case 2=match case
  [6] option2    choices: option 2 text; fill-in: 1=any order 2=keep order
  [7..] option3.. additional choice options

Encode newlines inside any field as the two-character token \n ; the script
turns them into real CRLF inside a quoted CSV field.

Usage:
  python build.py --tsv rows.tsv --out exam02.csv
                  [--header header.csv] [--category NAME | --category-file F]
                  [--big5] [--big5-out PATH]

  --category       one category applied to every row (column 2)
  --category-file  a text file with ONE category per line, matched to the TSV
                   rows in order (for sources whose sections differ per block)
  --big5           also emit a Big5 (cp950) copy; default path inserts "_big5"
                   before the extension

Big5 note: cp950 has a smaller repertoire than UTF-8. A few characters are
remapped to Big5 equivalents (see REMAP below). Any character that still cannot
be encoded is written as '?' and reported as a warning, so the operator can
decide whether the Big5 copy is acceptable.
"""
import argparse
import os
import re
import sys

# Characters with a Big5-friendly equivalent. Applied only to the Big5 copy.
REMAP = {
    "\u2265": "\u2267",  # >=
    "\u2264": "\u2266",  # <=
    "\u30fb": "\u2027",  # katakana middle dot -> hyphenation point
}

# The two-character token (backslash + n) that a TSV field uses to mean "newline".
# Spelled with chr(92) so the literal survives any copy/paste or shell quoting.
NL_TOKEN = chr(92) + "n"

SPLIT_LINES = re.compile(r"\r\n|\r|\n")
NEEDS_QUOTE = re.compile(r'["\r\n,]')


def read_text(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8")


def read_lines(path):
    text = read_text(path)
    return SPLIT_LINES.split(text)


def esc(value):
    if value is None:
        value = ""
    value = value.replace(NL_TOKEN, "\r\n")
    if NEEDS_QUOTE.search(value):
        return '"' + value.replace('"', '""') + '"'
    return value


def build_rows(tsv_path, categories):
    rows = []
    idx = 0
    for line in read_lines(tsv_path):
        if not line.strip():
            continue
        fields = line.split("\t")
        if categories is None:
            category = ""
        elif isinstance(categories, str):
            category = categories
        else:
            if idx >= len(categories):
                sys.exit(
                    "ERROR: category file has %d lines but the TSV has more rows"
                    % len(categories)
                )
            category = categories[idx]
        cols = ["", category] + fields
        cols = (cols + [""] * 27)[:27]
        rows.append(",".join(esc(c) for c in cols))
        idx += 1
    if isinstance(categories, list) and idx != len(categories):
        sys.exit(
            "ERROR: category file has %d lines but the TSV has %d rows"
            % (len(categories), idx)
        )
    return rows


def write_big5(content, path):
    remapped = content
    for src, dst in REMAP.items():
        remapped = remapped.replace(src, dst)

    bad = set()
    for ch in remapped:
        if ord(ch) < 32:
            continue
        try:
            ch.encode("cp950")
        except UnicodeEncodeError:
            bad.add("%s(U+%04X)" % (ch, ord(ch)))

    with open(path, "wb") as fh:
        fh.write(remapped.encode("cp950", errors="replace"))

    size = os.path.getsize(path)
    if bad:
        print(
            "WARN -> %s  (Big5/cp950)  bytes=%d  UNMAPPABLE chars replaced "
            "with '?': %s" % (path, size, ", ".join(sorted(bad)))
        )
    else:
        print("OK -> %s  (Big5/cp950, lossless)  bytes=%d" % (path, size))


def main():
    ap = argparse.ArgumentParser(description="TSV -> question-bank CSV")
    ap.add_argument("--tsv", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--header")
    ap.add_argument("--category", default="")
    ap.add_argument("--category-file", dest="category_file")
    ap.add_argument("--big5", action="store_true")
    ap.add_argument("--big5-out", dest="big5_out", default="")
    args = ap.parse_args()

    header_path = args.header or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "header.csv"
    )
    header = read_text(header_path).rstrip("\r\n")

    if args.category_file:
        if args.category:
            sys.exit("ERROR: use either --category or --category-file, not both")
        categories = [
            ln for ln in read_lines(args.category_file) if ln.strip() != ""
        ]
        label = "<per-row: %d>" % len(categories)
    else:
        categories = args.category
        label = args.category

    rows = build_rows(args.tsv, categories)
    content = header + "\r\n" + "\r\n".join(rows) + "\r\n"

    with open(args.out, "wb") as fh:
        fh.write(content.encode("utf-8"))

    data = open(args.out, "rb").read()
    has_bom = data[:3] == b"\xef\xbb\xbf"
    print(
        "OK -> %s  rows=%d  category='%s'  bytes=%d  BOM=%s"
        % (args.out, len(rows), label, len(data), has_bom)
    )

    if args.big5 or args.big5_out:
        big5_out = args.big5_out
        if not big5_out:
            root, ext = os.path.splitext(args.out)
            big5_out = root + "_big5" + ext
        write_big5(content, big5_out)


if __name__ == "__main__":
    main()
