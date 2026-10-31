local HUB = "Urban Reload"
local player = game:GetService("Players").LocalPlayer
local cache = {}
local espColor = Color3.fromRGB(130, 255, 170)
local lastError = nil
local lastProgress = ""
local collected, total = 0, 10
local originalReloadTimes = {}
local function setting(name, fallback)
    local ok, value = pcall(function() return UI.GetValue(name) end)
    if ok and value ~= nil then return value end
    return fallback
end
pcall(function() UI.RemoveTab(HUB) end)
UI.AddTab(HUB, function(tab)
    local farm = tab:Section("Zombie Autofarm", "Left")
    farm:Toggle("ur_farm", "Enabled", false)
    farm:Text("F6 toggles Zombie Autofarm")
    farm:Toggle("ur_collect", "Auto Collect", true)
    farm:Toggle("ur_ads", "Automatic ADS", true)
    farm:Toggle("ur_stationary", "Stationary Check", true)
    local aim = tab:Section("Aiming", "Right")
    aim:SliderFloat("ur_aim_speed", "Aim Speed", 0.1, 2, 0.8, "%.2f")
    aim:SliderInt("ur_radius", "Shoot Radius", 5, 100, 22)
    aim:SliderFloat("ur_still_wait", "Stationary Wait", 0.05, 1, 0.25, "%.2f")
    local weapon = tab:Section("Weapon Mods", "Right")
    weapon:Toggle("ur_recoil", "Recoil Compensation", false)
    weapon:SliderFloat("ur_recoil_strength", "Recoil Strength", 0.1, 5, 1.5, "%.2f")
    weapon:SliderFloat("ur_recoil_interval", "Compensation Interval", 0.01, 0.1, 0.02, "%.3f")
    weapon:Toggle("ur_recoil_firing", "Only While Firing", true)
    weapon:Text("CAUTIOUS! EXPERIMENTAL MIGHT BAN")
    weapon:Toggle("ur_instant_reload", "Instant Reload [EXPERIMENTAL]", false)
    local ghost = tab:Section("Halloween Ghost ESP", "Left")
    ghost:Toggle("ur_ghost_esp", "Enabled", false)
    ghost:ColorPicker("ur_ghost_color", 0.5, 1, 0.65, 1, function(color) espColor = color end)
    ghost:Toggle("ur_ghost_distance", "Show Distance", true)
    ghost:Toggle("ur_ghost_lines", "Snaplines", false)
    ghost:SliderInt("ur_ghost_range", "Max Distance", 50, 5000, 1500)
    local progress = tab:Section("Ghost Collection", "Left")
    progress:Text("Halloween Ghost Progress")
    progress:Text("Reads your actual collected count")
    progress:Button("Check Collection Progress", function()
        print("Halloween Ghosts:", collected .. "/" .. total, "Remaining:", total - collected)
    end)
    local camera = tab:Section("Camera", "Right")
    camera:Toggle("ur_snap", "Snap Back", true)
    camera:SliderFloat("ur_snap_speed", "Snap Speed", 0.5, 5, 3, "%.2f")
    local cases = tab:Section("Auto Case Opener", "Left")
    cases:Toggle("ur_auto_cases", "Auto Open Selected Case", false)
    cases:SliderInt("ur_case_delay", "Seconds Between Attempts", 5, 20, 10)
    cases:Text("Keep the case shop open and select a case")
    cases:Text("Uses GUI Activate; mouse fallback if available")
    cases:Button("Stop Auto Case Opener", function() UI.SetValue("ur_auto_cases", false) end)
    local settings = tab:Section("Settings", "Right")
    settings:Text("Urban Reload Hub V2.7")
    settings:Button("Disable Recoil Compensation", function() UI.SetValue("ur_recoil", false) end)
    settings:Button("Disable Instant Reload", function() UI.SetValue("ur_instant_reload", false) end)
    settings:Button("Disable Ghost ESP", function() UI.SetValue("ur_ghost_esp", false) end)
    settings:Button("Disable Autofarm", function() UI.SetValue("ur_farm", false) end)
end)


 

local AIM_SPEED = 0.80
local MAX_STEP = 65
local SHOOT_RADIUS = 22

local SNAP_SPEED = 3.0
local MAX_SNAP_STEP = 500
local RETURN_DEADZONE = 0.015

local STILL_SPEED = 5
local STILL_WAIT = 0.25
local SAMPLE_INTERVAL = 0.10

local REFRESH_INTERVAL = 0.15
local COIN_INTERVAL = 0.12
local KILL_PAUSE = 0.12

local AIM_TIMEOUT = 2.5
local DAMAGE_TIMEOUT = 2.5
local SKIP_DURATION = 4

local ADS_SETTLE_TIME = 0.12

local enabled = false
local wasDown = false

local leftHeld = false
local rightHeld = false
local adsSince = nil

local target = nil
local targetSince = 0
local lastHealth = 0
local lastDamage = 0
local shootingSince = nil

local lastPosition = nil
local lastSample = 0
local stillSince = nil
local targetStill = false

local pauseUntil = 0
local lastRefresh = 0
local lastCoin = 0

local savedForward = nil

local zombies = {}
local skipped = {}

local function clamp(value, limit)
    return math.max(-limit, math.min(limit, value))
end

local function releaseFire()
    if leftHeld then
        mouse1release()
        leftHeld = false
    end
end

local function releaseADS()
    if rightHeld then
        mouse2release()
        rightHeld = false
    end

    adsSince = nil
end

local function releaseAll()
    releaseFire()
    releaseADS()
end

local function holdADS(now)
    if not rightHeld then
        mouse2press()
        rightHeld = true
        adsSince = now
    end
end

local function isZombie(model)
    return model.Name == "Zombie1"
        or model.Name == "Zombie2"
        or model.Name == "Zombie3"
end

local function getParts(model)
    if not model then
        return nil
    end

    local humanoid = model:FindFirstChild("Humanoid")
    local head = model:FindFirstChild("Head")
    local root = model:FindFirstChild("HumanoidRootPart")

    if not humanoid or not head or not root then
        return nil
    end

    if humanoid.Health <= 0 or root.Position.Y < -100 then
        return nil
    end

    return humanoid, head, root
end

local function refreshZombies()
    zombies = {}

    local hood = workspace:FindFirstChild("HoodLocal")

    if not hood then
        return
    end

    for _, model in ipairs(hood:GetChildren()) do
        if isZombie(model) and getParts(model) then
            table.insert(zombies, model)
        end
    end
end

local function screenError(model)
    local _, head = getParts(model)

    if not head then
        return nil
    end

    local camera = workspace.CurrentCamera

    if not camera then
        return nil
    end

    local screen, visible = WorldToScreen(head.Position)

    if not visible then
        return nil
    end

    local dx = screen.X - camera.ViewportSize.X / 2
    local dy = screen.Y - camera.ViewportSize.Y / 2

    return dx, dy, math.sqrt(dx * dx + dy * dy)
end

local function chooseTarget(now)
    local camera = workspace.CurrentCamera

    if not camera then
        return nil
    end

    local best = nil
    local bestScore = math.huge

    for _, model in ipairs(zombies) do
        if not skipped[model] or skipped[model] <= now then
            local _, _, root = getParts(model)

            if root then
                local _, _, error = screenError(model)

                if error then
                    local distance =
                        (root.Position - camera.CFrame.Position).Magnitude

                    local score = error + distance * 0.05

                    if score < bestScore then
                        bestScore = score
                        best = model
                    end
                end
            end
        end
    end

    return best
end

local function clearTarget(now, skip)
    if skip and target then
        skipped[target] = now + SKIP_DURATION
    end

    target = nil
    targetSince = 0
    lastHealth = 0
    lastDamage = 0
    shootingSince = nil

    lastPosition = nil
    lastSample = 0
    stillSince = nil
    targetStill = false

    releaseAll()
    pauseUntil = now + KILL_PAUSE
end

local function acquireTarget(now)
    local selected = chooseTarget(now)

    if not selected then
        return
    end

    local humanoid, _, root = getParts(selected)

    if not humanoid then
        return
    end

    target = selected
    targetSince = now
    lastHealth = humanoid.Health
    lastDamage = now
    shootingSince = nil

    lastPosition = root.Position
    lastSample = now
    stillSince = nil
    targetStill = false
end

local function updateStillness(now)
    local _, _, root = getParts(target)

    if not root then
        targetStill = false
        return
    end

    if now - lastSample < SAMPLE_INTERVAL then
        return
    end

    local dt = now - lastSample

    if dt <= 0 then
        return
    end

    local speed =
        (root.Position - lastPosition).Magnitude / dt

    lastPosition = root.Position
    lastSample = now

    if speed <= STILL_SPEED then
        if not stillSince then
            stillSince = now
        end

        targetStill = now - stillSince >= setting("ur_still_wait", STILL_WAIT)
    else
        stillSince = nil
        targetStill = false
    end
end

local function aimAtTarget()
    local dx, dy, error = screenError(target)

    if not error then
        return false
    end

    mousemoverel(
        clamp(dx * setting("ur_aim_speed", AIM_SPEED), MAX_STEP),
        clamp(dy * setting("ur_aim_speed", AIM_SPEED), MAX_STEP)
    )

    return error <= setting("ur_radius", SHOOT_RADIUS)
end

local function snapForward()
    if not savedForward then
        return
    end

    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local cf = camera.CFrame

    local right = savedForward:Dot(cf.RightVector)
    local up = savedForward:Dot(cf.UpVector)
    local forward = savedForward:Dot(cf.LookVector)

    local yaw = math.atan2(right, forward)
    local pitch = math.atan2(
        up,
        math.sqrt(right * right + forward * forward)
    )

    if math.abs(yaw) < RETURN_DEADZONE
        and math.abs(pitch) < RETURN_DEADZONE
    then
        return
    end

    local turnX = clamp(
        yaw * 35 * setting("ur_snap_speed", SNAP_SPEED),
        MAX_SNAP_STEP
    )

    local turnY = clamp(
        -pitch * 35 * setting("ur_snap_speed", SNAP_SPEED),
        MAX_SNAP_STEP
    )

    mousemoverel(turnX, turnY)
end

local function updateTargetHealth(now)
    local humanoid = getParts(target)

    if not humanoid then
        clearTarget(now, false)
        return
    end

    if humanoid.Health < lastHealth then
        lastDamage = now
    end

    lastHealth = humanoid.Health

    if shootingSince then
        if now - lastDamage > DAMAGE_TIMEOUT then
            clearTarget(now, true)
        end
    elseif now - targetSince > AIM_TIMEOUT then
        local _, _, error = screenError(target)

        if not error or error > setting("ur_radius", SHOOT_RADIUS) then
            clearTarget(now, true)
        end
    end
end

local function collectCoins(now)
    if now - lastCoin >= COIN_INTERVAL then
        keypress(0x45)
        task.wait(0.025)
        keyrelease(0x45)

        lastCoin = now
    end
end


local function updateAutofarm()
    local down = iskeypressed(0x75)
    if down and not wasDown then
        UI.SetValue("ur_farm", not setting("ur_farm", false))
    end
    wasDown = down
    local now = os.clock()
    local requested = setting("ur_farm", false)

    if requested ~= enabled then
        enabled = requested
        clearTarget(now, false)

        if enabled then
            local camera = workspace.CurrentCamera

            if camera then
                savedForward = camera.CFrame.LookVector
            else
                savedForward = nil
            end

            print("Autofarm ON")
        else
            savedForward = nil
            releaseAll()
            print("Autofarm OFF")
        end
    end

    if enabled and isrbxactive() then
        if now - lastRefresh >= REFRESH_INTERVAL then
            refreshZombies()
            lastRefresh = now
        end

        if setting("ur_collect", true) then collectCoins(now) end

        if target then
            if not getParts(target) then
                clearTarget(now, false)
            else
                updateTargetHealth(now)
            end
        end

        if not target and now >= pauseUntil then
            acquireTarget(now)
        end

        if target then
            updateStillness(now)

            local aligned = aimAtTarget()
            local visible = screenError(target) ~= nil

            local readyToADS =
                visible and aligned and (not setting("ur_stationary", true) or targetStill)

            if readyToADS then
                local useADS = setting("ur_ads", true)
                if useADS then holdADS(now) else releaseADS() end

                if not useADS or (adsSince
                    and now - adsSince >= ADS_SETTLE_TIME)
                then
                    if not leftHeld then
                        mouse1press()
                        leftHeld = true
                        shootingSince = now
                        lastDamage = now
                    end
                else
                    releaseFire()
                end
            else
                releaseFire()
                releaseADS()
                shootingSince = nil
            end
        else
            releaseAll()
            if setting("ur_snap", true) then snapForward() end
        end
    else
        releaseAll()
    end

end
local function updateProgress()
    local gui = player:FindFirstChild("PlayerGui")
    local tracker = gui and gui:FindFirstChild("HalloweenTracker")
    local frame = tracker and tracker:FindFirstChild("Tracker")
    local panel = frame and frame:FindFirstChild("Panel")
    local bar = panel and panel:FindFirstChild("Bar")
    local amount = bar and bar:FindFirstChild("Amount")
    local progress = amount and amount.Text
    if not progress then return end
    local current, maximum = string.match(progress, "(%d+)%s*/%s*(%d+)")
    if current and maximum then
        collected, total = tonumber(current), tonumber(maximum)
        if progress ~= lastProgress then
            lastProgress = progress
            print("Halloween Ghosts:", collected .. "/" .. total, "Remaining:", total - collected)
        end
    end
end
local function makeESP(key)
    local label = Drawing.new("Text")
    label.Text, label.Size, label.Center, label.Outline = "Ghost", 16, true, true
    label.Color, label.Visible = espColor, false
    local line = Drawing.new("Line")
    line.Color, line.Thickness, line.Visible = espColor, 1, false
    cache[key] = {label = label, line = line}
end
local function hideESP(esp)
    esp.label.Visible, esp.line.Visible = false, false
end
local function updateESP()
    local camera = workspace.CurrentCamera
    local event = workspace:FindFirstChild("HalloweenEvent")
    local folder = event and event:FindFirstChild("Ghosts")
    if not setting("ur_ghost_esp", false) or not camera or not folder then
        for _, esp in pairs(cache) do hideESP(esp) end
        return
    end
    local active = {}
    for _, ghost in ipairs(folder:GetChildren()) do
        if ghost.Name == "Ghost" then
            local key = tostring(ghost:GetAttribute("GhostId") or ghost)
            active[key] = true
            if not cache[key] then makeESP(key) end
            local esp = cache[key]
            local body = ghost:FindFirstChild("Body") or ghost:FindFirstChild("Eyes")
            if body then
                local distance = (body.Position - camera.CFrame.Position).Magnitude
                local screen, visible = WorldToScreen(body.Position)
                if visible and distance <= setting("ur_ghost_range", 1500) then
                    local label = "Ghost #" .. key
                    if setting("ur_ghost_distance", true) then
                        label = label .. string.format(" [%d studs]", math.floor(distance))
                    end
                    esp.label.Text = label
                    esp.label.Position = Vector2.new(screen.X, screen.Y - 25)
                    esp.label.Color, esp.label.Visible = espColor, true
                    if setting("ur_ghost_lines", false) then
                        esp.line.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                        esp.line.To = Vector2.new(screen.X, screen.Y)
                        esp.line.Color, esp.line.Visible = espColor, true
                    else
                        esp.line.Visible = false
                    end
                else hideESP(esp) end
            else hideESP(esp) end
        end
    end
    for key, esp in pairs(cache) do
        if not active[key] then
            esp.label:Remove()
            esp.line:Remove()
            cache[key] = nil
        end
    end
end
local lastCompensation = 0
local function updateRecoil()
    if not setting("ur_recoil", false) or not isrbxactive() or setting("ur_farm", false) then return end
    if setting("ur_recoil_firing", true) and not ismouse1pressed() then return end
    local now = os.clock()
    if now - lastCompensation < setting("ur_recoil_interval", 0.02) then return end
    lastCompensation = now
    mousemoverel(0, setting("ur_recoil_strength", 1.5))
end
local instantReloadWasEnabled = false
local function applyInstantReload(container)
    if not container then return end
    for _, item in pairs(container:GetChildren()) do
        local value = item:GetAttribute("ReloadTime")
        if type(value) == "number" then
            if originalReloadTimes[item] == nil then originalReloadTimes[item] = value end
            if value ~= 0 then item:SetAttribute("ReloadTime", 0) end
        end
    end
end
local function updateInstantReload()
    local enabled = setting("ur_instant_reload", false)
    if enabled then
        applyInstantReload(player:FindFirstChild("Backpack"))
        applyInstantReload(player.Character)
    elseif instantReloadWasEnabled then
        for item, value in pairs(originalReloadTimes) do
            pcall(function() item:SetAttribute("ReloadTime", value) end)
            originalReloadTimes[item] = nil
        end
    end
    instantReloadWasEnabled = enabled
end
local caseNextAttempt = 0
local caseAttempts = 0
local caseWasEnabled = false
local caseWarned = false
local function updateCases()
    local on = setting("ur_auto_cases", false)
    if not on then
        caseWasEnabled = false
        caseWarned = false
        return
    end
    if not caseWasEnabled then
        caseWasEnabled = true
        caseNextAttempt = 0
        print("Auto Case Opener ON")
    end
    local now = os.clock()
    if now < caseNextAttempt or not isrbxactive() then return end
    caseNextAttempt = now + math.max(5, tonumber(setting("ur_case_delay", 10)) or 10)
    local gui = player:FindFirstChild("PlayerGui")
    local cases = gui and gui:FindFirstChild("Cases")
    local menu = cases and cases:FindFirstChild("Menu")
    local panel = menu and menu:FindFirstChild("Panel")
    local button = panel and panel:FindFirstChild("Open")
    if not button then
        if not caseWarned then print("Auto Case: open the normal case shop and select a case") end
        caseWarned = true
        return
    end
    local clicked = false
    local ok = pcall(function() button:Activate() end)
    if ok then clicked = true end
    if not clicked and type(mousemoveabs) == "function" then
        local pos = button.AbsolutePosition
        if pos and pos.X and pos.Y then
            local x, y = math.floor(pos.X + 70), math.floor(pos.Y + 20)
            mousemoveabs(x, y)
            mouse1press()
            task.wait(0.05)
            mouse1release()
            clicked = true
        end
    end
    if clicked then
        caseAttempts = caseAttempts + 1
        print("Auto Case: attempt", caseAttempts)
        caseWarned = false
    elseif not caseWarned then
        print("Auto Case: Matcha cannot activate GUI buttons; mousemoveabs unavailable")
        caseWarned = true
    end
end
print("Urban Reload Hub V2.7 loaded")
while true do
    local ok, err = pcall(function()
        updateAutofarm()
        updateProgress()
        updateESP()
        updateInstantReload()
        updateRecoil()
        updateCases()
    end)
    if not ok and err ~= lastError then
        print("Hub error:", tostring(err))
        lastError = err
    end
    task.wait(0.02)
end
