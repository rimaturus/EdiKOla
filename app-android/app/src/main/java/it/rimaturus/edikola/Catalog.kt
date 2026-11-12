// The catalog of newspapers, from konewspaper.koplugin/giornali.lua. Only free sources: paywalled articles give
// teasers and get skipped.
package it.rimaturus.edikola

/** lang: "en" for English papers (their titles and briefs are translated to Italian for the Sommario) */
data class Paper(val id: String, val section: String, val name: String, val feed: String, val lang: String?, val default: Boolean, val max: Int = 10)

data class Section(val id: String, val name: String)

val SECTIONS = listOf(
    Section("italia", "Italia"),
    Section("mondo", "Mondo"),
    Section("buone", "Buone notizie"),
    Section("scienza", "Scienza"),
)

val PAPERS = listOf(
    Paper("rainews", "italia", "RaiNews", "https://www.rainews.it/rss/tutti", null, true),
    Paper("fatto", "italia", "il Fatto Quotidiano", "https://www.ilfattoquotidiano.it/feed/", null, true),
    Paper("tgcom", "italia", "Tgcom24", "https://www.tgcom24.mediaset.it/rss/homepage.xml", null, true),
    Paper("skytg24", "italia", "Sky TG24", "https://tg24.sky.it/rss/tg24.xml", null, false),
    Paper("open", "italia", "Open", "https://www.open.online/feed/", null, false),
    Paper("agi", "italia", "AGI", "https://www.agi.it/rss", null, false),
    Paper("adnkronos", "italia", "Adnkronos", "https://www.adnkronos.com/RSS_Ultimora.xml", null, false),
    Paper("internaz", "italia", "Internazionale", "https://www.internazionale.it/sitemaps/rss.xml", null, false),
    Paper("corriere", "italia", "Corriere della Sera", "https://xml2.corriereobjects.it/rss/homepage.xml", null, true),
    Paper("lastampa", "italia", "La Stampa", "https://www.lastampa.it/rss/copertina.xml", null, false),
    Paper("sole24ore", "italia", "Il Sole 24 Ore", "https://www.ilsole24ore.com/rss/italia.xml", null, false),
    Paper("messaggero", "italia", "Il Messaggero", "https://www.ilmessaggero.it/rss/home.xml", null, false),
    Paper("today", "italia", "Today", "https://www.today.it/rss", null, false),
    Paper("euronewsit", "italia", "Euronews Italiano", "https://it.euronews.com/rss", null, false),
    Paper("guardian", "mondo", "The Guardian", "https://www.theguardian.com/world/rss", "en", true),
    Paper("bbc", "mondo", "BBC News", "https://feeds.bbci.co.uk/news/world/rss.xml", "en", true),
    Paper("npr", "mondo", "NPR", "https://feeds.npr.org/1001/rss.xml", "en", true),
    Paper("aljazeera", "mondo", "Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "en", false),
    Paper("dw", "mondo", "Deutsche Welle", "https://rss.dw.com/rdf/rss-en-all", "en", true),
    Paper("euronews", "mondo", "Euronews", "https://www.euronews.com/rss", "en", false),
    Paper("cbs", "mondo", "CBS News", "https://www.cbsnews.com/latest/rss/world", "en", false),
    Paper("abc", "mondo", "ABC News", "https://abcnews.go.com/abcnews/internationalheadlines", "en", false),
    Paper("conversation", "mondo", "The Conversation", "https://theconversation.com/global/articles.atom", "en", false),
    Paper("politico", "mondo", "Politico Europe", "https://www.politico.eu/feed/", "en", false),
    Paper("propublica", "mondo", "ProPublica", "https://www.propublica.org/feeds/propublica/main", "en", false),
    Paper("cambia", "buone", "Italia che Cambia", "https://www.italiachecambia.org/feed/", null, true),
    Paper("positive", "buone", "Positive News", "https://www.positive.news/feed/", "en", true),
    Paper("goodnews", "buone", "Good News Network", "https://www.goodnewsnetwork.org/feed/", "en", true),
    Paper("cheerful", "buone", "Reasons to be Cheerful", "https://reasonstobecheerful.world/feed/", "en", true),
    Paper("optimist", "buone", "The Optimist Daily", "https://www.optimistdaily.com/feed/", "en", true),
    Paper("upside", "buone", "The Guardian – The Upside", "https://www.theguardian.com/world/series/the-upside/rss", "en", true),
    Paper("greenme", "buone", "GreenMe", "https://www.greenme.it/feed/", null, true),
    Paper("focus", "scienza", "Focus", "https://www.focus.it/rss", null, true),
    Paper("ansasci", "scienza", "ANSA Scienza", "https://www.ansa.it/canale_scienza_tecnica/notizie/scienzaetecnica_rss.xml", null, true),
    Paper("guardsci", "scienza", "The Guardian Science", "https://www.theguardian.com/science/rss", "en", true),
    Paper("ars", "scienza", "Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "en", true),
    Paper("wiredit", "scienza", "Wired Italia", "https://www.wired.it/feed/rss", null, true),
    Paper("inaf", "scienza", "Media Inaf (spazio)", "https://www.media.inaf.it/feed/", null, true),
    Paper("galileo", "scienza", "Galileo", "https://www.galileonet.it/feed/", null, true),
    Paper("puntoinf", "scienza", "Punto Informatico", "https://www.punto-informatico.it/feed/", null, true),
    Paper("scidaily", "scienza", "ScienceDaily", "https://www.sciencedaily.com/rss/top.xml", "en", true),
    Paper("quanta", "scienza", "Quanta Magazine", "https://www.quantamagazine.org/feed/", "en", true),
    Paper("nasa", "scienza", "NASA", "https://www.nasa.gov/news-release/feed/", "en", true),
    Paper("bbcsci", "scienza", "BBC Science", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "en", true),
    Paper("convsci", "scienza", "The Conversation Science", "https://theconversation.com/global/topics/science-1214/articles.atom", "en", true),
)
