#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <files>
#include <console>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>

#undef REQUIRE_EXTENSIONS
#include <botcontroller>

#define MAXCHECKPOINTS 100
// about 10 mins (assuming 66.6/s)
#define MAXFRAMES 40000
#define POPULATION 100
#define LUCKYFEW 10

bool g_bRecording;
bool g_bPlayback;
bool g_bSimulating;
bool g_bBCExtension;
bool g_bGAIndividualMeasured[POPULATION];
bool g_bPopulation;
bool g_bGAplayback;
bool g_bDraw;

int g_iBot = -1;
int g_iBotTeam = 2;
int g_iPossibleButtons[8] = {IN_JUMP, IN_DUCK, IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT, IN_LEFT, IN_RIGHT};
int g_iSimIndex;
int g_iSimCurrentFrame;
int g_iTargetGen;
int g_iCurrentGen;
int g_iGAIndividualInputsInt[MAXFRAMES][POPULATION];
int g_iFrames;
int g_iStartTime = 200;
int g_iPlayBackStart = 0;
int g_iRecordingClient = -1;

float g_fTimeScale = 100.0;
float g_fStartPos[3];
float g_fStartAng[3];
float g_fGAIndividualInputsFloat[MAXFRAMES][POPULATION][2];
float g_fGAIndividualFitness[POPULATION];
float g_fGAStartPos[3];
float g_fGAStartAng[3];
float g_fGAEndPos[3];
float g_fGACheckPoints[MAXCHECKPOINTS][3];
float g_fTelePos[3] = {0.0, 0.0, 0.0};
float g_fOverrideFitness;

File g_hFile;

char g_cBotName[] = "GA-BOT";
char g_cPrintPrefix[] = "[{orange}GA{default}]";
char g_cPrintPrefixNoColor[] = "[GA]";

public Plugin myinfo =
{
    name = "GA-input",
    author = "Larry",
    description = "",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/pancakelarry"
};

public void OnPluginStart()
{
    // testing cmds
    RegConsoleCmd("ga_record", CmdRecord, "");
    RegConsoleCmd("ga_stoprecord", CmdStopRecord, "");
    RegConsoleCmd("ga_playback", CmdPlayback, "");
    RegConsoleCmd("ga_stopplayback", CmdStopPlayback, "");
    
    // config
    RegConsoleCmd("ga_savecfg", CmdSave, "");
    RegConsoleCmd("ga_loadcfg", CmdLoad, "");
    RegConsoleCmd("ga_start", CmdStart, "");
    RegConsoleCmd("ga_end", CmdEnd, "");
    RegConsoleCmd("ga_addcp", CmdAddCheckpoint, "");
    RegConsoleCmd("ga_removecp", CmdRemoveCheckpoint, "");
    
    // manual
    RegConsoleCmd("ga_gen", CmdGen, "");
    RegConsoleCmd("ga_sim", CmdSim, "");
    RegConsoleCmd("ga_breed", CmdBreed, "");
    
    // generation
    RegConsoleCmd("ga_loop", CmdLoop, "");
    RegConsoleCmd("ga_stoploop", CmdStopLoop, "");
    RegConsoleCmd("ga_clear", CmdClear, "");
    RegConsoleCmd("ga_savegen", CmdSaveGen, "");
    RegConsoleCmd("ga_loadgen", CmdLoadGen, "");
    RegConsoleCmd("ga_loadgenfromrec", CmdLoadGenFromRec, "");
    
    // debug
    RegConsoleCmd("ga_debug", CmdDebug, "");

    // playback
    RegConsoleCmd("ga_play", CmdPlay, "");
    
    // variables
    RegConsoleCmd("ga_timescale", CmdSetTimeScale, "");
    RegConsoleCmd("ga_frames", CmdSetFrames, "");
    
    CreateTimer(1.0, Timer_SetupBot);
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0");
    if(!FileExists("/GA/"))
        CreateDirectory("/GA/", 557);
    if(!FileExists("/GA/rec/"))
        CreateDirectory("/GA/rec/", 557);
    if(!FileExists("/GA/gen/"))
        CreateDirectory("/GA/gen/", 557);
    if(!FileExists("/GA/cfg/"))
        CreateDirectory("/GA/cfg/", 557);
}

public void OnPluginEnd() {    
    if (g_iBot != -1) {
        KickClient(g_iBot, "%s", "Kicked GA-BOT");
    }
    HideLines();
}

public void OnLibraryAdded(const char[] sName) {
    if (StrEqual(sName, "botcontroller")) 
    {
        g_bBCExtension = true;
    } 
}

public void OnAllPluginsLoaded() {
    g_bBCExtension = LibraryExists("botcontroller");
}

public void OnMapStart()
{
    g_iBot = -1;
    CreateTimer(1.0, Timer_SetupBot);
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeOut 0; exec surf; sv_timeout 120");
}

public void OnMapEnd()
{
    if (g_iBot != -1) {
        if(IsClientInGame(g_iBot))
            KickClient(g_iBot, "%s", "Kicked GA-BOT");
    }
    g_iBot = -1;
    HideLines();
}
float g_fLastPos[3];
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(g_bSimulating)
    {
        if(client == g_iBot)
        {
            if(g_iSimCurrentFrame == 0)
            {
            	/*if(GetGameTickCount() % 1000 != 0)
            		return Plugin_Continue;*/
        		
		        g_iPlayBackStart = GetGameTickCount();
		        PrintToServer("Playback start tick: %d", g_iPlayBackStart);
            }
            if(g_iSimCurrentFrame == g_iFrames)
            {
                g_bSimulating = false;
                g_bGAIndividualMeasured[g_iSimIndex] = true;

                CalculateFitness(g_iSimIndex);
                if(g_bGAplayback)
                {
                    g_bGAplayback = false;
                    g_bSimulating = false;
                    CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                    int currentTick = GetGameTickCount();
                    PrintToServer("Playback end tick: %d", currentTick);
                    PrintToServer("Playback duration: %d", currentTick - g_iPlayBackStart);
                    PrintToServer("g_iSimCurrentFrame: %d, g_iFrames: %d", g_iSimCurrentFrame, g_iFrames);
                    return Plugin_Continue;
                }
                g_iSimIndex++;
    
                if(g_iSimIndex < POPULATION)
                {
                    MeasureFitness(g_iSimIndex);
                }
                else
                {
                	float bestFitness = 0;
                	int fittestIndex = 0;
            	    for(int i=0; i<POPULATION;i++)
    				{
    					if(g_fGAIndividualFitness[i] > bestFitness)
    					{
    						bestFitness = g_fGAIndividualFitness[i];
    						fittestIndex = i;
    					}
    				}

                	PrintToServer("Best fitness of generation %d: %d (%f)", g_iCurrentGen, fittestIndex, bestFitness);

                    if(g_iTargetGen > g_iCurrentGen)
                    {
                        Breed();
                    }                        
                    else
                    {
                        PrintToServer("%s Finished loop", g_cPrintPrefixNoColor);
                        ServerCommand("host_timescale 1");
                    }
                }
                
                return Plugin_Continue;
            }
            if(g_bGAIndividualMeasured[g_iSimIndex] && !g_bGAplayback)
            {
                PrintToServer("%s Fitness of %d-%d: %f (parent)", g_cPrintPrefixNoColor, g_iCurrentGen, g_iSimIndex, g_fGAIndividualFitness[g_iSimIndex]);
                g_iSimIndex++;
    
                if(g_iSimIndex == POPULATION)
                {
                	float bestFitness = 0;
                	int fittestIndex = 0;
            	    for(int i=0; i<POPULATION;i++)
    				{
    					if(g_fGAIndividualFitness[i] > bestFitness)
    					{
    						bestFitness = g_fGAIndividualFitness[i];
    						fittestIndex = i;
    					}
    				}

                	PrintToServer("Best fitness of generation %d: %d (%f)", g_iCurrentGen, fittestIndex, bestFitness);

                    g_bSimulating = false;
                    if(g_iTargetGen > g_iCurrentGen)
                        Breed();                 
                }
                
                return Plugin_Continue;
            }
            
            if(g_iSimCurrentFrame != 0)
            {
                float fPos[3];
                GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", fPos);
                if(GetVectorDistance(g_fLastPos, fPos) > 91.0)
                {
                    //PrintToServer("last: %f, %f, %f - cur: %f, %f, %f", g_fLastPos[0], g_fLastPos[1], g_fLastPos[2], fPos[0], fPos[1], fPos[2]);
                    // teleported
                    g_bSimulating = false;
                    // uncomment to prevent parents of new generations from being measured again (faster), sometimes non-deterministic dunno why
                    g_bGAIndividualMeasured[g_iSimIndex] = true;
                    g_fTelePos = g_fLastPos;
                    CalculateFitness(g_iSimIndex);
                    if(g_bGAplayback)
                    {
                        g_bGAplayback = false;
                        g_bSimulating = false;
                        int currentTick = GetGameTickCount();
                        CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                        PrintToServer("Playback end tick: %d", currentTick);
                        PrintToServer("Playback duration: %d", currentTick - g_iPlayBackStart);
                        return Plugin_Continue;
                    }
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                    	float bestFitness = 0;
	                	int fittestIndex = 0;
	            	    for(int i=0; i<POPULATION;i++)
	    				{
	    					if(g_fGAIndividualFitness[i] > bestFitness)
	    					{
	    						bestFitness = g_fGAIndividualFitness[i];
	    						fittestIndex = i;
	    					}
	    				}

	                	PrintToServer("Best fitness of generation %d: %d (%f)", g_iCurrentGen, fittestIndex, bestFitness);

                        if(g_iTargetGen > g_iCurrentGen)
                        {
                            Breed();
                        }                        
                        else
                        {
                            PrintToServer("%s Finished loop", g_cPrintPrefixNoColor);
                            ServerCommand("host_timescale 1");
                        }
                    }
                    
                    return Plugin_Continue;
                }
            }
            GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fLastPos);
            
            if(g_iSimCurrentFrame > g_iStartTime)
            {
                float fPos[3];
                GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", fPos);
                float cPos[3];
                ClosestPoint(g_fGACheckPoints[0], g_fGAStartPos, fPos, cPos);
                // within 200 units of start after 200 ticks (hasn't left spawn area)
                /*if(GetVectorDistance(cPos, g_fGAStartPos) < 80)
                {
                    g_bSimulating = false;
                    // uncomment to prevent parents of new generations from being measured again (faster), sometimes non-deterministic dunno why
                    g_bGAIndividualMeasured[g_iSimIndex] = true;
                    g_fOverrideFitness = -10000000.0;
                    if(GetVectorDistance(cPos, g_fGAStartPos) > 0)
                		g_fOverrideFitness += GetVectorDistance(cPos, g_fGAStartPos);
            		else
            			g_fOverrideFitness -= GetVectorDistance(fPos, g_fGAStartPos);
                    CalculateFitness(g_iSimIndex);
                    if(g_bGAplayback)
                    {
                        g_bGAplayback = false;
                        g_bSimulating = false;
                        CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                        int currentTick = GetGameTickCount();
                        PrintToServer("Playback end tick: %d", currentTick);
                        PrintToServer("Playback duration: %d", currentTick - g_iPlayBackStart);
                        return Plugin_Continue;
                    }
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                        if(g_iTargetGen > g_iCurrentGen)
                        {
                            Breed();
                        }                        
                        else
                        {
                            PrintToServer("%s Finished loop", g_cPrintPrefixNoColor);
                            ServerCommand("host_timescale 1");
                        }
                    }
                    
                    return Plugin_Continue;
                }*/
            }
            
            float fAng[3];
            fAng[0] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][0];
            fAng[1] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][1];
            fAng[2] = 0.0;

            for(int i = 0; i < 3; i++)
            {
            	angles[i] = fAng[i];
            }

            //TeleportEntity(client, NULL_VECTOR, fAng, NULL_VECTOR);
            
            buttons = g_iGAIndividualInputsInt[g_iSimCurrentFrame][g_iSimIndex];
            
            buttons |= IN_RELOAD; // Autoreload
            impulse |= 101;
                
            if (buttons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK)
                vel[0] = 0.0;
            else if (buttons & IN_FORWARD)
                vel[0] = 400.0;
            else if (buttons & IN_BACK)
                vel[0] = -400.0;
            
            if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                vel[1] = 0.0;
            else if (buttons & IN_MOVELEFT)
                vel[1] = -400.0;
            else if (buttons & IN_MOVERIGHT)
                vel[1] = 400.0;
            
            buttons = 0;

            g_iSimCurrentFrame++;        
            
            return Plugin_Changed;
        }
        
    }
    if(g_hFile == INVALID_HANDLE)
    {
        return Plugin_Continue;
    }
    if(g_bRecording)
    {
        if(client != g_iRecordingClient)
            return Plugin_Continue;
        
        if (buttons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK)
            vel[0] = 0.0;
        else if (buttons & IN_FORWARD)
            vel[0] = 400.0;
        else if (buttons & IN_BACK)
            vel[0] = -400.0;
        
        if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
            vel[1] = 0.0;
        else if (buttons & IN_MOVELEFT)
            vel[1] = -400.0;
        else if (buttons & IN_MOVERIGHT)
            vel[1] = 400.0;

        // disable attack
        buttons &= ~IN_ATTACK;
        buttons &= ~IN_ATTACK2;

        g_hFile.WriteLine("%d,%f,%f", buttons, angles[0], angles[1]);

        // Disable button based movement
        buttons = 0;

        return Plugin_Changed;
    }
    else if(g_bPlayback)
    {
        if(client != g_iRecordingClient)
            return Plugin_Continue;
            
        if(g_hFile.EndOfFile())
        {
            StopPlayback();
            return Plugin_Continue;
        }
        
        char buffer[128];
        if(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            char butt[3][8];
            
            int n = ExplodeString(buffer, ",", butt, 3, 8);
            if(n == 3)
            {                
                buttons = StringToInt(butt[0]);
                
                if (buttons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK)
                    vel[0] = 0.0;
                else if (buttons & IN_FORWARD)
                    vel[0] = 400.0;
                else if (buttons & IN_BACK)
                    vel[0] = -400.0;
                
                if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                    vel[1] = 0.0;
                else if (buttons & IN_MOVELEFT)
                    vel[1] = -400.0;
                else if (buttons & IN_MOVERIGHT)
                    vel[1] = 400.0;

                buttons = 0;

                float fAng[3];
                fAng[0] = StringToFloat(butt[1]);
                fAng[1] = StringToFloat(butt[2]);
                fAng[2] = 0.0;

                for(int i = 0; i < 3; i++)
                {
                	angles[i] = fAng[i];
                }

                return Plugin_Changed;
            }
            else
            {
                PrintToServer("%s Bad input format", g_cPrintPrefixNoColor);
                StopPlayback();
                return Plugin_Continue;
            }
        }
    }
    return Plugin_Continue;
}

public Action CmdRecord(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(g_bRecording)
    {
        CPrintToChat(client, "%s Already recording!", g_cPrintPrefix);
        return Plugin_Handled;
    }
    if(args < 1)
    {
        CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/rec/";
    StrCat(path, sizeof(path), arg);
    
    int e=0;
    while(FileExists(path))
    {
        e++;
        path = "GA/rec/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(e, num, sizeof(num));
        StrCat(path, sizeof(path), num);
    }
    
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fStartPos);
    GetClientEyeAngles(client, g_fStartAng);
    
    g_hFile = OpenFile(path, "w+");
    if(g_hFile == INVALID_HANDLE)
    {
        CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid g_hFile handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.WriteLine("%f,%f,%f,%f,%f", g_fStartPos[0], g_fStartPos[1], g_fStartPos[2], g_fStartAng[0], g_fStartAng[1]);
    
    g_bRecording = true;
    g_bPlayback = false;
    g_bSimulating = false;
    CPrintToChat(client, "%s Recording started!", g_cPrintPrefix);
    g_iRecordingClient = client;
    return Plugin_Handled;
}

public Action CmdStopRecord(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(!g_bRecording)
    {
        CPrintToChat(client, "%s Not recording!", g_cPrintPrefix);
        return Plugin_Handled;
    }
    if(g_hFile != INVALID_HANDLE)
        g_hFile.Close();
    g_bRecording = false;
    g_bPlayback = false;
    g_bSimulating = false;
    CPrintToChat(client, "%s Recording stopped!", g_cPrintPrefix);
    return Plugin_Handled;
}

public Action CmdPlayback(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(args < 1)
    {
        CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    
    char arg[64], target[64] = "/GA/rec/";
    GetCmdArg(1, arg, sizeof(arg));
    StrCat(target, sizeof(target), arg);
    
    if(FileExists(target))
    {
        g_hFile = OpenFile(target, "r");
    }
    else
    {
        CPrintToChat(client, "%s Can't find file %s.", g_cPrintPrefix, arg);
        return Plugin_Handled;
    }
    if(g_hFile == INVALID_HANDLE)
    {
        CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid g_hFile handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.Seek(0, SEEK_SET);
    
    char buffer[128];
    if(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[5][16];
        int n = ExplodeString(buffer, ",", bu, 5, 16);
        
        if(n == 5)
        {
            for(int i=0; i<n; i++)
            {
                if(strlen(bu[i]) < 1)
                {
                    CPrintToChat(client, "%s Starting position not found! Playback cancelled.", g_cPrintPrefix);
                    g_bPlayback = false;
                    g_hFile.Close();
                    return Plugin_Handled;
                }
                if(i < 3)
                    g_fStartPos[i] = StringToFloat(bu[i]);
                else
                    g_fStartAng[i-3] = StringToFloat(bu[i]);
            }
            TeleportEntity(client, g_fStartPos, g_fStartAng, {0.0, 0.0, 0.0});
        }
        else
        {
            CPrintToChat(client, "%s Starting position not found! Playback cancelled.", g_cPrintPrefix);
            g_bPlayback = false;
            g_hFile.Close();
            return Plugin_Handled;
        }
    }

    g_bRecording = false;
    g_bPlayback = true;
    g_bSimulating = false;
    CPrintToChat(client, "%s Playback started!", g_cPrintPrefix);
    g_iRecordingClient = client;
    return Plugin_Handled;
}

public Action CmdStopPlayback(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(!g_bPlayback)
    {
        CPrintToChat(client, "%s No g_bPlayback active!", g_cPrintPrefix);
        return Plugin_Handled;
    }
    StopPlayback();
    return Plugin_Handled;
}

public Action CmdDebug(int client, int args)
{
    g_bDraw = !g_bDraw;
    if(g_bDraw)
    {
        DrawLines();
        CPrintToChatAll("%s Drawing debug lines", g_cPrintPrefix);
    }
    else
    {
       HideLines();
       CPrintToChatAll("%s Debug lines hidden", g_cPrintPrefix);
    }
    return Plugin_Handled;
}

public Action CmdSaveGen(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/gen/";
    StrCat(path, sizeof(path), arg);
    
    int e=0;
    while(FileExists(path))
    {
        e++;
        path = "/GA/gen/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(e, num, sizeof(num));
        StrCat(path, sizeof(path), num);
    }
    char tPath[64];
    strcopy(tPath, sizeof(tPath), path);
    for(int i=0; i < POPULATION; i++)
    {
        path = tPath;
        char suff[8] = "-";
        char numb[8];
        IntToString(i, numb, sizeof(numb));
        StrCat(suff, sizeof(suff), numb);
        StrCat(path, sizeof(path), suff);
        g_hFile = OpenFile(path, "w+");
        if(g_hFile == INVALID_HANDLE)
        {
            if(client == 0)
            {
                PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
                PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
                return Plugin_Handled;
            }
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
            PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        for(int f=0; f < g_iFrames; f++)
        {
            g_hFile.WriteLine("%d,%f,%f", g_iGAIndividualInputsInt[f][i], g_fGAIndividualInputsFloat[f][i][0], g_fGAIndividualInputsFloat[f][i][1]);
        }
        
        g_hFile.Close();    
    }
    
    if(client == 0)
    {
        PrintToServer("%s Saved generation to %s", g_cPrintPrefixNoColor, tPath);
        return Plugin_Handled;
    }
    CPrintToChat(client, "%s Saved generation to %s", g_cPrintPrefix, tPath);
    return Plugin_Handled;
}

public Action CmdLoadGen(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/gen/";
    StrCat(path, sizeof(path), arg);
    char tPath[64];
    strcopy(tPath, sizeof(tPath), path);
    for(int i=0; i < POPULATION; i++)
    {
        path = tPath;
        char suff[8] = "-";
        char numb[8];
        IntToString(i, numb, sizeof(numb));
        StrCat(suff, sizeof(suff), numb);
        StrCat(path, sizeof(path), suff);
        g_hFile = OpenFile(path, "r");
        if(g_hFile == INVALID_HANDLE)
        {
            if(client == 0)
            {
                PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
                PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
                return Plugin_Handled;
            }
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
            PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        int f;
        g_hFile.Seek(0, SEEK_SET);
        char buffer[128];
        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            char bu[3][16];
            int n = ExplodeString(buffer, ",", bu, 3, 16);
            
            if(n == 3)
            {
                g_iGAIndividualInputsInt[f][i] = StringToInt(bu[0]);
                g_fGAIndividualInputsFloat[f][i][0] = StringToFloat(bu[1]);
                g_fGAIndividualInputsFloat[f][i][1] = StringToFloat(bu[2]);
            }
            else
            {
                if(client == 0)
                    PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
                else
                    CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
                g_bPlayback = false;
                g_hFile.Close();
                return Plugin_Handled;
            }
            f++;
        }

        if (f > g_iFrames)
        	g_iFrames = f;
        g_hFile.Close();    
    }

    g_bPopulation = true;
    if(client == 0)
        PrintToServer("%s Loaded generation %s", g_cPrintPrefixNoColor, tPath);
    else
        CPrintToChat(client, "%s Loaded generation %s", g_cPrintPrefix, tPath);

    if(g_iFrames > MAXFRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAXFRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAXFRAMES);
        g_iFrames = MAXFRAMES;
    }

    if(client == 0)
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, g_iFrames);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);

    return Plugin_Handled;
}

public Action CmdLoadGenFromRec(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/rec/";
    StrCat(path, sizeof(path), arg);

    g_hFile = OpenFile(path, "r");

    if(g_hFile == INVALID_HANDLE)
    {
        if(client == 0)
        {
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
            PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
            return Plugin_Handled;
        }
        CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    int frames = 0;

    for(int i=0; i < POPULATION; i++)
    {
        g_hFile.Seek(0, SEEK_SET);
        char buffer[128];
        int f = 0;

        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            char bu[3][16];
            int n = ExplodeString(buffer, ",", bu, 3, 16);
            
            if(n == 3)
            {
                g_iGAIndividualInputsInt[f][i] = StringToInt(bu[0]);
                g_fGAIndividualInputsFloat[f][i][0] = StringToFloat(bu[1]);
                g_fGAIndividualInputsFloat[f][i][1] = StringToFloat(bu[2]);
            }
            else
            {
                if(client == 0)
                    PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
                else
                    CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
                g_bPlayback = false;
                g_hFile.Close();
                return Plugin_Handled;
            }

            // Increment frame count
        	f++;
        }

        if (i == 0)
        {
        	frames = f;
        }
    }

    g_hFile.Close(); 

    g_bPopulation = true;
    if(client == 0)
        PrintToServer("%s Loaded generation %s", g_cPrintPrefixNoColor, path);
    else
        CPrintToChat(client, "%s Loaded generation %s", g_cPrintPrefix, path);

    // set frame count
    if(frames > MAXFRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAXFRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAXFRAMES);
        frames = MAXFRAMES;
    }

    g_iFrames = frames;
    if(client == 0)
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, g_iFrames);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);

    return Plugin_Handled;
}

public Action CmdSave(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/cfg/";
    StrCat(path, sizeof(path), arg);
    
    int e=0;
    while(FileExists(path))
    {
        e++;
        path = "/GA/cfg/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(e, num, sizeof(num));
        StrCat(path, sizeof(path), num);
    }
    
    g_hFile = OpenFile(path, "w+");
    if(g_hFile == INVALID_HANDLE)
    {
        if(client == 0)
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.WriteLine("%d", g_iFrames);
    g_hFile.WriteLine("%f,%f,%f,%f,%f,%f,%f,%f,%f", g_fGAStartPos[0], g_fGAStartPos[1], g_fGAStartPos[2], g_fGAStartAng[0], g_fGAStartAng[1], g_fGAStartAng[2], g_fGAEndPos[0], g_fGAEndPos[1], g_fGAEndPos[2]);
    for(int i = 0; i<MAXCHECKPOINTS; i++)
    {
        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
            g_hFile.WriteLine("%f,%f,%f", g_fGACheckPoints[i][0], g_fGACheckPoints[i][1], g_fGACheckPoints[i][2]);
    }
    g_hFile.Close();    
    if(client == 0)
        PrintToServer("%s Saved config to %s", g_cPrintPrefixNoColor, path);
    else
        CPrintToChat(client, "%s Saved config to %s", g_cPrintPrefix, path);
    return Plugin_Handled;
}

public Action CmdLoad(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    
    char arg[64], target[64] = "/GA/cfg/";
    GetCmdArg(1, arg, sizeof(arg));
    StrCat(target, sizeof(target), arg);
    
    if(FileExists(target))
    {
        g_hFile = OpenFile(target, "r");
    }
    else
    {
        if(client == 0)
            PrintToServer("%s Can't find file %s.", g_cPrintPrefixNoColor, arg);
        else
            CPrintToChat(client, "%s Can't find file %s.", g_cPrintPrefix, arg);
        return Plugin_Handled;
    }
    if(g_hFile == INVALID_HANDLE)
    {
        if(client == 0)
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.Seek(0, SEEK_SET);
    
    char buffer[128];
    if(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        int num;
        if(StringToIntEx(buffer, num))
        {
            g_iFrames = num;
        }
        else
        {
            if(client == 0)
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            else
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            g_bPlayback = false;
            g_hFile.Close();
            return Plugin_Handled;
        }
    }
    if(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[9][16];
        int n = ExplodeString(buffer, ",", bu, 9, 16);
        
        if(n == 9)
        {
            for(int i = 0; i<3; i++)
            {
                g_fGAStartPos[i] = StringToFloat(bu[i]);
            }
            for(int i = 0; i<3; i++)
            {
                g_fGAStartAng[i] = StringToFloat(bu[i+3]);
            }
            for(int i = 0; i<3; i++)
            {
                g_fGAEndPos[i] = StringToFloat(bu[i+6]);
            }
        }
        else
        {
            if(client == 0)
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            else
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            g_bPlayback = false;
            g_hFile.Close();
            return Plugin_Handled;
        }
    }
    for(int i=0; i<MAXCHECKPOINTS; i++)
    {
        g_fGACheckPoints[i] = { 0.0, 0.0, 0.0 };
    }
    int cp;
    while(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[3][16];
        int n = ExplodeString(buffer, ",", bu, 3, 16);
        
        if(n == 3)
        {
            for(int i=0; i<3; i++)
            {
                g_fGACheckPoints[cp][i] = StringToFloat(bu[i]);
            }            
        }
        else
        {
            if(client == 0)
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            else
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            g_bPlayback = false;
            g_hFile.Close();
            return Plugin_Handled;
        }
        cp++;
    }

    g_hFile.Close(); 

    if(client == 0)
        PrintToServer("%s Loaded config from %s", g_cPrintPrefixNoColor, target);
    else
        CPrintToChat(client, "%s Loaded config from %s", g_cPrintPrefix, target);

    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    if(g_iFrames > MAXFRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAXFRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAXFRAMES);
        g_iFrames = MAXFRAMES;
    }

    if(client == 0)
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, g_iFrames);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);

    return Plugin_Handled;
}

public Action CmdSetTimeScale(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    float num;
    if(!StringToFloatEx(arg, num))
    {
        if(client == 0)
            PrintToServer("%s Failed to parse number", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Failed to parse number", g_cPrintPrefix);
        return Plugin_Handled;
    }
    g_fTimeScale = num;
    if(client == 0)
        PrintToServer("%s Loop timescale set to %f", g_cPrintPrefixNoColor, num);
    else
        CPrintToChat(client, "%s Loop timescale set to %f", g_cPrintPrefix, num);
    return Plugin_Handled;
}

public Action CmdSetFrames(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int num;
    if(!StringToIntEx(arg, num))
    {
        if(client == 0)
            PrintToServer("%s Failed to parse number", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Failed to parse number", g_cPrintPrefix);
        return Plugin_Handled;
    }
    if(num > MAXFRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAXFRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAXFRAMES);
        num = MAXFRAMES;
    }
    g_iFrames = num;
    if(client == 0)
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, num);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, num);
    return Plugin_Handled;
}

public Action CmdRemoveCheckpoint(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(args < 1)
    {
        CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int num;
    if(!StringToIntEx(arg, num))
    {
        CPrintToChat(client, "%s Failed to parse number", g_cPrintPrefix);
        return Plugin_Handled;
    }
    g_fGACheckPoints[num] = { 0.0, 0.0, 0.0 };
    for(int i=num; i<MAXCHECKPOINTS; i++)
    {
        if(i < MAXCHECKPOINTS - 1)
            g_fGACheckPoints[i] = g_fGACheckPoints[i+1];
    } 
    CPrintToChat(client, "%s Checkpoint %d removed!", g_cPrintPrefix, num);
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }
    return Plugin_Handled;
}

public Action CmdAddCheckpoint(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    for(int i=0; i<MAXCHECKPOINTS; i++)
    {
        if(g_fGACheckPoints[i][0] == 0 && g_fGACheckPoints[i][1] == 0 && g_fGACheckPoints[i][2] == 0)
        {
            GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGACheckPoints[i]);
            CPrintToChat(client, "%s Checkpoint %d set!", g_cPrintPrefix, i);
            break;
        }
        else
        {
            if(i == MAXCHECKPOINTS-1)
            {
                CPrintToChat(client, "%s Checkpoint limit reached! Try deleting some.", g_cPrintPrefix);
                return Plugin_Handled;
            }
        }
    }    
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }
    return Plugin_Handled;
}

public Action CmdStart(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGAStartPos);
    GetClientEyeAngles(client, g_fGAStartAng);
    CPrintToChat(client, "%s Start set", g_cPrintPrefix);
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }
    return Plugin_Handled;
}

public Action CmdEnd(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGAEndPos);
    CPrintToChat(client, "%s End set", g_cPrintPrefix);
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }
    return Plugin_Handled;
}

public Action CmdClear(int client, int args)
{
    g_bPopulation = false;
    g_iTargetGen = 0;
    g_iCurrentGen = 0;
    if(client == 0)
        PrintToServer("%s Cleared generation!", g_cPrintPrefixNoColor);
    else
        CPrintToChat(client, "%s Cleared generation!", g_cPrintPrefix);
    return Plugin_Handled;
}

public Action CmdGen(int client, int args)
{
    GeneratePopulation();
    return Plugin_Handled;
}

public Action CmdSim(int client, int args)
{
    MeasureFitness(0);
    return Plugin_Handled;
}

public Action CmdBreed(int client, int args)
{
    Breed();
    return Plugin_Handled;
}

public Action CmdStopLoop(int client, int args)
{
    g_iTargetGen = g_iCurrentGen;
    return Plugin_Handled;
}

public Action CmdLoop(int client, int args)
{
    SetEntProp(g_iBot, Prop_Data, "m_takedamage", 1, 1); // Buddha
    if(args < 1)
    {
        if(client == 0)
            PrintToServer("%s Missing number of generations argument", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Missing number of generations argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int gen = 0;
    if(StringToIntEx(arg, gen))
    {
        g_iTargetGen += gen;
        if(!g_bPopulation)
        {
            GeneratePopulation();
            return Plugin_Handled;
        }          
        
        if(g_iTargetGen > g_iCurrentGen)
            Breed();
    }        
    else
    {
        if(client == 0)
            PrintToServer("%s Couldn't parse number", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Couldn't parse number", g_cPrintPrefix);
    }
        
    if(client == 0)
        PrintToServer("%s Loop started", g_cPrintPrefixNoColor);
    else
        CPrintToChat(client, "%s Loop started", g_cPrintPrefix);
    return Plugin_Handled;
}

public Action CmdPlay(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    if(args < 1)
    {
        CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        return Plugin_Handled;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int index = 0;
    if(StringToIntEx(arg, index))
    {
        g_iSimIndex = index;
        g_bGAplayback = true;
        MeasureFitness(index);
        CPrintToChat(client, "%s Playing %d-%d", g_cPrintPrefix, g_iCurrentGen, index);
    }        
    else
        CPrintToChat(client, "%s Couldn't parse number", g_cPrintPrefix);        
    
    return Plugin_Handled;
}

public Action Timer_SetupBot(Handle hTimer)
{
    if (g_iBot != -1) {
        return;
    }
    if (g_bBCExtension) {
        g_iBot = BotController_CreateBot(g_cBotName);
        
        if (!IsClientInGame(g_iBot)) {
            SetFailState("%s", "Cannot create bot");
        }
        ChangeClientTeam(g_iBot, g_iBotTeam);
        TF2_SetPlayerClass(g_iBot, TFClass_Pyro);
        ServerCommand("mp_waitingforplayers_cancel 1;");
    } 
    else 
    {
        SetFailState("%s", "No bot controller extension");
    }
}

public Action Timer_KillEnt(Handle hTimer, int ent)
{
    if(IsValidEntity(ent))
        AcceptEntityInput(ent, "Kill");
}

public Action MeasureTimer(Handle timer, int index)
{
    g_iSimIndex = index;
    g_iSimCurrentFrame = 0;
    g_bSimulating = true;
}

public void DrawLines() {
    for(new i = 0; i < MAXCHECKPOINTS;i++) {
        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
        {
            if(i == 0)
            {
                DrawLaser(g_fGAStartPos, g_fGACheckPoints[i], 0, 255, 0);
            } 
            if(i+1<MAXCHECKPOINTS)
            {
                if(g_fGACheckPoints[i+1][0] != 0 && g_fGACheckPoints[i+1][1] != 0 && g_fGACheckPoints[i+1][2] != 0)
                {
                    DrawLaser(g_fGACheckPoints[i], g_fGACheckPoints[i+1], 0, 255, 0);
                }
                else
                {
                    DrawLaser(g_fGACheckPoints[i], g_fGAEndPos, 0, 255, 0);
                }
            }
        }
        else
        {
            // no cps
            if(i == 0)
            {
                DrawLaser(g_fGAStartPos, g_fGAEndPos, 0, 255, 0);
            }
        }
    }
}

//https://forums.alliedmods.net/showthread.php?t=190685
public int DrawLaser(float start[3], float end[3], int red, int green, int blue)
{
    new ent = CreateEntityByName("env_beam");
    if (ent != -1) {
        TeleportEntity(ent, start, NULL_VECTOR, NULL_VECTOR);
        SetEntityModel(ent, "sprites/laser.vmt");
        SetEntPropVector(ent, Prop_Data, "m_vecEndPos", end);
        DispatchKeyValue(ent, "targetname", "beam");
        new String:buffer[32];
        Format(buffer, sizeof(buffer), "%d %d %d", red, green, blue);
        DispatchKeyValue(ent, "rendercolor", buffer); //color
        DispatchKeyValue(ent, "renderamt", "100");
        DispatchSpawn(ent);
        SetEntPropFloat(ent, Prop_Data, "m_fWidth", 4.0); // how big the beam will be
        SetEntPropFloat(ent, Prop_Data, "m_fEndWidth", 4.0);
        ActivateEntity(ent);
        AcceptEntityInput(ent, "TurnOn");
    }
    return ent;
}

public void HideLines() {
    decl String:name[32];
    for(new i = MaxClients+1; i <= GetMaxEntities(); i++)
    {
        if(!IsValidEntity(i))
            continue;
    
        if(GetEdictClassname(i,name,sizeof(name)))
        {
             if(StrEqual("env_beam",name,false))
                RemoveEdict(i);
        }
    }
}

public void GeneratePopulation()
{
	ServerCommand("host_timescale 1");

    for(int t=0; t < g_iFrames; t++)
    {
        for(int p=0; p < POPULATION; p++)
        {
            for(int i=0; i < sizeof(g_iPossibleButtons); i++)
            {
                // random key inputs
                if(GetRandomInt(0, 100) > 10)
                {
                    if(g_iGAIndividualInputsInt[t][p] & g_iPossibleButtons[i])
                        g_iGAIndividualInputsInt[t][p] &= ~g_iPossibleButtons[i];
                    else
                        g_iGAIndividualInputsInt[t][p] |= g_iPossibleButtons[i];
                }
                    
                // chance for inputs to be duplicated from previous tick
                if(t != 0)
                {
                    if(g_iGAIndividualInputsInt[t-1][p] & g_iPossibleButtons[i])
                    {
                        if(GetRandomInt(0, 100) > 90)
                        {
                            g_iGAIndividualInputsInt[t][p] |= g_iPossibleButtons[i];
                        }                            
                    }
                }
            }
            g_fGAIndividualInputsFloat[t][p][0] = g_fGAStartAng[0];
            g_fGAIndividualInputsFloat[t][p][1] = g_fGAStartAng[1];

            // random mouse movement
            if(GetRandomInt(0,100) > 95)
            {
            	int prevPitch = g_fGAStartAng[0];
            	int prevYaw = g_fGAStartAng[1];

            	if (t > 0)
            	{
            		prevPitch = g_fGAIndividualInputsFloat[t - 1][p][0];
            		prevYaw = g_fGAIndividualInputsFloat[t - 1][p][1];
            	}

                g_fGAIndividualInputsFloat[t][p][0] = prevPitch + GetRandomFloat(-1.0, 1.0);

                if (g_fGAIndividualInputsFloat[t][p][0] < -89.0)
                	g_fGAIndividualInputsFloat[t][p][0] = -89.0;

            	if (g_fGAIndividualInputsFloat[t][p][0] > 89.0)
                	g_fGAIndividualInputsFloat[t][p][0] = 89.0;


                g_fGAIndividualInputsFloat[t][p][1] = prevYaw + GetRandomFloat(-1.0, 1.0);

                if (g_fGAIndividualInputsFloat[t][p][1] < -180.0)
                	g_fGAIndividualInputsFloat[t][p][1] += 360.0;

            	if (g_fGAIndividualInputsFloat[t][p][1] > 180.0)
                	g_fGAIndividualInputsFloat[t][p][1] -= 360.0;
            }
            
            // chance for inputs to be duplicated from previous tick
            if(t != 0)
            {
                for(int a=0; a<2; a++)
                {
                    if(GetRandomInt(0, 100) > 5)
                    {
                        g_fGAIndividualInputsFloat[t][p][a] = g_fGAIndividualInputsFloat[t-1][p][a];
                    }                        
                }
            }
        }
    }
    
    g_bPopulation = true;
    g_iCurrentGen = 0;
    for(int i=0;i<POPULATION; i++)
    {
        g_bGAIndividualMeasured[i] = false;
    }

	PrintToServer("%s Population generated!", g_cPrintPrefixNoColor);
    ServerCommand("host_timescale %f", g_fTimeScale);

    MeasureFitness(0);
}

public void CalculateFitness(int individual)
{
    float playerPos[3];
    float cP[3];
    int lastCP;
    
    GetEntPropVector(g_iBot, Prop_Data, "m_vecAbsOrigin", playerPos);
    cP = g_fGAStartPos;
    
    if(g_fTelePos[0] != 0.0 && g_fTelePos[1] != 0.0 && g_fTelePos[2] != 0.0)
        playerPos = g_fTelePos;
    
    g_fTelePos[0] = 0.0;
    g_fTelePos[1] = 0.0;
    g_fTelePos[2] = 0.0;
    
    for(new i = 0; i < MAXCHECKPOINTS;i++) {
    	float temp[3];

        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
        {
            if(i == 0)
            {
                ClosestPoint(g_fGACheckPoints[i], g_fGAStartPos, playerPos, temp);
                /*if(g_bDraw)
			    {
			        int ent = DrawLaser(playerPos, temp, 0, 255, 255);
			        CreateTimer(5.0, Timer_KillEnt, ent);
			    }*/
            } 
            else
            {
                ClosestPoint(g_fGACheckPoints[i], g_fGACheckPoints[i-1], playerPos, temp);
            }

            if(GetVectorDistance(temp, playerPos) < GetVectorDistance(cP, playerPos))
            {
                cP = temp;
                lastCP = i;
            }
        }
        else
        {
            if(i == 0)
            {
            	// no cps
                ClosestPoint(g_fGAEndPos, g_fGAStartPos, playerPos, cP);
                lastCP = i;
                break;
            }
            else
            {
            	// last cp was i - 1
            	ClosestPoint(g_fGAEndPos, g_fGACheckPoints[i-1], playerPos, temp);

	            if(GetVectorDistance(temp, playerPos) < GetVectorDistance(cP, playerPos))
	            {
	                cP = temp;
	                lastCP = i;
	            }
            }
        }
    }
    
    // Check for walls
    Handle trace = TR_TraceRayFilterEx(playerPos, cP, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceRayDontHitSelf, g_iBot);
    if(TR_DidHit(trace))
	   g_fOverrideFitness = -10000000.0;
   
	CloseHandle(trace);
    
    //PrintToServer("%s lastCP: %d", g_cPrintPrefixNoColor, lastCP);
    
    float dist;
    
    for(int i=0; i < lastCP; i++)
    {
        if(i == 0)
        {
            dist += GetVectorDistance(g_fGAStartPos, g_fGACheckPoints[i]);
        }
        else
            dist += GetVectorDistance(g_fGACheckPoints[i-1], g_fGACheckPoints[i]);
    }
    
    if(lastCP == 0)
        dist += GetVectorDistance(g_fGAStartPos, cP);
    else
        dist += GetVectorDistance(g_fGACheckPoints[lastCP - 1], cP);
        
    // subtract distance from line
    dist -= GetVectorDistance(cP, playerPos);
        
    g_fGAIndividualFitness[individual] = dist;

    if(g_fOverrideFitness != 0.0)
        g_fGAIndividualFitness[individual] = g_fOverrideFitness;

    g_fOverrideFitness = 0.0;

    PrintToServer("%s Fitness of %d-%d: %f", g_cPrintPrefixNoColor, g_iCurrentGen, individual, g_fGAIndividualFitness[individual]);

    if(g_bDraw)
    {
        int ent = DrawLaser(playerPos, cP, 255, 0, 0);
        CreateTimer(5.0, Timer_KillEnt, ent);
    }

    // save individual to file and stop generation if fitness low enough
    /*if(GAIndividualFitness[individual] < 50)
    {
        simulating = false;
        file = OpenFile("/GA/", "w+");
        for(int i=0; i<simFrames; i++)
        {
            file.WriteLine("%d,%f,%f", 
                GAIndividualInputsInt[i][individual],
                GAIndividualInputsFloat[i][individual][0],
                GAIndividualInputsFloat[i][individual][1]);
        }
        file.Close();
    }*/
}

public bool TraceRayDontHitSelf(int entity, int contentsMask, any data)
{
	// Don't return players or player projectiles
	int entity_owner;
	entity_owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");

	if(entity != data && !(0 < entity <= MaxClients) && !(0 < entity_owner <= MaxClients))
	{
		return true;
	}
	return false;
}


public void MeasureFitness(int index)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "tf_projectile_pipe_remote")) != -1)
    {
        AcceptEntityInput(ent, "Kill");
    }
    
    TeleportEntity(g_iBot, g_fGAStartPos, g_fGAStartAng, {0.0, 0.0, 0.0});
    // wait for attack cooldown
    // should probably manually reset it and impulse 101 instead of waiting
    CreateTimer(1.5, MeasureTimer, index);
}

// https://stackoverflow.com/questions/47481774/getting-point-on-line-segment-that-is-closest-to-another-point/47484153#47484153
public void ClosestPoint(float A[3], float B[3], float P[3], float ref[3])
{
    float AB[3];
    SubtractVectors(B, A, AB);
    float AP[3];
    SubtractVectors(P, A, AP);
    float lengthSqrAB = AB[0] * AB[0] + AB[1] * AB[1] + AB[2] * AB[2];
    float t = (AP[0] * AB[0] + AP[1] * AB[1] + AP[2] * AB[2]) / lengthSqrAB;
    if(t < 0)
     t = 0;
    if(t > 1)
        t = 1;
    ScaleVector(AB, t);
    AddVectors(A, AB, ref);
}

public void Breed()
{
	ServerCommand("host_timescale 1");

    int fittest[POPULATION/2];
    float order[POPULATION];
    for(int i=0; i<POPULATION;i++)
        order[i] = g_fGAIndividualFitness[i];

    SortFloats(order, POPULATION, Sort_Descending);
    for(int i=0; i<(POPULATION/2)-LUCKYFEW; i++)
    {
        for(int e=0; e<POPULATION; e++)
        {
            if(order[i] == g_fGAIndividualFitness[e])
                fittest[i] = e;
        }
    }
    
    // make lucky few individuals parents even if they're not the fittest
    for(int i=0; i<LUCKYFEW; i++)
    {
    	bool t = true;
    	while(t)
    	{
    		int r = GetRandomInt(0, POPULATION-1);
    		bool tt;
    		for(int e=0; e<POPULATION/2; e++)
    		{
    			if(fittest[e] == r)
    				tt = true;
    		}
    		if(!tt)
    		{
    			fittest[(POPULATION/2)-LUCKYFEW+i] = r;
    			t = false;
    		}
    	}
    }
    
    // pair parents randomly
    int parents[POPULATION/4][2];
    bool taken[POPULATION/2];
    int par = 0;
    for(int i=0; i<POPULATION/2; i++)
    {
        if(!taken[i])
        {
            int rand = GetRandomInt(0, (POPULATION/2) - 1);
            while(taken[rand] || rand == i)
                rand = GetRandomInt(0, (POPULATION/2) - 1);
            
            parents[par][0] = i;
            parents[par][1] = rand;
            taken[i] = true;
            taken[rand] = true;
            par++;
        }
    }
    for(int p=0; p<POPULATION/4; p++)
    {
        for(int i=0; i<POPULATION; i++)
        {
            bool cont = false;
            for(int e=0; e<POPULATION/2; e++)
            {
                if(fittest[e] == i)
                    cont = true;
            }
            if(cont)
                continue;
            
            // overwrite least fittest with children
            for(int t=0; t<g_iFrames; t++)
            {            
                // Get parts from both parents randomly
                for(int a=0; a<8; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    if(g_iGAIndividualInputsInt[t][parents[p][cross]] & g_iPossibleButtons[a])
                        g_iGAIndividualInputsInt[t][i] |= g_iPossibleButtons[a];
                    else
                        g_iGAIndividualInputsInt[t][i] &= ~g_iPossibleButtons[a];

                    // random mutations
                    if(GetRandomInt(0, 100) > 5)
                    {
                        if(g_iGAIndividualInputsInt[t][i] & g_iPossibleButtons[a])
                            g_iGAIndividualInputsInt[t][i] |= g_iPossibleButtons[a];
                        else
                            g_iGAIndividualInputsInt[t][i] &= ~g_iPossibleButtons[a];
                    }

                    // chance for inputs to be duplicated from previous tick
                    if(t != 0)
                    {
                        if(GetRandomInt(0, 100) > 5)
                        {
                            if(g_iGAIndividualInputsInt[t-1][i] & g_iPossibleButtons[a])
                                g_iGAIndividualInputsInt[t][i] |= g_iPossibleButtons[a];
                            else
                                g_iGAIndividualInputsInt[t][i] &= ~g_iPossibleButtons[a];
                        }
                    }
                }

                for(int a=0; a<2; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    g_fGAIndividualInputsFloat[t][i][a] = g_fGAIndividualInputsFloat[t][parents[p][cross]][a];
                }

                // random mutations
                if(GetRandomInt(0, 100) > 5)
                {
                    g_fGAIndividualInputsFloat[t][i][0] += GetRandomFloat(-1.0, 1.0);

                    if (g_fGAIndividualInputsFloat[t][i][0] < -89.0)
                    	g_fGAIndividualInputsFloat[t][i][0] = -89.0;

                	if (g_fGAIndividualInputsFloat[t][i][0] > 89.0)
                    	g_fGAIndividualInputsFloat[t][i][0] = 89.0;
                }
                if(GetRandomInt(0, 100) > 5)
                {
                    g_fGAIndividualInputsFloat[t][i][1] += GetRandomFloat(-1.0, 1.0);

                    if (g_fGAIndividualInputsFloat[t][i][1] < -180.0)
                    	g_fGAIndividualInputsFloat[t][i][1] += 360.0;

                	if (g_fGAIndividualInputsFloat[t][i][1] > 180.0)
                    	g_fGAIndividualInputsFloat[t][i][1] -= 360.0;
                }

                for(int a=0; a<2; a++)
                {
                    // chance for inputs to be duplicated from previous tick
                    if(t != 0)
                    {
                        if(GetRandomInt(0, 100) > 5)
                            g_fGAIndividualInputsFloat[t][i][a] = g_fGAIndividualInputsFloat[t-1][i][a];
                    }
                }
            }
            g_bGAIndividualMeasured[i] = false;
        }
    }
    g_iCurrentGen++;
    PrintToServer("%s Generation %d breeded!", g_cPrintPrefixNoColor, g_iCurrentGen);
    ServerCommand("host_timescale %f", g_fTimeScale);    
    MeasureFitness(0);      
}

public void StopPlayback()
{
    g_bPlayback = false;
    if(g_hFile != INVALID_HANDLE)
        g_hFile.Close();
    CPrintToChatAll("%s Playback stopped!", g_cPrintPrefix);
}