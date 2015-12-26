#include <sourcemod>
#include <sdktools>
#include <adminmenu>
#include <builtinvotes>
#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"

//Global Vars
new Handle:g_hModVote = INVALID_HANDLE;
new Handle:g_pluginNameArr;
new Handle:g_pluginFilenameArr;

new g_pluginReady=0;

new bool:g_pluginArrayBuilt = false;
new String:g_lastCampaign[80];

new String:g_DefaultDisabled[30][64];
new String:g_PluginsUsed[30][64];
new g_pluginStates[30];
new g_clientsPluginVoteId[8];
new g_pluginIdInVote = 0;

//ConVars
new Handle:PluginsDefaultDisabled;
new Handle:PluginsUsedFilter;
new Handle:PluginsResetAtCampaign;


public Plugin:myinfo =
{
	name = "Mod Vote",
	author = "Patrick Evans & Blazers Team",
	description = "Plugin for allowing players to vote other plugins on or off",
	version = "2.1.4.2",
	url = "http://www.sourcemod.net/"
};
 
public OnPluginStart()
{
	// Perform one-time startup tasks ..
	RegConsoleCmd("sm_mod", VoteModsMenu);
	
	PluginsDefaultDisabled = CreateConVar("plugins_default_disabled","","What plugins you want disabled by default (use full filename, and seperate by |)",FCVAR_PLUGIN);
	PluginsUsedFilter = CreateConVar("plugins_used_filter","","What plugins you want used for voting (use full filename, and seperate by |)",FCVAR_PLUGIN);
	PluginsResetAtCampaign = CreateConVar("plugins_reset_after_campaign","1","Should plugins be reset to default enabled/disabled on campaign change? 0 = Don't Reset, 1 = Reset",FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	AutoExecConfig(true,"l4d_pluginsvote");	
	
	g_pluginNameArr = CreateArray(256);	
	g_pluginFilenameArr = CreateArray(64);
	
	//Set g_lastMap to something random so that when plugin first starts it registers it as a new campaign
	strcopy( g_lastCampaign, sizeof(g_lastCampaign),"100 Narwhals on the wall");
	
    	HookEvent("round_start", _RoundStart);	
}

public _RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{	
	new bool:isNewCampaign = CheckNewCampaign();
	new reset = GetConVarInt(PluginsResetAtCampaign);
	
	if( !g_pluginArrayBuilt )
	{
		return;
	}
	
	if( (reset == 1) && isNewCampaign )
	{
		LogMessage( "Reset Plugins On Campaign Change Is On, Resetting Plugins Now " );
		DisableDefaultDisabledPlugins();
	}	
}

bool:CheckNewCampaign()
{
	decl String:mapName[256];
	decl String:mapParts[3][30];
	decl String:campaign[30];
	
	GetCurrentMap(mapName,sizeof(mapName));
	
	ExplodeString(mapName,"_",mapParts,3,30);
	
	new campaignNameEnd = strlen(mapParts[1])-2;
	strcopy(campaign,sizeof(campaign), mapParts[1]);
	campaign[campaignNameEnd] = '\0';
	
	if( strcmp( campaign, g_lastCampaign, false ) == 0  )
	{
		//The lastCampaign is the same as current campaigns so not a new campaign
		return false;
	}
	else
	{
		//The lastCampaign is not the same as current campaigns so its a new campaign
		LogMessage( "New Campaign Detected, Reset Default Plugins Should Occur If Setting Is On " );
		strcopy( g_lastCampaign, sizeof(g_lastCampaign), campaign);
		return true;
	}
}

DisableDefaultDisabledPlugins()
{
	new String:cmd[88];
	ServerCommand("sm plugins load_unlock");
	for( new i=0; i<30; i++ )
	{
		if( strlen(g_DefaultDisabled[i]) > 1 )
		{
			strcopy(cmd,sizeof(cmd),"sm plugins unload optional/coop/");
			StrCat(cmd,sizeof(cmd),g_DefaultDisabled[i]);
			ServerCommand(cmd);
			g_pluginStates[i] = 0;
		}
	}
	ServerCommand("sm plugins load_lock");
}

public OnAllPluginsLoaded()
{
	g_pluginReady = 1;
}

public Action:VoteModsMenu(client,args)
{
    if( g_pluginReady == 0 || !g_pluginArrayBuilt )
    {
    	PrintToChat(client,"\x03[VoteMod]\x01 Mod Voter Is Not Ready Yet. Please Try Again...");
    	return Plugin_Handled;
    }
    
    new Handle:menu = CreateMenu(ModsMenuHandler);
    new numPlugins = GetArraySize(g_pluginNameArr);
    
    decl String:plName[256];
    decl String:plPosition[2];
    decl String:menuItemTitle[320];
    
    SetMenuTitle(menu, "Choose Mod");
    
    for( new i=0; i<numPlugins; i++)
    {	
    	GetModName(i,plName,sizeof(plName));
    	IntToString(i,plPosition,sizeof(plPosition));	
    	strcopy(menuItemTitle,sizeof(menuItemTitle),plName);
    	StrCat(menuItemTitle,sizeof(menuItemTitle)," ( Currently ");
    	if( g_pluginStates[i] == 1 )
    	{
    		StrCat(menuItemTitle,sizeof(menuItemTitle)," ON )");
    	}
    	else
    	{
    		StrCat(menuItemTitle,sizeof(menuItemTitle)," OFF )");
    	}
    	AddMenuItem(menu, plPosition, menuItemTitle);
    }
    
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    
    return Plugin_Handled;
}

VoteModConfirm(client,plId)
{
    decl String:menuTitle[300];
    decl String:plName[256];
    new Handle:menu = CreateMenu(ModConfirmMenuHandler);
    
    GetModName(plId,plName,sizeof(plName));
    g_clientsPluginVoteId[client] = plId;
    
    if( g_pluginStates[plId] == 0 )
    {
    	strcopy(menuTitle,sizeof(menuTitle),"Vote To Turn ON ");
    	StrCat(menuTitle,sizeof(menuTitle),plName);
		StrCat(menuTitle,sizeof(menuTitle)," ?");
    }
    else
    {
    	strcopy(menuTitle,sizeof(menuTitle),"Vote To Turn OFF ");
    	StrCat(menuTitle,sizeof(menuTitle),plName);
		StrCat(menuTitle,sizeof(menuTitle)," ?");
    }
    
    SetMenuTitle(menu, menuTitle);
    
    AddMenuItem(menu, VOTE_YES, "Sure");
    AddMenuItem(menu, VOTE_NO, "Not sure");
    
    SetMenuExitButton(menu, true);
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public ModsMenuHandler(Handle:menu, MenuAction:action, client, itemNum)
{
	decl String:info[2];
	new plId = 0;
	
	if ( action == MenuAction_Select ) 
	{
		GetMenuItem(menu,itemNum,info,sizeof(info));
		plId = StringToInt(info);
		VoteModConfirm(client,plId);
	}	
}

public ModConfirmMenuHandler(Handle:menu, MenuAction:action, client, itemNum)
{
	decl String:info[64];
	
	if ( action == MenuAction_Select ) 
	{
		GetMenuItem(menu,itemNum,info,sizeof(info));
		if( strcmp(info,VOTE_YES) == 0 )
		{
			DisplayModVote(client);
		}
	}	
}


public DisplayModVote(client)
{
	if (!IsBuiltinVoteInProgress())//disregard sm_vote_delay
	{
		new iNumPlayers;
		decl iPlayers[MaxClients];
		//list of non-spectators players
		for (new i=1; i<=MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i) || (GetClientTeam(i) == 1))
			{
				continue;
			}
			iPlayers[iNumPlayers++] = i;
		}
		new String:sBuffer[64];
		g_hModVote = CreateBuiltinVote(Handler_VoteCallback, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		g_pluginIdInVote = g_clientsPluginVoteId[client];
		
		decl String:plName[256];

		GetModName(g_pluginIdInVote,plName,sizeof(plName));
		
		ReplaceString( plName, sizeof(plName), "[","" );
		ReplaceString( plName, sizeof(plName), "]","" );
		
		if( g_pluginStates[g_pluginIdInVote] == 0 )
		{
			Format(sBuffer, sizeof(sBuffer), "Turn ON '%s'?", plName);
		}
		else
		{
			Format(sBuffer, sizeof(sBuffer), "Turn OFF '%s'?", plName);
		}		
		
		SetBuiltinVoteArgument(g_hModVote, sBuffer);
		SetBuiltinVoteInitiator(g_hModVote, client);
		SetBuiltinVoteResultCallback(g_hModVote, VoteResultHandler);
		DisplayBuiltinVote(g_hModVote, iPlayers, iNumPlayers, 20);
		return true;
	}
	PrintToChat(client, "\x03[VoteMod] \x01Vote cannot be started now.");
	return false;
}

public Handler_VoteCallback(Handle:vote, BuiltinVoteAction:action, param1, param2)
{
	switch (action)
	{
		case BuiltinVoteAction_End:
		{
			g_hModVote = INVALID_HANDLE;
			CloseHandle(vote);
		}
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, BuiltinVoteFailReason:param1);
		}
	}
}

public VoteResultHandler(Handle:vote, num_votes, num_clients, const client_info[][2], num_items, const item_info[][2])
{
	for (new i=0; i<num_items; i++)
	{
		if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
		{
			if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_clients / 2))
			{
				if (g_pluginStates[g_pluginIdInVote] == 0)
				{
					DisplayBuiltinVotePass(vote, "Mod will be turned ON");
					ChangeMod(true);
					return;
				}
				else
				{
					DisplayBuiltinVotePass(vote, "Mod will be turned OFF");
					ChangeMod(false);
					return;
				}
			}
		}
	}
	DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

ChangeMod(bool:Enable)
{
	decl String:plFilename[64];

	decl String:loadString[88];
	decl String:unloadString[88];
	
	strcopy(loadString,sizeof(loadString),"sm plugins load optional/coop/");
	strcopy(unloadString,sizeof(unloadString),"sm plugins unload optional/coop/");
	
	GetModFilename(g_pluginIdInVote,plFilename,sizeof(plFilename));
	
	ServerCommand("sm plugins load_unlock");
	if( Enable )
	{
		StrCat(loadString,sizeof(loadString),plFilename);
		ServerCommand(loadString);
		g_pluginStates[g_pluginIdInVote]=1;
	}
	else
	{
		StrCat(unloadString,sizeof(unloadString),plFilename);
		ServerCommand(unloadString);
		g_pluginStates[g_pluginIdInVote]=0;
	}
	ServerCommand("sm plugins load_lock");
}


AddPluginToArray(String:filename[],String:name[])
{
	PushArrayString(g_pluginNameArr, name);
	PushArrayString(g_pluginFilenameArr, filename);
	new newIndex = GetArraySize(g_pluginNameArr);
	g_pluginStates[newIndex] = 1;
}

GetModName(index,String:buffer[],bufsize)
{	
	new lastIndex = GetArraySize(g_pluginNameArr)-1;
	if( index > lastIndex )
		return false;
	new copied = GetArrayString(g_pluginNameArr, index, buffer, bufsize);	
	if( copied > 0 )
		return true;
	else
		return false;
}

GetModFilename(index,String:buffer[],bufsize)
{	
	new lastIndex = GetArraySize(g_pluginFilenameArr)-1;
	if( index > lastIndex )
		return false;
	new copied = GetArrayString(g_pluginFilenameArr, index, buffer, bufsize);	
	if( copied > 0 )
		return true;
	else
		return false;
}

public OnConfigsExecuted()
{
	if( !g_pluginArrayBuilt )
	{
		decl String:nameBuffer[256];
		decl String:filenameBuffer[64];

		new Handle:iter = GetPluginIterator();
		new Handle:pl;


		new String:tempDefaultDisabled[1920];
		new String:tempUsed[1920];

		GetConVarString(PluginsDefaultDisabled,tempDefaultDisabled,sizeof(tempDefaultDisabled));
		GetConVarString(PluginsUsedFilter,tempUsed,sizeof(tempUsed));

		for(new i=0; i<30; i++)
		{
			g_DefaultDisabled[i][0] = '\0';
			g_PluginsUsed[i][0] = '\0';
			
			//All plugins are loaded by sourcemod on server load.
			g_pluginStates[i] = 1;
		}

		ExplodeString(tempDefaultDisabled,"|",g_DefaultDisabled,30,64);
		ExplodeString(tempUsed,"|",g_PluginsUsed,30,64);
		
		LogMessage( tempDefaultDisabled );

		while (MorePlugins(iter))
		{
			pl = ReadPlugin(iter);

			GetPluginFilename(pl, filenameBuffer, sizeof(filenameBuffer));
			GetPluginInfo(pl, PluginInfo:PlInfo_Name, nameBuffer,sizeof(nameBuffer));

			for( new i=0; i<30; i++ )
			{
				if( strcmp(filenameBuffer,g_PluginsUsed[i]) == 0 )
				{
					AddPluginToArray(filenameBuffer,nameBuffer);				
					break;
				}
			}		
		}

		CloseHandle(iter);

		g_pluginArrayBuilt = true;
		DisableDefaultDisabledPlugins();
	}
}
