#!/usr/bin/env python3
"""Makes app/src/main/assets/inglese.tsv: English words that may turn up in Italian articles, each with a
respelling that the Italian voice (espeak-ng's Italian rules) reads the way an Italian says it: "nature" ->
"nèiciur", "Google" -> "gùgol". Ascolta and the radio swap them in before the voice reads an Italian text.

Which words: the 30,000 most common English words (FrequencyWords, OpenSubtitles 2018) that CMUdict knows and
that are rare or absent in Italian (not among the 30,000 most common Italian words of the same corpus), plus
those espeak-ng's Italian rules already read as English (Google, Facebook…: the Italian voice would get English
sounds it was not trained on) and a few loanwords of the news. The respelling comes from CMUdict's phonemes.

  curl -LO https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict
  curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
  curl -LO https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/it/it_50k.txt
  pip install espeakng-loader phonemizer-fork
  python3 pronuncia.py > ../app/src/main/assets/inglese.tsv
"""
import re

V = {'AA': 'a', 'AE': 'e', 'AH': 'a', 'AO': 'o', 'AW': 'au', 'AY': 'ai', 'EH': 'e', 'ER': 'er', 'EY': 'ei',
     'IH': 'i', 'IY': 'i', 'OW': 'o', 'OY': 'oi', 'UH': 'u', 'UW': 'u'}
ACC = {'a': 'à', 'e': 'è', 'i': 'ì', 'o': 'ò', 'u': 'ù'}
# loanwords of the news, and words the rules get wrong
EXTRA = "show live report times match fake one trump social online manager marketing football twitter tweet".split()
FIX = {'new': 'niù', 'news': 'niùs', 'york': 'iòrk'}


def respell(ph):
    base = [re.sub(r'\d', '', p) for p in ph]
    st = [p[-1] if p[-1].isdigit() else None for p in ph]
    nvow = sum(1 for b in base if b in V)
    n = len(ph)
    tok = [None] * n
    for i, b in enumerate(base):  # vowels first: the consonants look at the letter written after them
        if b not in V:
            continue
        nxt = base[i + 1] if i + 1 < n else None
        v = V[b]
        if b == 'AH' and st[i] == '0':  # schwa: "gùgol", "compiùter", "bàiden", "amèrica"
            v = 'a' if nxt is None else 'o' if (nxt == 'L' and i + 2 == n) or nxt == 'M' else 'e'
        if b == 'ER' and st[i] != '1' and i > 0 and base[i - 1] in ('CH', 'SH'):  # "nèiciur", "prèsciur"
            v = 'ur'
        if st[i] == '1' and nvow > 1:  # the accent marks the stress
            v = ACC[v[0]] + v[1:]
        tok[i] = v
    for i in range(n - 1, -1, -1):
        b = base[i]
        if b in V:
            continue
        nx = tok[i + 1] if i + 1 < n else ''
        soft = nx[:1] in ('e', 'i', 'è', 'ì')
        vow = nx != '' and nx[:1] in 'aeiouàèìòù'
        if b == 'K': t = 'ch' if soft else 'c' if vow else 'k'
        elif b == 'G': t = 'gh' if soft else 'g'
        elif b in ('CH', 'JH'):
            c = 'c' if b == 'CH' else 'g'
            t = (c if soft else c + 'i') if vow else 'ch'  # final "ch": espeak says tʃ
        elif b in ('SH', 'ZH'): t = ('sc' if soft else 'sci') if vow else 'sh'
        elif b == 'TH': t = 't'
        elif b == 'DH': t = 'd'
        elif b == 'HH': t = ''
        elif b == 'W': t = 'u'
        elif b == 'Y': t = 'i'
        elif b == 'Z': t = 's'
        else: t = b.lower()
        tok[i] = t
    return ''.join(tok)


def main():
    cmu = {}
    for line in open('cmudict.dict'):
        p = line.split('#')[0].split()
        if p and '(' not in p[0]:
            cmu[p[0]] = p[1:]
    rank = lambda f: {l.split()[0]: i for i, l in enumerate(open(f))}
    en, it = rank('en_50k.txt'), rank('it_50k.txt')
    cand = [w for w, r in en.items() if r < 30000 and w in cmu and re.fullmatch(r'[a-z]{3,}', w)]
    words = {w for w in cand if it.get(w, 10 ** 9) > 30000}

    import espeakng_loader
    from phonemizer.backend.espeak.wrapper import EspeakWrapper
    EspeakWrapper.set_library(espeakng_loader.get_library_path())
    EspeakWrapper.set_data_path(espeakng_loader.get_data_path())
    from phonemizer.backend import EspeakBackend
    rest = [w for w in cand if w not in words]
    out = EspeakBackend('it', language_switch='keep-flags').phonemize([w.capitalize() for w in rest], strip=True)
    words |= {w for w, o in zip(rest, out) if '(en)' in o}
    words |= set(EXTRA)
    for w in sorted(words):
        print(f"{w}\t{FIX.get(w) or respell(cmu[w])}")


if __name__ == '__main__':
    main()
