/* ****************************************************************
    debug.sp

    Debug functions.
**************************************************************** */

// Summary:
// Draw a laser beam to all clients
// https://forums.alliedmods.net/showthread.php?t=190685
public int DrawLaser(float start[3], float end[3], int red, int green, int blue)
{
    int ent = CreateEntityByName("env_beam");

    if (ent != -1) 
    {
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

// Summary:
// Hide debug lines
public void HideLines() {
    char name[32];

    // Loop through entities
    // starting after client entities
    for(int i = MaxClients + 1; i <= GetMaxEntities(); i++)
    {
        if(!IsValidEntity(i))
        {
            continue;
        }
    
        if(GetEdictClassname(i, name, sizeof(name)))
        {
            if(StrEqual("env_beam", name, false))
            {
                RemoveEdict(i);
            }
        }
    }
}

// Summary:
// Draws debug lines to all clients
public void DrawLines(float[][3] fCheckpoints, int iSize, float fStartPoint[3], float fEndPoint[3]) 
{
    // Draw laser between start position, all checkpoints and end position
    for(int i = 0; i < iSize; i++) 
    {
        // Check if checkpoint is valid
        if(fCheckpoints[i][0] != 0 && fCheckpoints[i][1] != 0 && fCheckpoints[i][2] != 0)
        {
            if(i == 0)
            {
                // Laser from start position to first checkpoint
                DrawLaser(fStartPoint, fCheckpoints[i], 0, 255, 0);
            } 

            if(i + 1 < iSize)
            {
                // Check if checkpoint [i + 1] is valid
                if(fCheckpoints[i + 1][0] != 0 && fCheckpoints[i + 1][1] != 0 && fCheckpoints[i + 1][2] != 0)
                {
                    // Laser from checkpoint i to i + 1
                    DrawLaser(fCheckpoints[i], fCheckpoints[i + 1], 0, 255, 0);
                }
                else
                {
                    // Laser to end
                    DrawLaser(fCheckpoints[i], fEndPoint, 0, 255, 0);
                }
            }
            else
            {
                // Laser to end
                DrawLaser(fCheckpoints[i], fEndPoint, 0, 255, 0);
            }
        }
        else
        {
            if(i == 0)
            {
                // No checkpoints
                DrawLaser(fStartPoint, fEndPoint, 0, 255, 0);
            }
        }
    }
}

// Show keypresses of the bot
public void UpdateKeyDisplay(int iButtons, Handle hText)
{
    char sOutput[256];

    if(iButtons & IN_FORWARD)
    {
        Format(sOutput, sizeof(sOutput), "     W\n");
    }
    else
    {
        Format(sOutput, sizeof(sOutput), "     -\n");
    }

    if(iButtons & IN_JUMP)
    {
        Format(sOutput, sizeof(sOutput), "%s     JUMP\n", sOutput);
    }
    else
    {
        Format(sOutput, sizeof(sOutput), "%s     _   \n", sOutput);
    }
    
    if(iButtons & IN_MOVELEFT)
    {
        Format(sOutput, sizeof(sOutput), "%s  A", sOutput);
    }
    else
    {
        Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
    }        
        
    if(iButtons & IN_BACK)
    {
        Format(sOutput, sizeof(sOutput), "%s  S", sOutput);
    }        
    else
    {
        Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
    }        
        
    if(iButtons & IN_MOVERIGHT)
    {
        Format(sOutput, sizeof(sOutput), "%s  D", sOutput);
    }        
    else
    {
        Format(sOutput, sizeof(sOutput), "%s  -", sOutput);
    }

    if(iButtons & IN_DUCK)
    {
        Format(sOutput, sizeof(sOutput), "%s       DUCK\n", sOutput);
    }        
    else
    {
        Format(sOutput, sizeof(sOutput), "%s       _   \n", sOutput);
    }

    if(iButtons & IN_ATTACK)
    {
        Format(sOutput, sizeof(sOutput), "%sMOUSE1", sOutput);
    }
    else
    {
        Format(sOutput, sizeof(sOutput), "%s_     ", sOutput);
    }
    
    if(iButtons & IN_ATTACK2)
    {
        Format(sOutput, sizeof(sOutput), "%s  MOUSE2", sOutput);
    }
    else
    {
        Format(sOutput, sizeof(sOutput), "%s  _     ", sOutput);
    }

    SetHudTextParams(0.47, 0.67, 1.0, 255, 255, 255, 255);

    for(int i=1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            ShowSyncHudText(i, hText, sOutput); 
        }        
    }
}