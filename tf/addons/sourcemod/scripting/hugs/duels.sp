	public Action Command_Duel(int client, int args)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
			return Plugin_Handled;

		if (args < 1)
		{
			PrintToChat(client, "Usage: !duel <player name substring>");
			return Plugin_Handled;
		}

		if (g_bDuelRequested || g_bDuelActive)
		{
			PrintToChat(client, "A duel is already pending or in progress.");
			return Plugin_Handled;
		}

		char targetName[128];
		GetCmdArgString(targetName, sizeof(targetName));
		StripQuotes(targetName);
		TrimString(targetName);

		int target = FindPlayerBySubstring(targetName, client);
		if (target == 0)
		{
			PrintToChat(client, "No player found matching \"%s\".", targetName);
			return Plugin_Handled;
		}
		if (target == client)
		{
			PrintToChat(client, "You cannot duel yourself.");
			return Plugin_Handled;
		}

		// Set state
		g_iRequester     = client;
		g_iTarget        = target;
		g_bDuelRequested = true;
		g_iScoreReq      = 0;
		g_iScoreTgt      = 0;

		float timeout = g_hRequestTimeout.FloatValue;
		StartRequestTimer(timeout);

		// Private messages only to challenger and target
		PrintToChatAll("\x04[RAPE DUEL]\x01 %N challenged %N to a duel! (expires in %.0fs)", client, target, timeout);
		PrintToChat(target, "\x04[RAPE DUEL]\x01 %N challenged you to a duel! Type !accept to start! (expires in %.0fs).", client, timeout);

		// Play sound to both
		ClientCommand(client, "playgamesound ui/duel_challenge.wav");
		ClientCommand(target, "playgamesound ui/duel_challenge.wav");

		return Plugin_Handled;
	}

	public Action Command_Accept(int client, int args)
	{
		if (!IsClientIndexValid(client) || !IsClientInGame(client))
			return Plugin_Handled;

		if (!g_bDuelRequested || g_bDuelActive || client != g_iTarget)
			return Plugin_Continue;

		CancelRequestTimer();

		g_bDuelRequested = false;
		g_bDuelActive    = true;
		g_iScoreReq      = 0;
		g_iScoreTgt      = 0;
		CaptureDuelParticipantSnapshots();

		int targetScore = g_hTargetScore.IntValue;

		PrintToChatAll("\x04[RAPE DUEL]\x01 %N accepted %N's challenge! First to %d rapes wins!",
					   g_iTarget, g_iRequester, targetScore);

		ClientCommand(g_iTarget, "playgamesound ui/duel_challenge_accepted.wav");
		ClientCommand(g_iRequester, "playgamesound ui/duel_challenge_accepted.wav");
		return Plugin_Handled;
	}

	/* ---------------- Events ---------------- */

	public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
	{
		if (!g_bDuelActive) return;

		int victim   = GetClientOfUserId(event.GetInt("userid"));
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		int deathFlags = event.GetInt("death_flags");

		if (!IsClientIndexValid(attacker) || !IsClientIndexValid(victim))
			return;

		if (deathFlags & 32)
			return;

		bool duelKill = (attacker == g_iRequester && victim == g_iTarget) ||
						(attacker == g_iTarget     && victim == g_iRequester);

		if (!duelKill)
			return;

		if (attacker == g_iRequester)
			g_iScoreReq++;
		else
			g_iScoreTgt++;

		PrintToChatAll("\x04[RAPE DUEL]\x01 %N raped %N! Score: %N %d - %N %d",
					   attacker, victim,
					   g_iRequester, g_iScoreReq,
					   g_iTarget,    g_iScoreTgt);

		int targetScore = g_hTargetScore.IntValue;
		if (g_iScoreReq >= targetScore || g_iScoreTgt >= targetScore)
		{
			int winner = (g_iScoreReq > g_iScoreTgt) ? g_iRequester : g_iTarget;
			int loser  = (winner == g_iRequester) ? g_iTarget : g_iRequester;

			PrintToChatAll("\x04[RAPE DUEL]\x01 %N HAS RAPED %N!!! Final Score: %N %d - %N %d",
						   winner, loser,
						   g_iRequester, g_iScoreReq,
						   g_iTarget,    g_iScoreTgt);
			UpdateRapeStatsDuel(g_iRequester, g_iTarget, g_iScoreReq, g_iScoreTgt);
			int winnerScore = (winner == g_iRequester) ? g_iScoreReq : g_iScoreTgt;
			int loserScore = (winner == g_iRequester) ? g_iScoreTgt : g_iScoreReq;
			RecordDuelVictory(winner, loser, winnerScore, loserScore, "target_score");
			ResetDuel();
		}
	}

	public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
	{
		if (!g_bDuelActive && !g_bDuelRequested)
			return;

		if (g_bDuelRequested)
		{
			// Pending request never accepted before round end
			PrintToChatSafe(g_iRequester, "\x04[RAPE DUEL]\x01 Duel request with %N expired at round end.", g_iTarget);
			PrintToChatSafe(g_iTarget,    "\x04[RAPE DUEL]\x01 Duel request from %N expired at round end.", g_iRequester);
			ResetDuel();
			return;
		}

		if (g_iScoreReq == 0 && g_iScoreTgt == 0)
		{
			PrintToChatAll("\x04[RAPE DUEL]\x01 Duel between %N and %N ended with no rapes.", g_iRequester, g_iTarget);
		}
		else if (g_iScoreReq == g_iScoreTgt)
		{
			PrintToChatAll("\x04[RAPE DUEL]\x01 Duel between %N and %N ended in a tie (%d - %d).",
						   g_iRequester, g_iTarget, g_iScoreReq, g_iScoreTgt);
		}
		else
		{
			int winner = (g_iScoreReq > g_iScoreTgt) ? g_iRequester : g_iTarget;
			int loser  = (winner == g_iRequester) ? g_iTarget : g_iRequester;
			PrintToChatAll("\x04[RAPE DUEL]\x01 Round ended: %N wins the rape duel over %N! Final Score: %N %d - %N %d",
						   winner, loser,
						   g_iRequester, g_iScoreReq,
						   g_iTarget,    g_iScoreTgt);
			int winnerScore = (winner == g_iRequester) ? g_iScoreReq : g_iScoreTgt;
			int loserScore = (winner == g_iRequester) ? g_iScoreTgt : g_iScoreReq;
			RecordDuelVictory(winner, loser, winnerScore, loserScore, "round_end");
		}
		UpdateRapeStatsDuel(g_iRequester, g_iTarget, g_iScoreReq, g_iScoreTgt);
		ResetDuel();
	}

