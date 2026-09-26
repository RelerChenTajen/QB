#!/usr/bin/env python3
"""
extract.py - Extract plain text from a source exam document.

Cross-platform replacement for the PowerShell/.NET docx snippet, so the skill
works identically under Claude Code, OpenAI Codex and Gemini CLI on Windows,
macOS and Linux.

Supported:
  .docx  - unzipped and read from word/document.xml, one line per w:p paragraph
  .txt .md .csv .tsv - read as UTF-8 (BOM stripped) and passed through

Not supported (the agent should read these with its own file tools):
  .pdf   - use the host's PDF reading capability
  .doc   - legacy binary format; ask the user to save as .docx

Usage:
  python extract.py INPUT [-o OUTPUT]     # stdout if -o is omitted
"""
import argparse
import os
import sys
import zipfile
from xml.etree import ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"


def read_text_file(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8")


def docx_paragraphs(path):
    with zipfile.ZipFile(path) as zf:
        xml = zf.read("word/document.xml")
    root = ET.fromstring(xml)
    body = root.find(W + "body")
    if body is None:
        return []
    lines = []
    for para in body.iter(W + "p"):
        text = "".join(node.text or "" for node in para.iter(W + "t"))
        lines.append(text)
    return lines


def main():
    ap = argparse.ArgumentParser(description="Extract text from an exam source file")
    ap.add_argument("input")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()

    ext = os.path.splitext(args.input)[1].lower()
    if ext == ".docx":
        text = "\n".join(docx_paragraphs(args.input))
    elif ext in (".txt", ".md", ".csv", ".tsv"):
        text = read_text_file(args.input)
    elif ext == ".pdf":
        sys.exit("ERROR: read .pdf with the host agent's own PDF tool, not this script")
    elif ext == ".doc":
        sys.exit("ERROR: legacy .doc is not supported; ask the user to save as .docx")
    else:
        sys.exit("ERROR: unsupported file type: %s" % ext)

    if args.output:
        with open(args.output, "wb") as fh:
            fh.write(text.encode("utf-8"))
        print("OK -> %s  chars=%d" % (args.output, len(text)))
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
