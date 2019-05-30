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
// https://sm.alliedmods.net/new-api/core/PluginInfo
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

// Summary:
// Called when the plugin is fully initialized and all known external references are resolved
// https://sm.alliedmods.net/new-api/sourcemod/OnPluginStart
public void OnPluginStart()
{
    // ****************************************************************
    // Console commands
    // ****************************************************************

    // Recording commands
    RegConsoleCmd("ga_record", CmdRecord, "");              // Record player inputs
    RegConsoleCmd("ga_stoprecord", CmdStopRecord, "");      // Stop recording
    RegConsoleCmd("ga_removerecord", CmdRemoveRecord, "");  // Remove last recording

    // Playback commands
    RegConsoleCmd("ga_playback", CmdPlayback, "");          // Play a player recording
    RegConsoleCmd("ga_stopplayback", CmdStopPlayback, "");  // Stop playback
    RegConsoleCmd("ga_play", CmdPlay, "");                  // Play a generated individual
    
    // Config commands
    RegConsoleCmd("ga_savecfg", CmdSaveConfig, "");         // Save current config
    RegConsoleCmd("ga_loadcfg", CmdLoadConfig, "");         // Load a config
    RegConsoleCmd("ga_start", CmdStart, "");                // Set start location
    RegConsoleCmd("ga_end", CmdEnd, "");                    // Set end location
    RegConsoleCmd("ga_addcp", CmdAddCheckpoint, "");        // Add a checkpoint
    RegConsoleCmd("ga_removecp", CmdRemoveCheckpoint, "");  // Remove a checkpoint
    RegConsoleCmd("ga_timescale", CmdSetTimeScale, "");     // Set host_timescale for simulations
    RegConsoleCmd("ga_frames", CmdSetFrames, "");           // Set frame cut-off
    RegConsoleCmd("ga_mutation_chance", CmdSetMutationChance, "");                  // Set mutation chance for buttons
    RegConsoleCmd("ga_rotation_mutation_chance", CmdSetRotationMutationChance, ""); // Set mutation chance for rotation
    
    // Manual generation commands
    RegConsoleCmd("ga_gen", CmdGen, "");        // Generate new population
    RegConsoleCmd("ga_sim", CmdSim, "");        // Simulate current population
    RegConsoleCmd("ga_breed", CmdBreed, "");    // Breed next generation
    
    // Generation commands
    RegConsoleCmd("ga_loop", CmdLoop, "");                      // Start looping new generations
    RegConsoleCmd("ga_stoploop", CmdStopLoop, "");              // Stop looping
    RegConsoleCmd("ga_clear", CmdClear, "");                    // Clear population
    RegConsoleCmd("ga_savegen", CmdSaveGen, "");                // Save population
    RegConsoleCmd("ga_loadgen", CmdLoadGen, "");                // Load population
    RegConsoleCmd("ga_loadgenfromrec", CmdLoadGenFromRec, "");  // Load population from a player recording
    
    // Debug commands
    RegConsoleCmd("ga_debug", CmdDebug, "");        // Draw debug lines in-game
    RegConsoleCmd("ga_fitness", CmdFitness, "");    // Print fitness of each individual in population
    
    // Start a timer for spawning bot
    CreateTimer(1.0, Timer_SetupBot);

    // Set server config
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeout 0; exec surf; sv_timeout 120");

    // Create required directories
    if(!FileExists("/GA/"))
    {
        CreateDirectory("/GA/", 557);       // Root directory
    }
    if(!FileExists("/GA/rec/"))
    {
        CreateDirectory("/GA/rec/", 557);   // Recordings directory
    }
    if(!FileExists("/GA/gen/"))
    {
        CreateDirectory("/GA/gen/", 557);   // Generations directory
    }
    if(!FileExists("/GA/cfg/"))
    {
        CreateDirectory("/GA/cfg/", 557);   // Config directory
    }
}

// Summary:
// Called when the plugin is about to be unloaded
// https://sm.alliedmods.net/new-api/sourcemod/OnPluginEnd
public void OnPluginEnd()
{    
    // Kick bot
    if (g_iBot != -1)
    {
        KickClient(g_iBot, "%s", "OnPluginEnd()");
    }

    // Hide debug lines in-game
    HideLines();
}

// Summary:
// Called when a map is loaded
// https://sm.alliedmods.net/new-api/sourcemod/OnMapStart
public void OnMapStart()
{
    // Create new bot
    g_iBot = -1;
    CreateTimer(1.0, Timer_SetupBot);

    // Reapply server config
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeout 0; exec surf; sv_timeout 120");
}

// Summary:
// Called right before a map ends
// https://sm.alliedmods.net/new-api/sourcemod/OnMapEnd
public void OnMapEnd()
{
    // Kick bot
    if (g_iBot != -1)
    {
        if(IsClientInGame(g_iBot))
        {
            KickClient(g_iBot, "%s", "OnMapEnd()");
        }
    }
    g_iBot = -1;

    // Hide lines in-game
    HideLines();
}

// Summary:
// Called when a clients movement buttons are being processed.
// Also called for our bot.
// https://sm.alliedmods.net/new-api/sdktools_hooks/OnPlayerRunCmd
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    // ****************************************************************
    // Handle bot related functionality
    // ****************************************************************
    if(g_bSimulating)
    {
        // Make sure client is our bot
        if(client == g_iBot)
        {
            // Check if individual in population has already been measured
            if(g_bGAIndividualMeasured[g_iSimIndex] && !g_bGAplayback)
            {
                g_iSimIndex++;
                
                // Last individual of population
                if(g_iSimIndex == POPULATION_SIZE)
                {
                    // Get best fitness of population
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

                    // Continue to the next generation or stop looping
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

            // Check if we're at the end of this individual
            if(g_iSimCurrentFrame >= g_iFrames)
            {
                g_bSimulating = false;
                g_bGAIndividualMeasured[g_iSimIndex] = true;

                CalculateFitness(g_iSimIndex);

                // Return if playing back instead of measuring
                if(g_bGAplayback)
                {
                    g_bGAplayback = false;
                    CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                    return Plugin_Continue;
                }

                // Continue to the next individual if not last of population
                g_iSimIndex++;
    
                if(g_iSimIndex < POPULATION_SIZE)
                {
                    MeasureFitness(g_iSimIndex);
                }
                else
                {
                    // Get best fitness of population
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

                    // Continue to the next generation or stop looping
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
            
            // Not the first frame
            if(g_iSimCurrentFrame != 0)
            {
                // Get bot's position
                float fPos[3];
                GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", fPos);

                // Check if bot gets teleported
                if(GetVectorDistance(g_fLastPos, fPos) > 91.0)
                {
                    // If moved over 91 units since last tick, assume teleported
                    // Max velocity is 3500u/s on all 3 axes,
                    // sqrt(sqrt(3500^2 + 3500^2)^2 + 3500^2) ~ 91

                    g_bSimulating = false;
                    g_bGAIndividualMeasured[g_iSimIndex] = true;
                    // Set last position of bot before teleporting
                    // for fitness calculation
                    g_fTelePos = g_fLastPos;
                    CalculateFitness(g_iSimIndex);

                    // Return if playing back instead of measuring
                    if(g_bGAplayback)
                    {
                        g_bGAplayback = false;
                        g_bSimulating = false;
                        CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                        return Plugin_Continue;
                    }

                    // Continue to the next individual if not last of population
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION_SIZE)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                        // Get best fitness of population
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

                        // Continue to the next generation or stop looping
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

                // Check if bot is close enough to the end position
                // (within cutoff distance and above the end point
                // to prevent finishing through floors and such)
                if (GetVectorDistance(fPos, g_fGAEndPos) < g_fEndCutoff && fPos[2] > g_fGAEndPos[2])
                {
                    g_bSimulating = false;
                    g_bGAIndividualMeasured[g_iSimIndex] = true;
                    g_bMadeToEnd = true;
                    // Set amount of frames saved from cutoff limit
                    g_iLeftOverFrames = g_iFrames - g_iSimCurrentFrame;
                    CalculateFitness(g_iSimIndex);

                    PrintToServer("%d reached the end in %d frames! (%f)", g_iSimIndex, g_iSimCurrentFrame, g_fGAIndividualFitness[g_iSimIndex]);

                    // Return if playing back instead of measuring
                    if(g_bGAplayback)
                    {
                        g_bGAplayback = false;
                        g_bSimulating = false;
                        CPrintToChatAll("%s Playback ended", g_cPrintPrefix);
                        return Plugin_Continue;
                    }

                    // Continue to the next individual if not last of population
                    g_iSimIndex++;
        
                    if(g_iSimIndex < POPULATION_SIZE)
                    {
                        MeasureFitness(g_iSimIndex);
                    }
                    else
                    {
                        // Get best fitness of population
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

                        // Continue to the next generation or stop looping
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

                // Save last position
                g_fLastPos = fPos;
            }
            
            // Get buttons for current frame
            buttons = g_iGAIndividualInputsInt[g_iSimCurrentFrame][g_iSimIndex];
            
            // Add impulse 101 to refill health and ammo
            impulse |= 101;
            
            // Buttons don't do anything for the bot,
            // set desired velocity manually based on buttons.
            // Desired velocity still gets capped by class max movement speed,
            // use 400 to cover max movement speed of all classes.
            if (buttons & IN_FORWARD)
            {
                vel[0] = 400.0;
            }
            else
            {
                vel[0] = 0.0;
            }
            
            if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
            {
                vel[1] = 0.0;
            }
            else if (buttons & IN_MOVELEFT)
            {
                vel[1] = -400.0;
            }
            else if (buttons & IN_MOVERIGHT)
            {
                vel[1] = 400.0;
            }
            
            // Reset buttons to prevent jumping and ducking for now..
            buttons = 0;

            // Get angles for current frame
            angles[0] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][0];
            angles[1] = g_fGAIndividualInputsFloat[g_iSimCurrentFrame][g_iSimIndex][1];
            angles[2] = 0.0;

            // Increment frame
            g_iSimCurrentFrame++;        
            
            return Plugin_Changed;
        }        
    }

    // ****************************************************************
    // Handle player related functionality
    // ****************************************************************    
    if(g_hFile != null)
    {
        // Handle player recording inputs
        if(g_bRecording)
        {
            // Make sure client is the one recording
            if(client != g_iRecordingClient)
            {
                return Plugin_Continue;
            }
            
            // Use same movement method as the bot for consistency
            if (buttons & IN_FORWARD)
            {
                vel[0] = 400.0;
            }
            else
            {
                vel[0] = 0.0;
            }
            
            if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT)
            {
                vel[1] = 0.0;
            }
            else if (buttons & IN_MOVELEFT)
            {
                vel[1] = -400.0;
            }
            else if (buttons & IN_MOVERIGHT)
            {
                vel[1] = 400.0;
            }

            // Disable attack
            buttons &= ~IN_ATTACK;
            buttons &= ~IN_ATTACK2;

            // Write buttons and angles to file
            g_hFile.WriteLine("%d,%.16f,%.16f", buttons, angles[0], angles[1]);

            // Disable button based movement
            buttons = 0;

            return Plugin_Changed;
        }

        // Handle playing back a player recording
        if(g_bPlayback)
        {
            // Make sure client is the last one recording
            if(client != g_iRecordingClient)
            {
                return Plugin_Continue;
            }
                
            // Stop playback at end of file
            if(g_hFile.EndOfFile())
            {
                StopPlayback();
                return Plugin_Continue;
            }
            
            // Read from file to buffer
            char buffer[128];
            if(g_hFile.ReadLine(buffer, sizeof(buffer)))
            {
                // Split line to seperate strings
                char butt[3][18];                
                int n = ExplodeString(buffer, ",", butt, 3, 18);

                // Make sure we have correct number of strings
                if(n == 3)
                {                
                    // Parse buttons
                    buttons = StringToInt(butt[0]);
                    
                    // Use same movement method as the bot for consistency
                    if (buttons & IN_FORWARD)
                    {
                        vel[0] = 400.0;
                    }
                    else
                    {
                        vel[0] = 0.0;
                    }
                    
                    if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                    {
                        vel[1] = 0.0;
                    }
                    else if (buttons & IN_MOVELEFT)
                    {
                        vel[1] = -400.0;
                    }
                    else if (buttons & IN_MOVERIGHT)
                    {
                        vel[1] = 400.0;
                    }

                    // Disable button based movement
                    buttons = 0;

                    // Parse angles
                    angles[0] = StringToFloat(butt[1]);
                    angles[1] = StringToFloat(butt[2]);
                    angles[2] = 0.0;

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
    }
    
    return Plugin_Continue;
}

// ****************************************************************
// Commands
// ****************************************************************

// Summary:
// Handle player recording command
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
        CPrintToChat(client, "%s Missing recording name argument", g_cPrintPrefix);
        return Plugin_Handled;
    }

    // Get recording name from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to recording path
    char cPath[64] = "/GA/rec/";
    StrCat(cPath, sizeof(cPath), arg);

    // Set global variable for last recording 
    g_cLastRecord = "";
    StrCat(g_cLastRecord, sizeof(g_cLastRecord), arg);
    
    // Increment file path if name already exists
    int i = 0;
    while(FileExists(cPath))
    {
        i++;

        // Append name to recording path
        cPath = "/GA/rec/";
        StrCat(cPath, sizeof(cPath), arg);

        // Append index to recording path
        char num[8];
        IntToString(i, num, sizeof(num));
        StrCat(cPath, sizeof(cPath), num);

        // Set global variable for last recording 
        g_cLastRecord = "";
        StrCat(g_cLastRecord, sizeof(g_cLastRecord), arg);
        StrCat(g_cLastRecord, sizeof(g_cLastRecord), num);
    }
    
    // Teleport player to start position
    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, { 0.0, 0.0, 0.0 });

    // Set global file handle for writing
    // to file in OnPlayerRunCmd()
    g_hFile = OpenFile(cPath, "w+");
    
    g_bRecording = true;
    g_bPlayback = false;
    g_bSimulating = false;
    g_iRecordingClient = client;

    CPrintToChat(client, "%s Recording started!", g_cPrintPrefix);    

    return Plugin_Handled;
}

// Summary:
// Handle recording stop command
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

    if(g_iRecordingClient != client)
    {
        CPrintToChat(client, "%s Someone else is recording!", g_cPrintPrefix);
        return Plugin_Handled;
    }

    if(g_hFile != null)
    {
        g_hFile.Close();
    }

    g_bRecording = false;
    g_bPlayback = false;
    g_bSimulating = false;

    CPrintToChat(client, "%s Recording stopped!", g_cPrintPrefix);

    return Plugin_Handled;
}

// Summary:
// Handle remove record command
public Action CmdRemoveRecord(int client, int args)
{
    // Append last recording name to path
    char cPath[64] = "/GA/rec/";
    StrCat(cPath, sizeof(cPath), g_cLastRecord);

    // Make sure that last record name is not empty
    // (compare path to recording root directory)
    if(strcmp(cPath, "/GA/rec/", true) == 0)
    {
        PrintToServer("Couldn't find recording %s to delete", cPath);
        return Plugin_Handled;
    }
    
    // Make sure file exists
    if(FileExists(cPath))
    {
        if(DeleteFile(cPath, false))
        {
            PrintToServer("Deleted recording %s", cPath);
        }
        else
        {
            PrintToServer("Failed to delete recording %s", cPath);
        }
    }
    else
    {
        PrintToServer("Couldn't find recording %s to delete, file doesn't exist", cPath);
    }

    return Plugin_Handled;
}

// Summary:
// Handle player recording playback command
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
    
    // Append recording name to path
    char arg[64], target[64] = "/GA/rec/";
    GetCmdArg(1, arg, sizeof(arg));
    StrCat(target, sizeof(target), arg);
    
    // Make sure recording exists
    if(FileExists(target))
    {
        // Set global file handle for reading
        // from file in OnPlayerRunCmd()
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

    // Teleport client to start position
    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, {0.0, 0.0, 0.0});

    g_bRecording = false;
    g_bPlayback = true;
    g_bSimulating = false;
    g_iRecordingClient = client;

    CPrintToChat(client, "%s Playback started!", g_cPrintPrefix);

    return Plugin_Handled;
}

// Summary:
// Handle playback stop command
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

    if(g_iRecordingClient != client)
    {
        CPrintToChat(client, "%s Someone else is using playback!", g_cPrintPrefix);
        return Plugin_Handled;
    }

    StopPlayback();

    return Plugin_Handled;
}

// Summary:
// Handle drawing debug lines command
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

// Summary:
// Handle fitness print command
public Action CmdFitness(int client, int args)
{
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        PrintToServer("%s Fitness of individual %d: %f", g_cPrintPrefixNoColor, i, g_fGAIndividualFitness[i]);
    }
}

// Summary:
// Handle population save command
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

    // Get population name from args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to path
    char cPath[64] = "/GA/gen/";
    StrCat(cPath, sizeof(cPath), arg);
    
    // Increment index if file with same name already exists
    int i = 0;
    while(FileExists(cPath))
    {
        i++;

        // Append name to path
        cPath = "/GA/gen/";
        StrCat(cPath, sizeof(cPath), arg);

        // Append index to path
        char num[8];
        IntToString(i, num, sizeof(num));
        StrCat(cPath, sizeof(cPath), num);
    }

    // Base path for all individuals
    char cBasePath[64];
    strcopy(cBasePath, sizeof(cBasePath), cPath);

    // Loop through all individuals in population
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        // Set individual path
        cPath = cBasePath;

        // Get index of individual
        char numb[8];
        IntToString(i, numb, sizeof(numb));

        // Create suffix "-i"
        char suff[8] = "-";        
        StrCat(suff, sizeof(suff), numb);

        // Add suffix to individual path
        StrCat(cPath, sizeof(cPath), suff);

        // Open individual path for writing
        g_hFile = OpenFile(cPath, "w+");
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

        // Loop through all frames and write to file
        for(int j = 0; j < g_iFrames; j++)
        {
            g_hFile.WriteLine("%d,%.16f,%.16f", g_iGAIndividualInputsInt[j][i], g_fGAIndividualInputsFloat[j][i][0], g_fGAIndividualInputsFloat[j][i][1]);
        }
        
        g_hFile.Close();    
    }
    
    if(client == 0)
    {
        PrintToServer("%s Saved generation to %s", g_cPrintPrefixNoColor, cBasePath);
    }
    else
    {
        CPrintToChat(client, "%s Saved generation to %s", g_cPrintPrefix, cBasePath);
    }    

    return Plugin_Handled;
}

// Summary:
// Handle population load command
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

    // Get name from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to population path
    char cPath[64] = "/GA/gen/";
    StrCat(cPath, sizeof(cPath), arg);

    // Base path for all individuals
    char cBasePath[64];
    strcopy(cBasePath, sizeof(cBasePath), cPath);

    // Keep track of number of individuals loaded
    int iLastLoaded = 0;

    // Loop through population
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        // Set individual path
        cPath = cBasePath;

        // Get index of individual
        char numb[8];
        IntToString(i, numb, sizeof(numb));

        // Create suffix "-i"
        char suff[8] = "-";
        StrCat(suff, sizeof(suff), numb);

        // Append suffix to individual path
        StrCat(cPath, sizeof(cPath), suff);

        // Open individual file for reading
        g_hFile = OpenFile(cPath, "r");
        if(g_hFile == null)
        {
            // Error if first individual
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

        // Reset frame cutoff
        g_iFrames = 0;

        // Keep track of frame count of individual
        int f;

        // Go to beginning of file
        g_hFile.Seek(0, SEEK_SET);

        // Read each line to buffer
        char buffer[128];
        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            // Split buffer to buttons and angles
            char bu[3][18];
            int n = ExplodeString(buffer, ",", bu, 3, 18);
            
            if(n == 3)
            {
                // Parse buttons and angles
                g_iGAIndividualInputsInt[f][i] = StringToInt(bu[0]);
                g_fGAIndividualInputsFloat[f][i][0] = StringToFloat(bu[1]);
                g_fGAIndividualInputsFloat[f][i][1] = StringToFloat(bu[2]);
            }
            else
            {
                if(client == 0)
                {
                    PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
                }
                else
                {
                    CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
                }

                g_bPlayback = false;
                g_hFile.Close();

                return Plugin_Handled;
            }

            // Increment frame count
            f++;
        }

        // Update frame cutoff if individual is longer
        if (f > g_iFrames)
        {
            g_iFrames = f;
        }

        g_hFile.Close();

        iLastLoaded = i; 
    }

    // Clamp frame cutoff
    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
        {
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        }
        else
        {
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        }

        g_iFrames = MAX_FRAMES;
    }  

    if(iLastLoaded + 1 < POPULATION_SIZE)
    {
        // Generate rest of population if not all were loaded
        GeneratePopulation(iLastLoaded + 1);
    }
    else
    {
        g_bPopulation = true;

        if(client == 0)
        {
            PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
            PrintToServer("%s Loaded generation %s", g_cPrintPrefixNoColor, cBasePath);
            PrintToServer("%s You should run 'ga_sim' to calculate fitness values", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);
            CPrintToChat(client, "%s Loaded generation %s", g_cPrintPrefix, cBasePath);
            CPrintToChat(client, "%s You should run 'ga_sim' to calculate fitness values", g_cPrintPrefixNoColor);
        }    
    }          

    return Plugin_Handled;
}

// Summary:
// Handle population load from recording command
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

    // Get recording name from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to path
    char cPath[64] = "/GA/rec/";
    StrCat(cPath, sizeof(cPath), arg);

    // Reset frame cutoff
    g_iFrames = 0;

    // Keep track of individual frame counts
    int iFrameCounts[POPULATION_SIZE];

    // Keep track of last loaded individual
    int iLastLoaded = 0;

    // Loop through population
    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        // Get path for individual
        char cIndividualPath[64];
        strcopy(cIndividualPath, sizeof(cIndividualPath), cPath);

        // Append index to path if not 0
        char index[8];
        if(i != 0)
        {
            IntToString(i, index, sizeof(index));
            StrCat(cIndividualPath, sizeof(cIndividualPath), index);
        }

        // Open file for reading
        g_hFile = OpenFile(cIndividualPath, "r");

        if(g_hFile == null)
        {
            // Error if first individual
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
                // Reached last file
                break;
            }
        }

        // Go to beginning of file
        g_hFile.Seek(0, SEEK_SET);

        // Loop through lines in file
        char buffer[128];
        int j = 0;

        while(g_hFile.ReadLine(buffer, sizeof(buffer)))
        {
            // Split line
            char bu[3][18];
            int n = ExplodeString(buffer, ",", bu, 3, 18);
            
            if(n == 3)
            {
                // Parse buttons and angles
                g_iGAIndividualInputsInt[j][i] = StringToInt(bu[0]);
                g_fGAIndividualInputsFloat[j][i][0] = StringToFloat(bu[1]);
                g_fGAIndividualInputsFloat[j][i][1] = StringToFloat(bu[2]);
            }
            else
            {
                if(client == 0)
                {
                    PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
                }
                else
                {
                    CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
                }

                g_bPlayback = false;
                g_hFile.Close();

                return Plugin_Handled;
            }

            // Increment frame count
            iFrameCounts[i]++;
        }

        // Update frame cutoff if individual is longer
        if (iFrameCounts[i] > g_iFrames)
        {
            g_iFrames = iFrameCounts[i];
        }

        iLastLoaded = i;

        g_hFile.Close(); 
    }    

    if(client == 0)
    {
        PrintToServer("%s Loaded %d recordings from %s", g_cPrintPrefixNoColor, iLastLoaded + 1, cPath);
    }
    else
    {
        CPrintToChat(client, "%s Loaded %d recordings from %s", g_cPrintPrefix, iLastLoaded + 1, cPath);
    }

    // Clamp frame cutoff
    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
        {
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        }
        else
        {
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        }

        g_iFrames = MAX_FRAMES;
    }

    if(client == 0)
    {
        PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
    }
    else
    {
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);
    }

    // Pad other runs to match the longest one
    for(int i = 0; i < iLastLoaded; i++)
    {
        if(iFrameCounts[i] < g_iFrames)
        {
            Pad(i, iFrameCounts[i]);
        }
    }

    // Generate rest of the population if not enough were loaded
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

// Summary:
// Handle config save command
public Action CmdSaveConfig(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get config name from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to path
    char cPath[64] = "/GA/cfg/";
    StrCat(cPath, sizeof(cPath), arg);
    
    // Increment file path if name already exists
    int i = 0;
    while(FileExists(cPath))
    {
        i++;

        // Append name to path
        cPath = "/GA/cfg/";
        StrCat(cPath, sizeof(cPath), arg);

        // Append index to path
        char num[8];
        IntToString(i, num, sizeof(num));
        StrCat(cPath, sizeof(cPath), num);
    }
    
    // Open file for writing
    g_hFile = OpenFile(cPath, "w+");
    if(g_hFile == null)
    {
        if(client == 0)
        {
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        }

        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);

        return Plugin_Handled;
    }

    // Write frame count
    g_hFile.WriteLine("%d", g_iFrames);

    // Write start position, start rotation and end position
    g_hFile.WriteLine("%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f,%.16f", g_fGAStartPos[0], g_fGAStartPos[1], g_fGAStartPos[2], g_fGAStartAng[0], g_fGAStartAng[1], g_fGAStartAng[2], g_fGAEndPos[0], g_fGAEndPos[1], g_fGAEndPos[2]);
    
    // Loop through checkpoints
    for(int i = 0; i < MAX_CHECKPOINTS; i++)
    {
        // Check if checkpoint exists
        if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
        {
            // Write checkpoint position
            g_hFile.WriteLine("%.16f,%.16f,%.16f", g_fGACheckPoints[i][0], g_fGACheckPoints[i][1], g_fGACheckPoints[i][2]);
        }
    }

    g_hFile.Close();    

    if(client == 0)
    {
        PrintToServer("%s Saved config to %s", g_cPrintPrefixNoColor, cPath);
    }
    else
    {
        CPrintToChat(client, "%s Saved config to %s", g_cPrintPrefix, cPath);
    }

    return Plugin_Handled;
}

// Summary:
// Handle config load command
public Action CmdLoadConfig(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing name argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing name argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }
    
    // Get config name from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Append name to path
    char cPath[64] = "/GA/cfg/";
    StrCat(cPath, sizeof(cPath), arg);
    
    // Open file for reading
    if(FileExists(cPath))
    {
        g_hFile = OpenFile(cPath, "r");
    }
    else
    {
        if(client == 0)
        {
            PrintToServer("%s Can't find file %s.", g_cPrintPrefixNoColor, arg);
        }
        else
        {
            CPrintToChat(client, "%s Can't find file %s.", g_cPrintPrefix, arg);
        }

        return Plugin_Handled;
    }

    if(g_hFile == null)
    {
        if(client == 0)
        {
            PrintToServer("%s Something went wrong :(", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Something went wrong :(", g_cPrintPrefix);
        }

        PrintToServer("%s Invalid file handle", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    // Go to beginning of file
    g_hFile.Seek(0, SEEK_SET);
    
    // Buffer for reading
    char buffer[256];

    // Get frame count
    if(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        int iNum;
        if(StringToIntEx(buffer, iNum))
        {
            g_iFrames = iNum;
        }
        else
        {
            if(client == 0)
            {
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            }
            else
            {
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            }

            g_bPlayback = false;

            g_hFile.Close();

            return Plugin_Handled;
        }
    }

    // Read start position, start rotation and end position
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
            {
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            }
            else
            {
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            }

            g_bPlayback = false;

            g_hFile.Close();

            return Plugin_Handled;
        }
    }

    // Reset checkpoints
    for(int i = 0; i < MAX_CHECKPOINTS; i++)
    {
        g_fGACheckPoints[i] = { 0.0, 0.0, 0.0 };
    }

    // Read any checkpoints
    int iCP;
    while(g_hFile.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[3][18];
        int n = ExplodeString(buffer, ",", bu, 3, 18);
        
        if(n == 3)
        {
            for(int i = 0; i < 3; i++)
            {
                g_fGACheckPoints[iCP][i] = StringToFloat(bu[i]);
            }            
        }
        else
        {
            if(client == 0)
            {
                PrintToServer("%s Bad save format", g_cPrintPrefixNoColor);
            }
            else
            {
                CPrintToChat(client, "%s Bad save format", g_cPrintPrefix);
            }

            g_bPlayback = false;

            g_hFile.Close();

            return Plugin_Handled;
        }

        iCP++;
    }

    g_hFile.Close(); 

    if(client == 0)
    {
        PrintToServer("%s Loaded config from %s", g_cPrintPrefixNoColor, cPath);
    }
    else
    {
        CPrintToChat(client, "%s Loaded config from %s", g_cPrintPrefix, cPath);
    }

    // Reset debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    // Clamp frame cutoff
    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
        {
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        }
        else
        {
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        }

        g_iFrames = MAX_FRAMES;
    }

    if(client == 0)
    {
        PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
    }
    else
    {
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);
    }

    return Plugin_Handled;
}

// Summary:
// Handle timescale command 
public Action CmdSetTimeScale(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get timescale from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to float
    if(!StringToFloatEx(arg, g_fTimeScale))
    {
        if(client == 0)
        {
            PrintToServer("%s Failed to parse %s", g_cPrintPrefixNoColor, arg);
        }
        else
        {
            CPrintToChat(client, "%s Failed to parse %s", g_cPrintPrefix, arg);
        }

        return Plugin_Handled;
    }

    if(client == 0)
    {
        PrintToServer("%s Loop timescale set to %f", g_cPrintPrefixNoColor, g_fTimeScale);
    }
    else
    {
        CPrintToChat(client, "%s Loop timescale set to %f", g_cPrintPrefix, g_fTimeScale);
    }

    return Plugin_Handled;
}

// Summary:
// Handle frame cutoff command
public Action CmdSetFrames(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get cutoff from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to int
    if(!StringToIntEx(arg, g_iFrames))
    {
        if(client == 0)
        {
            PrintToServer("%s Failed to parse %s", g_cPrintPrefixNoColor, arg);
        }
        else
        {
            CPrintToChat(client, "%s Failed to parse %s", g_cPrintPrefix, arg);
        }

        return Plugin_Handled;
    }

    if(g_iFrames > MAX_FRAMES)
    {
        if(client == 0)
        {
            PrintToServer("%s Max frames limit is %d!", g_cPrintPrefixNoColor, MAX_FRAMES);
        }
        else
        {
            CPrintToChat(client, "%s Max frames limit is %d!", g_cPrintPrefix, MAX_FRAMES);
        }

        g_iFrames = MAX_FRAMES;
    }

    if(client == 0)
    {
        PrintToServer("%s Frames set to %f", g_cPrintPrefixNoColor, g_iFrames);
    }
    else
    {
        CPrintToChat(client, "%s Frames set to %d", g_cPrintPrefix, g_iFrames);
    }

    return Plugin_Handled;
}

// Summary:
// Handle mutation chance command
public Action CmdSetMutationChance(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get chance from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to float
    if(!StringToFloatEx(arg, g_fMutationChance))
    {
        if(client == 0)
        {
            PrintToServer("%s Failed to parse %s", g_cPrintPrefixNoColor, arg);
        }
        else
        {
            CPrintToChat(client, "%s Failed to parse %s", g_cPrintPrefix, arg);
        }

        return Plugin_Handled;
    }

    if(client == 0)
    {
        PrintToServer("%s Mutation chance set to %f", g_cPrintPrefixNoColor, g_fMutationChance);
    }
    else
    {
        CPrintToChat(client, "%s Mutation chance set to %f", g_cPrintPrefix, g_fMutationChance);
    }

    return Plugin_Handled;
}

// Summary:
// Handle rotation mutation chance command
public Action CmdSetRotationMutationChance(int client, int args)
{
    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing number argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing number argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get chance from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to float
    if(!StringToFloatEx(arg, g_fRotationMutationChance))
    {
        if(client == 0)
        {
            PrintToServer("%s Failed to parse %s", g_cPrintPrefixNoColor, arg);
        }
        else
        {
            CPrintToChat(client, "%s Failed to parse %s", g_cPrintPrefix, arg);
        }

        return Plugin_Handled;
    }

    if(client == 0)
    {
        PrintToServer("%s Rotation mutation chance set to %f", g_cPrintPrefixNoColor, g_fRotationMutationChance);
    }
    else
    {
        CPrintToChat(client, "%s Rotation mutation chance set to %f", g_cPrintPrefix, g_fRotationMutationChance);
    }

    return Plugin_Handled;
}

// Summary:
// Handle checkpoint remove command
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

    // Get checkpoint index from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to int
    int iCP;
    if(!StringToIntEx(arg, iCP))
    {
        CPrintToChat(client, "%s Failed to parse %s", g_cPrintPrefix, arg);
        return Plugin_Handled;
    }

    // Remove checkpoint
    g_fGACheckPoints[iCP] = { 0.0, 0.0, 0.0 };

    // Shift all checkpoints after iCP to new indices 
    for(int i = iCP; i < MAX_CHECKPOINTS; i++)
    {
        if(i < MAX_CHECKPOINTS - 1)
        {
            g_fGACheckPoints[i] = g_fGACheckPoints[i+1];
        }
    }

    // Reset last checkpoint
    // Will be a duplicate if all checkpoints are assigned before removing one
    g_fGACheckPoints[MAX_CHECKPOINTS - 1] = { 0.0, 0.0, 0.0 };

    CPrintToChat(client, "%s Checkpoint %d removed!", g_cPrintPrefix, iCP);

    // Update debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    return Plugin_Handled;
}

// Summary:
// Handle checkpoint add command
public Action CmdAddCheckpoint(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    // Find first unused checkpoint
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
            if(i >= MAX_CHECKPOINTS - 1)
            {
                CPrintToChat(client, "%s Checkpoint limit of %d reached! Try deleting some.", g_cPrintPrefix, MAX_CHECKPOINTS);
                return Plugin_Handled;
            }
        }
    }

    // Update debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    return Plugin_Handled;
}

// Summary:
// Handle start position command
public Action CmdStart(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    // Set global variables
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGAStartPos);
    GetClientEyeAngles(client, g_fGAStartAng);

    // Update debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    CPrintToChat(client, "%s Start set", g_cPrintPrefix);

    return Plugin_Handled;
}

// Summary:
// Handle end position command
public Action CmdEnd(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("%s This command cannot be used from server console.", g_cPrintPrefixNoColor);
        return Plugin_Handled;
    }

    // Set global variable
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", g_fGAEndPos);
    
    // Update debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines();
    }

    CPrintToChat(client, "%s End set", g_cPrintPrefix);

    return Plugin_Handled;
}

// Summary:
// Handle population clear command
public Action CmdClear(int client, int args)
{
    // Set global variables
    g_bPopulation = false;
    g_iTargetGen = 0;
    g_iCurrentGen = 0;

    if(client == 0)
    {
        PrintToServer("%s Cleared population!", g_cPrintPrefixNoColor);
    }
    else
    {
        CPrintToChat(client, "%s Cleared population!", g_cPrintPrefix);
    }

    return Plugin_Handled;
}

// Summary:
// Handle manual generation command
public Action CmdGen(int client, int args)
{
    GeneratePopulation();
    return Plugin_Handled;
}

// Summary:
// Handle manual simulation command
public Action CmdSim(int client, int args)
{
    ServerCommand("host_timescale %f", g_fTimeScale);
    MeasureFitness(0);
    return Plugin_Handled;
}

// Summary:
// Handle manual breed command
public Action CmdBreed(int client, int args)
{
    Breed();
    return Plugin_Handled;
}

// Summary:
// Handle breeding loop stop command
public Action CmdStopLoop(int client, int args)
{
    g_iTargetGen = g_iCurrentGen;
    return Plugin_Handled;
}

// Summary:
// Handle breeding loop command
public Action CmdLoop(int client, int args)
{
    // Prevent bot from taking damage
    SetEntProp(g_iBot, Prop_Data, "m_takedamage", 0, 0);

    if(args < 1)
    {
        if(client == 0)
        {
            PrintToServer("%s Missing number of generations argument", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Missing number of generations argument", g_cPrintPrefix);
        }

        return Plugin_Handled;
    }

    // Get loop count from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to int
    int gen = 0;
    if(StringToIntEx(arg, gen))
    {
        g_iTargetGen += gen;

        // Generate population if doesn't exist
        if(!g_bPopulation)
        {
            GeneratePopulation();
            return Plugin_Handled;
        }          
        
        // Start breeding
        if(g_iTargetGen > g_iCurrentGen)
        {
            Breed();
        }
    }        
    else
    {
        if(client == 0)
        {
            PrintToServer("%s Couldn't parse number", g_cPrintPrefixNoColor);
        }
        else
        {
            CPrintToChat(client, "%s Couldn't parse number", g_cPrintPrefix);
        }
    }
        
    if(client == 0)
    {
        PrintToServer("%s Loop started", g_cPrintPrefixNoColor);
    }
    else
    {
        CPrintToChat(client, "%s Loop started", g_cPrintPrefix);
    }

    return Plugin_Handled;
}

// Summary:
// Handle generated individual play command
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

    // Get individual index from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to int
    int index = 0;
    if(StringToIntEx(arg, index))
    {
        g_iSimIndex = index;
        g_bGAplayback = true;
        MeasureFitness(index);
        CPrintToChat(client, "%s Playing %d-%d", g_cPrintPrefix, g_iCurrentGen, index);
    }        
    else
    {
        CPrintToChat(client, "%s Couldn't parse number", g_cPrintPrefix);        
    }
    
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
    if (g_iBot != -1)
    {
        return;
    }

    g_iBot = BotController_CreateBot(g_cBotName);
    
    if (!IsClientInGame(g_iBot))
    {
        SetFailState("%s", "Cannot create bot");
    }

    ChangeClientTeam(g_iBot, g_iBotTeam);
    TF2_SetPlayerClass(g_iBot, TFClass_Pyro);
    ServerCommand("mp_waitingforplayers_cancel 1;");
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