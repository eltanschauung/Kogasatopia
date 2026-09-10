public void ConVarChanged_Multiplier(ConVar convar, const char[] oldValue, const char[] newValue)
{
	UpdateMultiplierValue();
	if (ShouldUseMultiplier())
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsHumanClientInGame(i))
			{
				MaybeScheduleReminder(i);
			}
		}
	}
}

void UpdateMultiplierValue()
{
	g_iMultiplier = (g_hMultiplierCvar != null) ? g_hMultiplierCvar.IntValue : 1;
	if (!ShouldUseMultiplier())
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			CancelReminderTimer(i);
		}
	}
}

bool ShouldUseMultiplier()
{
	int value = g_iMultiplier;
	if (value < 0)
	{
		value = -value;
	}
	return value > 1;
}

int GetEffectiveMultiplier()
{
	int value = g_iMultiplier;
	if (value < 0)
	{
		value = -value;
	}
	return (value > 1) ? value : 1;
}

void MaybeScheduleReminder(int client)
{
	CancelReminderTimer(client);
	if (!ShouldUseMultiplier() || !IsHumanClientInGame(client))
	{
		return;
	}

	g_hReminderTimer[client] = CreateTimer(60.0, Timer_MultiplierReminder, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void CancelReminderTimer(int client)
{
	if (!IsClientIndexValid(client))
	{
		return;
	}

	if (g_hReminderTimer[client] != null)
	{
		CloseHandle(g_hReminderTimer[client]);
		g_hReminderTimer[client] = null;
	}
}

void CancelStatsRetryTimer(int client)
{
	if (!IsClientIndexValid(client))
	{
		return;
	}

	if (g_hStatsRetryTimer[client] != null)
	{
		CloseHandle(g_hStatsRetryTimer[client]);
		g_hStatsRetryTimer[client] = null;
	}
}

void ScheduleStatsRetry(int client)
{
	CancelStatsRetryTimer(client);
	if (!IsClientIndexValid(client))
	{
		return;
	}

	g_hStatsRetryTimer[client] = CreateTimer(5.0, Timer_RetryStatsLoad, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RetryStatsLoad(Handle timer, any data)
{
	int client = GetClientOfUserId(data);
	if (!IsClientIndexValid(client) || !IsClientInGame(client))
	{
		return Plugin_Stop;
	}

	if (g_hStatsRetryTimer[client] == timer)
	{
		g_hStatsRetryTimer[client] = null;
	}

	AttemptLoadClientStats(client);
	return Plugin_Stop;
}

public Action Timer_MultiplierReminder(Handle timer, any data)
{
	int client = GetClientOfUserId(data);
	if (!IsClientIndexValid(client) || !IsClientInGame(client))
	{
		return Plugin_Stop;
	}

	if (g_hReminderTimer[client] == timer)
	{
		g_hReminderTimer[client] = null;
	}

	if (!ShouldUseMultiplier())
	{
		return Plugin_Stop;
	}

	if (IsClientRedlisted(client))
	{
		return Plugin_Stop;
	}

	int mult = GetEffectiveMultiplier();
	CPrintToChat(client, "{green}[Hugs]{default} There's an ongoing {crimson}%dx rapes event!!!{default} All hugs & rapes are multiplied by {crimson}%d{default}.", mult, mult);
	return Plugin_Stop;
}

