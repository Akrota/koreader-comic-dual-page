-- Comic Dual Page: Vorausladen im Doppelseiten-Modus.
-- KOReader laedt nach dem Zeichnen nur die Seite "aktuelle + 1" vor. Im Doppelseiten-Modus ist das
-- die rechte Haelfte der schon gezeigten Ansicht, die naechste Ansicht wurde also nie vorbereitet
-- und musste beim Umblaettern erst gerechnet werden (langsam, beim Zurueckblaettern dagegen schnell,
-- weil die Seiten noch im Speicher lagen). Hier werden stattdessen die Seiten der naechsten
-- Ansicht vorgeladen, mit genau der Vergroesserung, mit der sie danach gezeichnet werden.

local ReaderHinting = require("apps/reader/modules/readerhinting")
local logger = require("logger")

local crpOrigHintPage = ReaderHinting.onHintPage
function ReaderHinting:onHintPage()
    local paging = self.ui and self.ui.paging
    if not (self.view.hinting and paging and paging.isDualPageEnabled and paging:isDualPageEnabled()) then
        return crpOrigHintPage(self)
    end
    local ok, err = pcall(function()
        local base = paging:getPairBaseByRelativeMovement(1)
        local current = paging.current_pair_base
        if not base or (current and base == current) then return end -- schon die letzte Ansicht
        local pair = paging:getDualPagePairFromBasePage(base)
        local zooms = paging:calculateZoomFactorForPagePair(pair)
        local state = self.view.state
        for i, page in ipairs(pair) do
            if zooms[i] then
                self.document:hintPage(page, zooms[i], state.rotation, state.gamma, state.saturation)
            end
        end
    end)
    if not ok then logger.warn("ComicDualPage: Vorausladen fehlgeschlagen:", err) end
    return true
end
