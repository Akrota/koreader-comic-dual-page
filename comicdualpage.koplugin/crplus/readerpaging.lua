local ReaderPaging = require("apps/reader/modules/readerpaging")

local BD = require("ui/bidi")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local Math = require("optmath")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local logger = require("logger")
local Screen = Device.screen
local ButtonDialog = require("ui/widget/buttondialog")
local Notification = require("ui/widget/notification")

-- In dual page mode, this holds the base pair that we are at.
-- This is needed to do relative page changes.
-- It should also be the same value as current_page
ReaderPaging.current_pair_base = 0

ReaderPaging.default_reader_settings = ReaderPaging.default_reader_settings or {}
ReaderPaging.default_document_settings = ReaderPaging.default_document_settings or {}

ReaderPaging.default_reader_settings.first_time_dual_page_mode = true
ReaderPaging.default_reader_settings.auto_enable_dual_page_mode = false

ReaderPaging.default_document_settings.dual_page_mode = false
ReaderPaging.default_document_settings.dual_page_mode_first_page_is_cover = false
ReaderPaging.default_document_settings.dual_page_mode_rtl = false

local ReaderPagingInitOrig = ReaderPaging.init

local function patch_reader_paging(pagingInstance)
    if not pagingInstance or pagingInstance._comic_patched then
        return
    end

    pagingInstance.reader_settings = G_reader_settings:readSetting("paging", ReaderPaging.default_reader_settings)
    pagingInstance.document_settings =
        pagingInstance.ui.doc_settings:readSetting("paging", ReaderPaging.default_document_settings)

    local function do_register()
        -- For existing instances, registerToMainMenu() doesn't work because the menu
        -- has already been initialized. We need to manually add menu items instead.
        if pagingInstance.ui and pagingInstance.ui.menu then
            if type(pagingInstance.addToMainMenu) == "function" then
                local menu_items = {}
                pagingInstance:addToMainMenu(menu_items)

                if menu_items.dual_page_options then
                    pagingInstance.ui.menu.menu_items.dual_page_options = menu_items.dual_page_options
                    logger.dbg("ComicReaderPaging: Added dual_page_options to existing menu")
                end
            end
        end

        if type(pagingInstance.onDispatcherRegisterActions) == "function" then
            pagingInstance:onDispatcherRegisterActions()
        end
    end

    UIManager:nextTick(do_register)

    pagingInstance._comic_patched = true
    logger.dbg("ComicReaderPaging plugin patch applied")
end

function ReaderPaging:init()
    local res = ReaderPagingInitOrig(self)

    patch_reader_paging(self)

    return res
end

function ReaderPaging:onReadSettings(config)
    self.document_settings = config:readSetting("paging", self.default_document_settings)
    self.page_positions = config:readSetting("page_positions") or {}

    local page = config:readSetting("last_page") or 1

    self:_gotoPage(page)
    self.flipping_zoom_mode = config:readSetting("flipping_zoom_mode") or "page"
    self.flipping_scroll_mode = config:isTrue("flipping_scroll_mode")

    if not self:supportsDualPage() and self.document_settings.dual_page_mode then
        logger.dbg("ComicReaderPaging:onReadSettings disabling dual page mode")

        self.ui:handleEvent(Event:new("SetPageMode", 1))
        self:onSetPageMode(1)
    end

    if self.document_settings.dual_page_mode then
        logger.dbg("ComicReaderPaging:onReadSettings: sending dual mode enabled event", true, page)

        self.ui:handleEvent(Event:new("DualPageModeEnabled", true, self:getDualPageBaseFromPage(page)))
    end
end

-- This cannot be used with ReaderPaging as the actions would only be
-- registered if a Paging document is opened.
-- Instead, "hardcode" the actions in ./frontend/dispatcher.lua.
--
-- If someone is not reading a Paging document and tries to edit profiles or anything
-- that triggers the actions menu, a nil panic will happen as the actions that would be
-- in this function never got registered.
-- luacheck: ignore self
function ReaderPaging:onDispatcherRegisterActions(self) end

function ReaderPaging:addToMainMenu(menu_items)
    if self.ui.paging then
        menu_items.dual_page_options = {
            text = _("Dual Page Mode"),
            sub_item_table = self:genDualPagingMenu(),
            -- Comic Dual Page: Menue immer oeffnen, auch im Hochformat
            help_text = _([[Settings for when you're in dual page mode.
This is enabled when the device is in landscape mode!
]]),
        }
    end
end

local originalReaderPagingonPageUpdate = ReaderPaging.onPageUpdate

function ReaderPaging:onPageUpdate(new_page_no, orig_mode)
    logger.dbg(
        "ReaderPaging:onPageUpdatef: curr_page",
        self.current_page,
        "curr_pair_base",
        self.current_pair_base,
        "new_page",
        new_page_no
    )

    originalReaderPagingonPageUpdate(self, new_page_no, orig_mode)
end

function ReaderPaging:genDualPagingMenu()
    return {
        {
            text = _("First page is cover"),
            checked_func = function()
                return self.document_settings.dual_page_mode_first_page_is_cover
            end,
            callback = function()
                self.document_settings.dual_page_mode_first_page_is_cover =
                    not self.document_settings.dual_page_mode_first_page_is_cover
            end,
            enabled_func = function()
                return self:isDualPageEnabled()
            end,
            help_text = _(
                -- luacheck: no max line length
                [[When using Dual Page Mode, and the first page of the document should be shown on its owm, toggle this on.]]
            ),
        },
        {
            text = _("Right To Left (RTL)"),
            checked_func = function()
                return self.document_settings.dual_page_mode_rtl
            end,
            callback = function()
                self.document_settings.dual_page_mode_rtl = not self.document_settings.dual_page_mode_rtl
            end,
            enabled_func = function()
                return self:isDualPageEnabled()
            end,
            separator = true,
            help_text = _(
                -- luacheck: no max line length
                [[When using Dual Page Mode, and the second page needs to be rendered on the left and the first page on the right (RTL), enable this option.]]
            ),
        },
        {
            text = _("Auto Enable"),
            checked_func = function()
                return self.reader_settings.auto_enable_dual_page_mode
            end,
            callback = function()
                self.reader_settings.auto_enable_dual_page_mode = not self.reader_settings.auto_enable_dual_page_mode
            end,
            enabled_func = function()
                return self:isDualPageEnabled()
            end,
            separator = true,
            help_text = _(
                [[When this settings is enabled, when you rotate your device to landscape mode, Dual Page Mode will be enabled automatically.]]
            ),
        },
    }
end

-- Given the page number, calculate what the correct base page would be for
-- dual page mode.
--
-- @param page number
--
-- @return number
function ReaderPaging:getDualPageBaseFromPage(page)
    logger.dbg("ComicReaderPaging.getDualPageBaseFromPage: calculating base for page", page)

    if not page or page == 0 then
        page = 1
    end

    if self.document_settings.dual_page_mode_first_page_is_cover and page == 1 then
        return 1
    end

    if self.document_settings.dual_page_mode_first_page_is_cover then
        return (page % 2 == 0) and page or (page - 1)
    end

    return (page % 2 == 1) and page or (page - 1)
end

-- Returns the page pair for dual page mode for the given base
-- @param ordered boolean if the caller needs the page number in displaying order from LTR
function ReaderPaging:getDualPagePairFromBasePage(page, ordered)
    local pair_base = self:getDualPageBaseFromPage(page)
    ordered = ordered and ordered or false

    logger.dbg("ComicReaderPaging.getDualPagePairFromBasePage: got base for pair", pair_base)

    if self.document_settings.dual_page_mode_first_page_is_cover and pair_base == 1 then
        return { 1 }
    end

    -- Create the pair array
    local pair = { pair_base }
    if pair_base + 1 <= self.number_of_pages then
        table.insert(pair, pair_base + 1)
    end

    if not ordered then
        return pair
    end

    -- Fancy reversing
    local n = #pair
    for i = 1, math.floor(n / 2) do
        pair[i], pair[n - i + 1] = pair[n - i + 1], pair[i]
    end

    return pair
end

function ReaderPaging:updateFlippingPage(page)
    self.flipping_page = page

    if self:isDualPageEnabled() then
        self.flipping_page = self:getDualPageBaseFromPage(page)
    end
end

function ReaderPaging:pageFlipping(flipping_ges)
    local whole = self.number_of_pages
    local steps = #self.flip_steps
    local stp_proportion = flipping_ges.distance / Screen:getWidth()
    local abs_proportion = flipping_ges.distance / Screen:getHeight()
    local direction = BD.flipDirectionIfMirroredUILayout(flipping_ges.direction)
    if direction == "east" then
        self:onGotoPageRel(-self.flip_steps[math.ceil(steps * stp_proportion)])
    elseif direction == "west" then
        self:onGotoPageRel(self.flip_steps[math.ceil(steps * stp_proportion)])
    elseif direction == "south" then
        self:onGotoPageRel(-math.floor(whole * abs_proportion))
    elseif direction == "north" then
        self:onGotoPageRel(math.floor(whole * abs_proportion))
    end
    UIManager:setDirty(self.view.dialog, "partial")
end

function ReaderPaging:onPan(_, ges)
    if self.bookmark_flipping_mode then
        return true
    elseif self.page_flipping_mode then
        if self.view.zoom_mode == "page" or self:isDualPageEnabled() then
            logger.dbg("ReaderPaging:onPan", self.flipping_page, ges)
            self:pageFlipping(ges)
        else
            self.view:PanningStart(-ges.relative.x, -ges.relative.y)
        end
    elseif ges.direction == "north" or ges.direction == "south" then
        if ges.mousewheel_direction and not self.view.page_scroll then
            -- Mouse wheel generates a Pan event: in page mode, move one
            -- page per event. Scroll mode is handled in the 'else' branch
            -- and use the wheeled distance.
            self:onGotoViewRel(-1 * ges.mousewheel_direction)
        elseif self.view.page_scroll then
            if not self._pan_started then
                self._pan_started = true
                -- Re-init state variables
                self._pan_has_scrolled = false
                self._pan_prev_relative_y = 0
                self._pan_to_scroll_later = 0
                self._pan_real_last_time = 0
                if ges.mousewheel_direction then
                    self._pan_activation_time = false
                else
                    self._pan_activation_time = ges.time + self.scroll_activation_delay
                end
                -- We will restore the previous position if this pan
                -- ends up being a swipe or a multiswipe
                -- Somehow, accumulating the distances scrolled in a self._pan_dist_to_restore
                -- so we can scroll these back may not always put us back to the original
                -- position (possibly because of these page_states?). It's safer
                -- to remember the original page_states and restore that. We can keep
                -- a reference to the original table as onPanningRel() will have this
                -- table replaced.
                self._pan_page_states_to_restore = self.view.page_states
            end
            local scroll_now = false
            if self._pan_activation_time and ges.time >= self._pan_activation_time then
                self._pan_activation_time = false -- We can go on, no need to check again
            end
            if not self._pan_activation_time and ges.time - self._pan_real_last_time >= self.pan_interval then
                scroll_now = true
                self._pan_real_last_time = ges.time
            end
            local scroll_dist = 0
            if self.scroll_method == self.ui.scrolling.SCROLL_METHOD_CLASSIC then
                -- Scroll by the distance the finger moved since last pan event,
                -- having the document follows the finger
                scroll_dist = self._pan_prev_relative_y - ges.relative.y
                self._pan_prev_relative_y = ges.relative.y
                if not self._pan_has_scrolled then
                    -- Avoid checking this for each pan, no need once we have scrolled
                    if self.ui.scrolling:cancelInertialScroll() or self.ui.scrolling:cancelledByTouch() then
                        -- If this pan or its initial touch did cancel some inertial scrolling,
                        -- ignore activation delay to allow continuous scrolling
                        self._pan_activation_time = false
                        scroll_now = true
                        self._pan_real_last_time = ges.time
                    end
                end
                self.ui.scrolling:accountManualScroll(scroll_dist, ges.time)
            elseif self.scroll_method == self.ui.scrolling.SCROLL_METHOD_TURBO then
                -- Legacy scrolling "buggy" behaviour, that can actually be nice
                -- Scroll by the distance from the initial finger position, this distance
                -- controlling the speed of the scrolling)
                if scroll_now then
                    scroll_dist = -ges.relative.y
                end
                -- We don't accumulate in _pan_to_scroll_later
            elseif self.scroll_method == self.ui.scrolling.SCROLL_METHOD_ON_RELEASE then
                self._pan_to_scroll_later = -ges.relative.y
                if scroll_now then
                    self._pan_has_scrolled = true -- so we really apply it later
                end
                scroll_dist = 0
                scroll_now = false
            end
            if scroll_now then
                local dist = self._pan_to_scroll_later + scroll_dist
                self._pan_to_scroll_later = 0
                if dist ~= 0 then
                    self._pan_has_scrolled = true
                    UIManager.currently_scrolling = true
                    self:onPanningRel(dist)
                end
            else
                self._pan_to_scroll_later = self._pan_to_scroll_later + scroll_dist
            end
        end
    end
    return true
end

function ReaderPaging:onPanRelease(_, ges)
    if self.page_flipping_mode then
        if self.view.zoom_mode == "page" or self:isDualPageEnabled() then
            logger.dbg("ReaderPaging:onPanRelease", self.current_page, ges)
            self:updateFlippingPage(self.current_page)
        else
            self.view:PanningStop()
        end
    else
        if self._pan_has_scrolled and self._pan_to_scroll_later ~= 0 then
            self:onPanningRel(self._pan_to_scroll_later)
        end
        self._pan_started = false
        self._pan_page_states_to_restore = nil
        UIManager.currently_scrolling = false
        if self._pan_has_scrolled then
            self._pan_has_scrolled = false
            -- Don't do any inertial scrolling if pan events come from
            -- a mousewheel (which may have itself some inertia)
            if (ges and ges.from_mousewheel) or not self.ui.scrolling:startInertialScroll() then
                UIManager:setDirty(self.view.dialog, "partial")
            end
        end
    end
end

--- Automatically enables dual page mode when the device is rotated to landscape.
--
-- This method may be called during ReaderUI initialization before the plugin's patching
-- process has completed. Settings (document_settings and reader_settings) can be nil if:
-- 1. This event fires during ReaderUI:init() before patch_reader_paging() completes
-- 2. The plugin hasn't been fully loaded yet
--
-- The early return guards against nil dereference to prevent crashes during initialization.
function ReaderPaging:autoEnableDualPageModeIfLandscape()
    if not self.document_settings or not self.reader_settings or self.current_page == 0 then
        return
    end

    local should_enable = Screen:getScreenMode() == "landscape"
        and not self.document_settings.dual_page_mode
        and self.reader_settings.auto_enable_dual_page_mode

    logger.dbg("ComicReaderPaging:autoEnableDualPageModeIfLandscape", should_enable, self.view.page_scroll)

    if should_enable and self.view.page_scroll then
        UIManager:show(InfoMessage:new({
            text = _([[Dual page mode not automatically enabled due to continues view mode.]]),
            timeout = 4,
        }))

        return
    end

    -- Auto enable Dual Page Mode if we rotate to landscape
    if should_enable then
        self:onSetPageMode(2)

        Notification:notify(_("Dual mode page automatically enabled."), Notification.SOURCE_OTHER)
        self:onRedrawCurrentPage()
    end
end

--- Automatically disables dual page mode when the device is rotated to portrait.
--
-- This method may be called during ReaderUI initialization before the plugin's patching
-- process has completed. Settings can be nil if this event fires during ReaderUI:init()
-- before patch_reader_paging() has set document_settings.
--
-- The early return guards against nil dereference to prevent crashes during initialization.
function ReaderPaging:disableDualPageModeIfNotLandscape()
    if not self.document_settings or self.current_page == 0 then
        return
    end

    if Screen:getScreenMode() ~= "landscape" and self.document_settings.dual_page_mode then
        self:onSetPageMode(1)

        Notification:notify(_("Dual page mode automatically disabled."), Notification.SOURCE_OTHER)
        self:onRedrawCurrentPage()
    end
end

-- When the screen is rezised, we shall check if we ended up in landscape
function ReaderPaging:onSetDimensions(_)
    self:autoEnableDualPageModeIfLandscape()
    self:disableDualPageModeIfNotLandscape()
end

function ReaderPaging:onSetRotationMode(rotation)
    logger.dbg("ComicReaderPaging:onSetRotationMode:", rotation)

    self:autoEnableDualPageModeIfLandscape()
    self:disableDualPageModeIfNotLandscape()
end

function ReaderPaging:firstTimeDualPageMode()
    logger.dbg("ReaderPaging:firstTimeDualPageMode")

    UIManager:show(InfoMessage:new({
        text = _([[Welcome to Dual Page Mode!

One important thing you should know about this mode.
All the zooming functions are disabled!
So if you need to do any zooming, you must go back to single page mode.
If you're interested in why zooming is disabled, consult the wiki.

As a tip: you can register a shortcut to toggle dual page mode!
]]),
    }))

    self.reader_settings.first_time_dual_page_mode = false
end

-- This should be the only subscriber for this event.
-- Everyone else needs to sub to DualPageModeEnabled.
-- This event is sent by dispatcher, and since ReaderPaging owns page mode,
-- it's in charge to determine if the Toggle is valid or not.
--
-- If it is valid, the matching event will be sent:
-- - DualPageModeEnabled(true|flake, base_page)
function ReaderPaging:onToggleDualPageMode()
    logger.dbg("ReaderPaging:onToggleDualPageMode")

    if not self:canDualPageMode() then
        Notification:notify(_("Dual mode page is not supported."))

        return
    end

    if self.document_settings.dual_page_mode then
        Notification:notify(_("Dual mode page disabled."))
        self:onSetPageMode(1)

        return
    end

    Notification:notify(_("Dual mode page enabled."))
    self:onSetPageMode(2)
end

-- This returns boolean indicating if we are in a position to turn on dual page mode or not
--
-- @return boolean
function ReaderPaging:canDualPageMode()
    return self:supportsDualPage() and not self.view.page_scroll
end

-- This should be the only subscriber for this event.
-- Everyone else needs to sub to DualPageModeEnabled.
--
-- @param enabled boolean
function ReaderPaging:onSetAutoEnableDualPageMode(enabled)
    self.reader_settings.auto_enable_dual_page_mode = enabled
end

function ReaderPaging:onSetDualPageModeFirstPageIsCover(bool)
    self.document_settings.dual_page_mode_first_page_is_cover = bool
end

function ReaderPaging:onSetDualPageModeRTL(bool)
    self.document_settings.dual_page_mode_rtl = bool
end

-- @param mode number 1 = single, 2 = dual
function ReaderPaging:onSetPageMode(mode)
    logger.dbg(
        "ReaderPaging:onSetPageMode",
        mode,
        "dual paging currently enabled",
        self.document_settings.dual_page_mode
    )

    if mode ~= 2 and self.document_settings.dual_page_mode then
        self.ui:handleEvent(Event:new("DualPageModeEnabled", false))
        self.document_settings.dual_page_mode = false
    end

    if mode == 2 and not self.document_settings.dual_page_mode and self:canDualPageMode() then
        if self.reader_settings.first_time_dual_page_mode then
            self:firstTimeDualPageMode()
        end

        self.document_settings.dual_page_mode = true
        self:updatePagePairStatesForBase(self.current_pair_base)
        self.ui:handleEvent(Event:new("DualPageModeEnabled", true, self.current_pair_base))
    end

    self.ui.document.configurable.page_mode = mode
    self:onRedrawCurrentPage()
end

function ReaderPaging:onPageUpdate(new_page_no, orig_mode)
    self.current_pair_base = self:getDualPageBaseFromPage(new_page_no)

    logger.dbg(
        "ReaderPaging:onPageUpdatef: curr_page",
        self.current_page,
        "curr_pair_base",
        self.current_pair_base,
        "new_page",
        new_page_no
    )

    self.current_page = new_page_no
    if self.view.page_scroll and orig_mode ~= "scrolling" then
        self.ui:handleEvent(Event:new("InitScrollPageStates", orig_mode))
    end
end

-- We need to remember areas to handle page turn event.
--
-- If recalculate results in a new visible_area, we need to
-- recalculate the page states if we're in dual page mode.
--
-- @param visible_area Geom
-- @param page_area Geom
function ReaderPaging:onViewRecalculate(visible_area, page_area)
    logger.dbg("ComicReaderPaging:onViewRecalculate", visible_area, page_area)
    local va_changed = self.visible_area and not self.visible_area:equalSize(visible_area) or true

    self.visible_area = visible_area:copy()
    self.page_area = page_area

    if va_changed and self:isDualPageEnabled() then
        self:updatePagePairStatesForBase(self.current_pair_base)
    end
end

-- Get the maximum possible base page for dual page mode
function ReaderPaging:getMaxDualPageBase()
    local total_pages = self.number_of_pages
    if self.document_settings.dual_page_mode_first_page_is_cover then
        -- With cover: spreads are 2-3, 4-5, etc. (even bases)
        return total_pages % 2 == 0 and total_pages or total_pages - 1
    else
        -- Without cover: spreads are 1-2, 3-4, 5-6, etc. (odd bases)
        return total_pages % 2 == 1 and total_pages or total_pages - 1
    end
end

-- Given the current base and the relative page movements,
-- return the right base for dual page navigation.
--
-- If self.document_settings.dual_page_mode_first_page_is_cover is enabled, then we start counting pairs
-- from page 2 onwards.
-- So if we are at page 1, the next pairs are:
-- - 2,3
-- - 4,5
-- etc
--
-- If it's disabled, then it becomes:
-- - 1,2
-- - 3,4
-- etc
--
-- So if we are at base 1, and make a relative move +1, return 2
-- which will make readerview render page 2,3
--
function ReaderPaging:getPairBaseByRelativeMovement(diff)
    logger.dbg("ReaderPaging:getPairBaseByRelativeMovement:", diff)
    local total_pages = self.number_of_pages
    local current_base = self.current_pair_base

    if self.document_settings.dual_page_mode_first_page_is_cover and current_base == 1 then
        -- Handle cover page navigation
        if diff <= 0 then
            return 1 -- Stay on cover
        else
            -- Jump to first spread (2) + subsequent spreads
            return math.min(2 + (diff - 1) * 2, self:getMaxDualPageBase())
        end
    end

    -- Calculate new base for spreads
    local new_base = current_base + (diff * 2)

    -- Clamp to valid range. (ComicReader+: getMaxDualPageBase statt "immer gerade" – ohne Titelseite
    -- liegen die Paare auf ungeraden Seiten, sonst ist die letzte Seite bei ungerader Seitenzahl
    -- nicht erreichbar; KORComic #76)
    local max_base = self:getMaxDualPageBase()
    new_base = math.max(1, math.min(new_base, max_base))

    -- Handle backward navigation to cover
    if new_base < 2 then
        return total_pages >= 1 and 1 or new_base
    end

    return new_base
end

function ReaderPaging:onGotoPageRel(diff)
    logger.dbg("ComicReaderPaging:onGotoPageRel:", diff, self.current_page)
    local new_va = self.visible_area:copy()
    local x_pan_off, y_pan_off = 0, 0
    local right_to_left = self.ui.document.configurable.writing_direction
        and self.ui.document.configurable.writing_direction > 0
    local bottom_to_top = self.ui.zooming.zoom_bottom_to_top
    local h_progress = 1 - self.ui.zooming.zoom_overlap_h * (1 / 100)
    local v_progress = 1 - self.ui.zooming.zoom_overlap_v * (1 / 100)
    local old_va = self.visible_area
    local old_page = self.current_page
    local x, y, w, h = "x", "y", "w", "h"
    local x_diff = diff
    local y_diff = diff

    -- Adjust directions according to settings
    if self.ui.zooming.zoom_direction_vertical then -- invert axes
        y, x, h, w = x, y, w, h
        h_progress, v_progress = v_progress, h_progress
        if right_to_left then
            x_diff, y_diff = -x_diff, -y_diff
        end
        if bottom_to_top then
            x_diff = -x_diff
        end
    elseif bottom_to_top then
        y_diff = -y_diff
    end
    if right_to_left then
        x_diff = -x_diff
    end

    if self.zoom_mode ~= "free" then
        x_pan_off = Math.roundAwayFromZero(self.visible_area[w] * h_progress * x_diff)
        y_pan_off = Math.roundAwayFromZero(self.visible_area[h] * v_progress * y_diff)
    end

    -- Auxiliary functions to (as much as possible) keep things clear
    -- If going backwards (diff < 0) "end" is equivalent to "beginning", "next" to "previous";
    -- in column mode, "line" is equivalent to "column".
    local function at_end(axis)
        -- returns true if we're at the end of line (axis = x) or page (axis = y)
        local len, _diff
        if axis == x then
            len, _diff = w, x_diff
        else
            len, _diff = h, y_diff
        end
        return old_va[axis] + old_va[len] + _diff > self.page_area[axis] + self.page_area[len]
            or old_va[axis] + _diff < self.page_area[axis]
    end
    local function goto_end(axis, _diff)
        -- updates view area to the end of line (axis = x) or page (axis = y)
        local len = axis == x and w or h
        _diff = _diff or (axis == x and x_diff or y_diff)
        new_va[axis] = _diff > 0 and old_va[axis] + self.page_area[len] - old_va[len] or self.page_area[axis]
    end
    local function goto_next_line()
        new_va[y] = old_va[y] + y_pan_off
        goto_end(x, -x_diff)
    end

    local function goto_next_page()
        local new_page
        local curr_page = self.current_page

        if self.page_flipping_mode then
            curr_page = self.flipping_page
        end

        if self.ui.document:hasHiddenFlows() then
            logger.dbg("ComicReaderPaging:onGotoPageRel: document has hidden flows")
            local forward = diff > 0
            local pdiff = forward and math.ceil(diff) or math.ceil(-diff)
            new_page = curr_page
            for _ = 1, pdiff do
                local test_page = forward and self.ui.document:getNextPage(new_page)
                    or self.ui.document:getPrevPage(new_page)
                if test_page == 0 then -- start or end of document reached
                    if forward then
                        new_page = self.number_of_pages + 1 -- to trigger EndOfBook below
                    else
                        new_page = 0
                    end
                    break
                end
                new_page = test_page
            end
        elseif self:isDualPageEnabled() then
            logger.dbg("ComicReaderPaging:onGotoPageRel: dual page mode enabled")
            local max_base = self:getMaxDualPageBase()

            -- Check if we're at the last spread and trying to move forward
            if self.current_pair_base >= max_base and diff > 0 then
                logger.dbg("ComicReaderPaging:onGotoPageRel: at last spread, triggering end of book")
                new_page = self.number_of_pages + 1 -- to trigger EndOfBook below
            else
                new_page = self:getPairBaseByRelativeMovement(diff)
                logger.dbg("ComicReaderPaging: relative page pair move to", new_page)
            end
        else
            new_page = curr_page + diff
            logger.dbg("ComicReaderPaging: new_page", new_page, curr_page)
        end

        if new_page > self.number_of_pages then
            self.ui:handleEvent(Event:new("EndOfBook"))
            goto_end(y)
            goto_end(x)
        elseif new_page > 0 then
            -- Be sure that the new and old view areas are reset so that no value is carried over to next page.
            -- Without this, we would have panned_y = new_va.y - old_va.y > 0,
            -- and panned_y will be added to the next page's y direction.
            -- This occurs when the current page has a y > 0 position
            -- (for example, a cropped page) and can fit the whole page height,
            -- while the next page needs scrolling in the height.
            self:_gotoPage(new_page)
            new_va = self.visible_area:copy()
            old_va = self.visible_area
            goto_end(y, -y_diff)
            goto_end(x, -x_diff)
        else
            goto_end(x)
        end
    end

    -- Move the view area towards line end
    new_va[x] = old_va[x] + x_pan_off
    new_va[y] = old_va[y]

    local prev_page = self.current_page

    -- Handle cases when the view area gets out of page boundaries
    if not self.page_area:contains(new_va) then
        logger.dbg("ComicReaderPaging:onGotoPageRel self.page contains new_va")
        if not at_end(x) then
            logger.dbg("ComicReaderPaging:onGotoPageRel at_end(x)")
            goto_end(x)
        else
            goto_next_line()
            if not self.page_area:contains(new_va) then
                if not at_end(y) then
                    logger.dbg("ComicReaderPaging:onGotoPageRel at_end(y)")
                    goto_end(y)
                else
                    goto_next_page()
                end
            else
                -- FIXME(ogkevin): For some reason, we end in this case when moving to next page
                -- it turns out, this is only broken on start. Once the window size is refreshed,
                -- it works.
                logger.dbg("ComicReaderPaging:onGotoPageRel page_area does not contain new_va")
            end
        end
    end

    if self.current_page == prev_page then
        logger.dbg("ComicReaderPaging:onGotoPageRel page number didn't update")
        -- Page number haven't changed when panning inside a page,
        -- but time may: keep the footer updated
        self.view.footer:onUpdateFooter(self.view.footer_visible)
    end

    -- signal panning update
    local panned_x, panned_y = math.floor(new_va.x - old_va.x), math.floor(new_va.y - old_va.y)
    self.view:PanningUpdate(panned_x, panned_y)

    -- Update dim area in ReaderView
    if self.view.page_overlap_enable then
        if self.current_page ~= old_page then
            self.view.dim_area:clear()
        else
            -- We're post PanningUpdate, recompute via self.visible_area instead of new_va for accuracy,
            -- it'll have been updated via ViewRecalculate
            panned_x, panned_y = math.floor(self.visible_area.x - old_va.x), math.floor(self.visible_area.y - old_va.y)

            self.view.dim_area.h = self.visible_area.h - math.abs(panned_y)
            self.view.dim_area.w = self.visible_area.w - math.abs(panned_x)
            if panned_y < 0 then
                self.view.dim_area.y = self.visible_area.h - self.view.dim_area.h
            else
                self.view.dim_area.y = 0
            end
            if panned_x < 0 then
                self.view.dim_area.x = self.visible_area.w - self.view.dim_area.w
            else
                self.view.dim_area.x = 0
            end
        end
    end

    return true
end

--When page scroll is enabled, we need to disable Dual Page mode
--@param page_scroll bool if page_scroll is on or not
function ReaderPaging:onSetScrollMode(page_scroll)
    if not self:supportsDualPage() then
        return
    end
    if page_scroll then
        self:onSetPageMode(1)

        return
    end

    self:autoEnableDualPageModeIfLandscape()
end

-- If we are in a state to support dual page mode, e.g. device orientation and document ristrictions
--
-- @returns boolean
function ReaderPaging:supportsDualPage()
    local screen_mode = Screen:getScreenMode()

    logger.dbg("ComicReaderPaging:supportsDualPage", screen_mode)

    return screen_mode == "landscape"
end

-- @return bool
function ReaderPaging:isDualPageEnabled()
    local enabled = self.document_settings.dual_page_mode and self:supportsDualPage()
    logger.dbg("ComicReaderPaging:isDualPageEnabled()", enabled, "setting", self.document_settings.dual_page_mode)

    return enabled
end

function ReaderPaging:updatePagePairStatesForBase(pageno)
    logger.dbg("ReaderPaging:updatePagePairStatesForBase: setting dual page pairs")

    self.view.page_states = {}
    local pair = self:getDualPagePairFromBasePage(pageno)
    local zooms = self:calculateZoomFactorForPagePair(pair)

    for i, page in ipairs(pair) do
        local dimen = self.ui.document:getNativePageDimensions(page)
        -- zooms should be as long as pairs
        ---@diagnostic disable-next-line: need-check-nil
        local zoom = zooms[i]
        local scaled_w = dimen.w * zoom
        local scaled_h = dimen.h * zoom

        self.view.page_states[i] = {
            page = page,
            zoom = zoom,
            rotation = self.view.state.rotation,
            gamma = self.view.state.gamma,
            dimen = Geom:new({ w = scaled_w, h = scaled_h }),
            native_dimen = dimen,
        }
        logger.dbg("ReaderPaging:_gotoPage: set view page states to: ", self.view.page_states)
    end
end

-- For the given page pair, calculate their zooming factor
-- ATM, we only support filling the height for dual page mode.
function ReaderPaging:calculateZoomFactorForPagePair(pair)
    logger.dbg(
        "ReaderPaging:calculateZoomFactorForPagePair",
        self.visible_area,
        self.ui.view.visible_area,
        self.ui.view.dimen
    )

    -- There is a small chance where this method gets called while
    -- onViewRecalculate didn't get a chance to update self.visible_area.
    -- To prevent funny page rendering, update self.visible_area before it's
    -- used for calulcating the zoom factors.
    self.visible_area = self.ui.view.visible_area

    local visible_area = self.visible_area
    local max_height = visible_area.h
    local max_width = visible_area.w
    local zooms = {}

    local total_width = 0
    local height_zooms = {}
    for i, page in ipairs(pair) do
        local dimen = self.ui.document:getNativePageDimensions(page)
        local zoom = 1

        if dimen.h ~= max_height then
            zoom = max_height / dimen.h
        end

        height_zooms[i] = zoom
        total_width = total_width + dimen.w * zoom
    end
    -- If the total width exceeds the visible width, scale down both pages
    if total_width > max_width then
        -- Find the scaling factor to fit both pages
        local scale_factor = max_width / total_width
        for i, zoom in ipairs(height_zooms) do
            zooms[i] = zoom * scale_factor
        end
    else
        for i, zoom in ipairs(height_zooms) do
            zooms[i] = zoom
        end
    end

    return zooms
end

function ReaderPaging:onRedrawCurrentPage()
    logger.dbg("ReaderPaging:onRedrawCurrentPage")

    local page = self.current_page

    -- If we are not on a base of a pair, and we redraw, there can be
    -- some funny rendering. I'm not sure why that is, but ensuring
    -- that we goto base ensures that this doesn't happen.
    -- Most likely something with caching, it's always caching.
    -- As in, the page number didn't change but all of a sudden we're rendering
    -- something different?
    if self:isDualPageEnabled() then
        page = self:getDualPageBaseFromPage(self.current_page)
        -- Make sure page states are up to date
        self:updatePagePairStatesForBase(page)
    end

    self.ui:handleEvent(Event:new("PageUpdate", page))
    return true
end

-- wrapper for bounds checking
function ReaderPaging:_gotoPage(number, orig_mode)
    if number == self.current_page or not number then
        -- update footer even if we stay on the same page (like when
        -- viewing the bottom part of a page from a top part view)
        self.view.footer:onUpdateFooter(self.view.footer_visible)
        return true
    end
    if number > self.number_of_pages then
        logger.warn("page number too high: " .. number .. "!")
        number = self.number_of_pages
    elseif number < 1 then
        logger.warn("page number too low: " .. number .. "!")
        number = 1
    end
    if not self.view.page_scroll and self:supportsDualPage() then
        self:updatePagePairStatesForBase(number)
    end
    logger.dbg("ComicReaderPaging:_gotoPage: send page update event:", number)
    -- this is an event to allow other controllers to be aware of this change
    self.ui:handleEvent(Event:new("PageUpdate", number, orig_mode))
    return true
end

-- This function can be use to create a pop up and ask to user
-- which page number of the 2 pages shown in dual page mode should be used
-- for an action.
-- The selected page number will then be passed as the only argument to callbackfn
--
-- If we're not in DualPageMode, the function is called with the current page.
--
-- E.g. when a bookmark is toggled by pressing the right top corner
function ReaderPaging:requestPageFromUserInDualPageModeAndExec(callback)
    if not self:isDualPageEnabled() then
        callback(self.current_page)
        return
    end
    -- We are on the last page and it's alone
    if self.current_pair_base == self.number_of_pages then
        callback(self.current_page)
        return
    end
    -- We are on the first page and its shown on its own
    if self.document_settings.dual_page_mode_first_page_is_cover and self.current_pair_base == 1 then
        callback(self.current_page)
        return
    end
    local page_pair = self:getDualPagePairFromBasePage(self.current_pair_base)
    logger.dbg("ReaderPaging:requestPageFromUserInDualPageModeAndExec() page pair", page_pair)
    local button_dialog
    local buttons = {
        {
            {
                text = _("Left / First Rendered"),
                callback = function()
                    UIManager:close(button_dialog)
                    local page
                    if not self.document_settings.dual_page_mode_rtl then
                        page = page_pair[1]
                    else
                        page = page_pair[2]
                    end
                    logger.dbg("ReaderPaging:requestPageFromUserInDualPageModeAndExec() for left page", page)
                    callback(page)
                end,
            },
            {
                text = _("Right / Second Rendered"),
                callback = function()
                    UIManager:close(button_dialog)
                    local page
                    if not self.document_settings.dual_page_mode_rtl then
                        page = page_pair[2]
                    else
                        page = page_pair[1]
                    end
                    logger.dbg("ReaderPaging:requestPageFromUserInDualPageModeAndExec() for right page", page)
                    callback(page)
                end,
            },
        },
    }
    button_dialog = ButtonDialog:new({
        name = "ReaderPaging:requestPageFromUserInDualPageModeOrCurrent",
        title = "Annotate which page?",
        title_align = "center",
        buttons = buttons,
    })

    UIManager:show(button_dialog, "full")
end

-- ReaderUI.instance is not set until AFTER init() completes,
-- so we need to defer checking for an existing paging instance
UIManager:nextTick(function()
    logger.dbg("ComicReaderPaging: Deferred check for existing paging instance")

    if not (ReaderUI and ReaderUI.instance and ReaderUI.instance.paging) then
        logger.dbg("ComicReaderPaging: No existing paging instance found (normal startup or fresh ReaderUI)")

        return
    end

    local existing = ReaderUI.instance.paging

    if existing._comic_patched then
        logger.dbg("ComicReaderPaging: Existing paging instance already patched")

        return
    end

    logger.dbg("ComicReaderPaging: Detected existing paging instance (startup last-file case)")
    patch_reader_paging(existing)
end)

-- ── ComicReader+: Doppelseiten-Erkennung ───────────────────────────────────
-- Seiten im Querformat (breiter als hoch) sind meist Doppelseiten (Spreads) und werden im
-- Doppelseiten-Modus allein angezeigt, statt neben eine andere Seite gequetscht zu werden.
-- Die Aufteilung in Ansichten wird einmal von vorne nach hinten berechnet und gilt dann fuer
-- Blaettern, Springen, Lesezeichen und Eselsohr gleichermassen:
--   * Cover (falls eingestellt): allein
--   * Querformat-Seite: allein
--   * Hochformat-Seite, gefolgt von einer Hochformat-Seite: Paar
--   * Hochformat-Seite vor einer Querformat-Seite (oder als letzte Seite): allein
-- Ausgeschaltet verhaelt sich alles exakt wie im Original (die Original-Funktionen werden aufgerufen).

local SPREAD_RATIO = 1.05 -- breiter als 105 % der Hoehe = Doppelseite

local crp_texts = {
    de = {
        detect = "Doppelseiten erkennen",
        detect_help = "Seiten im Querformat (breiter als hoch) sind meist Doppelseiten. Sie werden allein angezeigt statt neben einer anderen Seite. Die Seiten davor und danach werden passend neu gepaart.\n\nBeim ersten Öffnen eines Comics werden die Seitengrößen bis zur aktuellen Seite einmal eingelesen und dann gespeichert.",
        about = "Wie funktioniert das?",
        help = "Im Querformat zeigt Comic Dual Page zwei Comic-Seiten nebeneinander (Doppelseiten-Modus). Die Einstellungen hier kannst du auch im Hochformat schon vorher setzen, sie gelten beim Drehen ins Querformat.\n\n• Doppelseiten erkennen: Seiten im Querformat sind meist schon Doppelseiten und werden allein gezeigt.\n• Erste Seite als Cover: Das Cover steht allein, danach folgen 2+3, 4+5 …\n• Rechts nach links: für Manga.\n• Automatisch einschalten: Der Modus startet beim Drehen ins Querformat von selbst.",
    },
    en = {
        detect = "Detect spreads",
        detect_help = "Landscape pages (wider than tall) are usually two-page spreads. They are shown on their own instead of next to another page, and the pages around them are paired up accordingly.\n\nThe first time a comic is opened, page sizes up to the current page are read once and then saved.",
        about = "How does it work?",
        help = "In landscape, Comic Dual Page shows two comic pages side by side (dual page mode). You can set the options here in portrait too, they apply once you rotate to landscape.\n\n• Detect spreads: landscape pages are usually two-page spreads already and are shown on their own.\n• First page is cover: the cover stands alone, then 2+3, 4+5 …\n• Right to left: for manga.\n• Auto enable: the mode turns on by itself when you rotate to landscape.",
    },
}

local function crpT(key)
    local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
    local l = (ok and type(lang) == "string" and lang:sub(1, 2):lower() == "de") and "de" or "en"
    return crp_texts[l][key] or crp_texts.en[key] or key
end

-- Erkennung ist an, solange sie fuer dieses Dokument nicht ausdruecklich abgeschaltet wurde
function ReaderPaging:crpDetectSpreads()
    local s = self.document_settings
    return not (s and s.dual_page_mode_detect_spreads == false)
end

function ReaderPaging:crpActive()
    return self:crpDetectSpreads() and self:isDualPageEnabled()
end

-- Querformat-Pruefung mit Speicher im Dokument (Seitengroessen einlesen kostet Zeit)
function ReaderPaging:crpIsSpread(page)
    if not self._crp_spreads then
        self._crp_spreads = self.ui.doc_settings and self.ui.doc_settings:readSetting("comicreaderplus_spreads") or {}
        if self.ui.doc_settings then self.ui.doc_settings:saveSetting("comicreaderplus_spreads", self._crp_spreads) end
    end
    local key = tostring(page)
    local known = self._crp_spreads[key]
    if known ~= nil then return known end
    local is_spread = false
    local ok, dimen = pcall(self.ui.document.getNativePageDimensions, self.ui.document, page)
    if ok and dimen and dimen.w and dimen.h and dimen.h > 0 then
        is_spread = dimen.w > dimen.h * SPREAD_RATIO
    end
    self._crp_spreads[key] = is_spread
    return is_spread
end

-- Liefert die Ansicht (Liste von 1 oder 2 Seiten in Lesereihenfolge), zu der die Seite gehoert.
-- Berechnet nur so weit wie noetig und merkt sich das Ergebnis.
function ReaderPaging:crpUnitOf(page)
    local n = self.number_of_pages or 0
    if n < 1 then return { 1 } end
    if not page or page < 1 then page = 1 end
    if page > n then page = n end

    local cover = self.document_settings.dual_page_mode_first_page_is_cover and true or false
    local L = self._crp_layout
    if not L or L.cover ~= cover or L.n ~= n then
        L = { cover = cover, n = n, unit_of = {}, next = 1 }
        self._crp_layout = L
    end

    while L.next <= page do
        local p = L.next
        local unit
        if cover and p == 1 then
            unit = { 1 }
        elseif self:crpIsSpread(p) then
            unit = { p }
        elseif p + 1 <= n and not self:crpIsSpread(p + 1) then
            unit = { p, p + 1 }
        else
            unit = { p }
        end
        for _, q in ipairs(unit) do
            L.unit_of[q] = unit
        end
        L.next = unit[#unit] + 1
    end

    return L.unit_of[page]
end

local crpOrigBaseFromPage = ReaderPaging.getDualPageBaseFromPage
function ReaderPaging:getDualPageBaseFromPage(page)
    if not self:crpActive() then return crpOrigBaseFromPage(self, page) end
    if not page or page == 0 then page = 1 end
    return self:crpUnitOf(page)[1]
end

local crpOrigPairFromBase = ReaderPaging.getDualPagePairFromBasePage
function ReaderPaging:getDualPagePairFromBasePage(page, ordered)
    if not self:crpActive() then return crpOrigPairFromBase(self, page, ordered) end
    local unit = self:crpUnitOf(page)
    local pair = {}
    for i, p in ipairs(unit) do pair[i] = p end
    -- Gleiche Bedeutung von "ordered" wie im Original (Reihenfolge umdrehen)
    if ordered and #pair == 2 then pair[1], pair[2] = pair[2], pair[1] end
    return pair
end

-- Wird beim Blaettern gefragt, ob man schon bei der letzten Ansicht ist. Nur anhand der aktuellen
-- Ansicht beantworten, sonst muesste beim ersten Umblaettern der ganze Comic vermessen werden.
local crpOrigMaxBase = ReaderPaging.getMaxDualPageBase
function ReaderPaging:getMaxDualPageBase()
    if not self:crpActive() then return crpOrigMaxBase(self) end
    local base = self.current_pair_base
    if not base or base < 1 then base = self.current_page or 1 end
    local unit = self:crpUnitOf(base)
    if unit[#unit] >= self.number_of_pages then
        return unit[1]
    end
    return self.number_of_pages + 1 -- aktuelle Ansicht ist nicht die letzte
end

local crpOrigRelMove = ReaderPaging.getPairBaseByRelativeMovement
function ReaderPaging:getPairBaseByRelativeMovement(diff)
    if not self:crpActive() then return crpOrigRelMove(self, diff) end
    local n = self.number_of_pages
    local base = self.current_pair_base
    if not base or base < 1 then base = self.current_page or 1 end
    base = self:crpUnitOf(base)[1]
    if diff > 0 then
        for _ = 1, diff do
            local unit = self:crpUnitOf(base)
            local next_page = unit[#unit] + 1
            if next_page > n then break end
            base = self:crpUnitOf(next_page)[1]
        end
    elseif diff < 0 then
        for _ = 1, -diff do
            if base <= 1 then break end
            base = self:crpUnitOf(base - 1)[1]
        end
    end
    return base
end

-- Lesezeichen/Eselsohr: Steht eine Seite allein, nicht nach "links oder rechts" fragen
local crpOrigRequestPage = ReaderPaging.requestPageFromUserInDualPageModeAndExec
function ReaderPaging:requestPageFromUserInDualPageModeAndExec(callback)
    if self:crpActive() then
        local unit = self:crpUnitOf(self.current_pair_base > 0 and self.current_pair_base or self.current_page)
        if #unit == 1 then
            callback(unit[1])
            return
        end
    end
    return crpOrigRequestPage(self, callback)
end

-- Menuepunkt im Doppelseiten-Menue
local crpOrigGenMenu = ReaderPaging.genDualPagingMenu
function ReaderPaging:genDualPagingMenu()
    local items = crpOrigGenMenu(self)
    table.insert(items, 1, {
        text = crpT("detect"),
        checked_func = function()
            return self:crpDetectSpreads()
        end,
        callback = function()
            self.document_settings.dual_page_mode_detect_spreads = not self:crpDetectSpreads()
            self._crp_layout = nil
            if self:isDualPageEnabled() then
                self:onRedrawCurrentPage()
            end
        end,
        enabled_func = function()
            return self:isDualPageEnabled()
        end,
        help_text = crpT("detect_help"),
    })
    -- Die Einstellungen lassen sich schon im Hochformat setzen (vor dem Drehen),
    -- (canDualPageMode verlangt Querformat). Nur im Endlos-Bildlauf geht es nicht.
    -- Sie gelten, sobald der Modus an ist.
    for _i, item in ipairs(items) do
        if item.enabled_func then
            item.enabled_func = function() return not self.view.page_scroll end
        end
    end
    -- Hilfe als letzter Eintrag (Standard in allen Plugins), auch im Hochformat lesbar
    items[#items].separator = true
    table.insert(items, {
        text = crpT("about"),
        keep_menu_open = true,
        callback = function()
            UIManager:show(require("ui/widget/infomessage"):new{ text = crpT("help") })
        end,
    })
    return items
end

-- Neues Dokument: zwischengespeicherte Aufteilung verwerfen
local crpOrigReadSettings = ReaderPaging.onReadSettings
function ReaderPaging:onReadSettings(config)
    self._crp_layout = nil
    self._crp_spreads = nil
    return crpOrigReadSettings(self, config)
end

return ReaderPaging
