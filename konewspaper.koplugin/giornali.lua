-- Catalog of newspapers. Choose which ones appear on the newsstand from the "Giornali" button.
--   id       folder name (letters, digits)  name     title on the newsstand
--   section  "italia", "mondo", "buone"    feed     RSS/Atom address
--            (good news) or "scienza"
--   max      articles per edition          default  shown until a selection is made
--   lang     "en" for English papers: their titles and briefs are translated to Italian for the Sommario
-- Only free sources: paywalled articles give teasers and get skipped.
return {
    { id = "rainews",   section = "italia", name = "RaiNews",             feed = "https://www.rainews.it/rss/tutti", default = true },
    { id = "fatto",     section = "italia", name = "il Fatto Quotidiano", feed = "https://www.ilfattoquotidiano.it/feed/", default = true },
    { id = "tgcom",     section = "italia", name = "Tgcom24",             feed = "https://www.tgcom24.mediaset.it/rss/homepage.xml", default = true },
    { id = "skytg24",   section = "italia", name = "Sky TG24",            feed = "https://tg24.sky.it/rss/tg24.xml" },
    { id = "open",      section = "italia", name = "Open",                feed = "https://www.open.online/feed/" },
    { id = "agi",       section = "italia", name = "AGI",                 feed = "https://www.agi.it/rss" },
    { id = "adnkronos", section = "italia", name = "Adnkronos",           feed = "https://www.adnkronos.com/RSS_Ultimora.xml" },
    { id = "internaz",  section = "italia", name = "Internazionale",      feed = "https://www.internazionale.it/sitemaps/rss.xml" },
    { id = "corriere",  section = "italia", name = "Corriere della Sera", feed = "https://xml2.corriereobjects.it/rss/homepage.xml", default = true },
    { id = "lastampa",  section = "italia", name = "La Stampa",           feed = "https://www.lastampa.it/rss/copertina.xml" },
    { id = "sole24ore", section = "italia", name = "Il Sole 24 Ore",      feed = "https://www.ilsole24ore.com/rss/italia.xml" },
    { id = "messaggero",section = "italia", name = "Il Messaggero",       feed = "https://www.ilmessaggero.it/rss/home.xml" },
    { id = "today",     section = "italia", name = "Today",               feed = "https://www.today.it/rss" },
    { id = "euronewsit",section = "italia", name = "Euronews Italiano",   feed = "https://it.euronews.com/rss" },

    { id = "guardian",  section = "mondo", lang = "en", name = "The Guardian",         feed = "https://www.theguardian.com/world/rss", default = true },
    { id = "bbc",       section = "mondo", lang = "en", name = "BBC News",             feed = "https://feeds.bbci.co.uk/news/world/rss.xml", default = true },
    { id = "npr",       section = "mondo", lang = "en", name = "NPR",                  feed = "https://feeds.npr.org/1001/rss.xml", default = true },
    { id = "aljazeera", section = "mondo", lang = "en", name = "Al Jazeera",           feed = "https://www.aljazeera.com/xml/rss/all.xml" },
    { id = "dw",        section = "mondo", lang = "en", name = "Deutsche Welle",       feed = "https://rss.dw.com/rdf/rss-en-all", default = true },
    { id = "euronews",  section = "mondo", lang = "en", name = "Euronews",             feed = "https://www.euronews.com/rss" },
    { id = "cbs",       section = "mondo", lang = "en", name = "CBS News",             feed = "https://www.cbsnews.com/latest/rss/world" },
    { id = "abc",       section = "mondo", lang = "en", name = "ABC News",             feed = "https://abcnews.go.com/abcnews/internationalheadlines" },
    { id = "conversation",section = "mondo", lang = "en", name = "The Conversation",   feed = "https://theconversation.com/global/articles.atom" },
    { id = "politico",  section = "mondo", lang = "en", name = "Politico Europe",      feed = "https://www.politico.eu/feed/" },
    { id = "propublica",section = "mondo", lang = "en", name = "ProPublica",           feed = "https://www.propublica.org/feeds/propublica/main" },

    -- Good news (live-tested 2026-11-02)
    { id = "cambia",    section = "buone", name = "Italia che Cambia",     feed = "https://www.italiachecambia.org/feed/", default = true },
    { id = "positive",  section = "buone", lang = "en", name = "Positive News",         feed = "https://www.positive.news/feed/", default = true },
    { id = "goodnews",  section = "buone", lang = "en", name = "Good News Network",     feed = "https://www.goodnewsnetwork.org/feed/", default = true },
    { id = "cheerful",  section = "buone", lang = "en", name = "Reasons to be Cheerful", feed = "https://reasonstobecheerful.world/feed/", default = true },
    { id = "optimist",  section = "buone", lang = "en", name = "The Optimist Daily",    feed = "https://www.optimistdaily.com/feed/", default = true },
    { id = "upside",    section = "buone", lang = "en", name = "The Guardian – The Upside", feed = "https://www.theguardian.com/world/series/the-upside/rss", default = true },
    { id = "greenme",   section = "buone", name = "GreenMe",               feed = "https://www.greenme.it/feed/", default = true },

    -- Science and technology (live-tested 2026-11-02)
    { id = "focus",     section = "scienza", name = "Focus",               feed = "https://www.focus.it/rss", default = true },
    { id = "ansasci",   section = "scienza", name = "ANSA Scienza",        feed = "https://www.ansa.it/canale_scienza_tecnica/notizie/scienzaetecnica_rss.xml", default = true },
    { id = "guardsci",  section = "scienza", lang = "en", name = "The Guardian Science", feed = "https://www.theguardian.com/science/rss", default = true },
    { id = "ars",       section = "scienza", lang = "en", name = "Ars Technica",        feed = "https://feeds.arstechnica.com/arstechnica/index", default = true },
    { id = "wiredit",   section = "scienza", name = "Wired Italia",        feed = "https://www.wired.it/feed/rss", default = true },
    { id = "inaf",      section = "scienza", name = "Media Inaf (spazio)", feed = "https://www.media.inaf.it/feed/", default = true },
    { id = "galileo",   section = "scienza", name = "Galileo",             feed = "https://www.galileonet.it/feed/", default = true },
    { id = "puntoinf",  section = "scienza", name = "Punto Informatico",   feed = "https://www.punto-informatico.it/feed/", default = true },
    { id = "scidaily",  section = "scienza", lang = "en", name = "ScienceDaily",        feed = "https://www.sciencedaily.com/rss/top.xml", default = true },
    { id = "quanta",    section = "scienza", lang = "en", name = "Quanta Magazine",     feed = "https://www.quantamagazine.org/feed/", default = true },
    { id = "nasa",      section = "scienza", lang = "en", name = "NASA",                feed = "https://www.nasa.gov/news-release/feed/", default = true },
    { id = "bbcsci",    section = "scienza", lang = "en", name = "BBC Science",         feed = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", default = true },
    { id = "convsci",   section = "scienza", lang = "en", name = "The Conversation Science", feed = "https://theconversation.com/global/topics/science-1214/articles.atom", default = true },
}
