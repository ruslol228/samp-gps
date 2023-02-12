require "lib.moonloader"

local imgui = require "imgui"
local memory = require "memory"
local encoding = require "encoding"
encoding.default = 'CP1251'
u8 = encoding.UTF8



-- модуль для работы с json на чистом lua 

local json = require "jumper.json"

-- модуль поиска пути не мой не буду выебываться 
-- (хотя я пытался создать с нуля свое но у меня медленно работало)
-- ссылка на Jumper: https://github.com/Yonaba/Jumper

local Grid = require ("jumper.grid")

local Pathfinder = require ("jumper.pathfinder")

window_state = imgui.ImBool(false)
gui_win_state = imgui.ImBool(false)



function main()
    repeat wait(0) until isSampAvailable()

    -- загрузка изображений

    map_img = imgui.CreateTextureFromFile("moonloader/jumper/map.jpg")
    cursor_img = imgui.CreateTextureFromFile("moonloader/jumper/cursor.png")


    gui_bg = imgui.CreateTextureFromFile("moonloader/jumper/gui/bg.png")
    gui_exit = imgui.CreateTextureFromFile("moonloader/jumper/gui/exit.png")


    -- для модуля поиска пути (jumper) нужна карта в виде массива,
    -- где 1 - это дорога по которой можно ехать, 0 - это препядствия
    -- так как массив большой (500 на 500), я выгружаю его с файла

    map = json.parse((io.open(getWorkingDirectory() .. "\\jumper\\map.txt", "r"):read("*a")))
    

    -- got_target: будет использоваться как переключатель для состояния цели

    got_target = false

    -- list: непосредственно сам массив в котором будет путь от игрока до цели
    
    list = {}

    -- короче тут я пытался убирать курсор при активации скирпта но оно что-то не пашет хз
    
    showCursor(false)




    if not doesFileExist(getWorkingDirectory() .. "\\jumper\\gui\\gui.json") then
        -- вот эти 4 страшные перменные лишь для корректной работы координат цели, не обращайте внимания
        RadarX = memory.getfloat(0x858A10)
        RadarY =  memory.getfloat(0x866B70)

        RadarWidth = memory.getfloat(0x866B78)
        RadarHeight = memory.getfloat(0x866B74)

        RadarSize = RadarHeight > RadarWidth and RadarHeight or RadarWidth


        f = io.open(getWorkingDirectory() .. "\\jumper\\gui\\gui.json", "w+")
        f:write("[" .. tostring(RadarSize) .. ", " .. tostring(RadarX) ..  ", " ..tostring(RadarY) .."]")
        f:close()
    else
        f = io.open(getWorkingDirectory() .. "\\jumper\\gui\\gui.json", "r")

        RadarList = json.parse(f:read("a"))

        RadarSize = RadarList[1]
        RadarX = RadarList[2]
        RadarY = RadarList[3]

        f:close()
    end

    
    sampRegisterChatCommand("gpsset", function () gui_win_state.v = not gui_win_state.v end)


    local oldTres, oldTx, oldTy, oldTz

    while true do
        wait(0)

        -- активация на М
        
        if isKeyJustPressed(VK_M) and not sampIsChatInputActive() and not sampIsDialogActive() and not isGamePaused() then
            window_state.v = not window_state.v
        end
        imgui.Process = window_state.v or gui_win_state.v


        -- Tres, Tx, Ty, Tz: корды локальной цели, которую сам игрок ставит на карте

        local Tres, Tx, Ty, Tz = getTargetBlipCoordinates()
        
        -- тут технические шоколадки небольшие, чтобы не багалось

        if oldTres then
            if oldTx ~= Tx and oldTy ~= Ty and oldTz ~= Tz then
                got_target = false
            end
        end
        
        oldTres, oldTx, oldTy, oldTz = Tres, Tx, Ty, Tz




        -- Px, Py, Pz: корды игрока 

        local Px, Py, Pz = getCharCoordinates(PLAYER_PED)
            
        -- коректировка небольшая, а то getCharCoordinates как то по странному возвращает корды

        if Px < 0 then
            Px = 3000 - math.abs(Px)
        else
            Px = 3000 + Px
        end

        if Py < 0 then
            Py = 3000 + math.abs(Py)
        else
            Py = 3000 - Py
        end


        -- здесь короче чтобы путь очищался когда игрок едет по нему,
        -- или наоборот искался новый путь если игрок вдалеке от первой точки путя

        if list[1] then
            if (math.abs((Px/12) - list[1][1]) <= 1.5 and math.abs((Py/12) - list[1][2]) < 5) or
            (math.abs((Px/12) - list[1][1]) < 5 and math.abs((Py/12) - list[1][2]) <= 1.5)
            then
                table.remove(list, 1)
            end
            if math.abs((Px/12) - list[1][1]) >= 5 and math.abs((Py/12) - list[1][2]) >= 5 then
                got_target = false
            end
        end


        -- дальше идет условие которые чекает какой чекпоинт сейчас активен
        -- и ищет путь к нему


        if (Tres or Bres) and not got_target then
            got_target = true

            
            if (Bres ~= nil and Bres) and not Tres then
                


                lua_thread.create(function ()
                    list = get_path({math.ceil(Px / 12), math.ceil(Py / 12)}, {math.ceil(BX/12), math.ceil(BY/12)}, map)   
                
                end)

            elseif Tres then
                if Tx < 0 then
                    Tx = 3000 - math.abs(Tx)
                else
                    Tx = 3000 + Tx
                end
        
                if Ty < 0 then
                    Ty = 3000 + math.abs(Ty)
                else
                    Ty = 3000 - Ty
                end                


        

                lua_thread.create(function ()
                    list = get_path({math.ceil(Px / 12), math.ceil(Py / 12)}, {math.ceil(Tx/12), math.ceil(Ty/12)}, map)   
                
                end)

            end

        -- если ни одной цели нет то очищаем путь и по новой

        elseif not Bres and not Tres then
            got_target = false
            list = {}
        end



    end
end



-- дальше сама функа поиска пути с моими корректировками

function get_path(start_point, end_point, map)


    -- is_trapped локальная функа которая проверяет на дороге ли цель,
    -- если цель не на дороге, то проводит дополнительную дорогу к ней
    

	local function is_trapped(map, x)

		map[x[1]][x[2]] = 1

		local ops = {
			{0, -1}, {0, 1}, {-1, 0}, {1, 0},
			{-1, -1}, {-1, 1}, {1, 1}, {1, -1}
		}
		local isTrapped = true
		for _, v in ipairs(ops) do
			if (x[1] + v[1]) <= #map and (x[1] + v[1]) >= 1 and (x[2] + v[2]) <= #map[1] and (x[2] + v[2]) >= 1 then
				if map[x[1] + v[1]][x[2] + v[2]] == 1 then
					isTrapped = false
				end
			end
			--map[x[1] + v[1]][x[2] + v[2]] = 1
		end


		local ops_ratio = 0

		while isTrapped do
			local ops = {
				{0, -1-ops_ratio}, {0, 1+ops_ratio}, {-1-ops_ratio, 0}, {1+ops_ratio, 0},
				{-1-ops_ratio, -1-ops_ratio}, {-1-ops_ratio, 1+ops_ratio},
				{1+ops_ratio, 1+ops_ratio}, {1+ops_ratio, -1-ops_ratio}
			}
			local skips = 0
			for _, v in ipairs(ops) do
				if (x[1] + v[1]) <= #map and (x[1] + v[1]) >= 1 and (x[2] + v[2]) <= #map[1] and (x[2] + v[2]) >= 1 then
					if map[x[1] + v[1]][x[2] + v[2]] == 1 then
						isTrapped = false
						break
					else
						map[x[1] + v[1]][x[2] + v[2]] = 1
					end
				else
					skips = skips + 1
				end
			end
			if skips == 8 then
				break
			end
			ops_ratio = ops_ratio + 1
		end
	end

	

    -- наша мапа

	local map = map or json.parse(io.open("map.txt", "r"):read("*a"))


    -- проверка на дороге ли игрок и цель

	is_trapped(map, {start_point[2], start_point[1]})
	is_trapped(map, {end_point[2], end_point[1]})


    -- подключение модуля поиска пути

	local grid = Grid(map)


	local myFinder = Pathfinder(grid, 'ASTAR', 1)



	local startx, starty = start_point[1], start_point[2]
	local endx, endy = end_point[1], end_point[2]


	local path = myFinder:getPath(startx, starty, endx, endy)

	local result_path = {}


	if path then
		for node, count in path:nodes() do
			table.insert(result_path, {node:getX(), node:getY()})
		end
	end

	return result_path

end


-- тут пару функций для удобной работы в дальнейшем
-- rotateVector поворот вектора, нужен будет скоро для ебли в имгуи

function rotateVector(vec, ang)
    x = vec[1] * math.cos(ang) - vec[2] * math.sin(ang);
    y = vec[1] * math.sin(ang) + vec[2] * math.cos(ang);
    return {x, y}
  end

-- returnAngle получение угла поворота камеры, опять же для имгуи

function returnAngle()
    local camCoordX, camCoordY, camCoordZ = getActiveCameraCoordinates()
    local targetCamX, targetCamY, targetCamZ = getActiveCameraPointAt()
    return getHeadingFromVector2d(targetCamX - camCoordX, targetCamY - camCoordY)
end




-- корректировка темы для имгуи

function theme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    style.WindowPadding = imgui.ImVec2(0, 0)
    style.WindowRounding = 0
    style.ChildWindowRounding = 15
    style.FramePadding = imgui.ImVec2(0, 0)
    style.FrameRounding = 3.0
    style.ItemSpacing = imgui.ImVec2(0, 0)
    style.ItemInnerSpacing = imgui.ImVec2(0, 0)
    style.IndentSpacing = 21
    style.ScrollbarSize = 10.0
    style.ScrollbarRounding = 13
    style.GrabMinSize = 8
    style.GrabRounding = 1
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)


    colors[clr.Text] = ImVec4(0.860, 0.930, 0.890, 0.78)
    colors[clr.TextDisabled] = ImVec4(0.860, 0.930, 0.890, 0.28)
    colors[clr.Text]                 = ImVec4(1, 1, 1, 1)
    colors[clr.TextDisabled]         = ImVec4(0.36, 0.42, 0.47, 1.00)
    colors[clr.WindowBg]             = ImVec4(111/255, 138/255, 168/255, 1)
    colors[clr.ChildWindowBg]        = ImVec4(0.15, 0.18, 0.22, 1.00)
    colors[clr.PopupBg]              = ImVec4(0.08, 0.08, 0.08, 0.94)
    colors[clr.Border]               = ImVec4(0.43, 0.43, 0.50, 0.50)
    colors[clr.BorderShadow]         = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.FrameBg]              = ImVec4(0.20, 0.25, 0.29, 1.00)
    colors[clr.FrameBgHovered]       = ImVec4(0.12, 0.20, 0.28, 1.00)
    colors[clr.FrameBgActive]        = ImVec4(0.09, 0.12, 0.14, 1.00)
    colors[clr.TitleBg]              = ImVec4(0.09, 0.12, 0.14, 0.65)
    colors[clr.TitleBgActive]        = ImVec4(0.11, 0.30, 0.59, 1.00)
    colors[clr.TitleBgCollapsed]     = ImVec4(0.00, 0.00, 0.00, 0.51)
    colors[clr.MenuBarBg]            = ImVec4(0.15, 0.18, 0.22, 1.00)
    colors[clr.ScrollbarBg]          = ImVec4(0.02, 0.02, 0.02, 0.39)
    colors[clr.ScrollbarGrab]        = ImVec4(0.20, 0.25, 0.29, 1.00)
    colors[clr.ScrollbarGrabHovered] = ImVec4(0.18, 0.22, 0.25, 1.00)
    colors[clr.ScrollbarGrabActive]  = ImVec4(0.09, 0.21, 0.31, 1.00)
    colors[clr.ComboBg]              = ImVec4(0.20, 0.25, 0.29, 1.00)
    colors[clr.CheckMark]            = ImVec4(0.28, 0.56, 1.00, 1.00)
    colors[clr.SliderGrab]           = ImVec4(0.28, 0.56, 1.00, 1.00)
    colors[clr.SliderGrabActive]     = ImVec4(0.37, 0.61, 1.00, 1.00)
    colors[clr.Button]               = ImVec4(0.06, 0.53, 0.98, 1.00)
    colors[clr.ButtonHovered]        = ImVec4(0.28, 0.56, 1.00, 1.00)
    colors[clr.ButtonActive]         = ImVec4(0.06, 0.53, 0.98, 1.00)
    colors[clr.Header]               = ImVec4(0.20, 0.25, 0.29, 0.55)
    colors[clr.HeaderHovered]        = ImVec4(0.26, 0.59, 0.98, 0.80)
    colors[clr.HeaderActive]         = ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[clr.Separator]            = ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[clr.SeparatorHovered]     = ImVec4(0.60, 0.60, 0.70, 1.00)
    colors[clr.SeparatorActive]      = ImVec4(0.70, 0.70, 0.90, 1.00)
    colors[clr.ResizeGrip]           = ImVec4(0.26, 0.59, 0.98, 0.25)
    colors[clr.ResizeGripHovered]    = ImVec4(0.26, 0.59, 0.98, 0.67)
    colors[clr.ResizeGripActive]     = ImVec4(0.06, 0.05, 0.07, 1.00)
    colors[clr.CloseButton]          = ImVec4(0.40, 0.39, 0.38, 0.16)
    colors[clr.CloseButtonHovered]   = ImVec4(0.40, 0.39, 0.38, 0.39)
    colors[clr.CloseButtonActive]    = ImVec4(0.40, 0.39, 0.38, 1.00)
    colors[clr.PlotLines]            = ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[clr.PlotLinesHovered]     = ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[clr.PlotHistogram]        = ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[clr.PlotHistogramHovered] = ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[clr.TextSelectedBg]       = ImVec4(0.25, 1.00, 0.00, 0.43)
    colors[clr.ModalWindowDarkening] = ImVec4(1.00, 0.98, 0.95, 0.73)
end
theme()





-- дальше гениальная функа челов с бласта чтобы поворачивать картинку

function ImRotate(v, cos_a, sin_a) return imgui.ImVec2(v.x * cos_a - v.y * sin_a, v.x * sin_a + v.y * cos_a); end
function calcAddImVec2(l, r) return imgui.ImVec2(l.x + r.x, l.y + r.y) end

function ImageRotated(tex_id, center, size, angle, color)
   local color = color or 0xFFFFFFFF
   local drawlist = imgui.GetWindowDrawList()
   local cos_a = math.cos(angle)
   local sin_a = math.sin(angle)
   local pos = {
      calcAddImVec2(center, ImRotate(imgui.ImVec2(-size.x * 0.5, -size.y * 0.5), cos_a, sin_a)),
      calcAddImVec2(center, ImRotate(imgui.ImVec2(size.x * 0.5, -size.y * 0.5), cos_a, sin_a)),
      calcAddImVec2(center, ImRotate(imgui.ImVec2(size.x * 0.5, size.y * 0.5), cos_a, sin_a)),
      calcAddImVec2(center, ImRotate(imgui.ImVec2(-size.x * 0.5, size.y * 0.5), cos_a, sin_a))
    }
    local uvs =
    {
      imgui.ImVec2(0.0, 0.0),
      imgui.ImVec2(1.0, 0.0),
      imgui.ImVec2(1.0, 1.0),
      imgui.ImVec2(0.0, 1.0)
    }
    drawlist:AddImageQuad(tex_id, pos[1], pos[2], pos[3], pos[4], uvs[1], uvs[2], uvs[3], uvs[4], color)
end



-- тут тоже функа с бласта, которую я подправил, она ловит серверную метку

function onReceiveRpc(int,bit)

    if int == 38 then -- SetRaceCheckpoint(Гоночный checkpoint)
        
        local typeRace = raknetBitStreamReadInt8(bit)

        -- BX, BY, BZ: корды серверной метки

        BX = raknetBitStreamReadFloat(bit)
        BY = raknetBitStreamReadFloat(bit)
        local BZ = raknetBitStreamReadFloat(bit)
        local nextX = raknetBitStreamReadFloat(bit)
        local nextY = raknetBitStreamReadFloat(bit)
        local nextZ = raknetBitStreamReadFloat(bit)
        local Bradius = raknetBitStreamReadFloat(bit)

        if BX < 0 then
            BX = 3000 - math.abs(BX)
        else
            BX = 3000 + BX
        end

        if BY < 0 then
            BY = 3000 + math.abs(BY)
        else
            BY = 3000 - BY
        end
        Bres = true

    elseif int == 107 then -- Если SetCheckpoint(Обычный checkpoint)
        -- BX, BY, BZ: корды серверной метки

        local BX = raknetBitStreamReadFloat(bit)
        local BY = raknetBitStreamReadFloat(bit)
        local BZ = raknetBitStreamReadFloat(bit)
        local Brdus = raknetBitStreamReadFloat(bit)
        if BX < 0 then
            BX = 3000 - math.abs(BX)
        else
            BX = 3000 + BX
        end

        if BY < 0 then
            BY = 3000 + math.abs(BY)
        else
            BY = 3000 - BY
        end
        Bres = true
    elseif int == 39 then
        Bres = false
    end
end



function imgui.MaterialSlider(id, width, max_value, value, color, bg_color)
    local function bringFloatTo(from, to, start_time, duration)
        local timer = os.clock() - start_time
        if timer >= 0.00 and timer <= duration then
            local count = timer / (duration / 100)
            return from + (count * (to - from) / 100), true
        end
        return (timer > duration) and to or from, false
    end
    if UI_MATERIALSLIDER == nil then UI_MATERIALSLIDER = {} end
    if not UI_MATERIALSLIDER[id] then UI_MATERIALSLIDER[id] = {height = width / 12, curr_width = 0, clicked = nil, c_pos_y = nil, c_pos_y_old = nil, c_pos_x = imgui.GetCursorPos().x + imgui.GetWindowPos().x, text = nil, hovered = {nil, nil}} end
    local pool = UI_MATERIALSLIDER[id]
    if max_value ~= nil and value ~= nil and pool["clicked"] == nil then
        pool["curr_width"] = width * (value / (max_value + 1))
        pool["text"] = tostring(value)
    end
    if pool["c_pos_y"] == nil then pool["c_pos_y"] = imgui.GetCursorPos().y + (pool["height"] / 2) end
    if pool["c_pos_y_old"] == nil then pool["c_pos_y_old"] = pool["c_pos_y"] end
    imgui.SetCursorPosY(pool["c_pos_y"])
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, pool["height"])
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(0, 0, 0, 0))
    local draw_list = imgui.GetWindowDrawList()
    draw_list:AddRectFilled(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x, imgui.GetCursorPos().y + imgui.GetWindowPos().y - imgui.GetScrollY()), imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + width, imgui.GetCursorPos().y + imgui.GetWindowPos().y + pool["height"] - imgui.GetScrollY()), imgui.GetColorU32(bg_color or imgui.GetStyle().Colors[imgui.Col.TextDisabled]), pool["height"] / 2)
    imgui.BeginChild("##" .. id, imgui.ImVec2(width, pool["height"]))
    if pool["curr_width"] < pool["height"] / 2 then
        draw_list:PathArcTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + (pool["height"] / 2), imgui.GetCursorPos().y + imgui.GetWindowPos().y + (pool["height"] / 2) - imgui.GetScrollY()), pool["height"] / 2, math.acos(-(((pool["height"] / 2) - pool["curr_width"]) / (pool["height"] / 2))), math.acos(((pool["height"] / 2) - pool["curr_width"]) / (pool["height"] / 2)) + 3.141)
        draw_list:PathFillConvex(imgui.GetColorU32(color or imgui.GetStyle().Colors[imgui.Col.ButtonActive]))
        draw_list:PathClear()
    else
        draw_list:AddRectFilled(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x, imgui.GetCursorPos().y + imgui.GetWindowPos().y - imgui.GetScrollY()), imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + pool["curr_width"], imgui.GetCursorPos().y + imgui.GetWindowPos().y + pool["height"] - imgui.GetScrollY()), imgui.GetColorU32(color or imgui.GetStyle().Colors[imgui.Col.ButtonActive]), pool["height"] / 2)
    end
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.PopStyleVar()
    if imgui.IsItemClicked() then pool["clicked"] = true end
    if imgui.IsItemHovered() then
        if pool["hovered"][1] == nil then pool["hovered"][1] = os.clock() end
        pool["hovered"][2] = nil
    else
        if pool["hovered"][2] == nil then pool["hovered"][2] = os.clock() end
        pool["hovered"][1] = nil
    end
    if pool["hovered"][1] ~= nil then
        pool["height"] = bringFloatTo(pool["height"], width / 8, pool["hovered"][1], 0.3)
        pool["c_pos_y"] = bringFloatTo(pool["c_pos_y"], pool["c_pos_y_old"] - ((((width/8) - (width/16)) / 2) * 0.5), pool["hovered"][1], 0.3)
    elseif pool["hovered"][2] ~= nil then
        pool["height"] = bringFloatTo(pool["height"], width / 12, pool["hovered"][2], 0.3)
        pool["c_pos_y"] = bringFloatTo(pool["c_pos_y"], pool["c_pos_y_old"], pool["hovered"][2], 0.3)
    end
    if imgui.IsMouseDown(0) and pool["clicked"] then
        if imgui.GetMousePos().x - pool["c_pos_x"] > width then pool["curr_width"] = width
        elseif imgui.GetMousePos().x - pool["c_pos_x"] < 0 then pool["curr_width"] = 0
        else pool["curr_width"] = imgui.GetMousePos().x - pool["c_pos_x"] end
        if max_value ~= nil and max_value > 1 then
            local nearest = nil
            local min_dist = nil
            for i = 0, max_value do
                if nearest == nil then nearest = i end
                if min_dist == nil then min_dist = math.abs((i * (width / max_value)) - pool["curr_width"]) end
                if math.abs((i * (width / max_value)) - pool["curr_width"]) < min_dist then
                    min_dist = math.abs((i * (width / max_value)) - pool["curr_width"])
                    nearest = i
                end
            end
            pool["curr_width"] = nearest * (width / max_value)
            pool["text"] = tostring(nearest)
        end
    elseif not imgui.IsMouseDown(0) and pool["clicked"] then pool["clicked"] = false end
    return pool["text"] or pool["curr_width"]
end

function imgui.RippleButton(text, size, duration, rounding, parent_color)

        
    local function CenterTextFor2Dims(text)
        local width = imgui.GetWindowWidth()
        local calc = imgui.CalcTextSize(text)

        local height = imgui.GetWindowHeight()

        imgui.SetCursorPosX( width / 2 - calc.x / 2 )
        imgui.SetCursorPosY(height / 2 - calc.y / 2)
        imgui.Text(text)
    end


    local function bringVec4To(from, to, start_time, duration)
        local timer = os.clock() - start_time
        if timer >= 0.00 and timer <= duration then
            local count = timer / (duration / 100)
            return imgui.ImVec4(
                from.x + (count * (to.x - from.x) / 100),
                from.y + (count * (to.y - from.y) / 100),
                from.z + (count * (to.z - from.z) / 100),
                from.w + (count * (to.w - from.w) / 100)
            ), true
        end
        return (timer > duration) and to or from, false
    end


    if UI_RIPPLEBUTTON == nil then
        UI_RIPPLEBUTTON = {}
    end
    if not UI_RIPPLEBUTTON[text] then
        UI_RIPPLEBUTTON[text] = {animation = nil, radius = 5, mouse_coor = nil, time = nil, color = nil}
    end
    local pool = UI_RIPPLEBUTTON[text]
    local radius
    
    if rounding == nil then
        rounding = 0
    end

    if parent_color == nil then
        parent_color = imgui.GetStyle().Colors[imgui.Col.WindowBg]
    end    

    if pool["color"] == nil then
        pool["color"] = imgui.ImVec4(parent_color.x, parent_color.y, parent_color.z, parent_color.w)
    end

    if size == nil then
        local text_size = imgui.CalcTextSize(text:match("(.+)##.+") or text)
        size = imgui.ImVec2(text_size.x + 20, text_size.y + 20)
    end

    if size.x > size.y then
        radius = size.x
        if duration == nil then duration = size.x / 64 end
    else
        radius = size.y
        if duration == nil then duration = size.y / 64 end
    end

    imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.GetStyle().Colors[imgui.Col.Button])
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(0,0))
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, rounding)

    imgui.BeginChild("##ripple effect" .. text, imgui.ImVec2(size.x, size.y), false, imgui.WindowFlags.NoScrollbar)
    
        local draw_list = imgui.GetWindowDrawList()
        if pool["animation"] and pool["radius"] <= radius * 2.8125 then
            draw_list:AddCircleFilled(pool["mouse_coor"], pool["radius"], imgui.GetColorU32(imgui.ImVec4(1, 1, 1, 0.6)), 64)
            pool["radius"] = pool["radius"] + (3 * duration)
            pool["time"] = os.clock()
        elseif pool["animation"] and pool["radius"] >= radius * 2.8125 then
            if bringVec4To(imgui.ImVec4(1, 1, 1, 0.6), imgui.ImVec4(1, 1, 1, 0), pool["time"], 1).w ~= 0 then                   
                draw_list:AddCircleFilled(pool["mouse_coor"], pool["radius"], imgui.GetColorU32(imgui.ImVec4(1, 1, 1, bringVec4To(imgui.ImVec4(1, 1, 1, 0.6), imgui.ImVec4(1, 1, 1, 0), pool["time"], 1).w)), 64)
            else
                pool["animation"] = false
            end
        elseif not pool["animation"] and pool["radius"] >= radius * 2.8125 then
            pool["animation"] = false
            pool["radius"] = 5
            pool["time"] = nil
        end

        if rounding ~= 0 then                
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y)
            )
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + rounding)
            )
            draw_list:PathArcTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + rounding,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + rounding), rounding, -3, -1.5, 64
            )
            
            draw_list:PathFillConvex(imgui.GetColorU32(pool["color"]))

            draw_list:PathClear()

            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y)
            )
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x - rounding,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y)
            )
            draw_list:PathArcTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x - rounding,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + rounding), rounding, -1.5, 0, 64
            )
            draw_list:PathFillConvex(imgui.GetColorU32(pool["color"]))

            draw_list:PathClear()
            
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y)
            )
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y - rounding)
            )
            draw_list:PathArcTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + rounding,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y - rounding), rounding, 3, 1.5, 64
            )
            draw_list:PathFillConvex(imgui.GetColorU32(pool["color"]))

            draw_list:PathClear()

            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y)
            )
            draw_list:PathLineTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y - rounding)
            )
            draw_list:PathArcTo(imgui.ImVec2(imgui.GetCursorPos().x + imgui.GetWindowPos().x + size.x - rounding,
                imgui.GetCursorPos().y + imgui.GetWindowPos().y + size.y - rounding), rounding, 0, 1.5, 64
            )
            draw_list:PathFillConvex(imgui.GetColorU32(pool["color"]))

            draw_list:PathClear()
        end

        CenterTextFor2Dims(text:match("(.+)##.+") or text)
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.PopStyleVar(2)
    
    
    imgui.SetCursorPos(imgui.ImVec2(imgui.GetCursorPos().x, imgui.GetCursorPos().y + 10))
    if imgui.IsItemClicked() then
            pool["animation"] = true
            pool["radius"] = 5
            pool["mouse_coor"] = imgui.GetMousePos()
            return true
    end
end




function imgui.ExitButton(image, width, height)
	imgui.Image(image, imgui.ImVec2(width, height))
	if imgui.IsItemClicked() then
		lua_thread.create(function()
			wait(100)
			gui_win_state.v = false
		end)
		
	end
end



local fontsize = nil
function imgui.BeforeDrawFrame()
    if fontsize == nil then
        fontsize = imgui.GetIO().Fonts:AddFontFromFileTTF(getGameDirectory() .. '\\moonloader\\jumper\\gui\\Ubuntu-bold.ttf', 24.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic()) -- вместо 30 любой нужный размер
    end
end
















-- ну погнали имгуи
-- короче сам радар это имгуи окно, в котором есть фотка карты сан андреса 2000х2000 пикселей
-- в зависимости от того как далеко игрок отошел от начала координат,
-- так же будет отдаляться фотка карты от окна, тем самым показывать текующее местоположение.
-- и еще эта фотка поворачивается в зависимости от угла поворота камеры игрока
-- (блять сколько я убил нервов и времени чтобы понять как эту хуйню поворачивать чтобы не убегало)


function imgui.OnDrawFrame()
    local X, Y = getScreenResolution()


    if window_state.v then


        local winSize = RadarSize * 2.5

        -- блядский курсор все равно показывается при активации

        imgui.ShowCursor = false

        imgui.SetNextWindowSize(imgui.ImVec2(winSize, winSize), imgui.Cond.Always)
        --imgui.SetNextWindowPos(imgui.ImVec2( X / 9.14, (Y/2) + (Y/3.13)), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowPos(imgui.ImVec2(RadarX, Y - RadarY  - (RadarSize / 4)), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        
        -- куча флагов для окна, похуй
        
        imgui.Begin("title", window_state, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoInputs + 
        imgui.WindowFlags.NoBringToFrontOnFocus)

            -- драв лист

            local draw_list = imgui.GetWindowDrawList()

            -- размеры мапы на радаре

            local sizeMap = X * 1.5625


            local x, y, z = getCharCoordinates(PLAYER_PED)


            if x < 0 then
                x = 3000 - math.abs(x)
            else
                x = 3000 + x
            end

            if y < 0 then
                y = 3000 + math.abs(y)
            else
                y = 3000 - y
            end
            

            -- offsetX, offsetY: офсеты чтобы смещать карты в радаре


            local offsetX = (x / (6000 / sizeMap)) - (imgui.GetWindowSize().x / 2)

            local offsetY = (y / (6000 / sizeMap)) - (imgui.GetWindowSize().y / 2)


            -- все что дальше это моя ебля чтобы правильно поворачивать картинку на радаре
            -- чтобы оно не убегало в казахстан при повороте а оставалось на месте

            rotated_vec =  rotateVector({
                (imgui.GetWindowPos().x + (sizeMap / 2) - offsetX) - (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                (imgui.GetWindowPos().y + (sizeMap / 2) - offsetY) - (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
            },

                math.rad(returnAngle()))

            ImageRotated(map_img,
                imgui.ImVec2(
                    rotated_vec[1] + (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    rotated_vec[2] + (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                ),
                imgui.ImVec2(sizeMap, sizeMap),
                math.rad(returnAngle())
            )


            -- рисую маленькие красные кружочки по координатам из массива с путем

            for i = 1, #list do
                path_vec = rotateVector({
                    (imgui.GetWindowPos().x + (list[i][1] * (sizeMap / 500)) - offsetX) - (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    (imgui.GetWindowPos().y + (list[i][2] * (sizeMap / 500)) - offsetY) - (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                },
                math.rad(returnAngle())
                )
                
                draw_list:AddCircleFilled(imgui.ImVec2(
                    path_vec[1] + (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    path_vec[2] + (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                ),
                X/256, imgui.GetColorU32(imgui.ImVec4(1, 0, 0, 1)))
            end


            -- игрок на радаре

            ImageRotated(
                cursor_img,
                imgui.ImVec2(
                    imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2),
                    imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2)
                ),
                imgui.ImVec2(sizeMap/64, sizeMap/64),
                -math.rad(getCharHeading(PLAYER_PED)) + math.rad(returnAngle())
            )

            -- дальше рисую большой красный кружок для метки

            local Tres, Tx, Ty, Tz = getTargetBlipCoordinates()
            if (Bres ~= nil and Bres) and (BX ~= nil and BY ~= nil) and not Tres then
                blip_vec = rotateVector({
                    (imgui.GetWindowPos().x + (BX / (6000 / sizeMap)) - offsetX) - (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    (imgui.GetWindowPos().y + (BY / (6000 / sizeMap)) - offsetY) - (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                },
                math.rad(returnAngle()))

                draw_list:AddCircleFilled(imgui.ImVec2(
                    blip_vec[1] + (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    blip_vec[2] + (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                ),
                X/128, imgui.GetColorU32(imgui.ImVec4(1, 0, 0, 1)))
            elseif Tres then
                if Tx < 0 then
                    Tx = 3000 - math.abs(Tx)
                else
                    Tx = 3000 + Tx
                end
        
                if Ty < 0 then
                    Ty = 3000 + math.abs(Ty)
                else
                    Ty = 3000 - Ty
                end

                blip_vec = rotateVector({
                    (imgui.GetWindowPos().x + (Tx / (6000 / sizeMap)) - offsetX) - (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    (imgui.GetWindowPos().y + (Ty / (6000 / sizeMap)) - offsetY) - (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                },
                math.rad(returnAngle()))

                draw_list:AddCircleFilled(imgui.ImVec2(
                    blip_vec[1] + (imgui.GetWindowPos().x + (imgui.GetWindowSize().x / 2)),
                    blip_vec[2] + (imgui.GetWindowPos().y + (imgui.GetWindowSize().y / 2))
                ),
                X/128, imgui.GetColorU32(imgui.ImVec4(1, 0, 0, 1)))
            end

        draw_list:AddRect(
            imgui.ImVec2(imgui.GetWindowPos().x, imgui.GetWindowPos().y),
            imgui.ImVec2(imgui.GetWindowPos().x + winSize, imgui.GetWindowPos().y + winSize),
            imgui.GetColorU32(imgui.ImVec4(1, 1, 1, 1)), 10, nil, 10
        )

        imgui.End()
    end

    if gui_win_state.v then
        imgui.ShowCursor = true


        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(1, 1, 1, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.06, 0.53, 0.98, 1.00))
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 15)
        imgui.PushFont(fontsize)

        imgui.SetNextWindowSize(imgui.ImVec2(768, 512), imgui.Cond.FirstUseEver)
	    imgui.SetNextWindowPos(imgui.ImVec2(X / 2, Y / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

        imgui.Begin("gui", gui_win_state, imgui.WindowFlags.NoMove + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize)

            local gui_draw = imgui.GetWindowDrawList()

            gui_draw:AddImage(gui_bg, 
                imgui.ImVec2(imgui.GetWindowPos().x, imgui.GetWindowPos().y),
                imgui.ImVec2(imgui.GetWindowPos().x + 768, imgui.GetWindowPos().y + 512)
            )

            imgui.SetCursorPos(imgui.ImVec2(704, 16))
            imgui.ExitButton(gui_exit, 48, 48)


            imgui.SetCursorPos(imgui.ImVec2(400, 80))
            imgui.Text(u8"Размер радара: ")

            imgui.SetCursorPos(imgui.ImVec2(400, 112))
            
            text_radar_size = (imgui.MaterialSlider("1", 250, 390, RadarSize - 10, nil, imgui.ImVec4(220/255, 220/255, 220/255, 0.8)) + 10)

            imgui.SetCursorPos(imgui.ImVec2(666, 114))
            imgui.Text(tostring(text_radar_size))


            
            imgui.SetCursorPos(imgui.ImVec2(400, 192))
            imgui.Text(u8"Координаты радара по Х:")

            imgui.SetCursorPos(imgui.ImVec2(400, 224))

            text_pos_x = (imgui.MaterialSlider("2", 250, X, RadarX, nil, imgui.ImVec4(220/255, 220/255, 220/255, 0.8)))

            imgui.SetCursorPos(imgui.ImVec2(666, 226))
            imgui.Text(tostring(text_pos_x))



            imgui.SetCursorPos(imgui.ImVec2(400, 304))
            imgui.Text(u8"Координаты радара по Y:")

            imgui.SetCursorPos(imgui.ImVec2(400, 336))

            text_pos_y = (imgui.MaterialSlider("3", 250, Y, RadarY, nil, imgui.ImVec4(220/255, 220/255, 220/255, 0.8)))

            imgui.SetCursorPos(imgui.ImVec2(666, 338))
            imgui.Text(tostring(text_pos_y))


            imgui.PopStyleColor()
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1.00))
            imgui.SetCursorPos(imgui.ImVec2(501, 448))


            if imgui.RippleButton(u8"Сохранить", imgui.ImVec2(150, 48), 4, 15, imgui.GetStyle().Colors[imgui.Col.WindowBg]) then

                RadarSize = text_radar_size
                RadarX = text_pos_x
                RadarY = text_pos_y

                f = io.open(getWorkingDirectory() .. "\\jumper\\gui\\gui.json", "w+")
                f:write("[" .. text_radar_size .. ", " .. text_pos_x ..  ", " .. text_pos_y .."]")
                f:close()
                --[[
                lua_thread.create(function ()
                    wait(1000)
                    thisScript():reload()
                end)
                ]]
            end


            

        imgui.End()
        

        imgui.PopFont()
        imgui.PopStyleColor(2)
        imgui.PopStyleVar()
    end

end


-- ну все пиздец
