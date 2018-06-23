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

bool recording = false, playback = false;

float startPos[3], startAngle[3], prevAngle[3];

File file;

public void OnPluginStart()
{
    RegConsoleCmd("sm_record", CmdRecord, "");
    RegConsoleCmd("sm_stoprecord", CmdStopRecord, "");
    
    RegConsoleCmd("sm_playback", CmdPlayback, "");
    RegConsoleCmd("sm_stopplayback", CmdStopPlayback, "");
}

public Action CmdRecord(int client, int args)
{
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
            TeleportEntity(client, startPos, startAngle, NULL_VECTOR);
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
                if(prevAngle[0] > 89)
                    prevAngle[0] = 89;
                else if(prevAngle[0] < -89)
                    prevAngle[0] = -89;
                if(prevAngle[1] > 180)
                    prevAngle[1] -= 360;
                else if(prevAngle[1] < -180)
                    prevAngle[1] += 360;
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