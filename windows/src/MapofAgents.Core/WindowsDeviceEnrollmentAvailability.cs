namespace MapofAgents.Core;

public static class WindowsDeviceEnrollmentAvailability
{
    public const bool CanStartHostListener = false;
    public const bool CanGeneratePairingCode = false;
    public const bool IsAvailable = CanStartHostListener && CanGeneratePairingCode;
    public const string Label = "Secure enrollment unavailable";
    public const string Title = "Secure device enrollment unavailable";
    public const string Detail = "Secure device enrollment is not yet available on Windows.";
}
