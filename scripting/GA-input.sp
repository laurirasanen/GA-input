/* ****************************************************************
    GA-input: Genetic algorithm plugin for Team Fortress 2.

    Copyright (C) 2020 Lauri Räsänen

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
**************************************************************** */

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
#include <botcontroller>

// ****************************************************************
// Plugin modules
// ****************************************************************
#include "core/debug.sp"
#include "core/util.sp"

// ****************************************************************
// Pragma
// ****************************************************************
#pragma semicolon 1         // Don't allow missing semicolons
#pragma newdecls required   // Enforce new 1.7 SourcePawn syntax

// ****************************************************************
// Constants
// ****************************************************************
#define MODE_RJ false
#define MAX_CHECKPOINTS 100
#define MAX_FRAMES 1000         // Max length of an individual, about 15 seconds (assuming 66.6 ticks/s)
#define POPULATION_SIZE 300
#define LUCKY_FEW 30            // Individuals not part of the fittest chosen to be parents
#define INPUT_INTERVAL 20       // How many ticks to repeat inputs, MAX_FRAMES must be evenly divisible by this

#if MODE_RJ
#define ANGLE_DELTA 6.0         // The maximum view angle change in a tick
#define MAX_PITCH 89.0          // How far up or down the view can be pitched
#else
#define ANGLE_DELTA 2.5
#define MAX_PITCH 30.0
#endif

// ****************************************************************
// Global variables
// ****************************************************************
bool g_bRecording;                              // Player recording status
bool g_bPlayback;                               // Player recording playback status
bool g_bSimulating;                             // Individual simulation status
bool g_bGAIndividualMeasured[POPULATION_SIZE];  // Population individuals measured status
bool g_bPopulation;                             // Population existence status
bool g_bGAPlayback;                             // Generated individual playback status
bool g_bDraw;                                   // Debug line draw status
bool g_bMadeToEnd;                              // Individual reached end position status
bool g_bShowKeys;                               // Show bots keypresses status

int g_iBot = -1;                                // Bot client index
int g_iBotTeam = 2;                             // Bot team
#if MODE_RJ
int g_iPossibleButtons[7] = {IN_JUMP, IN_DUCK, IN_FORWARD, IN_MOVELEFT, IN_MOVERIGHT, IN_ATTACK, IN_DUCK};  // Buttons that can be generated
#else
int g_iPossibleButtons[5] = {IN_JUMP, IN_DUCK, IN_FORWARD, IN_MOVELEFT, IN_MOVERIGHT};
#endif
int g_iSimIndex;                                // Individual index being simulated
int g_iSimCurrentFrame;                         // Current frame of simulation
int g_iTargetGen;                               // Target generation to generate until
int g_iCurrentGen;                              // Current generation index
int g_iLastImproveGen;
int g_iGAIndividualInputsInt[MAX_FRAMES/INPUT_INTERVAL][POPULATION_SIZE];  // Button inputs of individuals
int g_iFrames;                                  // Frame cutoff (chromosome length)
int g_iRecordingClient = -1;                    // Recording client index
int g_iLeftOverFrames = 0;                      // Time saved by individual when reaching end
int g_iSolutionStopDelay = -1;                  // Automatically stop looping after this many generations since first solution. <0 = disabled
int g_iLoopBeginTime = 0;                       // Unix timestamp for when generation loop started

float g_fTimeScale = 1000.0;                    // Timescale used for simulating
float g_fGAIndividualInputsFloat[MAX_FRAMES/INPUT_INTERVAL][POPULATION_SIZE][2];   // Angle inputs of individuals
float g_fGAIndividualFitness[POPULATION_SIZE];  // Fitness of individuals
float g_fGAStartPos[3];                         // Starting position
float g_fGAStartAng[3];                         // Starting angle
float g_fGAEndPos[3];                           // End position of fitness line
float g_fGACheckPoints[MAX_CHECKPOINTS][3];     // Checkpoints of fitness line
float g_fTelePos[3] = { 0.0, 0.0, 0.0 };        // Position where individual teleported
float g_fOverrideFitness;                       // Override to use for individual fitness
float g_fLastPos[3];                            // Position of individual during last tick
float g_fEndCutoff = 200.0;                     // Distance from end position to end simulation
float g_fVerticalFitnessScale = 0.5;            // Used for subtracting points if below the closest point on fitness line
float g_fLastImproveFitness = -1000000000000.0;
// These values were found to be roughly ideal for input interval of 20 ticks.
// You'll probably want to lower the one for movement keys if you lower the input interval.
#if MODE_RJ
float g_fMutationChance = 0.15;                 // Button mutation chance
float g_fRotationMutationChance = 0.1;          // Angles mutation chance
#else
float g_fMutationChance = 0.05;
float g_fRotationMutationChance = 0.1;
#endif

File g_hFile;                                   // File handle
Handle g_hShowKeys;                             // Show keys hud handle

char g_cBotName[] = "GA-BOT";                       // Name of the bot
char g_cPrintPrefix[] = "[{orange}GA{default}]";    // Chat prefix for prints
char g_cPrintPrefixNoColor[] = "[GA]";              // Prefix for server console prints
char g_cLastRecord[64];                             // Name of last player recording
char g_cServerConfig[] = "sv_cheats 1; tf_allow_server_hibernation 0; sm config SlowScriptTimeout 0; sv_timeout 300"; // Server commands to apply on load and map start

// Plugin info
// https://sm.alliedmods.net/new-api/core/PluginInfo
public Plugin myinfo =
{
    name = "GA-input",
    author = "laurirasanen",
    description = "Genetic algorithm for surf and rocketjump",
    version = "1.0.13",
    url = "https://github.com/laurirasanen"
};

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
    RegConsoleCmd("ga_solution_stop_delay", CmdSetSolutionStopDelay, ""); // Set delay for stopping after solution found
    
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
    RegConsoleCmd("ga_skeys", CmdShowKeys, "");     // Toggle display of bots keys
    
    // Start a timer for spawning bot
    CreateTimer(1.0, Timer_SetupBot);

    // Set server config
    ServerCommand(g_cServerConfig);

    // Create hud handle for show keys
    g_hShowKeys = CreateHudSynchronizer();

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
    ServerCommand(g_cServerConfig);
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
    // Handle bot related functionality
    if (client == g_iBot)
    {
        return OnPlayerRunCmd_Bot(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse);
    }

    // Handle player related functionality  
    return OnPlayerRunCmd_Human(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse);
}

public Action OnPlayerRunCmd_Bot(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(!g_bSimulating)
    {
        return Plugin_Continue;
    }

    // Check if individual has already been measured (from previous generations)
    if(g_bGAIndividualMeasured[g_iSimIndex] && !g_bGAPlayback)
    {
        return OnIndividualEnd();
    }

    // Check if we're at the end of this individual
    if(g_iSimCurrentFrame >= g_iFrames)
    {
        return OnIndividualEnd();
    }
    
    // Get bot's position
    float fPos[3];
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", fPos);

    // Not the first frame
    if(g_iSimCurrentFrame != 0)
    {
        // Check if bot gets teleported
        if(GetVectorDistance(g_fLastPos, fPos) > 91.0)
        {
            // If moved over 91 units since last tick, assume teleported
            // Max velocity is 3500u/s on all 3 axes,
            // sqrt(sqrt(3500^2 + 3500^2)^2 + 3500^2) ~ 91

            // Set last position of bot before teleporting
            // for fitness calculation
            g_fTelePos = g_fLastPos;
            return OnIndividualEnd();
        }

        // Check if bot is close enough to the end position
        // (within cutoff distance and above the end point
        // to prevent finishing through floors and such)
        if (GetVectorDistance(fPos, g_fGAEndPos) < g_fEndCutoff && fPos[2] > g_fGAEndPos[2])
        {
            g_bMadeToEnd = true;
            return OnIndividualEnd();
        }
    }

    // Save last position
    g_fLastPos = fPos;
    
    // Get buttons for current frame
    buttons = g_iGAIndividualInputsInt[g_iSimCurrentFrame/INPUT_INTERVAL][g_iSimIndex];
    
    // Add impulse 101 to refill health and ammo
    impulse |= 101;
    
    // Movement buttons don't do anything for the bot,
    // set desired velocity manually based on buttons.
    // Desired velocity still gets capped by class max movement speed,
    // use 400 to cover max movement speed of all classes.
    VelocityFromButtons(vel, buttons);
    
    // Remove movement buttons to be sure
    buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);

    // Get delta angles for current frame
    float eyeAngles[3];
    
    if (g_iSimCurrentFrame == 0)
    {
        // Teleporting to start does not set eye angles it seems
        eyeAngles = g_fGAStartAng;
    }
    else
    {
        GetClientEyeAngles(client, eyeAngles);
    }

    eyeAngles[0] += g_fGAIndividualInputsFloat[g_iSimCurrentFrame/INPUT_INTERVAL][g_iSimIndex][0];
    eyeAngles[1] += g_fGAIndividualInputsFloat[g_iSimCurrentFrame/INPUT_INTERVAL][g_iSimIndex][1];

    ClampEyeAngles(eyeAngles, MAX_PITCH);

    angles[0] = eyeAngles[0];
    angles[1] = eyeAngles[1];
    angles[2] = 0.0;

    // Show keys
    if(g_bShowKeys)
    {
        UpdateKeyDisplay(g_iGAIndividualInputsInt[g_iSimCurrentFrame / INPUT_INTERVAL][g_iSimIndex], g_hShowKeys);
    }
    
    // Increment frame
    g_iSimCurrentFrame++;        
    
    return Plugin_Changed;
}

public Action OnPlayerRunCmd_Human(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (g_hFile == null)
    {
        return Plugin_Continue;
    }

    if(client != g_iRecordingClient)
    {
        return Plugin_Continue;
    }

    // Handle player recording inputs
    if(g_bRecording)
    {
        // Use same movement method as the bot for consistency
        VelocityFromButtons(vel, buttons);

        // Write buttons and angles to file
        g_hFile.WriteLine("%d,%.16f,%.16f", buttons, angles[0], angles[1]);

        // Remove movement buttons to be sure
        buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);

        return Plugin_Changed;
    }

    // Handle playing back a player recording
    if(g_bPlayback)
    { 
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
                VelocityFromButtons(vel, buttons);

                // Disable button based movement
                buttons &= ~(IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT);

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
        else 
        {
            PrintToServer("%s Unexpected end of file while playing back recording", g_cPrintPrefixNoColor);
            StopPlayback();
            return Plugin_Continue;
        }
    }

    return Plugin_Continue;
}

// Summary:
// Stop playback of a player recording
public void StopPlayback()
{
    g_bPlayback = false;

    if(g_hFile != null)
    {
        g_hFile.Close();
    }

    CPrintToChatAll("%s Playback stopped!", g_cPrintPrefix);
}


// Summary:
// Pad length of individual with random inputs
public void Pad(int individual, int startFrame)
{
    PrintToServer("%s Padding %d by %d frames", g_cPrintPrefixNoColor, individual, g_iFrames - startFrame);
    
    for(int t = startFrame; t < g_iFrames/INPUT_INTERVAL; t++)
    {
        for(int i = 0; i < sizeof(g_iPossibleButtons); i++)
        {
            // Random buttons
            if(GetRandomFloat(0.0, 1.0) < g_fMutationChance)
            {
                if(g_iGAIndividualInputsInt[t][individual] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                {
                    // Has button, remove
                    g_iGAIndividualInputsInt[t][individual] &= ~g_iPossibleButtons[i];
                }
                else
                {
                    // Doesn't have button, add
                    g_iGAIndividualInputsInt[t][individual] |= g_iPossibleButtons[i];
                }
            }
        }

        // Random mouse movement
        if(GetRandomFloat(0.0, 1.0) < g_fRotationMutationChance)
        {
            g_fGAIndividualInputsFloat[t][individual][0] = GetRandomFloat(-ANGLE_DELTA, ANGLE_DELTA);
            g_fGAIndividualInputsFloat[t][individual][1] = GetRandomFloat(-ANGLE_DELTA, ANGLE_DELTA);
        }
        else
        {
            g_fGAIndividualInputsFloat[t][individual][0] = 0.0;
            g_fGAIndividualInputsFloat[t][individual][1] = 0.0;
        }
    }   
}

// Summary:
// Timer for spawning bot
public Action Timer_SetupBot(Handle hTimer)
{
    if (g_iBot != -1)
    {
        return;
    }

    g_iBot = BotController_CreateBot(g_cBotName);
    
    if (!IsClientInGame(g_iBot))
    {
        SetFailState("%s", "Couldn't create bot");
    }

    ChangeClientTeam(g_iBot, g_iBotTeam);
#if MODE_RJ
    TF2_SetPlayerClass(g_iBot, TFClass_Soldier);
#else
    TF2_SetPlayerClass(g_iBot, TFClass_Pyro);
#endif
    ServerCommand("mp_waitingforplayers_cancel 1;");
}

// Summary:
// Timer for killing an entity
public Action Timer_KillEnt(Handle hTimer, int ent)
{
    if(IsValidEntity(ent))
    {
        AcceptEntityInput(ent, "Kill");
    }
}

// Summary:
// Timer for measuring individual
public Action MeasureTimer(Handle timer, int index)
{
    g_iSimIndex = index;
    g_iSimCurrentFrame = 0;
    g_bSimulating = true;
}

Action OnIndividualEnd()
{
    g_bSimulating = false;

    if(!g_bGAIndividualMeasured[g_iSimIndex])
    {        
        g_bGAIndividualMeasured[g_iSimIndex] = true;            
        // Set amount of frames saved from cutoff limit
        g_iLeftOverFrames = g_iFrames - g_iSimCurrentFrame;
        CalculateFitness(g_iSimIndex);
    }

    // Return if playing back instead of measuring
    if(g_bGAPlayback)
    {
        g_bGAPlayback = false;
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

        char timeStamp[9];
        FormatUnixTimestamp(timeStamp, GetTime() - g_iLoopBeginTime);

        PrintToServer(
            "%s Generation %d | best: %d (%f) | imp^: %d | time: %s", 
            g_cPrintPrefixNoColor, 
            g_iCurrentGen, 
            fittestIndex, 
            bestFitness, 
            g_iCurrentGen - g_iLastImproveGen,
            timeStamp
        );

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

// Summary:
// Generate a population
void GeneratePopulation(int iStartIndex = 0)
{
    // Reset timescale to avoid client timeout when server freezes
    ServerCommand("host_timescale 1");

    // Loop through individuals
    for(int p = iStartIndex; p < POPULATION_SIZE; p++)
    {
        for(int t = 0; t < g_iFrames/INPUT_INTERVAL; t++)
        {
            for(int i = 0; i < sizeof(g_iPossibleButtons); i++)
            {
                // Random key inputs
                if(GetRandomFloat(0.0, 1.0) < g_fMutationChance * 2.0)
                {
                    if(g_iGAIndividualInputsInt[t][p] & g_iPossibleButtons[i] == g_iPossibleButtons[i])
                    {
                        // Has button, remove
                        g_iGAIndividualInputsInt[t][p] &= ~g_iPossibleButtons[i];
                    }
                    else
                    {
                        // Doesn't have button, add
                        g_iGAIndividualInputsInt[t][p] |= g_iPossibleButtons[i];
                    }
                }
            }

            // Random mouse movement
            if(GetRandomFloat(0.0, 1.0) < g_fRotationMutationChance * 2.0)
            {
                g_fGAIndividualInputsFloat[t][p][0] = GetRandomFloat(-ANGLE_DELTA, ANGLE_DELTA);
                g_fGAIndividualInputsFloat[t][p][1] = GetRandomFloat(-ANGLE_DELTA, ANGLE_DELTA);
            }
            else
            {
                g_fGAIndividualInputsFloat[t][p][0] = 0.0;
                g_fGAIndividualInputsFloat[t][p][1] = 0.0;
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

    // Start measuring loop
    MeasureFitness(0);
}

// Summary:
// Calculate fitness of an individual
public void CalculateFitness(int individual)
{
    float fPlayerPos[3];
    float fClosestPoint[3];
    int iLastCP = -1;
    
    GetEntPropVector(g_iBot, Prop_Data, "m_vecAbsOrigin", fPlayerPos);
    fClosestPoint = g_fGAStartPos;
    
    // Get position individual teleported at
    if(g_fTelePos[0] != 0.0 && g_fTelePos[1] != 0.0 && g_fTelePos[2] != 0.0)
    {
        fPlayerPos = g_fTelePos;
    }
    
    // Reset teleport position
    g_fTelePos[0] = 0.0;
    g_fTelePos[1] = 0.0;
    g_fTelePos[2] = 0.0;   

    if (g_bMadeToEnd)
    {
        fClosestPoint = g_fGAEndPos;

        for(int i = 0; i < MAX_CHECKPOINTS; i++) 
        {
            // Check if checkpoint is valid
            if(g_fGACheckPoints[i][0] != 0 && g_fGACheckPoints[i][1] != 0 && g_fGACheckPoints[i][2] != 0)
            {
                iLastCP = i;
            }
            else
            {
                break;
            }
        }
    }
    else
    {
        // Loop through checkpoints to find the last checkpoint individual passed
        // and the closest point on the fitness line
        for(int i = -1; i < MAX_CHECKPOINTS - 1; i++) 
        {
            float fTempPos[3];

            // Check if next checkpoint is valid
            if(g_fGACheckPoints[i + 1][0] != 0 && g_fGACheckPoints[i + 1][1] != 0 && g_fGACheckPoints[i + 1][2] != 0)
            {
                float fCurrentToNext[3];
                float fPlayerToCurrent[3];

                if(i == -1)
                {
                    // Start position to first checkpoint
                    ClosestPoint(g_fGAStartPos, g_fGACheckPoints[i + 1], fPlayerPos, fTempPos);
                    SubtractVectors(g_fGACheckPoints[i + 1], g_fGAStartPos, fCurrentToNext);
                    SubtractVectors(g_fGAStartPos, fPlayerPos, fPlayerToCurrent);
                }
                else
                {
                    // Checkpoint i to i + 1
                    ClosestPoint(g_fGACheckPoints[i], g_fGACheckPoints[i + 1], fPlayerPos, fTempPos);
                    SubtractVectors(g_fGACheckPoints[i + 1], g_fGACheckPoints[i], fCurrentToNext);
                    SubtractVectors(g_fGACheckPoints[i], fPlayerPos, fPlayerToCurrent);
                }             

                // Check if individual has passed checkpoint
                if (GetVectorDotProduct(fCurrentToNext, fPlayerToCurrent) < 0)
                {
                    // If dot product < 0
                    // individual has passed checkpoint i

                    // Check if new point is closer than previous
                    if(GetVectorDistance(fTempPos, fPlayerPos) < GetVectorDistance(fClosestPoint, fPlayerPos))
                    {
                        fClosestPoint = fTempPos;
                        iLastCP = i;
                    }
                }
            }
            else
            {          
                // Checkpoint i + 1 is not valid

                if(i == -1)
                {
                    // No checkpoints,
                    // get closest point from start to end position
                    ClosestPoint(g_fGAEndPos, g_fGAStartPos, fPlayerPos, fClosestPoint);
                }
                else
                {
                    // Has checkpoints, i was the last one

                    float fCurrentToNext[3];
                    float fPlayerToCurrent[3];

                    // Checkpoint i to end position
                    ClosestPoint(g_fGACheckPoints[i], g_fGAEndPos, fPlayerPos, fTempPos);
                    SubtractVectors(g_fGAEndPos, g_fGACheckPoints[i], fCurrentToNext);
                    SubtractVectors(g_fGACheckPoints[i], fPlayerPos, fPlayerToCurrent);

                    // Check if individual passed checkpoint i
                    if (GetVectorDotProduct(fCurrentToNext, fPlayerToCurrent) < 0)
                    {
                        // If dot product < 0
                        // player has passed checkpoint i

                        // Check if new point is closer than previous
                        if(GetVectorDistance(fTempPos, fPlayerPos) < GetVectorDistance(fClosestPoint, fPlayerPos))
                        {
                            fClosestPoint = fTempPos;
                            iLastCP = i;
                        }
                    }
                }

                break;
            }
        }
    }
    
    // Get distance along the fitness line to closest point
    float fDistance;
    
    // Loop through all passed checkpoints
    for(int i = 0; i <= iLastCP; i++)
    {
        if(i == 0)
        {
            fDistance += GetVectorDistance(g_fGAStartPos, g_fGACheckPoints[i]);
        }
        else
        {
            fDistance += GetVectorDistance(g_fGACheckPoints[i - 1], g_fGACheckPoints[i]);
        }
    }
    
    // Add distance from last checkpoint or start position
    // to closest point
    if(iLastCP < 0)
    {
        fDistance += GetVectorDistance(g_fGAStartPos, fClosestPoint);
    }
    else
    {
        fDistance += GetVectorDistance(g_fGACheckPoints[iLastCP], fClosestPoint);
    }
        
    // Subtract distance away from line
    fDistance -= GetVectorDistance(fClosestPoint, fPlayerPos);

    if (fPlayerPos[2] < fClosestPoint[2])
    {
        // Player is below the point, subtract extra points.

        // We want to prioritize height so that
        // the bot will actually get on top of the end platform
        // and not get stuck at a local maximum underneath it.
        fDistance -= (fClosestPoint[2] - fPlayerPos[2]) * g_fVerticalFitnessScale;
    }
    
    // Set fitness to final distance
    g_fGAIndividualFitness[individual] = fDistance;

    // Override fitness if set
    if(g_fOverrideFitness != 0.0)
    {
        g_fGAIndividualFitness[individual] = g_fOverrideFitness;
    }

    // Reset override
    g_fOverrideFitness = 0.0;

    // Add extra fitness for time saved if individual made it to the end
    if (g_bMadeToEnd)
    {
        g_fGAIndividualFitness[individual] += g_iLeftOverFrames;
    }
    else
    {
        // Add small amount of fitness if the simulation ends early,
        // even when we don't make it to the end.
        // This is to discourage the bot from just standing
        // still on a platform or on top of a ramp.
        g_fGAIndividualFitness[individual] += g_iLeftOverFrames * 0.1;
    }

    if (g_bMadeToEnd && g_iSolutionStopDelay >= 0)
    {
        // Stop automatically after reaching end
        if (g_iTargetGen - g_iCurrentGen > g_iSolutionStopDelay)
        {
            PrintToServer("- - - - - - - - - - - - - - - - - - - - - - - -");
            PrintToServer("%s Reached end, stopping in %d generations.",  g_cPrintPrefixNoColor, g_iSolutionStopDelay);
            PrintToServer("- - - - - - - - - - - - - - - - - - - - - - - -");
            g_iTargetGen = g_iCurrentGen + g_iSolutionStopDelay;
        }
    }

    // Reset end status
    g_bMadeToEnd = false;
    g_iLeftOverFrames = 0;

    // Draw laser from individual to closest point
    if(g_bDraw)
    {
        int ent = DrawLaser(fPlayerPos, fClosestPoint, 255, 0, 0);
        CreateTimer(5.0, Timer_KillEnt, ent);
    }
}

// Summary:
// Measure fitness of an individual
public void MeasureFitness(int index)
{
    // Teleport to start
    TeleportEntity(g_iBot, g_fGAStartPos, g_fGAStartAng, view_as<float>({ 0.0, 0.0, 0.0 }));

    // Wait a second in case start position is in the air
    CreateTimer(1.0, MeasureTimer, index);
}

// Summary:
// Breed a new generation
public void Breed()
{
    ServerCommand("host_timescale 1");

    // Order fitness values
    float fOrder[POPULATION_SIZE];

    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        fOrder[i] = g_fGAIndividualFitness[i];
    }

    SortFloats(fOrder, POPULATION_SIZE, Sort_Descending);
    if (fOrder[0] > g_fLastImproveFitness)
    {
        g_fLastImproveFitness = fOrder[0];
        g_iLastImproveGen = g_iCurrentGen;
    }

    // Get the indices of fittest 50% - LUCKY_FEW individuals
    int iFittest[POPULATION_SIZE/2];

    for(int i = 0; i < (POPULATION_SIZE / 2) - LUCKY_FEW; i++)
    {
        for(int j = 0; j < POPULATION_SIZE; j++)
        {
            if(fOrder[i] == g_fGAIndividualFitness[j])
            {
                iFittest[i] = j;
            }
        }
    }
    
    // Get the indices of LUCKY_FEW individuals
    for(int i = 0; i < LUCKY_FEW; i++)
    {
        bool bDone = false;

        while(!bDone)
        {
            // Get random individual from population
            int iRandom = GetRandomInt(0, POPULATION_SIZE-1);

            bool bAssigned;

            // Check if individual is already in fittest
            for(int j = 0; j < POPULATION_SIZE / 2; j++)
            {
                if(iFittest[j] == iRandom)
                {
                    bAssigned = true;
                }
            }

            // Add to fittest
            if(!bAssigned)
            {
                iFittest[(POPULATION_SIZE / 2) - LUCKY_FEW + i] = iRandom;
                bDone = true;
            }
        }
    }
    
    // Pair parents randomly
    int iParents[POPULATION_SIZE/4][2];
    bool bTaken[POPULATION_SIZE/2];
    int iParentIndex = 0;

    for(int i = 0; i < POPULATION_SIZE / 2; i++)
    {
        if(!bTaken[i])
        {   
            // Get random parent
            int iRandom = GetRandomInt(0, (POPULATION_SIZE/2) - 1);

            // Increment if taken
            while(bTaken[iRandom] || iRandom == i)
            {
                iRandom = GetRandomInt(0, (POPULATION_SIZE/2) - 1);
            }
            
            // Set parents
            iParents[iParentIndex][0] = iFittest[i];
            iParents[iParentIndex][1] = iFittest[iRandom];

            // Set taken status
            bTaken[i] = true;
            bTaken[iRandom] = true;

            iParentIndex++;
        }
    }

    // Create arrays for new children
    int iChildrenInputsInt[MAX_FRAMES/INPUT_INTERVAL][POPULATION_SIZE/2];
    float fChildrenInputsFloat[MAX_FRAMES/INPUT_INTERVAL][POPULATION_SIZE/2][2];

    // loop through parents
    for(int i = 0; i < POPULATION_SIZE / 4; i++)
    {
        // Two-point crossover
        int iSize = (g_iFrames/INPUT_INTERVAL) - 1;
        int iCxPoint1 = GetRandomInt(1, iSize);
        int iCxPoint2 = GetRandomInt(1, iSize - 1);

        if (iCxPoint2 >= iCxPoint1)
        {
            iCxPoint2 += 1;
        }
        else
        {
            // Swap crossover points
            int iTemp = iCxPoint1;
            iCxPoint1 = iCxPoint2;
            iCxPoint2 = iTemp;
        }

        // Loop through both parents
        for (int iCrossParent = 0; iCrossParent < 2; iCrossParent++)
        {
            // A pair of parents will create 2 children,
            // determine child index
            int iChildIndex = i*2 + iCrossParent;

            // Loop through frames
            for(int t = 0; t < g_iFrames/INPUT_INTERVAL; t++)
            {            
                // Get genes from other parent if frame is between crossover points
                if(t >= iCxPoint1 && t <= iCxPoint2)
                {
                    iCrossParent = iCrossParent == 0 ? 1 : 0;
                }

                // Get buttons from parent
                for(int j = 0; j < sizeof(g_iPossibleButtons); j++)
                {
                    // Check if parent has button
                    if(g_iGAIndividualInputsInt[t][iParents[i][iCrossParent]] & g_iPossibleButtons[j] == g_iPossibleButtons[j])
                    {
                        // Parent has button, add to child
                        iChildrenInputsInt[t][iChildIndex] |= g_iPossibleButtons[j];
                    }
                    else
                    {
                        // Parent does not have button, remove from child
                        iChildrenInputsInt[t][iChildIndex] &= ~g_iPossibleButtons[j];
                    }

                    // Random mutations
                    if(GetRandomFloat(0.0, 1.0) < g_fMutationChance)
                    {
                        if(iChildrenInputsInt[t][iChildIndex] & g_iPossibleButtons[j] == g_iPossibleButtons[j])
                        {
                            // Has button, remove
                            iChildrenInputsInt[t][iChildIndex] &= ~g_iPossibleButtons[j];
                        }
                        else
                        {                            
                            // Doesn't have button, add
                            iChildrenInputsInt[t][iChildIndex] |= g_iPossibleButtons[j];
                        }
                    }
                }

                for(int j = 0; j < 2; j++)
                {
                    if(GetRandomFloat(0.0, 1.0) < g_fRotationMutationChance)
                    {
                        // Random mutations
                        fChildrenInputsFloat[t][iChildIndex][j] = GetRandomFloat(-ANGLE_DELTA, ANGLE_DELTA);
                    }
                    else
                    {
                        // Get angles from parent
                        fChildrenInputsFloat[t][iChildIndex][j] = g_fGAIndividualInputsFloat[t][iParents[i][iCrossParent]][j];
                    }
                }
            }
        }
    }

    // Overwrite least fittest with new children
    int iLastUsedChild = 0;

    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        // Check if individual is a parent
        bool bParent = false;

        for(int j = 0; j < POPULATION_SIZE / 4; j++)
        {
            if (iParents[j][0] == i || iParents[j][1] == i)
            {
                bParent = true;
            }
        }

        if(bParent)
        {
            continue;
        }
        
        // Overwrite frames
        for (int j = 0; j < g_iFrames/INPUT_INTERVAL; j++)
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

    ServerCommand("host_timescale %f", g_fTimeScale);  

    MeasureFitness(0);      
}

// ****************************************************************
// Command callbacks
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
    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, view_as<float>({ 0.0, 0.0, 0.0 }));

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
        PrintToServer("%s Couldn't find recording %s to delete", g_cPrintPrefixNoColor, cPath);
        return Plugin_Handled;
    }
    
    // Make sure file exists
    if(FileExists(cPath))
    {
        if(DeleteFile(cPath, false))
        {
            PrintToServer("%2 Deleted recording %s", g_cPrintPrefixNoColor, cPath);
        }
        else
        {
            PrintToServer("%s Failed to delete recording %s", g_cPrintPrefixNoColor, cPath);
        }
    }
    else
    {
        PrintToServer("%s Couldn't find recording %s to delete, file doesn't exist", g_cPrintPrefixNoColor, cPath);
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
    TeleportEntity(client, g_fGAStartPos, g_fGAStartAng, view_as<float>({ 0.0, 0.0, 0.0 }));

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
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
// Handle show keys command
public Action CmdShowKeys(int client, int args)
{
    g_bShowKeys = !g_bShowKeys;

    if (g_bShowKeys)
    {
        CPrintToChatAll("%s Showing bots keys", g_cPrintPrefix);
    }
    else
    {
        CPrintToChatAll("%s Hiding bots keys", g_cPrintPrefix);
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
    int iSuffix = 0;
    while(FileExists(cPath))
    {
        iSuffix++;

        // Append name to path
        cPath = "/GA/gen/";
        StrCat(cPath, sizeof(cPath), arg);

        // Append index to path
        char num[8];
        IntToString(iSuffix, num, sizeof(num));
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
            // Write all frames for compatibility with other INPUT_INTERVAL values
            int f = j / INPUT_INTERVAL;
            g_hFile.WriteLine("%d,%.16f,%.16f", g_iGAIndividualInputsInt[f][i], g_fGAIndividualInputsFloat[f][i][0], g_fGAIndividualInputsFloat[f][i][1]);
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
                g_iGAIndividualInputsInt[f/INPUT_INTERVAL][i] = StringToInt(bu[0]);
                g_fGAIndividualInputsFloat[f/INPUT_INTERVAL][i][0] = StringToFloat(bu[1]);
                g_fGAIndividualInputsFloat[f/INPUT_INTERVAL][i][1] = StringToFloat(bu[2]);
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
            CPrintToChat(client, "%s You should run 'ga_sim' to calculate fitness values", g_cPrintPrefix);
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
        if(iFrameCounts[i] < g_iFrames/INPUT_INTERVAL)
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
    int iSuffix = 0;
    while(FileExists(cPath))
    {
        iSuffix++;

        // Append name to path
        cPath = "/GA/cfg/";
        StrCat(cPath, sizeof(cPath), arg);

        // Append index to path
        char num[8];
        IntToString(iSuffix, num, sizeof(num));
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
        g_fGACheckPoints[i] = view_as<float>({ 0.0, 0.0, 0.0 });
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
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
        PrintToServer("%s Frames set to %d", g_cPrintPrefixNoColor, g_iFrames);
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
        CPrintToChat(client, "%s Rotation mutation chance set to %f", g_cPrintPrefixNoColor, g_fRotationMutationChance);
    }

    return Plugin_Handled;
}

// Summary:
// Handle setting automatic stop delay
public Action CmdSetSolutionStopDelay(int client, int args)
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

    // Get number from command args
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));

    // Parse to int
    int iNum;
    if(!StringToIntEx(arg, iNum))
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

    g_iSolutionStopDelay = iNum;

    if(client == 0)
    {
        PrintToServer("%s Solution stop delay set to %d", g_cPrintPrefixNoColor, g_iSolutionStopDelay);
    }
    else
    {
        CPrintToChat(client, "%s Solution stop delay set to %d", g_cPrintPrefix, g_iSolutionStopDelay);
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
    g_fGACheckPoints[iCP] = view_as<float>({ 0.0, 0.0, 0.0 });

    // Shift all checkpoints after iCP to new indices 
    for(int i = iCP; i < MAX_CHECKPOINTS; i++)
    {
        if(i < MAX_CHECKPOINTS - 1)
        {
            g_fGACheckPoints[i] = g_fGACheckPoints[i+1];
        }
    }

    // Reset last checkpoint
    // Will be a duplicate if all checkpoints are bAssigned before removing one
    g_fGACheckPoints[MAX_CHECKPOINTS - 1] = view_as<float>({ 0.0, 0.0, 0.0 });

    CPrintToChat(client, "%s Checkpoint %d removed!", g_cPrintPrefix, iCP);

    // Update debug lines
    if(g_bDraw)
    {
        HideLines();
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
        DrawLines(g_fGACheckPoints, MAX_CHECKPOINTS, g_fGAStartPos, g_fGAEndPos);
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
    g_iLastImproveGen = 0;

    for(int i = 0; i < POPULATION_SIZE; i++)
    {
        g_fGAIndividualFitness[i] = 0.0;
        g_bGAIndividualMeasured[i] = false;
    }

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
#if !MODE_RJ
    // Prevent bot from taking damage
    SetEntProp(g_iBot, Prop_Data, "m_takedamage", 0, 0);
#endif

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
        g_iLoopBeginTime = GetTime();
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
        g_bGAPlayback = true;
        MeasureFitness(index);
        CPrintToChat(client, "%s Playing %d-%d", g_cPrintPrefix, g_iCurrentGen, index);
    }        
    else
    {
        CPrintToChat(client, "%s Couldn't parse number", g_cPrintPrefix);        
    }
    
    return Plugin_Handled;
}