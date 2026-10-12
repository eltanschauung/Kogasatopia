// Full RTD owns these hooks only while selected for the current map. The
// optional bridge owns automatic forwards, which SourceMod cannot unregister
// individually. Keeping it under plugins/disabled prevents automatic loading.
#define RTD_FULL_EVENTS_PLUGIN "disabled/rtd_full_events.smx"
Handle g_hFullBridgeLoadTimer;

public int Native_GetRuntimeOwner(Handle plugin, int params)
{
	return view_as<int>(GetMyHandle());
}

void InitFireworkRuntime()
{
	Perk firework = g_hPerkContainer.Get("firework");
	if (firework == null)
		return;
	Firework_Init(firework);
	char sample[PLATFORM_MAX_PATH];
	firework.GetSound(sample, sizeof(sample));
	if (sample[0])
		PrecacheSound(sample);
}

bool ReplyIfFullRtdDisabled(int client)
{
	if (!g_bFireworkOnly)
		return false;
	ReplyToCommand(client, "[RTD] RTD is disabled; !firework is still available.");
	return true;
}

void EnsureRtdCooldownHudTimer()
{
	if (g_hRtdCooldownHudTimer == null)
		g_hRtdCooldownHudTimer = CreateTimer(1.0, Timer_RtdCooldownHud, _, TIMER_REPEAT);
}

void HookFullRtdClient(int client)
{
	if (!g_bFullClientHooked[client])
	{
		SDKHook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		g_bFullClientHooked[client] = true;
	}
}

void UnhookFullRtdClient(int client)
{
	if (g_bFullClientHooked[client])
	{
		SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		g_bFullClientHooked[client] = false;
	}
}

void StartFullRtdRuntime()
{
	if (g_bFullRuntimeActive || g_bFireworkOnly)
		return;
	g_bFullRuntimeActive = true;
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_changeclass", Event_ClassChange);
	HookEvent("teamplay_round_active", Event_RoundActive);
	HookEvent("post_inventory_application", Event_Resupply);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_chargedeployed", Event_UberchargeDeployed);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("teamplay_round_start", Event_RoundStart);
	HookEvent("arena_round_start", Event_RoundStart);
	HookEvent("mvm_begin_wave", Event_RoundStart);
	AddCommandListener(Listener_Say, "say");
	AddCommandListener(Listener_Say, "say_team");
	AddCommandListener(Listener_Voice, "voicemenu");
	AddNormalSoundHook(Listener_Sound);
	Storage_Precache();
	Stocks_OnMapStart();
	PrecachePerkSounds();
	Events.Init();
	InitPerks();
	EnsureRtdCooldownHudTimer();
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client))
			HookFullRtdClient(client);
	ServerCommand("sm plugins load " ... RTD_FULL_EVENTS_PLUGIN);
	// Console-buffer execution is deferred/reentrant in some map transitions.
	g_hFullBridgeLoadTimer = CreateTimer(0.1, Timer_VerifyFullRtdBridge, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_VerifyFullRtdBridge(Handle timer)
{
	if (timer != g_hFullBridgeLoadTimer)
		return Plugin_Stop;
	g_hFullBridgeLoadTimer = null;
	if (g_bFullRuntimeActive)
	{
		Handle bridge = FindPluginByFile(RTD_FULL_EVENTS_PLUGIN);
		if (bridge == null || GetPluginStatus(bridge) != Plugin_Running)
			SetFailState("Full RTD requires plugins/" ... RTD_FULL_EVENTS_PLUGIN);
	}
	return Plugin_Stop;
}

void StopFullRtdRuntime(RTDRemoveReason reason)
{
	if (!g_bFullRuntimeActive)
		return;
	// A queued unload may run after this function returns; block its forwards
	// before releasing any event/homing state. No ServerExecute in OnPluginEnd.
	g_bFullRuntimeActive = false;
	delete g_hFullBridgeLoadTimer;
	ResetAllClients(reason, .bForce=false);
	ServerCommand("sm plugins unload " ... RTD_FULL_EVENTS_PLUGIN);
	RemoveCommandListener(Listener_Say, "say");
	RemoveCommandListener(Listener_Say, "say_team");
	RemoveCommandListener(Listener_Voice, "voicemenu");
	RemoveNormalSoundHook(Listener_Sound);
	UnhookEvent("player_death", Event_PlayerDeath);
	UnhookEvent("player_changeclass", Event_ClassChange);
	UnhookEvent("teamplay_round_active", Event_RoundActive);
	UnhookEvent("post_inventory_application", Event_Resupply);
	UnhookEvent("player_hurt", Event_PlayerHurt);
	UnhookEvent("player_chargedeployed", Event_UberchargeDeployed);
	UnhookEvent("player_team", Event_PlayerTeam);
	UnhookEvent("teamplay_round_start", Event_RoundStart);
	UnhookEvent("arena_round_start", Event_RoundStart);
	UnhookEvent("mvm_begin_wave", Event_RoundStart);
	UnhookEvent("teamplay_round_start", Event_Homing_RoundStart);
	for (int client = 1; client <= MaxClients; client++)
		UnhookFullRtdClient(client);
	Events.Cleanup();
	delete g_hHoming;
	g_iActiveEntitySpawnedSubscribers = 0;
	g_bIsRegisteringOpen = false;
}

public bool RTD_Full_IsEnabled()
{
	return g_bFullRuntimeActive && !g_bFireworkOnly;
}
