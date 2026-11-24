-- Beschreibung auf Deutsch oder Englisch, je nach KOReader-Sprache
local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
local de = ok and type(lang) == "string" and lang:sub(1, 2):lower() == "de"
return {
    fullname = "Comic Dual Page",
    description = de
        and "Doppelseiten-Modus für Comics (zwei Seiten nebeneinander im Querformat) mit Doppelseiten-Erkennung: Seiten im Querformat werden allein angezeigt. Basiert auf ComicReader 0.0.7 (KORComic, AGPL-3.0). Nicht zusammen mit dem Original installieren."
        or "Dual page mode for comics (two pages side by side in landscape) with spread detection: landscape pages are shown on their own. Based on ComicReader 0.0.7 (KORComic, AGPL-3.0). Do not install together with the original.",
    version = "0.0.7-cdp1",
}
