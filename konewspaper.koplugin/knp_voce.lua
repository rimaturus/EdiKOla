--[[--
The voice: reads text aloud, offline, with sherpa-onnx (a C library, called through LuaJIT's FFI) and two Piper
voices, Paola for Italian and Alba (British) for English. Only in the phone APK (android/build.sh puts the
library in the APK and the voices in voci/); without them ready() is false and nothing shows.

    V.lang(text)                        "it" or "en", from the most common short words
    V.read(epub)                        { { title =, text = { paragraphs } } } for each article of an edition
    V.chunks(articles, intro)           what to say, in order: { { text =, lang =, article =, pause = } }
    V.synth(chunk, wav)                 writes the chunk's audio (16-bit WAV), true when done

Pure Lua apart from synth() and read(), so the tests run it under any LuaJIT.
]]
local V = {}

V.dir = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/voci" -- the tests point it elsewhere
V.VOICES = { it = "it_IT-paola-medium.onnx", en = "en_GB-alba-medium.onnx" }

local function exists(p) local f = io.open(p, "rb"); if f then f:close() end; return f ~= nil end

local function libDir()
    local ok, android = pcall(require, "android")
    return ok and android and android.nativeLibraryDir or V.dir .. "/lib"
end

function V.ready()
    if V._ready == nil then
        V._ready = exists(libDir() .. "/libsherpa-onnx-c-api.so") and exists(V.dir .. "/it/" .. V.VOICES.it)
            and exists(V.dir .. "/en/" .. V.VOICES.en)
    end
    return V._ready
end

-- Words that are frequent in one language and rare in the other
local IT = {}
for w in ("il lo la gli le di del della dei delle che è e per un una non con nel nella alla al sono anche più ma come si ha da ci questo questa dopo tra"):gmatch("%S+") do IT[w] = true end
local EN = {}
for w in ("the and of to is that for on with was it are as by at from this have be has an not but he she they said were their which will been who would"):gmatch("%S+") do EN[w] = true end

function V.lang(text)
    local it, en = 0, 0
    for w in text:lower():gmatch("[%a\128-\255]+") do
        if IT[w] then it = it + 1 elseif EN[w] then en = en + 1 end
    end
    return en > it and "en" or "it"
end

local function plain(html)
    local X = require("knp_extract")
    return (X.decode(html:gsub("<[^>]*>", "")):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

--- The articles of an edition built by knp_build: chapters a1.xhtml, a2.xhtml… with <h1>, <h3> and <p>
function V.parse(xhtml)
    local title, text = nil, {}
    local body = xhtml:match("<body>(.*)</body>") or ""
    for tag, attrs, inner in body:gmatch("<(%w+)([^>]*)>(.-)</%1>") do
        local t = plain(inner)
        if tag == "h1" then title = t
        elseif (tag == "p" or tag == "h3") and t ~= "" and not attrs:find("back", 1, true) then table.insert(text, t) end
    end
    return title and { title = title, text = text }
end

function V.read(epub)
    local arc = require("ffi/archiver").Reader:new()
    if not arc:open(epub) then return {} end
    local found = {}
    for e in arc:iterate() do
        local n = e.mode == "file" and tonumber(e.path:match("^OEBPS/a(%d+)%.xhtml$"))
        if n then found[n] = arc:extractToMemory(e.path) end
    end
    arc:close()
    local out = {}
    for n = 1, #found do
        local a = found[n] and V.parse(found[n])
        if a then table.insert(out, a) end
    end
    return out
end

local CHUNK = 700 -- characters: a few sentences, so a skip is quick
local FIRST = 250 -- an article's first piece is shorter, so its voice is ready soon after the title

--- What to say: the intro (the paper's name and date), then each article's title, then its text in pieces.
-- An article's language decides its voice; pause = seconds of silence after the piece.
function V.chunks(articles, intro)
    local out = {}
    if intro then table.insert(out, { text = intro, lang = "it", article = 1, pause = 1 }) end
    for i, a in ipairs(articles) do
        local lang = V.lang(a.title .. " " .. table.concat(a.text, " "))
        table.insert(out, { text = a.title, lang = lang, article = i, pause = 0.8 })
        local piece = {}
        local function flush()
            if #piece > 0 then
                table.insert(out, { text = table.concat(piece, "\n"), lang = lang, article = i, pause = 0.5 })
                piece = {}
            end
        end
        local len, first = 0, true
        for _, para in ipairs(a.text) do
            -- a long paragraph goes in sentences, so no piece gets much longer than CHUNK
            local units = { para }
            if #para > CHUNK then
                units = {}
                for sentence in para:gmatch("[^%.!?]+[%.!?]*%s*") do table.insert(units, sentence) end
            end
            for _, p in ipairs(units) do
                if len > 0 and len + #p > (first and FIRST or CHUNK) then flush(); len, first = 0, false end
                table.insert(piece, p)
                len = len + #p
            end
        end
        flush()
        out[#out].pause = 1.5 -- between articles
    end
    return out
end

local C, engines
local function load()
    if C then return C end
    local ffi = require("ffi")
    ffi.cdef[[
typedef struct { const char *model; const char *lexicon; const char *tokens; const char *data_dir;
  float noise_scale; float noise_scale_w; float length_scale; const char *dict_dir; } KnpVits;
typedef struct { const char *a, *b, *c, *d, *e; float f, g; const char *h; } KnpMatcha;
typedef struct { const char *a, *b, *c, *d; float e; const char *f, *g, *h; } KnpKokoro;
typedef struct { const char *a, *b, *c, *d; float e; } KnpKitten;
typedef struct { const char *a, *b, *c, *d, *e, *f; float g, h, i, j; } KnpZipvoice;
typedef struct { const char *a, *b, *c, *d, *e, *f, *g; int32_t h; } KnpPocket;
typedef struct { const char *a, *b, *c, *d, *e, *f, *g; } KnpSupertonic;
typedef struct { KnpVits vits; int32_t num_threads; int32_t debug; const char *provider; KnpMatcha matcha;
  KnpKokoro kokoro; KnpKitten kitten; KnpZipvoice zipvoice; KnpPocket pocket; KnpSupertonic supertonic; } KnpTtsModel;
typedef struct { KnpTtsModel model; const char *rule_fsts; int32_t max_num_sentences; const char *rule_fars;
  float silence_scale; } KnpTtsConfig;
typedef struct { const float *samples; int32_t n; int32_t sample_rate; } KnpAudio;
const void *SherpaOnnxCreateOfflineTts(const KnpTtsConfig *config);
const KnpAudio *SherpaOnnxOfflineTtsGenerate(const void *tts, const char *text, int32_t sid, float speed);
void SherpaOnnxDestroyOfflineTtsGeneratedAudio(const KnpAudio *p);
int32_t SherpaOnnxWriteWave(const float *samples, int32_t n, int32_t sample_rate, const char *filename);
]]
    local lib = libDir()
    ffi.load(lib .. "/libonnxruntime.so", true) -- the C API's own dependency, found by name once loaded
    C = ffi.load(lib .. "/libsherpa-onnx-c-api.so")
    engines = {}
    return C
end

local keep = {} -- strings the configs point to
local function engine(lang)
    load()
    if engines[lang] == nil then
        local ffi = require("ffi")
        local function s(v) table.insert(keep, v); return v end
        local cfg = ffi.new("KnpTtsConfig")
        cfg.model.vits.model = s(V.dir .. "/" .. lang .. "/" .. V.VOICES[lang])
        cfg.model.vits.tokens = s(V.dir .. "/" .. lang .. "/tokens.txt")
        cfg.model.vits.data_dir = s(V.dir .. "/espeak-ng-data")
        cfg.model.vits.noise_scale, cfg.model.vits.noise_scale_w, cfg.model.vits.length_scale = 0.667, 0.8, 1.0
        cfg.model.num_threads = 4
        cfg.model.provider = "cpu"
        cfg.max_num_sentences = 1
        cfg.silence_scale = 0.2
        local tts = C.SherpaOnnxCreateOfflineTts(cfg)
        engines[lang] = tts ~= nil and tts or false
    end
    return engines[lang] or nil
end

function V.synth(chunk, wav, speed)
    local tts = engine(chunk.lang)
    if not tts then return false end
    local ffi = require("ffi")
    local a = C.SherpaOnnxOfflineTtsGenerate(tts, chunk.text, 0, speed or 1.0)
    if a == nil then return false end
    local pad = math.floor((chunk.pause or 0) * a.sample_rate)
    local buf = ffi.new("float[?]", a.n + pad) -- zero-filled: the pause after the piece
    ffi.copy(buf, a.samples, a.n * ffi.sizeof("float"))
    local ok = C.SherpaOnnxWriteWave(buf, a.n + pad, a.sample_rate, wav) == 1
    C.SherpaOnnxDestroyOfflineTtsGeneratedAudio(a)
    return ok
end

return V
