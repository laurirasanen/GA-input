/* ****************************************************************
    debug.sp

    Utility functions.
**************************************************************** */

// Summary:
// Get the closest point on a line from point A to B
public void ClosestPoint(float A[3], float B[3], float P[3], float ref[3])
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
    AddVectors(A, AB, ref);
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