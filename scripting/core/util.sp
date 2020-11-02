/* ****************************************************************
    util.sp

    Utility functions.
**************************************************************** */

// Summary:
// Get the closest point (out) on line AB to point P
public void ClosestPoint(float A[3], float B[3], float P[3], float out[3])
{
    float AB[3];
    SubtractVectors(B, A, AB);

    float AP[3];
    SubtractVectors(P, A, AP);

    float lengthSqrAB = AB[0] * AB[0] + AB[1] * AB[1] + AB[2] * AB[2];
    float t = (AP[0] * AB[0] + AP[1] * AB[1] + AP[2] * AB[2]) / lengthSqrAB;

    if(t < 0.0)
    {
        t = 0.0;
    }

    if(t > 1.0)
    {
        t = 1.0;
    }

    ScaleVector(AB, t);
    AddVectors(A, AB, out);
}

// Summary:
// Clamp client eye angles
public void ClampEyeAngles(float fAngles[3], float fMaxPitch)
{
    // clamp pitch
    if (fAngles[0] < -fMaxPitch)
    {
        fAngles[0] = -fMaxPitch;
    }
    else if (fAngles[0] > fMaxPitch)
    {
        fAngles[0] = fMaxPitch;
    }

    // yaw wrap around
    if (fAngles[1] < -180.0)
    {
        fAngles[1] += 360.0;
    }
    else if (fAngles[1] > 180.0)
    {
        fAngles[1] -= 360.0;
    }
}

// Summary:
// Get desired velocity from buttons
public void VelocityFromButtons(float fVel[3], int iButtons)
{
    if (iButtons & IN_FORWARD)
    {
        fVel[0] = 400.0;
    }
    else
    {
        fVel[0] = 0.0;
    }
    
    if (iButtons & (IN_MOVELEFT|IN_MOVERIGHT) == IN_MOVELEFT|IN_MOVERIGHT)
    {
        fVel[1] = 0.0;
    }
    else if (iButtons & IN_MOVELEFT)
    {
        fVel[1] = -400.0;
    }
    else if (iButtons & IN_MOVERIGHT)
    {
        fVel[1] = 400.0;
    }
}

public void FormatUnixTimestamp(char cTimeStamp[9], int iTime)
{
    int iHours = iTime / (60 * 60);
    int iMinutes = (iTime % (60 * 60)) / (60);
    int iSeconds = iTime % 60;

    char cHours[3];
    char cMinutes[3];
    char cSeconds[3];

    Format(cHours, 3, "%s%d", iHours < 9 ? "0" : "", iHours);
    Format(cMinutes, 3, "%s%d", iMinutes < 9 ? "0" : "", iMinutes);
    Format(cSeconds, 3, "%s%d", iSeconds < 9 ? "0" : "", iSeconds);

    Format(cTimeStamp, 9, "%s:%s:%s", cHours, cMinutes, cSeconds);
}