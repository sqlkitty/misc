-- ============================================================
-- Are you going to keep going? timer 
-- ============================================================
--
-- A small Hammerspoon utility that periodically asks me to
-- explain what I'm doing on my computer before allowing me
-- to continue.
--
-- The interval changes depending on the time of day:
--
--   Work hours (Mon-Fri, 8am-5pm)  -> 30 minutes
--   Outside work hours             -> 10 minutes
--   Vacation mode                  -> 10 minutes
--
-- The timer is also aware of sleep/wake events, displays the
-- remaining time in the macOS menu bar, and logs each response
-- to a text file.


-- ============================================================
-- Configuration / State
-- ============================================================

-- Set this to true when I'm on vacation.
-- Vacation mode always uses the shorter 10-minute interval.
local VACATION_MODE = false

-- These hold the timer and sleep/wake watcher.
-- Keeping them in variables lets us stop/restart them later.
local countdown = nil
local watcher = nil

-- Hammerspoon can create native macOS menu bar items.
-- This gives us a convenient place to display the countdown.
local menuBar = hs.menubar.new()

-- Number of seconds remaining in the current countdown.
local remaining = 0

-- Store responses in a simple text file.
-- os.getenv("HOME") gives us the user's home directory.
local LOG_FILE =
    os.getenv("HOME") ..
    "/.hammerspoon/hammerspoon_continuation_log.txt"


-- Start with an empty menu bar title.
menuBar:setTitle("")


-- ============================================================
-- Determine whether we're outside working hours
-- ============================================================

local function isOffHours()

    local now = os.date("*t")

    -- In Lua's date table:
    --   Sunday = 1
    --   Monday = 2
    --   ...
    --   Saturday = 7
    --
    -- So Monday-Friday is 2 through 6.
    local weekday =
        (now.wday >= 2 and now.wday <= 6)

    -- Working hours are 8:00am through 4:59pm.
    local duringWorkHours =
        (now.hour >= 8 and now.hour < 17)

    -- If it's not a weekday during working hours,
    -- we're considered to be "off hours".
    return not (weekday and duringWorkHours)
end


-- ============================================================
-- Stop the countdown
-- ============================================================

local function stopTimer()

    -- Hammerspoon timers need to be explicitly stopped.
    if countdown then
        countdown:stop()
        countdown = nil
    end

    -- Clear the countdown from the menu bar.
    menuBar:setTitle("")
end


-- ============================================================
-- Log a completed interval
-- ============================================================

local function logResponse(label, duration, response)

    -- Open the log in append mode so we don't overwrite
    -- previous responses.
    local file = io.open(LOG_FILE, "a")

    if file then

        -- Each entry looks roughly like:
        --
        -- 2025-01-15 10:30:00 | 30 min | 30 Minute Check | ...
        --
        -- Keeping this as plain text makes the log easy to
        -- inspect, grep, or process later.
        file:write(
            os.date("%Y-%m-%d %H:%M:%S"),
            " | ",
            duration / 60,
            " min",
            " | ",
            label,
            " | ",
            response,
            "\n"
        )

        file:close()
    end
end


-- ============================================================
-- Decide how long the next interval should be
-- ============================================================

local function getDurationAndLabel()

    -- Vacation mode intentionally uses the shorter interval.
    if VACATION_MODE then
        return 600, "10 Minute Check (Vacation Mode)"
    end

    local offHours = isOffHours()

    if offHours then

        -- Outside work hours:
        -- check in every 10 minutes.
        return 600, "10 Minute Check"

    else

        -- During work hours:
        -- give myself a 30-minute block.
        return 1800, "30 Minute Check"
    end
end


-- ============================================================
-- Ask what I'm doing
-- ============================================================

local function askToContinue(label, duration)

    -- Keep asking until a valid response is provided.
    while true do

        -- Hammerspoon provides a native macOS text prompt.
        --
        -- The prompt explains how long I've been on the
        -- computer and asks me to justify continuing.
        local button, text = hs.dialog.textPrompt(
            label,
            string.format(
                "You've been on your computer for %d minutes.\n\n" ..
                "What are you doing right now, and why do you need to continue?\n\n" ..
                "Please enter at least 10 characters.",
                duration / 60
            ),
            "",
            "Continue"
        )

        if button == "Continue" and text then

            -- Ignore whitespace when checking whether the
            -- response is long enough.
            --
            -- This means something like "a b c d e" doesn't
            -- pass just because it contains lots of spaces.
            local cleanedText = text:gsub("%s+", "")

            if #cleanedText >= 10 then

                -- Keep the original response when logging it.
                -- We only remove whitespace temporarily for
                -- validation.
                logResponse(label, duration, text)

                -- Start the next interval.
                remaining = getDurationAndLabel()

                return
            end
        end

        -- If the response was too short (or the prompt was
        -- dismissed), loop back around and ask again.
    end
end


-- ============================================================
-- Start a countdown cycle
-- ============================================================

local function startCycle()

    -- Don't accidentally create multiple timers if this
    -- function gets called more than once.
    if countdown then
        return
    end

    -- Determine the interval based on the current state.
    remaining = getDurationAndLabel()

    -- Run this function once every second.
    countdown = hs.timer.doEvery(1, function()

        remaining = remaining - 1

        -- Convert seconds into a human-friendly MM:SS display.
        local m = math.floor(remaining / 60)
        local s = remaining % 60

        -- Put the countdown directly in the macOS menu bar.
        menuBar:setTitle(
            string.format("%d:%02d", m, s)
        )

        -- The interval has finished.
        if remaining <= 0 then

            -- Remember which interval just completed.
            local duration, label =
                getDurationAndLabel()

            -- Before starting another interval, ask me what
            -- I was doing and why I want to continue.
            askToContinue(label, duration)
        end
    end)
end


-- ============================================================
-- Sleep / wake handling
-- ============================================================

-- Hammerspoon can listen for system-level caffeinate events.
--
-- This watcher lets the timer respond to the Mac going to
-- sleep and waking back up.

watcher = hs.caffeinate.watcher.new(function(event)

    -- The Mac woke up.
    --
    -- Start a fresh countdown rather than letting the timer
    -- continue counting while the computer was asleep.
    if event == 4 then
        startCycle()
    end

    -- The Mac is going to sleep.
    --
    -- Stop the countdown so it doesn't become stale while
    -- the computer is suspended.
    if event == 3 then
        stopTimer()
    end
end)


-- Start listening for sleep/wake events.
watcher:start()
