-- Catalog of newspapers. Choose which ones appear on the newsstand from the "Giornali" button.
--   id       folder name (letters only)    name     title on the newsstand
--   section  "italia" or "mondo"           feed     RSS/Atom address
--   max      articles per edition          default  shown until a selection is made
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
    { id = "wiredit",   section = "italia", name = "Wired Italia",        feed = "https://www.wired.it/feed/rss" },

    { id = "guardian",  section = "mondo", name = "The Guardian",         feed = "https://www.theguardian.com/world/rss", default = true },
    { id = "bbc",       section = "mondo", name = "BBC News",             feed = "https://feeds.bbci.co.uk/news/world/rss.xml", default = true },
    { id = "npr",       section = "mondo", name = "NPR",                  feed = "https://feeds.npr.org/1001/rss.xml", default = true },
    { id = "aljazeera", section = "mondo", name = "Al Jazeera",           feed = "https://www.aljazeera.com/xml/rss/all.xml" },
    { id = "dw",        section = "mondo", name = "Deutsche Welle",       feed = "https://rss.dw.com/rdf/rss-en-all", default = true },
    { id = "euronews",  section = "mondo", name = "Euronews",             feed = "https://www.euronews.com/rss" },
    { id = "cbs",       section = "mondo", name = "CBS News",             feed = "https://www.cbsnews.com/latest/rss/world" },
    { id = "abc",       section = "mondo", name = "ABC News",             feed = "https://abcnews.go.com/abcnews/internationalheadlines" },
    { id = "conversation",section = "mondo", name = "The Conversation",   feed = "https://theconversation.com/global/articles.atom" },
    { id = "politico",  section = "mondo", name = "Politico Europe",      feed = "https://www.politico.eu/feed/" },
    { id = "propublica",section = "mondo", name = "ProPublica",           feed = "https://www.propublica.org/feeds/propublica/main" },
}
