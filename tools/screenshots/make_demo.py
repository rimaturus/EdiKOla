"""Builds a demo Kobo home for README screenshots: fictional newspapers with original placeholder
text and drawn covers, so no real outlet's content or name ends up in the images.

    python3 make_demo.py <home_dir>
"""
import datetime, os, re, struct, sys, zipfile, zlib

home = sys.argv[1]
today = datetime.date.today().isoformat()

PAPERS = [  # id, name, section, headline
    ("borgo", "Il Corriere del Borgo", "italia", "Torna il mercato del sabato in piazza: banchi di frutta, fiori e formaggi"),
    ("valle", "Gazzetta della Valle", "italia", "Nuova pista ciclabile lungo il fiume, inaugurazione domenica mattina"),
    ("lago", "La Voce del Lago", "italia", "Concerto all'aperto per l'estate: il coro cittadino canta al porto"),
    ("colle", "Il Giornale del Colle", "italia", "Biblioteca aperta anche la sera: più posti per leggere e studiare"),
    ("harbor", "Harbor Herald", "mondo", "Coastal towns plant new dunes to protect beaches from winter storms"),
    ("north", "The Northern Post", "mondo", "Night trains return: new sleeper routes link three capitals"),
    ("globe", "Daily Globe Demo", "mondo", "Community gardens spread across city rooftops this spring"),
    ("sorriso", "Il Sorriso Quotidiano", "buone", "Il paese adotta i nonni: ogni giovedì merenda e racconti a scuola"),
    ("sunny", "Sunny Side Post", "buone", "A retired baker teaches the whole street to make bread on Sundays"),
    ("stelle", "Cronache delle Stelle", "scienza", "Una nuova cometa sarà visibile a occhio nudo prima di Natale"),
    ("lab", "Lab Notes Demo", "scienza", "Quieter, cheaper heat pumps reach small apartments"),
]

ARTICLE = ("Questo è un testo di esempio scritto per le immagini del README. "
           "Serve a mostrare come appare un articolo su EdiKOla: solo testo e foto, "
           "nessuna pubblicità, nessun menu, nessun link che porta altrove. ") * 6


def png(path, w, h, seed):
    """Grayscale landscape: sky gradient, sun, rolling hills. Pure stdlib."""
    import math
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            v = 235 - int(60 * y / h)
            if (x - w * 0.72) ** 2 + (y - h * 0.28) ** 2 < (h * 0.12) ** 2:
                v = 250
            hill1 = h * (0.62 + 0.08 * math.sin(x / w * 6.3 + seed))
            hill2 = h * (0.78 + 0.06 * math.sin(x / w * 9.1 + seed * 2))
            if y > hill1:
                v = 150
            if y > hill2:
                v = 90
            row.append(v)
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                + chunk(b"IDAT", raw) + chunk(b"IEND", b""))


def xhtml(title, body):
    return (f'<?xml version="1.0" encoding="utf-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head>'
            f'<title>{title}</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>{body}</body></html>')


# Same stylesheet the real editions use
_build = open(os.path.join(os.path.dirname(__file__), "..", "..", "konewspaper.koplugin", "knp_build.lua"), encoding="utf8").read()
CSS = re.search(r"local CSS = \[\[\n(.*?)\]\]", _build, re.S).group(1)

for i, (pid, name, section, headline) in enumerate(PAPERS):
    d = os.path.join(home, "KoNewspaper", pid)
    os.makedirs(d, exist_ok=True)
    cover = os.path.join(d, f"{today}.cover.png")
    png(cover, 480, 300, i)
    titles = [headline, "Un secondo titolo di esempio", "Un terzo titolo di esempio"]
    toc = "".join(f'<p><a href="a{n}.xhtml">{t}</a></p>' for n, t in enumerate(titles, 1))
    with zipfile.ZipFile(os.path.join(d, f"{today}.epub"), "w") as z:
        z.writestr("mimetype", "application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        z.writestr("OEBPS/style.css", CSS)
        z.writestr("OEBPS/index.xhtml", xhtml(name, f'<h1 class="mast">{name}</h1><p class="date">{today}</p><div class="toc">{toc}</div>'))
        for n, t in enumerate(titles, 1):
            img = '<div class="img"><img src="cover.png" alt=""/></div>' if n == 1 else ""
            z.writestr(f"OEBPS/a{n}.xhtml", xhtml(t, f"<h1>{t}</h1>{img}<p>{ARTICLE}</p><p>{ARTICLE}</p>"
                                                   '<p class="back"><a href="index.xhtml">↩ Torna ai titoli</a></p>'))
        z.write(cover, "OEBPS/cover.png", zipfile.ZIP_STORED)
        items = "".join(f'<item id="a{n}" href="a{n}.xhtml" media-type="application/xhtml+xml"/>' for n in range(1, 4))
        spine = "".join(f'<itemref idref="a{n}"/>' for n in range(1, 4))
        z.writestr("OEBPS/content.opf", f'<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" unique-identifier="id" version="2.0"><metadata><dc:title>{name}</dc:title><dc:identifier id="id">demo-{pid}</dc:identifier><dc:language>it</dc:language></metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="css" href="style.css" media-type="text/css"/><item id="index" href="index.xhtml" media-type="application/xhtml+xml"/>{items}<item id="cover" href="cover.png" media-type="image/png"/></manifest><spine toc="ncx"><itemref idref="index"/>{spine}</spine></package>')
        nav = "".join(f'<navPoint id="n{n}" playOrder="{n}"><navLabel><text>{t}</text></navLabel><content src="{f}"/></navPoint>'
                      for n, (t, f) in enumerate([("Prima pagina", "index.xhtml")] + [(t, f"a{k}.xhtml") for k, t in enumerate(titles, 1)], 1))
        z.writestr("OEBPS/toc.ncx", f'<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>{name}</text></docTitle><navMap>{nav}</navMap></ncx>')
    with open(os.path.join(d, f"{today}.meta.lua"), "w", encoding="utf8") as f:
        brief = "Questo è un testo di esempio scritto per le immagini del README."
        arts = ", ".join(f'{{ title = "{t}", brief = "{brief}" }}' for t in titles)
        f.write(f'return {{ headline = "{headline}", cover = "{cover}", articles = {{ {arts} }} }}\n')

# The demo catalog: fictional papers, all selected
with open(os.path.join(home, "giornali_demo.lua"), "w", encoding="utf8") as f:
    f.write("return {\n" + "".join(
        f'  {{ id = "{p}", section = "{s}", name = "{n}", feed = "https://example.invalid/{p}", default = true }},\n'
        for p, n, s, _ in PAPERS) + "}\n")

# A few books for "I miei libri" (names only matter for the list)
libri = os.path.join(home, "Libri")
os.makedirs(libri, exist_ok=True)
for b in ["I promessi sposi.epub", "Le avventure di Pinocchio.epub", "Cuore.pdf", "Ricette della nonna.pdf", "Pride and Prejudice.epub"]:
    open(os.path.join(libri, b), "wb").close()
print("demo home ready:", home)
