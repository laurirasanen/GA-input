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

#define MAXCHECKPOINTS 100
// about 10 mins
#define MAXFRAMES 40000

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
int g_iTimeScale = 10;

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
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0");
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
    RegConsoleCmd("sm_stoploop", CmdStopLoop, "");
    RegConsoleCmd("sm_clear", CmdClear, "");
    RegConsoleCmd("sm_gaplay", CmdPlay, "");
    RegConsoleCmd("sm_gastart", CmdStart, "");
    RegConsoleCmd("sm_gaend", CmdEnd, "");
    RegConsoleCmd("sm_gaaddcp", CmdAddCheckpoint, "");
    RegConsoleCmd("sm_garemovecp", CmdRemoveCheckpoint, "");
    RegConsoleCmd("sm_gadrawdebug", CmdDrawDebug, "");
    RegConsoleCmd("sm_gatimescale", CmdSetTimeScale, "");
    RegConsoleCmd("sm_gaframes", CmdSetFrames, "");
    RegConsoleCmd("sm_gasave", CmdSave, "");
    RegConsoleCmd("sm_gaload", CmdLoad, "");
    CreateTimer(1.0, Timer_SetupBot);
    ServerCommand("sv_cheats 1; tf_allow_server_hibernation 0");
}

float GAStartPos[3] = {-1338.432861, -547.227173, -2875.968750};
float GAStartAng[3] = {0.000000, 90.000000, 0.000000};
float GAEndPos[3] = {-1344.424927, 35.828671, -2619.968750};
// why doesn't this work..
//float GACheckPoints[MAXCHECKPOINTS][3] = { { -1.0, ... }, ... };
float GACheckPoints[MAXCHECKPOINTS][3];

int populationSize = 12,
    simFrames,
    simIndex,
    simCurrentFrame,
    targetGen,
    curGen;

int GAIndividualInputsInt[MAXFRAMES][12];
float GAIndividualInputsFloat[MAXFRAMES][12][2];
float GAIndividualFitness[12];
bool GAIndividualMeasured[12];
bool population = false;
bool GAplayback = false;
int PossibleButtons[8] = {IN_ATTACK, IN_ATTACK2, IN_JUMP, IN_DUCK, IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT};
bool g_linesVisible;
public void DrawLines() {
    for(new i = 0; i < MAXCHECKPOINTS;i++) {
        if(GACheckPoints[i][0] != 0 && GACheckPoints[i][1] != 0 && GACheckPoints[i][2] != 0)
        {
            if(i == 0)
            {
                DrawLaser(GAStartPos, GACheckPoints[i], 0, 255, 0);
            } 
            if(i+1<MAXCHECKPOINTS)
            {
                if(GACheckPoints[i+1][0] != 0 && GACheckPoints[i+1][1] != 0 && GACheckPoints[i+1][2] != 0)
                {
                    DrawLaser(GACheckPoints[i], GACheckPoints[i+1], 0, 255, 0);
                }
                else
                {
                    DrawLaser(GACheckPoints[i], GAEndPos, 0, 255, 0);
                }
            }
        }
        else
        {
            // no cps
            if(i == 0)
            {
                DrawLaser(GAStartPos, GAEndPos, 0, 255, 0);
            }
        }
    }
}
//https://forums.alliedmods.net/showthread.php?t=190685
public int DrawLaser(Float:start[3], Float:end[3],red,green,blue)
{
    new ent = CreateEntityByName("env_beam");
    if (ent != -1) {
        TeleportEntity(ent, start, NULL_VECTOR, NULL_VECTOR);
        SetEntityModel(ent, "sprites/laser.vmt");
        SetEntPropVector(ent, Prop_Data, "m_vecEndPos", end);
        DispatchKeyValue(ent, "targetname", "beam");
        new String:buffer[32];
        Format(buffer,sizeof(buffer),"%d %d %d",red,green,blue);
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
    for(new i = MaxClients+1;i <= GetMaxEntities() ;i++){
        if(!IsValidEntity(i))
            continue;
    
        if(GetEdictClassname(i,name,sizeof(name))){
             if(StrEqual("env_beam",name,false))
                RemoveEdict(i);
        }
    }
}
public Action CmdDrawDebug(int client, int args)
{
    g_linesVisible = !g_linesVisible;
    if(g_linesVisible)
    {
        DrawLines();
        PrintToChatAll("Drawing debug crap");
    }
    else
       {
           HideLines();
           PrintToChatAll("Hiding debug crap");
       }
}
public Action CmdSave(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing name argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    char path[64] = "/GA/";
    StrCat(path, sizeof(path), arg);
    
    int e=0;
    while(FileExists(path))
    {
        e++;
        path = "/GA/";
        StrCat(path, sizeof(path), arg);
        char num[8];
        IntToString(e, num, sizeof(num));
        StrCat(path, sizeof(path), num);
    }
    
    file = OpenFile(path, "w+");
    if(file == INVALID_HANDLE)
    {
        PrintToChat(client, "Something went wrong :(");
        PrintToServer("Invalid file handle");
        return;
    }
    file.WriteLine("%d", simFrames);
    file.WriteLine("%f,%f,%f,%f,%f,%f,%f,%f,%f", GAStartPos[0], GAStartPos[1], GAStartPos[2], GAStartAng[0], GAStartAng[1], GAStartAng[2], GAEndPos[0], GAEndPos[1], GAEndPos[2]);
    for(int i = 0; i<MAXCHECKPOINTS; i++)
    {
        if(GACheckPoints[i][0] != 0 && GACheckPoints[i][1] != 0 && GACheckPoints[i][2] != 0)
            file.WriteLine("%f,%f,%f", GACheckPoints[i][0], GACheckPoints[i][1], GACheckPoints[i][2]);
    }
    file.Close();    
    PrintToChat(client, "Saved config to %s", path);
}
public Action CmdLoad(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing name argument");
        return;
    }
    
    char arg[64], target[64] = "/GA/";
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
        int num;
        if(StringToIntEx(buffer, num))
        {
            simFrames = num;
        }
        else
        {
            PrintToChat(client, "Bad save format");
            playback = false;
            file.Close();
            return;
        }
    }
    if(file.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[9][16];
        int n = ExplodeString(buffer, ",", bu, 9, 16);
        
        if(n == 9)
        {
            for(int i = 0; i<3; i++)
            {
                GAStartPos[i] = StringToFloat(bu[i]);
            }
            for(int i = 0; i<3; i++)
            {
                GAStartAng[i] = StringToFloat(bu[i+3]);
            }
            for(int i = 0; i<3; i++)
            {
                GAEndPos[i] = StringToFloat(bu[i+6]);
            }
        }
        else
        {
            PrintToChat(client, "Bad save format");
            playback = false;
            file.Close();
            return;
        }
    }
    for(int i=0; i<MAXCHECKPOINTS; i++)
    {
        GACheckPoints[i] = { 0.0, 0.0, 0.0 };
    }
    int cp;
    while(file.ReadLine(buffer, sizeof(buffer)))
    {
        char bu[3][16];
        int n = ExplodeString(buffer, ",", bu, 3, 16);
        
        if(n == 3)
        {
            for(int i=0; i<3; i++)
            {
                GACheckPoints[cp][i] = StringToFloat(bu[i]);
            }            
        }
        else
        {
            PrintToChat(client, "Bad save format");
            playback = false;
            file.Close();
            return;
        }
        cp++;
    }
    file.Close(); 
    PrintToChat(client, "Loaded config from %s", target);
    if(g_linesVisible)
    {
        HideLines();
        DrawLines();
    }
}
public Action CmdSetTimeScale(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing number argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int num;
    if(!StringToIntEx(arg, num))
    {
        PrintToChat(client, "Failed to parse number");
        return;
    }
    g_iTimeScale = num;
    PrintToChat(client, "Loop timescale set to %d", num);
}
public Action CmdSetFrames(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing number argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int num;
    if(!StringToIntEx(arg, num))
    {
        PrintToChat(client, "Failed to parse number");
        return;
    }
    if(num > MAXFRAMES)
    {
    	PrintToChat(client, "Max frames limit is %d!", MAXFRAMES);
    	num = MAXFRAMES;
    }
    simFrames = num;
    PrintToChat(client, "Frames set to %d", num);
}
public Action CmdRemoveCheckpoint(int client, int args)
{
    if(args < 1)
    {
        PrintToChat(client, "Missing number argument");
        return;
    }
    char arg[64];
    GetCmdArg(1, arg, sizeof(arg));
    int num;
    if(!StringToIntEx(arg, num))
    {
        PrintToChat(client, "Failed to parse number");
        return;
    }
    GACheckPoints[num] = { 0.0, 0.0, 0.0 };
    for(int i=num; i<MAXCHECKPOINTS; i++)
    {
        if(i < MAXCHECKPOINTS - 1)
            GACheckPoints[i] = GACheckPoints[i+1];
    } 
    PrintToChat(client, "Checkpoint %d removed!", num);
    if(g_linesVisible)
    {
        HideLines();
        DrawLines();
    }
}
public Action CmdAddCheckpoint(int client, int args)
{
    for(int i=0; i<MAXCHECKPOINTS; i++)
    {
        if(GACheckPoints[i][0] == 0 && GACheckPoints[i][1] == 0 && GACheckPoints[i][2] == 0)
        {
            GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", GACheckPoints[i]);
            PrintToChat(client, "Checkpoint %d set!", i);
            break;
        }
    }    
    if(g_linesVisible)
    {
        HideLines();
        DrawLines();
    }
}
public Action CmdStart(int client, int args)
{
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", GAStartPos);
    GetClientEyeAngles(client, GAStartAng);
    PrintToChat(client, "Start set");
    if(g_linesVisible)
    {
        HideLines();
        DrawLines();
    }
}
public Action CmdEnd(int client, int args)
{
    GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", GAEndPos);
    PrintToChat(client, "End set");
    if(g_linesVisible)
    {
        HideLines();
        DrawLines();
    }
}
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
public Action CmdStopLoop(int client, int args)
{
    targetGen = curGen;
}
public Action CmdLoop(int client, int args)
{
    ServerCommand("host_timescale %d", g_iTimeScale);
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
        PrintToChat(client, "Playing %d-%d", curGen, index);
    }        
    else
        PrintToChat(client, "Couldn't parse number");
}

public void GeneratePopulation()
{
    for(int t=0; t<simFrames; t++)
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
    float cP[3];
    cP = GAStartPos;
    int lastCP;
    for(new i = 0; i < MAXCHECKPOINTS;i++) {
        if(GACheckPoints[i][0] != 0 && GACheckPoints[i][1] != 0 && GACheckPoints[i][2] != 0)
        {
            float temp[3];
            if(i == 0)
            {
                ClosestPoint(GAStartPos, GACheckPoints[i], playerPos, temp);
                //PrintToServer("i: %d", i);
                //PrintToServer("GAStartPos: %f %f %f", GAStartPos[0], GAStartPos[1], GAStartPos[2]);
                //PrintToServer("GACheckPoints[i]: %f %f %f", GACheckPoints[i][0], GACheckPoints[i][1], GACheckPoints[i][2]);                
            } 
            else
            {
                if(i+1<MAXCHECKPOINTS)
                {
                    if(GACheckPoints[i+1][0] != 0 && GACheckPoints[i+1][1] != 0 && GACheckPoints[i+1][2] != 0)
                    {
                        ClosestPoint(GACheckPoints[i], GACheckPoints[i+1], playerPos, temp);
                        //PrintToServer("i: %d", i);
                        //PrintToServer("GACheckPoints[i]: %f %f %f", GACheckPoints[i][0], GACheckPoints[i][1], GACheckPoints[i][2]);
                        //PrintToServer("GACheckPoints[i+1]: %f %f %f", GACheckPoints[i+1][0], GACheckPoints[i+1][1], GACheckPoints[i+1][2]);
                    }
                    else
                    {
                        ClosestPoint(GACheckPoints[i], GAEndPos, playerPos, temp);
                        //PrintToServer("i: %d", i);
                        //PrintToServer("GACheckPoints[i]: %f %f %f", GACheckPoints[i][0], GACheckPoints[i][1], GACheckPoints[i][2]);
                        //PrintToServer("GAEndPos: %f %f %f", GAEndPos[0], GAEndPos[1], GAEndPos[2]);
                    }
                }
                 else
                {
                    ClosestPoint(GACheckPoints[i], GAEndPos, playerPos, temp);
                    //PrintToServer("i(2): %d", i);
                    //PrintToServer("GACheckPoints[i]: %f %f %f", GACheckPoints[i][0], GACheckPoints[i][1], GACheckPoints[i][2]);
                    //PrintToServer("GAEndPos: %f %f %f", GAEndPos[0], GAEndPos[1], GAEndPos[2]);
                }
            }
            if(GetVectorDistance(temp, playerPos) < GetVectorDistance(cP, playerPos))
            {
                cP = temp;
                lastCP = i;
            }
        }
        else
        {
            // no cps
            if(i == 0)
            {
                ClosestPoint(GAStartPos, GAEndPos, playerPos, cP);
                lastCP = i;
            }
        }
    }
    PrintToServer("lastCP: %d", lastCP);
    float dist;
    for(int i=0; i<lastCP; i++)
    {
        if(i == 0)
        {
            dist += GetVectorDistance(GAStartPos, GACheckPoints[i]);
        }
        else
            dist += GetVectorDistance(GACheckPoints[i-1], GACheckPoints[i]);
    }
    if(lastCP == 0)
        dist += GetVectorDistance(GAStartPos, cP);
    else
        dist += GetVectorDistance(GACheckPoints[lastCP], cP);
    // hasn't made it past start point, set distance to start as negative fitness
    if(dist <= 0)
        dist -= GetVectorDistance(GAStartPos, playerPos);
    GAIndividualFitness[individual] = dist;
    PrintToServer("Fitness of %d-%d: %f", curGen, individual, GAIndividualFitness[individual]);
    int ent = DrawLaser(playerPos, cP, 255, 0, 0);
    CreateTimer(5.0, Timer_KillEnt, ent);
    // save individual to file and stop generation if fitness low enough
    /*if(GAIndividualFitness[individual] < 50)
    {
        simulating = false;
        file = OpenFile("runs/GA", "w+");
        for(int i=0; i<simFrames; i++)
        {
            file.WriteLine("%d,%f,%f", 
                GAIndividualInputsInt[i][individual],
                GAIndividualInputsFloat[i][individual][0],
                GAIndividualInputsFloat[i][individual][1]);
        }
        file.Close();
    }        */
}
public Action Timer_KillEnt(Handle hTimer, int ent)
{
    if(IsValidEntity(ent))
        AcceptEntityInput(ent, "Kill");
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
    simCurrentFrame = 0;
    simulating = true;
}
// FIXME: bork
// https://math.stackexchange.com/questions/13176/how-to-find-a-point-on-a-line-closest-to-another-given-point/1658288#1658288
public void ClosestPoint(float A[3], float B[3], float P[3], float ref[3])
{
    float C[3];
    MakeVectorFromPoints(A, B, C);
    AddVectors(A, C, C);
    float t = (- C[0] * (A[0] - P[0]) - C[1] * (A[1] - P[1]) - C[2] * (A[2] - P[2])) / (C[0] * C[0] + C[1] * C[1] + C[2] * C[2]);
    float D[3];
    ScaleVector(C, t);
    AddVectors(A, C, D);
    ref = D;
}

public void Breed()
{
    int fittest[6];
    float order[12];
    for(int i=0; i<populationSize;i++)
        order[i] = GAIndividualFitness[i];

    SortFloats(order, populationSize, Sort_Descending);
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
            for(int t=0; t<simFrames; t++)
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
//int oldEnt = -1;
//int entTick;
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    /*if(client != g_iBot)
    {
        if(entTick == 0)
        {
            if(GACheckPoints[1][0] != 0)
            {
                if(IsValidEntity(oldEnt))
                       AcceptEntityInput(oldEnt, "Kill");
                float p[3], p2[3];
                GetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", p);
                ClosestPoint(GAStartPos, GACheckPoints[1], p, p2);
                oldEnt = DrawLaser(p, p2, 255, 0, 0);
    
            }
        }

        entTick++;
        if(entTick >= 66)
            entTick = 0;
    }*/

    if(simulating)
    {
        if(client == g_iBot)
        {
            if(simCurrentFrame == simFrames)
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
                    PrintToChatAll("Playback ended");
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
                        ServerCommand("host_timescale 1");
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
            fAng[0] = GAIndividualInputsFloat[simCurrentFrame][simIndex][0];
            fAng[1] = GAIndividualInputsFloat[simCurrentFrame][simIndex][1];
            TeleportEntity(client, NULL_VECTOR, fAng, NULL_VECTOR);
            
            buttons = GAIndividualInputsInt[simCurrentFrame][simIndex];
            
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
            
            simCurrentFrame++;
            
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