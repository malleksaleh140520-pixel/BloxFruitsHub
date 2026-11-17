local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local CONFIG_DIR = "MADiumBloxFruits"
local CONFIG_FILE = CONFIG_DIR .. "/config.json"
local TOGGLE_KEY = Enum.KeyCode.Insert

local settings = {
    auto_farm = false,
    auto_quest = false,
    auto_attack = false,
    fast_attack = false,
    auto_mastery = false,
    auto_collect_fruits = false,
    esp_fruits = false,
    esp_chests = false,
    esp_players = false,
    esp_enemies = false,
    teleport_islands = false,
    movement_override = false,
    infinite_jump = false,
    auto_boss_farm = false,
    auto_raid = false,
    auto_sea_events = false,
    auto_stats = false,
    server_hop = false,
    offset_x = 0,
    offset_y = 8,
    offset_z = 0,
    farm_range = 350,
    walk_speed = 16,
    jump_power = 50,
    attack_delay = 0.15
}

local menu_open = true
local status_text = "Ready"
local esp_objects = {}
local connections = {}
local shutting_down = false
local last_farm_tick = 0
local last_collect_tick = 0
local last_esp_tick = 0

local function track(connection)
    table.insert(connections, connection)
    return connection
end

local function get_character()
    return player.Character
end

local function get_root(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function get_humanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end

local function get_enemy_folder()
    return Workspace:FindFirstChild("Enemies")
end

local function is_alive_model(model)
    local humanoid = get_humanoid(model)
    local root = get_root(model)
    return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function nearest_enemy(boss_only)
    local folder = get_enemy_folder()
    local root = get_root(get_character())
    if not folder or not root then return nil, math.huge end

    local best_target, best_distance = nil, settings.farm_range
    for _, enemy in ipairs(folder:GetChildren()) do
        local name = string.lower(enemy.Name)
        local looks_like_boss = string.find(name, "boss", 1, true) ~= nil
        if is_alive_model(enemy) and (not boss_only or looks_like_boss) then
            local enemy_root = get_root(enemy)
            local distance = (root.Position - enemy_root.Position).Magnitude
            if distance < best_distance then
                best_target, best_distance = enemy, distance
            end
        end
    end
    return best_target, best_distance
end

local function equip_tool()
    local character = get_character()
    local backpack = player:FindFirstChildOfClass("Backpack")
    if not character or not backpack then return nil end

    local tool = character:FindFirstChildOfClass("Tool")
    if not tool then
        tool = backpack:FindFirstChildOfClass("Tool")
        local humanoid = get_humanoid(character)
        if tool and humanoid then humanoid:EquipTool(tool) end
    end
    return tool
end

local function move_to_model(model, x, y, z)
    local root = get_root(get_character())
    local target_root = get_root(model)
    if not root or not target_root then return false end
    root.CFrame = target_root.CFrame * CFrame.new(x, y, z)
    return true
end

local function find_fruit()
    local root = get_root(get_character())
    if not root then return nil end

    local closest, closest_distance = nil, math.huge
    for _, object in ipairs(Workspace:GetChildren()) do
        local name = string.lower(object.Name)
        if string.find(name, "fruit", 1, true) then
            local part = object:IsA("BasePart") and object or get_root(object)
            if part then
                local distance = (root.Position - part.Position).Magnitude
                if distance < closest_distance then
                    closest, closest_distance = object, distance
                end
            end
        end
    end
    return closest
end

local function clear_esp()
    for key, object in pairs(esp_objects) do
        if object then object:Destroy() end
        esp_objects[key] = nil
    end
end

local function add_highlight(target, color, key)
    if not target or esp_objects[key] then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "MADium_" .. key
    highlight.Adornee = target
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(235, 220, 255)
    highlight.FillTransparency = 0.68
    highlight.OutlineTransparency = 0.08
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = Workspace
    esp_objects[key] = highlight
end

local function refresh_esp()
    local wanted = {}

    if settings.esp_fruits then
        for _, object in ipairs(Workspace:GetChildren()) do
            if string.find(string.lower(object.Name), "fruit", 1, true) then
                local key = "fruit_" .. object:GetFullName()
                wanted[key] = true
                add_highlight(object, Color3.fromRGB(190, 105, 255), key)
            end
        end
    end

    if settings.esp_enemies then
        local folder = get_enemy_folder()
        if folder then
            for _, enemy in ipairs(folder:GetChildren()) do
                local key = "enemy_" .. enemy:GetFullName()
                wanted[key] = true
                add_highlight(enemy, Color3.fromRGB(255, 90, 110), key)
            end
        end
    end

    if settings.esp_players then
        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= player and target.Character then
                local key = "player_" .. tostring(target.UserId)
                wanted[key] = true
                add_highlight(target.Character, Color3.fromRGB(100, 175, 255), key)
            end
        end
    end

    if settings.esp_chests then
        for _, object in ipairs(Workspace:GetDescendants()) do
            if object:IsA("Model") and string.find(string.lower(object.Name), "chest", 1, true) then
                local key = "chest_" .. object:GetFullName()
                wanted[key] = true
                add_highlight(object, Color3.fromRGB(255, 205, 90), key)
            end
        end
    end

    for key, highlight in pairs(esp_objects) do
        if not wanted[key] then
            if highlight then highlight:Destroy() end
            esp_objects[key] = nil
        end
    end
end

local function save_config()
    local ok, err = pcall(function()
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(CONFIG_FILE, HttpService:JSONEncode(settings))
    end)
    status_text = ok and "Settings saved" or ("Save failed: " .. tostring(err))
end

local function load_config()
    local ok, result = pcall(function()
        if not isfile(CONFIG_FILE) then error("No saved config") end
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(result) ~= "table" then
        status_text = "Load failed: " .. tostring(result)
        return
    end

    for key, default_value in pairs(settings) do
        if type(result[key]) == type(default_value) then
            settings[key] = result[key]
        end
    end
    status_text = "Settings loaded"
end

local function reset_config()
    for key, value in pairs({
        auto_farm = false, auto_quest = false, auto_attack = false,
        fast_attack = false, auto_mastery = false, auto_collect_fruits = false,
        esp_fruits = false, esp_chests = false, esp_players = false,
        esp_enemies = false, teleport_islands = false, movement_override = false,
        infinite_jump = false, auto_boss_farm = false, auto_raid = false,
        auto_sea_events = false, auto_stats = false, server_hop = false,
        offset_x = 0, offset_y = 8, offset_z = 0, farm_range = 350,
        walk_speed = 16, jump_power = 50, attack_delay = 0.15
    }) do
        settings[key] = value
    end
    clear_esp()
    status_text = "Settings reset"
end

local function draw_checkbox(label, key)
    local value = ImGui.Checkbox(label, settings[key])
    if type(value) == "boolean" then settings[key] = value end
end

local function draw_slider(label, key, minimum, maximum, format)
    local value = ImGui.SliderFloat(label, settings[key], minimum, maximum, format or "%.1f")
    if type(value) == "number" then settings[key] = value end
end

local function draw_unwired(label, key, explanation)
    draw_checkbox(label, key)
    ImGui.TextWrapped("Integration status: not connected. " .. explanation)
end

local function draw_farm_tab()
    ImGui.Text("THIRD SEA | LEVEL 2800 | DOUGH")
    ImGui.Separator()
    draw_checkbox("Auto Farm Level", "auto_farm")
    draw_checkbox("Auto Attack", "auto_attack")
    draw_checkbox("Fast Attack", "fast_attack")
    draw_checkbox("Auto Boss Farm", "auto_boss_farm")
    draw_checkbox("Auto Mastery", "auto_mastery")
    draw_checkbox("Auto Quest", "auto_quest")

    draw_slider("Attack interval (seconds)", "attack_delay", 0.08, 0.8, "%.2f")
    draw_slider("Farm detection range", "farm_range", 50, 1500, "%.0f")

    ImGui.Separator()
    ImGui.Text("AUTO FARM POSITION OFFSET")
    draw_slider("X offset", "offset_x", -60, 60, "%.1f")
    draw_slider("Y offset", "offset_y", -20, 80, "%.1f")
    draw_slider("Z offset", "offset_z", -60, 60, "%.1f")

    if ImGui.Button("Reset X / Y / Z") then
        settings.offset_x, settings.offset_y, settings.offset_z = 0, 8, 0
    end
    ImGui.SameLine()
    if ImGui.Button("Move to nearest enemy") then
        local enemy = nearest_enemy(false)
        status_text = enemy and (move_to_model(enemy, settings.offset_x, settings.offset_y, settings.offset_z) and "Moved to " .. enemy.Name or "Character not ready") or "No enemy in range"
    end

    local target, distance = nearest_enemy(false)
    ImGui.Separator()
    ImGui.Text("Nearest target: " .. (target and target.Name or "None"))
    ImGui.Text("Distance: " .. (distance < math.huge and string.format("%.1f studs", distance) or "N/A"))
end

local function draw_esp_tab()
    ImGui.Text("VISUALS")
    ImGui.Separator()
    draw_checkbox("Fruit ESP", "esp_fruits")
    draw_checkbox("Chest ESP", "esp_chests")
    draw_checkbox("Player ESP", "esp_players")
    draw_checkbox("Enemy ESP", "esp_enemies")
    if ImGui.Button("Refresh ESP") then refresh_esp() end
    ImGui.SameLine()
    if ImGui.Button("Clear ESP") then clear_esp() end
    draw_checkbox("Auto Collect Fruits", "auto_collect_fruits")
    ImGui.TextWrapped("ESP highlights objects currently visible to the client. Fruit pickup behavior depends on the game's current pickup interaction.")
end

local function draw_movement_tab()
    ImGui.Text("MOVEMENT")
    ImGui.Separator()
    draw_checkbox("Enable WalkSpeed / JumpPower", "movement_override")
    draw_slider("WalkSpeed", "walk_speed", 16, 150, "%.0f")
    draw_slider("JumpPower", "jump_power", 50, 200, "%.0f")
    draw_checkbox("Infinite Jump", "infinite_jump")
    if ImGui.Button("Reset movement") then
        settings.walk_speed, settings.jump_power = 16, 50
        settings.movement_override, settings.infinite_jump = false, false
    end
end

local function draw_travel_tab()
    ImGui.Text("TRAVEL")
    ImGui.Separator()
    if ImGui.Button("Move to nearest enemy") then
        local enemy = nearest_enemy(false)
        status_text = enemy and (move_to_model(enemy, 0, 8, 0) and "Moved to " .. enemy.Name or "Character not ready") or "No enemy in range"
    end
    if ImGui.Button("Move to nearest fruit") then
        local fruit = find_fruit()
        local root = get_root(get_character())
        local fruit_root = fruit and (fruit:IsA("BasePart") and fruit or get_root(fruit))
        if root and fruit_root then
            root.CFrame = fruit_root.CFrame * CFrame.new(0, 3, 0)
            status_text = "Moved to nearest visible fruit"
        else
            status_text = "No visible fruit found"
        end
    end
    if ImGui.Button("Rejoin current server") then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
    end
    draw_unwired("Teleport between islands", "teleport_islands", "Island destination coordinates and route rules have not been configured.")
    draw_unwired("Server Hop", "server_hop", "A server-list query and filtering method are not configured.")
    ImGui.Text("Status: " .. status_text)
end

local function draw_events_tab()
    ImGui.Text("RAIDS / SEA EVENTS")
    ImGui.Separator()
    draw_unwired("Auto Raid", "auto_raid", "Raid entry, chip purchase and stage progression need current game interaction mappings.")
    draw_unwired("Auto Sea Events", "auto_sea_events", "Sea event detection and interaction mappings are not connected.")
    ImGui.Text("Event automation is not active in this build.")
end

local function draw_stats_tab()
    ImGui.Text("STATS")
    ImGui.Separator()
    draw_unwired("Auto Stats", "auto_stats", "Stat allocation requires a verified in-game allocation interface and selected stat priorities.")
    ImGui.Text("Profile: Third Sea | Level 2800 | Dough")
end

local function draw_settings_tab()
    ImGui.Text("CONFIGURATION")
    ImGui.Separator()
    if ImGui.Button("Save settings") then save_config() end
    ImGui.SameLine()
    if ImGui.Button("Load settings") then load_config() end
    if ImGui.Button("Reset all settings") then reset_config() end
    ImGui.Separator()
    ImGui.Text("Menu key: INSERT")
    ImGui.Text("Theme base: Dark (purple accent pending verified color constants)")
    ImGui.Text("Status: " .. status_text)
    ImGui.TextWrapped("Only features explicitly connected to client-visible game objects are active. Unconnected game automation is labeled in its tab.")
end

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or shutting_down then return end
    if input.KeyCode == TOGGLE_KEY then
        menu_open = not menu_open
    end
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space and settings.infinite_jump then
        local humanoid = get_humanoid(get_character())
        if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

local render_connection = ImGui.OnRender(function()
    if shutting_down or not menu_open then return end

    ImGui.StyleColorsDark()
    ImGui.SetNextWindowSize(Vector2.new(700, 610))
    local visible = ImGui.Begin("MADium | Blox Fruits Hub", true)

    if visible then
        ImGui.Text("MADium ULTIMATE HUB")
        ImGui.Text("THIRD SEA  |  LEVEL 2800  |  DOUGH")
        ImGui.Separator()

        if ImGui.BeginTabBar("MADium_Main_Tabs") then
            if ImGui.BeginTabItem("Farm") then draw_farm_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("ESP") then draw_esp_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("Movement") then draw_movement_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("Travel") then draw_travel_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("Raids / Events") then draw_events_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("Stats") then draw_stats_tab(); ImGui.EndTabItem() end
            if ImGui.BeginTabItem("Settings") then draw_settings_tab(); ImGui.EndTabItem() end
            ImGui.EndTabBar()
        end
    end

    ImGui.End()
end)

track(RunService.Heartbeat:Connect(function()
    if shutting_down then return end

    local character = get_character()
    local root = get_root(character)
    local humanoid = get_humanoid(character)

    if humanoid and settings.movement_override then
        humanoid.WalkSpeed = settings.walk_speed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = settings.jump_power
    end

    local now = os.clock()
    if now - last_farm_tick >= settings.attack_delay then
        last_farm_tick = now

        local boss_mode = settings.auto_boss_farm and not settings.auto_farm
        local target = (settings.auto_farm or settings.auto_boss_farm) and nearest_enemy(boss_mode) or nil
        if target and root then
            if settings.auto_farm or settings.auto_boss_farm then
                move_to_model(target, settings.offset_x, settings.offset_y, settings.offset_z)
            end

            if settings.auto_attack or settings.fast_attack or settings.auto_mastery then
                local tool = equip_tool()
                if tool then pcall(function() tool:Activate() end) end
            end
        end
    end

    if settings.auto_collect_fruits and now - last_collect_tick > 1.0 then
        last_collect_tick = now
        local fruit = find_fruit()
        local fruit_root = fruit and (fruit:IsA("BasePart") and fruit or get_root(fruit))
        if root and fruit_root then
            root.CFrame = fruit_root.CFrame * CFrame.new(0, 3, 0)
            status_text = "Moved toward visible fruit"
        end
    end

    if now - last_esp_tick > 1.2 then
        last_esp_tick = now
        if settings.esp_fruits or settings.esp_chests or settings.esp_players or settings.esp_enemies then
            pcall(refresh_esp)
        elseif next(esp_objects) then
            clear_esp()
        end
    end
end))

track(player.CharacterAdded:Connect(function()
    task.wait(1)
    status_text = "Character respawned"
end))

_G.MADiumBloxFruitsShutdown = function()
    shutting_down = true
    clear_esp()
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    if render_connection then
        pcall(function() render_connection:Disconnect() end)
    end
    status_text = "Stopped"
end

status_text = "Loaded. Press INSERT to hide/show the menu."
