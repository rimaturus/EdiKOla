// The catalog of newspapers, from konewspaper.koplugin/giornali.lua, plus engineering. Only free sources:
// paywalled articles give teasers and get skipped.
// Preselected (default = true): a balanced, daily-updated mix: Italian and world politics, geopolitics and economy,
// then science and engineering, with one source of good news. CATALOG changes when the preselection changes:
// shelves chosen with an older catalog start over from it.
package it.rimaturus.edikola

/** lang: "en" for English papers (their titles and briefs are translated to Italian for the Sommario) */
data class Paper(val id: String, val section: String, val name: String, val feed: String, val lang: String?, val default: Boolean, val max: Int = 10)

data class Section(val id: String, val name: String)

const val CATALOG = 2

val SECTIONS = listOf(
    Section("italia", "Italia"),
    Section("mondo", "Mondo"),
    Section("buone", "Buone notizie"),
    Section("scienza", "Scienza"),
    Section("ingegneria", "Ingegneria"),
)

val PAPERS = listOf(
    Paper("rainews", "italia", "RaiNews", "https://www.rainews.it/rss/tutti", null, true),
    Paper("ilpost", "italia", "Il Post", "https://www.ilpost.it/feed/", null, true),
    Paper("formiche", "italia", "Formiche (geopolitica)", "https://formiche.net/feed/", null, true),
    Paper("startmag", "italia", "Startmag (economia, energia)", "https://www.startmag.it/feed/", null, true),
    Paper("fatto", "italia", "il Fatto Quotidiano", "https://www.ilfattoquotidiano.it/feed/", null, false),
    Paper("tgcom", "italia", "Tgcom24", "https://www.tgcom24.mediaset.it/rss/homepage.xml", null, false),
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
    Paper("npr", "mondo", "NPR", "https://feeds.npr.org/1001/rss.xml", "en", false),
    Paper("aljazeera", "mondo", "Al Jazeera", "https://www.aljazeera.com/xml/rss/all.xml", "en", false),
    Paper("dw", "mondo", "Deutsche Welle", "https://rss.dw.com/rdf/rss-en-all", "en", true),
    Paper("euronews", "mondo", "Euronews", "https://www.euronews.com/rss", "en", false),
    Paper("cbs", "mondo", "CBS News", "https://www.cbsnews.com/latest/rss/world", "en", false),
    Paper("abc", "mondo", "ABC News", "https://abcnews.go.com/abcnews/internationalheadlines", "en", false),
    Paper("conversation", "mondo", "The Conversation", "https://theconversation.com/global/articles.atom", "en", false),
    Paper("politico", "mondo", "Politico Europe", "https://www.politico.eu/feed/", "en", true),
    Paper("wotr", "mondo", "War on the Rocks (geopolitica)", "https://warontherocks.com/feed/", "en", true, max = 5),
    Paper("propublica", "mondo", "ProPublica", "https://www.propublica.org/feeds/propublica/main", "en", false),
    Paper("cambia", "buone", "Italia che Cambia", "https://www.italiachecambia.org/feed/", null, false),
    Paper("positive", "buone", "Positive News", "https://www.positive.news/feed/", "en", false),
    Paper("goodnews", "buone", "Good News Network", "https://www.goodnewsnetwork.org/feed/", "en", false),
    Paper("cheerful", "buone", "Reasons to be Cheerful", "https://reasonstobecheerful.world/feed/", "en", true),
    Paper("optimist", "buone", "The Optimist Daily", "https://www.optimistdaily.com/feed/", "en", false),
    Paper("upside", "buone", "The Guardian – The Upside", "https://www.theguardian.com/world/series/the-upside/rss", "en", false),
    Paper("greenme", "buone", "GreenMe", "https://www.greenme.it/feed/", null, false),
    Paper("focus", "scienza", "Focus", "https://www.focus.it/rss", null, false),
    Paper("ansasci", "scienza", "ANSA Scienza", "https://www.ansa.it/canale_scienza_tecnica/notizie/scienzaetecnica_rss.xml", null, true),
    Paper("guardsci", "scienza", "The Guardian Science", "https://www.theguardian.com/science/rss", "en", true),
    Paper("ars", "scienza", "Ars Technica", "https://feeds.arstechnica.com/arstechnica/index", "en", true),
    Paper("wiredit", "scienza", "Wired Italia", "https://www.wired.it/feed/rss", null, false),
    Paper("inaf", "scienza", "Media Inaf (spazio)", "https://www.media.inaf.it/feed/", null, true),
    Paper("galileo", "scienza", "Galileo", "https://www.galileonet.it/feed/", null, false),
    Paper("puntoinf", "scienza", "Punto Informatico", "https://www.punto-informatico.it/feed/", null, false),
    Paper("scidaily", "scienza", "ScienceDaily", "https://www.sciencedaily.com/rss/top.xml", "en", false),
    Paper("quanta", "scienza", "Quanta Magazine", "https://www.quantamagazine.org/feed/", "en", true),
    Paper("nasa", "scienza", "NASA", "https://www.nasa.gov/news-release/feed/", "en", false),
    Paper("bbcsci", "scienza", "BBC Science", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml", "en", false),
    Paper("convsci", "scienza", "The Conversation Science", "https://theconversation.com/global/topics/science-1214/articles.atom", "en", false),
    Paper("spectrum", "ingegneria", "IEEE Spectrum", "https://spectrum.ieee.org/feeds/feed.rss", "en", true),
    Paper("hackaday", "ingegneria", "Hackaday", "https://hackaday.com/blog/feed/", "en", true),
    Paper("eetimes", "ingegneria", "EE Times", "https://www.eetimes.com/feed/", "en", true),
    Paper("newatlas", "ingegneria", "New Atlas", "https://newatlas.com/index.rss", "en", true),
    Paper("elettronica", "ingegneria", "Elettronica News", "https://www.elettronicanews.it/feed/", null, true),
    Paper("intereng", "ingegneria", "Interesting Engineering", "https://interestingengineering.com/feed", "en", false),
    Paper("electrek", "ingegneria", "Electrek (auto elettriche)", "https://electrek.co/feed/", "en", false),
    Paper("tomshw", "ingegneria", "Tom's Hardware Italia", "https://www.tomshw.it/feed", null, false),
)
