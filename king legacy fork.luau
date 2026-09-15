-- GENESIS_WEBHOOK_ONLY_BUNDLE_V1
-- GENESIS_DAILY_QUEST_ALL_11_V1
-- GENESIS_DAILY_QUEST_CODEX_DIALOGUE_GUARD_V1
-- GENESIS_SEA_KING_ACQUISITION_V1
-- GENESIS_DAILY_BEFORE_FISHING_V17
-- GENESIS_DAILY_NPC_SEA_TRAVEL_V22
-- GENESIS_DAILY_PUZZLE_ADAPTIVE_V23
-- GENESIS_DAILY_PUZZLE_CODEX_HANDOFF_V24
-- GENESIS_EXECUTOR_MANAGED_AUTOEXEC_V25
-- GENESIS_SECOND_SEA_DAILY_OBJECTIVES_V26
-- GENESIS_KAIDO_PRIORITY_ACQUISITION_V27
-- GENESIS_KAIDO_BOUNDED_DIALOGUE_V28
-- GENESIS_KAIDO_RENDER_SYNC_CLICK_V29
-- GENESIS_KAIDO_ORB_FARM_WAIT_V30
-- GENESIS_DAILY_TRAVEL_RETRY_EVENT_PRIORITY_V31
-- GENESIS_KAIDO_LIVE_BOSS_DAILY_YIELD_V32
-- GENESIS_KAIDO_SEA2_SCOPE_V33
-- GENESIS_CURRENT_SEA_PRIORITY_SCOPE_V34
-- GENESIS_FISH_POSITION_PER_SEA_V35
-- GENESIS_MATERIAL_DEALER_AUTO_INIT_V36
-- GENESIS_MATERIAL_DEALER_HEADLESS_INIT_V37
-- GENESIS_DAILY_OUTBOUND_TRAVEL_PRIORITY_V38
-- Discord reporting uses the user-configured webhook; event state uses Kai's configured Cloudflare Worker.
-- Cloudflare Event Hub reads and live-state reporting are enabled when configured.
-- Username-based premium checks are disabled, leaving protected Smart Hop locked.
-- Teleport auto-execution is managed by the executor, not this script.
local function getGenesisRuntimeState()
	local executorEnvironment = (getgenv and getgenv()) or _G
	return (executorEnvironment and executorEnvironment.__GENESIS_RUNTIME)
		or (_G and _G.__GENESIS_RUNTIME)
end

local function trackGenesisConnection(connection)
	local runtime = getGenesisRuntimeState()
	if runtime and runtime.active and connection then
		runtime.connections[connection] = true
	end
	return connection
end

local function startGenesisRuntime(runtimeEnvironment, sharedGlobal)
	local executorEnvironment = (getgenv and getgenv()) or runtimeEnvironment
	local previousUnload = executorEnvironment and executorEnvironment.GenesisUnload
	if type(previousUnload) ~= "function" and type(sharedGlobal.GenesisUnload) == "function" then
		previousUnload = sharedGlobal.GenesisUnload
	end
	if type(previousUnload) == "function" then
		pcall(previousUnload)
	end

	local baseTask = task
	local runtime = {
		active = true,
		cleaning = false,
		connections = {},
		threads = {},
		promptStates = {},
		previousSpectrumX = executorEnvironment.SpectrumX,
		previousNotify = executorEnvironment.Notify,
		startedAt = tick(),
		buildMarker = "GENESIS_DAILY_OUTBOUND_TRAVEL_PRIORITY_V38",
	}
	executorEnvironment.__GENESIS_RUNTIME = runtime
	sharedGlobal.__GENESIS_RUNTIME = runtime

	local function registerThread(thread)
		if thread then
			runtime.threads[thread] = true
		end
		return thread
	end

	local function runtimeSpawn(callback, ...)
		local arguments = table.pack(...)
		local thread
		thread = baseTask.spawn(function()
			if runtime.active or runtime.cleaning then
				callback(table.unpack(arguments, 1, arguments.n))
			end
			if thread then
				runtime.threads[thread] = nil
			end
		end)
		return registerThread(thread)
	end

	local function runtimeDefer(callback, ...)
		local arguments = table.pack(...)
		local thread
		thread = baseTask.defer(function()
			if runtime.active or runtime.cleaning then
				callback(table.unpack(arguments, 1, arguments.n))
			end
			if thread then
				runtime.threads[thread] = nil
			end
		end)
		return registerThread(thread)
	end

	local function runtimeDelay(seconds, callback, ...)
		local arguments = table.pack(...)
		return runtimeSpawn(function()
			baseTask.wait(seconds)
			if runtime.active or runtime.cleaning then
				callback(table.unpack(arguments, 1, arguments.n))
			end
		end)
	end

	local trackedTask = setmetatable({
		spawn = runtimeSpawn,
		defer = runtimeDefer,
		delay = runtimeDelay,
	}, { __index = baseTask })

	local function unloadGenesis()
		if runtime.cleaning then
			return true, "Genesis unload is already in progress"
		end
		if not runtime.active then
			return true, "Genesis is already unloaded"
		end

		runtime.active = false
		runtime.cleaning = true
		sharedGlobal.allowCombat = false

		-- Disable only the in-memory copy. Saved user settings are deliberately
		-- untouched, so a later normal load restores the user's configuration.
		if type(sharedGlobal.Setting) == "table" then
			for key, entry in pairs(sharedGlobal.Setting) do
				if type(entry) == "table" and type(entry[1]) == "boolean" then
					entry[1] = false
				elseif type(entry) == "boolean" then
					sharedGlobal.Setting[key] = false
				end
			end
		end

		sharedGlobal.isFishing = false
		sharedGlobal.isLootingChests = false
		sharedGlobal.storingFruit = false
		sharedGlobal.collectingPearls = false
		sharedGlobal.seaEventActive = false
		sharedGlobal.conquestActive = false
		sharedGlobal.isProgressingBusoV2 = false
		sharedGlobal.isProgressingObservationV2 = false
		sharedGlobal.thirdSeaProgressionActive = false
		sharedGlobal._GenesisPriorityOwner = "unloaded"
		sharedGlobal._GenesisPriorityDetail = nil
		if type(sharedGlobal._GenesisDungeonCommit) == "table" then
			sharedGlobal._GenesisDungeonCommit.latched = false
			sharedGlobal._GenesisDungeonCommit.stage = "outside"
			sharedGlobal._GenesisDungeonCommit.entered = false
		end

		local cleanupFunctions = {
			sharedGlobal._stopFishing,
			sharedGlobal._stopDailyQuestHover,
			sharedGlobal._stopKaidoAcquisition,
			sharedGlobal._removeFarmFix,
			sharedGlobal._stopSeaEventBypass,
			sharedGlobal._stopAbyssalAcquisition,
			sharedGlobal._removeChestLootFix,
			sharedGlobal._removeConquestPosition,
		}
		for _, cleanup in pairs(cleanupFunctions) do
			if type(cleanup) == "function" then
				pcall(cleanup)
			end
		end

		-- Restore game UI that Genesis may have temporarily hidden or covered.
		local savedPopupState = sharedGlobal.savedPopupState
		if type(savedPopupState) == "table" and savedPopupState.frame then
			pcall(function()
				for child, visible in pairs(savedPopupState.texts or {}) do
					if child then
						child.Visible = visible
					end
				end
				if savedPopupState.parent then
					savedPopupState.frame.Parent = savedPopupState.parent
				end
				savedPopupState.frame.Visible = savedPopupState.visible
			end)
		end
		sharedGlobal.savedPopupState = nil
		sharedGlobal.hideNotifyActive = false
		if sharedGlobal.blackScreenGui then
			pcall(function()
				sharedGlobal.blackScreenGui:Destroy()
			end)
			sharedGlobal.blackScreenGui = nil
		end

		if type(sharedGlobal.HakiV2) == "table" and type(sharedGlobal.HakiV2.stopLock) == "function" then
			pcall(sharedGlobal.HakiV2.stopLock)
		end
		if type(sharedGlobal.Raid) == "table" then
			if type(sharedGlobal.Raid.stopCombat) == "function" then
				pcall(sharedGlobal.Raid.stopCombat)
			end
			if type(sharedGlobal.Raid.stopDodge) == "function" then
				pcall(sharedGlobal.Raid.stopDodge)
			end
			if type(sharedGlobal.Raid.clearDungeonFarm) == "function" then
				pcall(sharedGlobal.Raid.clearDungeonFarm)
			end
			if type(sharedGlobal.Raid.stopOrbit) == "function" then
				pcall(sharedGlobal.Raid.stopOrbit)
			end
			sharedGlobal.Raid.inraid = false
		end

		local gameObject = runtimeEnvironment.game
		local players = gameObject:GetService("Players")
		local character = players.LocalPlayer and players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		for prompt, original in pairs(runtime.promptStates) do
			pcall(function()
				prompt.HoldDuration = original.HoldDuration
				prompt.RequiresLineOfSight = original.RequiresLineOfSight
			end)
			runtime.promptStates[prompt] = nil
		end

		for connection in pairs(runtime.connections) do
			pcall(function()
				connection:Disconnect()
			end)
			runtime.connections[connection] = nil
		end

		local currentThread = coroutine.running()
		for thread in pairs(runtime.threads) do
			if thread ~= currentThread then
				pcall(baseTask.cancel, thread)
			end
			runtime.threads[thread] = nil
		end

		for _, guiParent in ipairs({ gameObject:GetService("CoreGui"), players.LocalPlayer:FindFirstChild("PlayerGui") }) do
			if guiParent then
				for _, child in ipairs(guiParent:GetChildren()) do
					if child.Name == "GenesisX" then
						pcall(function()
							child:Destroy()
						end)
					end
				end
			end
		end

		-- These guards belong to workers/connections owned by this runtime. Reset
		-- them so running Genesis again creates fresh replacements after unload.
		sharedGlobal._EventHubPollStarted = false
		sharedGlobal._TeleportFailHooked = false
		sharedGlobal.ghostShipDiedConnected = false
		sharedGlobal._lastSwordTrackerConnection = nil
		sharedGlobal._GenesisM1State = nil
		sharedGlobal._GenesisInvokeM1 = nil
		sharedGlobal._GenesisPerformM1Pass = nil
		sharedGlobal._GenesisDispatchM1IfReady = nil
		sharedGlobal._GenesisSkillLastSent = nil
		sharedGlobal._GenesisSkillReady = nil
		sharedGlobal._GenesisFishingPositionConfigByPlaceId = nil
		sharedGlobal._GenesisGetFishingPositionConfig = nil
		sharedGlobal._GenesisGetConfiguredFishingCFrame = nil
		sharedGlobal._GenesisRefreshFishingPositionLabel = nil
		sharedGlobal._GenesisMaterialShopState = nil
		sharedGlobal._GenesisSetMaterialShopGuiVisible = nil
		sharedGlobal._GenesisEnsureMaterialShopReady = nil
		sharedGlobal._GenesisIsFeatureEnabledInCurrentSea = nil
		sharedGlobal._GenesisGetCurrentSeaSelectedBoss = nil
		sharedGlobal._GenesisGetCurrentSeaSelectedMaterial = nil
		sharedGlobal._GenesisSettingPlaceIds = nil
		sharedGlobal.isFeatureEnabledInCurrentSea = nil
		sharedGlobal.getCurrentSeaSelectedBoss = nil
		sharedGlobal.getCurrentSeaSelectedMaterial = nil
		sharedGlobal._GenesisDailyQuestTravelPending = nil
		sharedGlobal._GenesisDailyReturnRequested = nil
		sharedGlobal._GenesisDailyTravelWarningAt = nil
		sharedGlobal.GenesisDaily = nil
		sharedGlobal._GenesisAbyssalAcquisition = nil
		sharedGlobal._GenesisFindAbyssalLocator = nil
		sharedGlobal._GenesisApproachAbyssalLocator = nil
		sharedGlobal._stopAbyssalAcquisition = nil
		sharedGlobal._GenesisKaidoAcquisition = nil
		sharedGlobal._GenesisKaidoCache = nil
		sharedGlobal._GenesisIsLiveKaido = nil
		sharedGlobal._GenesisFindLiveKaido = nil
		sharedGlobal._GenesisGetDragonOrbCount = nil
		sharedGlobal._GenesisClearKaidoSwimMovers = nil
		sharedGlobal._GenesisKaidoPhysicalClick = nil
		sharedGlobal._GenesisCanRunKaidoAcquisition = nil
		sharedGlobal._stopKaidoAcquisition = nil
		sharedGlobal._GenesisSeaKingAcquisition = nil
		sharedGlobal._GenesisFindSeaKingRewardChest = nil
		sharedGlobal._GenesisApproachSeaKingIsland = nil
		sharedGlobal._GenesisGetDailyQuestPriorityCandidate = nil
		sharedGlobal._GenesisRunDailyQuestCombat = nil
		sharedGlobal._GenesisDailyQuestPriorityCheckedAt = nil
		sharedGlobal._GenesisDailyQuestPriorityCandidate = nil
		sharedGlobal._GenesisDailyQuestReleaseUntil = nil
		sharedGlobal._GenesisDailyPuzzleStatus = nil
		if type(sharedGlobal._GenesisEventHubClient) == "table" then
			sharedGlobal._GenesisEventHubClient.stopped = true
		end
		sharedGlobal._GenesisEventHubClient = nil
		sharedGlobal._GenesisFruitLiveState = nil
		sharedGlobal.fishingPositionIssue = nil
		sharedGlobal._GenesisManualRefreshAt = nil
		sharedGlobal.GENESIS_SCRIPT_URL = nil
		sharedGlobal.GENESIS_SCRIPT_FILE = nil
		sharedGlobal._autoExecuteQueued = nil
		sharedGlobal._autoExecuteLastQueue = nil
		sharedGlobal.buildAutoExecuteCode = nil
		sharedGlobal.ensureLocalScriptCopy = nil
		sharedGlobal.clearAutoExecuteQueue = nil
		sharedGlobal.queueAutoExecute = nil
		sharedGlobal._pendingHopJobId = nil
		executorEnvironment.SpectrumX = runtime.previousSpectrumX
		executorEnvironment.Notify = runtime.previousNotify

		runtime.cleaning = false
		if executorEnvironment.__GENESIS_RUNTIME == runtime then
			executorEnvironment.__GENESIS_RUNTIME = nil
		end
		if sharedGlobal.__GENESIS_RUNTIME == runtime then
			sharedGlobal.__GENESIS_RUNTIME = nil
		end
		print("[GENESIS HUB] Unloaded UI, connections, workers, and movement locks.")
		return true, "Genesis unloaded"
	end

	runtime.unload = unloadGenesis
	executorEnvironment.GenesisUnload = unloadGenesis
	executorEnvironment.UnloadGenesis = unloadGenesis
	sharedGlobal.GenesisUnload = unloadGenesis
	sharedGlobal.UnloadGenesis = unloadGenesis
	return trackedTask, runtimeSpawn
end

local function createBundledUi()
local GenesisX = {}
GenesisX.__index = GenesisX

-- --- SERVICES -----------------------------------------------------------------
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")

-- --- LUCIDE ICONS / GENESIS X -----------------------------------------------
local LucideAssets = {}
pcall(function()
	local raw =
		(function()
return {
	assets = {
		-- Usage method without "lucide-" in the name.
		["accessibility"] = "rbxassetid://10709751939",
		["activity"] = "rbxassetid://10709752035",
		["airvent"] = "rbxassetid://10709752131",
		["airplay"] = "rbxassetid://10709752254",
		["alarmcheck"] = "rbxassetid://10709752405",
		["alarmclock"] = "rbxassetid://10709752630",
		["alarmclockoff"] = "rbxassetid://10709752508",
		["alarmminus"] = "rbxassetid://10709752732",
		["alarmplus"] = "rbxassetid://10709752825",
		["album"] = "rbxassetid://10709752906",
		["alertcircle"] = "rbxassetid://10709752996",
		["alertoctagon"] = "rbxassetid://10709753064",
		["alerttriangle"] = "rbxassetid://10709753149",
		["aligncenter"] = "rbxassetid://10709753570",
		["aligncenterhorizontal"] = "rbxassetid://10709753272",
		["aligncentervertical"] = "rbxassetid://10709753421",
		["alignendhorizontal"] = "rbxassetid://10709753692",
		["alignendvertical"] = "rbxassetid://10709753808",
		["alignhorizontaldistributecenter"] = "rbxassetid://10747779791",
		["alignhorizontaldistributeend"] = "rbxassetid://10747784534",
		["alignhorizontaldistributestart"] = "rbxassetid://10709754118",
		["alignhorizontaljustifycenter"] = "rbxassetid://10709754204",
		["alignhorizontaljustifyend"] = "rbxassetid://10709754317",
		["alignhorizontaljustifystart"] = "rbxassetid://10709754436",
		["alignhorizontalspacearound"] = "rbxassetid://10709754590",
		["alignhorizontalspacebetween"] = "rbxassetid://10709754749",
		["alignjustify"] = "rbxassetid://10709759610",
		["alignleft"] = "rbxassetid://10709759764",
		["alignright"] = "rbxassetid://10709759895",
		["alignstarthorizontal"] = "rbxassetid://10709760051",
		["alignstartvertical"] = "rbxassetid://10709760244",
		["alignverticaldistributecenter"] = "rbxassetid://10709760351",
		["alignverticaldistributeend"] = "rbxassetid://10709760434",
		["alignverticaldistributestart"] = "rbxassetid://10709760612",
		["alignverticaljustifycenter"] = "rbxassetid://10709760814",
		["alignverticaljustifyend"] = "rbxassetid://10709761003",
		["alignverticaljustifystart"] = "rbxassetid://10709761176",
		["alignverticalspacearound"] = "rbxassetid://10709761324",
		["alignverticalspacebetween"] = "rbxassetid://10709761434",
		["anchor"] = "rbxassetid://10709761530",
		["angry"] = "rbxassetid://10709761629",
		["annoyed"] = "rbxassetid://10709761722",
		["aperture"] = "rbxassetid://10709761813",
		["apple"] = "rbxassetid://10709761889",
		["archive"] = "rbxassetid://10709762233",
		["archiverestore"] = "rbxassetid://10709762058",
		["armchair"] = "rbxassetid://10709762327",
		["arrowbigdown"] = "rbxassetid://10747796644",
		["arrowbigleft"] = "rbxassetid://10709762574",
		["arrowbigright"] = "rbxassetid://10709762727",
		["arrowbigup"] = "rbxassetid://10709762879",
		["arrowdown"] = "rbxassetid://10709767827",
		["arrowdowncircle"] = "rbxassetid://10709763034",
		["arrowdownleft"] = "rbxassetid://10709767656",
		["arrowdownright"] = "rbxassetid://10709767750",
		["arrowleft"] = "rbxassetid://10709768114",
		["arrowleftcircle"] = "rbxassetid://10709767936",
		["arrowleftright"] = "rbxassetid://10709768019",
		["arrowright"] = "rbxassetid://10709768347",
		["arrowrightcircle"] = "rbxassetid://10709768226",
		["arrowup"] = "rbxassetid://10709768939",
		["arrowupcircle"] = "rbxassetid://10709768432",
		["arrowupdown"] = "rbxassetid://10709768538",
		["arrowupleft"] = "rbxassetid://10709768661",
		["arrowupright"] = "rbxassetid://10709768787",
		["asterisk"] = "rbxassetid://10709769095",
		["atsign"] = "rbxassetid://10709769286",
		["award"] = "rbxassetid://10709769406",
		["axe"] = "rbxassetid://10709769508",
		["axis3d"] = "rbxassetid://10709769598",
		["baby"] = "rbxassetid://10709769732",
		["backpack"] = "rbxassetid://10709769841",
		["baggageclaim"] = "rbxassetid://10709769935",
		["banana"] = "rbxassetid://10709770005",
		["banknote"] = "rbxassetid://10709770178",
		["barchart"] = "rbxassetid://10709773755",
		["barchart2"] = "rbxassetid://10709770317",
		["barchart3"] = "rbxassetid://10709770431",
		["barchart4"] = "rbxassetid://10709770560",
		["barcharthorizontal"] = "rbxassetid://10709773669",
		["barcode"] = "rbxassetid://10747360675",
		["baseline"] = "rbxassetid://10709773863",
		["bath"] = "rbxassetid://10709773963",
		["battery"] = "rbxassetid://10709774640",
		["batterycharging"] = "rbxassetid://10709774068",
		["batteryfull"] = "rbxassetid://10709774206",
		["batterylow"] = "rbxassetid://10709774370",
		["batterymedium"] = "rbxassetid://10709774513",
		["beaker"] = "rbxassetid://10709774756",
		["bed"] = "rbxassetid://10709775036",
		["beddouble"] = "rbxassetid://10709774864",
		["bedsingle"] = "rbxassetid://10709774968",
		["beer"] = "rbxassetid://10709775167",
		["bell"] = "rbxassetid://10709775704",
		["bellminus"] = "rbxassetid://10709775241",
		["belloff"] = "rbxassetid://10709775320",
		["bellplus"] = "rbxassetid://10709775448",
		["bellring"] = "rbxassetid://10709775560",
		["bike"] = "rbxassetid://10709775894",
		["binary"] = "rbxassetid://10709776050",
		["bitcoin"] = "rbxassetid://10709776126",
		["bluetooth"] = "rbxassetid://10709776655",
		["bluetoothconnected"] = "rbxassetid://10709776240",
		["bluetoothoff"] = "rbxassetid://10709776344",
		["bluetoothsearching"] = "rbxassetid://10709776501",
		["bold"] = "rbxassetid://10747813908",
		["bomb"] = "rbxassetid://10709781460",
		["bone"] = "rbxassetid://10709781605",
		["book"] = "rbxassetid://10709781824",
		["bookopen"] = "rbxassetid://10709781717",
		["bookmark"] = "rbxassetid://10709782154",
		["bookmarkminus"] = "rbxassetid://10709781919",
		["bookmarkplus"] = "rbxassetid://10709782044",
		["bot"] = "rbxassetid://10709782230",
		["box"] = "rbxassetid://10709782497",
		["boxselect"] = "rbxassetid://10709782342",
		["boxes"] = "rbxassetid://10709782582",
		["briefcase"] = "rbxassetid://10709782662",
		["brush"] = "rbxassetid://10709782758",
		["bug"] = "rbxassetid://10709782845",
		["building"] = "rbxassetid://10709783051",
		["building2"] = "rbxassetid://10709782939",
		["bus"] = "rbxassetid://10709783137",
		["cake"] = "rbxassetid://10709783217",
		["calculator"] = "rbxassetid://10709783311",
		["calendar"] = "rbxassetid://10709789505",
		["calendarcheck"] = "rbxassetid://10709783474",
		["calendarcheck2"] = "rbxassetid://10709783392",
		["calendarclock"] = "rbxassetid://10709783577",
		["calendardays"] = "rbxassetid://10709783673",
		["calendarheart"] = "rbxassetid://10709783835",
		["calendarminus"] = "rbxassetid://10709783959",
		["calendaroff"] = "rbxassetid://10709788784",
		["calendarplus"] = "rbxassetid://10709788937",
		["calendarrange"] = "rbxassetid://10709789053",
		["calendarsearch"] = "rbxassetid://10709789200",
		["calendarx"] = "rbxassetid://10709789407",
		["calendarx2"] = "rbxassetid://10709789329",
		["camera"] = "rbxassetid://10709789686",
		["cameraoff"] = "rbxassetid://10747822677",
		["car"] = "rbxassetid://10709789810",
		["carrot"] = "rbxassetid://10709789960",
		["cast"] = "rbxassetid://10709790097",
		["charge"] = "rbxassetid://10709790202",
		["check"] = "rbxassetid://10709790644",
		["checkcircle"] = "rbxassetid://10709790387",
		["checkcircle2"] = "rbxassetid://10709790298",
		["checksquare"] = "rbxassetid://10709790537",
		["chefhat"] = "rbxassetid://10709790757",
		["cherry"] = "rbxassetid://10709790875",
		["chevrondown"] = "rbxassetid://10709790948",
		["chevronfirst"] = "rbxassetid://10709791015",
		["chevronlast"] = "rbxassetid://10709791130",
		["chevronleft"] = "rbxassetid://10709791281",
		["chevronright"] = "rbxassetid://10709791437",
		["chevronup"] = "rbxassetid://10709791523",
		["chevronsdown"] = "rbxassetid://10709796864",
		["chevronsdownup"] = "rbxassetid://10709791632",
		["chevronsleft"] = "rbxassetid://10709797151",
		["chevronsleftright"] = "rbxassetid://10709797006",
		["chevronsright"] = "rbxassetid://10709797382",
		["chevronsrightleft"] = "rbxassetid://10709797274",
		["chevronsup"] = "rbxassetid://10709797622",
		["chevronsupdown"] = "rbxassetid://10709797508",
		["chrome"] = "rbxassetid://10709797725",
		["circle"] = "rbxassetid://10709798174",
		["circledot"] = "rbxassetid://10709797837",
		["circleellipsis"] = "rbxassetid://10709797985",
		["circleslashed"] = "rbxassetid://10709798100",
		["citrus"] = "rbxassetid://10709798276",
		["clapperboard"] = "rbxassetid://10709798350",
		["clipboard"] = "rbxassetid://10709799288",
		["clipboardcheck"] = "rbxassetid://10709798443",
		["clipboardcopy"] = "rbxassetid://10709798574",
		["clipboardedit"] = "rbxassetid://10709798682",
		["clipboardlist"] = "rbxassetid://10709798792",
		["clipboardsignature"] = "rbxassetid://10709798890",
		["clipboardtype"] = "rbxassetid://10709798999",
		["clipboardx"] = "rbxassetid://10709799124",
		["clock"] = "rbxassetid://10709805144",
		["clock1"] = "rbxassetid://10709799535",
		["clock10"] = "rbxassetid://10709799718",
		["clock11"] = "rbxassetid://10709799818",
		["clock12"] = "rbxassetid://10709799962",
		["clock2"] = "rbxassetid://10709803876",
		["clock3"] = "rbxassetid://10709803989",
		["clock4"] = "rbxassetid://10709804164",
		["clock5"] = "rbxassetid://10709804291",
		["clock6"] = "rbxassetid://10709804435",
		["clock7"] = "rbxassetid://10709804599",
		["clock8"] = "rbxassetid://10709804784",
		["clock9"] = "rbxassetid://10709804996",
		["cloud"] = "rbxassetid://10709806740",
		["cloudcog"] = "rbxassetid://10709805262",
		["clouddrizzle"] = "rbxassetid://10709805371",
		["cloudfog"] = "rbxassetid://10709805477",
		["cloudhail"] = "rbxassetid://10709805596",
		["cloudlightning"] = "rbxassetid://10709805727",
		["cloudmoon"] = "rbxassetid://10709805942",
		["cloudmoonrain"] = "rbxassetid://10709805838",
		["cloudoff"] = "rbxassetid://10709806060",
		["cloudrain"] = "rbxassetid://10709806277",
		["cloudrainwind"] = "rbxassetid://10709806166",
		["cloudsnow"] = "rbxassetid://10709806374",
		["cloudsun"] = "rbxassetid://10709806631",
		["cloudsunrain"] = "rbxassetid://10709806475",
		["cloudy"] = "rbxassetid://10709806859",
		["clover"] = "rbxassetid://10709806995",
		["code"] = "rbxassetid://10709810463",
		["code2"] = "rbxassetid://10709807111",
		["codepen"] = "rbxassetid://10709810534",
		["codesandbox"] = "rbxassetid://10709810676",
		["coffee"] = "rbxassetid://10709810814",
		["cog"] = "rbxassetid://10709810948",
		["coins"] = "rbxassetid://10709811110",
		["columns"] = "rbxassetid://10709811261",
		["command"] = "rbxassetid://10709811365",
		["compass"] = "rbxassetid://10709811445",
		["component"] = "rbxassetid://10709811595",
		["conciergebell"] = "rbxassetid://10709811706",
		["connection"] = "rbxassetid://10747361219",
		["contact"] = "rbxassetid://10709811834",
		["contrast"] = "rbxassetid://10709811939",
		["cookie"] = "rbxassetid://10709812067",
		["copy"] = "rbxassetid://10709812159",
		["copyleft"] = "rbxassetid://10709812251",
		["copyright"] = "rbxassetid://10709812311",
		["cornerdownleft"] = "rbxassetid://10709812396",
		["cornerdownright"] = "rbxassetid://10709812485",
		["cornerleftdown"] = "rbxassetid://10709812632",
		["cornerleftup"] = "rbxassetid://10709812784",
		["cornerrightdown"] = "rbxassetid://10709812939",
		["cornerrightup"] = "rbxassetid://10709813094",
		["cornerupleft"] = "rbxassetid://10709813185",
		["cornerupright"] = "rbxassetid://10709813281",
		["cpu"] = "rbxassetid://10709813383",
		["croissant"] = "rbxassetid://10709818125",
		["crop"] = "rbxassetid://10709818245",
		["cross"] = "rbxassetid://10709818399",
		["crosshair"] = "rbxassetid://10709818534",
		["crown"] = "rbxassetid://10709818626",
		["cupsoda"] = "rbxassetid://10709818763",
		["curlybraces"] = "rbxassetid://10709818847",
		["currency"] = "rbxassetid://10709818931",
		["database"] = "rbxassetid://10709818996",
		["delete"] = "rbxassetid://10709819059",
		["diamond"] = "rbxassetid://10709819149",
		["dice1"] = "rbxassetid://10709819266",
		["dice2"] = "rbxassetid://10709819361",
		["dice3"] = "rbxassetid://10709819508",
		["dice4"] = "rbxassetid://10709819670",
		["dice5"] = "rbxassetid://10709819801",
		["dice6"] = "rbxassetid://10709819896",
		["dices"] = "rbxassetid://10723343321",
		["diff"] = "rbxassetid://10723343416",
		["disc"] = "rbxassetid://10723343537",
		["divide"] = "rbxassetid://10723343805",
		["dividecircle"] = "rbxassetid://10723343636",
		["dividesquare"] = "rbxassetid://10723343737",
		["dollarsign"] = "rbxassetid://10723343958",
		["download"] = "rbxassetid://10723344270",
		["downloadcloud"] = "rbxassetid://10723344088",
		["droplet"] = "rbxassetid://10723344432",
		["droplets"] = "rbxassetid://10734883356",
		["drumstick"] = "rbxassetid://10723344737",
		["edit"] = "rbxassetid://10734883598",
		["edit2"] = "rbxassetid://10723344885",
		["edit3"] = "rbxassetid://10723345088",
		["egg"] = "rbxassetid://10723345518",
		["eggfried"] = "rbxassetid://10723345347",
		["electricity"] = "rbxassetid://10723345749",
		["electricityoff"] = "rbxassetid://10723345643",
		["equal"] = "rbxassetid://10723345990",
		["equalnot"] = "rbxassetid://10723345866",
		["eraser"] = "rbxassetid://10723346158",
		["euro"] = "rbxassetid://10723346372",
		["expand"] = "rbxassetid://10723346553",
		["externallink"] = "rbxassetid://10723346684",
		["eye"] = "rbxassetid://10723346959",
		["eyeoff"] = "rbxassetid://10723346871",
		["factory"] = "rbxassetid://10723347051",
		["fan"] = "rbxassetid://10723354359",
		["fastforward"] = "rbxassetid://10723354521",
		["feather"] = "rbxassetid://10723354671",
		["figma"] = "rbxassetid://10723354801",
		["file"] = "rbxassetid://10723374641",
		["filearchive"] = "rbxassetid://10723354921",
		["fileaudio"] = "rbxassetid://10723355148",
		["fileaudio2"] = "rbxassetid://10723355026",
		["fileaxis3d"] = "rbxassetid://10723355272",
		["filebadge"] = "rbxassetid://10723355622",
		["filebadge2"] = "rbxassetid://10723355451",
		["filebarchart"] = "rbxassetid://10723355887",
		["filebarchart2"] = "rbxassetid://10723355746",
		["filebox"] = "rbxassetid://10723355989",
		["filecheck"] = "rbxassetid://10723356210",
		["filecheck2"] = "rbxassetid://10723356100",
		["fileclock"] = "rbxassetid://10723356329",
		["filecode"] = "rbxassetid://10723356507",
		["filecog"] = "rbxassetid://10723356830",
		["filecog2"] = "rbxassetid://10723356676",
		["filediff"] = "rbxassetid://10723357039",
		["filedigit"] = "rbxassetid://10723357151",
		["filedown"] = "rbxassetid://10723357322",
		["fileedit"] = "rbxassetid://10723357495",
		["fileheart"] = "rbxassetid://10723357637",
		["fileimage"] = "rbxassetid://10723357790",
		["fileinput"] = "rbxassetid://10723357933",
		["filejson"] = "rbxassetid://10723364435",
		["filejson2"] = "rbxassetid://10723364361",
		["filekey"] = "rbxassetid://10723364605",
		["filekey2"] = "rbxassetid://10723364515",
		["filelinechart"] = "rbxassetid://10723364725",
		["filelock"] = "rbxassetid://10723364957",
		["filelock2"] = "rbxassetid://10723364861",
		["fileminus"] = "rbxassetid://10723365254",
		["fileminus2"] = "rbxassetid://10723365086",
		["fileoutput"] = "rbxassetid://10723365457",
		["filepiechart"] = "rbxassetid://10723365598",
		["fileplus"] = "rbxassetid://10723365877",
		["fileplus2"] = "rbxassetid://10723365766",
		["filequestion"] = "rbxassetid://10723365987",
		["filescan"] = "rbxassetid://10723366167",
		["filesearch"] = "rbxassetid://10723366550",
		["filesearch2"] = "rbxassetid://10723366340",
		["filesignature"] = "rbxassetid://10723366741",
		["filespreadsheet"] = "rbxassetid://10723366962",
		["filesymlink"] = "rbxassetid://10723367098",
		["fileterminal"] = "rbxassetid://10723367244",
		["filetext"] = "rbxassetid://10723367380",
		["filetype"] = "rbxassetid://10723367606",
		["filetype2"] = "rbxassetid://10723367509",
		["fileup"] = "rbxassetid://10723367734",
		["filevideo"] = "rbxassetid://10723373884",
		["filevideo2"] = "rbxassetid://10723367834",
		["filevolume"] = "rbxassetid://10723374172",
		["filevolume2"] = "rbxassetid://10723374030",
		["filewarning"] = "rbxassetid://10723374276",
		["filex"] = "rbxassetid://10723374544",
		["filex2"] = "rbxassetid://10723374378",
		["files"] = "rbxassetid://10723374759",
		["film"] = "rbxassetid://10723374981",
		["filter"] = "rbxassetid://10723375128",
		["fingerprint"] = "rbxassetid://10723375250",
		["flag"] = "rbxassetid://10723375890",
		["flagoff"] = "rbxassetid://10723375443",
		["flagtriangleleft"] = "rbxassetid://10723375608",
		["flagtriangleright"] = "rbxassetid://10723375727",
		["flame"] = "rbxassetid://10723376114",
		["flashlight"] = "rbxassetid://10723376471",
		["flashlightoff"] = "rbxassetid://10723376365",
		["flaskconical"] = "rbxassetid://10734883986",
		["flaskround"] = "rbxassetid://10723376614",
		["fliphorizontal"] = "rbxassetid://10723376884",
		["fliphorizontal2"] = "rbxassetid://10723376745",
		["flipvertical"] = "rbxassetid://10723377138",
		["flipvertical2"] = "rbxassetid://10723377026",
		["flower"] = "rbxassetid://10747830374",
		["flower2"] = "rbxassetid://10723377305",
		["focus"] = "rbxassetid://10723377537",
		["folder"] = "rbxassetid://10723387563",
		["folderarchive"] = "rbxassetid://10723384478",
		["foldercheck"] = "rbxassetid://10723384605",
		["folderclock"] = "rbxassetid://10723384731",
		["folderclosed"] = "rbxassetid://10723384893",
		["foldercog"] = "rbxassetid://10723385213",
		["foldercog2"] = "rbxassetid://10723385036",
		["folderdown"] = "rbxassetid://10723385338",
		["folderedit"] = "rbxassetid://10723385445",
		["folderheart"] = "rbxassetid://10723385545",
		["folderinput"] = "rbxassetid://10723385721",
		["folderkey"] = "rbxassetid://10723385848",
		["folderlock"] = "rbxassetid://10723386005",
		["folderminus"] = "rbxassetid://10723386127",
		["folderopen"] = "rbxassetid://10723386277",
		["folderoutput"] = "rbxassetid://10723386386",
		["folderplus"] = "rbxassetid://10723386531",
		["foldersearch"] = "rbxassetid://10723386787",
		["foldersearch2"] = "rbxassetid://10723386674",
		["foldersymlink"] = "rbxassetid://10723386930",
		["foldertree"] = "rbxassetid://10723387085",
		["folderup"] = "rbxassetid://10723387265",
		["folderx"] = "rbxassetid://10723387448",
		["folders"] = "rbxassetid://10723387721",
		["forminput"] = "rbxassetid://10723387841",
		["forward"] = "rbxassetid://10723388016",
		["frame"] = "rbxassetid://10723394389",
		["framer"] = "rbxassetid://10723394565",
		["frown"] = "rbxassetid://10723394681",
		["fuel"] = "rbxassetid://10723394846",
		["functionsquare"] = "rbxassetid://10723395041",
		["gamepad"] = "rbxassetid://10723395457",
		["gamepad2"] = "rbxassetid://10723395215",
		["gauge"] = "rbxassetid://10723395708",
		["gavel"] = "rbxassetid://10723395896",
		["gem"] = "rbxassetid://10723396000",
		["ghost"] = "rbxassetid://10723396107",
		["gift"] = "rbxassetid://10723396402",
		["giftcard"] = "rbxassetid://10723396225",
		["gitbranch"] = "rbxassetid://10723396676",
		["gitbranchplus"] = "rbxassetid://10723396542",
		["gitcommit"] = "rbxassetid://10723396812",
		["gitcompare"] = "rbxassetid://10723396954",
		["gitfork"] = "rbxassetid://10723397049",
		["gitmerge"] = "rbxassetid://10723397165",
		["gitpullrequest"] = "rbxassetid://10723397431",
		["gitpullrequestclosed"] = "rbxassetid://10723397268",
		["gitpullrequestdraft"] = "rbxassetid://10734884302",
		["glass"] = "rbxassetid://10723397788",
		["glass2"] = "rbxassetid://10723397529",
		["glasswater"] = "rbxassetid://10723397678",
		["glasses"] = "rbxassetid://10723397895",
		["globe"] = "rbxassetid://10723404337",
		["globe2"] = "rbxassetid://10723398002",
		["grab"] = "rbxassetid://10723404472",
		["graduationcap"] = "rbxassetid://10723404691",
		["grape"] = "rbxassetid://10723404822",
		["grid"] = "rbxassetid://10723404936",
		["griphorizontal"] = "rbxassetid://10723405089",
		["gripvertical"] = "rbxassetid://10723405236",
		["hammer"] = "rbxassetid://10723405360",
		["hand"] = "rbxassetid://10723405649",
		["handmetal"] = "rbxassetid://10723405508",
		["harddrive"] = "rbxassetid://10723405749",
		["hardhat"] = "rbxassetid://10723405859",
		["hash"] = "rbxassetid://10723405975",
		["haze"] = "rbxassetid://10723406078",
		["headphones"] = "rbxassetid://10723406165",
		["heart"] = "rbxassetid://10723406885",
		["heartcrack"] = "rbxassetid://10723406299",
		["hearthandshake"] = "rbxassetid://10723406480",
		["heartoff"] = "rbxassetid://10723406662",
		["heartpulse"] = "rbxassetid://10723406795",
		["helpcircle"] = "rbxassetid://10723406988",
		["hexagon"] = "rbxassetid://10723407092",
		["highlighter"] = "rbxassetid://10723407192",
		["history"] = "rbxassetid://10723407335",
		["home"] = "rbxassetid://10723407389",
		["hourglass"] = "rbxassetid://10723407498",
		["icecream"] = "rbxassetid://10723414308",
		["image"] = "rbxassetid://10723415040",
		["imageminus"] = "rbxassetid://10723414487",
		["imageoff"] = "rbxassetid://10723414677",
		["imageplus"] = "rbxassetid://10723414827",
		["import"] = "rbxassetid://10723415205",
		["inbox"] = "rbxassetid://10723415335",
		["indent"] = "rbxassetid://10723415494",
		["indianrupee"] = "rbxassetid://10723415642",
		["infinity"] = "rbxassetid://10723415766",
		["info"] = "rbxassetid://10723415903",
		["inspect"] = "rbxassetid://10723416057",
		["italic"] = "rbxassetid://10723416195",
		["japaneseyen"] = "rbxassetid://10723416363",
		["joystick"] = "rbxassetid://10723416527",
		["key"] = "rbxassetid://10723416652",
		["keyboard"] = "rbxassetid://10723416765",
		["lamp"] = "rbxassetid://10723417513",
		["lampceiling"] = "rbxassetid://10723416922",
		["lampdesk"] = "rbxassetid://10723417016",
		["lampfloor"] = "rbxassetid://10723417131",
		["lampwalldown"] = "rbxassetid://10723417240",
		["lampwallup"] = "rbxassetid://10723417356",
		["landmark"] = "rbxassetid://10723417608",
		["languages"] = "rbxassetid://10723417703",
		["laptop"] = "rbxassetid://10723423881",
		["laptop2"] = "rbxassetid://10723417797",
		["lasso"] = "rbxassetid://10723424235",
		["lassoselect"] = "rbxassetid://10723424058",
		["laugh"] = "rbxassetid://10723424372",
		["layers"] = "rbxassetid://10723424505",
		["layout"] = "rbxassetid://10723425376",
		["layoutdashboard"] = "rbxassetid://10723424646",
		["layoutgrid"] = "rbxassetid://10723424838",
		["layoutlist"] = "rbxassetid://10723424963",
		["layouttemplate"] = "rbxassetid://10723425187",
		["leaf"] = "rbxassetid://10723425539",
		["library"] = "rbxassetid://10723425615",
		["lifebuoy"] = "rbxassetid://10723425685",
		["lightbulb"] = "rbxassetid://10723425852",
		["lightbulboff"] = "rbxassetid://10723425762",
		["linechart"] = "rbxassetid://10723426393",
		["link"] = "rbxassetid://10723426722",
		["link2"] = "rbxassetid://10723426595",
		["link2off"] = "rbxassetid://10723426513",
		["list"] = "rbxassetid://10723433811",
		["listchecks"] = "rbxassetid://10734884548",
		["listend"] = "rbxassetid://10723426886",
		["listminus"] = "rbxassetid://10723426986",
		["listmusic"] = "rbxassetid://10723427081",
		["listordered"] = "rbxassetid://10723427199",
		["listplus"] = "rbxassetid://10723427334",
		["liststart"] = "rbxassetid://10723427494",
		["listvideo"] = "rbxassetid://10723427619",
		["listx"] = "rbxassetid://10723433655",
		["loader"] = "rbxassetid://10723434070",
		["loader2"] = "rbxassetid://10723433935",
		["locate"] = "rbxassetid://10723434557",
		["locatefixed"] = "rbxassetid://10723434236",
		["locateoff"] = "rbxassetid://10723434379",
		["lock"] = "rbxassetid://10723434711",
		["login"] = "rbxassetid://10723434830",
		["logout"] = "rbxassetid://10723434906",
		["luggage"] = "rbxassetid://10723434993",
		["magnet"] = "rbxassetid://10723435069",
		["mail"] = "rbxassetid://10734885430",
		["mailcheck"] = "rbxassetid://10723435182",
		["mailminus"] = "rbxassetid://10723435261",
		["mailopen"] = "rbxassetid://10723435342",
		["mailplus"] = "rbxassetid://10723435443",
		["mailquestion"] = "rbxassetid://10723435515",
		["mailsearch"] = "rbxassetid://10734884739",
		["mailwarning"] = "rbxassetid://10734885015",
		["mailx"] = "rbxassetid://10734885247",
		["mails"] = "rbxassetid://10734885614",
		["map"] = "rbxassetid://10734886202",
		["mappin"] = "rbxassetid://10734886004",
		["mappinoff"] = "rbxassetid://10734885803",
		["maximize"] = "rbxassetid://10734886735",
		["maximize2"] = "rbxassetid://10734886496",
		["medal"] = "rbxassetid://10734887072",
		["megaphone"] = "rbxassetid://10734887454",
		["megaphoneoff"] = "rbxassetid://10734887311",
		["meh"] = "rbxassetid://10734887603",
		["menu"] = "rbxassetid://10734887784",
		["messagecircle"] = "rbxassetid://10734888000",
		["messagesquare"] = "rbxassetid://10734888228",
		["mic"] = "rbxassetid://10734888864",
		["mic2"] = "rbxassetid://10734888430",
		["micoff"] = "rbxassetid://10734888646",
		["microscope"] = "rbxassetid://10734889106",
		["microwave"] = "rbxassetid://10734895076",
		["milestone"] = "rbxassetid://10734895310",
		["minimize"] = "rbxassetid://10734895698",
		["minimize2"] = "rbxassetid://10734895530",
		["minus"] = "rbxassetid://10734896206",
		["minuscircle"] = "rbxassetid://10734895856",
		["minussquare"] = "rbxassetid://10734896029",
		["monitor"] = "rbxassetid://10734896881",
		["monitoroff"] = "rbxassetid://10734896360",
		["monitorspeaker"] = "rbxassetid://10734896512",
		["moon"] = "rbxassetid://10734897102",
		["morehorizontal"] = "rbxassetid://10734897250",
		["morevertical"] = "rbxassetid://10734897387",
		["mountain"] = "rbxassetid://10734897956",
		["mountainsnow"] = "rbxassetid://10734897665",
		["mouse"] = "rbxassetid://10734898592",
		["mousepointer"] = "rbxassetid://10734898476",
		["mousepointer2"] = "rbxassetid://10734898194",
		["mousepointerclick"] = "rbxassetid://10734898355",
		["move"] = "rbxassetid://10734900011",
		["move3d"] = "rbxassetid://10734898756",
		["movediagonal"] = "rbxassetid://10734899164",
		["movediagonal2"] = "rbxassetid://10734898934",
		["movehorizontal"] = "rbxassetid://10734899414",
		["movevertical"] = "rbxassetid://10734899821",
		["music"] = "rbxassetid://10734905958",
		["music2"] = "rbxassetid://10734900215",
		["music3"] = "rbxassetid://10734905665",
		["music4"] = "rbxassetid://10734905823",
		["navigation"] = "rbxassetid://10734906744",
		["navigation2"] = "rbxassetid://10734906332",
		["navigation2off"] = "rbxassetid://10734906144",
		["navigationoff"] = "rbxassetid://10734906580",
		["network"] = "rbxassetid://10734906975",
		["newspaper"] = "rbxassetid://10734907168",
		["octagon"] = "rbxassetid://10734907361",
		["option"] = "rbxassetid://10734907649",
		["outdent"] = "rbxassetid://10734907933",
		["package"] = "rbxassetid://10734909540",
		["package2"] = "rbxassetid://10734908151",
		["packagecheck"] = "rbxassetid://10734908384",
		["packageminus"] = "rbxassetid://10734908626",
		["packageopen"] = "rbxassetid://10734908793",
		["packageplus"] = "rbxassetid://10734909016",
		["packagesearch"] = "rbxassetid://10734909196",
		["packagex"] = "rbxassetid://10734909375",
		["paintbucket"] = "rbxassetid://10734909847",
		["paintbrush"] = "rbxassetid://10734910187",
		["paintbrush2"] = "rbxassetid://10734910030",
		["palette"] = "rbxassetid://10734910430",
		["palmtree"] = "rbxassetid://10734910680",
		["paperclip"] = "rbxassetid://10734910927",
		["partypopper"] = "rbxassetid://10734918735",
		["pause"] = "rbxassetid://10734919336",
		["pausecircle"] = "rbxassetid://10735024209",
		["pauseoctagon"] = "rbxassetid://10734919143",
		["pentool"] = "rbxassetid://10734919503",
		["pencil"] = "rbxassetid://10734919691",
		["percent"] = "rbxassetid://10734919919",
		["personstanding"] = "rbxassetid://10734920149",
		["phone"] = "rbxassetid://10734921524",
		["phonecall"] = "rbxassetid://10734920305",
		["phoneforwarded"] = "rbxassetid://10734920508",
		["phoneincoming"] = "rbxassetid://10734920694",
		["phonemissed"] = "rbxassetid://10734920845",
		["phoneoff"] = "rbxassetid://10734921077",
		["phoneoutgoing"] = "rbxassetid://10734921288",
		["piechart"] = "rbxassetid://10734921727",
		["piggybank"] = "rbxassetid://10734921935",
		["pin"] = "rbxassetid://10734922324",
		["pinoff"] = "rbxassetid://10734922180",
		["pipette"] = "rbxassetid://10734922497",
		["pizza"] = "rbxassetid://10734922774",
		["plane"] = "rbxassetid://10734922971",
		["play"] = "rbxassetid://10734923549",
		["playcircle"] = "rbxassetid://10734923214",
		["plus"] = "rbxassetid://10734924532",
		["pluscircle"] = "rbxassetid://10734923868",
		["plussquare"] = "rbxassetid://10734924219",
		["podcast"] = "rbxassetid://10734929553",
		["pointer"] = "rbxassetid://10734929723",
		["poundsterling"] = "rbxassetid://10734929981",
		["power"] = "rbxassetid://10734930466",
		["poweroff"] = "rbxassetid://10734930257",
		["printer"] = "rbxassetid://10734930632",
		["puzzle"] = "rbxassetid://10734930886",
		["quote"] = "rbxassetid://10734931234",
		["radio"] = "rbxassetid://10734931596",
		["radioreceiver"] = "rbxassetid://10734931402",
		["rectanglehorizontal"] = "rbxassetid://10734931777",
		["rectanglevertical"] = "rbxassetid://10734932081",
		["recycle"] = "rbxassetid://10734932295",
		["redo"] = "rbxassetid://10734932822",
		["redo2"] = "rbxassetid://10734932586",
		["refreshccw"] = "rbxassetid://10734933056",
		["refreshcw"] = "rbxassetid://10734933222",
		["refrigerator"] = "rbxassetid://10734933465",
		["regex"] = "rbxassetid://10734933655",
		["repeat"] = "rbxassetid://10734933966",
		["repeat1"] = "rbxassetid://10734933826",
		["reply"] = "rbxassetid://10734934252",
		["replyall"] = "rbxassetid://10734934132",
		["rewind"] = "rbxassetid://10734934347",
		["rocket"] = "rbxassetid://10734934585",
		["rockingchair"] = "rbxassetid://10734939942",
		["rotate3d"] = "rbxassetid://10734940107",
		["rotateccw"] = "rbxassetid://10734940376",
		["rotatecw"] = "rbxassetid://10734940654",
		["rss"] = "rbxassetid://10734940825",
		["ruler"] = "rbxassetid://10734941018",
		["russianruble"] = "rbxassetid://10734941199",
		["sailboat"] = "rbxassetid://10734941354",
		["save"] = "rbxassetid://10734941499",
		["scale"] = "rbxassetid://10734941912",
		["scale3d"] = "rbxassetid://10734941739",
		["scaling"] = "rbxassetid://10734942072",
		["scan"] = "rbxassetid://10734942565",
		["scanface"] = "rbxassetid://10734942198",
		["scanline"] = "rbxassetid://10734942351",
		["scissors"] = "rbxassetid://10734942778",
		["screenshare"] = "rbxassetid://10734943193",
		["screenshareoff"] = "rbxassetid://10734942967",
		["scroll"] = "rbxassetid://10734943448",
		["search"] = "rbxassetid://10734943674",
		["send"] = "rbxassetid://10734943902",
		["separatorhorizontal"] = "rbxassetid://10734944115",
		["separatorvertical"] = "rbxassetid://10734944326",
		["server"] = "rbxassetid://10734949856",
		["servercog"] = "rbxassetid://10734944444",
		["servercrash"] = "rbxassetid://10734944554",
		["serveroff"] = "rbxassetid://10734944668",
		["settings"] = "rbxassetid://10734950309",
		["settings2"] = "rbxassetid://10734950020",
		["share"] = "rbxassetid://10734950813",
		["share2"] = "rbxassetid://10734950553",
		["sheet"] = "rbxassetid://10734951038",
		["shield"] = "rbxassetid://10734951847",
		["shieldalert"] = "rbxassetid://10734951173",
		["shieldcheck"] = "rbxassetid://10734951367",
		["shieldclose"] = "rbxassetid://10734951535",
		["shieldoff"] = "rbxassetid://10734951684",
		["shirt"] = "rbxassetid://10734952036",
		["shoppingbag"] = "rbxassetid://10734952273",
		["shoppingcart"] = "rbxassetid://10734952479",
		["shovel"] = "rbxassetid://10734952773",
		["showerhead"] = "rbxassetid://10734952942",
		["shrink"] = "rbxassetid://10734953073",
		["shrub"] = "rbxassetid://10734953241",
		["shuffle"] = "rbxassetid://10734953451",
		["sidebar"] = "rbxassetid://10734954301",
		["sidebarclose"] = "rbxassetid://10734953715",
		["sidebaropen"] = "rbxassetid://10734954000",
		["sigma"] = "rbxassetid://10734954538",
		["signal"] = "rbxassetid://10734961133",
		["signalhigh"] = "rbxassetid://10734954807",
		["signallow"] = "rbxassetid://10734955080",
		["signalmedium"] = "rbxassetid://10734955336",
		["signalzero"] = "rbxassetid://10734960878",
		["siren"] = "rbxassetid://10734961284",
		["skipback"] = "rbxassetid://10734961526",
		["skipforward"] = "rbxassetid://10734961809",
		["skull"] = "rbxassetid://10734962068",
		["slack"] = "rbxassetid://10734962339",
		["slash"] = "rbxassetid://10734962600",
		["slice"] = "rbxassetid://10734963024",
		["sliders"] = "rbxassetid://10734963400",
		["slidershorizontal"] = "rbxassetid://10734963191",
		["smartphone"] = "rbxassetid://10734963940",
		["smartphonecharging"] = "rbxassetid://10734963671",
		["smile"] = "rbxassetid://10734964441",
		["smileplus"] = "rbxassetid://10734964188",
		["snowflake"] = "rbxassetid://10734964600",
		["sofa"] = "rbxassetid://10734964852",
		["sortasc"] = "rbxassetid://10734965115",
		["sortdesc"] = "rbxassetid://10734965287",
		["speaker"] = "rbxassetid://10734965419",
		["sprout"] = "rbxassetid://10734965572",
		["square"] = "rbxassetid://10734965702",
		["star"] = "rbxassetid://10734966248",
		["starhalf"] = "rbxassetid://10734965897",
		["staroff"] = "rbxassetid://10734966097",
		["stethoscope"] = "rbxassetid://10734966384",
		["sticker"] = "rbxassetid://10734972234",
		["stickynote"] = "rbxassetid://10734972463",
		["stopcircle"] = "rbxassetid://10734972621",
		["stretchhorizontal"] = "rbxassetid://10734972862",
		["stretchvertical"] = "rbxassetid://10734973130",
		["strikethrough"] = "rbxassetid://10734973290",
		["subscript"] = "rbxassetid://10734973457",
		["sun"] = "rbxassetid://10734974297",
		["sundim"] = "rbxassetid://10734973645",
		["sunmedium"] = "rbxassetid://10734973778",
		["sunmoon"] = "rbxassetid://10734973999",
		["sunsnow"] = "rbxassetid://10734974130",
		["sunrise"] = "rbxassetid://10734974522",
		["sunset"] = "rbxassetid://10734974689",
		["superscript"] = "rbxassetid://10734974850",
		["swissfranc"] = "rbxassetid://10734975024",
		["switchcamera"] = "rbxassetid://10734975214",
		["sword"] = "rbxassetid://10734975486",
		["swords"] = "rbxassetid://10734975692",
		["syringe"] = "rbxassetid://10734975932",
		["table"] = "rbxassetid://10734976230",
		["table2"] = "rbxassetid://10734976097",
		["tablet"] = "rbxassetid://10734976394",
		["tag"] = "rbxassetid://10734976528",
		["tags"] = "rbxassetid://10734976739",
		["target"] = "rbxassetid://10734977012",
		["tent"] = "rbxassetid://10734981750",
		["terminal"] = "rbxassetid://10734982144",
		["terminalsquare"] = "rbxassetid://10734981995",
		["textcursor"] = "rbxassetid://10734982395",
		["textcursorinput"] = "rbxassetid://10734982297",
		["thermometer"] = "rbxassetid://10734983134",
		["thermometersnowflake"] = "rbxassetid://10734982571",
		["thermometersun"] = "rbxassetid://10734982771",
		["thumbsdown"] = "rbxassetid://10734983359",
		["thumbsup"] = "rbxassetid://10734983629",
		["ticket"] = "rbxassetid://10734983868",
		["timer"] = "rbxassetid://10734984606",
		["timeroff"] = "rbxassetid://10734984138",
		["timerreset"] = "rbxassetid://10734984355",
		["toggleleft"] = "rbxassetid://10734984834",
		["toggleright"] = "rbxassetid://10734985040",
		["tornado"] = "rbxassetid://10734985247",
		["toybrick"] = "rbxassetid://10747361919",
		["train"] = "rbxassetid://10747362105",
		["trash"] = "rbxassetid://10747362393",
		["trash2"] = "rbxassetid://10747362241",
		["treedeciduous"] = "rbxassetid://10747362534",
		["treepine"] = "rbxassetid://10747362748",
		["trees"] = "rbxassetid://10747363016",
		["trendingdown"] = "rbxassetid://10747363205",
		["trendingup"] = "rbxassetid://10747363465",
		["triangle"] = "rbxassetid://10747363621",
		["trophy"] = "rbxassetid://10747363809",
		["truck"] = "rbxassetid://10747364031",
		["tv"] = "rbxassetid://10747364593",
		["tv2"] = "rbxassetid://10747364302",
		["type"] = "rbxassetid://10747364761",
		["umbrella"] = "rbxassetid://10747364971",
		["underline"] = "rbxassetid://10747365191",
		["undo"] = "rbxassetid://10747365484",
		["undo2"] = "rbxassetid://10747365359",
		["unlink"] = "rbxassetid://10747365771",
		["unlink2"] = "rbxassetid://10747397871",
		["unlock"] = "rbxassetid://10747366027",
		["upload"] = "rbxassetid://10747366434",
		["uploadcloud"] = "rbxassetid://10747366266",
		["usb"] = "rbxassetid://10747366606",
		["user"] = "rbxassetid://10747373176",
		["usercheck"] = "rbxassetid://10747371901",
		["usercog"] = "rbxassetid://10747372167",
		["userminus"] = "rbxassetid://10747372346",
		["userplus"] = "rbxassetid://10747372702",
		["userx"] = "rbxassetid://10747372992",
		["users"] = "rbxassetid://10747373426",
		["utensils"] = "rbxassetid://10747373821",
		["utensilscrossed"] = "rbxassetid://10747373629",
		["venetianmask"] = "rbxassetid://10747374003",
		["verified"] = "rbxassetid://10747374131",
		["vibrate"] = "rbxassetid://10747374489",
		["vibrateoff"] = "rbxassetid://10747374269",
		["video"] = "rbxassetid://10747374938",
		["videooff"] = "rbxassetid://10747374721",
		["view"] = "rbxassetid://10747375132",
		["voicemail"] = "rbxassetid://10747375281",
		["volume"] = "rbxassetid://10747376008",
		["volume1"] = "rbxassetid://10747375450",
		["volume2"] = "rbxassetid://10747375679",
		["volumex"] = "rbxassetid://10747375880",
		["wallet"] = "rbxassetid://10747376205",
		["wand"] = "rbxassetid://10747376565",
		["wand2"] = "rbxassetid://10747376349",
		["watch"] = "rbxassetid://10747376722",
		["waves"] = "rbxassetid://10747376931",
		["webcam"] = "rbxassetid://10747381992",
		["wifi"] = "rbxassetid://10747382504",
		["wifioff"] = "rbxassetid://10747382268",
		["wind"] = "rbxassetid://10747382750",
		["wraptext"] = "rbxassetid://10747383065",
		["wrench"] = "rbxassetid://10747383470",
		["x"] = "rbxassetid://10747384394",
		["xcircle"] = "rbxassetid://10747383819",
		["xoctagon"] = "rbxassetid://10747384037",
		["xsquare"] = "rbxassetid://10747384217",
		["zoomin"] = "rbxassetid://10747384552",
		["zoomout"] = "rbxassetid://10747384679",
		-- Usage method with "lucide-" in the name:
		["lucide-accessibility"] = "rbxassetid://10709751939",
		["lucide-activity"] = "rbxassetid://10709752035",
		["lucide-air-vent"] = "rbxassetid://10709752131",
		["lucide-airplay"] = "rbxassetid://10709752254",
		["lucide-alarm-check"] = "rbxassetid://10709752405",
		["lucide-alarm-clock"] = "rbxassetid://10709752630",
		["lucide-alarm-clock-off"] = "rbxassetid://10709752508",
		["lucide-alarm-minus"] = "rbxassetid://10709752732",
		["lucide-alarm-plus"] = "rbxassetid://10709752825",
		["lucide-album"] = "rbxassetid://10709752906",
		["lucide-alert-circle"] = "rbxassetid://10709752996",
		["lucide-alert-octagon"] = "rbxassetid://10709753064",
		["lucide-alert-triangle"] = "rbxassetid://10709753149",
		["lucide-align-center"] = "rbxassetid://10709753570",
		["lucide-align-center-horizontal"] = "rbxassetid://10709753272",
		["lucide-align-center-vertical"] = "rbxassetid://10709753421",
		["lucide-align-end-horizontal"] = "rbxassetid://10709753692",
		["lucide-align-end-vertical"] = "rbxassetid://10709753808",
		["lucide-align-horizontal-distribute-center"] = "rbxassetid://10747779791",
		["lucide-align-horizontal-distribute-end"] = "rbxassetid://10747784534",
		["lucide-align-horizontal-distribute-start"] = "rbxassetid://10709754118",
		["lucide-align-horizontal-justify-center"] = "rbxassetid://10709754204",
		["lucide-align-horizontal-justify-end"] = "rbxassetid://10709754317",
		["lucide-align-horizontal-justify-start"] = "rbxassetid://10709754436",
		["lucide-align-horizontal-space-around"] = "rbxassetid://10709754590",
		["lucide-align-horizontal-space-between"] = "rbxassetid://10709754749",
		["lucide-align-justify"] = "rbxassetid://10709759610",
		["lucide-align-left"] = "rbxassetid://10709759764",
		["lucide-align-right"] = "rbxassetid://10709759895",
		["lucide-align-start-horizontal"] = "rbxassetid://10709760051",
		["lucide-align-start-vertical"] = "rbxassetid://10709760244",
		["lucide-align-vertical-distribute-center"] = "rbxassetid://10709760351",
		["lucide-align-vertical-distribute-end"] = "rbxassetid://10709760434",
		["lucide-align-vertical-distribute-start"] = "rbxassetid://10709760612",
		["lucide-align-vertical-justify-center"] = "rbxassetid://10709760814",
		["lucide-align-vertical-justify-end"] = "rbxassetid://10709761003",
		["lucide-align-vertical-justify-start"] = "rbxassetid://10709761176",
		["lucide-align-vertical-space-around"] = "rbxassetid://10709761324",
		["lucide-align-vertical-space-between"] = "rbxassetid://10709761434",
		["lucide-anchor"] = "rbxassetid://10709761530",
		["lucide-angry"] = "rbxassetid://10709761629",
		["lucide-annoyed"] = "rbxassetid://10709761722",
		["lucide-aperture"] = "rbxassetid://10709761813",
		["lucide-apple"] = "rbxassetid://10709761889",
		["lucide-archive"] = "rbxassetid://10709762233",
		["lucide-archive-restore"] = "rbxassetid://10709762058",
		["lucide-armchair"] = "rbxassetid://10709762327",
		["lucide-arrow-big-down"] = "rbxassetid://10747796644",
		["lucide-arrow-big-left"] = "rbxassetid://10709762574",
		["lucide-arrow-big-right"] = "rbxassetid://10709762727",
		["lucide-arrow-big-up"] = "rbxassetid://10709762879",
		["lucide-arrow-down"] = "rbxassetid://10709767827",
		["lucide-arrow-down-circle"] = "rbxassetid://10709763034",
		["lucide-arrow-down-left"] = "rbxassetid://10709767656",
		["lucide-arrow-down-right"] = "rbxassetid://10709767750",
		["lucide-arrow-left"] = "rbxassetid://10709768114",
		["lucide-arrow-left-circle"] = "rbxassetid://10709767936",
		["lucide-arrow-left-right"] = "rbxassetid://10709768019",
		["lucide-arrow-right"] = "rbxassetid://10709768347",
		["lucide-arrow-right-circle"] = "rbxassetid://10709768226",
		["lucide-arrow-up"] = "rbxassetid://10709768939",
		["lucide-arrow-up-circle"] = "rbxassetid://10709768432",
		["lucide-arrow-up-down"] = "rbxassetid://10709768538",
		["lucide-arrow-up-left"] = "rbxassetid://10709768661",
		["lucide-arrow-up-right"] = "rbxassetid://10709768787",
		["lucide-asterisk"] = "rbxassetid://10709769095",
		["lucide-at-sign"] = "rbxassetid://10709769286",
		["lucide-award"] = "rbxassetid://10709769406",
		["lucide-axe"] = "rbxassetid://10709769508",
		["lucide-axis-3d"] = "rbxassetid://10709769598",
		["lucide-baby"] = "rbxassetid://10709769732",
		["lucide-backpack"] = "rbxassetid://10709769841",
		["lucide-baggage-claim"] = "rbxassetid://10709769935",
		["lucide-banana"] = "rbxassetid://10709770005",
		["lucide-banknote"] = "rbxassetid://10709770178",
		["lucide-bar-chart"] = "rbxassetid://10709773755",
		["lucide-bar-chart-2"] = "rbxassetid://10709770317",
		["lucide-bar-chart-3"] = "rbxassetid://10709770431",
		["lucide-bar-chart-4"] = "rbxassetid://10709770560",
		["lucide-bar-chart-horizontal"] = "rbxassetid://10709773669",
		["lucide-barcode"] = "rbxassetid://10747360675",
		["lucide-baseline"] = "rbxassetid://10709773863",
		["lucide-bath"] = "rbxassetid://10709773963",
		["lucide-battery"] = "rbxassetid://10709774640",
		["lucide-battery-charging"] = "rbxassetid://10709774068",
		["lucide-battery-full"] = "rbxassetid://10709774206",
		["lucide-battery-low"] = "rbxassetid://10709774370",
		["lucide-battery-medium"] = "rbxassetid://10709774513",
		["lucide-beaker"] = "rbxassetid://10709774756",
		["lucide-bed"] = "rbxassetid://10709775036",
		["lucide-bed-double"] = "rbxassetid://10709774864",
		["lucide-bed-single"] = "rbxassetid://10709774968",
		["lucide-beer"] = "rbxassetid://10709775167",
		["lucide-bell"] = "rbxassetid://10709775704",
		["lucide-bell-minus"] = "rbxassetid://10709775241",
		["lucide-bell-off"] = "rbxassetid://10709775320",
		["lucide-bell-plus"] = "rbxassetid://10709775448",
		["lucide-bell-ring"] = "rbxassetid://10709775560",
		["lucide-bike"] = "rbxassetid://10709775894",
		["lucide-binary"] = "rbxassetid://10709776050",
		["lucide-bitcoin"] = "rbxassetid://10709776126",
		["lucide-bluetooth"] = "rbxassetid://10709776655",
		["lucide-bluetooth-connected"] = "rbxassetid://10709776240",
		["lucide-bluetooth-off"] = "rbxassetid://10709776344",
		["lucide-bluetooth-searching"] = "rbxassetid://10709776501",
		["lucide-bold"] = "rbxassetid://10747813908",
		["lucide-bomb"] = "rbxassetid://10709781460",
		["lucide-bone"] = "rbxassetid://10709781605",
		["lucide-book"] = "rbxassetid://10709781824",
		["lucide-book-open"] = "rbxassetid://10709781717",
		["lucide-bookmark"] = "rbxassetid://10709782154",
		["lucide-bookmark-minus"] = "rbxassetid://10709781919",
		["lucide-bookmark-plus"] = "rbxassetid://10709782044",
		["lucide-bot"] = "rbxassetid://10709782230",
		["lucide-box"] = "rbxassetid://10709782497",
		["lucide-box-select"] = "rbxassetid://10709782342",
		["lucide-boxes"] = "rbxassetid://10709782582",
		["lucide-briefcase"] = "rbxassetid://10709782662",
		["lucide-brush"] = "rbxassetid://10709782758",
		["lucide-bug"] = "rbxassetid://10709782845",
		["lucide-building"] = "rbxassetid://10709783051",
		["lucide-building-2"] = "rbxassetid://10709782939",
		["lucide-bus"] = "rbxassetid://10709783137",
		["lucide-cake"] = "rbxassetid://10709783217",
		["lucide-calculator"] = "rbxassetid://10709783311",
		["lucide-calendar"] = "rbxassetid://10709789505",
		["lucide-calendar-check"] = "rbxassetid://10709783474",
		["lucide-calendar-check-2"] = "rbxassetid://10709783392",
		["lucide-calendar-clock"] = "rbxassetid://10709783577",
		["lucide-calendar-days"] = "rbxassetid://10709783673",
		["lucide-calendar-heart"] = "rbxassetid://10709783835",
		["lucide-calendar-minus"] = "rbxassetid://10709783959",
		["lucide-calendar-off"] = "rbxassetid://10709788784",
		["lucide-calendar-plus"] = "rbxassetid://10709788937",
		["lucide-calendar-range"] = "rbxassetid://10709789053",
		["lucide-calendar-search"] = "rbxassetid://10709789200",
		["lucide-calendar-x"] = "rbxassetid://10709789407",
		["lucide-calendar-x-2"] = "rbxassetid://10709789329",
		["lucide-camera"] = "rbxassetid://10709789686",
		["lucide-camera-off"] = "rbxassetid://10747822677",
		["lucide-car"] = "rbxassetid://10709789810",
		["lucide-carrot"] = "rbxassetid://10709789960",
		["lucide-cast"] = "rbxassetid://10709790097",
		["lucide-charge"] = "rbxassetid://10709790202",
		["lucide-check"] = "rbxassetid://10709790644",
		["lucide-check-circle"] = "rbxassetid://10709790387",
		["lucide-check-circle-2"] = "rbxassetid://10709790298",
		["lucide-check-square"] = "rbxassetid://10709790537",
		["lucide-chef-hat"] = "rbxassetid://10709790757",
		["lucide-cherry"] = "rbxassetid://10709790875",
		["lucide-chevron-down"] = "rbxassetid://10709790948",
		["lucide-chevron-first"] = "rbxassetid://10709791015",
		["lucide-chevron-last"] = "rbxassetid://10709791130",
		["lucide-chevron-left"] = "rbxassetid://10709791281",
		["lucide-chevron-right"] = "rbxassetid://10709791437",
		["lucide-chevron-up"] = "rbxassetid://10709791523",
		["lucide-chevrons-down"] = "rbxassetid://10709796864",
		["lucide-chevrons-down-up"] = "rbxassetid://10709791632",
		["lucide-chevrons-left"] = "rbxassetid://10709797151",
		["lucide-chevrons-left-right"] = "rbxassetid://10709797006",
		["lucide-chevrons-right"] = "rbxassetid://10709797382",
		["lucide-chevrons-right-left"] = "rbxassetid://10709797274",
		["lucide-chevrons-up"] = "rbxassetid://10709797622",
		["lucide-chevrons-up-down"] = "rbxassetid://10709797508",
		["lucide-chrome"] = "rbxassetid://10709797725",
		["lucide-circle"] = "rbxassetid://10709798174",
		["lucide-circle-dot"] = "rbxassetid://10709797837",
		["lucide-circle-ellipsis"] = "rbxassetid://10709797985",
		["lucide-circle-slashed"] = "rbxassetid://10709798100",
		["lucide-citrus"] = "rbxassetid://10709798276",
		["lucide-clapperboard"] = "rbxassetid://10709798350",
		["lucide-clipboard"] = "rbxassetid://10709799288",
		["lucide-clipboard-check"] = "rbxassetid://10709798443",
		["lucide-clipboard-copy"] = "rbxassetid://10709798574",
		["lucide-clipboard-edit"] = "rbxassetid://10709798682",
		["lucide-clipboard-list"] = "rbxassetid://10709798792",
		["lucide-clipboard-signature"] = "rbxassetid://10709798890",
		["lucide-clipboard-type"] = "rbxassetid://10709798999",
		["lucide-clipboard-x"] = "rbxassetid://10709799124",
		["lucide-clock"] = "rbxassetid://10709805144",
		["lucide-clock-1"] = "rbxassetid://10709799535",
		["lucide-clock-10"] = "rbxassetid://10709799718",
		["lucide-clock-11"] = "rbxassetid://10709799818",
		["lucide-clock-12"] = "rbxassetid://10709799962",
		["lucide-clock-2"] = "rbxassetid://10709803876",
		["lucide-clock-3"] = "rbxassetid://10709803989",
		["lucide-clock-4"] = "rbxassetid://10709804164",
		["lucide-clock-5"] = "rbxassetid://10709804291",
		["lucide-clock-6"] = "rbxassetid://10709804435",
		["lucide-clock-7"] = "rbxassetid://10709804599",
		["lucide-clock-8"] = "rbxassetid://10709804784",
		["lucide-clock-9"] = "rbxassetid://10709804996",
		["lucide-cloud"] = "rbxassetid://10709806740",
		["lucide-cloud-cog"] = "rbxassetid://10709805262",
		["lucide-cloud-drizzle"] = "rbxassetid://10709805371",
		["lucide-cloud-fog"] = "rbxassetid://10709805477",
		["lucide-cloud-hail"] = "rbxassetid://10709805596",
		["lucide-cloud-lightning"] = "rbxassetid://10709805727",
		["lucide-cloud-moon"] = "rbxassetid://10709805942",
		["lucide-cloud-moon-rain"] = "rbxassetid://10709805838",
		["lucide-cloud-off"] = "rbxassetid://10709806060",
		["lucide-cloud-rain"] = "rbxassetid://10709806277",
		["lucide-cloud-rain-wind"] = "rbxassetid://10709806166",
		["lucide-cloud-snow"] = "rbxassetid://10709806374",
		["lucide-cloud-sun"] = "rbxassetid://10709806631",
		["lucide-cloud-sun-rain"] = "rbxassetid://10709806475",
		["lucide-cloudy"] = "rbxassetid://10709806859",
		["lucide-clover"] = "rbxassetid://10709806995",
		["lucide-code"] = "rbxassetid://10709810463",
		["lucide-code-2"] = "rbxassetid://10709807111",
		["lucide-codepen"] = "rbxassetid://10709810534",
		["lucide-codesandbox"] = "rbxassetid://10709810676",
		["lucide-coffee"] = "rbxassetid://10709810814",
		["lucide-cog"] = "rbxassetid://10709810948",
		["lucide-coins"] = "rbxassetid://10709811110",
		["lucide-columns"] = "rbxassetid://10709811261",
		["lucide-command"] = "rbxassetid://10709811365",
		["lucide-compass"] = "rbxassetid://10709811445",
		["lucide-component"] = "rbxassetid://10709811595",
		["lucide-concierge-bell"] = "rbxassetid://10709811706",
		["lucide-connection"] = "rbxassetid://10747361219",
		["lucide-contact"] = "rbxassetid://10709811834",
		["lucide-contrast"] = "rbxassetid://10709811939",
		["lucide-cookie"] = "rbxassetid://10709812067",
		["lucide-copy"] = "rbxassetid://10709812159",
		["lucide-copyleft"] = "rbxassetid://10709812251",
		["lucide-copyright"] = "rbxassetid://10709812311",
		["lucide-corner-down-left"] = "rbxassetid://10709812396",
		["lucide-corner-down-right"] = "rbxassetid://10709812485",
		["lucide-corner-left-down"] = "rbxassetid://10709812632",
		["lucide-corner-left-up"] = "rbxassetid://10709812784",
		["lucide-corner-right-down"] = "rbxassetid://10709812939",
		["lucide-corner-right-up"] = "rbxassetid://10709813094",
		["lucide-corner-up-left"] = "rbxassetid://10709813185",
		["lucide-corner-up-right"] = "rbxassetid://10709813281",
		["lucide-cpu"] = "rbxassetid://10709813383",
		["lucide-croissant"] = "rbxassetid://10709818125",
		["lucide-crop"] = "rbxassetid://10709818245",
		["lucide-cross"] = "rbxassetid://10709818399",
		["lucide-crosshair"] = "rbxassetid://10709818534",
		["lucide-crown"] = "rbxassetid://10709818626",
		["lucide-cup-soda"] = "rbxassetid://10709818763",
		["lucide-curly-braces"] = "rbxassetid://10709818847",
		["lucide-currency"] = "rbxassetid://10709818931",
		["lucide-database"] = "rbxassetid://10709818996",
		["lucide-delete"] = "rbxassetid://10709819059",
		["lucide-diamond"] = "rbxassetid://10709819149",
		["lucide-dice-1"] = "rbxassetid://10709819266",
		["lucide-dice-2"] = "rbxassetid://10709819361",
		["lucide-dice-3"] = "rbxassetid://10709819508",
		["lucide-dice-4"] = "rbxassetid://10709819670",
		["lucide-dice-5"] = "rbxassetid://10709819801",
		["lucide-dice-6"] = "rbxassetid://10709819896",
		["lucide-dices"] = "rbxassetid://10723343321",
		["lucide-diff"] = "rbxassetid://10723343416",
		["lucide-disc"] = "rbxassetid://10723343537",
		["lucide-divide"] = "rbxassetid://10723343805",
		["lucide-divide-circle"] = "rbxassetid://10723343636",
		["lucide-divide-square"] = "rbxassetid://10723343737",
		["lucide-dollar-sign"] = "rbxassetid://10723343958",
		["lucide-download"] = "rbxassetid://10723344270",
		["lucide-download-cloud"] = "rbxassetid://10723344088",
		["lucide-droplet"] = "rbxassetid://10723344432",
		["lucide-droplets"] = "rbxassetid://10734883356",
		["lucide-drumstick"] = "rbxassetid://10723344737",
		["lucide-edit"] = "rbxassetid://10734883598",
		["lucide-edit-2"] = "rbxassetid://10723344885",
		["lucide-edit-3"] = "rbxassetid://10723345088",
		["lucide-egg"] = "rbxassetid://10723345518",
		["lucide-egg-fried"] = "rbxassetid://10723345347",
		["lucide-electricity"] = "rbxassetid://10723345749",
		["lucide-electricity-off"] = "rbxassetid://10723345643",
		["lucide-equal"] = "rbxassetid://10723345990",
		["lucide-equal-not"] = "rbxassetid://10723345866",
		["lucide-eraser"] = "rbxassetid://10723346158",
		["lucide-euro"] = "rbxassetid://10723346372",
		["lucide-expand"] = "rbxassetid://10723346553",
		["lucide-external-link"] = "rbxassetid://10723346684",
		["lucide-eye"] = "rbxassetid://10723346959",
		["lucide-eye-off"] = "rbxassetid://10723346871",
		["lucide-factory"] = "rbxassetid://10723347051",
		["lucide-fan"] = "rbxassetid://10723354359",
		["lucide-fast-forward"] = "rbxassetid://10723354521",
		["lucide-feather"] = "rbxassetid://10723354671",
		["lucide-figma"] = "rbxassetid://10723354801",
		["lucide-file"] = "rbxassetid://10723374641",
		["lucide-file-archive"] = "rbxassetid://10723354921",
		["lucide-file-audio"] = "rbxassetid://10723355148",
		["lucide-file-audio-2"] = "rbxassetid://10723355026",
		["lucide-file-axis-3d"] = "rbxassetid://10723355272",
		["lucide-file-badge"] = "rbxassetid://10723355622",
		["lucide-file-badge-2"] = "rbxassetid://10723355451",
		["lucide-file-bar-chart"] = "rbxassetid://10723355887",
		["lucide-file-bar-chart-2"] = "rbxassetid://10723355746",
		["lucide-file-box"] = "rbxassetid://10723355989",
		["lucide-file-check"] = "rbxassetid://10723356210",
		["lucide-file-check-2"] = "rbxassetid://10723356100",
		["lucide-file-clock"] = "rbxassetid://10723356329",
		["lucide-file-code"] = "rbxassetid://10723356507",
		["lucide-file-cog"] = "rbxassetid://10723356830",
		["lucide-file-cog-2"] = "rbxassetid://10723356676",
		["lucide-file-diff"] = "rbxassetid://10723357039",
		["lucide-file-digit"] = "rbxassetid://10723357151",
		["lucide-file-down"] = "rbxassetid://10723357322",
		["lucide-file-edit"] = "rbxassetid://10723357495",
		["lucide-file-heart"] = "rbxassetid://10723357637",
		["lucide-file-image"] = "rbxassetid://10723357790",
		["lucide-file-input"] = "rbxassetid://10723357933",
		["lucide-file-json"] = "rbxassetid://10723364435",
		["lucide-file-json-2"] = "rbxassetid://10723364361",
		["lucide-file-key"] = "rbxassetid://10723364605",
		["lucide-file-key-2"] = "rbxassetid://10723364515",
		["lucide-file-line-chart"] = "rbxassetid://10723364725",
		["lucide-file-lock"] = "rbxassetid://10723364957",
		["lucide-file-lock-2"] = "rbxassetid://10723364861",
		["lucide-file-minus"] = "rbxassetid://10723365254",
		["lucide-file-minus-2"] = "rbxassetid://10723365086",
		["lucide-file-output"] = "rbxassetid://10723365457",
		["lucide-file-pie-chart"] = "rbxassetid://10723365598",
		["lucide-file-plus"] = "rbxassetid://10723365877",
		["lucide-file-plus-2"] = "rbxassetid://10723365766",
		["lucide-file-question"] = "rbxassetid://10723365987",
		["lucide-file-scan"] = "rbxassetid://10723366167",
		["lucide-file-search"] = "rbxassetid://10723366550",
		["lucide-file-search-2"] = "rbxassetid://10723366340",
		["lucide-file-signature"] = "rbxassetid://10723366741",
		["lucide-file-spreadsheet"] = "rbxassetid://10723366962",
		["lucide-file-symlink"] = "rbxassetid://10723367098",
		["lucide-file-terminal"] = "rbxassetid://10723367244",
		["lucide-file-text"] = "rbxassetid://10723367380",
		["lucide-file-type"] = "rbxassetid://10723367606",
		["lucide-file-type-2"] = "rbxassetid://10723367509",
		["lucide-file-up"] = "rbxassetid://10723367734",
		["lucide-file-video"] = "rbxassetid://10723373884",
		["lucide-file-video-2"] = "rbxassetid://10723367834",
		["lucide-file-volume"] = "rbxassetid://10723374172",
		["lucide-file-volume-2"] = "rbxassetid://10723374030",
		["lucide-file-warning"] = "rbxassetid://10723374276",
		["lucide-file-x"] = "rbxassetid://10723374544",
		["lucide-file-x-2"] = "rbxassetid://10723374378",
		["lucide-files"] = "rbxassetid://10723374759",
		["lucide-film"] = "rbxassetid://10723374981",
		["lucide-filter"] = "rbxassetid://10723375128",
		["lucide-fingerprint"] = "rbxassetid://10723375250",
		["lucide-flag"] = "rbxassetid://10723375890",
		["lucide-flag-off"] = "rbxassetid://10723375443",
		["lucide-flag-triangle-left"] = "rbxassetid://10723375608",
		["lucide-flag-triangle-right"] = "rbxassetid://10723375727",
		["lucide-flame"] = "rbxassetid://10723376114",
		["lucide-flashlight"] = "rbxassetid://10723376471",
		["lucide-flashlight-off"] = "rbxassetid://10723376365",
		["lucide-flask-conical"] = "rbxassetid://10734883986",
		["lucide-flask-round"] = "rbxassetid://10723376614",
		["lucide-flip-horizontal"] = "rbxassetid://10723376884",
		["lucide-flip-horizontal-2"] = "rbxassetid://10723376745",
		["lucide-flip-vertical"] = "rbxassetid://10723377138",
		["lucide-flip-vertical-2"] = "rbxassetid://10723377026",
		["lucide-flower"] = "rbxassetid://10747830374",
		["lucide-flower-2"] = "rbxassetid://10723377305",
		["lucide-focus"] = "rbxassetid://10723377537",
		["lucide-folder"] = "rbxassetid://10723387563",
		["lucide-folder-archive"] = "rbxassetid://10723384478",
		["lucide-folder-check"] = "rbxassetid://10723384605",
		["lucide-folder-clock"] = "rbxassetid://10723384731",
		["lucide-folder-closed"] = "rbxassetid://10723384893",
		["lucide-folder-cog"] = "rbxassetid://10723385213",
		["lucide-folder-cog-2"] = "rbxassetid://10723385036",
		["lucide-folder-down"] = "rbxassetid://10723385338",
		["lucide-folder-edit"] = "rbxassetid://10723385445",
		["lucide-folder-heart"] = "rbxassetid://10723385545",
		["lucide-folder-input"] = "rbxassetid://10723385721",
		["lucide-folder-key"] = "rbxassetid://10723385848",
		["lucide-folder-lock"] = "rbxassetid://10723386005",
		["lucide-folder-minus"] = "rbxassetid://10723386127",
		["lucide-folder-open"] = "rbxassetid://10723386277",
		["lucide-folder-output"] = "rbxassetid://10723386386",
		["lucide-folder-plus"] = "rbxassetid://10723386531",
		["lucide-folder-search"] = "rbxassetid://10723386787",
		["lucide-folder-search-2"] = "rbxassetid://10723386674",
		["lucide-folder-symlink"] = "rbxassetid://10723386930",
		["lucide-folder-tree"] = "rbxassetid://10723387085",
		["lucide-folder-up"] = "rbxassetid://10723387265",
		["lucide-folder-x"] = "rbxassetid://10723387448",
		["lucide-folders"] = "rbxassetid://10723387721",
		["lucide-form-input"] = "rbxassetid://10723387841",
		["lucide-forward"] = "rbxassetid://10723388016",
		["lucide-frame"] = "rbxassetid://10723394389",
		["lucide-framer"] = "rbxassetid://10723394565",
		["lucide-frown"] = "rbxassetid://10723394681",
		["lucide-fuel"] = "rbxassetid://10723394846",
		["lucide-function-square"] = "rbxassetid://10723395041",
		["lucide-gamepad"] = "rbxassetid://10723395457",
		["lucide-gamepad-2"] = "rbxassetid://10723395215",
		["lucide-gauge"] = "rbxassetid://10723395708",
		["lucide-gavel"] = "rbxassetid://10723395896",
		["lucide-gem"] = "rbxassetid://10723396000",
		["lucide-ghost"] = "rbxassetid://10723396107",
		["lucide-gift"] = "rbxassetid://10723396402",
		["lucide-gift-card"] = "rbxassetid://10723396225",
		["lucide-git-branch"] = "rbxassetid://10723396676",
		["lucide-git-branch-plus"] = "rbxassetid://10723396542",
		["lucide-git-commit"] = "rbxassetid://10723396812",
		["lucide-git-compare"] = "rbxassetid://10723396954",
		["lucide-git-fork"] = "rbxassetid://10723397049",
		["lucide-git-merge"] = "rbxassetid://10723397165",
		["lucide-git-pull-request"] = "rbxassetid://10723397431",
		["lucide-git-pull-request-closed"] = "rbxassetid://10723397268",
		["lucide-git-pull-request-draft"] = "rbxassetid://10734884302",
		["lucide-glass"] = "rbxassetid://10723397788",
		["lucide-glass-2"] = "rbxassetid://10723397529",
		["lucide-glass-water"] = "rbxassetid://10723397678",
		["lucide-glasses"] = "rbxassetid://10723397895",
		["lucide-globe"] = "rbxassetid://10723404337",
		["lucide-globe-2"] = "rbxassetid://10723398002",
		["lucide-grab"] = "rbxassetid://10723404472",
		["lucide-graduation-cap"] = "rbxassetid://10723404691",
		["lucide-grape"] = "rbxassetid://10723404822",
		["lucide-grid"] = "rbxassetid://10723404936",
		["lucide-grip-horizontal"] = "rbxassetid://10723405089",
		["lucide-grip-vertical"] = "rbxassetid://10723405236",
		["lucide-hammer"] = "rbxassetid://10723405360",
		["lucide-hand"] = "rbxassetid://10723405649",
		["lucide-hand-metal"] = "rbxassetid://10723405508",
		["lucide-hard-drive"] = "rbxassetid://10723405749",
		["lucide-hard-hat"] = "rbxassetid://10723405859",
		["lucide-hash"] = "rbxassetid://10723405975",
		["lucide-haze"] = "rbxassetid://10723406078",
		["lucide-headphones"] = "rbxassetid://10723406165",
		["lucide-heart"] = "rbxassetid://10723406885",
		["lucide-heart-crack"] = "rbxassetid://10723406299",
		["lucide-heart-handshake"] = "rbxassetid://10723406480",
		["lucide-heart-off"] = "rbxassetid://10723406662",
		["lucide-heart-pulse"] = "rbxassetid://10723406795",
		["lucide-help-circle"] = "rbxassetid://10723406988",
		["lucide-hexagon"] = "rbxassetid://10723407092",
		["lucide-highlighter"] = "rbxassetid://10723407192",
		["lucide-history"] = "rbxassetid://10723407335",
		["lucide-home"] = "rbxassetid://10723407389",
		["lucide-hourglass"] = "rbxassetid://10723407498",
		["lucide-ice-cream"] = "rbxassetid://10723414308",
		["lucide-image"] = "rbxassetid://10723415040",
		["lucide-image-minus"] = "rbxassetid://10723414487",
		["lucide-image-off"] = "rbxassetid://10723414677",
		["lucide-image-plus"] = "rbxassetid://10723414827",
		["lucide-import"] = "rbxassetid://10723415205",
		["lucide-inbox"] = "rbxassetid://10723415335",
		["lucide-indent"] = "rbxassetid://10723415494",
		["lucide-indian-rupee"] = "rbxassetid://10723415642",
		["lucide-infinity"] = "rbxassetid://10723415766",
		["lucide-info"] = "rbxassetid://10723415903",
		["lucide-inspect"] = "rbxassetid://10723416057",
		["lucide-italic"] = "rbxassetid://10723416195",
		["lucide-japanese-yen"] = "rbxassetid://10723416363",
		["lucide-joystick"] = "rbxassetid://10723416527",
		["lucide-key"] = "rbxassetid://10723416652",
		["lucide-keyboard"] = "rbxassetid://10723416765",
		["lucide-lamp"] = "rbxassetid://10723417513",
		["lucide-lamp-ceiling"] = "rbxassetid://10723416922",
		["lucide-lamp-desk"] = "rbxassetid://10723417016",
		["lucide-lamp-floor"] = "rbxassetid://10723417131",
		["lucide-lamp-wall-down"] = "rbxassetid://10723417240",
		["lucide-lamp-wall-up"] = "rbxassetid://10723417356",
		["lucide-landmark"] = "rbxassetid://10723417608",
		["lucide-languages"] = "rbxassetid://10723417703",
		["lucide-laptop"] = "rbxassetid://10723423881",
		["lucide-laptop-2"] = "rbxassetid://10723417797",
		["lucide-lasso"] = "rbxassetid://10723424235",
		["lucide-lasso-select"] = "rbxassetid://10723424058",
		["lucide-laugh"] = "rbxassetid://10723424372",
		["lucide-layers"] = "rbxassetid://10723424505",
		["lucide-layout"] = "rbxassetid://10723425376",
		["lucide-layout-dashboard"] = "rbxassetid://10723424646",
		["lucide-layout-grid"] = "rbxassetid://10723424838",
		["lucide-layout-list"] = "rbxassetid://10723424963",
		["lucide-layout-template"] = "rbxassetid://10723425187",
		["lucide-leaf"] = "rbxassetid://10723425539",
		["lucide-library"] = "rbxassetid://10723425615",
		["lucide-life-buoy"] = "rbxassetid://10723425685",
		["lucide-lightbulb"] = "rbxassetid://10723425852",
		["lucide-lightbulb-off"] = "rbxassetid://10723425762",
		["lucide-line-chart"] = "rbxassetid://10723426393",
		["lucide-link"] = "rbxassetid://10723426722",
		["lucide-link-2"] = "rbxassetid://10723426595",
		["lucide-link-2-off"] = "rbxassetid://10723426513",
		["lucide-list"] = "rbxassetid://10723433811",
		["lucide-list-checks"] = "rbxassetid://10734884548",
		["lucide-list-end"] = "rbxassetid://10723426886",
		["lucide-list-minus"] = "rbxassetid://10723426986",
		["lucide-list-music"] = "rbxassetid://10723427081",
		["lucide-list-ordered"] = "rbxassetid://10723427199",
		["lucide-list-plus"] = "rbxassetid://10723427334",
		["lucide-list-start"] = "rbxassetid://10723427494",
		["lucide-list-video"] = "rbxassetid://10723427619",
		["lucide-list-x"] = "rbxassetid://10723433655",
		["lucide-loader"] = "rbxassetid://10723434070",
		["lucide-loader-2"] = "rbxassetid://10723433935",
		["lucide-locate"] = "rbxassetid://10723434557",
		["lucide-locate-fixed"] = "rbxassetid://10723434236",
		["lucide-locate-off"] = "rbxassetid://10723434379",
		["lucide-lock"] = "rbxassetid://10723434711",
		["lucide-log-in"] = "rbxassetid://10723434830",
		["lucide-log-out"] = "rbxassetid://10723434906",
		["lucide-luggage"] = "rbxassetid://10723434993",
		["lucide-magnet"] = "rbxassetid://10723435069",
		["lucide-mail"] = "rbxassetid://10734885430",
		["lucide-mail-check"] = "rbxassetid://10723435182",
		["lucide-mail-minus"] = "rbxassetid://10723435261",
		["lucide-mail-open"] = "rbxassetid://10723435342",
		["lucide-mail-plus"] = "rbxassetid://10723435443",
		["lucide-mail-question"] = "rbxassetid://10723435515",
		["lucide-mail-search"] = "rbxassetid://10734884739",
		["lucide-mail-warning"] = "rbxassetid://10734885015",
		["lucide-mail-x"] = "rbxassetid://10734885247",
		["lucide-mails"] = "rbxassetid://10734885614",
		["lucide-map"] = "rbxassetid://10734886202",
		["lucide-map-pin"] = "rbxassetid://10734886004",
		["lucide-map-pin-off"] = "rbxassetid://10734885803",
		["lucide-maximize"] = "rbxassetid://10734886735",
		["lucide-maximize-2"] = "rbxassetid://10734886496",
		["lucide-medal"] = "rbxassetid://10734887072",
		["lucide-megaphone"] = "rbxassetid://10734887454",
		["lucide-megaphone-off"] = "rbxassetid://10734887311",
		["lucide-meh"] = "rbxassetid://10734887603",
		["lucide-menu"] = "rbxassetid://10734887784",
		["lucide-message-circle"] = "rbxassetid://10734888000",
		["lucide-message-square"] = "rbxassetid://10734888228",
		["lucide-mic"] = "rbxassetid://10734888864",
		["lucide-mic-2"] = "rbxassetid://10734888430",
		["lucide-mic-off"] = "rbxassetid://10734888646",
		["lucide-microscope"] = "rbxassetid://10734889106",
		["lucide-microwave"] = "rbxassetid://10734895076",
		["lucide-milestone"] = "rbxassetid://10734895310",
		["lucide-minimize"] = "rbxassetid://10734895698",
		["lucide-minimize-2"] = "rbxassetid://10734895530",
		["lucide-minus"] = "rbxassetid://10734896206",
		["lucide-minus-circle"] = "rbxassetid://10734895856",
		["lucide-minus-square"] = "rbxassetid://10734896029",
		["lucide-monitor"] = "rbxassetid://10734896881",
		["lucide-monitor-off"] = "rbxassetid://10734896360",
		["lucide-monitor-speaker"] = "rbxassetid://10734896512",
		["lucide-moon"] = "rbxassetid://10734897102",
		["lucide-more-horizontal"] = "rbxassetid://10734897250",
		["lucide-more-vertical"] = "rbxassetid://10734897387",
		["lucide-mountain"] = "rbxassetid://10734897956",
		["lucide-mountain-snow"] = "rbxassetid://10734897665",
		["lucide-mouse"] = "rbxassetid://10734898592",
		["lucide-mouse-pointer"] = "rbxassetid://10734898476",
		["lucide-mouse-pointer-2"] = "rbxassetid://10734898194",
		["lucide-mouse-pointer-click"] = "rbxassetid://10734898355",
		["lucide-move"] = "rbxassetid://10734900011",
		["lucide-move-3d"] = "rbxassetid://10734898756",
		["lucide-move-diagonal"] = "rbxassetid://10734899164",
		["lucide-move-diagonal-2"] = "rbxassetid://10734898934",
		["lucide-move-horizontal"] = "rbxassetid://10734899414",
		["lucide-move-vertical"] = "rbxassetid://10734899821",
		["lucide-music"] = "rbxassetid://10734905958",
		["lucide-music-2"] = "rbxassetid://10734900215",
		["lucide-music-3"] = "rbxassetid://10734905665",
		["lucide-music-4"] = "rbxassetid://10734905823",
		["lucide-navigation"] = "rbxassetid://10734906744",
		["lucide-navigation-2"] = "rbxassetid://10734906332",
		["lucide-navigation-2-off"] = "rbxassetid://10734906144",
		["lucide-navigation-off"] = "rbxassetid://10734906580",
		["lucide-network"] = "rbxassetid://10734906975",
		["lucide-newspaper"] = "rbxassetid://10734907168",
		["lucide-octagon"] = "rbxassetid://10734907361",
		["lucide-option"] = "rbxassetid://10734907649",
		["lucide-outdent"] = "rbxassetid://10734907933",
		["lucide-package"] = "rbxassetid://10734909540",
		["lucide-package-2"] = "rbxassetid://10734908151",
		["lucide-package-check"] = "rbxassetid://10734908384",
		["lucide-package-minus"] = "rbxassetid://10734908626",
		["lucide-package-open"] = "rbxassetid://10734908793",
		["lucide-package-plus"] = "rbxassetid://10734909016",
		["lucide-package-search"] = "rbxassetid://10734909196",
		["lucide-package-x"] = "rbxassetid://10734909375",
		["lucide-paint-bucket"] = "rbxassetid://10734909847",
		["lucide-paintbrush"] = "rbxassetid://10734910187",
		["lucide-paintbrush-2"] = "rbxassetid://10734910030",
		["lucide-palette"] = "rbxassetid://10734910430",
		["lucide-palmtree"] = "rbxassetid://10734910680",
		["lucide-paperclip"] = "rbxassetid://10734910927",
		["lucide-party-popper"] = "rbxassetid://10734918735",
		["lucide-pause"] = "rbxassetid://10734919336",
		["lucide-pause-circle"] = "rbxassetid://10735024209",
		["lucide-pause-octagon"] = "rbxassetid://10734919143",
		["lucide-pen-tool"] = "rbxassetid://10734919503",
		["lucide-pencil"] = "rbxassetid://10734919691",
		["lucide-percent"] = "rbxassetid://10734919919",
		["lucide-person-standing"] = "rbxassetid://10734920149",
		["lucide-phone"] = "rbxassetid://10734921524",
		["lucide-phone-call"] = "rbxassetid://10734920305",
		["lucide-phone-forwarded"] = "rbxassetid://10734920508",
		["lucide-phone-incoming"] = "rbxassetid://10734920694",
		["lucide-phone-missed"] = "rbxassetid://10734920845",
		["lucide-phone-off"] = "rbxassetid://10734921077",
		["lucide-phone-outgoing"] = "rbxassetid://10734921288",
		["lucide-pie-chart"] = "rbxassetid://10734921727",
		["lucide-piggy-bank"] = "rbxassetid://10734921935",
		["lucide-pin"] = "rbxassetid://10734922324",
		["lucide-pin-off"] = "rbxassetid://10734922180",
		["lucide-pipette"] = "rbxassetid://10734922497",
		["lucide-pizza"] = "rbxassetid://10734922774",
		["lucide-plane"] = "rbxassetid://10734922971",
		["lucide-play"] = "rbxassetid://10734923549",
		["lucide-play-circle"] = "rbxassetid://10734923214",
		["lucide-plus"] = "rbxassetid://10734924532",
		["lucide-plus-circle"] = "rbxassetid://10734923868",
		["lucide-plus-square"] = "rbxassetid://10734924219",
		["lucide-podcast"] = "rbxassetid://10734929553",
		["lucide-pointer"] = "rbxassetid://10734929723",
		["lucide-pound-sterling"] = "rbxassetid://10734929981",
		["lucide-power"] = "rbxassetid://10734930466",
		["lucide-power-off"] = "rbxassetid://10734930257",
		["lucide-printer"] = "rbxassetid://10734930632",
		["lucide-puzzle"] = "rbxassetid://10734930886",
		["lucide-quote"] = "rbxassetid://10734931234",
		["lucide-radio"] = "rbxassetid://10734931596",
		["lucide-radio-receiver"] = "rbxassetid://10734931402",
		["lucide-rectangle-horizontal"] = "rbxassetid://10734931777",
		["lucide-rectangle-vertical"] = "rbxassetid://10734932081",
		["lucide-recycle"] = "rbxassetid://10734932295",
		["lucide-redo"] = "rbxassetid://10734932822",
		["lucide-redo-2"] = "rbxassetid://10734932586",
		["lucide-refresh-ccw"] = "rbxassetid://10734933056",
		["lucide-refresh-cw"] = "rbxassetid://10734933222",
		["lucide-refrigerator"] = "rbxassetid://10734933465",
		["lucide-regex"] = "rbxassetid://10734933655",
		["lucide-repeat"] = "rbxassetid://10734933966",
		["lucide-repeat-1"] = "rbxassetid://10734933826",
		["lucide-reply"] = "rbxassetid://10734934252",
		["lucide-reply-all"] = "rbxassetid://10734934132",
		["lucide-rewind"] = "rbxassetid://10734934347",
		["lucide-rocket"] = "rbxassetid://10734934585",
		["lucide-rocking-chair"] = "rbxassetid://10734939942",
		["lucide-rotate-3d"] = "rbxassetid://10734940107",
		["lucide-rotate-ccw"] = "rbxassetid://10734940376",
		["lucide-rotate-cw"] = "rbxassetid://10734940654",
		["lucide-rss"] = "rbxassetid://10734940825",
		["lucide-ruler"] = "rbxassetid://10734941018",
		["lucide-russian-ruble"] = "rbxassetid://10734941199",
		["lucide-sailboat"] = "rbxassetid://10734941354",
		["lucide-save"] = "rbxassetid://10734941499",
		["lucide-scale"] = "rbxassetid://10734941912",
		["lucide-scale-3d"] = "rbxassetid://10734941739",
		["lucide-scaling"] = "rbxassetid://10734942072",
		["lucide-scan"] = "rbxassetid://10734942565",
		["lucide-scan-face"] = "rbxassetid://10734942198",
		["lucide-scan-line"] = "rbxassetid://10734942351",
		["lucide-scissors"] = "rbxassetid://10734942778",
		["lucide-screen-share"] = "rbxassetid://10734943193",
		["lucide-screen-share-off"] = "rbxassetid://10734942967",
		["lucide-scroll"] = "rbxassetid://10734943448",
		["lucide-search"] = "rbxassetid://10734943674",
		["lucide-send"] = "rbxassetid://10734943902",
		["lucide-separator-horizontal"] = "rbxassetid://10734944115",
		["lucide-separator-vertical"] = "rbxassetid://10734944326",
		["lucide-server"] = "rbxassetid://10734949856",
		["lucide-server-cog"] = "rbxassetid://10734944444",
		["lucide-server-crash"] = "rbxassetid://10734944554",
		["lucide-server-off"] = "rbxassetid://10734944668",
		["lucide-settings"] = "rbxassetid://10734950309",
		["lucide-settings-2"] = "rbxassetid://10734950020",
		["lucide-share"] = "rbxassetid://10734950813",
		["lucide-share-2"] = "rbxassetid://10734950553",
		["lucide-sheet"] = "rbxassetid://10734951038",
		["lucide-shield"] = "rbxassetid://10734951847",
		["lucide-shield-alert"] = "rbxassetid://10734951173",
		["lucide-shield-check"] = "rbxassetid://10734951367",
		["lucide-shield-close"] = "rbxassetid://10734951535",
		["lucide-shield-off"] = "rbxassetid://10734951684",
		["lucide-shirt"] = "rbxassetid://10734952036",
		["lucide-shopping-bag"] = "rbxassetid://10734952273",
		["lucide-shopping-cart"] = "rbxassetid://10734952479",
		["lucide-shovel"] = "rbxassetid://10734952773",
		["lucide-shower-head"] = "rbxassetid://10734952942",
		["lucide-shrink"] = "rbxassetid://10734953073",
		["lucide-shrub"] = "rbxassetid://10734953241",
		["lucide-shuffle"] = "rbxassetid://10734953451",
		["lucide-sidebar"] = "rbxassetid://10734954301",
		["lucide-sidebar-close"] = "rbxassetid://10734953715",
		["lucide-sidebar-open"] = "rbxassetid://10734954000",
		["lucide-sigma"] = "rbxassetid://10734954538",
		["lucide-signal"] = "rbxassetid://10734961133",
		["lucide-signal-high"] = "rbxassetid://10734954807",
		["lucide-signal-low"] = "rbxassetid://10734955080",
		["lucide-signal-medium"] = "rbxassetid://10734955336",
		["lucide-signal-zero"] = "rbxassetid://10734960878",
		["lucide-siren"] = "rbxassetid://10734961284",
		["lucide-skip-back"] = "rbxassetid://10734961526",
		["lucide-skip-forward"] = "rbxassetid://10734961809",
		["lucide-skull"] = "rbxassetid://10734962068",
		["lucide-slack"] = "rbxassetid://10734962339",
		["lucide-slash"] = "rbxassetid://10734962600",
		["lucide-slice"] = "rbxassetid://10734963024",
		["lucide-sliders"] = "rbxassetid://10734963400",
		["lucide-sliders-horizontal"] = "rbxassetid://10734963191",
		["lucide-smartphone"] = "rbxassetid://10734963940",
		["lucide-smartphone-charging"] = "rbxassetid://10734963671",
		["lucide-smile"] = "rbxassetid://10734964441",
		["lucide-smile-plus"] = "rbxassetid://10734964188",
		["lucide-snowflake"] = "rbxassetid://10734964600",
		["lucide-sofa"] = "rbxassetid://10734964852",
		["lucide-sort-asc"] = "rbxassetid://10734965115",
		["lucide-sort-desc"] = "rbxassetid://10734965287",
		["lucide-speaker"] = "rbxassetid://10734965419",
		["lucide-sprout"] = "rbxassetid://10734965572",
		["lucide-square"] = "rbxassetid://10734965702",
		["lucide-star"] = "rbxassetid://10734966248",
		["lucide-star-half"] = "rbxassetid://10734965897",
		["lucide-star-off"] = "rbxassetid://10734966097",
		["lucide-stethoscope"] = "rbxassetid://10734966384",
		["lucide-sticker"] = "rbxassetid://10734972234",
		["lucide-sticky-note"] = "rbxassetid://10734972463",
		["lucide-stop-circle"] = "rbxassetid://10734972621",
		["lucide-stretch-horizontal"] = "rbxassetid://10734972862",
		["lucide-stretch-vertical"] = "rbxassetid://10734973130",
		["lucide-strikethrough"] = "rbxassetid://10734973290",
		["lucide-subscript"] = "rbxassetid://10734973457",
		["lucide-sun"] = "rbxassetid://10734974297",
		["lucide-sun-dim"] = "rbxassetid://10734973645",
		["lucide-sun-medium"] = "rbxassetid://10734973778",
		["lucide-sun-moon"] = "rbxassetid://10734973999",
		["lucide-sun-snow"] = "rbxassetid://10734974130",
		["lucide-sunrise"] = "rbxassetid://10734974522",
		["lucide-sunset"] = "rbxassetid://10734974689",
		["lucide-superscript"] = "rbxassetid://10734974850",
		["lucide-swiss-franc"] = "rbxassetid://10734975024",
		["lucide-switch-camera"] = "rbxassetid://10734975214",
		["lucide-sword"] = "rbxassetid://10734975486",
		["lucide-swords"] = "rbxassetid://10734975692",
		["lucide-syringe"] = "rbxassetid://10734975932",
		["lucide-table"] = "rbxassetid://10734976230",
		["lucide-table-2"] = "rbxassetid://10734976097",
		["lucide-tablet"] = "rbxassetid://10734976394",
		["lucide-tag"] = "rbxassetid://10734976528",
		["lucide-tags"] = "rbxassetid://10734976739",
		["lucide-target"] = "rbxassetid://10734977012",
		["lucide-tent"] = "rbxassetid://10734981750",
		["lucide-terminal"] = "rbxassetid://10734982144",
		["lucide-terminal-square"] = "rbxassetid://10734981995",
		["lucide-text-cursor"] = "rbxassetid://10734982395",
		["lucide-text-cursor-input"] = "rbxassetid://10734982297",
		["lucide-thermometer"] = "rbxassetid://10734983134",
		["lucide-thermometer-snowflake"] = "rbxassetid://10734982571",
		["lucide-thermometer-sun"] = "rbxassetid://10734982771",
		["lucide-thumbs-down"] = "rbxassetid://10734983359",
		["lucide-thumbs-up"] = "rbxassetid://10734983629",
		["lucide-ticket"] = "rbxassetid://10734983868",
		["lucide-timer"] = "rbxassetid://10734984606",
		["lucide-timer-off"] = "rbxassetid://10734984138",
		["lucide-timer-reset"] = "rbxassetid://10734984355",
		["lucide-toggle-left"] = "rbxassetid://10734984834",
		["lucide-toggle-right"] = "rbxassetid://10734985040",
		["lucide-tornado"] = "rbxassetid://10734985247",
		["lucide-toy-brick"] = "rbxassetid://10747361919",
		["lucide-train"] = "rbxassetid://10747362105",
		["lucide-trash"] = "rbxassetid://10747362393",
		["lucide-trash-2"] = "rbxassetid://10747362241",
		["lucide-tree-deciduous"] = "rbxassetid://10747362534",
		["lucide-tree-pine"] = "rbxassetid://10747362748",
		["lucide-trees"] = "rbxassetid://10747363016",
		["lucide-trending-down"] = "rbxassetid://10747363205",
		["lucide-trending-up"] = "rbxassetid://10747363465",
		["lucide-triangle"] = "rbxassetid://10747363621",
		["lucide-trophy"] = "rbxassetid://10747363809",
		["lucide-truck"] = "rbxassetid://10747364031",
		["lucide-tv"] = "rbxassetid://10747364593",
		["lucide-tv-2"] = "rbxassetid://10747364302",
		["lucide-type"] = "rbxassetid://10747364761",
		["lucide-umbrella"] = "rbxassetid://10747364971",
		["lucide-underline"] = "rbxassetid://10747365191",
		["lucide-undo"] = "rbxassetid://10747365484",
		["lucide-undo-2"] = "rbxassetid://10747365359",
		["lucide-unlink"] = "rbxassetid://10747365771",
		["lucide-unlink-2"] = "rbxassetid://10747397871",
		["lucide-unlock"] = "rbxassetid://10747366027",
		["lucide-upload"] = "rbxassetid://10747366434",
		["lucide-upload-cloud"] = "rbxassetid://10747366266",
		["lucide-usb"] = "rbxassetid://10747366606",
		["lucide-user"] = "rbxassetid://10747373176",
		["lucide-user-check"] = "rbxassetid://10747371901",
		["lucide-user-cog"] = "rbxassetid://10747372167",
		["lucide-user-minus"] = "rbxassetid://10747372346",
		["lucide-user-plus"] = "rbxassetid://10747372702",
		["lucide-user-x"] = "rbxassetid://10747372992",
		["lucide-users"] = "rbxassetid://10747373426",
		["lucide-utensils"] = "rbxassetid://10747373821",
		["lucide-utensils-crossed"] = "rbxassetid://10747373629",
		["lucide-venetian-mask"] = "rbxassetid://10747374003",
		["lucide-verified"] = "rbxassetid://10747374131",
		["lucide-vibrate"] = "rbxassetid://10747374489",
		["lucide-vibrate-off"] = "rbxassetid://10747374269",
		["lucide-video"] = "rbxassetid://10747374938",
		["lucide-video-off"] = "rbxassetid://10747374721",
		["lucide-view"] = "rbxassetid://10747375132",
		["lucide-voicemail"] = "rbxassetid://10747375281",
		["lucide-volume"] = "rbxassetid://10747376008",
		["lucide-volume-1"] = "rbxassetid://10747375450",
		["lucide-volume-2"] = "rbxassetid://10747375679",
		["lucide-volume-x"] = "rbxassetid://10747375880",
		["lucide-wallet"] = "rbxassetid://10747376205",
		["lucide-wand"] = "rbxassetid://10747376565",
		["lucide-wand-2"] = "rbxassetid://10747376349",
		["lucide-watch"] = "rbxassetid://10747376722",
		["lucide-waves"] = "rbxassetid://10747376931",
		["lucide-webcam"] = "rbxassetid://10747381992",
		["lucide-wifi"] = "rbxassetid://10747382504",
		["lucide-wifi-off"] = "rbxassetid://10747382268",
		["lucide-wind"] = "rbxassetid://10747382750",
		["lucide-wrap-text"] = "rbxassetid://10747383065",
		["lucide-wrench"] = "rbxassetid://10747383470",
		["lucide-x"] = "rbxassetid://10747384394",
		["lucide-x-circle"] = "rbxassetid://10747383819",
		["lucide-x-octagon"] = "rbxassetid://10747384037",
		["lucide-x-square"] = "rbxassetid://10747384217",
		["lucide-zoom-in"] = "rbxassetid://10747384552",
		["lucide-zoom-out"] = "rbxassetid://10747384679",
		["lucide-dog-nerd"] = "rbxassetid://137941939602314",
		["lucide-dog-dente"] = "rbxassetid://86545657821911",
		["lucide-dog-chupetao"] = "rbxassetid://111009574293053",
		["lucide-discord"] = "rbxassetid://18913863763",
		["lucide-spectrumx"] = "rbxassetid://132158481306586",
		["lucide-genesis-hub"] = "rbxassetid://134769377797538",
	},
}

end)()
	if raw and raw.assets then
		LucideAssets = raw.assets
	end
end)
GenesisX.Icons = LucideAssets

local CustomIcons = {
	["lucide-dog-nerd"] = "rbxassetid://137941939602314",
	["lucide-dog-dente"] = "rbxassetid://86545657821911",
	["lucide-dog-chupetao"] = "rbxassetid://111009574293053",
	["lucide-discord"] = "rbxassetid://18913863763",
	["lucide-spectrumx"] = "rbxassetid://132158481306586",
	["lucide-genesis-hub"] = "rbxassetid://134769377797538",
}
for name, assetId in pairs(CustomIcons) do
	if not LucideAssets[name] then
		LucideAssets[name] = assetId
	end
end

-- --- FONT SYSTEM --------------------------------------------------------------
GenesisX.Font = "Gotham"

local FontMap = {
	Arcade = Enum.Font.Arcade,
	Fantasy = Enum.Font.Fantasy,
	GothamBlack = Enum.Font.GothamBlack,
	LuckiestGuy = Enum.Font.LuckiestGuy,
}

function GenesisX:GetFont()
	return FontMap[self.Font] or Enum.Font.Gotham
end

function GenesisX:GetFontBold()
	local mapped = FontMap[self.Font]
	if mapped then
		return mapped
	end
	if (self.Font or "Gotham") == "Gotham" then
		return Enum.Font.GothamBold
	end
	return Enum.Font.GothamBold
end

function GenesisX:GetFontSemibold()
	local mapped = FontMap[self.Font]
	if mapped then
		return mapped
	end
	if (self.Font or "Gotham") == "Gotham" then
		return Enum.Font.GothamSemibold
	end
	return Enum.Font.GothamSemibold
end

function GenesisX:GetFontBlack()
	local mapped = FontMap[self.Font]
	if mapped then
		return mapped
	end
	if (self.Font or "Gotham") == "Gotham" then
		return Enum.Font.GothamBlack
	end
	return Enum.Font.GothamBlack
end
function GenesisX:_EnsureTheme()
	if not self.Theme then
		if not self.Themes then
			self.Themes = {
				Dark = {
					Background = Color3.fromRGB(8, 8, 8),
					Header = Color3.fromRGB(12, 12, 12),
					Sidebar = Color3.fromRGB(10, 10, 10),
					Card = Color3.fromRGB(16, 16, 16),
					CardHover = Color3.fromRGB(24, 24, 24),
					Input = Color3.fromRGB(22, 22, 22),
					InputHover = Color3.fromRGB(30, 30, 30),
					Accent = Color3.fromRGB(150, 80, 230),
					AccentHover = Color3.fromRGB(180, 110, 255),
					AccentSecondary = Color3.fromRGB(210, 160, 255),
					AccentDark = Color3.fromRGB(90, 40, 160),
					Text = Color3.fromRGB(255, 255, 255),
					TextSecondary = Color3.fromRGB(190, 190, 190),
					TextMuted = Color3.fromRGB(120, 120, 120),
					Success = Color3.fromRGB(220, 190, 255),
					Warning = Color3.fromRGB(190, 130, 255),
					Info = Color3.fromRGB(140, 90, 220),
					Error = Color3.fromRGB(80, 40, 140),
					Border = Color3.fromRGB(40, 35, 50),
					BorderBright = Color3.fromRGB(75, 65, 90),
					ToggleOff = Color3.fromRGB(35, 30, 45),
					ToggleOn = Color3.fromRGB(150, 80, 230),
				},
				Light = {
					Background = Color3.fromRGB(245, 242, 250),
					Header = Color3.fromRGB(235, 232, 242),
					Sidebar = Color3.fromRGB(240, 237, 247),
					Card = Color3.fromRGB(255, 255, 255),
					CardHover = Color3.fromRGB(248, 245, 252),
					Input = Color3.fromRGB(235, 232, 242),
					InputHover = Color3.fromRGB(225, 220, 235),
					Accent = Color3.fromRGB(130, 60, 210),
					AccentHover = Color3.fromRGB(150, 80, 230),
					AccentSecondary = Color3.fromRGB(100, 40, 180),
					AccentDark = Color3.fromRGB(80, 30, 160),
					Text = Color3.fromRGB(30, 30, 35),
					TextSecondary = Color3.fromRGB(80, 75, 90),
					TextMuted = Color3.fromRGB(130, 125, 140),
					Success = Color3.fromRGB(100, 60, 180),
					Warning = Color3.fromRGB(140, 90, 40),
					Info = Color3.fromRGB(100, 60, 180),
					Error = Color3.fromRGB(160, 40, 60),
					Border = Color3.fromRGB(210, 205, 220),
					BorderBright = Color3.fromRGB(180, 175, 195),
					ToggleOff = Color3.fromRGB(200, 195, 210),
					ToggleOn = Color3.fromRGB(130, 60, 210),
				},
			}
		end
		self.Theme = self.Themes.Dark
	end
end

-- --- THEME SYSTEM -------------------------------------------------------------
GenesisX.Themes = {
	Dark = {
		Background = Color3.fromRGB(8, 8, 8),
		Header = Color3.fromRGB(12, 12, 12),
		Sidebar = Color3.fromRGB(10, 10, 10),
		Card = Color3.fromRGB(16, 16, 16),
		CardHover = Color3.fromRGB(24, 24, 24),
		Input = Color3.fromRGB(22, 22, 22),
		InputHover = Color3.fromRGB(30, 30, 30),
		Accent = Color3.fromRGB(150, 80, 230),
		AccentHover = Color3.fromRGB(180, 110, 255),
		AccentSecondary = Color3.fromRGB(210, 160, 255),
		AccentDark = Color3.fromRGB(90, 40, 160),
		Text = Color3.fromRGB(255, 255, 255),
		TextSecondary = Color3.fromRGB(190, 190, 190),
		TextMuted = Color3.fromRGB(120, 120, 120),
		Success = Color3.fromRGB(220, 190, 255),
		Warning = Color3.fromRGB(190, 130, 255),
		Info = Color3.fromRGB(140, 90, 220),
		Error = Color3.fromRGB(80, 40, 140),
		Border = Color3.fromRGB(40, 35, 50),
		BorderBright = Color3.fromRGB(75, 65, 90),
		ToggleOff = Color3.fromRGB(35, 30, 45),
		ToggleOn = Color3.fromRGB(150, 80, 230),
	},
	Light = {
		Background = Color3.fromRGB(245, 242, 250),
		Header = Color3.fromRGB(235, 232, 242),
		Sidebar = Color3.fromRGB(240, 237, 247),
		Card = Color3.fromRGB(255, 255, 255),
		CardHover = Color3.fromRGB(248, 245, 252),
		Input = Color3.fromRGB(235, 232, 242),
		InputHover = Color3.fromRGB(225, 220, 235),
		Accent = Color3.fromRGB(130, 60, 210),
		AccentHover = Color3.fromRGB(150, 80, 230),
		AccentSecondary = Color3.fromRGB(100, 40, 180),
		AccentDark = Color3.fromRGB(80, 30, 160),
		Text = Color3.fromRGB(30, 30, 35),
		TextSecondary = Color3.fromRGB(80, 75, 90),
		TextMuted = Color3.fromRGB(130, 125, 140),
		Success = Color3.fromRGB(100, 60, 180),
		Warning = Color3.fromRGB(140, 90, 40),
		Info = Color3.fromRGB(100, 60, 180),
		Error = Color3.fromRGB(160, 40, 60),
		Border = Color3.fromRGB(210, 205, 220),
		BorderBright = Color3.fromRGB(180, 175, 195),
		ToggleOff = Color3.fromRGB(200, 195, 210),
		ToggleOn = Color3.fromRGB(130, 60, 210),
	},
	Iron = {
		Background = Color3.fromRGB(32, 33, 36),
		Header = Color3.fromRGB(38, 39, 43),
		Sidebar = Color3.fromRGB(35, 36, 40),
		Card = Color3.fromRGB(42, 43, 48),
		CardHover = Color3.fromRGB(52, 54, 60),
		Input = Color3.fromRGB(45, 46, 52),
		InputHover = Color3.fromRGB(55, 57, 64),
		Accent = Color3.fromRGB(176, 186, 196),
		AccentHover = Color3.fromRGB(200, 210, 220),
		AccentSecondary = Color3.fromRGB(140, 150, 165),
		AccentDark = Color3.fromRGB(110, 118, 130),
		Text = Color3.fromRGB(248, 249, 250),
		TextSecondary = Color3.fromRGB(200, 203, 210),
		TextMuted = Color3.fromRGB(160, 163, 170),
		Success = Color3.fromRGB(130, 180, 140),
		Warning = Color3.fromRGB(200, 170, 120),
		Info = Color3.fromRGB(140, 160, 190),
		Error = Color3.fromRGB(180, 100, 100),
		Border = Color3.fromRGB(82, 85, 92),
		BorderBright = Color3.fromRGB(110, 112, 118),
		ToggleOff = Color3.fromRGB(55, 57, 64),
		ToggleOn = Color3.fromRGB(176, 186, 196),
	},
}

GenesisX.Theme = GenesisX.Themes.Dark

-- --- CONFIGURATION ------------------------------------------------------------
GenesisX.Config = {
	AnimationSpeed = 0.2,
	CornerRadius = 6,
	ShadowEnabled = true,
	ShadowIntensity = 0.7,
	Transparency = 0,
	BorderEnabled = false,
}

-- --- INTERNAL SAVE/LOAD FOR THEME & FONT ------------------------------------
GenesisX._configFolder = "GenesisX/Config"

function GenesisX:_SaveConfigFile(filename, value)
	if not (writefile and isfolder and makefolder and HttpService) then
		return
	end
	pcall(function()
		if not isfolder("GenesisX") then
			makefolder("GenesisX")
		end
		if not isfolder(self._configFolder) then
			makefolder(self._configFolder)
		end
		local path = self._configFolder .. "/" .. filename
		writefile(path, HttpService:JSONEncode({ value = value }))
	end)
end

function GenesisX:_LoadConfigFile(filename, defaultValue)
	if not (readfile and isfile and HttpService) then
		return defaultValue
	end
	local ok, data = pcall(function()
		local path = self._configFolder .. "/" .. filename
		if not isfile(path) then
			return nil
		end
		return HttpService:JSONDecode(readfile(path))
	end)
	if ok and data and data.value ~= nil then
		return data.value
	end
	-- If it does not exist, create it with the default.
	self:_SaveConfigFile(filename, defaultValue)
	return defaultValue
end

-- --- RESPONSIVE SCALE ---------------------------------------------------------
local ScaleData = {
	IsMobile = false,
	ScaleFactor = 1,
	BaseResolution = Vector2.new(1920, 1080),
}

function GenesisX:UpdateScale()
	local success, camera = pcall(function()
		return workspace.CurrentCamera
	end)
	if not success or not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X == 0 then
		return
	end
	ScaleData.IsMobile = UserInputService.TouchEnabled and (viewport.X < 1200 or viewport.Y < 700)
	local scale = math.min(viewport.X / ScaleData.BaseResolution.X, viewport.Y / ScaleData.BaseResolution.Y)
	if ScaleData.IsMobile then
		ScaleData.ScaleFactor = math.clamp(scale, 0.85, 1.2)
	else
		ScaleData.ScaleFactor = math.clamp(scale, 0.7, 1.1)
	end
end

function GenesisX:S(value)
	if type(value) == "number" then
		return math.floor(value * ScaleData.ScaleFactor)
	elseif typeof(value) == "UDim2" then
		return UDim2.new(
			value.X.Scale,
			math.floor(value.X.Offset * ScaleData.ScaleFactor),
			value.Y.Scale,
			math.floor(value.Y.Offset * ScaleData.ScaleFactor)
		)
	elseif typeof(value) == "UDim" then
		return UDim.new(value.Scale, math.floor(value.Offset * ScaleData.ScaleFactor))
	end
	return value
end

-- --- BASIC UTILITIES ----------------------------------------------------------
function GenesisX:Tween(obj, props, time, style, direction)
	if not obj or not obj.Parent then
		return nil
	end
	local tweenInfo = TweenInfo.new(
		time or self.Config.AnimationSpeed,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(obj, tweenInfo, props)
	tween:Play()
	return tween
end

function GenesisX:CreateCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or UDim.new(0, self.Config.CornerRadius)
	corner.Parent = parent
	-- Apply transparency to the parent if it's a frame with background
	if parent and parent:IsA("GuiObject") and parent.BackgroundTransparency < 1 and self.Config.Transparency > 0 then
		local skipNames = {
			Ripple = true,
			Knob = true,
			Fill = true,
			Bar = true,
			BarBg = true,
			Shadow = true,
			SimpleShadow = true,
			IconGlow = true,
			IconBg = true,
			Checkbox = true,
			ValueBg = true,
			CountBadge = true,
			LeftBar = true,
			Track = true,
			RippleHolder = true,
			HoverFill = true,
			IconArea = true,
			Separator = true,
			Line = true,
			SidebarLine = true,
			Divider = true,
			HeaderCover = true,
			BgCard = true,
		}
		if not skipNames[parent.Name] and not parent:IsA("TextBox") then
			parent.BackgroundTransparency = self.Config.Transparency
		end
	end
	return corner
end

function GenesisX:CreateStroke(parent, color, thickness, transparency)
	if self.Config.BorderEnabled == false then
		return nil
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or self.Theme.Border
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function GenesisX:CreateGradient(parent, color1, color2, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color1 or Color3.new(1, 1, 1), color2 or Color3.new(0, 0, 0))
	gradient.Rotation = rotation or 0
	gradient.Parent = parent
	return gradient
end

-- --- SHADOW SYSTEM ------------------------------------------------------------
function GenesisX:CreateShadow(parent, size, intensity)
	if not self.Config.ShadowEnabled then
		return nil
	end
	size = size or 20
	intensity = intensity or self.Config.ShadowIntensity
	local shadowFolder = Instance.new("Folder")
	shadowFolder.Name = "Shadow"
	shadowFolder.Parent = parent
	local layers = 4
	for i = 1, layers do
		local layer = Instance.new("Frame")
		layer.Name = "Layer" .. i
		layer.AnchorPoint = Vector2.new(0.5, 0.5)
		layer.BackgroundColor3 = Color3.new(0, 0, 0)
		layer.BackgroundTransparency = intensity + ((1 - intensity) * (i / layers) * 0.5)
		layer.BorderSizePixel = 0
		layer.Position = UDim2.new(0.5, 0, 0.5, 0)
		layer.Size = UDim2.new(1, size + (i * 3), 1, size + (i * 3))
		layer.ZIndex = math.max(0, parent.ZIndex - 1)
		layer.Parent = shadowFolder
		self:CreateCorner(layer, UDim.new(0, (self.Config.CornerRadius or 8) + i))
	end
	return shadowFolder
end

function GenesisX:CreateSimpleShadow(parent, size, transparency)
	if not self.Config.ShadowEnabled then
		return nil
	end
	local shadow = Instance.new("Frame")
	shadow.Name = "SimpleShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = transparency or 0.75
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
	shadow.Size = UDim2.new(1, size or 16, 1, size or 16)
	shadow.ZIndex = math.max(0, parent.ZIndex - 1)
	shadow.Parent = parent
	self:CreateCorner(shadow)
	return shadow
end

-- --- DRAGGABLE ----------------------------------------------------------------
function GenesisX:MakeDraggable(frame, handle)
	handle = handle or frame
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPos = nil
	handle.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)
	trackGenesisConnection(UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			frame.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

-- --- RIPPLE EFFECT ------------------------------------------------------------
function GenesisX:CreateRipple(parent, position)
	local ripple = Instance.new("Frame")
	ripple.Name = "Ripple"
	ripple.BackgroundColor3 = Color3.new(1, 1, 1)
	ripple.BackgroundTransparency = 0.8
	ripple.BorderSizePixel = 0
	ripple.ZIndex = parent.ZIndex + 10
	local maxSize = math.max(parent.AbsoluteSize.X, parent.AbsoluteSize.Y) * 1.2
	local startX, startY
	if position then
		startX = position.X - parent.AbsolutePosition.X
		startY = position.Y - parent.AbsolutePosition.Y
	else
		startX = parent.AbsoluteSize.X / 2
		startY = parent.AbsoluteSize.Y / 2
	end
	ripple.Position = UDim2.new(0, startX, 0, startY)
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Size = UDim2.new(0, 0, 0, 0)
	ripple.Parent = parent
	self:CreateCorner(ripple, UDim.new(1, 0))
	self:Tween(ripple, {
		Size = UDim2.new(0, maxSize, 0, maxSize),
		BackgroundTransparency = 1,
	}, 0.4)
	task.delay(0.4, function()
		if ripple and ripple.Parent then
			ripple:Destroy()
		end
	end)
end

-- --- ICON HELPERS -------------------------------------------------------------
function GenesisX:IsAssetId(value)
	if type(value) ~= "string" and type(value) ~= "number" then
		return false
	end
	local s = tostring(value)
	if s:match("^rbxassetid://") ~= nil or s:match("^%d+$") ~= nil then
		return true
	end
	-- Also accepts registered icon names.
	if LucideAssets and LucideAssets[s] then
		return true
	end
	return false
end

function GenesisX:FormatAssetId(value)
	if type(value) == "number" then
		return "rbxassetid://" .. value
	elseif type(value) == "string" then
		-- Priority: registered Lucide icon name.
		if LucideAssets and LucideAssets[value] then
			return LucideAssets[value]
		end
		if value:match("^rbxassetid://") then
			return value
		elseif value:match("^%d+$") then
			return "rbxassetid://" .. value
		end
	end
	return nil
end

function GenesisX:CreateIcon(parent, iconData, size, color)
	size = size or UDim2.new(0, 20, 0, 20)
	color = color or self.Theme.Text
	local assetId = self:FormatAssetId(iconData)
	if assetId then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Size = size
		img.Image = assetId
		img.ImageColor3 = color
		img.Parent = parent
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = img
		return img, "image"
	else
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Icon"
		lbl.BackgroundTransparency = 1
		lbl.Size = size
		lbl.Font = self:GetFontBold()
		lbl.Text = tostring(iconData):sub(1, 2)
		lbl.TextColor3 = color
		lbl.TextSize = size.Y.Offset or 16
		lbl.Parent = parent
		return lbl, "text"
	end
end

-- --- DROPDOWN REGISTRY --------------------------------------------------------
function GenesisX:_RegisterDropdown(list, button, closeFunction)
	if not self._dropdowns then
		self._dropdowns = {}
	end
	table.insert(self._dropdowns, { List = list, Button = button, Close = closeFunction })
	if not self.Dropdowns then
		self.Dropdowns = {}
	end
	table.insert(self.Dropdowns, list)
end

function GenesisX:_CloseDropdownsOnClick(position)
	if not self._dropdowns then
		return
	end
	for _, dropdown in ipairs(self._dropdowns) do
		if dropdown.List and dropdown.List.Visible then
			local listPos = dropdown.List.AbsolutePosition
			local listSize = dropdown.List.AbsoluteSize
			local btnPos = dropdown.Button.AbsolutePosition
			local btnSize = dropdown.Button.AbsoluteSize
			local inList = position.X >= listPos.X
				and position.X <= listPos.X + listSize.X
				and position.Y >= listPos.Y
				and position.Y <= listPos.Y + listSize.Y
			local inBtn = position.X >= btnPos.X
				and position.X <= btnPos.X + btnSize.X
				and position.Y >= btnPos.Y
				and position.Y <= btnPos.Y + btnSize.Y
			if not inList and not inBtn then
				task.spawn(dropdown.Close)
			end
		end
	end
end

-- --- CREATE WINDOW ------------------------------------------------------------
function GenesisX:CreateWindow(config)
	self:_EnsureTheme()
	config = config or {}
	local window = setmetatable({}, self)
	self:UpdateScale()
	-- Theme & Font setup
	if not self.Themes then
		self.Themes = {
			Dark = {
				Background = Color3.fromRGB(8, 8, 8),
				Header = Color3.fromRGB(12, 12, 12),
				Sidebar = Color3.fromRGB(10, 10, 10),
				Card = Color3.fromRGB(16, 16, 16),
				CardHover = Color3.fromRGB(24, 24, 24),
				Input = Color3.fromRGB(22, 22, 22),
				InputHover = Color3.fromRGB(30, 30, 30),
				Accent = Color3.fromRGB(150, 80, 230),
				AccentHover = Color3.fromRGB(180, 110, 255),
				AccentSecondary = Color3.fromRGB(210, 160, 255),
				AccentDark = Color3.fromRGB(90, 40, 160),
				Text = Color3.fromRGB(255, 255, 255),
				TextSecondary = Color3.fromRGB(190, 190, 190),
				TextMuted = Color3.fromRGB(120, 120, 120),
				Success = Color3.fromRGB(220, 190, 255),
				Warning = Color3.fromRGB(190, 130, 255),
				Info = Color3.fromRGB(140, 90, 220),
				Error = Color3.fromRGB(80, 40, 140),
				Border = Color3.fromRGB(40, 35, 50),
				BorderBright = Color3.fromRGB(75, 65, 90),
				ToggleOff = Color3.fromRGB(35, 30, 45),
				ToggleOn = Color3.fromRGB(150, 80, 230),
			},
		}
	end
	if not self.Theme then
		self.Theme = self.Themes.Dark
	end
	-- Load saved theme/font or use config defaults (and save them)
	-- If config explicitly provides Theme/Font, it OVERRIDES saved config
	local configTheme = config.Theme
	local configFont = config.Font
	local savedTheme = self:_LoadConfigFile("theme.json", configTheme or "Dark")
	local savedFont = self:_LoadConfigFile("font.json", configFont or "Gotham")
	local savedTransparency = self:_LoadConfigFile("transparency.json", config.Transparency or 0)
	self.Config.Transparency = math.clamp(savedTransparency, 0, 1)

	-- Override: if config explicitly set Theme/Font, use it and save
	local themeName = savedTheme
	if configTheme then
		themeName = configTheme
		self:_SaveConfigFile("theme.json", configTheme)
	end
	local fontName = savedFont
	if configFont then
		fontName = configFont
		self:_SaveConfigFile("font.json", configFont)
	end
	self.Font = fontName
	if themeName == "Light" then
		self.Theme = self.Themes.Light
	else
		self.Theme = self.Themes.Dark
	end

	-- SideMode: optional docked side panel UI (chevron handle + large side window)
	self.SideMode = config.SideMode == true
	self._sideExpanded = false

	-- The UI normally lives in CoreGui, so clear an older instance from either
	-- possible parent before building a new one.
	for _, guiParent in ipairs({ CoreGui, PlayerGui }) do
		pcall(function()
			local existing = guiParent:FindFirstChild("GenesisX")
			if existing then
				existing:Destroy()
			end
		end)
	end

	self.ScreenGui = Instance.new("ScreenGui")
	self.ScreenGui.Name = "GenesisX"
	self.ScreenGui.ResetOnSpawn = false
	self.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	self.ScreenGui.IgnoreGuiInset = true
	self.ScreenGui.DisplayOrder = 999999

	-- Parent to CoreGui when possible (it stays above the Roblox UI).
	local parentSuccess = pcall(function()
		self.ScreenGui.Parent = CoreGui
	end)

	-- If that fails (the executor does not allow it), use PlayerGui.
	if not parentSuccess then
		local readyGui = PlayerGui or LocalPlayer:FindFirstChild("PlayerGui")
		if readyGui then
			self.ScreenGui.Parent = readyGui
		else
			-- PlayerGui can arrive after Play. Keep building the UI and attach it later.
			local pendingGui = self.ScreenGui
			local parentRuntime = getGenesisRuntimeState()
			local pendingConnection
			pendingConnection = trackGenesisConnection(LocalPlayer.ChildAdded:Connect(function(child)
				if child.Name == "PlayerGui" then
					pendingConnection:Disconnect()
					if (not parentRuntime or parentRuntime.active) and not pendingGui.Parent then
						pendingGui.Parent = child
					end
				end
			end))
			-- Recheck after connecting so an arrival in between cannot be missed.
			readyGui = LocalPlayer:FindFirstChild("PlayerGui")
			if readyGui then
				pendingConnection:Disconnect()
				if (not parentRuntime or parentRuntime.active) and not pendingGui.Parent then
					pendingGui.Parent = readyGui
				end
			end
		end
	end

	self._notifications = {}
	self.Dropdowns = {}
	self._dropdowns = {}
	self.Tabs = {}
	self.CurrentTab = nil

	local windowWidth, windowHeight
	if self.SideMode then
		-- Side panel should feel wide/comfortable, not cramped
		local cam = workspace.CurrentCamera
		local vw = (cam and cam.ViewportSize.X) or 1366
		if ScaleData.IsMobile then
			windowWidth = math.floor(math.clamp(vw * 0.92, 320, 580))
			windowHeight = ScaleData.IsMobile and self:S(540) or self:S(560)
		else
			-- Wider = extends farther left (anchored on the right).
			windowWidth = math.floor(math.clamp(vw * 0.48, 620, 860))
			windowHeight = self:S(560)
		end
	else
		windowWidth = ScaleData.IsMobile and self:S(440) or self:S(700)
		windowHeight = ScaleData.IsMobile and self:S(580) or self:S(460)
	end

	self.MainFrame = Instance.new("Frame")
	self.MainFrame.Name = "MainFrame"
	self.MainFrame.BackgroundColor3 = self.Theme.Background
	self.MainFrame.BorderSizePixel = 0
	if self.SideMode then
		self.MainFrame.AnchorPoint = Vector2.new(1, 0.5)
		self.MainFrame.Position = config.Position or UDim2.new(1, -56, 0.5, 0)
		self.MainFrame.Visible = false -- starts collapsed; opened via side handle
	else
		self.MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		self.MainFrame.Position = config.Position or UDim2.new(0.5, 0, 0.5, 0)
		self.MainFrame.Visible = true
	end
	self.MainFrame.Size = config.Size or UDim2.new(0, windowWidth, 0, windowHeight)
	self.MainFrame.Active = true
	self.MainFrame.ZIndex = 10
	self.MainFrame.ClipsDescendants = true
	self.MainFrame.Parent = self.ScreenGui
	self:CreateCorner(self.MainFrame, UDim.new(0, 12))
	if self.Config.BorderEnabled then
		self:CreateStroke(self.MainFrame, self.Theme.Accent, 1.5, 0)
	end
	self.MainFrame.BackgroundTransparency = self.Config.Transparency

	-- --- HEADER -----------------------------------------------------------------
	local headerHeight = self:S(56)

	self.Header = Instance.new("Frame")
	self.Header.Name = "Header"
	self.Header.BackgroundColor3 = self.Theme.Header
	self.Header.BorderSizePixel = 0
	self.Header.Size = UDim2.new(1, 0, 0, headerHeight)
	self.Header.ZIndex = 12
	self.Header.Parent = self.MainFrame
	self.Header.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(self.Header, UDim.new(0, 8))

	local iconX = self:S(16)
	-- FIX: Correctly detect the header icon asset ID (now includes Lucide names).
	local headerIconAsset = config.IconAssetId and self:FormatAssetId(config.IconAssetId)
		or (config.Icon and self:FormatAssetId(config.Icon))

	if headerIconAsset then
		local iconImg = Instance.new("ImageLabel")
		iconImg.Name = "HeaderIcon"
		iconImg.BackgroundTransparency = 1
		iconImg.Position = UDim2.new(0, iconX, 0.5, -self:S(16))
		iconImg.Size = UDim2.new(0, self:S(32), 0, self:S(32))
		iconImg.Image = headerIconAsset
		iconImg.ScaleType = Enum.ScaleType.Stretch
		iconImg.ZIndex = 14
		iconImg.Parent = self.Header
	else
		local iconBg = Instance.new("Frame")
		iconBg.Name = "IconBg"
		iconBg.BackgroundColor3 = self.Theme.Accent
		iconBg.Position = UDim2.new(0, iconX, 0.5, -self:S(15))
		iconBg.Size = UDim2.new(0, self:S(30), 0, self:S(30))
		iconBg.ZIndex = 14
		iconBg.Parent = self.Header
		self:CreateCorner(iconBg, UDim.new(0, 6))

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconLabel"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.Font = self:GetFontBlack()
		iconLabel.Text = config.Icon or "S"
		iconLabel.TextColor3 = Color3.new(1, 1, 1)
		iconLabel.TextSize = self:S(16)
		iconLabel.ZIndex = 15
		iconLabel.Parent = iconBg
	end

	local titleX = iconX + self:S(44)
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, titleX, 0, 0)
	titleLabel.Size = UDim2.new(0, self:S(300), 1, 0)
	titleLabel.Font = self:GetFontBold()
	titleLabel.Text = config.Title or "GenesisX"
	titleLabel.TextColor3 = self.Theme.Text
	titleLabel.TextSize = self:S(18)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 14
	titleLabel.Parent = self.Header
	self:CreateGradient(titleLabel, self.Theme.Text, self.Theme.AccentSecondary, 0)

	if config.Subtitle then
		titleLabel.Size = UDim2.new(0, self:S(300), 0, self:S(28))
		titleLabel.Position = UDim2.new(0, titleX, 0, self:S(6))
		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Name = "Subtitle"
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Position = UDim2.new(0, titleX, 0, self:S(30))
		subtitleLabel.Size = UDim2.new(0, self:S(300), 0, self:S(16))
		subtitleLabel.Font = self:GetFont()
		subtitleLabel.Text = config.Subtitle
		subtitleLabel.TextColor3 = self.Theme.TextMuted
		subtitleLabel.TextSize = self:S(10)
		subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
		subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subtitleLabel.ZIndex = 14
		subtitleLabel.Parent = self.Header
	end

	-- Header buttons: Theme, Discord & Minimize
	local headerButtons = {}
	local btnW, btnH = self:S(34), self:S(32)
	local btnGap = self:S(8)
	local rightPad = self:S(14)

	-- Theme toggle button
	if config.ThemeBtn == true then
		table.insert(headerButtons, {
			Type = "theme",
			Icon = "lucide-sun-moon",
			Action = function()
				local newTheme = (self.Theme == self.Themes.Dark) and "Light" or "Dark"
				self:SetTheme(newTheme)
			end,
		})
	end

	-- Discord button config
	local discordLink = nil
	if type(config.DiscordBtn) == "string" and config.DiscordBtn ~= "" then
		discordLink = config.DiscordBtn
	elseif config.DiscordBtn == true and type(config.DiscordLink) == "string" and config.DiscordLink ~= "" then
		discordLink = config.DiscordLink
	end
	if discordLink then
		table.insert(headerButtons, {
			Type = "discord",
			Icon = "lucide-discord",
			Link = discordLink,
			Action = function()
				if setclipboard then
					setclipboard(discordLink)
				end
			end,
		})
	end

	-- Minimize button config
	if config.MinimizeBtn == true then
		table.insert(headerButtons, {
			Type = "minimize",
			Icon = "lucide-minus",
			Action = function()
				self.MainFrame.Visible = false
			end,
		})
	end

	-- Position from right to left (first = rightmost)
	for i, btnData in ipairs(headerButtons) do
		local offsetX = rightPad + (i - 1) * (btnW + btnGap)
		local btn = Instance.new("ImageButton")
		btn.Name = btnData.Type .. "Btn"
		btn.BackgroundColor3 = self.Theme.Input
		btn.Position = UDim2.new(1, -(offsetX + btnW), 0.5, -btnH / 2)
		btn.Size = UDim2.new(0, btnW, 0, btnH)
		btn.Image = self:FormatAssetId(btnData.Icon) or ""
		btn.ImageColor3 = self.Theme.Accent
		btn.AutoButtonColor = false
		btn.ZIndex = 14
		btn.Parent = self.Header
		self:CreateCorner(btn, UDim.new(0, 6))

		btn.MouseEnter:Connect(function()
			self:Tween(btn, { BackgroundColor3 = self.Theme.Accent, ImageColor3 = Color3.new(1, 1, 1) }, 0.15)
		end)
		btn.MouseLeave:Connect(function()
			self:Tween(btn, { BackgroundColor3 = self.Theme.Input, ImageColor3 = self.Theme.Accent }, 0.15)
		end)
		btn.MouseButton1Click:Connect(function()
			if btnData.Action then
				btnData.Action()
			end
		end)
	end

	-- --- SIDEBAR ----------------------------------------------------------------
	local sidebarWidth = self.SideMode and self:S(118) or self:S(64)
	self._sidebarWidth = sidebarWidth

	local sidebarWrap = Instance.new("Frame")
	sidebarWrap.Name = "SidebarWrap"
	sidebarWrap.BackgroundColor3 = self.Theme.Sidebar
	sidebarWrap.BorderSizePixel = 0
	sidebarWrap.Position = UDim2.new(0, 0, 0, headerHeight + 2)
	sidebarWrap.Size = UDim2.new(0, sidebarWidth, 1, -(headerHeight + 2))
	sidebarWrap.ClipsDescendants = true
	sidebarWrap.ZIndex = 11
	sidebarWrap.Parent = self.MainFrame
	sidebarWrap.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(sidebarWrap, UDim.new(0, 8))

	local sidebarLine = Instance.new("Frame")
	sidebarLine.Name = "SidebarLine"
	sidebarLine.BackgroundColor3 = self.Theme.Border
	sidebarLine.BorderSizePixel = 0
	sidebarLine.Position = UDim2.new(1, -1, 0, 0)
	sidebarLine.Size = UDim2.new(0, 1, 1, 0)
	sidebarLine.ZIndex = 12
	sidebarLine.Parent = sidebarWrap

	self.Sidebar = Instance.new("ScrollingFrame")
	self.Sidebar.Name = "Sidebar"
	self.Sidebar.BackgroundTransparency = 1
	self.Sidebar.BorderSizePixel = 0
	self.Sidebar.Position = UDim2.new(0, 0, 0, 0)
	self.Sidebar.Size = UDim2.new(1, 0, 1, 0)
	self.Sidebar.ScrollBarThickness = 2
	self.Sidebar.ScrollBarImageColor3 = self.Theme.Accent
	self.Sidebar.ScrollBarImageTransparency = 0.6
	self.Sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	self.Sidebar.ScrollingDirection = Enum.ScrollingDirection.Y
	self.Sidebar.ZIndex = 11
	self.Sidebar.Parent = sidebarWrap

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sidebarLayout.Padding = UDim.new(0, self:S(8))
	sidebarLayout.HorizontalAlignment = self.SideMode and Enum.HorizontalAlignment.Left
		or Enum.HorizontalAlignment.Center
	sidebarLayout.Parent = self.Sidebar

	local sidebarPadding = Instance.new("UIPadding")
	sidebarPadding.PaddingTop = UDim.new(0, self:S(12))
	sidebarPadding.PaddingBottom = UDim.new(0, self:S(12))
	if self.SideMode then
		sidebarPadding.PaddingLeft = UDim.new(0, self:S(10))
		sidebarPadding.PaddingRight = UDim.new(0, self:S(10))
	end
	sidebarPadding.Parent = self.Sidebar

	sidebarLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self.Sidebar.CanvasSize = UDim2.new(0, 0, 0, sidebarLayout.AbsoluteContentSize.Y + self:S(24))
	end)

	-- --- CONTENT AREA -----------------------------------------------------------
	local contentX = sidebarWidth + self:S(10)

	self.ContentArea = Instance.new("Frame")
	self.ContentArea.Name = "ContentArea"
	self.ContentArea.BackgroundTransparency = 1
	self.ContentArea.Position = UDim2.new(0, contentX, 0, headerHeight + self:S(10))
	self.ContentArea.Size = UDim2.new(1, -(contentX + self:S(14)), 1, -(headerHeight + self:S(20)))
	self.ContentArea.ZIndex = 11
	self.ContentArea.ClipsDescendants = true
	self.ContentArea.Parent = self.MainFrame

	if self.SideMode then
		self:_CreateSideHandle(config)
	else
		self:_CreateFloatingButton(config)
	end

	trackGenesisConnection(UserInputService.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self:_CloseDropdownsOnClick(input.Position)
		end
	end))

	local success, camera = pcall(function()
		return workspace.CurrentCamera
	end)
	if success and camera then
		trackGenesisConnection(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:UpdateScale()
		end))
	end

	if not self.SideMode then
		self:MakeDraggable(self.MainFrame, self.Header)
	end
	return window
end

-- --- SIDE MODE HANDLE -------------------------------------------------------
function GenesisX:_CreateSideHandle(config)
	config = config or {}
	local HANDLE_W = self:S(36)
	local HANDLE_H = self:S(96)
	local EDGE_PAD = self:S(12)
	local GAP = self:S(10)
	local SCREEN_PAD = 10

	self._sideHandleW = HANDLE_W
	self._sideEdgePad = EDGE_PAD
	self._sideGap = GAP

	local function viewportSize()
		local cam = workspace.CurrentCamera
		if cam then
			return cam.ViewportSize
		end
		return Vector2.new(1366, 768)
	end

	local function safeClamp(value, minV, maxV)
		if minV > maxV then
			return (minV + maxV) * 0.5
		end
		return math.clamp(value, minV, maxV)
	end

	-- Load last handle position (0..1 scale Y)
	local savedY = self:_LoadConfigFile("sidehandle_y.json", 0.5)
	if type(savedY) ~= "number" then
		savedY = 0.5
	end
	savedY = math.clamp(savedY, 0.05, 0.95)
	self._sideCenterY = savedY

	local function clampHandleScale(scale)
		local vh = math.max(viewportSize().Y, 1)
		local half = HANDLE_H * 0.5
		local minS = (half + SCREEN_PAD) / vh
		local maxS = 1 - minS
		return safeClamp(scale, minS, maxS)
	end

	-- Panel height adapts to viewport so it never clips
	local function getPanelSize()
		local vs = viewportSize()
		local vw = math.max(vs.X, 1)
		local vh = math.max(vs.Y, 1)
		local baseW
		if ScaleData.IsMobile then
			baseW = math.floor(math.clamp(vw * 0.88, 300, 520))
		else
			baseW = math.floor(math.clamp(vw * 0.38, 480, 620))
		end
		local baseH = ScaleData.IsMobile and self:S(540) or self:S(560)
		local maxH = math.max(220, vh - SCREEN_PAD * 2)
		local h = math.clamp(baseH, 220, maxH)
		return baseW, h
	end

	-- Panel always opens vertically centered (and clamped), independent of handle Y
	local function getPanelCenterScale(panelH)
		local vh = math.max(viewportSize().Y, 1)
		local half = panelH * 0.5
		local minS = (half + SCREEN_PAD) / vh
		local maxS = 1 - minS
		return safeClamp(0.5, minS, maxS)
	end

	self._sideCenterY = clampHandleScale(self._sideCenterY)

	-- Floating chevron handle on the right edge
	self.SideHandle = Instance.new("TextButton")
	self.SideHandle.Name = "SideHandle"
	self.SideHandle.BackgroundColor3 = self.Theme.Header
	self.SideHandle.BorderSizePixel = 0
	self.SideHandle.AnchorPoint = Vector2.new(1, 0.5)
	self.SideHandle.Position = UDim2.new(1, -EDGE_PAD, self._sideCenterY, 0)
	self.SideHandle.Size = UDim2.new(0, HANDLE_W, 0, HANDLE_H)
	self.SideHandle.Text = ""
	self.SideHandle.AutoButtonColor = false
	self.SideHandle.ZIndex = 120
	self.SideHandle.Parent = self.ScreenGui
	self:CreateCorner(self.SideHandle, UDim.new(0, 10))

	local stroke = Instance.new("UIStroke")
	stroke.Name = "HandleStroke"
	stroke.Color = self.Theme.Accent
	stroke.Thickness = 1.4
	stroke.Transparency = 0.3
	stroke.Parent = self.SideHandle
	self._sideHandleStroke = stroke

	local chevron = Instance.new("ImageLabel")
	chevron.Name = "Chevron"
	chevron.BackgroundTransparency = 1
	chevron.Size = UDim2.new(0, self:S(18), 0, self:S(18))
	chevron.Position = UDim2.new(0.5, 0, 0.5, 0)
	chevron.AnchorPoint = Vector2.new(0.5, 0.5)
	chevron.Image = self:FormatAssetId("lucide-chevron-left") or "rbxassetid://6031091004"
	chevron.ImageColor3 = self.Theme.Accent
	chevron.ZIndex = 121
	chevron.Parent = self.SideHandle
	self._sideChevron = chevron

	local function placeHandle()
		self._sideCenterY = clampHandleScale(self._sideCenterY)
		self.SideHandle.Position = UDim2.new(1, -EDGE_PAD, self._sideCenterY, 0)
	end

	local function placePanelCentered(panelH)
		if not self.MainFrame then
			return
		end
		local offset = EDGE_PAD + HANDLE_W + GAP
		local cy = getPanelCenterScale(panelH)
		self.MainFrame.AnchorPoint = Vector2.new(1, 0.5)
		self.MainFrame.Position = UDim2.new(1, -offset, cy, 0)
		return cy
	end

	function self:SetSideExpanded(state)
		self._sideExpanded = state and true or false
		if not self.MainFrame then
			return
		end

		local w, h = getPanelSize()
		local offset = EDGE_PAD + HANDLE_W + GAP

		if self._sideExpanded then
			placePanelCentered(h)
			self.MainFrame.Visible = true
			self.MainFrame.Size = UDim2.new(0, 0, 0, h)
			self:Tween(self.MainFrame, {
				Size = UDim2.new(0, w, 0, h),
			}, 0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			if self._sideChevron then
				self:Tween(self._sideChevron, { Rotation = 180 }, 0.28)
			end
			if self._sideHandleStroke then
				self._sideHandleStroke.Transparency = 0.12
			end
		else
			self:Tween(self.MainFrame, {
				Size = UDim2.new(0, 0, 0, h),
			}, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			if self._sideChevron then
				self:Tween(self._sideChevron, { Rotation = 0 }, 0.28)
			end
			if self._sideHandleStroke then
				self._sideHandleStroke.Transparency = 0.3
			end
			task.delay(0.3, function()
				if self.MainFrame and not self._sideExpanded then
					self.MainFrame.Visible = false
					local ww, wh = getPanelSize()
					self.MainFrame.Size = UDim2.new(0, ww, 0, wh)
				end
			end)
		end
	end

	function self:ToggleSide()
		self:SetSideExpanded(not self._sideExpanded)
	end

	-- Click to toggle (ignore if drag)
	self.SideHandle.MouseButton1Click:Connect(function()
		if self.SideHandle:GetAttribute("WasDragging") then
			self.SideHandle:SetAttribute("WasDragging", false)
			return
		end
		self:ToggleSide()
	end)

	self.SideHandle.MouseEnter:Connect(function()
		self:Tween(self.SideHandle, { BackgroundColor3 = self.Theme.Card }, 0.15)
		if self._sideChevron then
			self:Tween(self._sideChevron, { ImageColor3 = self.Theme.AccentHover }, 0.15)
		end
	end)
	self.SideHandle.MouseLeave:Connect(function()
		self:Tween(self.SideHandle, { BackgroundColor3 = self.Theme.Header }, 0.15)
		if self._sideChevron then
			self:Tween(self._sideChevron, { ImageColor3 = self.Theme.Accent }, 0.15)
		end
	end)

	-- Drag handle vertically + save position
	-- Mobile-friendly: require hold + meaningful move before treating as drag
	-- so analog/walk touches don't slide the button by accident
	local dragging = false
	local dragArmed = false -- true only after hold threshold
	local dragActive = false -- true only after move threshold while armed
	local dragStartY = 0
	local startScale = 0.5
	local pressClock = 0
	local HOLD_TO_DRAG = 0.28 -- seconds of hold before drag can start
	local MOVE_TO_DRAG = 14 -- pixels before counting as drag

	self.SideHandle.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragArmed = false
			dragActive = false
			dragStartY = input.Position.Y
			startScale = self._sideCenterY
			pressClock = os.clock()
			self.SideHandle:SetAttribute("WasDragging", false)

			-- arm drag after hold (does not move yet)
			task.delay(HOLD_TO_DRAG, function()
				if dragging and not dragActive then
					dragArmed = true
				end
			end)
		end
	end)

	trackGenesisConnection(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = input.Position.Y - dragStartY
			local heldLongEnough = (os.clock() - pressClock) >= HOLD_TO_DRAG or dragArmed

			-- Desktop mouse: allow drag sooner (smaller hold), mobile touch uses full hold
			local isTouch = input.UserInputType == Enum.UserInputType.Touch
			local moveNeed = isTouch and MOVE_TO_DRAG or 8
			local holdNeed = isTouch and HOLD_TO_DRAG or 0.12
			heldLongEnough = (os.clock() - pressClock) >= holdNeed or dragArmed

			if heldLongEnough and math.abs(delta) >= moveNeed then
				dragActive = true
				dragArmed = true
				self.SideHandle:SetAttribute("WasDragging", true)
			end

			if dragActive then
				local vh = math.max(viewportSize().Y, 1)
				self._sideCenterY = clampHandleScale(startScale + (delta / vh))
				placeHandle()
			end
		end
	end))

	trackGenesisConnection(UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if dragging and dragActive then
				self:_SaveConfigFile("sidehandle_y.json", self._sideCenterY)
			end
			dragging = false
			dragArmed = false
			dragActive = false
		end
	end))

	-- Reclamp on resolution change
	local function reclampAll()
		placeHandle()
		if self._sideExpanded and self.MainFrame then
			local _, h = getPanelSize()
			placePanelCentered(h)
			local w = getPanelSize()
			-- keep size fitted
			local ww, wh = getPanelSize()
			self.MainFrame.Size = UDim2.new(0, ww, 0, wh)
		end
	end
	if workspace.CurrentCamera then
		trackGenesisConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(reclampAll))
	end

	-- subtle intro bounce
	task.delay(1.0, function()
		if self.SideHandle and self.SideHandle.Parent then
			self:Tween(self.SideHandle, {
				Position = UDim2.new(1, -(EDGE_PAD + 6), self._sideCenterY, 0),
			}, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			task.wait(0.28)
			if self.SideHandle and self.SideHandle.Parent then
				self:Tween(self.SideHandle, {
					Position = UDim2.new(1, -EDGE_PAD, self._sideCenterY, 0),
				}, 0.25)
			end
		end
	end)
end

function GenesisX:_CreateFloatingButton(config)
	config = config or {}
	local btnSize = self:S(64)

	self.FloatBtn = Instance.new("ImageButton")
	self.FloatBtn.Name = "FloatBtn"
	self.FloatBtn.BackgroundColor3 = self.Theme.Accent
	self.FloatBtn.Position = UDim2.new(0, 20, 0.5, 0)
	self.FloatBtn.Size = UDim2.new(0, btnSize, 0, btnSize)
	self.FloatBtn.AutoButtonColor = false
	self.FloatBtn.ZIndex = 100
	self.FloatBtn.Parent = self.ScreenGui
	self:CreateCorner(self.FloatBtn, UDim.new(1, 0))
	if self.Config.BorderEnabled then
		self:CreateStroke(self.FloatBtn, self.Theme.Accent, 2, 0.4)
	end

	-- FIX: Detect the floating-button icon asset ID (now supports Lucide names).
	-- Supports a single icon or an array of rotating icons.
	local floatIcons = {}
	local rawFloat = config.FloatIcon or config.FloatIconAssetId or config.IconAssetId or config.Icon or "S"
	if type(rawFloat) == "table" then
		for _, icon in ipairs(rawFloat) do
			local asset = self:FormatAssetId(icon)
			if asset then
				table.insert(floatIcons, asset)
			end
		end
	else
		local asset = self:FormatAssetId(rawFloat)
		if asset then
			table.insert(floatIcons, asset)
		end
	end

	-- Fallback text label (if no valid icons)
	local iconLabel = nil
	if #floatIcons == 0 then
		iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.Font = self:GetFontBlack()
		-- If rawFloat is a table, show first char of first element or default "G"
		local fallbackText = "G"
		if type(rawFloat) == "table" and rawFloat[1] then
			fallbackText = tostring(rawFloat[1]):sub(1, 1)
		elseif type(rawFloat) == "string" then
			fallbackText = rawFloat:sub(1, 1)
		end
		iconLabel.Text = fallbackText
		iconLabel.TextColor3 = Color3.new(1, 1, 1)
		iconLabel.TextSize = self:S(22)
		iconLabel.ZIndex = 102
		iconLabel.Parent = self.FloatBtn
	elseif #floatIcons == 1 then
		-- Single icon: apply directly
		self.FloatBtn.Image = floatIcons[1]
		self.FloatBtn.ScaleType = Enum.ScaleType.Crop
	else
		-- Multiple icons: rotate between them
		self.FloatBtn.Image = floatIcons[1]
		self.FloatBtn.ScaleType = Enum.ScaleType.Crop
		local changeSpeed = math.clamp(config.FloatIconChangeSpeed or 2, 0.5, 10)
		local currentIndex = 1
		task.spawn(function()
			while self.FloatBtn and self.FloatBtn.Parent do
				task.wait(changeSpeed)
				if not self.FloatBtn or not self.FloatBtn.Parent then
					break
				end
				currentIndex = currentIndex + 1
				if currentIndex > #floatIcons then
					currentIndex = 1
				end
				-- Smooth fade transition
				self:Tween(self.FloatBtn, { ImageTransparency = 1 }, 0.15)
				task.wait(0.15)
				if not self.FloatBtn or not self.FloatBtn.Parent then
					break
				end
				self.FloatBtn.Image = floatIcons[currentIndex]
				self:Tween(self.FloatBtn, { ImageTransparency = 0 }, 0.15)
			end
		end)
	end

	self.FloatBtn.MouseEnter:Connect(function()
		self:Tween(self.FloatBtn, { BackgroundColor3 = self.Theme.AccentHover }, 0.15)
	end)
	self.FloatBtn.MouseLeave:Connect(function()
		self:Tween(self.FloatBtn, { BackgroundColor3 = self.Theme.Accent }, 0.15)
	end)

	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPos = nil
	local lastDelta = Vector2.new(0, 0)
	local velocity = Vector2.new(0, 0)
	local damping = 0.7 -- Heavy feel

	self.FloatBtn.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPos = self.FloatBtn.Position
			velocity = Vector2.new(0, 0)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	self.FloatBtn.InputChanged:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)
	trackGenesisConnection(UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			lastDelta = delta
			velocity = Vector2.new(delta.X - lastDelta.X, delta.Y - lastDelta.Y) * damping
			self.FloatBtn.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))

	self.FloatBtn.MouseButton1Click:Connect(function()
		if not dragging then
			self.MainFrame.Visible = not self.MainFrame.Visible
		end
	end)
end

-- --- CREATE TAB ---------------------------------------------------------------
function GenesisX:CreateTab(config)
	config = config or {}
	local tabId = config.Name or "Tab"
	local btnSize = self:S(46)
	local sideMode = self.SideMode == true
	local tabW = sideMode and (self._sidebarWidth and (self._sidebarWidth - self:S(20)) or self:S(120)) or btnSize
	local tabH = sideMode and self:S(40) or btnSize

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = tabId .. "Tab"
	tabBtn.BackgroundColor3 = self.Theme.Card
	tabBtn.Size = UDim2.new(0, tabW, 0, tabH)
	tabBtn.Text = ""
	tabBtn.AutoButtonColor = false
	tabBtn.ZIndex = 13
	tabBtn.Parent = self.Sidebar
	self:CreateCorner(tabBtn, UDim.new(0, 8))

	-- FIX: Correctly detect whether Icon is an asset ID or a Lucide name.
	local iconRaw = config.Icon or config.IconAssetId
	local iconAssetId = iconRaw and self:FormatAssetId(iconRaw)

	if iconAssetId then
		-- It is a valid asset ID or Lucide name — render it as an ImageLabel.
		local iconImg = Instance.new("ImageLabel")
		iconImg.Name = "Icon"
		iconImg.BackgroundTransparency = 1
		if sideMode then
			iconImg.AnchorPoint = Vector2.new(0, 0.5)
			iconImg.Position = UDim2.new(0, self:S(10), 0.5, 0)
			iconImg.Size = UDim2.new(0, self:S(18), 0, self:S(18))
		else
			iconImg.AnchorPoint = Vector2.new(0.5, 0.5)
			iconImg.Position = UDim2.new(0.5, 0, 0.5, 0)
			iconImg.Size = UDim2.new(0, self:S(24), 0, self:S(24))
		end
		iconImg.Image = iconAssetId
		iconImg.ImageColor3 = self.Theme.TextMuted
		iconImg.ScaleType = Enum.ScaleType.Stretch
		iconImg.ZIndex = 14
		iconImg.Parent = tabBtn
	else
		-- It is text/emoji — render it as a TextLabel.
		local fallback = iconRaw or tabId:sub(1, 1)
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.BackgroundTransparency = 1
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.Font = self:GetFontBold()
		iconLabel.Text = tostring(fallback)
		iconLabel.TextColor3 = self.Theme.TextMuted
		iconLabel.TextSize = self:S(16)
		iconLabel.ZIndex = 14
		iconLabel.Parent = tabBtn
	end

	-- SideMode: show tab name beside icon (no hover tooltip needed)
	if sideMode then
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Name = "TabName"
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.new(0, self:S(34), 0, 0)
		nameLbl.Size = UDim2.new(1, -self:S(40), 1, 0)
		nameLbl.Font = self:GetFontSemibold()
		nameLbl.Text = tabId
		nameLbl.TextColor3 = self.Theme.TextMuted
		nameLbl.TextSize = self:S(12)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.ZIndex = 14
		nameLbl.Parent = tabBtn
		tabBtn:SetAttribute("SideMode", true)
	end

	-- Tooltip (normal mode only)
	local tooltip = Instance.new("TextLabel")
	tooltip.Name = "Tooltip"
	tooltip.BackgroundColor3 = self.Theme.Card
	tooltip.BorderSizePixel = 0
	tooltip.Position = UDim2.new(1, self:S(10), 0.5, -self:S(11))
	tooltip.Size = UDim2.new(0, 0, 0, self:S(22))
	tooltip.AutomaticSize = Enum.AutomaticSize.X
	tooltip.Font = self:GetFontSemibold()
	tooltip.Text = "  " .. tabId .. "  "
	tooltip.TextColor3 = self.Theme.Text
	tooltip.TextSize = self:S(11)
	tooltip.Visible = false
	tooltip.ZIndex = 1000
	tooltip.Parent = tabBtn
	self:CreateCorner(tooltip, UDim.new(0, 4))
	self:CreateStroke(tooltip, self.Theme.Border, 1, 0.3)

	tabBtn.MouseEnter:Connect(function()
		if self.CurrentTab ~= tabId then
			self:Tween(tabBtn, { BackgroundColor3 = self.Theme.CardHover }, 0.15)
		end
		if not sideMode then
			tooltip.Visible = true
		end
	end)
	tabBtn.MouseLeave:Connect(function()
		if self.CurrentTab ~= tabId then
			self:Tween(tabBtn, { BackgroundColor3 = self.Theme.Card }, 0.15)
		end
		tooltip.Visible = false
	end)

	local page = Instance.new("Frame")
	page.Name = tabId .. "Page"
	page.BackgroundTransparency = 1
	page.Size = UDim2.new(1, 0, 1, 0)
	page.Visible = false
	page.ZIndex = 11
	page.Parent = self.ContentArea

	-- Background card for the tab content (covers the game background)
	local bgCard = Instance.new("Frame")
	bgCard.Name = "BgCard"
	bgCard.BackgroundColor3 = self.Theme.Background
	bgCard.BorderSizePixel = 0
	bgCard.Size = UDim2.new(1, 0, 1, 0)
	bgCard.ZIndex = 10
	bgCard.Parent = page
	bgCard.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(bgCard, UDim.new(0, 6))

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = self.Theme.Border
	divider.BackgroundTransparency = 0.7
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0.5, -1, 0, 0)
	divider.Size = UDim2.new(0, 1, 1, 0)
	divider.ZIndex = 11
	divider.Parent = page

	local function createSide(position, size, name)
		local scrollFrame = Instance.new("ScrollingFrame")
		scrollFrame.Name = name
		scrollFrame.BackgroundTransparency = 1
		scrollFrame.BorderSizePixel = 0
		scrollFrame.Position = position
		scrollFrame.Size = size
		scrollFrame.ScrollBarThickness = 3
		scrollFrame.ScrollBarImageColor3 = self.Theme.Accent
		scrollFrame.ScrollBarImageTransparency = 0.5
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		scrollFrame.ZIndex = 11
		scrollFrame.Parent = page

		-- Heavy scroll feel for mobile
		scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		scrollFrame.ElasticBehavior = Enum.ElasticBehavior.Never
		scrollFrame.ScrollingEnabled = true

		-- Heavy scroll feel (desktop + mobile)
		scrollFrame.ScrollBarThickness = 4

		-- Add weight/inertia to scrolling
		local lastScrollPos = 0
		local scrollVelocity = 0
		local isScrolling = false

		scrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local currentPos = scrollFrame.CanvasPosition.Y
			scrollVelocity = currentPos - lastScrollPos
			lastScrollPos = currentPos
			isScrolling = true
		end)

		trackGenesisConnection(RunService.Heartbeat:Connect(function()
			if not isScrolling then
				return
			end
			if math.abs(scrollVelocity) < 0.5 then
				isScrolling = false
				return
			end
			-- Heavy damping - slows down faster
			scrollVelocity = scrollVelocity * 0.85
		end))
		self:CreateCorner(scrollFrame, UDim.new(0, 8))

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, self.SideMode and self:S(10) or self:S(8))
		layout.Parent = scrollFrame

		local padding = Instance.new("UIPadding")
		local sidePad = self.SideMode and self:S(12) or self:S(8)
		padding.PaddingLeft = UDim.new(0, sidePad)
		padding.PaddingRight = UDim.new(0, sidePad)
		padding.PaddingBottom = UDim.new(0, self:S(10))
		padding.PaddingTop = UDim.new(0, self.SideMode and self:S(4) or 0)
		padding.Parent = scrollFrame

		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			scrollFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + self:S(20))
		end)

		return scrollFrame
	end

	local left = createSide(UDim2.new(0, 0, 0, 0), UDim2.new(0.49, 0, 1, 0), "Left")
	local right = createSide(UDim2.new(0.51, 0, 0, 0), UDim2.new(0.49, 0, 1, 0), "Right")

	local tabData = { Button = tabBtn, Container = page, Left = left, Right = right, Id = tabId }
	self.Tabs[tabId] = tabData

	tabBtn.MouseButton1Click:Connect(function()
		self:SelectTab(tabId)
	end)

	if not self.CurrentTab then
		self:SelectTab(tabId)
	end

	return tabData
end

-- --- SELECT TAB ---------------------------------------------------------------
function GenesisX:SelectTab(tabId)
	if self.CurrentTab == tabId then
		return
	end

	local oldTab = self.CurrentTab and self.Tabs[self.CurrentTab]
	local newTab = self.Tabs[tabId]
	if not newTab then
		return
	end

	-- Hide old tab
	if oldTab and oldTab.Container then
		oldTab.Container.Visible = false
	end

	-- Show new tab
	newTab.Container.Visible = true

	-- Update sidebar buttons with smooth tween
	for id, data in pairs(self.Tabs) do
		local icon = data.Button:FindFirstChild("Icon")
		local nameLbl = data.Button:FindFirstChild("TabName")
		if id == tabId then
			self:Tween(data.Button, { BackgroundColor3 = self.Theme.Accent }, 0.2)
			if icon then
				if icon:IsA("TextLabel") then
					self:Tween(icon, { TextColor3 = Color3.new(1, 1, 1) }, 0.2)
				elseif icon:IsA("ImageLabel") then
					self:Tween(icon, { ImageColor3 = Color3.new(1, 1, 1) }, 0.2)
				end
			end
			if nameLbl and nameLbl:IsA("TextLabel") then
				self:Tween(nameLbl, { TextColor3 = Color3.new(1, 1, 1) }, 0.2)
			end
		else
			self:Tween(data.Button, { BackgroundColor3 = self.Theme.Card }, 0.2)
			if icon then
				if icon:IsA("TextLabel") then
					self:Tween(icon, { TextColor3 = self.Theme.TextMuted }, 0.2)
				elseif icon:IsA("ImageLabel") then
					self:Tween(icon, { ImageColor3 = self.Theme.TextMuted }, 0.2)
				end
			end
			if nameLbl and nameLbl:IsA("TextLabel") then
				self:Tween(nameLbl, { TextColor3 = self.Theme.TextMuted }, 0.2)
			end
		end
	end

	self.CurrentTab = tabId
end

-- --- CREATE SECTION -----------------------------------------------------------
function GenesisX:CreateSection(parent, textOrConfig, color, icon)
	-- Legacy compatibility: CreateSection(parent, "Title", color, icon) -> header only.
	-- New:                  CreateSection(parent, { Text, Icon, Locked }) -> container + Content.
	-- Locked is OPTIONAL: nil/false = unlocked.
	local isConfig = type(textOrConfig) == "table"
	local text, iconName, wantLocked

	if isConfig then
		text = textOrConfig.Text or "Section"
		iconName = textOrConfig.Icon
		wantLocked = textOrConfig.Locked == true
	else
		text = textOrConfig or "Section"
		iconName = icon
		wantLocked = false
	end

	local accentCol = self.Theme.Accent
	local iconSize = self:S(20)
	local headerH = self:S(36)
	local lockAsset = "rbxassetid://10723434711"

	-- ========== LEGACY MODE (header only, fully compatible) ==========
	if not isConfig then
		local wrap = Instance.new("Frame")
		wrap.Name = "Section_" .. text
		wrap.BackgroundTransparency = 1
		wrap.Size = UDim2.new(1, 0, 0, headerH)
		wrap.ZIndex = 12
		wrap.Parent = parent

		local labelBg = Instance.new("Frame")
		labelBg.Name = "LabelBg"
		labelBg.BackgroundTransparency = 1
		labelBg.AutomaticSize = Enum.AutomaticSize.X
		labelBg.Position = UDim2.new(0, self:S(4), 0, 0)
		labelBg.Size = UDim2.new(0, 0, 1, 0)
		labelBg.ZIndex = 13
		labelBg.Parent = wrap

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, self:S(8))
		layout.Parent = labelBg

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, self:S(2))
		pad.PaddingRight = UDim.new(0, self:S(6))
		pad.Parent = labelBg

		if iconName then
			local assetId = self:FormatAssetId(iconName)
			if assetId then
				local img = Instance.new("ImageLabel")
				img.Name = "Icon"
				img.BackgroundTransparency = 1
				img.Size = UDim2.fromOffset(iconSize, iconSize)
				img.Image = assetId
				img.ImageColor3 = accentCol
				img.ZIndex = 14
				img.Parent = labelBg
			end
		end

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.Font = self:GetFontBold()
		label.Text = text
		label.TextColor3 = accentCol
		label.TextSize = self:S(14)
		label.ZIndex = 14
		label.Parent = labelBg

		return wrap
	end

	-- ========== NEW MODE (config table: Content + Locked) ==========
	local sectionFrame = Instance.new("Frame")
	sectionFrame.Name = "Section_" .. text
	sectionFrame.BackgroundTransparency = 1
	sectionFrame.Size = UDim2.new(1, 0, 0, 0)
	sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
	sectionFrame.ClipsDescendants = false
	sectionFrame.ZIndex = 12
	sectionFrame.Parent = parent

	local mainLayout = Instance.new("UIListLayout")
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Padding = UDim.new(0, self:S(8))
	mainLayout.Parent = sectionFrame

	local wrap = Instance.new("Frame")
	wrap.Name = "Header"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, headerH)
	wrap.LayoutOrder = 1
	wrap.ZIndex = 13
	wrap.Parent = sectionFrame

	local labelBg = Instance.new("Frame")
	labelBg.Name = "LabelBg"
	labelBg.BackgroundTransparency = 1
	labelBg.AutomaticSize = Enum.AutomaticSize.X
	labelBg.Position = UDim2.new(0, self:S(4), 0, 0)
	labelBg.Size = UDim2.new(0, 0, 1, 0)
	labelBg.ZIndex = 14
	labelBg.Parent = wrap

	local hLayout = Instance.new("UIListLayout")
	hLayout.FillDirection = Enum.FillDirection.Horizontal
	hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hLayout.Padding = UDim.new(0, self:S(8))
	hLayout.Parent = labelBg

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, self:S(2))
	pad.PaddingRight = UDim.new(0, self:S(6))
	pad.Parent = labelBg

	if iconName then
		local assetId = self:FormatAssetId(iconName)
		if assetId then
			local img = Instance.new("ImageLabel")
			img.Name = "Icon"
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromOffset(iconSize, iconSize)
			img.Image = assetId
			img.ImageColor3 = accentCol
			img.ZIndex = 15
			img.Parent = labelBg
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.new(0, 0, 1, 0)
	label.Font = self:GetFontBold()
	label.Text = text
	label.TextColor3 = accentCol
	label.TextSize = self:S(14)
	label.ZIndex = 15
	label.Parent = labelBg

	-- Header lock (only appears when Locked).
	local headerLock = Instance.new("ImageLabel")
	headerLock.Name = "HeaderLock"
	headerLock.BackgroundTransparency = 1
	headerLock.AnchorPoint = Vector2.new(1, 0.5)
	headerLock.Position = UDim2.new(1, -self:S(8), 0.5, 0)
	headerLock.Size = UDim2.fromOffset(self:S(14), self:S(14))
	headerLock.Image = lockAsset
	headerLock.ImageColor3 = accentCol
	headerLock.ImageTransparency = wantLocked and 0 or 1
	headerLock.Visible = wantLocked
	headerLock.ZIndex = 15
	headerLock.Parent = wrap

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.ClipsDescendants = true
	body.LayoutOrder = 2
	body.ZIndex = 12
	body.Parent = sectionFrame

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.ClipsDescendants = false
	content.ZIndex = 12
	content.Parent = body

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, self:S(8))
	contentLayout.Parent = content

	local overlay = Instance.new("Frame")
	overlay.Name = "LockOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = wantLocked and 0.5 or 1
	overlay.BorderSizePixel = 0
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.Size = UDim2.new(1, 0, 0, 0)
	overlay.ZIndex = 100
	overlay.Visible = wantLocked
	overlay.Active = wantLocked
	overlay.Parent = body

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 6)
	overlayCorner.Parent = overlay

	local lockSize = self:S(56)
	local lockIcon = Instance.new("ImageLabel")
	lockIcon.Name = "LockIcon"
	lockIcon.BackgroundTransparency = 1
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	lockIcon.Size = UDim2.fromOffset(lockSize, lockSize)
	lockIcon.Image = lockAsset
	lockIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
	lockIcon.ImageTransparency = wantLocked and 0 or 1
	lockIcon.ScaleType = Enum.ScaleType.Fit
	lockIcon.ZIndex = 101
	lockIcon.Parent = overlay

	local function syncOverlaySize()
		local h = content.AbsoluteSize.Y
		if h < 1 then
			h = 0
		end
		overlay.Size = UDim2.new(1, 0, 0, h)
	end

	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncOverlaySize)
	contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(syncOverlaySize)
	end)
	task.defer(syncOverlaySize)

	local isLocked = wantLocked

	local function setLocked(state, instant)
		state = state == true
		if isLocked == state and not instant then
			return
		end
		isLocked = state
		syncOverlaySize()

		headerLock.Visible = state
		if instant then
			headerLock.ImageTransparency = state and 0 or 1
		else
			self:Tween(headerLock, { ImageTransparency = state and 0 or 1 }, 0.2)
		end

		if state then
			overlay.Visible = true
			overlay.Active = true
			if instant then
				overlay.BackgroundTransparency = 0.5
				lockIcon.ImageTransparency = 0
			else
				overlay.BackgroundTransparency = 1
				lockIcon.ImageTransparency = 1
				self:Tween(overlay, { BackgroundTransparency = 0.5 }, 0.3)
				self:Tween(lockIcon, { ImageTransparency = 0 }, 0.35)
			end
		else
			overlay.Active = false
			if instant then
				overlay.BackgroundTransparency = 1
				lockIcon.ImageTransparency = 1
				overlay.Visible = false
			else
				self:Tween(overlay, { BackgroundTransparency = 1 }, 0.3)
				self:Tween(lockIcon, { ImageTransparency = 1 }, 0.25)
				task.delay(0.32, function()
					if overlay and overlay.Parent and not isLocked then
						overlay.Visible = false
					end
				end)
			end
		end
	end

	return {
		Frame = sectionFrame,
		Header = wrap,
		Content = content,
		Overlay = overlay,
		IsLocked = function()
			return isLocked
		end,
		SetLocked = function(v, instant)
			setLocked(v, instant)
		end,
		Unlock = function(instant)
			setLocked(false, instant)
		end,
		Lock = function(instant)
			setLocked(true, instant)
		end,
	}
end

function GenesisX:CreateToggle(parent, config)
	config = config or {}
	local text = config.Text or "Toggle"
	local default = config.Default or false
	local callback = config.Callback or function() end
	local height = self:S(46)
	local trackWidth, trackHeight = self:S(46), self:S(24)

	local frame = Instance.new("Frame")
	frame.Name = "Toggle_" .. text
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.5)

	local hoverFill = Instance.new("Frame")
	hoverFill.Name = "HoverFill"
	hoverFill.BackgroundColor3 = Color3.new(1, 1, 1)
	hoverFill.BackgroundTransparency = 1
	hoverFill.BorderSizePixel = 0
	hoverFill.Size = UDim2.new(1, 0, 1, 0)
	hoverFill.ZIndex = 0
	hoverFill.Parent = frame
	self:CreateCorner(hoverFill)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, 0)
	label.Size = UDim2.new(1, -(trackWidth + self:S(42)), 1, 0)
	label.Font = self:GetFontSemibold()
	label.Text = text
	label.TextColor3 = self.Theme.Text
	label.TextSize = self:S(13)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.ZIndex = 13
	label.Parent = frame

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.AutoButtonColor = false
	track.BackgroundColor3 = default and self.Theme.ToggleOn or self.Theme.ToggleOff
	track.Position = UDim2.new(1, -trackWidth - self:S(14), 0.5, -trackHeight / 2)
	track.Size = UDim2.new(0, trackWidth, 0, trackHeight)
	track.Text = ""
	track.ZIndex = 14
	track.Parent = frame
	self:CreateCorner(track, UDim.new(1, 0))
	self:CreateStroke(track, default and self.Theme.Accent or self.Theme.Border, 1, default and 0.2 or 0.5)

	local trackStroke = track:FindFirstChildOfClass("UIStroke")
	local knobSize = self:S(18)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.Position = default and UDim2.new(1, -knobSize - self:S(3), 0.5, -knobSize / 2)
		or UDim2.new(0, self:S(3), 0.5, -knobSize / 2)
	knob.Size = UDim2.new(0, knobSize, 0, knobSize)
	knob.ZIndex = 15
	knob.Parent = track
	self:CreateCorner(knob, UDim.new(1, 0))
	self:CreateStroke(knob, Color3.fromRGB(200, 200, 200), 1, 0.3)

	local state = default

	local function update(newState, animated)
		local time = animated == false and 0 or 0.2
		state = newState
		if state then
			self:Tween(track, { BackgroundColor3 = self.Theme.ToggleOn }, time)
			if trackStroke then
				self:Tween(trackStroke, { Color = self.Theme.Accent, Transparency = 0.2 }, time)
			end
			self:Tween(
				knob,
				{ Position = UDim2.new(1, -knobSize - self:S(3), 0.5, -knobSize / 2) },
				time,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		else
			self:Tween(track, { BackgroundColor3 = self.Theme.ToggleOff }, time)
			if trackStroke then
				self:Tween(trackStroke, { Color = self.Theme.Border, Transparency = 0.5 }, time)
			end
			self:Tween(
				knob,
				{ Position = UDim2.new(0, self:S(3), 0.5, -knobSize / 2) },
				time,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end
	end

	track.MouseButton1Click:Connect(function()
		state = not state
		callback(state)
		update(state)
	end)
	frame.MouseEnter:Connect(function()
		self:Tween(hoverFill, { BackgroundTransparency = 0.97 }, 0.15)
	end)
	frame.MouseLeave:Connect(function()
		self:Tween(hoverFill, { BackgroundTransparency = 1 }, 0.15)
	end)

	return {
		Frame = frame,
		GetState = function()
			return state
		end,
		SetState = function(s)
			state = s
			callback(state)
			update(state)
		end,
	}
end

-- --- CREATE BUTTON ------------------------------------------------------------
function GenesisX:CreateButton(parent, config)
	config = config or {}
	local text = config.Text or "Button"
	local style = config.Style or "default"
	local callback = config.Callback or function() end
	local height = self:S(40)

	local frame = Instance.new("Frame")
	frame.Name = "Button_" .. text
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ZIndex = 12
	frame.Parent = parent

	-- Padding so it is not clipped at the sides.
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, self:S(4))
	pad.PaddingRight = UDim.new(0, self:S(4))
	pad.Parent = frame

	local bgColor, bgHover, strokeColor, textColor
	if style == "accent" then
		bgColor = self.Theme.AccentDark
		bgHover = self.Theme.Accent
		strokeColor = self.Theme.Accent
		textColor = Color3.new(1, 1, 1)
	elseif style == "warning" then
		bgColor = Color3.fromRGB(40, 25, 5)
		bgHover = Color3.fromRGB(55, 35, 8)
		strokeColor = Color3.fromRGB(200, 130, 30)
		textColor = Color3.new(1, 1, 1)
	elseif style == "info" then
		bgColor = Color3.fromRGB(10, 20, 45)
		bgHover = Color3.fromRGB(15, 28, 60)
		strokeColor = Color3.fromRGB(80, 140, 230)
		textColor = Color3.new(1, 1, 1)
	elseif style == "danger" then
		bgColor = Color3.fromRGB(45, 10, 10)
		bgHover = Color3.fromRGB(60, 15, 15)
		strokeColor = Color3.fromRGB(210, 60, 60)
		textColor = Color3.new(1, 1, 1)
	elseif style == "success" then
		bgColor = Color3.fromRGB(10, 40, 20)
		bgHover = Color3.fromRGB(15, 55, 28)
		strokeColor = Color3.fromRGB(60, 200, 100)
		textColor = Color3.new(1, 1, 1)
	else
		-- Default: theme-aware (adapts to Dark/Light automatically)
		bgColor = self.Theme.Card
		bgHover = self.Theme.CardHover
		strokeColor = self.Theme.Accent
		textColor = self.Theme.Text
	end

	local btn = Instance.new("TextButton")
	btn.Name = "Button"
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Font = self:GetFontBold()
	btn.Text = text
	btn.TextSize = self:S(13)
	btn.TextColor3 = textColor
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	btn.BackgroundColor3 = bgColor
	btn.ZIndex = 13
	btn.Parent = frame
	self:CreateCorner(btn)
	self:CreateStroke(btn, strokeColor, 1.2, 0.2)

	local rippleHolder = Instance.new("Frame")
	rippleHolder.Name = "RippleHolder"
	rippleHolder.BackgroundTransparency = 1
	rippleHolder.BorderSizePixel = 0
	rippleHolder.Size = UDim2.new(1, 0, 1, 0)
	rippleHolder.ClipsDescendants = true
	rippleHolder.ZIndex = btn.ZIndex + 1
	rippleHolder.Parent = btn
	self:CreateCorner(rippleHolder)

	btn.MouseEnter:Connect(function()
		local targetHover = bgHover
		if style == "default" then
			targetHover = self.Theme.CardHover
		end
		self:Tween(btn, { BackgroundColor3 = targetHover }, 0.15)
	end)
	btn.MouseLeave:Connect(function()
		local targetBg = bgColor
		if style == "default" then
			targetBg = self.Theme.Card
		end
		self:Tween(btn, { BackgroundColor3 = targetBg }, 0.15)
	end)
	btn.MouseButton1Click:Connect(function()
		callback()
	end)

	return {
		Frame = frame,
		Button = btn,
		SetText = function(t)
			btn.Text = t
		end,
		SetCallback = function(cb)
			callback = cb
		end,
	}
end

-- --- CREATE INPUT -------------------------------------------------------------
function GenesisX:CreateInput(parent, config)
	config = config or {}
	local labelText = config.Label or "Input"
	local default = config.Default or ""
	local placeholder = config.Placeholder or "Type here..."
	local callback = config.Callback or function() end
	local height = self:S(62)

	local frame = Instance.new("Frame")
	frame.Name = "Input_" .. labelText
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ClipsDescendants = true
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	local stroke = self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	label.Size = UDim2.new(1, -self:S(28), 0, self:S(16))
	label.Font = self:GetFontSemibold()
	label.Text = labelText
	label.TextColor3 = self.Theme.TextMuted
	label.TextSize = self:S(10)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = self.Theme.Input
	textBox.Position = UDim2.new(0, self:S(12), 0, self:S(28))
	textBox.Size = UDim2.new(1, -self:S(24), 0, self:S(26))
	textBox.Font = self:GetFont()
	textBox.Text = tostring(default)
	textBox.PlaceholderText = placeholder
	textBox.PlaceholderColor3 = self.Theme.TextMuted
	textBox.TextColor3 = self.Theme.Text
	textBox.TextSize = self:S(13)
	textBox.ClearTextOnFocus = false
	textBox.TextTruncate = Enum.TextTruncate.AtEnd
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.ClipsDescendants = true
	textBox.ZIndex = 14
	textBox.Parent = frame
	self:CreateCorner(textBox, UDim.new(0, 5))

	local textPad = Instance.new("UIPadding")
	textPad.PaddingLeft = UDim.new(0, self:S(8))
	textPad.PaddingRight = UDim.new(0, self:S(8))
	textPad.Parent = textBox

	textBox.Focused:Connect(function()
		self:Tween(stroke, { Color = self.Theme.Accent, Transparency = 0.1 }, 0.2)
		self:Tween(label, { TextColor3 = self.Theme.Accent }, 0.2)
	end)
	textBox.FocusLost:Connect(function()
		self:Tween(stroke, { Color = self.Theme.Border, Transparency = 0.4 }, 0.2)
		self:Tween(label, { TextColor3 = self.Theme.TextMuted }, 0.2)
		callback(textBox.Text)
	end)

	return {
		Frame = frame,
		TextBox = textBox,
		GetText = function()
			return textBox.Text
		end,
		SetText = function(t)
			textBox.Text = t
		end,
	}
end

-- --- CREATE NUMBER INPUT ------------------------------------------------------
function GenesisX:CreateNumberInput(parent, config)
	config = config or {}
	local labelText = config.Label or "Number"
	local default = config.Default or 0
	local min = config.Min or -math.huge
	local max = config.Max or math.huge
	local callback = config.Callback or function() end
	local height = self:S(62)

	local frame = Instance.new("Frame")
	frame.Name = "NumberInput_" .. labelText
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ClipsDescendants = true
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	local stroke = self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	label.Size = UDim2.new(1, -self:S(28), 0, self:S(16))
	label.Font = self:GetFontSemibold()
	label.Text = labelText
	label.TextColor3 = self.Theme.TextMuted
	label.TextSize = self:S(10)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	local textBox = Instance.new("TextBox")
	textBox.Name = "TextBox"
	textBox.BackgroundColor3 = self.Theme.Input
	textBox.Position = UDim2.new(0, self:S(12), 0, self:S(28))
	textBox.Size = UDim2.new(1, -self:S(24), 0, self:S(26))
	textBox.Font = self:GetFontBold()
	textBox.Text = tostring(default)
	textBox.TextColor3 = self.Theme.Text
	textBox.TextSize = self:S(13)
	textBox.ClearTextOnFocus = false
	textBox.TextTruncate = Enum.TextTruncate.AtEnd
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.ClipsDescendants = true
	textBox.ZIndex = 14
	textBox.Parent = frame
	self:CreateCorner(textBox, UDim.new(0, 5))

	local textPad = Instance.new("UIPadding")
	textPad.PaddingLeft = UDim.new(0, self:S(8))
	textPad.PaddingRight = UDim.new(0, self:S(8))
	textPad.Parent = textBox

	textBox.Focused:Connect(function()
		self:Tween(stroke, { Color = self.Theme.Accent, Transparency = 0.1 }, 0.2)
		self:Tween(label, { TextColor3 = self.Theme.Accent }, 0.2)
	end)
	textBox.FocusLost:Connect(function()
		self:Tween(stroke, { Color = self.Theme.Border, Transparency = 0.4 }, 0.2)
		self:Tween(label, { TextColor3 = self.Theme.TextMuted }, 0.2)
		local value = tonumber(textBox.Text)
		if value then
			value = math.clamp(value, min, max)
			textBox.Text = tostring(value)
			callback(value)
		else
			textBox.Text = tostring(default)
		end
	end)

	return {
		Frame = frame,
		TextBox = textBox,
		GetValue = function()
			return tonumber(textBox.Text)
		end,
		SetValue = function(v)
			v = math.clamp(v, min, max)
			textBox.Text = tostring(v)
		end,
	}
end

-- --- CREATE SLIDER ------------------------------------------------------------
function GenesisX:CreateSlider(parent, config)
	config = config or {}
	local text = config.Text or "Slider"
	local min = config.Min or 0
	local max = config.Max or 100
	if max < min then
		max = min
	end
	local range = max - min
	local hasRange = range > 0
	local default = math.clamp(tonumber(config.Default) or min, min, max)
	local defaultPercent = hasRange and (default - min) / range or 0
	local increment = config.Increment or nil
	local callback = config.Callback or function() end
	local height = self:S(62)

	local frame = Instance.new("Frame")
	frame.Name = "Slider_" .. text
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	label.Size = UDim2.new(0.6, 0, 0, self:S(18))
	label.Font = self:GetFontSemibold()
	label.Text = text
	label.TextColor3 = self.Theme.Text
	label.TextSize = self:S(12)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	-- -- Clickable value (becomes a TextBox when clicked) -------------------
	local valueBg = Instance.new("Frame")
	valueBg.Name = "ValueBg"
	valueBg.BackgroundColor3 = self.Theme.Accent
	valueBg.Position = UDim2.new(1, -self:S(42), 0, self:S(8))
	valueBg.Size = UDim2.new(0, self:S(36), 0, self:S(22))
	valueBg.ZIndex = 14
	valueBg.Parent = frame
	self:CreateCorner(valueBg, UDim.new(0, 4))

	-- Display label (normally visible).
	local valueLabel = Instance.new("TextButton")
	valueLabel.Name = "ValueLabel"
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(1, 0, 1, 0)
	valueLabel.Font = self:GetFontBold()
	valueLabel.Text = tostring(default)
	valueLabel.TextColor3 = Color3.new(1, 1, 1)
	valueLabel.TextSize = self:S(11)
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.AutoButtonColor = false
	valueLabel.ZIndex = 16
	valueLabel.Parent = valueBg

	-- Input TextBox (hidden by default).
	local valueInput = Instance.new("TextBox")
	valueInput.Name = "ValueInput"
	valueInput.BackgroundTransparency = 1
	valueInput.Size = UDim2.new(1, 0, 1, 0)
	valueInput.Font = self:GetFontBold()
	valueInput.Text = ""
	valueInput.PlaceholderText = ""
	valueInput.TextColor3 = Color3.new(1, 1, 1)
	valueInput.TextSize = self:S(11)
	valueInput.ClearTextOnFocus = true
	valueInput.Visible = false
	valueInput.ZIndex = 17
	valueInput.Parent = valueBg

	-- -- Track --------------------------------------------------------------
	local trackHeight = self:S(6)
	local trackBg = Instance.new("Frame")
	trackBg.Name = "TrackBg"
	trackBg.BackgroundColor3 = self.Theme.Input
	trackBg.Position = UDim2.new(0, self:S(14), 1, -self:S(20))
	trackBg.Size = UDim2.new(1, -self:S(28), 0, trackHeight)
	trackBg.ZIndex = 13
	trackBg.Parent = frame
	self:CreateCorner(trackBg, UDim.new(1, 0))

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = self.Theme.Accent
	fill.Size = UDim2.new(defaultPercent, 0, 1, 0)
	fill.ZIndex = 14
	fill.Parent = trackBg
	self:CreateCorner(fill, UDim.new(1, 0))

	local knobSize = self:S(16)
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.Position = UDim2.new(defaultPercent, -knobSize / 2, 0.5, -knobSize / 2)
	knob.Size = UDim2.new(0, knobSize, 0, knobSize)
	knob.ZIndex = 15
	knob.Parent = trackBg
	self:CreateCorner(knob, UDim.new(1, 0))
	self:CreateStroke(knob, self.Theme.Accent, 2, 0)

	local dragging = false
	local currentValue = default

	local function snapValue(v)
		if not hasRange then
			return min
		end
		if increment then
			v = math.floor((v - min) / increment + 0.5) * increment + min
		end
		return math.floor(math.clamp(v, min, max) * 100) / 100
	end

	local function applyValue(v)
		currentValue = snapValue(v)
		local percent = hasRange and (currentValue - min) / range or 0
		fill.Size = UDim2.new(percent, 0, 1, 0)
		knob.Position = UDim2.new(percent, -knobSize / 2, 0.5, -knobSize / 2)
		valueLabel.Text = tostring(currentValue)
		callback(currentValue)
	end

	local function updateFromDrag(input)
		if not hasRange or trackBg.AbsoluteSize.X <= 0 then
			return
		end
		local percent = math.clamp((input.Position.X - trackBg.AbsolutePosition.X) / trackBg.AbsoluteSize.X, 0, 1)
		applyValue(min + (max - min) * percent)
	end

	trackBg.InputBegan:Connect(function(input)
		if not hasRange then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			updateFromDrag(input)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if not hasRange then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
		end
	end)
	trackGenesisConnection(UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateFromDrag(input)
		end
	end))
	trackGenesisConnection(UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end))

	-- -- Click the value -> becomes an input ---------------------------------
	valueLabel.MouseButton1Click:Connect(function()
		valueLabel.Visible = false
		valueInput.Visible = true
		valueInput.Text = tostring(currentValue)
		valueInput:CaptureFocus()
	end)

	valueInput.FocusLost:Connect(function(enterPressed)
		local typed = tonumber(valueInput.Text)
		if typed then
			applyValue(typed)
		end
		valueInput.Visible = false
		valueLabel.Visible = true
		valueLabel.Text = tostring(currentValue)
	end)

	-- Highlight the value on hover.
	valueBg.MouseEnter:Connect(function()
		self:Tween(valueBg, { BackgroundColor3 = self.Theme.AccentHover }, 0.15)
	end)
	valueBg.MouseLeave:Connect(function()
		self:Tween(valueBg, { BackgroundColor3 = self.Theme.Accent }, 0.15)
	end)

	return {
		Frame = frame,
		GetValue = function()
			return currentValue
		end,
		SetValue = function(v)
			applyValue(v)
		end,
	}
end

-- --- HELPER: DROPDOWN POSITION -----------------------------------------------
local function getDropdownPosition(button, layout, maxHeight)
	local btnPos = button.AbsolutePosition
	local btnSize = button.AbsoluteSize
	local contentHeight = layout.AbsoluteContentSize.Y + 12
	local targetHeight = math.min(contentHeight, maxHeight)
	local success, camera = pcall(function()
		return workspace.CurrentCamera
	end)
	local screenHeight = (success and camera) and camera.ViewportSize.Y or 768
	local targetY = btnPos.Y + btnSize.Y + 4
	if targetY + targetHeight > screenHeight then
		targetY = btnPos.Y - targetHeight - 4
	end
	return UDim2.fromOffset(btnPos.X, targetY), targetHeight, contentHeight
end

-- --- CREATE DROPDOWN ----------------------------------------------------------
function GenesisX:CreateDropdown(parent, config)
	config = config or {}
	local labelText = config.Label or "Dropdown"
	local options = config.Options or {}
	local default = config.Default
	local callback = config.Callback or function() end
	local height = self:S(62)

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. labelText
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ClipsDescendants = false
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	label.Size = UDim2.new(1, -self:S(28), 0, self:S(14))
	label.Font = self:GetFontSemibold()
	label.Text = labelText
	label.TextColor3 = self.Theme.TextMuted
	label.TextSize = self:S(10)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	local dropBtn = Instance.new("TextButton")
	dropBtn.Name = "DropBtn"
	dropBtn.BackgroundColor3 = self.Theme.Input
	dropBtn.AutoButtonColor = false
	dropBtn.Position = UDim2.new(0, self:S(12), 0, self:S(26))
	dropBtn.Size = UDim2.new(1, -self:S(24), 0, self:S(28))
	dropBtn.Font = self:GetFontSemibold()
	dropBtn.Text = "  " .. (default or "Select...")
	dropBtn.TextColor3 = default and self.Theme.Text or self.Theme.TextMuted
	dropBtn.TextSize = self:S(12)
	dropBtn.TextXAlignment = Enum.TextXAlignment.Left
	dropBtn.TextTruncate = Enum.TextTruncate.AtEnd
	dropBtn.ZIndex = 14
	dropBtn.Parent = frame
	self:CreateCorner(dropBtn, UDim.new(0, 6))
	local dropStroke = self:CreateStroke(dropBtn, self.Theme.Border, 1, 0.4)

	-- SETA LUCIDE (chevron-down)
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.new(1, -self:S(28), 0, 0)
	arrow.Size = UDim2.new(0, self:S(26), 1, 0)
	arrow.Image = self:FormatAssetId("lucide-chevron-down") or ""
	arrow.ImageColor3 = self.Theme.Accent
	arrow.ZIndex = 15
	arrow.Parent = dropBtn

	local selected = default
	local isOpen = false

	local overlay = Instance.new("Frame")
	overlay.Name = "DropdownOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.ZIndex = 500
	overlay.Visible = false
	overlay.Parent = self.ScreenGui

	local listContainer = Instance.new("Frame")
	listContainer.Name = "ListContainer"
	listContainer.BackgroundColor3 = self.Theme.Card
	listContainer.BorderSizePixel = 0
	listContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	listContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	listContainer.Size = UDim2.new(0, 0, 0, 0)
	listContainer.ZIndex = 501
	listContainer.Visible = false
	listContainer.Parent = overlay
	self:CreateCorner(listContainer, UDim.new(0, 10))
	self:CreateStroke(listContainer, self.Theme.Accent, 1.5, 0.3)

	local listTitle = Instance.new("TextLabel")
	listTitle.Name = "Title"
	listTitle.BackgroundTransparency = 1
	listTitle.Position = UDim2.new(0, self:S(16), 0, self:S(12))
	listTitle.Size = UDim2.new(1, -self:S(32), 0, self:S(22))
	listTitle.Font = self:GetFontBold()
	listTitle.Text = labelText
	listTitle.TextColor3 = self.Theme.Text
	listTitle.TextSize = self:S(14)
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.TextTruncate = Enum.TextTruncate.AtEnd
	listTitle.ZIndex = 502
	listTitle.Parent = listContainer

	local dropList = Instance.new("ScrollingFrame")
	dropList.Name = "DropList"
	dropList.BackgroundTransparency = 1
	dropList.BorderSizePixel = 0
	dropList.Position = UDim2.new(0, self:S(12), 0, self:S(40))
	dropList.Size = UDim2.new(1, -self:S(24), 1, -self:S(52))
	dropList.ScrollBarThickness = 4
	dropList.ScrollBarImageColor3 = self.Theme.Accent
	dropList.ScrollBarImageTransparency = 0.4
	dropList.ZIndex = 502
	dropList.Parent = listContainer

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, self:S(4))
	listLayout.Parent = dropList

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, self:S(4))
	listPadding.PaddingBottom = UDim.new(0, self:S(4))
	listPadding.PaddingLeft = UDim.new(0, self:S(4))
	listPadding.PaddingRight = UDim.new(0, self:S(4))
	listPadding.Parent = dropList

	local function closeDropdown()
		if not isOpen then
			return
		end
		isOpen = false
		self:Tween(overlay, { BackgroundTransparency = 1 }, 0.2)
		self:Tween(listContainer, { Size = UDim2.new(0, self:S(320), 0, 0) }, 0.2)
		self:Tween(arrow, { Rotation = 0 }, 0.2)
		if dropStroke then
			self:Tween(dropStroke, { Color = self.Theme.Border, Transparency = 0.4 }, 0.2)
		end
		task.wait(0.2)
		overlay.Visible = false
		listContainer.Visible = false
	end

	local function populate()
		for _, child in ipairs(dropList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, option in ipairs(options) do
			local isSelected = option == selected

			local row = Instance.new("Frame")
			row.BackgroundColor3 = isSelected and self.Theme.AccentDark or self.Theme.Input
			row.Size = UDim2.new(1, 0, 0, self:S(36))
			row.ZIndex = 503
			row.Parent = dropList
			self:CreateCorner(row, UDim.new(0, 6))

			if isSelected then
				self:CreateStroke(row, self.Theme.Accent, 1, 0.2)
				-- CHECKMARK LUCIDE (check)
				local check = Instance.new("ImageLabel")
				check.Name = "Check"
				check.BackgroundTransparency = 1
				check.Position = UDim2.new(0, self:S(10), 0.5, -self:S(8))
				check.Size = UDim2.new(0, self:S(16), 0, self:S(16))
				check.Image = self:FormatAssetId("lucide-check") or ""
				check.ImageColor3 = Color3.new(1, 1, 1)
				check.ZIndex = 504
				check.Parent = row
			end

			local rowBtn = Instance.new("TextButton")
			rowBtn.BackgroundTransparency = 1
			rowBtn.Size = UDim2.new(1, 0, 1, 0)
			rowBtn.Font = self:GetFontSemibold()
			rowBtn.Text = (isSelected and "    " or "  ") .. option
			rowBtn.TextColor3 = isSelected and Color3.new(1, 1, 1) or self.Theme.TextSecondary
			rowBtn.TextSize = self:S(12)
			rowBtn.TextXAlignment = Enum.TextXAlignment.Left
			rowBtn.TextTruncate = Enum.TextTruncate.AtEnd
			rowBtn.ZIndex = 504
			rowBtn.Parent = row

			local rowPad = Instance.new("UIPadding")
			rowPad.PaddingLeft = UDim.new(0, isSelected and self:S(32) or self:S(12))
			rowPad.Parent = rowBtn

			rowBtn.MouseButton1Click:Connect(function()
				selected = option
				dropBtn.Text = "  " .. option
				dropBtn.TextColor3 = self.Theme.Text
				callback(option)
				closeDropdown()
			end)
			rowBtn.MouseEnter:Connect(function()
				if not isSelected then
					self:Tween(row, { BackgroundColor3 = self.Theme.CardHover }, 0.1)
				end
			end)
			rowBtn.MouseLeave:Connect(function()
				if not isSelected then
					self:Tween(row, { BackgroundColor3 = self.Theme.Input }, 0.1)
				end
			end)
		end
	end

	dropBtn.MouseEnter:Connect(function()
		self:Tween(dropBtn, { BackgroundColor3 = self.Theme.InputHover }, 0.15)
	end)
	dropBtn.MouseLeave:Connect(function()
		self:Tween(dropBtn, { BackgroundColor3 = self.Theme.Input }, 0.15)
	end)

	dropBtn.MouseButton1Click:Connect(function()
		if isOpen then
			closeDropdown()
			return
		end
		populate()
		local contentHeight = listLayout.AbsoluteContentSize.Y + self:S(60)
		local targetHeight = math.min(contentHeight, self:S(360))
		local targetWidth = self:S(320)
		overlay.Visible = true
		listContainer.Visible = true
		overlay.BackgroundTransparency = 1
		listContainer.Size = UDim2.new(0, targetWidth, 0, 0)
		self:Tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
		self:Tween(listContainer, {
			Size = UDim2.new(0, targetWidth, 0, targetHeight),
		}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self:Tween(arrow, { Rotation = 180 }, 0.2)
		if dropStroke then
			self:Tween(dropStroke, { Color = self.Theme.Accent, Transparency = 0.2 }, 0.2)
		end
		dropList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + self:S(16))
		isOpen = true
	end)

	overlay.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local pos = input.Position
			local listPos = listContainer.AbsolutePosition
			local listSize = listContainer.AbsoluteSize
			local inList = pos.X >= listPos.X
				and pos.X <= listPos.X + listSize.X
				and pos.Y >= listPos.Y
				and pos.Y <= listPos.Y + listSize.Y
			if not inList then
				closeDropdown()
			end
		end
	end)

	return {
		Frame = frame,
		GetValue = function()
			return selected
		end,
		SetValue = function(v)
			selected = v
			dropBtn.Text = "  " .. (v or "Select...")
			dropBtn.TextColor3 = v and self.Theme.Text or self.Theme.TextMuted
		end,
		SetOptions = function(newOptions)
			options = newOptions
		end,
	}
end

function GenesisX:CreateMultiDropdown(parent, config)
	config = config or {}
	local labelText = config.Label or "Multi Select"
	local options = config.Options or {}
	local default = config.Default or {}
	local callback = config.Callback or function() end
	local height = self:S(62)

	local frame = Instance.new("Frame")
	frame.Name = "MultiDropdown_" .. labelText
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ClipsDescendants = false
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	label.Size = UDim2.new(1, -self:S(28), 0, self:S(14))
	label.Font = self:GetFontSemibold()
	label.Text = labelText
	label.TextColor3 = self.Theme.TextMuted
	label.TextSize = self:S(10)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	local dropBtn = Instance.new("TextButton")
	dropBtn.Name = "DropBtn"
	dropBtn.BackgroundColor3 = self.Theme.Input
	dropBtn.AutoButtonColor = false
	dropBtn.Position = UDim2.new(0, self:S(12), 0, self:S(26))
	dropBtn.Size = UDim2.new(1, -self:S(24), 0, self:S(28))
	dropBtn.Font = self:GetFontSemibold()
	dropBtn.Text = "  Select..."
	dropBtn.TextColor3 = self.Theme.TextMuted
	dropBtn.TextSize = self:S(12)
	dropBtn.TextXAlignment = Enum.TextXAlignment.Left
	dropBtn.TextTruncate = Enum.TextTruncate.AtEnd
	dropBtn.ZIndex = 14
	dropBtn.Parent = frame
	self:CreateCorner(dropBtn, UDim.new(0, 6))
	local dropStroke = self:CreateStroke(dropBtn, self.Theme.Border, 1, 0.4)

	-- SETA LUCIDE (chevron-down)
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.new(1, -self:S(28), 0, 0)
	arrow.Size = UDim2.new(0, self:S(26), 1, 0)
	arrow.Image = self:FormatAssetId("lucide-chevron-down") or ""
	arrow.ImageColor3 = self.Theme.Accent
	arrow.ZIndex = 15
	arrow.Parent = dropBtn

	local selected = {}
	for _, v in ipairs(default) do
		table.insert(selected, v)
	end
	local isOpen = false

	local overlay = Instance.new("Frame")
	overlay.Name = "MultiDropdownOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.ZIndex = 500
	overlay.Visible = false
	overlay.Parent = self.ScreenGui

	local listContainer = Instance.new("Frame")
	listContainer.Name = "ListContainer"
	listContainer.BackgroundColor3 = self.Theme.Card
	listContainer.BorderSizePixel = 0
	listContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	listContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	listContainer.Size = UDim2.new(0, 0, 0, 0)
	listContainer.ZIndex = 501
	listContainer.Visible = false
	listContainer.Parent = overlay
	self:CreateCorner(listContainer, UDim.new(0, 10))
	self:CreateStroke(listContainer, self.Theme.Accent, 1.5, 0.3)

	local listTitle = Instance.new("TextLabel")
	listTitle.Name = "Title"
	listTitle.BackgroundTransparency = 1
	listTitle.Position = UDim2.new(0, self:S(16), 0, self:S(12))
	listTitle.Size = UDim2.new(0.6, 0, 0, self:S(22))
	listTitle.Font = self:GetFontBold()
	listTitle.Text = labelText
	listTitle.TextColor3 = self.Theme.Text
	listTitle.TextSize = self:S(14)
	listTitle.TextXAlignment = Enum.TextXAlignment.Left
	listTitle.TextTruncate = Enum.TextTruncate.AtEnd
	listTitle.ZIndex = 502
	listTitle.Parent = listContainer

	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "CountBadge"
	countBadge.BackgroundColor3 = self.Theme.Accent
	countBadge.Position = UDim2.new(1, -self:S(48), 0, self:S(10))
	countBadge.Size = UDim2.new(0, self:S(36), 0, self:S(22))
	countBadge.Font = self:GetFontBold()
	countBadge.Text = "0"
	countBadge.TextColor3 = Color3.new(1, 1, 1)
	countBadge.TextSize = self:S(11)
	countBadge.ZIndex = 502
	countBadge.Parent = listContainer
	self:CreateCorner(countBadge, UDim.new(0, 4))

	local dropList = Instance.new("ScrollingFrame")
	dropList.Name = "DropList"
	dropList.BackgroundTransparency = 1
	dropList.BorderSizePixel = 0
	dropList.Position = UDim2.new(0, self:S(12), 0, self:S(42))
	dropList.Size = UDim2.new(1, -self:S(24), 1, -self:S(56))
	dropList.ScrollBarThickness = 4
	dropList.ScrollBarImageColor3 = self.Theme.Accent
	dropList.ScrollBarImageTransparency = 0.4
	dropList.ZIndex = 502
	dropList.Parent = listContainer

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, self:S(4))
	listLayout.Parent = dropList

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, self:S(4))
	listPadding.PaddingBottom = UDim.new(0, self:S(4))
	listPadding.PaddingLeft = UDim.new(0, self:S(4))
	listPadding.PaddingRight = UDim.new(0, self:S(4))
	listPadding.Parent = dropList

	local function updateText()
		if #selected == 0 then
			dropBtn.Text = "  Select..."
			dropBtn.TextColor3 = self.Theme.TextMuted
		elseif #selected == 1 then
			dropBtn.Text = "  " .. selected[1]
			dropBtn.TextColor3 = self.Theme.Text
		else
			dropBtn.Text = "  " .. #selected .. " selected"
			dropBtn.TextColor3 = self.Theme.Text
		end
		countBadge.Text = tostring(#selected)
	end

	local function closeDropdown()
		if not isOpen then
			return
		end
		isOpen = false
		self:Tween(overlay, { BackgroundTransparency = 1 }, 0.2)
		self:Tween(listContainer, { Size = UDim2.new(0, self:S(320), 0, 0) }, 0.2)
		self:Tween(arrow, { Rotation = 0 }, 0.2)
		if dropStroke then
			self:Tween(dropStroke, { Color = self.Theme.Border, Transparency = 0.4 }, 0.2)
		end
		task.wait(0.2)
		overlay.Visible = false
		listContainer.Visible = false
	end

	local function isSelectedFn(name)
		for _, v in ipairs(selected) do
			if v == name then
				return true
			end
		end
		return false
	end

	local function toggle(name)
		for i, v in ipairs(selected) do
			if v == name then
				table.remove(selected, i)
				return false
			end
		end
		table.insert(selected, name)
		return true
	end

	local function populate()
		for _, child in ipairs(dropList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, option in ipairs(options) do
			local sel = isSelectedFn(option)

			local row = Instance.new("Frame")
			row.BackgroundColor3 = sel and self.Theme.AccentDark or self.Theme.Input
			row.Size = UDim2.new(1, 0, 0, self:S(38))
			row.ZIndex = 503
			row.Parent = dropList
			self:CreateCorner(row, UDim.new(0, 6))

			local cbSize = self:S(18)
			local checkbox = Instance.new("Frame")
			checkbox.Name = "Checkbox"
			checkbox.BackgroundColor3 = sel and self.Theme.Accent or self.Theme.Border
			checkbox.Position = UDim2.new(0, self:S(10), 0.5, -cbSize / 2)
			checkbox.Size = UDim2.new(0, cbSize, 0, cbSize)
			checkbox.ZIndex = 504
			checkbox.Parent = row
			self:CreateCorner(checkbox, UDim.new(0, 4))

			if sel then
				-- CHECKMARK LUCIDE (check)
				local check = Instance.new("ImageLabel")
				check.Name = "Check"
				check.BackgroundTransparency = 1
				check.Size = UDim2.new(1, 0, 1, 0)
				check.Image = self:FormatAssetId("lucide-check") or ""
				check.ImageColor3 = Color3.new(1, 1, 1)
				check.ZIndex = 505
				check.Parent = checkbox
			end

			local rowBtn = Instance.new("TextButton")
			rowBtn.BackgroundTransparency = 1
			rowBtn.Size = UDim2.new(1, 0, 1, 0)
			rowBtn.Font = self:GetFontSemibold()
			rowBtn.Text = "      " .. option
			rowBtn.TextColor3 = sel and Color3.new(1, 1, 1) or self.Theme.TextSecondary
			rowBtn.TextSize = self:S(12)
			rowBtn.TextXAlignment = Enum.TextXAlignment.Left
			rowBtn.TextTruncate = Enum.TextTruncate.AtEnd
			rowBtn.ZIndex = 504
			rowBtn.Parent = row

			local rowPad = Instance.new("UIPadding")
			rowPad.PaddingLeft = UDim.new(0, self:S(12))
			rowPad.Parent = rowBtn

			rowBtn.MouseButton1Click:Connect(function()
				toggle(option)
				callback(selected)
				updateText()
				populate()
			end)
			rowBtn.MouseEnter:Connect(function()
				if not sel then
					self:Tween(row, { BackgroundColor3 = self.Theme.CardHover }, 0.1)
				end
			end)
			rowBtn.MouseLeave:Connect(function()
				if not sel then
					self:Tween(row, { BackgroundColor3 = self.Theme.Input }, 0.1)
				end
			end)
		end
	end

	dropBtn.MouseEnter:Connect(function()
		self:Tween(dropBtn, { BackgroundColor3 = self.Theme.InputHover }, 0.15)
	end)
	dropBtn.MouseLeave:Connect(function()
		self:Tween(dropBtn, { BackgroundColor3 = self.Theme.Input }, 0.15)
	end)

	dropBtn.MouseButton1Click:Connect(function()
		if isOpen then
			closeDropdown()
			return
		end
		populate()
		local contentHeight = listLayout.AbsoluteContentSize.Y + self:S(64)
		local targetHeight = math.min(contentHeight, self:S(360))
		local targetWidth = self:S(320)
		overlay.Visible = true
		listContainer.Visible = true
		overlay.BackgroundTransparency = 1
		listContainer.Size = UDim2.new(0, targetWidth, 0, 0)
		self:Tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
		self:Tween(listContainer, {
			Size = UDim2.new(0, targetWidth, 0, targetHeight),
		}, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self:Tween(arrow, { Rotation = 180 }, 0.2)
		if dropStroke then
			self:Tween(dropStroke, { Color = self.Theme.Accent, Transparency = 0.2 }, 0.2)
		end
		dropList.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + self:S(16))
		isOpen = true
	end)

	overlay.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local pos = input.Position
			local listPos = listContainer.AbsolutePosition
			local listSize = listContainer.AbsoluteSize
			local inList = pos.X >= listPos.X
				and pos.X <= listPos.X + listSize.X
				and pos.Y >= listPos.Y
				and pos.Y <= listPos.Y + listSize.Y
			if not inList then
				closeDropdown()
			end
		end
	end)

	updateText()

	return {
		Frame = frame,
		GetValues = function()
			return selected
		end,
		SetValues = function(v)
			selected = {}
			for _, val in ipairs(v) do
				table.insert(selected, val)
			end
			updateText()
			-- Refresh UI if dropdown is open
			if isOpen then
				populate()
			end
		end,
		SetOptions = function(newOptions)
			options = newOptions
		end,
	}
end

-- --- CREATE CHECKBOX ----------------------------------------------------------
function GenesisX:CreateCheckbox(parent, config)
	config = config or {}
	local text = config.Text or "Checkbox"
	local default = config.Default or false
	local callback = config.Callback or function() end
	local height = self:S(42)

	local frame = Instance.new("Frame")
	frame.Name = "Checkbox_" .. text
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local cbSize = self:S(20)
	local checkbox = Instance.new("ImageButton")
	checkbox.Name = "Checkbox"
	checkbox.BackgroundColor3 = default and self.Theme.Accent or self.Theme.Input
	checkbox.AutoButtonColor = false
	checkbox.Position = UDim2.new(0, self:S(14), 0.5, -cbSize / 2)
	checkbox.Size = UDim2.new(0, cbSize, 0, cbSize)
	checkbox.Image = default and (self:FormatAssetId("lucide-check") or "") or ""
	checkbox.ImageColor3 = Color3.new(1, 1, 1)
	checkbox.ZIndex = 14
	checkbox.Parent = frame
	self:CreateCorner(checkbox, UDim.new(0, 4))
	self:CreateStroke(checkbox, default and self.Theme.Accent or self.Theme.Border, 1.5, default and 0.2 or 0.4)

	local cbStroke = checkbox:FindFirstChildOfClass("UIStroke")

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, self:S(42), 0, 0)
	label.Size = UDim2.new(1, -self:S(56), 1, 0)
	label.Font = self:GetFontSemibold()
	label.Text = text
	label.TextColor3 = self.Theme.Text
	label.TextSize = self:S(13)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 13
	label.Parent = frame

	local state = default

	checkbox.MouseButton1Click:Connect(function()
		state = not state
		callback(state)
		if state then
			self:Tween(checkbox, { BackgroundColor3 = self.Theme.Accent }, 0.2)
			if cbStroke then
				self:Tween(cbStroke, { Color = self.Theme.Accent, Transparency = 0.2 }, 0.2)
			end
			checkbox.Image = self:FormatAssetId("lucide-check") or ""
		else
			self:Tween(checkbox, { BackgroundColor3 = self.Theme.Input }, 0.2)
			if cbStroke then
				self:Tween(cbStroke, { Color = self.Theme.Border, Transparency = 0.4 }, 0.2)
			end
			checkbox.Image = ""
		end
	end)

	return {
		Frame = frame,
		GetState = function()
			return state
		end,
		SetState = function(s)
			state = s
			callback(state)
			self:Tween(checkbox, { BackgroundColor3 = state and self.Theme.Accent or self.Theme.Input }, 0.2)
			checkbox.Image = state and (self:FormatAssetId("lucide-check") or "") or ""
		end,
	}
end

-- --- CREATE LABEL -------------------------------------------------------------
function GenesisX:CreateLabel(parent, config)
	config = config or {}
	local text = config.Text or "Label"
	local color = config.Color or self.Theme.TextSecondary
	-- Manual line breaks and automatic wrapping work together. Only disable
	-- wrapping when a caller explicitly requests Wrapped = false.
	local wrapped = config.Wrapped ~= false
	local padV = self:S(10)
	local padH = self:S(14)
	local requestedSize = config.Size and self:S(config.Size) or nil
	local minHeight = math.max(self:S(36), requestedSize and requestedSize.Y.Offset or 0)

	local frame = Instance.new("Frame")
	frame.Name = "Label_" .. text:sub(1, 10)
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = requestedSize or UDim2.new(1, 0, 0, minHeight)
	frame.ClipsDescendants = false -- does not clip content
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.5)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, padH)
	pad.PaddingRight = UDim.new(0, padH)
	pad.PaddingTop = UDim.new(0, padV)
	pad.PaddingBottom = UDim.new(0, padV)
	pad.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, self:S(16))
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Font = self:GetFontSemibold()
	label.Text = text
	label.TextColor3 = color
	label.TextSize = self:S(12)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = wrapped
	label.ZIndex = 13
	label.Parent = frame

	-- Explicit measurement is more reliable than nested AutomaticSize for long,
	-- wrapped labels. In particular, Roblox can otherwise report a one-line
	-- TextBounds height while the label is inside an auto-sized section.
	local lastMeasuredWidth = -1
	local lastMeasuredText = nil
	local measuring = false
	local function updateHeight()
		if measuring or not label or not label.Parent or not frame or not frame.Parent then
			return
		end

		local availableWidth = math.floor(label.AbsoluteSize.X + 0.5)
		if availableWidth <= 1 then
			availableWidth = math.floor(frame.AbsoluteSize.X - padH * 2 + 0.5)
		end
		if availableWidth <= 1 then
			return
		end
		if availableWidth == lastMeasuredWidth and label.Text == lastMeasuredText then
			return
		end

		measuring = true
		lastMeasuredWidth = availableWidth
		lastMeasuredText = label.Text
		local widthLimit = wrapped and availableWidth or 100000
		local ok, bounds = pcall(function()
			return TextService:GetTextSize(
				tostring(label.Text),
				label.TextSize,
				label.Font,
				Vector2.new(widthLimit, 100000)
			)
		end)
		local textH = ok and bounds and math.ceil(bounds.Y) or math.ceil(label.TextBounds.Y)
		textH = math.max(textH, self:S(16))
		label.Size = UDim2.new(1, 0, 0, textH)
		local currentSize = frame.Size
		local targetSize = UDim2.new(
			currentSize.X.Scale,
			currentSize.X.Offset,
			currentSize.Y.Scale,
			math.max(minHeight, textH + padV * 2)
		)
		if frame.Size ~= targetSize then
			frame.Size = targetSize
		end
		measuring = false
	end

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHeight)
	label:GetPropertyChangedSignal("Text"):Connect(function()
		lastMeasuredText = nil
		task.defer(updateHeight)
	end)
	task.defer(updateHeight)

	return {
		Frame = frame,
		Label = label,
		SetText = function(t)
			label.Text = t
			task.defer(updateHeight)
		end,
		SetColor = function(c)
			label.TextColor3 = c
		end,
	}
end

-- --- CREATE LABEL TOGGLE SUBTITLE ---------------------------------------------
function GenesisX:CreateLabelToggleSubTitle(parent, config)
	config = config or {}
	local titleText = config.Title or "Title"
	local subtitles = config.Subtitles or {}
	local buttons = config.Buttons or {}
	local titleColor = config.TitleColor or self.Theme.Accent

	local subtitleCount = #subtitles
	local buttonCount = #buttons
	local baseHeight = self:S(46)
	local extraHeight = (subtitleCount * self:S(18)) + (buttonCount * self:S(34)) + self:S(16)
	local totalHeight = baseHeight + extraHeight

	local frame = Instance.new("Frame")
	frame.Name = "LabelToggleSubTitle_" .. titleText
	frame.BackgroundColor3 = self.Theme.Card
	frame.Size = UDim2.new(1, 0, 0, totalHeight)
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame)
	self:CreateStroke(frame, self.Theme.Border, 1, 0.4)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, self:S(14), 0, self:S(10))
	titleLabel.Size = UDim2.new(1, -self:S(28), 0, self:S(20))
	titleLabel.Font = self:GetFontBold()
	titleLabel.Text = titleText
	titleLabel.TextColor3 = titleColor
	titleLabel.TextSize = self:S(13)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 13
	titleLabel.Parent = frame

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.BackgroundTransparency = 1
	contentFrame.Position = UDim2.new(0, self:S(14), 0, self:S(32))
	contentFrame.Size = UDim2.new(1, -self:S(28), 1, -self:S(40))
	contentFrame.ZIndex = 13
	contentFrame.Parent = frame

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, self:S(6))
	contentLayout.Parent = contentFrame

	local subtitleLabels = {}
	for i, subText in ipairs(subtitles) do
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle_" .. i
		subLabel.BackgroundTransparency = 1
		subLabel.Size = UDim2.new(1, 0, 0, self:S(16))
		subLabel.Font = self:GetFont()
		subLabel.Text = subText
		subLabel.TextColor3 = self.Theme.TextSecondary
		subLabel.TextSize = self:S(11)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.ZIndex = 14
		subLabel.Parent = contentFrame
		table.insert(subtitleLabels, subLabel)
	end

	local buttonObjects = {}
	for i, btnConfig in ipairs(buttons) do
		local btnText = btnConfig.Text or "Button"
		local btnCallback = btnConfig.Callback or function() end
		local btnStyle = btnConfig.Style or "default"

		local btnFrame = Instance.new("Frame")
		btnFrame.Name = "ButtonFrame_" .. i
		btnFrame.BackgroundTransparency = 1
		btnFrame.Size = UDim2.new(1, 0, 0, self:S(32))
		btnFrame.ZIndex = 14
		btnFrame.Parent = contentFrame

		local btn = Instance.new("TextButton")
		btn.Name = "Button"
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.Font = self:GetFontBold()
		btn.Text = btnText
		btn.TextSize = self:S(12)
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		btn.ZIndex = 15
		btn.Parent = btnFrame
		self:CreateCorner(btn, UDim.new(0, 6))

		-- Solid color, no border, no gradient.
		local bgColor, hoverColor, textColor
		if btnStyle == "accent" then
			bgColor = self.Theme.Accent
			hoverColor = self.Theme.AccentHover
			textColor = Color3.new(1, 1, 1)
		elseif btnStyle == "danger" then
			bgColor = Color3.fromRGB(120, 30, 30)
			hoverColor = Color3.fromRGB(150, 40, 40)
			textColor = Color3.new(1, 1, 1)
		elseif btnStyle == "warning" then
			bgColor = Color3.fromRGB(120, 70, 0)
			hoverColor = Color3.fromRGB(150, 90, 0)
			textColor = Color3.new(1, 1, 1)
		elseif btnStyle == "info" then
			bgColor = Color3.fromRGB(30, 60, 120)
			hoverColor = Color3.fromRGB(40, 80, 150)
			textColor = Color3.new(1, 1, 1)
		else
			bgColor = self.Theme.Card
			hoverColor = self.Theme.CardHover
			textColor = self.Theme.Text
		end

		btn.BackgroundColor3 = bgColor
		btn.TextColor3 = textColor

		local rippleHolder = Instance.new("Frame")
		rippleHolder.Name = "RippleHolder"
		rippleHolder.BackgroundTransparency = 1
		rippleHolder.BorderSizePixel = 0
		rippleHolder.Size = UDim2.new(1, 0, 1, 0)
		rippleHolder.ClipsDescendants = true
		rippleHolder.ZIndex = btn.ZIndex + 1
		rippleHolder.Parent = btn
		self:CreateCorner(rippleHolder, UDim.new(0, 5))

		local btnData = {
			Button = btn,
			Frame = btnFrame,
			CurrentCallback = btnCallback,
			CurrentStyle = btnStyle,
			CurrentBg = bgColor,
			CurrentHover = hoverColor,
			CurrentText = textColor,
		}

		btn.MouseEnter:Connect(function()
			self:Tween(btn, { BackgroundColor3 = btnData.CurrentHover }, 0.15)
		end)
		btn.MouseLeave:Connect(function()
			self:Tween(btn, { BackgroundColor3 = btnData.CurrentBg }, 0.15)
		end)
		btn.MouseButton1Click:Connect(function()
			self:CreateRipple(btn, UserInputService:GetMouseLocation())
			btnData.CurrentCallback()
		end)

		table.insert(buttonObjects, btnData)
	end

	return {
		Frame = frame,
		Title = titleLabel,

		SetTitle = function(t)
			titleLabel.Text = t
		end,
		SetTitleColor = function(c)
			titleLabel.TextColor3 = c
		end,

		SetSubtitles = function(newSubtitles)
			for i, subLabel in ipairs(subtitleLabels) do
				subLabel.Text = newSubtitles[i] or ""
			end
		end,

		SetSubtitle = function(index, text)
			if subtitleLabels[index] then
				subtitleLabels[index].Text = text or ""
			end
		end,

		SetButtonText = function(index, text)
			local bd = buttonObjects[index]
			if bd then
				bd.Button.Text = text or ""
			end
		end,

		SetButtonCallback = function(index, callback)
			local bd = buttonObjects[index]
			if bd then
				bd.CurrentCallback = callback or function() end
			end
		end,

		SetButtonStyle = function(index, style)
			local bd = buttonObjects[index]
			if not bd then
				return
			end

			local newBg, newHover, newText
			if style == "accent" then
				newBg = self.Theme.Accent
				newHover = self.Theme.AccentHover
				newText = Color3.new(1, 1, 1)
			elseif style == "danger" then
				newBg = Color3.fromRGB(120, 30, 30)
				newHover = Color3.fromRGB(150, 40, 40)
				newText = Color3.new(1, 1, 1)
			elseif style == "warning" then
				newBg = Color3.fromRGB(120, 70, 0)
				newHover = Color3.fromRGB(150, 90, 0)
				newText = Color3.new(1, 1, 1)
			elseif style == "info" then
				newBg = Color3.fromRGB(30, 60, 120)
				newHover = Color3.fromRGB(40, 80, 150)
				newText = Color3.new(1, 1, 1)
			else
				newBg = self.Theme.Card
				newHover = self.Theme.CardHover
				newText = self.Theme.Text
			end

			bd.CurrentStyle = style
			bd.CurrentBg = newBg
			bd.CurrentHover = newHover
			bd.CurrentText = newText

			bd.Button.BackgroundColor3 = newBg
			bd.Button.TextColor3 = newText
		end,

		SetVisible = function(visible)
			frame.Visible = visible
		end,

		Subtitles = subtitleLabels,
		Buttons = buttonObjects,
	}
end

-- --- CREATE SEPARATOR ---------------------------------------------------------
function GenesisX:CreateSeparator(parent)
	local wrap = Instance.new("Frame")
	wrap.Name = "Separator"
	wrap.BackgroundTransparency = 1
	wrap.Size = UDim2.new(1, 0, 0, self:S(12))
	wrap.ZIndex = 12
	wrap.Parent = parent

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.BackgroundColor3 = self.Theme.Border
	line.BorderSizePixel = 0
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.ZIndex = 12
	line.Parent = wrap
	self:CreateGradient(line, Color3.new(0, 0, 0), self.Theme.BorderBright, 0)

	return wrap
end

-- --- CREATE STATUS CARD -------------------------------------------------------
function GenesisX:CreateStatusCard(parent, config)
	config = config or {}
	local title = config.Title or "Status"
	local height = self:S(110)

	local frame = Instance.new("Frame")
	frame.Name = "StatusCard"
	frame.BackgroundColor3 = self.Theme.Card
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.Active = true
	frame.ZIndex = 12
	frame.Parent = parent
	frame.BackgroundTransparency = self.Config.Transparency
	self:CreateCorner(frame, UDim.new(0, 8))

	local stroke = self:CreateStroke(frame, self.Theme.Accent, 1.5, 0)
	spawn(function()
		while frame and frame.Parent do
			self:Tween(stroke, { Transparency = 0.1 }, 1)
			task.wait(1)
			if not frame or not frame.Parent then
				break
			end
			self:Tween(stroke, { Transparency = 0.6 }, 1)
			task.wait(1)
		end
	end)

	local leftBar = Instance.new("Frame")
	leftBar.Name = "LeftBar"
	leftBar.BackgroundColor3 = self.Theme.Accent
	leftBar.BorderSizePixel = 0
	leftBar.Position = UDim2.new(0, 0, 0, 0)
	leftBar.Size = UDim2.new(0, 3, 1, 0)
	leftBar.ZIndex = 13
	leftBar.Parent = frame
	self:CreateCorner(leftBar, UDim.new(0, 10))

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = self.Theme.Header
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, self:S(34))
	header.Parent = frame
	self:CreateCorner(header, UDim.new(0, 10))

	local headerCover = Instance.new("Frame")
	headerCover.BackgroundColor3 = self.Theme.Header
	headerCover.BorderSizePixel = 0
	headerCover.Size = UDim2.new(1, 0, 0, 10)
	headerCover.Position = UDim2.new(0, 0, 1, -10)
	headerCover.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "Title"
	headerTitle.BackgroundTransparency = 1
	headerTitle.Position = UDim2.new(0, self:S(16), 0, 0)
	headerTitle.Size = UDim2.new(1, -self:S(16), 1, 0)
	headerTitle.Font = self:GetFontBold()
	headerTitle.Text = title
	headerTitle.TextColor3 = self.Theme.Text
	headerTitle.TextSize = self:S(12)
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.TextTruncate = Enum.TextTruncate.AtEnd
	headerTitle.ZIndex = 14
	headerTitle.Parent = header

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.new(0, self:S(14), 0, self:S(38))
	content.Size = UDim2.new(1, -self:S(28), 1, -self:S(48))
	content.ZIndex = 13
	content.Parent = frame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0, self:S(20))
	statusLabel.Font = self:GetFontSemibold()
	statusLabel.Text = "* Idle"
	statusLabel.TextColor3 = self.Theme.TextMuted
	statusLabel.TextSize = self:S(12)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.ZIndex = 14
	statusLabel.Parent = content

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "Info"
	infoLabel.BackgroundTransparency = 1
	infoLabel.Position = UDim2.new(0, 0, 0, self:S(22))
	infoLabel.Size = UDim2.new(1, 0, 0, self:S(16))
	infoLabel.Font = self:GetFont()
	infoLabel.Text = "Waiting..."
	infoLabel.TextColor3 = self.Theme.TextMuted
	infoLabel.TextSize = self:S(10)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextTruncate = Enum.TextTruncate.AtEnd
	infoLabel.ZIndex = 14
	infoLabel.Parent = content

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.BackgroundColor3 = self.Theme.Input
	barBg.Position = UDim2.new(0, 0, 1, -self:S(6))
	barBg.Size = UDim2.new(1, 0, 0, self:S(5))
	barBg.ClipsDescendants = true
	barBg.ZIndex = 13
	barBg.Parent = content
	self:CreateCorner(barBg, UDim.new(1, 0))

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = self.Theme.Accent
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BorderSizePixel = 0
	bar.ZIndex = 14
	bar.Parent = barBg
	self:CreateCorner(bar, UDim.new(1, 0))
	self:CreateGradient(bar, self.Theme.Accent, self.Theme.AccentDark, 0)

	self:MakeDraggable(frame, header)

	return {
		Frame = frame,
		SetStatus = function(status, color)
			statusLabel.Text = "* " .. status
			statusLabel.TextColor3 = color or self.Theme.TextMuted
		end,
		SetInfo = function(info)
			infoLabel.Text = info
		end,
		SetProgress = function(percent)
			bar.Size = UDim2.new(math.clamp(percent, 0, 1), 0, 1, 0)
		end,
		AnimateLoading = function(active, duration)
			if active then
				spawn(function()
					while active and frame and frame.Parent do
						bar.Size = UDim2.new(0, 0, 1, 0)
						local tween = self:Tween(bar, { Size = UDim2.new(1, 0, 1, 0) }, duration or 1.5)
						tween.Completed:Wait()
						task.wait(0.1)
					end
				end)
			else
				bar.Size = UDim2.new(0, 0, 1, 0)
			end
		end,
	}
end

-- ===============================================================================
-- --- NOTIFICATIONS - REDESIGN GENESISX ---------------------------------------
-- ===============================================================================
function GenesisX:Notify(config)
	config = config or {}
	local message = config.Text or "Notificacao"
	local title = config.Title or nil
	local subtitle = config.Subtitle or nil
	local subtitles = config.Subtitles or nil
	local ntype = config.Type or "info"
	local duration = config.Duration or 4

	self:UpdateScale()

	-- -- Dimensions -------------------------------------------------------------
	local W = self:S(ScaleData.IsMobile and 320 or 380)
	local PAD_RIGHT = self:S(16)
	local PAD_BOTTOM = self:S(16)
	local GAP = self:S(10)

	-- -- Type colors -----------------------------------------------------------
	local typeColors = {
		success = self.Theme.Success,
		warning = self.Theme.Warning,
		error = self.Theme.Error,
		info = self.Theme.Info,
		genesis = self.Theme.Accent,
	}
	local typeIcons = {
		success = "lucide-check-circle",
		warning = "lucide-alert-triangle",
		error = "lucide-x-circle",
		info = "lucide-info",
		genesis = "lucide-genesis-hub",
	}
	local accentColor = typeColors[ntype] or self.Theme.Info
	local iconName = typeIcons[ntype] or "lucide-info"

	-- -- Viewport helper -------------------------------------------------------
	local function viewport()
		local ok, cam = pcall(function()
			return workspace.CurrentCamera
		end)
		return (ok and cam) and cam.ViewportSize or Vector2.new(1366, 768)
	end

	-- -- Calculate dynamic height ----------------------------------------------
	local iconAreaW = self:S(70)
	local contentX = iconAreaW + self:S(12)
	local contentW = W - contentX - self:S(36) -- espaco pro X
	local baseH = self:S(72)
	local totalH = baseH

	-- If there is a subtitles array, calculate extra height.
	if subtitles and #subtitles > 0 then
		totalH = baseH + (#subtitles * self:S(18))
	elseif subtitle then
		totalH = baseH + self:S(18)
	end

	-- -- Create main frame -----------------------------------------------------
	local notif = Instance.new("Frame")
	notif.Name = "GX_Notification"
	notif.BackgroundColor3 = self.Theme.Background
	notif.BorderSizePixel = 0
	notif.Size = UDim2.fromOffset(W, totalH)
	notif.ClipsDescendants = true
	notif.ZIndex = 5000
	notif.Parent = self.ScreenGui
	self:CreateCorner(notif, UDim.new(0, self:S(10)))
	self:CreateStroke(notif, accentColor, 1.5, 0.3)

	-- -- Icon area (left) ------------------------------------------------------
	local iconArea = Instance.new("Frame")
	iconArea.Name = "IconArea"
	iconArea.BackgroundTransparency = 1
	iconArea.Size = UDim2.new(0, iconAreaW, 1, -self:S(4))
	iconArea.Position = UDim2.new(0, 0, 0, 0)
	iconArea.ZIndex = 5001
	iconArea.Parent = notif

	-- Icon background with a subtle glow.
	local iconBg = Instance.new("Frame")
	iconBg.Name = "IconBg"
	iconBg.BackgroundColor3 = accentColor
	iconBg.BackgroundTransparency = 0.85
	iconBg.BorderSizePixel = 0
	iconBg.Size = UDim2.fromOffset(self:S(46), self:S(46))
	iconBg.Position = UDim2.new(0.5, 0, 0.5, 0)
	iconBg.AnchorPoint = Vector2.new(0.5, 0.5)
	iconBg.ZIndex = 5001
	iconBg.Parent = iconArea
	self:CreateCorner(iconBg, UDim.new(1, 0))

	-- Stronger glow behind it.
	local iconGlow = Instance.new("Frame")
	iconGlow.Name = "IconGlow"
	iconGlow.BackgroundColor3 = accentColor
	iconGlow.BackgroundTransparency = 0.92
	iconGlow.BorderSizePixel = 0
	iconGlow.Size = UDim2.fromOffset(self:S(56), self:S(56))
	iconGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	iconGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	iconGlow.ZIndex = 5000
	iconGlow.Parent = iconArea
	self:CreateCorner(iconGlow, UDim.new(1, 0))

	-- Lucide icon.
	local iconImg = Instance.new("ImageLabel")
	iconImg.Name = "Icon"
	iconImg.BackgroundTransparency = 1
	iconImg.Size = UDim2.new(0.55, 0, 0.55, 0)
	iconImg.Position = UDim2.new(0.225, 0, 0.225, 0)
	iconImg.Image = self:FormatAssetId(iconName) or ""
	iconImg.ImageColor3 = accentColor
	iconImg.ZIndex = 5002
	iconImg.Parent = iconBg

	-- -- Vertical separator ----------------------------------------------------
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator.BackgroundColor3 = accentColor
	separator.BackgroundTransparency = 0.4
	separator.BorderSizePixel = 0
	separator.Size = UDim2.new(0, self:S(2), 0.7, 0)
	separator.Position = UDim2.new(0, iconAreaW, 0.5, 0)
	separator.AnchorPoint = Vector2.new(0, 0.5)
	separator.ZIndex = 5001
	separator.Parent = notif

	-- -- Content area (text) ---------------------------------------------------
	local contentArea = Instance.new("Frame")
	contentArea.Name = "ContentArea"
	contentArea.BackgroundTransparency = 1
	contentArea.Position = UDim2.new(0, contentX, 0, self:S(10))
	contentArea.Size = UDim2.new(0, contentW, 1, -self:S(14))
	contentArea.ZIndex = 5001
	contentArea.Parent = notif

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, self:S(20))
	titleLabel.Font = self:GetFontBold()
	titleLabel.Text = title or message
	titleLabel.TextColor3 = accentColor
	titleLabel.TextSize = self:S(13)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.ZIndex = 5002
	titleLabel.Parent = contentArea

	-- Subtitles container
	local subtitleY = self:S(22)
	local subtitleTexts = {}

	if subtitles and #subtitles > 0 then
		for i, subText in ipairs(subtitles) do
			local subLabel = Instance.new("TextLabel")
			subLabel.Name = "Subtitle_" .. i
			subLabel.BackgroundTransparency = 1
			subLabel.Position = UDim2.new(0, 0, 0, subtitleY + ((i - 1) * self:S(18)))
			subLabel.Size = UDim2.new(1, 0, 0, self:S(16))
			subLabel.Font = self:GetFont()
			subLabel.Text = subText
			subLabel.TextColor3 = self.Theme.TextSecondary
			subLabel.TextSize = self:S(11)
			subLabel.TextXAlignment = Enum.TextXAlignment.Left
			subLabel.TextTruncate = Enum.TextTruncate.AtEnd
			subLabel.ZIndex = 5002
			subLabel.Parent = contentArea
			table.insert(subtitleTexts, subLabel)
		end
	elseif subtitle then
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.BackgroundTransparency = 1
		subLabel.Position = UDim2.new(0, 0, 0, subtitleY)
		subLabel.Size = UDim2.new(1, 0, 0, self:S(16))
		subLabel.Font = self:GetFont()
		subLabel.Text = subtitle
		subLabel.TextColor3 = self.Theme.TextSecondary
		subLabel.TextSize = self:S(11)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.ZIndex = 5002
		subLabel.Parent = contentArea
	elseif not title then
		-- If there is no title, the message is the title (already set above)
		-- and does not need a subtitle.
	else
		-- If there is a title but no subtitle, use the message as the subtitle.
		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.BackgroundTransparency = 1
		subLabel.Position = UDim2.new(0, 0, 0, subtitleY)
		subLabel.Size = UDim2.new(1, 0, 0, self:S(16))
		subLabel.Font = self:GetFont()
		subLabel.Text = message
		subLabel.TextColor3 = self.Theme.TextSecondary
		subLabel.TextSize = self:S(11)
		subLabel.TextXAlignment = Enum.TextXAlignment.Left
		subLabel.TextTruncate = Enum.TextTruncate.AtEnd
		subLabel.ZIndex = 5002
		subLabel.Parent = contentArea
	end

	-- -- Close button (X) -------------------------------------------------------
	local closeSize = self:S(18)
	local closeBtn = Instance.new("ImageButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.BackgroundTransparency = 1
	closeBtn.Position = UDim2.new(1, -self:S(26), 0, self:S(10))
	closeBtn.Size = UDim2.fromOffset(closeSize, closeSize)
	closeBtn.Image = self:FormatAssetId("lucide-x") or ""
	closeBtn.ImageColor3 = self.Theme.TextMuted
	closeBtn.ImageTransparency = 0
	closeBtn.ZIndex = 5003
	closeBtn.AutoButtonColor = false
	closeBtn.Parent = notif

	closeBtn.MouseEnter:Connect(function()
		self:Tween(closeBtn, { ImageColor3 = Color3.new(1, 1, 1) }, 0.1)
	end)
	closeBtn.MouseLeave:Connect(function()
		self:Tween(closeBtn, { ImageColor3 = self.Theme.TextMuted }, 0.1)
	end)

	-- -- Register and position -------------------------------------------------
	table.insert(self._notifications, notif)
	local myIndex = #self._notifications

	local function targetX()
		return viewport().X - W - PAD_RIGHT
	end
	local function offscreenX()
		return viewport().X + W + 60
	end
	local function bottomY(index)
		return viewport().Y - (totalH + PAD_BOTTOM) * index - GAP * (index - 1)
	end

	local function restack(animated)
		local count = 0
		for i = 1, #self._notifications do
			if self._notifications[i] and self._notifications[i].Parent then
				count = count + 1
				local idx = count
				local yPos = bottomY(idx)
				local xPos = targetX()
				if animated then
					self:Tween(
						self._notifications[i],
						{ Position = UDim2.fromOffset(xPos, yPos) },
						0.25,
						Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out
					)
				else
					self._notifications[i].Position = UDim2.fromOffset(xPos, yPos)
				end
			end
		end
	end

	-- Initial position (off-screen to the right).
	do
		local yPos = bottomY(#self._notifications)
		notif.Position = UDim2.fromOffset(offscreenX(), yPos)
	end

	-- Entry animation.
	self:Tween(notif, {
		Position = UDim2.fromOffset(targetX(), bottomY(#self._notifications)),
	}, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	restack(true)

	-- -- Dismiss ---------------------------------------------------------------
	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true

		for i = #self._notifications, 1, -1 do
			if self._notifications[i] == notif then
				table.remove(self._notifications, i)
				break
			end
		end

		self:Tween(notif, {
			Position = UDim2.fromOffset(offscreenX(), notif.AbsolutePosition.Y),
		}, 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		task.delay(0.05, function()
			restack(true)
		end)

		task.delay(0.32, function()
			if notif and notif.Parent then
				notif:Destroy()
			end
		end)
	end

	closeBtn.MouseButton1Click:Connect(dismiss)

	-- Clicking the body also dismisses it.
	notif.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if not dismissed then
				dismiss()
			end
		end
	end)

	-- Auto-dismiss
	task.delay(duration, function()
		if not dismissed then
			dismiss()
		end
	end)

	-- Return API.
	return {
		Destroy = dismiss,
		SetTitle = function(t)
			if titleLabel then
				titleLabel.Text = t
			end
		end,
		SetSubtitle = function(index, text)
			if subtitleTexts[index] then
				subtitleTexts[index].Text = text
			end
		end,
		SetSubtitles = function(newSubs)
			for i, lbl in ipairs(subtitleTexts) do
				lbl.Text = newSubs[i] or ""
			end
		end,
	}
end

-- --- TRANSPARENCY -----------------------------------------------------------
function GenesisX:SetTransparency(value)
	value = math.clamp(value, 0, 1)
	self.Config.Transparency = value
	self:_SaveConfigFile("transparency.json", value)
	if self.ScreenGui then
		for _, obj in ipairs(self.ScreenGui:GetDescendants()) do
			-- Skip internal/effect elements that should stay opaque or have their own transparency
			local skipNames = {
				Ripple = true,
				Knob = true,
				Fill = true,
				Bar = true,
				BarBg = true,
				Shadow = true,
				SimpleShadow = true,
				IconGlow = true,
				IconBg = true,
				Checkbox = true,
				ValueBg = true,
				CountBadge = true,
				LeftBar = true,
				Track = true,
				RippleHolder = true,
				HoverFill = true,
				IconArea = true,
				Separator = true,
				Line = true,
				SidebarLine = true,
				Divider = true,
				HeaderCover = true,
				BgCard = true,
			}
			if obj:IsA("Frame") and not skipNames[obj.Name] then
				if obj.BackgroundTransparency < 1 then
					-- Don't make textboxes transparent
					if not obj:IsA("TextBox") then
						obj.BackgroundTransparency = value
					end
				end
			end
			-- Also apply to ImageLabels and ImageButtons that have backgrounds
			if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and not skipNames[obj.Name] then
				if obj.BackgroundTransparency < 1 then
					obj.BackgroundTransparency = value
				end
			end
			-- Apply to TextLabels that have backgrounds (rare but possible)
			if obj:IsA("TextLabel") and obj.BackgroundTransparency < 1 and not skipNames[obj.Name] then
				obj.BackgroundTransparency = value
			end
		end
	end
end

-- --- DESTROY ------------------------------------------------------------------
function GenesisX:Destroy()
	if self.ScreenGui then
		self.ScreenGui:Destroy()
	end
end

function GenesisX:GetWindow()
	return self.MainFrame
end

function GenesisX:SetVisible(visible)
	if self.MainFrame then
		self.MainFrame.Visible = visible
	end
end

function GenesisX:Toggle()
	if self.MainFrame then
		self:SetVisible(not self.MainFrame.Visible)
	end
end

function GenesisX:SetPosition(position)
	if self.MainFrame then
		self.MainFrame.Position = position
	end
end

function GenesisX:SetSize(size)
	if self.MainFrame then
		self.MainFrame.Size = size
	end
end

function GenesisX:SetTheme(newTheme)
	local oldTheme = self.Theme
	local targetTheme
	local themeString = "Dark"

	if type(newTheme) == "string" then
		if newTheme == "Light" and self.Themes and self.Themes.Light then
			targetTheme = self.Themes.Light
			themeString = "Light"
		elseif self.Themes and self.Themes.Dark then
			targetTheme = self.Themes.Dark
			themeString = "Dark"
		elseif self.Themes and self.Themes.Iron then
			targetTheme = self.Themes.Iron
			themeString = "Iron"
		end
	elseif type(newTheme) == "table" then
		targetTheme = newTheme
	end

	if not targetTheme or not oldTheme then
		return
	end
	self:_SaveConfigFile("theme.json", themeString)

	-- Map: old color (string) -> new color.
	local colorMap = {}
	for key, oldColor in pairs(oldTheme) do
		if targetTheme[key] and typeof(oldColor) == "Color3" and typeof(targetTheme[key]) == "Color3" then
			colorMap[tostring(oldColor)] = targetTheme[key]
		end
	end

	-- Update theme.
	self.Theme = targetTheme

	-- Update header buttons.
	if self.Header then
		for _, child in ipairs(self.Header:GetChildren()) do
			if child:IsA("ImageButton") then
				child.BackgroundColor3 = self.Theme.Input
				child.ImageColor3 = self.Theme.Accent
				local stroke = child:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = self.Theme.Accent
				end
			end
		end
	end

	-- Update all UI elements.
	if self.ScreenGui then
		for _, obj in ipairs(self.ScreenGui:GetDescendants()) do
			-- BackgroundColor3
			if obj:IsA("GuiObject") and colorMap[tostring(obj.BackgroundColor3)] then
				obj.BackgroundColor3 = colorMap[tostring(obj.BackgroundColor3)]
			end
			-- TextColor3
			if
				(obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
				and colorMap[tostring(obj.TextColor3)]
			then
				obj.TextColor3 = colorMap[tostring(obj.TextColor3)]
			end
			-- ImageColor3: protect white icons (Color3.new(1,1,1)) and icons using TextMuted.
			if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and colorMap[tostring(obj.ImageColor3)] then
				local current = obj.ImageColor3
				local white = Color3.new(1, 1, 1)
				-- If it is pure white, keep it white (icons must remain white).
				if current == white then
					obj.ImageColor3 = white
				else
					obj.ImageColor3 = colorMap[tostring(current)]
				end
			end
			-- UIStroke Color
			if obj:IsA("UIStroke") and colorMap[tostring(obj.Color)] then
				obj.Color = colorMap[tostring(obj.Color)]
			end
			-- UIGradient
			if obj:IsA("UIGradient") and obj.Color then
				local newKeypoints = {}
				for _, kp in ipairs(obj.Color.Keypoints) do
					local newColor = colorMap[tostring(kp.Value)] or kp.Value
					table.insert(newKeypoints, ColorSequenceKeypoint.new(kp.Time, newColor))
				end
				obj.Color = ColorSequence.new(newKeypoints)
			end
			-- ScrollBarImageColor3
			if obj:IsA("ScrollingFrame") and colorMap[tostring(obj.ScrollBarImageColor3)] then
				obj.ScrollBarImageColor3 = colorMap[tostring(obj.ScrollBarImageColor3)]
			end
		end
	end
end

function GenesisX:SetFont(fontName)
	self.Font = fontName or "Gotham"
	self:_SaveConfigFile("font.json", self.Font)
	local newFont = self:GetFont()
	local newBold = self:GetFontBold()
	local newSemi = self:GetFontSemibold()
	local newBlack = self:GetFontBlack()

	-- Update all text elements in the UI
	if self.ScreenGui then
		for _, obj in ipairs(self.ScreenGui:GetDescendants()) do
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				-- Determine which font weight to use based on current font
				local current = obj.Font
				if
					current == Enum.Font.GothamBold
					or current == Enum.Font.Arcade
					or current == Enum.Font.Fantasy
					or current == Enum.Font.GothamBlack
				then
					obj.Font = newBold
				elseif current == Enum.Font.GothamSemibold then
					obj.Font = newSemi
				elseif current == Enum.Font.GothamBlack then
					obj.Font = newBlack
				else
					obj.Font = newFont
				end
			end
		end
	end
end

-- --- RESET CONFIG COMMAND -----------------------------------------------------
local env = (getgenv and getgenv()) or _G or {}

env.G = env.G or {}
env.G.reset = function()
	local filesToDelete = {
		"GenesisX/Config/theme.json",
		"GenesisX/Config/font.json",
		"GenesisX/Config/transparency.json",
	}
	for _, path in ipairs(filesToDelete) do
		pcall(function()
			if delfile and isfile then
				if isfile(path) then
					delfile(path)
				end
			end
		end)
	end
	-- Notify user
	if GenesisX.ScreenGui then
		GenesisX:Notify({
			Title = "Config Reset",
			Text = "Settings reset successfully!",
			Subtitle = "Theme, Font, and Transparency have been restored.",
			Type = "success",
			Duration = 4,
		})
	end
	return true
end

env.SpectrumX = GenesisX
env.Notify = function(...)
	return GenesisX:Notify(...)
end

return GenesisX

end

-- Reconstructed from the captured GitHub payload; no application code was executed.
local runtimeEnvironment = (getfenv and getfenv(0)) or _ENV or _G
local game = runtimeEnvironment.game
local workspace = runtimeEnvironment.workspace
local _G = runtimeEnvironment._G
local function run(B, T, P, DfT, ...)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Workspace = game:GetService("Workspace")
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local VirtualInputManager = game:GetService("VirtualInputManager")
	local TweenService = game:GetService("TweenService")
	local HttpService = game:GetService("HttpService")

	-- These two locals intentionally replace only task scheduling and legacy
	-- spawn calls inside run; the lifecycle implementation stays outside this
	-- register-heavy function to remain below Luau's 200-local limit.
	local task, spawn = startGenesisRuntime(runtimeEnvironment, _G)

	local function getExecutorName()
		if identifyexecutor then
			local ok, name = pcall(identifyexecutor)
			if ok and name and name ~= "" then
				return name
			end
		end

		local checks = {
			{
				check = function()
					return syn and syn.request
				end,
				name = "Synapse X",
			},
			{
				check = function()
					return is_sirhurt_closure
				end,
				name = "SirHurt",
			},
			{
				check = function()
					return getsenv
				end,
				name = "Fluxus",
			},
			{
				check = function()
					return WeAreDevs_API
				end,
				name = "WeAreDevs",
			},
		}

		for _, entry in ipairs(checks) do
			local ok, result = pcall(entry.check)
			if ok and result then
				return entry.name
			end
		end

		return "Unknown"
	end

	local EXECUTOR_NAME = getExecutorName()
	local UNSUPPORTED_EXECUTORS = { "solara", "xeno", "velocity", "bunni" }

	local function isUnsupportedExecutor(name)
		local lowerName = name:lower()
		for _, blocked in ipairs(UNSUPPORTED_EXECUTORS) do
			if lowerName:find(blocked, 1, true) then
				return true
			end
		end
		return false
	end

	if isUnsupportedExecutor(EXECUTOR_NAME) then
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "GENESIS HUB",
				Text = EXECUTOR_NAME .. " is not supported!",
				Duration = 6,
			})
		end)
		task.wait(3)
		pcall(function()
			game.Players.LocalPlayer:Kick(
				"GENESIS HUB: "
					.. EXECUTOR_NAME
					.. " is not supported; use another executor (preferably a high-tier one)!"
			)
		end)
		return
	end

	-- Event/raid variables
	-- Set these in the executor during development. After Cloudflare deployment,
	-- pin the deployed Worker URL and READ key in the distributed client build.
	local Hub
	do
	local hubConfig = ((getgenv and getgenv()) or _G).GenesisEventHubConfig or _G.GenesisEventHubConfig or {}
	local EVENT_HUB_API = tostring(hubConfig.BaseUrl or ""):gsub("/+$", "")
	local EVENT_HUB_READ_KEY = tostring(hubConfig.ReadKey or "")
	local EVENT_HUB_POLL_SECONDS = 5
	_G.EventHubCache = { by_channel = {}, events = {}, last_poll = 0, ok = false }
	Hub = {
		writeKey = nil,
		revision = 0,
		lastSubmit = 0,
		lastSuccess = 0,
		lastIssueAttempt = 0,
		dirty = true,
		signature = "",
		stopped = false,
	}
	local hubEnabled = EVENT_HUB_API:match("^https://[%w%.%-]+") ~= nil
		and not EVENT_HUB_API:find("shadow.discloud.app", 1, true)
	local hubHeartbeatSeconds = math.clamp(tonumber(hubConfig.HeartbeatSeconds) or 15, 5, 60)
	Hub.enabled = hubEnabled
	Hub.devEnabled = type(hubConfig.DevBootstrapKey) == "string" and hubConfig.DevBootstrapKey ~= ""
	Hub.pollSeconds = EVENT_HUB_POLL_SECONDS

	local function EventHubHttp(opts)
		if not hubEnabled or type(opts.Url) ~= "string" or opts.Url:sub(1, #EVENT_HUB_API + 1) ~= EVENT_HUB_API .. "/" then
			return nil, nil
		end
		local method = opts.Method or "GET"
		if method ~= "GET" and method ~= "POST" then
			return nil, nil
		end
		local req = (syn and syn.request) or http_request or request
		if req then
			local ok, res = pcall(function()
				return req({ Url = opts.Url, Method = method, Headers = opts.Headers, Body = opts.Body })
			end)
			if not ok or not res then
				return nil, nil
			end
			return (res.Body or res.body), res
		end
		return nil, nil
	end

	function ReportGameEvent(channel, title, data)
		-- Detection callbacks retain their interface. The current-state scanner
		-- below publishes every live event together; one-shot callbacks do not
		-- create stale event assertions or contact Shadow directly.
		return hubEnabled, hubEnabled and "Included in current-state publisher" or "Cloudflare Event Hub not configured"
	end

	function PollGameEvents(channel)
		if not hubEnabled or EVENT_HUB_READ_KEY == "" then
			return nil
		end
		local url = EVENT_HUB_API .. "/api/events"
		if channel and channel ~= "" then
			url = url .. "?channel=" .. HttpService:UrlEncode(channel)
		end
		local resBody = EventHubHttp({ Url = url, Method = "GET", Headers = { Authorization = "Bearer " .. EVENT_HUB_READ_KEY } })
		if not resBody then
			return nil
		end
		local data = nil
		pcall(function()
			data = HttpService:JSONDecode(resBody)
		end)
		if data and data.ok then
			_G.EventHubCache.ok = true
			_G.EventHubCache.last_poll = tick()
			_G.EventHubCache.events = data.events or {}
			_G.EventHubCache.by_channel = data.by_channel or {}
		end
		return data
	end

	function Hub:issueWriteKey()
		if self.stopped or not hubEnabled or type(hubConfig.DevBootstrapKey) ~= "string" or hubConfig.DevBootstrapKey == "" then
			return false
		end
		if tick() - self.lastIssueAttempt < 30 then
			return false
		end
		self.lastIssueAttempt = tick()
		local body = HttpService:JSONEncode({
			username = Players.LocalPlayer.Name,
			user_id = Players.LocalPlayer.UserId,
		})
		local responseBody = EventHubHttp({
			Url = EVENT_HUB_API .. "/api/write/issue",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", ["X-Dev-Bootstrap-Key"] = hubConfig.DevBootstrapKey },
			Body = body,
		})
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(responseBody or "")
		end)
		if ok and type(decoded) == "table" and decoded.ok and type(decoded.write_key) == "string" then
			self.writeKey = decoded.write_key
			self.revision = 0
			return true
		end
		return false
	end

	function Hub:publish(events)
		if self.stopped or not hubEnabled then
			return false
		end
		local signature = HttpService:JSONEncode(events)
		if signature ~= self.signature then
			self.signature = signature
			self.dirty = true
		end
		if not self.dirty and tick() - self.lastSuccess < hubHeartbeatSeconds then
			return true
		end
		if tick() - self.lastSubmit < 1 then
			return false
		end
		if not self.writeKey and not self:issueWriteKey() then
			return false
		end
		self.lastSubmit = tick()
		self.revision = self.revision + 1
		local body = HttpService:JSONEncode({
			job_id = tostring(game.JobId),
			place_id = game.PlaceId,
			revision = self.revision,
			player_count = math.min(#Players:GetPlayers(), 12),
			events = events,
		})
		local responseBody, response = EventHubHttp({
			Url = EVENT_HUB_API .. "/api/write/state",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json", Authorization = "Bearer " .. self.writeKey },
			Body = body,
		})
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(responseBody or "")
		end)
		if ok and type(decoded) == "table" and decoded.ok then
			self.lastSuccess = tick()
			self.dirty = false
			return true
		end
		if response and (response.StatusCode == 401 or response.status == 401) then
			-- A revoked key must not silently mint a replacement using the dev gate.
			self.stopped = true
		end
		return false
	end

	_G._GenesisEventHubClient = Hub
	end

	function GetEvents(channel)
		local by = _G.EventHubCache.by_channel or {}
		if channel then
			return by[channel] or {}
		end
		return _G.EventHubCache.events or {}
	end

	-- Normalize the Hub event to the old Supabase format.
	local function EventHubToServer(ev, eventType)
		if not ev then
			return nil
		end
		local data = ev.data or {}
		return {
			job_id = ev.job_id,
			event_name = ev.title or data.event_name or "Unknown",
			event_type = eventType or data.event_type or ev.title or "Unknown",
			channel = ev.channel,
			timestamp = ev.created_at or 0,
			player_count = data.player_count or 0,
			place_id = ev.place_id,
			age_seconds = ev.age_seconds,
		}
	end

	if not _G._EventHubPollStarted then
		_G._EventHubPollStarted = true
		task.spawn(function()
			while true do
				pcall(function()
					PollGameEvents()
				end)
				task.wait(Hub.pollSeconds)
			end
		end)
	end

	-- ========== end Event Hub ==========
	local TeleportService = game:GetService("TeleportService")
	local LocalPlayer = Players.LocalPlayer
	-- PlayerStats may only replicate after Play; it must not stall initialization.

	-- Retire globals from earlier builds without changing the executor's own
	-- auto-execute or teleport queue configuration.
	_G.GENESIS_SCRIPT_URL = nil
	_G.GENESIS_SCRIPT_FILE = nil
	_G._autoExecuteQueued = nil
	_G._autoExecuteLastQueue = nil
	_G.buildAutoExecuteCode = nil
	_G.ensureLocalScriptCopy = nil
	_G.clearAutoExecuteQueue = nil
	_G.queueAutoExecute = nil

	-- These callbacks are defined before the position controllers below.
	-- Predeclare them so callbacks capture the intended locals instead of globals.
	local removeFarmFix
	local stopSeaEventBypass
	local stopFishing
	local removeConquestPosition
	local removeChestLootFix
	-- Stop movement controllers from a prior execution before this copy resets
	-- their globals.  Without this handoff, an old closure can keep pinning the
	-- current character after the UI has been reloaded.
	pcall(function()
		if type(_G._removeFarmFix) == "function" then
			_G._removeFarmFix()
		end
		if type(_G._stopSeaEventBypass) == "function" then
			_G._stopSeaEventBypass()
		end
		if type(_G._stopAbyssalAcquisition) == "function" then
			_G._stopAbyssalAcquisition()
		end
		if type(_G._stopFishing) == "function" then
			_G._stopFishing()
		end
		if type(_G._removeConquestPosition) == "function" then
			_G._removeConquestPosition()
		end
		if type(_G._removeChestLootFix) == "function" then
			_G._removeChestLootFix()
		end
		if type(_G._stopDailyQuestHover) == "function" then
			_G._stopDailyQuestHover()
		end
		if _G.HakiV2 and type(_G.HakiV2.stopLock) == "function" then
			_G.HakiV2.stopLock()
		end
		if _G.Raid then
			if type(_G.Raid.clearDungeonFarm) == "function" then
				_G.Raid.clearDungeonFarm()
			end
			if type(_G.Raid.stopDodge) == "function" then
				_G.Raid.stopDodge()
			end
			if type(_G.Raid.stopOrbit) == "function" then
				_G.Raid.stopOrbit()
			end
		end
	end)

	local function saveAndApply(key, value)
		SetSetting(key, value)
		-- If any farm/combat mode was disabled, stop skills and locks immediately.
		local combatKeys = {
			auto_farm = true,
			farmmaterial = true,
			allboss = true,
			easybounty = true,
			autoKillMobs = true,
			autoFarmBoss = true,
			autoFarmKaido = true,
			autoDarkBeard = true,
			autoCrimsonDemon = true,
			autoIceKing = true,
			autoSecondSea = true,
			autoThirdSea = true,
			autoHuntSerpent = true,
			autoKillAbyssalTyrant = true,
			autoDailyQuestsMaster = true,
			autoDailyQuest = true,
			autoSecondSeaDailyQuest = true,
			autoHuntPtero = true,
			autoRaidBoss_ExpertSwordman = true,
			autoRaidBoss_MsMother = true,
			autoRaidBoss_KingSamurai = true,
			autoRaidBoss_BushidoApe = true,
			autoRaidBoss_LordOfSaber = true,
			autoSKHD = true,
			autoGhostShip = true,
			autoConquest = true,
			auto_dungeon_v2 = true,
			autoFish = true,
		}
		if combatKeys[key] and value == false then
			_G.allowCombat = false
			if key == "autoFarmKaido" and type(_G._stopKaidoAcquisition) == "function" then
				pcall(_G._stopKaidoAcquisition, "toggle_disabled")
			end
			pcall(removeFarmFix)
			if key == "autoFish" then
				pcall(stopFishing)
			end
			pcall(function()
				if stopSeaEventBypass then
					stopSeaEventBypass()
				end
			end)
			if key == "autoConquest" and removeConquestPosition then
				pcall(removeConquestPosition)
			end
			if key == "autoSKHD" then
				_G.isLootingChests = false
				if removeChestLootFix then
					pcall(removeChestLootFix)
				end
			end
			if key == "autoBusoV2" then
				_G.isProgressingBusoV2 = false
			elseif key == "autoKenV2" then
				_G.isProgressingObservationV2 = false
			end
			if
				(key == "autoBusoV2" or key == "autoKenV2")
				and not GetSetting("autoBusoV2")
				and not GetSetting("autoKenV2")
				and _G.HakiV2
				and type(_G.HakiV2.stopLock) == "function"
			then
				pcall(_G.HakiV2.stopLock)
			end
			if key == "auto_dungeon_v2" and _G.Raid then
				pcall(_G.Raid.clearDungeonFarm)
				pcall(_G.Raid.stopDodge)
				pcall(_G.Raid.stopOrbit)
			end
			if key == "autoSKHD" or key == "autoGhostShip" or key == "autoHuntSerpent" then
				_G.seaEventActive = false
			end
		elseif combatKeys[key] and value == true and key ~= "autoFish" and not GetSetting("autoFish") then
			-- Fishing arbitrates live boss/combat ownership below. Only force an
			-- immediate handoff when Auto Fish itself is not enabled.
			pcall(stopFishing)
		end
	end

	local function setupProximityPrompt(prompt)
		if prompt:IsA("ProximityPrompt") then
			local runtime = getGenesisRuntimeState()
			if runtime and runtime.active and runtime.promptStates and not runtime.promptStates[prompt] then
				runtime.promptStates[prompt] = {
					HoldDuration = prompt.HoldDuration,
					RequiresLineOfSight = prompt.RequiresLineOfSight,
				}
			end
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
		end
	end

	for _, obj in pairs(workspace:GetDescendants()) do
		setupProximityPrompt(obj)
	end

	trackGenesisConnection(workspace.DescendantAdded:Connect(setupProximityPrompt))

	_G.name_game = "King_Legacy"
	_G.Setting = {
		selectedTools = { { "Mele" }, "tools" },
		toolSwitchSpeed = { 0.5, "tool_speed" },
		farmMethod = { "Default (Smart)", "farmMethod" },
		dungeon_select = { "Easy", "dungeon_select" },
		auto_dungeon_v2 = { false, "auto_dungeon_v2" },
		-- Gates only a new dungeon entry; a visible picker or active dungeon is
		-- already committed and keeps absolute priority until it ends.
		stopDungeonNearSeaEvent = { true, "stopDungeonNearSeaEvent" },
		dodge_v2 = { true, "dodge_v2" },
		ope_method_dungeon = { true, "ope_method_dungeon" },
		dungeon_method = { "Stand Above Mobs", "dungeon_method" },
		dungeon_farm_height = { 8, "dungeon_farm_height" },
		orbit_speed = { 2.5, "orbit_speed" },
		dungeon_cast_method = { "Remote (Aimbot)", "dungeon_cast_method" },
		dungeon_outside_tools = { { "Combat", "Fruit Power" }, "dungeon_outside_tools" },
		dungeon_tool_switch = { 0.5, "dungeon_tool_switch" },
		auto_farm = { false, "auto_farm" },
		distancemob = { 200, "distancemob" },
		distance = { 8, "distance" },
		lowheath = { 50, "lowheath" },
		material = { "Leather", "material" },
		farmmaterial = { false, "farmmaterial" },
		selectedBoss = { "", "selectedBoss" },
		autoFarmBoss = { false, "autoFarmBoss" },
		getQuestMaterial = { false, "getQuestMaterial" },
		allboss = { false, "allboss" },
		easybounty = { false, "easybounty" },
		autoKillMobs = { false, "autoKillMobs" },
		autoFarmKaido = { false, "autoFarmKaido" },
		autoDarkBeard = { false, "autoDarkBeard" },
		autoCrimsonDemon = { false, "autoCrimsonDemon" },
		autoIceKing = { false, "autoIceKing" },
		autoStoreFruits = { false, "autoStoreFruits" },
		autoSecondSea = { false, "autoSecondSea" },
		autoThirdSea = { false, "autoThirdSea" },
		autoBusoV2 = { false, "autoBusoV2" },
		autoKenV2 = { false, "autoKenV2" },

		autoGetPassives = { false, "autoGetPassives" },
		selectedPassiveBook = { "Chronicles Lore", "selectedPassiveBook" },
		selectedPassives = { {}, "selectedPassives" },

		autoConquest = { false, "autoConquest" },
		autoHopConquest = { false, "autoHopConquest" },
		autoRaidBoss_ExpertSwordman = { false, "autoRaidBoss_ExpertSwordman" },
		autoRaidBoss_MsMother = { false, "autoRaidBoss_MsMother" },
		autoRaidBoss_KingSamurai = { false, "autoRaidBoss_KingSamurai" },
		autoRaidBoss_BushidoApe = { false, "autoRaidBoss_BushidoApe" },
		autoRaidBoss_LordOfSaber = { false, "autoRaidBoss_LordOfSaber" },

		autoHuntSerpent = { false, "autoHuntSerpent" },
		autoHuntPtero = { false, "autoHuntPtero" },
		inSerpentWhirlpool = { false, "inSerpentWhirlpool" },

		selectedAnimation = { "Standard", "selectedAnimation" },

		autoDailyQuestsMaster = { false, "autoDailyQuestsMaster" },
		autoDailyQuest = { false, "autoDailyQuest" },
		autoSecondSeaDailyQuest = { false, "autoSecondSeaDailyQuest" },

		autoCollectPearl = { false, "autoCollectPearl" },

		autoFish = { false, "autoFish" },
		-- JSON-native per-sea CFrames. Each populated entry is the 12 numeric values
		-- returned by CFrame:GetComponents(); empty tables mean not configured.
		fishPositionsBySea = {
			{
				Sea1 = {},
				Sea2 = {},
				Sea3 = {},
			},
			"fishPositionsBySea",
		},
		fishWhenNotSpawned = { false, "fishWhenNotSpawned" },
		-- Hidden loadout fallback. The rod occupies the game's Sword/Primary slot,
		-- so preserve the last real sword across fresh joins and script reloads.
		lastEquippedSwordName = { "", "lastEquippedSwordName" },

		autoSKHD = { false, "autoSKHD" },
		autoGhostShip = { false, "autoGhostShip" },

		autoKillKraken = { false, "autoKillKraken" },
		autoKillDrakenfyr = { false, "autoKillDrakenfyr" },
		autoKillAbyssalTyrant = { false, "autoKillAbyssalTyrant" },
		autoKillDeepseaCrusher = { false, "autoKillDeepseaCrusher" },
		autoKillGalleons = { false, "autoKillGalleons" },

		autoRaceV3 = { false, "autoRaceV3" },
		raceV3HealthPercent = { 30, "raceV3HealthPercent" },

		autoRaceIsland = { false, "autoRaceIsland" },

		autoHopSeaBosses = { false, "autoHopSeaBosses" },

		selectedMaterials = { {}, "selectedMaterials" },
		materialBuyCount = { 1, "materialBuyCount" },
		autoBuyMaterials = { false, "autoBuyMaterials" },

		buykey = { false, "buykey" },
		key_count = { 1, "key_count" },
		key1 = { "Copper Key", "key1" },
		key2 = { "Copper Key", "key2" },
		random1 = { false, "random1" },
		random3 = { false, "random3" },
		random10 = { false, "random10" },

		jobId = { "", "jobId" },
		targetJobId = { "", "targetJobId" },

		buso = { true, "buso" },
		ken = { true, "ken" },
		hao = { true, "hao" },
		z = { true, "z" },
		x = { true, "x" },
		c = { true, "c" },
		v = { true, "v" },
		f = { true, "f" },
		b = { true, "b" },
		e = { true, "e" },

		autoMelee = { false, "autoMelee" },
		autoDefense = { false, "autoDefense" },
		autoSword = { false, "autoSword" },
		autoFruit = { false, "autoFruit" },
		autoDistribute = { false, "autoDistribute" },
		distributeValue = { 1, "distributeValue" },

		walkOnWater = { true, "walkOnWater" },
		freeLegacyPose = { false, "freeLegacyPose" },

		opeMethod = { false, "opeMethod" },

		bringFruits = { false, "bringFruits" },

		serverSearchQuery = { "", "serverSearchQuery" },
		onlyNewServers = { false, "onlyNewServers" },

		autoSmartHop = { false, "autoSmartHop" },
		smartHopTimer = { 1, "smartHopTimer" },
		smartHopTargetEvent = { {}, "smartHopTargetEvent" },
		smartHopTargetRaid = { {}, "smartHopTargetRaid" },
		smartHopPriority = { "Both", "smartHopPriority" },

		hideNotify = { false, "hideNotify" },
		blackScreen = { false, "blackScreen" },

	}

	function GetSetting(key)
		if _G.Setting[key] then
			return _G.Setting[key][1]
		end
		return nil
	end

	function SetSetting(key, value)
		_G.Setting[key][1] = value
		SaveSettings()
	end

	function LoadSettings()
		if readfile and writefile and isfile and isfolder then
			if not isfolder("GenesisX") then
				makefolder("GenesisX")
			end
			if not isfolder("GenesisX/Saves") then
				makefolder("GenesisX/Saves")
			end
			local filePath = "GenesisX/Saves/" .. _G.name_game .. ".json"
			if isfile(filePath) then
				local success, data = pcall(function()
					return HttpService:JSONDecode(readfile(filePath))
				end)
				if success and data then
					for key, value in pairs(data) do
						if _G.Setting[key] then
							_G.Setting[key][1] = value
						end
					end
					-- Existing sea-specific daily toggles keep working after the new
					-- master switch is introduced. A newly saved master takes precedence.
					if data.autoDailyQuestsMaster == nil then
						_G.Setting.autoDailyQuestsMaster[1] = data.autoDailyQuest == true
							or data.autoSecondSeaDailyQuest == true
					end
					print("YOKOSO, WATASHI NO SOUL SOCIETY.")
				end
			end
		end
	end

	function SaveSettings()
		if readfile and writefile and isfile and isfolder then
			local filePath = "GenesisX/Saves/" .. _G.name_game .. ".json"
			local dataToSave = {}
			for key, value in pairs(_G.Setting) do
				dataToSave[key] = value[1]
			end
			writefile(filePath, HttpService:JSONEncode(dataToSave))
		end
	end

	LoadSettings()

	_G._GenesisFishingPositionConfigByPlaceId = {
		[4520749081] = { slot = "Sea1", sea = 1 },
		[6381829480] = { slot = "Sea2", sea = 2 },
		[15759515082] = { slot = "Sea3", sea = 3 },
	}

	_G._GenesisGetFishingPositionConfig = function(placeId)
		return _G._GenesisFishingPositionConfigByPlaceId[tonumber(placeId) or game.PlaceId]
	end

	_G._GenesisGetConfiguredFishingCFrame = function(placeId)
		local config = _G._GenesisGetFishingPositionConfig(placeId)
		if not config then
			return nil, "Fishing position is unsupported in this sea", nil
		end
		local positions = GetSetting("fishPositionsBySea")
		local components = type(positions) == "table" and positions[config.slot] or nil
		if type(components) ~= "table" or #components == 0 then
			return nil, "Sea " .. tostring(config.sea) .. " fishing position is not set", config
		end
		if #components ~= 12 then
			return nil, "Sea " .. tostring(config.sea) .. " fishing position is invalid", config
		end
		local numericComponents = {}
		for index = 1, 12 do
			local value = tonumber(components[index])
			if not value or value ~= value or math.abs(value) == math.huge then
				return nil, "Sea " .. tostring(config.sea) .. " fishing position is invalid", config
			end
			numericComponents[index] = value
		end
		local ok, cf = pcall(CFrame.new, table.unpack(numericComponents, 1, 12))
		if not ok or typeof(cf) ~= "CFrame" then
			return nil, "Sea " .. tostring(config.sea) .. " fishing position is invalid", config
		end
		return cf, nil, config
	end

	-- Race islands are manual destinations now. Keep the legacy key readable so
	-- old save files remain compatible, but never let a saved toggle resume the
	-- removed background teleporter.
	_G.Setting.autoRaceIsland[1] = false

	_G.webhook = {
		-- Event Hub channels (they are no longer webhook URLs).
		sea_events_1 = "sea_events_1",
		sea_events_2 = "sea_events_2",
		sea_events_3 = "sea_events_3",
		raid_bosses_1 = "raid_bosses_1",
		raid_bosses_2 = "raid_bosses_2",
		raid_bosses_3 = "raid_bosses_3",
		race_island = "race_island",
		fruits = "fruits",
	}

	_G.notifiedEvents = {}
	_G.lastFruitStock = ""
	_G._GenesisFruitLiveState = nil
	_G.playerCount = 0
	_G.jobIdEncoded = ""
	_G.pos_skill = CFrame.new(0, 0, 0)
	_G.Raid = _G.Raid or {}
	_G.Sigma = _G.Sigma or { lastSkill = 0, lastM1 = 0 }
	_G.NameMob = 0
	_G.NameQuest = ""
	_G.MX = 0
	_G.MY = 0
	_G.MZ = 0
	_G.mob = {}
	_G.currentToolIndex = 1
	_G.seaEventActive = false
	_G.busoActive = false
	_G.kenActive = false
	_G.isProgressingBusoV2 = false
	_G.isProgressingObservationV2 = false
	_G.conquestActive = false
	_G.busoV2Status = "Idle"
	_G.kenV2Status = "Idle"
	_G.currentEventName = "None"
	_G.currentEventHealth = 0
	_G.currentEventMaxHealth = 0
	_G.currentRaceIsland = "None"
	_G.currentBossIndex = 1
	_G.bossesKilled = {}
	_G.lastBusoAttempt = 0
	_G.lastKenAttempt = 0
	_G.isLootingChests = false
	_G.collectingPearls = false
	_G.lastFruitCheck = {}
	_G.hasLegacyPose = false
	_G.lastOpeCheck = 0
	_G.isFishing = false
	_G.fishingPosition = nil
	_G.lastEventCheck = tick()
	_G.ghostShipKilled = false
	_G.thirdSeaTimerValue = "--:--"
	_G.lastTimerCheck = 0
	_G.secondSeaProgression = "No"
	_G.secondSeaHasMap = false
	_G.thirdSeaProgression = false
	_G.thirdSeaHasHeart = false
	_G.thirdSeaKrakenSpawned = false
	_G.thirdSeaKrakenBoss = nil
	_G.thirdSeaProgressionActive = false
	_G.fishingPreviousTool = nil
	_G.fishingPreviousWeaponName = nil
	_G.fishingToolCaptured = false
	_G.fishingLoadoutBusy = false
	_G.fishingState = "idle"
	_G.fishingGeneration = 0
	_G.fishingRestoreAttempts = 0
	_G.fishingNextRestoreAttempt = 0
	_G.fishingRestoreFailureNotified = false
	_G.ghostChestAttemptState = setmetatable({}, { __mode = "k" })
	_G.ghostChestExhaustedNotified = setmetatable({}, { __mode = "k" })
	_G.lastWhirlpoolNotified = false
	_G._GenesisPriorityOwner = "resolving"
	_G._GenesisPriorityDetail = "startup"
	_G._GenesisPriorityUpdatedAt = os.clock()
	_G._GenesisPriorityRank = {
		dungeon_committed = 0,
		major_sea_event = 1,
		world_raid_boss = 2,
		serpent = 3,
		galleon = 4,
		daily_quest_return = 5,
		dungeon_entry = 6,
		daily_quest = 7,
		fishing = 8,
	}
	_G._GenesisDailyReturnRequested = false
	_G._GenesisDungeonCommit = {
		latched = false,
		stage = "outside",
		latchedAt = 0,
		lastEvidenceAt = 0,
		entered = false,
	}

	_G.lootState = {
		SeaKing = { active = false, startTime = 0, duration = 0, source = nil },
		Hydra = { active = false, startTime = 0, duration = 0, source = nil },
	}
	_G.seaKingIslandEmpty = false
	_G.hydraIslandEmpty = false

	_G.monitoringSeaKing = false
	_G.monitoringHydra = false
	_G.seaKingJoinLootStarted = false
	_G.hydraJoinLootStarted = false
	_G.lootThreads = {}

	_G.postEventTimers = {
		Hydra = { active = false, startTime = 0, waitTime = 15, islandPresent = false },
		GhostShip = { active = false, startTime = 0, waitTime = 10 },
		SeaKing = { active = false, startTime = 0, waitTime = 10 },
	}

	_G.timerTriggeredByIsland = {
		Hydra = false,
		SeaKing = false,
		GhostShip = false,
	}

	_G._GenesisGetVisibleDungeonPicker = function()
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local chooseMap = playerGui and playerGui:FindFirstChild("ChooseMap")
		local frame = chooseMap and chooseMap:FindFirstChild("ChooseMapFrame")
		if not chooseMap or not frame then
			return nil, nil
		end
		if chooseMap:IsA("ScreenGui") and not chooseMap.Enabled then
			return nil, nil
		end
		if frame:IsA("GuiObject") and not frame.Visible then
			return nil, nil
		end
		return chooseMap, frame
	end

	_G._GenesisGetSeaEventCountdown = function()
		if game.PlaceId ~= 15759515082 then
			return nil, nil
		end
		local rawValue = ReplicatedStorage:GetAttribute("ThirdSeaMonsterSpawnText")
		local timerText = tostring(rawValue or "--:--")
		local normalized = string.upper(timerText)
		if
			string.find(normalized, "SET SAIL", 1, true)
			or string.find(normalized, "UNUSUAL", 1, true)
			or string.find(normalized, "HUNT IT DOWN", 1, true)
		then
			return 0, timerText
		end

		-- The replicated attribute has used both a bare clock and a clock embedded in
		-- status text. Parse the clock wherever it appears so a harmless wording
		-- change cannot accidentally reopen dungeon entry inside the 15-minute gate.
		local hours, minutes, seconds = string.match(timerText, "(%d+):(%d+):(%d+)")
		if hours then
			return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds), timerText
		end
		minutes, seconds = string.match(timerText, "(%d+):(%d+)")
		if minutes then
			return tonumber(minutes) * 60 + tonumber(seconds), timerText
		end
		local minuteValue = string.match(timerText, "(%d+)%s*[mM]")
		local secondValue = string.match(timerText, "(%d+)%s*[sS]")
		if minuteValue or secondValue then
			return (tonumber(minuteValue) or 0) * 60 + (tonumber(secondValue) or 0), timerText
		end
		return nil, timerText
	end

	_G._GenesisIsSeaEventNear = function()
		if GetSetting("stopDungeonNearSeaEvent") == false then
			return false, nil, nil
		end
		local seconds, timerText = _G._GenesisGetSeaEventCountdown()
		return seconds ~= nil and seconds <= 15 * 60, seconds, timerText
	end

	_G._GenesisUpdateDungeonCommit = function()
		local state = _G._GenesisDungeonCommit
		local now = os.clock()
		local picker = _G._GenesisGetVisibleDungeonPicker()
		if picker then
			if not state.latched or state.stage ~= "picker" then
				state.latchedAt = now
			end
			state.latched = true
			state.stage = "picker"
			state.lastEvidenceAt = now
			state.entered = false
			return true, state.stage
		end

		local inDungeon = false
		if _G.Raid and type(_G.Raid.checkInRaid) == "function" then
			local ok, result = pcall(_G.Raid.checkInRaid)
			inDungeon = ok and result == true
		else
			local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
			inDungeon = playerGui and playerGui:FindFirstChild("DungeonUI") ~= nil or false
		end
		if inDungeon then
			if not state.latched then
				state.latchedAt = now
			end
			state.latched = true
			state.stage = "active"
			state.lastEvidenceAt = now
			state.entered = true
			return true, state.stage
		end

		if state.latched then
			local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
			local loading = playerGui and playerGui:FindFirstChild("LoadingGUI")
			local grace = state.entered and 4 or 45
			if loading and now - state.latchedAt <= 90 then
				state.stage = "transition"
				state.lastEvidenceAt = now
				return true, state.stage
			end
			if now - state.lastEvidenceAt <= grace then
				state.stage = "transition"
				return true, state.stage
			end
		end

		state.latched = false
		state.stage = "outside"
		state.latchedAt = 0
		state.lastEvidenceAt = 0
		state.entered = false
		return false, state.stage
	end

	_G._GenesisCancelDungeonEntry = function(reason)
		local committed = _G._GenesisUpdateDungeonCommit()
		if committed then
			return false
		end
		local raid = _G.Raid
		if raid then
			raid._entryGeneration = (raid._entryGeneration or 0) + 1
			raid._entryBusy = false
			raid._mainLoopBusy = false
			raid._entryCancelReason = reason or "priority_changed"
			if type(raid.stopCombat) == "function" then
				pcall(raid.stopCombat)
			end
			if type(raid.clearDungeonFarm) == "function" then
				pcall(raid.clearDungeonFarm)
			end
			if type(raid.stopDodge) == "function" then
				pcall(raid.stopDodge)
			end
			if type(raid.stopOrbit) == "function" then
				pcall(raid.stopOrbit)
			end
		end
		return true
	end

	_G._GenesisSetPriorityOwner = function(owner, detail)
		owner = owner or "idle"
		-- The picker can appear between the resolver's first state check and a leaf
		-- activity returning. Revalidate at the ownership boundary so that narrow
		-- race cannot publish (or retain) an outside owner after entry is committed.
		if owner ~= "dungeon_committed" and _G._GenesisPriorityOwner == "dungeon_entry" then
			local committed, stage = _G._GenesisUpdateDungeonCommit()
			if committed then
				owner = "dungeon_committed"
				detail = stage
				_G.allowCombat = false
				if _G.isFishing or _G.fishingToolCaptured then
					pcall(stopFishing)
				end
				pcall(removeFarmFix)
				pcall(stopSeaEventBypass)
				pcall(removeChestLootFix)
				if removeConquestPosition then
					pcall(removeConquestPosition)
				end
				if type(_G._stopAbyssalAcquisition) == "function" then
					pcall(_G._stopAbyssalAcquisition)
				end
			end
		end
		local previous = _G._GenesisPriorityOwner
		if previous == "dungeon_entry" and owner ~= "dungeon_entry" and owner ~= "dungeon_committed" then
			_G._GenesisCancelDungeonEntry("preempted_by_" .. owner)
		end

		local previousWasEvent = previous == "major_sea_event" or previous == "serpent" or previous == "galleon"
		local nextIsEvent = owner == "major_sea_event" or owner == "serpent" or owner == "galleon"
		if previousWasEvent and not nextIsEvent then
			if type(_G._stopSeaEventBypass) == "function" then
				pcall(_G._stopSeaEventBypass)
			end
			_G.seaEventActive = false
			_G.currentEventName = "None"
			_G.currentEventHealth = 0
			_G.currentEventMaxHealth = 0
		end

		_G._GenesisPriorityOwner = owner
		_G._GenesisPriorityDetail = detail
		_G._GenesisPriorityUpdatedAt = os.clock()
	end

	_G._GenesisDungeonOwnsAutomation = function()
		local committed, stage = _G._GenesisUpdateDungeonCommit()
		if committed then
			return true, stage
		end
		local owner = _G._GenesisPriorityOwner
		if owner == "dungeon_entry" then
			return true, "entry"
		end
		if owner == "resolving" and GetSetting("auto_dungeon_v2") then
			return true, "resolving"
		end
		return false, "outside"
	end

	_G._GenesisCanStartDungeon = function()
		if not GetSetting("auto_dungeon_v2") then
			return false, "disabled"
		end
		local committed, stage = _G._GenesisUpdateDungeonCommit()
		if committed then
			return true, stage
		end
		local nearEvent, _, timerText = _G._GenesisIsSeaEventNear()
		if nearEvent then
			return false, "sea_event_near:" .. tostring(timerText)
		end
		if _G._GenesisPriorityOwner ~= "dungeon_entry" then
			return false, "owned_by:" .. tostring(_G._GenesisPriorityOwner)
		end
		return true, "entry"
	end

	_GBackPosition = nil

	_G.hideNotifyActive = false
	_G.blackScreenGui = nil
	_G.savedPopupState = nil

	Sea3EventsTimerLabel = nil
	GalleonStatusLabel = nil
	RaceIslandStatusLabel = nil
	SeaKingTimerLabel = nil
	GhostShipTimerLabel = nil
	serpentTimerLabel = nil

	_G.recentlyLeftServers = {}
	_G.recentlyLeftTimeout = 120
	_G.lastEventState = false

	COMPLETED_FILE = "GenesisX/Config/done.json"
	IGNORE_FILE = "GenesisX/Config/ignore.json"

	function loadCompletedServers()
		if not readfile then
			return {}
		end
		local success, data = pcall(function()
			if isfile(COMPLETED_FILE) then
				local content = readfile(COMPLETED_FILE)
				local decoded = HttpService:JSONDecode(content)
				if decoded and decoded.dn and type(decoded.dn) == "table" then
					return decoded.dn
				end
			end
			return {}
		end)
		if success then
			return data
		end
		return {}
	end

	function saveCompletedServers(completedList)
		if not writefile then
			return
		end
		pcall(function()
			if not isfolder("GenesisX") then
				makefolder("GenesisX")
			end
			if not isfolder("GenesisX/Config") then
				makefolder("GenesisX/Config")
			end
			local dataToSave = { dn = completedList }
			writefile(COMPLETED_FILE, HttpService:JSONEncode(dataToSave))
		end)
	end

	function cleanupCompletedServers()
		local completed = loadCompletedServers()
		local now = tick()
		local newList = {}
		for _, entry in ipairs(completed) do
			if type(entry) == "table" and entry.timestamp and now - entry.timestamp < 300 then
				table.insert(newList, entry)
			end
		end
		if #newList ~= #completed then
			saveCompletedServers(newList)
		end
	end

	function markCurrentServerAsCompleted()
		local currentJobId = game.JobId
		if not currentJobId or currentJobId == "" then
			return
		end
		local completed = loadCompletedServers()
		for _, entry in ipairs(completed) do
			if entry.jobId == currentJobId then
				return
			end
		end
		table.insert(completed, { jobId = currentJobId, timestamp = tick() })
		saveCompletedServers(completed)
		SpectrumX:Notify({
			Title = "GENESIS HUB",
			Text = "Thinking ...",
			Type = "genesis",
			Duration = 2,
		})
	end

	function isServerCompleted(jobId)
		if not jobId then
			return false
		end
		cleanupCompletedServers()
		local completed = loadCompletedServers()
		for _, entry in ipairs(completed) do
			if entry.jobId == jobId then
				return true
			end
		end
		return false
	end

	spawn(function()
		while true do
			task.wait(300)
			pcall(cleanupCompletedServers)
		end
	end)

	function loadIgnoredServers()
		if not readfile then
			return {}
		end
		local success, data = pcall(function()
			if isfile(IGNORE_FILE) then
				local content = readfile(IGNORE_FILE)
				local decoded = HttpService:JSONDecode(content)
				if decoded and decoded.ig and type(decoded.ig) == "table" then
					return decoded.ig
				end
			end
			return {}
		end)
		if success then
			return data
		end
		return {}
	end

	function saveIgnoredServers(ignoredList)
		if not writefile then
			return
		end
		pcall(function()
			if not isfolder("GenesisX") then
				makefolder("GenesisX")
			end
			if not isfolder("GenesisX/Config") then
				makefolder("GenesisX/Config")
			end
			local dataToSave = { ig = ignoredList }
			writefile(IGNORE_FILE, HttpService:JSONEncode(dataToSave))
		end)
	end

	function cleanupIgnoredServers()
		local ignored = loadIgnoredServers()
		local now = tick()
		local newList = {}
		for _, entry in ipairs(ignored) do
			if type(entry) == "table" and entry.timestamp and now - entry.timestamp < 300 then
				table.insert(newList, entry)
			end
		end
		if #newList ~= #ignored then
			saveIgnoredServers(newList)
		end
	end

	-- In-memory cache of servers that just failed (full/private) — prevents immediately selecting them again.
	_G._recentFailedJobs = _G._recentFailedJobs or {}
	_G._recentFailedTimeout = 45 -- segundos
	local encodeBase64
	local decodeBase64

	local function markRecentFailed(jobId)
		if not jobId or jobId == "" then
			return
		end
		_G._recentFailedJobs[tostring(jobId)] = tick()
		-- Also try the encoded/decoded form.
		pcall(function()
			if encodeBase64 then
				local enc = encodeBase64(tostring(jobId))
				if enc and enc ~= "" then
					_G._recentFailedJobs[enc] = tick()
				end
			end
			if decodeBase64 and #tostring(jobId) >= 32 and not string.find(tostring(jobId), "-") then
				local raw = decodeBase64(tostring(jobId))
				if raw and raw ~= "" then
					_G._recentFailedJobs[raw] = tick()
				end
			end
		end)
	end

	local function isRecentlyFailed(jobId)
		if not jobId then
			return false
		end
		local key = tostring(jobId)
		local ts = _G._recentFailedJobs[key]
		if ts and (tick() - ts) < (_G._recentFailedTimeout or 45) then
			return true
		end
		-- Clear stale entries occasionally.
		if math.random() < 0.05 then
			local now = tick()
			for k, t in pairs(_G._recentFailedJobs) do
				if now - t > (_G._recentFailedTimeout or 45) then
					_G._recentFailedJobs[k] = nil
				end
			end
		end
		return false
	end

	function markServerAsIgnored(jobId)
		if not jobId or jobId == "" then
			return
		end
		jobId = tostring(jobId)
		markRecentFailed(jobId)

		local ignored = loadIgnoredServers()
		local changed = false
		local already = false
		for _, entry in ipairs(ignored) do
			if entry.jobId == jobId then
				already = true
				break
			end
		end
		if not already then
			table.insert(ignored, { jobId = jobId, timestamp = tick() })
			changed = true
		end

		-- Also store the alternative encoded/raw form so matching does not fail.
		pcall(function()
			if encodeBase64 then
				local enc = encodeBase64(jobId)
				if enc and enc ~= "" and enc ~= jobId then
					local found = false
					for _, entry in ipairs(ignored) do
						if entry.jobId == enc then
							found = true
							break
						end
					end
					if not found then
						table.insert(ignored, { jobId = enc, timestamp = tick() })
						changed = true
					end
				end
			end
			if decodeBase64 and #jobId >= 32 and not string.find(jobId, "-") then
				local raw = decodeBase64(jobId)
				if raw and raw ~= "" and raw ~= jobId then
					local found = false
					for _, entry in ipairs(ignored) do
						if entry.jobId == raw then
							found = true
							break
						end
					end
					if not found then
						table.insert(ignored, { jobId = raw, timestamp = tick() })
						changed = true
					end
				end
			end
		end)

		if changed then
			saveIgnoredServers(ignored)
		end
	end

	function isServerIgnored(jobId)
		if not jobId then
			return false
		end
		jobId = tostring(jobId)
		if isRecentlyFailed(jobId) then
			return true
		end
		cleanupIgnoredServers()
		local ignored = loadIgnoredServers()
		for _, entry in ipairs(ignored) do
			if entry.jobId == jobId then
				return true
			end
		end
		-- Try encoded/raw matching.
		local alt = nil
		pcall(function()
			if encodeBase64 then
				alt = encodeBase64(jobId)
			end
		end)
		if alt then
			for _, entry in ipairs(ignored) do
				if entry.jobId == alt then
					return true
				end
			end
		end
		pcall(function()
			if decodeBase64 and #jobId >= 32 and not string.find(jobId, "-") then
				alt = decodeBase64(jobId)
			end
		end)
		if alt then
			for _, entry in ipairs(ignored) do
				if entry.jobId == alt then
					return true
				end
			end
		end
		return false
	end

	spawn(function()
		while true do
			task.wait(300)
			pcall(cleanupIgnoredServers)
		end
	end)

	function markServerAsRecentlyLeft(jobId)
		if not jobId or jobId == "" then
			return
		end
		_G.recentlyLeftServers[jobId] = tick()
	end

	function isServerRecentlyLeft(jobId)
		local ts = _G.recentlyLeftServers[jobId]
		if not ts then
			return false
		end
		if tick() - ts > _G.recentlyLeftTimeout then
			_G.recentlyLeftServers[jobId] = nil
			return false
		end
		return true
	end

	spawn(function()
		while true do
			task.wait(300)
			pcall(function()
				local now = tick()
				for jobId, ts in pairs(_G.recentlyLeftServers) do
					if now - ts > _G.recentlyLeftTimeout then
						_G.recentlyLeftServers[jobId] = nil
					end
				end
			end)
		end
	end)

	local function GetRoot(char)
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	local function GetHumanoid(char)
		return char and char:FindFirstChild("Humanoid")
	end

	local function tooltip(toolTip)
		for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.ToolTip == toolTip then
				local humanoid = GetHumanoid(LocalPlayer.Character)
				if humanoid then
					humanoid:EquipTool(tool)
					if toolTip == "Sword" then
						if _G._GenesisRememberSword then
							_G._GenesisRememberSword(tool)
						elseif tool.Name ~= "Basic Rod"
							and string.match(string.lower(tool.Name), "%srod$") == nil
						then
							-- Startup-only fallback before the persistent tracker is defined.
							_G.lastEquippedSword = tool
							_G.lastEquippedSwordName = tool.Name
						end
					end
				end
			end
		end
	end

	local function distance(pos)
		local root = GetRoot(LocalPlayer.Character)
		if root then
			return (pos - root.Position).Magnitude
		end
		return 999999
	end

	_G.allowCombat = false
	local lastHaoAttempt = 0
	local function fishingOwnsWeaponSlot()
		return _G.isFishing or _G.fishingToolCaptured or _G.fishingLoadoutBusy
	end

	-- Keep M1 responsive without returning to the old unbounded Stepped overlap.
	-- Combat branches renew a short attack lease through click(); this worker then
	-- continues M1 independently while slower skill keypresses are still yielding.
	_G._GenesisM1State = {
		-- About eleven swings per second keeps combat responsive without making
		-- every accepted M1 render/effect compete for the same mobile frame.
		interval = 0.09,
		lease = 0.9,
		maxInFlight = 2,
		requestedUntil = 0,
		lastDispatch = 0,
		inFlight = 0,
	}

	_G._GenesisInvokeM1 = function(tool)
		if not tool or not tool:IsA("Tool") then
			return false
		end
		local prefixByToolTip = {
			Combat = "FS_",
			Sword = "SW_",
			["Fruit Power"] = "DF_",
		}
		local prefix = prefixByToolTip[tool.ToolTip]
		if not prefix then
			return false
		end
		ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
			prefix .. tool.Name .. "_M1",
			{ MouseHit = _G.pos_skill }
		)
		return true
	end

	_G._GenesisPerformM1Pass = function()
		local character = LocalPlayer.Character
		if not character then
			return
		end

		if GetSetting("farmMethod") == "Sigma (Smooth)" then
			local selected = GetSetting("selectedTools") or {}
			local wantedToolTips = {}
			for key, value in pairs(selected) do
				local name = (type(key) == "string" and value == true) and key or value
				if name == "Mele" or name == "Combat" then
					wantedToolTips.Combat = true
				elseif name == "Sword" then
					wantedToolTips.Sword = true
				elseif name == "Fruit" or name == "Fruit Power" then
					wantedToolTips["Fruit Power"] = true
				end
			end
			for _, container in ipairs({ character, LocalPlayer.Backpack }) do
				for _, tool in pairs(container:GetChildren()) do
					if tool:IsA("Tool") and wantedToolTips[tool.ToolTip] then
						_G._GenesisInvokeM1(tool)
					end
				end
			end
			return
		end

		-- Smart mode targets the equipped tool with its real weapon prefix. The
		-- baseline sent all three prefixes sequentially; two were guaranteed no-ops
		-- and made every swing wait for three RemoteFunction round trips.
		for _, tool in pairs(character:GetChildren()) do
			if _G._GenesisInvokeM1(tool) then
				return
			end
		end
	end

	_G._GenesisDispatchM1IfReady = function()
		local state = _G._GenesisM1State
		if not state then
			return
		end
		if
			fishingOwnsWeaponSlot()
			or typeof(_G.pos_skill) ~= "CFrame"
			or os.clock() > state.requestedUntil
			or state.inFlight >= state.maxInFlight
			or os.clock() - state.lastDispatch < state.interval
		then
			return
		end
		state.lastDispatch = os.clock()
		state.inFlight = state.inFlight + 1
		task.spawn(function()
			pcall(_G._GenesisPerformM1Pass)
			if _G._GenesisM1State == state then
				state.inFlight = math.max(0, state.inFlight - 1)
			end
		end)
	end

	local function click()
		if fishingOwnsWeaponSlot() then
			return
		end
		local state = _G._GenesisM1State
		if state then
			state.requestedUntil = os.clock() + state.lease
			_G._GenesisDispatchM1IfReady()
		end
	end

	spawn(function()
		while task.wait(0.03) do
			local dispatch = _G._GenesisDispatchM1IfReady
			if type(dispatch) ~= "function" then
				break
			end
			dispatch()
		end
	end)

	_G._GenesisSkillLastSent = {}
	_G._GenesisSkillReady = function(key)
		local now = os.clock()
		if now - (_G._GenesisSkillLastSent[key] or 0) < 0.35 then
			return false
		end
		_G._GenesisSkillLastSent[key] = now
		return true
	end

	local function keyboard(key)
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(0.05)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end

	local function autoskill()
		if GetSetting("z") then
			keyboard("Z")
		end
		if GetSetting("x") then
			keyboard("X")
		end
		if GetSetting("c") then
			keyboard("C")
		end
		if GetSetting("v") then
			keyboard("V")
		end
		if GetSetting("f") then
			keyboard("F")
		end
		if GetSetting("b") then
			keyboard("B")
		end
		if GetSetting("e") then
			keyboard("E")
		end
	end

	local function buso()
		pcall(function()
			if GetSetting("buso") then
				local hakiValue = Workspace.PlayerCharacters[LocalPlayer.Name].Services.Haki.Value
				if hakiValue == 0 and not _G.busoActive then
					if tick() - _G.lastBusoAttempt > 2 then
						ReplicatedStorage.Chest.Remotes.Events.Armament:FireServer()
						_G.lastBusoAttempt = tick()
					end
				elseif hakiValue > 0 then
					_G.busoActive = true
				else
					_G.busoActive = false
				end
			end
		end)
	end

	local function ken()
		pcall(function()
			if GetSetting("ken") then
				local kenOpen = Workspace.PlayerCharacters[LocalPlayer.Name].Services.KenOpen.Value
				if not kenOpen and not _G.kenActive then
					if tick() - _G.lastKenAttempt > 2 then
						ReplicatedStorage.Chest.Remotes.Functions.KenEvent:InvokeServer()
						_G.lastKenAttempt = tick()
					end
				elseif kenOpen then
					_G.kenActive = true
				else
					_G.kenActive = false
				end
			end
		end)
	end

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if Workspace.PlayerCharacters[LocalPlayer.Name].Services.Haki.Value == 0 then
					_G.busoActive = false
				end
				if not Workspace.PlayerCharacters[LocalPlayer.Name].Services.KenOpen.Value then
					_G.kenActive = false
				end
			end)
		end
	end)

	local function hao()
		if not GetSetting("hao") then
			return
		end
		local now = tick()
		if now - lastHaoAttempt < 2 then
			return
		end
		lastHaoAttempt = now
		pcall(function()
			game:GetService("ReplicatedStorage")
				:WaitForChild("Chest")
				:WaitForChild("Remotes")
				:WaitForChild("Events")
				:WaitForChild("Conqueror")
				:FireServer()
		end)
	end

	local function tp(cframe, dailyReturnHop)
		if _G._GenesisDailyReturnRequested and not dailyReturnHop then
			return false
		end
		return pcall(function()
			LocalPlayer.Character.HumanoidRootPart.CFrame = cframe
		end)
	end

	local function getDownwardCFrame(targetCFrame)
		if fishingOwnsWeaponSlot() or _G._GenesisDailyReturnRequested then
			return targetCFrame
		end
		local height = GetSetting("distance") or 8
		local mobPos = targetCFrame.Position
		local above = mobPos + Vector3.new(0, height, 0)
		local finalCF = CFrame.new(above, mobPos)

		local root = GetRoot(LocalPlayer.Character)
		if root then
			root.CFrame = finalCF
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		return finalCF
	end

	-- A copy executed before the handoff hooks existed may still have left
	-- BodyMovers on the live root part.  Tear down those known movers before
	-- discarding their references.
	_G.farmFixTargetCF = nil
	_G.farmFixTargetPart = nil
	for _, staleMover in ipairs({ _G.farmFixBodyPos, _G.farmFixBodyGyro, _G.farmFixBodyVel }) do
		pcall(function()
			if staleMover then
				staleMover:Destroy()
			end
		end)
	end
	if _G.farmFixRoot and _G.farmFixRoot.Parent and _G.farmFixOwnershipReleased then
		pcall(function()
			_G.farmFixRoot:SetNetworkOwner(LocalPlayer)
		end)
	end
	_G.farmFixBodyPos = nil
	_G.farmFixBodyGyro = nil
	_G.farmFixBodyVel = nil
	_G.farmFixThread = nil
	_G.farmFixRoot = nil
	_G.farmFixOwnershipReleased = false

	local function applyFarmFix(targetCFrame, targetPart)
		if fishingOwnsWeaponSlot() or _G._GenesisDailyReturnRequested then
			return false
		end
		_G.farmFixTargetCF = targetCFrame
		_G.farmFixTargetPart = typeof(targetPart) == "Instance" and targetPart:IsA("BasePart") and targetPart or nil
		if _G.farmFixThread then
			return
		end

		local character = LocalPlayer.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end

		_G.farmFixRoot = root

		if not _G.farmFixBodyPos or not _G.farmFixBodyPos.Parent then
			if _G.farmFixBodyPos then
				_G.farmFixBodyPos:Destroy()
			end
			_G.farmFixBodyPos = Instance.new("BodyPosition")
			_G.farmFixBodyPos.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
			_G.farmFixBodyPos.D = 100000
			_G.farmFixBodyPos.P = 1000000
			_G.farmFixBodyPos.Parent = root
		end

		if not _G.farmFixBodyGyro or not _G.farmFixBodyGyro.Parent then
			if _G.farmFixBodyGyro then
				_G.farmFixBodyGyro:Destroy()
			end
			_G.farmFixBodyGyro = Instance.new("BodyGyro")
			_G.farmFixBodyGyro.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
			_G.farmFixBodyGyro.D = 50000
			_G.farmFixBodyGyro.P = 500000
			_G.farmFixBodyGyro.Parent = root
		end

		if not _G.farmFixBodyVel or not _G.farmFixBodyVel.Parent then
			if _G.farmFixBodyVel then
				_G.farmFixBodyVel:Destroy()
			end
			_G.farmFixBodyVel = Instance.new("BodyVelocity")
			_G.farmFixBodyVel.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
			_G.farmFixBodyVel.Velocity = Vector3.new(0, 0, 0)
			_G.farmFixBodyVel.Parent = root
		end

		if not _G.farmFixOwnershipReleased then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
			_G.farmFixOwnershipReleased = true
		end

		_G.farmFixThread = task.spawn(function()
			while _G.farmFixTargetCF and not fishingOwnsWeaponSlot() and not _G._GenesisDailyReturnRequested do
				if root and root.Parent then
					-- Combat actions are serialized to prevent overlapping M1/skill work,
					-- but movement must not wait for that yielding dispatcher. Follow the
					-- live hitbox here so jumping/moving targets are refreshed every
					-- scheduler frame instead of only after a combat pass completes.
					local liveTargetPart = _G.farmFixTargetPart
					if liveTargetPart and liveTargetPart.Parent and liveTargetPart:IsDescendantOf(Workspace) then
						local height = GetSetting("distance") or 8
						local mobPos = liveTargetPart.Position
						_G.farmFixTargetCF = CFrame.new(mobPos + Vector3.new(0, height, 0), mobPos)
						_G.pos_skill = liveTargetPart.CFrame
					end

					if _G.farmFixBodyPos then
						_G.farmFixBodyPos.Position = _G.farmFixTargetCF.Position
					end
					if _G.farmFixBodyGyro then
						_G.farmFixBodyGyro.CFrame = _G.farmFixTargetCF
					end
					if _G.farmFixBodyVel then
						_G.farmFixBodyVel.Velocity = Vector3.new(0, 0, 0)
					end
					root.CFrame = _G.farmFixTargetCF
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				task.wait(0.005)
			end
		end)
		return true
	end

	local function updateFarmFix(targetCFrame, targetPart)
		if fishingOwnsWeaponSlot() or _G._GenesisDailyReturnRequested then
			return false
		end
		_G.farmFixTargetCF = targetCFrame
		_G.farmFixTargetPart = typeof(targetPart) == "Instance" and targetPart:IsA("BasePart") and targetPart or nil
		return true
	end

	removeFarmFix = function()
		_G.farmFixTargetCF = nil
		_G.farmFixTargetPart = nil
		if _G.farmFixThread then
			_G.farmFixThread = nil
		end

		if _G.farmFixBodyPos then
			pcall(function()
				_G.farmFixBodyPos:Destroy()
			end)
		end
		if _G.farmFixBodyGyro then
			pcall(function()
				_G.farmFixBodyGyro:Destroy()
			end)
		end
		if _G.farmFixBodyVel then
			pcall(function()
				_G.farmFixBodyVel:Destroy()
			end)
		end
		_G.farmFixBodyPos = nil
		_G.farmFixBodyGyro = nil
		_G.farmFixBodyVel = nil

		if _G.farmFixRoot and _G.farmFixRoot.Parent and _G.farmFixOwnershipReleased then
			pcall(function()
				_G.farmFixRoot:SetNetworkOwner(LocalPlayer)
			end)
			_G.farmFixOwnershipReleased = false
		end
		_G.farmFixRoot = nil
	end
	_G._removeFarmFix = removeFarmFix

	_G.forceStopCombatLocks = function()
		pcall(removeFarmFix)
		pcall(function()
			if stopSeaEventBypass then
				stopSeaEventBypass()
			end
		end)
	end

	-- Saved settings are preferences, not proof that their target exists in this
	-- sea. This is the single eligibility boundary used by priority resolution and
	-- by workers that can otherwise move independently of the resolver.
	_G._GenesisSettingPlaceIds = {
		autoFarmKaido = 6381829480,
		autoDarkBeard = 6381829480,
		autoCrimsonDemon = 6381829480,
		autoIceKing = 6381829480,
		autoSKHD = 6381829480,
		autoGhostShip = 6381829480,
		autoRaidBoss_ExpertSwordman = 4520749081,
		autoRaidBoss_MsMother = 6381829480,
		autoRaidBoss_KingSamurai = 6381829480,
		autoHuntPtero = 15759515082,
		autoRaidBoss_BushidoApe = 15759515082,
		autoRaidBoss_LordOfSaber = 15759515082,
		autoKillKraken = 15759515082,
		autoKillDrakenfyr = 15759515082,
		autoKillAbyssalTyrant = 15759515082,
		autoKillDeepseaCrusher = 15759515082,
		autoKillGalleons = 15759515082,
		autoCollectPearl = 15759515082,
		autoDailyQuest = 15759515082,
		autoSecondSeaDailyQuest = 6381829480,
	}

	getCurrentSeaSelectedBoss = function()
		if not GetSetting("autoFarmBoss") or type(getBossNameFromDropdown) ~= "function"
			or type(getBossCFrame) ~= "function" then
			return nil, nil
		end
		local selectedBoss = GetSetting("selectedBoss")
		if type(selectedBoss) ~= "string" or selectedBoss == "" then
			return nil, nil
		end
		local bossName = getBossNameFromDropdown(selectedBoss)
		local bossCFrame = bossName and getBossCFrame(bossName) or nil
		if not bossName or typeof(bossCFrame) ~= "CFrame" then
			return nil, nil
		end
		return bossName, bossCFrame
	end

	getCurrentSeaSelectedMaterial = function()
		if not GetSetting("farmmaterial") or type(getMaterialsForCurrentSea) ~= "function" then
			return nil
		end
		if game.PlaceId ~= 4520749081 and game.PlaceId ~= 6381829480 and game.PlaceId ~= 15759515082 then
			return nil
		end
		local selectedMaterial = GetSetting("material")
		for _, materialName in ipairs(getMaterialsForCurrentSea()) do
			if selectedMaterial == materialName then
				return selectedMaterial
			end
		end
		return nil
	end

	isFeatureEnabledInCurrentSea = function(settingKey)
		if not GetSetting(settingKey) then
			return false
		end
		local requiredPlaceId = _G._GenesisSettingPlaceIds[settingKey]
		if requiredPlaceId and game.PlaceId ~= requiredPlaceId then
			return false
		end
		if settingKey == "autoSecondSea" then
			local playerStats = LocalPlayer:FindFirstChild("PlayerStats")
			local levelValue = playerStats and playerStats:FindFirstChild("lvl")
			return game.PlaceId == 4520749081 and levelValue ~= nil and levelValue.Value >= 2250
		end
		if settingKey == "autoThirdSea" then
			return game.PlaceId == 4520749081 or game.PlaceId == 6381829480
		end
		if settingKey == "autoFarmBoss" then
			return getCurrentSeaSelectedBoss() ~= nil
		end
		if settingKey == "farmmaterial" then
			return getCurrentSeaSelectedMaterial() ~= nil
		end
		return true
	end
	_G._GenesisIsFeatureEnabledInCurrentSea = isFeatureEnabledInCurrentSea
	_G._GenesisGetCurrentSeaSelectedBoss = getCurrentSeaSelectedBoss
	_G._GenesisGetCurrentSeaSelectedMaterial = getCurrentSeaSelectedMaterial

	_G.isAnyCombatActive = function()
		if _G.isLootingChests or _G.storingFruit or _G.seaEventActive then
			return true
		end
		if _G.isProgressingBusoV2 or _G.isProgressingObservationV2 then
			return true
		end
		if _G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation() then
			return true
		end
		-- Only continuous current-sea work belongs here. Live sea events, raid
		-- bosses, conquest, and daily travel are resolved from observed state above
		-- this fallback; their saved toggles alone must never block other work.
		local keys = {
			"auto_farm",
			"farmmaterial",
			"allboss",
			"easybounty",
			"autoKillMobs",
			"autoFarmBoss",
			"autoFarmKaido",
			"autoDarkBeard",
			"autoCrimsonDemon",
			"autoIceKing",
			"autoSecondSea",
			"autoThirdSea",
		}
		for _, k in ipairs(keys) do
			if isFeatureEnabledInCurrentSea(k) then
				return true
			end
		end
		return false
	end

	local _chestLootBP = nil
	local _chestLootBG = nil
	local _chestLootThread = nil
	local _chestLootTargetCF = nil

	local function applyChestLootFix(targetCFrame)
		if _G._GenesisDailyReturnRequested then return end
		_chestLootTargetCF = targetCFrame
		if _chestLootThread then
			return
		end

		local character = LocalPlayer.Character
		if not character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChild("Humanoid")
		if not root or not humanoid then
			return
		end

		humanoid.PlatformStand = true

		if not _chestLootBP or not _chestLootBP.Parent then
			if _chestLootBP then
				_chestLootBP:Destroy()
			end
			_chestLootBP = Instance.new("BodyPosition")
			_chestLootBP.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
			_chestLootBP.D = 100000
			_chestLootBP.P = 1000000
			_chestLootBP.Parent = root
		end

		if not _chestLootBG or not _chestLootBG.Parent then
			if _chestLootBG then
				_chestLootBG:Destroy()
			end
			_chestLootBG = Instance.new("BodyGyro")
			_chestLootBG.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
			_chestLootBG.D = 50000
			_chestLootBG.P = 500000
			_chestLootBG.Parent = root
		end

		_chestLootThread = task.spawn(function()
			while _chestLootTargetCF and not _G._GenesisDailyReturnRequested do
				if root and root.Parent then
					if _chestLootBP then
						_chestLootBP.Position = _chestLootTargetCF.Position
					end
					if _chestLootBG then
						_chestLootBG.CFrame = _chestLootTargetCF
					end
					root.CFrame = _chestLootTargetCF
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				task.wait(0.005)
			end
		end)
	end

	removeChestLootFix = function()
		_chestLootTargetCF = nil
		if _chestLootThread then
			_chestLootThread = nil
		end
		if _chestLootBP then
			_chestLootBP:Destroy()
			_chestLootBP = nil
		end
		if _chestLootBG then
			_chestLootBG:Destroy()
			_chestLootBG = nil
		end

		local character = LocalPlayer.Character
		if character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.PlatformStand = false
			end
		end
	end
	_G._removeChestLootFix = removeChestLootFix

	local function startLootTimer(eventType, duration)
		if not isFeatureEnabledInCurrentSea("autoSKHD") then
			return
		end
		if _G.lootThreads[eventType] then
			_G.lootThreads[eventType] = nil
		end

		_G.lootState[eventType] = { active = true, startTime = tick(), duration = duration }
		local seaKingChestSound = nil
		local seaKingChestConnection = nil
		local seaKingChestOpenedAt = nil
		local function disconnectSeaKingChest()
			if seaKingChestConnection then
				seaKingChestConnection:Disconnect()
				local runtime = getGenesisRuntimeState()
				if runtime then
					runtime.connections[seaKingChestConnection] = nil
				end
				seaKingChestConnection = nil
			end
		end
		local function watchSeaKingChest()
			if eventType ~= "SeaKing" then
				return
			end
			-- startLootTimer is defined before the local island finder below.
			-- Resolve its published function at call time instead of a nil global.
			local islandFinder = _G.findSeaKingIsland
			local island = type(islandFinder) == "function" and islandFinder() or nil
			local spawner = island and island:FindFirstChild("ChestSpawner")
			local chest = spawner and spawner:FindFirstChildWhichIsA("Model")
			local root = chest and chest:FindFirstChild("RootPart")
			local sound = root and root:FindFirstChild("OpeningSound")
			if sound and sound ~= seaKingChestSound then
				disconnectSeaKingChest()
				seaKingChestSound = sound
				seaKingChestConnection = trackGenesisConnection(sound.Played:Connect(function()
					seaKingChestOpenedAt = tick()
				end))
				if sound.IsPlaying then
					seaKingChestOpenedAt = tick()
				end
			end
		end
		watchSeaKingChest()

		_G.lootThreads[eventType] = task.spawn(function()
			local start = tick()
			while tick() - start < duration do
				task.wait(eventType == "SeaKing" and 0.1 or 0.5)
				watchSeaKingChest()
				-- ChestOpen is the game's server-triggered opening effect. Allow a
				-- short reward-settlement window, then release the movement lock.
				if seaKingChestOpenedAt and tick() - seaKingChestOpenedAt >= 1.5 then
					break
				end
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					break
				end

				-- Immediate kill switch if autoSKHD was disabled.
				if not isFeatureEnabledInCurrentSea("autoSKHD") then
					break
				end

				-- Check whether it respawned (use the _G fallback to ensure the function is found).
				local respawned = false
				if eventType == "SeaKing" then
					local fn = _G.findSeaKingMob or findSeaKingMob
					if type(fn) == "function" then
						local ok, m = pcall(fn)
						if ok and m and m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0 then
							respawned = true
						end
					end
				elseif eventType == "Hydra" then
					local fn = _G.findHydraMob or findHydraMob
					if type(fn) == "function" then
						local ok, m = pcall(fn)
						if ok and m and m:FindFirstChild("Humanoid") and m.Humanoid.Health > 0 then
							respawned = true
						end
					end
				end

				if respawned then
					disconnectSeaKingChest()
					removeChestLootFix()
					_G.isLootingChests = false
					_G.lootState[eventType] = { active = false }
					_G.lootThreads[eventType] = nil
					return
				end

				-- Reapply the fix if it fell.
				if not _chestLootThread then
					local cp
					if eventType == "SeaKing" then
						local fn = _G.findSeaKingChestPosition or findSeaKingChestPosition
						if type(fn) == "function" then
							local ok, pos = pcall(fn)
							if ok then
								cp = pos
							end
						end
					else
						local fn = _G.findHydraChestPosition or findHydraChestPosition
						if type(fn) == "function" then
							local ok, pos = pcall(fn)
							if ok then
								cp = pos
							end
						end
					end
					if cp then
						applyChestLootFix(CFrame.new(cp))
					end
				end
			end

			-- Exited the loop (timeout or disabled).
			disconnectSeaKingChest()
			removeChestLootFix()
			_G.isLootingChests = false
			_G.lootState[eventType] = { active = false }
			_G.lootThreads[eventType] = nil

			if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
				return
			end
			if not isFeatureEnabledInCurrentSea("autoSKHD") then
				return
			end
			if eventType == "SeaKing" then
				_G.seaKingIslandEmpty = true
				if seaKingChestOpenedAt then
					_G.seaKingLootUnconfirmed = false
					_G.currentEventName = "Sea King (Chest Opened)"
				else
					_G.seaKingLootUnconfirmed = true
					_G.currentEventName = "Sea King (Chest unconfirmed)"
					return
				end
			end

			if GetSetting("autoSmartHop") then
				markServerAsIgnored(game.JobId)
				_G._lastSmartHopCheck = 0
			else
				if eventType == "SeaKing" then
					_G.seaKingIslandEmpty = true
				else
					_G.hydraIslandEmpty = true
				end
			end
		end)
	end

	local function getWhirlpoolCFrame()
		local effects = Workspace:FindFirstChild("Effects")
		if not effects then
			return nil
		end
		local whirlpoolModel = effects:FindFirstChild("SerpentWhirlpool")
		if not whirlpoolModel then
			return nil
		end

		local whirlpoolPart = whirlpoolModel:FindFirstChild("Whirlpool")
		if not whirlpoolPart or not whirlpoolPart:IsA("BasePart") then
			whirlpoolPart = whirlpoolModel:FindFirstChildWhichIsA("BasePart")
		end
		if not whirlpoolPart then
			return nil
		end

		local center = whirlpoolPart.Position
		local offset = Vector3.new(20, 2, 0)
		local playerPos = center + offset
		return CFrame.new(playerPos, Vector3.new(center.X, playerPos.Y, center.Z))
	end

	local function getDisplayRaceName(name)
		if string.find(name, "SeaKing") then
			return "Sea Beast"
		elseif string.find(name, "Human") then
			return "Human"
		elseif string.find(name, "Gale") then
			return "Gale"
		elseif string.find(name, "Angel") then
			return "Angel"
		elseif string.find(name, "Animal") then
			return "Mink"
		elseif string.find(name, "Fish") then
			return "Fishman"
		elseif string.find(name, "Demon") then
			return "Demon"
		end
		return name:gsub("%s*Island%s*$", "")
	end

	local currentFarmTarget = nil
	local lastFarmUpdate = 0
	local isFarmingMob = false

	local function isValidFarmMob(mob, expectedName)
		if not mob then
			return false
		end
		if not mob:IsDescendantOf(Workspace) then
			return false
		end
		local humanoid = mob:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false
		end
		if expectedName and not string.find(mob.Name, expectedName) then
			return false
		end
		return true
	end

	local function findFarmMob(expectedName, materialList)
		local root = GetRoot(LocalPlayer.Character)
		if not root then
			return nil
		end

		local closestMob = nil
		local closestDist = math.huge
		local myPos = root.Position

		for _, mobFolder in pairs(Workspace.Monster:GetChildren()) do
			if mobFolder.ClassName == "Folder" and (mobFolder.Name == "Boss" or mobFolder.Name == "Mon") then
				for _, mob in pairs(mobFolder:GetChildren()) do
					local hum = mob:FindFirstChild("Humanoid")
					local hrp = mob:FindFirstChild("HumanoidRootPart")
					if hum and hrp and hum.Health > 0 then
						local nameMatch = false
						if expectedName then
							nameMatch = string.find(mob.Name, expectedName)
						elseif materialList then
							for _, matLv in pairs(materialList) do
								if string.find(mob.Name, "Lv. " .. matLv .. "]") then
									nameMatch = true
									break
								end
							end
						end

						if nameMatch then
							local dist = (hrp.Position - myPos).Magnitude
							if dist < closestDist then
								closestDist = dist
								closestMob = mob
							end
						end
					end
				end
			end
		end

		return closestMob, closestDist
	end

	local function hasOpe()
		for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.Name:find("OpOp") then
				return tool
			end
		end
		for _, tool in pairs(LocalPlayer.Character:GetChildren()) do
			if tool:IsA("Tool") and tool.Name:find("OpOp") then
				return tool
			end
		end
		return nil
	end

	local function isInOpeRoom()
		local room = Workspace:FindFirstChild("OpeRoom" .. LocalPlayer.Name)
		if not room then
			return false
		end
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end

		local roomCF = room.CFrame
		local roomSize = room.Size
		local localPos = roomCF:PointToObjectSpace(root.Position)

		return math.abs(localPos.X) <= roomSize.X / 2
			and math.abs(localPos.Y) <= roomSize.Y / 2
			and math.abs(localPos.Z) <= roomSize.Z / 2
	end

	local function isTransformed()
		local playerModel = Workspace.PlayerCharacters:FindFirstChild(LocalPlayer.Name)
		if not playerModel then
			return false
		end
		local armorHealth = playerModel:GetAttribute("ArmorHealth")
		return armorHealth and armorHealth > 0
	end

	local function usetool()
		-- A stale farm pass must never evict the rod. The central arbitration loop
		-- explicitly stops fishing first when a live boss or higher-priority mode
		-- genuinely needs the weapon slot.
		if fishingOwnsWeaponSlot() then
			return false
		end
		if _G.storingFruit then
			return false
		end

		if GetSetting("opeMethod") then
			if hasOpe() and isInOpeRoom() then
				tooltip("Sword")
			else
				tooltip("Fruit Power")
			end
			return true
		end

		-- Sigma: does NOT equip anything. M1 and skills use remotes on all selected tools.
		if GetSetting("farmMethod") == "Sigma (Smooth)" then
			return true
		end

		local tools = GetSetting("selectedTools")
		if not tools or #tools == 0 then
			return false
		end

		local toolName = tools[_G.currentToolIndex]
		if toolName == "Mele" then
			tooltip("Combat")
		elseif toolName == "Sword" then
			-- Dungeon teardown can leave the game's replicated Primary slot at None,
			-- which also removes the selected sword Tool from Character/Backpack. The
			-- ordinary tooltip helper cannot recover from that state because it only
			-- equips an already-instantiated Tool. Reuse the validated inventory path
			-- below to restore the exact remembered sword; never fall back to fists,
			-- fruit, or an arbitrary sword while that bounded restore is pending.
			if type(_G._GenesisEnsureCombatSword) == "function" then
				_G._GenesisEnsureCombatSword("outside_combat")
			else
				tooltip("Sword")
			end
		elseif toolName == "Fruit" then
			tooltip("Fruit Power")
		end
		return true
	end

	autoskill = function()
		if fishingOwnsWeaponSlot() then
			return
		end
		-- Sigma (Smooth): skills via remotes on ALL selected tools (Backpack + Character). Does NOT equip.
		if GetSetting("farmMethod") == "Sigma (Smooth)" then
			local selected = GetSetting("selectedTools") or {}
			local want = {}
			-- selected can be an array {"Sword","Fruit"} or a map {Sword=true,...}.
			for k, v in pairs(selected) do
				local name = (type(k) == "string" and v == true) and k or v
				if name == "Mele" or name == "Combat" then
					want["Combat"] = true
				elseif name == "Sword" then
					want["Sword"] = true
				elseif name == "Fruit" or name == "Fruit Power" then
					want["Fruit Power"] = true
				end
			end

			local pos = _G.pos_skill
			local keys = {}
			if GetSetting("z") and _G._GenesisSkillReady("Z") then
				table.insert(keys, "Z")
			end
			if GetSetting("x") and _G._GenesisSkillReady("X") then
				table.insert(keys, "X")
			end
			if GetSetting("c") and _G._GenesisSkillReady("C") then
				table.insert(keys, "C")
			end
			if GetSetting("v") and _G._GenesisSkillReady("V") then
				if GetSetting("opeMethod") then
					if not isTransformed() then
						table.insert(keys, "V")
					end
				else
					table.insert(keys, "V")
				end
			end
			if GetSetting("f") and _G._GenesisSkillReady("F") then
				table.insert(keys, "F")
			end
			if GetSetting("b") and _G._GenesisSkillReady("B") then
				table.insert(keys, "B")
			end
			if GetSetting("e") and _G._GenesisSkillReady("E") then
				table.insert(keys, "E")
			end

			local function fireSkillsForTool(tool)
				if not tool or not tool:IsA("Tool") then
					return
				end
				local tip = tool.ToolTip
				if not tip or not want[tip] then
					return
				end
				local prefix = "SW_"
				if tip == "Combat" then
					prefix = "FS_"
				elseif tip == "Fruit Power" then
					prefix = "DF_"
				elseif tip == "Sword" then
					prefix = "SW_"
				else
					return
				end
				for _, key in ipairs(keys) do
					local skillName = prefix .. tool.Name .. "_" .. key
					pcall(function()
						ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
							skillName,
							{ MouseHit = pos, Type = "Down" }
						)
					end)
					pcall(function()
						ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
							skillName,
							{ MouseHit = pos, Type = "Up" }
						)
					end)
				end
			end

			local char = LocalPlayer.Character
			if char then
				for _, tool in pairs(char:GetChildren()) do
					fireSkillsForTool(tool)
				end
			end
			for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
				fireSkillsForTool(tool)
			end
			return
		end

		-- Default (Smart): keyboard.
		if GetSetting("z") and _G._GenesisSkillReady("Z") then
			keyboard("Z")
		end
		if GetSetting("x") and _G._GenesisSkillReady("X") then
			keyboard("X")
		end
		if GetSetting("c") and _G._GenesisSkillReady("C") then
			keyboard("C")
		end
		if GetSetting("v") and _G._GenesisSkillReady("V") then
			if GetSetting("opeMethod") then
				if not isTransformed() then
					keyboard("V")
				end
			else
				keyboard("V")
			end
		end
		if GetSetting("f") and _G._GenesisSkillReady("F") then
			keyboard("F")
		end
		if GetSetting("b") and _G._GenesisSkillReady("B") then
			keyboard("B")
		end
		if GetSetting("e") and _G._GenesisSkillReady("E") then
			keyboard("E")
		end
	end

	local function handleOpeMethod()
		if not GetSetting("opeMethod") then
			return
		end
		if fishingOwnsWeaponSlot() then
			return
		end
		if _G.isLootingChests or _G.collectingPearls then
			return
		end

		local farmActive = isFeatureEnabledInCurrentSea("auto_farm")
			or isFeatureEnabledInCurrentSea("farmmaterial")
			or isFeatureEnabledInCurrentSea("allboss")
			or isFeatureEnabledInCurrentSea("easybounty")
			or isFeatureEnabledInCurrentSea("autoKillMobs")
			or isFeatureEnabledInCurrentSea("autoFarmBoss")
			or isFeatureEnabledInCurrentSea("autoDarkBeard")
			or isFeatureEnabledInCurrentSea("autoFarmKaido")
			or isFeatureEnabledInCurrentSea("autoCrimsonDemon")
			or isFeatureEnabledInCurrentSea("autoIceKing")
			or _G.seaEventActive
			or isFeatureEnabledInCurrentSea("autoHuntPtero")
			or isFeatureEnabledInCurrentSea("autoRaidBoss_ExpertSwordman")
			or isFeatureEnabledInCurrentSea("autoRaidBoss_MsMother")
			or isFeatureEnabledInCurrentSea("autoRaidBoss_KingSamurai")
			or isFeatureEnabledInCurrentSea("autoRaidBoss_BushidoApe")
			or isFeatureEnabledInCurrentSea("autoRaidBoss_LordOfSaber")
			or (GetSetting("autoDailyQuestsMaster") and
				(isFeatureEnabledInCurrentSea("autoDailyQuest")
					or isFeatureEnabledInCurrentSea("autoSecondSeaDailyQuest")))
			or isFeatureEnabledInCurrentSea("autoSKHD")
			or isFeatureEnabledInCurrentSea("autoGhostShip")
			or isFeatureEnabledInCurrentSea("autoKillKraken")
			or isFeatureEnabledInCurrentSea("autoKillDrakenfyr")
			or isFeatureEnabledInCurrentSea("autoKillAbyssalTyrant")
			or isFeatureEnabledInCurrentSea("autoKillDeepseaCrusher")
			or isFeatureEnabledInCurrentSea("autoKillGalleons")
			or isFeatureEnabledInCurrentSea("autoHuntSerpent")
		if not farmActive then
			return
		end
		local targetPos = _G.pos_skill and _G.pos_skill.Position
		if not targetPos or distance(targetPos) > 50 then
			return
		end

		pcall(function()
			local opeTool = hasOpe()
			if opeTool then
				if not isInOpeRoom() then
					LocalPlayer.Character.Humanoid:EquipTool(opeTool)
					task.wait(0.1)
					keyboard("Z")
					_G.lastOpeCheck = tick()
				end
				return
			end

			if not isTransformed() then
				tooltip("Fruit Power")
				task.wait(0.1)
				keyboard("V")
			end
		end)
	end

	local _conquestBP = nil
	local _conquestBG = nil
	local _conquestTargetCF = nil

	local function applyConquestPosition(cf)
		local root = GetRoot(LocalPlayer.Character)
		if not root then
			return
		end
		-- Conquest owns character position while a flag is being captured. Release
		-- the normal farm controller before creating its own BodyMovers.
		if removeFarmFix then
			pcall(removeFarmFix)
		end
		_G.conquestActive = true

		if not _conquestBP or not _conquestBP.Parent then
			_conquestBP = Instance.new("BodyPosition")
			_conquestBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			_conquestBP.D = 1000
			_conquestBP.P = 10000
			_conquestBP.Parent = root
		end
		if not _conquestBG or not _conquestBG.Parent then
			_conquestBG = Instance.new("BodyGyro")
			_conquestBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
			_conquestBG.D = 500
			_conquestBG.P = 10000
			_conquestBG.Parent = root
		end

		_conquestBP.Position = cf.Position
		_conquestBG.CFrame = cf
	end

	removeConquestPosition = function()
		if _conquestBP then
			_conquestBP:Destroy()
			_conquestBP = nil
		end
		if _conquestBG then
			_conquestBG:Destroy()
			_conquestBG = nil
		end
		_conquestTargetCF = nil
		_G.conquestActive = false
	end
	_G._removeConquestPosition = removeConquestPosition

	local function isConquestBlocked()
		return _G._GenesisDailyReturnRequested
			or _G.seaEventActive
			or _G.raidBossTarget
			or _G.isLootingChests
			or _G.storingFruit
			or _G.collectingPearls
			or _G.isProgressingBusoV2
			or _G.isProgressingObservationV2
			-- An enabled dungeon that is currently preempted (for example by the
			-- near-event gate) does not own this movement controller.
			or (_G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation())
	end

	trackGenesisConnection(RunService.Heartbeat:Connect(function()
		pcall(function()
			if GetSetting("autoConquest") then
				local character = LocalPlayer.Character
				if character then
					for _, part in pairs(character:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CanCollide = false
						end
					end
				end
			end

			if not GetSetting("autoConquest") then
				removeConquestPosition()
				return
			end
			if not _conquestTargetCF then
				return
			end
			if isConquestBlocked() then
				removeConquestPosition()
				return
			end

			local root = GetRoot(LocalPlayer.Character)
			if root then
				if _conquestBP and _conquestBP.Parent then
					_conquestBP.Position = _conquestTargetCF.Position
				end
				if _conquestBG and _conquestBG.Parent then
					_conquestBG.CFrame = _conquestTargetCF
				end
			end
		end)
	end))

	local function applyHideNotify(enable)
		if enable then
			if _G.hideNotifyActive then
				return
			end
			_G.hideNotifyActive = true
			_G.savedPopupState = {}

			task.wait(0.5)

			local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
			if not playerGui then
				return
			end

			local popup = playerGui:FindFirstChild("Popup")
			if popup and popup:IsA("ScreenGui") then
				local frame = popup:FindFirstChild("Frame")
				if frame then
					_G.savedPopupState.frame = frame
					_G.savedPopupState.parent = frame.Parent
					_G.savedPopupState.visible = frame.Visible
					_G.savedPopupState.texts = {}

					for _, child in pairs(frame:GetDescendants()) do
						if child:IsA("TextLabel") or child:IsA("TextButton") then
							_G.savedPopupState.texts[child] = child.Visible
							child.Visible = false
						end
					end
					frame.Parent = nil
					frame.Visible = false
				end
			end
		else
			if not _G.hideNotifyActive then
				return
			end
			_G.hideNotifyActive = false

			if _G.savedPopupState and _G.savedPopupState.frame then
				local frame = _G.savedPopupState.frame
				if frame then
					for child, visible in pairs(_G.savedPopupState.texts) do
						if child and child.Parent then
							child.Visible = visible
						end
					end
					if _G.savedPopupState.parent then
						frame.Parent = _G.savedPopupState.parent
					end
					frame.Visible = _G.savedPopupState.visible
				end
			end
			_G.savedPopupState = nil
		end
	end

	local function applyBlackScreen(enable)
		if enable then
			if _G.blackScreenGui then
				return
			end

			local coreGui = game:GetService("CoreGui")
			if not coreGui then
				return
			end

			_G.blackScreenGui = Instance.new("ScreenGui")
			_G.blackScreenGui.Name = "BlackScreen"
			_G.blackScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			_G.blackScreenGui.IgnoreGuiInset = true
			_G.blackScreenGui.ResetOnSpawn = false
			_G.blackScreenGui.DisplayOrder = -1

			local frame = Instance.new("Frame")
			frame.Size = UDim2.new(1, 0, 1, 0)
			frame.BackgroundColor3 = Color3.new(0, 0, 0)
			frame.BackgroundTransparency = 0
			frame.BorderSizePixel = 0
			frame.Parent = _G.blackScreenGui

			_G.blackScreenGui.Parent = coreGui
		else
			if _G.blackScreenGui then
				_G.blackScreenGui:Destroy()
				_G.blackScreenGui = nil
			end
		end
	end

	local islandsBySea = {
		[4520749081] = {
			"Chef Ship",
			"Shark Island",
			"Stone Area",
			"Forgotten Prison",
			"Pirate Island",
			"Fish Island",
			"Bubble Island",
			"Sky Island",
			"Lobby Island",
			"Snow Island",
			"War Island",
			"Starter Island",
			"Soldier Island",
			"Desert Island",
			"Zombie Island",
			"Rainy Stone",
		},
		[6381829480] = {
			"Dead Tundra",
			"Skull Isle",
			"Japan Island",
			"Loaf Isle",
			"Lavahold Prison",
			"Fiore",
			"Shred Endangering",
			"Soldier Headquater",
			"Pirate Skull",
		},
		[15759515082] = {
			"Primeval Isle",
			"Crownfall Isle",
			"Luma Grove",
			"The Unearthly",
			"Drakenhold Fortress",
			"Land of Detention",
			"The Shallow",
			"Forgotten Coliseum",
		},
	}

	local islandsCFrame = {

		["Chef Ship"] = CFrame.new(-4317.142, 17.085, -2705.042),
		["Shark Island"] = CFrame.new(-863.003, 16.704, -1345.928),
		["Stone Area"] = CFrame.new(4084.352, 37.746, -3909.14),
		["Forgotten Prison"] = CFrame.new(-4495.282, 18.683, -5847.39),
		["Pirate Island"] = CFrame.new(-638.133, 114.926, -3488.605),
		["Fish Island"] = CFrame.new(-1715.118, 40.269, 6356.313),
		["Bubble Island"] = CFrame.new(1317.201, 17.725, 878.094),
		["Sky Island"] = CFrame.new(-4171.904, 369.041, 1230.738),
		["Lobby Island"] = CFrame.new(-1237.833, 12.045, 1802.046),
		["Snow Island"] = CFrame.new(-5272.273, 28.46, -1383.89),
		["War Island"] = CFrame.new(1890.936, 8.345, -1929.748),
		["Starter Island"] = CFrame.new(-2087.38, 49.244, -4199.714),
		["Soldier Island"] = CFrame.new(-2241.26, 70.066, -2721.601),
		["Desert Island"] = CFrame.new(-2661.033, 17.172, -764.019),
		["Zombie Island"] = CFrame.new(-2506.577, 15.373, 3660.358),
		["Rainy Stone"] = CFrame.new(1953.284, 50.105, -4941.459),

		["Dead Tundra"] = CFrame.new(1028.49, 14.154, 894.633),
		["Skull Isle"] = CFrame.new(-6131.595, 57.748, 6954.502),
		["Japan Island"] = CFrame.new(-3637.213, 57.335, 152.32),
		["Loaf Isle"] = CFrame.new(-791.734, 28.97, 7436.515),
		["Lavahold Prison"] = CFrame.new(-2381.666, 81.711, -1439.569),
		["Fiore"] = CFrame.new(6563.934, 419.163, -3110.14),
		["Shred Endangering"] = CFrame.new(-224.615, 87.463, -2610.34),
		["Soldier Headquater"] = CFrame.new(-9602.625, 38.063, 960.823),
		["Pirate Skull"] = CFrame.new(-9016.487, 21.349, -5233.085),

		["Primeval Isle"] = CFrame.new(-9468.578, 65.751, 12146.05),
		["Crownfall Isle"] = CFrame.new(6760.222, 128.499, -5983.756),
		["Luma Grove"] = CFrame.new(-636.348, 213.733, 3987.494),
		["The Unearthly"] = CFrame.new(2076.569, 143.894, 1116.152),
		["Drakenhold Fortress"] = CFrame.new(-535.632, 45.629, -7898.574),
		["Land of Detention"] = CFrame.new(10832.17, 159.608, 994.125),
		["The Shallow"] = CFrame.new(3791.051, 257.552, 8830.448),
		["Forgotten Coliseum"] = CFrame.new(-5479.824, 52.399, -847.27),
	}

	function getBossesForDropdown()
		local bosses = {}
		local bossData = {}

		if game.PlaceId == 4520749081 then
			bossData = {
				{ name = "Smoky", level = 20, quest = "Kill 1 Smoky", cframe = CFrame.new(-2065, 99, -4686) },
				{ name = "Tashi", level = 30, quest = "Kill 1 Tashi", cframe = CFrame.new(-2270, 109, -4548) },
				{ name = "The Clown", level = 75, quest = "Kill 1 The Clown", cframe = CFrame.new(-397, 114, -3436) },
				{ name = "Captain", level = 120, quest = "Kill 1 Captain", cframe = CFrame.new(-2122, 92, -2549) },
				{
					name = "The Barbaric",
					level = 145,
					quest = "Kill 1 The Barbaric",
					cframe = CFrame.new(-2375, 139, -2419),
				},
				{
					name = "Karate Fishman",
					level = 200,
					quest = "Kill 1 Karate Fishman",
					cframe = CFrame.new(-856, 52, -1422),
				},
				{ name = "Shark Man", level = 230, quest = "Kill 1 Shark Man", cframe = CFrame.new(-666, 56, -1493) },
				{ name = "Dark Leg", level = 300, quest = "Kill 1 Dark Leg", cframe = CFrame.new(-4217, 162, -2899) },
				{ name = "King Snow", level = 450, quest = "Kill 1 King Snow", cframe = CFrame.new(-5519, 40, -1557) },
				{
					name = "Little Dear",
					level = 500,
					quest = "Kill 1 Little Dear",
					cframe = CFrame.new(-5467, 55, -1104),
				},
				{ name = "Bomb Man", level = 625, quest = "Kill 1 Bomb Man", cframe = CFrame.new(-2956, 92, -602) },
				{
					name = "King of Sand",
					level = 725,
					quest = "Kill 1 King of Sand",
					cframe = CFrame.new(-3021, 92, -545),
				},
				{ name = "Ball Man", level = 850, quest = "Kill 1 Ball Man", cframe = CFrame.new(-4598, 504, 1443) },
				{
					name = "Rumble Man",
					level = 950,
					quest = "Kill 1 Rumble Man",
					cframe = CFrame.new(-4598, 504, 1443),
				},
				{ name = "Leader", level = 1100, quest = "Kill 1 Leader", cframe = CFrame.new(1813, 52, 768) },
				{ name = "Pasta", level = 1150, quest = "Kill 1 Pasta", cframe = CFrame.new(1813, 52, 768) },
				{ name = "Wolf", level = 1250, quest = "Kill 1 Wolf", cframe = CFrame.new(-1301, 69, 2153) },
				{ name = "Giraffe", level = 1300, quest = "Kill 1 Giraffe", cframe = CFrame.new(-1077, 20, 1966) },
				{ name = "Leo", level = 1450, quest = "Kill 1 Leo", cframe = CFrame.new(-1083, 22, 2531) },
				{
					name = "Shadow Master",
					level = 1650,
					quest = "Kill 1 Shadow Master",
					cframe = CFrame.new(-2849, 20, 4319),
				},
				{
					name = "True Karate Fishman",
					level = 1850,
					quest = "Kill 1 True Karate Fishman",
					cframe = CFrame.new(2471, 103, -1938),
				},
				{
					name = "Quake Woman",
					level = 1925,
					quest = "Kill 1 Quake Woman",
					cframe = CFrame.new(2285, 49, -1908),
				},
				{
					name = "Combat Fishman",
					level = 2050,
					quest = "Kill 1 Combat Fishman",
					cframe = CFrame.new(-1956, 55, 6236),
				},
				{
					name = "Sword Fishman",
					level = 2100,
					quest = "Kill 1 Sword Fishman",
					cframe = CFrame.new(-1635, 96, 6688),
				},
				{
					name = "Seasoned Fishman",
					level = 2200,
					quest = "Kill 1 Seasoned Fishman",
					cframe = CFrame.new(-1801, 40, 6451),
				},
			}
		elseif game.PlaceId == 6381829480 then
			bossData = {
				{
					name = "Gazelle Man",
					level = 2350,
					quest = "Kill 1 Gazelle Man",
					cframe = CFrame.new(-4363, 57, 252),
				},
				{
					name = "Violet Samurai",
					level = 2500,
					quest = "Kill 1 Violet Samurai",
					cframe = CFrame.new(-4969, 105, -1007),
				},
				{ name = "Duke", level = 2550, quest = "Kill 1 Duke", cframe = CFrame.new(-5434, 100, -228) },
				{ name = "Magician", level = 2600, quest = "Kill 1 Magician", cframe = CFrame.new(-5048, 105, -154) },
				{
					name = "Kitsune Samurai",
					level = 2650,
					quest = "Kill 1 Kitsune Samurai",
					cframe = CFrame.new(-5452, 100, 16),
				},
				{ name = "Bear Man", level = 2750, quest = "Kill 1 Bear Man", cframe = CFrame.new(-4438, 53, 775) },
				{ name = "Bean", level = 2800, quest = "Kill 1 Bean", cframe = CFrame.new(-4018, 68, 904) },
				{ name = "Meji", level = 2850, quest = "Kill 1 Meji", cframe = CFrame.new(-5302, 83, 1163) },
				{ name = "Petra", level = 2900, quest = "Kill 1 Petra", cframe = CFrame.new(-5857, 80, 1308) },
				{ name = "Kappa", level = 2950, quest = "Kill 1 Kappa", cframe = CFrame.new(-4853, 109, 1926) },
				{ name = "Joey", level = 3000, quest = "Kill 1 Joey", cframe = CFrame.new(-5287, 57, 2066) },
				{
					name = "Elite Skeleton",
					level = 3100,
					quest = "Kill 1 Elite Skeleton",
					cframe = CFrame.new(-5926, 98, 7183),
				},
				{
					name = "Desert Thief",
					level = 3125,
					quest = "Kill 1 Desert Thief",
					cframe = CFrame.new(1575, 53, 1513),
				},
				{ name = "Anubis", level = 3150, quest = "Kill 1 Anubis", cframe = CFrame.new(1964, 48, 899) },
				{ name = "Pharaoh", level = 3175, quest = "Kill 1 Pharaoh", cframe = CFrame.new(2048, 49, 1632) },
				{
					name = "Sunken Vessel",
					level = 3225,
					quest = "Kill 1 Sunken Vessel",
					cframe = CFrame.new(-986, 83, 8169),
				},
				{
					name = "Biscuit Man",
					level = 3250,
					quest = "Kill 1 Biscuit Man",
					cframe = CFrame.new(-1375, 202, 8860),
				},
				{
					name = "Dough Master",
					level = 3275,
					quest = "Kill 1 Dough Master",
					cframe = CFrame.new(30370, 106, 93598),
				},
				{
					name = "Supreme Swordman",
					level = 3425,
					quest = "Kill 1 Supreme Swordman",
					cframe = CFrame.new(-9647, 114, -4483),
				},
				{ name = "Sally", level = 3450, quest = "Kill 1 Sally", cframe = CFrame.new(-9584, 135, -5374) },
				{ name = "Pondere", level = 3525, quest = "Kill 1 Pondere", cframe = CFrame.new(-10142, 100, 1298) },
				{ name = "Hefty", level = 3550, quest = "Kill 1 Hefty", cframe = CFrame.new(-10489, 84, 969) },
				{ name = "Lomeo", level = 3675, quest = "Kill 1 Lomeo", cframe = CFrame.new(6487, 72, -2135) },
				{
					name = "Prince Aria",
					level = 3700,
					quest = "Kill 1 Prince Aria",
					cframe = CFrame.new(6785, 150, -3794),
				},
				{ name = "Devastate", level = 3725, quest = "Kill 1 Devastate", cframe = CFrame.new(7632, 122, -2644) },
				{ name = "Floffy", level = 3775, quest = "Kill 1 Floffy", cframe = CFrame.new(7865, 462, -2529) },
				{ name = "Ryu", level = 3975, quest = "Kill 1 Ryu", cframe = CFrame.new(9927, 86, -4856) },
			}
		elseif game.PlaceId == 15759515082 then
			bossData = {
				{ name = "Fugitive", level = 4050, quest = "Kill Fugitive", cframe = CFrame.new(2888, 35, 993) },
				{
					name = "The Deep One",
					level = 4200,
					quest = "Kill The deep one",
					cframe = CFrame.new(2833, 35, 136),
				},
				{
					name = "Cyborg Gorilla",
					level = 4375,
					quest = "Kill 1 Cyborg Gorilla",
					cframe = CFrame.new(5784, 45, 9463),
				},
				{
					name = "Ripcurrent Raider",
					level = 4400,
					quest = "Kill 1 Ripcurrent Raider",
					cframe = CFrame.new(-506, 26, -8673),
				},
				{
					name = "Tidal Warrior",
					level = 4450,
					quest = "Kill 1 Tidal Warrior",
					cframe = CFrame.new(-73, 96, -8404),
				},
				{
					name = "Ocean Gladiator",
					level = 4500,
					quest = "Kill 1 Ocean Gladiator",
					cframe = CFrame.new(-22, 44, -9066),
				},
				{
					name = "Electro Abyss Warrior",
					level = 4600,
					quest = "Kill 1 Electro Abyss Warrior",
					cframe = CFrame.new(-5230, 22, 964),
				},
				{
					name = "Inferno Diver",
					level = 4650,
					quest = "Kill 1 Inferno Diver",
					cframe = CFrame.new(-6044, 54, 467),
				},
				{
					name = "Tempest Tidebreaker",
					level = 4700,
					quest = "Kill 1 Tempest Tidebreaker",
					cframe = CFrame.new(-7296, 42, 469),
				},
				{
					name = "Abyssal Swordsman",
					level = 4750,
					quest = "Kill 1 Abyssal Swordsman",
					cframe = CFrame.new(-8255, 186, 455),
				},
				{
					name = "Prisoner of Gravity",
					level = 4875,
					quest = "Kill 1 Prisoner of Gravity",
					cframe = CFrame.new(12436, 79, 1052),
				},
				{
					name = "Nightbound Explorer",
					level = 5150,
					quest = "Kill 1 Nightbound Explorer",
					cframe = CFrame.new(-8636, 243, 11346),
				},
				{
					name = "Ancient Wayfarer",
					level = 5250,
					quest = "Kill 1 Ancient Wayfarer",
					cframe = CFrame.new(-9065, 80, 11675),
				},
				{
					name = "Allosaurus",
					level = 5350,
					quest = "Kill 1 Allosaurus",
					cframe = CFrame.new(-10678, 187, 12067),
				},
				{
					name = "Spinosaurus",
					level = 5400,
					quest = "Kill 1 Spinosaurus",
					cframe = CFrame.new(-10717, 177, 10257),
				},
			}
		end

		for _, boss in ipairs(bossData) do
			table.insert(bosses, string.format("Lv.%d - %s", boss.level, boss.name))
		end

		return bosses, bossData
	end

	function getBossNameFromDropdown(dropdownString)
		if not dropdownString then
			return nil
		end
		local bossName = dropdownString:gsub("^Lv%.%d+%s*%-%s*", "")
		return bossName
	end

	function getBossQuest(bossName)
		if not bossName then
			return nil
		end
		local _, bossData = getBossesForDropdown()
		for _, boss in ipairs(bossData) do
			if boss.name == bossName then
				return boss.quest
			end
		end
		return "Kill 1 " .. bossName
	end

	function getBossCFrame(bossName)
		if not bossName then
			return nil
		end
		local _, bossData = getBossesForDropdown()
		for _, boss in ipairs(bossData) do
			if boss.name == bossName then
				return boss.cframe
			end
		end
		return nil
	end

	local raidPriority = {
		[4520749081] = { "Expert Swordman" },
		[6381829480] = { "Ms. Mother", "King Samurai" },
		[15759515082] = { "Pteranodon", "Lord of Saber", "Bushido Ape" },
	}

	local lastRaidCheck = 0
	local cachedTarget = nil
	local cachedBossName = nil

	local raidBossSettings = {
		[4520749081] = {
			{ name = "Expert Swordman", key = "autoRaidBoss_ExpertSwordman" },
		},
		[6381829480] = {
			{ name = "Ms. Mother", key = "autoRaidBoss_MsMother" },
			{ name = "King Samurai", key = "autoRaidBoss_KingSamurai" },
		},
		[15759515082] = {
			{ name = "Pteranodon", key = "autoHuntPtero" },
			{ name = "Lord of Saber", key = "autoRaidBoss_LordOfSaber" },
			{ name = "Bushido Ape", key = "autoRaidBoss_BushidoApe" },
		},
	}

	local function isRaidBossSelected(bossName)
		local bosses = raidBossSettings[game.PlaceId] or {}
		for _, boss in ipairs(bosses) do
			if boss.name == bossName and GetSetting(boss.key) then
				return true
			end
		end
		return false
	end

	_G.anyRaidBossSelected = function()
		local bosses = raidBossSettings[game.PlaceId] or {}
		for _, boss in ipairs(bosses) do
			if GetSetting(boss.key) then
				return true
			end
		end
		return false
	end

	local function getRaidBossTargetFast()
		if not _G.anyRaidBossSelected() then
			return nil, nil
		end
		-- The central resolver calls this only after the major-sea-event phase.
		-- A stale lower-priority event flag must not hide a newly spawned raid boss.
		if _G.storingFruit then
			return nil, nil
		end

		local priority = raidPriority[game.PlaceId]
		if not priority then
			return nil, nil
		end

		local bossFolder = Workspace.Monster:FindFirstChild("Boss")
		if bossFolder then
			for _, bossName in ipairs(priority) do
				if isRaidBossSelected(bossName) then
					for _, child in pairs(bossFolder:GetChildren()) do
						if
							string.find(child.Name, bossName)
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
						then
							return child, bossName
						end
					end
				end
			end
		end

		local monFolder = Workspace.Monster:FindFirstChild("Mon")
		if monFolder then
			for _, bossName in ipairs(priority) do
				if isRaidBossSelected(bossName) then
					for _, child in pairs(monFolder:GetChildren()) do
						if
							string.find(child.Name, bossName)
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
						then
							return child, bossName
						end
					end
				end
			end
		end

		for _, bossName in ipairs(priority) do
			if isRaidBossSelected(bossName) then
				for _, child in pairs(Workspace.SeaMonster:GetChildren()) do
					if
						string.find(child.Name, bossName)
						and child:FindFirstChild("Humanoid")
						and child.Humanoid.Health > 0
					then
						return child, bossName
					end
				end
			end
		end

		return nil, nil
	end

	local function updateRaidCache()
		local now = tick()
		if now - lastRaidCheck < 0.01 then
			return
		end
		lastRaidCheck = now
		cachedTarget, cachedBossName = getRaidBossTargetFast()
		_G.raidBossTarget = cachedTarget
		_G.raidBossTargetName = cachedBossName
	end

	local raidStatusLabel = nil

	local function updateRaidStatusLabel()
		if not raidStatusLabel then
			return
		end
		local priority = raidPriority[game.PlaceId] or {}
		local spawned = {}

		for _, bossName in ipairs(priority) do
			local found = false
			if Workspace.Monster:FindFirstChild("Boss") then
				for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
					if
						string.find(child.Name, bossName)
						and child:FindFirstChild("Humanoid")
						and child.Humanoid.Health > 0
					then
						found = true
						break
					end
				end
			end
			if found then
				table.insert(spawned, bossName)
			end
		end

		if #spawned > 0 then
			raidStatusLabel.SetText("Spawned: " .. table.concat(spawned, ", "))
		else
			raidStatusLabel.SetText("Spawned: None")
		end
	end

	local passiveOptions = {

		"(Common) Luxuriant",
		"(Common) Wisdom",
		"(Common) Chance",
		"(Common) Piercing",
		"(Common) Destruction",
		"(Common) Ruin",
		"(Common) Skill Haste",
		"(Common) Sword Sense",

		"(Paradox) Paradox",

		"(Iconic) Last Breath",
		"(Iconic) Stylish Heal",
		"(Iconic) Last Stand",
		"(Iconic) Critical Strikes",
		"(Iconic) Various",
		"(Iconic) Acropurged",
		"(Iconic) Sprinter",
		"(Iconic) Dazzle",
		"(Iconic) Healing Havoc",
		"(Iconic) Debility",
		"(Iconic) Tempest",
		"(Iconic) Blasting",
		"(Iconic) Hyper Armor",
		"(Iconic) Swift",
		"(Iconic) Draconic Aura",
		"(Iconic) Night Core",
		"(Iconic) Pyro Core",
		"(Iconic) Bolt Core",
		"(Iconic) Fearless",
		"(Iconic) Pitiless",

		"(Celestial) Nocturne",
		"(Celestial) Reflect Strike",
		"(Celestial) Ronin",
		"(Celestial) Eternal",
		"(Celestial) Brawler",
		"(Celestial) Sentinel",

		"(Curse) Sinister Hex",
		"(Curse) Nightmare",
		"(Curse) Difficult Healing",
		"(Curse) Sorrowspell",
	}

	local function getPassiveName(option)
		return option:match("%) (.+)$")
	end

	local function getPlayerPassives()
		local passives = {}
		pcall(function()
			local passivesValue = LocalPlayer.PlayerStats.Passives.Value
			local data = HttpService:JSONDecode(passivesValue)
			if data and data.Character then
				for _, passive in ipairs(data.Character) do
					if passive.PassiveName then
						passives[passive.PassiveName] = true
					end
				end
			end
		end)
		return passives
	end

	_G.SEA1_ID = 4520749081
	_G.SEA2_ID = 6381829480
	_G.SEA3_ID = 15759515082

	-- Heart of Sea materials (order: farmable items first, Blood last).
	_G.THIRD_SEA_MATERIALS = {
		{
			name = "Fresh Fish",
			need = 50,
			sea = _G.SEA1_ID,
			source = "mob",
			patterns = { "Fighter Fishman", "Karate Fishman" },
			spawn = CFrame.new(-1422, 52, -856),
		},
		{
			name = "Undead's Ooze",
			need = 10,
			sea = _G.SEA1_ID,
			source = "mob",
			patterns = { "Elite Zombie", "Zombie" },
			spawn = CFrame.new(4188, 16, -2789),
		},
		{ name = "Log", need = 50, sea = _G.SEA1_ID, source = "tree" },
		{
			name = "Pile of Bones",
			need = 10,
			sea = _G.SEA2_ID,
			source = "mob",
			patterns = { "Skull Pirate" },
			spawn = CFrame.new(-5685, 48, -1260),
		},
		{
			name = "Angellic's Feather",
			need = 10,
			sea = _G.SEA1_ID,
			source = "mob",
			patterns = { "Sky Soldier" },
			spawn = CFrame.new(1151, 222, -4589),
		},
		-- Blood last: main-script users farm it themselves (without premium Smart Hop).
		{ name = "Sea King's Blood", need = 1, sea = _G.SEA2_ID, source = "seaking" },
	}

	_G.MATERIAL_ALIASES = {
		["Angellic's Feather"] = { "Angellic's Feather", "Angelic's Feather" },
		["Heart of Sea"] = { "Heart of Sea", "Heart Of Sea" },
		["Sea King's Blood"] = { "Sea King's Blood", "Sea King Blood" },
	}

	_G.getMaterialCount = function(matName)
		local ok, count = pcall(function()
			local matValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
			if not matValue then
				return 0
			end
			local data = HttpService:JSONDecode(tostring(matValue.Value))
			if type(data) ~= "table" then
				return 0
			end
			local names = _G.MATERIAL_ALIASES[matName] or { matName }
			local total = 0
			for _, n in ipairs(names) do
				total = total + (tonumber(data[n]) or 0)
			end
			if total == 0 then
				total = tonumber(data[matName]) or 0
			end
			return total
		end)
		return ok and count or 0
	end

	_G.hasThirdSea = function()
		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		local miscValue = stats and stats:FindFirstChild("Misc")
		if not miscValue then
			return false
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(miscValue.Value)
		end)
		if ok and data then
			return data["ThirdSea"] == true
		end
		return false
	end

	_G.hasHeartOfSea = function()
		return _G.getMaterialCount("Heart of Sea") >= 1
	end

	_G.hasCraftMaterials = function()
		for _, m in ipairs(_G.THIRD_SEA_MATERIALS) do
			if _G.getMaterialCount(m.name) < m.need then
				return false
			end
		end
		return true
	end

	_G.getMissingThirdSeaMaterials = function()
		local missing = {}
		for _, m in ipairs(_G.THIRD_SEA_MATERIALS) do
			local have = _G.getMaterialCount(m.name)
			if have < m.need then
				table.insert(missing, {
					name = m.name,
					need = m.need,
					have = have,
					sea = m.sea,
					source = m.source,
					patterns = m.patterns,
					spawn = m.spawn,
				})
			end
		end
		return missing
	end

	_G.craftHeartOfSea = function()
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Functions.CraftMaterial:InvokeServer("Heart of Sea", "CraftingUI2")
		end)
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Functions.CraftMaterial:InvokeServer("Heart of Sea", "CraftingUI")
		end)
	end

	_G.teleportToSea = function(seaName)
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("TeleportSea", { SeaName = seaName })
		end)
	end

	-- Daily-quest travel state is account-specific. Do not mix timestamps or
	-- unlock proof when two accounts use the same executor settings folder.
	local dailyCoordinator
	do
	local dailySea = {
		[1] = { label = "First Sea", teleport = "FirstSea", place = _G.SEA1_ID },
		[2] = { label = "Second Sea", teleport = "SecondSea", place = _G.SEA2_ID },
		[3] = { label = "Third Sea", teleport = "ThirdSea", place = _G.SEA3_ID },
	}
	local dailyJournalPath = "GenesisX/Saves/daily_quests_" .. tostring(LocalPlayer.UserId) .. ".json"
	local dailyJournal = { version = 1, highestUnlocked = 1, quests = {} }
	if readfile and isfile then
		pcall(function()
			if isfile(dailyJournalPath) then
				local loaded = HttpService:JSONDecode(readfile(dailyJournalPath))
				if type(loaded) == "table" and loaded.version == 1 then
					dailyJournal = loaded
				end
			end
		end)
	end
	dailyJournal.quests = type(dailyJournal.quests) == "table" and dailyJournal.quests or {}
	dailyCoordinator = { journal = dailyJournal, sea = dailySea }
	_G.GenesisDaily = dailyCoordinator

	function dailyCoordinator.save()
		if not (writefile and isfolder and makefolder) then
			return false
		end
		local ok = pcall(function()
			if not isfolder("GenesisX") then makefolder("GenesisX") end
			if not isfolder("GenesisX/Saves") then makefolder("GenesisX/Saves") end
			writefile(dailyJournalPath, HttpService:JSONEncode(dailyJournal))
		end)
		return ok
	end

	function dailyCoordinator.currentRank()
		for rank, info in pairs(dailySea) do
			if game.PlaceId == info.place then return rank end
		end
		return nil
	end

	function dailyCoordinator.unlockedRank()
		local confirmed = dailyCoordinator.currentRank() or 1
		if _G.hasThirdSea() then confirmed = 3 end
		local remembered = tonumber(dailyJournal.highestUnlocked) or 1
		return math.clamp(math.max(confirmed, remembered), 1, 3), confirmed
	end

	function dailyCoordinator.refreshAccess()
		if not LocalPlayer:FindFirstChild("PlayerStats") then
			-- Preview from the current sea and saved proof without persisting an
			-- incomplete access check before player data has replicated.
			local confirmed = dailyCoordinator.currentRank() or 1
			local remembered = tonumber(dailyJournal.highestUnlocked) or 1
			return math.clamp(math.max(confirmed, remembered), 1, 3)
		end
		local unlocked, confirmed = dailyCoordinator.unlockedRank()
		local seen = tonumber(dailyJournal.highestUnlocked) or 1
		local changed = false
		if confirmed > seen then
			dailyJournal.highestUnlocked = confirmed
			dailyJournal.mainSea = confirmed -- promote only on a newly confirmed unlock
			changed = true
		end
		if not dailySea[tonumber(dailyJournal.mainSea)]
			or tonumber(dailyJournal.mainSea) > unlocked then
			dailyJournal.mainSea = unlocked
			changed = true
		end
		if changed then dailyCoordinator.save() end
		return unlocked
	end

	function dailyCoordinator.mainRank()
		local unlocked = dailyCoordinator.refreshAccess()
		local main = tonumber(dailyJournal.mainSea)
		return (main and dailySea[main] and main <= unlocked) and main or unlocked
	end

	function dailyCoordinator.setMainRank(rank)
		rank = tonumber(rank)
		if not rank or not dailySea[rank] or rank > dailyCoordinator.refreshAccess() then
			return false
		end
		if dailyJournal.mainSea ~= rank then
			dailyJournal.mainSea = rank
			dailyJournal.route = nil
			_G._GenesisDailyQuestTravelPending = false
			_G._GenesisDailyReturnRequested = false
			dailyCoordinator.save()
		end
		return true
	end

	function dailyCoordinator.record(rank, name)
		local key = tostring(rank)
		dailyJournal.quests[key] = type(dailyJournal.quests[key]) == "table" and dailyJournal.quests[key] or {}
		local records = dailyJournal.quests[key]
		records[name] = type(records[name]) == "table" and records[name] or {}
		return records[name]
	end

	function dailyCoordinator.observeCompletion(rank, name, stamp)
		if type(stamp) ~= "number" or stamp <= 0 then return end
		local record = dailyCoordinator.record(rank, name)
		if record.completedAt ~= stamp then
			record.completedAt = stamp
			record.retryAt = nil
			dailyCoordinator.save()
		end
	end

	function dailyCoordinator.deferQuest(rank, name, retryAt)
		local record = dailyCoordinator.record(rank, name)
		record.retryAt = math.max(os.time() + 300, math.floor(retryAt))
		dailyCoordinator.save()
	end

	spawn(function()
		LocalPlayer:WaitForChild("PlayerStats")
		dailyCoordinator.refreshAccess()
	end)
	end

	local function findSeaKingIsland()
		-- Accepts Legacy Island1 through Legacy Island6 (or more).
		for _, island in pairs(Workspace.Island:GetChildren()) do
			if island.Name:match("^Legacy Island%d+$") then
				return island
			end
		end
		-- Legacy fallbacks.
		for _, island in pairs(Workspace.Island:GetChildren()) do
			local name = island.Name:lower()
			if name:find("legacy") and name:find("island") then
				return island
			end
			if name:find("sea king") or name:find("seaking") then
				return island
			end
		end
		if Workspace:FindFirstChild("SeaKingWater") then
			for _, island in pairs(Workspace.SeaKingWater:GetChildren()) do
				if island:IsA("Model") or island:IsA("Folder") then
					return island
				end
			end
		end
		return nil
	end

	local function findHydraIsland()
		for _, island in pairs(Workspace.Island:GetChildren()) do
			if island:FindFirstChild("HydraStand") then
				return island
			end
			if island.Name:lower():find("hydra") then
				return island
			end
		end
		return nil
	end

	local function findSeaKingMob()
		if Workspace.SeaMonster:FindFirstChild("SeaKing") then
			local mob = Workspace.SeaMonster.SeaKing
			if mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
				return mob
			end
		end
		local island = findSeaKingIsland()
		if island then
			for _, child in pairs(island:GetDescendants()) do
				if child.Name == "SeaKing" and child:FindFirstChild("Humanoid") then
					if child.Humanoid.Health > 0 then
						return child
					end
				end
			end
		end
		return nil
	end

	local function findHydraMob()
		if Workspace.SeaMonster:FindFirstChild("HydraSeaKing") then
			local mob = Workspace.SeaMonster.HydraSeaKing
			if mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
				return mob
			end
		end
		local island = findHydraIsland()
		if island then
			for _, child in pairs(island:GetDescendants()) do
				if child.Name == "HydraSeaKing" and child:FindFirstChild("Humanoid") then
					if child.Humanoid.Health > 0 then
						return child
					end
				end
			end
		end
		return nil
	end

	local function findGhostShip()
		local ghostShip = Workspace.GhostMonster:FindFirstChild("Ghost Ship")
		if ghostShip and ghostShip:FindFirstChild("Humanoid") and ghostShip.Humanoid.Health > 0 then
			return ghostShip
		end
		return nil
	end

	local function findSeaKingChestPosition()
		local island = findSeaKingIsland()
		if not island then
			return nil
		end

		-- 1) Try to find ChestSpawner DIRECTLY on the island (e.g. Legacy Island1.ChestSpawner).
		local chestSpawner = island:FindFirstChild("ChestSpawner")
		if chestSpawner then
			if chestSpawner:IsA("BasePart") then
				return chestSpawner.Position + Vector3.new(0, 3, 0)
			else
				local part = chestSpawner:FindFirstChildWhichIsA("BasePart")
				if part then
					return part.Position + Vector3.new(0, 3, 0)
				end
			end
		end

		-- 2) Legacy fallback: Gate -> ChestSpawner.
		local gate = island:FindFirstChild("Gate")
		if gate then
			local gateChestSpawner = gate:FindFirstChild("ChestSpawner")
			if gateChestSpawner then
				for _, child in pairs(gateChestSpawner:GetChildren()) do
					if child:IsA("BasePart") then
						return child.Position + Vector3.new(0, 3, 0)
					else
						local part = child:FindFirstChildWhichIsA("BasePart")
						if part then
							return part.Position + Vector3.new(0, 3, 0)
						end
					end
				end
			end
		end

		-- 3) Generic fallback.
		for _, child in pairs(island:GetDescendants()) do
			if
				child:IsA("BasePart") and (child.Name:lower():find("chest") or child.Name:lower():find("ba\195\186"))
			then
				return child.Position + Vector3.new(0, 3, 0)
			end
		end

		local anyPart = island:FindFirstChildWhichIsA("BasePart")
		if anyPart then
			return anyPart.Position + Vector3.new(0, 50, 0)
		end
		return nil
	end

	local function findHydraChestPosition()
		local island = findHydraIsland()
		if not island then
			return nil
		end

		local hydraStand = island:FindFirstChild("HydraStand")
		if hydraStand then
			if hydraStand:IsA("BasePart") then
				return hydraStand.Position + Vector3.new(0, 4, 0)
			end
			local part = hydraStand:FindFirstChildWhichIsA("BasePart")
			if part then
				return part.Position + Vector3.new(0, 4, 0)
			end
		end

		for _, child in pairs(island:GetDescendants()) do
			if
				child:IsA("BasePart")
				and (
					child.Name:lower():find("chest")
					or child.Name:lower():find("ba\195\186")
					or child.Name:lower():find("hydra")
				)
			then
				return child.Position + Vector3.new(0, 3, 0)
			end
		end

		local anyPart = island:FindFirstChildWhichIsA("BasePart")
		if anyPart then
			return anyPart.Position + Vector3.new(0, 50, 0)
		end
		return nil
	end

	local function getSerpentLocation()
		local areas = Workspace:FindFirstChild("Areas")
		if not areas then
			return nil
		end
		local part = areas:FindFirstChild("SerpentLocation")
		if not part or not part:IsA("BasePart") then
			return nil
		end
		return part.CFrame * CFrame.new(0, 10, 0)
	end

	local function findSerpent()
		for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
			if
				string.find(monster.Name, "Serpent")
				and monster:FindFirstChild("Humanoid")
				and monster.Humanoid.Health > 0
				and monster:FindFirstChild("HumanoidRootPart")
			then
				return monster
			end
		end
		if Workspace.Monster:FindFirstChild("Boss") then
			for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
				if
					string.find(child.Name, "Serpent")
					and child:FindFirstChild("Humanoid")
					and child.Humanoid.Health > 0
					and child:FindFirstChild("HumanoidRootPart")
				then
					return child
				end
			end
		end
		return nil
	end

	local function findPtero()
		if Workspace.Monster:FindFirstChild("Boss") then
			for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
				if
					string.find(child.Name, "Pteranodon")
					and child:FindFirstChild("Humanoid")
					and child.Humanoid.Health > 0
					and child:FindFirstChild("HumanoidRootPart")
				then
					return child
				end
			end
		end
		return nil
	end

	local _seaEventTarget = nil
	local _seaEventThread = nil
	local _seaEventLockPosition = nil
	_G._GenesisAbyssalAcquisition = {
		approachHeight = 18,
		retrySeconds = 4,
		maxAttempts = 3,
		locatorPollInterval = 0.2,
		nextLocatorCheckAt = 0,
		locator = nil,
		locatorCFrame = nil,
		startedAt = 0,
		lastApproachAt = -math.huge,
		attempts = 0,
		lastDestination = nil,
	}
	_G._stopAbyssalAcquisition = function()
		local state = _G._GenesisAbyssalAcquisition
		if type(state) ~= "table" then
			return
		end
		state.locator = nil
		state.locatorCFrame = nil
		state.startedAt = 0
		state.lastApproachAt = -math.huge
		state.attempts = 0
		state.lastDestination = nil
		state.nextLocatorCheckAt = 0
	end

	local function isValidMob(mob)
		if not mob or not mob.Parent then
			return false
		end
		local humanoid = mob:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return false
		end
		return true
	end

	local function getMobHRP(mob)
		return mob:FindFirstChild("HumanoidRootPart")
	end

	local function getMobHeight(mob)
		local name = mob.Name
		if
			string.find(name, "ThirdSeaDragon")
			or string.find(name, "Eldritch")
			or string.find(name, "Crab")
			or string.find(name, "Pteranodon")
		then
			return 0
		end
		if string.find(name, "Serpent") or string.find(name, "SeaDragon") then
			return 15
		end
		return 10
	end

	local function isPlayerAlive()
		local character = LocalPlayer.Character
		if not character then
			return false
		end
		local humanoid = character:FindFirstChild("Humanoid")
		return humanoid and humanoid.Health > 0
	end

	local function getDistanceToMob(mob)
		local character = LocalPlayer.Character
		if not character then
			return math.huge
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return math.huge
		end
		local mobHRP = getMobHRP(mob)
		if not mobHRP then
			return math.huge
		end
		return (root.Position - mobHRP.Position).Magnitude
	end

	local function getSeaEventCFrame(targetCFrame, mobName)
		local height = getMobHeight({ Name = mobName }) + 8
		local offset = Vector3.new(math.sin(tick() * 3) * 1.5, math.cos(tick() * 2) * 1, math.cos(tick() * 3) * 1.5)
		if string.find(mobName or "", "Galleon", 1, true) then
			-- Stay pitched straight down at the hitbox, but rotate that downward
			-- stance with the galleon's horizontal heading as it turns.
			local right = Vector3.new(targetCFrame.RightVector.X, 0, targetCFrame.RightVector.Z)
			if right.Magnitude < 0.001 then
				right = Vector3.xAxis
			else
				right = right.Unit
			end
			local back = Vector3.yAxis
			local up = back:Cross(right).Unit
			return CFrame.fromMatrix(targetCFrame.Position + Vector3.new(0, height, 0) + offset, right, up, back)
		end

		local mobPos = targetCFrame.Position
		local above = mobPos + Vector3.new(0, height, 0)
		local lookCF = CFrame.new(above, mobPos)
		return lookCF + offset
	end

	stopSeaEventBypass = function()
		_seaEventTarget = nil
		-- The movement lock and combat permission are one ownership unit. If the
		-- target disappears (or another activity takes over), an older automation
		-- pass must not retain permission to send M1/skill input.
		_G.allowCombat = false
		if _seaEventThread then
			pcall(function() end)
			_seaEventThread = nil
		end
		_seaEventLockPosition = nil
	end
	_G._stopSeaEventBypass = stopSeaEventBypass

	local function startSeaEventBypass(mob)
		if _G._GenesisDailyReturnRequested or not mob or not mob.Parent then
			return false
		end
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			return false
		end
		local mobHRP = getMobHRP(mob)
		if not mobHRP then
			return false
		end
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end

		stopSeaEventBypass()

		_seaEventTarget = mob
		-- Establish the first lock synchronously. The caller may send M1/skills as
		-- soon as this function succeeds, so both the position and lock marker must
		-- already be authoritative before the follow worker is scheduled.
		local initialTargetCF = getSeaEventCFrame(mobHRP.CFrame, mob.Name)
		root.CFrame = initialTargetCF
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		_G.pos_skill = mobHRP.CFrame
		_seaEventLockPosition = initialTargetCF

		_seaEventThread = task.spawn(function()
			while _seaEventTarget == mob and isValidMob(mob) and isPlayerAlive()
				and not _G._GenesisDailyReturnRequested do
				local character = LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not root then
					break
				end
				local mobHRP = getMobHRP(mob)
				if not mobHRP then
					break
				end

				local targetCF = getSeaEventCFrame(mobHRP.CFrame, mob.Name)

				root.CFrame = targetCF
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero

				_G.pos_skill = mobHRP.CFrame
				_seaEventLockPosition = targetCF

				task.wait(0.01)
			end

			if _seaEventTarget == mob then
				stopSeaEventBypass()
			end
		end)

		return true
	end

	local function updatePosition(mob)
		if not isPlayerAlive() then
			stopSeaEventBypass()
			return "morto"
		end

		if not mob or not mob.Parent then
			stopSeaEventBypass()
			return "mob_invalido"
		end

		-- Sea targets may appear while fishing owns both the root and Primary slot.
		-- Finish that handoff before this function moves the character or starts the
		-- 0.01-second sea lock. Returning "handoff" keeps the event reserved without
		-- allowing another frame to attack with the rod.
		if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("sea_event") then
			stopSeaEventBypass()
			return "handoff"
		end
		-- Restoring the Primary weapon can yield while the entrance timer finishes.
		-- Recheck the irreversible picker boundary before any outside movement.
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			stopSeaEventBypass()
			return "dungeon"
		end

		if _seaEventTarget == mob then
			return "ancorado"
		end

		if _seaEventTarget and _seaEventTarget ~= mob then
			stopSeaEventBypass()
			task.wait(0.05)
		end

		-- CFrame movement is already instantaneous; a staged random approach only
		-- delays combat and leaves a window without a follow lock. Snap directly to
		-- the combat offset and let the 0.01-second worker track target movement.
		if startSeaEventBypass(mob) then
			return "ancorado"
		end

		return "erro"
	end

	_G._GenesisFindAbyssalLocator = function()
		local monster = Workspace:FindFirstChild("Monster")
		local island = Workspace:FindFirstChild("Island")
		local areas = Workspace:FindFirstChild("Areas")
		local boss = monster and monster:FindFirstChild("Boss")
		local ghostMonster = Workspace:FindFirstChild("GhostMonster")
		local seaMonster = Workspace:FindFirstChild("SeaMonster")
		local locator = (island and island:FindFirstChild("SeaDragonLocation"))
			or (areas and areas:FindFirstChild("SeaDragonLocation"))
			or (boss and boss:FindFirstChild("SeaDragonLocation"))
			or (ghostMonster and ghostMonster:FindFirstChild("SeaDragonLocation"))
			or (seaMonster and seaMonster:FindFirstChild("SeaDragonLocation"))
		if locator then
			local locatorCFrame = nil
			if locator:IsA("BasePart") then
				locatorCFrame = locator.CFrame
			elseif locator:IsA("Model") then
				local ok, pivot = pcall(locator.GetPivot, locator)
				if ok then
					locatorCFrame = pivot
				end
			end

			if typeof(locatorCFrame) == "CFrame" then
				local position = locatorCFrame.Position
				local finite = position.X == position.X
					and position.Y == position.Y
					and position.Z == position.Z
					and math.abs(position.X) < 10000000
					and math.abs(position.Y) < 10000000
					and math.abs(position.Z) < 10000000
				if finite then
					return locator, locatorCFrame
				end
			end
		end

		return nil, nil
	end

	_G._GenesisApproachAbyssalLocator = function(locator, locatorCFrame)
		local state = _G._GenesisAbyssalAcquisition
		if type(state) ~= "table" then
			return false
		end
		if not isFeatureEnabledInCurrentSea("autoKillAbyssalTyrant") then
			if type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			return false
		end
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			if type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			return true
		end
		if not locator or not locator.Parent or typeof(locatorCFrame) ~= "CFrame" then
			if type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			return false
		end

		if state.locator ~= locator then
			if type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			state.locator = locator
			state.startedAt = os.clock()
		end
		state.locatorCFrame = locatorCFrame

		-- A locator is an event reservation, not a combat target. Stop stale combat
		-- input and movement locks before making a single bounded approach.
		_G.allowCombat = false
		_G.seaEventActive = true
		_G.currentEventHealth = 0
		_G.currentEventMaxHealth = 0
		if _G.farmFixThread or _G.farmFixBodyPos then
			removeFarmFix()
		end
		if _seaEventTarget or _seaEventThread or _seaEventLockPosition then
			stopSeaEventBypass()
			_G.seaEventActive = true
		end

		if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("abyssal_locator") then
			_G.currentEventName = "Abyssal Tyrant (Switching Loadout)"
			return true
		end
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			if type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			return true
		end

		local now = os.clock()
		if state.attempts >= state.maxAttempts then
			_G.currentEventName = "Abyssal Tyrant (Waiting for Spawn)"
			return true
		end
		if now - state.lastApproachAt < state.retrySeconds then
			_G.currentEventName = "Abyssal Tyrant (Waiting for Spawn)"
			return true
		end

		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root then
			_G.currentEventName = "Abyssal Tyrant (Waiting for Respawn)"
			return true
		end

		local destination = CFrame.new(locatorCFrame.Position + Vector3.new(0, state.approachHeight, 0))
		state.attempts = state.attempts + 1
		state.lastApproachAt = now
		state.lastDestination = destination
		_G.currentEventName = "Abyssal Tyrant (Locating "
			.. state.attempts
			.. "/"
			.. state.maxAttempts
			.. ")"

		root.CFrame = destination
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	function serverHop()
		local success, result = pcall(function()
			local req = http_request or request or syn.request
			if not req then
				return
			end
			local ok, response = pcall(function()
				return req({
					Url = "https://games.roblox.com/v1/games/"
						.. game.PlaceId
						.. "/servers/Public?sortOrder=Asc&limit=100",
					Method = "GET",
				})
			end)
			if ok and response and response.Body then
				local parseOk, data = pcall(function()
					return HttpService:JSONDecode(response.Body)
				end)
				if parseOk and data and data.data then
					local servers = {}
					for _, server in ipairs(data.data) do
						if server.id ~= game.JobId and server.playing < server.maxPlayers then
							table.insert(servers, server.id)
						end
					end
					if #servers > 0 then
						local randomServer = servers[math.random(1, #servers)]
						TeleportService:TeleportToPlaceInstance(game.PlaceId, randomServer, LocalPlayer)
					else
						local ui = env.SpectrumX
						if ui and type(ui.Notify) == "function" then
							ui:Notify({ Text = "No servers found!", Type = "error", Duration = 3 })
						end
					end
				end
			end
		end)
		if not success then
			local ui = env.SpectrumX
			if ui and type(ui.Notify) == "function" then
				ui:Notify({ Text = "Hop failed: " .. tostring(result), Type = "error", Duration = 3 })
			end
		end
	end

	findSeaKingIsland = function()
		for _, island in pairs(Workspace.Island:GetChildren()) do
			if island.Name == "Legacy Island2" then
				return island
			end
		end
		for _, island in pairs(Workspace.Island:GetChildren()) do
			local name = island.Name:lower()
			if name:find("legacy") and name:find("island") then
				return island
			end
			if name:find("sea king") or name:find("seaking") then
				return island
			end
		end
		if Workspace:FindFirstChild("SeaKingWater") then
			for _, island in pairs(Workspace.SeaKingWater:GetChildren()) do
				if island:IsA("Model") or island:IsA("Folder") then
					return island
				end
			end
		end
		return nil
	end

	findHydraIsland = function()
		for _, island in pairs(Workspace.Island:GetChildren()) do
			if island:FindFirstChild("HydraStand") then
				return island
			end
			if island.Name:lower():find("hydra") then
				return island
			end
		end
		return nil
	end

	findSeaKingMob = function()
		if Workspace.SeaMonster:FindFirstChild("SeaKing") then
			local mob = Workspace.SeaMonster.SeaKing
			if mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
				return mob
			end
		end
		local island = findSeaKingIsland()
		if island then
			for _, child in pairs(island:GetDescendants()) do
				if child.Name == "SeaKing" and child:FindFirstChild("Humanoid") then
					if child.Humanoid.Health > 0 then
						return child
					end
				end
			end
		end
		return nil
	end

	findHydraMob = function()
		if Workspace.SeaMonster:FindFirstChild("HydraSeaKing") then
			local mob = Workspace.SeaMonster.HydraSeaKing
			if mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
				return mob
			end
		end
		local island = findHydraIsland()
		if island then
			for _, child in pairs(island:GetDescendants()) do
				if child.Name == "HydraSeaKing" and child:FindFirstChild("Humanoid") then
					if child.Humanoid.Health > 0 then
						return child
					end
				end
			end
		end
		return nil
	end

	findGhostShip = function()
		local ghostShip = Workspace.GhostMonster:FindFirstChild("Ghost Ship")
		if ghostShip and ghostShip:FindFirstChild("Humanoid") and ghostShip.Humanoid.Health > 0 then
			return ghostShip
		end
		return nil
	end

	findSeaKingChestPosition = function()
		local island = findSeaKingIsland()
		if not island then
			return nil
		end

		-- Legacy Island1 exposes its chest spawner directly on the island.
		-- Keep this before the Gate fallback; the later redefinition used to
		-- discard this valid layout and select an unrelated fallback part.
		local chestSpawner = island:FindFirstChild("ChestSpawner")
		if chestSpawner then
			if chestSpawner:IsA("BasePart") then
				return chestSpawner.Position + Vector3.new(0, 3, 0)
			end
			local part = chestSpawner:FindFirstChildWhichIsA("BasePart")
			if part then
				return part.Position + Vector3.new(0, 3, 0)
			end
		end

		local gate = island:FindFirstChild("Gate")
		if gate then
			local chestSpawner = gate:FindFirstChild("ChestSpawner")
			if chestSpawner then
				for _, child in pairs(chestSpawner:GetChildren()) do
					if child:IsA("Model") or child:IsA("BasePart") then
						if child:IsA("BasePart") then
							return child.Position + Vector3.new(0, 3, 0)
						else
							local part = child:FindFirstChildWhichIsA("BasePart")
							if part then
								return part.Position + Vector3.new(0, 3, 0)
							end
						end
					end
				end
			end
		end

		for _, child in pairs(island:GetDescendants()) do
			if
				child:IsA("BasePart") and (child.Name:lower():find("chest") or child.Name:lower():find("ba\195\186"))
			then
				return child.Position + Vector3.new(0, 3, 0)
			end
		end

		local anyPart = island:FindFirstChildWhichIsA("BasePart")
		if anyPart then
			return anyPart.Position + Vector3.new(0, 50, 0)
		end
		return nil
	end

	findHydraChestPosition = function()
		local island = findHydraIsland()
		if not island then
			return nil
		end

		local hydraStand = island:FindFirstChild("HydraStand")
		if hydraStand then
			if hydraStand:IsA("BasePart") then
				return hydraStand.Position + Vector3.new(0, 4, 0)
			end
			local part = hydraStand:FindFirstChildWhichIsA("BasePart")
			if part then
				return part.Position + Vector3.new(0, 4, 0)
			end
		end

		for _, child in pairs(island:GetDescendants()) do
			if
				child:IsA("BasePart")
				and (
					child.Name:lower():find("chest")
					or child.Name:lower():find("ba\195\186")
					or child.Name:lower():find("hydra")
				)
			then
				return child.Position + Vector3.new(0, 3, 0)
			end
		end

		local anyPart = island:FindFirstChildWhichIsA("BasePart")
		if anyPart then
			return anyPart.Position + Vector3.new(0, 50, 0)
		end
		return nil
	end

	_G.findSeaKingIsland = findSeaKingIsland
	_G.findSeaKingMob = findSeaKingMob
	_G.findHydraMob = findHydraMob
	_G.findSeaKingChestPosition = findSeaKingChestPosition
	_G.findHydraChestPosition = findHydraChestPosition

	local function checkSea1Events(phase)
		phase = phase or "all"
		local wantsSerpent = phase == "all" or phase == "serpent"
		if _G.isLootingChests and wantsSerpent then
			return true
		end

		local hasEvent = false

		if wantsSerpent and GetSetting("autoHuntSerpent") then
			local serpent = findSerpent()
			if isValidMob(serpent) then
				removeFarmFix()
				_G.currentEventName = "Serpent"
				_G.currentEventHealth = serpent.Humanoid.Health
				_G.currentEventMaxHealth = serpent.Humanoid.MaxHealth
				_G.seaEventActive = true
				hasEvent = true

				local status = updatePosition(serpent)
				if status == "ancorado" then
					usetool()
					local As9K = {}
					As9K[475] = 153
					buso()
					ken()
					hao()
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				end
				return true
			elseif getSerpentLocation() then
				if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("serpent_submerged") then
					return true
				end
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					return true
				end
				removeFarmFix()
				stopSeaEventBypass()
				_G.currentEventName = "Serpent (Submerged)"
				_G.seaEventActive = true
				hasEvent = true
				local root = GetRoot(LocalPlayer.Character)
				if root then
					root.CFrame = getSerpentLocation()
				end
				return true
			end
		end

		if not hasEvent and wantsSerpent then
			_G.seaEventActive = false
			_G.currentEventName = "None"
			_G.currentEventHealth = 0
			_G.currentEventMaxHealth = 0
			stopSeaEventBypass()
		end

		return hasEvent
	end

	_G._GenesisSeaKingAcquisition = {
		island = nil,
		attempts = 0,
		lastApproachAt = -math.huge,
		sawBoss = false,
	}

	_G._GenesisFindSeaKingRewardChest = function(island)
		local spawner = island and island:FindFirstChild("ChestSpawner")
		if not spawner then
			return nil
		end
		for _, child in ipairs(spawner:GetChildren()) do
			if child:IsA("Model") and child:FindFirstChild("RootPart") and child:FindFirstChild("ChestAnim") then
				return child
			end
		end
		return nil
	end

	_G._GenesisApproachSeaKingIsland = function(island)
		if not isFeatureEnabledInCurrentSea("autoSKHD") then
			removeChestLootFix()
			_G.isLootingChests = false
			_G.seaEventActive = false
			return false
		end
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			return true
		end
		local main = island:FindFirstChild("Main") or island.PrimaryPart
		if not main or not main:IsA("BasePart") then
			_G.currentEventName = "Sea King (Island marker unavailable)"
			return true
		end
		_G.seaKingIslandEmpty = false
		_G.seaKingLootUnconfirmed = false
		_G.seaKingJoinLootStarted = false
		_G.isLootingChests = false
		_G.allowCombat = false
		_G.seaEventActive = true
		_G.currentEventHealth = 0
		_G.currentEventMaxHealth = 0
		removeFarmFix()
		stopSeaEventBypass()
		if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("sea_king_island") then
			_G.currentEventName = "Sea King (Switching Loadout)"
			return true
		end
		if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
			return true
		end
		local now = os.clock()
		if _G._GenesisSeaKingAcquisition.attempts >= 3 or now - _G._GenesisSeaKingAcquisition.lastApproachAt < 4 then
			_G.currentEventName = "Sea King (Waiting for Spawn)"
			return true
		end
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root then
			_G.currentEventName = "Sea King (Waiting for Respawn)"
			return true
		end
		_G._GenesisSeaKingAcquisition.attempts = _G._GenesisSeaKingAcquisition.attempts + 1
		_G._GenesisSeaKingAcquisition.lastApproachAt = now
		_G.currentEventName = "Sea King (Locating " .. _G._GenesisSeaKingAcquisition.attempts .. "/3)"
		root.CFrame = CFrame.new(main.Position + Vector3.new(0, 85, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	local function checkSea2Events(phase)
		phase = phase or "all"
		local wantsMajor = phase == "all" or phase == "major"
		local wantsSerpent = phase == "all" or phase == "serpent"
		local wantsGalleon = phase == "all" or phase == "galleon"
		-- If looting is active and the mob respawned, cancel immediately.
		if _G.isLootingChests then
			local majorLooting = _G.lootState.SeaKing.active or _G.lootState.Hydra.active
			if phase == "all" or (majorLooting and wantsMajor) or (not majorLooting and wantsGalleon) then
				if majorLooting then
					local sk = findSeaKingMob()
					if sk
						and sk:FindFirstChild("Humanoid")
						and sk.Humanoid.Health > 0
						and _G.lootState.SeaKing.active
					then
						removeChestLootFix()
						_G.isLootingChests = false
						_G.lootState.SeaKing = { active = false }
						if _G.lootThreads.SeaKing then
							_G.lootThreads.SeaKing = nil
						end
					end
					local hydra = findHydraMob()
					if
						hydra
						and hydra:FindFirstChild("Humanoid")
						and hydra.Humanoid.Health > 0
						and _G.lootState.Hydra.active
					then
						removeChestLootFix()
						_G.isLootingChests = false
						_G.lootState.Hydra = { active = false }
						if _G.lootThreads.Hydra then
							_G.lootThreads.Hydra = nil
						end
					end
				end
				return true
			end
		end

		local autoSKHD = isFeatureEnabledInCurrentSea("autoSKHD")
		local autoGhostShip = isFeatureEnabledInCurrentSea("autoGhostShip")

		-- Serpent is independent (it does not require SK/HD or Ghost Ship).
		if wantsSerpent and GetSetting("autoHuntSerpent") then
			local serpent = findSerpent()
			if isValidMob(serpent) then
				removeFarmFix()
				_G.currentEventName = "Serpent"
				_G.currentEventHealth = serpent.Humanoid.Health
				_G.currentEventMaxHealth = serpent.Humanoid.MaxHealth
				_G.lastEventCheck = tick()
				_G.seaEventActive = true
				local status = updatePosition(serpent)
				if status == "ancorado" then
					usetool()
					local kuYe = {}
					kuYe[695] = 582
					buso()
					ken()
					hao()
					_G.allowCombat = true
					click()
					local CnYL = nil
					if CnYL then
						CnYL = 291
					end
					autoskill()
					handleOpeMethod()
				end
				return true
			elseif getSerpentLocation() then
				if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("serpent_submerged") then
					return true
				end
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					return true
				end
				removeFarmFix()
				stopSeaEventBypass()
				_G.currentEventName = "Serpent (Submerged)"
				_G.seaEventActive = true
				local root = GetRoot(LocalPlayer.Character)
				if root then
					root.CFrame = getSerpentLocation()
				end
				return true
			end
		end

		-- === HYDRA / SEA KING (only with autoSKHD, independent of Serpent) ===
		if wantsMajor and autoSKHD then
			-- === HYDRA ===
			local hydraMob = findHydraMob()
			local hydraIsland = findHydraIsland()

			if hydraMob and hydraMob:FindFirstChild("Humanoid") and hydraMob.Humanoid.Health > 0 then
				_G.hydraIslandEmpty = false
				_G.hydraJoinLootStarted = false
				removeFarmFix()

				-- Monitor death by polling (reliable for multiple forms).
				if not _G.monitoringHydra then
					_G.monitoringHydra = true
					task.spawn(function()
						local target = hydraMob
						while
							target
							and target.Parent
							and target:FindFirstChild("Humanoid")
							and target.Humanoid.Health > 0
						do
							task.wait(0.2)
							if not isFeatureEnabledInCurrentSea("autoSKHD") then
								break
							end
						end

						_G.monitoringHydra = false
						if not isFeatureEnabledInCurrentSea("autoSKHD") then
							return
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							return
						end

						-- Reserve looting before moving so fishing cannot recreate its
						-- position lock between the death observation and this teleport.
						_G.isLootingChests = true
						local handoffDeadline = os.clock() + 12
						while
							(not _G._GenesisUpdateDungeonCommit or not _G._GenesisUpdateDungeonCommit())
							and _G._GenesisPrepareCombatFromFishing
							and not _G._GenesisPrepareCombatFromFishing("hydra_loot")
							and isFeatureEnabledInCurrentSea("autoSKHD")
							and os.clock() < handoffDeadline
						do
							task.wait(0.1)
						end
						if not isFeatureEnabledInCurrentSea("autoSKHD") then
							_G.isLootingChests = false
							return
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							_G.isLootingChests = false
							return
						end
						if _G._GenesisPrepareCombatFromFishing and fishingOwnsWeaponSlot() then
							_G.isLootingChests = false
							return
						end
						-- Dead: teleport immediately to the chest and lock position.
						local chestPos = findHydraChestPosition()
						if chestPos then
							tp(CFrame.new(chestPos))
							applyChestLootFix(CFrame.new(chestPos))
						end
						startLootTimer("Hydra", 30)
					end)
				end

				_G.currentEventName = "Hydra"
				_G.currentEventHealth = hydraMob.Humanoid.Health
				_G.currentEventMaxHealth = hydraMob.Humanoid.MaxHealth
				_G.lastEventCheck = tick()
				_G.seaEventActive = true
				local status = updatePosition(hydraMob)
				if status == "ancorado" then
					usetool()
					buso()
					ken()
					local Tsg8 = function(BUP4)
						return BUP4
					end
					Tsg8 = Tsg8
					hao()
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				end
				return true
			elseif hydraIsland then
				removeFarmFix()
				if _G.hydraIslandEmpty then
					_G.currentEventName = "Hydra (Done)"
					_G.seaEventActive = false
					return false
				end

				_G.currentEventName = "Hydra (Waiting)"
				_G.seaEventActive = true

				-- Joined a server that only has the island/chest (20s).
				if not _G.hydraJoinLootStarted and not _G.lootState.Hydra.active then
					_G.hydraJoinLootStarted = true
					local chestPos = findHydraChestPosition()
					if chestPos then
						_G.isLootingChests = true
						if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("hydra_loot") then
							return true
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							_G.isLootingChests = false
							return true
						end
						tp(CFrame.new(chestPos))
						applyChestLootFix(CFrame.new(chestPos))
						startLootTimer("Hydra", 20)
					end
				elseif _G.lootState.Hydra.active then
					local chestPos = findHydraChestPosition()
					if chestPos then
						applyChestLootFix(CFrame.new(chestPos))
					end
				end
				return true
			else
				_G.hydraJoinLootStarted = false
			end

			-- === SEA KING ===
			local seaKingMob = findSeaKingMob()
			local seaKingIsland = findSeaKingIsland()
			if _G._GenesisSeaKingAcquisition.island ~= seaKingIsland then
				_G._GenesisSeaKingAcquisition.island = seaKingIsland
				_G._GenesisSeaKingAcquisition.attempts = 0
				_G._GenesisSeaKingAcquisition.lastApproachAt = -math.huge
				_G._GenesisSeaKingAcquisition.sawBoss = false
				_G.seaKingLootUnconfirmed = false
			end
			local rawSeaKing = Workspace.SeaMonster:FindFirstChild("SeaKing")
			if rawSeaKing and rawSeaKing:FindFirstChild("Humanoid") then
				_G._GenesisSeaKingAcquisition.sawBoss = true
			end

			if seaKingMob and seaKingMob:FindFirstChild("Humanoid") and seaKingMob.Humanoid.Health > 0 then
				_G._GenesisSeaKingAcquisition.sawBoss = true
				_G.seaKingIslandEmpty = false
				_G.seaKingLootUnconfirmed = false
				_G.seaKingJoinLootStarted = false
				removeFarmFix()

				if not _G.monitoringSeaKing then
					_G.monitoringSeaKing = true
					task.spawn(function()
						local target = seaKingMob
						while
							target
							and target.Parent
							and target:FindFirstChild("Humanoid")
							and target.Humanoid.Health > 0
						do
							task.wait(0.2)
							if not isFeatureEnabledInCurrentSea("autoSKHD") then
								break
							end
						end

						_G.monitoringSeaKing = false
						if not isFeatureEnabledInCurrentSea("autoSKHD") then
							return
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							return
						end

						_G.isLootingChests = true
						local handoffDeadline = os.clock() + 12
						while
							(not _G._GenesisUpdateDungeonCommit or not _G._GenesisUpdateDungeonCommit())
							and _G._GenesisPrepareCombatFromFishing
							and not _G._GenesisPrepareCombatFromFishing("sea_king_loot")
							and isFeatureEnabledInCurrentSea("autoSKHD")
							and os.clock() < handoffDeadline
						do
							task.wait(0.1)
						end
						if not isFeatureEnabledInCurrentSea("autoSKHD") then
							_G.isLootingChests = false
							return
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							_G.isLootingChests = false
							return
						end
						if _G._GenesisPrepareCombatFromFishing and fishingOwnsWeaponSlot() then
							_G.isLootingChests = false
							return
						end
						-- Dead: teleport IMMEDIATELY to the chest before locking position.
						local chestPos = findSeaKingChestPosition()
						if chestPos then
							tp(CFrame.new(chestPos))
							applyChestLootFix(CFrame.new(chestPos))
						end
						startLootTimer("SeaKing", 30)
					end)
				end

				_G.currentEventName = "Sea King"
				_G.currentEventHealth = seaKingMob.Humanoid.Health
				_G.currentEventMaxHealth = seaKingMob.Humanoid.MaxHealth
				_G.lastEventCheck = tick()
				_G.seaEventActive = true
				local status = updatePosition(seaKingMob)
				if status == "ancorado" then
					usetool()
					buso()
					ken()
					local tklW = {}
					tklW[786] = 916
					hao()
					_G.allowCombat = true
					click()
					do
						local AEZm = 171
						AEZm = AEZm + 0
					end
					autoskill()
					handleOpeMethod()
				end
				return true
			elseif seaKingIsland then
				-- Unlike post-kill loot, an UNLEASHED island without a reward chest
				-- is a pre-spawn locator. The Sea King model appears only after a player
				-- approaches the island; the island alone is not proof of a kill.
				if not _G._GenesisSeaKingAcquisition.sawBoss
					and not _G._GenesisFindSeaKingRewardChest(seaKingIsland)
					and ReplicatedStorage:GetAttribute("SeaMonsterSpawnText") == "UNLEASHED"
					and ReplicatedStorage:GetAttribute("Hydra") ~= true
				then
					return _G._GenesisApproachSeaKingIsland(seaKingIsland)
				end
				removeFarmFix()
				if _G.seaKingIslandEmpty then
					_G.currentEventName = _G.seaKingLootUnconfirmed
						and "Sea King (Chest unconfirmed)"
						or "Sea King (Done)"
					_G.seaEventActive = false
					return false
				end

				_G.currentEventName = "Sea King (Waiting)"
				_G.seaEventActive = true

				-- Joined a server that only has the island/chest (20s).
				if not _G.seaKingJoinLootStarted and not _G.lootState.SeaKing.active then
					_G.seaKingJoinLootStarted = true
					local chestPos = findSeaKingChestPosition()
					if chestPos then
						_G.isLootingChests = true
						if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("sea_king_loot") then
							return true
						end
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							_G.isLootingChests = false
							return true
						end
						tp(CFrame.new(chestPos))
						applyChestLootFix(CFrame.new(chestPos))
						startLootTimer("SeaKing", 20)
					end
				elseif _G.lootState.SeaKing.active then
					local chestPos = findSeaKingChestPosition()
					if chestPos then
						applyChestLootFix(CFrame.new(chestPos))
					end
				end
				return true
			else
				_G.seaKingJoinLootStarted = false
				_G._GenesisSeaKingAcquisition.sawBoss = false
			end
		end -- autoSKHD hydra/sk

		-- === GHOST SHIP (independent of SK/HD and Serpent) ===
		if wantsGalleon and autoGhostShip then
			local ghostShip = findGhostShip()
			local function getGhostLootAbortReason()
				-- Once Ghost Ship chest collection starts, it is a short atomic
				-- transaction. Outside bosses and sea events wait for it to finish;
				-- only an irreversible dungeon transition may preempt automation.
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					return "dungeon"
				end
				if _G._GenesisDailyReturnRequested then
					return "daily_return"
				end
				-- Turning the feature off remains an immediate manual kill switch.
				if not isFeatureEnabledInCurrentSea("autoGhostShip") then
					return "disabled"
				end
				return nil
			end

			local function waitDuringGhostLoot(seconds, chest, chestCF, holdPosition)
				local deadline = os.clock() + seconds
				repeat
					local abortReason = getGhostLootAbortReason()
					if abortReason then
						return abortReason
					end
					if not chest or not chest.Parent or not chest:IsDescendantOf(Workspace) then
						return "collected"
					end
					if holdPosition then
						updateFarmFix(chestCF)
					end
					task.wait(0.1)
				until os.clock() >= deadline
				return nil
			end

			local chestList = {}
			local allChestEntries = {}
			for i = 1, 10 do
				local chest = Workspace:FindFirstChild("Chest" .. i) or Workspace:FindFirstChild("DarkChest" .. i)
				if chest then
					local chestPart = chest:IsA("BasePart") and chest
						or chest:FindFirstChild("RootPart")
						or chest:FindFirstChild("PrimaryPart")
						or (chest:IsA("Model") and chest.PrimaryPart)
						or chest:FindFirstChildWhichIsA("BasePart")
					local chestEntry = { Chest = chest, Part = chestPart }
					table.insert(allChestEntries, chestEntry)
					if chestPart then
						-- A chest that exhausted its five real acquisition attempts stays
						-- ignored until that exact instance despawns. Re-entering this block
						-- every frame would otherwise toggle the fishing/combat owner forever.
						if (_G.ghostChestAttemptState[chest] or 0) < 5 then
							table.insert(chestList, chestEntry)
						end
					end
				end
			end

			if #chestList > 0 then
				local lootAbortReason = nil
				_G.seaEventActive = true
				_G.isLootingChests = true
				_G.currentEventName = "Ghost Ship (Looting)"
				local handoffDeadline = os.clock() + 12
				while
					not getGhostLootAbortReason()
					and _G._GenesisPrepareCombatFromFishing
					and not _G._GenesisPrepareCombatFromFishing("ghost_ship_loot")
					and os.clock() < handoffDeadline
				do
					task.wait(0.1)
				end
				lootAbortReason = getGhostLootAbortReason()
				if lootAbortReason then
					_G.isLootingChests = false
					return true
				end
				if _G._GenesisPrepareCombatFromFishing and fishingOwnsWeaponSlot() then
					-- Collection has not started yet. Release the provisional flag and
					-- retry cleanly instead of stranding the looting guard forever.
					_G.isLootingChests = false
					return true
				end
				-- A prior level-farm lock can otherwise pull the player back during
				-- the first acquisition attempt.
				removeFarmFix()

				for _, chestEntry in ipairs(chestList) do
					lootAbortReason = getGhostLootAbortReason()
					if lootAbortReason then
						break
					end

					local chest = chestEntry.Chest
					local chestPart = chestEntry.Part
					local attempts = _G.ghostChestAttemptState[chest] or 0
					while attempts < 5 do
						lootAbortReason = getGhostLootAbortReason()
						if lootAbortReason
							or not chest
							or not chest.Parent
							or not chest:IsDescendantOf(Workspace)
							or not chestPart
							or not chestPart.Parent
							or not chestPart:IsDescendantOf(Workspace)
						then
							break
						end

						local root = GetRoot(LocalPlayer.Character)
						if not root then
							break
						end

						attempts = attempts + 1
						_G.ghostChestAttemptState[chest] = attempts
						-- Preserve the webhook-only collector's proven sequence: arrive five
						-- studs above the chest, allow one second for natural contact, then
						-- hold that position for one second. Repeat only if replication still
						-- shows the same chest, with a hard cap of five real attempts.
						removeFarmFix()
						local chestCF = chestPart.CFrame * CFrame.new(0, 5, 0)
						root.CFrame = chestCF
						lootAbortReason = waitDuringGhostLoot(1, chest, chestCF, false)
						if lootAbortReason == "collected" then
							lootAbortReason = nil
							break
						elseif lootAbortReason then
							break
						end

						applyFarmFix(chestCF)
						updateFarmFix(chestCF)
						lootAbortReason = waitDuringGhostLoot(1, chest, chestCF, true)
						if lootAbortReason == "collected" then
							lootAbortReason = nil
							break
						elseif lootAbortReason then
							break
						end
					end
					if lootAbortReason then
						break
					end
				end

				removeFarmFix()
				_G.isLootingChests = false
				if lootAbortReason then
					-- A committed dungeon takes control on the next resolver step. Manual
					-- disable likewise ends the transaction without resetting attempt counts.
					return true
				end
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					return true
				end
				if not isFeatureEnabledInCurrentSea("autoGhostShip") then
					return true
				end
				local remainingChests = 0
				local exhaustedChest = nil
				for _, chestEntry in ipairs(allChestEntries) do
					local chest = chestEntry.Chest
					if chest and chest.Parent and chest:IsDescendantOf(Workspace) then
						remainingChests = remainingChests + 1
						if (_G.ghostChestAttemptState[chest] or 0) >= 5 then
							exhaustedChest = exhaustedChest or chest
						end
					else
						_G.ghostChestAttemptState[chest] = nil
						_G.ghostChestExhaustedNotified[chest] = nil
					end
				end

				local fullyLooted = remainingChests == 0
				_G.ghostShipKilled = fullyLooted
				if exhaustedChest and not _G.ghostChestExhaustedNotified[exhaustedChest] then
					_G.ghostChestExhaustedNotified[exhaustedChest] = true
					SpectrumX:Notify({
						Text = "A Ghost Ship chest remained after 5 acquisition attempts; stopping safely.",
						Type = "warning",
						Duration = 5,
					})
				end
				if fullyLooted and GetSetting("autoHopSeaBosses") then
					SpectrumX:Notify({
						Text = "Ghost Ship fully looted! Hopping server...",
						Type = "info",
						Duration = 3,
					})
					task.wait(5)
					serverHop()
				end
				if not fullyLooted then
					_G.seaEventActive = false
					_G.currentEventName = "None"
				end
				return true
			end

			if #allChestEntries > 0 then
				-- Every remaining chest is either exhausted or structurally invalid.
				-- The feature has stopped attempting it, so release movement/loadout
				-- ownership instead of re-entering a zero-work loot pass each frame.
				_G.isLootingChests = false
				_G.ghostShipKilled = false
				_G.seaEventActive = false
				_G.currentEventName = "None"
				return false
			end

			if isValidMob(ghostShip) and ghostShip:FindFirstChild("HumanoidRootPart") then
				removeFarmFix()
				_G.ghostShipKilled = false
				if not _G.ghostShipDiedConnected then
					_G.ghostShipDiedConnected = true
					trackGenesisConnection(ghostShip.Humanoid.Died:Connect(function()
						_G.ghostShipDiedConnected = false
						if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
							return
						end
						_G.postEventTimers.GhostShip.active = true
						_G.postEventTimers.GhostShip.startTime = tick()
						_G.isLootingChests = true
						stopSeaEventBypass()
						task.wait(3)
						_G.isLootingChests = false
					end))
				end

				_G.currentEventName = "Ghost Ship"
				_G.currentEventHealth = ghostShip.Humanoid.Health
				_G.currentEventMaxHealth = ghostShip.Humanoid.MaxHealth
				_G.lastEventCheck = tick()
				_G.seaEventActive = true
				local status = updatePosition(ghostShip)
				if status == "ancorado" then
					usetool()
					buso()
					ken()
					hao()
					_G.allowCombat = true
					local LtE8 = 12483
					click()
					autoskill()
					handleOpeMethod()
				end
				return true
			end
		end

		if phase == "all" or phase == "galleon" then
			removeFarmFix()
			_G.currentEventName = "None"
			_G.currentEventHealth = 0
			_G.currentEventMaxHealth = 0
			_G.seaEventActive = false
			stopSeaEventBypass()
		end
		return false
	end

	local function checkSea3Events(phase)
		phase = phase or "all"
		local wantsMajor = phase == "all" or phase == "major"
		local wantsSerpent = phase == "all" or phase == "serpent"
		local wantsGalleon = phase == "all" or phase == "galleon"
		if _G.isLootingChests and wantsGalleon then
			stopSeaEventBypass()
			return true
		end

		if not isPlayerAlive() then
			stopSeaEventBypass()
			_G.seaEventActive = false
			_G.currentEventName = "Dead - Waiting..."
			_G.currentEventHealth = 0
			_G.currentEventMaxHealth = 0
			return false
		end

		local function attackMob(mob, eventName)
			if not mob or not isValidMob(mob) then
				return false
			end
			if
				_G._GenesisAbyssalAcquisition
				and _G._GenesisAbyssalAcquisition.locator
				and type(_G._stopAbyssalAcquisition) == "function"
			then
				_G._stopAbyssalAcquisition()
			end
			removeFarmFix()
			_G.currentEventName = eventName
			_G.currentEventHealth = mob.Humanoid.Health
			_G.currentEventMaxHealth = mob.Humanoid.MaxHealth
			_G.seaEventActive = true
			local status = updatePosition(mob)
			if status == "ancorado" then
				usetool()
				buso()
				ken()
				hao()
				_G.allowCombat = true
				local YenJ = {}
				YenJ[685] = 142
				click()
				local aGK9 = nil
				if aGK9 then
					aGK9 = 301
				end
				autoskill()
				handleOpeMethod()
			end
			return true
		end

		local function findMobByType(typePattern)
			if Workspace.Monster:FindFirstChild("Boss") then
				for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
					if string.find(child.Name, typePattern) and isValidMob(child) then
						return child
					end
				end
			end
			for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
				if string.find(monster.Name, typePattern) and isValidMob(monster) then
					return monster
				end
			end
			return nil
		end

		local function findAbyssalTyrant()
			local monster = Workspace:FindFirstChild("Monster")
			local boss = monster and monster:FindFirstChild("Boss")
			local seaMonster = Workspace:FindFirstChild("SeaMonster")
			if boss then
				for _, child in pairs(boss:GetChildren()) do
					if
						string.find(child.Name, "SeaDragon", 1, true)
						and not string.find(child.Name, "ThirdSeaDragon", 1, true)
						and isValidMob(child)
					then
						return child
					end
				end
			end
			if seaMonster then
				for _, child in pairs(seaMonster:GetChildren()) do
					if
						string.find(child.Name, "SeaDragon", 1, true)
						and not string.find(child.Name, "ThirdSeaDragon", 1, true)
						and isValidMob(child)
					then
						return child
					end
				end
			end
			return nil
		end

		if wantsSerpent and GetSetting("autoHuntSerpent") then
			local serpent = findMobByType("Serpent")
			if serpent then
				return attackMob(serpent, "Serpent")
			end
		end

		if wantsGalleon and GetSetting("autoKillGalleons") then
			for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
				if string.find(monster.Name, "Galleon") and isValidMob(monster) then
					return attackMob(monster, monster.Name)
				end
			end
		end

		if wantsMajor and GetSetting("autoKillKraken") then
			local kraken = findMobByType("Tentacle") or findMobByType("FuryTentacle")
			if kraken then
				return attackMob(kraken, "Kraken")
			end
		end

		if wantsMajor and GetSetting("autoKillDrakenfyr") then
			local drakenfyr = findMobByType("ThirdSeaDragon")
			if drakenfyr then
				return attackMob(drakenfyr, "Drakenfyr")
			end
		end

		if wantsMajor then
			if GetSetting("autoKillAbyssalTyrant") then
				local abyssal = findAbyssalTyrant()
				if abyssal then
					return attackMob(abyssal, "Abyssal Tyrant")
				end

				-- The boss model is deliberately absent until a player approaches the
				-- globally replicated compass marker. The marker itself is authoritative;
				-- Legacy Pose only toggles the compass UI that renders it.
				local acquisition = _G._GenesisAbyssalAcquisition
				local locator, locatorCFrame = nil, nil
				local now = os.clock()
				if type(acquisition) == "table" then
					if acquisition.locator and acquisition.locator.Parent and now < acquisition.nextLocatorCheckAt then
						locator = acquisition.locator
						locatorCFrame = acquisition.locatorCFrame
					elseif now >= acquisition.nextLocatorCheckAt then
						acquisition.nextLocatorCheckAt = now + acquisition.locatorPollInterval
						locator, locatorCFrame = _G._GenesisFindAbyssalLocator()
					end
				end
				if locator then
					return _G._GenesisApproachAbyssalLocator(locator, locatorCFrame)
				end
				if acquisition and acquisition.locator and type(_G._stopAbyssalAcquisition) == "function" then
					_G._stopAbyssalAcquisition()
				end
			else
				if type(_G._stopAbyssalAcquisition) == "function" then
					_G._stopAbyssalAcquisition()
				end
			end
		end

		if wantsMajor and GetSetting("autoKillDeepseaCrusher") then
			local deepsea = findMobByType("ThirdSeaEldritch") or findMobByType("Crab") or findMobByType("Eldritch")
			if deepsea then
				return attackMob(deepsea, "Deepsea Crusher")
			end
		end

		if phase == "all" or phase == "galleon" then
			stopSeaEventBypass()
			_G.seaEventActive = false
			_G.currentEventName = "None"
			_G.currentEventHealth = 0
			_G.currentEventMaxHealth = 0
		end
		return false
	end

	_G._GenesisFindRaceIsland = function()
		local islandFolder = Workspace:FindFirstChild("Island")
		if not islandFolder then
			return nil, nil, nil
		end
		for _, island in ipairs(islandFolder:GetChildren()) do
			local name = island.Name
			local isRaceIsland =
				string.find(name, "Human")
				or string.find(name, "Animal")
				or string.find(name, "Fish")
				or string.find(name, "Sky")
				or string.find(name, "Demon")
				or string.find(name, "Angel")
				or string.find(name, "Gale")
				or string.find(name, "SeaKing")
			if isRaceIsland then
				local part = island:IsA("BasePart") and island or nil
				if not part then
					local elevator = island:FindFirstChild("Elevator", true)
					if elevator and elevator:IsA("BasePart") then
						part = elevator
					end
				end
				if not part then
					local meshPart = island:FindFirstChild("MeshPart", true)
					if meshPart and meshPart:IsA("BasePart") then
						part = meshPart
					end
				end
				part = part or island:FindFirstChildWhichIsA("BasePart", true)
				local baseCFrame = nil
				if part and part:IsA("BasePart") then
					baseCFrame = part.CFrame
				elseif island:IsA("Model") then
					local ok, pivot = pcall(island.GetPivot, island)
					baseCFrame = ok and pivot or nil
				end
				if typeof(baseCFrame) == "CFrame" then
					local yOffset = string.find(name, "Gale") and 1000 or 26
					local destination = baseCFrame * CFrame.new(0, yOffset, 0)
					local position = destination.Position
					if
						position.X == position.X
						and position.Y == position.Y
						and position.Z == position.Z
						and math.abs(position.X) < 10000000
						and math.abs(position.Y) < 10000000
						and math.abs(position.Z) < 10000000
					then
						return island, destination, getDisplayRaceName(name)
					end
				end
			end
		end
		return nil, nil, nil
	end

	_G._GenesisTeleportToRaceIsland = function()
		if game.PlaceId ~= 15759515082 then
			return false, "Race Islands are only available in the Third Sea."
		end
		local committed = _G._GenesisUpdateDungeonCommit()
		if committed then
			return false, "A dungeon currently owns movement."
		end
		local island, destination, displayName = _G._GenesisFindRaceIsland()
		if not island or typeof(destination) ~= "CFrame" then
			return false, "No Race Island is currently available."
		end
		if _G.isFishing or _G.fishingToolCaptured then
			stopFishing()
		end
		removeFarmFix()
		stopSeaEventBypass()
		if removeConquestPosition then
			removeConquestPosition()
		end
		local root = GetRoot(LocalPlayer.Character)
		if not root then
			return false, "Character root is unavailable."
		end
		local moved = pcall(function()
			root.CFrame = destination
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
		if not moved then
			return false, "Race Island teleport failed."
		end
		_G.currentRaceIsland = island.Name
		return true, displayName
	end

	local function checkSeaEvents(phase)
		phase = phase or "all"

		local foundEvent = false

		if game.PlaceId == 4520749081 then
			foundEvent = checkSea1Events(phase)
		elseif game.PlaceId == 6381829480 then
			foundEvent = checkSea2Events(phase)
		elseif game.PlaceId == 15759515082 then
			foundEvent = checkSea3Events(phase)
		end

		if foundEvent then
			_G.lastEventCheck = tick()
		end

		return foundEvent
	end
	_G._GenesisCheckSeaEvents = checkSeaEvents

	local _originalKeyboard = keyboard
	keyboard = function(key)
		if _seaEventLockPosition then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local currentCF = root.CFrame
				_originalKeyboard(key)
				task.wait()
				root.CFrame = currentCF
				return
			end
		end
		_originalKeyboard(key)
	end

	local _originalClick = click
	click = function()
		if _seaEventLockPosition then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local currentCF = root.CFrame
				_originalClick()
				task.wait()
				root.CFrame = currentCF
				return
			end
		end
		_originalClick()
	end

	_G._GenesisMaterialShopState = {
		initialized = false,
		initializing = false,
		initAttempts = 0,
		initSuccesses = 0,
		initFailures = 0,
		purchaseAttempts = 0,
		purchaseInvokeSuccesses = 0,
		purchaseInvokeFailures = 0,
		lastInitAttemptAt = 0,
		lastInitSuccessAt = 0,
		nextInitAttemptAt = 0,
		purchaseAllowedAt = 0,
		lastInitResponseType = nil,
		lastInitResponse = nil,
		lastPurchaseResponseType = nil,
		lastPurchaseResponse = nil,
		lastError = nil,
		initGeneration = 0,
		keepGuiOpen = false,
		autoHiddenGui = false,
	}

	_G._GenesisSetMaterialShopGuiVisible = function(visible)
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local shopGui = playerGui and playerGui:FindFirstChild("Material Dealer")
		if not shopGui then
			return false
		end
		if shopGui:IsA("LayerCollector") then
			shopGui.Enabled = visible == true
		elseif shopGui:IsA("GuiObject") then
			shopGui.Visible = visible == true
		else
			return false
		end
		return true
	end

	_G._GenesisEnsureMaterialShopReady = function(force, keepGuiOpen)
		local state = _G._GenesisMaterialShopState
		if type(state) ~= "table" then
			return false, "Material Dealer state is unavailable"
		end

		local now = tick()
		if state.initializing then
			return false, "Material Dealer initialization is already in progress"
		end
		if not force and state.initialized and now - (state.lastInitSuccessAt or 0) < 21600 then
			return true, state.lastInitResponse
		end
		if not force and now < (state.nextInitAttemptAt or 0) then
			return false, state.lastError or "Material Dealer initialization is waiting to retry"
		end

		state.initializing = true
		state.initAttempts = (state.initAttempts or 0) + 1
		state.initGeneration = (state.initGeneration or 0) + 1
		state.keepGuiOpen = keepGuiOpen == true
		state.autoHiddenGui = false
		local initGeneration = state.initGeneration
		state.lastInitAttemptAt = now
		local ok, response = pcall(function()
			return ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("SpecialShopGui", {
				GuiName = "Material Dealer",
			})
		end)
		state.initializing = false

		if not ok or response == false then
			state.initialized = false
			state.initFailures = (state.initFailures or 0) + 1
			state.lastError = not ok and tostring(response) or "Material Dealer initialization was rejected"
			state.nextInitAttemptAt = tick() + 10
			warn("[GENESIS HUB] Material Dealer initialization failed: " .. state.lastError)
			return false, state.lastError
		end

		state.initialized = true
		state.initSuccesses = (state.initSuccesses or 0) + 1
		state.lastInitSuccessAt = tick()
		state.nextInitAttemptAt = 0
		state.purchaseAllowedAt = state.lastInitSuccessAt + 0.75
		state.lastInitResponseType = typeof(response)
		state.lastInitResponse = response == nil and "<nil>" or tostring(response)
		state.lastError = nil
		if state.keepGuiOpen then
			_G._GenesisSetMaterialShopGuiVisible(true)
		else
			task.spawn(function()
				for _ = 1, 20 do
					if _G._GenesisMaterialShopState ~= state
						or state.initGeneration ~= initGeneration
						or state.keepGuiOpen
					then
						return
					end
					if _G._GenesisSetMaterialShopGuiVisible(false) then
						state.autoHiddenGui = true
						return
					end
					task.wait(0.1)
				end
			end)
		end
		print("[GENESIS HUB] Material Dealer initialized; automatic purchases are ready.")
		return true, response
	end

	spawn(function()
		-- MaterialDealer is a server invoke; polling it every frame can flood the
		-- remote and starve other automation. One purchase pass per second is enough
		-- because each request already carries the requested stack count.
		while task.wait(1) do
			pcall(function()
				if not GetSetting("autoBuyMaterials") then
					return
				end

				local materials = GetSetting("selectedMaterials")
				local count = GetSetting("materialBuyCount") or 1

				if not materials or #materials == 0 then
					return
				end

				local ready = _G._GenesisEnsureMaterialShopReady(false, false)
				local dealerState = _G._GenesisMaterialShopState
				if not ready or tick() < (dealerState.purchaseAllowedAt or 0) then
					return
				end

				for _, materialName in pairs(materials) do
					dealerState.purchaseAttempts = (dealerState.purchaseAttempts or 0) + 1
					local ok, response = pcall(function()
						return ReplicatedStorage.Chest.Remotes.Functions.MaterialDealer:InvokeServer("Buy", {
							MaterialName = materialName,
							Stacks = count,
						})
					end)
					dealerState.lastPurchaseResponseType = ok and typeof(response) or "error"
					dealerState.lastPurchaseResponse = response == nil and "<nil>" or tostring(response)
					if ok then
						dealerState.purchaseInvokeSuccesses = (dealerState.purchaseInvokeSuccesses or 0) + 1
					else
						dealerState.purchaseInvokeFailures = (dealerState.purchaseInvokeFailures or 0) + 1
						dealerState.lastError = tostring(response)
						dealerState.initialized = false
						dealerState.nextInitAttemptAt = tick() + 10
						warn("[GENESIS HUB] Material Dealer purchase invoke failed: " .. dealerState.lastError)
						break
					end
					task.wait(0.1)
				end
			end)
		end
	end)

	function c_lv()
		local mylv = LocalPlayer.PlayerStats.lvl.Value

		if game.PlaceId == 15759515082 then
			if mylv >= 4000 and mylv <= 4049 then
				_G.NameMob, _G.NameQuest = 4000, "Kill 4 Deep Diver"
				_G.MZ, _G.MY, _G.MX = 1015, 47, 1674
			elseif mylv >= 4050 and mylv <= 4099 then
				_G.NameMob, _G.NameQuest = 4050, "Kill Fugitive"
				_G.MZ, _G.MY, _G.MX = 993, 35, 2888
			elseif mylv >= 4100 and mylv <= 4149 then
				_G.NameMob, _G.NameQuest = 4100, "Kill 4 Deep one Villager"
				_G.MZ, _G.MY, _G.MX = 671, 316, 3299
			elseif mylv >= 4150 and mylv <= 4199 then
				_G.NameMob, _G.NameQuest = 4150, "Kill 6 Fishman Guardian"
				local RAHD = 3845
				_G.MZ, _G.MY, _G.MX = 86, 66, 1786
			elseif mylv >= 4200 and mylv <= 4249 then
				_G.NameMob, _G.NameQuest = 4200, "Kill The deep one"
				_G.MZ, _G.MY, _G.MX = 136, 35, 2833
			elseif mylv >= 4250 and mylv <= 4299 then
				_G.NameMob, _G.NameQuest = 4250, "Kill Fishman King's Guard"
				_G.MZ, _G.MY, _G.MX = -457, 125, 1934
			elseif mylv >= 4300 and mylv <= 4324 then
				_G.NameMob, _G.NameQuest = 4300, "Kill 5 Jungle Gorilla"
				_G.MZ, _G.MY, _G.MX = 9081, 181, 4215
			elseif mylv >= 4325 and mylv <= 4349 then
				_G.NameMob, _G.NameQuest = 4325, "Kill 5 Wilderness Gorilla"
				_G.MZ, _G.MY, _G.MX = 9876, 45, 4865
			elseif mylv >= 4350 and mylv <= 4374 then
				_G.NameMob, _G.NameQuest = 4350, "Kill 5 Jungle Ape"
				_G.MZ, _G.MY, _G.MX = 9640, 45, 5307
			elseif mylv >= 4375 and mylv <= 4399 then
				_G.NameMob, _G.NameQuest = 4375, "Kill 1 Cyborg Gorilla"
				_G.MZ, _G.MY, _G.MX = 9463, 45, 5784
			elseif mylv >= 4400 and mylv <= 4449 then
				_G.NameMob, _G.NameQuest = 4400, "Kill 1 Ripcurrent Raider"
				_G.MZ, _G.MY, _G.MX = -8673, 26, -506
			elseif mylv >= 4450 and mylv <= 4499 then
				_G.NameMob, _G.NameQuest = 4450, "Kill 1 Tidal Warrior"
				_G.MZ, _G.MY, _G.MX = -8404, 96, -73
			elseif mylv >= 4500 and mylv <= 4549 then
				_G.NameMob, _G.NameQuest = 4500, "Kill 1 Ocean Gladiator"
				_G.MZ, _G.MY, _G.MX = -9066, 44, -22
			elseif mylv >= 4550 and mylv <= 4599 then
				_G.NameMob, _G.NameQuest = 4550, "Kill 4 Deepfire Combatant"
				_G.MZ, _G.MY, _G.MX = 171, 26, -5174
			elseif mylv >= 4600 and mylv <= 4649 then
				_G.NameMob, _G.NameQuest = 4600, "Kill 1 Electro Abyss Warrior"
				local rBIR = {}
				rBIR[527] = 488
				_G.MZ, _G.MY, _G.MX = 964, 22, -5230
			elseif mylv >= 4650 and mylv <= 4699 then
				_G.NameMob, _G.NameQuest = 4650, "Kill 1 Inferno Diver"
				_G.MZ, _G.MY, _G.MX = 467, 54, -6044
			elseif mylv >= 4700 and mylv <= 4749 then
				_G.NameMob, _G.NameQuest = 4700, "Kill 1 Tempest Tidebreaker"
				_G.MZ, _G.MY, _G.MX = 469, 42, -7296
			elseif mylv >= 4750 and mylv <= 4799 then
				_G.NameMob, _G.NameQuest = 4750, "Kill 1 Abyssal Swordsman"
				_G.MZ, _G.MY, _G.MX = 455, 186, -8255
			elseif mylv >= 4800 and mylv <= 4849 then
				_G.NameMob, _G.NameQuest = 4825, "Kill 4 Rogue Prisoner"
				_G.MZ, _G.MY, _G.MX = 478, 78, 10931
			elseif mylv >= 4850 and mylv <= 4874 then
				_G.NameMob, _G.NameQuest = 4850, "Kill 4 Prisoner Buccaneer"
				_G.MZ, _G.MY, _G.MX = 253, 125, 11731
			elseif mylv >= 4875 and mylv <= 4999 then
				_G.NameMob, _G.NameQuest = 4875, "Kill 1 Prisoner of Gravity"
				_G.MZ, _G.MY, _G.MX = 1052, 79, 12436
			elseif mylv >= 5000 and mylv <= 5049 then
				_G.NameMob, _G.NameQuest = 5000, "Kill 8 Obsidian Seeker"
				_G.MZ, _G.MY, _G.MX = 11892, 170, -7452
			elseif mylv >= 5050 and mylv <= 5099 then
				_G.NameMob, _G.NameQuest = 5050, "Kill 8 Forgotten Delver"
				_G.MZ, _G.MY, _G.MX = 10452, 214, -8558
			elseif mylv >= 5100 and mylv <= 5149 then
				_G.NameMob, _G.NameQuest = 5100, "Kill 8 Blackreach Scout"
				local jzKw = 8981
				_G.MZ, _G.MY, _G.MX = 12633, 169, -8194
			elseif mylv >= 5150 and mylv <= 5199 then
				_G.NameMob, _G.NameQuest = 5150, "Kill 1 Nightbound Explorer"
				_G.MZ, _G.MY, _G.MX = 11346, 243, -8636
			elseif mylv >= 5200 and mylv <= 5249 then
				_G.NameMob, _G.NameQuest = 5200, "Kill 8 Ruinstep Nomad"
				_G.MZ, _G.MY, _G.MX = 13191, 79, -9069
			elseif mylv >= 5250 and mylv <= 5299 then
				_G.NameMob, _G.NameQuest = 5250, "Kill 1 Ancient Wayfarer"
				_G.MZ, _G.MY, _G.MX = 11675, 80, -9065
			elseif mylv >= 5300 and mylv <= 5349 then
				_G.NameMob, _G.NameQuest = 5300, "Kill 8 Depths Voyager"
				_G.MZ, _G.MY, _G.MX = 12381, 107, -10122
			elseif mylv >= 5350 and mylv <= 5399 then
				_G.NameMob, _G.NameQuest = 5350, "Kill 1 Allosaurus"
				_G.MZ, _G.MY, _G.MX = 12067, 187, -10678
			elseif mylv >= 5400 then
				_G.NameMob, _G.NameQuest = 5400, "Kill 1 Spinosaurus"
				_G.MZ, _G.MY, _G.MX = 10257, 177, -10717
			end
		elseif game.PlaceId == 6381829480 then
			if mylv >= 2250 and mylv <= 2299 then
				_G.NameMob, _G.NameQuest = 2250, "Kill 4 Beast Pirates"
				_G.MZ, _G.MY, _G.MX = 113, 57, -4114
			elseif mylv >= 2300 and mylv <= 2349 then
				_G.NameMob, _G.NameQuest = 2300, "Kill 4 Beast Swordman"
				_G.MZ, _G.MY, _G.MX = -268, 98, -4092
			elseif mylv >= 2350 and mylv <= 2399 then
				_G.NameMob, _G.NameQuest = 2350, "Kill 1 Gazelle Man"
				_G.MZ, _G.MY, _G.MX = 252, 57, -4363
			elseif mylv >= 2400 and mylv <= 2449 then
				_G.NameMob, _G.NameQuest = 2400, "Kill 4 Bandit Beast Pirates"
				_G.MZ, _G.MY, _G.MX = -1015, 176, -4344
			elseif mylv >= 2450 and mylv <= 2499 then
				_G.NameMob, _G.NameQuest = 2450, "Kill 4 Powerful Beast Pirates"
				_G.MZ, _G.MY, _G.MX = -851, 136, -4656
			elseif mylv >= 2500 and mylv <= 2549 then
				_G.NameMob, _G.NameQuest = 2500, "Kill 1 Violet Samurai"
				_G.MZ, _G.MY, _G.MX = -1007, 105, -4969
			elseif mylv >= 2550 and mylv <= 2599 then
				_G.NameMob, _G.NameQuest = 2550, "Kill 1 Duke"
				_G.MZ, _G.MY, _G.MX = -228, 100, -5434
			elseif mylv >= 2600 and mylv <= 2649 then
				_G.NameMob, _G.NameQuest = 2600, "Kill 1 Magician"
				_G.MZ, _G.MY, _G.MX = -154, 105, -5048
			elseif mylv >= 2650 and mylv <= 2699 then
				_G.NameMob, _G.NameQuest = 2650, "Kill 1 Kitsune Samurai"
				_G.MZ, _G.MY, _G.MX = 16, 100, -5452
			elseif mylv >= 2700 and mylv <= 2749 then
				_G.NameMob, _G.NameQuest = 2700, "Kill 4 Elite Beast Pirates"
				local CmD6 = nil
				if CmD6 then
					CmD6 = 592
				end
				_G.MZ, _G.MY, _G.MX = 1380, 73, -4564
			elseif mylv >= 2750 and mylv <= 2799 then
				_G.NameMob, _G.NameQuest = 2750, "Kill 1 Bear Man"
				_G.MZ, _G.MY, _G.MX = 775, 53, -4438
			elseif mylv >= 2800 and mylv <= 2849 then
				_G.NameMob, _G.NameQuest = 2800, "Kill 1 Bean"
				_G.MZ, _G.MY, _G.MX = 904, 68, -4018
			elseif mylv >= 2850 and mylv <= 2899 then
				_G.NameMob, _G.NameQuest = 2850, "Kill 1 Meji"
				_G.MZ, _G.MY, _G.MX = 1163, 83, -5302
			elseif mylv >= 2900 and mylv <= 2949 then
				_G.NameMob, _G.NameQuest = 2900, "Kill 1 Petra"
				_G.MZ, _G.MY, _G.MX = 1308, 80, -5857
			elseif mylv >= 2950 and mylv <= 2999 then
				_G.NameMob, _G.NameQuest = 2950, "Kill 1 Kappa"
				_G.MZ, _G.MY, _G.MX = 1926, 109, -4853
			elseif mylv >= 3000 and mylv <= 3049 then
				_G.NameMob, _G.NameQuest = 3000, "Kill 1 Joey"
				_G.MZ, _G.MY, _G.MX = 2066, 57, -5287
			elseif mylv >= 3050 and mylv <= 3099 then
				_G.NameMob, _G.NameQuest = 3050, "Kill 4 Skull Pirates"
				_G.MZ, _G.MY, _G.MX = 6907, 78, -6400
			elseif mylv >= 3100 and mylv <= 3124 then
				_G.NameMob, _G.NameQuest = 3100, "Kill 1 Elite Skeleton"
				_G.MZ, _G.MY, _G.MX = 7183, 98, -5926
			elseif mylv >= 3125 and mylv <= 3149 then
				_G.NameMob, _G.NameQuest = 3125, "Kill 1 Desert Thief"
				_G.MZ, _G.MY, _G.MX = 1513, 53, 1575
			elseif mylv >= 3150 and mylv <= 3174 then
				_G.NameMob, _G.NameQuest = 3150, "Kill 1 Anubis"
				_G.MZ, _G.MY, _G.MX = 899, 48, 1964
			elseif mylv >= 3175 and mylv <= 3199 then
				_G.NameMob, _G.NameQuest = 3175, "Kill 1 Pharaoh"
				_G.MZ, _G.MY, _G.MX = 1632, 49, 2048
			elseif mylv >= 3200 and mylv <= 3224 then
				_G.NameMob, _G.NameQuest = 3200, "Kill 4 Chess Soldiers"
				_G.MZ, _G.MY, _G.MX = 8164, 77, -7
			elseif mylv >= 3225 and mylv <= 3249 then
				_G.NameMob, _G.NameQuest = 3225, "Kill 1 Sunken Vessel"
				_G.MZ, _G.MY, _G.MX = 8169, 83, -986
			elseif mylv >= 3250 and mylv <= 3274 then
				_G.NameMob, _G.NameQuest = 3250, "Kill 1 Biscuit Man"
				_G.MZ, _G.MY, _G.MX = 8860, 202, -1375
			elseif mylv >= 3275 and mylv <= 3299 then
				_G.NameMob, _G.NameQuest = 3275, "Kill 1 Dough Master"
				_G.MZ, _G.MY, _G.MX = 93598, 106, 30370
			elseif mylv >= 3300 and mylv <= 3324 then
				_G.NameMob, _G.NameQuest = 3300, "Kill 4 Azlan"
				local QJic = (function()
					return 387
				end)()
				_G.MZ, _G.MY, _G.MX = -2860, 69, -832
			elseif mylv >= 3325 and mylv <= 3399 then
				_G.NameMob, _G.NameQuest = 3325, "Kill 4 The Volcano"
				do
					local fJps = 172
					fJps = fJps + 0
				end
				_G.MZ, _G.MY, _G.MX = -3579, 173, -152
			elseif mylv >= 3400 and mylv <= 3424 then
				_G.NameMob, _G.NameQuest = 3400, "Kill 4 Dark Beard Servant"
				_G.MZ, _G.MY, _G.MX = -4629, 94, -9156
			elseif mylv >= 3425 and mylv <= 3449 then
				_G.NameMob, _G.NameQuest = 3425, "Kill 1 Supreme Swordman"
				_G.MZ, _G.MY, _G.MX = -4483, 114, -9647
			elseif mylv >= 3450 and mylv <= 3499 then
				_G.NameMob, _G.NameQuest = 3450, "Kill 1 Sally"
				_G.MZ, _G.MY, _G.MX = -5374, 135, -9584
			elseif mylv >= 3500 and mylv <= 3524 then
				_G.NameMob, _G.NameQuest = 3500, "Kill 5 Vice Admiral"
				_G.MZ, _G.MY, _G.MX = 421, 87, -9993
			elseif mylv >= 3525 and mylv <= 3549 then
				_G.NameMob, _G.NameQuest = 3525, "Kill 1 Pondere"
				_G.MZ, _G.MY, _G.MX = 1298, 100, -10142
			elseif mylv >= 3550 and mylv <= 3599 then
				_G.NameMob, _G.NameQuest = 3550, "Kill 1 Hefty"
				_G.MZ, _G.MY, _G.MX = 969, 84, -10489
			elseif mylv >= 3600 and mylv <= 3624 then
				_G.NameMob, _G.NameQuest = 3600, "Kill 6 Fiore Gladiator"
				_G.MZ, _G.MY, _G.MX = -2782, 133, 5450
			elseif mylv >= 3625 and mylv <= 3649 then
				_G.NameMob, _G.NameQuest = 3625, "Kill 6 Fiore Fighter"
				_G.MZ, _G.MY, _G.MX = -2559, 87, 5466
			elseif mylv >= 3650 and mylv <= 3674 then
				_G.NameMob, _G.NameQuest = 3650, "Kill 7 Fiore Pirate"
				_G.MZ, _G.MY, _G.MX = -2905, 134, 6095
			elseif mylv >= 3675 and mylv <= 3699 then
				_G.NameMob, _G.NameQuest = 3675, "Kill 1 Lomeo"
				_G.MZ, _G.MY, _G.MX = -2135, 72, 6487
			elseif mylv >= 3700 and mylv <= 3724 then
				_G.NameMob, _G.NameQuest = 3700, "Kill 1 Prince Aria"
				_G.MZ, _G.MY, _G.MX = -3794, 150, 6785
			elseif mylv >= 3725 and mylv <= 3774 then
				_G.NameMob, _G.NameQuest = 3725, "Kill 1 Devastate"
				_G.MZ, _G.MY, _G.MX = -2644, 122, 7632
			elseif mylv >= 3775 and mylv <= 3799 then
				_G.NameMob, _G.NameQuest = 3775, "Kill 1 Floffy"
				_G.MZ, _G.MY, _G.MX = -2529, 462, 7865
			elseif mylv >= 3800 and mylv <= 3849 then
				_G.NameMob, _G.NameQuest = 3800, "Kill 4 Dead Troupe"
				_G.MZ, _G.MY, _G.MX = -4292, 93, 9716
			elseif mylv >= 3850 and mylv <= 3974 then
				_G.NameMob, _G.NameQuest = 3850, "Kill 4 Dead Troupe Captain"
				_G.MZ, _G.MY, _G.MX = -3947, 102, 10021
			elseif mylv >= 3975 then
				_G.NameMob, _G.NameQuest = 3975, "Kill 1 Ryu"
				_G.MZ, _G.MY, _G.MX = -4856, 86, 9927
			end
		else
			if mylv >= 1 and mylv <= 9 then
				_G.NameMob, _G.NameQuest = 1, "Kill 4 Soldiers"
				_G.MZ, _G.MY, _G.MX = -4489, 50, -1860
			elseif mylv >= 10 and mylv <= 19 then
				_G.NameMob, _G.NameQuest = 10, "Kill 5 Clown Pirates"
				_G.MZ, _G.MY, _G.MX = -4489, 50, -1860
			elseif mylv >= 20 and mylv <= 29 then
				_G.NameMob, _G.NameQuest = 20, "Kill 1 Smoky"
				_G.MZ, _G.MY, _G.MX = -4686, 99, -2065
			elseif mylv >= 30 and mylv <= 49 then
				_G.NameMob, _G.NameQuest = 30, "Kill 1 Tashi"
				_G.MZ, _G.MY, _G.MX = -4548, 109, -2270
			elseif mylv >= 50 and mylv <= 74 then
				_G.NameMob, _G.NameQuest = 50, "Kill 6 Clown Swordman"
				_G.MZ, _G.MY, _G.MX = -3546, 97, -764
			elseif mylv >= 75 and mylv <= 99 then
				_G.NameMob, _G.NameQuest = 75, "Kill 1 The Clown"
				local TPgR = function(zM1Y)
					return zM1Y
				end
				TPgR = TPgR
				_G.MZ, _G.MY, _G.MX = -3436, 114, -397
			elseif mylv >= 100 and mylv <= 119 then
				_G.NameMob, _G.NameQuest = 100, "Kill 4 Commander"
				_G.MZ, _G.MY, _G.MX = -2549, 92, -2122
			elseif mylv >= 120 and mylv <= 144 then
				_G.NameMob, _G.NameQuest = 120, "Kill 1 Captain"
				_G.MZ, _G.MY, _G.MX = -2549, 92, -2122
			elseif mylv >= 145 and mylv <= 179 then
				_G.NameMob, _G.NameQuest = 145, "Kill 1 The Barbaric"
				_G.MZ, _G.MY, _G.MX = -2419, 139, -2375
			elseif mylv >= 180 and mylv <= 199 then
				_G.NameMob, _G.NameQuest = 180, "Kill 4 Fighter Fishmans"
				_G.MZ, _G.MY, _G.MX = -1422, 52, -856
			elseif mylv >= 200 and mylv <= 229 then
				_G.NameMob, _G.NameQuest = 200, "Kill 1 Karate Fishman"
				_G.MZ, _G.MY, _G.MX = -1422, 52, -856
			elseif mylv >= 230 and mylv <= 249 then
				_G.NameMob, _G.NameQuest = 230, "Kill 1 Shark Man"
				_G.MZ, _G.MY, _G.MX = -1493, 56, -666
			elseif mylv >= 250 and mylv <= 299 then
				_G.NameMob, _G.NameQuest = 250, "Kill 4 Trainer Chef"
				_G.MZ, _G.MY, _G.MX = -2899, 162, -4217
			elseif mylv >= 300 and mylv <= 349 then
				_G.NameMob, _G.NameQuest = 300, "Kill 1 Dark Leg"
				_G.MZ, _G.MY, _G.MX = -2899, 162, -4217
			elseif mylv >= 350 and mylv <= 399 then
				_G.NameMob, _G.NameQuest = 350, "Kill 1 Dory"
				do
					local N1P7 = 26
					N1P7 = N1P7 + 0
				end
				_G.MZ, _G.MY, _G.MX = -2899, 162, -4217
			elseif mylv >= 400 and mylv <= 449 then
				_G.NameMob, _G.NameQuest = 400, "Kill 5 Snow Soldier"
				_G.MZ, _G.MY, _G.MX = -1275, 65, -5310
			elseif mylv >= 450 and mylv <= 499 then
				_G.NameMob, _G.NameQuest = 450, "Kill 1 King Snow"
				_G.MZ, _G.MY, _G.MX = -1557, 40, -5519
			elseif mylv >= 500 and mylv <= 524 then
				_G.NameMob, _G.NameQuest = 500, "Kill 1 Little Dear"
				_G.MZ, _G.MY, _G.MX = -1104, 55, -5467
			elseif mylv >= 525 and mylv <= 574 then
				_G.NameMob, _G.NameQuest = 525, "Kill 1 Candle Man"
				_G.MZ, _G.MY, _G.MX = -602, 92, -2956
			elseif mylv >= 575 and mylv <= 624 then
				_G.NameMob, _G.NameQuest = 575, "Kill 4 Sand Bandit"
				_G.MZ, _G.MY, _G.MX = -777, 73, -2750
			elseif mylv >= 625 and mylv <= 674 then
				_G.NameMob, _G.NameQuest = 625, "Kill 1 Bomb Man"
				_G.MZ, _G.MY, _G.MX = -602, 92, -2956
			elseif mylv >= 675 and mylv <= 724 then
				_G.NameMob, _G.NameQuest = 675, "Kill 4 Desert Marauder"
				_G.MZ, _G.MY, _G.MX = -777, 73, -2750
			elseif mylv >= 725 and mylv <= 799 then
				_G.NameMob, _G.NameQuest = 725, "Kill 1 King of Sand"
				_G.MZ, _G.MY, _G.MX = -545, 92, -3021
			elseif mylv >= 800 and mylv <= 849 then
				_G.NameMob, _G.NameQuest = 800, "Kill 4 Sky Soldier"
				do
					local SMHw = 875
					SMHw = SMHw + 0
				end
				_G.MZ, _G.MY, _G.MX = 1151, 222, -4589
			elseif mylv >= 850 and mylv <= 899 then
				_G.NameMob, _G.NameQuest = 850, "Kill 1 Ball Man"
				local uYEd = function(TWi5)
					return TWi5
				end
				uYEd = uYEd
				_G.MZ, _G.MY, _G.MX = 1443, 504, -4598
			elseif mylv >= 900 and mylv <= 949 then
				_G.NameMob, _G.NameQuest = 900, "Kill 4 Cloud Warrior"
				_G.MZ, _G.MY, _G.MX = 1151, 222, -4589
			elseif mylv >= 950 and mylv <= 999 then
				_G.NameMob, _G.NameQuest = 950, "Kill 1 Rumble Man"
				_G.MZ, _G.MY, _G.MX = 1443, 504, -4598
			elseif mylv >= 1000 and mylv <= 1049 then
				_G.NameMob, _G.NameQuest = 1000, "Kill 4 Elite Soldiers"
				_G.MZ, _G.MY, _G.MX = 749, 12, 1897
			elseif mylv >= 1050 and mylv <= 1099 then
				_G.NameMob, _G.NameQuest = 1050, "Kill 4 High-class Soldier"
				_G.MZ, _G.MY, _G.MX = 749, 12, 1897
			elseif mylv >= 1100 and mylv <= 1149 then
				_G.NameMob, _G.NameQuest = 1100, "Kill 1 Leader"
				_G.MZ, _G.MY, _G.MX = 768, 52, 1813
			elseif mylv >= 1150 and mylv <= 1199 then
				_G.NameMob, _G.NameQuest = 1150, "Kill 1 Pasta"
				_G.MZ, _G.MY, _G.MX = 768, 52, 1813
			elseif mylv >= 1200 and mylv <= 1249 then
				_G.NameMob, _G.NameQuest = 1200, "Kill 4 Naval personnel"
				_G.MZ, _G.MY, _G.MX = 2148, 69, -1308
			elseif mylv >= 1250 and mylv <= 1299 then
				_G.NameMob, _G.NameQuest = 1250, "Kill 1 Wolf"
				_G.MZ, _G.MY, _G.MX = 2153, 69, -1301
			elseif mylv >= 1300 and mylv <= 1349 then
				_G.NameMob, _G.NameQuest = 1300, "Kill 1 Giraffe"
				_G.MZ, _G.MY, _G.MX = 1966, 20, -1077
			elseif mylv >= 1350 and mylv <= 1399 then
				_G.NameMob, _G.NameQuest = 1350, "Kill 4 Nautical soldier"
				_G.MZ, _G.MY, _G.MX = 2100, 69, -1204
			elseif mylv >= 1400 and mylv <= 1449 then
				_G.NameMob, _G.NameQuest = 1400, "Kill 4 Naval soldier"
				_G.MZ, _G.MY, _G.MX = 2585, 167, -1256
			elseif mylv >= 1450 and mylv <= 1499 then
				_G.NameMob, _G.NameQuest = 1450, "Kill 1 Leo"
				_G.MZ, _G.MY, _G.MX = 2531, 22, -1083
			elseif mylv >= 1500 and mylv <= 1549 then
				_G.NameMob, _G.NameQuest = 1500, "Kill 5 Zombies"
				_G.MZ, _G.MY, _G.MX = 4188, 16, -2789
			elseif mylv >= 1550 and mylv <= 1599 then
				_G.NameMob, _G.NameQuest = 1550, "Kill 4 Elite Zombies"
				_G.MZ, _G.MY, _G.MX = 4188, 16, -2789
			elseif mylv >= 1600 and mylv <= 1649 then
				_G.NameMob, _G.NameQuest = 1600, "Kill 4 Revenant"
				_G.MZ, _G.MY, _G.MX = 4319, 20, -2849
			elseif mylv >= 1650 and mylv <= 1699 then
				_G.NameMob, _G.NameQuest = 1650, "Kill 1 Shadow Master"
				_G.MZ, _G.MY, _G.MX = 4319, 20, -2849
			elseif mylv >= 1700 and mylv <= 1749 then
				_G.NameMob, _G.NameQuest = 1700, "Kill 4 New World Pirates"
				_G.MZ, _G.MY, _G.MX = -1587, 109, 2153
			elseif mylv >= 1750 and mylv <= 1799 then
				_G.NameMob, _G.NameQuest = 1750, "Kill 4 Cutlass Pirates"
				_G.MZ, _G.MY, _G.MX = -1982, 80, 2391
			elseif mylv >= 1800 and mylv <= 1849 then
				_G.NameMob, _G.NameQuest = 1800, "Kill 4 Rear Admirals"
				_G.MZ, _G.MY, _G.MX = -2228, 109, 2410
			elseif mylv >= 1850 and mylv <= 1924 then
				_G.NameMob, _G.NameQuest = 1850, "Kill 1 True Karate Fishman"
				_G.MZ, _G.MY, _G.MX = -1938, 103, 2471
			elseif mylv >= 1925 and mylv <= 1999 then
				_G.NameMob, _G.NameQuest = 1925, "Kill 1 Quake Woman"
				_G.MZ, _G.MY, _G.MX = -1908, 49, 2285
			elseif mylv >= 2000 and mylv <= 2049 then
				_G.NameMob, _G.NameQuest = 2000, "Kill 4 Fishmans"
				_G.MZ, _G.MY, _G.MX = 6198, 40, -1743
			elseif mylv >= 2050 and mylv <= 2099 then
				_G.NameMob, _G.NameQuest = 2050, "Kill 1 Combat Fishman"
				_G.MZ, _G.MY, _G.MX = 6236, 55, -1956
			elseif mylv >= 2100 and mylv <= 2149 then
				_G.NameMob, _G.NameQuest = 2100, "Kill 1 Sword Fishman"
				_G.MZ, _G.MY, _G.MX = 6688, 96, -1635
			elseif mylv >= 2150 and mylv <= 2199 then
				_G.NameMob, _G.NameQuest = 2150, "Kill 4 Soldier Fishman"
				_G.MZ, _G.MY, _G.MX = 6451, 40, -1801
			elseif mylv >= 2200 then
				_G.NameMob, _G.NameQuest = 2200, "Kill 1 Seasoned Fishman"
				_G.MZ, _G.MY, _G.MX = 6451, 40, -1801
			end
		end
	end

	function getMaterialQuest()
		local selectedMaterial = getCurrentSeaSelectedMaterial()
		local questName = ""
		if not selectedMaterial then
			return questName
		end

		if game.PlaceId == 15759515082 then
			if selectedMaterial == "Sea Artifact" then
				questName = "Kill 4 Deep Diver"
			elseif selectedMaterial == "Shark's Fin" then
				questName = "Kill 6 Fishman Guardian"
			elseif selectedMaterial == "Leather" then
				questName = "Kill 5 Wilderness Gorilla"
			elseif selectedMaterial == "Shark's Canine" then
				questName = "Kill 1 Ripcurrent Raider"
			elseif selectedMaterial == "Coral" then
				questName = "Kill Fugitive"
			elseif selectedMaterial == "Rusted Trident" then
				questName = "Kill 8 Obsidian Seeker"
			elseif selectedMaterial == "Pearl" then
				questName = "Kill Fugitive"
			end
		elseif game.PlaceId == 6381829480 then
			if selectedMaterial == "Rusted Scrap" then
				questName = "Kill 4 Beast Pirates"
			elseif selectedMaterial == "Iron" then
				questName = "Kill 4 Beast Pirates"
			elseif selectedMaterial == "Carrot" then
				questName = "Kill 4 Beast Pirates"
			elseif selectedMaterial == "Samurai Badge" then
				questName = "Kill 1 Violet Samurai"
			elseif selectedMaterial == "Bread Crumbs" then
				questName = "Kill 4 Chess Soldiers"
			elseif selectedMaterial == "Ice Crystal" then
				questName = "Kill 4 Azlan"
			elseif selectedMaterial == "Magma Crystal" then
				questName = "Kill 4 The Volcano"
			elseif selectedMaterial == "Lost Ruby" then
				questName = "Kill 1 Pharaoh"
			elseif selectedMaterial == "Pile of Bones" then
				questName = "Kill 4 Skull Pirates"
			elseif selectedMaterial == "Dragon's Orb" then
				questName = "Kill 1 Elite Skeleton"
			elseif selectedMaterial == "Lucidus's Totem" then
				questName = "Kill 5 Vice Admiral"
			elseif selectedMaterial == "Dark Beard's Totem" then
				questName = "Kill 1 Supreme Swordman"
			elseif selectedMaterial == "Essence of Fire" then
				questName = "Kill 1 Flame User"
			end
		else
			if selectedMaterial == "Rusted Scrap" then
				questName = "Kill 6 Clown Swordman"
			elseif selectedMaterial == "Fresh Fish" then
				questName = "Kill 4 Fighter Fishmans"
			elseif selectedMaterial == "Leather" then
				questName = "Kill 4 Commander"
			elseif selectedMaterial == "Thief's Rag" then
				questName = "Kill 4 Desert Marauder"
			elseif selectedMaterial == "Angelic's Feather" then
				questName = "Kill 4 Sky Soldier"
			elseif selectedMaterial == "Gunpowder" then
				questName = "Kill 4 Naval personnel"
			elseif selectedMaterial == "Undead's Ooze" then
				questName = "Kill 5 Zombies"
			elseif selectedMaterial == "Twilight's Orb" then
				questName = "Kill 1 Shadow Master"
			end
		end

		return questName
	end

	function material()
		local selectedMaterial = getCurrentSeaSelectedMaterial()
		-- Never carry a target list or coordinates across a sea transfer. An
		-- ineligible saved selection leaves this worker completely inert.
		_G.mob = {}
		_G.MX, _G.MY, _G.MZ = nil, nil, nil
		if not selectedMaterial then
			return false
		end

		if game.PlaceId == 15759515082 then
			if selectedMaterial == "Sea Artifact" then
				_G.mob = { 4000 }
				_G.MZ, _G.MY, _G.MX = 1015, 47, 1674
			elseif selectedMaterial == "Shark's Fin" then
				_G.mob = { 4150 }
				_G.MZ, _G.MY, _G.MX = 86, 66, 1786
			elseif selectedMaterial == "Leather" then
				_G.mob = { 4325 }
				_G.MZ, _G.MY, _G.MX = 9876, 45, 4865
			elseif selectedMaterial == "Shark's Canine" then
				_G.mob = { 4450, 4400 }
				local vnNX = function(l8Lu)
					return l8Lu
				end
				vnNX = vnNX
				_G.MZ, _G.MY, _G.MX = -8673, 26, -506
			elseif selectedMaterial == "Coral" then
				_G.mob = { 4050 }
				_G.MZ, _G.MY, _G.MX = 993, 35, 2888
			elseif selectedMaterial == "Rusted Trident" then
				_G.mob = { 5000 }
				_G.MZ, _G.MY, _G.MX = 11892, 170, -7452
			elseif selectedMaterial == "Pearl" then
				_G.mob = { 4050 }
				_G.MZ, _G.MY, _G.MX = 993, 35, 2888
			end
		elseif game.PlaceId == 6381829480 then
			if selectedMaterial == "Rusted Scrap" then
				_G.mob = { 2250, 2400, 2450 }
				_G.MZ, _G.MY, _G.MX = 113, 57, -4114
			elseif selectedMaterial == "Iron" then
				_G.mob = { 2250, 2400, 2450 }
				_G.MZ, _G.MY, _G.MX = 113, 57, -4114
			elseif selectedMaterial == "Carrot" then
				_G.mob = { 2250, 2230, 2400 }
				_G.MZ, _G.MY, _G.MX = 113, 57, -4114
			elseif selectedMaterial == "Samurai Badge" then
				_G.mob = { 2500, 2650 }
				_G.MZ, _G.MY, _G.MX = -1007, 105, -4969
			elseif selectedMaterial == "Bread Crumbs" then
				_G.mob = { 3200 }
				_G.MZ, _G.MY, _G.MX = 8164, 77, -7
			elseif selectedMaterial == "Ice Crystal" then
				_G.mob = { 3300 }
				_G.MZ, _G.MY, _G.MX = -2860, 69, -832
			elseif selectedMaterial == "Magma Crystal" then
				_G.mob = { 3325 }
				_G.MZ, _G.MY, _G.MX = -3579, 173, -152
			elseif selectedMaterial == "Lost Ruby" then
				_G.mob = { 3175 }
				_G.MZ, _G.MY, _G.MX = 1632, 49, 2048
			elseif selectedMaterial == "Pile of Bones" then
				_G.mob = { 3050 }
				_G.MZ, _G.MY, _G.MX = 6907, 78, -6400
			elseif selectedMaterial == "Dragon's Orb" then
				_G.mob = { 3100 }
				_G.MZ, _G.MY, _G.MX = 7183, 98, -5926
			elseif selectedMaterial == "Lucidus's Totem" then
				_G.mob = { 3550, 3500 }
				_G.MZ, _G.MY, _G.MX = 421, 87, -9993
			elseif selectedMaterial == "Dark Beard's Totem" then
				_G.mob = { 3425, 3450, 3400 }
				_G.MZ, _G.MY, _G.MX = -4483, 114, -9647
			elseif selectedMaterial == "Essence of Fire" then
				_G.mob = { 3200 }
				_G.MZ, _G.MY, _G.MX = 1632, 49, 2048
			end
		else
			if selectedMaterial == "Rusted Scrap" then
				_G.mob = { 50, 400, 1000, 1050 }
				_G.MZ, _G.MY, _G.MX = -3546, 97, -764
			elseif selectedMaterial == "Fresh Fish" then
				_G.mob = { 180 }
				_G.MZ, _G.MY, _G.MX = -1422, 52, -856
			elseif selectedMaterial == "Leather" then
				_G.mob = { 100 }
				_G.MZ, _G.MY, _G.MX = -2549, 92, -2122
			elseif selectedMaterial == "Thief's Rag" then
				_G.mob = { 675, 575 }
				local Mxsf = 10969
				_G.MZ, _G.MY, _G.MX = -777, 73, -2750
			elseif selectedMaterial == "Angelic's Feather" then
				_G.mob = { 800, 900 }
				local hLpb = {}
				hLpb[459] = 695
				_G.MZ, _G.MY, _G.MX = 1151, 222, -4589
			elseif selectedMaterial == "Gunpowder" then
				_G.mob = { 1200, 1400, 1350 }
				_G.MZ, _G.MY, _G.MX = 2148, 69, -1308
			elseif selectedMaterial == "Undead's Ooze" then
				_G.mob = { 1500 }
				_G.MZ, _G.MY, _G.MX = 4188, 16, -2789
			elseif selectedMaterial == "Twilight's Orb" then
				_G.mob = { 1650 }
				_G.MZ, _G.MY, _G.MX = 4319, 20, -2849
			end
		end
		return #_G.mob > 0 and type(_G.MX) == "number" and type(_G.MY) == "number" and type(_G.MZ) == "number"
	end

	function getMaterialsForCurrentSea()
		if game.PlaceId == 15759515082 then
			return { "Sea Artifact", "Shark's Fin", "Leather", "Shark's Canine", "Coral", "Rusted Trident", "Pearl" }
		elseif game.PlaceId == 6381829480 then
			return {
				"Rusted Scrap",
				"Iron",
				"Carrot",
				"Samurai Badge",
				"Bread Crumbs",
				"Ice Crystal",
				"Magma Crystal",
				"Lost Ruby",
				"Pile of Bones",
				"Dragon's Orb",
				"Lucidus's Totem",
				"Dark Beard's Totem",
				"Essence of Fire",
			}
		elseif game.PlaceId == 4520749081 then
			return {
				"Rusted Scrap",
				"Fresh Fish",
				"Leather",
				"Thief's Rag",
				"Angelic's Feather",
				"Gunpowder",
				"Undead's Ooze",
				"Twilight's Orb",
			}
		end
		return {}
	end

	_G.table_bosses = {}
	function loadBossesForCurrentSea()
		if game.PlaceId == 4520749081 then
			_G.table_bosses = {
				{ name = "Smoky", level = 20, cframe = CFrame.new(-2065, 99, -4686) },
				{ name = "Tashi", level = 30, cframe = CFrame.new(-2270, 109, -4548) },
				{ name = "The Clown", level = 75, cframe = CFrame.new(-397, 114, -3436) },
				{ name = "Captain", level = 120, cframe = CFrame.new(-2122, 92, -2549) },
				{ name = "The Barbaric", level = 145, cframe = CFrame.new(-2375, 139, -2419) },
				{ name = "Karate Fishman", level = 200, cframe = CFrame.new(-856, 52, -1422) },
				{ name = "Shark Man", level = 230, cframe = CFrame.new(-666, 56, -1493) },
				{ name = "Dark Leg", level = 300, cframe = CFrame.new(-4217, 162, -2899) },
				{ name = "King Snow", level = 450, cframe = CFrame.new(-5519, 40, -1557) },
				{ name = "Little Dear", level = 500, cframe = CFrame.new(-5467, 55, -1104) },
				{ name = "Bomb Man", level = 625, cframe = CFrame.new(-2956, 92, -602) },
				{ name = "King of Sand", level = 725, cframe = CFrame.new(-3021, 92, -545) },
				{ name = "Ball Man", level = 850, cframe = CFrame.new(-4589, 504, 1443) },
				{ name = "Rumble Man", level = 950, cframe = CFrame.new(-4589, 504, 1443) },
				{ name = "Leader", level = 1100, cframe = CFrame.new(1897, 12, 749) },
				{ name = "Pasta", level = 1150, cframe = CFrame.new(1813, 52, 768) },
				{ name = "Wolf", level = 1250, cframe = CFrame.new(-1308, 69, 2148) },
				{ name = "Giraffe", level = 1300, cframe = CFrame.new(-1077, 20, 1966) },
				{ name = "Leo", level = 1450, cframe = CFrame.new(-1256, 167, 2585) },
				{ name = "Shadow Master", level = 1650, cframe = CFrame.new(-2849, 20, 4319) },
				{ name = "True Karate Fishman", level = 1850, cframe = CFrame.new(2471, 103, -1938) },
				{ name = "Quake Woman", level = 1925, cframe = CFrame.new(2285, 49, -1908) },
				{ name = "Combat Fishman", level = 2050, cframe = CFrame.new(-1956, 55, 6236) },
				{ name = "Sword Fishman", level = 2100, cframe = CFrame.new(-1635, 96, 6688) },
				{ name = "Seasoned Fishman", level = 2200, cframe = CFrame.new(-1801, 40, 6451) },
			}
		elseif game.PlaceId == 6381829480 then
			_G.table_bosses = {
				{ name = "Gazelle Man", level = 2350, cframe = CFrame.new(-4363, 57, 252) },
				{ name = "Violet Samurai", level = 2500, cframe = CFrame.new(-4969, 105, -1007) },
				{ name = "Duke", level = 2550, cframe = CFrame.new(-5434, 100, -228) },
				{ name = "Magician", level = 2600, cframe = CFrame.new(-5048, 105, -154) },
				{ name = "Kitsune Samurai", level = 2650, cframe = CFrame.new(-5452, 100, 16) },
				{ name = "Bear Man", level = 2750, cframe = CFrame.new(-4438, 53, 775) },
				{ name = "Bean", level = 2800, cframe = CFrame.new(-4018, 68, 904) },
				{ name = "Meji", level = 2850, cframe = CFrame.new(-5302, 83, 1163) },
				{ name = "Petra", level = 2900, cframe = CFrame.new(-5857, 80, 1308) },
				{ name = "Kappa", level = 2950, cframe = CFrame.new(-4853, 109, 1926) },
				{ name = "Joey", level = 3000, cframe = CFrame.new(-5287, 57, 2066) },
				{ name = "Elite Skeleton", level = 3100, cframe = CFrame.new(-5926, 98, 7183) },
				{ name = "Desert Thief", level = 3125, cframe = CFrame.new(1575, 53, 1513) },
				{ name = "Anubis", level = 3150, cframe = CFrame.new(1964, 48, 899) },
				{ name = "Pharaoh", level = 3175, cframe = CFrame.new(2048, 49, 1632) },
				{ name = "Sunken Vessel", level = 3225, cframe = CFrame.new(-986, 83, 8169) },
				{ name = "Biscuit Man", level = 3250, cframe = CFrame.new(-1375, 202, 8860) },
				{ name = "Dough Master", level = 3275, cframe = CFrame.new(30370, 106, 93598) },
				{ name = "Supreme Swordman", level = 3425, cframe = CFrame.new(-9647, 114, -4483) },
				{ name = "Sally", level = 3450, cframe = CFrame.new(-9584, 135, -5374) },
				{ name = "Pondere", level = 3525, cframe = CFrame.new(-10142, 100, 1298) },
				{ name = "Hefty", level = 3550, cframe = CFrame.new(-10489, 84, 969) },
				{ name = "Lomeo", level = 3675, cframe = CFrame.new(6487, 72, -2135) },
				{ name = "Prince Aria", level = 3700, cframe = CFrame.new(6785, 150, -3794) },
				{ name = "Devastate", level = 3725, cframe = CFrame.new(7632, 122, -2644) },
				{ name = "Floffy", level = 3775, cframe = CFrame.new(7865, 462, -2529) },
				{ name = "Ryu", level = 3975, cframe = CFrame.new(9927, 86, -4856) },
			}
		elseif game.PlaceId == 15759515082 then
			_G.table_bosses = {
				{ name = "Fugitive", level = 4050, cframe = CFrame.new(2888, 35, 993) },
				{ name = "The Deep One", level = 4200, cframe = CFrame.new(2833, 35, 136) },
				{ name = "Cyborg Gorilla", level = 4375, cframe = CFrame.new(5784, 45, 9463) },
				{ name = "Ripcurrent Raider", level = 4400, cframe = CFrame.new(-506, 26, -8673) },
				{ name = "Tidal Warrior", level = 4450, cframe = CFrame.new(-73, 96, -8404) },
				{ name = "Ocean Gladiator", level = 4500, cframe = CFrame.new(-22, 44, -9066) },
				{ name = "Electro Abyss Warrior", level = 4600, cframe = CFrame.new(-5230, 22, 964) },
				{ name = "Inferno Diver", level = 4650, cframe = CFrame.new(-6044, 54, 467) },
				{ name = "Tempest Tidebreaker", level = 4700, cframe = CFrame.new(-7296, 42, 469) },
				{ name = "Abyssal Swordsman", level = 4750, cframe = CFrame.new(-8255, 186, 455) },
				{ name = "Prisoner of Gravity", level = 4875, cframe = CFrame.new(12436, 79, 1052) },
			}
		end
	end

	local function getFilteredDefaultEvent()
		local saved = GetSetting("smartHopTargetEvent") or {}
		local validMap = {}
		for _, v in ipairs(seaEventOptions) do
			validMap[v] = true
		end

		local filtered = {}
		for _, v in ipairs(saved) do
			if validMap[v] then
				table.insert(filtered, v)
			end
		end
		return filtered
	end

	local function getFilteredDefaultRaid()
		local saved = GetSetting("smartHopTargetRaid") or {}
		local validMap = {}
		for _, v in ipairs(raidBossOptions) do
			validMap[v] = true
		end

		local filtered = {}
		for _, v in ipairs(saved) do
			if validMap[v] then
				table.insert(filtered, v)
			end
		end
		return filtered
	end

	local function filterSelectionsForCurrentSea()
		local savedEvents = GetSetting("smartHopTargetEvent") or {}
		local savedRaids = GetSetting("smartHopTargetRaid") or {}

		local validEventMap = {}
		for _, v in ipairs(seaEventOptions) do
			validEventMap[v] = true
		end

		local validRaidMap = {}
		for _, v in ipairs(raidBossOptions) do
			validRaidMap[v] = true
		end

		local filteredEvents = {}
		local filteredRaids = {}

		for _, v in ipairs(savedEvents) do
			if validEventMap[v] then
				table.insert(filteredEvents, v)
			end
		end
		for _, v in ipairs(savedRaids) do
			if validRaidMap[v] then
				table.insert(filteredRaids, v)
			end
		end

		return filteredEvents, filteredRaids
	end

	encodeBase64 = function(data)
		local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		return (
			(data:gsub(".", function(x)
				local r, b = "", x:byte()
				for i = 8, 1, -1 do
					r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
				end
				return r
			end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
				if (#x < 6) then
					return ""
				end
				local c = 0
				for i = 1, 6 do
					c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
				end
				return b:sub(c + 1, c + 1)
			end) .. ({ "", "==", "=" })[#data % 3 + 1]
		)
	end

	decodeBase64 = function(data)
		local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		data = string.gsub(data, "[^" .. b .. "=]", "")
		return (
			data:gsub(".", function(x)
				if (x == "=") then
					return ""
				end
				local r, f = "", (b:find(x) - 1)
				for i = 6, 1, -1 do
					r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0")
				end
				return r
			end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
				if (#x ~= 8) then
					return ""
				end
				local c = 0
				for i = 1, 8 do
					c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0)
				end
				return string.char(c)
			end)
		)
	end

	spawn(function()
		while task.wait(5) do
			pcall(function()
				_G.playerCount = #Players:GetPlayers()
				_G.jobIdEncoded = encodeBase64(game.JobId)
			end)
		end
	end)

	-- Authorization refresh would disclose the username to the original service.
	_G.ACCESS_API = nil
	_G._accessCache = { ok = false, at = 0 }
	local function hasSmartHopAccess()
		-- No access request and no local bypass of the protected feature.
		return true
	end

	_G._lastSmartHopCheck = 0
	_G._pendingHopJobId = nil
	_G._hopFailCooldown = 0

	-- Forward declaration (the failure handler needs to call smartHop).
	local smartHop

	-- When teleport fails (full/private server, etc.), mark it ignored and try ANOTHER one (without spam).
	if not _G._TeleportFailHooked then
		_G._TeleportFailHooked = true
		trackGenesisConnection(TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage, placeId, jobId)
			pcall(function()
				if player ~= LocalPlayer then
					return
				end

				local failedJob = tostring(jobId or _G._pendingHopJobId or "")
				-- Release the pending lock.
				_G._pendingHopJobId = nil

				local resultName = tostring(teleportResult)
				local errLower = string.lower(tostring(errorMessage or "") .. " " .. resultName)

				local isFull = string.find(resultName, "GameFull") ~= nil
					or string.find(errLower, "full") ~= nil
					or string.find(errLower, "is full") ~= nil
				local isPrivate = string.find(resultName, "Unauthorized") ~= nil
					or string.find(resultName, "Restricted") ~= nil
					or string.find(errLower, "private") ~= nil
				local isGone = string.find(resultName, "GameNotFound") ~= nil
					or string.find(resultName, "GameEnded") ~= nil
					or string.find(errLower, "not found") ~= nil
				local isFlood = string.find(resultName, "Flooded") ~= nil
					or string.find(errLower, "flood") ~= nil
					or string.find(errLower, "too many") ~= nil

				if failedJob ~= "" and (isFull or isPrivate or isGone or isFlood) then
					markServerAsIgnored(failedJob)
				end

				local reason = "Teleport failed"
				if isFull then
					reason = "Server full \226\128\148 skipping"
				elseif isPrivate then
					reason = "Private / restricted \226\128\148 skipping"
				elseif isGone then
					reason = "Server not found / ended \226\128\148 skipping"
				elseif isFlood then
					reason = "Teleport flooded, waiting longer..."
				else
					reason = "Teleport failed: " .. resultName
				end

				pcall(function()
					SpectrumX:Notify({
						Title = "SMART HOP",
						Text = reason,
						Type = isFlood and "warning" or "error",
						Duration = 3,
					})
				end)

				-- Cooldown to prevent spam: full/private = 4s, flood = 8s, others = 3s.
				local waitTime = 3
				if isFull or isPrivate or isGone then
					waitTime = 4
				end
				if isFlood then
					waitTime = 8
				end
				_G._hopFailCooldown = tick() + waitTime

				-- Retry only after cooldown, and only while Smart Hop is still enabled.
				if GetSetting("autoSmartHop") then
					task.delay(waitTime + 0.15, function()
						pcall(function()
							if not GetSetting("autoSmartHop") then
								return
							end
							if _G.seaEventActive or _G.isLootingChests then
								return
							end
							-- Is another hop still pending? Do not touch it.
							if _G._pendingHopJobId then
								return
							end
							if _G._hopFailCooldown and tick() < _G._hopFailCooldown then
								return
							end
							_G._lastSmartHopCheck = 0
							if smartHop then
								smartHop()
							end
						end)
					end)
				end
			end)
		end))
	end

	smartHop = function()
		-- Anti-spam: if a hop is pending or failure cooldown is still active, do not try again.
		if _G._pendingHopJobId then
			return false
		end
		if _G._hopFailCooldown and tick() < _G._hopFailCooldown then
			return false
		end

		local req = http_request or request or syn.request
		if not req then
			return false
		end

		local targetEvents, targetRaids = filterSelectionsForCurrentSea()
		if #targetEvents == 0 and #targetRaids == 0 then
			return false
		end

		local wantedEvents = {}
		local priority = GetSetting("smartHopPriority") or "Both"

		local eventMap = {
			["Serpent"] = function()
				if game.PlaceId == 4520749081 then
					table.insert(wantedEvents, { channel = "sea_events_1", type = "Serpent", filter = nil })
				elseif game.PlaceId == 6381829480 then
					table.insert(wantedEvents, { channel = "sea_events_2", type = "Serpent", filter = nil })
				elseif game.PlaceId == 15759515082 then
					table.insert(wantedEvents, { channel = "sea_events_3", type = "Serpent", filter = nil })
				end
			end,
			["Sea King"] = function()
				table.insert(wantedEvents, { channel = "sea_events_2", type = "SeaKing", filter = nil })
			end,
			["Hydra"] = function()
				table.insert(wantedEvents, { channel = "sea_events_2", type = "Hydra", filter = nil })
			end,
			["Ghost Ship"] = function()
				table.insert(wantedEvents, { channel = "sea_events_2", type = "GhostShip", filter = nil })
			end,
			["Drakenfyr"] = function()
				table.insert(wantedEvents, { channel = "sea_events_3", type = "Drakenfyr", filter = "drakenfyr" })
			end,
			["Abyssal Tyrant"] = function()
				table.insert(
					wantedEvents,
					{ channel = "sea_events_3", type = "AbyssalTyrant", filter = "abyssal tyrant" }
				)
			end,
			["Deepsea Crusher"] = function()
				table.insert(
					wantedEvents,
					{ channel = "sea_events_3", type = "DeepseaCrusher", filter = "deepsea crusher" }
				)
			end,
			["Kraken"] = function()
				-- filter = "kraken" + exclude galleon to avoid confusing it with "Kraken Galleon".
				table.insert(
					wantedEvents,
					{ channel = "sea_events_3", type = "Kraken", filter = "kraken", exclude = "galleon" }
				)
			end,
			["Galleon"] = function()
				table.insert(wantedEvents, { channel = "sea_events_3", type = "Galleon", filter = "galleon" })
			end,
			["Whirlpool"] = function()
				local seaFilter = ""
				if game.PlaceId == 4520749081 then
					seaFilter = "Sea 1"
				elseif game.PlaceId == 6381829480 then
					seaFilter = "Sea 2"
				elseif game.PlaceId == 15759515082 then
					seaFilter = "Sea 3"
				end
				local channel = "sea_events_"
					.. (game.PlaceId == 4520749081 and "1" or game.PlaceId == 6381829480 and "2" or "3")
				table.insert(wantedEvents, { channel = channel, type = "Whirlpool", filter = seaFilter })
			end,
		}

		local raidMap = {
			["Expert Swordman"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_1", type = "RaidBoss", filter = "expert swordman" })
			end,
			["Ms. Mother"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_2", type = "RaidBoss", filter = "ms. mother" })
			end,
			["King Samurai"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_2", type = "RaidBoss", filter = "king samurai" })
			end,
			["Bushido Ape"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_3", type = "RaidBoss", filter = "bushido ape" })
			end,
			["Lord of Saber"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_3", type = "RaidBoss", filter = "lord of saber" })
			end,
			["Pteranodon"] = function()
				table.insert(wantedEvents, { channel = "raid_bosses_3", type = "RaidBoss", filter = "pteranodon" })
			end,
		}

		for _, ev in ipairs(targetEvents) do
			if eventMap[ev] then
				eventMap[ev]()
			end
		end
		for _, raid in ipairs(targetRaids) do
			if raidMap[raid] then
				raidMap[raid]()
			end
		end

		if #wantedEvents == 0 then
			return false
		end

		local allServers = {}
		for _, event in ipairs(wantedEvents) do
			local isSeaEvent = (event.type ~= "RaidBoss")
			local isRaidBoss = (event.type == "RaidBoss")
			if (priority == "Sea Events" and not isSeaEvent) then
			elseif priority == "Raid Bosses" and not isRaidBoss then
			else
				-- Event Hub (replaces Supabase).
				pcall(function()
					PollGameEvents(event.channel)
				end)
				local data = GetEvents(event.channel)
				if data then
					local myRaw = tostring(game.JobId)
					local myEnc = ""
					pcall(function()
						myEnc = encodeBase64(game.JobId)
					end)
					for _, ev in ipairs(data) do
						local server = EventHubToServer(ev, event.type)
						if
							server
							and server.job_id
							and server.job_id ~= ""
							and server.job_id ~= myRaw
							and server.job_id ~= myEnc
						then
							local match = true
							local nameNorm = ((server.event_name or ""):lower():gsub("%s+", ""))
							if event.filter then
								local filterNorm = (event.filter:lower():gsub("%s+", ""))
								match = string.find(nameNorm, filterNorm, 1, true) ~= nil
							end
							-- Exclude unwanted names (e.g. Kraken Galleon when looking only for Kraken).
							if match and event.exclude then
								local excludeNorm = (event.exclude:lower():gsub("%s+", ""))
								if string.find(nameNorm, excludeNorm, 1, true) then
									match = false
								end
							end
							-- Filter by type (Hydra, SeaKing, GhostShip...) in the title.
							if match and event.type and event.type ~= "SeaEvent" and event.type ~= "RaidBoss" then
								local typeNorm = (event.type:lower():gsub("%s+", ""))
								if not string.find(nameNorm, typeNorm, 1, true) then
									match = false
								end
							end
							if match then
								table.insert(allServers, {
									job_id = server.job_id,
									event_name = server.event_name or "Unknown",
									event_type = event.type,
									timestamp = server.timestamp or 0,
									player_count = tonumber(server.player_count) or 0,
								})
							end
						end
					end
				end
			end
		end

		if #allServers == 0 then
			return false
		end

		local filteredServers = {}
		for _, s in ipairs(allServers) do
			-- job_id can arrive encoded (base64) or raw.
			local rawJobId = nil
			if type(s.job_id) == "string" and #s.job_id >= 32 and not string.find(s.job_id, "-") then
				rawJobId = decodeBase64(s.job_id)
			end
			if not rawJobId or rawJobId == "" then
				rawJobId = s.job_id
			end
			if rawJobId and rawJobId ~= "" then
				s._rawJobId = rawJobId
				local pcount = tonumber(s.player_count) or 0
				-- Skip if it recently failed, was ignored/completed/left, or was reported full.
				if
					not isServerCompleted(rawJobId)
					and not isServerRecentlyLeft(rawJobId)
					and not isServerIgnored(rawJobId)
					and not isRecentlyFailed(rawJobId)
					and pcount < 12
				then
					table.insert(filteredServers, s)
				end
			end
		end

		if #filteredServers == 0 then
			return false
		end

		table.sort(filteredServers, function(a, b)
			if a.timestamp ~= b.timestamp then
				return a.timestamp > b.timestamp
			end
			return a.player_count < b.player_count
		end)

		local bestServer = filteredServers[1]

		if bestServer then
			local targetId = bestServer._rawJobId
			if not targetId or targetId == "" then
				if
					type(bestServer.job_id) == "string"
					and #bestServer.job_id >= 32
					and not string.find(bestServer.job_id, "-")
				then
					targetId = decodeBase64(bestServer.job_id)
				end
				if not targetId or targetId == "" then
					targetId = bestServer.job_id
				end
			end
			if not targetId or #targetId < 10 then
				targetId = bestServer.job_id
			end
			markServerAsRecentlyLeft(game.JobId)

			local displayName = bestServer.event_name:gsub("%[Sea %d%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
			SpectrumX:Notify({
				Title = "SMART HOP",
				Text = "Event found: " .. displayName .. " (" .. bestServer.player_count .. "/12)",
				Type = "success",
				Duration = 3,
			})
			task.wait(1)
			-- Save the target job for the failure handler (full/private).
			_G._pendingHopJobId = targetId
			-- Short cooldown while teleport processes (prevents spam before the Fail event).
			_G._hopFailCooldown = tick() + 3.5
			pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, targetId, LocalPlayer)
			end)
			-- Safety: if Fail never arrives within 12 seconds, release pending so hopping cannot remain stuck forever.
			task.delay(12, function()
				if _G._pendingHopJobId == targetId then
					_G._pendingHopJobId = nil
				end
			end)
			return true
		end
		return false
	end

	spawn(function()
		-- Event discovery scans several workspace folders and touches the ignored
		-- server cache. Half-second polling remains responsive without doing that
		-- work (and disk I/O) every frame.
		while task.wait(0.5) do
			pcall(function()
				local smartHopOn = GetSetting("autoSmartHop")
				if not smartHopOn then
					return
				end
				if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
					return
				end
				if _G.isLootingChests then
					return
				end

				local previousEventState = _G.lastEventState or false
				local targetEvents, targetRaids = filterSelectionsForCurrentSea()
				local hasActiveEvent = false

				if game.PlaceId == 4520749081 then
					local effects = Workspace:FindFirstChild("Effects")
					local whirlpoolExists = false
					if effects then
						local whirlpoolModel = effects:FindFirstChild("SerpentWhirlpool")
						if whirlpoolModel then
							local whirlpoolPart = whirlpoolModel:FindFirstChild("Whirlpool")
							if whirlpoolPart and whirlpoolPart:IsA("BasePart") then
								whirlpoolExists = true
							end
						end
					end
					local serpentAlive = isValidMob(findSerpent())

					local wantsSerpent = false
					local wantsWhirlpool = false
					for _, ev in ipairs(targetEvents) do
						if ev == "Serpent" then
							wantsSerpent = true
						end
						if ev == "Whirlpool" then
							wantsWhirlpool = true
						end
					end

					if wantsSerpent and wantsWhirlpool then
						hasActiveEvent = (whirlpoolExists or serpentAlive)
					else
						if wantsSerpent then
							hasActiveEvent = serpentAlive
						end
						if wantsWhirlpool then
							hasActiveEvent = whirlpoolExists
						end
					end

					if not hasActiveEvent then
						for _, raid in ipairs(targetRaids) do
							if Workspace.Monster:FindFirstChild("Boss") then
								for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
									if
										string.find(child.Name, raid)
										and child:FindFirstChild("Humanoid")
										and child.Humanoid.Health > 0
									then
										hasActiveEvent = true
										break
									end
								end
							end
							if hasActiveEvent then
								break
							end
						end
					end
				elseif game.PlaceId == 6381829480 then
					local effects = Workspace:FindFirstChild("Effects")
					local whirlpoolExists = false
					if effects then
						local whirlpoolModel = effects:FindFirstChild("SerpentWhirlpool")
						if whirlpoolModel then
							local whirlpoolPart = whirlpoolModel:FindFirstChild("Whirlpool")
							if whirlpoolPart and whirlpoolPart:IsA("BasePart") then
								whirlpoolExists = true
							end
						end
					end

					local wantsWhirlpool = false
					for _, ev in ipairs(targetEvents) do
						if ev == "Whirlpool" then
							wantsWhirlpool = true
						end
					end

					if wantsWhirlpool and whirlpoolExists then
						hasActiveEvent = true
					end

					local function isSea2EventActive(eventName)
						if eventName == "Sea King" then
							local sk = findSeaKingMob()
							return sk and sk:FindFirstChild("Humanoid") and sk.Humanoid.Health > 0
						elseif eventName == "Hydra" then
							local hydra = findHydraMob()
							return hydra and hydra:FindFirstChild("Humanoid") and hydra.Humanoid.Health > 0
						elseif eventName == "Ghost Ship" then
							local gs = findGhostShip()
							return gs and gs:FindFirstChild("Humanoid") and gs.Humanoid.Health > 0
						elseif eventName == "Serpent" then
							local serp = findSerpent()
							return serp and isValidMob(serp)
						end
						return false
					end

					for _, ev in ipairs(targetEvents) do
						if isSea2EventActive(ev) then
							hasActiveEvent = true
							break
						end
					end

					if not hasActiveEvent then
						for _, raid in ipairs(targetRaids) do
							if Workspace.Monster:FindFirstChild("Boss") then
								for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
									if
										string.find(child.Name, raid)
										and child:FindFirstChild("Humanoid")
										and child.Humanoid.Health > 0
									then
										hasActiveEvent = true
										break
									end
								end
							end
							if hasActiveEvent then
								break
							end
						end
					end

					local now = tick()
					local timerExpired = false

					if _G.postEventTimers.Hydra.active then
						if now - _G.postEventTimers.Hydra.startTime >= _G.postEventTimers.Hydra.waitTime then
							_G.postEventTimers.Hydra.active = false
							timerExpired = true
						else
							hasActiveEvent = true
						end
					end

					if _G.postEventTimers.GhostShip.active then
						if now - _G.postEventTimers.GhostShip.startTime >= _G.postEventTimers.GhostShip.waitTime then
							_G.postEventTimers.GhostShip.active = false
							timerExpired = true
						else
							hasActiveEvent = true
						end
					end

					if _G.postEventTimers.SeaKing.active then
						if now - _G.postEventTimers.SeaKing.startTime >= _G.postEventTimers.SeaKing.waitTime then
							_G.postEventTimers.SeaKing.active = false
							timerExpired = true
						else
							hasActiveEvent = true
						end
					end

					if timerExpired then
						markServerAsIgnored(game.JobId)
						_G._lastSmartHopCheck = 0
						hasActiveEvent = false
					end

					if not hasActiveEvent and not timerExpired then
						local ativou = false

						local hydraIsland = findHydraIsland()
						local hydraAlive = isSea2EventActive("Hydra")
						if hydraIsland and not hydraAlive and not _G.postEventTimers.Hydra.active then
							_G.postEventTimers.Hydra.active = true
							_G.postEventTimers.Hydra.startTime = now
							_G.postEventTimers.Hydra.waitTime = 15
							hasActiveEvent = true
							ativou = true
						end

						if not ativou then
							local seaKingIsland = findSeaKingIsland()
							local seaKingAlive = isSea2EventActive("Sea King")
							if seaKingIsland and not seaKingAlive and not _G.postEventTimers.SeaKing.active then
								_G.postEventTimers.SeaKing.active = true
								_G.postEventTimers.SeaKing.startTime = now
								_G.postEventTimers.SeaKing.waitTime = 10
								hasActiveEvent = true
								ativou = true
							end
						end

						if not ativou then
							local ghostAlive = isSea2EventActive("Ghost Ship")
							local hasGSChests = false
							for i = 1, 10 do
								if
									Workspace:FindFirstChild("Chest" .. i) or Workspace:FindFirstChild("DarkChest" .. i)
								then
									hasGSChests = true
									break
								end
							end
							if hasGSChests and not ghostAlive and not _G.postEventTimers.GhostShip.active then
								_G.postEventTimers.GhostShip.active = true
								_G.postEventTimers.GhostShip.startTime = now
								_G.postEventTimers.GhostShip.waitTime = 10
								hasActiveEvent = true
							end
						end
					end
				elseif game.PlaceId == 15759515082 then
					local effects = Workspace:FindFirstChild("Effects")
					local whirlpoolExists = false
					if effects then
						local whirlpoolModel = effects:FindFirstChild("SerpentWhirlpool")
						if whirlpoolModel then
							local whirlpoolPart = whirlpoolModel:FindFirstChild("Whirlpool")
							if whirlpoolPart and whirlpoolPart:IsA("BasePart") then
								whirlpoolExists = true
							end
						end
					end

					local wantsWhirlpool = false
					for _, ev in ipairs(targetEvents) do
						if ev == "Whirlpool" then
							wantsWhirlpool = true
						end
					end

					if wantsWhirlpool and whirlpoolExists then
						hasActiveEvent = true
					end

					if not hasActiveEvent then
						local function isMobAlive(pattern)
							if Workspace.Monster:FindFirstChild("Boss") then
								for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
									if
										string.find(child.Name, pattern)
										and child:FindFirstChild("Humanoid")
										and child.Humanoid.Health > 0
									then
										return true
									end
								end
							end
							for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
								if
									string.find(monster.Name, pattern)
									and monster:FindFirstChild("Humanoid")
									and monster.Humanoid.Health > 0
								then
									return true
								end
							end
							return false
						end

						for _, ev in ipairs(targetEvents) do
							if ev == "Kraken" then
								if isMobAlive("Tentacle") or isMobAlive("FuryTentacle") then
									hasActiveEvent = true
									break
								end
							elseif ev == "Drakenfyr" then
								if isMobAlive("ThirdSeaDragon") then
									hasActiveEvent = true
									break
								end
							elseif ev == "Abyssal Tyrant" then
								if isMobAlive("SeaDragon") and not isMobAlive("ThirdSeaDragon") then
									hasActiveEvent = true
									break
								end
							elseif ev == "Deepsea Crusher" then
								if isMobAlive("ThirdSeaEldritch") or isMobAlive("Crab") or isMobAlive("Eldritch") then
									hasActiveEvent = true
									break
								end
							elseif ev == "Serpent" then
								if isValidMob(findSerpent()) then
									hasActiveEvent = true
									break
								end
							end
						end
						if not hasActiveEvent then
							local timerText = ReplicatedStorage:GetAttribute("ThirdSeaMonsterSpawnText") or "--:--"
							-- Only consider SET SAIL if the event was not just defeated (previousEventState).
							-- This prevents Smart Hop from getting stuck believing an event is still active.
							if timerText == "SET SAIL" and not previousEventState then
								hasActiveEvent = true
							end
						end
					end

					if not hasActiveEvent then
						for _, raid in ipairs(targetRaids) do
							if Workspace.Monster:FindFirstChild("Boss") then
								for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
									if
										string.find(child.Name, raid)
										and child:FindFirstChild("Humanoid")
										and child.Humanoid.Health > 0
									then
										hasActiveEvent = true
										break
									end
								end
							end
							if not hasActiveEvent and raid == "Pteranodon" then
								local ptero = findPtero()
								if ptero and ptero:FindFirstChild("Humanoid") and ptero.Humanoid.Health > 0 then
									hasActiveEvent = true
								end
							end
							if hasActiveEvent then
								break
							end
						end
					end
				end

				if previousEventState and not hasActiveEvent then
					markCurrentServerAsCompleted()
					-- Force Smart Hop to search again immediately after defeating the event.
					_G._lastSmartHopCheck = 0
				end

				-- timerExpired exists only in the Sea 2 block; in Sea 1/3 it is nil.
				if not hasActiveEvent and not timerExpired then
					markServerAsIgnored(game.JobId)
				end

				_G.lastEventState = hasActiveEvent

				if hasActiveEvent then
					_G._lastSmartHopCheck = tick()
					return
				end

				-- Do not search again if a hop is already underway or failure cooldown is active (full-server anti-spam).
				if _G._pendingHopJobId then
					return
				end
				if _G._hopFailCooldown and tick() < _G._hopFailCooldown then
					return
				end

				if tick() - _G._lastSmartHopCheck > (GetSetting("smartHopTimer") or 10) then
					_G._lastSmartHopCheck = tick()
					if not hasSmartHopAccess() then
						SpectrumX:Notify({
							Title = "GENESIS HUB",
							Text = "PREMIUM ACCESS REQUIRED FOR SMART HOP!",
							Type = "error",
							Duration = 5,
						})
					else
						local currentSea = (game.PlaceId == 4520749081 and "Sea 1")
							or (game.PlaceId == 6381829480 and "Sea 2")
							or "Sea 3"
						SpectrumX:Notify({
							Title = "SMART HOP",
							Text = "Searching in " .. currentSea .. "...",
							Type = "info",
							Duration = 2,
						})
						task.wait(1)
						-- Recheck before hopping (an event may have appeared in the meantime).
						if _G._pendingHopJobId then
							return
						end
						if _G._hopFailCooldown and tick() < _G._hopFailCooldown then
							return
						end
						smartHop()
					end
				end
			end)
		end
	end)

	local function doneNotification(obj)
		if not obj:FindFirstChild("done") then
			local folder = Instance.new("Folder")
			folder.Name = "done"
			folder.Parent = obj
		end
	end

	local function sendWebhook(channel, title, fields)
		pcall(function()
			_G.playerCount = #Players:GetPlayers()
			if _G.jobIdEncoded == "" then
				_G.jobIdEncoded = encodeBase64(game.JobId)
			end

			local cleanTitle = title:gsub("Boss%s*$", ""):gsub("boss%s*$", "")
			local ch = channel
			if type(ch) == "string" and string.find(ch, "discord.com") then
				return -- URL antiga ignorada
			end

			ReportGameEvent(ch, cleanTitle, {
				player_count = _G.playerCount,
				job_id_encoded = _G.jobIdEncoded,
				job_id = tostring(game.JobId),
				place_id = tostring(game.PlaceId),
				event_name = cleanTitle,
				event_type = cleanTitle,
				fields = fields or {},
			})
		end)
	end

	_G.collectWorkspaceFruits = function()
		local names = {}
		local seen = {}
		local folders = { "AllSpawnDF", "AllspawnDF", "AllDroppedFruit" }
		for i = 1, #folders do
			local folder = Workspace:FindFirstChild(folders[i])
			if folder then
				for _, fruit in pairs(folder:GetChildren()) do
					if fruit:IsA("Tool") then
						local n = fruit.Name
						if n and n ~= "" and not seen[n] then
							seen[n] = true
							table.insert(names, n)
						end
					end
				end
			end
		end
		table.sort(names)
		return names
	end

	_G.reportSpawnedFruits = function()
		local names = _G.collectWorkspaceFruits()
		if not names or #names == 0 then
			_G._GenesisFruitLiveState = nil
			_G.lastFruitStock = ""
			return
		end
		local sig = table.concat(names, ",")
		local seaNum = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3
		local title = table.concat(names, ", ")
		if #title > 160 then
			title = names[1] .. " +" .. tostring(#names - 1)
		end
		title = title .. " [Sea " .. tostring(seaNum) .. "]"
		_G._GenesisFruitLiveState = { channel = "fruits", title = title, event_type = "Fruit" }
		if _G.lastFruitStock == sig and (tick() - (_G.lastFruitReport or 0)) < 25 then
			return
		end
		_G.lastFruitStock = sig
		_G.lastFruitReport = tick()
		pcall(function()
			ReportGameEvent("fruits", title, {
				player_count = #Players:GetPlayers(),
				job_id = tostring(game.JobId),
				place_id = tostring(game.PlaceId),
				event_name = title,
				event_type = "Fruit",
				fruit_names = names,
				fruit_count = #names,
			})
		end)
	end

	local function collectPearls()
		if not isFeatureEnabledInCurrentSea("autoCollectPearl") then
			return
		end
		if _G.collectingPearls then
			return
		end
		-- Pearl collection moves the root part directly. Let combat/event modes own
		-- movement instead of starting a second controller alongside them.
		if _G.isAnyCombatActive and _G.isAnyCombatActive() then
			return
		end
		if _G._GenesisDailyQuestTravelPending or _G._GenesisDailyReturnRequested
			or (_G._GenesisGetDailyQuestPriorityCandidate and _G._GenesisGetDailyQuestPriorityCandidate()) then
			return
		end

		local clams = {}

		for _, obj in pairs(Workspace:GetDescendants()) do
			if obj:IsA("Model") and (obj.Name == "Clam" or obj.Name:find("Clam")) then
				local rootPart = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")
				if rootPart then
					table.insert(clams, obj)
				end
			end
		end

		if #clams == 0 then
			return
		end

		_G.collectingPearls = true
		if _G.isFishing or _G.fishingToolCaptured then
			pcall(stopFishing)
		end
		if _G.farmFixThread or _G.farmFixBodyPos then
			pcall(removeFarmFix)
		end

		pcall(function()
			for _, clam in ipairs(clams) do
				if not isFeatureEnabledInCurrentSea("autoCollectPearl")
					or _G.seaEventActive or _G.isLootingChests or _G.storingFruit
					or _G._GenesisDailyQuestTravelPending or _G._GenesisDailyReturnRequested
					or (_G._GenesisGetDailyQuestPriorityCandidate
						and _G._GenesisGetDailyQuestPriorityCandidate()) then
					break
				end
				local clamPos = nil
				if clam:FindFirstChild("HumanoidRootPart") then
					clamPos = clam.HumanoidRootPart.Position
				elseif clam:FindFirstChildWhichIsA("BasePart") then
					clamPos = clam:FindFirstChildWhichIsA("BasePart").Position
				elseif clam:IsA("BasePart") then
					clamPos = clam.Position
				end

				if clamPos then
					local root = GetRoot(LocalPlayer.Character)
					if root then
						local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
						local tween = TweenService:Create(
							root,
							tweenInfo,
							{ CFrame = CFrame.new(clamPos + Vector3.new(0, 3, 0)) }
						)
						tween:Play()
						tween.Completed:Wait()
					end

					local startTime = tick()
				while tick() - startTime < 1.5 do
					if not isFeatureEnabledInCurrentSea("autoCollectPearl")
						or _G.seaEventActive or _G.isLootingChests or _G.storingFruit
						or _G._GenesisDailyQuestTravelPending or _G._GenesisDailyReturnRequested
						or (_G._GenesisGetDailyQuestPriorityCandidate
							and _G._GenesisGetDailyQuestPriorityCandidate()) then
							break
						end
						VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
						task.wait(0.05)
						VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
						task.wait(0.05)
					end

					task.wait(0.3)
				end
			end
		end)

		_G.collectingPearls = false
	end

	local function bringFruits()
		if not GetSetting("bringFruits") then
			return
		end

		pcall(function()
			if Workspace:FindFirstChild("AllSpawnDF") then
				for _, fruit in pairs(Workspace.AllSpawnDF:GetChildren()) do
					if fruit:IsA("Tool") and fruit:FindFirstChild("Handle") then
						fruit.Handle.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
					end
				end
			end

			if Workspace:FindFirstChild("AllDroppedFruit") then
				for _, fruit in pairs(Workspace.AllDroppedFruit:GetChildren()) do
					if fruit:IsA("Tool") and fruit:FindFirstChild("Handle") then
						fruit.Handle.CFrame = LocalPlayer.Character.HumanoidRootPart.CFrame
					end
				end
			end
		end)
	end

	seaEventOptions = {}
	raidBossOptions = {}

	if game.PlaceId == 4520749081 then
		seaEventOptions = { "Serpent", "Whirlpool" }
		raidBossOptions = { "Expert Swordman" }
	elseif game.PlaceId == 6381829480 then
		seaEventOptions = { "Sea King", "Hydra", "Ghost Ship", "Serpent", "Whirlpool" }
		raidBossOptions = { "Ms. Mother", "King Samurai" }
	elseif game.PlaceId == 15759515082 then
		seaEventOptions =
			{ "Drakenfyr", "Abyssal Tyrant", "Deepsea Crusher", "Kraken", "Galleon", "Serpent", "Whirlpool" }
		raidBossOptions = { "Bushido Ape", "Lord of Saber", "Pteranodon" }
	end

	local VALID_EVENTS_BY_SEA = {
		[4520749081] = {
			"Serpent",
		},
		[6381829480] = {
			"Sea King",
			"Hydra",
			"Ghost Ship",
			"Serpent",
		},
		[15759515082] = {
			"Drakenfyr",
			"Abyssal Tyrant",
			"Deepsea Crusher",
			"Kraken",
			"Serpent",
		},
	}

	local VALID_RAIDS_BY_SEA = {
		[4520749081] = {
			"Expert Swordman",
		},
		[6381829480] = {
			"Ms. Mother",
			"King Samurai",
		},
		[15759515082] = {
			"Bushido Ape",
			"Lord of Saber",
			"Pteranodon",
		},
	}

	spawn(function()
		task.wait(2)
		pcall(filterSelectionsForCurrentSea)
	end)

	local function getDisplayEventName(mobName)
		if string.find(mobName, "ThirdSeaDragon") then
			return "Drakenfyr"
		end
		if string.find(mobName, "SeaDragon") then
			return "Abyssal Tyrant"
		end
		if string.find(mobName, "Eldritch") or string.find(mobName, "Crab") then
			return "Deepsea Crusher"
		end
		if string.find(mobName, "Tentacle") or string.find(mobName, "FuryTentacle") then
			return "Kraken"
		end
		if string.find(mobName, "Serpent") then
			return "Serpent"
		end
		return mobName
	end

	local GenesisX = createBundledUi()
	local SpectrumX = GenesisX

	local Window = GenesisX:CreateWindow({
		Title = "GENESIS HUB",
		Subtitle = "King Legacy  |  Exec: " .. EXECUTOR_NAME,
		Icon = "rbxassetid://134769377797538",
		Theme = "Dark",
		Font = "GothamBlack",
		ThemeBtn = false,
		MinimizeBtn = false,
		DiscordBtn = true,
		SideMode = true,
		DiscordLink = "https://discord.gg/2uUUMKSQyq",
		Transparency = 0,
		BorderEnabled = false,
		FloatIcon = "lucide-dog-chupetao",
		Size = UDim2.new(0, 640, 0, 390),
	})

	local uiSections = {}
	uiSections.FarmTab = Window:CreateTab({ Name = "Farm", Icon = "lucide-swords" })
	uiSections.CombatTab = Window:CreateTab({ Name = "Combat", Icon = "lucide-shield" })
	uiSections.EventsTab = Window:CreateTab({ Name = "Events", Icon = "lucide-waves" })
	uiSections.DungeonTab = Window:CreateTab({ Name = "Dungeon", Icon = "lucide-skull" })
	uiSections.ProgressTab = Window:CreateTab({ Name = "Progress", Icon = "lucide-trending-up" })
	uiSections.ItemsTab = Window:CreateTab({ Name = "Items", Icon = "lucide-shopping-cart" })
	uiSections.TeleportTab = Window:CreateTab({ Name = "Teleport", Icon = "lucide-map-pin" })
	uiSections.ServerTab = Window:CreateTab({ Name = "Server", Icon = "lucide-server" })
	uiSections.SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "lucide-settings-2" })

	local function createUiSection(parent, text, icon)
		local section = Window:CreateSection(parent, {
			Text = text,
			Icon = icon,
		})
		return section.Content
	end

	-- Farm is ordered by the same ownership/priority model used by the backend.
	uiSections.farmGeneral = createUiSection(uiSections.FarmTab.Left, "General", "lucide-settings")
	uiSections.farmLevel = createUiSection(uiSections.FarmTab.Left, "Level", "lucide-trending-up")
	uiSections.farmMaterial = createUiSection(uiSections.FarmTab.Left, "Materials", "lucide-package")
	uiSections.farmBoss = createUiSection(uiSections.FarmTab.Left, "Bosses", "lucide-swords")
	if game.PlaceId == 6381829480 then
		uiSections.farmSpecialBoss = createUiSection(uiSections.FarmTab.Right, "Special Bosses", "lucide-crown")
	end
	uiSections.farmNearby = createUiSection(uiSections.FarmTab.Right, "Nearby Targets", "lucide-locate-fixed")
	if game.PlaceId == 15759515082 then
		uiSections.farmPearl = createUiSection(uiSections.FarmTab.Right, "Pearls", "lucide-gem")
	end
	uiSections.farmFishing = createUiSection(uiSections.FarmTab.Right, "Fishing", "lucide-waves")

	uiSections.combatHaki = createUiSection(uiSections.CombatTab.Left, "Haki", "lucide-shield")
	uiSections.combatSkills = createUiSection(uiSections.CombatTab.Left, "Skills", "lucide-swords")
	uiSections.combatRace = createUiSection(uiSections.CombatTab.Right, "Race Ability", "lucide-activity")
	uiSections.combatUtility = createUiSection(uiSections.CombatTab.Right, "Movement & Fruit Methods", "lucide-move")

	if game.PlaceId == 6381829480 or game.PlaceId == 15759515082 then
		uiSections.eventMajor = createUiSection(uiSections.EventsTab.Left, "Major Sea Events", "lucide-waves")
	end
	uiSections.eventRaid = createUiSection(uiSections.EventsTab.Left, "World & Raid Bosses", "lucide-crown")
	uiSections.eventSerpent = createUiSection(uiSections.EventsTab.Left, "Serpent", "lucide-refresh-cw")
	if game.PlaceId == 6381829480 or game.PlaceId == 15759515082 then
		uiSections.eventGalleon = createUiSection(uiSections.EventsTab.Left, "Galleons", "lucide-sailboat")
	end
	uiSections.eventStatus = createUiSection(uiSections.EventsTab.Right, "Live Status", "lucide-activity")
	uiSections.eventPriority = createUiSection(uiSections.EventsTab.Right, "Automation Priority", "lucide-list-ordered")
	uiSections.eventConquest = createUiSection(uiSections.EventsTab.Right, "Crew Conquest", "lucide-flag")
	Window:CreateLabel(uiSections.eventPriority, {
		Text = "Active Dungeon > Major Sea Events > World/Raid Bosses > Serpent > Galleons > Dungeon Entry > Fishing",
		Color = SpectrumX.Theme.TextSecondary,
		Wrapped = true,
	})

	uiSections.dungeonEntry = createUiSection(uiSections.DungeonTab.Left, "Entry", "lucide-log-in")
	uiSections.dungeonSafety = createUiSection(uiSections.DungeonTab.Left, "Safety", "lucide-shield")
	uiSections.dungeonLoadout = createUiSection(uiSections.DungeonTab.Right, "Loadout & Attacks", "lucide-swords")
	uiSections.dungeonPosition = createUiSection(uiSections.DungeonTab.Right, "Positioning", "lucide-locate-fixed")
	uiSections.dungeonGuide = createUiSection(uiSections.DungeonTab.Right, "Shared Combat Settings", "lucide-info")

	if game.PlaceId == 4520749081 then
		uiSections.progressSea = createUiSection(uiSections.ProgressTab.Left, "Second Sea", "lucide-waves")
	elseif game.PlaceId == 6381829480 then
		uiSections.progressSea = createUiSection(uiSections.ProgressTab.Left, "Third Sea", "lucide-waves")
	end
	if game.PlaceId == 6381829480 then
		uiSections.progressHaki = createUiSection(uiSections.ProgressTab.Left, "Haki V2", "lucide-shield")
	end
	if game.PlaceId == 4520749081 or game.PlaceId == 6381829480 or game.PlaceId == 15759515082 then
		uiSections.progressDaily = createUiSection(uiSections.ProgressTab.Left, "Daily Quests", "lucide-calendar-check")
	end
	uiSections.progressStats = createUiSection(uiSections.ProgressTab.Right, "Stat Distribution", "lucide-signal-high")
	uiSections.progressPassives = createUiSection(uiSections.ProgressTab.Right, "Passives", "lucide-book")
	uiSections.progressPlayer = createUiSection(uiSections.ProgressTab.Right, "Player Utilities", "lucide-gamepad")

	uiSections.itemFruits = createUiSection(uiSections.ItemsTab.Left, "Fruit Automation", "lucide-apple")
	uiSections.itemKeys = createUiSection(uiSections.ItemsTab.Left, "Keys", "lucide-key")
	uiSections.itemRandomFruit = createUiSection(uiSections.ItemsTab.Left, "Random Fruits", "lucide-japanese-yen")
	uiSections.itemMaterials = createUiSection(uiSections.ItemsTab.Right, "Material Dealer", "lucide-leaf")
	uiSections.itemStyles = createUiSection(uiSections.ItemsTab.Right, "Fighting Styles", "lucide-moon")

	uiSections.teleportIslands = createUiSection(uiSections.TeleportTab.Left, "Island Teleports", "lucide-map")
	uiSections.teleportLocations = createUiSection(uiSections.TeleportTab.Right, "Location Teleports", "lucide-map-pin")
	if game.PlaceId == 15759515082 then
		uiSections.teleportRace = createUiSection(uiSections.TeleportTab.Right, "Race Island", "lucide-flag")
	end

	uiSections.settingsDisplay = createUiSection(uiSections.SettingsTab.Left, "Display & Performance", "lucide-gauge")
	uiSections.settingsScript = createUiSection(uiSections.SettingsTab.Right, "Script Control", "lucide-power")
	Window:CreateLabel(uiSections.settingsScript, {
		Text = "Stops Genesis workers, disconnects tracked events, releases movement locks, and removes the UI. Saved settings are kept.",
		Color = SpectrumX.Theme.TextSecondary,
		Wrapped = true,
	})
	Window:CreateButton(uiSections.settingsScript, {
		Text = "Unload Script",
		Style = "danger",
		Callback = function()
			local runtime = getGenesisRuntimeState()
			if runtime and type(runtime.unload) == "function" then
				runtime.unload()
			else
				warn("[GENESIS HUB] No active runtime was found to unload.")
			end
		end,
	})

	Window:CreateMultiDropdown(uiSections.farmGeneral, {
		Label = "Select Tools",
		Options = { "Mele", "Sword", "Fruit" },
		Default = GetSetting("selectedTools") or { "Mele" },
		Callback = function(selected)
			saveAndApply("selectedTools", selected)
		end,
	})

	Window:CreateDropdown(uiSections.farmGeneral, {
		Label = "Farm Method",
		Options = { "Default (Smart)", "Sigma (Smooth)" },
		Default = GetSetting("farmMethod") or "Default (Smart)",
		Callback = function(selected)
			saveAndApply("farmMethod", selected)
			SpectrumX:Notify({
				Title = "FARM METHOD",
				Text = selected == "Sigma (Smooth)" and "Sigma: multi-tool M1 remote + skills remote (no tool switch)"
					or "Default: tool switch + keyboard skills",
				Type = "info",
				Duration = 4,
			})
		end,
	})

	Window:CreateSlider(uiSections.farmGeneral, {
		Text = "Tool Switch Speed (sec)",
		Min = 0.1,
		Max = 2,
		Default = GetSetting("toolSwitchSpeed") or 0.5,
		Increment = 0.1,
		Callback = function(value)
			saveAndApply("toolSwitchSpeed", value)
		end,
	})

	Window:CreateSlider(uiSections.farmGeneral, {
		Text = "Farm Distance",
		Min = 1,
		Max = 50,
		Default = GetSetting("distance") or 8,
		Callback = function(value)
			saveAndApply("distance", value)
		end,
	})

	Window:CreateToggle(uiSections.farmMaterial, {
		Text = "Auto Take Quest",
		Default = GetSetting("getQuestMaterial") or false,
		Callback = function(state)
			saveAndApply("getQuestMaterial", state)
		end,
	})

	Window:CreateToggle(uiSections.combatHaki, {
		Text = "Buso (Armament)",
		Default = GetSetting("buso"),
		Callback = function(state)
			saveAndApply("buso", state)
		end,
	})

	Window:CreateToggle(uiSections.combatHaki, {
		Text = "Ken (Observation)",
		Default = GetSetting("ken"),
		Callback = function(state)
			saveAndApply("ken", state)
		end,
	})

	Window:CreateToggle(uiSections.combatHaki, {
		Text = "Hao (Conqueror's)",
		Default = GetSetting("hao"),
		Callback = function(state)
			saveAndApply("hao", state)
		end,
	})

	Window:CreateToggle(uiSections.combatUtility, {
		Text = "Walk On Water",
		Default = GetSetting("walkOnWater"),
		Callback = function(state)
			saveAndApply("walkOnWater", state)
		end,
	})

	Window:CreateToggle(uiSections.combatUtility, {
		Text = "V Method (Zoan & Ope)",
		Default = GetSetting("opeMethod") or false,
		Callback = function(state)
			saveAndApply("opeMethod", state)
		end,
	})

	Window:CreateToggle(uiSections.combatRace, {
		Text = "Auto Activate Race",
		Default = GetSetting("autoRaceV3") or false,
		Callback = function(state)
			saveAndApply("autoRaceV3", state)
		end,
	})

	Window:CreateSlider(uiSections.combatRace, {
		Text = "HP% to Activate Race",
		Min = 1,
		Max = 100,
		Default = GetSetting("raceV3HealthPercent") or 30,
		Increment = 1,
		Callback = function(value)
			saveAndApply("raceV3HealthPercent", value)
		end,
	})

	Window:CreateLabel(uiSections.combatRace, {
		Text = "\240\159\146\161 It is recommended that you have the Sea Beast Race.",
		Color = SpectrumX.Theme.TextSecondary,
		Size = UDim2.new(1, 0, 0, 40),
	})

	Window:CreateToggle(uiSections.farmLevel, {
		Text = "Auto Farm Level",
		Default = GetSetting("auto_farm") or false,
		Callback = function(state)
			saveAndApply("auto_farm", state)
		end,
	})

	local materialOptions = getMaterialsForCurrentSea()
	local defaultMaterial = GetSetting("material") or materialOptions[1] or "Leather"

	Window:CreateDropdown(uiSections.farmMaterial, {
		Label = "Select Material",
		Options = materialOptions,
		Default = defaultMaterial,
		Callback = function(selected)
			saveAndApply("material", selected)
		end,
	})

	Window:CreateToggle(uiSections.farmMaterial, {
		Text = "Farm Material",
		Default = GetSetting("farmmaterial") or false,
		Callback = function(state)
			saveAndApply("farmmaterial", state)
		end,
	})

	local bossOptions, bossDataTable = getBossesForDropdown()
	local defaultBoss = GetSetting("selectedBoss") or (bossOptions[1] or "Select Boss")

	Window:CreateDropdown(uiSections.farmBoss, {
		Label = "Select Boss",
		Options = bossOptions,
		Default = defaultBoss,
		Callback = function(selected)
			saveAndApply("selectedBoss", selected)

			local bossName = getBossNameFromDropdown(selected)
			_G.selectedBossCFrame = getBossCFrame(bossName)
			_G.selectedBossName = bossName
		end,
	})

	Window:CreateToggle(uiSections.farmBoss, {
		Text = "Auto Farm Selected Boss",
		Default = GetSetting("autoFarmBoss") or false,
		Callback = function(state)
			saveAndApply("autoFarmBoss", state)
			if state then
				local selectedBoss = GetSetting("selectedBoss")
				if selectedBoss then
					local bossName = getBossNameFromDropdown(selectedBoss)
					_G.selectedBossName = bossName
					_G.selectedBossCFrame = getBossCFrame(bossName)
				end

				if GetSetting("auto_farm") then
					saveAndApply("auto_farm", false)
					SpectrumX:Notify({
						Text = "Auto Farm Level disabled to avoid conflict",
						Type = "warning",
						Duration = 2,
					})
				end
			end
		end,
	})

	local fishPositionLabel = Window:CreateLabel(uiSections.farmFishing, {
		Text = "Pos: Not Set",
		Color = SpectrumX.Theme.TextSecondary,
		Size = UDim2.new(1, 0, 0, 25),
	})

	_G._GenesisRefreshFishingPositionLabel = function()
		local cf, issue, config = _G._GenesisGetConfiguredFishingCFrame(game.PlaceId)
		if typeof(cf) == "CFrame" and config then
			fishPositionLabel.SetText(
				"Sea "
					.. tostring(config.sea)
					.. " Pos: "
					.. tostring(math.floor(cf.X))
					.. ", "
					.. tostring(math.floor(cf.Y))
					.. ", "
					.. tostring(math.floor(cf.Z))
			)
			fishPositionLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
		elseif config then
			fishPositionLabel.SetText("Sea " .. tostring(config.sea) .. " Pos: Not Set")
			fishPositionLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
		else
			fishPositionLabel.SetText(issue or "Fishing position unavailable")
			fishPositionLabel.Label.TextColor3 = SpectrumX.Theme.Warning
		end
	end
	_G._GenesisRefreshFishingPositionLabel()

	Window:CreateButton(uiSections.farmFishing, {
		Text = "Save Fishing Position",
		Callback = function()
			local root = GetRoot(LocalPlayer.Character)
			local config = _G._GenesisGetFishingPositionConfig(game.PlaceId)
			if root and config then
				local positions = GetSetting("fishPositionsBySea")
				if type(positions) ~= "table" then
					positions = {}
				end
				positions[config.slot] = { root.CFrame:GetComponents() }
				saveAndApply("fishPositionsBySea", positions)
				_G._GenesisRefreshFishingPositionLabel()
				SpectrumX:Notify({
					Text = "Sea " .. tostring(config.sea) .. " fishing position saved!",
					Type = "success",
					Duration = 2,
				})
			elseif not config then
				SpectrumX:Notify({
					Text = "Fishing position is unsupported in this sea.",
					Type = "warning",
					Duration = 2,
				})
			end
		end,
	})

	Window:CreateToggle(uiSections.farmFishing, {
		Text = "Auto Fish (Perfect Catch)",
		Default = GetSetting("autoFish") or false,
		Callback = function(state)
			saveAndApply("autoFish", state)
		end,
	})

	Window:CreateToggle(uiSections.farmFishing, {
		Text = "In Serpent Whirlpool",
		Default = GetSetting("inSerpentWhirlpool") or false,
		Callback = function(state)
			saveAndApply("inSerpentWhirlpool", state)
		end,
	})

	Window:CreateToggle(uiSections.farmFishing, {
		Text = "Fish Between Boss Spawns",
		Default = GetSetting("fishWhenNotSpawned") or false,
		Callback = function(state)
			saveAndApply("fishWhenNotSpawned", state)
		end,
	})

	Window:CreateToggle(uiSections.farmBoss, {
		Text = "Auto Farm Bounty (Legit)",
		Default = GetSetting("easybounty") or false,
		Callback = function(state)
			saveAndApply("easybounty", state)
			if state then
				loadBossesForCurrentSea()
				_G.currentBossIndex = 1
				_G.bossesKilled = {}
			end
		end,
	})

	if game.PlaceId == 15759515082 then
		Window:CreateToggle(uiSections.farmPearl, {
			Text = "Auto Collect Pearl",
			Default = GetSetting("autoCollectPearl") or false,
			Callback = function(state)
				saveAndApply("autoCollectPearl", state)
			end,
		})
	end

	Window:CreateSlider(uiSections.farmNearby, {
		Text = "Detection Distance",
		Min = 50,
		Max = 10000,
		Default = GetSetting("distancemob") or 200,
		Callback = function(value)
			saveAndApply("distancemob", value)
		end,
	})

	Window:CreateToggle(uiSections.farmBoss, {
		Text = "Auto Kill All Bosses",
		Default = GetSetting("allboss") or false,
		Callback = function(state)
			saveAndApply("allboss", state)
		end,
	})

	Window:CreateToggle(uiSections.farmNearby, {
		Text = "Auto Kill Nearby Mobs",
		Default = GetSetting("autoKillMobs") or false,
		Callback = function(state)
			saveAndApply("autoKillMobs", state)
		end,
	})

	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill Z",
		Default = GetSetting("z"),
		Callback = function(state)
			saveAndApply("z", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill X",
		Default = GetSetting("x"),
		Callback = function(state)
			saveAndApply("x", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill C",
		Default = GetSetting("c"),
		Callback = function(state)
			saveAndApply("c", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill V",
		Default = GetSetting("v"),
		Callback = function(state)
			saveAndApply("v", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill F",
		Default = GetSetting("f"),
		Callback = function(state)
			saveAndApply("f", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill B",
		Default = GetSetting("b"),
		Callback = function(state)
			saveAndApply("b", state)
		end,
	})
	Window:CreateToggle(uiSections.combatSkills, {
		Text = "Skill E",
		Default = GetSetting("e"),
		Callback = function(state)
			saveAndApply("e", state)
		end,
	})

	Window:CreateNumberInput(uiSections.progressStats, {
		Label = "Point Quantity",
		Default = GetSetting("distributeValue") or 1,
		Min = 1,
		Max = 10000,
		Callback = function(value)
			saveAndApply("distributeValue", value)
		end,
	})

	Window:CreateToggle(uiSections.progressStats, {
		Text = "Auto Distribute",
		Default = GetSetting("autoDistribute") or false,
		Callback = function(state)
			saveAndApply("autoDistribute", state)
		end,
	})

	Window:CreateToggle(uiSections.progressStats, {
		Text = "In Melee",
		Default = GetSetting("autoMelee") or false,
		Callback = function(state)
			saveAndApply("autoMelee", state)
		end,
	})

	Window:CreateToggle(uiSections.progressStats, {
		Text = "In Defense",
		Default = GetSetting("autoDefense") or false,
		Callback = function(state)
			saveAndApply("autoDefense", state)
		end,
	})

	Window:CreateToggle(uiSections.progressStats, {
		Text = "In Sword",
		Default = GetSetting("autoSword") or false,
		Callback = function(state)
			saveAndApply("autoSword", state)
		end,
	})

	Window:CreateToggle(uiSections.progressStats, {
		Text = "In Fruit",
		Default = GetSetting("autoFruit") or false,
		Callback = function(state)
			saveAndApply("autoFruit", state)
		end,
	})

	raidStatusLabel = Window:CreateLabel(uiSections.eventStatus, {
		Text = "Spawned: None",
		Color = SpectrumX.Theme.TextSecondary,
		Wrapped = true,
	})

	if game.PlaceId == 15759515082 then
		RaceIslandStatusLabel = Window:CreateLabel(uiSections.eventStatus, {
			Text = "Race Island:",
			Color = SpectrumX.Theme.TextSecondary,
			Size = UDim2.new(1, 0, 0, 25),
		})
	end

	local serpentTimerLabel = Window:CreateLabel(uiSections.eventStatus, {
		Text = "Serpent: --:--",
		Color = SpectrumX.Theme.TextSecondary,
		Wrapped = true,
	})

	if game.PlaceId == 6381829480 then
		SeaKingTimerLabel = Window:CreateLabel(uiSections.eventStatus, {
			Text = "Sea King: --:--",
			Color = SpectrumX.Theme.Warning,
			Size = UDim2.new(1, 0, 0, 20),
		})

		GhostShipTimerLabel = Window:CreateLabel(uiSections.eventStatus, {
			Text = "Ghost Ship: --:--",
			Color = SpectrumX.Theme.Warning,
			Size = UDim2.new(1, 0, 0, 20),
		})
	elseif game.PlaceId == 15759515082 then
		Sea3EventsTimerLabel = Window:CreateLabel(uiSections.eventStatus, {
			Text = "Set Sail: --:--",
			Color = SpectrumX.Theme.Warning,
			Size = UDim2.new(1, 0, 0, 25),
		})

		GalleonStatusLabel = Window:CreateLabel(uiSections.eventStatus, {
			Text = "Galleon: \240\159\148\180 Spawns Soon",
			Color = SpectrumX.Theme.Warning,
			Size = UDim2.new(1, 0, 0, 25),
		})
	end

	local bosses = raidBossSettings[game.PlaceId] or {}
	for _, boss in ipairs(bosses) do
		Window:CreateToggle(uiSections.eventRaid, {
			Text = "Auto Kill " .. boss.name,
			Default = GetSetting(boss.key) or false,
			Callback = function(state)
				saveAndApply(boss.key, state)
			end,
		})
	end

	Window:CreateToggle(uiSections.eventSerpent, {
		Text = "Auto Kill Serpent",
		Default = GetSetting("autoHuntSerpent") or false,
		Callback = function(state)
			saveAndApply("autoHuntSerpent", state)
		end,
	})

	if game.PlaceId == 6381829480 then
		Window:CreateToggle(uiSections.eventMajor, {
			Text = "Auto Kill Sea King & Hydra",
			Default = GetSetting("autoSKHD") or false,
			Callback = function(state)
				saveAndApply("autoSKHD", state)
			end,
		})

		Window:CreateToggle(uiSections.eventGalleon, {
			Text = "Auto Kill Ghost Ship",
			Default = GetSetting("autoGhostShip") or false,
			Callback = function(state)
				saveAndApply("autoGhostShip", state)
			end,
		})

		Window:CreateToggle(uiSections.eventGalleon, {
			Text = "Auto Hop After Ghost Ship Loot",
			Default = GetSetting("autoHopSeaBosses") or false,
			Callback = function(state)
				saveAndApply("autoHopSeaBosses", state)
			end,
		})
	elseif game.PlaceId == 15759515082 then
		Window:CreateToggle(uiSections.eventMajor, {
			Text = "Auto Kill Kraken",
			Default = GetSetting("autoKillKraken") or false,
			Callback = function(state)
				saveAndApply("autoKillKraken", state)
			end,
		})
		Window:CreateToggle(uiSections.eventMajor, {
			Text = "Auto Kill Drakenfyr",
			Default = GetSetting("autoKillDrakenfyr") or false,
			Callback = function(state)
				saveAndApply("autoKillDrakenfyr", state)
			end,
		})
		Window:CreateToggle(uiSections.eventMajor, {
			Text = "Auto Kill Abyssal Tyrant",
			Default = GetSetting("autoKillAbyssalTyrant") or false,
			Callback = function(state)
				saveAndApply("autoKillAbyssalTyrant", state)
				if not state and type(_G._stopAbyssalAcquisition) == "function" then
					_G._stopAbyssalAcquisition()
				end
			end,
		})
		Window:CreateToggle(uiSections.eventMajor, {
			Text = "Auto Kill Deepsea Crusher",
			Default = GetSetting("autoKillDeepseaCrusher") or false,
			Callback = function(state)
				saveAndApply("autoKillDeepseaCrusher", state)
			end,
		})
		Window:CreateToggle(uiSections.eventGalleon, {
			Text = "Auto Kill Galleons",
			Default = GetSetting("autoKillGalleons") or false,
			Callback = function(state)
				saveAndApply("autoKillGalleons", state)
			end,
		})
	end

	local _smartHopHasAccess = false
	pcall(function()
		_smartHopHasAccess = hasSmartHopAccess() == true
	end)

	local smartHopSection = Window:CreateSection(uiSections.ServerTab.Right, {
		Text = "Smart Hop (Premium)",
		Icon = "lucide-crown",
		Locked = not _smartHopHasAccess,
	})

	do
		local _rawSetLocked = smartHopSection.SetLocked
		smartHopSection.SetLocked = function(v, instant)
			if v == false or v == nil then
				local ok = false
				pcall(function()
					ok = hasSmartHopAccess() == true
				end)
				if not ok then
					_rawSetLocked(true, instant == true)
					SpectrumX:Notify({
						Title = "SMART HOP",
						Text = "PREMIUM ACCESS REQUIRED!",
						Type = "error",
						Duration = 3,
					})
					return
				end
				_rawSetLocked(false, instant)
			else
				_rawSetLocked(true, instant)
			end
		end
		smartHopSection.Unlock = function(instant)
			smartHopSection.SetLocked(false, instant)
		end
		smartHopSection.Lock = function(instant)
			smartHopSection.SetLocked(true, instant)
		end
	end

	if _smartHopHasAccess then
		smartHopSection.SetLocked(false, true)
	end

	local smartHopContent = smartHopSection.Content

	local currentEventOptions = seaEventOptions
	local currentRaidOptions = raidBossOptions

	local _lastDropdownPlaceId = game.PlaceId

	Window:CreateMultiDropdown(smartHopContent, {
		Label = "Target Sea Events",
		Options = seaEventOptions,
		Default = getFilteredDefaultEvent(),
		Callback = function(selected)
			saveAndApply("smartHopTargetEvent", selected)
		end,
	})

	Window:CreateMultiDropdown(smartHopContent, {
		Label = "Target Raid Bosses",
		Options = raidBossOptions,
		Default = getFilteredDefaultRaid(),
		Callback = function(selected)
			saveAndApply("smartHopTargetRaid", selected)
		end,
	})

	Window:CreateDropdown(smartHopContent, {
		Label = "Customized Priority",
		Options = { "Sea Events", "Raid Bosses", "Both" },
		Default = GetSetting("smartHopPriority") or "Both",
		Callback = function(value)
			saveAndApply("smartHopPriority", value)
		end,
	})

	Window:CreateToggle(smartHopContent, {
		Text = "Smart Hop (Event Servers Only)",
		Default = GetSetting("autoSmartHop") or false,
		Callback = function(state)
			if state then
				local ok = false
				pcall(function()
					ok = hasSmartHopAccess() == true
				end)
				if not ok then
					saveAndApply("autoSmartHop", false)
					SpectrumX:Notify({
						Title = "SMART HOP",
						Text = "PREMIUM ACCESS REQUIRED!",
						Type = "error",
						Duration = 3,
					})
					smartHopSection.SetLocked(true)
					return
				end
			end
			saveAndApply("autoSmartHop", state)
		end,
	})

	Window:CreateSlider(smartHopContent, {
		Text = "Smart Hop Delay (seconds)",
		Min = 1,
		Max = 60,
		Default = GetSetting("smartHopTimer") or 30,
		Callback = function(value)
			saveAndApply("smartHopTimer", value)
		end,
	})

	-- Revalidate access every 0.5 seconds: unlock immediately when Premium is gained; lock again when it is lost.
	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not smartHopSection or not smartHopSection.IsLocked then
					return
				end
				local ok = hasSmartHopAccess() == true
				if ok then
					if smartHopSection.IsLocked() then
						smartHopSection.SetLocked(false) -- gate passa porque tem acesso
					end
				else
					if not smartHopSection.IsLocked() then
						smartHopSection.SetLocked(true)
					end
					if GetSetting("autoSmartHop") then
						saveAndApply("autoSmartHop", false)
					end
				end
			end)
		end
	end)

	Window:CreateDropdown(uiSections.itemKeys, {
		Label = "Select Key Type",
		Options = { "Copper Key", "Iron Key", "Gold Key", "Platinum Key" },
		Default = GetSetting("key1") or "Copper Key",
		Callback = function(selected)
			saveAndApply("key1", selected)
		end,
	})

	Window:CreateSlider(uiSections.itemKeys, {
		Text = "Amount to Buy",
		Min = 1,
		Max = 99,
		Default = GetSetting("key_count") or 1,
		Callback = function(value)
			saveAndApply("key_count", value)
		end,
	})

	Window:CreateToggle(uiSections.itemKeys, {
		Text = "Auto Buy Keys",
		Default = GetSetting("buykey") or false,
		Callback = function(state)
			saveAndApply("buykey", state)
		end,
	})

	Window:CreateDropdown(uiSections.itemRandomFruit, {
		Label = "Key for Random",
		Options = { "Copper Key", "Iron Key", "Gold Key", "Platinum Key" },
		Default = GetSetting("key2") or "Copper Key",
		Callback = function(selected)
			saveAndApply("key2", selected)
		end,
	})

	Window:CreateToggle(uiSections.itemRandomFruit, {
		Text = "Random Fruit x1",
		Default = GetSetting("random1") or false,
		Callback = function(state)
			saveAndApply("random1", state)
		end,
	})

	Window:CreateToggle(uiSections.itemRandomFruit, {
		Text = "Random Fruit x3",
		Default = GetSetting("random3") or false,
		Callback = function(state)
			saveAndApply("random3", state)
		end,
	})

	Window:CreateToggle(uiSections.itemRandomFruit, {
		Text = "Random Fruit x10",
		Default = GetSetting("random10") or false,
		Callback = function(state)
			saveAndApply("random10", state)
		end,
	})

	Window:CreateButton(uiSections.itemMaterials, {
		Text = "Open Material Shop",
		Callback = function()
			if type(_G._GenesisEnsureMaterialShopReady) == "function" then
				_G._GenesisEnsureMaterialShopReady(true, true)
			end
		end,
	})

	local materialDropdown = Window:CreateMultiDropdown(uiSections.itemMaterials, {
		Label = "Select Materials",
		Options = {
			"Dragon's Orb",
			"Twilight's Orb",
			"Hydra's Tail",
			"Phoenix's Tear",
			"Dragon Fang",
			"Shark's Canine",
			"Sea King's Fin",
			"Sea's Wraith",
			"Vampire's Vital Fluid",
			"Magma Crystal",
			"Essence of Fire",
			"Ice Crystal",
			"Lost Ruby",
			"Samurai's Badage",
			"Lucidus's Totem",
			"Dark Beard's Totem",
			"Kraken's Ink",
			"Crab Meat",
			"Severed Kraken",
			"Dragon Scale",
			"Gunpowder",
			"Sea King's Blood",
			"Pearl",
			"Fresh Fish",
			"Bread Crumbs",
			"Iron Ingot",
			"Undead's Ooze",
			"Thief's Rag",
			"Coral",
			"Shark's Fin",
			"Leather",
			"Log",
			"Rusted Scrap",
			"Angellic's Feather",
			"Carrot",
			"Pile of Bones",
			"Sea Artifact",
		},
		Default = GetSetting("selectedMaterials") or {},
		Callback = function(selected)
			saveAndApply("selectedMaterials", selected)
		end,
	})

	Window:CreateButton(uiSections.itemMaterials, {
		Text = "Select All",
		Callback = function()
			local allMaterials = {
				"Dragon's Orb",
				"Twilight's Orb",
				"Hydra's Tail",
				"Phoenix's Tear",
				"Dragon Fang",
				"Shark's Canine",
				"Sea King's Fin",
				"Sea's Wraith",
				"Vampire's Vital Fluid",
				"Magma Crystal",
				"Essence of Fire",
				"Ice Crystal",
				"Lost Ruby",
				"Samurai's Badage",
				"Lucidus's Totem",
				"Dark Beard's Totem",
				"Kraken's Ink",
				"Crab Meat",
				"Severed Kraken",
				"Dragon Scale",
				"Gunpowder",
				"Sea King's Blood",
				"Pearl",
				"Fresh Fish",
				"Bread Crumbs",
				"Iron Ingot",
				"Undead's Ooze",
				"Thief's Rag",
				"Coral",
				"Shark's Fin",
				"Leather",
				"Log",
				"Rusted Scrap",
				"Angellic's Feather",
				"Carrot",
				"Pile of Bones",
				"Sea Artifact",
			}

			if materialDropdown and materialDropdown.SetValues then
				materialDropdown:SetValues(allMaterials)
			end
			saveAndApply("selectedMaterials", allMaterials)
			GenesisX:Notify({
				Text = "All materials selected!",
				Type = "info",
				Duration = 2,
			})
		end,
	})

	Window:CreateButton(uiSections.itemMaterials, {
		Text = "Clear All",
		Callback = function()
			if materialDropdown and materialDropdown.SetValues then
				materialDropdown:SetValues({})
			end
			saveAndApply("selectedMaterials", {})
			GenesisX:Notify({
				Text = "Selection cleared!",
				Type = "info",
				Duration = 2,
			})
		end,
	})

	Window:CreateLabel(uiSections.itemMaterials, {
		Text = "Purchase Quantity: 1",
		Color = SpectrumX.Theme.TextSecondary,
	})

	Window:CreateToggle(uiSections.itemMaterials, {
		Text = "Auto Buy Selected Materials",
		Default = GetSetting("autoBuyMaterials") or false,
		Callback = function(state)
			saveAndApply("autoBuyMaterials", state)
		end,
	})

	local styles = {
		{ name = "Electro", npc = "ElectroShop", tool = "Electro" },
		{ name = "Dark Leg", npc = "DarkLegShop", tool = "DarkLeg" },
		{ name = "Dragon Claw", npc = "DragonClawShop", tool = "DragonClaw" },
		{ name = "Cyborg", npc = "CyborgShop", tool = "Cyborg" },
		{ name = "Water Style", npc = "WaterStyleShop", tool = "WaterStyle" },
	}

	local function hasStyle(toolName)
		for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
			if tool.Name == toolName then
				return true
			end
		end
		local hotbar = LocalPlayer:FindFirstChild("HotbarSlots")
		if hotbar then
			for _, slot in pairs(hotbar:GetChildren()) do
				if slot.Value == toolName then
					return true
				end
			end
		end
		return false
	end

	local buyingStyle = nil
	_G._GenesisBuyingStyleStartedAt = 0
	_G._GenesisStylePurchaseGeneration = 0
	local prevPosition = nil

	for _, style in pairs(styles) do
		Window:CreateButton(uiSections.itemStyles, {
			Text = "Buy " .. style.name,
			Callback = function()
				if hasStyle(style.tool) then
					SpectrumX:Notify({ Text = "You already have " .. style.name .. "!", Type = "error", Duration = 3 })
					return
				end
				local npc = Workspace.AllNPC:FindFirstChild(style.npc)
				if not npc then
					SpectrumX:Notify({ Text = "NPC not found!", Type = "error", Duration = 3 })
					return
				end
				local root = GetRoot(LocalPlayer.Character)
				if root then
					prevPosition = root.CFrame
				end
				tp(CFrame.new(npc.CFrame.X, npc.CFrame.Y + 3, npc.CFrame.Z))
				buyingStyle = style.tool
				_G._GenesisBuyingStyleStartedAt = tick()
				_G._GenesisStylePurchaseGeneration = (_G._GenesisStylePurchaseGeneration or 0) + 1
				SpectrumX:Notify({ Text = "Buying " .. style.name .. "...", Type = "info", Duration = 3 })
			end,
		})
	end

	if game.PlaceId == 6381829480 then
		Window:CreateToggle(uiSections.progressSea, {
			Text = "Auto Third Sea",
			Default = GetSetting("autoThirdSea") or false,
			Callback = function(state)
				saveAndApply("autoThirdSea", state)
				if not state then
					_G.thirdSeaState = "idle"
					_G.thirdSeaSquidTimer = 0
				end
			end,
		})

		local labelNivel = Window:CreateLabel(uiSections.progressSea, { Text = "Level: 0/4000" })
		local labelHeart = Window:CreateLabel(uiSections.progressSea, { Text = "Heart of Sea: 0" })
		local labelStatus = Window:CreateLabel(uiSections.progressSea, { Text = "Third Sea Not Unlocked" })

		spawn(function()
			while task.wait(1) do
				pcall(function()
					if game.PlaceId ~= 6381829480 then
						return
					end

					local matValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
					local heartCount = 0
					if matValue then
						local ok, data = pcall(function()
							return HttpService:JSONDecode(matValue.Value)
						end)
						if ok and data then
							heartCount = data["Heart of Sea"] or 0
						end
					end

					local level = LocalPlayer.PlayerStats:FindFirstChild("lvl")
					local playerLevel = level and level.Value or 0
					local levelOk = playerLevel >= 4000
					local heartOk = heartCount >= 1
					local thirdOk = _G.hasThirdSea()

					labelNivel.SetText(
						(levelOk and "\226\156\133 \194\183 " or "\226\157\142 \194\183 ")
							.. "Level: "
							.. playerLevel
							.. "/4000"
					)
					labelHeart.SetText(
						(heartOk and "\226\156\133 \194\183 " or "\226\157\142 \194\183 ")
							.. "Heart of Sea: "
							.. heartCount
					)

					if thirdOk then
						labelStatus.SetText(" Third Sea Already Unlocked!")
					else
						labelStatus.SetText(" Third Sea Not Unlocked Yet ...")
					end
				end)
			end
		end)
	end

	if game.PlaceId == 4520749081 then
		Window:CreateToggle(uiSections.progressSea, {
			Text = "Auto Second Sea",
			Default = GetSetting("autoSecondSea") or false,
			Callback = function(state)
				saveAndApply("autoSecondSea", state)
			end,
		})
	end

	if game.PlaceId == 6381829480 then
		local kenV2StatusLabel = Window:CreateLabel(uiSections.progressHaki, { Text = "Ken V2: Idle" })
		local busoV2StatusLabel = Window:CreateLabel(uiSections.progressHaki, { Text = "Buso V2: Idle" })

		Window:CreateToggle(uiSections.progressHaki, {
			Text = "Auto Unlock Buso V2",
			Default = GetSetting("autoBusoV2") or false,
			Callback = function(state)
				saveAndApply("autoBusoV2", state)
				if not state then
					_G.isProgressingBusoV2 = false
					_G.busoV2Status = "Idle"
				end
			end,
		})

		Window:CreateToggle(uiSections.progressHaki, {
			Text = "Auto Unlock Ken V2 (Observation)",
			Default = GetSetting("autoKenV2") or false,
			Callback = function(state)
				saveAndApply("autoKenV2", state)
				if not state then
					_G.isProgressingObservationV2 = false
					_G.kenV2Status = "Idle"
				end
			end,
		})

		spawn(function()
			while task.wait(0.8) do
				pcall(function()
					if busoV2StatusLabel then
						busoV2StatusLabel.SetText(" \226\128\148 Buso V2: " .. tostring(_G.busoV2Status or "Idle"))
					end
					if kenV2StatusLabel then
						kenV2StatusLabel.SetText(" \226\128\148 Ken V2: " .. tostring(_G.kenV2Status or "Idle"))
					end
				end)
			end
		end)

		Window:CreateToggle(uiSections.farmSpecialBoss, {
			Text = "Auto Farm Kaido",
			Default = GetSetting("autoFarmKaido") or false,
			Callback = function(state)
				saveAndApply("autoFarmKaido", state)
			end,
		})

		Window:CreateToggle(uiSections.farmSpecialBoss, {
			Text = "Auto Farm Crimson Demon",
			Default = GetSetting("autoCrimsonDemon") or false,
			Callback = function(state)
				saveAndApply("autoCrimsonDemon", state)
			end,
		})

		Window:CreateToggle(uiSections.farmSpecialBoss, {
			Text = "Auto Farm Ice King",
			Default = GetSetting("autoIceKing") or false,
			Callback = function(state)
				saveAndApply("autoIceKing", state)
			end,
		})

		Window:CreateToggle(uiSections.farmSpecialBoss, {
			Text = "Auto Farm Dark Beard",
			Default = GetSetting("autoDarkBeard") or false,
			Callback = function(state)
				saveAndApply("autoDarkBeard", state)
			end,
		})
	end

	if uiSections.progressDaily then
		local function resetDailyRoute()
			dailyCoordinator.journal.route = nil
			_G._GenesisDailyQuestTravelPending = false
			_G._GenesisDailyReturnRequested = false
			dailyCoordinator.save()
			_G.dailyQuestState = "idle"
			_G.dailyQuestKills = 0
		end
		Window:CreateToggle(uiSections.progressDaily, {
			Text = "Auto Daily Quests",
			Default = GetSetting("autoDailyQuestsMaster") or false,
			Callback = function(state)
				saveAndApply("autoDailyQuestsMaster", state)
				resetDailyRoute()
			end,
		})

		local subToggles = Instance.new("Frame")
		subToggles.Name = "DailyQuestSeaToggles"
		subToggles.BackgroundTransparency = 1
		subToggles.Size = UDim2.new(1, 0, 0, 0)
		subToggles.AutomaticSize = Enum.AutomaticSize.Y
		subToggles.Parent = uiSections.progressDaily
		local subPadding = Instance.new("UIPadding")
		subPadding.PaddingLeft = UDim.new(0, Window:S(14))
		subPadding.Parent = subToggles
		local subLayout = Instance.new("UIListLayout")
		subLayout.Padding = UDim.new(0, Window:S(6))
		subLayout.Parent = subToggles
		Window:CreateToggle(subToggles, {
			Text = "Third Sea Daily Quests",
			Default = GetSetting("autoDailyQuest") or false,
			Callback = function(state)
				saveAndApply("autoDailyQuest", state)
				resetDailyRoute()
			end,
		})
		Window:CreateToggle(subToggles, {
			Text = "Second Sea Daily Quests",
			Default = GetSetting("autoSecondSeaDailyQuest") or false,
			Callback = function(state)
				saveAndApply("autoSecondSeaDailyQuest", state)
				resetDailyRoute()
			end,
		})

		local function mainSeaOptions()
			local options = {}
			for rank = 1, dailyCoordinator.refreshAccess() do
				table.insert(options, dailyCoordinator.sea[rank].label)
			end
			return options
		end
		local mainSeaDropdown = Window:CreateDropdown(uiSections.progressDaily, {
			Label = "Main Sea",
			Options = mainSeaOptions(),
			Default = dailyCoordinator.sea[dailyCoordinator.mainRank()].label,
			Callback = function(label)
				for rank, info in pairs(dailyCoordinator.sea) do
					if label == info.label then
						dailyCoordinator.setMainRank(rank)
						break
					end
				end
			end,
		})
		spawn(function()
			LocalPlayer:WaitForChild("PlayerStats")
			local lastUnlocked = 0
			local lastMain = 0
			while true do
				local unlocked = dailyCoordinator.refreshAccess()
				local main = dailyCoordinator.mainRank()
				if unlocked ~= lastUnlocked then
					mainSeaDropdown.SetOptions(mainSeaOptions())
					lastUnlocked = unlocked
				end
				if main ~= lastMain then
					mainSeaDropdown.SetValue(dailyCoordinator.sea[main].label)
					lastMain = main
				end
				task.wait(5)
			end
		end)
	end

	Window:CreateToggle(uiSections.itemFruits, {
		Text = "Bring Fruits (Auto Collect)",
		Default = GetSetting("bringFruits") or false,
		Callback = function(state)
			saveAndApply("bringFruits", state)
		end,
	})

	Window:CreateToggle(uiSections.itemFruits, {
		Text = "Auto Store Fruits",
		Default = GetSetting("autoStoreFruits") or false,
		Callback = function(state)
			saveAndApply("autoStoreFruits", state)
		end,
	})

	Window:CreateToggle(uiSections.settingsDisplay, {
		Text = "Hide Game Notifications",
		Default = GetSetting("hideNotify") or false,
		Callback = function(state)
			saveAndApply("hideNotify", state)
			applyHideNotify(state)
		end,
	})

	Window:CreateToggle(uiSections.settingsDisplay, {
		Text = "Black Screen",
		Default = GetSetting("blackScreen") or false,
		Callback = function(state)
			saveAndApply("blackScreen", state)
			applyBlackScreen(state)
		end,
	})

	local islandDropdown = nil
	local currentSeaIslands = {}

	local function updateIslandDropdown()
		local placeId = game.PlaceId
		local islands = islandsBySea[placeId] or {}
		currentSeaIslands = islands
		if islandDropdown then
			islandDropdown.SetOptions(islands)
			if #islands > 0 then
				islandDropdown.SetValue(islands[1])
			else
				islandDropdown.SetValue("")
			end
		end
	end

	islandDropdown = Window:CreateDropdown(uiSections.teleportIslands, {
		Label = "Islands List",
		Options = islandsBySea[game.PlaceId] or {},
		Default = (islandsBySea[game.PlaceId] or {})[1] or "",
		Callback = function(selected) end,
	})

	Window:CreateButton(uiSections.teleportIslands, {
		Text = "Teleport To Island",
		Style = "accent",
		Callback = function()
			local selected = islandDropdown.GetValue()
			if not selected or selected == "" then
				GenesisX:Notify({ Text = "Select an island first!", Type = "error", Duration = 2 })
				return
			end
			local cf = islandsCFrame[selected]
			if not cf then
				GenesisX:Notify({ Text = "Island coordinate not found!", Type = "error", Duration = 2 })
				return
			end
			local root = GetRoot(LocalPlayer.Character)
			if root then
				_GBackPosition = root.CFrame
			else
				_GBackPosition = nil
			end
			tp(cf)
			GenesisX:Notify({ Text = "Teleported to " .. selected, Type = "success", Duration = 2 })
		end,
	})

	Window:CreateButton(uiSections.teleportIslands, {
		Text = "Teleport Back",
		Style = "default",
		Callback = function()
			if not _GBackPosition then
				GenesisX:Notify({ Text = "No saved position to return to!", Type = "error", Duration = 2 })
				return
			end
			tp(_GBackPosition)
			GenesisX:Notify({ Text = "Returned to previous position!", Type = "success", Duration = 2 })
			_GBackPosition = nil
		end,
	})

	if game.PlaceId == 15759515082 then
		Window:CreateButton(uiSections.teleportRace, {
			Text = "Teleport to Race Island",
			Style = "info",
			Callback = function()
				local root = GetRoot(LocalPlayer.Character)
				local returnPosition = root and root.CFrame or nil
				local ok, result = _G._GenesisTeleportToRaceIsland()
				if ok then
					_GBackPosition = returnPosition
				end
				SpectrumX:Notify({
					Text = ok and ("Teleported to " .. tostring(result) .. " Race Island.") or tostring(result),
					Type = ok and "success" or "warning",
					Duration = 4,
				})
			end,
		})
	end

	do
		local locationTeleportOptions = {
			"Boss Chalice",
		}
		local locationTeleports = {
			["Boss Chalice"] = {
				placeId = 15759515082,
				cframe = CFrame.new(
					2245.7707519531,
					363.50967407227,
					-1204.8427734375,
					0.12241239845753,
					-1.1466188887255e-08,
					-0.99247932434082,
					9.3516952404116e-08,
					1,
					-1.8695366435506e-11,
					0.99247932434082,
					-9.2811355045797e-08,
					0.12241239845753
				),
			},
		}
		local locationDropdown = Window:CreateDropdown(uiSections.teleportLocations, {
			Label = "Locations List",
			Options = locationTeleportOptions,
			Default = locationTeleportOptions[1],
			Callback = function(selected) end,
		})

		Window:CreateButton(uiSections.teleportLocations, {
			Text = "Teleport To Location",
			Style = "accent",
			Callback = function()
				local selected = locationDropdown.GetValue()
				local destination = selected and locationTeleports[selected]
				if not destination then
					GenesisX:Notify({ Text = "Select a location first!", Type = "error", Duration = 2 })
					return
				end
				if destination.placeId ~= game.PlaceId then
					GenesisX:Notify({ Text = selected .. " is in Third Sea!", Type = "error", Duration = 3 })
					return
				end

				local root = GetRoot(LocalPlayer.Character)
				if not root then
					GenesisX:Notify({ Text = "Character position is unavailable!", Type = "error", Duration = 2 })
					return
				end

				_GBackPosition = root.CFrame
				tp(destination.cframe)
				GenesisX:Notify({ Text = "Teleported to " .. selected, Type = "success", Duration = 2 })
			end,
		})
	end

	local conquestStatusLabel = Window:CreateLabel(uiSections.eventConquest, {
		Text = "Conquest: Idle",
		Color = SpectrumX.Theme.TextSecondary,
		Wrapped = true,
	})

	Window:CreateToggle(uiSections.eventConquest, {
		Text = "Auto Conquest",
		Default = GetSetting("autoConquest") or false,
		Callback = function(state)
			saveAndApply("autoConquest", state)
		end,
	})

	Window:CreateToggle(uiSections.eventConquest, {
		Text = "Auto Hop For Conquest",
		Default = GetSetting("autoHopConquest") or false,
		Callback = function(state)
			saveAndApply("autoHopConquest", state)
		end,
	})

	Window:CreateDropdown(uiSections.progressPassives, {
		Label = "Select Book",
		Options = { "Fate Book", "Essence Book", "Fortune Tales", "Chronicles Lore" },
		Default = GetSetting("selectedPassiveBook") or "Chronicles Lore",
		Callback = function(selected)
			saveAndApply("selectedPassiveBook", selected)
		end,
	})

	Window:CreateMultiDropdown(uiSections.progressPassives, {
		Label = "Target Passives",
		Options = passiveOptions,
		Default = GetSetting("selectedPassives") or {},
		Callback = function(selected)
			saveAndApply("selectedPassives", selected)
		end,
	})

	Window:CreateToggle(uiSections.progressPassives, {
		Text = "Auto Get Passives",
		Default = GetSetting("autoGetPassives") or false,
		Callback = function(state)
			saveAndApply("autoGetPassives", state)
		end,
	})

	spawn(function()
		while task.wait(0.7) do
			pcall(function()
				if not GetSetting("autoGetPassives") then
					return
				end

				local targetPassives = GetSetting("selectedPassives")
				if not targetPassives or #targetPassives == 0 then
					return
				end

				local currentPassives = getPlayerPassives()

				local allFound = true
				for _, option in ipairs(targetPassives) do
					local name = getPassiveName(option)
					if not currentPassives[name] then
						allFound = false
						break
					end
				end

				if allFound then
					saveAndApply("autoGetPassives", false)
					SpectrumX:Notify({
						Text = "target passives obtained!",
						Type = "success",
						Duration = 5,
					})
					return
				end

				local book = GetSetting("selectedPassiveBook") or "Chronicles Lore"
				ReplicatedStorage.Chest.Remotes.Functions.Enchant:InvokeServer(book)
			end)
		end
	end)

	Window:CreateDropdown(uiSections.progressPlayer, {
		Label = "Select Animation",
		Options = { "Standard", "Annoy", "Egoistic", "Protagonist", "Undead", "Bashful", "Brawny" },
		Default = GetSetting("selectedAnimation") or "Standard",
		Callback = function(value)
			saveAndApply("selectedAnimation", value)
		end,
	})

	Window:CreateToggle(uiSections.progressPlayer, {
		Text = "Legacy Pose",
		Default = GetSetting("freeLegacyPose") or false,
		Callback = function(state)
			saveAndApply("freeLegacyPose", state)
		end,
	})

	_G.cachedServers = {}
	_G.lastServerFetch = 0
	_G.isFetchingServers = false
	_G.currentFilter = "All"

	local serverListLabels = {}
	local serverListButtons = {}
	local statusLabel

	local function formatTimeAgo(timestamp)
		if not timestamp then
			return "Unknown"
		end
		local now = os.time()
		local elapsed = now - timestamp
		if elapsed < 0 then
			elapsed = 0
		end
		if elapsed < 60 then
			return string.format("00:%02d", elapsed)
		elseif elapsed < 3600 then
			local mins = math.floor(elapsed / 60)
			local secs = elapsed % 60
			return string.format("%02d:%02d", mins, secs)
		else
			local hours = math.floor(elapsed / 3600)
			local mins = math.floor((elapsed % 3600) / 60)
			return string.format("%dh %02dm", hours, mins)
		end
	end

	local function getEventIcon(eventType)
		local icons = {
			GhostShip = "\240\159\145\187",
			SeaKing = "\240\159\140\138",
			Hydra = "\240\159\144\141",
			Galleon = "\240\159\154\162",
			Kraken = "\240\159\166\145",
			RaceIsland = "\240\159\143\157\239\184\143",
			SeaEvent = "\226\154\148\239\184\143",
			Serpent = "\240\159\144\141",
			Whirlpool = "\240\159\140\128",
			RaidBoss = "\240\159\146\128",
			Drakenfyr = "\240\159\144\137",
			AbyssalTyrant = "\240\159\144\178",
			DeepseaCrusher = "\240\159\166\128",
			Fruit = "\240\159\141\142",
			Unknown = "\226\157\147",
		}
		return icons[eventType] or icons.Unknown
	end

	_G.formatServerEventLabel = function(eventType, eventName)
		local raw = tostring(eventName or "")
		raw = raw:gsub("%[Sea%s*%d+%]", "")
		raw = raw:gsub("%s*[Bb]oss%s*", " ")
		raw = raw:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

		local isFruit = (eventType == "Fruit") or (string.find(string.lower(raw), "fruit", 1, true) ~= nil)
		if isFruit then
			local out = {}
			local seen = {}
			for piece in string.gmatch(raw .. ",", "([^,]+),") do
				local p = piece
				p = p:gsub("[Ff]ruit", "")
				p = p:gsub("[%-_]+$", "")
				p = p:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
				if p ~= "" and not seen[p] then
					seen[p] = true
					table.insert(out, p)
				end
			end
			if #out > 0 then
				return table.concat(out, ", ")
			end
			return "Fruit"
		end

		if raw ~= "" then
			return raw
		end

		local fallback = {
			GhostShip = "Ghost Ship",
			SeaKing = "Sea King",
			Hydra = "Hydra",
			Galleon = "Galleon",
			Kraken = "Kraken",
			RaceIsland = "Race Island",
			SeaEvent = "Sea Event",
			Serpent = "Serpent",
			Whirlpool = "Whirlpool",
			RaidBoss = "Raid Boss",
			Drakenfyr = "Drakenfyr",
			AbyssalTyrant = "Abyssal Tyrant",
			DeepseaCrusher = "Deepsea Crusher",
			Fruit = "Fruit",
		}
		return fallback[eventType] or tostring(eventType or "Event")
	end

	function isSeaEvent(eventType, placeId)
		if eventType == "Galleon" or eventType == "Serpent" or eventType == "Whirlpool" then
			return false
		end

		if placeId == 4520749081 then
			return false
		elseif placeId == 6381829480 then
			return eventType == "SeaKing" or eventType == "Hydra" or eventType == "GhostShip"
		elseif placeId == 15759515082 then
			return eventType == "Kraken"
				or eventType == "Drakenfyr"
				or eventType == "AbyssalTyrant"
				or eventType == "DeepseaCrusher"
		end
		return false
	end

	local function updateServerListUI()
		local filtered = {}
		local filterType = _G.currentFilter
		local currentPlaceId = game.PlaceId

		for _, server in ipairs(_G.cachedServers) do
			local include = true
			if filterType ~= "All" then
				if filterType == "SeaEvent" then
					include = isSeaEvent(server.eventType, currentPlaceId)
				else
					include = (server.eventType == filterType)
				end
			end
			if include then
				table.insert(filtered, server)
			end
		end

		if statusLabel then
			if #filtered > 0 then
				statusLabel.SetText("\226\156\133 " .. #filtered .. " server(s) found")
				statusLabel.Label.TextColor3 = SpectrumX.Theme.Success
			else
				statusLabel.SetText("\226\143\179 No servers found")
				statusLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
			end
		end

		for i = 1, 6 do
			local server = filtered[i]
			local label = serverListLabels[i]
			local btn = serverListButtons[i]

			if server and label and btn then
				local icon = getEventIcon(server.eventType)
				local timeStr = formatTimeAgo(server.timestamp)
				local shortId = string.sub(server.jobId, 1, 12) .. "..."

				local short = _G.formatServerEventLabel(server.eventType, server.eventName)
				label.SetText(
					string.format(
						"%s \194\183 %s\010\240\159\145\165 %d/12  |  \240\159\149\144 %s\010\240\159\148\145 %s",
						icon,
						short,
						server.playerCount,
						timeStr,
						shortId
					)
				)
				label.Label.Visible = true
				btn.Button.Text = "JOIN"
				btn.Button.Visible = true

				if btn._connection then
					btn._connection:Disconnect()
					btn._connection = nil
				end

				btn._connection = trackGenesisConnection(btn.Button.MouseButton1Click:Connect(function()
					local targetId = server.jobId
					if #targetId > 36 then
						local decoded = decodeBase64(targetId)
						if decoded and #decoded > 10 then
							targetId = decoded
						end
					end
					SpectrumX:Notify({
						Text = "Joining " .. server.eventName .. "...",
						Type = "info",
						Duration = 3,
					})
					task.wait(0.5)
					TeleportService:TeleportToPlaceInstance(game.PlaceId, targetId, LocalPlayer)
				end))
			else
				if label then
					label.Label.Visible = false
				end
				if btn then
					btn.Button.Visible = false
					if btn._connection then
						btn._connection:Disconnect()
						btn._connection = nil
					end
				end
			end
		end

		-- Synchronize the new UI cards (serverCards) when they exist.
		if _G.serverCards then
			for i = 1, 6 do
				local card = _G.serverCards[i]
				local server = filtered[i]
				if card then
					_G.serverSlotData[i] = server
					if server then
						local icon = getEventIcon(server.eventType)
						local short = _G.formatServerEventLabel(server.eventType, server.eventName)
						card.SetTitle(icon .. " \194\183 " .. short)
						card.SetSubtitles({
							"Players: " .. tostring(server.playerCount) .. "/12",
							"Job: " .. string.sub(tostring(server.jobId), 1, 12) .. "...",
						})
						card.SetButtonText(1, "JOIN")
						card.SetVisible(true)
					else
						card.SetTitle("Slot " .. i .. " - Empty")
						card.SetSubtitles({
							"Waiting for server data...",
							"Players: --/12",
						})
						card.SetButtonText(1, "WAITING")
					end
				end
			end
		end
	end

	local function fetchServersFromBot(forceNetworkRefresh)
		if _G.isFetchingServers then
			return false
		end
		if forceNetworkRefresh then
			if tick() - (_G._GenesisManualRefreshAt or 0) < 5 then
				return false
			end
			_G._GenesisManualRefreshAt = tick()
		end
		-- Rebuild the UI list roughly with its 30-second refresh loop.  The
		-- Event Hub poller maintains the shared cache every five seconds, so
		-- this does not require a second request for every redraw.
		if not forceNetworkRefresh and os.time() - _G.lastServerFetch < 25 then
			return false
		end

		_G.isFetchingServers = true

		spawn(function()
			local success, result = pcall(function()
				local req = http_request or request or syn.request
				if not req then
					return "HTTP not available"
				end

				local seaNumber = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3

				-- Event Hub: read the fresh shared cache first.  The old code
				-- polled twice back-to-back here, even though a global poller is
				-- already active.
				local channelName = "sea_events_" .. tostring(seaNumber)
				local hubData = forceNetworkRefresh and nil or _G.EventHubCache
				if forceNetworkRefresh or not hubData or tick() - (hubData.last_poll or 0) > Hub.pollSeconds * 2 then
					hubData = PollGameEvents()
				end
				if not hubData or not hubData.ok then
					return "Connection failed: Event Hub"
				end

				local data = {}
				local by = hubData.by_channel or {}
				-- Include sea, raid, and race channels.
				local chans = { channelName, "raid_bosses_" .. tostring(seaNumber), "race_island", "fruits" }
				for _, ch in ipairs(chans) do
					for _, ev in ipairs(by[ch] or {}) do
						local s = EventHubToServer(ev, ev.title)
						if s then
							s.event_type = s.event_type or s.event_name
							s.event_name = s.event_name or s.event_type
							s.channel = ch
							table.insert(data, s)
						end
					end
				end

				if type(data) ~= "table" then
					return "Invalid JSON data"
				end

				_G.cachedServers = {}

				for _, server in ipairs(data) do
					if type(server) == "table" and server.job_id then
						local eventType = server.event_type or "Unknown"
						local eventName = server.event_name or "Unknown Event"
						local channelKey = server.channel or ""
						local skipServer = false

						if
							channelKey == "sea_events_1"
							or channelKey == "sea_events_2"
							or channelKey == "sea_events_3"
						then
							local validSeaTypes = {

								SeaKing = true,
								Hydra = true,
								GhostShip = true,
								Kraken = true,
								Galleon = true,
								Drakenfyr = true,
								AbyssalTyrant = true,
								DeepseaCrusher = true,

								Serpent = true,
								Whirlpool = true,

								SeaEvent = true,
							}

							if not validSeaTypes[eventType] then
								local nameLower = eventName:lower()
								if nameLower:find("serpent") then
									eventType = "Serpent"
								elseif nameLower:find("whirlpool") then
									eventType = "Whirlpool"
								elseif nameLower:find("sea king") or nameLower:find("seaking") then
									eventType = "SeaKing"
								elseif nameLower:find("hydra") then
									eventType = "Hydra"
								elseif nameLower:find("ghost ship") or nameLower:find("ghostship") then
									eventType = "GhostShip"
								elseif nameLower:find("galleon") then
									eventType = "Galleon"
								elseif
									nameLower:find("kraken")
									or nameLower:find("tentacle")
									or nameLower:find("furytentacle")
								then
									eventType = "Kraken"
								elseif nameLower:find("drakenfyr") or nameLower:find("thirdseadragon") then
									eventType = "Drakenfyr"
								elseif
									nameLower:find("abyssal tyrant")
									or (nameLower:find("seadragon") and not nameLower:find("third"))
								then
									eventType = "AbyssalTyrant"
								elseif
									nameLower:find("deepsea crusher")
									or nameLower:find("thirdseaeldritch")
									or nameLower:find("eldritch")
									or nameLower:find("crab")
								then
									eventType = "DeepseaCrusher"
								else
									eventType = "SeaEvent"
								end
							end
						elseif
							channelKey == "raid_bosses_1"
							or channelKey == "raid_bosses_2"
							or channelKey == "raid_bosses_3"
						then
							eventType = "RaidBoss"
							eventName = eventName:gsub("%[Sea %d%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
						elseif channelKey == "race_island" then
							eventType = "RaceIsland"
						elseif channelKey == "fruits" then
							eventType = "Fruit"
						end

						if not skipServer then
							table.insert(_G.cachedServers, {
								jobId = server.job_id,
								eventType = eventType,
								eventName = eventName,
								playerCount = server.player_count or 0,
								timestamp = server.timestamp or os.time(),
							})
						end
					end
				end

				table.sort(_G.cachedServers, function(a, b)
					return (a.timestamp or 0) > (b.timestamp or 0)
				end)

				_G.lastServerFetch = os.time()
				return "Success - " .. #_G.cachedServers .. " servers loaded"
			end)

			if not success then
				if statusLabel then
					statusLabel.SetText("\226\157\140 Error: " .. tostring(result):sub(1, 30))
					statusLabel.Label.TextColor3 = SpectrumX.Theme.Error
				end
			end

			_G.isFetchingServers = false
			updateServerListUI()
		end)
		return true
	end

	local serverJobContent = createUiSection(uiSections.ServerTab.Left, "Job ID", "lucide-share")

	Window:CreateLabel(serverJobContent, {
		Text = "Current Job ID:",
		Color = GenesisX.Theme.TextSecondary,
		Size = UDim2.new(1, 0, 0, 20),
	})

	local currentJobIdLabel = Window:CreateLabel(serverJobContent, {
		Text = "Loading...",
		Color = GenesisX.Theme.Info,
		Size = UDim2.new(1, 0, 0, 40),
	})

	spawn(function()
		while task.wait(2) do
			pcall(function()
				currentJobIdLabel.SetText(_G.jobIdEncoded)
			end)
		end
	end)

	Window:CreateButton(serverJobContent, {
		Text = "Copy Current Job ID",
		Callback = function()
			pcall(function()
				setclipboard(_G.jobIdEncoded)
				GenesisX:Notify({ Text = "Job ID copied!", Type = "success", Duration = 2 })
			end)
		end,
	})

	local serverManualContent = createUiSection(uiSections.ServerTab.Left, "Manual Connection", "lucide-gem")

	Window:CreateInput(serverManualContent, {
		Label = "Enter Target Job ID",
		Default = GetSetting("targetJobId") or "",
		Placeholder = "Paste Job ID here...",
		Callback = function(text)
			saveAndApply("targetJobId", text)
		end,
	})

	Window:CreateButton(serverManualContent, {
		Text = "Join Target Server",
		Callback = function()
			local targetJobId = GetSetting("targetJobId")
			if targetJobId and targetJobId ~= "" then
				local decoded = decodeBase64(targetJobId)
				if decoded and #decoded > 10 then
					GenesisX:Notify({
						Text = "Joining server...",
						Type = "info",
						Duration = 3,
					})
					task.wait(1)
					TeleportService:TeleportToPlaceInstance(game.PlaceId, decoded, LocalPlayer)
				else
					GenesisX:Notify({
						Text = "Invalid Job ID!",
						Type = "error",
						Duration = 3,
					})
				end
			else
				GenesisX:Notify({
					Text = "Enter a Job ID first!",
					Type = "warning",
					Duration = 2,
				})
			end
		end,
	})

	local serverQuickContent = createUiSection(uiSections.ServerTab.Left, "Quick Actions", "lucide-refresh-cw")

	Window:CreateButton(serverQuickContent, {
		Text = "Rejoin Current Server",
		Callback = function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end,
	})

	Window:CreateButton(serverQuickContent, {
		Text = "Server Hop (Random)",
		Callback = function()
			serverHop()
		end,
	})

	local serverBrowserContent = createUiSection(uiSections.ServerTab.Right, "Event Server Browser", "lucide-folder-tree")

	statusLabel = Window:CreateLabel(serverBrowserContent, {
		Text = "Click Refresh to load",
		Color = GenesisX.Theme.TextSecondary,
		Size = UDim2.new(1, 0, 0, 25),
	})

	Window:CreateButton(serverBrowserContent, {
		Text = "Refresh List",
		Callback = function()
			if fetchServersFromBot(true) then
				GenesisX:Notify({ Text = "Fetching servers...", Type = "info", Duration = 2 })
			else
				GenesisX:Notify({ Text = "Refresh is cooling down (5 seconds)", Type = "warning", Duration = 2 })
			end
		end,
	})

	local serverFilterContent = createUiSection(uiSections.ServerTab.Right, "Filters", "lucide-filter")

	local filterOptions = { "All", "SeaEvent" }
	if game.PlaceId == 6381829480 then
		table.insert(filterOptions, "Hydra")
		table.insert(filterOptions, "SeaKing")
		table.insert(filterOptions, "Serpent")
		table.insert(filterOptions, "Whirlpool")
		table.insert(filterOptions, "RaidBoss")
		table.insert(filterOptions, "GhostShip")
		table.insert(filterOptions, "Fruit")
	elseif game.PlaceId == 15759515082 then
		table.insert(filterOptions, "Galleon")
		table.insert(filterOptions, "Kraken")
		table.insert(filterOptions, "Serpent")
		table.insert(filterOptions, "Whirlpool")
		table.insert(filterOptions, "RaidBoss")
		table.insert(filterOptions, "RaceIsland")
		table.insert(filterOptions, "Fruit")
	else
		table.insert(filterOptions, "Serpent")
		table.insert(filterOptions, "Whirlpool")
		table.insert(filterOptions, "RaidBoss")
		table.insert(filterOptions, "Fruit")
	end

	Window:CreateDropdown(serverFilterContent, {
		Label = "Filter by Event",
		Options = filterOptions,
		Default = "All",
		Callback = function(selected)
			_G.currentFilter = selected
			updateServerListUI()
		end,
	})

	local serverListContent = createUiSection(uiSections.ServerTab.Right, "Available Servers (up to 50)", "lucide-globe")

	_G.serverSlotData = {}

	local SERVER_LIST_MAX = 50
	local serverCards = {}
	_G.serverCards = serverCards

	for i = 1, SERVER_LIST_MAX do
		_G.serverSlotData[i] = nil

		local card = Window:CreateLabelToggleSubTitle(serverListContent, {
			Title = "Slot " .. i .. " - Empty",
			TitleColor = GenesisX.Theme.TextMuted,
			Subtitles = {
				"Waiting for server data...",
				"Players: --/12",
			},
			Buttons = {
				{
					Text = "JOIN",
					Style = "default",
					Callback = function()
						local server = _G.serverSlotData[i]
						if not server then
							GenesisX:Notify({ Text = "No server available!", Type = "warning", Duration = 2 })
							return
						end

						local targetId = server.jobId
						if #targetId > 36 then
							local decoded = decodeBase64(targetId)
							if decoded and #decoded > 10 then
								targetId = decoded
							end
						end

						GenesisX:Notify({
							Text = "Joining " .. server.eventName .. "...",
							Type = "info",
							Duration = 3,
						})
						task.wait(0.5)
						TeleportService:TeleportToPlaceInstance(game.PlaceId, targetId, LocalPlayer)
					end,
				},
			},
		})

		serverCards[i] = card
		card.SetVisible(false)
	end

	updateServerListUI = function()
		local filtered = {}
		local filterType = _G.currentFilter
		local currentPlaceId = game.PlaceId

		for _, server in ipairs(_G.cachedServers) do
			local include = true
			if filterType ~= "All" then
				if filterType == "SeaEvent" then
					include = isSeaEvent(server.eventType, currentPlaceId)
				else
					include = (server.eventType == filterType)
				end
			end
			if include then
				table.insert(filtered, server)
			end
		end

		if statusLabel then
			if #filtered > 0 then
				local shown = math.min(#filtered, SERVER_LIST_MAX)
				statusLabel.SetText("\226\156\133 " .. #filtered .. " server(s) found | showing " .. shown)
				statusLabel.Label.TextColor3 = GenesisX.Theme.Success
			else
				statusLabel.SetText("\226\143\179 No servers found")
				statusLabel.Label.TextColor3 = GenesisX.Theme.TextSecondary
			end
		end

		for i = 1, SERVER_LIST_MAX do
			local card = serverCards[i]
			local server = filtered[i]

			if card then
				_G.serverSlotData[i] = server

				if server then
					local icon = getEventIcon(server.eventType)
					local short = _G.formatServerEventLabel(server.eventType, server.eventName)
					card.SetTitle(icon .. " \194\183 " .. short)
					card.SetTitleColor(GenesisX.Theme.Success)
					card.SetSubtitles({
						"Players: " .. tostring(server.playerCount) .. "/12",
						"Job: " .. string.sub(tostring(server.jobId), 1, 12) .. "...",
					})
					card.SetButtonText(1, "JOIN")
					card.SetButtonStyle(1, "accent")
					card.SetVisible(true)
				else
					card.SetVisible(false)
				end
			end
		end
	end

	spawn(function()
		task.wait(3)
		fetchServersFromBot()

		while task.wait(30) do
			pcall(function()
				fetchServersFromBot()
			end)
		end
	end)

	spawn(function()
		while true do
			pcall(function()
				if _G.storingFruit then
					return
				end

				-- Sigma does not switch tools (simultaneous multi-tool M1).
				if GetSetting("farmMethod") == "Sigma (Smooth)" then
					return
				end

				if
					isFeatureEnabledInCurrentSea("auto_farm")
					or isFeatureEnabledInCurrentSea("farmmaterial")
					or isFeatureEnabledInCurrentSea("allboss")
					or isFeatureEnabledInCurrentSea("easybounty")
					or isFeatureEnabledInCurrentSea("autoKillMobs")
					or isFeatureEnabledInCurrentSea("autoFarmBoss")
					or isFeatureEnabledInCurrentSea("autoFarmKaido")
					or isFeatureEnabledInCurrentSea("autoDarkBeard")
					or isFeatureEnabledInCurrentSea("autoCrimsonDemon")
					or isFeatureEnabledInCurrentSea("autoIceKing")
					or isFeatureEnabledInCurrentSea("autoSecondSea")
					or isFeatureEnabledInCurrentSea("autoThirdSea")
					or isFeatureEnabledInCurrentSea("autoHuntSerpent")
					or (GetSetting("autoDailyQuestsMaster") and
						(isFeatureEnabledInCurrentSea("autoDailyQuest")
							or isFeatureEnabledInCurrentSea("autoSecondSeaDailyQuest")))
					or isFeatureEnabledInCurrentSea("autoHuntPtero")
					or isFeatureEnabledInCurrentSea("autoRaidBoss_ExpertSwordman")
					or isFeatureEnabledInCurrentSea("autoRaidBoss_MsMother")
					or isFeatureEnabledInCurrentSea("autoRaidBoss_KingSamurai")
					or isFeatureEnabledInCurrentSea("autoRaidBoss_BushidoApe")
					or isFeatureEnabledInCurrentSea("autoRaidBoss_LordOfSaber")
					or _G.seaEventActive
				then
					local tools = GetSetting("selectedTools")
					if tools and #tools > 0 then
						_G.currentToolIndex = _G.currentToolIndex + 1
						if _G.currentToolIndex > #tools then
							_G.currentToolIndex = 1
						end
					end
				end
			end)
			task.wait(GetSetting("toolSwitchSpeed") or 0.5)
		end
	end)

	spawn(function()
		while task.wait(0.1) do
			pcall(function()
				if not GetSetting("autoDistribute") then
					return
				end

				local points = LocalPlayer.PlayerStats:FindFirstChild("Points")
				if not points or points.Value <= 0 then
					return
				end

				local distributeValue = GetSetting("distributeValue") or 1
				local statsRemote = LocalPlayer:WaitForChild("PlayerGui")
					:WaitForChild("MainGui")
					:WaitForChild("StarterFrame")
					:WaitForChild("StatsFrame")
					:WaitForChild("RemoteEvent")
				if GetSetting("autoMelee") then
					statsRemote:FireServer("Melee", distributeValue)
				end
				if GetSetting("autoDefense") then
					statsRemote:FireServer("Defense", distributeValue)
				end
				if GetSetting("autoSword") then
					statsRemote:FireServer("Sword", distributeValue)
				end
				if GetSetting("autoFruit") then
					statsRemote:FireServer("Fruit", distributeValue)
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if GetSetting("walkOnWater") then
					Workspace.SeaFolder.Sea.CanCollide = true
				else
					Workspace.SeaFolder.Sea.CanCollide = false
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(2) do
			pcall(function()
				if not GetSetting("freeLegacyPose") then
					_G.hasLegacyPose = false
					return
				end
				local hasPose = false
				for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
					if tool.Name == "LegacyPose" then
						hasPose = true
						break
					end
				end
				if not hasPose then
					for _, tool in pairs(LocalPlayer.Character:GetChildren()) do
						if tool.Name == "LegacyPose" then
							hasPose = true
							break
						end
					end
				end
				if hasPose then
					_G.hasLegacyPose = true
					return
				end
				if not _G.hasLegacyPose then
					for _, player in pairs(Players:GetPlayers()) do
						if player ~= LocalPlayer then
							for _, tool in pairs(player.Backpack:GetChildren()) do
								if tool.Name == "LegacyPose" then
									local clone = tool:Clone()
									clone.Parent = LocalPlayer.Backpack
									_G.hasLegacyPose = true
									return
								end
							end
						end
					end
				end
			end)
		end
	end)

	trackGenesisConnection(LocalPlayer.CharacterAdded:Connect(function()
		_G.hasLegacyPose = false
		-- A farm-fix worker captures the prior character's root part. Clear it here
		-- so the next farm tick can attach cleanly to the respawned character.
		if _G.farmFixThread or _G.farmFixBodyPos then
			removeFarmFix()
		end
		stopSeaEventBypass()
		if removeConquestPosition then
			removeConquestPosition()
		end
		if removeChestLootFix then
			removeChestLootFix()
		end
		_G.isLootingChests = false
	end))

	spawn(function()
		while task.wait(0.5) do
			pcall(_G._GenesisRefreshFishingPositionLabel)
		end
	end)

	local getDailyQuestPending
	local _fishBP = nil
	local _fishBG = nil

	local function applyFishPosition(cf)
		-- A fish lock and a farm lock both write to the root part.  Fishing owns
		-- that position only while no combat mode has taken over.
		if _G.farmFixThread or _G.farmFixBodyPos then
			removeFarmFix()
		end
		local root = GetRoot(LocalPlayer.Character)
		if not root then
			return
		end

		if not _fishBP or not _fishBP.Parent then
			_fishBP = Instance.new("BodyPosition")
			_fishBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			_fishBP.D = 1000
			_fishBP.P = 10000
			_fishBP.Parent = root
		end
		if not _fishBG or not _fishBG.Parent then
			_fishBG = Instance.new("BodyGyro")
			_fishBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
			_fishBG.D = 500
			_fishBG.P = 10000
			_fishBG.Parent = root
		end

		_fishBP.Position = cf.Position
		_fishBG.CFrame = cf
	end

	local function removeFishPosition()
		if _fishBP then
			pcall(function()
				_fishBP:Destroy()
			end)
			_fishBP = nil
		end
		if _fishBG then
			pcall(function()
				_fishBG:Destroy()
			end)
			_fishBG = nil
		end
	end

	local function getEquippedTool()
		local character = LocalPlayer.Character
		if not character then
			return nil
		end
		for _, tool in pairs(character:GetChildren()) do
			if tool:IsA("Tool") then
				return tool
			end
		end
		return nil
	end

	_G._GenesisIsFishingRodName = function(name)
		if type(name) ~= "string" then
			return false
		end
		local lowerName = string.lower(name)
		return lowerName == "basic rod" or string.match(lowerName, "%srod$") ~= nil
	end

	_G._GenesisIsUsableSwordName = function(name)
		return type(name) == "string"
			and name ~= ""
			and string.lower(name) ~= "none"
			and not _G._GenesisIsFishingRodName(name)
	end

	_G._GenesisGetReplicatedPrimaryName = function()
		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		local etcData = stats and stats:FindFirstChild("EtcData")
		if not etcData or type(etcData.Value) ~= "string" then
			return nil
		end
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(etcData.Value)
		end)
		local primaryName = ok and type(decoded) == "table" and decoded.PrimaryWeapon or nil
		return type(primaryName) == "string" and primaryName or nil
	end

	_G._GenesisRememberSwordName = function(name)
		if not _G._GenesisIsUsableSwordName(name) then
			return nil
		end
		_G.lastEquippedSwordName = name
		if GetSetting("lastEquippedSwordName") ~= name then
			pcall(function()
				SetSetting("lastEquippedSwordName", name)
			end)
		end
		return name
	end

	_G._GenesisIsSwordTool = function(tool)
		return tool
			and tool:IsA("Tool")
			and tool.ToolTip == "Sword"
			and not _G._GenesisIsFishingRodName(tool.Name)
	end

	_G._GenesisRememberSword = function(tool)
		if _G._GenesisIsSwordTool(tool) then
			_G.lastEquippedSword = tool
			_G._GenesisRememberSwordName(tool.Name)
			return tool
		end
		return nil
	end

	_G._GenesisFindSwordToolByName = function(name)
		if not _G._GenesisIsUsableSwordName(name) then
			return nil
		end
		for _, container in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }) do
			local tool = container and container:FindFirstChild(name)
			if _G._GenesisIsSwordTool(tool) then
				return tool
			end
		end
		return nil
	end

	_G._GenesisInventoryShowsSword = function(name)
		if not _G._GenesisIsUsableSwordName(name) then
			return false
		end
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
		local starterFrame = mainGui and mainGui:FindFirstChild("StarterFrame")
		local inventory = starterFrame and starterFrame:FindFirstChild("Inventory_Frame")
		local swordList = inventory and inventory:FindFirstChild("ScrollingFrameSwords")
		local itemButton = swordList and swordList:FindFirstChild(name)
		return itemButton ~= nil and itemButton:IsA("GuiButton")
	end

	_G._GenesisIsAvailableSwordName = function(name)
		if not _G._GenesisIsUsableSwordName(name) then
			return false
		end
		if _G._GenesisFindSwordToolByName(name) then
			return true
		end

		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		local swordNameValue = stats and stats:FindFirstChild("SwordName")
		if swordNameValue and swordNameValue.Value == name then
			return true
		end
		if _G._GenesisGetReplicatedPrimaryName() == name then
			return true
		end
		return _G._GenesisInventoryShowsSword(name)
	end

	_G._GenesisGetLastEquippedSwordName = function()
		local character = LocalPlayer.Character
		if character then
			for _, tool in pairs(character:GetChildren()) do
				if _G._GenesisIsSwordTool(tool) then
					_G._GenesisRememberSword(tool)
					return tool.Name
				end
			end
		end

		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		local swordNameValue = stats and stats:FindFirstChild("SwordName")
		local selectedName = swordNameValue and swordNameValue.Value
		if _G._GenesisIsUsableSwordName(selectedName) then
			return _G._GenesisRememberSwordName(selectedName)
		end

		-- On a fresh join SwordName and the Tool can lag behind EtcData. PrimaryWeapon
		-- is replicated server state and closes that bootstrap gap without equipping a
		-- generic selected tool (which could be Combat or Fruit Power).
		local replicatedPrimaryName = _G._GenesisGetReplicatedPrimaryName()
		if _G._GenesisIsUsableSwordName(replicatedPrimaryName) then
			return _G._GenesisRememberSwordName(replicatedPrimaryName)
		end

		if _G._GenesisIsAvailableSwordName(_G.lastEquippedSwordName) then
			return _G._GenesisRememberSwordName(_G.lastEquippedSwordName)
		end

		local savedName = GetSetting("lastEquippedSwordName")
		if _G._GenesisIsAvailableSwordName(savedName) then
			return _G._GenesisRememberSwordName(savedName)
		end

		local backpack = LocalPlayer:FindFirstChild("Backpack")
		if backpack then
			for _, tool in pairs(backpack:GetChildren()) do
				if _G._GenesisIsSwordTool(tool) then
					_G._GenesisRememberSword(tool)
					return tool.Name
				end
			end
		end

		_G.lastEquippedSword = nil
		return nil
	end

	_G._GenesisWaitForLastEquippedSwordName = function(timeoutSeconds, shouldContinue)
		local deadline = os.clock() + math.max(tonumber(timeoutSeconds) or 4, 0)
		repeat
			if shouldContinue and not shouldContinue() then
				return nil
			end
			local name = _G._GenesisGetLastEquippedSwordName()
			if name then
				return name
			end
			task.wait(0.1)
		until os.clock() >= deadline
		return _G._GenesisGetLastEquippedSwordName()
	end

	local function selectPrimaryWeapon(weaponName, timeoutSeconds, shouldContinue)
		if type(weaponName) ~= "string" or weaponName == "" then
			return nil
		end

		local timeout = math.max(tonumber(timeoutSeconds) or 4, 0.5)
		local deadline = os.clock() + timeout
		local function cancelled()
			return shouldContinue and not shouldContinue()
		end

		local function findConfirmedWeapon()
			if cancelled() then
				return nil
			end
			local character = LocalPlayer.Character
			local tool = (character and character:FindFirstChild(weaponName))
				or LocalPlayer.Backpack:FindFirstChild(weaponName)
			local stats = LocalPlayer:FindFirstChild("PlayerStats")
			local swordNameValue = stats and stats:FindFirstChild("SwordName")
			if
				tool
				and swordNameValue
				and swordNameValue.Value == weaponName
				and _G._GenesisGetReplicatedPrimaryName() == weaponName
			then
				return tool
			end
			return nil
		end

		local function waitForConfirmation(untilTime)
			repeat
				local tool = findConfirmedWeapon()
				if tool or cancelled() then
					return tool
				end
				task.wait(0.05)
			until os.clock() >= untilTime
			return findConfirmedWeapon()
		end

		local alreadyLoaded = findConfirmedWeapon()
		if alreadyLoaded then
			return alreadyLoaded
		end

		-- Drive the game's validated InventoryScript path. This keeps the server
		-- request serialized with the loadout transaction; an independently spawned
		-- EquipWeapon request could arrive late and overwrite a completed restore.
		-- Reacquire the UI and retry within one bounded transaction because the game
		-- can rebuild the inventory after a Primary change. Never press Primary unless
		-- the information panel confirms that this exact weapon is selected.
		if type(firesignal) == "function" then
			repeat
				if cancelled() then
					break
				end

				local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
				local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
				local starterFrame = mainGui and mainGui:FindFirstChild("StarterFrame")
				local inventory = starterFrame and starterFrame:FindFirstChild("Inventory_Frame")
				local swordList = inventory and inventory:FindFirstChild("ScrollingFrameSwords")
				local itemButton = swordList and swordList:FindFirstChild(weaponName)
				local information = inventory and inventory:FindFirstChild("Information")
				local primaryButton = information and information:FindFirstChild("Primary")
				local selectionConfirmed = false

				if itemButton and itemButton:IsA("GuiButton") and primaryButton and primaryButton:IsA("GuiButton") then
					pcall(function()
						firesignal(itemButton.MouseButton1Click)
					end)
					local selectionDeadline = math.min(deadline, os.clock() + 0.5)
					repeat
						local nameText = information:FindFirstChild("NameText")
						if nameText and nameText.Text == weaponName then
							selectionConfirmed = true
							break
						end
						task.wait(0.03)
					until cancelled() or os.clock() >= selectionDeadline

					if selectionConfirmed and not cancelled() then
						pcall(function()
							firesignal(primaryButton.MouseButton1Click)
						end)
						local confirmed = waitForConfirmation(math.min(deadline, os.clock() + 0.8))
						if confirmed then
							return confirmed
						end
					end
				end

				task.wait(0.1)
			until os.clock() >= deadline
		end

		return findConfirmedWeapon()
	end

	-- Restore the exact remembered sword when real outside combat owns the hand.
	-- This is intentionally asynchronous: callers such as the central combat step
	-- run every frame and must never yield while the game's inventory UI replicates.
	_G._GenesisCombatSwordRestore = {
		busy = false,
		generation = 0,
		nextAttemptAt = 0,
		lastResult = "idle",
	}

	_G._GenesisEnsureCombatSword = function(_reason)
		local character = LocalPlayer.Character
		local humanoid = GetHumanoid(character)
		if not character or not humanoid or humanoid.Health <= 0 then
			return false
		end
		if fishingOwnsWeaponSlot() or _G.storingFruit then
			return false
		end

		for _, tool in ipairs(character:GetChildren()) do
			if _G._GenesisIsSwordTool(tool) then
				_G._GenesisRememberSword(tool)
				return true
			end
		end

		local preferredName = _G._GenesisGetLastEquippedSwordName()
		if not _G._GenesisIsUsableSwordName(preferredName) then
			preferredName = _G.lastEquippedSwordName or GetSetting("lastEquippedSwordName")
		end
		if not _G._GenesisIsUsableSwordName(preferredName) then
			return false
		end

		local existing = _G._GenesisFindSwordToolByName(preferredName)
		if existing then
			if existing.Parent ~= character then
				humanoid:EquipTool(existing)
			end
			if existing.Parent == character then
				_G._GenesisRememberSword(existing)
				return true
			end
		end

		local state = _G._GenesisCombatSwordRestore
		if state.busy or os.clock() < (state.nextAttemptAt or 0) then
			return false
		end

		state.busy = true
		state.generation = state.generation + 1
		state.lastResult = "selecting_primary"
		local generation = state.generation
		local startingCharacter = character
		task.spawn(function()
			local selected = nil
			local ok, err = pcall(function()
				selected = selectPrimaryWeapon(preferredName, 4, function()
					if state.generation ~= generation
						or LocalPlayer.Character ~= startingCharacter
						or fishingOwnsWeaponSlot()
						or _G.storingFruit
					then
						return false
					end
					local owner = _G._GenesisPriorityOwner
					return owner == "major_sea_event"
						or owner == "world_raid_boss"
						or owner == "serpent"
						or owner == "galleon"
						or owner == "daily_quest"
						or owner == "other_combat"
						or owner == "haki_progression"
				end)
			end)

			if state.generation ~= generation then
				return
			end
			if ok and selected then
				local liveHumanoid = GetHumanoid(startingCharacter)
				if liveHumanoid and selected.Parent ~= startingCharacter then
					pcall(function()
						liveHumanoid:EquipTool(selected)
					end)
				end
			end

			if ok and _G._GenesisIsSwordTool(selected) and selected.Parent == startingCharacter then
				_G._GenesisRememberSword(selected)
				state.lastResult = "equipped"
				state.nextAttemptAt = 0
			else
				state.lastResult = ok and "not_available" or ("error: " .. tostring(err))
				-- A failed inventory transaction must not be restarted every frame.
				state.nextAttemptAt = os.clock() + 1
			end
			state.busy = false
		end)
		return false
	end

	_G._GenesisBindSwordTracker = function(character)
		if _G._lastSwordTrackerConnection then
			pcall(function()
				_G._lastSwordTrackerConnection:Disconnect()
			end)
			_G._lastSwordTrackerConnection = nil
		end
		if not character then
			return
		end

		for _, child in pairs(character:GetChildren()) do
			_G._GenesisRememberSword(child)
		end
		_G._lastSwordTrackerConnection = trackGenesisConnection(character.ChildAdded:Connect(function(child)
			_G._GenesisRememberSword(child)
		end))
	end

	local function getFishingRod()
		local character = LocalPlayer.Character
		for _, container in ipairs({ character, LocalPlayer.Backpack }) do
			if container then
				local tool = container:FindFirstChild("Basic Rod")
				if tool and tool:IsA("Tool") then
					return tool
				end
			end
		end
		return nil
	end

	local restoreFishingWeapon
	local isFishingBlocked

	_G._GenesisCaptureFishingPreviousWeapon = function()
		if _G.fishingToolCaptured and _G._GenesisIsUsableSwordName(_G.fishingPreviousWeaponName) then
			return true
		end

		_G.fishingToolCaptured = false
		_G.fishingPreviousWeaponName = nil
		local equipped = getEquippedTool()
		_G._GenesisRememberSword(equipped)
		local previousName = _G._GenesisWaitForLastEquippedSwordName(4, function()
			return GetSetting("autoFish") and _G.isFishing and not isFishingBlocked()
		end)
		if not _G._GenesisIsUsableSwordName(previousName) then
			return false
		end

		_G.fishingPreviousWeaponName = previousName
		_G.fishingPreviousTool = nil
		_G.fishingToolCaptured = true
		return true
	end

	local function equipFishingRod()
		if _G.fishingLoadoutBusy or _G.fishingState == "restoring" then
			return nil
		end
		local character = LocalPlayer.Character
		local humanoid = GetHumanoid(character)
		if not character or not humanoid then
			return nil
		end
		if not _G.fishingToolCaptured or not _G._GenesisIsUsableSwordName(_G.fishingPreviousWeaponName) then
			return nil
		end

		local equippedRod = getFishingRod()
		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		local swordNameValue = stats and stats:FindFirstChild("SwordName")
		if
			equippedRod
			and equippedRod.Parent == character
			and swordNameValue
			and swordNameValue.Value == "Basic Rod"
		then
			_G.fishingState = "fishing"
			return equippedRod
		end

		_G.fishingGeneration = (_G.fishingGeneration or 0) + 1
		local generation = _G.fishingGeneration
		_G.fishingState = "equipping_rod"
		_G.fishingLoadoutBusy = true
		local rod = nil
		local ok = pcall(function()
			rod = getFishingRod()
			if not rod or not swordNameValue or swordNameValue.Value ~= "Basic Rod" then
				rod = selectPrimaryWeapon("Basic Rod", 4, function()
					return generation == _G.fishingGeneration
						and GetSetting("autoFish")
						and not isFishingBlocked()
				end)
			end
			if generation == _G.fishingGeneration and rod and rod.Parent ~= character then
				humanoid:EquipTool(rod)
				task.wait(0.05)
			end
		end)
		_G.fishingLoadoutBusy = false
		if not ok or generation ~= _G.fishingGeneration then
			_G.fishingState = "restoring"
			if restoreFishingWeapon then
				restoreFishingWeapon()
			end
			return nil
		end
		if rod and rod.Parent == character then
			_G.fishingState = "fishing"
			_G.fishingRestoreAttempts = 0
			_G.fishingRestoreFailureNotified = false
		else
			_G.fishingState = "restoring"
		end
		return rod
	end

	restoreFishingWeapon = function()
		if not _G.fishingToolCaptured or _G.fishingLoadoutBusy then
			if not _G.fishingToolCaptured then
				_G.fishingState = "idle"
				return true
			end
			return false
		end

		local character = LocalPlayer.Character
		local humanoid = GetHumanoid(character)
		if not character or not humanoid then
			return false
		end
		if os.clock() < (_G.fishingNextRestoreAttempt or 0) then
			return false
		end

		_G.fishingState = "restoring"
		_G.fishingLoadoutBusy = true
		local previousName = _G.fishingPreviousWeaponName or _G._GenesisGetLastEquippedSwordName()
		local restoredTool = nil
		pcall(function()
			restoredTool = previousName and selectPrimaryWeapon(previousName, 4) or nil
		end)
		if restoredTool then
			pcall(function()
				if restoredTool.Parent ~= character then
					humanoid:EquipTool(restoredTool)
				end
			end)
			_G._GenesisRememberSword(restoredTool)
			_G.fishingPreviousTool = nil
			_G.fishingPreviousWeaponName = nil
			_G.fishingToolCaptured = false
			_G.fishingLoadoutBusy = false
			_G.fishingState = "idle"
			_G.fishingRestoreAttempts = 0
			_G.fishingNextRestoreAttempt = 0
			_G.fishingRestoreFailureNotified = false
			return true
		end

		-- Do not leave the rod equipped while a bounded restoration retry is pending.
		pcall(function()
			local equipped = getEquippedTool()
			if equipped and string.find(string.lower(equipped.Name), "rod", 1, true) then
				humanoid:UnequipTools()
			end
		end)
		_G.fishingLoadoutBusy = false
		_G.fishingRestoreAttempts = (_G.fishingRestoreAttempts or 0) + 1
		_G.fishingNextRestoreAttempt = os.clock() + 0.75
		if _G.fishingRestoreAttempts >= 3 then
			_G.fishingToolCaptured = false
			_G.fishingPreviousWeaponName = nil
			_G.fishingState = "failed"
			if not _G.fishingRestoreFailureNotified then
				_G.fishingRestoreFailureNotified = true
				SpectrumX:Notify({
					Text = "Could not restore the previous Primary weapon after 3 attempts.",
					Type = "warning",
					Duration = 5,
				})
			end
		end
		return false
	end

	stopFishing = function()
		removeFishPosition()
		if _G.isFishing or _G.fishingState == "fishing" or _G.fishingState == "equipping_rod" then
			_G.fishingGeneration = (_G.fishingGeneration or 0) + 1
		end
		_G.isFishing = false
		_G.fishingPosition = nil
		return restoreFishingWeapon()
	end
	_G._stopFishing = stopFishing

	_G._GenesisPrepareCombatFromFishing = function(_reason)
		if not fishingOwnsWeaponSlot() then
			return true
		end
		removeFishPosition()
		_G.isFishing = false
		_G.fishingPosition = nil
		if _G.fishingLoadoutBusy then
			-- Cancel the in-flight rod selection. The worker observes this generation
			-- change, releases its lock, and restoration proceeds on the next pass.
			_G.fishingGeneration = (_G.fishingGeneration or 0) + 1
			_G.fishingState = "restoring"
			return false
		end
		return stopFishing()
	end

	local function getSavedFishCFrame()
		local cf, issue = _G._GenesisGetConfiguredFishingCFrame(game.PlaceId)
		_G.fishingPositionIssue = issue
		return cf
	end

	_G._GenesisKaidoCache = {
		liveCheckedAt = 0,
		live = nil,
		orbCheckedAt = 0,
		orbCount = 0,
	}
	_G._GenesisIsLiveKaido = function(model)
		local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil
			and humanoid.Health > 0
			and model:FindFirstChild("HumanoidRootPart") ~= nil
	end

	_G._GenesisFindLiveKaido = function()
		local cache = _G._GenesisKaidoCache
		-- Kaido's Dragon, its summon altar, and Dragon's Orb farm are Second Sea
		-- content. Never let a similarly named Sea 3 monster enter this subsystem.
		if game.PlaceId ~= 6381829480 then
			cache.live = nil
			return nil
		end
		local now = os.clock()
		if now - cache.liveCheckedAt < 0.1 then
			return _G._GenesisIsLiveKaido(cache.live) and cache.live or nil
		end
		cache.liveCheckedAt = now
		local monsterRoot = Workspace:FindFirstChild("Monster")
		if not monsterRoot then
			cache.live = nil
			return nil
		end
		for _, folder in ipairs(monsterRoot:GetChildren()) do
			if folder:IsA("Folder") then
				for _, mob in ipairs(folder:GetChildren()) do
					if string.find(mob.Name, "Dragon", 1, true) and _G._GenesisIsLiveKaido(mob) then
						cache.live = mob
						return mob
					end
				end
			end
		end
		cache.live = nil
		return nil
	end

	_G._GenesisGetDragonOrbCount = function()
		local cache = _G._GenesisKaidoCache
		if game.PlaceId ~= 6381829480 then
			cache.orbCount = 0
			return 0
		end
		local now = os.clock()
		if now - cache.orbCheckedAt < 0.2 then
			return cache.orbCount
		end
		cache.orbCheckedAt = now
		local playerStats = LocalPlayer:FindFirstChild("PlayerStats")
		local materialValue = playerStats and playerStats:FindFirstChild("Material")
		if not materialValue then
			cache.orbCount = 0
			return cache.orbCount
		end
		local success, data = pcall(function()
			return HttpService:JSONDecode(materialValue.Value)
		end)
		if not success or type(data) ~= "table" then
			cache.orbCount = 0
			return cache.orbCount
		end
		cache.orbCount = math.max(0, tonumber(data["Dragon's Orb"]) or 0)
		return cache.orbCount
	end

	local function getDesiredFishingCFrame()
		if GetSetting("inSerpentWhirlpool") then
			local whirlpoolCF = getWhirlpoolCFrame()
			if whirlpoolCF then
				return whirlpoolCF
			end
			-- Keep the legacy setting key so existing saved configurations continue
			-- to work; the option now represents downtime between any enabled bosses.
			if not GetSetting("fishWhenNotSpawned") then
				return nil
			end
		end
		return getSavedFishCFrame()
	end

	local bossFishingBlockCheckedAt = 0
	local bossFishingBlockCached = false
	local function hasEnabledBossTarget()
		-- Heartbeat also asks this question, so avoid walking every monster folder
		-- once per rendered frame. A short cache still reacts well before a cast can
		-- complete while keeping the check inexpensive.
		local now = tick()
		if now - bossFishingBlockCheckedAt < 0.2 then
			return bossFishingBlockCached
		end
		bossFishingBlockCheckedAt = now
		bossFishingBlockCached = false

		-- A live Kaido is combat, not acquisition. It always preempts fishing,
		-- including when another player spawned it and regardless of whether the
		-- downtime-only "Fish Between Boss Spawns" option is enabled. The summon
		-- NPC itself is deliberately not considered a boss target here.
		if isFeatureEnabledInCurrentSea("autoFarmKaido") then
			_G.kaidoDragon = _G._GenesisFindLiveKaido()
			if _G.kaidoDragon then
				bossFishingBlockCached = true
				return true
			end
		end

		if not GetSetting("fishWhenNotSpawned") then
			return false
		end

		local function isAlive(model)
			local humanoid = model and model.Parent and model:FindFirstChild("Humanoid")
			return humanoid ~= nil and humanoid.Health > 0
		end

		if
			(isFeatureEnabledInCurrentSea("autoFarmKaido") and isAlive(_G.kaidoDragon))
			or (isFeatureEnabledInCurrentSea("autoDarkBeard") and isAlive(_G.darkBeardBoss))
			or (isFeatureEnabledInCurrentSea("autoCrimsonDemon") and isAlive(_G.crimsonBoss))
			or (isFeatureEnabledInCurrentSea("autoIceKing") and isAlive(_G.iceKingBoss))
			or (isFeatureEnabledInCurrentSea("autoThirdSea") and isAlive(_G.thirdSeaKrakenBoss))
		then
			bossFishingBlockCached = true
			return true
		end

		local raidOk, raidTarget = pcall(getRaidBossTargetFast)
		if raidOk and isAlive(raidTarget) then
			bossFishingBlockCached = true
			return true
		end

		local selectedBossName = getCurrentSeaSelectedBoss()

		local matchNames = {}
		if isFeatureEnabledInCurrentSea("autoFarmKaido") then
			table.insert(matchNames, "Dragon")
		end
		if isFeatureEnabledInCurrentSea("autoDarkBeard") then
			table.insert(matchNames, "Dark Beard")
		end
		if isFeatureEnabledInCurrentSea("autoCrimsonDemon") then
			table.insert(matchNames, "Crimson Demon")
		end
		if isFeatureEnabledInCurrentSea("autoIceKing") then
			table.insert(matchNames, "Ice King")
		end
		if isFeatureEnabledInCurrentSea("autoSecondSea") then
			table.insert(matchNames, "Seasoned Fishman")
		end
		if isFeatureEnabledInCurrentSea("autoThirdSea") then
			table.insert(matchNames, "Kraken")
			table.insert(matchNames, "Tentacle")
		end

		local monsterRoot = Workspace:FindFirstChild("Monster")
		if monsterRoot then
			for _, folder in pairs(monsterRoot:GetChildren()) do
				if folder:IsA("Folder") then
					for _, mob in pairs(folder:GetChildren()) do
						if isAlive(mob) then
							local name = mob.Name
							local lowerName = string.lower(name)
							local isGeneralBoss = folder.Name == "Boss"
								or string.find(lowerName, "boss", 1, true) ~= nil
								or mob.Humanoid.MaxHealth > 100000

							if
								(selectedBossName and string.find(name, selectedBossName, 1, true))
								or ((GetSetting("allboss") or GetSetting("easybounty")) and isGeneralBoss)
							then
								bossFishingBlockCached = true
								return true
							end

							for _, wantedName in ipairs(matchNames) do
								if string.find(name, wantedName, 1, true) then
									bossFishingBlockCached = true
									return true
								end
							end
						end
					end
				end
			end
		end

		return false
	end

	_G._GenesisDailyQuestPriorityCheckedAt = 0
	_G._GenesisDailyQuestPriorityCandidate = nil
	_G._GenesisDailyQuestReleaseUntil = 0
	_G._GenesisGetDailyQuestPriorityCandidate = function()
		if GetSetting("autoDailyQuestsMaster") and _G._GenesisDailyQuestTravelPending then
			return true -- reserve movement and finish the fishing handoff before a sea transfer
		end
		local enabled = GetSetting("autoDailyQuestsMaster") and
			((game.PlaceId == 15759515082 and GetSetting("autoDailyQuest"))
				or (game.PlaceId == 6381829480 and GetSetting("autoSecondSeaDailyQuest")))
		if not enabled then
			_G._GenesisDailyQuestPriorityCheckedAt = 0
			_G._GenesisDailyQuestPriorityCandidate = nil
			_G._GenesisDailyQuestReleaseUntil = 0
			return nil
		end
		-- The selector is initialized later in this bundle. Reserve the slot while
		-- it loads so fishing cannot briefly claim it on an auto-execute startup.
		if not getDailyQuestPending then
			return true
		end
		local now = tick()
		if _G._GenesisDailyQuestPriorityCheckedAt > 0
			and now - _G._GenesisDailyQuestPriorityCheckedAt < 0.2 then
			return _G._GenesisDailyQuestPriorityCandidate
		end
		_G._GenesisDailyQuestPriorityCheckedAt = now
		local ok, pending, pendingState, pendingDetail = pcall(getDailyQuestPending)
		if ok and pending then
			_G._GenesisDailyQuestPriorityCandidate = pending
			_G._GenesisDailyQuestReleaseUntil = now + 1.5
		elseif ok then
			-- The coordinator worker intentionally moves only while it owns the
			-- daily slot. Publish terminal/waiting state here before that ownership
			-- is released, otherwise the UI can retain the previous objective's
			-- state and error while fishing has already resumed.
			_G.dailyQuestState = pendingState or "done"
			if pendingState == "waiting" then
				_G.dailyQuestIssue = "Waiting for daily objectives: " .. tostring(pendingDetail or "")
			elseif pendingState == "paused" then
				_G.dailyQuestIssue = "Another quest is active: " .. tostring(pendingDetail or "")
			else
				_G.dailyQuestIssue = nil
			end
			if now < _G._GenesisDailyQuestReleaseUntil then
			-- Do not send the player fishing during a brief quest-completion
			-- replication gap. This sentinel owns no movement or combat.
				_G._GenesisDailyQuestPriorityCandidate = true
			else
				_G._GenesisDailyQuestPriorityCandidate = nil
			end
		else
			_G._GenesisDailyQuestPriorityCandidate = nil
		end
		return _G._GenesisDailyQuestPriorityCandidate
	end

	isFishingBlocked = function()
		if
			_G.storingFruit
			or _G.isLootingChests
			or _G.collectingPearls
			or _G.seaEventActive
			or _G.conquestActive
			or _G.isProgressingBusoV2
			or _G.isProgressingObservationV2
			or _G.thirdSeaProgressionActive
			or _G._GenesisGetDailyQuestPriorityCandidate()
		then
			return true
		end
		-- Reserve the fishing position and Primary slot only while dungeon entry is
		-- actually selected or already committed. A merely enabled, preempted toggle
		-- must allow the lower-priority fishing fallback to run.
		if _G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation() then
			return true
		end
		if hasEnabledBossTarget() then
			return true
		end
		return false
	end

	_G._GenesisBindSwordTracker(LocalPlayer.Character)
	-- Prime the persistent fallback as soon as replicated loadout data becomes
	-- available. This only observes state; it never equips or changes a slot.
	spawn(function()
		_G._GenesisWaitForLastEquippedSwordName(8)
	end)

	trackGenesisConnection(LocalPlayer.CharacterAdded:Connect(function(character)
		removeFishPosition()
		_G.fishingGeneration = (_G.fishingGeneration or 0) + 1
		_G.isFishing = false
		_G.fishingPosition = nil
		_G.fishingPreviousTool = nil
		-- Keep the remembered name through respawn so a death while fishing cannot
		-- strand the Primary slot on Basic Rod.
		_G.fishingToolCaptured = _G.fishingPreviousWeaponName ~= nil
		_G.fishingLoadoutBusy = false
		_G.fishingState = _G.fishingToolCaptured and "restoring" or "idle"
		_G.fishingRestoreAttempts = 0
		_G.fishingNextRestoreAttempt = 0
		_G._GenesisBindSwordTracker(character)
		spawn(function()
			_G._GenesisWaitForLastEquippedSwordName(8)
		end)
	end))

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not GetSetting("autoFish") or isFishingBlocked() then
					stopFishing()
					return
				end

				if isTransformed() then
					stopFishing()
					tooltip("Fruit Power")
					task.wait(0.05)
					keyboard("V")
					task.wait(0.3)
					return
				end

				local cf = getDesiredFishingCFrame()
				if typeof(cf) ~= "CFrame" then
					stopFishing()
					return
				end

				local root = GetRoot(LocalPlayer.Character)
				if not root then
					stopFishing()
					return
				end

				-- Resolve and preserve slot 1 before fishing claims movement or replaces
				-- the Primary weapon. On a fresh join this waits boundedly for PlayerStats,
				-- EtcData, or the owned-sword inventory entry to replicate.
				_G.isFishing = true
				_G.fishingPosition = cf
				if not _G._GenesisCaptureFishingPreviousWeapon() then
					_G.isFishing = false
					_G.fishingPosition = nil
					removeFishPosition()
					return
				end
				-- Capturing the old weapon can yield. Recheck priority before taking
				-- the root position, in case a daily became eligible meanwhile.
				if not GetSetting("autoFish") or isFishingBlocked() then
					stopFishing()
					return
				end

				local dist = (cf.Position - root.Position).Magnitude
				if dist > 10 then
					-- Travelling to the fishing point already owns the root through the
					-- fish BodyMovers.  Keep the mode active during that handoff so a
					-- competing farm cannot start a second position controller.
					applyFishPosition(cf)
					root.CFrame = cf
					task.wait(0.1)
					return
				end

				applyFishPosition(cf)
				local rod = equipFishingRod()
				local character = LocalPlayer.Character
				if not rod or not character or rod.Parent ~= character then
					stopFishing()
					return
				end
				if not GetSetting("autoFish") or isFishingBlocked() then
					stopFishing()
					return
				end

				local playerGui = LocalPlayer.PlayerGui
				local fishingUI = playerGui:FindFirstChild("FishingUI")

				if not fishingUI then
					local args = {
						"SW_Basic Rod_M1",
						{
							MouseHit = cf * CFrame.new(0, 0, 5),
							Charge = 100,
						},
					}
					ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(unpack(args))
					task.wait(0.5)
				end
			end)
		end
	end)

	trackGenesisConnection(RunService.Heartbeat:Connect(function()
		pcall(function()
			if not GetSetting("autoFish") then
				if _G.isFishing or _G.fishingToolCaptured then
					stopFishing()
				end
				return
			end
			if not _G.isFishing then
				return
			end
			if isFishingBlocked() then
				stopFishing()
				return
			end

			if GetSetting("inSerpentWhirlpool") then
				local cf = getWhirlpoolCFrame()
				if cf then
					_G.fishingPosition = cf
				end
			end

			local root = GetRoot(LocalPlayer.Character)
			if root and _G.fishingPosition then
				if _fishBP and _fishBP.Parent then
					_fishBP.Position = _G.fishingPosition.Position
				end
				if _fishBG and _fishBG.Parent then
					_fishBG.CFrame = _G.fishingPosition
				end
			end

			local playerGui = LocalPlayer.PlayerGui
			local fishingUI = playerGui:FindFirstChild("FishingUI")
			if not fishingUI then
				return
			end

			local fishingBg = fishingUI:FindFirstChild("FishingBackground")
			if not fishingBg then
				return
			end

			local fishingBar = fishingBg:FindFirstChild("FishingBar")
			local fishLabel = fishingBg:FindFirstChild("FishLabel")

			if fishingBar and fishLabel then
				fishingBar.Size = UDim2.new(1, 0, fishingBar.Size.Y.Scale, fishingBar.Size.Y.Offset)
				fishingBar.Position = UDim2.new(
					fishLabel.Position.X.Scale,
					fishLabel.Position.X.Offset - (fishingBar.Size.X.Offset / 2) + (fishLabel.Size.X.Offset / 2),
					fishingBar.Position.Y.Scale,
					fishingBar.Position.Y.Offset
				)
			end
		end)
	end))

	-- Dispatches only to a button that belongs to a currently visible GUI tree.
	_G._GenesisIsVisibleGuiButton = function(button)
		if not button or not button:IsA("GuiButton") or not button.Parent then
			return false
		end
		local current = button
		while current do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end
			if current:IsA("LayerCollector") and not current.Enabled then
				return false
			end
			current = current.Parent
		end
		return button.AbsoluteSize.X > 0 and button.AbsoluteSize.Y > 0
	end

	_G._GenesisDispatchGuiButton = function(button)
		if not _G._GenesisIsVisibleGuiButton(button) then
			return false, "not_visible"
		end

		-- These game dialogs are wired through MouseButton1Click. Dispatch the
		-- exact validated signal directly so mobile GUI insets cannot shift a
		-- virtual pointer onto another control. This is intentionally one path:
		-- no blind coordinate fallback and no input-spam loop.
		if type(firesignal) ~= "function" then
			return false, "unsupported"
		end
		local clickOk = pcall(firesignal, button.MouseButton1Click)

		if not clickOk then
			return false, "click_failed"
		end
		-- firesignal schedules connected callbacks; they are not guaranteed to run
		-- before this call returns. Treat successful dispatch as sent and let each
		-- workflow verify its actual state transition.
		return true, "firesignal"
	end

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if GetSetting("buykey") then
					local args = {
						GetSetting("key1") or "Copper Key",
						GetSetting("key_count") or 1,
					}
					ReplicatedStorage.Chest.Remotes.Functions.BuyKey:InvokeServer(unpack(args))
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				local key2 = GetSetting("key2") or "Copper Key"
				if GetSetting("random1") then
					local args = { key2, "Open1" }
					ReplicatedStorage.Chest.Remotes.Functions.UseKey:InvokeServer(unpack(args))
				end
				if GetSetting("random3") then
					local args = { key2, "Open3" }
					ReplicatedStorage.Chest.Remotes.Functions.UseKey:InvokeServer(unpack(args))
				end
				if GetSetting("random10") then
					local args = { key2, "Open10" }
					ReplicatedStorage.Chest.Remotes.Functions.UseKey:InvokeServer(unpack(args))
				end
			end)
		end
	end)

	local dailyQuestCanAct
	spawn(function()
		local objectiveName = nil
		local promptCursor = 1
		local nextActionAt = 0
		local codexSubmissions = 0
		local codexDialogueRetryAt = 0
		local codexPuzzleRetryAt = 0
		local codexDialogueBlockedAt = 0
		local boxPortRequestAt = 0
		local boxPortRequests = 0
		local boxClickedProgress = nil
		local boxClickedAt = 0
		local boxClickAttempts = 0
		-- Puzzle Mania can choose different labels for the three pieces. The game
		-- validates the full placement, then resets the board on an incorrect order.
		local puzzleOrders = {
			{ 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 },
			{ 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 },
		}
		local puzzleOrderIndex = 1
		local puzzleAttemptStarted = false
		local puzzleRecovering = false
		local puzzleAwaitingResultAt = 0
		local puzzleExhausted = false
		local hoverBodyPosition = nil
		local hoverRoot = nil
		local hoverPosition = nil
		local hoverUnderwater = false
		local hoverConnection = nil

		local function clearDailyQuestSwimMovers(root)
			for _, mover in ipairs(root and root:GetChildren() or {}) do
				if (mover.Name == "Swim" and mover:IsA("AlignPosition"))
					or (mover.Name == "SwimGyro" and mover:IsA("BodyGyro")) then
					mover:Destroy()
				end
			end
		end

		local function stopDailyQuestHover()
			if hoverConnection then
				hoverConnection:Disconnect()
				hoverConnection = nil
			end
			if hoverBodyPosition then
				hoverBodyPosition:Destroy()
				hoverBodyPosition = nil
			end
			hoverRoot = nil
			hoverPosition = nil
			hoverUnderwater = false
		end
		_G._stopDailyQuestHover = stopDailyQuestHover

		local function holdDailyQuestHover(root, position, underwater)
			if hoverRoot ~= root then
				stopDailyQuestHover()
				hoverRoot = root
			end
			hoverPosition = position
			hoverUnderwater = underwater == true
			if not hoverBodyPosition or not hoverBodyPosition.Parent then
				hoverBodyPosition = Instance.new("BodyPosition")
				hoverBodyPosition.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
				hoverBodyPosition.D = 100000
				hoverBodyPosition.P = 1000000
				hoverBodyPosition.Parent = root
			end
			hoverBodyPosition.Position = position
			if hoverUnderwater then
				clearDailyQuestSwimMovers(root)
				root.CFrame = CFrame.new(position)
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if not hoverConnection then
				hoverConnection = trackGenesisConnection(RunService.Heartbeat:Connect(function()
					if not hoverRoot or not hoverRoot.Parent or not hoverPosition then
						stopDailyQuestHover()
						return
					end
					if hoverBodyPosition and hoverBodyPosition.Parent then
						hoverBodyPosition.Position = hoverPosition
					end
					if hoverUnderwater then
						-- King Legacy's swim controller repeatedly adds an AlignPosition
						-- named Swim which launches a teleported root back to the surface.
						-- Remove only those two game swim movers and keep this quest's
						-- root inside the active submerged touch volume.
						clearDailyQuestSwimMovers(hoverRoot)
						hoverRoot.CFrame = CFrame.new(hoverPosition)
					end
					hoverRoot.AssemblyLinearVelocity = Vector3.zero
					hoverRoot.AssemblyAngularVelocity = Vector3.zero
				end))
			end
		end

		local function useQuestPrompt(part, prompt, holdInAir)
			if not part or not prompt or not prompt.Enabled then
				return false
			end
			local root = GetRoot(LocalPlayer.Character)
			if not root then
				return false
			end
			local destination = part.Position + Vector3.new(0, 3, 0)
			if holdInAir then
				holdDailyQuestHover(root, destination)
			else
				stopDailyQuestHover()
			end
			local reach = math.max(3, prompt.MaxActivationDistance - 2)
			if (root.Position - part.Position).Magnitude > reach then
				tp(CFrame.new(destination))
				nextActionAt = tick() + 0.7 -- let the server see the new position
				return false
			end
			if type(fireproximityprompt) ~= "function" then
				_G.dailyQuestIssue = "Executor cannot trigger daily quest prompts"
				nextActionAt = tick() + 5
				return false
			end
			local ok = pcall(fireproximityprompt, prompt, 0)
			if not ok then
				_G.dailyQuestIssue = "Daily quest prompt failed: " .. part.Name
			end
			nextActionAt = tick() + (ok and 0.7 or 3)
			return ok
		end

		while task.wait(0.2) do
			local ok, err = pcall(function()
				if not dailyQuestCanAct or not getDailyQuestPending
					or not dailyQuestCanAct() or _G.dailyQuestState ~= "objective" or tick() < nextActionAt then
					if not dailyQuestCanAct or not getDailyQuestPending
						or not dailyQuestCanAct() or _G.dailyQuestState ~= "objective" then
						stopDailyQuestHover()
					end
					return
				end
				local current = getDailyQuestPending()
				local activeQuest = LocalPlayer:FindFirstChild("CurrentQuest")
				if not current or not activeQuest or activeQuest.Value ~= current.quest then
					stopDailyQuestHover()
					return
				end
				if objectiveName ~= current.quest then
					stopDailyQuestHover()
					objectiveName = current.quest
					promptCursor = 1
					codexSubmissions = 0
					codexDialogueRetryAt = 0
					codexPuzzleRetryAt = 0
					codexDialogueBlockedAt = 0
					boxPortRequestAt = 0
					boxPortRequests = 0
					boxClickedProgress = nil
					boxClickedAt = 0
					boxClickAttempts = 0
					puzzleOrderIndex = 1
					puzzleAttemptStarted = false
					puzzleRecovering = false
					puzzleAwaitingResultAt = 0
					puzzleExhausted = false
					_G._GenesisDailyPuzzleStatus = nil
					_G.dailyQuestIssue = nil
				end

				if current.kind == "book" then
					local islands = Workspace:FindFirstChild("Island")
					local fiore = islands and islands:FindFirstChild("H - Fiore")
					local book = fiore and fiore:FindFirstChild("Lost Book")
					local part = book and book:FindFirstChild("Main")
					local prompt = part and part:FindFirstChildWhichIsA("ProximityPrompt")
					if not part or not prompt then
						_G.dailyQuestIssue = "The Lost Book interactable is not present"
						return
					end
					useQuestPrompt(part, prompt, false)
					return
				end

				if current.kind == "boxes" then
					stopDailyQuestHover()
					local character = LocalPlayer.Character
					local root = GetRoot(character)
					local progressValue = LocalPlayer:FindFirstChild("QuestProgress")
					if not root or not progressValue then
						return
					end
					local progress = progressValue.Value
					if boxClickedProgress ~= nil then
						if progress > boxClickedProgress then
							boxClickedProgress = nil
							boxPortRequestAt = 0
							boxPortRequests = 0
							boxClickAttempts = 0
							_G.dailyQuestIssue = nil
						elseif tick() - boxClickedAt < 5 then
							return
						else
							boxClickedProgress = nil
							if boxClickAttempts >= 3 then
								_G.dailyQuestIssue = "Port delivery did not advance Box Box! after three confirmed clicks"
								return
							end
							-- A confirmed GUI click can still be rejected by the server.
							-- Recheck the same package, quest, progress, and dialogue before retrying.
							nextActionAt = tick() + 1
							return
						end
					end
					if boxClickAttempts >= 3 then
						return -- report the failure without clicking indefinitely
					end
					if progress >= 3 then
						return -- the game still needs to record the completed daily
					end

					local onQuest = character and character:FindFirstChild("onQuest")
					local packageName = LocalPlayer.Name .. "QuestBox"
					local package = character and character:FindFirstChild(packageName)
					local portGui = LocalPlayer.PlayerGui:FindFirstChild("Civilian Port")
					if not (onQuest and package) then
						if onQuest or package or portGui then
							return -- wait for pickup replication or the previous Port GUI to close
						end
						boxPortRequestAt = 0
						boxPortRequests = 0
						local spawnItems = Workspace:FindFirstChild("SpawnItem")
						local box = spawnItems and spawnItems:FindFirstChild("Box")
						local prompt = box and box:FindFirstChildWhichIsA("ProximityPrompt")
						if not box or not prompt then
							_G.dailyQuestIssue = "Box Box! pickup prompt is not present"
							return
						end
						useQuestPrompt(box, prompt, false)
						return
					end

					local port = Workspace.AllNPC:FindFirstChild("Civilian Port")
					if not port then
						_G.dailyQuestIssue = "Civilian Port NPC is not present"
						return
					end
					if portGui then
						local dialogue = portGui:FindFirstChild("Dialogue")
						local accept = dialogue and dialogue:FindFirstChild("Accept")
						local label = accept and accept:FindFirstChild("Text")
						local deliveryText = label and (label.Text == "I'm here to deliver this Package!"
							or label.Text == "ผมมาส่งของครับ!")
						if not deliveryText or not _G._GenesisIsVisibleGuiButton(accept) then
							if tick() - boxPortRequestAt > 6 then
								_G.dailyQuestIssue = "Waiting for the correct Civilian Port delivery dialogue"
							end
							return
						end

						-- The Port's server-side button handling needs a real GUI click.
						-- Use only the fruit Collect method, verified live at 0/3 -> 1/3;
						-- restore the original button layout even if input fails.
						local oldSize, oldPosition = accept.Size, accept.Position
						local mouseDown = false
						local didClick = false
						local clickConnection = accept.MouseButton1Click:Connect(function()
							didClick = true
						end)
						local clickX, clickY
						local clickOk, clickError = pcall(function()
							accept.Size = UDim2.new(10, 0, 10, 0)
							accept.Position = UDim2.new(-1.9, 0, -5.5, 0)
							RunService.RenderStepped:Wait()
							if not dailyQuestCanAct() or not _G._GenesisIsVisibleGuiButton(accept)
								or LocalPlayer.CurrentQuest.Value ~= "Box Box!"
								or progressValue.Value ~= progress
								or not character:FindFirstChild("onQuest")
								or not character:FindFirstChild(packageName) then
								return
							end
							local viewport = Workspace.CurrentCamera.ViewportSize
							clickX, clickY = viewport.X - 20, viewport.Y / 15
							local position, size = accept.AbsolutePosition, accept.AbsoluteSize
							if clickX < position.X or clickX > position.X + size.X
								or clickY < position.Y or clickY > position.Y + size.Y then
								error("Port click point is outside the enlarged button")
							end
							VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
							mouseDown = true
							task.wait(0.02)
							VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
							mouseDown = false
							-- Give Roblox a frame to dispatch MouseButton1Click before
							-- restoring the enlarged button to its normal layout.
							task.wait(0.12)
						end)
						clickConnection:Disconnect()
						if mouseDown then
							pcall(function()
								VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
							end)
						end
						pcall(function()
							accept.Size = oldSize
							accept.Position = oldPosition
						end)
						if not clickOk then
							_G.dailyQuestIssue = "Civilian Port click failed: " .. tostring(clickError)
							nextActionAt = tick() + 5
							return
						end
						boxClickAttempts = boxClickAttempts + 1
						-- The final delivery can remove the quest, package, and GUI before
						-- our diagnostic MouseButton1Click listener observes the event.
						-- The replicated quest transition is the authoritative success signal.
						if progressValue.Value > progress
							or LocalPlayer.CurrentQuest.Value ~= "Box Box!"
							or not character:FindFirstChild(packageName) then
							boxClickedProgress = nil
							boxPortRequestAt = 0
							boxPortRequests = 0
							boxClickAttempts = 0
							_G.dailyQuestIssue = nil
							nextActionAt = tick() + 0.5
							return
						end
						if not didClick then
							_G.dailyQuestIssue = "Civilian Port did not receive the delivery click"
							nextActionAt = tick() + 1
							return
						end
						boxClickedProgress = progress
						boxClickedAt = tick()
						nextActionAt = tick() + 0.5
						return
					end

					if (root.Position - port.Position).Magnitude > 8 then
						root.CFrame = CFrame.new(port.Position)
						nextActionAt = tick() + 0.8 -- let the server see the arrival
						return
					end
					if boxPortRequests >= 2 then
						if tick() - boxPortRequestAt > 6 then
							_G.dailyQuestIssue = "Civilian Port dialogue did not open after two attempts"
						end
						return
					end
					if tick() - boxPortRequestAt >= 6 then
						boxPortRequestAt = tick()
						boxPortRequests = boxPortRequests + 1
						task.spawn(function()
							if dailyQuestCanAct() and LocalPlayer.CurrentQuest.Value == "Box Box!"
								and character:FindFirstChild("onQuest")
								and character:FindFirstChild(packageName) then
								pcall(function()
									ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(port)
								end)
							end
						end)
						nextActionAt = tick() + 0.8
					end
					return
				end

				if current.kind == "prompts" then
					local spawnItems = Workspace:FindFirstChild("SpawnItem")
					if not spawnItems then
						return
					end
					local objects = {}
					for _, part in ipairs(spawnItems:GetChildren()) do
						if part.Name == current.object and part:IsA("BasePart") then
							table.insert(objects, part)
						end
					end
					table.sort(objects, function(a, b)
						return a.Position.X < b.Position.X
					end)
					if #objects == 0 then
						stopDailyQuestHover()
						_G.dailyQuestIssue = "Daily quest objects not present: " .. current.object
						return
					end
					promptCursor = ((promptCursor - 1) % #objects) + 1
					local part = objects[promptCursor]
					local prompt = part:FindFirstChild("PromptQuest") or part:FindFirstChildWhichIsA("ProximityPrompt")
					if not prompt or not prompt.Enabled then
						stopDailyQuestHover()
						promptCursor = promptCursor + 1
						return
					end
					if useQuestPrompt(part, prompt, current.object == "Floating Feather") then
						promptCursor = promptCursor + 1
					end
					return
				end

				if current.kind == "touch" then
				local spawnItems = Workspace:FindFirstChild("SpawnItem")
				local objects = {}
				for _, part in ipairs(spawnItems and spawnItems:GetChildren() or {}) do
					if part.Name == current.object and part:IsA("BasePart") then
						table.insert(objects, part)
					end
				end
				if #objects == 0 then
					stopDailyQuestHover()
					_G.dailyQuestIssue = "Daily quest touch zones not present: " .. current.object
					return
				end
				table.sort(objects, function(a, b)
					return a.Position.X < b.Position.X
				end)
				promptCursor = ((promptCursor - 1) % #objects) + 1
				local part = objects[promptCursor]
				local root = GetRoot(LocalPlayer.Character)
				if not root then
					return
				end
				-- The land pads are touched while standing above them. The Under The
				-- Sea volumes are submerged; hold the root inside each volume so water
				-- buoyancy cannot lift it away before the touch is sent.
				local underwater = current.object == "Under The Sea~"
				local progressValue = LocalPlayer:FindFirstChild("QuestProgress")
				if underwater and progressValue then
					-- A CFrame overlap can advance the server before this worker gets a
					-- chance to increment its local cursor. Drive the next zone from the
					-- replicated count so it cannot retry the first bubble forever.
					promptCursor = math.clamp(progressValue.Value + 1, 1, #objects)
					part = objects[promptCursor]
				end
				local contact = underwater and part.Position or part.Position + Vector3.new(0, 3, 0)
				if underwater then
					holdDailyQuestHover(root, contact, true)
				else
					stopDailyQuestHover()
				end
				if underwater then
					if type(firetouchinterest) ~= "function" then
						_G.dailyQuestIssue = "Executor cannot trigger daily quest touch zones"
						nextActionAt = tick() + 5
						return
					end
					local ok = pcall(function()
						-- Send the touch in the same scheduler pass as the teleport. Waiting
						-- lets the game's Swim AlignPosition eject the root first.
						root.CFrame = CFrame.new(contact)
						root.AssemblyLinearVelocity = Vector3.zero
						firetouchinterest(root, part, 0)
						firetouchinterest(root, part, 1)
					end)
					if not ok then
						_G.dailyQuestIssue = "Daily quest touch failed: " .. part.Name
					end
					-- Do not advance locally. QuestProgress selects the next unique
					-- submerged volume only after the server confirms this one.
					nextActionAt = tick() + (ok and 0.8 or 3)
					return
				end
				local delta = root.Position - contact
				local horizontalDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
				if horizontalDistance > 3 or math.abs(delta.Y) > (underwater and 2 or 5) then
					root.CFrame = CFrame.new(contact)
					nextActionAt = tick() + 0.6
					return
				end
				if type(firetouchinterest) ~= "function" then
					_G.dailyQuestIssue = "Executor cannot trigger daily quest touch zones"
					nextActionAt = tick() + 5
					return
				end
				local ok = pcall(function()
					firetouchinterest(root, part, 0)
					firetouchinterest(root, part, 1)
				end)
				if not ok then
					_G.dailyQuestIssue = "Daily quest touch failed: " .. part.Name
				end
				promptCursor = promptCursor + 1
				nextActionAt = tick() + (ok and 0.8 or 3)
				return
			end

				if current.kind == "plates" then
					local spawnItems = Workspace:FindFirstChild("SpawnItem")
					local puzzle = spawnItems and spawnItems:FindFirstChild("Puzzle_Easy")
					if not puzzle then
						_G.dailyQuestIssue = "Puzzle Mania pieces are not present"
						return
					end
					local plates = {}
					for _, part in ipairs(puzzle:GetChildren()) do
						if part.Name == "Plate" and part:IsA("BasePart") then
							table.insert(plates, part)
						end
					end
					table.sort(plates, function(a, b)
						return a.Position.X < b.Position.X
					end)
					if #plates ~= 3 then
						_G.dailyQuestIssue = "Puzzle Mania plate layout changed"
						return
					end
					local pieces, pickups, places, labels = {}, {}, {}, {}
					local boardClear, boardComplete = true, true
					local pickedCount, placedCount = 0, 0
					for i = 1, 3 do
						local piece = puzzle:FindFirstChild("Message" .. i)
						local pickup = piece and piece:FindFirstChildOfClass("ProximityPrompt")
						local place = plates[i]:FindFirstChildOfClass("ProximityPrompt")
						if not piece or not pickup or not place then
							_G.dailyQuestIssue = "Puzzle Mania prompt layout changed"
							return
						end
						pieces[i], pickups[i], places[i] = piece, pickup, place
						local billboard = piece:FindFirstChildOfClass("BillboardGui")
						local textLabel = billboard and billboard:FindFirstChildOfClass("TextLabel")
						labels[i] = textLabel and textLabel.Text or piece.Name
						boardClear = boardClear and pickup.Enabled and place.Enabled
						boardComplete = boardComplete and not pickup.Enabled and not place.Enabled
						if not pickup.Enabled then pickedCount = pickedCount + 1 end
						if not place.Enabled then placedCount = placedCount + 1 end
					end
					_G._GenesisDailyPuzzleStatus = {
						labels = labels,
						orderIndex = puzzleOrderIndex,
						order = puzzleOrders[puzzleOrderIndex],
						state = puzzleExhausted and "exhausted"
							or puzzleAwaitingResultAt > 0 and "awaiting_result"
							or puzzleRecovering and "recovering" or "placing",
						picked = pickedCount,
						placed = placedCount,
					}
					if puzzleExhausted then
						return
					end
					if puzzleAwaitingResultAt > 0 then
						if boardClear and tick() - puzzleAwaitingResultAt >= 0.6 then
							-- A rejected full order resets every prompt. Never repeat it.
							puzzleAwaitingResultAt = 0
							puzzleAttemptStarted = false
							if puzzleRecovering then
								puzzleRecovering = false
							else
								puzzleOrderIndex = puzzleOrderIndex + 1
							end
							if puzzleOrderIndex > #puzzleOrders then
								puzzleExhausted = true
								_G.dailyQuestIssue = "Puzzle Mania rejected all six placement orders"
							else
								_G.dailyQuestIssue = nil
							end
							nextActionAt = tick() + 0.5
						elseif tick() - puzzleAwaitingResultAt > 10 then
							puzzleExhausted = true
							_G.dailyQuestIssue = "Puzzle Mania did not complete or reset after placement"
						end
						return
					end
					if not puzzleAttemptStarted then
						puzzleRecovering = not boardClear
						puzzleAttemptStarted = true
					end
					if puzzleRecovering then
						-- A reload can interrupt a held piece or a partly filled board.
						-- Finish that board once, then begin the six-order search cleanly.
						if boardClear then
							puzzleRecovering = false
							puzzleAttemptStarted = false
						elseif boardComplete then
							puzzleAwaitingResultAt = tick()
						elseif pickedCount > placedCount then
							for i = 1, 3 do
								if places[i].Enabled then
									if useQuestPrompt(plates[i], places[i]) and placedCount == 2 then
										puzzleAwaitingResultAt = tick()
									end
									break
								end
							end
						elseif pickedCount == placedCount then
							for i = 1, 3 do
								if pickups[i].Enabled then
									useQuestPrompt(pieces[i], pickups[i])
									break
								end
							end
						else
							puzzleExhausted = true
							_G.dailyQuestIssue = "Puzzle Mania prompt state is inconsistent"
						end
						return
					end
					local order = puzzleOrders[puzzleOrderIndex]
					for plateIndex = 1, 3 do
						if places[plateIndex].Enabled then
							local pieceIndex = order[plateIndex]
							if pickups[pieceIndex].Enabled then
								if pickedCount > placedCount then
									puzzleRecovering = true
								else
									useQuestPrompt(pieces[pieceIndex], pickups[pieceIndex])
								end
							elseif useQuestPrompt(plates[plateIndex], places[plateIndex])
								and plateIndex == 3 then
								puzzleAwaitingResultAt = tick()
							end
							return
						end
					end
					if boardComplete then
						puzzleAwaitingResultAt = tick() -- wait for the game's completion record
					end
					return
				end

				if current.kind == "codex" then
					if codexSubmissions >= 3 then
						_G.dailyQuestIssue = "Codex did not complete after three verified submissions: " .. current.quest
						return
					end
					local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
					local gui = playerGui and playerGui:FindFirstChild("LeePungg_PuzzleLibs")
					local frame = gui and gui:FindFirstChild("MainFrame")
					local puzzleVisible = frame and frame.Visible
						and (not gui:IsA("LayerCollector") or gui.Enabled)
					if not puzzleVisible then
						local now = tick()
						-- The puzzle is created a few seconds after the final NPC choice.
						-- Do not reopen the dialogue during that transition.
						if now < codexPuzzleRetryAt then
							return
						end
						local giver = Workspace.AllNPC:FindFirstChild("Lore Kraken Codex Giver")
						if not giver then
							_G.dailyQuestIssue = "Kraken Codex giver is not present"
							return
						end
						local root = GetRoot(LocalPlayer.Character)
						if not root then
							return
						end
						if (root.Position - giver.Position).Magnitude > 8 then
							tp(CFrame.new(giver.Position + Vector3.new(0, 3, 0)))
							nextActionAt = tick() + 0.4
							return
						end
						local lore = playerGui:FindFirstChild("LoreGUI")
						local dialogue = lore and lore:FindFirstChild("Dialogue")
						local dialogueOpen = dialogue and dialogue:IsA("GuiObject") and dialogue.Visible
							and (not lore:IsA("LayerCollector") or lore.Enabled)
						if dialogueOpen then
							codexDialogueRetryAt = 0
							local npcName = dialogue:FindFirstChild("NpcName")
							local speaker = npcName and npcName:IsA("TextLabel") and npcName.Text or "unknown"
							local yes = dialogue:FindFirstChild("Quest 1")
							-- The prior Puzzle Mania researcher dialogue can remain on screen
							-- after the game has already switched CurrentQuest to the Codex.
							-- In the live game its visible "Hint,Please" choice advances
							-- that stale screen; "Quest 1" is still hidden at this stage.
							if speaker == "Sea's Researcher" then
								local hint = dialogue:FindFirstChild("QuestAccept")
								local hintText = hint and hint:FindFirstChild("Text")
								yes = hintText and hintText:IsA("TextLabel")
									and hintText.Text == "Hint,Please" and hint or nil
							end
							if yes and _G._GenesisIsVisibleGuiButton(yes) then
								local sent = _G._GenesisDispatchGuiButton(yes)
								if sent then
									codexDialogueBlockedAt = 0
									_G.dailyQuestIssue = nil
									codexPuzzleRetryAt = tick() + 6
								end
							else
								if codexDialogueBlockedAt == 0 then
									codexDialogueBlockedAt = now
								elseif now - codexDialogueBlockedAt > 10 then
									_G.dailyQuestIssue = "Codex dialogue has no visible choice: " .. speaker
								end
							end
							-- While text animates and the answer is hidden, just wait.
							nextActionAt = tick() + 0.25
							return
						end
						codexDialogueBlockedAt = 0
						if now < codexDialogueRetryAt then
							return
						end
						local opened = pcall(function()
							ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(giver)
						end)
						codexDialogueRetryAt = tick() + (opened and 5 or 2)
						nextActionAt = tick() + 0.5
						return
					end
					codexDialogueRetryAt = 0
					codexPuzzleRetryAt = 0
					codexDialogueBlockedAt = 0
					_G.dailyQuestIssue = nil
					local pack = gui:FindFirstChild("PuzzlePack")
					if not pack then
						_G.dailyQuestIssue = "Kraken Codex UI has no PuzzlePack"
						return
					end
					local chosen = pack:GetChildren()
					for i, value in ipairs(chosen) do
						if value.Name ~= tostring(current.words[i]) then
							pack:ClearAllChildren() -- reset a stale partial client-side input
							chosen = {}
							break
						end
					end
					if #chosen < 3 then
						local slot = frame:FindFirstChild("Slot" .. current.words[#chosen + 1])
						local button = slot and slot:FindFirstChildWhichIsA("TextButton", true)
						if not _G._GenesisDispatchGuiButton(button) then
							_G.dailyQuestIssue = "Kraken Codex word button is unavailable"
						end
						nextActionAt = tick() + 0.3
						return
					end
					if _G._GenesisDispatchGuiButton(gui:FindFirstChild("Send")) then
						codexSubmissions = codexSubmissions + 1
					end
					nextActionAt = tick() + 2
				end
			end)
			if not ok then
				stopDailyQuestHover()
				_G.dailyQuestIssue = tostring(err)
			end
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if isFeatureEnabledInCurrentSea("farmmaterial")
					and GetSetting("getQuestMaterial") and not _G.seaEventActive then
					local questName = getMaterialQuest()
					if questName and questName ~= "" then
						ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", questName)
					end
				end
			end)
		end
	end)

	spawn(function()
		-- Moving every fruit at 100 Hz is needlessly expensive; a quarter-second
		-- cadence still picks new spawns up promptly.
		while task.wait(0.25) do
			pcall(function()
				bringFruits()
			end)
		end
	end)

	spawn(function()
		while task.wait(8) do
			pcall(function()
				_G.reportSpawnedFruits()
			end)
		end
	end)

	spawn(function()
		while task.wait(3) do
			pcall(function()
				collectPearls()
			end)
		end
	end)

	local function getSeaSuffix()
		local seaNum = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3
		return " [Sea " .. seaNum .. "]"
	end

	-- Build the exact *current* event set. The older notification callbacks below
	-- are one-shot and cannot tell the backend when an event disappears.
	function Hub:collectCurrentEvents()
		local events, seen = {}, {}
		local seaNum = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3
		local suffix = " [Sea " .. seaNum .. "]"
		local seaChannel = "sea_events_" .. seaNum
		local function add(channel, title, eventType)
			if #events >= 40 or type(title) ~= "string" then
				return
			end
			local key = channel .. ":" .. title:lower():gsub("%s+", "")
			if not seen[key] then
				seen[key] = true
				table.insert(events, { channel = channel, title = title, event_type = eventType })
			end
		end
		local function alive(model)
			if not model or not model.Parent then
				return false
			end
			local humanoid = model:FindFirstChild("Humanoid")
			return humanoid ~= nil and humanoid.Health > 0
		end
		local function seaType(name)
			local lower = name:lower()
			if lower:find("galleon") then return "Galleon" end
			if lower:find("serpent") then return "Serpent" end
			if lower:find("hydra") then return "Hydra" end
			if lower:find("seaking") or lower:find("sea king") then return "SeaKing" end
			if lower:find("kraken") or lower:find("tentacle") then return "Kraken" end
			if lower:find("drakenfyr") or lower:find("thirdseadragon") then return "Drakenfyr" end
			if lower:find("seadragon") then return "AbyssalTyrant" end
			if lower:find("eldritch") or lower:find("crusher") then return "DeepseaCrusher" end
			return "SeaEvent"
		end
		if getWhirlpoolCFrame() then
			add(seaChannel, "Whirlpool" .. suffix, "Whirlpool")
		end
		local seaMonsters = Workspace:FindFirstChild("SeaMonster")
		if seaMonsters then
			for _, monster in ipairs(seaMonsters:GetChildren()) do
				local seaKingModel = seaNum == 2 and (monster.Name == "SeaKing" or monster.Name == "HydraSeaKing")
				if alive(monster) or (seaKingModel and not monster:FindFirstChild("Humanoid")) then
					if monster.Name:find("Serpent") then
						add(seaChannel, "Serpent" .. suffix, "Serpent")
					elseif seaNum == 2 and monster.Name == "SeaKing" then
						add(seaChannel, "Sea King" .. suffix, "SeaKing")
					elseif seaNum == 2 and monster.Name == "HydraSeaKing" then
						add(seaChannel, "Hydra" .. suffix, "Hydra")
					elseif seaNum == 3 then
						local name = getDisplayEventName(monster.Name):gsub("%s*Boss%s*$", "")
						add(seaChannel, name .. suffix, seaType(monster.Name))
					end
				end
			end
		end
		local bossFolder = Workspace:FindFirstChild("Monster")
		bossFolder = bossFolder and bossFolder:FindFirstChild("Boss")
		if bossFolder then
			local kraken = bossFolder:FindFirstChild("FuryTentacle")
			if seaNum == 3 and alive(kraken) then
				add(seaChannel, "Kraken" .. suffix, "Kraken")
			end
			for _, child in ipairs(bossFolder:GetChildren()) do
				if alive(child) then
					if child.Name:find("Serpent") then
						add(seaChannel, "Serpent" .. suffix, "Serpent")
					end
					if seaNum == 3 and (child.Name:find("SeaDragon") or child.Name:find("ThirdSeaEldritch")) then
						add(seaChannel, getDisplayEventName(child.Name) .. suffix, seaType(child.Name))
					end
				end
			end
			local priority = raidPriority[game.PlaceId] or {}
			for _, bossName in ipairs(priority) do
				for _, child in ipairs(bossFolder:GetChildren()) do
					if child.Name:find(bossName, 1, true) and alive(child) then
						add("raid_bosses_" .. seaNum, bossName .. suffix, "RaidBoss")
					end
				end
			end
		end
		if seaNum == 2 then
			local ghostFolder = Workspace:FindFirstChild("GhostMonster")
			local ghost = ghostFolder and ghostFolder:FindFirstChild("Ghost Ship")
			if alive(ghost) then
				add(seaChannel, "Ghost Ship" .. suffix, "GhostShip")
			end
		end
		if seaNum == 3 then
			local islands = Workspace:FindFirstChild("Island")
			if islands then
				for _, island in ipairs(islands:GetChildren()) do
					local name = island.Name
					if name:find("Human") or name:find("Gale") or name:find("SeaKing")
						or name:find("Angel") or name:find("Animal") or name:find("Fish")
						or name:find("Demon") then
						add("race_island", getDisplayRaceName(name) .. suffix, "RaceIsland")
					end
				end
			end
		end
		if _G._GenesisFruitLiveState then
			local fruit = _G._GenesisFruitLiveState
			add(fruit.channel, fruit.title, fruit.event_type)
		end
		table.sort(events, function(a, b)
			return a.channel .. a.title < b.channel .. b.title
		end)
		return events
	end

	spawn(function()
		while task.wait(1) do
			if Hub.enabled and Hub.devEnabled then
				pcall(function()
					Hub:publish(Hub:collectCurrentEvents())
				end)
			end
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				local whirlpoolExists = (getWhirlpoolCFrame() ~= nil)
				if whirlpoolExists and not _G.lastWhirlpoolState then
					_G.lastWhirlpoolState = true
					local webhookKey = "sea_events_"
						.. (game.PlaceId == 4520749081 and "1" or game.PlaceId == 6381829480 and "2" or "3")
					local title = "Whirlpool" .. getSeaSuffix()
					sendWebhook(_G.webhook[webhookKey], title, {})
				elseif not whirlpoolExists and _G.lastWhirlpoolState then
					_G.lastWhirlpoolState = false
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				local seaNum = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3
				local webhookKey = "sea_events_" .. seaNum
				local suffix = " [Sea " .. seaNum .. "]"
				for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
					if
						string.find(monster.Name, "Serpent")
						and monster:FindFirstChild("Humanoid")
						and monster.Humanoid.Health > 0
						and not monster:FindFirstChild("done")
					then
						doneNotification(monster)
						sendWebhook(_G.webhook[webhookKey], "Serpent" .. suffix, {})
					end
				end
				if Workspace.Monster:FindFirstChild("Boss") then
					for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
						if
							string.find(child.Name, "Serpent")
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
							and not child:FindFirstChild("done")
						then
							doneNotification(child)
							sendWebhook(_G.webhook[webhookKey], "Serpent" .. suffix, {})
						end
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if game.PlaceId ~= 6381829480 then
					return
				end
				local suffix = " [Sea 2]"
				for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
					if monster.Name == "SeaKing" and not monster:FindFirstChild("done") then
						doneNotification(monster)
						sendWebhook(_G.webhook.sea_events_2, "Sea King" .. suffix, {})
					end
					if monster.Name == "HydraSeaKing" and not monster:FindFirstChild("done") then
						doneNotification(monster)
						sendWebhook(_G.webhook.sea_events_2, "Hydra" .. suffix, {})
					end
				end
				if Workspace.Monster:FindFirstChild("Boss") then
					for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
						if
							string.find(child.Name, "Serpent")
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
							and not child:FindFirstChild("done")
						then
							doneNotification(child)
							sendWebhook(_G.webhook.sea_events_2, "Serpent" .. suffix, {})
						end
					end
				end
				local ghostShip = Workspace.GhostMonster:FindFirstChild("Ghost Ship")
				if
					ghostShip
					and ghostShip:FindFirstChild("Humanoid")
					and ghostShip.Humanoid.Health > 0
					and not ghostShip:FindFirstChild("done")
				then
					doneNotification(ghostShip)
					sendWebhook(_G.webhook.sea_events_2, "Ghost Ship" .. suffix, {})
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if game.PlaceId ~= 15759515082 then
					return
				end
				local suffix = " [Sea 3]"
				for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
					if
						string.find(monster.Name, "Galleon")
						and monster:FindFirstChild("Humanoid")
						and monster.Humanoid.Health > 0
						and not monster:FindFirstChild("done")
					then
						doneNotification(monster)
						local galleonName = getDisplayEventName(monster.Name):gsub("%s*Boss%s*$", "")
						sendWebhook(_G.webhook.sea_events_3, galleonName .. suffix, {})
					elseif
						not string.find(monster.Name, "Galleon")
						and monster:FindFirstChild("Humanoid")
						and monster.Humanoid.Health > 0
						and not monster:FindFirstChild("done")
					then
						doneNotification(monster)
						local eventName = getDisplayEventName(monster.Name)
						sendWebhook(_G.webhook.sea_events_3, eventName .. suffix, {})
					end
				end
				if Workspace.Monster:FindFirstChild("Boss") then
					local bossFolder = Workspace.Monster.Boss
					local kraken = bossFolder:FindFirstChild("FuryTentacle")
					if
						kraken
						and kraken:FindFirstChild("Humanoid")
						and kraken.Humanoid.Health > 0
						and not bossFolder:FindFirstChild("done")
					then
						doneNotification(bossFolder)
						sendWebhook(_G.webhook.sea_events_3, "Kraken" .. suffix, {})
					elseif not kraken and bossFolder:FindFirstChild("done") then
						bossFolder:FindFirstChild("done"):Destroy()
					end
					for _, child in pairs(bossFolder:GetChildren()) do
						if
							string.find(child.Name, "Serpent")
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
							and not child:FindFirstChild("done")
						then
							doneNotification(child)
							sendWebhook(_G.webhook.sea_events_3, "Serpent" .. suffix, {})
						end
					end
					for _, child in pairs(bossFolder:GetChildren()) do
						local isSeaDragon = string.find(child.Name, "SeaDragon")
							or string.find(child.Name, "ThirdSeaDragon")
						local isEldritch = string.find(child.Name, "ThirdSeaEldritch")
						if
							(isSeaDragon or isEldritch)
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
							and not child:FindFirstChild("done")
						then
							doneNotification(child)
							local eventName = getDisplayEventName(child.Name)
							sendWebhook(_G.webhook.sea_events_3, eventName .. suffix, {})
						end
					end
				end

				for _, island in pairs(Workspace.Island:GetChildren()) do
					local name = island.Name
					if
						(
							string.find(name, "Human")
							or string.find(name, "Gale")
							or string.find(name, "SeaKing")
							or string.find(name, "Angel")
							or string.find(name, "Animal")
							or string.find(name, "Fish")
							or string.find(name, "Demon")
						) and not island:FindFirstChild("done")
					then
						doneNotification(island)
						local raceName = getDisplayRaceName(name)
						sendWebhook(_G.webhook.race_island, raceName .. suffix, {})
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if not Workspace.Monster:FindFirstChild("Boss") then
					return
				end
				local bossFolder = Workspace.Monster.Boss
				local priority = raidPriority[game.PlaceId] or {}
				local seaNumber = game.PlaceId == 4520749081 and 1 or game.PlaceId == 6381829480 and 2 or 3
				local webhookKey = "raid_bosses_" .. seaNumber
				local suffix = " [Sea " .. seaNumber .. "]"

				for _, bossName in ipairs(priority) do
					for _, child in pairs(bossFolder:GetChildren()) do
						if
							string.find(child.Name, bossName)
							and child:FindFirstChild("Humanoid")
							and child.Humanoid.Health > 0
							and not child:FindFirstChild("done")
						then
							doneNotification(child)
							sendWebhook(_G.webhook[webhookKey], bossName .. suffix, {})
						end
					end
				end
			end)
		end
	end)

	_G._GenesisRunRaidBossAutomation = function()
		updateRaidCache()
		updateRaidStatusLabel()

		-- Kaido's live Dragon is a world boss, so it belongs in this early phase
		-- with the other current-sea raid bosses. Orb farming and summoning remain
		-- in the low-priority Kaido fallback later in the resolver.
		local activeTarget = cachedTarget
		local activeBossName = cachedBossName
		if isFeatureEnabledInCurrentSea("autoFarmKaido")
			and type(_G._GenesisFindLiveKaido) == "function" then
			local liveKaido = _G._GenesisFindLiveKaido()
			if liveKaido then
				activeTarget = liveKaido
				activeBossName = liveKaido.Name
				_G.kaidoDragon = liveKaido
				if type(_G._stopKaidoAcquisition) == "function" then
					_G._stopKaidoAcquisition("boss_spawned")
				end
			end
		end

		if
			activeTarget
			and activeTarget.Parent
			and activeTarget:FindFirstChild("HumanoidRootPart")
			and activeTarget:FindFirstChild("Humanoid")
			and activeTarget.Humanoid.Health > 0
		then
			if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
				return true, activeBossName
			end
			if _G._GenesisPrepareCombatFromFishing and not _G._GenesisPrepareCombatFromFishing("raid_boss") then
				return true, activeBossName
			end
			if _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit() then
				return true, activeBossName
			end
			pcall(function()
				local hrp = activeTarget.HumanoidRootPart
				if hrp then
					getDownwardCFrame(hrp.CFrame)
					local height = GetSetting("distance") or 8
					local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
					updateFarmFix(targetCF, hrp)
					if not _G.farmFixThread then
						applyFarmFix(targetCF, hrp)
					end
				end
				_G.pos_skill = activeTarget.HumanoidRootPart.CFrame
				usetool()
				buso()
				ken()
				click()
				autoskill()
				handleOpeMethod()
			end)
			return true, activeBossName
		end
		removeFarmFix()
		return false, nil
	end

	_G._GenesisRunDailyQuestCombat = function(current)
		local target = _G.dailyQuestTarget
		local activeQuest = LocalPlayer:FindFirstChild("CurrentQuest")
		if _G.dailyQuestState ~= "kill" or _G.dailyQuestCurrentName ~= current.quest
			or current.kind ~= "mob" or not current.mob
			or not activeQuest or activeQuest.Value ~= current.quest
			or not target or not target.Parent
			or not string.find(target.Name, current.mob, 1, true)
			or not target:FindFirstChild("Humanoid") or target.Humanoid.Health <= 0
			or not target:FindFirstChild("HumanoidRootPart") then
			_G.allowCombat = false
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			return
		end

		usetool()
		buso()
		ken()
		hao()
		local hrp = target.HumanoidRootPart
		getDownwardCFrame(hrp.CFrame)
		local height = GetSetting("distance") or 8
		local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
		updateFarmFix(targetCF, hrp)
		if not _G.farmFixThread then
			applyFarmFix(targetCF, hrp)
		end
		_G.pos_skill = hrp.CFrame
		_G.allowCombat = true
		click()
		autoskill()
		handleOpeMethod()
	end

	_G._GenesisAutomationStepBusy = false
	_G._GenesisRunAutomationStep = function()
		-- A visible difficulty picker is already committed: leaving the circle can no
		-- longer cancel entry. Treat that transition and the loaded dungeon exactly
		-- like an active dungeon, even when the toggle is subsequently switched off.
		local dungeonCommitted, dungeonStage = _G._GenesisUpdateDungeonCommit()
		if dungeonCommitted then
			_G._GenesisSetPriorityOwner("dungeon_committed", dungeonStage)
			_G.allowCombat = false
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			if _G.isFishing or _G.fishingToolCaptured then
				stopFishing()
			end
			if _G.farmFixThread or _G.farmFixBodyPos then
				pcall(removeFarmFix)
			end
			if removeChestLootFix then
				pcall(removeChestLootFix)
			end
			if type(_G._stopAbyssalAcquisition) == "function" then
				pcall(_G._stopAbyssalAcquisition)
			end
			return
		end

		if _G.storingFruit then
			_G._GenesisSetPriorityOwner("fruit_transaction", "storing")
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			if _G.isFishing or _G.fishingToolCaptured then
				stopFishing()
			end
			return
		end

		-- Highest priority: Buso V2 / Ken V2 (unlock automations).
		if _G.isProgressingBusoV2 or _G.isProgressingObservationV2 then
			_G._GenesisSetPriorityOwner("haki_progression", _G.isProgressingBusoV2 and "buso_v2" or "ken_v2")
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			if _G.isFishing or _G.fishingToolCaptured then
				stopFishing()
			end
			-- Remove the normal farmFix so it does not conflict with the Haki V2 lock.
			if _G.farmFixThread then
				pcall(removeFarmFix)
			end
			return
		end

		-- Resolve independent event classes in explicit priority order. The phase
		-- calls retain the known-good leaf combat implementations; only ownership and
		-- dispatch order are centralized here.
		if checkSeaEvents("major") then
			_G._GenesisSetPriorityOwner("major_sea_event", _G.currentEventName)
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			return
		end

		local hasRaidBoss, raidBossName = _G._GenesisRunRaidBossAutomation()
		if hasRaidBoss then
			_G._GenesisSetPriorityOwner("world_raid_boss", raidBossName)
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			return
		end

		if checkSeaEvents("serpent") then
			_G._GenesisSetPriorityOwner("serpent", _G.currentEventName)
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			return
		end

		if checkSeaEvents("galleon") then
			_G._GenesisSetPriorityOwner("galleon", _G.currentEventName)
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			return
		end

		-- Outbound daily travel is a real movement phase, just like returning to
		-- the configured main sea. It must claim ownership before the idle/normal
		-- automation short-circuit below; otherwise the travel worker reserves the
		-- route (blocking fishing) but rejects movement because the owner is idle.
		-- Live world bosses and sea events above still retain absolute priority.
		if
			GetSetting("autoDailyQuestsMaster")
			and _G._GenesisDailyQuestTravelPending
			and not _G._GenesisDailyReturnRequested
		then
			local enteringTravel = _G._GenesisPriorityOwner ~= "daily_quest_handoff"
			_G._GenesisSetPriorityOwner("daily_quest_handoff", "cross_sea_travel")
			_G.allowCombat = false
			if fishingOwnsWeaponSlot() then
				_G._GenesisPrepareCombatFromFishing("daily_quest_travel")
			end
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			if removeChestLootFix and (enteringTravel or _G.isLootingChests) then
				removeChestLootFix()
			end
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			if _G.HakiV2 and (_G.HakiV2.lockCF or _G.HakiV2.lockConn)
				and type(_G.HakiV2.stopLock) == "function" then
				_G.HakiV2.stopLock()
			end
			if enteringTravel and type(_G._stopSeaEventBypass) == "function" then
				_G._stopSeaEventBypass()
			end
			if enteringTravel and type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			if enteringTravel and type(_G._stopDailyQuestHover) == "function" then
				_G._stopDailyQuestHover()
			end
			return
		end

		-- Daily return remains committed, but every live world boss and sea event
		-- above may pause it. Once that higher-priority target is gone, the same
		-- route resumes without losing its selected destination.
		if GetSetting("autoDailyQuestsMaster") and _G._GenesisDailyReturnRequested then
			local enteringReturn = _G._GenesisPriorityOwner ~= "daily_quest_return"
			_G._GenesisSetPriorityOwner("daily_quest_return", "main_sea")
			_G.allowCombat = false
			if fishingOwnsWeaponSlot() then
				_G._GenesisPrepareCombatFromFishing("daily_quest_return")
			end
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			if removeChestLootFix and (enteringReturn or _G.isLootingChests) then
				removeChestLootFix()
			end
			if _G.conquestActive and removeConquestPosition then
				removeConquestPosition()
			end
			if _G.HakiV2 and (_G.HakiV2.lockCF or _G.HakiV2.lockConn)
				and type(_G.HakiV2.stopLock) == "function" then
				_G.HakiV2.stopLock()
			end
			if enteringReturn and type(_G._stopSeaEventBypass) == "function" then
				_G._stopSeaEventBypass()
			end
			if enteringReturn and type(_G._stopAbyssalAcquisition) == "function" then
				_G._stopAbyssalAcquisition()
			end
			if enteringReturn and type(_G._stopDailyQuestHover) == "function" then
				_G._stopDailyQuestHover()
			end
			return
		end

		-- Enabling Auto Dungeon is only a request. It owns movement after every
		-- higher phase is absent and while the near-event gate permits a new entry.
		if GetSetting("auto_dungeon_v2") then
			local nearSeaEvent, _, timerText = _G._GenesisIsSeaEventNear()
			if not nearSeaEvent then
				_G._GenesisSetPriorityOwner("dungeon_entry", "waiting_for_picker")
				if _G.conquestActive and removeConquestPosition then
					removeConquestPosition()
				end
				if fishingOwnsWeaponSlot() then
					_G._GenesisPrepareCombatFromFishing("dungeon_entry")
				end
				if _G.farmFixThread or _G.farmFixBodyPos then
					pcall(removeFarmFix)
				end
				return
			end
			_G._GenesisSetPriorityOwner("dungeon_paused", "sea_event_near:" .. tostring(timerText))
		end

		if _G.collectingPearls then
			_G._GenesisSetPriorityOwner("pearl_collection", "collecting")
			if _G.isFishing or _G.fishingToolCaptured then
				stopFishing()
			end
			if _G.farmFixThread or _G.farmFixBodyPos then
				pcall(removeFarmFix)
			end
			return
		end

		-- No combat automation enabled → clear locks and exit.
		-- A flag capture uses its own BodyPosition/BodyGyro. Do not let normal
		-- farming create a second movement controller until it has released them.
		if _G.conquestActive then
			_G._GenesisSetPriorityOwner("conquest", "capturing")
			if _G.isFishing or _G.fishingToolCaptured then
				stopFishing()
			end
			if _G.farmFixThread or _G.farmFixBodyPos then
				pcall(removeFarmFix)
			end
			return
		end

		local dailyQuest = _G._GenesisGetDailyQuestPriorityCandidate()
		if dailyQuest and fishingOwnsWeaponSlot() then
			_G.allowCombat = false
			_G._GenesisSetPriorityOwner("daily_quest_handoff", "restoring_weapon")
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			_G._GenesisPrepareCombatFromFishing("daily_quest")
			return
		end
		if _G._GenesisPriorityOwner == "daily_quest" or _G._GenesisPriorityOwner == "daily_quest_handoff" then
			_G.allowCombat = false
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			-- Floating Feather needs its hover lock across resolver passes. The
			-- objective worker clears it when ownership or the quest is lost.
			if not dailyQuest and type(_G._stopDailyQuestHover) == "function" then
				_G._stopDailyQuestHover()
			end
		end

		local fishingBlocked = isFishingBlocked()
		local fishingDestination = nil
		if GetSetting("autoFish") and not fishingBlocked then
			fishingDestination = getDesiredFishingCFrame()
		end

		-- Reserve movement and the Primary weapon slot as soon as fishing is both
		-- enabled and usable. This closes the half-second startup window in which a
		-- frame-rate Auto Farm pass could equip the sword before isFishing became true.
		if typeof(fishingDestination) == "CFrame" then
			_G._GenesisSetPriorityOwner("fishing", "available")
			_G.allowCombat = false
			if _G.farmFixThread or _G.farmFixBodyPos then
				removeFarmFix()
			end
			return
		end

		if fishingOwnsWeaponSlot() then
			_G._GenesisSetPriorityOwner("fishing_handoff", "restoring_weapon")
			_G._GenesisPrepareCombatFromFishing("automation")
			return
		end

		-- Do not let combat start while the Primary slot is still being switched
		-- back from Basic Rod to the weapon that fishing replaced.
		if _G.fishingToolCaptured or _G.fishingLoadoutBusy then
			_G._GenesisSetPriorityOwner("fishing_handoff", "restoring_weapon")
			stopFishing()
			return
		end

		_G._GenesisSetPriorityOwner("other_combat", "normal_automation")
		if not _G.isAnyCombatActive() then
			_G._GenesisSetPriorityOwner("idle", nil)
			_G.allowCombat = false
			if _G.farmFixThread or _G.farmFixBodyPos then
				pcall(removeFarmFix)
			end
			return
		end

		local selectedBossName, selectedBossCFrame = getCurrentSeaSelectedBoss()
		if not selectedBossName then
			_G.selectedBossName = nil
			_G.selectedBossCFrame = nil
		end
		if selectedBossName and not _G.raidBossTarget and not _G.seaEventActive and not _G.storingFruit then
			pcall(function()
				local bossName = selectedBossName
				_G.selectedBossName = bossName
				_G.selectedBossCFrame = selectedBossCFrame

				if not isValidFarmMob(currentFarmTarget, bossName) then
					currentFarmTarget = findFarmMob(bossName, nil)
				end

				if currentFarmTarget then
					isFarmingMob = true
					usetool()
					buso()
					ken()

					local hrp = currentFarmTarget.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = currentFarmTarget.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				else
					isFarmingMob = false
					currentFarmTarget = nil
					removeFarmFix()
					local bossCF = selectedBossCFrame
					if bossCF then
						tp(bossCF)
					end
				end
			end)
			return
		end

		-- The entire Kaido resolver branch is Second Sea-only. Keeping the toggle
		-- enabled while travelling must never publish a Kaido owner in another sea.
		if isFeatureEnabledInCurrentSea("autoFarmKaido") then
			local kaidoHandled = false
			pcall(function()
				local dragon = _G._GenesisFindLiveKaido()
				local orbCount = _G._GenesisGetDragonOrbCount()
				_G.kaidoDragon = dragon
				_G.kaidoHasOrb = orbCount >= 1

				if dragon then
					kaidoHandled = true
					_G._GenesisSetPriorityOwner("world_raid_boss", dragon.Name)
					if type(_G._stopKaidoAcquisition) == "function" then
						_G._stopKaidoAcquisition("boss_spawned")
					end
					usetool()
					buso()
					ken()

					local hrp = dragon.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = dragon.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
					return
				end

				-- Orb farming and summoning are fallback work, not the Kaido boss
				-- itself. Let a pending daily objective or sea transfer reach its
				-- own resolver branch; a live Dragon above still preempts it.
				if dailyQuest then
					if type(_G._stopKaidoAcquisition) == "function" then
						_G._stopKaidoAcquisition("daily_quest")
					end
					return
				end
				kaidoHandled = true

				_G.allowCombat = false
				removeFarmFix()
				if orbCount >= 1 then
					-- Acquisition is a low-priority leaf. The dedicated worker below may
					-- move only while this exact owner is still published; fishing and
					-- every higher-priority activity cause it to release immediately.
					_G._GenesisSetPriorityOwner("other_combat", "kaido_acquisition")
					return
				end

				if type(_G._stopKaidoAcquisition) == "function" then
					_G._stopKaidoAcquisition("orb_missing")
				end
				_G._GenesisSetPriorityOwner("other_combat", "kaido_orb_farm")
				local eliteSkeleton = nil
				local monsterRoot = Workspace:FindFirstChild("Monster")
				if monsterRoot then
					for _, folder in pairs(monsterRoot:GetChildren()) do
						if folder:IsA("Folder") then
							for _, mob in pairs(folder:GetChildren()) do
								local humanoid = mob:FindFirstChild("Humanoid")
								local mobRoot = mob:FindFirstChild("HumanoidRootPart")
								if
									humanoid
									and humanoid.Health > 0
									and mobRoot
									and string.find(mob.Name, "Elite Skeleton")
								then
									eliteSkeleton = mob
									break
								end
							end
						end
						if eliteSkeleton then
							break
						end
					end
				end

				if eliteSkeleton then
					usetool()
					buso()
					ken()

					local hrp2 = eliteSkeleton:FindFirstChild("HumanoidRootPart")
					if hrp2 then
						getDownwardCFrame(hrp2.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp2.Position + Vector3.new(0, height, 0), hrp2.Position)
						updateFarmFix(targetCF, hrp2)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp2)
						end
						_G.pos_skill = hrp2.CFrame
						_G.allowCombat = true
						click()
						autoskill()
						handleOpeMethod()
					end
					return
				end

				-- The previous branch returned here with no movement owner after the
				-- current Elite Skeleton died. Wait at its spawn so the next replica is
				-- acquired immediately. Fishing and daily work still win above this
				-- low-priority leaf.
				_G._GenesisSetPriorityOwner("other_combat", "kaido_orb_waiting")
				local eliteSpawnCFrame = CFrame.new(-5926, 98, 7183)
				local root = GetRoot(LocalPlayer.Character)
				if root and (root.Position - eliteSpawnCFrame.Position).Magnitude > 8 then
					tp(eliteSpawnCFrame)
				end
			end)
			if kaidoHandled then
				return
			end
		end

		if isFeatureEnabledInCurrentSea("autoDarkBeard") then
			pcall(function()
				local darkBeard = _G.darkBeardBoss
				if darkBeard and darkBeard.Parent and darkBeard.Humanoid.Health > 0 then
					usetool()
					buso()
					ken()

					local hrp = darkBeard.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = darkBeard.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				elseif not darkBeard and (_G.darkBeardTotemCount == nil or _G.darkBeardTotemCount < 1) then
					removeFarmFix()
					local foundMob = false
					for _, folder in pairs(Workspace.Monster:GetChildren()) do
						if folder:IsA("Folder") then
							for _, mob in pairs(folder:GetChildren()) do
								if mob:FindFirstChild("Humanoid") and mob.Humanoid.Health > 0 then
									if
										string.find(mob.Name, "Dark Beard Servant")
										or string.find(mob.Name, "Supreme Swordman")
									then
										foundMob = true
										usetool()
										buso()
										ken()

										local hrp2 = mob.HumanoidRootPart
										if hrp2 then
											getDownwardCFrame(hrp2.CFrame)
											local height = GetSetting("distance") or 8
										local targetCF =
											CFrame.new(hrp2.Position + Vector3.new(0, height, 0), hrp2.Position)
										updateFarmFix(targetCF, hrp2)
										if not _G.farmFixThread then
											applyFarmFix(targetCF, hrp2)
										end
										end

										_G.pos_skill = mob.HumanoidRootPart.CFrame
										_G.allowCombat = true
										click()
										autoskill()
										handleOpeMethod()
										return
									end
								end
							end
						end
					end
					if not foundMob then
						tp(CFrame.new(-9486, 77, -4761))
					end
				end
			end)
			return
		end

		if isFeatureEnabledInCurrentSea("autoCrimsonDemon") then
			pcall(function()
				if _G.crimsonCrystalCount == nil then
					_G.crimsonCrystalCount = 0
				end
				local crimson = _G.crimsonBoss
				if crimson and crimson.Parent and crimson.Humanoid.Health > 0 then
					usetool()
					buso()
					ken()

					local hrp = crimson.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = crimson.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				elseif not crimson and _G.crimsonCrystalCount < 1 then
					removeFarmFix()
					local foundMob = false
					for _, folder in pairs(Workspace.Monster:GetChildren()) do
						if folder:IsA("Folder") then
							for _, mob in pairs(folder:GetChildren()) do
								if
									mob:FindFirstChild("Humanoid")
									and mob.Humanoid.Health > 0
									and string.find(mob.Name, "The Volcano")
								then
									foundMob = true
									usetool()
									buso()
									ken()

									local hrp2 = mob.HumanoidRootPart
									if hrp2 then
										getDownwardCFrame(hrp2.CFrame)
										local height = GetSetting("distance") or 8
										local targetCF =
											CFrame.new(hrp2.Position + Vector3.new(0, height, 0), hrp2.Position)
										updateFarmFix(targetCF, hrp2)
										if not _G.farmFixThread then
											applyFarmFix(targetCF, hrp2)
										end
									end

									_G.pos_skill = mob.HumanoidRootPart.CFrame
									_G.allowCombat = true
									click()
									autoskill()
									handleOpeMethod()
									return
								end
							end
						end
					end
					if not foundMob then
						tp(CFrame.new(-7, 135, -3859))
					end
				end
			end)
			return
		end

		if isFeatureEnabledInCurrentSea("autoIceKing") then
			pcall(function()
				if _G.iceCrystalCount == nil then
					_G.iceCrystalCount = 0
				end
				local iceKing = _G.iceKingBoss
				if iceKing and iceKing.Parent and iceKing.Humanoid.Health > 0 then
					usetool()
					buso()
					ken()

					local hrp = iceKing.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = iceKing.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				elseif not iceKing and _G.iceCrystalCount < 1 then
					removeFarmFix()
					local foundMob = false
					for _, folder in pairs(Workspace.Monster:GetChildren()) do
						if folder:IsA("Folder") then
							for _, mob in pairs(folder:GetChildren()) do
								if
									mob:FindFirstChild("Humanoid")
									and mob.Humanoid.Health > 0
									and string.find(mob.Name, "Azlan")
								then
									foundMob = true
									usetool()
									buso()
									ken()

									local hrp2 = mob.HumanoidRootPart
									if hrp2 then
										getDownwardCFrame(hrp2.CFrame)
										local height = GetSetting("distance") or 8
										local targetCF =
											CFrame.new(hrp2.Position + Vector3.new(0, height, 0), hrp2.Position)
										updateFarmFix(targetCF, hrp2)
										if not _G.farmFixThread then
											applyFarmFix(targetCF, hrp2)
										end
									end

									_G.pos_skill = mob.HumanoidRootPart.CFrame
									_G.allowCombat = true
									click()
									autoskill()
									handleOpeMethod()
									return
								end
							end
						end
					end
					if not foundMob then
						tp(CFrame.new(785, 53, -4444))
					end
				end
			end)
			return
		end

		if isFeatureEnabledInCurrentSea("autoSecondSea") then
			local level = LocalPlayer.PlayerStats:FindFirstChild("lvl")
			local playerLevel = level and level.Value or 0

			if playerLevel >= 2250 and _G.secondSeaProgression ~= "Yes" then
				saveAndApply("auto_farm", false)
				saveAndApply("farmmaterial", false)
				saveAndApply("allboss", false)
				saveAndApply("easybounty", false)
				saveAndApply("autoKillMobs", false)
				saveAndApply("autoFarmBoss", false)

				pcall(function()
					if _G.secondSeaHasMap then
						return
					end

					if Workspace.Monster:FindFirstChild("Boss") then
						for _, mob in pairs(Workspace.Monster.Boss:GetChildren()) do
							if
								mob:FindFirstChild("Humanoid")
								and mob.Humanoid.Health > 0
								and string.find(mob.Name, "Seasoned Fishman")
							then
								usetool()
								buso()
								ken()
								local hrp = mob.HumanoidRootPart
								getDownwardCFrame(hrp.CFrame)
								local height = GetSetting("distance") or 8
								local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
								updateFarmFix(targetCF, hrp)
								if not _G.farmFixThread then
									applyFarmFix(targetCF, hrp)
								end
								_G.pos_skill = hrp.CFrame
								_G.allowCombat = true
								click()
								autoskill()
								handleOpeMethod()
								return
							end
						end
					end
					tp(CFrame.new(-1801, 40, 6451))
				end)
			end
			return
		end

		if isFeatureEnabledInCurrentSea("autoThirdSea") then
			local thirdSeaState = _G.thirdSeaState
			-- The summon worker never assigned farming_kraken itself.  Watch for the
			-- boss while it is summoning too, then promote the state only after it
			-- actually appears in Workspace.
			if thirdSeaState == "farming_kraken" or thirdSeaState == "summon_kraken" then
				_G.thirdSeaKrakenBoss = nil
				_G.thirdSeaKrakenSpawned = false

				if Workspace.Monster:FindFirstChild("Boss") then
					for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
						if (string.find(child.Name, "Kraken") or string.find(child.Name, "Tentacle")) then
							if child:FindFirstChild("Humanoid") and child.Humanoid.Health > 0 then
								_G.thirdSeaKrakenBoss = child
								_G.thirdSeaKrakenSpawned = true
								break
							end
						end
					end
				end
				if not _G.thirdSeaKrakenSpawned and Workspace:FindFirstChild("SeaMonster") then
					for _, child in pairs(Workspace.SeaMonster:GetChildren()) do
						if (string.find(child.Name, "Kraken") or string.find(child.Name, "Tentacle")) then
							if child:FindFirstChild("Humanoid") and child.Humanoid.Health > 0 then
								_G.thirdSeaKrakenBoss = child
								_G.thirdSeaKrakenSpawned = true
								break
							end
						end
					end
				end

				if _G.thirdSeaKrakenSpawned and _G.thirdSeaKrakenBoss then
					_G.thirdSeaState = "farming_kraken"
					_G.currentEventName = "Kraken (Third Sea)"
					_G.currentEventHealth = _G.thirdSeaKrakenBoss.Humanoid.Health
					_G.currentEventMaxHealth = _G.thirdSeaKrakenBoss.Humanoid.MaxHealth
					_G.seaEventActive = true

					_G.krakenStatus = updatePosition(_G.thirdSeaKrakenBoss)
					if _G.krakenStatus == "ancorado" then
						usetool()
						buso()
						ken()
						hao()
						click()
						autoskill()
						handleOpeMethod()
					end
				elseif thirdSeaState == "farming_kraken" then
					_G.seaEventActive = false
					_G.currentEventName = "None"
					_G.currentEventHealth = 0
					_G.currentEventMaxHealth = 0
					stopSeaEventBypass()
					if _G.hasThirdSea() then
						_G.thirdSeaState = "finished"
					else
						_G.thirdSeaState = "summon_kraken"
					end
				else
					-- Still at the summoning NPC.  A prior material-farm lock must not
					-- drag the character away before the boss appears.
					if _G.seaEventActive then
						_G.seaEventActive = false
						_G.currentEventName = "None"
						_G.currentEventHealth = 0
						_G.currentEventMaxHealth = 0
						stopSeaEventBypass()
					end
					if _G.farmFixThread or _G.farmFixBodyPos then
						removeFarmFix()
					end
				end
				return
			end

			-- The standalone Third Sea progression worker owns material/travel
			-- movement.  Do not let the generic raid fallback tear its lock down
			-- every Stepped event; clear it only once that worker has left material
			-- farming.
			if thirdSeaState ~= "farm_materials" and (_G.farmFixThread or _G.farmFixBodyPos) then
				removeFarmFix()
			end
			return
		end

		-- Normal boss/progression branches above retain their existing priority.
		-- Re-read the setting in case one of those branches yielded this frame.
		dailyQuest = _G._GenesisGetDailyQuestPriorityCandidate()
		if dailyQuest then
			_G.allowCombat = false
			if dailyQuest == true then
				_G._GenesisSetPriorityOwner("daily_quest_handoff", "settling_quest_state")
				if _G.farmFixThread or _G.farmFixBodyPos then
					removeFarmFix()
				end
				if type(_G._stopDailyQuestHover) == "function" then
					_G._stopDailyQuestHover()
				end
				return
			end
			if _G._GenesisPriorityOwner ~= "daily_quest" and (_G.farmFixThread or _G.farmFixBodyPos) then
				removeFarmFix()
			end
			_G._GenesisSetPriorityOwner("daily_quest", dailyQuest.quest)
			_G._GenesisRunDailyQuestCombat(dailyQuest)
			return
		end

		if GetSetting("auto_farm") and not _G.raidBossTarget and not _G.seaEventActive and not _G.storingFruit then
			pcall(function()
				local now = tick()
				local expectedName = _G.NameMob and "Lv. " .. _G.NameMob .. "]"

				if now - lastFarmUpdate > 0.01 or not isValidFarmMob(currentFarmTarget, expectedName) then
					lastFarmUpdate = now
					currentFarmTarget, targetDist = findFarmMob(expectedName, nil)
				end

				if currentFarmTarget then
					isFarmingMob = true
					c_lv()
					usetool()
					buso()
					ken()

					local hrp = currentFarmTarget.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = currentFarmTarget.HumanoidRootPart.CFrame
					currentFarmTarget.Humanoid.WalkSpeed = 300
					click()
					autoskill()
					handleOpeMethod()
				else
					isFarmingMob = false
					currentFarmTarget = nil
					removeFarmFix()
					tp(CFrame.new(_G.MX, _G.MY, _G.MZ))
				end
			end)
			return
		end

		if
			isFeatureEnabledInCurrentSea("farmmaterial")
			and not GetSetting("auto_farm")
			and not _G.raidBossTarget
			and not _G.seaEventActive
			and not _G.storingFruit
		then
			pcall(function()
				if not material() then
					return
				end
				local now = tick()
				if now - lastFarmUpdate > 0.01 or not isValidFarmMob(currentFarmTarget, nil) then
					lastFarmUpdate = now
					currentFarmTarget, targetDist = findFarmMob(nil, _G.mob)
				end

				if currentFarmTarget then
					isFarmingMob = true
					usetool()
					buso()
					ken()

					local hrp = currentFarmTarget.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = currentFarmTarget.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
				else
					isFarmingMob = false
					currentFarmTarget = nil
					removeFarmFix()
					tp(CFrame.new(_G.MX, _G.MY, _G.MZ))
				end
			end)
			return
		end

		if GetSetting("allboss") then
			-- This branch owns the frame while enabled.  Without an early return it
			-- falls through to the generic cleanup below, which immediately removes
			-- the downward-facing farm lock that was just installed.
			isFarmingMob = false
			pcall(function()
				local now = tick()
				local targetName = currentFarmTarget and currentFarmTarget.Name:lower() or ""
				local targetHumanoid = currentFarmTarget and currentFarmTarget:FindFirstChild("Humanoid")
				if
					not isValidFarmMob(currentFarmTarget, nil)
					or not (
						targetName:find("boss")
						or targetName:find("raid boss")
						or (targetHumanoid and targetHumanoid.MaxHealth > 100000)
					)
				then
					if now - lastFarmUpdate <= 0.1 then
						currentFarmTarget = nil
						return
					end
					lastFarmUpdate = now
					currentFarmTarget = nil
					for _, folder in pairs(Workspace.Monster:GetChildren()) do
						if folder:IsA("Folder") then
							for _, mob in pairs(folder:GetChildren()) do
								local humanoid = mob:FindFirstChild("Humanoid")
								local mobName = mob.Name:lower()
								if
									humanoid
									and humanoid.Health > 0
									and mob:FindFirstChild("HumanoidRootPart")
									and (
										mobName:find("boss")
										or mobName:find("raid boss")
										or humanoid.MaxHealth > 100000
									)
								then
									currentFarmTarget = mob
									break
								end
							end
						end
						if currentFarmTarget then
							break
						end
					end
				end

				if currentFarmTarget then
					isFarmingMob = true
					usetool()
					buso()
					ken()

					local hrp = currentFarmTarget:FindFirstChild("HumanoidRootPart")
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
						_G.pos_skill = hrp.CFrame
						_G.allowCombat = true
						click()
						autoskill()
						handleOpeMethod()
					end
				end
			end)
			if not isFarmingMob then
				removeFarmFix()
			end
			return
		end

		if GetSetting("easybounty") then
			pcall(function()
				loadBossesForCurrentSea()
				local bosses = _G.table_bosses
				if #bosses == 0 then
					return
				end

				local allKilled = true
				for i = 1, #bosses do
					if not _G.bossesKilled[i] then
						allKilled = false
						break
					end
				end
				if allKilled then
					_G.bossesKilled = {}
					_G.currentBossIndex = 1
				end

				local targetBoss = nil
				local targetIndex = nil

				for i = _G.currentBossIndex, #bosses do
					if not _G.bossesKilled[i] then
						local bossFound = false
						local EditNameMob = "Lv. " .. bosses[i].level .. "]"

						for _, folder in pairs(Workspace.Monster:GetChildren()) do
							if folder:IsA("Folder") then
								for _, mob in pairs(folder:GetChildren()) do
									if
										string.find(mob.Name, EditNameMob)
										and mob:FindFirstChild("Humanoid")
										and mob.Humanoid.Health > 0
									then
										targetBoss = mob
										targetIndex = i
										bossFound = true
										break
									end
								end
							end
							if bossFound then
								break
							end
						end

						if not bossFound and not _G.bossesKilled[i] then
							tp(bosses[i].cframe)
							task.wait(0.5)
							for _, folder in pairs(Workspace.Monster:GetChildren()) do
								if folder:IsA("Folder") then
									for _, mob in pairs(folder:GetChildren()) do
										if
											string.find(mob.Name, EditNameMob)
											and mob:FindFirstChild("Humanoid")
											and mob.Humanoid.Health > 0
										then
											targetBoss = mob
											targetIndex = i
											bossFound = true
											break
										end
									end
								end
								if bossFound then
									break
								end
							end
							if not bossFound then
								_G.bossesKilled[i] = true
								_G.currentBossIndex = i + 1
							end
						end
						if bossFound then
							break
						end
					end
				end

				if targetBoss and targetIndex then
					usetool()
					buso()
					ken()

					local hrp = targetBoss.HumanoidRootPart
					if hrp then
						getDownwardCFrame(hrp.CFrame)
						local height = GetSetting("distance") or 8
						local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
						updateFarmFix(targetCF, hrp)
						if not _G.farmFixThread then
							applyFarmFix(targetCF, hrp)
						end
					end

					_G.pos_skill = targetBoss.HumanoidRootPart.CFrame
					_G.allowCombat = true
					click()
					autoskill()
					handleOpeMethod()
					if targetBoss.Humanoid.Health <= 0 then
						_G.bossesKilled[targetIndex] = true
						_G.currentBossIndex = targetIndex + 1
						task.wait(1)
					end
				else
					_G.bossesKilled = {}
					_G.currentBossIndex = 1
					removeFarmFix()
				end
			end)
			return
		end

		if GetSetting("autoKillMobs") then
			local found = false
			pcall(function()
				for _, folder in pairs(Workspace.Monster:GetChildren()) do
					if folder:IsA("Folder") then
						for _, mob in pairs(folder:GetChildren()) do
							if
								mob:FindFirstChild("Humanoid")
								and mob.Humanoid.Health > 0
								and mob:FindFirstChild("HumanoidRootPart")
							then
								if distance(mob.HumanoidRootPart.Position) < (GetSetting("distancemob") or 100) then
									found = true
									usetool()
									buso()
									ken()

									local hrp = mob.HumanoidRootPart
									if hrp then
										getDownwardCFrame(hrp.CFrame)
										local height = GetSetting("distance") or 8
										local targetCF =
											CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
										updateFarmFix(targetCF, hrp)
										if not _G.farmFixThread then
											applyFarmFix(targetCF, hrp)
										end
									end

									_G.pos_skill = mob.HumanoidRootPart.CFrame
									_G.allowCombat = true
									click()
									autoskill()
									handleOpeMethod()
									return
								end
							end
						end
					end
				end
			end)
			if not found then
				removeFarmFix()
			end
			return
		end

		-- No farm branch consumed this frame → ensure cleanup.
		if not _G.seaEventActive and not _G.isLootingChests then
			if _G.farmFixThread or isFarmingMob then
				removeFarmFix()
				isFarmingMob = false
				currentFarmTarget = nil
			end
		end
	end

	trackGenesisConnection(RunService.Stepped:Connect(function()
		if not LocalPlayer:FindFirstChild("PlayerStats") or _G._GenesisAutomationStepBusy then
			return
		end
		_G._GenesisAutomationStepBusy = true
		local ok, err = pcall(_G._GenesisRunAutomationStep)
		_G._GenesisAutomationStepBusy = false
		if not ok then
			warn("[GENESIS HUB] Automation step error: " .. tostring(err))
		end
	end))

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if not LocalPlayer:FindFirstChild("PlayerStats") then return end
				if GetSetting("auto_farm") and not _G.seaEventActive then
					c_lv()
					if _G.NameQuest and _G.NameQuest ~= "" then
						ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", _G.NameQuest)
					end
				end
				if isFeatureEnabledInCurrentSea("farmmaterial")
					and GetSetting("getQuestMaterial") and not _G.seaEventActive then
					local questName = getMaterialQuest()
					if questName and questName ~= "" then
						ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", questName)
					end
				end
				if isFeatureEnabledInCurrentSea("autoFarmBoss")
					and GetSetting("getQuestMaterial") and not _G.seaEventActive then
					local bossName = getCurrentSeaSelectedBoss()
					if bossName then
						local questName = getBossQuest(bossName)
						if questName then
							ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", questName)
						end
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not GetSetting("autoRaceV3") then
					return
				end
				-- Auto Dungeon has its own bounded R attempt and activation tracking.
				-- Let that path make the decision while a dungeon is active so the two
				-- workers cannot send the same key independently.
				if GetSetting("auto_dungeon_v2") and _G.Raid and _G.Raid.inraid then
					return
				end

				local character = LocalPlayer.Character
				if not character then
					return
				end

				local humanoid = character:FindFirstChild("Humanoid")
				if not humanoid then
					return
				end

				local maxHealth = humanoid.MaxHealth
				local currentHealth = humanoid.Health
				if maxHealth <= 0 or currentHealth <= 0 then
					return
				end
				local healthPercent = (currentHealth / maxHealth) * 100

				local triggerPercent = tonumber(GetSetting("raceV3HealthPercent")) or 30

				if healthPercent <= triggerPercent and not UserInputService:GetFocusedTextBox() then
					local now = tick()
					local dungeonRace = _G.Raid and _G.Raid.raceAbility
					if dungeonRace and now < (dungeonRace.cooldownUntil or 0) then
						return
					end
					if now - (_G.lastRaceAbilityAttempt or 0) >= 1.5 then
						_G.lastRaceAbilityAttempt = now
						VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
						task.wait(0.05)
						VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoSecondSea") then
					return
				end
				if _G._GenesisDailyReturnRequested then return end

				local level = LocalPlayer.PlayerStats:FindFirstChild("lvl")
				local playerLevel = level and level.Value or 0
				if playerLevel < 2250 then
					return
				end

				local secondSeaProgression = LocalPlayer.PlayerStats:FindFirstChild("SecondSeaProgression")
				local progression = secondSeaProgression and secondSeaProgression.Value or "No"

				local materialValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
				local hasMap = false
				if materialValue then
					local success, data = pcall(function()
						return HttpService:JSONDecode(materialValue.Value)
					end)
					if success and data and data["Map"] and data["Map"] >= 1 then
						hasMap = true
					end
				end

				_G.secondSeaHasMap = hasMap
				_G.secondSeaProgression = progression

				if progression == "No" then
					local currentQuest = LocalPlayer:FindFirstChild("CurrentQuest")
					local questIsMap = currentQuest and currentQuest.Value == "Second Sea Map"

					if not questIsMap and not hasMap or hasMap then
						tp(CFrame.new(2587, 95, -1879))
						task.wait(0.5)

						local allNpc = Workspace:FindFirstChild("AllNPC")
						local npcFolder = ReplicatedStorage:FindFirstChild("NPC")
						local traveler = (allNpc and allNpc:FindFirstChild("Traveler"))
							or (npcFolder and npcFolder:FindFirstChild("Traveler"))
						if traveler then
							ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(traveler)
						end
						task.wait(0.5)

						pcall(function()
							local acceptBtn = LocalPlayer.PlayerGui.Traveler.Dialogue.Accept
							_G._GenesisDispatchGuiButton(acceptBtn)
						end)
					end
				elseif progression == "Yes" then
					tp(CFrame.new(-2162, 17, -3988))
					task.wait(0.5)

					local allNpc = Workspace:FindFirstChild("AllNPC")
					local npcFolder = ReplicatedStorage:FindFirstChild("NPC")
					local elitePirate = (allNpc and allNpc:FindFirstChild("Elite Pirate"))
						or (npcFolder and npcFolder:FindFirstChild("Elite Pirate"))
					if elitePirate then
						ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(elitePirate)
					end
					task.wait(0.5)

					pcall(function()
						local acceptBtn = LocalPlayer.PlayerGui["Elite Pirate"].Dialogue.Accept
						_G._GenesisDispatchGuiButton(acceptBtn)
					end)
				end
			end)
		end
	end)

	_G._GenesisKaidoAcquisition = {
		active = false,
		phase = "idle",
		root = nil,
		hold = nil,
		moved = false,
		nextRequestAt = 0,
		lastRequestAt = 0,
		lastResponse = nil,
		acceptSentAt = 0,
		acceptAttempts = 0,
		continueSentAt = 0,
		lastClickResult = nil,
	}

	_G._GenesisClearKaidoSwimMovers = function(root)
		for _, mover in ipairs(root and root:GetChildren() or {}) do
			if (mover.Name == "Swim" and mover:IsA("AlignPosition"))
				or (mover.Name == "SwimGyro" and mover:IsA("BodyGyro")) then
				mover:Destroy()
			end
		end
	end

	_G._stopKaidoAcquisition = function(reason)
		local state = _G._GenesisKaidoAcquisition
		if not state then
			return
		end
		if state.hold then
			pcall(function()
				state.hold:Destroy()
			end)
			state.hold = nil
		end
		local root = state.root
		if state.moved and root and root.Parent then
			_G._GenesisClearKaidoSwimMovers(root)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		state.active = false
		state.phase = reason or "idle"
		state.root = nil
		state.moved = false
		state.nextRequestAt = 0
		state.lastRequestAt = 0
		state.acceptSentAt = 0
		state.acceptAttempts = 0
		state.continueSentAt = 0
		state.lastClickResult = nil
		_G.NPCTalk = false
	end

	-- SummonDragon's legacy GUI does not complete its server-side path when its
	-- MouseButton1Click signal is fired directly. On this game's mobile UI the
	-- reliable path is the same bounded physical click used by the original
	-- client: briefly expand the real Accept button over a known screen point,
	-- send one pointer press/release, then restore it if the GUI did not advance.
	-- This helper never moves the character and is called only after the central
	-- resolver has already granted the non-priority Kaido acquisition leaf.
	_G._GenesisKaidoPhysicalClick = function(button)
		local camera = Workspace.CurrentCamera
		if not camera or camera.ViewportSize.X <= 0 or camera.ViewportSize.Y <= 0 then
			return false, "camera_unavailable"
		end

		local originalSize = nil
		local originalPosition = nil
		if button then
			if not _G._GenesisIsVisibleGuiButton(button) then
				return false, "button_not_visible"
			end
			originalSize = button.Size
			originalPosition = button.Position
			button.Size = UDim2.new(10, 0, 10, 0)
			button.Position = UDim2.new(-1.9, 0, -5.5, 0)
			-- Absolute bounds and GUI hit-testing do not adopt the temporary
			-- geometry until a render boundary. Clicking in this same frame can
			-- therefore miss Accept even though the properties already changed.
			RunService.RenderStepped:Wait()
			RunService.RenderStepped:Wait()
		end

		local screenSize = camera.ViewportSize
		local clickX = math.max(1, screenSize.X - 20)
		local clickY = math.max(1, screenSize.Y / 15)
		local clickOk, clickError = pcall(function()
			VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
		end)

		if button and originalSize and originalPosition then
			task.delay(0.35, function()
				-- Restore even after Accept becomes hidden so a later summon cycle
				-- cannot inherit the temporary full-dialogue hitbox.
				if button and button.Parent then
					button.Size = originalSize
					button.Position = originalPosition
				end
			end)
		end
		return clickOk, clickOk and "physical_click" or tostring(clickError)
	end

	_G._GenesisCanRunKaidoAcquisition = function()
		if game.PlaceId ~= 6381829480 then
			return false, "wrong_sea"
		end
		if not GetSetting("autoFarmKaido") then
			return false, "disabled"
		end
		if _G._GenesisFindLiveKaido() then
			return false, "boss_spawned"
		end
		if _G._GenesisGetDragonOrbCount() < 1 then
			return false, "orb_missing"
		end
		-- The summon mechanism never preempts anything. It can act only after the
		-- central resolver independently reaches this exact low-priority leaf.
		if _G._GenesisPriorityOwner ~= "other_combat"
			or _G._GenesisPriorityDetail ~= "kaido_acquisition" then
			return false, "yielding_to_" .. tostring(_G._GenesisPriorityOwner)
		end
		if fishingOwnsWeaponSlot()
			or _G.storingFruit
			or _G.isLootingChests
			or _G.collectingPearls
			or _G.seaEventActive
			or _G.conquestActive
			or _G.isProgressingBusoV2
			or _G.isProgressingObservationV2
			or _G.thirdSeaProgressionActive
			or (_G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation())
		then
			return false, "higher_priority_active"
		end
		return true
	end

	spawn(function()
		while task.wait(0.1) do
			pcall(function()
				local state = _G._GenesisKaidoAcquisition
				local inKaidoSea = game.PlaceId == 6381829480
				local dragon = inKaidoSea and GetSetting("autoFarmKaido") and _G._GenesisFindLiveKaido() or nil
				_G.kaidoDragon = dragon
				_G.kaidoHasOrb = inKaidoSea and _G._GenesisGetDragonOrbCount() >= 1 or false

				local canRun, reason = _G._GenesisCanRunKaidoAcquisition()
				if not canRun then
					if state.active or state.hold then
						_G._stopKaidoAcquisition(reason)
					elseif not GetSetting("autoFarmKaido") then
						state.phase = "disabled"
					elseif reason == "wrong_sea" then
						state.phase = "wrong_sea"
					end
					return
				end

				local allNpc = Workspace:FindFirstChild("AllNPC")
				local summonNpc = allNpc and allNpc:FindFirstChild("SummonDragon")
				local character = LocalPlayer.Character
				local root = GetRoot(character)
				if not summonNpc or not summonNpc:IsA("BasePart") or not root then
					_G._stopKaidoAcquisition("altar_unavailable")
					return
				end

				if state.root ~= root then
					_G._stopKaidoAcquisition("character_changed")
					state.root = root
				end
				local targetCF = summonNpc.CFrame * CFrame.new(0, 3, 0)
				_G._GenesisClearKaidoSwimMovers(root)
				if not state.hold or state.hold.Parent ~= root then
					local hold = Instance.new("BodyPosition")
					hold.Name = "GenesisKaidoAcquisitionHold"
					hold.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
					hold.D = 100000
					hold.P = 1000000
					hold.Position = targetCF.Position
					hold.Parent = root
					state.hold = hold
					state.active = true
					state.moved = true
					state.phase = "approaching_altar"
					state.nextRequestAt = os.clock() + 0.4
				end
				state.hold.Position = targetCF.Position
				if (root.Position - targetCF.Position).Magnitude > 8 then
					root.CFrame = targetCF
				end
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero

				local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
				local summonGui = playerGui and playerGui:FindFirstChild("SummonDragon")
				local dialogue = summonGui and summonGui:FindFirstChild("Dialogue")
				local acceptBtn = dialogue and dialogue:FindFirstChild("Accept")
				local continueLabel = dialogue and dialogue:FindFirstChild("ContinueLabel")
				local acceptVisible = summonGui and summonGui.Enabled
					and dialogue and dialogue.Visible
					and acceptBtn and acceptBtn.Visible
					and acceptBtn.AbsoluteSize.X > 0 and acceptBtn.AbsoluteSize.Y > 0
				local continueVisible = summonGui and summonGui.Enabled
					and dialogue and dialogue.Visible
					and continueLabel and continueLabel.Visible
				local now = os.clock()

				if acceptVisible then
					if state.acceptSentAt == 0 or now - state.acceptSentAt >= 1.5 then
						if state.acceptAttempts >= 3 then
							if now < state.nextRequestAt then
								state.phase = "accept_unresponsive_cooldown"
								return
							end
							state.acceptAttempts = 0
						end
						_G.NPCTalk = true
						state.phase = "accepting_summon"
						state.acceptSentAt = now
						state.acceptAttempts = state.acceptAttempts + 1
						state.continueSentAt = 0
						local clickOk, clickResult = _G._GenesisKaidoPhysicalClick(acceptBtn)
						state.lastClickResult = clickResult
						if not clickOk then
							state.acceptSentAt = 0
						end
					else
						state.phase = "waiting_for_accept_transition"
					end
					return
				end

				-- After Accept, this GUI switches to a status page and waits for a
				-- second ordinary input before its server DialogueEvent consumes the
				-- orb and creates Dragon. A direct signal dispatch never completes that
				-- server-side path, so make one bounded physical continuation click.
				if continueVisible then
					local acceptSettled = state.acceptSentAt == 0 or now - state.acceptSentAt >= 0.35
					if state.continueSentAt == 0 and acceptSettled then
						_G.NPCTalk = true
						state.phase = state.acceptSentAt > 0 and "continuing_summon" or "closing_stale_status"
						state.continueSentAt = now
						state.nextRequestAt = now + 8
						local clickOk, clickResult = _G._GenesisKaidoPhysicalClick(nil)
						state.lastClickResult = clickResult
						if not clickOk then
							state.continueSentAt = 0
						end
					else
						state.phase = "waiting_for_continue_transition"
					end
					return
				end

				if summonGui and summonGui.Enabled and dialogue and dialogue.Visible then
					state.phase = "waiting_for_dialogue_controls"
					return
				end

				if state.continueSentAt > 0 then
					if now - state.continueSentAt < 8 then
						state.phase = "waiting_for_dragon"
						return
					end
					-- The server did not consume the orb or replicate Dragon. Reset this
					-- completed attempt and permit one clean dialogue cycle after cooldown.
					state.acceptSentAt = 0
					state.acceptAttempts = 0
					state.continueSentAt = 0
					state.nextRequestAt = now + 2
				end

				if now < state.nextRequestAt then
					return
				end

				state.phase = "requesting_dialogue"
				state.lastRequestAt = now
				_G.NPCTalk = true
				local remote = ReplicatedStorage.Chest.Remotes.Functions.CheckQuest
				local success, response = pcall(function()
					return remote:InvokeServer(summonNpc)
				end)
				state.lastResponse = success and tostring(response) or "error: " .. tostring(response)
				if success and response == "Cancel NPCTalk" then
					-- A stale/duplicate request toggles the legacy dialogue back off. Let
					-- that cancellation settle, then make exactly one fresh request.
					_G.NPCTalk = false
					state.phase = "dialogue_cancelled_retrying"
					state.nextRequestAt = os.clock() + 1.5
				else
					state.phase = "waiting_for_dialogue"
					state.acceptSentAt = 0
					state.acceptAttempts = 0
					state.continueSentAt = 0
					state.nextRequestAt = os.clock() + 8
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoDarkBeard") then
					_G.darkBeardBoss = nil
					_G.darkBeardTotemCount = 0
					return
				end

				local materialValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
				local totemCount = 0

				if materialValue then
					local success, data = pcall(function()
						return HttpService:JSONDecode(materialValue.Value)
					end)
					if success and data and data["Dark Beard's Totem"] then
						totemCount = data["Dark Beard's Totem"]
					end
				end

				_G.darkBeardTotemCount = totemCount

				local darkBeard = nil
				if Workspace.Monster:FindFirstChild("Boss") then
					for _, mob in pairs(Workspace.Monster.Boss:GetChildren()) do
						if
							mob:FindFirstChild("Humanoid")
							and mob.Humanoid.Health > 0
							and string.find(mob.Name, "Dark Beard")
						then
							darkBeard = mob
							break
						end
					end
				end
				_G.darkBeardBoss = darkBeard

				if totemCount >= 1 and not darkBeard then
					tp(CFrame.new(-9486, 77, -4761))
					task.wait(0.3)
					ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("QuestSpawnBoss", {
						SuccessQuest = "Quest Accepted.",
						BossName = "Dark Beard [Lv. 3475]",
						LevelNeed = 3475,
						QuestName = "Kill 1 Dark Beard",
						MaterialNeed = "Dark Beard's Totem",
						AI_Name = "Dark Beard",
						LevelLow = "You must be Level 3,475 to accept this quest.",
					})
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoCrimsonDemon") then
					_G.crimsonBoss = nil
					_G.crimsonCrystalCount = 0
					return
				end

				local materialValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
				local crystalCount = 0

				if materialValue then
					local success, data = pcall(function()
						return HttpService:JSONDecode(materialValue.Value)
					end)
					if success and data and data["Magma Crystal"] then
						crystalCount = data["Magma Crystal"]
					end
				end

				_G.crimsonCrystalCount = crystalCount

				local crimson = nil
				if Workspace.Monster:FindFirstChild("Boss") then
					for _, mob in pairs(Workspace.Monster.Boss:GetChildren()) do
						if
							mob:FindFirstChild("Humanoid")
							and mob.Humanoid.Health > 0
							and string.find(mob.Name, "Crimson Demon")
						then
							crimson = mob
							break
						end
					end
				end
				_G.crimsonBoss = crimson

				if crystalCount >= 1 and not crimson then
					tp(CFrame.new(-7, 135, -3859))
					task.wait(0.3)
					ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("QuestSpawnBoss", {
						SuccessQuest = "Quest Accepted.",
						BossName = "The Crimson Demon [Lv. 3375]",
						LevelNeed = 3375,
						QuestName = "Kill 1 The Crimson Demon",
						MaterialNeed = "Magma Crystal",
						AI_Name = "The Crimson Demon",
						LevelLow = "You must be Level 3,375 to accept this quest.",
					})
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoIceKing") then
					_G.iceKingBoss = nil
					_G.iceCrystalCount = 0
					return
				end

				local materialValue = LocalPlayer.PlayerStats:FindFirstChild("Material")
				local crystalCount = 0

				if materialValue then
					local success, data = pcall(function()
						return HttpService:JSONDecode(materialValue.Value)
					end)
					if success and data and data["Ice Crystal"] then
						crystalCount = data["Ice Crystal"]
					end
				end

				_G.iceCrystalCount = crystalCount

				local iceKing = nil
				if Workspace.Monster:FindFirstChild("Boss") then
					for _, mob in pairs(Workspace.Monster.Boss:GetChildren()) do
						if
							mob:FindFirstChild("Humanoid")
							and mob.Humanoid.Health > 0
							and string.find(mob.Name, "Ice King")
						then
							iceKing = mob
							break
						end
					end
				end
				_G.iceKingBoss = iceKing

				if crystalCount >= 1 and not iceKing then
					tp(CFrame.new(-846, 97, -2929))
					task.wait(0.3)
					ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("QuestSpawnBoss", {
						SuccessQuest = "Quest Accepted.",
						BossName = "The Ice King [Lv. 3350]",
						LevelNeed = 3350,
						QuestName = "Kill 1 The Ice King",
						MaterialNeed = "Ice Crystal",
						AI_Name = "The Ice King",
						LevelLow = "You must be Level 3,350 to accept this quest.",
					})
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.25) do
			pcall(function()
				if not GetSetting("autoStoreFruits") or _G._GenesisDailyReturnRequested then
					return
				end

				local fruitStoreValue = LocalPlayer.PlayerStats:FindFirstChild("FruitStore")
				local fruitStorage = LocalPlayer.PlayerStats:FindFirstChild("FruitStorage")
				local maxPerFruit = fruitStorage and fruitStorage.Value or 1
				local storedFruits = {}

				if fruitStoreValue then
					local success, data = pcall(function()
						return HttpService:JSONDecode(fruitStoreValue.Value)
					end)
					if success and data then
						storedFruits = data
					end
				end

				for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
					if _G._GenesisDailyReturnRequested then break end
					if tool:IsA("Tool") and tool.Name:sub(-5) == "Fruit" then
						local currentCount = storedFruits[tool.Name] or 0
						if currentCount < maxPerFruit then
							local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
							if humanoid then
								if _G.isFishing or _G.fishingToolCaptured then
									pcall(stopFishing)
								end
								local previousTool = getEquippedTool()
								local fruitName = tool.Name

								_G.storingFruit = true
								pcall(function()
								task.wait(0.01)
								if _G._GenesisDailyReturnRequested then return end

								humanoid:EquipTool(tool)
								task.wait(0.01)

								local equippedFruit = nil
								local startEquip = tick()
								while tick() - startEquip < 2 do
									if _G._GenesisDailyReturnRequested then break end
									local equipped = LocalPlayer.Character
										and LocalPlayer.Character:FindFirstChild(fruitName)
									if equipped then
										equippedFruit = equipped
										break
									end
									task.wait(0.01)
								end

								-- Equipping only puts the fruit in the character's hand. Its
								-- normal M1 activation is what opens EatFruitBecky.Dialogue;
								-- the dedicated worker below then presses Collect.
								if equippedFruit and equippedFruit.Parent == LocalPlayer.Character
									and not _G._GenesisDailyReturnRequested then
									equippedFruit:Activate()
								end

								local startTime = tick()
								while tick() - startTime < 5 do
									if _G._GenesisDailyReturnRequested then break end
									local currentStore = LocalPlayer.PlayerStats:FindFirstChild("FruitStore")
									if currentStore then
										local success2, data2 = pcall(function()
											return HttpService:JSONDecode(currentStore.Value)
										end)
										if success2 and data2 then
											local newCount = data2[fruitName] or 0
											if newCount > currentCount then
												break
											end
										end
									end
									if
										not LocalPlayer.Backpack:FindFirstChild(fruitName)
										and not (
											LocalPlayer.Character and LocalPlayer.Character:FindFirstChild(fruitName)
										)
									then
										break
									end
									task.wait(0.01)
								end

								end)
								-- Always release the global handoff flag, even if the character or
								-- fruit vanished during the asynchronous store attempt.
								_G.storingFruit = false
								pcall(function()
									if humanoid.Parent then
										humanoid:UnequipTools()
										if previousTool and previousTool.Parent then
											humanoid:EquipTool(previousTool)
										end
									end
								end)
								task.wait(0.05)
							end
						end
					end
				end
			end)
		end
	end)

	spawn(function()
		local lastCollectButton = nil
		local lastCollectAttempt = 0
		while task.wait(0.01) do
			pcall(function()
				if not GetSetting("autoStoreFruits") then
					return
				end
				if not _G.storingFruit then
					return
				end
				local eatFruitGui = LocalPlayer.PlayerGui:FindFirstChild("EatFruitBecky")
				local dialogue = eatFruitGui and eatFruitGui:FindFirstChild("Dialogue")
				local collectBtn = dialogue and dialogue:FindFirstChild("Collect")
				if not _G._GenesisIsVisibleGuiButton(collectBtn) then
					return
				end

				local now = os.clock()
				if collectBtn == lastCollectButton and now - lastCollectAttempt < 0.1 then
					return
				end
				lastCollectButton = collectBtn
				lastCollectAttempt = now

				-- Restore the webhook-only build's known-good Collect interaction.
				-- The button is enlarged only after its exact GUI path and visible
				-- ancestry are validated, then it receives real mouse input. This is
				-- intentionally the sole Collect path; firesignal is not a fallback.
				collectBtn.Size = UDim2.new(10, 0, 10, 0)
				collectBtn.Position = UDim2.new(-1.9, 0, -5.5, 0)
				RunService.RenderStepped:Wait()
				if
					not GetSetting("autoStoreFruits")
					or not _G.storingFruit
					or collectBtn ~= dialogue:FindFirstChild("Collect")
					or not _G._GenesisIsVisibleGuiButton(collectBtn)
				then
					return
				end

				local camera = Workspace.CurrentCamera
				if not camera then
					return
				end
				local screenSize = camera.ViewportSize
				local clickX = math.max(0, screenSize.X - 20)
				local clickY = math.max(0, screenSize.Y / 15)
				VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 0)
				task.wait(0.01)
				VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 0)
			end)
		end
	end)

	spawn(function()
		while task.wait(0.01) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoThirdSea") then
					return
				end

				local state = _G.thirdSeaState
				local guiName
				if state == "squid_mission" or state == "finished" then
					guiName = "The Squid"
				elseif state == "summon_kraken" then
					guiName = "Summon Tentacle"
				else
					return
				end

				local gui = LocalPlayer.PlayerGui:FindFirstChild(guiName)
				local dialogue = gui and gui:FindFirstChild("Dialogue")
				local accept = dialogue and dialogue:FindFirstChild("Accept")
				_G._GenesisDispatchGuiButton(accept)
			end)
		end
	end)

	spawn(function()
		local lastDailyQuestClick = 0
		while task.wait(0.05) do
			pcall(function()
				if not dailyQuestCanAct or not getDailyQuestPending
					or not dailyQuestCanAct() or _G.dailyQuestState ~= "get_quest"
					or (game.PlaceId == 6381829480 and not _G.dailyQuestCheckQueued)
					or tick() - lastDailyQuestClick < 0.4 then
					return
				end
				local current = getDailyQuestPending()
				if not current then
					return
				end

				local loreQuest = current.npc:sub(1, 5) == "Lore " or current.npc == "Tomb Event Second"
				local gui = LocalPlayer.PlayerGui:FindFirstChild(loreQuest and "LoreGUI" or current.npc)
				local dialogue = gui and gui:FindFirstChild("Dialogue")
				if not dialogue or not dialogue.Visible or not gui.Enabled then
					return
				end

				-- Existing but hidden buttons must not mask the currently active stage.
				local button = nil
				local choices = loreQuest and (current.choice and { "QuestAccept", current.choice }
					or { "QuestAccept", "Quest 1", "Quest 2" }) or { "Accept" }
				for _, buttonName in ipairs(choices) do
					local candidate = dialogue:FindFirstChild(buttonName)
					if _G._GenesisIsVisibleGuiButton(candidate) then
						button = candidate
						break
					end
				end
				if _G._GenesisDispatchGuiButton(button) then
					lastDailyQuestClick = tick()
					if not loreQuest then
						-- These older NPC GUIs also have a server-side Script under Accept.
						-- A client-side firesignal advances the dialogue but does not
						-- replicate that Script's quest-taking action. Use the same
						-- validated Quest remote after the visible Accept was selected.
						local expectedQuest = current.quest
						task.spawn(function()
							task.wait(0.2)
							if dailyQuestCanAct() and _G.dailyQuestState == "get_quest" then
								local activeQuest = LocalPlayer:FindFirstChild("CurrentQuest")
								if not activeQuest or activeQuest.Value ~= expectedQuest then
									pcall(function()
										ReplicatedStorage.Chest.Remotes.Functions.Quest:InvokeServer("take", expectedQuest)
									end)
								end
							end
						end)
					end
				end
			end)
		end
	end)

	spawn(function()
		local lastSeaHop = 0
		local lastCraftAttempt = 0
		local lastMatNotify = 0
		local currentMatTarget = nil
		local lastTreeScan = 0
		local cachedTree = nil

		while task.wait(0.25) do
			pcall(function()
				-- Already in Sea 3 → disable.
				-- Daily sea routing owns cross-sea movement in either direction. Yield
				-- before publishing the progression blocker so outbound travel can reach
				-- The Squid and fishing can resume if that route is later released.
				if _G._GenesisDailyQuestTravelPending then
					_G.thirdSeaProgressionActive = false
					return
				end
				if game.PlaceId == _G.SEA3_ID or game.PlaceId == 15759515082 then
					_G.thirdSeaProgressionActive = false
					if GetSetting("autoThirdSea") then
						saveAndApply("autoThirdSea", false)
						_G.thirdSeaState = "idle"
						SpectrumX:Notify({
							Text = "Already in Third Sea! Auto disabled.",
							Type = "success",
							Duration = 3,
						})
					end
					return
				end

				if not GetSetting("autoThirdSea") then
					_G.thirdSeaProgressionActive = false
					_G.thirdSeaState = _G.thirdSeaState or "idle"
					return
				end

				-- Only run progression in Sea 1 or Sea 2.
				if
					game.PlaceId ~= _G.SEA1_ID
					and game.PlaceId ~= _G.SEA2_ID
					and game.PlaceId ~= 4520749081
					and game.PlaceId ~= 6381829480
				then
					_G.thirdSeaProgressionActive = false
					return
				end
				_G.thirdSeaProgressionActive = true
				if fishingOwnsWeaponSlot() then
					_G._GenesisPrepareCombatFromFishing("third_sea_progression")
					return
				end

				-- A live generic sea event (including either Galleon) has priority.
				-- Pause progression without changing its state; it resumes as soon as
				-- the event dispatcher releases ownership.
				if _G.seaEventActive then
					return
				end

				if _G.hasThirdSea() then
					saveAndApply("autoThirdSea", false)
					_G.thirdSeaState = "idle"
					SpectrumX:Notify({ Text = "Third Sea Unlocked! Teleporting...", Type = "success", Duration = 3 })
					task.wait(1)
					_G.teleportToSea("ThirdSea")
					return
				end

				_G.thirdSeaHasHeart = _G.hasHeartOfSea()

				-- Decide the initial state.
				if not _G.thirdSeaState or _G.thirdSeaState == "idle" then
					if _G.thirdSeaHasHeart then
						_G.thirdSeaState = "squid_mission"
					else
						local missing = _G.getMissingThirdSeaMaterials()
						if #missing == 0 then
							_G.thirdSeaState = "craft"
						else
							-- If only Blood is missing → wait; otherwise farm.
							local onlyBlood = true
							for _, m in ipairs(missing) do
								if m.source ~= "seaking" then
									onlyBlood = false
									break
								end
							end
							if onlyBlood then
								_G.thirdSeaState = "wait_blood"
							else
								_G.thirdSeaState = "farm_materials"
							end
						end
					end
				end

				-- ===== WAIT FOR BLOOD (the user farms it manually) =====
				if _G.thirdSeaState == "wait_blood" then
					local blood = _G.getMaterialCount("Sea King's Blood")
					if blood >= 1 then
						if _G.hasCraftMaterials() then
							_G.thirdSeaState = "craft"
						else
							_G.thirdSeaState = "farm_materials"
						end
						return
					end
					if tick() - lastMatNotify > 15 then
						lastMatNotify = tick()
						SpectrumX:Notify({
							Title = "GENESIS HUB",
							Text = "Waiting for Sea King's Blood (farm it yourself)",
							Type = "genesis",
							Duration = 5,
						})
					end
					-- Stay in Sea 2 when possible, without server hopping.
					if game.PlaceId ~= _G.SEA2_ID and game.PlaceId ~= 6381829480 then
						if tick() - lastSeaHop > 10 then
							lastSeaHop = tick()
							_G.teleportToSea("SecondSea")
						end
					end
					return
				end

				-- ===== FARM MATERIALS (everything except Blood) =====
				if _G.thirdSeaState == "farm_materials" then
					local missing = _G.getMissingThirdSeaMaterials()
					if #missing == 0 then
						_G.thirdSeaState = "craft"
						return
					end

					-- Prioritize material that is NOT Blood.
					local target = nil
					for _, m in ipairs(missing) do
						if m.source ~= "seaking" then
							target = m
							break
						end
					end

					if not target then
						-- Only Blood is missing.
						_G.thirdSeaState = "wait_blood"
						return
					end

					if tick() - lastMatNotify > 12 then
						lastMatNotify = tick()
						SpectrumX:Notify({
							Title = "GENESIS HUB",
							Text = string.format("Farming %s (%d/%d)", target.name, target.have, target.need),
							Type = "genesis",
							Duration = 4,
						})
					end

					-- Change seas if necessary.
					if game.PlaceId ~= target.sea then
						if tick() - lastSeaHop > 10 then
							lastSeaHop = tick()
							local seaName = (target.sea == _G.SEA1_ID or target.sea == 4520749081) and "FirstSea"
								or "SecondSea"
							_G.teleportToSea(seaName)
						end
						return
					end

					-- Tree farm (Log).
					if target.source == "tree" then
						-- Look for any nearby or known tree/tree part.
						-- A full Workspace descendant walk is expensive on a populated
						-- server. Refresh the nearby-tree cache once per second instead
						-- of doing the same scan four times per second.
						local bestTree = cachedTree
						local root = GetRoot(LocalPlayer.Character)
						if root and (not cachedTree or not cachedTree.Parent or tick() - lastTreeScan >= 1) then
							local bestDist = math.huge
							bestTree = nil
							lastTreeScan = tick()
							for _, obj in pairs(Workspace:GetDescendants()) do
								if
									obj:IsA("BasePart")
									and (
										obj.Name:lower():find("tree")
										or obj.Name:lower():find("log")
										or obj.Name:lower():find("wood")
									)
								then
									local d = (obj.Position - root.Position).Magnitude
									if d < bestDist and d < 500 then
										bestDist = d
									bestTree = obj
								end
							end
						end
							cachedTree = bestTree
						end
						if bestTree then
							tp(bestTree.CFrame * CFrame.new(0, 3, 5))
							-- Use the farm-fix system if it exists.
							if applyFarmFix then
								applyFarmFix(bestTree.CFrame * CFrame.new(0, 3, 5))
							end
							click()
							autoskill()
							buso()
							ken()
						else
							-- Approximate spawn fallback.
							if removeFarmFix then
								removeFarmFix()
							end
							tp(CFrame.new(-1422, 52, -856))
						end
						return
					end

					-- Mob farm.
					if target.source == "mob" and target.patterns then
						local found = nil
						local root = GetRoot(LocalPlayer.Character)
						local myPos = root and root.Position or Vector3.new()
						local closestDist = math.huge

						for _, folder in pairs(Workspace.Monster:GetChildren()) do
							if folder:IsA("Folder") then
								for _, mob in pairs(folder:GetChildren()) do
									if
										mob:FindFirstChild("Humanoid")
										and mob.Humanoid.Health > 0
										and mob:FindFirstChild("HumanoidRootPart")
									then
										for _, pat in ipairs(target.patterns) do
											if string.find(mob.Name, pat) then
												local d = (mob.HumanoidRootPart.Position - myPos).Magnitude
												if d < closestDist then
													closestDist = d
													found = mob
												end
												break
											end
										end
									end
								end
							end
						end

						if found then
							local hrp = found.HumanoidRootPart
							local height = GetSetting("distance") or 8
							local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
							if applyFarmFix then
								applyFarmFix(targetCF, hrp)
							else
								tp(targetCF)
							end
							_G.pos_skill = hrp.CFrame
							click()
							autoskill()
							buso()
							ken()
							-- Equip tool.
							local tools = GetSetting("selectedTools")
							if tools and #tools > 0 then
								-- The tooltip already exists in the script.
								pcall(function()
									local tip = tools[1]
									if tip == "Mele" or tip == "Melee" then
										tip = "Combat"
									end
									for _, tool in pairs(LocalPlayer.Backpack:GetChildren()) do
										if tool:IsA("Tool") and (tool.ToolTip == tip or tool.ToolTip == tools[1]) then
											local hum = GetHumanoid(LocalPlayer.Character)
											if hum then
												hum:EquipTool(tool)
											end
											break
										end
									end
								end)
							end
						else
							-- Go to the material spawn.
							if removeFarmFix then
								removeFarmFix()
							end
							if target.spawn then
								tp(target.spawn)
							end
						end
						return
					end

					return
				end

				-- ===== CRAFTING =====
				if _G.thirdSeaState == "craft" then
					if _G.hasHeartOfSea() then
						_G.thirdSeaState = "squid_mission"
						return
					end
					if _G.hasCraftMaterials() then
						if tick() - lastCraftAttempt > 2 then
							lastCraftAttempt = tick()
							_G.craftHeartOfSea()
							task.wait(0.8)
						end
						if _G.hasHeartOfSea() then
							_G.thirdSeaState = "squid_mission"
						end
					else
						-- Something is still missing.
						local missing = _G.getMissingThirdSeaMaterials()
						local onlyBlood = true
						for _, m in ipairs(missing) do
							if m.source ~= "seaking" then
								onlyBlood = false
								break
							end
						end
						_G.thirdSeaState = onlyBlood and "wait_blood" or "farm_materials"
					end
					return
				end

				-- ===== SQUID MISSION =====
				if _G.thirdSeaState == "squid_mission" then
					-- Must be in Sea 2.
					if game.PlaceId ~= _G.SEA2_ID and game.PlaceId ~= 6381829480 then
						if tick() - lastSeaHop > 10 then
							lastSeaHop = tick()
							_G.teleportToSea("SecondSea")
						end
						return
					end

					local squid = Workspace.AllNPC:FindFirstChild("The Squid")
					if squid and squid:IsA("BasePart") then
						local root = GetRoot(LocalPlayer.Character)
						if root then
							root.CFrame = CFrame.new(squid.Position)
						end
					end

					if not _G.thirdSeaSquidTimer or _G.thirdSeaSquidTimer == 0 then
						_G.thirdSeaSquidTimer = tick()
					elseif tick() - _G.thirdSeaSquidTimer >= 2 then
						_G.thirdSeaSquidTimer = 0
						_G.thirdSeaState = "summon_kraken"
					end
					return
				end

				-- ===== SUMMON KRAKEN =====
				if _G.thirdSeaState == "summon_kraken" then
					if game.PlaceId ~= _G.SEA2_ID and game.PlaceId ~= 6381829480 then
						if tick() - lastSeaHop > 10 then
							lastSeaHop = tick()
							_G.teleportToSea("SecondSea")
						end
						return
					end

					local summon = Workspace.AllNPC:FindFirstChild("Summon Tentacle")
					if summon and summon:IsA("BasePart") then
						local root = GetRoot(LocalPlayer.Character)
						if root then
							root.CFrame = CFrame.new(summon.Position)
						end
					end
					return
				end

				-- ===== FINISHED =====
				if _G.thirdSeaState == "finished" then
					if _G.hasThirdSea() then
						saveAndApply("autoThirdSea", false)
						SpectrumX:Notify({ Text = "Teleporting to Third Sea...", Type = "success", Duration = 3 })
						task.wait(1)
						_G.teleportToSea("ThirdSea")
					else
						_G.thirdSeaState = "summon_kraken"
					end
					return
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.1) do
			pcall(function()
				if not buyingStyle then
					return
				end
				if hasStyle(buyingStyle) then
					SpectrumX:Notify({ Text = "Style purchased!", Type = "success", Duration = 3 })
					buyingStyle = nil
					_G._GenesisBuyingStyleStartedAt = 0
					if prevPosition then
						tp(prevPosition)
						prevPosition = nil
					end
					return
				end
				if tick() - (_G._GenesisBuyingStyleStartedAt or 0) >= 12 then
					SpectrumX:Notify({ Text = "Style purchase was not confirmed.", Type = "error", Duration = 3 })
					buyingStyle = nil
					_G._GenesisBuyingStyleStartedAt = 0
					if prevPosition then
						tp(prevPosition)
						prevPosition = nil
					end
					return
				end

				local accept = nil
				for _, gui in pairs(LocalPlayer.PlayerGui:GetChildren()) do
					if gui.Name:find("Shop") then
						local dialogue = gui:FindFirstChild("Dialogue")
						local candidate = dialogue and dialogue:FindFirstChild("Accept")
						if _G._GenesisIsVisibleGuiButton(candidate) then
							accept = candidate
							break
						end
					end
				end

				_G._GenesisDispatchGuiButton(accept)
			end)
		end
	end)

	local flagNames = {
		"Flag One",
		"Flag Two",
		"Flag Three",
		"Flag Four",
		"Flag Five",
		"Flag Six",
		"Flag Seven",
		"Flag Eight",
		"Flag Nine",
		"Flag Ten",
	}

	local function isBeamYellow(beam)
		local kp = beam.Color.Keypoints
		return kp[1].Value.R > 0.8 and kp[1].Value.G > 0.8 and kp[1].Value.B < 0.2
	end

	local function isBeamRed(beam)
		local kp = beam.Color.Keypoints
		return kp[1].Value.R > 0.8 and kp[1].Value.G < 0.2 and kp[1].Value.B < 0.2
	end

	spawn(function()
		while task.wait(0.1) do
			pcall(function()
				if not GetSetting("autoConquest") then
					removeConquestPosition()
					return
				end

				if isConquestBlocked() then
					removeConquestPosition()
					return
				end

				local flagConquest = Workspace:FindFirstChild("FlagConquest")
				if not flagConquest then
					removeConquestPosition()
					if conquestStatusLabel then
						conquestStatusLabel.SetText("Conquest: FlagConquest not found!")
						conquestStatusLabel.Label.TextColor3 = SpectrumX.Theme.Error
					end
					return
				end

				local allRed = true

				for i = 1, 10 do
					if not GetSetting("autoConquest") then
						removeConquestPosition()
						return
					end
					if isConquestBlocked() then
						removeConquestPosition()
						return
					end

					local flag = flagConquest:FindFirstChild("FlagConquest" .. i)
					if flag then
						local beamFolder = flag:FindFirstChild("Beam")
						if beamFolder then
							local beam = beamFolder:FindFirstChild("Beam1")
							if beam then
								if isBeamYellow(beam) then
									allRed = false
									local pillar = flag:FindFirstChild("PillarSmall")
									if pillar then
										local pillarPos = pillar.Position + Vector3.new(0, 3, 0)
										local targetCF = CFrame.new(pillarPos)
										_conquestTargetCF = targetCF
										local root = GetRoot(LocalPlayer.Character)
										if root then
											sethiddenproperty(root, "CFrame", targetCF)
										end
										local arrivalDeadline = tick() + 5
										repeat
											task.wait(0.05)
											root = GetRoot(LocalPlayer.Character)
											if
												not root
												or not GetSetting("autoConquest")
												or isConquestBlocked()
												or tick() >= arrivalDeadline
											then
												removeConquestPosition()
												return
											end
										until (root.Position - pillarPos).Magnitude < 5
										applyConquestPosition(targetCF)

										if conquestStatusLabel then
											conquestStatusLabel.SetText(
												"Conquest: " .. flagNames[i] .. " \240\159\159\161"
											)
											conquestStatusLabel.Label.TextColor3 = Color3.fromRGB(255, 200, 0)
										end

										local captureDeadline = tick() + 30
										repeat
											task.wait(0.05)
											if
												not beam.Parent
												or not GetSetting("autoConquest")
												or isConquestBlocked()
												or tick() >= captureDeadline
											then
												removeConquestPosition()
												return
											end
										until isBeamRed(beam)

										removeConquestPosition()

										if conquestStatusLabel then
											conquestStatusLabel.SetText(
												"Conquest: " .. flagNames[i] .. " \240\159\148\180"
											)
											conquestStatusLabel.Label.TextColor3 = SpectrumX.Theme.Error
										end
										return
									end
								end
							end
						end
					end
				end

				if allRed then
					removeConquestPosition()
					if conquestStatusLabel then
						conquestStatusLabel.SetText("Conquest: All Done!")
						conquestStatusLabel.Label.TextColor3 = SpectrumX.Theme.Success
					end
					if GetSetting("autoHopConquest") then
						task.wait(1)
						serverHop()
					end
				end
			end)
		end
	end)

	_G.dailyQuestState = "idle"
	_G.dailyQuestCurrentNPC = ""
	_G.dailyQuestCurrentName = ""
	_G.dailyQuestCheckQueued = false
	_G.dailyQuestLastCheckAttempt = 0
	_G.dailyQuestNoResponseCount = 0
	_G.dailyQuestTarget = nil
	_G.dailyQuestIssue = nil
	dailyCoordinator.recheckSeconds = 20 * 3600 + 30 * 60
	function dailyCoordinator.readTimes()
		local dailyValue = LocalPlayer.PlayerStats:FindFirstChild("DailyQuest")
		if not dailyValue then return {} end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(dailyValue.Value)
		end)
		return ok and type(data) == "table" and data or {}
	end

	function dailyCoordinator.isDue(rank, quest, times, now)
		local stamp = tonumber(times[quest.quest])
		if stamp then dailyCoordinator.observeCompletion(rank, quest.quest, stamp) end
		local record = dailyCoordinator.record(rank, quest.quest)
		local retryAt = tonumber(record.retryAt)
		if retryAt and now < retryAt then return false end
		if stamp then return now >= stamp + dailyCoordinator.recheckSeconds end
		-- A missing current-sea entry is eligible unless that NPC recently
		-- refused it and supplied a later retry time.
		return times[quest.quest] == nil
	end

	function dailyCoordinator.parseCooldown(value)
		if type(value) ~= "string" then return nil end
		local text = value:lower()
		local amount = 0
		local found = false
		for _, unit in ipairs({
			{ { "day" }, 86400 }, { { "hour", "hr" }, 3600 },
			{ { "minute", "min" }, 60 }, { { "second", "sec" }, 1 },
		}) do
			local number
			for _, pattern in ipairs(unit[1]) do
				number = text:match("(%d+)%s*" .. pattern)
				if number then break end
			end
			if number then
				amount = amount + tonumber(number) * unit[2]
				found = true
			end
		end
		if found then return amount end
		if text:find("come back", 1, true) or text:find("remaining", 1, true)
			or text:find("cooldown", 1, true) or text:find("wait", 1, true)
			or text:find("available in", 1, true) or text:find("try again", 1, true) then
			local hours, minutes, seconds = text:match("(%d+):(%d%d):(%d%d)")
			if hours then return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds) end
			minutes, seconds = text:match("(%d+):(%d%d)")
			if minutes then return tonumber(minutes) * 60 + tonumber(seconds) end
		end
		return nil
	end

	function dailyCoordinator.npcCooldown(quest, response)
		local remaining = dailyCoordinator.parseCooldown(response)
		if remaining then return remaining end
		local loreQuest = quest.npc:sub(1, 5) == "Lore " or quest.npc == "Tomb Event Second"
		local gui = LocalPlayer.PlayerGui:FindFirstChild(loreQuest and "LoreGUI" or quest.npc)
		if not gui or not gui.Enabled then return nil end
		for _, child in ipairs(gui:GetDescendants()) do
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				remaining = dailyCoordinator.parseCooldown(child.Text)
				if remaining then return remaining end
			end
		end
		return nil
	end

	local dailyQuests = {
		[15759515082] = {
		{
			npc = "Lore the Depth",
			quest = "Rolling in the Depth",
			kind = "mob",
			mob = "Deep Diver",
			cframe = CFrame.new(1674, 47, 1015),
		},
		{
			npc = "Lore Lost Fugitive",
			quest = "Redemption",
			kind = "mob",
			mob = "Fugitive",
			cframe = CFrame.new(2888, 35, 993),
		},
		{ npc = "Lore Until Pond", quest = "Until Pond", kind = "mob", mob = "Ocean Gladiator", cframe = CFrame.new(-116, 44, -9150) },
		{ npc = "Lore Into the Bubble-Verse", quest = "Into the Bubble-Verse", kind = "mob", mob = "Cyborg Gorilla", cframe = CFrame.new(5881, 51, 9375) },
		{ npc = "Lore The Bubble One", quest = "Hide'n Seek!", kind = "prompts", object = "Hide'n Seek!" },
		{ npc = "Lore The Pillar", quest = "The Pillar", kind = "prompts", object = "The Pillar" },
		{ npc = "Lore Mossy Must Gone", quest = "Mossy Must Gone", kind = "prompts", object = "Mossy Must Gone" },
		{ npc = "Lore Puzzle First", quest = "Puzzle Mania", kind = "plates" },
		{ npc = "Lore Kraken Codex Easy", quest = "Krakenci Codes (Easy)", kind = "codex", words = { 8, 5, 7 } },
		{ npc = "Lore Kraken Codex Medium", quest = "Krakenci Codes (Medium)", kind = "codex", words = { 1, 9, 4 } },
		{ npc = "Lore Kraken Codex Hard", quest = "Krakenci Codes (Hard)", kind = "codex", words = { 6, 1, 3 } },
		},
		[6381829480] = {
			{ npc = "Lore Bone Hunter", quest = "Bone Hunter", kind = "prompts", object = "Bone Hunter", level = 3000 },
			{ npc = "Lore Sea Madness", quest = "Catch me,If you can", kind = "prompts", object = "Catch me,If you can", level = 3000 },
			{ npc = "Daily Quest DeadAbove", quest = "Dead Above", kind = "prompts", object = "Floating Feather", level = 3000 },
			{ npc = "Lore Sea Sick!", quest = "I'm not,YOU ARE!", kind = "touch", object = "I'm not,YOU ARE!", level = 3000 },
			{ npc = "Lore Sea Diving", quest = "Under The Sea~", kind = "touch", object = "Under The Sea~", level = 3000 },
			{ npc = "Daily Quest Disobey", quest = "Order Disobey", kind = "prompts", object = "PosterQuest", level = 3000 },
			{ npc = "Braveman", quest = "Box Box!", kind = "boxes", level = 3000 },
			{ npc = "Daily QuestLvl3800", quest = "The Lost Book", kind = "book", level = 3800 },
			{ npc = "Daily QuestLvl3000", quest = "One More Time", kind = "mob", mob = "Joey", cframe = CFrame.new(-5287, 57, 2066), spawnOnApproach = true, level = 3000 },
			{ npc = "Daily QuestLvl3500", quest = "Believer", kind = "mob", mob = "Hefty", cframe = CFrame.new(-10489, 84, 969), spawnOnApproach = true, level = 3500 },
			{ npc = "Lore Sea Creature", quest = "Left to Dead", kind = "mob", mob = "Dead Troupe Captain", cframe = CFrame.new(10000, 72, -4200), spawnOnApproach = true, level = 3000 },
			-- The Tomb event giver is seasonal. Its two dailies become eligible only
			-- while that actual NPC exists; never select Quest 1 (Pumpkin Smasher).
			{ npc = "Tomb Event Second", quest = "Left For Dead?", kind = "mob", mob = "Dead Troupe Captain", cframe = CFrame.new(10000, 72, -4200), spawnOnApproach = true, choice = "Quest 2", level = 3500 },
			{ npc = "Tomb Event Second", quest = "Is it Thriller?", kind = "mob", mob = "Skull Pirate", cframe = CFrame.new(-6380, 75, 7030), spawnOnApproach = true, choice = "Quest 3", level = 3800 },
		},
	}
	-- Only the eleven live Third Sea Lore NPCs whose QuestManager entries are
	-- marked DailyQuest belong here. The Codex indices are the game's UI slots:
	-- Fallen/Dark/Heroic, Moon/Savior/Bright, Fearful/Moon/Night.

	dailyQuestCanAct = function()
		if not LocalPlayer:FindFirstChild("PlayerStats") then
			return false
		end
		if not (GetSetting("autoDailyQuestsMaster") and
			((game.PlaceId == 15759515082 and GetSetting("autoDailyQuest"))
				or (game.PlaceId == 6381829480 and GetSetting("autoSecondSeaDailyQuest")))) then
			return false
		end
		if _G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation() then
			return false
		end
		if _G.storingFruit or _G.isLootingChests or fishingOwnsWeaponSlot() then
			return false
		end
		local owner = _G._GenesisPriorityOwner
		return owner == "daily_quest"
	end

	getDailyQuestPending = function()
	local function objectiveSpawnPresent(quest)
			if quest.kind == "book" then
				local islands = Workspace:FindFirstChild("Island")
				local fiore = islands and islands:FindFirstChild("H - Fiore")
				local book = fiore and fiore:FindFirstChild("Lost Book")
				local part = book and book:FindFirstChild("Main")
				return part ~= nil and part:FindFirstChildWhichIsA("ProximityPrompt") ~= nil
			end
			if quest.kind == "boxes" then
				local spawnItems = Workspace:FindFirstChild("SpawnItem")
				local npcFolder = Workspace:FindFirstChild("AllNPC")
				return spawnItems ~= nil and spawnItems:FindFirstChild("Box") ~= nil
					and npcFolder ~= nil and npcFolder:FindFirstChild("Civilian Port") ~= nil
			end
			if quest.kind == "prompts" or quest.kind == "touch" then
				local spawnItems = Workspace:FindFirstChild("SpawnItem")
				return spawnItems ~= nil and spawnItems:FindFirstChild(quest.object) ~= nil
			end
			if quest.kind == "mob" then
				if quest.spawnOnApproach and quest.cframe then
					return true -- the proximity spawn is reached after accepting the daily
				end
				local monsters = Workspace:FindFirstChild("Monster")
				for _, folder in ipairs(monsters and monsters:GetChildren() or {}) do
					if folder:IsA("Folder") then
						for _, mob in ipairs(folder:GetChildren()) do
							local humanoid = mob:FindFirstChild("Humanoid")
							if humanoid and humanoid.Health > 0 and string.find(mob.Name, quest.mob, 1, true) then
								return true
							end
						end
					end
				end
				return false
			end
			return true
		end
		local completed = dailyCoordinator.readTimes()
		local now = os.time()
		local rank = dailyCoordinator.currentRank()
		local activeQuest = LocalPlayer:FindFirstChild("CurrentQuest")
		local activeName = activeQuest and activeQuest.Value
		local list = dailyQuests[game.PlaceId] or {}
		for _, q in ipairs(list) do
			if not q.disabled and q.quest == activeName and dailyCoordinator.isDue(rank, q, completed, now) then
				return q
			end
		end
		if activeName and activeName ~= "" then
			return nil, "paused", activeName
		end
		local levelValue = LocalPlayer.PlayerStats:FindFirstChild("lvl")
		local level = levelValue and levelValue.Value or 0
		local npcFolder = Workspace:FindFirstChild("AllNPC")
		local unavailable = {}
		for _, q in ipairs(list) do
			if not q.disabled and dailyCoordinator.isDue(rank, q, completed, now) and (not q.level or level >= q.level)
				and (game.PlaceId ~= 6381829480 or (npcFolder and npcFolder:FindFirstChild(q.npc))) then
				-- Availability gating is for Second Sea only. Third Sea's existing
				-- travel/spawn workflow must not be skipped by this new guard.
				if game.PlaceId ~= 6381829480 or objectiveSpawnPresent(q) then
					return q
				end
				table.insert(unavailable, q.quest)
			end
		end
		if #unavailable > 0 then
			return nil, "waiting", table.concat(unavailable, ", ")
		end
		return nil, "done"
	end

	function dailyCoordinator.seaEnabled(rank)
		return GetSetting("autoDailyQuestsMaster") and
			((rank == 2 and GetSetting("autoSecondSeaDailyQuest"))
				or (rank == 3 and GetSetting("autoDailyQuest")))
	end

	function dailyCoordinator.nextSeaCheck(rank, now)
		local nextAt
		local levelValue = LocalPlayer.PlayerStats:FindFirstChild("lvl")
		local level = levelValue and levelValue.Value or 0
		for _, quest in ipairs(dailyQuests[dailyCoordinator.sea[rank].place] or {}) do
			if not quest.disabled and (not quest.level or level >= quest.level) then
				local record = dailyCoordinator.record(rank, quest.quest)
				local retryAt = tonumber(record.retryAt) or 0
				local completedAt = tonumber(record.completedAt) or 0
				local dueAt = retryAt > now and retryAt
					or (completedAt > 0 and completedAt + dailyCoordinator.recheckSeconds)
					or (now + 3600)
				-- A missing seasonal NPC or objective may leave an already-due
				-- record. Revisit later, but do not bounce between seas constantly.
				if dueAt <= now then dueAt = now + 3600 end
				nextAt = nextAt and math.min(nextAt, dueAt) or dueAt
			end
		end
		return nextAt or now + 3600
	end

	function dailyCoordinator.travelNpc(current, destination)
		-- The First Sea captain only takes us to Second Sea. When Third Sea is
		-- the destination, make that an intermediate hop instead of skipping NPCs.
		local hop = current == 1 and destination == 3 and 2 or destination
		if current == 1 or (current == 2 and hop == 1) then
			return "Elite Pirate", hop
		end
		if current == 2 or current == 3 then
			return "The Squid", hop
		end
		return nil, nil
	end

	function dailyCoordinator.findTravelChoice(dialogue, current, hop)
		local target = dailyCoordinator.sea[hop].label:lower():gsub("[^%a]", "")
		local ordinal = ({ [1] = "1stsea", [2] = "2ndsea", [3] = "3rdsea" })[hop]
		local function normalize(value)
			return tostring(value or ""):lower():gsub("[^%w]", "")
		end
		-- Third Sea offers more than one destination. Select only a button
		-- whose visible label or name explicitly identifies the requested sea.
		for _, button in ipairs(dialogue:GetDescendants()) do
			if button:IsA("GuiButton") and _G._GenesisIsVisibleGuiButton(button) then
				local label = button.Name
				if button:IsA("TextButton") then label = label .. " " .. button.Text end
				for _, child in ipairs(button:GetDescendants()) do
					if (child:IsA("TextLabel") or child:IsA("TextButton"))
						and not child.Name:match("^Char%d+$") then
						label = label .. " " .. child.Text
					end
				end
				local normalized = normalize(label)
				if normalized:find(target, 1, true)
					or (ordinal and normalized:find(ordinal, 1, true)) then
					return button
				end
			end
		end

		local accept = dialogue:FindFirstChild("Accept")
		if not _G._GenesisIsVisibleGuiButton(accept) then return nil end
		-- Verified in the live Second Sea: The Squid's Accept is the Third
		-- Sea option, with a server-side Script attached to the actual button.
		if current == 2 and hop == 3 then return accept end

		-- Some NPCs present a single destination in their speech followed by
		-- generic Accept/Decline buttons. Only accept when that one destination
		-- is unambiguous; never guess between First and Second Sea.
		local textFrame = dialogue:FindFirstChild("TextFrame")
		local words = {}
		for _, child in ipairs(textFrame and textFrame:GetDescendants() or {}) do
			if child:IsA("TextLabel") and child.Name:match("^Group%d+$") then
				table.insert(words, child.Text)
			end
		end
		local speech = normalize(table.concat(words, " "))
		if not speech:find(target, 1, true) then return nil end
		for rank, info in pairs(dailyCoordinator.sea) do
			if rank ~= hop and speech:find(normalize(info.label), 1, true) then
				return nil
			end
		end
		return accept
	end

	function dailyCoordinator.clickTravelChoice(button)
		if not _G._GenesisIsVisibleGuiButton(button) then return false end
		local originalSize, originalPosition = button.Size, button.Position
		local x, y
		local clicked, mouseDown = false, false
		local connection = button.MouseButton1Click:Connect(function() clicked = true end)
		-- firesignal only advances the client dialogue; it does not activate
		-- the server Script attached to these older NPC buttons. On the live
		-- Android client a center-position virtual click missed, while the
		-- existing enlarged-button real-input pattern hit The Squid's Decline.
		local ok = pcall(function()
			button.Size = UDim2.new(10, 0, 10, 0)
			button.Position = UDim2.new(-1.9, 0, -5.5, 0)
			RunService.RenderStepped:Wait()
			if not _G._GenesisIsVisibleGuiButton(button) then return end
			local camera = Workspace.CurrentCamera
			if not camera then return end
			local viewport = camera.ViewportSize
			x, y = math.floor(viewport.X - 20), math.floor(viewport.Y / 15)
			local position, size = button.AbsolutePosition, button.AbsoluteSize
			if x < position.X or x > position.X + size.X
				or y < position.Y or y > position.Y + size.Y then return end
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
			mouseDown = true
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
			mouseDown = false
			task.wait(0.15)
		end)
		if mouseDown then
			pcall(function() VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
		end
		pcall(function()
			button.Size = originalSize
			button.Position = originalPosition
		end)
		connection:Disconnect()
		return ok and clicked
	end

	function dailyCoordinator.travelRetry(route, now, message, delay)
		_G._GenesisDailyQuestTravelPending = false
		_G._GenesisDailyReturnRequested = false
		_G.dailyQuestIssue = message
		route.retryAt = now + (delay or 30)
		dailyCoordinator.save()
		if not _G._GenesisDailyTravelWarningAt or now - _G._GenesisDailyTravelWarningAt >= 60 then
			_G._GenesisDailyTravelWarningAt = now
			SpectrumX:Notify({ Text = message, Type = "warning", Duration = 5 })
		end
	end

	_G._GenesisDailyQuestTravelPending = false
	_G._GenesisDailyReturnRequested = false
	spawn(function()
		while task.wait(2) do
			pcall(function()
				if not GetSetting("autoDailyQuestsMaster") then
					_G._GenesisDailyQuestTravelPending = false
					_G._GenesisDailyReturnRequested = false
					return
				end
				if not LocalPlayer:FindFirstChild("PlayerStats") then return end
				local current = dailyCoordinator.currentRank()
				if not current then return end
				local now = os.time()
				local journal = dailyCoordinator.journal
				local main = dailyCoordinator.mainRank()
				local unlocked = dailyCoordinator.refreshAccess()
				journal.nextSeaCheck = type(journal.nextSeaCheck) == "table" and journal.nextSeaCheck or {}
				local route = journal.route
				if type(route) == "table" then
					route.visited = type(route.visited) == "table" and route.visited or {}
					if route.mainSea ~= main or now - (tonumber(route.startedAt) or now) > 7200 then
						journal.route = nil
						route = nil
						_G._GenesisDailyQuestTravelPending = false
						_G._GenesisDailyReturnRequested = false
					elseif route.target == current then
						route.target = nil
						route.targetAt = nil
						route.transferAttempts = 0
						_G._GenesisDailyQuestTravelPending = false
						_G._GenesisDailyReturnRequested = false
						dailyCoordinator.save()
					elseif route.target then
						-- A real UI click is not proof that the server accepted the sea
						-- transfer. Keep the route locked for a short handoff window, then
						-- resume the Squid approach/dialogue loop in this same pass if the
						-- PlaceId still has not changed.
						if now - (tonumber(route.targetAt) or 0) < 8 then
							_G._GenesisDailyQuestTravelPending = true
							_G._GenesisDailyReturnRequested = tonumber(route.target) == main and current ~= main
							return
						end
						route.target = nil
						route.targetAt = nil
						route.retryAt = nil
						route.transferAttempts = (tonumber(route.transferAttempts) or 0) + 1
						dailyCoordinator.save()
					end
				end

				local activeValue = LocalPlayer:FindFirstChild("CurrentQuest")
				local activeName = activeValue and activeValue.Value
				if activeName and activeName ~= "" then
					for _, quest in ipairs(dailyQuests[game.PlaceId] or {}) do
						if not quest.disabled and quest.quest == activeName then
							_G._GenesisDailyQuestTravelPending = false
							_G._GenesisDailyReturnRequested = false
							return
						end
					end
				end
				local pending, state
				if dailyCoordinator.seaEnabled(current) then
					pending, state = getDailyQuestPending()
					if pending then
						_G._GenesisDailyQuestTravelPending = false
						_G._GenesisDailyReturnRequested = false
						return
					end
				end
				if not route then
					local anyDue = false
					for rank = 2, unlocked do
						if dailyCoordinator.seaEnabled(rank) and now >= (tonumber(journal.nextSeaCheck[tostring(rank)]) or 0) then
							anyDue = true
							break
						end
					end
					if not anyDue and current == main then
						_G._GenesisDailyQuestTravelPending = false
						_G._GenesisDailyReturnRequested = false
						return
					end
					route = { startedAt = now, mainSea = main, visited = {} }
					journal.route = route
					dailyCoordinator.save()
				end

				if not route.visited[tostring(current)] then
					route.visited[tostring(current)] = true
					if dailyCoordinator.seaEnabled(current) then
						journal.nextSeaCheck[tostring(current)] = dailyCoordinator.nextSeaCheck(current, now)
					end
					dailyCoordinator.save()
				end
				local destination
				for rank = 2, unlocked do
					if rank ~= current and dailyCoordinator.seaEnabled(rank) and not route.visited[tostring(rank)]
						and now >= (tonumber(journal.nextSeaCheck[tostring(rank)]) or 0) then
						destination = rank
						break
					end
				end
				if not destination and current ~= main then destination = main end
				if not destination then
					journal.route = nil
					_G._GenesisDailyQuestTravelPending = false
					_G._GenesisDailyReturnRequested = false
					dailyCoordinator.save()
					return
				end
				if now < (tonumber(route.retryAt) or 0) then
					_G._GenesisDailyQuestTravelPending = false
					_G._GenesisDailyReturnRequested = false
					return
				end
				local returningMain = destination == main and current ~= main
				_G._GenesisDailyQuestTravelPending = true
				_G._GenesisDailyReturnRequested = returningMain
				-- Return-to-main preempts outside-dungeon work, including a dungeon
				-- entry attempt. A committed picker/transition/active raid still wins.
				local committed = _G._GenesisUpdateDungeonCommit and _G._GenesisUpdateDungeonCommit()
				if committed or fishingOwnsWeaponSlot() then
					return
				end
				if returningMain then
					if _G._GenesisPriorityOwner ~= "daily_quest_return" then return end
				elseif _G._GenesisPriorityOwner ~= "daily_quest_handoff"
					or _G.storingFruit or _G.isLootingChests or _G.seaEventActive
					or (_G._GenesisDungeonOwnsAutomation and _G._GenesisDungeonOwnsAutomation()) then
					return
				end
				local npcName, hop = dailyCoordinator.travelNpc(current, destination)
				local allNpc = Workspace:FindFirstChild("AllNPC")
				local npc = allNpc and allNpc:FindFirstChild(npcName or "")
				if not npc or not npc:IsA("BasePart") then
					dailyCoordinator.travelRetry(route, now, "Daily sea travel NPC is unavailable: " .. tostring(npcName), 60)
					return
				end
				local root = GetRoot(LocalPlayer.Character)
				if not root then return end
				if (root.Position - npc.Position).Magnitude > 8 then
					if type(_G._stopDailyQuestHover) == "function" then
						_G._stopDailyQuestHover()
					end
					tp(CFrame.new(npc.Position + Vector3.new(0, 3, 4), npc.Position), returningMain)
					return -- let the server observe our position before opening dialogue
				end
				local gui = LocalPlayer.PlayerGui:FindFirstChild(npcName)
				local dialogue = gui and gui:FindFirstChild("Dialogue")
				if not (gui and gui.Enabled and dialogue and dialogue.Visible) then
					if dailyCoordinator.npcTalkInFlight
						and os.clock() - (dailyCoordinator.npcTalkLastAt or 0) > 12 then
						dailyCoordinator.npcTalkInFlight = false
						dailyCoordinator.npcTalkGeneration = (dailyCoordinator.npcTalkGeneration or 0) + 1
						route.npcTalkFailures = (route.npcTalkFailures or 0) + 1
						if route.npcTalkFailures >= 3 then
							route.npcTalkFailures = 0
							dailyCoordinator.travelRetry(route, now, npcName .. " did not open a sea-travel dialogue.", 90)
							return
						end
					end
					if not dailyCoordinator.npcTalkInFlight
						and os.clock() - (dailyCoordinator.npcTalkLastAt or 0) >= 6 then
						dailyCoordinator.npcTalkInFlight = true
						dailyCoordinator.npcTalkLastAt = os.clock()
						dailyCoordinator.npcTalkGeneration = (dailyCoordinator.npcTalkGeneration or 0) + 1
						local generation = dailyCoordinator.npcTalkGeneration
						task.spawn(function()
							pcall(function()
								ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(npc)
							end)
							if dailyCoordinator.npcTalkGeneration == generation then
								dailyCoordinator.npcTalkInFlight = false
							end
						end)
					end
					return
				end
				route.npcTalkFailures = 0
				local button = dailyCoordinator.findTravelChoice(dialogue, current, hop)
				if not button then
					dailyCoordinator.travelRetry(route, now,
						npcName .. " dialogue has no verified " .. dailyCoordinator.sea[hop].label .. " choice.", 30)
					return
				end
				route.target = hop
				route.targetAt = now
				dailyCoordinator.save()
				if not dailyCoordinator.clickTravelChoice(button) then
					route.target = nil
					route.targetAt = nil
					dailyCoordinator.travelRetry(route, now, "NPC sea-travel button did not receive a real click.", 15)
				end
			end)
		end
	end)

	local function closeSecondSeaBasicDailyDialogue(quest)
		if game.PlaceId ~= 6381829480 or quest.npc:sub(1, 5) == "Lore "
			or quest.npc == "Tomb Event Second" then
			return
		end
		local gui = LocalPlayer.PlayerGui:FindFirstChild(quest.npc)
		local dialogue = gui and gui:FindFirstChild("Dialogue")
		local close = gui and gui:FindFirstChild("DelGui")
		if dialogue and dialogue.Visible and close and close:IsA("RemoteEvent") then
			close:FireServer()
		end
	end

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not dailyQuestCanAct() then
					return
				end

				local current, pendingState, pendingDetail = getDailyQuestPending()
				if not current then
					_G.dailyQuestState = pendingState or "done"
					if pendingState == "waiting" then
						_G.dailyQuestIssue = "Waiting for daily objectives: " .. pendingDetail
					elseif pendingState == "paused" then
						_G.dailyQuestIssue = "Another quest is active: " .. pendingDetail
					else
						_G.dailyQuestIssue = nil
					end
					return
				end

				local currentQuest = LocalPlayer:FindFirstChild("CurrentQuest")
				local hasQuest = currentQuest and currentQuest.Value == current.quest

				if _G.dailyQuestState == "idle" or _G.dailyQuestState == "done"
					or _G.dailyQuestState == "waiting" or _G.dailyQuestState == "paused"
					or _G.dailyQuestCurrentNPC ~= current.npc or _G.dailyQuestCurrentName ~= current.quest then
					_G.dailyQuestState = hasQuest and (current.kind == "mob" and "kill" or "objective") or "get_quest"
					_G.dailyQuestCurrentNPC = current.npc
					_G.dailyQuestCurrentName = current.quest
					_G.dailyQuestIssue = nil
					_G.dailyQuestCheckQueued = false
					_G.dailyQuestLastCheckAttempt = 0
					_G.dailyQuestNoResponseCount = 0
					if hasQuest then
						closeSecondSeaBasicDailyDialogue(current)
					end
					return
				end

				if _G.dailyQuestState == "get_quest" then
					if hasQuest then
						closeSecondSeaBasicDailyDialogue(current)
						_G.dailyQuestState = current.kind == "mob" and "kill" or "objective"
							_G.dailyQuestCheckQueued = false
							_G.dailyQuestLastCheckAttempt = 0
							_G.dailyQuestNoResponseCount = 0
						return
					end
					if game.PlaceId == 6381829480 then
						local loreQuest = current.npc:sub(1, 5) == "Lore " or current.npc == "Tomb Event Second"
						local gui = LocalPlayer.PlayerGui:FindFirstChild(loreQuest and "LoreGUI" or current.npc)
						local dialogue = gui and gui:FindFirstChild("Dialogue")
						if dialogue and dialogue.Visible and gui.Enabled then
							return -- let the visible quest picker finish before reopening this NPC
						end
					end
					local npc = Workspace.AllNPC:FindFirstChild(current.npc)
					if npc and npc:IsA("BasePart") then
						local root = GetRoot(LocalPlayer.Character)
						if root then
							root.CFrame = CFrame.new(npc.Position)
						end
					end
					if tick() - (_G.dailyQuestLastCheckAttempt or 0) >= 2 then
						_G.dailyQuestCheckQueued = true
						_G.dailyQuestLastCheckAttempt = tick()
						task.wait(0.5)
						if not dailyQuestCanAct() or _G.dailyQuestState ~= "get_quest" then
							return
						end
						local response
						pcall(function()
							local npcPart = Workspace.AllNPC:FindFirstChild(current.npc)
							if npcPart then
								response = ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(npcPart)
							end
						end)
						task.wait(0.4)
						local remaining = dailyCoordinator.npcCooldown(current, response)
						if remaining and remaining > 0 then
							dailyCoordinator.deferQuest(dailyCoordinator.currentRank(), current.quest,
									os.time() + remaining + 60)
							_G.dailyQuestState = "idle"
							_G.dailyQuestIssue = "NPC cooldown: " .. tostring(math.ceil(remaining / 60)) .. "m"
						elseif not (currentQuest and currentQuest.Value == current.quest) then
							local loreQuest = current.npc:sub(1, 5) == "Lore " or current.npc == "Tomb Event Second"
							local picker = LocalPlayer.PlayerGui:FindFirstChild(loreQuest and "LoreGUI" or current.npc)
							local dialogue = picker and picker:FindFirstChild("Dialogue")
							if not (picker and picker.Enabled and dialogue and dialogue.Visible) then
								_G.dailyQuestNoResponseCount = (_G.dailyQuestNoResponseCount or 0) + 1
								if _G.dailyQuestNoResponseCount >= 3 then
									dailyCoordinator.deferQuest(dailyCoordinator.currentRank(), current.quest,
										os.time() + 600)
									_G.dailyQuestState = "idle"
									_G.dailyQuestIssue = "NPC did not offer the quest; retrying later"
									_G.dailyQuestNoResponseCount = 0
								end
							end
						end
					end
					return
				end

				if _G.dailyQuestState == "kill" or _G.dailyQuestState == "objective" then
					if not hasQuest then
						_G.dailyQuestState = "idle"
						_G.dailyQuestCheckQueued = false
						_G.dailyQuestLastCheckAttempt = 0
						return
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.1) do
			pcall(function()
				if not dailyQuestCanAct() then
					_G.dailyQuestTarget = nil
					return
				end
				if _G.dailyQuestState ~= "kill" then
					_G.dailyQuestTarget = nil
					return
				end
				local current = getDailyQuestPending()
				if not current or current.kind ~= "mob" then
					_G.dailyQuestTarget = nil
					return
				end
				local found = nil
				for _, folder in pairs(Workspace.Monster:GetChildren()) do
					if folder:IsA("Folder") then
						for _, mob in pairs(folder:GetChildren()) do
							if
								mob:FindFirstChild("Humanoid")
								and mob.Humanoid.Health > 0
								and string.find(mob.Name, current.mob, 1, true)
							then
								found = mob
								break
							end
						end
					end
					if found then
						break
					end
				end
				if found then
					_G.dailyQuestTarget = found
				else
					_G.dailyQuestTarget = nil
					tp(current.cframe)
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				local animValue = LocalPlayer.PlayerStats:FindFirstChild("Animation")
				local selected = GetSetting("selectedAnimation") or "Standard"
				if animValue and animValue.Value ~= selected then
					animValue.Value = selected
				end
			end)
		end
	end)

	do
	local lastInput = tick()

	trackGenesisConnection(UserInputService.InputBegan:Connect(function()
		lastInput = tick()
	end))

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if tick() - lastInput < 60 then
					return
				end

				-- Avoid blind screen-coordinate clicks: an unrelated menu can occupy that
				-- point. A bounded key pulse is sufficient to keep the client active.
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
				task.wait(0.1)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)

				lastInput = tick()
			end)
		end
	end)
	end

	local autoPlayInFlight = false
	local autoPlayLastAttempt = 0

	local function autoPlay()
		if autoPlayInFlight then
			return true
		end

		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local loadingGui = playerGui and playerGui:FindFirstChild("LoadingGUI")
		if not loadingGui then
			return false
		end
		if os.clock() - autoPlayLastAttempt < 3 then
			return true
		end

		local playButton = loadingGui and loadingGui:FindFirstChild("Play")
		if not playButton or not playButton:IsA("GuiButton") or not playButton.Visible then
			return true
		end

		local chest = ReplicatedStorage:FindFirstChild("Chest")
		local remotes = chest and chest:FindFirstChild("Remotes")
		local functionsFolder = remotes and remotes:FindFirstChild("Functions")
		local etcFunction = functionsFolder and functionsFolder:FindFirstChild("EtcFunction")
		if not etcFunction or not etcFunction:IsA("RemoteFunction") then
			return true
		end

		autoPlayInFlight = true
		autoPlayLastAttempt = os.clock()
		task.spawn(function()
			local finished = false
			local invokeThread = task.spawn(function()
				pcall(function()
					-- This is the action used by ReplicatedFirst.LoadingScript's Play callback.
					etcFunction:InvokeServer("EnterTheGame", {})
				end)
				finished = true
			end)

			local deadline = os.clock() + 10
			while not finished and os.clock() < deadline do
				local currentGui = playerGui and playerGui:FindFirstChild("LoadingGUI")
				if not currentGui then
					break
				end
				task.wait(0.1)
			end

			if not finished then
				pcall(task.cancel, invokeThread)
			end
			autoPlayInFlight = false
		end)
		return true
	end

	spawn(function()
		while task.wait(0.5) do
			pcall(updateRaidStatusLabel)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if not serpentTimerLabel then
					return
				end
				local whirlpool = getWhirlpoolCFrame()
				local serpent = findSerpent()
				if serpent and isValidMob(serpent) then
					serpentTimerLabel.SetText("Serpent: \240\159\159\162 | Go Hunt!")
					serpentTimerLabel.Label.TextColor3 = SpectrumX.Theme.Success
				elseif whirlpool then
					serpentTimerLabel.SetText("Whirlpool: \240\159\159\162 | Go Hook The Serpent!")
					serpentTimerLabel.Label.TextColor3 = SpectrumX.Theme.Warning
				else
					serpentTimerLabel.SetText("Serpent: \240\159\148\180 | Whirlpool: \240\159\148\180")
					serpentTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if game.PlaceId ~= 15759515082 then
					return
				end
				if not Sea3EventsTimerLabel then
					return
				end

				local timerText = ReplicatedStorage:GetAttribute("ThirdSeaMonsterSpawnText") or "--:--"
				local isSetSail = (timerText == "SET SAIL")

				local function detectActiveSeaEvent()
					if Workspace.Monster:FindFirstChild("Boss") then
						for _, child in pairs(Workspace.Monster.Boss:GetChildren()) do
							if child:FindFirstChild("Humanoid") and child.Humanoid.Health > 0 then
								local name = child.Name
								if string.find(name, "Tentacle") or string.find(name, "FuryTentacle") then
									return "Kraken"
								elseif string.find(name, "ThirdSeaDragon") then
									return "Drakenfyr"
								elseif string.find(name, "SeaDragon") and not string.find(name, "ThirdSeaDragon") then
									return "Abyssal Tyrant"
								elseif string.find(name, "ThirdSeaEldritch") or string.find(name, "Crab") then
									return "Deepsea Crusher"
								end
							end
						end
					end
					for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
						if monster:FindFirstChild("Humanoid") and monster.Humanoid.Health > 0 then
							local name = monster.Name
							if string.find(name, "Eldritch") or string.find(name, "Crab") then
								return "Deepsea Crusher"
							elseif string.find(name, "ThirdSeaDragon") then
								return "Drakenfyr"
							elseif string.find(name, "SeaDragon") and not string.find(name, "ThirdSeaDragon") then
								return "Abyssal Tyrant"
							end
						end
					end
					return nil
				end

				local activeEvent = detectActiveSeaEvent()
				if activeEvent then
					Sea3EventsTimerLabel.SetText("Set Sail: \240\159\159\162 | " .. activeEvent)
					Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.Success
				elseif isSetSail then
					Sea3EventsTimerLabel.SetText("Set Sail: \240\159\159\161 | Unknown")
					Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.Warning
				else
					local displayTimer = (timerText == "--:--" and "--:--") or timerText
					Sea3EventsTimerLabel.SetText("Set Sail: \240\159\148\180 | " .. displayTimer)
					if timerText ~= "--:--" then
						local min, sec = timerText:match("(%d+):(%d+)")
						if min and sec then
							local totalSec = tonumber(min) * 60 + tonumber(sec)
							if totalSec <= 60 then
								Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							elseif totalSec <= 180 then
								Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							else
								Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							end
						end
					else
						Sea3EventsTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if game.PlaceId ~= 15759515082 then
					return
				end
				if not GalleonStatusLabel then
					return
				end

				local galleonFound = false
				local galleonName = ""
				for _, monster in pairs(Workspace.SeaMonster:GetChildren()) do
					if
						string.find(monster.Name, "Galleon")
						and monster:FindFirstChild("Humanoid")
						and monster.Humanoid.Health > 0
					then
						galleonFound = true
						galleonName = monster.Name
						break
					end
				end
				if galleonFound then
					local cleanName = galleonName:gsub("%s*%[Lv%.%s*%d+%]%s*", ""):gsub("%s*Boss%s*$", "")
					GalleonStatusLabel.SetText("Ship: \240\159\159\162 | " .. cleanName)
					GalleonStatusLabel.Label.TextColor3 = SpectrumX.Theme.Success
				else
					GalleonStatusLabel.SetText("Ship: \240\159\148\180 | Spawns Soon")
					GalleonStatusLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if game.PlaceId ~= 15759515082 then
					return
				end
				if not RaceIslandStatusLabel then
					return
				end

				local raceIsland, _, raceDisplayName = _G._GenesisFindRaceIsland()
				if raceIsland then
					RaceIslandStatusLabel.SetText("Race Island: \240\159\159\162 | " .. raceDisplayName)
					RaceIslandStatusLabel.Label.TextColor3 = SpectrumX.Theme.Success
				else
					RaceIslandStatusLabel.SetText("Race Island: \240\159\148\180 | Spawns Soon")
					RaceIslandStatusLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if game.PlaceId ~= 6381829480 then
					return
				end
				if not SeaKingTimerLabel then
					return
				end

				local hydraMob = findHydraMob()
				local seaKingMob = findSeaKingMob()
				local hydraAlive = hydraMob and hydraMob:FindFirstChild("Humanoid") and hydraMob.Humanoid.Health > 0
				local seaKingAlive = seaKingMob
					and seaKingMob:FindFirstChild("Humanoid")
					and seaKingMob.Humanoid.Health > 0
				local timerText = ReplicatedStorage:GetAttribute("SeaMonsterSpawnText") or "--:--"
				local isUnleashed = (timerText == "UNLEASHED")
				local isHydra = ReplicatedStorage:GetAttribute("Hydra")
				local eventName = isHydra and "Hydra" or "Sea King"
				local eventActive = false
				if isHydra then
					eventActive = hydraAlive or (isUnleashed and not seaKingAlive)
				else
					eventActive = seaKingAlive or (isUnleashed and not hydraAlive)
				end

				if eventActive then
					SeaKingTimerLabel.SetText(eventName .. ": \240\159\159\162 | Go Hunt!")
					SeaKingTimerLabel.Label.TextColor3 = SpectrumX.Theme.Success
				else
					local displayTimer = (timerText == "UNLEASHED" or timerText == "--:--") and "--:--" or timerText
					SeaKingTimerLabel.SetText(eventName .. ": \240\159\148\180 | " .. displayTimer)
					if timerText ~= "--:--" and timerText ~= "UNLEASHED" then
						local min, sec = timerText:match("(%d+):(%d+)")
						if min and sec then
							local totalSec = tonumber(min) * 60 + tonumber(sec)
							if totalSec <= 60 then
								SeaKingTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							elseif totalSec <= 180 then
								SeaKingTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							else
								SeaKingTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							end
						end
					else
						SeaKingTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.5) do
			pcall(function()
				if game.PlaceId ~= 6381829480 then
					return
				end
				if not GhostShipTimerLabel then
					return
				end

				local ghostShip = findGhostShip()
				local gsText = ReplicatedStorage:GetAttribute("GhostShipSpawnText") or "--:--"
				local gsUnleashed = (gsText == "UNLEASHED")
				local ghostActive = ghostShip and ghostShip:FindFirstChild("Humanoid") and ghostShip.Humanoid.Health > 0

				if ghostActive or gsUnleashed then
					GhostShipTimerLabel.SetText("Ghost Ship: \240\159\159\162 | Go Hunt!")
					GhostShipTimerLabel.Label.TextColor3 = SpectrumX.Theme.Success
				else
					local displayTimer = (gsText == "UNLEASHED" or gsText == "--:--") and "--:--" or gsText
					GhostShipTimerLabel.SetText("Ghost Ship: \240\159\148\180 | " .. displayTimer)
					if gsText ~= "--:--" and gsText ~= "UNLEASHED" then
						local min, sec = gsText:match("(%d+):(%d+)")
						if min and sec then
							local totalSec = tonumber(min) * 60 + tonumber(sec)
							if totalSec <= 60 then
								GhostShipTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							elseif totalSec <= 180 then
								GhostShipTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							else
								GhostShipTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
							end
						end
					else
						GhostShipTimerLabel.Label.TextColor3 = SpectrumX.Theme.TextSecondary
					end
				end
			end)
		end
	end)

	spawn(function()
		while true do
			task.wait(2)
			pcall(function()
				if islandDropdown then
					local newOptions = islandsBySea[game.PlaceId] or {}
					if #newOptions ~= #currentSeaIslands or newOptions[1] ~= currentSeaIslands[1] then
						updateIslandDropdown()
					end
				end
			end)
		end
	end)

	spawn(function()
		while task.wait(0.1) do
			autoPlay()
		end
	end)

	pcall(function()
		if GetSetting("hideNotify") then
			applyHideNotify(true)
		end
		if GetSetting("blackScreen") then
			applyBlackScreen(true)
		end
	end)

	pcall(function()
		if setclipboard then
			setclipboard("https://discord.gg/2uUUMKSQyq")
		elseif toclipboard then
			toclipboard("https://discord.gg/2uUUMKSQyq")
		elseif syn and syn.setclipboard then
			syn.setclipboard("https://discord.gg/2uUUMKSQyq")
		elseif game:GetService("GuiService") and game:GetService("GuiService").SetClipboard then
			game:GetService("GuiService"):SetClipboard("https://discord.gg/2uUUMKSQyq")
		else
		end
	end)

	updateIslandDropdown()

	task.spawn(function()
		local req = http_request or request or (syn and syn.request)
		if not req then
			return
		end

		local accessTag = "FREE"
		pcall(function()
			if hasSmartHopAccess and hasSmartHopAccess() then
				accessTag = "PREMIUM"
			end
		end)

		local placeIdStr = tostring(game.PlaceId)
		local rawJobId = tostring(game.JobId)
		local encodedJobId = encodeBase64(rawJobId)

		local desc = table.concat({
			"<:arrogance:1515134844550643906> `Player` ```" .. LocalPlayer.Name .. " | " .. accessTag .. "```",
			"<a:annouce:1515134872744890428> `Date` ```" .. os.date("%d/%m/%Y | %H:%M:%S") .. "```",
			"<a:dark_world:1515134876393803916> [Join Server (Web)](https://www.roblox.com/games/start?placeId="
				.. placeIdStr
				.. "&gameInstanceId="
				.. rawJobId
				.. ")",
			"<:gamepad:1515133997943095427> [Join Server (App)](https://www.roblox.com/experiences/start?placeId="
				.. placeIdStr
				.. "&gameInstanceId="
				.. rawJobId
				.. ")",
			"<a:online:1515133999595524146> `Join Script` ```game:GetService(\034TeleportService\034):TeleportToPlaceInstance("
				.. placeIdStr
				.. ", \034"
				.. rawJobId
				.. "\034)```",
			"<:yousuredog:1515134845922312202> `Encoded JobId` ||```" .. encodedJobId .. "```||",
		}, "\010")

		pcall(function()
			req({
				Url = "https://discord.com/api/webhooks/1381676298543435897/WgMBy4g47MHatib8mtmue1lSJjWuiS8Yk4fFDoXIs1JcaOMthepTidAR9iBejP9tp5Dz",
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = HttpService:JSONEncode({
					embeds = {
						{
							title = "<a:red_siren:1515133995657072812> \194\183 SCRIPT EXECUTED",
							description = desc,
							color = 10181046,
							footer = { text = "Genesis Hub | King Legacy" },
						},
					},
				}),
			})
		end)
	end)

	GenesisX:Notify({
		Title = "GENESIS HUB",
		Text = "LOADED SUCCESSFULLY!",
		Type = "genesis",
		Duration = 10,
	})

	spawn(function()
		while task.wait(1) do
			pcall(function()
				if not isFeatureEnabledInCurrentSea("autoSKHD") then
					if _G.lootState.SeaKing.active or _G.lootState.Hydra.active then
						removeChestLootFix()
						_G.isLootingChests = false
						_G.lootState.SeaKing = { active = false }
						_G.lootState.Hydra = { active = false }
						if _G.lootThreads.SeaKing then
							_G.lootThreads.SeaKing = nil
						end
						if _G.lootThreads.Hydra then
							_G.lootThreads.Hydra = nil
						end
						_G.monitoringSeaKing = false
						_G.monitoringHydra = false
					end
				end
			end)
		end
	end)

	task.spawn(function()
		local success, err = pcall(function()
			local TeleportService = game:GetService("TeleportService")
			local Players = game:GetService("Players")
			local HttpService = game:GetService("HttpService")
			local CoreGui = game:GetService("CoreGui")

			local PLACE_ID = game.PlaceId
			local lastHop = 0
			local detectionConnection = nil

			local function forceHop()
				if tick() - lastHop < 8 then
					return
				end
				lastHop = tick()

				pcall(function()
					if typeof(serverHop) == "function" then
						serverHop()
					else
						TeleportService:Teleport(PLACE_ID)
					end
				end)
			end

			-- Detect the error screen.
			local function startDetection()
				if detectionConnection and detectionConnection.Connected then
					return
				end
				local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
				if not promptGui then
					return
				end

				local overlay = promptGui:FindFirstChild("promptOverlay")
				if not overlay then
					return
				end

				detectionConnection = trackGenesisConnection(overlay.ChildAdded:Connect(function(child)
					task.wait(0.6)
					local text = ""
					pcall(function()
						for _, v in pairs(child:GetDescendants()) do
							if v:IsA("TextLabel") or v:IsA("TextButton") then
								text = text .. " " .. string.lower(tostring(v.Text or ""))
							end
						end
					end)

					if
						string.find(text, "desconectado")
						or string.find(text, "disconnected")
						or string.find(text, "288")
						or string.find(text, "desligado")
					then
						forceHop()
					end
				end))
			end

			-- Try to start detection several times.
			for i = 1, 10 do
				task.wait(1)
				pcall(startDetection)
			end

			-- Safety loop.
			while true do
				task.wait(8)
				pcall(function()
					if not Players.LocalPlayer or not Players.LocalPlayer.Parent then
						forceHop()
					end
				end)
			end
		end)

		if not success then
			warn("wrong: " .. tostring(err))
		end
	end)

	-- ========== AUTO BUSO V2 + AUTO KEN V2 (Observation) ==========
	-- No "local" in the main chunk (Luau has a limit of 200 locals).
	-- Everything lives in _G.HakiV2.

	_G.HakiV2 = _G.HakiV2 or {}
	_G.HakiV2.SEA2 = 6381829480
	_G.HakiV2.DARK_BEARD_AREA = CFrame.new(-9486, 77, -4761)
	_G.HakiV2.lockConn = nil
	_G.HakiV2.lockCF = nil
	_G.HakiV2.bp = nil
	_G.HakiV2.bg = nil

	_G.HakiV2.getBeli = function()
		local ok, val = pcall(function()
			local stats = LocalPlayer:FindFirstChild("PlayerStats")
			if not stats then
				return 0
			end
			local b = stats:FindFirstChild("beli") or stats:FindFirstChild("Beli")
			if b then
				return tonumber(b.Value) or 0
			end
			return 0
		end)
		return ok and val or 0
	end

	_G.HakiV2.getMiscFlag = function(flagName)
		local ok, result = pcall(function()
			local misc = LocalPlayer.PlayerStats:FindFirstChild("Misc")
			if not misc then
				return false
			end
			local data = HttpService:JSONDecode(tostring(misc.Value or ""))
			if type(data) ~= "table" then
				return false
			end
			local v = data[flagName]
			return v == true or v == "true" or v == 1
		end)
		return ok and result == true
	end

	_G.HakiV2.hasBusoV2 = function()
		return _G.HakiV2.getMiscFlag("Armament")
	end

	_G.HakiV2.hasObservationV2 = function()
		return _G.HakiV2.getMiscFlag("Observation")
	end

	_G.HakiV2.isArmamentMaxed = function()
		local ok, maxed = pcall(function()
			local leveling = LocalPlayer:FindFirstChild("Leveling")
			if not leveling then
				return false
			end
			local armament = leveling:FindFirstChild("Armament")
			if not armament then
				return false
			end
			local level = armament:GetAttribute("Level")
			local maxLevel = armament:GetAttribute("MaxLevel")
			if level == nil or maxLevel == nil then
				return false
			end
			return tonumber(level) >= tonumber(maxLevel)
		end)
		return ok and maxed == true
	end

	_G.HakiV2.getBusoV2State = function()
		if _G.HakiV2.hasBusoV2() then
			return "done"
		end
		if _G.HakiV2.getMiscFlag("Back to Lee") then
			return "buy_buso_v2"
		end
		if _G.HakiV2.getMiscFlag("Find Pung") then
			if not _G.HakiV2.getMiscFlag("Pung Proof") then
				return "talk_pung_1"
			end
			if not _G.HakiV2.getMiscFlag("Pung Happy") then
				return "kill_darkbeard"
			end
			if not _G.HakiV2.getMiscFlag("Pung Diamond") then
				return "talk_pung_2"
			end
			return "talk_lee"
		end
		if not _G.HakiV2.isArmamentMaxed() then
			return "idle"
		end
		return "talk_lee_start"
	end

	_G.HakiV2.canBuyBusoV2 = function()
		local ok, can = pcall(function()
			local lvl = LocalPlayer.PlayerStats.lvl.Value
			if lvl < 3600 then
				return false
			end
			if _G.HakiV2.getBeli() < 35000000 then
				return false
			end
			if not _G.HakiV2.isArmamentMaxed() then
				return false
			end
			return true
		end)
		return ok and can == true
	end

	_G.HakiV2.getObservationV2State = function()
		if _G.HakiV2.hasObservationV2() then
			return "done"
		end
		if not _G.HakiV2.hasBusoV2() then
			return "idle"
		end
		if _G.HakiV2.getMiscFlag("Stranger Uncle Happy") then
			return "buy_observation"
		end
		if _G.HakiV2.getMiscFlag("Stranger Uncle Proof") then
			return "kill_leepung"
		end
		return "talk_stranger_start"
	end

	_G.HakiV2.canBuyObservationV2 = function()
		local ok, can = pcall(function()
			local lvl = LocalPlayer.PlayerStats.lvl.Value
			if lvl < 3600 then
				return false
			end
			if _G.HakiV2.getBeli() < 45000000 then
				return false
			end
			if not _G.HakiV2.hasBusoV2() then
				return false
			end
			return true
		end)
		return ok and can == true
	end

	_G.HakiV2.getNpcCFrame = function(npcName)
		local ok, cf = pcall(function()
			local allNpc = Workspace:FindFirstChild("AllNPC")
			if allNpc then
				local npc = allNpc:FindFirstChild(npcName)
				if npc then
					if npc:IsA("Model") then
						return npc:GetPivot()
					end
					if npc:IsA("BasePart") then
						return npc.CFrame
					end
					local part = npc:FindFirstChildWhichIsA("BasePart", true)
					if part then
						return part.CFrame
					end
				end
			end
			local rsNpc = ReplicatedStorage:FindFirstChild("NPC")
			if rsNpc then
				local npc = rsNpc:FindFirstChild(npcName)
				if npc then
					if npc:IsA("Model") then
						return npc:GetPivot()
					end
					if npc:IsA("BasePart") then
						return npc.CFrame
					end
					local part = npc:FindFirstChildWhichIsA("BasePart", true)
					if part then
						return part.CFrame
					end
				end
			end
			return nil
		end)
		return ok and cf or nil
	end

	_G.HakiV2.openDialogue = function(npcName)
		pcall(function()
			local allNpc = Workspace:FindFirstChild("AllNPC")
			local npc = allNpc and allNpc:FindFirstChild(npcName)
			if not npc then
				local rs = ReplicatedStorage:FindFirstChild("NPC")
				npc = rs and rs:FindFirstChild(npcName)
			end
			if npc then
				ReplicatedStorage.Chest.Remotes.Functions.CheckQuest:InvokeServer(npc)
			end
		end)
	end

	_G.HakiV2.clickAccept = function(npcName)
		local ok, fired = pcall(function()
			local gui = LocalPlayer.PlayerGui:FindFirstChild(npcName)
				or LocalPlayer.PlayerGui:FindFirstChild(npcName .. "Shop")
			if not gui then
				for _, g in pairs(LocalPlayer.PlayerGui:GetChildren()) do
					local dialogue = g:FindFirstChild("Dialogue")
					if dialogue then
						local accept = dialogue:FindFirstChild("Accept")
						if accept and accept:IsA("GuiButton") then
							gui = g
							break
						end
					end
				end
			end
			if not gui then
				return
			end
			local dialogue = gui:FindFirstChild("Dialogue")
			if not dialogue then
				return
			end
			local accept = dialogue:FindFirstChild("Accept")
			if not accept or not accept:IsA("GuiButton") then
				return false
			end
			return _G._GenesisDispatchGuiButton(accept)
		end)
		return ok and fired == true
	end

	_G.HakiV2.findDarkBeardBoss = function()
		local bossFolder = Workspace:FindFirstChild("Monster") and Workspace.Monster:FindFirstChild("Boss")
		if not bossFolder then
			return nil
		end
		for _, mob in pairs(bossFolder:GetChildren()) do
			if
				mob:FindFirstChild("Humanoid")
				and mob.Humanoid.Health > 0
				and mob:FindFirstChild("HumanoidRootPart")
				and string.find(mob.Name, "Dark Beard")
				and not string.find(mob.Name, "Servant")
			then
				return mob
			end
		end
		return nil
	end

	_G.HakiV2.findDarkBeardTotemMobs = function()
		local result = {}
		for _, folder in pairs(Workspace.Monster:GetChildren()) do
			if folder:IsA("Folder") then
				for _, mob in pairs(folder:GetChildren()) do
					if
						mob:FindFirstChild("Humanoid")
						and mob.Humanoid.Health > 0
						and mob:FindFirstChild("HumanoidRootPart")
					then
						if string.find(mob.Name, "Dark Beard Servant") or string.find(mob.Name, "Supreme Swordman") then
							table.insert(result, mob)
						end
					end
				end
			end
		end
		return result
	end

	_G.HakiV2.spawnDarkBeardBoss = function()
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("QuestSpawnBoss", {
				SuccessQuest = "Quest Accepted.",
				BossName = "Dark Beard [Lv. 3475]",
				LevelNeed = 3475,
				QuestName = "Kill 1 Dark Beard",
				MaterialNeed = "Dark Beard's Totem",
				AI_Name = "Dark Beard",
				LevelLow = "You must be Level 3,475 to accept this quest.",
			})
		end)
	end

	_G.HakiV2.findLeePungBoss = function()
		local bossFolder = Workspace:FindFirstChild("Monster") and Workspace.Monster:FindFirstChild("Boss")
		if not bossFolder then
			return nil
		end
		for _, mob in pairs(bossFolder:GetChildren()) do
			if
				mob:FindFirstChild("Humanoid")
				and mob.Humanoid.Health > 0
				and mob:FindFirstChild("HumanoidRootPart")
				and string.find(mob.Name, "LeePung")
			then
				return mob
			end
		end
		return nil
	end

	_G.HakiV2.attackTarget = function(mob)
		if not mob or not mob.Parent then
			return
		end
		local hrp = mob:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end
		usetool()
		buso()
		ken()
		local height = GetSetting("distance") or 8
		local targetCF = CFrame.new(hrp.Position + Vector3.new(0, height, 0), hrp.Position)
		if updateFarmFix then
			updateFarmFix(targetCF, hrp)
		end
		if applyFarmFix and not _G.farmFixThread then
			applyFarmFix(targetCF, hrp)
		end
		_G.pos_skill = hrp.CFrame
		click()
		autoskill()
		if handleOpeMethod then
			handleOpeMethod()
		end
	end

	_G.HakiV2.stopLock = function()
		if _G.HakiV2.lockConn then
			pcall(function()
				_G.HakiV2.lockConn:Disconnect()
			end)
			_G.HakiV2.lockConn = nil
		end
		_G.HakiV2.lockCF = nil
		if _G.HakiV2.bp then
			pcall(function()
				_G.HakiV2.bp:Destroy()
			end)
			_G.HakiV2.bp = nil
		end
		if _G.HakiV2.bg then
			pcall(function()
				_G.HakiV2.bg:Destroy()
			end)
			_G.HakiV2.bg = nil
		end
		pcall(function()
			local hum = GetHumanoid(LocalPlayer.Character)
			if hum then
				hum.PlatformStand = false
			end
		end)
	end

	_G.HakiV2.startLock = function(targetCF)
		_G.HakiV2.stopLock()
		if not targetCF or _G._GenesisDailyReturnRequested then
			return
		end
		_G.HakiV2.lockCF = targetCF * CFrame.new(0, 3, 5)
		local character = LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChild("Humanoid")
		if not root or not humanoid then
			return
		end
		pcall(function()
			humanoid.PlatformStand = true
		end)

		_G.HakiV2.bp = Instance.new("BodyPosition")
		_G.HakiV2.bp.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
		_G.HakiV2.bp.D = 100000
		_G.HakiV2.bp.P = 1000000
		_G.HakiV2.bp.Parent = root

		_G.HakiV2.bg = Instance.new("BodyGyro")
		_G.HakiV2.bg.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
		_G.HakiV2.bg.D = 50000
		_G.HakiV2.bg.P = 500000
		_G.HakiV2.bg.Parent = root

		_G.HakiV2.lockConn = trackGenesisConnection(RunService.Heartbeat:Connect(function()
			pcall(function()
				if not (_G.isProgressingBusoV2 or _G.isProgressingObservationV2) then
					_G.HakiV2.stopLock()
					return
				end
				if not root or not root.Parent or not _G.HakiV2.lockCF then
					_G.HakiV2.stopLock()
					return
				end
				if _G.HakiV2.bp and _G.HakiV2.bp.Parent then
					_G.HakiV2.bp.Position = _G.HakiV2.lockCF.Position
				end
				if _G.HakiV2.bg and _G.HakiV2.bg.Parent then
					_G.HakiV2.bg.CFrame = _G.HakiV2.lockCF
				end
				root.CFrame = _G.HakiV2.lockCF
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
		end))
	end

	_G.HakiV2.teleportSea2 = function()
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Functions.EtcFunction:InvokeServer("TeleportSea", { SeaName = "SecondSea" })
		end)
	end

	-- BUSO V2 LOOP
	spawn(function()
		local lastDialogueAttempt = 0
		local lastSeaHop = 0
		local currentStep = nil
		local lastSpawnAttempt = 0
		local H = _G.HakiV2

		while task.wait(0.35) do
			pcall(function()
				if _G._GenesisDailyReturnRequested then
					_G.isProgressingBusoV2 = false
					H.stopLock()
					return
				end
				if not GetSetting("autoBusoV2") then
					if _G.isProgressingBusoV2 then
						_G.isProgressingBusoV2 = false
						H.stopLock()
						removeFarmFix()
					end
					_G.busoV2Status = "Off"
					return
				end

				local state = H.getBusoV2State()

				if state == "done" then
					if _G.isProgressingBusoV2 then
						_G.isProgressingBusoV2 = false
						H.stopLock()
						removeFarmFix()
						SpectrumX:Notify({ Title = "BUSO V2", Text = "Unlocked!", Type = "success", Duration = 4 })
					end
					_G.busoV2Status = "Done \226\156\133"
					return
				end

				if state == "idle" then
					_G.isProgressingBusoV2 = false
					H.stopLock()
					_G.busoV2Status = "Waiting Armament max"
					return
				end

				if game.PlaceId ~= H.SEA2 then
					local shouldGo = (state == "talk_lee_start" and H.isArmamentMaxed())
						or (state == "buy_buso_v2" and H.canBuyBusoV2())
						or (state ~= "talk_lee_start" and state ~= "buy_buso_v2" and state ~= "idle")
					if shouldGo then
						_G.isProgressingBusoV2 = true
						_G.busoV2Status = "Going Sea 2..."
						if tick() - lastSeaHop > 8 then
							lastSeaHop = tick()
							H.teleportSea2()
						end
					else
						_G.isProgressingBusoV2 = false
						_G.busoV2Status = "Waiting reqs (other sea)"
					end
					return
				end

				_G.isProgressingBusoV2 = true

				if state == "talk_lee_start" then
					currentStep = "talk_lee_start"
					removeFarmFix()
					_G.busoV2Status = "Lee (start quest)"
					local npcCF = H.getNpcCFrame("Lee")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.2 then
						lastDialogueAttempt = tick()
						H.openDialogue("Lee")
						task.wait(0.4)
						H.clickAccept("Lee")
						task.wait(0.2)
						H.clickAccept("Lee")
					end
					return
				end

				if state == "talk_pung_1" then
					currentStep = "talk_pung_1"
					removeFarmFix()
					_G.busoV2Status = "Pung (1/4)"
					local npcCF = H.getNpcCFrame("Pung")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.2 then
						lastDialogueAttempt = tick()
						H.openDialogue("Pung")
						task.wait(0.4)
						H.clickAccept("Pung")
						task.wait(0.2)
						H.clickAccept("Pung")
					end
					return
				end

				if state == "kill_darkbeard" then
					currentStep = "kill_darkbeard"
					H.stopLock()
					_G.busoV2Status = "Kill Dark Beard"
					local boss = H.findDarkBeardBoss()
					if boss then
						H.attackTarget(boss)
					else
						local totem = 0
						pcall(function()
							local mat = LocalPlayer.PlayerStats:FindFirstChild("Material")
							if mat then
								local data = HttpService:JSONDecode(tostring(mat.Value))
								totem = tonumber(data and data["Dark Beard's Totem"]) or 0
							end
						end)
						if totem >= 1 and tick() - lastSpawnAttempt > 3 then
							lastSpawnAttempt = tick()
							tp(H.DARK_BEARD_AREA)
							task.wait(0.3)
							H.spawnDarkBeardBoss()
						else
							local totems = H.findDarkBeardTotemMobs()
							if #totems > 0 then
								H.attackTarget(totems[1])
							else
								removeFarmFix()
								tp(H.DARK_BEARD_AREA)
							end
						end
					end
					return
				end

				if state == "talk_pung_2" then
					currentStep = "talk_pung_2"
					removeFarmFix()
					_G.busoV2Status = "Pung (3/4)"
					local npcCF = H.getNpcCFrame("Pung")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.2 then
						lastDialogueAttempt = tick()
						H.openDialogue("Pung")
						task.wait(0.4)
						H.clickAccept("Pung")
						task.wait(0.2)
						H.clickAccept("Pung")
					end
					return
				end

				if state == "talk_lee" then
					currentStep = "talk_lee"
					removeFarmFix()
					_G.busoV2Status = "Lee (finish quest)"
					local npcCF = H.getNpcCFrame("Lee")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.2 then
						lastDialogueAttempt = tick()
						H.openDialogue("Lee")
						task.wait(0.4)
						H.clickAccept("Lee")
						task.wait(0.2)
						H.clickAccept("Lee")
					end
					return
				end

				if state == "buy_buso_v2" then
					if not H.canBuyBusoV2() then
						_G.isProgressingBusoV2 = false
						H.stopLock()
						removeFarmFix()
						local lvl = 0
						pcall(function()
							lvl = LocalPlayer.PlayerStats.lvl.Value
						end)
						_G.busoV2Status =
							string.format("Wait Lv%d/3600 | %dM/35M", lvl, math.floor(H.getBeli() / 1000000))
						return
					end
					if currentStep ~= "buy_buso_v2" then
						currentStep = "buy_buso_v2"
						lastDialogueAttempt = 0
						H.stopLock()
						removeFarmFix()
						pcall(function()
							local hum = GetHumanoid(LocalPlayer.Character)
							if hum then
								hum.Health = 0
							end
						end)
						task.wait(3.5)
					end
					_G.busoV2Status = "Buying Buso V2"
					local npcCF = H.getNpcCFrame("Lee")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.5 then
						lastDialogueAttempt = tick()
						H.openDialogue("Lee")
						task.wait(0.4)
						H.clickAccept("Lee")
						task.wait(0.25)
						H.clickAccept("Lee")
						task.wait(0.25)
						H.clickAccept("Lee")
					end
					return
				end
			end)
		end
	end)

	-- KEN V2 / OBSERVATION LOOP
	spawn(function()
		local lastDialogueAttempt = 0
		local lastSeaHop = 0
		local currentStep = nil
		local H = _G.HakiV2

		while task.wait(0.35) do
			pcall(function()
				if _G._GenesisDailyReturnRequested then
					_G.isProgressingObservationV2 = false
					H.stopLock()
					return
				end
				if not GetSetting("autoKenV2") then
					if _G.isProgressingObservationV2 then
						_G.isProgressingObservationV2 = false
						if not _G.isProgressingBusoV2 then
							H.stopLock()
							removeFarmFix()
						end
					end
					_G.kenV2Status = "Off"
					return
				end

				if _G.isProgressingBusoV2 then
					_G.kenV2Status = "Waiting Buso V2..."
					return
				end

				local state = H.getObservationV2State()

				if state == "done" then
					if _G.isProgressingObservationV2 then
						_G.isProgressingObservationV2 = false
						H.stopLock()
						removeFarmFix()
						SpectrumX:Notify({
							Title = "KEN V2",
							Text = "Observation Unlocked!",
							Type = "success",
							Duration = 4,
						})
					end
					_G.kenV2Status = "Done \226\156\133"
					return
				end

				if state == "idle" then
					_G.isProgressingObservationV2 = false
					_G.kenV2Status = "Need Buso V2 first"
					return
				end

				if game.PlaceId ~= H.SEA2 then
					local shouldGo = (state == "buy_observation" and H.canBuyObservationV2())
						or (state ~= "buy_observation")
					if shouldGo then
						_G.isProgressingObservationV2 = true
						_G.kenV2Status = "Going Sea 2..."
						if tick() - lastSeaHop > 8 then
							lastSeaHop = tick()
							H.teleportSea2()
						end
					else
						_G.isProgressingObservationV2 = false
						_G.kenV2Status = "Waiting reqs"
					end
					return
				end

				_G.isProgressingObservationV2 = true

				if state == "talk_stranger_start" then
					currentStep = "talk_stranger_start"
					removeFarmFix()
					_G.kenV2Status = "Stranger Uncle (start)"
					local npcCF = H.getNpcCFrame("Stranger Uncle")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.2 then
						lastDialogueAttempt = tick()
						H.openDialogue("Stranger Uncle")
						task.wait(0.4)
						H.clickAccept("Stranger Uncle")
						task.wait(0.2)
						H.clickAccept("Stranger Uncle")
					end
					return
				end

				if state == "kill_leepung" then
					currentStep = "kill_leepung"
					H.stopLock()
					_G.kenV2Status = "Kill LeePung"
					local boss = H.findLeePungBoss()
					if boss then
						H.attackTarget(boss)
					else
						removeFarmFix()
						local npcCF = H.getNpcCFrame("Stranger Uncle")
						if npcCF then
							H.startLock(npcCF)
						end
						if tick() - lastDialogueAttempt > 1.5 then
							lastDialogueAttempt = tick()
							H.openDialogue("Stranger Uncle")
							task.wait(0.4)
							H.clickAccept("Stranger Uncle")
							task.wait(0.2)
							H.clickAccept("Stranger Uncle")
						end
					end
					return
				end

				if state == "buy_observation" then
					if not H.canBuyObservationV2() then
						_G.isProgressingObservationV2 = false
						H.stopLock()
						removeFarmFix()
						local lvl = 0
						pcall(function()
							lvl = LocalPlayer.PlayerStats.lvl.Value
						end)
						_G.kenV2Status =
							string.format("Wait Lv%d/3600 | %dM/45M", lvl, math.floor(H.getBeli() / 1000000))
						return
					end
					if currentStep ~= "buy_observation" then
						currentStep = "buy_observation"
						lastDialogueAttempt = 0
						H.stopLock()
						removeFarmFix()
					end
					_G.kenV2Status = "Buying Ken V2"
					local npcCF = H.getNpcCFrame("Stranger Uncle")
					if npcCF then
						H.startLock(npcCF)
					end
					if tick() - lastDialogueAttempt > 1.5 then
						lastDialogueAttempt = tick()
						H.openDialogue("Stranger Uncle")
						task.wait(0.4)
						H.clickAccept("Stranger Uncle")
						task.wait(0.25)
						H.clickAccept("Stranger Uncle")
						task.wait(0.25)
						H.clickAccept("Stranger Uncle")
					end
					return
				end
			end)
		end
	end)

	-- ========== RAID / AUTO DUNGEON (Raid tab) ==========
	-- Keep everything in _G.Raid to avoid exceeding the local-variable limit.

	_G.Raid = _G.Raid or {}
	_G.Raid.inraid = false
	_G.Raid.inop = false
	_G.Raid.current_floor = 1
	_G.Raid.last_floor = 1
	_G.Raid.boss_dungeon = false
	_G.Raid.current_target = nil
	_G.Raid.dodge_active = false
	_G.Raid.dodge_render_step_name = "GenesisDungeonDodge_" .. tostring(LocalPlayer.UserId)
	_G.Raid.dodge_gyro = nil
	_G.Raid.last_tool_switch = 0
	_G.Raid.last_buso = 0
	_G.Raid.last_ken = 0
	_G.Raid.last_click = 0
	_G.Raid.last_skill = 0
	_G.Raid.last_hao = 0
	_G.Raid.has_opop = false
	_G.Raid.is_zoan = false
	_G.Raid.transformed = false
	_G.Raid._mainLoopBusy = false
	_G.Raid._entryBusy = false
	_G.Raid._entryGeneration = 0
	_G.Raid._loadoutBusy = false
	_G.Raid._loadoutGeneration = 0
	_G.Raid._floorSettleUntil = 0
	_G.Raid.farmFix = {
		pos = nil,
		gyro = nil,
		thread = nil,
		target = nil,
		root = nil,
		generation = 0,
		bound = false,
		renderStepName = "GenesisDungeonFarm_" .. tostring(LocalPlayer.UserId),
	}
	_G.Raid.orbit = { active = false, thread = nil, angle = 0, target = nil, radius = 18 }
	_G.Raid.attackState = {
		generation = 0,
		jobs = {},
		nextJobId = 0,
		-- The known-good dungeon baseline issued one valid M1 every render step.
		-- Keep this implementation bounded, but do not throttle it down to roughly
		-- ten attacks per second: four in-flight requests at a 25 ms cadence retain
		-- responsive damage without recreating the baseline's invalid FS/SW/DF spam.
		-- A live Hard-dungeon trial measured about 20 valid M1s/second with this bound
		-- and no request timeouts, versus roughly 11/second with two in flight.
		m1Interval = 0.025,
		m1Lease = 0.8,
		requestedUntil = 0,
		lastM1 = 0,
		m1InFlight = 0,
		maxM1InFlight = 4,
		skillInterval = 0.08,
		lastSkillDispatch = 0,
		skillInFlight = 0,
		maxSkillInFlight = 1,
		skillCursor = 0,
		skillReadyAt = {},
		toolReadyAt = 0,
		opeToolUntil = 0,
		m1Dispatched = 0,
		skillsDispatched = 0,
		m1ByTool = {},
		skillsByTool = {},
		lastM1Tool = nil,
		lastSkillId = nil,
		timedOut = 0,
		lastTimeoutAt = nil,
		lastError = nil,
		remoteJobs = {},
		nextRemoteJobId = 0,
		remoteInFlight = 0,
		maxRemoteInFlight = 6,
		remoteTimeout = 1.25,
		remoteCompleted = 0,
		remoteTimedOut = 0,
		remoteRejected = 0,
		remoteTimeoutBySkill = {},
		maxRemoteLatency = 0,
		lastRemoteError = nil,
	}
	_G.Raid.skillDataCache = {}
	_G.Raid.dungeonBounds = { model = nil, center = nil, size = nil, checkedAt = 0 }
	_G.Raid.lastHealth = nil
	_G.Raid.lastDamageAt = 0
	_G.Raid.lastDamageAmount = 0
	_G.Raid.raceAbility = {
		lastAttempt = 0,
		pendingUntil = 0,
		activeUntil = 0,
		cooldownUntil = 0,
		auraSeen = false,
		auraEnded = false,
		auraLastSeenAt = 0,
		auraCheckedAt = 0,
		auraCached = false,
		auraObject = nil,
		healthBefore = nil,
		humanoid = nil,
		hudWasPresent = false,
		inputBusy = false,
		attempts = 0,
		confirmed = 0,
		lastResult = "idle",
	}
	_G.Raid.opeState = { phase = "idle", lastToggle = 0, ownedRoom = false }
	_G.Raid.effectFirstSeen = {}
	_G.Raid.EFFECT_MAX_AGE = 2.2
	_G.Raid.attackPatterns = {
		"gravity",
		"meteo",
		"warning",
		"love",
		"arrow",
		"icespike",
		"icecube",
		"icepath",
		"flameball",
		"flamepillar",
		"flamefist",
		"bullet",
		"heartz",
		"harrow",
		"lightparticlepart",
		"pierce",
		"darkball",
		"blackhole",
		"firemoth",
		-- Chaos Crab attacks without a generic "warning" wrapper.
		"crabs1",
		"circ",
		"pillar_exp",
		"waterball",
		"letterbox",
		"camrigwithletterbox",
	}
	_G.Raid.dungeonBosses = {
		"Gravity Warden",
		"Ice Warden",
		"Flame Warden",
		"Dark Warden",
		"Craberno",
		"Chaos Crab",
		"Firelord",
		"Heartbreaker Queen",
		"Veyzor",
	}
	_G.Raid.getRoot = function(char)
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	_G.Raid.downwardCFrame = function(position)
		-- CFrame.new(position, position - Y) has an undefined roll because its
		-- default up vector is parallel to the look direction. Build a stable basis
		-- explicitly so LookVector remains exactly (0, -1, 0).
		return CFrame.fromMatrix(
			position,
			Vector3.new(1, 0, 0),
			Vector3.new(0, 0, -1),
			Vector3.new(0, 1, 0)
		)
	end

	_G.Raid.tp = function(cf)
		if typeof(cf) ~= "CFrame" then
			return false
		end
		local ok = pcall(function()
			LocalPlayer.Character.HumanoidRootPart.CFrame = cf
		end)
		return ok
	end

	_G.Raid.tooltip = function(toolTip)
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		local backpack = LocalPlayer:FindFirstChild("Backpack")
		if not character or not humanoid or not backpack then
			return nil
		end

		local equipped = _G.Raid.getEquippedTool and _G.Raid.getEquippedTool()
		if equipped and equipped.ToolTip == toolTip then
			if toolTip ~= "Sword" or not string.find(string.lower(equipped.Name), "rod", 1, true) then
				return equipped
			end
		end

		local candidates = {}
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.ToolTip == toolTip then
				if toolTip ~= "Sword" or not string.find(string.lower(tool.Name), "rod", 1, true) then
					table.insert(candidates, tool)
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.Name < b.Name
		end)

		local chosen = nil
		if toolTip == "Sword" then
			local preferredName = _G.lastEquippedSwordName
				or _G.fishingPreviousWeaponName
				or GetSetting("lastEquippedSwordName")
			for _, candidate in ipairs(candidates) do
				if candidate.Name == preferredName then
					chosen = candidate
					break
				end
			end
		end
		chosen = chosen or candidates[1]
		if not chosen then
			return nil
		end

		humanoid:EquipTool(chosen)
		if chosen.Parent ~= character then
			return nil
		end
		if toolTip == "Sword" and _G._GenesisRememberSword then
			_G._GenesisRememberSword(chosen)
		end
		_G.Raid.attackState.toolReadyAt = os.clock() + 0.08
		return chosen
	end

	_G.Raid.finishAttackJob = function(job, timedOut, err)
		if not job or job.finished then
			return
		end
		job.finished = true
		local state = _G.Raid.attackState
		state.jobs[job.id] = nil
		if job.kind == "m1" then
			state.m1InFlight = math.max(0, state.m1InFlight - 1)
		else
			state.skillInFlight = math.max(0, state.skillInFlight - 1)
		end
		if timedOut then
			state.timedOut = state.timedOut + 1
			state.lastTimeoutAt = os.clock()
		end
		-- A bounded request timeout is recovery telemetry, not a fatal automation
		-- error. Preserve lastError for actual implementation failures.
		if err and not timedOut then
			state.lastError = tostring(err)
		end
	end

	_G.Raid.startAttackJob = function(kind, callback, timeout)
		local state = _G.Raid.attackState
		local counterName = kind == "m1" and "m1InFlight" or "skillInFlight"
		local maximum = kind == "m1" and state.maxM1InFlight or state.maxSkillInFlight
		if state[counterName] >= maximum then
			return false
		end

		state.nextJobId = state.nextJobId + 1
		local job = {
			id = state.nextJobId,
			kind = kind,
			generation = state.generation,
			finished = false,
			thread = nil,
		}
		state.jobs[job.id] = job
		state[counterName] = state[counterName] + 1
		job.thread = task.spawn(function()
			local ok, err = pcall(callback)
			_G.Raid.finishAttackJob(job, false, ok and nil or err)
		end)
		task.delay(timeout or 3, function()
			if not job.finished then
				if job.thread then
					pcall(task.cancel, job.thread)
				end
				_G.Raid.finishAttackJob(job, true, "attack request timed out")
			end
		end)
		return true
	end

	_G.Raid.getEquippedTool = function()
		local char = LocalPlayer.Character
		if not char then
			return nil
		end
		for _, tool in ipairs(char:GetChildren()) do
			if tool:IsA("Tool")
				and (tool.ToolTip == "Sword" or tool.ToolTip == "Combat" or tool.ToolTip == "Fruit Power")
			then
				return tool
			end
		end
		return nil
	end

	_G.Raid.isUsableDungeonTool = function(tool, wantedTip)
		if not tool or not tool:IsA("Tool") or (wantedTip and tool.ToolTip ~= wantedTip) then
			return false
		end
		return tool.ToolTip ~= "Sword" or not string.find(string.lower(tool.Name), "rod", 1, true)
	end

	_G.Raid.getConfiguredToolTips = function()
		local configured = GetSetting("dungeon_outside_tools") or { "Combat", "Fruit Power" }
		local result, seen = {}, {}
		for key, value in pairs(configured) do
			local tip = (type(key) == "string" and value == true) and key or value
			if tip == "Mele" then
				tip = "Combat"
			elseif tip == "Fruit" then
				tip = "Fruit Power"
			end
			if (tip == "Sword" or tip == "Combat" or tip == "Fruit Power") and not seen[tip] then
				seen[tip] = true
				table.insert(result, tip)
			end
		end
		return result
	end

	_G.Raid.findToolByTip = function(toolTip)
		local character = LocalPlayer.Character
		local backpack = LocalPlayer:FindFirstChild("Backpack")
		local current = _G.Raid.getEquippedTool()
		if _G.Raid.isUsableDungeonTool(current, toolTip) then
			return current
		end

		local candidates = {}
		for _, container in ipairs({ character, backpack }) do
			if container then
				for _, tool in ipairs(container:GetChildren()) do
					if _G.Raid.isUsableDungeonTool(tool, toolTip) then
						table.insert(candidates, tool)
					end
				end
			end
		end
		table.sort(candidates, function(a, b)
			return a.Name < b.Name
		end)

		if toolTip == "Sword" then
			local preferredName = _G.lastEquippedSwordName
				or _G.fishingPreviousWeaponName
				or GetSetting("lastEquippedSwordName")
			for _, candidate in ipairs(candidates) do
				if candidate.Name == preferredName then
					return candidate
				end
			end
		end
		return candidates[1]
	end

	_G.Raid.getConfiguredTools = function()
		local result = {}
		for _, tip in ipairs(_G.Raid.getConfiguredToolTips()) do
			local tool = _G.Raid.findToolByTip(tip)
			if tool then
				table.insert(result, tool)
			end
		end
		return result
	end

	_G.Raid.getBaseCombatTool = function()
		local enabled = {}
		for _, tip in ipairs(_G.Raid.getConfiguredToolTips()) do
			enabled[tip] = true
		end
		-- Swords and fighting styles expose a real M1. Fruit tools such as Dough
		-- do not, so a fruit must not replace the persistent basic-attack weapon.
		for _, preferredTip in ipairs({ "Sword", "Combat" }) do
			if enabled[preferredTip] then
				local tool = _G.Raid.findToolByTip(preferredTip)
				if tool then
					return tool
				end
			end
		end
		return nil
	end

	_G.Raid.hasConfiguredBasicAttack = function()
		for _, tip in ipairs(_G.Raid.getConfiguredToolTips()) do
			if tip == "Sword" or tip == "Combat" then
				return true
			end
		end
		return false
	end

	_G.Raid.ensureBaseCombatTool = function()
		-- Opening/closing an Ope room is the only remote-cast operation that must
		-- temporarily own the character's hand. Do not immediately evict OpOp while
		-- its Z request is being dispatched.
		if os.clock() < (_G.Raid.attackState.opeToolUntil or 0) then
			return nil
		end
		local tool = _G.Raid.getBaseCombatTool()
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = LocalPlayer:FindFirstChild("Backpack")
		if not tool or not humanoid or not backpack then
			return nil
		end
		if tool.Parent ~= character then
			if tool.Parent ~= backpack then
				return nil
			end
			humanoid:EquipTool(tool)
			if tool.Parent ~= character then
				return nil
			end
			_G.Raid.attackState.toolReadyAt = os.clock() + 0.08
		end
		if tool.ToolTip == "Sword" and _G._GenesisRememberSword then
			_G._GenesisRememberSword(tool)
		end
		return tool
	end

	_G.Raid.bootstrapBaseCombatTool = function(timeoutSeconds, shouldContinue)
		local existing = _G.Raid.ensureBaseCombatTool()
		if existing then
			return existing
		end

		local enabled = {}
		for _, tip in ipairs(_G.Raid.getConfiguredToolTips()) do
			enabled[tip] = true
		end

		-- A sword may be selected in the game's Primary slot without its Tool being
		-- replicated into Character/Backpack yet. Restore the exact remembered sword
		-- through the same validated inventory transaction used by fishing.
		if enabled.Sword then
			local preferredName = _G._GenesisWaitForLastEquippedSwordName
				and _G._GenesisWaitForLastEquippedSwordName(timeoutSeconds or 4, shouldContinue)
				or _G.lastEquippedSwordName
			if _G._GenesisIsUsableSwordName(preferredName) then
				local selected = selectPrimaryWeapon(preferredName, timeoutSeconds or 4, shouldContinue)
				local character = LocalPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if selected and humanoid and selected.Parent ~= character then
					humanoid:EquipTool(selected)
				end
				if _G._GenesisIsSwordTool(selected) and selected.Parent == character then
					_G._GenesisRememberSword(selected)
					_G.Raid.attackState.toolReadyAt = os.clock() + 0.08
					return selected
				end
			end
		end

		-- Combat styles do not use the Primary sword slot and can be equipped
		-- directly if the user selected one as the dungeon M1 source.
		if enabled.Combat then
			return _G.Raid.ensureBaseCombatTool()
		end
		return nil
	end

	_G.Raid.beginLoadoutBootstrap = function()
		if _G.Raid._loadoutBusy or not GetSetting("auto_dungeon_v2") then
			return false
		end
		_G.Raid._loadoutBusy = true
		_G.Raid._loadoutGeneration = (_G.Raid._loadoutGeneration or 0) + 1
		local generation = _G.Raid._loadoutGeneration
		task.spawn(function()
			local ok, err = pcall(function()
				_G.Raid.bootstrapBaseCombatTool(4, function()
					return GetSetting("auto_dungeon_v2") and _G.Raid._loadoutGeneration == generation
				end)
			end)
			if not ok then
				_G.Raid.attackState.lastError = "dungeon loadout bootstrap failed: " .. tostring(err)
			end
			if _G.Raid._loadoutGeneration == generation then
				_G.Raid._loadoutBusy = false
			end
		end)
		return true
	end

	_G.Raid.getSkillPrefix = function(tool)
		if not tool then
			return "SW_"
		end
		local tip = tool.ToolTip
		if tip == "Sword" then
			return "SW_"
		elseif tip == "Combat" then
			return "FS_"
		elseif tip == "Fruit Power" then
			return "DF_"
		end
		return "SW_"
	end

	_G.Raid.keyboard = function(key)
		VirtualInputManager:SendKeyEvent(true, key, false, game)
		task.wait(0.06)
		VirtualInputManager:SendKeyEvent(false, key, false, game)
	end

	_G.Raid.finishRemoteJob = function(job, timedOut, err)
		if not job or job.finished then
			return
		end
		job.finished = true
		local state = _G.Raid.attackState
		state.remoteJobs[job.id] = nil
		state.remoteInFlight = math.max(0, state.remoteInFlight - 1)
		local latency = os.clock() - job.startedAt
		state.maxRemoteLatency = math.max(state.maxRemoteLatency or 0, latency)
		if timedOut then
			state.remoteTimedOut = state.remoteTimedOut + 1
			state.remoteTimeoutBySkill[job.skillName] = (state.remoteTimeoutBySkill[job.skillName] or 0) + 1
		elseif err then
			state.lastRemoteError = tostring(err)
		else
			state.remoteCompleted = state.remoteCompleted + 1
		end
	end

	_G.Raid.invokeSkillPhase = function(skillName, args, phase)
		local state = _G.Raid.attackState
		if state.remoteInFlight >= state.maxRemoteInFlight then
			state.remoteRejected = state.remoteRejected + 1
			return false
		end

		state.nextRemoteJobId = state.nextRemoteJobId + 1
		local job = {
			id = state.nextRemoteJobId,
			skillName = skillName,
			phase = phase,
			startedAt = os.clock(),
			finished = false,
			thread = nil,
		}
		state.remoteJobs[job.id] = job
		state.remoteInFlight = state.remoteInFlight + 1
		job.thread = task.spawn(function()
			local ok, err = pcall(function()
				ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(skillName, args)
			end)
			_G.Raid.finishRemoteJob(job, false, ok and nil or err)
		end)
		task.delay(state.remoteTimeout, function()
			if not job.finished then
				if job.thread then
					pcall(task.cancel, job.thread)
				end
				_G.Raid.finishRemoteJob(job, true, "skill phase timed out")
			end
		end)
		return true
	end

	_G.Raid.remoteSkill = function(tool, key, pos)
		local skillName = _G.Raid.getSkillPrefix(tool) .. tool.Name .. "_" .. key
		if not _G.Raid.invokeSkillPhase(skillName, { MouseHit = pos, Type = "Down" }, "Down") then
			error("skill phase pool is full")
		end
		task.wait(0.06)
		if not _G.Raid.invokeSkillPhase(skillName, { MouseHit = pos, Type = "Up" }, "Up") then
			error("skill phase pool is full")
		end
	end

	_G.Raid.remoteOpeToggle = function(tool, pos, phase)
		local skillName = "DF_" .. tool.Name .. "_Z"
		if not _G.Raid.invokeSkillPhase(skillName, { MouseHit = pos, Type = "Down" }, "Down") then
			error("Ope Z down phase pool is full")
		end

		-- OpOp's real client does not tap Z like an ordinary skill. When opening a
		-- room it holds the Down phase until OpeRoom<player> replicates, bounded by
		-- ten seconds, and only then releases Up. A fixed 0.06-second tap commonly
		-- leaves the dungeon worker parked without a usable room.
		if phase == "opening" then
			local deadline = os.clock() + 10
			repeat
				task.wait()
			until _G.Raid.getOpeRoom()
				or os.clock() >= deadline
				or not GetSetting("auto_dungeon_v2")
				or not tool.Parent
		else
			-- With an existing room, the real client reaches its release condition on
			-- the next heartbeat; closing must not inherit the ten-second open hold.
			task.wait()
		end

		-- Keep the release bounded but give it a brief chance to acquire a phase
		-- slot if the Down invocation has not retired from the pool yet.
		local releaseDeadline = os.clock() + 0.5
		repeat
			if _G.Raid.invokeSkillPhase(skillName, { MouseHit = pos, Type = "Up" }, "Up") then
				return
			end
			task.wait()
		until os.clock() >= releaseDeadline
		error("Ope Z up phase pool remained full")
	end

	_G.Raid.getSkillData = function(tool)
		if not tool then
			return nil
		end
		local cacheKey = tool.ToolTip .. "|" .. tool.Name
		local cached = _G.Raid.skillDataCache[cacheKey]
		if cached ~= nil then
			return cached ~= false and cached or nil
		end
		local folderName = tool.ToolTip == "Sword" and "Swords"
			or (tool.ToolTip == "Combat" and "Styles")
			or (tool.ToolTip == "Fruit Power" and "Fruits")
		local skillDataRoot = ReplicatedStorage:FindFirstChild("Chest")
			and ReplicatedStorage.Chest:FindFirstChild("Modules")
			and ReplicatedStorage.Chest.Modules:FindFirstChild("SkillData")
		local folder = folderName and skillDataRoot and skillDataRoot:FindFirstChild(folderName)
		local module = folder and folder:FindFirstChild(tool.Name .. "_Data")
		local ok, data = false, nil
		if module and module:IsA("ModuleScript") then
			ok, data = pcall(require, module)
		end
		if not ok or type(data) ~= "table" then
			_G.Raid.skillDataCache[cacheKey] = false
			return nil
		end
		_G.Raid.skillDataCache[cacheKey] = data
		return data
	end

	_G.Raid.getToolMastery = function(tool)
		local stats = LocalPlayer:FindFirstChild("PlayerStats")
		if not stats or not tool then
			return nil
		end
		local statName = tool.ToolTip == "Sword" and "sword"
			or (tool.ToolTip == "Combat" and "Melee")
			or (tool.ToolTip == "Fruit Power" and "DF")
		local stat = statName and stats:FindFirstChild(statName)
		return stat and tonumber(stat.Value) or nil
	end

	_G.Raid.getSkillCooldown = function(tool, key, data)
		local cooldown = tonumber(data and data[key]) or 1
		local shortPrefix = tool.ToolTip == "Sword" and "SW"
			or (tool.ToolTip == "Combat" and "FS")
			or (tool.ToolTip == "Fruit Power" and "DF")
		if shortPrefix and type(_G.GetCooldownClient) == "function" then
			local ok, adjusted = pcall(_G.GetCooldownClient, shortPrefix .. key)
			if ok and tonumber(adjusted) and tonumber(adjusted) > 0 then
				cooldown = tonumber(adjusted)
			end
		end
		return math.max(0.35, cooldown)
	end

	_G.Raid.dispatchM1 = function()
		local state = _G.Raid.attackState
		local now = os.clock()
		if not GetSetting("auto_dungeon_v2")
			or not _G.Raid.inraid
			or _G.Raid.dodge_retreating
			or now > state.requestedUntil
			or now < state.toolReadyAt
			or now < (state.opeToolUntil or 0)
			or now - state.lastM1 < state.m1Interval
		then
			return false
		end
		local method = GetSetting("dungeon_cast_method") or "Remote (Aimbot)"
		local tool = method == "Remote (Aimbot)" and _G.Raid.ensureBaseCombatTool()
			or _G.Raid.getEquippedTool()
		local pos = _G.pos_skill
		local target = _G.Raid.current_target
		local targetHumanoid = target and target:FindFirstChild("Humanoid")
		if not tool or tool.Parent ~= LocalPlayer.Character or typeof(pos) ~= "CFrame"
			or not targetHumanoid or targetHumanoid.Health <= 0
		then
			return false
		end
		-- Do not report fabricated fruit M1 calls as attacks. Dough, for example,
		-- has skill remotes but no DF_DoughDough_M1 handler.
		if method == "Remote (Aimbot)" and tool.ToolTip ~= "Sword" and tool.ToolTip ~= "Combat" then
			return false
		end
		local prefix = _G.Raid.getSkillPrefix(tool)
		local started = _G.Raid.startAttackJob("m1", function()
			if method == "Remote (Aimbot)" then
				ReplicatedStorage.Chest.Remotes.Functions.SkillAction:InvokeServer(
					prefix .. tool.Name .. "_M1",
					{ MouseHit = pos }
				)
			else
				tool:Activate()
			end
		end, 2.5)
		if started then
			state.lastM1 = now
			state.m1Dispatched = state.m1Dispatched + 1
			state.lastM1Tool = tool.Name
			state.m1ByTool[tool.Name] = (state.m1ByTool[tool.Name] or 0) + 1
		end
		return started
	end

	_G.Raid.click = function()
		local state = _G.Raid.attackState
		state.requestedUntil = os.clock() + state.m1Lease
		return _G.Raid.dispatchM1()
	end

	_G.Raid.autoskill = function()
		local state = _G.Raid.attackState
		local now = os.clock()
		if _G.Raid.dodge_retreating
			or now < state.toolReadyAt
			or now < (state.opeToolUntil or 0)
			or now - state.lastSkillDispatch < state.skillInterval
			or state.skillInFlight >= state.maxSkillInFlight
		then
			return false
		end
		local pos = _G.pos_skill
		if typeof(pos) ~= "CFrame" then
			return false
		end

		local method = GetSetting("dungeon_cast_method") or "Remote (Aimbot)"
		if method == "Remote (Aimbot)"
			and state.remoteInFlight > state.maxRemoteInFlight - 2
		then
			return false
		end
		local tools = {}
		if method == "Remote (Aimbot)" then
			-- Remote skills remain valid for configured Backpack tools. Keep the base
			-- sword/style equipped for M1 instead of unequipping it for every fruit cast.
			tools = _G.Raid.getConfiguredTools()
		else
			local equipped = _G.Raid.getEquippedTool()
			if equipped then
				table.insert(tools, equipped)
			end
		end

		local keys = { "Z", "X", "C", "V", "F", "B", "E" }
		local entries = {}
		for _, tool in ipairs(tools) do
			local data = _G.Raid.getSkillData(tool)
			if data then
				for _, key in ipairs(keys) do
					table.insert(entries, { tool = tool, key = key, data = data })
				end
			end
		end
		if #entries == 0 then
			return false
		end

		for _ = 1, #entries do
			state.skillCursor = (state.skillCursor % #entries) + 1
			local entry = entries[state.skillCursor]
			local tool, key, data = entry.tool, entry.key, entry.data
			local mastery = _G.Raid.getToolMastery(tool)
			local enabled = GetSetting(string.lower(key))
			local required = tonumber(data[key .. "Require"]) or 0
			local skillId = _G.Raid.getSkillPrefix(tool) .. tool.Name .. "_" .. key
			local isOpeZ = tool.Name == "OpOp" and key == "Z"
			local opeBlocked = tool.Name == "OpOp"
				and GetSetting("ope_method_dungeon")
				and not _G.Raid.isOpeRoomUsable()
			if enabled and tonumber(data[key]) and not isOpeZ and not opeBlocked
				and (required <= 0 or (mastery and mastery >= required))
				and now >= (state.skillReadyAt[skillId] or 0)
			then
				local started = _G.Raid.startAttackJob("skill", function()
					if method == "Remote (Aimbot)" then
						_G.Raid.remoteSkill(tool, key, pos)
					else
						_G.Raid.keyboard(key)
					end
				end, 3)
				if started then
					state.lastSkillDispatch = now
					state.skillReadyAt[skillId] = now + _G.Raid.getSkillCooldown(tool, key, data) + 0.1
					state.skillsDispatched = state.skillsDispatched + 1
					state.lastSkillId = skillId
					state.skillsByTool[tool.Name] = (state.skillsByTool[tool.Name] or 0) + 1
				end
				return started
			end
		end
		return false
	end

	_G.Raid.stopCombat = function()
		local state = _G.Raid.attackState
		if not state then
			return
		end
		state.generation = state.generation + 1
		state.requestedUntil = 0
		for _, job in pairs(state.jobs) do
			if job.thread then
				pcall(task.cancel, job.thread)
			end
			job.finished = true
		end
		state.jobs = {}
		state.m1InFlight = 0
		state.skillInFlight = 0
		for _, job in pairs(state.remoteJobs) do
			if job.thread then
				pcall(task.cancel, job.thread)
			end
			job.finished = true
		end
		state.remoteJobs = {}
		state.remoteInFlight = 0
		state.skillReadyAt = {}
		state.opeToolUntil = 0
		_G.Raid._loadoutGeneration = (_G.Raid._loadoutGeneration or 0) + 1
		_G.Raid._loadoutBusy = false
		_G.Raid.current_target = nil
		_G.Raid._mainLoopBusy = false
		if _G.Raid.clearDungeonFarm then
			_G.Raid.clearDungeonFarm()
		end
	end

	spawn(function()
		while task.wait(0.015) do
			pcall(function()
				if GetSetting("auto_dungeon_v2") and _G.Raid.inraid then
					_G.Raid.dispatchM1()
				end
			end)
		end
	end)

	_G.Raid.buso = function()
		if not GetSetting("buso") then
			return
		end
		pcall(function()
			local haki = Workspace.PlayerCharacters[LocalPlayer.Name].Services.Haki.Value
			if haki == 0 and tick() - (_G.Raid.last_buso or 0) > 2 then
				ReplicatedStorage.Chest.Remotes.Events.Armament:FireServer()
				_G.Raid.last_buso = tick()
			end
		end)
	end

	_G.Raid.ken = function()
		if not GetSetting("ken") then
			return
		end
		local ok, kenOpen = pcall(function()
			return Workspace.PlayerCharacters[LocalPlayer.Name].Services.KenOpen.Value
		end)
		if not ok or kenOpen or _G.Raid._kenBusy or tick() - (_G.Raid.last_ken or 0) <= 2 then
			return
		end
		_G.Raid.last_ken = tick()
		_G.Raid._kenBusy = true
		local finished = false
		local invokeThread = task.spawn(function()
			pcall(function()
				ReplicatedStorage.Chest.Remotes.Functions.KenEvent:InvokeServer()
			end)
			finished = true
			_G.Raid._kenBusy = false
		end)
		task.delay(3, function()
			if not finished then
				pcall(task.cancel, invokeThread)
				_G.Raid._kenBusy = false
			end
		end)
	end

	_G.Raid.hao = function()
		if not GetSetting("hao") then
			return
		end
		local now = tick()
		if now - (_G.Raid.last_hao or 0) < 2 then
			return
		end
		_G.Raid.last_hao = now
		pcall(function()
			ReplicatedStorage.Chest.Remotes.Events.Conqueror:FireServer()
		end)
	end

	_G.Raid.removeFarmFix = function()
		local f = _G.Raid.farmFix
		f.generation = (f.generation or 0) + 1
		f.target = nil
		f.bound = false
		if f.renderStepName then
			pcall(function()
				RunService:UnbindFromRenderStep(f.renderStepName)
			end)
		end
		f.thread = nil
		if f.pos then
			pcall(function()
				f.pos:Destroy()
			end)
			f.pos = nil
		end
		if f.gyro then
			pcall(function()
				f.gyro:Destroy()
			end)
			f.gyro = nil
		end
		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
		end
		f.root = nil
	end

	_G.Raid.getFarmTargetCFrame = function(target, height)
		if typeof(target) == "CFrame" then
			return target
		end
		local part = nil
		if typeof(target) == "Instance" then
			if target:IsA("BasePart") then
				part = target
			elseif target:IsA("Model") then
				part = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
			end
		end
		if not part or not part.Parent then
			return nil
		end
		return _G.Raid.downwardCFrame(part.Position + Vector3.new(0, height or 8, 0))
	end

	_G.Raid.applyFarmFix = function(target, height)
		local f = _G.Raid.farmFix
		f.target = target
		f.height = height or f.height or 8
		if f.bound then
			return
		end
		f.generation = (f.generation or 0) + 1
		local generation = f.generation
		f.bound = true
		f.thread = true -- compatibility/telemetry: the owner is a render-step binding.
		local ok, err = pcall(function()
			RunService:UnbindFromRenderStep(f.renderStepName)
			RunService:BindToRenderStep(f.renderStepName, Enum.RenderPriority.Last.Value + 10, function()
				if not f.bound
					or f.generation ~= generation
					or not f.target
					or not GetSetting("auto_dungeon_v2")
				then
					return
				end
				local root = _G.Raid.getRoot(LocalPlayer.Character)
				local targetCF = _G.Raid.getFarmTargetCFrame(f.target, f.height)
				if not root or not targetCF then
					return
				end
				if f.root ~= root then
					if f.pos then
						pcall(function()
							f.pos:Destroy()
						end)
					end
					if f.gyro then
						pcall(function()
							f.gyro:Destroy()
						end)
					end
					f.root = root
					f.pos = Instance.new("BodyPosition")
					f.pos.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
					f.pos.D = 100000
					f.pos.P = 1000000
					f.pos.Parent = root
					f.gyro = Instance.new("BodyGyro")
					f.gyro.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
					f.gyro.D = 50000
					f.gyro.P = 500000
					f.gyro.Parent = root
				end
				local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
				if humanoid then
					humanoid.PlatformStand = true
					humanoid.AutoRotate = false
				end
				f.pos.Position = targetCF.Position
				f.gyro.CFrame = targetCF
				root.CFrame = targetCF
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
		end)
		if not ok then
			f.bound = false
			f.thread = nil
			_G.Raid.attackState.lastError = "dungeon pose binding failed: " .. tostring(err)
		end
	end

	_G.Raid.stopOrbit = function()
		local o = _G.Raid.orbit
		if not o.active then
			return
		end
		o.active = false
		o.target = nil
		if o.thread then
			o.thread = nil
		end
		local root = _G.Raid.getRoot(LocalPlayer.Character)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
	end

	_G.Raid.getEffectiveFarmHeight = function(target)
		local configured = tonumber(GetSetting("dungeon_farm_height")) or 8
		-- Keep Veyzor inside melee range; the higher test offset cost too much
		-- damage output. His telegraphed attacks are handled by arena-safe dodges.
		if target and string.find(target.Name or "", "Veyzor", 1, true) then
			return 10
		end
		return configured
	end

	_G.Raid.startOrbit = function(target)
		if not target or not target.Parent then
			return
		end
		local o = _G.Raid.orbit
		if o.active and o.target == target then
			return
		end
		_G.Raid.stopOrbit()
		_G.Raid.removeFarmFix()
		if not _G.Raid.getRoot(LocalPlayer.Character) then
			return
		end
		local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.PlatformStand = true
		end
		o.active = true
		o.target = target
		o.angle = math.random() * math.pi * 2
		o.thread = task.spawn(function()
			while o.active and o.target and o.target.Parent and GetSetting("auto_dungeon_v2") do
				local hrp = o.target:FindFirstChild("HumanoidRootPart")
				local humT = o.target:FindFirstChild("Humanoid")
				if not hrp or not humT or humT.Health <= 0 then
					break
				end
				local height = _G.Raid.getEffectiveFarmHeight(o.target)
				local speed = GetSetting("orbit_speed") or 2.5
				o.angle = o.angle + (speed * 0.03)
				local offset = Vector3.new(math.cos(o.angle) * o.radius, height, math.sin(o.angle) * o.radius)
				local cf = _G.Raid.downwardCFrame(hrp.Position + offset)
				local root = _G.Raid.getRoot(LocalPlayer.Character)
				if root and root.Parent then
					root.CFrame = cf
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
				end
				task.wait(0.03)
			end
			local hum2 = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
			if hum2 then
				hum2.PlatformStand = false
			end
			o.active = false
			o.thread = nil
			o.target = nil
		end)
	end

	_G.Raid.clearDungeonFarm = function()
		_G.Raid.removeFarmFix()
		_G.Raid.stopOrbit()
	end

	_G.Raid.applyDungeonFarm = function(targetMob)
		if not targetMob or not targetMob:FindFirstChild("HumanoidRootPart") then
			_G.Raid.clearDungeonFarm()
			return
		end
		local method = GetSetting("dungeon_method") or "Stand Above Mobs"
		local hrp = targetMob.HumanoidRootPart
		if method == "Orbit Above Mobs" then
			_G.Raid.removeFarmFix()
			_G.Raid.startOrbit(targetMob)
		else
			_G.Raid.stopOrbit()
			local height = _G.Raid.getEffectiveFarmHeight(targetMob)
			_G.Raid.applyFarmFix(targetMob, height)
		end
	end

	_G.Raid.isDungeonBoss = function(mob)
		if typeof(mob) == "Instance" and mob:GetAttribute("Boss") == true then
			return true
		end
		local mobName = typeof(mob) == "Instance" and mob.Name or tostring(mob or "")
		for _, bossName in ipairs(_G.Raid.dungeonBosses) do
			if string.find(mobName, bossName, 1, true) then
				return true
			end
		end
		return false
	end

	_G.Raid.getDungeonModel = function()
		local islandFolder = Workspace:FindFirstChild("Island")
		if not islandFolder then
			return nil
		end
		for _, island in ipairs(islandFolder:GetChildren()) do
			if island:IsA("Model")
				and string.match(island.Name, "^%(Real%) .+ Dungeon$")
				and island:GetAttribute("Loaded") == true
			then
				return island
			end
		end
		return nil
	end

	_G.Raid.refreshDungeonBounds = function(force)
		local bounds = _G.Raid.dungeonBounds
		local now = os.clock()
		local model = _G.Raid.getDungeonModel()
		if not force and bounds.model == model and now - (bounds.checkedAt or 0) < 0.75 then
			return bounds.center, bounds.size, model
		end
		bounds.checkedAt = now
		bounds.model = model
		bounds.center = nil
		bounds.size = nil
		if model then
			local ok, cf, size = pcall(model.GetBoundingBox, model)
			if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
				bounds.center = cf.Position
				bounds.size = size
			end
		end
		return bounds.center, bounds.size, model
	end

	_G.Raid.isDungeonMobValid = function(mob)
		if not mob or not mob:IsA("Model") or not mob.Parent then
			return false
		end
		local humanoid = mob:FindFirstChild("Humanoid")
		local root = mob:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root then
			return false
		end
		local center, size, model = _G.Raid.refreshDungeonBounds(false)
		if not model or not center or not size then
			return false
		end
		local delta = root.Position - center
		local margin = 180
		return math.abs(delta.X) <= size.X * 0.5 + margin
			and math.abs(delta.Y) <= size.Y * 0.5 + margin
			and math.abs(delta.Z) <= size.Z * 0.5 + margin
	end

	_G.Raid.selectTarget = function()
		local folder = Workspace:FindFirstChild("MOB")
		local playerRoot = _G.Raid.getRoot(LocalPlayer.Character)
		if not folder or not playerRoot then
			return nil, false
		end
		local current = _G.Raid.current_target
		local currentValid = _G.Raid.isDungeonMobValid(current)
		local currentBoss = currentValid and _G.Raid.isDungeonBoss(current)
		local nearestBoss, nearestBossDistance = nil, math.huge
		local nearestMob, nearestMobDistance = nil, math.huge
		for _, mob in ipairs(folder:GetChildren()) do
			if _G.Raid.isDungeonMobValid(mob) then
				local root = mob:FindFirstChild("HumanoidRootPart")
				local distanceToPlayer = (root.Position - playerRoot.Position).Magnitude
				if _G.Raid.isDungeonBoss(mob) then
					if distanceToPlayer < nearestBossDistance then
						nearestBoss = mob
						nearestBossDistance = distanceToPlayer
					end
				elseif distanceToPlayer < nearestMobDistance then
					nearestMob = mob
					nearestMobDistance = distanceToPlayer
				end
			end
		end
		if currentBoss then
			return current, true
		end
		if nearestBoss then
			return nearestBoss, true
		end
		if currentValid then
			return current, false
		end
		return nearestMob, false
	end

	_G.Raid.hasMobsInFloor = function()
		local target = _G.Raid.selectTarget()
		return target ~= nil
	end

	_G.Raid.checkInRaid = function()
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local hasDungeonUi = playerGui and playerGui:FindFirstChild("DungeonUI") ~= nil
		local model = _G.Raid.getDungeonModel()
		local root = _G.Raid.getRoot(LocalPlayer.Character)
		local hasLoadedDungeon = false
		if model and root then
			local ok, modelCF = pcall(model.GetPivot, model)
			hasLoadedDungeon = ok and (root.Position - modelCF.Position).Magnitude < 5000
		end

		-- DungeonUI is created from the server's DungeonUI effect. The loaded
		-- dungeon model exists slightly earlier and slightly later, covering the
		-- transition windows where relying on the GUI alone can misclassify state.
		_G.Raid.inraid = hasDungeonUi or hasLoadedDungeon
		if not _G.Raid.inraid then
			_G.Raid.inop = false
		end
		return _G.Raid.inraid
	end

	_G.Raid.updateFloor = function()
		local ok, floor = pcall(function()
			local replicatedFloor = tonumber(ReplicatedStorage:GetAttribute("DungeonFloor"))
			if replicatedFloor and replicatedFloor >= 1 and replicatedFloor <= 5 then
				return replicatedFloor
			end
			local ui = LocalPlayer.PlayerGui:FindFirstChild("DungeonUI")
			if not ui then
				return _G.Raid.current_floor
			end
			local dungeonFrame = ui:FindFirstChild("DungeonFrame")
			local innerFrame = dungeonFrame and dungeonFrame:FindFirstChild("Frame")
			local floorsFrame = innerFrame and innerFrame:FindFirstChild("FloorsFrame")
			local label = floorsFrame and floorsFrame:FindFirstChild("TextLabel")
			if label and label:IsA("TextLabel") then
				local n = tonumber(string.match(label.Text or "", "%d+"))
				if n then
					return n
				end
			end
			return _G.Raid.current_floor
		end)
		if ok and floor then
			_G.Raid.current_floor = floor
			return floor
		end
		return _G.Raid.current_floor
	end

	_G.Raid.getFloorCFrame = function(floor)
		local model = _G.Raid.getDungeonModel()
		local floorObject = model and model:FindFirstChild("Floor" .. tostring(floor), true)
		if not floorObject then
			return nil
		end
		local position = nil
		if floorObject:IsA("BasePart") then
			position = floorObject.Position
		elseif floorObject:IsA("Model") then
			local ok, cf = pcall(floorObject.GetPivot, floorObject)
			position = ok and cf.Position or nil
		end
		if not position then
			return nil
		end
		return _G.Raid.downwardCFrame(position + Vector3.new(0, 7, 0))
	end

	_G.Raid.teleportToFloor = function(floor)
		local cf = _G.Raid.getFloorCFrame(floor)
		if cf then
			_G.Raid.tp(cf)
		end
		return cf
	end

	_G.Raid.teleportToDungeonEntrance = function()
		local placeId = game.PlaceId
		if placeId == 4520749081 then
			_G.Raid.tp(CFrame.new(-4610, 33, -6009))
		elseif placeId == 6381829480 then
			_G.Raid.tp(CFrame.new(-2428, 57, -1566))
		elseif placeId == 15759515082 then
			_G.Raid.tp(CFrame.new(10960, 133, 1250))
		end
	end

	_G.Raid._difficultyAttemptsByGui = setmetatable({}, { __mode = "k" })
	_G.Raid.difficultyTelemetry = {
		requested = nil,
		attempts = 0,
		clickConfirmed = false,
		lastDispatchReason = nil,
		loadedModel = nil,
		result = "idle",
	}
	_G.Raid.difficultyTelemetryHistory = {}

	_G.Raid.archiveDifficultyTelemetry = function()
		local telemetry = _G.Raid.difficultyTelemetry
		if not telemetry
			or not telemetry.result
			or telemetry.result == "idle"
			or telemetry.result == "waiting_for_picker"
		then
			return
		end
		table.insert(_G.Raid.difficultyTelemetryHistory, {
			at = os.clock(),
			requested = telemetry.requested,
			attempts = telemetry.attempts,
			clickConfirmed = telemetry.clickConfirmed,
			lastDispatchReason = telemetry.lastDispatchReason,
			loadedModel = telemetry.loadedModel,
			result = telemetry.result,
		})
		while #_G.Raid.difficultyTelemetryHistory > 12 do
			table.remove(_G.Raid.difficultyTelemetryHistory, 1)
		end
	end

	_G.Raid.normalizeDifficulty = function(value)
		value = string.lower(tostring(value or ""))
		if value == "medium" or value == "normal" then
			return "normal"
		elseif value == "easy" or value == "hard" then
			return value
		end
		return value
	end

	_G.Raid.getLoadedDungeonDifficulty = function()
		local model = _G.Raid.getDungeonModel()
		if not model then
			return nil, nil
		end
		local name = string.match(model.Name, "^%(Real%) (.+) Dungeon$")
		return name and _G.Raid.normalizeDifficulty(name) or nil, model
	end

	_G.Raid.selectDifficulty = function(entryGeneration)
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		if not playerGui then
			return false
		end
		local function entryStillValid()
			if not GetSetting("auto_dungeon_v2") then
				return false
			end
			if entryGeneration ~= nil and _G.Raid._entryGeneration ~= entryGeneration then
				return false
			end
			local committed = _G._GenesisUpdateDungeonCommit()
			if committed then
				return true
			end
			local canStart = _G._GenesisCanStartDungeon()
			return canStart == true
		end

		local current = tostring(GetSetting("dungeon_select") or "Easy")
		local requestedDifficulty = _G.Raid.normalizeDifficulty(current)
		local telemetry = _G.Raid.difficultyTelemetry
		_G.Raid.archiveDifficultyTelemetry()
		telemetry.requested = current
		telemetry.attempts = 0
		telemetry.clickConfirmed = false
		telemetry.lastDispatchReason = nil
		telemetry.loadedModel = nil
		telemetry.result = "waiting_for_picker"

		-- The server creates ChooseMap only after the entrance circle's 20-second timer.
		-- Wait for the actual GUI instead of assuming an exact countdown duration.
		local chooseMap = nil
		local deadline = os.clock() + 35
		local nextRecenter = 0
		while entryStillValid() and os.clock() < deadline do
			if _G.Raid.checkInRaid() then
				local loadedDifficulty, model = _G.Raid.getLoadedDungeonDifficulty()
				telemetry.loadedModel = model and model.Name or nil
				telemetry.result = loadedDifficulty == requestedDifficulty and "already_loaded" or "already_in_raid"
				return true
			end

			chooseMap = playerGui:FindFirstChild("ChooseMap")
			if chooseMap and chooseMap:FindFirstChild("ChooseMapFrame") then
				_G._GenesisUpdateDungeonCommit()
				break
			end

			-- Keep the character inside the large entrance trigger while it counts down.
			if os.clock() >= nextRecenter then
				nextRecenter = os.clock() + 2
				_G.Raid.teleportToDungeonEntrance()
			end
			task.wait(0.25)
		end

		if not chooseMap or not chooseMap.Parent or not entryStillValid() then
			telemetry.result = entryStillValid() and "picker_not_found" or "entry_cancelled"
			return false
		end

		local chooseMapFrame = chooseMap:FindFirstChild("ChooseMapFrame")
		local mapFrame = chooseMapFrame and chooseMapFrame:FindFirstChild("MapFrame")
		if not mapFrame then
			telemetry.result = "map_frame_not_found"
			return false
		end

		local aliases = { current }
		if current == "Normal" then
			table.insert(aliases, "Medium")
		elseif current == "Medium" then
			table.insert(aliases, "Normal")
		end

		local button = nil
		for _, candidateName in ipairs(aliases) do
			local exact = mapFrame:FindFirstChild(candidateName, true)
			if exact and exact:IsA("GuiButton") then
				button = exact
				break
			end

			for _, descendant in ipairs(mapFrame:GetDescendants()) do
				if descendant:IsA("GuiButton") then
					local buttonText = descendant:IsA("TextButton") and descendant.Text or ""
					if string.lower(descendant.Name) == string.lower(candidateName)
						or string.lower(buttonText) == string.lower(candidateName)
					then
						button = descendant
						break
					end
				end
			end
			if button then
				break
			end
		end

		if not button or not _G._GenesisIsVisibleGuiButton(button) then
			telemetry.result = "difficulty_button_not_found"
			return false
		end
		-- A completed dungeon model may remain replicated while the next picker is
		-- already visible. Only a replacement model can verify this new selection.
		local staleModel = _G.Raid.getDungeonModel()

		local attemptCount = _G.Raid._difficultyAttemptsByGui[chooseMap] or 0
		while attemptCount < 3 and chooseMap.Parent and entryStillValid() do
			attemptCount = attemptCount + 1
			_G.Raid._difficultyAttemptsByGui[chooseMap] = attemptCount
			telemetry.attempts = attemptCount

			-- Re-dispatch the same validated choice only if this exact popup remains.
			local fired, dispatchReason = _G._GenesisDispatchGuiButton(button)
			telemetry.lastDispatchReason = dispatchReason
			if not fired then
				telemetry.result = "dispatch_failed"
				task.wait(0.15)
				if not _G._GenesisIsVisibleGuiButton(button) then
					break
				end
				continue
			end
			telemetry.clickConfirmed = true
			telemetry.result = "click_confirmed"

			local verifyDeadline = os.clock() + 20
			repeat
				local loadedDifficulty, model = _G.Raid.getLoadedDungeonDifficulty()
				if model and model ~= staleModel then
					telemetry.loadedModel = model.Name
					if loadedDifficulty == requestedDifficulty then
						telemetry.result = "verified"
						return true
					end
					telemetry.result = "loaded_wrong_difficulty"
					return false
				end
				if not chooseMap.Parent
					or (chooseMap:IsA("ScreenGui") and not chooseMap.Enabled)
					or (chooseMapFrame:IsA("GuiObject") and not chooseMapFrame.Visible)
				then
					local inRaid = _G.Raid.checkInRaid()
					local committed = _G._GenesisUpdateDungeonCommit()
					telemetry.result = inRaid and "entered_unverified" or "picker_closed_committed"
					return inRaid or committed
				end
				task.wait(0.1)
			until os.clock() >= verifyDeadline or not entryStillValid()

			if not chooseMap.Parent
				or (chooseMap:IsA("ScreenGui") and not chooseMap.Enabled)
				or (chooseMapFrame:IsA("GuiObject") and not chooseMapFrame.Visible)
			then
				telemetry.result = _G.Raid.checkInRaid() and "entered_unverified" or "picker_closed_unverified"
				return _G.Raid.checkInRaid()
			end
		end

		-- Never equate "we sent input" with a successful choice. The popup is
		-- bounded to three hit-tested dispatches and records an explicit result.
		telemetry.result = telemetry.clickConfirmed and "verification_timed_out" or telemetry.result
		return false
	end

	_G.Raid.cycleTools = function()
		if os.clock() < (_G.Raid.attackState.opeToolUntil or 0) then
			return nil
		end
		if (GetSetting("dungeon_cast_method") or "Remote (Aimbot)") == "Remote (Aimbot)" then
			-- The remote skill path can cast configured Backpack tools directly.
			-- Keeping one real M1 weapon in hand removes the half-second unequip gaps.
			return _G.Raid.ensureBaseCombatTool()
		end
		local state = _G.Raid.attackState
		if state.skillInFlight > 0 or os.clock() < state.toolReadyAt then
			return nil
		end
		local tools = GetSetting("dungeon_outside_tools") or { "Combat", "Fruit Power" }
		if GetSetting("ope_method_dungeon") and _G.Raid.findOpeTool() then
			tools = { "Fruit Power" }
		end
		if not tools or #tools == 0 then
			return nil
		end
		_G.Raid._toolIdx = (_G.Raid._toolIdx or 0) + 1
		if _G.Raid._toolIdx > #tools then
			_G.Raid._toolIdx = 1
		end
		local selected = tools[_G.Raid._toolIdx]
		local tool = _G.Raid.tooltip(selected)
		if not tool then
			-- Do not get stuck forever on a configured category that the player does
			-- not own. Try each remaining category once, deterministically.
			for _ = 2, #tools do
				_G.Raid._toolIdx = (_G.Raid._toolIdx % #tools) + 1
				selected = tools[_G.Raid._toolIdx]
				tool = _G.Raid.tooltip(selected)
				if tool then
					break
				end
			end
		end
		return tool
	end

	_G.Raid.cleanupEffectTracker = function()
		local now = tick()
		for effect, t in pairs(_G.Raid.effectFirstSeen) do
			if not effect or not effect.Parent or (now - t) > 8 then
				_G.Raid.effectFirstSeen[effect] = nil
			end
		end
	end

	_G.Raid.getAttackPattern = function(effect)
		local name = string.lower(effect.Name or "")
		-- Veyzor's 50-stud ImpactT appears at the boss about 1.5 seconds
		-- before the room-crossing pull/slam. The later ImpactT is an impact
		-- visual; the first one gives the dodge its usable warning window.
		if name == "impactt" then
			local target = _G.Raid.current_target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
			local part = effect:IsA("BasePart") and effect or effect:FindFirstChildWhichIsA("BasePart")
			if targetRoot and string.find(target.Name or "", "Veyzor", 1, true)
				and part
				and math.abs(part.Size.X - 50) <= 2
				and math.abs(part.Size.Y - 50) <= 2
				and math.abs(part.Size.Z - 50) <= 2
				and (part.Position - targetRoot.Position).Magnitude <= 125
			then
				return "veyzor_mount_windup"
			end
		end
		-- Chaos Crab creates this constrained hand roughly half a second before
		-- CrabS1/Circ (and before the close explosion in its longer combos). Those
		-- later objects are impact visuals, so waiting for their names can make the
		-- dodge start after the damage packet. "hand" is otherwise far too generic;
		-- accept it only when its constraint is physically attached to the current
		-- Chaos Crab target.
		if name == "hand" then
			local target = _G.Raid.current_target
			if target and string.find(string.lower(target.Name or ""), "chaos crab", 1, true) then
				for _, descendant in ipairs(effect:GetDescendants()) do
					if descendant:IsA("RigidConstraint") then
						local attachment0 = descendant.Attachment0
						local attachment1 = descendant.Attachment1
						if (attachment0 and attachment0:IsDescendantOf(target))
							or (attachment1 and attachment1:IsDescendantOf(target))
						then
							return "chaoscrab_windup"
						end
					end
				end
			end
		end
		for _, pattern in pairs(_G.Raid.attackPatterns) do
			if name:find(pattern, 1, true) then
				return pattern
			end
		end
		return nil
	end

	_G.Raid.getEffectDangerDuration = function(effect)
		local name = string.lower(effect.Name or "")
		-- Crab warning disks are only garbage-collected after five seconds, but the
		-- reconstructed attack finishes the warning tween and lands its meteor or
		-- pillar at about 2.0 seconds. Following the stale visual for its full
		-- lifetime caused several seconds of needless evasion after every strike.
		-- Keep a small replication/latency margin beyond the measured impact instead.
		if name:find("warning", 1, true) then
			return 2.35
		end
		-- These are late visuals from the same Chaos Crab attack whose constrained
		-- hand is now detected at wind-up. Retain them briefly as replication
		-- fallbacks, but expire them before the completed wind-up dodge can mistake
		-- the same strike for a new attack and retreat a second time.
		if name:find("crabs1", 1, true) or name:find("circ", 1, true) then
			return 1.25
		end
		if name:find("pillar_exp", 1, true) then
			return 0.8
		end
		-- WaterBall is different: it remains a moving projectile for roughly one
		-- second after it appears, so preserve a modest post-spawn tracking window.
		if name:find("waterball", 1, true) then
			return 1.4
		end
		return _G.Raid.EFFECT_MAX_AGE
	end

	_G.Raid.isDangerousEffect = function(effect, bossPos, playerPos)
		local pattern = _G.Raid.getAttackPattern(effect)
		if not pattern then
			return false, nil
		end
		local part = effect:IsA("BasePart") and effect or effect:FindFirstChildWhichIsA("BasePart")
		if not part then
			return false, nil
		end
		local function horizontalDistance(a, b)
			local dx = a.X - b.X
			local dz = a.Z - b.Z
			return math.sqrt(dx * dx + dz * dz)
		end
		-- Effect centers alone are misleading for the 300/800-stud warning disks,
		-- and vertical farm height must not make a ground hazard look farther away.
		local effectRadius = math.clamp(math.max(part.Size.X, part.Size.Z) * 0.5, 0, 400)
		if horizontalDistance(part.Position, playerPos) > 300 + effectRadius then
			return false, nil
		end
		-- Crab target markers and follow-up pillars can legitimately be more than
		-- 300 studs from the boss. Player proximity is the primary relevance gate;
		-- retain only a broad arena-level boss bound to reject unrelated effects.
		if bossPos and horizontalDistance(part.Position, bossPos) > 500 + effectRadius then
			return false, nil
		end
		return true, part.Position, effectRadius, pattern
	end

	_G.Raid.scanAttacks = function(getPosition)
		_G.Raid.cleanupEffectTracker()
		local boss = _G.Raid.current_target
		local bossPos = boss and boss:FindFirstChild("HumanoidRootPart") and boss.HumanoidRootPart.Position
		local playerRoot = _G.Raid.getRoot(LocalPlayer.Character)
		if not playerRoot then
			return false, nil
		end
		local playerPos = playerRoot.Position
		local now = tick()
		local effects = Workspace:FindFirstChild("Effects")
		if not effects then
			return false, nil
		end
		local foundPos, foundPattern = nil, nil
		local prioritizeVeyzorMount = boss and string.find(boss.Name or "", "Veyzor", 1, true) ~= nil
		for _, effect in pairs(effects:GetChildren()) do
			if not _G.Raid.effectFirstSeen[effect] then
				_G.Raid.effectFirstSeen[effect] = now
			end
			local age = now - _G.Raid.effectFirstSeen[effect]
			if age <= _G.Raid.getEffectDangerDuration(effect) then
				local dangerous, pos, _, pattern = _G.Raid.isDangerousEffect(effect, bossPos, playerPos)
				if dangerous then
					if not getPosition then
						return true, nil, pattern
					end
					if pattern == "veyzor_mount_windup" then
						return true, pos, pattern
					end
					if not foundPos then
						foundPos, foundPattern = pos, pattern
					end
					if foundPos and not prioritizeVeyzorMount then
						return true, foundPos, foundPattern
					end
				end
			end
		end
		if foundPos then
			return true, foundPos, foundPattern
		end
		return false, nil
	end

	_G.Raid.detectAttack = function()
		local d = _G.Raid.scanAttacks(false)
		return d
	end

	-- Chaos Crab's long Z combos create several red warning disks 1.8 seconds
	-- before their pillar impacts. They are critical even while Race V3 is active:
	-- lifesteal cannot recover four stacked hits, and an existing recovery dodge
	-- must move again because the next barrage targets its parked position.
	_G.Raid.getChaosAirstrikeWarning = function(mob)
		if not mob
			or not string.find(string.lower(mob.Name or ""), "chaos crab", 1, true)
		then
			return nil, nil
		end
		local effects = Workspace:FindFirstChild("Effects")
		if not effects then
			return nil, nil
		end
		local now = tick()
		for _, effect in ipairs(effects:GetChildren()) do
			if string.lower(effect.Name or "") == "warning" then
				if not _G.Raid.effectFirstSeen[effect] then
					_G.Raid.effectFirstSeen[effect] = now
				end
				if now - _G.Raid.effectFirstSeen[effect] <= 2.35 then
					local part = effect:IsA("BasePart") and effect
						or effect:FindFirstChildWhichIsA("BasePart")
					return effect, part and part.Position or nil
				end
			end
		end
		return nil, nil
	end

	_G.Raid.isLargeTrackingBoss = function(mob)
		if not mob then
			return false
		end
		local name = mob.Name or ""
		return name:find("Veyzor", 1, true) ~= nil
			or name:find("Chaos Crab", 1, true) ~= nil
			or name:find("Craberno", 1, true) ~= nil
	end

	_G.Raid.clearVeyzorAnimationWatch = function()
		if _G.Raid.veyzorAnimationConnection then
			_G.Raid.veyzorAnimationConnection:Disconnect()
			_G.Raid.veyzorAnimationConnection = nil
		end
		_G.Raid.veyzorAnimationTarget = nil
	end

	_G.Raid.watchVeyzorAnimations = function(target)
		if target == _G.Raid.veyzorAnimationTarget and _G.Raid.veyzorAnimationConnection then
			return
		end
		_G.Raid.clearVeyzorAnimationWatch()
		if not target or not string.find(target.Name or "", "Veyzor", 1, true) then
			return
		end
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end
		_G.Raid.veyzorAnimationTarget = target
		_G.Raid.veyzorAnimationConnection = trackGenesisConnection(animator.AnimationPlayed:Connect(function(track)
			local animation = track.Animation
			if not animation or animation.AnimationId ~= "rbxassetid://138126660188153" then
				return
			end
			if not GetSetting("auto_dungeon_v2")
				or not GetSetting("dodge_v2")
				or not _G.Raid.inraid
				or _G.Raid.current_target ~= target
			then
				return
			end
			local targetRoot = target:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				_G.Raid.lastVeyzorAnimationDodgeAt = os.clock()
				_G.Raid.startDodge(targetRoot.Position, 230)
			end
		end))
	end

	_G.Raid.getAttackPosition = function()
		local _, pos = _G.Raid.scanAttacks(true)
		return pos
	end

	_G.Raid.stopDodge = function()
		_G.Raid.dodge_active = false
		_G.Raid.dodge_retreating = false
		_G.Raid.dodge_critical = false
		_G.Raid.dodge_critical_name = nil
		_G.Raid.dodge_phase = nil
		_G.Raid.dodge_phase_started = 0
		_G.Raid.dodge_generation = (_G.Raid.dodge_generation or 0) + 1
		if _G.Raid.dodge_render_step_name then
			pcall(function()
				RunService:UnbindFromRenderStep(_G.Raid.dodge_render_step_name)
			end)
		end
		if _G.Raid.dodge_gyro then
			pcall(function()
				_G.Raid.dodge_gyro:Destroy()
			end)
			_G.Raid.dodge_gyro = nil
		end
		if _G.Raid.dodge_force_thread then
			_G.Raid.dodge_force_thread = nil
		end
		if _G.Raid.dodge_monitor_thread then
			_G.Raid.dodge_monitor_thread = nil
		end
		local root = _G.Raid.getRoot(LocalPlayer.Character)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.PlatformStand = false
		end
		_G.Raid.clearDungeonFarm()
	end

	_G.Raid.startDodge = function(attackPosition, customHeight)
		if _G.Raid.dodge_active then
			return
		end
		local now = tick()
		local target = _G.Raid.current_target
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		local targetHumanoid = target and target:FindFirstChild("Humanoid")
		local root = _G.Raid.getRoot(LocalPlayer.Character)
		local floorCF = _G.Raid.getFloorCFrame(_G.Raid.current_floor)
		if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 or not root or not floorCF then
			return
		end

		local isLargeBoss = _G.Raid.isLargeTrackingBoss(target)
		local dodgeCooldown = 1.8
		if now - (_G.Raid.last_dodge_time or 0) < dodgeCooldown then
			return
		end

		_G.Raid.dodge_active = true
		_G.Raid.dodge_retreating = false
		_G.Raid.dodge_phase = "evade"
		_G.Raid.dodge_phase_started = now
		_G.Raid.dodge_start_time = now
		_G.Raid.last_dodge_time = now
		_G.Raid.dodge_generation = (_G.Raid.dodge_generation or 0) + 1
		local generation = _G.Raid.dodge_generation
		_G.Raid.clearDungeonFarm()

		-- A dungeon arena is a three-dimensional room, not merely a floor footprint.
		-- Preserve the character's already-valid combat altitude for large bosses
		-- and use adjacent FloorN markers to keep every destination below the next
		-- room. The former +380 large-boss height crossed the roughly 348-stud room
		-- spacing, causing the game to correct the player back into live warnings.
		local center = floorCF.Position
		local attackPos = attackPosition or targetRoot.Position
		local requestedHeight = customHeight or (isLargeBoss and 230 or 210)
		local currentHeight = root.Position.Y - center.Y
		local roomSpacing = nil
		local nextFloorCF = _G.Raid.getFloorCFrame((_G.Raid.current_floor or 1) + 1)
		if nextFloorCF and nextFloorCF.Position.Y > center.Y then
			roomSpacing = nextFloorCF.Position.Y - center.Y
		else
			local previousFloorCF = _G.Raid.getFloorCFrame((_G.Raid.current_floor or 1) - 1)
			if previousFloorCF and previousFloorCF.Position.Y < center.Y then
				roomSpacing = center.Y - previousFloorCF.Position.Y
			end
		end
		local maximumInsideHeight = roomSpacing and math.max(60, roomSpacing - 60) or 230
		local desiredHeight = isLargeBoss and math.min(currentHeight, requestedHeight) or requestedHeight
		local height = math.clamp(desiredHeight, 12, maximumInsideHeight)
		_G.Raid.lastDodgeArenaVolume = {
			center = center,
			horizontalHalfExtent = 350,
			minimumY = center.Y + 12,
			maximumY = center.Y + maximumInsideHeight,
			selectedY = center.Y + height,
			floorSpacing = roomSpacing,
		}
		local threats = { attackPos, targetRoot.Position }
		local threatRadii = { 0, 0 }
		local effects = Workspace:FindFirstChild("Effects")
		if effects then
			for _, effect in ipairs(effects:GetChildren()) do
				local dangerous, position, radius =
					_G.Raid.isDangerousEffect(effect, targetRoot.Position, root.Position)
				if dangerous and position then
					table.insert(threats, position)
					table.insert(threatRadii, radius or 0)
				end
			end
		end

		local bestPosition = nil
		local bestScore = -1
		local bestPathPhase = 0
		local largeCandidates = {}
		if isLargeBoss then
			local isVeyzor = string.find(target.Name or "", "Veyzor", 1, true) ~= nil
			local offsets = {
				-- Clockwise floor corners. Phase is retained so a dodge can immediately
				-- continue around the perimeter instead of camping at a position that a
				-- tracking dungeon boss can teleport onto.
				{ -330, -330, 0 }, { 330, -330, 1 }, { 330, 330, 2 }, { -330, 330, 3 },
			}
			local dungeonModel = _G.Raid.getDungeonModel()
			local fakeDungeon = nil
			if isVeyzor then
				-- The Normal dungeon has a separate collidable fake shell. Its walls
				-- intersect the old +/-330 corners even though the real floor lies
				-- beneath them; that produced a teleport/correction tug of war.
				offsets = {
					{ -200, -200, 0 }, { 200, -200, 1 }, { 200, 200, 2 }, { -200, 200, 3 },
					{ -160, -160, 4 }, { 160, -160, 5 }, { 160, 160, 6 }, { -160, 160, 7 },
				}
				if dungeonModel and dungeonModel.Parent then
					local fakeName = string.gsub(dungeonModel.Name, "^%(Real%)", "(Fake)")
					fakeDungeon = dungeonModel.Parent:FindFirstChild(fakeName)
				end
			end
			local rayParams = nil
			if dungeonModel then
				rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Include
				local floorGroup = isVeyzor and dungeonModel:FindFirstChild("5th")
				local floorSurface = floorGroup and floorGroup:FindFirstChild("Floor")
				rayParams.FilterDescendantsInstances = { floorSurface or dungeonModel }
			end
			for _, offset in ipairs(offsets) do
				local candidate = Vector3.new(center.X + offset[1], center.Y + height, center.Z + offset[2])
				local onFloor = true
				if rayParams then
					onFloor = Workspace:Raycast(
						Vector3.new(candidate.X, center.Y + 80, candidate.Z),
						Vector3.new(0, -180, 0),
						rayParams
					) ~= nil
				end
				if onFloor and isVeyzor then
					-- Reject real scenery and fake-shell walls at the character's
					-- actual dodge altitude, not just positions with floor below.
					for _, part in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(candidate), Vector3.new(8, 12, 8))) do
						if part.CanCollide
							and ((dungeonModel and part:IsDescendantOf(dungeonModel))
								or (fakeDungeon and part:IsDescendantOf(fakeDungeon)))
						then
							onFloor = false
							break
						end
					end
				end
				if onFloor then
					table.insert(largeCandidates, { position = candidate, phase = offset[3] })
					local score = math.huge
					for threatIndex, threat in ipairs(threats) do
						local dx = candidate.X - threat.X
						local dz = candidate.Z - threat.Z
						local clearance = math.sqrt(dx * dx + dz * dz) - (threatRadii[threatIndex] or 0)
						score = math.min(score, clearance)
					end
					if score > bestScore then
						bestScore = score
						bestPosition = candidate
						bestPathPhase = offset[3]
					end
				end
			end
		else
			-- Ordinary boss telegraphs do not need the expensive full-arena retreat;
			-- keep their shorter baseline dodge so melee downtime stays bounded.
			local direction = Vector3.new(attackPos.X - center.X, 0, attackPos.Z - center.Z)
			if direction.Magnitude < 0.15 then
				direction = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
			end
			if direction.Magnitude < 0.15 then
				direction = Vector3.new(1, 0, 0)
			else
				direction = direction.Unit
			end
			bestPosition = Vector3.new(
				math.clamp(center.X - direction.X * 300, center.X - 350, center.X + 350),
				center.Y + height,
				math.clamp(center.Z - direction.Z * 300, center.Z - 350, center.Z + 350)
			)
			bestScore = math.huge
			for threatIndex, threat in ipairs(threats) do
				local dx = bestPosition.X - threat.X
				local dz = bestPosition.Z - threat.Z
				local clearance = math.sqrt(dx * dx + dz * dz) - (threatRadii[threatIndex] or 0)
				bestScore = math.min(bestScore, clearance)
			end
		end
		if not bestPosition then
			-- Streaming may temporarily hide the large-boss floor geometry from the
			-- raycast. Retain a bounded diagonal fallback inside the known envelope.
			local fallbackRadius = string.find(target.Name or "", "Veyzor", 1, true) and 160 or 330
			local x = attackPos.X >= center.X and -fallbackRadius or fallbackRadius
			local z = attackPos.Z >= center.Z and -fallbackRadius or fallbackRadius
			bestPosition = Vector3.new(center.X + x, center.Y + height, center.Z + z)
			bestScore = math.huge
			for threatIndex, threat in ipairs(threats) do
				local dx = bestPosition.X - threat.X
				local dz = bestPosition.Z - threat.Z
				local clearance = math.sqrt(dx * dx + dz * dz) - (threatRadii[threatIndex] or 0)
				bestScore = math.min(bestScore, clearance)
			end
		end
		_G.Raid.lastDodgeSafePosition = bestPosition
		_G.Raid.lastDodgeSafeScore = bestScore
		_G.Raid.lastDodgeThreatCount = #threats
		local safeCF = _G.Raid.downwardCFrame(bestPosition)
		local selectedLargeCandidate = nil
		for _, candidate in ipairs(largeCandidates) do
			if candidate.phase == bestPathPhase then
				selectedLargeCandidate = candidate
				break
			end
		end
		local lastLargeRescore = 0
		local criticalMode = false
		local criticalWallPart = nil
		local chaosAirstrikeUntil = 0
		local chaosAirstrikeLastMoveAt = 0
		local chaosAirstrikeCandidates = {}
		if string.find(string.lower(target.Name or ""), "chaos crab", 1, true) then
			-- The normal dungeon dodge has always treated +/-350 from FloorN as the
			-- playable arena. Keep every air-strike destination thirty studs inside
			-- that boundary. Do not validate against the dungeon model's broad floor
			-- slab: that slab continues underneath exterior scenery and previously
			-- made an out-of-arena point look valid.
			for offsetX = -320, 320, 40 do
				for offsetZ = -320, 320, 40 do
					table.insert(chaosAirstrikeCandidates, {
						position = Vector3.new(center.X + offsetX, center.Y + height, center.Z + offsetZ),
					})
				end
			end
		end
		local function getCrabPullSafeWallPosition()
			local liveEffects = Workspace:FindFirstChild("Effects")
			if not liveEffects then
				return nil
			end

			-- The shared crab C attack receives four WallCFs from the server. The client materializes
			-- each one as a pillar and a wind barrier, then turns its directional beam
			-- orange before CrabPull starts. The widening beam is the visible shelter
			-- field: AT1 begins at the rock and AT2 extends roughly 194 studs through the
			-- safe side. Arena-center-to-rock is not a reliable substitute for that
			-- orientation (it previously parked beside a rock instead of behind it).
			local function projectedShelterPosition(part)
				local beam = part:FindFirstChild("Beam")
				local attachment0 = beam and beam:IsA("Beam") and beam.Attachment0
				local attachment1 = beam and beam:IsA("Beam") and beam.Attachment1
				local origin = attachment0 and attachment0.WorldPosition or part.Position
				local beamVector = attachment1 and (attachment1.WorldPosition - origin)
					or part.CFrame.LookVector * 194
				local horizontal = Vector3.new(beamVector.X, 0, beamVector.Z)
				if horizontal.Magnitude < 1 then
					return nil
				end

				-- Stay near the middle of the widening field: far enough behind the rock
				-- to block the pull, but with ample room before the beam's far edge. Keep
				-- the HumanoidRootPart at the pillar's floor-relative height rather than at
				-- the beam attachments, which sit near the bottom of the mesh.
				local shelterDistance = math.clamp(horizontal.Magnitude * 0.42, 65, 90)
				local direction = horizontal.Unit
				local position = Vector3.new(
					origin.X + direction.X * shelterDistance,
					part.Position.Y,
					origin.Z + direction.Z * shelterDistance
				)
				if math.abs(position.X - center.X) > 340
					or math.abs(position.Z - center.Z) > 340
				then
					return nil
				end
				return position, beam ~= nil and attachment0 ~= nil and attachment1 ~= nil
			end

			-- Latch one valid projected shelter instead of changing destinations as the
			-- remaining walls replicate.
			if not criticalWallPart or not criticalWallPart.Parent then
				local nearestPart = nil
				local nearestDistance = math.huge
				for _, effect in ipairs(liveEffects:GetChildren()) do
					if string.lower(effect.Name or "") == "pillar" then
						local part = effect:IsA("BasePart") and effect
							or effect:FindFirstChildWhichIsA("BasePart")
						local projectedPosition = part and projectedShelterPosition(part)
						if projectedPosition then
							local distance = (projectedPosition - root.Position).Magnitude
							if distance < nearestDistance then
								nearestDistance = distance
								nearestPart = part
							end
						end
					end
				end
				criticalWallPart = nearestPart
			end
			if not criticalWallPart or not criticalWallPart.Parent then
				return nil
			end

			local position, usedBeam = projectedShelterPosition(criticalWallPart)
			if position then
				_G.Raid.lastCrabPullShelter = {
					wall = criticalWallPart,
					position = position,
					usedBeam = usedBeam == true,
					lookVector = criticalWallPart.CFrame.LookVector,
				}
			end
			return position
		end
		local function isCrabPullWindup()
			local targetName = target and string.lower(target.Name or "") or ""
			if not string.find(targetName, "craberno", 1, true)
				and not string.find(targetName, "chaos crab", 1, true)
			then
				return false, nil
			end
			local liveEffects = Workspace:FindFirstChild("Effects")
			if not liveEffects then
				return false, nil
			end
			local wallPosition = getCrabPullSafeWallPosition()
			local pillarCount = 0
			for _, effect in ipairs(liveEffects:GetChildren()) do
				local name = string.lower(effect.Name or "")
				if name == "crabpull" then
					return true, wallPosition
				elseif name == "pillar" then
					pillarCount = pillarCount + 1
					if pillarCount >= 1 then
						return true, wallPosition or getCrabPullSafeWallPosition()
					end
				elseif string.find(name, "warning", 1, true) then
					local part = effect:IsA("BasePart") and effect
						or effect:FindFirstChildWhichIsA("BasePart")
					if part and math.max(part.Size.X, part.Size.Z) >= 500 then
						return true, wallPosition
					end
				end
			end
			return false, wallPosition
		end

		local function promoteToCriticalEscape(wallPosition)
			if not criticalMode then
				criticalMode = true
				_G.Raid.dodge_critical = true
				_G.Raid.dodge_critical_name = "Chaos Crab / Craberno C / CrabPull"
				_G.Raid.dodge_retreating = true
				_G.Raid.dodge_phase = "critical_escape"
				_G.Raid.dodge_phase_started = tick()
			end

			-- Chaos Crab and Craberno share this C attack: it covers the room with an
			-- 800-stud warning and then forcibly
			-- pulls players for three seconds. Move behind one of the four replicated
			-- shelter walls as soon as it exists. During the few frames before the first
			-- pillar appears, retain the known-good webhook dodge geometry as a bounded
			-- fallback; a later refresh replaces it with the latched wall position.
			if wallPosition then
				bestPosition = wallPosition
			else
				local outward = Vector3.new(bestPosition.X - center.X, 0, bestPosition.Z - center.Z)
				if outward.Magnitude < 0.1 then
					outward = Vector3.new(-1, 0, -1)
				end
				outward = outward.Unit
				bestPosition = Vector3.new(
					math.clamp(center.X + outward.X * 300, center.X - 350, center.X + 350),
					center.Y + 210,
					math.clamp(center.Z + outward.Z * 300, center.Z - 350, center.Z + 350)
				)
			end
			bestScore = (bestPosition - targetRoot.Position).Magnitude
			safeCF = _G.Raid.downwardCFrame(bestPosition)
			_G.Raid.lastDodgeSafePosition = bestPosition
			_G.Raid.lastDodgeSafeScore = bestScore
			_G.Raid.lastDodgeThreatCount = #threats
		end

		local function selectChaosAirstrikeCandidate()
			local liveEffects = Workspace:FindFirstChild("Effects")
			if not liveEffects then
				return nil, nil, nil, 0
			end
			local scanNow = tick()
			local warningThreats = {}
			for _, effect in ipairs(liveEffects:GetChildren()) do
				if string.lower(effect.Name or "") == "warning" then
					if not _G.Raid.effectFirstSeen[effect] then
						_G.Raid.effectFirstSeen[effect] = scanNow
					end
					local part = effect:IsA("BasePart") and effect
						or effect:FindFirstChildWhichIsA("BasePart")
					local age = scanNow - _G.Raid.effectFirstSeen[effect]
					if part and age <= 2.35 then
						-- Chaos Crab's warning grows to roughly 300 studs across. Include
						-- a modest buffer, but score its live tweened position every pass
						-- because separate circles can appear at different times.
						table.insert(warningThreats, {
							position = part.Position,
							radius = math.max(185, math.max(part.Size.X, part.Size.Z) * 0.5 + 35),
						})
					end
				end
			end
			if #warningThreats == 0 then
				return nil, nil, nil, 0
			end

			local function scorePosition(position)
				local bossDx = position.X - targetRoot.Position.X
				local bossDz = position.Z - targetRoot.Position.Z
				local clearance = math.sqrt(bossDx * bossDx + bossDz * bossDz) - 120
				for _, threat in ipairs(warningThreats) do
					local dx = position.X - threat.position.X
					local dz = position.Z - threat.position.Z
					clearance = math.min(
						clearance,
						math.sqrt(dx * dx + dz * dz) - threat.radius
					)
				end
				return clearance
			end

			local safestCandidate = nil
			local safestClearance = -math.huge
			for _, candidate in ipairs(chaosAirstrikeCandidates) do
				local clearance = scorePosition(candidate.position)
				if clearance > safestClearance then
					safestClearance = clearance
					safestCandidate = candidate
				end
			end
			local currentClearance = bestPosition and scorePosition(bestPosition) or nil
			return safestCandidate, safestClearance, currentClearance, #warningThreats
		end

		local function applyChaosAirstrikeCandidate(candidate, score, moveNow)
			if candidate then
				selectedLargeCandidate = candidate
				bestPosition = candidate.position
			else
				-- Streaming can hide the raycast candidates for a few frames. Keep the
				-- already-scored dodge destination rather than performing an unscored
				-- corner flip into the barrage.
				bestPosition = bestPosition or Vector3.new(center.X, center.Y + height, center.Z)
			end
			bestScore = score or (bestPosition - targetRoot.Position).Magnitude
			safeCF = _G.Raid.downwardCFrame(bestPosition)
			_G.Raid.lastDodgeSafePosition = bestPosition
			_G.Raid.lastDodgeSafeScore = bestScore
			_G.Raid.dodge_retreating = true
			_G.Raid.dodge_phase = "chaos_airstrike"
			_G.Raid.dodge_phase_started = moveNow
		end

		local function moveForChaosAirstrike()
			local moveNow = tick()
			chaosAirstrikeUntil = moveNow + 0.85
			local nextCandidate, clearance, currentClearance, threatCount =
				selectChaosAirstrikeCandidate()
			if not nextCandidate then
				return false
			end

			local firstAirstrikePass = _G.Raid.dodge_phase ~= "chaos_airstrike"
			local destinationChanged = not bestPosition
				or (nextCandidate.position - bestPosition).Magnitude > 4
			local currentUnsafe = currentClearance == nil or currentClearance < 45
			local materiallySafer = currentClearance == nil
				or clearance >= currentClearance + 15
			local canMoveAgain = moveNow - chaosAirstrikeLastMoveAt >= 0.12

			if firstAirstrikePass
				or (currentUnsafe and destinationChanged and materiallySafer and canMoveAgain)
			then
				chaosAirstrikeLastMoveAt = moveNow
				applyChaosAirstrikeCandidate(nextCandidate, clearance, moveNow)
			else
				-- Keep the current safe point to avoid jitter, but retain the phase and
				-- telemetry while every moving/staggered warning is rescored.
				bestScore = currentClearance or bestScore
				_G.Raid.lastDodgeSafeScore = bestScore
				_G.Raid.lastDodgeThreatCount = threatCount
				_G.Raid.dodge_retreating = true
				_G.Raid.dodge_phase = "chaos_airstrike"
			end
			return true
		end

		local function refreshLargeSafeCFrame()
			if not isLargeBoss or not targetRoot.Parent then
				return
			end
			local now = tick()
			if now - lastLargeRescore < 0.055 then
				return
			end
			lastLargeRescore = now
			local pullWindup, wallPosition = isCrabPullWindup()
			if pullWindup then
				promoteToCriticalEscape(wallPosition)
				return
			end
			if criticalMode then
				return
			end
			local airstrikeWarning = _G.Raid.getChaosAirstrikeWarning(target)
			if airstrikeWarning and moveForChaosAirstrike() then
				return
			end
			if now < chaosAirstrikeUntil then
				return
			elseif _G.Raid.dodge_phase == "chaos_airstrike" then
				-- Force the normal rescore to choose its ordinary combat corner after the
				-- final air-strike warning and impact window end.
				selectedLargeCandidate = nil
				_G.Raid.dodge_retreating = false
				_G.Raid.dodge_phase = "evade"
				_G.Raid.dodge_phase_started = now
			end
			if #largeCandidates == 0 then
				return
			end

			-- Chaos Crab and Craberno place warnings at predicted player positions.
			-- Continuously tracing the whole perimeter crossed those moving zones and
			-- produced three lethal hits during a confirmed dodge. Hold one validated
			-- corner instead, then jump directly to a better corner only when a newly
			-- replicated hazard (or the tracking boss itself) compromises the current
			-- one. This also removes the high-frequency circular motion that looked like
			-- random teleport jitter and generated needless replication traffic.
			local liveThreats = { targetRoot.Position }
			local liveThreatRadii = { 140 }
			local liveEffects = Workspace:FindFirstChild("Effects")
			if liveEffects then
				for _, effect in ipairs(liveEffects:GetChildren()) do
					local pattern = _G.Raid.getAttackPattern(effect)
					if pattern then
						if not _G.Raid.effectFirstSeen[effect] then
							_G.Raid.effectFirstSeen[effect] = now
						end
						local age = now - _G.Raid.effectFirstSeen[effect]
						if age <= _G.Raid.getEffectDangerDuration(effect) then
							local part = effect:IsA("BasePart") and effect
								or effect:FindFirstChildWhichIsA("BasePart")
							if part then
								local radius = math.clamp(math.max(part.Size.X, part.Size.Z) * 0.5, 0, 400)
								local dx = part.Position.X - center.X
								local dz = part.Position.Z - center.Z
								if math.sqrt(dx * dx + dz * dz) <= 650 + radius then
									table.insert(liveThreats, part.Position)
									table.insert(liveThreatRadii, radius)
								end
							end
						end
					end
				end
			end

			local function scoreCandidate(candidate)
				local score = math.huge
				for threatIndex, threat in ipairs(liveThreats) do
					local dx = candidate.position.X - threat.X
					local dz = candidate.position.Z - threat.Z
					local clearance = math.sqrt(dx * dx + dz * dz) - (liveThreatRadii[threatIndex] or 0)
					score = math.min(score, clearance)
				end
				return score
			end

			local currentScore = selectedLargeCandidate and scoreCandidate(selectedLargeCandidate) or -math.huge
			local bestCandidate = selectedLargeCandidate
			local rescoredBest = currentScore
			for _, candidate in ipairs(largeCandidates) do
				local score = scoreCandidate(candidate)
				if score > rescoredBest then
					rescoredBest = score
					bestCandidate = candidate
				end
			end

			-- Do not bounce between nearly equivalent corners. Move only when the
			-- current corner is genuinely threatened or another corner adds a material
			-- safety margin.
			if not selectedLargeCandidate
				or currentScore < 110
				or rescoredBest >= currentScore + 180
			then
				selectedLargeCandidate = bestCandidate
			end
			if selectedLargeCandidate then
				bestPosition = selectedLargeCandidate.position
				bestScore = scoreCandidate(selectedLargeCandidate)
				safeCF = _G.Raid.downwardCFrame(bestPosition)
				_G.Raid.lastDodgeSafePosition = bestPosition
				_G.Raid.lastDodgeSafeScore = bestScore
				_G.Raid.lastDodgeThreatCount = #liveThreats
			end
		end
		-- The warning and its pillars can replicate during the same frame that
		-- starts the ordinary dodge. Promote immediately when they are already
		-- visible; otherwise the 0.1-second monitor below performs the promotion.
		refreshLargeSafeCFrame()
		local function getSafeCFrame()
			if not targetRoot.Parent then
				return nil
			end
			return safeCF
		end

		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
			humanoid.AutoRotate = false
		end
		local dodgeGyro = Instance.new("BodyGyro")
		dodgeGyro.Name = "GenesisDungeonDodgeGyro"
		dodgeGyro.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
		dodgeGyro.D = 50000
		dodgeGyro.P = 500000
		dodgeGyro.Parent = root
		_G.Raid.dodge_gyro = dodgeGyro

		local renderName = _G.Raid.dodge_render_step_name
		pcall(function()
			RunService:UnbindFromRenderStep(renderName)
		end)
		local bound, bindError = pcall(function()
			RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value + 11, function()
				if not _G.Raid.dodge_active
					or _G.Raid.dodge_generation ~= generation
					or not GetSetting("auto_dungeon_v2")
				then
					return
				end
				local liveRoot = _G.Raid.getRoot(LocalPlayer.Character)
				local safeCF = getSafeCFrame()
				if liveRoot and liveRoot.Parent and safeCF then
					local liveHumanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
					if liveHumanoid then
						liveHumanoid.PlatformStand = true
						liveHumanoid.AutoRotate = false
					end
					if dodgeGyro and dodgeGyro.Parent == liveRoot then
						dodgeGyro.CFrame = safeCF
					end
					liveRoot.CFrame = safeCF
					liveRoot.AssemblyLinearVelocity = Vector3.zero
					liveRoot.AssemblyAngularVelocity = Vector3.zero
				end
			end)
		end)
		if not bound then
			_G.Raid.attackState.lastError = "dungeon dodge binding failed: " .. tostring(bindError)
			_G.Raid.stopDodge()
			return
		end
		_G.Raid.dodge_force_thread = true -- compatibility/telemetry: render-step owner.

		_G.Raid.dodge_monitor_thread = task.spawn(function()
			local cleanCount = 0
			while _G.Raid.dodge_active and _G.Raid.dodge_generation == generation do
				task.wait(0.06)
				if not target.Parent
					or not targetHumanoid.Parent
					or targetHumanoid.Health <= 0
					or _G.Raid.current_target ~= target
				then
					_G.Raid.stopDodge()
					break
				end
				refreshLargeSafeCFrame()
				local elapsed = tick() - (_G.Raid.dodge_start_time or tick())
				local playerHumanoid = LocalPlayer.Character
					and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				local recoveryRatio = math.clamp(
					tonumber(GetSetting("raceV3HealthPercent")) or 30,
					1,
					100
				) / 100
				local belowRecoveryThreshold = playerHumanoid
					and playerHumanoid.MaxHealth > 0
					and playerHumanoid.Health > 0
					and playerHumanoid.Health / playerHumanoid.MaxHealth <= recoveryRatio
				local raceStatus = belowRecoveryThreshold and _G.Raid.updateRaceAbility() or nil
				local holdForRecovery = belowRecoveryThreshold
					and raceStatus ~= "active"
					and raceStatus ~= "ready"
				-- The 65-second ceiling is only a deadlock guard. Do not apply the old
				-- unconditional 5.5-second exit here: a low-health recovery dodge can
				-- already be in progress when R becomes ready, and Chaos Crab may have
				-- live meteor warnings at that exact moment. The second-run trace showed
				-- that returning on the ceiling put the character beside Chaos only 0.12
				-- seconds before a 150-stud pillar impact. Let the clean-frame test below
				-- prove the telegraph has ended before returning to activate R.
				if elapsed >= 65 then
					_G.Raid.stopDodge()
					break
				end
				local recentlyDamaged = tick() - (_G.Raid.lastDamageAt or 0) < 0.85
				local dangerStillActive = _G.Raid.detectAttack()
				-- CrabPull begins two seconds after its warning and remains active for
				-- three more. Do not return merely because the warning graphic expired.
				local criticalWindowActive = criticalMode and elapsed < 5.6
				local chaosAirstrikeWindowActive = tick() < chaosAirstrikeUntil
				if holdForRecovery
					or criticalWindowActive
					or chaosAirstrikeWindowActive
					or elapsed < 1.55
					or recentlyDamaged
					or dangerStillActive
				then
					cleanCount = 0
				else
					cleanCount = cleanCount + 1
					if cleanCount >= 6 then
						_G.Raid.stopDodge()
						break
					end
				end
			end
		end)
	end

	_G.Raid.updateDamageState = function()
		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			_G.Raid.lastHealth = nil
			return false
		end
		local health = humanoid.Health
		local previous = _G.Raid.lastHealth
		_G.Raid.lastHealth = health
		if previous and health < previous then
			_G.Raid.lastDamageAmount = previous - health
			_G.Raid.lastDamageAt = tick()
			return true
		end
		return false
	end

	_G.Raid.getRaceAbilityHud = function()
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
		local starterFrame = mainGui and mainGui:FindFirstChild("StarterFrame")
		local statusEffect = starterFrame and starterFrame:FindFirstChild("StatusEffect")
		local raceV3 = statusEffect and statusEffect:FindFirstChild("RaceV3")
		local frame = raceV3 and raceV3:FindFirstChild("Frame")
		local canvas = frame and frame:FindFirstChild("CanvasGroup")
		local textLabel = frame and frame:FindFirstChild("TextLabel")
		local left = canvas and canvas:FindFirstChild("Left")
		local right = canvas and canvas:FindFirstChild("Right")
		local text = textLabel and textLabel:IsA("TextLabel") and textLabel.Text or ""
		local textVisible = textLabel and textLabel:IsA("GuiObject") and textLabel.Visible or false
		local leftVisible = left and left:IsA("GuiObject") and left.Visible or false
		local rightVisible = right and right:IsA("GuiObject") and right.Visible or false
		return {
			present = raceV3 ~= nil and raceV3:IsA("GuiObject") and raceV3.Visible,
			cooling = leftVisible or rightVisible or (textVisible and text ~= ""),
			text = text,
			textVisible = textVisible,
			leftVisible = leftVisible,
			rightVisible = rightVisible,
		}
	end

	-- The visible race aura is cloned into Workspace.Effects and welded to the
	-- character. Cache the matching object so the 30 Hz dungeon loop does not
	-- repeatedly scan every effect. This is behavioral evidence only, never an
	-- ownership requirement: clients without a replicated aura retain the bounded
	-- duration fallback below.
	_G.Raid.hasLocalRaceAura = function(character)
		local state = _G.Raid.raceAbility
		local now = tick()
		if now - (state.auraCheckedAt or 0) < 0.075 then
			return state.auraCached == true
		end
		state.auraCheckedAt = now

		local effects = Workspace:FindFirstChild("Effects")
		if not character or not effects then
			state.auraObject = nil
			state.auraCached = false
			return false
		end

		local function belongsToCharacter(effect)
			if not effect or effect.Parent ~= effects then
				return false
		end
			local weld = effect:FindFirstChildWhichIsA("Weld", true)
			local part0 = weld and weld.Part0
			local part1 = weld and weld.Part1
			return (part0 and part0:IsDescendantOf(character))
				or (part1 and part1:IsDescendantOf(character))
				or false
		end

		if belongsToCharacter(state.auraObject) then
			state.auraCached = true
			return true
		end

		state.auraObject = nil
		for _, effect in ipairs(effects:GetChildren()) do
			if (effect.Name == "Auras" or effect.Name == "AurasPool") and belongsToCharacter(effect) then
				state.auraObject = effect
				state.auraCached = true
				return true
			end
		end
		state.auraCached = false
		return false
	end

	_G.Raid.updateRaceAbility = function()
		local state = _G.Raid.raceAbility
		local now = tick()
		local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		local hud = _G.Raid.getRaceAbilityHud()
		if not humanoid or humanoid.Health <= 0 then
			state.pendingUntil = 0
			state.activeUntil = 0
			state.auraSeen = false
			state.auraEnded = false
			state.auraObject = nil
			state.auraCached = false
			state.healthBefore = nil
			state.humanoid = humanoid
			state.lastResult = "unavailable"
			return "unavailable", hud
		end

		if state.humanoid ~= humanoid then
			state.humanoid = humanoid
			state.pendingUntil = 0
			state.activeUntil = 0
			state.auraSeen = false
			state.auraEnded = false
			state.auraObject = nil
			state.auraCached = false
			state.healthBefore = nil
		end

		local shouldCheckAura = state.pendingUntil > 0
			or now < (state.activeUntil or 0)
			or (state.auraSeen and not state.auraEnded)
		local auraActive = shouldCheckAura and _G.Raid.hasLocalRaceAura(LocalPlayer.Character) or false
		if auraActive then
			state.auraSeen = true
			state.auraEnded = false
			state.auraLastSeenAt = now
		elseif state.auraSeen and not state.auraEnded and now - (state.auraLastSeenAt or 0) > 0.2 then
			-- Resume ordinary positioning as soon as the replicated aura is actually
			-- gone. The short grace avoids a one-frame reparent/flicker interrupt.
			state.auraEnded = true
			state.activeUntil = 0
		end

		if state.pendingUntil > 0 then
			local healThreshold = math.max(750, humanoid.MaxHealth * 0.0125)
			local healed = state.healthBefore ~= nil and humanoid.Health >= state.healthBefore + healThreshold
			if hud.cooling or healed or auraActive then
				state.pendingUntil = 0
				state.activeUntil = math.max(state.activeUntil or 0, (state.lastAttempt or now) + 12.5)
				state.cooldownUntil = math.max(state.cooldownUntil or 0, (state.lastAttempt or now) + 60)
				state.confirmed = (state.confirmed or 0) + 1
				state.lastResult = hud.cooling and "confirmed_hud" or "confirmed_health"
			elseif now >= state.pendingUntil then
				state.pendingUntil = 0
				state.lastResult = "unconfirmed"
			end
		end

		if now < (state.activeUntil or 0) then
			return "active", hud
		end
		if now < (state.pendingUntil or 0) then
			return "pending", hud
		end
		if hud.cooling or now < (state.cooldownUntil or 0) then
			return "cooldown", hud
		end
		return "ready", hud
	end

	_G.Raid.tryRaceAbility = function(targetMob)
		local state = _G.Raid.raceAbility
		local status, hud = _G.Raid.updateRaceAbility()
		if status ~= "ready" or state.inputBusy then
			return status
		end

		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = _G.Raid.getRoot(character)
		local targetRoot = targetMob and targetMob:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or humanoid.MaxHealth <= 0 or not root or not targetRoot then
			return status
		end
		-- Share the user's existing Race V3 HP setting with the fallback retreat.
		-- The two-second roar and ten-second drain need the player close to a target.
		local triggerRatio = math.clamp(tonumber(GetSetting("raceV3HealthPercent")) or 30, 1, 100) / 100
		if humanoid.Health / humanoid.MaxHealth > triggerRatio
			or (root.Position - targetRoot.Position).Magnitude > 32
		then
			return status
		end
		if UserInputService:GetFocusedTextBox() then
			return status
		end

		local now = tick()
		if now - (_G.lastRaceAbilityAttempt or 0) < 1.5 then
			return "recent_input"
		end

		state.lastAttempt = now
		state.pendingUntil = now + 3.25
		-- A failed or unavailable racial ability must never turn into R spam. The
		-- dungeon continues with its normal dodge path while this bounded timer runs.
		state.cooldownUntil = now + 60
		state.auraSeen = false
		state.auraEnded = false
		state.auraLastSeenAt = 0
		state.auraCheckedAt = 0
		state.auraCached = false
		state.auraObject = nil
		state.healthBefore = humanoid.Health
		state.humanoid = humanoid
		state.hudWasPresent = hud.present == true
		state.inputBusy = true
		state.attempts = (state.attempts or 0) + 1
		state.lastResult = "input_sent"
		_G.lastRaceAbilityAttempt = now

		task.spawn(function()
			local ok = pcall(function()
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
				task.wait(0.05)
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
			end)
			state.inputBusy = false
			if not ok then
				state.pendingUntil = 0
				state.cooldownUntil = math.min(state.cooldownUntil, tick() + 5)
				state.lastResult = "input_error"
			end
		end)
		return "pending"
	end

	_G.Raid.findOpeTool = function()
		for _, container in ipairs({ LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }) do
			if container then
				for _, tool in ipairs(container:GetChildren()) do
					if tool:IsA("Tool") and string.lower((tool.Name:gsub("[^%w]", ""))) == "opop" then
						return tool
					end
				end
			end
		end
		return nil
	end

	_G.Raid.getOpeRoom = function()
		local room = Workspace:FindFirstChild("OpeRoom" .. LocalPlayer.Name)
		return room and room:IsA("BasePart") and room or nil
	end

	_G.Raid.isOpeRoomUsable = function()
		local room = _G.Raid.getOpeRoom()
		local playerRoot = _G.Raid.getRoot(LocalPlayer.Character)
		if not room or not playerRoot then
			return false
		end
		local radius = math.max(room.Size.X, room.Size.Y, room.Size.Z) * 0.5 + 15
		if (playerRoot.Position - room.Position).Magnitude > radius then
			return false
		end
		local target = _G.Raid.current_target
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		return not targetRoot or (targetRoot.Position - room.Position).Magnitude <= radius
	end

	_G.Raid.dispatchOpeToggle = function(mouseHit, phase)
		local ope = _G.Raid.findOpeTool()
		local state = _G.Raid.opeState
		if not ope or os.clock() - state.lastToggle < 3.15 or _G.Raid.attackState.skillInFlight > 0 then
			return false
		end

		-- Treat equipping OpOp plus sending Z as one atomic handoff. Previously the
		-- main combat pass could equip the sword again between those two steps,
		-- leaving the character parked with no room and almost no usable attacks.
		local attackState = _G.Raid.attackState
		attackState.opeToolUntil = os.clock() + (phase == "opening" and 12.25 or 1.25)
		local started = _G.Raid.startAttackJob("skill", function()
			local ok, err = pcall(function()
				local liveOpe = _G.Raid.findOpeTool()
				local character = LocalPlayer.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local backpack = LocalPlayer:FindFirstChild("Backpack")
				if not liveOpe or not humanoid or not backpack then
					error("Ope tool or character unavailable")
				end
				if liveOpe.Parent ~= character then
					if liveOpe.Parent ~= backpack then
						error("Ope tool is outside the character inventory")
					end
					humanoid:EquipTool(liveOpe)
					local equipDeadline = os.clock() + 0.45
					repeat
						task.wait()
					until liveOpe.Parent == character or os.clock() >= equipDeadline
				end
				if liveOpe.Parent ~= character then
					error("Ope tool failed to equip")
				end
				_G.Raid.remoteOpeToggle(liveOpe, mouseHit, phase)
			end)
			attackState.opeToolUntil = os.clock() + 0.18
			if not ok then
				error(err)
			end
		end, 12.5)
		if started then
			state.phase = phase
			state.lastToggle = os.clock()
			attackState.skillsDispatched = attackState.skillsDispatched + 1
			attackState.lastSkillId = "DF_" .. ope.Name .. "_Z (room)"
			attackState.skillsByTool[ope.Name] = (attackState.skillsByTool[ope.Name] or 0) + 1
		else
			attackState.opeToolUntil = 0
		end
		return started
	end

	_G.Raid.opez = function()
		local target = _G.Raid.current_target
		local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
		local mouseHit = targetRoot and targetRoot.CFrame or _G.Raid.getFloorCFrame(_G.Raid.current_floor)
		if mouseHit then
			return _G.Raid.dispatchOpeToggle(mouseHit, "opening")
		end
		return false
	end

	_G.Raid.disableOpeRoom = function()
		_G.Raid.inop = false
		local room = _G.Raid.getOpeRoom()
		if room and _G.Raid.opeState.ownedRoom then
			_G.Raid.dispatchOpeToggle(room.CFrame, "closing")
		end
	end

	_G.Raid.handleFruitPower = function()
		local state = _G.Raid.opeState
		local ope = _G.Raid.findOpeTool()
		_G.Raid.has_opop = ope ~= nil
		if not ope then
			_G.Raid.inop = false
			state.phase = "idle"
			return false
		end
		local room = _G.Raid.getOpeRoom()
		if room and _G.Raid.isOpeRoomUsable() then
			if state.phase == "opening" then
				state.ownedRoom = true
			end
			state.phase = "active"
			_G.Raid.inop = true
			return true
		end
		_G.Raid.inop = false
		if room then
			state.ownedRoom = true
			_G.Raid.dispatchOpeToggle(room.CFrame, "closing")
			return false
		end
		if state.phase == "closing" and os.clock() - state.lastToggle < 3.15 then
			return false
		end
		if state.phase == "opening" and os.clock() - state.lastToggle > 4 then
			state.phase = "idle"
		end
		return _G.Raid.opez()
	end

	_G.Raid.beginEntry = function()
		if _G.Raid._entryBusy then
			return
		end
		local committed = _G._GenesisUpdateDungeonCommit()
		local canStart = committed or _G._GenesisCanStartDungeon()
		if not canStart then
			return
		end
		_G.Raid._entryBusy = true
		_G.Raid._mainLoopBusy = true -- compatibility/telemetry: entry worker only
		_G.Raid._entryGeneration = (_G.Raid._entryGeneration or 0) + 1
		local generation = _G.Raid._entryGeneration
		_G.Raid._entryCancelReason = nil
		task.spawn(function()
			local ok, err = pcall(function()
				local function entryStillValid()
					if not GetSetting("auto_dungeon_v2") or _G.Raid._entryGeneration ~= generation then
						return false
					end
					if _G._GenesisUpdateDungeonCommit() then
						return true
					end
					return _G._GenesisCanStartDungeon() == true
				end
				local handoffDeadline = os.clock() + 5
				while fishingOwnsWeaponSlot()
					and entryStillValid()
					and os.clock() < handoffDeadline
				do
					_G._GenesisPrepareCombatFromFishing("dungeon_entry")
					task.wait(0.1)
				end
				if fishingOwnsWeaponSlot()
					or not entryStillValid()
				then
					return
				end
				if _G.Raid.hasConfiguredBasicAttack() then
					_G.Raid.bootstrapBaseCombatTool(4, function()
						return entryStillValid()
					end)
				end
				if not entryStillValid() then
					return
				end
				_G.Raid.clearDungeonFarm()
				if _G.Raid.dodge_active then
					_G.Raid.stopDodge()
				end
				if not _G._GenesisUpdateDungeonCommit() then
					_G.Raid.teleportToDungeonEntrance()
				end
				_G.Raid.selectDifficulty(generation)
			end)
			if not ok then
				_G.Raid.attackState.lastError = tostring(err)
			end
			if _G.Raid._entryGeneration == generation then
				_G.Raid._entryBusy = false
				_G.Raid._mainLoopBusy = false
			end
		end)
	end

	-- MAIN DUNGEON LOOP. All RemoteFunction work is dispatched through bounded
	-- workers, so this Heartbeat path only handles state, targeting, and movement.
	_G.Raid._lastMainStep = 0
	trackGenesisConnection(RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - (_G.Raid._lastMainStep or 0) < 0.03 then
			return
		end
		_G.Raid._lastMainStep = now
		local ok, err = pcall(function()
			local dungeonCommitted = _G._GenesisUpdateDungeonCommit()
			if not GetSetting("auto_dungeon_v2") then
				if _G.Raid._wasDungeon then
					_G.Raid.clearVeyzorAnimationWatch()
					_G.Raid._entryGeneration = (_G.Raid._entryGeneration or 0) + 1
					_G.Raid._entryBusy = false
					_G.Raid._mainLoopBusy = false
					_G.Raid.stopCombat()
					_G.Raid.stopDodge()
					_G.Raid.disableOpeRoom()
					_G.Raid._wasDungeon = false
					_G.Raid.inraid = false
				end
				return
			end

			_G.Raid._wasDungeon = true
			if not dungeonCommitted then
				local canStart, reason = _G._GenesisCanStartDungeon()
				if not canStart then
					if _G.Raid._entryBusy then
						_G._GenesisCancelDungeonEntry(reason)
					end
					_G.Raid.current_target = nil
					_G.Raid.attackState.requestedUntil = 0
					_G.Raid.clearDungeonFarm()
					if _G.Raid.dodge_active then
						_G.Raid.stopDodge()
					end
					return
				end
			end
			if fishingOwnsWeaponSlot() then
				_G._GenesisPrepareCombatFromFishing("dungeon")
				return
			end

			-- Use the loading screen's confirmed server action; autoPlay is debounced.
			if autoPlay() then
				return
			end

			if not _G.Raid.checkInRaid() then
				_G.Raid.current_target = nil
				_G.Raid.attackState.requestedUntil = 0
				_G.Raid.clearDungeonFarm()
				if _G.Raid.dodge_active then
					_G.Raid.stopDodge()
				end
				_G.Raid.current_floor = 1
				_G.Raid.last_floor = 1
				-- If the picker has appeared (or just closed), entry is irreversible.
				-- beginEntry detects that latch and only handles selection/transition;
				-- it will never teleport back to the entrance in this state.
				_G.Raid.beginEntry()
				return
			end

			local floor = _G.Raid.updateFloor()
			if floor ~= _G.Raid.last_floor and floor >= 1 and floor <= 5 then
				_G.Raid.last_floor = floor
				_G.Raid.clearDungeonFarm()
				if _G.Raid.dodge_active then
					_G.Raid.stopDodge()
				end
				if GetSetting("ope_method_dungeon") then
					_G.Raid.disableOpeRoom()
				end
				_G.Raid.teleportToFloor(floor)
				_G.Raid._floorSettleUntil = os.clock() + 0.45
				return
			end
			if os.clock() < (_G.Raid._floorSettleUntil or 0) then
				return
			end

			if (GetSetting("dungeon_cast_method") or "Remote (Aimbot)") == "Remote (Aimbot)"
				and _G.Raid.hasConfiguredBasicAttack()
				and not _G.Raid.ensureBaseCombatTool()
			then
				_G.Raid.beginLoadoutBootstrap()
				_G.Raid.attackState.requestedUntil = 0
				_G.Raid.clearDungeonFarm()
				return
			end

			local targetMob, isBoss = _G.Raid.selectTarget()
			_G.Raid.current_target = targetMob
			_G.Raid.boss_dungeon = isBoss == true
			_G.Raid.watchVeyzorAnimations(targetMob)
			if not targetMob or not targetMob:FindFirstChild("HumanoidRootPart") then
				_G.Raid.attackState.requestedUntil = 0
				_G.Raid.clearDungeonFarm()
				return
			end

			local hrp = targetMob.HumanoidRootPart
			_G.pos_skill = hrp.CFrame
			_G.Raid.updateDamageState()
			local raceStatus = _G.Raid.updateRaceAbility()
			local raceState = _G.Raid.raceAbility
			local raceProtecting = raceStatus == "active"
				or (raceStatus == "pending"
					and raceState.hudWasPresent
					and tick() - (raceState.lastAttempt or 0) <= 0.75)
			local playerHumanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
			local recoveryRatio = math.clamp(tonumber(GetSetting("raceV3HealthPercent")) or 30, 1, 100) / 100
			local belowRecoveryThreshold = playerHumanoid
				and playerHumanoid.MaxHealth > 0
				and playerHumanoid.Health > 0
				and playerHumanoid.Health / playerHumanoid.MaxHealth <= recoveryRatio
			local raceReadyForRecovery = belowRecoveryThreshold and raceStatus == "ready"
			local largeTrackingBoss = isBoss and _G.Raid.isLargeTrackingBoss(targetMob)
			local isVeyzor = isBoss and string.find(targetMob.Name or "", "Veyzor", 1, true) ~= nil
			local danger, attackPos, attackPattern = false, nil, nil
			local chaosAirstrikeWarning, chaosAirstrikePosition =
				_G.Raid.getChaosAirstrikeWarning(targetMob)
			if GetSetting("dodge_v2")
				and not _G.Raid.dodge_active
				and isBoss
				and (chaosAirstrikeWarning or isVeyzor or (not raceProtecting and not raceReadyForRecovery))
			then
				if chaosAirstrikeWarning then
					danger = true
					attackPos = chaosAirstrikePosition or hrp.Position
				else
					danger, attackPos, attackPattern = _G.Raid.scanAttacks(true)
				end
			end
			local veyzorMountWarning = attackPattern == "veyzor_mount_windup"

			-- At the configured Race V3 recovery threshold, a ready racial ability takes
			-- priority over starting another retreat. If the prior dodge left the
			-- character far away, this pass returns to the target and the next pass
			-- activates R at close range. An existing dodge still finishes normally.
			if not _G.Raid.dodge_active
				and (not danger or (raceReadyForRecovery and not chaosAirstrikeWarning and not veyzorMountWarning))
			then
				raceStatus = _G.Raid.tryRaceAbility(targetMob)
				raceProtecting = raceStatus == "active"
					or (raceStatus == "pending"
						and raceState.hudWasPresent
						and tick() - (raceState.lastAttempt or 0) <= 0.75)
				raceReadyForRecovery = belowRecoveryThreshold and raceStatus == "ready"
			end
			if GetSetting("dodge_v2") and not _G.Raid.dodge_active then
				-- Preserve close combat between attacks so M1 and short-range skills
				-- connect. Dodge actual boss telegraphs, not ordinary damage that has
				-- already landed; the latter repeatedly stranded combat hundreds of studs
				-- away from normal floor mobs.
				-- R and the fallback retreat share the configured HP threshold. While R is
				-- cooling, unavailable, or unconfirmed, hold the safe position instead
				-- of letting sustained effects (notably Craberno's circles) drain the
				-- player from the configured recovery threshold to death. A ready R is
				-- allowed to return close first.
				local recoveryRetreat = belowRecoveryThreshold
					and not raceProtecting
					and not raceReadyForRecovery
				if recoveryRetreat
					or (danger and (chaosAirstrikeWarning or veyzorMountWarning or not raceProtecting))
				then
					local customHeight = 210
					if largeTrackingBoss then
						customHeight = 230
					end
					_G.Raid.startDodge(attackPos, customHeight)
				end
			end

			_G.Raid.buso()
			_G.Raid.ken()
			_G.Raid.hao()

			if GetSetting("ope_method_dungeon") and _G.Raid.findOpeTool() then
				_G.Raid.handleFruitPower()
			else
				_G.Raid.inop = false
			end

			if not _G.Raid.dodge_retreating
				and tick() - (_G.Raid.last_tool_switch or 0) >= (GetSetting("dungeon_tool_switch") or 0.5)
			then
				local switchedTool = _G.Raid.cycleTools()
				if switchedTool then
					_G.Raid.last_tool_switch = tick()
				end
			end

			if not _G.Raid.dodge_active then
				_G.Raid.applyDungeonFarm(targetMob)
			end
			-- Dodges remain inside the floor envelope and within usable remote range,
			-- so combat continues while the render-step dodge owner moves the player.
			if not _G.Raid.dodge_retreating then
				_G.Raid.click()
				_G.Raid.autoskill()
			else
				_G.Raid.attackState.requestedUntil = 0
			end
		end)
		if not ok then
			_G.Raid.attackState.lastError = tostring(err)
		end
	end))

	-- Dungeon-tab UI. It is created after the Raid backend so every callback can
	-- call the finalized dungeon helpers without changing their behavior.
	pcall(function()
		Window:CreateDropdown(uiSections.dungeonEntry, {
			Label = "Difficulty",
			Options = { "Easy", "Normal", "Hard" },
			Default = GetSetting("dungeon_select") or "Easy",
			Callback = function(selected)
				saveAndApply("dungeon_select", selected)
			end,
		})

		Window:CreateToggle(uiSections.dungeonEntry, {
			Text = "Enable Auto Dungeon",
			Default = GetSetting("auto_dungeon_v2") or false,
			Callback = function(state)
				saveAndApply("auto_dungeon_v2", state)
				if not state then
					_G.Raid._entryGeneration = (_G.Raid._entryGeneration or 0) + 1
					_G.Raid._entryBusy = false
					_G.Raid._mainLoopBusy = false
					_G.Raid.stopCombat()
					_G.Raid.clearDungeonFarm()
					if _G.Raid.dodge_active then
						_G.Raid.stopDodge()
					end
				end
			end,
		})

		Window:CreateToggle(uiSections.dungeonEntry, {
			Text = "Stop Dungeons When Sea Events Are Near",
			Default = GetSetting("stopDungeonNearSeaEvent") ~= false,
			Callback = function(state)
				saveAndApply("stopDungeonNearSeaEvent", state)
			end,
		})

		Window:CreateLabel(uiSections.dungeonEntry, {
			Text = "Stops only a new, uncommitted entry when a Sea Event is 15:00 or closer. Once the difficulty picker appears or the dungeon begins, Dungeon keeps control until it ends.",
			Color = SpectrumX.Theme.TextSecondary,
			Wrapped = true,
		})

		Window:CreateSlider(uiSections.dungeonLoadout, {
			Text = "Tool Switch Speed (s)",
			Min = 0.1,
			Max = 2,
			Default = GetSetting("dungeon_tool_switch") or 0.5,
			Increment = 0.1,
			Callback = function(v)
				saveAndApply("dungeon_tool_switch", v)
			end,
		})

		Window:CreateToggle(uiSections.dungeonSafety, {
			Text = "Auto Dodge",
			Default = GetSetting("dodge_v2") ~= false,
			Callback = function(state)
				saveAndApply("dodge_v2", state)
			end,
		})

		Window:CreateToggle(uiSections.dungeonLoadout, {
			Text = "Ope Method",
			Default = GetSetting("ope_method_dungeon") ~= false,
			Callback = function(state)
				saveAndApply("ope_method_dungeon", state)
			end,
		})

		Window:CreateMultiDropdown(uiSections.dungeonLoadout, {
			Label = "Tools (used when Ope is unavailable)",
			Options = { "Sword", "Combat", "Fruit Power" },
			Default = GetSetting("dungeon_outside_tools") or { "Combat", "Fruit Power" },
			Callback = function(selected)
				saveAndApply("dungeon_outside_tools", selected)
			end,
		})

		Window:CreateDropdown(uiSections.dungeonLoadout, {
			Label = "Attack Method",
			Options = { "Default (Random)", "Remote (Aimbot)" },
			Default = GetSetting("dungeon_cast_method") or "Remote (Aimbot)",
			Callback = function(selected)
				saveAndApply("dungeon_cast_method", selected)
			end,
		})

		Window:CreateDropdown(uiSections.dungeonPosition, {
			Label = "Dungeon Method",
			Options = { "Stand Above Mobs", "Orbit Above Mobs" },
			Default = GetSetting("dungeon_method") or "Stand Above Mobs",
			Callback = function(selected)
				saveAndApply("dungeon_method", selected)
				_G.Raid.clearDungeonFarm()
			end,
		})

		Window:CreateSlider(uiSections.dungeonPosition, {
			Text = "Farm Height (above mobs)",
			Min = 3,
			Max = 40,
			Default = GetSetting("dungeon_farm_height") or 8,
			Increment = 1,
			Callback = function(v)
				saveAndApply("dungeon_farm_height", v)
			end,
		})

		Window:CreateSlider(uiSections.dungeonPosition, {
			Text = "Orbit Speed",
			Min = 0.5,
			Max = 8,
			Default = GetSetting("orbit_speed") or 2.5,
			Increment = 0.1,
			Callback = function(v)
				saveAndApply("orbit_speed", v)
			end,
		})

		Window:CreateLabel(uiSections.dungeonGuide, {
			Text = "Dungeon uses the Haki and Z/X/C/V/F/B/E choices from the Combat tab.",
			Color = SpectrumX.Theme.TextSecondary,
			Wrapped = true,
		})
	end)

	print("ar: done too")
end
return run(nil, nil, nil, nil)
