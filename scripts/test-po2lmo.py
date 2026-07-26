#!/usr/bin/env python3
"""Tests for the LMO compiler and the translation catalogues.

The hash vectors are pinned against the upstream po2lmo binary built from
luci-base. Set PO2LMO_REFERENCE to a real po2lmo executable to additionally
diff the compiled output byte for byte.
"""

import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from po2lmo import compile_po, sfh_hash  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATALOG = "mtproto-monitor"
LANGUAGES = ["ru"]

# Verified against sfh_hash() from luci-base/src/lib/lmo.c. The browser side
# computes the same values in sfh() from luci-base/htdocs/.../cbi.js.
HASH_VECTORS = {
    "": 0x00000000,
    "a": 0x115EA782,
    "ab": 0x516B8B44,
    "abc": 0xD2BE198A,
    "abcd": 0xDAD8B8DB,
    "Show": 0x49D1A0A4,
    "ctx\1key": 0x999A0ABE,
}


def fail(message):
    print(f"test-po2lmo: {message}", file=sys.stderr)
    sys.exit(1)


def check(condition, message):
    if not condition:
        fail(message)


def read_lmo(payload):
    """Decode an LMO archive the way lmo.c reads it: {key_id: value}."""
    (blob_size,) = struct.unpack(">I", payload[-4:])
    index = payload[blob_size:-4]
    check(len(index) % 16 == 0, "index size is not a multiple of the entry size")

    catalog = {}
    previous = None
    for offset in range(0, len(index), 16):
        key_id, _val_id, value_offset, length = struct.unpack(
            ">IIII", index[offset:offset + 16]
        )
        check(
            previous is None or key_id >= previous,
            "index is not sorted by key_id",
        )
        previous = key_id
        check(
            value_offset + length <= blob_size,
            f"entry {key_id:08x} points outside the string blob",
        )
        catalog[key_id] = payload[value_offset:value_offset + length].decode()
    return catalog


def trimws(value):
    """The normalisation _() applies before hashing, from cbi.js."""
    return re.sub(r"[ \t\n]+", " ", value.strip())


def lookup_key(context, msgid):
    """The key _(msgid, context) hashes, from cbi.js."""
    prefix = f"{trimws(context)}\1" if context is not None else ""
    return sfh_hash(f"{prefix}{trimws(msgid)}".encode())


def parse_po(path):
    """Return {(msgctxt, msgid): msgstr} for the single-form records we ship."""
    entries = {}
    context = None
    msgid = None
    field = None
    values = {"msgctxt": "", "msgid": "", "msgstr": ""}
    pending = False

    def flush():
        if pending and values["msgid"]:
            entries[(context, values["msgid"])] = values["msgstr"]

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#") or not line:
            continue

        match = re.match(r'^(msgctxt|msgid|msgstr)\s+"(.*)"$', line)
        if match:
            keyword, text = match.groups()
            if keyword == "msgctxt":
                flush()
                pending = False
                context = text
                values = {"msgctxt": text, "msgid": "", "msgstr": ""}
            elif keyword == "msgid":
                if pending:
                    flush()
                    context = None
                values["msgid"] = text
                values["msgstr"] = ""
                pending = True
            else:
                values["msgstr"] = text
            field = keyword
            msgid = values["msgid"]
            continue

        match = re.match(r'^"(.*)"$', line)
        if match and field:
            key = "msgctxt" if field == "msgctxt" else field
            values[key] += match.group(1)
            if field == "msgctxt":
                context = values["msgctxt"]
    flush()
    del msgid
    return entries


def declared_context():
    """The context luci/shared.js passes to _()."""
    text = (ROOT / "luci" / "shared.js").read_text(encoding="utf-8")
    match = re.search(r"var CONTEXT = '((?:[^'\\]|\\.)*)';", text)
    check(match is not None, "luci/shared.js does not declare a CONTEXT")
    check(
        re.search(r"return _\(\s*text\s*,\s*CONTEXT\s*\)", text) is not None,
        "luci/shared.js does not translate through _(text, CONTEXT)",
    )
    return match.group(1)


def source_strings():
    """Every literal passed to common.tr() in the shipped JavaScript."""
    found = set()
    for path in sorted((ROOT / "luci").glob("*.js")):
        text = path.read_text(encoding="utf-8")
        for match in re.finditer(r"common\.tr\(\s*'((?:[^'\\]|\\.)*)'", text):
            found.add(match.group(1).replace("\\'", "'").replace("\\\\", "\\"))
    return found


def test_hash_vectors():
    for value, expected in HASH_VECTORS.items():
        actual = sfh_hash(value.encode())
        check(
            actual == expected,
            f"sfh_hash({value!r}) = {actual:08x}, expected {expected:08x}",
        )


def test_empty_catalog():
    header = 'msgid ""\nmsgstr "Content-Type: text/plain; charset=UTF-8\\n"\n'
    check(
        compile_po(header) is None,
        "a catalogue without translations must not produce a file",
    )


def test_identical_translation_omitted():
    check(
        compile_po('msgid "same"\nmsgstr "same"\n') is None,
        "a translation identical to its source must be omitted",
    )


def test_plural_forms_recorded():
    payload = compile_po(
        'msgid ""\nmsgstr ""\n'
        '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n'
    )
    check(payload is not None, "the plural formula must be compiled")
    catalog = read_lmo(payload)
    check(
        catalog.get(0) == "nplurals=2; plural=(n != 1);",
        f"unexpected plural formula entry: {catalog.get(0)!r}",
    )


def test_context_is_applied():
    """A context must change the key, otherwise it isolates nothing."""
    plain = compile_po('msgid "Connections"\nmsgstr "Подключения"\n')
    scoped = compile_po(
        'msgctxt "mtproto-monitor"\n'
        'msgid "Connections"\nmsgstr "Подключения"\n'
    )
    check(plain is not None and scoped is not None, "both catalogues compile")
    check(
        set(read_lmo(plain)) != set(read_lmo(scoped)),
        "msgctxt did not change the compiled key",
    )
    check(
        lookup_key("mtproto-monitor", "Connections") in read_lmo(scoped),
        "the scoped key is not the one _() would look up",
    )


def test_catalogs_round_trip():
    """Every translation must be reachable through the hash _() computes."""
    context = declared_context()
    for language in LANGUAGES:
        path = ROOT / "po" / language / f"{CATALOG}.po"
        entries = parse_po(path)
        check(bool(entries), f"{path} has no translations")

        payload = compile_po(path.read_text(encoding="utf-8"))
        check(payload is not None, f"{path} compiled to an empty catalogue")
        catalog = read_lmo(payload)

        for (msgctxt, msgid), msgstr in entries.items():
            check(
                msgctxt == context,
                f"{path}: {msgid!r} uses msgctxt {msgctxt!r}, "
                f"but luci/shared.js passes {context!r}",
            )
            check(
                msgid == trimws(msgid),
                f"{path}: msgid is not whitespace-normalised: {msgid!r}",
            )
            key = lookup_key(msgctxt, msgid)
            # po2lmo drops an entry whose key and value hash alike.
            if key == sfh_hash(msgstr.encode()):
                continue
            check(
                catalog.get(key) == msgstr,
                f"{path}: {msgid!r} resolves to {catalog.get(key)!r}, "
                f"expected {msgstr!r}",
            )


def test_catalogs_cover_sources():
    used = source_strings()
    check(bool(used), "no common.tr() strings were found in the sources")

    template = parse_po(ROOT / "po" / "templates" / f"{CATALOG}.pot")
    template_ids = {msgid for _context, msgid in template}
    check(
        template_ids == used,
        f"po/templates/{CATALOG}.pot is out of sync with the sources; "
        f"only in template: {sorted(template_ids - used)}; "
        f"only in sources: {sorted(used - template_ids)}",
    )
    check(
        not any(template.values()),
        "the template must not carry translations",
    )

    for language in LANGUAGES:
        path = ROOT / "po" / language / f"{CATALOG}.po"
        entries = parse_po(path)
        entry_ids = {msgid for _context, msgid in entries}
        check(
            entry_ids == used,
            f"{path} is out of sync with the sources; "
            f"only in catalogue: {sorted(entry_ids - used)}; "
            f"only in sources: {sorted(used - entry_ids)}",
        )
        for (_context, msgid), msgstr in entries.items():
            check(msgstr != "", f"{path}: {msgid!r} is untranslated")


def test_no_untranslated_literals():
    """A user-visible string must go through common.tr(), not sit in the code.

    Comments are exempt: the reason a string is translated the way it is often
    has to be written down next to the code that translates it.
    """
    comment = re.compile(r"^\s*(//|/\*|\*)")
    for path in sorted((ROOT / "luci").glob("*.js")):
        for number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), 1
        ):
            if comment.match(line):
                continue
            check(
                not re.search(r"[А-Яа-яЁё]", line),
                f"{path.name}:{number}: translated text belongs in po/, "
                f"not in the source: {line.strip()!r}",
            )


def test_languages_registered():
    """Every shipped catalogue needs a display name in the uci-defaults script.

    LuCI only offers languages listed in luci.languages, so a catalogue with no
    entry there can never be selected.
    """
    script = (
        ROOT / "runtime" / "mtproto-monitor.uci-defaults"
    ).read_text(encoding="utf-8")

    for language in LANGUAGES:
        check(
            re.search(rf"^\s*{re.escape(language)}\)\s", script, re.MULTILINE),
            f"{language} has no display name in the uci-defaults script",
        )


def test_reference_binary():
    reference = os.environ.get("PO2LMO_REFERENCE")
    if not reference:
        print("test-po2lmo: PO2LMO_REFERENCE not set, skipping oracle diff")
        return

    for language in LANGUAGES:
        source = ROOT / "po" / language / f"{CATALOG}.po"
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / "reference.lmo"
            subprocess.run([reference, str(source), str(expected)], check=True)
            check(
                expected.read_bytes()
                == compile_po(source.read_text(encoding="utf-8")),
                f"{source}: output differs from {reference}",
            )
    print("test-po2lmo: output matches the reference po2lmo binary")


def main():
    test_hash_vectors()
    test_empty_catalog()
    test_identical_translation_omitted()
    test_plural_forms_recorded()
    test_context_is_applied()
    test_catalogs_round_trip()
    test_catalogs_cover_sources()
    test_no_untranslated_literals()
    test_languages_registered()
    test_reference_binary()
    print("po2lmo tests OK")


if __name__ == "__main__":
    main()
