# -*- coding: utf-8 -*-
"""
Erzeugt die Bildmarke von AdminWerk.

Entwurf
-------
Sechskant (Mutter) im Blauverlauf der Anwendung, darin ein "A" in Segoe UI Bold.
Der Sechskant steht fuer "Werk" - Handwerk, Technik -, das A fuer AdminWerk.

Bewusst vermieden:
  * das Windows-Logo (Marke der Microsoft Corporation)
  * eine blaue Kachel mit ">_" - das ist praktisch die Bildmarke von PowerShell
    und waere in der Taskleiste daneben nicht zu unterscheiden

Bei kleinen Groessen wird der Rand schmaler und der Buchstabe groesser, damit
die Marke auch bei 16 Pixel noch lesbar bleibt.

Aufruf:  python logo-final.py <projektverzeichnis>
"""

import io
import math
import struct
import sys
from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageFont

VERLAUF_OBEN  = (0x6F, 0xB2, 0xFF)
VERLAUF_UNTEN = (0x2A, 0x63, 0xC8)
GLYPH         = (0xF4, 0xF8, 0xFF)
TEXT_HELL     = (0xE6, 0xED, 0xF3)
TEXT_AKZENT   = (0x4C, 0x9A, 0xFF)
TEXT_GRAU     = (0x93, 0xA1, 0xB1)
TEXT_DUNKEL   = (0x1B, 0x24, 0x30)   # fuer helle Hintergruende

SEGOE_FETT   = r"C:\Windows\Fonts\segoeuib.ttf"
SEGOE_NORMAL = r"C:\Windows\Fonts\segoeui.ttf"

UEBERABTASTUNG = 4

# Groesse -> (Randanteil, Buchstabenanteil). Kleine Symbole vertragen weniger Rand.
ABSTIMMUNG = {
    256: (0.030, 0.66), 128: (0.030, 0.66), 64: (0.022, 0.68),
    48:  (0.018, 0.70),  32: (0.014, 0.72), 24: (0.010, 0.74), 16: (0.008, 0.78),
}


def _abstimmung(groesse):
    for grenze in sorted(ABSTIMMUNG, reverse=True):
        if groesse >= grenze:
            return ABSTIMMUNG[grenze]
    return ABSTIMMUNG[16]


def _verlauf(g):
    """Diagonaler Zweifarbverlauf."""
    kante = 256
    grau = Image.new("L", (kante, kante))
    px = grau.load()
    for y in range(kante):
        for x in range(kante):
            px[x, y] = (x + y) * 255 // (2 * (kante - 1))
    return ImageOps.colorize(grau, black=VERLAUF_OBEN, white=VERLAUF_UNTEN).resize((g, g), Image.BICUBIC)


def _schein(g, maske):
    """Weicher Lichtschein im oberen Bereich."""
    alpha = Image.new("L", (g, g), 0)
    px = alpha.load()
    for y in range(g):
        s = max(0, 40 - int(40 * y / (g * 0.55)))
        for x in range(g):
            px[x, y] = s
    return ImageChops.multiply(alpha, maske)


def _maske_sechseck(g, rand_anteil):
    """Sechskant mit abgerundeten Ecken, waagerechte Kanten oben und unten."""
    rand = int(g * rand_anteil)
    R = (g - 2 * rand) / 2.0
    c = g / 2.0
    ecken = [(c + R * math.cos(math.radians(60 * i)), c + R * math.sin(math.radians(60 * i)))
             for i in range(6)]
    # Die flache Ausrichtung ist breiter als hoch - senkrecht strecken, damit
    # die Marke das quadratische Symbolfeld besser ausfuellt.
    ecken = [(x, c + (y - c) * (2 / math.sqrt(3)) * 0.88) for x, y in ecken]

    maske = Image.new("L", (g, g), 0)
    z = ImageDraw.Draw(maske)
    eckradius = max(1, int(R * 0.15))
    z.polygon(ecken, fill=255)
    z.line(ecken + [ecken[0]], fill=255, width=eckradius * 2, joint="curve")
    # Runde Kappe auf jeder Ecke - sonst bleibt an der Naht eine Kerbe stehen.
    for x, y in ecken:
        z.ellipse((x - eckradius, y - eckradius, x + eckradius, y + eckradius), fill=255)
    return maske


def bildmarke(groesse):
    """Zeichnet die Marke in der gewuenschten Kantenlaenge."""
    rand_anteil, buchstabe_anteil = _abstimmung(groesse)
    g = groesse * UEBERABTASTUNG

    maske = _maske_sechseck(g, rand_anteil)
    bild = Image.new("RGBA", (g, g), (0, 0, 0, 0))
    bild.paste(_verlauf(g), (0, 0), maske)
    bild.paste(Image.new("RGBA", (g, g), (255, 255, 255, 255)), (0, 0), _schein(g, maske))

    schrift = ImageFont.truetype(SEGOE_FETT, int(g * buchstabe_anteil))
    z = ImageDraw.Draw(bild)
    kasten = z.textbbox((0, 0), "A", font=schrift)
    x = (g - (kasten[2] - kasten[0])) / 2 - kasten[0]
    y = (g - (kasten[3] - kasten[1])) / 2 - kasten[1]
    z.text((x, y), "A", font=schrift, fill=GLYPH)

    return bild.resize((groesse, groesse), Image.LANCZOS)


def wortmarke(kachel=300, fuer_dunkel=True):
    """
    Bildmarke plus Schriftzug, transparenter Hintergrund.
    fuer_dunkel=False liefert die Fassung fuer helle Hintergruende - sonst
    verschwindet "Admin" im hellen Thema von GitHub.
    """
    fett   = ImageFont.truetype(SEGOE_FETT, 168)
    normal = ImageFont.truetype(SEGOE_NORMAL, 58)

    messer = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    b_admin = messer.textlength("Admin", font=fett)
    b_werk  = messer.textlength("Werk", font=fett)
    untertitel = "Windows Administration Suite"
    b_unter = messer.textlength(untertitel, font=normal)

    polster = 18
    abstand = 52
    text_x = polster + kachel + abstand
    breite = int(text_x + max(b_admin + b_werk, b_unter) + polster + 8)
    hoehe = 360

    bild = Image.new("RGBA", (breite, hoehe), (0, 0, 0, 0))
    marke = bildmarke(kachel)
    bild.paste(marke, (polster, (hoehe - kachel) // 2), marke)

    z = ImageDraw.Draw(bild)
    grundlinie = 188
    farbe_admin = TEXT_HELL if fuer_dunkel else TEXT_DUNKEL
    z.text((text_x, grundlinie), "Admin", font=fett, fill=farbe_admin, anchor="ls")
    z.text((text_x + b_admin, grundlinie), "Werk", font=fett, fill=TEXT_AKZENT, anchor="ls")
    z.text((text_x + 4, grundlinie + 74), untertitel, font=normal, fill=TEXT_GRAU, anchor="ls")
    return bild


def ico_schreiben(pfad, bilder):
    """Baut einen ICO-Container aus mehreren PNG-Bildern (Vista und neuer)."""
    daten = []
    for bild in bilder:
        puffer = io.BytesIO()
        bild.save(puffer, format="PNG")
        daten.append(puffer.getvalue())

    kopf = struct.pack("<HHH", 0, 1, len(bilder))
    versatz = len(kopf) + 16 * len(bilder)
    eintraege = b""
    for bild, roh in zip(bilder, daten):
        kante = 0 if bild.width >= 256 else bild.width   # 0 bedeutet 256
        eintraege += struct.pack("<BBBBHHII", kante, kante, 0, 0, 1, 32, len(roh), versatz)
        versatz += len(roh)

    with open(pfad, "wb") as datei:
        datei.write(kopf + eintraege + b"".join(daten))


if __name__ == "__main__":
    projekt = sys.argv[1] if len(sys.argv) > 1 else "."

    bildmarke(512).save(f"{projekt}/docs/bilder/logo.png")
    print("docs/bilder/logo.png")

    wortmarke(fuer_dunkel=True).save(f"{projekt}/docs/bilder/logo-wortmarke-dunkel.png")
    print("docs/bilder/logo-wortmarke-dunkel.png")

    wortmarke(fuer_dunkel=False).save(f"{projekt}/docs/bilder/logo-wortmarke-hell.png")
    print("docs/bilder/logo-wortmarke-hell.png")

    groessen = [256, 128, 64, 48, 32, 24, 16]
    ico_schreiben(f"{projekt}/src/AdminWerk/Themes/adminwerk.ico",
                  [bildmarke(g) for g in groessen])
    print("src/AdminWerk/Themes/adminwerk.ico  (" + ", ".join(str(g) for g in groessen) + ")")
