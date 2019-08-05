local addonName, addon = ...
local L = addon.L

local function findQuestType(line, pos)
	local typ, s = addon.findInLists(line, {[L.WORD_LIST_ACCEPT] = "A", [L.WORD_LIST_COMPLETE] = "C", [L.WORD_LIST_TURN_IN] = "T", [L.WORD_LIST_SKIP] = "S"}, false)
	if typ ~= nil and s <= pos then return typ end
end

local function parseLine(l, line, questids, previds, questname, activeQuests, turnedInQuests)
	local pos, err
	-- find quest 
	while true do
		local q, typ, objective, s, e, part, pre, post, lastTwo, skip
		local wordListMap = {}
		wordListMap["%[q([acts])%s*([%d/%?]+).-%]"] = function(...) s, e, typ, q = ...; typ = typ:upper(); skip = true end
		local questPattern = "\"([^\"]+)\""
		wordListMap[" " .. questPattern .. " "] = function(...) s, e, q = ... end
		wordListMap[" " .. questPattern .. L.WORD_LIST_PART_N:gsub(";", "; " .. questPattern)] = function(...) s, e, q, part = ...; part = tonumber(part) end
		wordListMap[L.WORD_LIST_PART_N] = function(...) s, e, part = ...; q = questname; part = tonumber(part) end
		local i = 1
		while L["WORD_LIST_PART_" .. i] ~= nil do
			local ii = i
			wordListMap[" " .. questPattern .. L["WORD_LIST_PART_" .. i]:gsub(";", "; " .. questPattern)] = function(...) s, e, q = ...; part = ii end
			wordListMap[L["WORD_LIST_PART_".. i]] = function(...) s, e = ...; q = questname; part = ii end
			i = i + 1
		end
		wordListMap[L.WORD_LIST_NEXT_PART] = function(...) s, e = ...; q = questname
			if questids ~= nil and #questids == 1 and addon.questsDB[questids[1]] ~= nil and addon.questsDB[questids[1]].series ~= nil then 
				part = addon.questsDB[questids[1]].series + 1
			else
				part = 2
			end
		end
		if questids ~= nil then
			wordListMap[L.WORD_LIST_COMPLETE_LAST] = function(...) s, e, pre, post = ...; typ = "C" end
			wordListMap[L.WORD_LIST_TURN_IN_LAST] = function(...) s, e, pre, post = ...; typ = "T" end
		end
		if previds ~= nil then
			wordListMap[L.WORD_LIST_COMPLETE_LAST_TWO] = function(...) s, e, pre, post = ...; typ = "C"; lastTwo = true end
			wordListMap[L.WORD_LIST_TURN_IN_LAST_TWO] = function(...) s, e, pre, post = ...; typ = "T"; lastTwo = true end
		end
		for id, active in pairs(activeQuests) do
			for i, objList in ipairs(addon.getQuestObjectives(id)) do
				for j, object in ipairs(objList) do
					wordListMap[" " .. object:lower() .. "s? "] = function(...) s, e = ...; q = id; objective = i; typ = "C" end
				end
			end
		end
		addon.findInLists(line, wordListMap, true, pos)
		if skip then
			previds = questids
			questids = {}
			for id in q:gmatch("[^/]+") do
				if tonumber(id) ~= nil then 
					table.insert(questids, tonumber(q))
				end
			end
			if #questids ~= 1 then err = "" end
			pos = e
		else
			if s == nil then break end
			if pre ~= nil then s = s + #pre elseif s == 0 or line:sub(s, s):match("[%s%p]") then s = s + 1 end
			if post ~= nil then e = e - #post elseif e > #line or line:sub(e, e):match("[%s%p]") then e = e - 1 end
			
			if typ == nil then 
				typ = findQuestType(line, s) 
				if typ == nil then 
					typ = "C"
				end
			end
	
			-- when quest to be completed is followed by a single digit interpret this is an objective #
			local title = line:sub(s,e):gsub("\"", "")
			if typ == "C" and objective == nil and tonumber(line:sub(e + 1, e + 1)) ~= nil then
				objective = tonumber(line:sub(e + 1, e + 1))
				e = e + 1
			end
			
			if type(q) == "number" then
				previds = questids
				questids = {q}
			elseif q ~= nil then
				previds = questids
				questids = addon.getPossibleQuestIdsByName(q, part) 
			end
			if typ ~= "A" and #questids > 1 then
				-- found more than one? only search in active quests
				local ids2 = {}
				for i, id in ipairs(questids) do
					if activeQuests[id] then
						table.insert(ids2, id)
					end
				end
				if #ids2 > 0 then questids = ids2 end
			elseif typ == "A" and #questids > 1 then
				-- found more than one? exclude turned in quests
				local ids2 = {}
				for i, id in ipairs(questids) do
					if not turnedInQuests[id] then
						table.insert(ids2, id)
					end
				end
				if #ids2 > 0 then questids = ids2 end
			end
			if q ~= nil and #questids > 1 and part == nil then
				--more than 1 found and no part given? assume part 1
				local ids2 = addon.getPossibleQuestIdsByName(q, 1)
				if ids2 ~= nil and #ids2 > 0 then questids = ids2 end
			end
			if #questids ~= 1 then err = "" end
			
			if #questids ~= 0 then
				questname = addon.getQuestNameById(questids[1])
				if questname == nil then err = "quest " .. questids[1] .. " not found" end
			else
				questname = nil
			end
			
			local rest = line:sub(e + 1)
			line = line:sub(1, s - 1) 
			if objective ~= nil then objective = "," .. objective else objective = "" end
			
			if lastTwo then
				local questid = "?"
				if (typ == "C" or typ == "T") and previds ~= nil and #previds > 0 then 
					questid = table.concat(previds, "/") 
					if #previds > 1 then err = "" end
				else 
					err = true 
				end
				line = line .. "[Q" .. typ .. questid .. " -]" 
			end
			
			local questid
			if #questids > 0 then questid = table.concat(questids, "/") else questid = "?" end
			line = line .. "[Q" .. typ .. questid .. objective .. " " .. title .. "]" 
			
			if questids ~= nil and #questids == 1 then
				if addon.questsDB[questids[1]].races ~= nil or addon.questsDB[questids[1]].classes ~= nil then
					line = line .. "[A "
					local first = true
					if addon.questsDB[questids[1]].races ~= nil then
						for i, race in ipairs(addon.questsDB[questids[1]].races) do
							if not first then line = line .. "," end
							line = line .. addon.getRace(race)
							first = false
						end
					end
					if addon.questsDB[questids[1]].classes ~= nil then
						for i, class in ipairs(addon.questsDB[questids[1]].classes) do
							if not first then line = line .. "," end
							line = line .. addon.getClass(class)
							first = false
						end
					end
					line = line .. "]"
				end
			end
			pos = #line
			line = line .. rest
		end
		for _, id in ipairs(questids) do
			if typ == "A" then
				if turnedInQuests[id] then err = "accept quest " .. id .. " after turn in" end
				activeQuests[id] = true
			elseif typ == "T" then
				if turnedInQuests[id] then err = "quest " .. id .. " turned in twice" end
				if line:find("%[OC?%]") then 
					activeQuests[id] = nil 
					if #questids == 1 then turnedInQuests[id] = true end
				end
			elseif typ == "C" then
				if turnedInQuests[id] then err = "complete quest " .. id .. " after turn in" end
			end
		end
	end
	
	--found the word quest(/s) but no quest tags were created? ids have to be added manually unless completing/turning in only one/two remaining active quests
	if count == 0 then
		local s, e, count
		addon.findInLists(line, {
			[L.WORD_LIST_QUESTS] = function(...) s, e = ...; count = 2 end,
			[L.WORD_LIST_QUEST] = function(...) s, e = ...; count = 1 end
		})
		if s ~= nil then
			s = s + 1
			e = e - 1
		 	local typ = findQuestType(line:sub(1, s - 1))
			if typ ~= nil then 
				local rest = line:sub(e + 1)
				local title = line:sub(s,e)
				line = line:sub(1, s - 1)
				local id1, id2 = "?", "?"
				local activeIds = {}
				for id, _ in pairs(activeQuests) do table.insert(activeIds, id) end
				if (typ == "C" or typ == "T") and #activeIds == count then 
					id1 = activeIds[1]
					id2 = activeIds[2] 
					if typ == "T" then
						activeQuests[id1] = nil; turnedInQuests[id1] = true
						if id2 ~= nil then activeQuests[id2] = nil; turnedInQuests[id2] = true end
					end
				end
				if count == 2 then
					line = line .. "[Q" .. typ .. id2 .. " -]" 
				end
				line = line .. "[Q" .. typ .. id1 .. " " .. title .. "]" 
				line = line .. rest
			end
		end
	end

	local code, s, e, pre, post = addon.findInLists(line, {
		[L.WORD_LIST_XP] = "XP",
		[L.WORD_LIST_SET_HEARTH] = "S",
		[L.WORD_LIST_HEARTH] = "H",
		[L.WORD_LIST_FLY] = "F",
		[L.WORD_LIST_GET_FLIGHT_POINT] = "P",
		[L.WORD_LIST_VENDOR] = "V",
		[L.WORD_LIST_REPAIR] = "R",
		[L.WORD_LIST_TRAIN] = "T"
	})
	if code ~= nil and line:find("%[".. code) == nil then
		if pre ~= nil then s = s + #pre elseif s == 0 or line:sub(s, s):match("[%s%p]") then s = s + 1 end
		if post ~= nil then e = e - #post elseif e > #line or line:sub(e, e):match("[%s%p]") then e = e - 1 end
		if e > s then code = code .. " " end
		line = line:sub(1, s - 1) .. "[" .. code .. line:sub(s, e) .. "]" .. line:sub(e + 1)
	end
	
	if err == "" then 
		line = "ERROR " .. line 
	elseif err ~= nil then
		line = "ERROR (" .. err .. ") " .. line 
	end
	return line, questids, previds, questname, activeQuests, turnedInQuests
end

function addon.importPlainText(text)
	local l = 0
	local questids
	local previds
	local questname = "?"
	local activeQuests = {}
	local turnedInQuests = {}
	local hasErrors = false
	
	text = text:gsub("([^\n]+)", function(line)
		l = l + 1
		if line ~= "" then
			if line:sub(1, 6) == "ERROR " or line:sub(1, 6) == "      " then line = line:sub(7) end
			line, questids, previds, questname, activeQuests, turnedInQuests = parseLine(l, line, questids, previds, questname, activeQuests, turnedInQuests)
			if line:sub(1, 6) == "ERROR " then hasErrors = true end
			return line
		end
	end)
	if hasErrors then
		text = text:gsub("([^\n]+)", function(line)
			if line:sub(1, 6) ~= "ERROR " and line:sub(1, 6) ~= "      " then return "      " .. line end
		end)
	end
	return text
end

