#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <files>
#include <console>

public Plugin myinfo =
{
    name = "GA-input",
    author = "Larry",
    description = "",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/pancakelarry"
};

bool recording = false, playback = false, simulating = false;

float startPos[3], startAngle[3], prevAngle[3];

File file;

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
}

float GAStartPos[3] = {-1338.432861, -547.227173, -2875.968750};
float GAStartAng[3] = {0.000000, 90.000000, 0.000000};
float GAEndPos[3] = {-1344.424927, 35.828671, -2619.968750};
//float GAEndAng[3] = {0.000000, 90.000000, 0.000000};

int populationSize = 12;
int simTicks = 400;
int simClient = 1;
int simIndex = 0;
int simTick = 0;
int targetGen = 0;
int curGen = 0;

int GAIndividualInputsInt[400][12][8];
float GAIndividualInputsFloat[400][12][2];
float GAIndividualFitness[12];
bool GAIndividualMeasured[12];
bool population = false;
bool GAplayback = false;

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
    simClient = client;
    MeasureFitness(0);
}
public Action CmdBreed(int client, int args)
{
    Breed();
}
public Action CmdLoop(int client, int args)
{
    simClient = client;
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
            for(int i=0; i<8; i++)
            {
                GAIndividualInputsInt[t][p][i] = GetRandomInt(0, 1);
            }
            GAIndividualInputsFloat[t][p][0] = GetRandomFloat(-10, 10);
            GAIndividualInputsFloat[t][p][1] = GetRandomFloat(-10, 10);
        }
    }
    PrintToServer("Population generated!");
    population = true;
    curGen = 0;
    //PrintToServer("First input of each individual:");
    for(int i=0;i<populationSize; i++)
    {
        GAIndividualMeasured[i] = false;
        /*PrintToServer("%d, %d, %d, %d, %d, %d, %d, %d, %f, %f",
            GAIndividualInputsInt[0][i][0],
            GAIndividualInputsInt[0][i][1],
            GAIndividualInputsInt[0][i][2],
            GAIndividualInputsInt[0][i][3],
            GAIndividualInputsInt[0][i][4],
            GAIndividualInputsInt[0][i][5],
            GAIndividualInputsInt[0][i][6],
            GAIndividualInputsInt[0][i][7],
            GAIndividualInputsFloat[0][i][0],
            GAIndividualInputsFloat[0][i][1]);*/
    }
    MeasureFitness(0);
}

public void CalculateFitness(int individual)
{
    float playerPos[3];
    GetEntPropVector(simClient, Prop_Data, "m_vecAbsOrigin", playerPos);
    //float cP[3];
    //ClosestPoint(GAStartPos, GAEndPos, playerPos, cP);
    GAIndividualFitness[individual] =  GetVectorDistance(playerPos, GAEndPos);
    PrintToServer("Fitness of %d-%d: %f", curGen, individual, GAIndividualFitness[individual]);
    if(GAIndividualFitness[individual] < 50)
    {
    	simulating = false;
    	file = OpenFile("runs/GA", "w+");
    	for(int i=0; i<simTicks; i++)
    	{
    		file.WriteLine("%d,%d,%d,%d,%d,%d,%d,%d,%f,%f", 
    			GAIndividualInputsInt[i][individual][0],
    			GAIndividualInputsInt[i][individual][1],
    			GAIndividualInputsInt[i][individual][2],
    			GAIndividualInputsInt[i][individual][3],
    			GAIndividualInputsInt[i][individual][4],
    			GAIndividualInputsInt[i][individual][5],
    			GAIndividualInputsInt[i][individual][6],
    			GAIndividualInputsInt[i][individual][7],
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
    
    TeleportEntity(simClient, GAStartPos, GAStartAng, {0.000000, 0.000000, 0.000000});
    CreateTimer(1.5, MeasureTimer, index);
}

public Action MeasureTimer(Handle timer, int index)
{
    prevAngle = GAStartAng;
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
            for(int e=0; e<simTicks; e++)
            {            
                // Get parts from both parents randomly
                for(int a=0; a<8; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    GAIndividualInputsInt[e][i][a] = GAIndividualInputsInt[e][parents[p][cross]][a];
                    // random mutations
                    if(GetRandomInt(0, 100) > 95)
                    {
                        GAIndividualInputsInt[e][i][a] = GAIndividualInputsInt[e][i][a] == 1 ? 0 : 1;
                    }
                }
                for(int a=0; a<2; a++)
                {
                    int cross = GetRandomInt(0, 1);
                    GAIndividualInputsFloat[e][i][a] = GAIndividualInputsFloat[e][parents[p][cross]][a];
                    // random mutations
                    if(GetRandomInt(0, 100) > 80)
                    {
                        GAIndividualInputsFloat[e][i][a] += GetRandomFloat(-10, 10);
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
    prevAngle[0] = startAngle[0];
    prevAngle[1] = startAngle[1];
    
    file = OpenFile(path, "w+");
    if(file == INVALID_HANDLE)
    {
        PrintToChat(client, "Something went wrong :(");
        PrintToServer("Invalid file handle");
        return;
    }
    file.WriteLine("%f,%f,%f,%f,%f", startPos[0],startPos[1],startPos[2], startAngle[0], startAngle[1]);
    
    recording = true;
    playback = false;
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
            TeleportEntity(client, startPos, startAngle, {0.000000, 0.000000, 0.000000});
            prevAngle[0] = startAngle[0];
            prevAngle[1] = startAngle[1];
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
        if(client == simClient)
        {
            if(simTick == simTicks)
            {
                simulating = false;
                GAIndividualMeasured[simIndex] = true;
                CalculateFitness(simIndex);
                if(GAplayback)
                {
                	GAplayback = false;
                	simulating = false;
                	PrintToChat(simClient, "Simulation ended");
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
                        Breed();
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
            buttons = 0;
            
            if(GAIndividualInputsInt[simTick][simIndex][0] == 1)
                buttons |= IN_ATTACK;
            
            if(GAIndividualInputsInt[simTick][simIndex][1] == 1)
                buttons |= IN_ATTACK2;
            
            if(GAIndividualInputsInt[simTick][simIndex][2] == 1)
                buttons |= IN_JUMP;
            
            if(GAIndividualInputsInt[simTick][simIndex][3] == 1)
                buttons |= IN_DUCK;
    
            if(GAIndividualInputsInt[simTick][simIndex][4] == 1)
                buttons |= IN_FORWARD;
            
            if(GAIndividualInputsInt[simTick][simIndex][5] == 1)
                buttons |= IN_BACK;
            
            if(GAIndividualInputsInt[simTick][simIndex][6] == 1)
                buttons |= IN_MOVELEFT;
            
            if(GAIndividualInputsInt[simTick][simIndex][7] == 1)
                buttons |= IN_MOVERIGHT;
            
            buttons |= IN_RELOAD; // Autoreload
                
            if (buttons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK)
                vel[0] = 0.0;
            else if (buttons & IN_FORWARD)
                vel[0] = 280.0;
            else if (buttons & IN_BACK)
                vel[0] = -280.0;
            
            if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                vel[1] = 0.0;
            else if (buttons & IN_MOVELEFT)
                vel[1] = -280.0;
            else if (buttons & IN_MOVERIGHT)
                vel[1] = 280.0;
                
            prevAngle[0] += GAIndividualInputsInt[simTick][simIndex][0];
            prevAngle[1] += GAIndividualInputsInt[simTick][simIndex][1];
            if(prevAngle[0] > 89.000000)
                prevAngle[0] = 89.000000;
            else if(prevAngle[0] < -89.000000)
                prevAngle[0] = -89.000000;
            if(prevAngle[1] > 180.000000)
                prevAngle[1] -= 360.000000;
            else if(prevAngle[1] < -180.000000)
                prevAngle[1] += 360.000000;
            TeleportEntity(client, NULL_VECTOR, prevAngle, NULL_VECTOR);
            
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
        float dAng[2];
        dAng[0] = angles[0] - prevAngle[0];
        dAng[1] = angles[1] - prevAngle[1];
        
        if(dAng[1] > 180)
            dAng[1] -= 360;
        else if(dAng[1] < -180)
            dAng[1] += 360;
        
        file.WriteLine("%d,%d,%d,%d,%d,%d,%d,%d,%f,%f",
                buttons & IN_ATTACK ? 1 : 0,
                buttons & IN_ATTACK2 ? 1 : 0,
                buttons & IN_JUMP ? 1 : 0,
                buttons & IN_DUCK ? 1 : 0,
                buttons & IN_FORWARD ? 1 : 0,
                buttons & IN_BACK ? 1 : 0,
                buttons & IN_MOVELEFT ? 1 : 0,
                buttons & IN_MOVERIGHT ? 1 : 0,
                dAng[0],
                dAng[1]);
        
        for(int i = 0; i < 2; i++)
        {
            prevAngle[i] = angles[i];
        }
    }
    else if(playback)
    {
        if(file.EndOfFile())
        {
            StopPlayback();
            return Plugin_Continue;
        }
        
        buttons = 0;
        
        char buffer[128];
        if(file.ReadLine(buffer, sizeof(buffer)))
        {
            char bu[10][8];
            
            int n = ExplodeString(buffer, ",", bu, 10, 8);
            if(n == 10)
            {
                int butt[8];
                for(int i=0; i<8; i++)
                {
                    butt[i] = StringToInt(bu[i]);
                }
                
                if(butt[0] == 1)
                    buttons |= IN_ATTACK;
                else
                    buttons &= ~IN_ATTACK;
                
                if(butt[1] == 1)
                    buttons |= IN_ATTACK2;
                else
                    buttons &= ~IN_ATTACK2;
                
                if(butt[2] == 1)
                    buttons |= IN_JUMP;
                else
                    buttons &= ~IN_JUMP;
                
                if(butt[3] == 1)
                    buttons |= IN_DUCK;
                else
                    buttons &= ~IN_DUCK;
                
                if(butt[4] == 1)
                    buttons |= IN_FORWARD;
                else
                    buttons &= ~IN_FORWARD;
                
                if(butt[5] == 1)
                    buttons |= IN_BACK;
                else
                    buttons &= ~IN_BACK;
                
                if(butt[6] == 1)
                    buttons |= IN_MOVELEFT;
                else
                    buttons &= ~IN_MOVELEFT;
                
                if(butt[7] == 1)
                    buttons |= IN_MOVERIGHT;
                else
                    buttons &= ~IN_MOVERIGHT;
                        
                buttons |= IN_RELOAD; // Autoreload
            
                if (buttons & (IN_FORWARD|IN_BACK) == IN_FORWARD|IN_BACK)
                    vel[0] = 0.0;
                else if (buttons & IN_FORWARD)
                    vel[0] = 280.0;
                else if (buttons & IN_BACK)
                    vel[0] = -280.0;
                
                if (buttons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT) 
                    vel[1] = 0.0;
                else if (buttons & IN_MOVELEFT)
                    vel[1] = -280.0;
                else if (buttons & IN_MOVERIGHT)
                    vel[1] = 280.0;
                
                prevAngle[0] += StringToFloat(bu[sizeof(bu)-2]);
                prevAngle[1] += StringToFloat(bu[sizeof(bu)-1]);
                if(prevAngle[0] > 89.000000)
                    prevAngle[0] = 89.000000;
                else if(prevAngle[0] < -89.000000)
                    prevAngle[0] = -89.000000;
                if(prevAngle[1] > 180.000000)
                    prevAngle[1] -= 360.000000;
                else if(prevAngle[1] < -180.000000)
                    prevAngle[1] += 360.000000;
                TeleportEntity(client, NULL_VECTOR, prevAngle, NULL_VECTOR);

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