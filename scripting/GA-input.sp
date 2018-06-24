#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <files>
#include <console>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_EXTENSIONS
#include <botcontroller>

public Plugin myinfo =
{
    name = "GA-input",
    author = "Larry",
    description = "",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/pancakelarry"
};

bool recording = false, playback = false, simulating = false;
bool g_bBCExtension;
int g_iBot = -1;
int g_iBotTeam = 2;
char g_hBotName[] = "GA-BOT";
float startPos[3], startAngle[3];

File file;

public Action Timer_SetupBot(Handle hTimer)
{
    if (g_iBot != -1) {
        return;
    }
    if (g_bBCExtension) {
        g_iBot = BotController_CreateBot(g_hBotName);
        
        if (!IsClientInGame(g_iBot)) {
            SetFailState("%t", "Cannot Create Bot");
        }
		ChangeClientTeam(g_iBot, g_iBotTeam);
		TF2_SetPlayerClass(g_iBot, TFClass_Soldier);
		ServerCommand("mp_waitingforplayers_cancel 1;");
    } 
    else 
    {
        SetFailState("%t", "No bot controller extension");
    }
}

public void OnPluginEnd() {	
	if (g_iBot != -1) {
		KickClient(g_iBot, "%s", "Kicked GA-BOT");
	}
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

public void OnPluginStart()
{
    RegConsoleCmd("sm_record", CmdRecord, "");
    RegConsoleCmd("sm_stoprecord", CmdStopRecord, "");
    
    RegConsoleCmd("sm_playback", CmdPlayback, "");
    RegConsoleCmd("sm_stopplayback", CmdStopPlayback, "");
    
    RegConsoleCmd("sm_gen", CmdGen, "");
    RegConsoleCmd("sm_sim", CmdSim, "");
    RegConsoleCmd("sm_breed", CmdBreed, "");
    RegConsoleCmd("sm_loop", CmdLoop, "");
    RegConsoleCmd("sm_clear", CmdClear, "");
    RegConsoleCmd("sm_gaplay", CmdPlay, "");
    CreateTimer(1.0, Timer_SetupBot);
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0");
}

float GAStartPos[3] = {-1338.432861, -547.227173, -2875.968750};
float GAStartAng[3] = {0.000000, 90.000000, 0.000000};
float GAEndPos[3] = {-1344.424927, 35.828671, -2619.968750};
//float GAEndAng[3] = {0.000000, 90.000000, 0.000000};

int populationSize = 12;
int simTicks = 400;
int simIndex = 0;
int simTick = 0;
int targetGen = 0;
int curGen = 0;

int GAIndividualInputsInt[400][12];
float GAIndividualInputsFloat[400][12][2];
float GAIndividualFitness[12];
bool GAIndividualMeasured[12];
bool population = false;
bool GAplayback = false;
int PossibleButtons[8] = {IN_ATTACK, IN_ATTACK2, IN_JUMP, IN_DUCK, IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT};

public Action CmdClear(int client, int args)
{
    population = false;
    targetGen = 0;
    curGen = 0;
}
public Action CmdGen(int client, int args)
{
    GeneratePopulation();
}
public Action CmdSim(int client, int args)
{
    MeasureFitness(0);
}
public Action CmdBreed(int client, int args)
{
    Breed();
}
public Action CmdLoop(int client, int args)
{
    ServerCommand("host_timescale 10");
    SetEntProp(g_iBot, Prop_Data, "m_takedamage", 1, 1); // Buddha
    if(args < 1)
    {
        PrintToChat(client, "Missing number of generations argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int gen = 0;
    if(StringToIntEx(arg, gen))
    {
        targetGen += gen;
        if(!population)
        {
            GeneratePopulation();
            return;
        }          
        
        if(targetGen > curGen)
            Breed();
    }        
    else
        PrintToChat(client, "Couldn't parse number");
}
public Action CmdPlay(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing number argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int index = 0;
    if(StringToIntEx(arg, index))
    {
        simIndex = index;
        GAplayback = true;
        MeasureFitness(index);
        PrintToChat(client, "Simulating %d-%d", curGen, index);
    }        
    else
        PrintToChat(client, "Couldn't parse number");
}

public void GeneratePopulation()
{
    for(int t=0; t<simTicks; t++)
    {
        for(int p=0; p < populationSize; p++)
        {
            for(int i=0; i<sizeof(PossibleButtons); i++)
            {
                // random key inputs
                if(GetRandomInt(0, 100) > 90)
                {
                    if(GAIndividualInputsInt[t][p] & PossibleButtons[i])
                        GAIndividualInputsInt[t][p] &= ~PossibleButtons[i];
                    else
                        GAIndividualInputsInt[t][p] |= PossibleButtons[i];
                }
                    
                // chance for inputs to be duplicated from previous tick
                if(t != 0)
                {
                    if(GAIndividualInputsInt[t-1][p] & PossibleButtons[i])
                    {
                        if(GetRandomInt(0, 100) > 20)
                        {
                            GAIndividualInputsInt[t][p] |= PossibleButtons[i];
                        }                            
                    }
                }
            }
            GAIndividualInputsFloat[t][p][0] = GAStartAng[0];
            GAIndividualInputsFloat[t][p][1] = GAStartAng[1];
            // random mouse movement
            if(GetRandomInt(0,100) > 95)
            {
                GAIndividualInputsFloat[t][p][0] = GetRandomFloat(-89.0, 89.0);
                GAIndividualInputsFloat[t][p][1] = GetRandomFloat(-180.0, 180.0);
            }
            
            // chance for inputs to be duplicated from previous tick
            /*if(t != 0)
            {
                for(int a=0; a<2; a++)
                {
                    if(GAIndividualInputsFloat[t-1][p][a] > 0 || GAIndividualInputsFloat[t-1][p][a] < 0)
                    {
                        if(GetRandomInt(0, 100) > 20)
                        {
                            GAIndividualInputsFloat[t][p][a] = GAIndividualInputsFloat[t-1][p][a];
                        }                        
                    }
                }
            }*/
        }
    }
    PrintToServer("Population generated!");
    population = true;
    curGen = 0;
    for(int i=0;i<populationSize; i++)
    {
        GAIndividualMeasured[i] = false;
    }
    MeasureFitness(0);
}

public void CalculateFitness(int individual)
{
    float playerPos[3];
    GetEntPropVector(g_iBot, Prop_Data, "m_vecAbsOrigin", playerPos);
    // FIXME: closest point on line not working
    //float cP[3];
    //ClosestPoint(GAStartPos, GAEndPos, playerPos, cP);
    GAIndividualFitness[individual] =  GetVectorDistance(playerPos, GAEndPos);
    PrintToServer("Fitness of %d-%d: %f", curGen, individual, GAIndividualFitness[individual]);
    
    // save individual to file and stop generation if fitness low enough
    if(GAIndividualFitness[individual] < 50)
    {
        simulating = false;
        file = OpenFile("runs/GA", "w+");
        for(int i=0; i<simTicks; i++)
        {
            file.WriteLine("%d,%f,%f", 
                GAIndividualInputsInt[i][individual],
                GAIndividualInputsFloat[i][individual][0],
                GAIndividualInputsFloat[i][individual][1]);
        }
        file.Close();
    }        
}

public void MeasureFitness(int index)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "tf_projectile_pipe_remote")) != -1)
    {
        AcceptEntityInput(ent, "Kill");
    }
    while ((ent = FindEntityByClassname(ent, "tf_projectile_rocket")) != -1)
    {
        AcceptEntityInput(ent, "Kill");
    }
    
    TeleportEntity(g_iBot, GAStartPos, GAStartAng, {0.0, 0.0, 0.0});
    CreateTimer(1.5, MeasureTimer, index);
}

public Action MeasureTimer(Handle timer, int index)
{
    simIndex = index;
    simTick = 0;
    simulating = true;
}

public void ClosestPoint(float A[3], float B[3], float P[3], float ref[3])
{
    float d[3];
    MakeVectorFromPoints(A, B, d);
    NormalizeVector(d, d);
    
    float w[3];
    MakeVectorFromPoints(A, P, w);
    ScaleVector(d, GetVectorDotProduct(w, d));
    ref = d;
}

public void Breed()
{
    int fittest[6];
    float order[12];
    for(int i=0; i<populationSize;i++)
        order[i] = GAIndividualFitness[i];

    SortFloats(order, populationSize, Sort_Ascending);
    for(int i=0; i<populationSize/2; i++)
    {
        for(int e=0; e<populationSize; e++)
        {
            if(order[i] == GAIndividualFitness[e])
                fittest[i] = e;
        }
    }
    
    // pair fittest randomly
    int parents[3][2];
    bool taken[6];
    int par = 0;
    for(int i=0; i<populationSize/2; i++)
    {
        if(!taken[i])
        {
            int rand = GetRandomInt(0, (populationSize/2) - 1);
            while(taken[rand] || rand == i)
                rand = GetRandomInt(0, (populationSize/2) - 1);
            
            parents[par][0] = i;
            parents[par][1] = rand;
            taken[i] = true;
            taken[rand] = true;
            par++;
        }
    }
    for(int p=0; p<populationSize/4; p++)
    {
        for(int i=0; i<populationSize; i++)
        {
            bool cont = false;
            for(int e=0; e<populationSize/2; e++)
            {
                if(fittest[e] == i)
                    cont = true;
            }
            if(cont)
                continue;
            
            // overwrite least fittest with children
            for(int t=0; t<simTicks; t++)
            {            
                // Get parts from both parents randomly
                for(int a=0; a<8; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    if(GAIndividualInputsInt[t][parents[p][cross]] & PossibleButtons[a])
                        GAIndividualInputsInt[t][i] |= PossibleButtons[a];
                    else
                        GAIndividualInputsInt[t][i] &= ~PossibleButtons[a];
                    // random mutations
                    if(GetRandomInt(0, 100) > 80)
                    {
                        if(GAIndividualInputsInt[t][i] & PossibleButtons[a])
                            GAIndividualInputsInt[t][i] |= PossibleButtons[a];
                        else
                            GAIndividualInputsInt[t][i] &= ~PossibleButtons[a];
                    }
                    // chance for inputs to be duplicated from previous tick
                    if(t != 0)
                    {
                        if(GetRandomInt(0, 100) > 50)
                        {
                            if(GAIndividualInputsInt[t-1][i] & PossibleButtons[a])
                                GAIndividualInputsInt[t][i] |= PossibleButtons[a];
                            else
                                GAIndividualInputsInt[t][i] &= ~PossibleButtons[a];
                        }
                    }
                }
                for(int a=0; a<2; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    GAIndividualInputsFloat[t][i][a] = GAIndividualInputsFloat[t][parents[p][cross]][a];
                }
                // random mutations
                if(GetRandomInt(0, 100) > 80)
                {
                    GAIndividualInputsFloat[t][i][0] = GetRandomFloat(-89.0, 89.0);
                }
                if(GetRandomInt(0, 100) > 80)
                {
                    GAIndividualInputsFloat[t][i][1] = GetRandomFloat(-180.0, 180.0);
                }
                for(int a=0; a<2; a++)
                {
                    // chance for inputs to be duplicated from previous tick
                    if(t != 0)
                    {
                        if(GetRandomInt(0, 100) > 20)
                            GAIndividualInputsFloat[t][i][a] = GAIndividualInputsFloat[t-1][i][a];
                    }
                }

            }
            GAIndividualMeasured[i] = false;
        }
    }
    curGen++;
    PrintToServer("Generation %d breeded!", curGen);    
    MeasureFitness(0);      
}

public Action CmdRecord(int client, int args)
{
    if(recording)
    {
        PrintToChat(client, "Already recording!");
        return;
    }
    if(args < 1)
    {
        PrintToChat(client, "Missing name argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/runs/";
    StrCat(path, sizeof(path), arg);
    
    int e=0;
    while(FileExists(path))
    {
        e++;
        path = "/runs/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(e, num, sizeof(num));
        StrCat(path, sizeof(path), num);
    }
    
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", startPos);
    GetClientEyeAngles(client, startAngle);
    
    file = OpenFile(path, "w+");
    if(file == INVALID_HANDLE)
    {
        PrintToChat(client, "Something went wrong :(");
        PrintToServer("Invalid file handle");
        return;
    }
    file.WriteLine("%f,%f,%f,%f,%f", startPos[0], startPos[1], startPos[2], startAngle[0], startAngle[1]);
    
    recording = true;
    playback = false;
    simulating = false;
    PrintToChat(client, "Recording started!");
}

public Action CmdStopRecord(int client, int args)
{
    if(!recording)
    {
        PrintToChat(client, "Not recording!");
        return;
    }
    if(file != INVALID_HANDLE)
        file.Close();
    recording = false;
    playback = false;
    simulating = false;
    PrintToChat(client, "Recording stopped!");
}

public Action CmdPlayback(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing name argument");
        return;
    }
    
    char arg[64], target[64] = "runs/";
    GetCmdArg(1, arg, sizeof(arg));
    StrCat(target, sizeof(target), arg);
    
    if(FileExists(target))
    {
        file = OpenFile(target, "r");
    }
    else
    {
        PrintToChat(client, "Can't find file %s.", arg);
        return;
    }
    if(file == INVALID_HANDLE)
    {
        PrintToChat(client, "Something went wrong :(");
        PrintToServer("Invalid file handle");
        return;
    }
    file.Seek(0, SEEK_SET);
    
    char buffer[128];
    if(file.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[5][16];
        int n = ExplodeString(buffer, ",", bu, 5, 16);
        
        if(n == 5)
        {
            for(int i=0; i<n; i++)
            {
                if(strlen(bu[i]) < 1)
                {
                    PrintToChat(client, "Starting position not found! Playback cancelled.");
                    playback = false;
                    file.Close();
                    return;
                }
                if(i < 3)
                    startPos[i] = StringToFloat(bu[i]);
                else
                    startAngle[i-3] = StringToFloat(bu[i]);
            }
            TeleportEntity(client, startPos, startAngle, {0.0, 0.0, 0.0});
        }
        else
        {
            PrintToChat(client, "Starting position not found! Playback cancelled.");
            playback = false;
            file.Close();
            return;
        }
    }

    recording = false;
    playback = true;
    simulating = false;
    PrintToChat(client, "Playback started!");
}

public Action CmdStopPlayback(int client, int args)
{
    if(!playback)
    {
        PrintToChat(client, "No playback active!");
        return;
    }
    StopPlayback();
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if(simulating)
    {
        if(client == g_iBot)
        {
            if(simTick == simTicks)
            {
                simulating = false;
                // uncomment to prevent parents of new generations from being measured again (faster)
                // disabled because runs don't seem deterministic (good fitness might just be a fluke)
                GAIndividualMeasured[simIndex] = true;
                CalculateFitness(simIndex);
                if(GAplayback)
                {
                    GAplayback = false;
                    simulating = false;
                    PrintToChatAll("Simulation ended");
                    return Plugin_Continue;
                }
                simIndex++;
    
                if(simIndex < populationSize)
                {
                    MeasureFitness(simIndex);
                }
                else
                {
                    if(targetGen > curGen)
                    {
                    	Breed();
                    }                        
                    else
                    {
                    	PrintToServer("Finished loop");
                    	ServerCommand("host_timescale 10");
                    }
                }
                
                return Plugin_Continue;
            }
            if(GAIndividualMeasured[simIndex] && !GAplayback)
            {
                PrintToServer("Fitness of %d-%d: %f (parent)", curGen, simIndex, GAIndividualFitness[simIndex]);
                simIndex++;
    
                if(simIndex == populationSize)
                {
                    simulating = false;
                    if(targetGen > curGen)
                        Breed();                 
                }
                
                return Plugin_Continue;
            }
            float fAng[3];
            fAng[0] = GAIndividualInputsFloat[simTick][simIndex][0];
            fAng[1] = GAIndividualInputsFloat[simTick][simIndex][1];
            TeleportEntity(client, NULL_VECTOR, fAng, NULL_VECTOR);
            
            buttons = GAIndividualInputsInt[simTick][simIndex];
            
            buttons |= IN_RELOAD; // Autoreload
                
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
            
            simTick++;
            
            return Plugin_Changed;
        }
        
    }
    if(file == INVALID_HANDLE)
    {
        return Plugin_Continue;
    }
    if(recording)
    {
        if(client != g_iBot)
            return Plugin_Continue;
            
        file.WriteLine("%d,%f,%f", buttons, angles[0], angles[1]);
    }
    else if(playback)
    {
        if(client != g_iBot)
            return Plugin_Continue;
            
        if(file.EndOfFile())
        {
            StopPlayback();
            return Plugin_Continue;
        }
        
        char buffer[128];
        if(file.ReadLine(buffer, sizeof(buffer)))
        {
            char butt[3][8];
            
            int n = ExplodeString(buffer, ",", butt, 3, 8);
            if(n == 3)
            {
                float fAng[3];
                fAng[0] = StringToFloat(butt[1]);
                fAng[1] = StringToFloat(butt[2]);

                TeleportEntity(client, NULL_VECTOR, fAng, NULL_VECTOR);
                
                buttons = StringToInt(butt[0]);
                        
                buttons |= IN_RELOAD; // Autoreload
                
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

                return Plugin_Changed;
            }
            else
            {
                PrintToServer("Bad input format");
                StopPlayback();
                return Plugin_Continue;
            }
        }
    }
    return Plugin_Continue;
}

public void StopPlayback()
{
    playback = false;
    if(file != INVALID_HANDLE)
        file.Close();
    PrintToChatAll("Playback stopped!");
}