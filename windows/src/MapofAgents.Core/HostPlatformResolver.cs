namespace MapofAgents.Core;

public static class HostPlatformResolver
{
    public static string Resolve(string? value)
    {
        var normalized = (value ?? "").ToLowerInvariant();
        if (normalized.Contains("mac") || normalized.Contains("darwin"))
        {
            return HostPlatforms.MacOS;
        }

        if (normalized.Contains("windows"))
        {
            return HostPlatforms.Windows;
        }

        if (normalized.Contains("linux"))
        {
            return HostPlatforms.Linux;
        }

        if (normalized.Contains("ipad"))
        {
            return HostPlatforms.IPadOS;
        }

        if (normalized.Contains("ios"))
        {
            return HostPlatforms.IOS;
        }

        return HostPlatforms.Unknown;
    }
}
