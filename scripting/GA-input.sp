// ****************************************************************
// Genetic algorithm plugin for Team Fortress 2.
// Author: Lauri Räsänen
// ****************************************************************

// ****************************************************************
// SourceMod includes
// ****************************************************************
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <files>
#include <console>
#include <tf2>
#include <tf2_stocks>

// ****************************************************************
// Custom includes
// ****************************************************************
#include <morecolors>

// ****************************************************************
// Extension includes
// ****************************************************************
#include <botcontroller>

// ****************************************************************
// Pragma
// ****************************************************************
#pragma semicolon 1         // Don't allow missing semicolons
#pragma newdecls required   // Enforce new 1.7 SourcePawn syntax

// ****************************************************************
// Constants
// ****************************************************************
#define MAX_CHECKPOINTS 100
#define MAX_FRAMES 5000     // about 75 seconds (assuming 66.6 ticks/s)
#define POPULATION_SIZE 64
#define LUCKY_FEW 8

// ****************************************************************
// Global variables
// ****************************************************************
bool g_bRecording;
bool g_bPlayback;
bool g_bSimulating;
bool g_bBCExtension;
bool g_bGAIndividualMeasured[POPULATION_SIZE];
bool g_bPopulation;
bool g_bGAplayback;
bool g_bDraw;
bool g_bMadeToEnd;

int g_iBot = -1;
int g_iBotTeam = 2;
int g_iPossibleButtons[5] = {IN_JUMP, IN_DUCK, IN_FORWARD, IN_MOVELEFT, IN_MOVERIGHT};
int g_iSimIndex;
int g_iSimCurrentFrame;
int g_iTargetGen;
int g_iCurrentGen;
int g_iGAIndividualInputsInt[MAX_FRAMES][POPULATION_SIZE];
int g_iFrames;
int g_iRecordingClient = -1;
int g_iLeftOverFrames = 0;

float g_fTimeScale = 1000.0;
float g_fGAIndividualInputsFloat[MAX_FRAMES][POPULATION_SIZE][2];
float g_fGAIndividualFitness[POPULATION_SIZE];
float g_fGAStartPos[3];
float g_fGAStartAng[3];
float g_fGAEndPos[3];
float g_fGACheckPoints[MAX_CHECKPOINTS][3];
float g_fTelePos[3] = {0.0, 0.0, 0.0};
float g_fOverrideFitness;
float g_fLastPos[3];
float g_fMutationChance = 0.05;
float g_fRotationMutationChance = 0.05;
float g_fEndCutoff = 400.0;

File g_hFile;

char g_cBotName[] = "GA-BOT";
char g_cPrintPrefix[] = "[{orange}GA{default}]";
char g_cPrintPrefixNoColor[] = "[GA]";
char g_cLastRecord[64];

// ****************************************************************
// Plugin info
// ****************************************************************
public Plugin myinfo =
{
    name = "GA-input",
    author = "Larry",
    description = "Genetic algorithm for surf",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/pancakelarry"
};

// ****************************************************************
// SourceMod callbacks
// ****************************************************************
public void OnPluginStart()
{
    // testing cmds
    RegConsoleCmd("ga_record", CmdRecord, "");
    RegConsoleCmd("ga_stoprecord", CmdStopRecord, "");
    RegConsoleCmd("ga_removerecord", CmdRemoveRecord, "");
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
    RegConsoleCmd("ga_fitness", CmdFitness, "");

    // playback
    RegConsoleCmd("ga_play", CmdPlay, "");
    
    // variables
    RegConsoleCmd("ga_timescale", CmdSetTimeScale, "");
    RegConsoleCmd("ga_frames", CmdSetFrames, "");
    RegConsoleCmd("ga_mutation_chance", CmdSetMutationChance, "");
    RegConsoleCmd("ga_rotation_mutation_chance", CmdSetRotationMutationChance, "");

    CreateTimer(1.0, Timer_SetupBot);
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeout 0; exec surf; sv_timeout 120");
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
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeout 0; exec surf; sv_timeout 120");
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(g_bSimulating)
    {
        if(client == g_iBot)
        {
            // already measured
            if(g_bGAIndividualMeasured[g_iSimIndex] && !g_bGAplayback)
            {
                //PrintToServer("%s Fitness of %d-%d: %f (parent)", g_cPrintPrefixNoColor, g_iCurrentGen, g_iSimIndex, g_fGAIndividualFitness[g_iSimIndex]);
                g_iSimIndex++;
    
                if(g_iSimIndex == POPULATION_SIZE)
                {
                    float bestFitness = 0.0;
                    int fittestIndex = 0;
                    for(int i = 0; i < POPULATION_SIZE; i++)
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
                    {
                        Breed();  
                    }                        
                    else
                    {
                        ServerCommand("host_timescale 1");
                    }               
                }
                
                return Plugin_Continue;
            }

            if(g_iSimCurrentFrame == g_iFrames)
            {
                g_bSimulating = false;
                g_bGAIndividualMeasured[g_iSimIndex] = true;

                CalculateFitness(g_iSimIndex);
                if(g_bGAplayback)
                {
                    g_bGAplayback = false;
                    CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                    int currentTick = GetGameTickCount();
                    PrintToServer("Playback end tick: %d", currentTick);
                    PrintToServer("g_iSimCurrentFrame: %d, g_iFrames: %d", g_iSimCurrentFrame, g_iFrames);
                    return Plugin_Continue;
                }
                g_iSimIndex++;
    
                if(g_iSimIndex < POPULATION_SIZE)
                {
                    MeasureFitness(g_iSimIndex);
                }
                else
                {
                    float bestFitness = 0.0;
                    int fittestIndex = 0;

                    for(int i = 0; i < POPULATION_SIZE; i++)
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
                        return Plugin_Continue;
                    }
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION_SIZE)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                        float bestFitness = 0.0;
                        int fittestIndex = 0;
                        for(int i = 0; i < POPULATION_SIZE; i++)
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

                if (GetVectorDistance(fPos, g_fGAEndPos) < g_fEndCutoff && fPos[2] > g_fGAEndPos[2])
                {
                    // At end
                    // stop generation
                    //g_iTargetGen = g_iCurrentGen;

                    g_bSimulating = false;
                    g_bGAIndividualMeasured[g_iSimIndex] = true;
                    g_bMadeToEnd = true;
                    g_iLeftOverFrames = g_iFrames - g_iSimCurrentFrame;
                    CalculateFitness(g_iSimIndex);

                    PrintToServer("%d reached the end in %d frames! (%f)", g_iSimIndex, g_iSimCurrentFrame, g_fGAIndividualFitness[g_iSimIndex]);

                    if(g_bGAplayback)
                    {
                        g_bGAplayback = false;
                        g_bSimulating = false;
                        int currentTick = GetGameTickCount();
                        CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                        PrintToServer("Playback end tick: %d", currentTick);
                        return Plugin_Continue;
                    }
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION_SIZE)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                        float bestFitness = 0.0;
                        int fittestIndex = 0;
                        for(int i = 0; i < POPULATION_SIZE; i++)
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
            
            buttons = g_iGAIndividualInputsInt[g_iSimCurrentFrame][g_iSimIndex];
            
            buttons |= IN_RELOAD; // Autoreload
            impulse |= 101;
                
            if (buttons & IN_FORWARD)
                vel[0] = 400.0;
            else
                vel[0] = 0.0;
            
            if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                vel[1] = 0.0;
            else if (buttons & IN_MOVELEFT)
                vel[1] = -400.0;
            else if (buttons & IN_MOVERIGHT)
                vel[1] = 400.0;
            
            buttons = 0;

            float fAng[3];
            fAng[0] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][0];
            fAng[1] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][1];
            fAng[2] = 0.0;

            for(int i = 0; i < 3; i++)
            {
                angles[i] = fAng[i];
            }

            g_iSimCurrentFrame++;        
            
            return Plugin_Changed;
        }
        
    }
    if(g_hFile == null)
    {
        return Plugin_Continue;
    }
    if(g_bRecording)
    {
        if(client != g_iRecordingClient)
            return Plugin_Continue;
        
        if (buttons & IN_FORWARD)
            vel[0] = 400.0;
        else
            vel[0] = 0.0;
        
        if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
            vel[1] = 0.0;
        else if (buttons & IN_MOVELEFT)
            vel[1] = -400.0;
        else if (buttons & IN_MOVERIGHT)
            vel[1] = 400.0;

        // disable attack
        buttons &= ~IN_ATTACK;
        buttons &= ~IN_ATTACK2;

        g_hFile.WriteLine("%d,%.16f,%.16f", buttons, angles[0], angles[1]);

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
            char butt[3][18];
            
            int n = ExplodeString(buffer, ",", butt, 3, 18);
            if(n == 3)
            {                
                buttons = StringToInt(butt[0]);
                
                if (buttons & IN_FORWARD)
                    vel[0] = 400.0;
                else
                    vel[0] = 0.0;
                
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

// ****************************************************************
// Commands
// ****************************************************************

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

    g_cLastRecord = "";
    StrCat(g_cLastRecord, sizeof(g_cLastRecord), arg);
    
    int i = 0;
    while(FileExists(path))
    {
        i++;
        path = "/GA/rec/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(i, num, sizeof(num));
        StrCat(path, sizeof(path), num);

        g_cLastRecord = "";
        StrCat(g_cLastRecord, sizeof(g_cLastRecord), arg);
        StrCat(g_cLastRecord, sizeof(g_cLastRecord), num);
    }
    
    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, { 0.0, 0.0, 0.0 });

    g_hFile = OpenFile(path, "w+");
    
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
    if(g_hFile != null)
        g_hFile.Close();
    g_bRecording = false;
    g_bPlayback = false;
    g_bSimulating = false;
    CPrintToChat(client, "%s Recording stopped!", g_cPrintPrefix);
    return Plugin_Handled;
}

public Action CmdRemoveRecord(int client, int args)
{
    char path[64] = "/GA/rec/";
    StrCat(path, sizeof(path), g_cLastRecord);

    if(strcmp(path, "/GA/rec/", true) == 0)
    {
        PrintToServer("Couldn't find recording %s to delete", path);
        return Plugin_Handled;
    }
    
    if(FileExists(path))
    {
        if(DeleteFile(path, false))
        {
            PrintToServer("Deleted recording %s", path);
        }
        else
        {
            PrintToServer("Failed to delete recording %s", path);
        }
    }
    else
    {
        PrintToServer("Couldn't find recording %s to delete, file doesn't exist", path);
    }
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
    if(g_hFile == null)
    {
        CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid g_hFile handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, {0.0, 0.0, 0.0});

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

public Action CmdFitness(int client, int args)
{
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        PrintToServer("%s Fitness of individual %d: %f", g_cPrintPrefixNoColor, i, g_fGAIndividualFitness[i]);
    }
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
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        path = tPath;
        char suff[8] = "-";
        char numb[8];
        IntToString(i, numb, sizeof(numb));
        StrCat(suff, sizeof(suff), numb);
        StrCat(path, sizeof(path), suff);
        g_hFile = OpenFile(path, "w+");
        if(g_hFile == null)
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
        for(int f = 0; f < g_iFrames; f++)
        {
            g_hFile.WriteLine("%d,%.16f,%.16f", g_iGAIndividualInputsInt[f][i], g_fGAIndividualInputsFloat[f][i][0], g_fGAIndividualInputsFloat[f][i][1]);
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
    int lastLoaded = 0;
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        path = tPath;
        char suff[8] = "-";
        char numb[8];
        IntToString(i, numb, sizeof(numb));
        StrCat(suff, sizeof(suff), numb);
        StrCat(path, sizeof(path), suff);
        g_hFile = OpenFile(path, "r");
        if(g_hFile == null)
        {
            if(i == 0)
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
            break;
        }
        int f;
        g_hFile.Seek(0, SEEK_SET);
        char buffer[128];
        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            char bu[3][18];
            int n = ExplodeString(buffer, ",", bu, 3, 18);
            
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
        lastLoaded = i; 
    }

    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        g_iFrames = MAX_FRAMES;
    }  

    if(lastLoaded + 1 < POPULATION_SIZE)
    {
        GeneratePopulation(lastLoaded + 1);
    }
    else
    {
        g_bPopulation = true;
        if(client == 0)
        {
            PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
            PrintToServer("%s Loaded generation %s", g_cPrintPrefixNoColor, tPath);
            PrintToServer("%s You should run 'ga_sim' to calculate fitness values", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);
            CPrintToChat(client, "%s Loaded generation %s", g_cPrintPrefix, tPath);
            CPrintToChat(client, "%s You should run 'ga_sim' to calculate fitness values", g_cPrintPrefixNoColor);
        }    
    }          

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

    int frames = 0;
    int iFrameCounts[POPULATION_SIZE];
    int iLastLoaded = 0;

    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        char individualPath[64];
        strcopy(individualPath, sizeof(individualPath), path);
        char index[8];

        if(i != 0)
        {
            IntToString(i, index, sizeof(index));
            StrCat(individualPath, sizeof(individualPath), index);
        }

        g_hFile = OpenFile(individualPath, "r");

        if(g_hFile == null)
        {
            if (i == 0)
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
            else
            {
                // reached last file
                break;
            }
        }

        g_hFile.Seek(0, SEEK_SET);
        char buffer[128];
        int f = 0;

        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            char bu[3][18];
            int n = ExplodeString(buffer, ",", bu, 3, 18);
            
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

        if (f > frames)
        {
            frames = f;
        }

        iFrameCounts[i] = f;
        iLastLoaded = i;

        g_hFile.Close(); 
    }    

    if(client == 0)
        PrintToServer("%s Loaded %d recordings from %s", g_cPrintPrefixNoColor, iLastLoaded + 1, path);
    else
        CPrintToChat(client, "%s Loaded %d recordings from %s", g_cPrintPrefix, iLastLoaded + 1, path);

    // set frame count
    if(frames > MAX_FRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        frames = MAX_FRAMES;
    }

    g_iFrames = frames;
    if(client == 0)
        PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);

    // Pad other runs to match longest one
    for(int i = 0; i < iLastLoaded; i++)
    {
        if(iFrameCounts[i] < frames)
        {
            Pad(i, iFrameCounts[i]);
        }
    }

    // generate rest of Population
    if(iLastLoaded < POPULATION_SIZE)
    {
        GeneratePopulation(iLastLoaded + 1);
    }
    else
    {
        g_bPopulation = true;
        MeasureFitness(0);
    }    

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
    if(g_hFile == null)
    {
        if(client == 0)
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.WriteLine("%d", g_iFrames);
    g_hFile.WriteLine("%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f", g_fGAStartPos[0], g_fGAStartPos[1], g_fGAStartPos[2], g_fGAStartAng[0], g_fGAStartAng[1], g_fGAStartAng[2], g_fGAEndPos[0], g_fGAEndPos[1], g_fGAEndPos[2]);
    for(int i = 0; i < MAX_CHECKPOINTS; i++)
    {
        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
            g_hFile.WriteLine("%.16f,%.16f,%.16f", g_fGACheckPoints[i][0], g_fGACheckPoints[i][1], g_fGACheckPoints[i][2]);
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
    if(g_hFile == null)
    {
        if(client == 0)
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        else
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }
    g_hFile.Seek(0, SEEK_SET);
    
    char buffer[256];
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
        char bu[9][18];
        int n = ExplodeString(buffer, ",", bu, 9, 18);
        
        if(n == 9)
        {
            for(int i = 0; i < 3; i++)
            {
                g_fGAStartPos[i] = StringToFloat(bu[i]);
            }
            for(int i = 0; i < 3; i++)
            {
                g_fGAStartAng[i] = StringToFloat(bu[i+3]);
            }
            for(int i = 0; i < 3; i++)
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
    for(int i = 0; i < MAX_CHECKPOINTS; i++)
    {
        g_fGACheckPoints[i] = { 0.0, 0.0, 0.0 };
    }
    int cp;
    while(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[3][18];
        int n = ExplodeString(buffer, ",", bu, 3, 18);
        
        if(n == 3)
        {
            for(int i = 0; i < 3; i++)
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

    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        g_iFrames = MAX_FRAMES;
    }

    if(client == 0)
        PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
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
    if(num > MAX_FRAMES)
    {
        if(client == 0)
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        else
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        num = MAX_FRAMES;
    }
    g_iFrames = num;
    if(client == 0)
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, num);
    else
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, num);
    return Plugin_Handled;
}

public Action CmdSetMutationChance(int client, int args)
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

    g_fMutationChance = num;

    if(client == 0)
        PrintToServer("%s Mutation chance set to %f", g_cPrintPrefixNoColor, num);
    else
        CPrintToChat(client, "%s Mutation chance set to %f", g_cPrintPrefix, num);

    return Plugin_Handled;
}

public Action CmdSetRotationMutationChance(int client, int args)
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

    g_fRotationMutationChance = num;

    if(client == 0)
        PrintToServer("%s Rotation mutation chance set to %f", g_cPrintPrefixNoColor, num);
    else
        CPrintToChat(client, "%s Rotation mutation chance set to %f", g_cPrintPrefix, num);

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
    for(int i = num; i < MAX_CHECKPOINTS; i++)
    {
        if(i < MAX_CHECKPOINTS - 1)
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
    for(int i = 0; i < MAX_CHECKPOINTS; i++)
    {
        if(g_fGACheckPoints[i][0] == 0 && g_fGACheckPoints[i][1] == 0 && g_fGACheckPoints[i][2] == 0)
        {
            GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGACheckPoints[i]);
            CPrintToChat(client, "%s Checkpoint %d set!", g_cPrintPrefix, i);
            break;
        }
        else
        {
            if(i == MAX_CHECKPOINTS-1)
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
    ServerCommand("host_timescale %f", g_fTimeScale);
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

// ****************************************************************
// Functions
// ****************************************************************

public void Pad(int individual, int startFrame)
{
    PrintToServer("Padding %d by %d frames", individual, g_iFrames - startFrame);
    
    for(int t = startFrame; t < g_iFrames; t++)
    {
        for(int i = 0; i < sizeof(g_iPossibleButtons); i++)
        {
            // random key inputs
            if(GetRandomFloat(0.0, 1.0) < 0.5)
            {
                if(g_iGAIndividualInputsInt[t][individual] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                {
                    // has button, remove
                    g_iGAIndividualInputsInt[t][individual] &= ~g_iPossibleButtons[i];
                }
                else
                {
                    // doesn't have button, add
                    g_iGAIndividualInputsInt[t][individual] |= g_iPossibleButtons[i];
                }
            }
                
            // chance for inputs to be duplicated from previous tick
            if(t != 0)
            {
                if(g_iGAIndividualInputsInt[t-1][individual] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                {
                    // previous tick has button
                    if(GetRandomFloat(0.0, 1.0) < 0.9)
                    {
                        // add to this
                        g_iGAIndividualInputsInt[t][individual] |= g_iPossibleButtons[i];
                    }                            
                }
            }
        }
        g_fGAIndividualInputsFloat[t][individual][0] = g_fGAStartAng[0];
        g_fGAIndividualInputsFloat[t][individual][1] = g_fGAStartAng[1];

        float prevPitch = g_fGAStartAng[0];
        float prevYaw = g_fGAStartAng[1];

        if (t > 0)
        {
            prevPitch = g_fGAIndividualInputsFloat[t - 1][individual][0];
            prevYaw = g_fGAIndividualInputsFloat[t - 1][individual][1];
        }

        // random mouse movement
        if(GetRandomFloat(0.0, 1.0) < 0.9)
        {
            g_fGAIndividualInputsFloat[t][individual][0] = prevPitch + GetRandomFloat(-1.0, 1.0);

            if (g_fGAIndividualInputsFloat[t][individual][0] < -89.0)
                g_fGAIndividualInputsFloat[t][individual][0] = -89.0;

            if (g_fGAIndividualInputsFloat[t][individual][0] > 89.0)
                g_fGAIndividualInputsFloat[t][individual][0] = 89.0;


            g_fGAIndividualInputsFloat[t][individual][1] = prevYaw + GetRandomFloat(-1.0, 1.0);

            if (g_fGAIndividualInputsFloat[t][individual][1] < -180.0)
                g_fGAIndividualInputsFloat[t][individual][1] += 360.0;

            if (g_fGAIndividualInputsFloat[t][individual][1] > 180.0)
                g_fGAIndividualInputsFloat[t][individual][1] -= 360.0;
        }
        else
        {
            g_fGAIndividualInputsFloat[t][individual][0] = prevPitch;
            g_fGAIndividualInputsFloat[t][individual][1] = prevYaw;
        }
    }   
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
    for(int i = 0; i < MAX_CHECKPOINTS; i++) {
        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
        {
            if(i == 0)
            {
                DrawLaser(g_fGAStartPos, g_fGACheckPoints[i], 0, 255, 0);
            } 
            if(i+1<MAX_CHECKPOINTS)
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
    int ent = CreateEntityByName("env_beam");
    if (ent != -1) {
        TeleportEntity(ent, start, NULL_VECTOR, NULL_VECTOR);
        SetEntityModel(ent, "sprites/laser.vmt");
        SetEntPropVector(ent, Prop_Data, "m_vecEndPos", end);
        DispatchKeyValue(ent, "targetname", "beam");
        char buffer[32];
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
    char name[32];
    for(int i = MaxClients + 1; i <= GetMaxEntities(); i++)
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

void GeneratePopulation(int iStartIndex = 0)
{
    ServerCommand("host_timescale 1");

    for(int p = iStartIndex; p < POPULATION_SIZE; p++)
    {
        // Set initial rotation to start angle
        g_fGAIndividualInputsFloat[0][p][0] = g_fGAStartAng[0];
        g_fGAIndividualInputsFloat[0][p][1] = g_fGAStartAng[1];

        for(int t = 0; t < g_iFrames; t++)
        {
            for(int i = 0; i < 5; i++)
            {
                // random key inputs
                if(GetRandomFloat(0.0, 1.0) < g_fMutationChance)
                {
                    if(g_iGAIndividualInputsInt[t][p] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                    {
                        // has button, remove
                        g_iGAIndividualInputsInt[t][p] &= ~g_iPossibleButtons[i];
                    }
                    else
                    {
                        // doesn't have button, add
                        g_iGAIndividualInputsInt[t][p] |= g_iPossibleButtons[i];
                    }
                }
                    
                // chance for inputs to be duplicated from previous tick
                if(t != 0)
                {
                    if(g_iGAIndividualInputsInt[t-1][p] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                    {
                        // previous tick has button
                        if(GetRandomFloat(0.0, 1.0) < 0.5)
                        {
                            // add to this
                            g_iGAIndividualInputsInt[t][p] |= g_iPossibleButtons[i];
                        }                            
                    }
                }
            }
            
            float prevPitch = g_fGAStartAng[0];
            float prevYaw = g_fGAStartAng[1];

            if (t > 0)
            {
                prevPitch = g_fGAIndividualInputsFloat[t - 1][p][0];
                prevYaw = g_fGAIndividualInputsFloat[t - 1][p][1];
            }

            // random mouse movement
            if(GetRandomFloat(0.0, 1.0) < 0.9)
            {
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
            else
            {
                g_fGAIndividualInputsFloat[t][p][0] = prevPitch;
                g_fGAIndividualInputsFloat[t][p][1] = prevYaw;
            }
        }
    }
    
    g_bPopulation = true;
    g_iCurrentGen = 0;
    for(int i = 0; i < POPULATION_SIZE; i++)
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
    int lastCP = -1;
    
    GetEntPropVector(g_iBot, Prop_Data, "m_vecAbsOrigin", playerPos);
    cP = g_fGAStartPos;
    
    if(g_fTelePos[0] != 0.0 && g_fTelePos[1] != 0.0 && g_fTelePos[2] != 0.0)
        playerPos = g_fTelePos;
    
    g_fTelePos[0] = 0.0;
    g_fTelePos[1] = 0.0;
    g_fTelePos[2] = 0.0;
    


    for(int i = -1; i < MAX_CHECKPOINTS - 1; i++) {
        float temp[3];

        if(g_fGACheckPoints[i + 1][0] != 0 && g_fGACheckPoints[i + 1][1] != 0 && g_fGACheckPoints[i + 1][2] != 0)
        {
            float currentToNext[3];
            float playerToCurrent[3];

            if(i == -1)
            {
                // start to first cp
                ClosestPoint(g_fGAStartPos, g_fGACheckPoints[i + 1], playerPos, temp);
                SubtractVectors(g_fGACheckPoints[i + 1], g_fGAStartPos, currentToNext);
                SubtractVectors(g_fGAStartPos, playerPos, playerToCurrent);
            }
            else
            {
                ClosestPoint(g_fGACheckPoints[i], g_fGACheckPoints[i + 1], playerPos, temp);
                SubtractVectors(g_fGACheckPoints[i + 1], g_fGACheckPoints[i], currentToNext);
                SubtractVectors(g_fGACheckPoints[i], playerPos, playerToCurrent);
            }             

            if (GetVectorDotProduct(currentToNext, playerToCurrent) < 0)
            {
                // If dot product < 0
                // player has passed checkpoint i

                if(GetVectorDistance(temp, playerPos) < GetVectorDistance(cP, playerPos))
                {
                    cP = temp;
                    lastCP = i;
                }
            }
        }
        else
        {
            

            if(i == -1)
            {
                // no cps
                ClosestPoint(g_fGAEndPos, g_fGAStartPos, playerPos, cP);
            }
            else
            {
                float currentToNext[3];
                float playerToCurrent[3];

                // last cp was i
                ClosestPoint(g_fGACheckPoints[i], g_fGAEndPos, playerPos, temp);
                SubtractVectors(g_fGAEndPos, g_fGACheckPoints[i], currentToNext);
                SubtractVectors(g_fGACheckPoints[i], playerPos, playerToCurrent);

                if (GetVectorDotProduct(currentToNext, playerToCurrent) < 0)
                {
                    // If dot product < 0
                    // player has passed checkpoint i

                    if(GetVectorDistance(temp, playerPos) < GetVectorDistance(cP, playerPos))
                    {
                        cP = temp;
                        lastCP = i;
                    }
                }
            }

            break;
        }
    }
    
    // Check for walls
    /*Handle trace = TR_TraceRayFilterEx(playerPos, cP, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TraceRayDontHitSelf, g_iBot);
    if(TR_DidHit(trace))
       g_fOverrideFitness = -10000000.0;
   
    CloseHandle(trace);*/
    
    //PrintToServer("%s individual %d lastCP: %d", g_cPrintPrefixNoColor, individual, lastCP);
    
    float dist;
    
    for(int i = 0; i <= lastCP; i++)
    {
        if(i == 0)
        {
            dist += GetVectorDistance(g_fGAStartPos, g_fGACheckPoints[i]);
        }
        else
            dist += GetVectorDistance(g_fGACheckPoints[i - 1], g_fGACheckPoints[i]);
    }
    
    if(lastCP < 0)
        dist += GetVectorDistance(g_fGAStartPos, cP);
    else
        dist += GetVectorDistance(g_fGACheckPoints[lastCP], cP);
        
    // subtract distance from line
    dist -= GetVectorDistance(cP, playerPos) * 0.5;
        
    g_fGAIndividualFitness[individual] = dist;

    if(g_fOverrideFitness != 0.0)
        g_fGAIndividualFitness[individual] = g_fOverrideFitness;

    g_fOverrideFitness = 0.0;

    if (g_bMadeToEnd)
    {
        g_fGAIndividualFitness[individual] += g_iLeftOverFrames * 10;
    }

    g_bMadeToEnd = false;
    g_iLeftOverFrames = 0;

    //PrintToServer("%s Fitness of %d-%d: %f", g_cPrintPrefixNoColor, g_iCurrentGen, individual, g_fGAIndividualFitness[individual]);

    if(g_bDraw)
    {
        int ent = DrawLaser(playerPos, cP, 255, 0, 0);
        CreateTimer(5.0, Timer_KillEnt, ent);
    }
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
    if(t < 0.0)
        t = 0.0;
    if(t > 1.0)
        t = 1.0;
    ScaleVector(AB, t);
    AddVectors(A, AB, ref);
}

public void Breed()
{
    ServerCommand("host_timescale 1");

    int fittest[POPULATION_SIZE/2];
    float order[POPULATION_SIZE];
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        order[i] = g_fGAIndividualFitness[i];
    }

    SortFloats(order, POPULATION_SIZE, Sort_Descending);
    for(int i = 0; i < (POPULATION_SIZE / 2) - LUCKY_FEW; i++)
    {
        for(int j = 0; j < POPULATION_SIZE; j++)
        {
            if(order[i] == g_fGAIndividualFitness[j])
                fittest[i] = j;
        }
    }
    
    // make lucky few individuals parents even if they're not the fittest
    for(int i = 0; i < LUCKY_FEW; i++)
    {
        bool t = true;
        while(t)
        {
            int r = GetRandomInt(0, POPULATION_SIZE-1);
            bool tt;
            for(int j = 0; j < POPULATION_SIZE / 2; j++)
            {
                if(fittest[j] == r)
                {
                    tt = true;
                }
            }
            if(!tt)
            {
                fittest[(POPULATION_SIZE / 2) - LUCKY_FEW + i] = r;
                t = false;
            }
        }
    }
    
    // pair parents randomly
    int parents[POPULATION_SIZE/4][2];
    bool taken[POPULATION_SIZE/2];
    int par = 0;
    for(int i = 0; i < POPULATION_SIZE / 2; i++)
    {
        if(!taken[i])
        {
            int rand = GetRandomInt(0, (POPULATION_SIZE/2) - 1);
            while(taken[rand] || rand == i)
                rand = GetRandomInt(0, (POPULATION_SIZE/2) - 1);
            
            parents[par][0] = fittest[i];
            parents[par][1] = fittest[rand];
            taken[i] = true;
            taken[rand] = true;
            par++;
        }
    }

    // init array for new children
    int iChildrenInputsInt[MAX_FRAMES][POPULATION_SIZE/2];
    float fChildrenInputsFloat[MAX_FRAMES][POPULATION_SIZE/2][2];

    // loop through parents
    for(int p = 0; p < POPULATION_SIZE / 4; p++)
    {
        // two-point crossover
        int iSize = g_iFrames - 1;
        int iCxPoint1 = GetRandomInt(1, iSize);
        int iCxPoint2 = GetRandomInt(1, iSize - 1);

        if (iCxPoint2 >= iCxPoint1)
        {
            iCxPoint2 += 1;
        }
        else
        {
            // swap
            int iTemp = iCxPoint1;
            iCxPoint1 = iCxPoint2;
            iCxPoint2 = iTemp;
        }

        // Loop through both parents
        for (int iParent = 0; iParent < 2; iParent++)
        {
            int iChildIndex = p*2 + iParent;

            // Loop through frames
            for(int t = 0; t < g_iFrames; t++)
            {            
                // Get genes from other parent if frame is between crossover points
                if(t >= iCxPoint1 && t <= iCxPoint2)
                {
                    iParent = iParent == 0 ? 1 : 0;
                }

                // Get buttons from parent
                for(int a = 0; a < 5; a++)
                {
                    // Check if parent has button
                    if(g_iGAIndividualInputsInt[t][parents[p][iParent]] & g_iPossibleButtons[a] == g_iPossibleButtons[a])
                    {
                        // parent has button, add to child
                        iChildrenInputsInt[t][iChildIndex] |= g_iPossibleButtons[a];
                    }
                    else
                    {
                        // parent does not have button, remove from child
                        iChildrenInputsInt[t][iChildIndex] &= ~g_iPossibleButtons[a];
                    }

                    // random mutations
                    if(GetRandomFloat(0.0, 1.0) < g_fMutationChance)
                    {
                        if(iChildrenInputsInt[t][iChildIndex] & g_iPossibleButtons[a] == g_iPossibleButtons[a])
                        {
                            // has button, remove
                            iChildrenInputsInt[t][iChildIndex] &= ~g_iPossibleButtons[a];
                        }
                        else
                        {                            
                            // doesn't have button, add
                            iChildrenInputsInt[t][iChildIndex] |= g_iPossibleButtons[a];
                        }
                    }
                }

                // Get angles from parents
                for(int a = 0; a < 2; a++)
                {
                    fChildrenInputsFloat[t][iChildIndex][a] = g_fGAIndividualInputsFloat[t][parents[p][iParent]][a];
                }

                // random mutations
                if(GetRandomFloat(0.0, 1.0) < g_fRotationMutationChance)
                {
                    float val = GetRandomFloat(-0.1, 0.1);

                    // Change all future ticks rotation as well
                    for(int j = t; j < g_iFrames; j++)
                    {
                        fChildrenInputsFloat[j][iChildIndex][0] += val;

                        if (fChildrenInputsFloat[j][iChildIndex][0] < -89.0)
                            fChildrenInputsFloat[j][iChildIndex][0] = -89.0;

                        if (fChildrenInputsFloat[j][iChildIndex][0] > 89.0)
                            fChildrenInputsFloat[j][iChildIndex][0] = 89.0;
                    }

                }
                if(GetRandomFloat(0.0, 1.0) < g_fRotationMutationChance)
                {
                    float val = GetRandomFloat(-0.1, 0.1);

                    // Change all future ticks rotation as well
                    for(int j = t; j < g_iFrames; j++)
                    {
                        fChildrenInputsFloat[j][iChildIndex][1] += val;

                        if (fChildrenInputsFloat[j][iChildIndex][1] < -180.0)
                            fChildrenInputsFloat[j][iChildIndex][1] += 360.0;

                        if (fChildrenInputsFloat[j][iChildIndex][1] > 180.0)
                            fChildrenInputsFloat[j][iChildIndex][1] -= 360.0;
                    }
                }
            }
        }
    }

    // overwrite least fittest with new children
    int iLastUsedChild = 0;
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        // Check if individual is a parent
        bool bParent = false;
        for(int j = 0; j < POPULATION_SIZE / 4; j++)
        {
            if (parents[j][0] == i || parents[j][1] == i)
            {
                bParent = true;
            }
        }
        if(bParent)
        {
            continue;
        }
        
        // overwrite frames
        for (int j = 0; j < g_iFrames; j++)
        {
            g_iGAIndividualInputsInt[j][i] = iChildrenInputsInt[j][iLastUsedChild];
            g_fGAIndividualInputsFloat[j][i][0] = fChildrenInputsFloat[j][iLastUsedChild][0];
            g_fGAIndividualInputsFloat[j][i][1] = fChildrenInputsFloat[j][iLastUsedChild][1];
        }
        
        g_bGAIndividualMeasured[i] = false;

        iLastUsedChild++;
        if (iLastUsedChild >= (POPULATION_SIZE/2) - 1)
        {
            break;
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
    if(g_hFile != null)
        g_hFile.Close();
    CPrintToChatAll("%s Playback stopped!", g_cPrintPrefix);
}