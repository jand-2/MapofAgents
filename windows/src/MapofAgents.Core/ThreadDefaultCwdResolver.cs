namespace MapofAgents.Core;

public static class ThreadDefaultCwdResolver
{
    public static string? DefaultCwd(
        CanvasNode machine,
        string localHostId,
        string? localDefaultDirectory = null)
    {
        if (!string.IsNullOrWhiteSpace(machine.Metadata.CodexHome))
        {
            var codexHome = machine.Metadata.CodexHome.Trim();
            var fallbackDirectory = SameHost(machine.Metadata.HostID, localHostId)
                ? localDefaultDirectory
                : null;
            return UsableDefaultDirectory(
                    ParentDirectory(codexHome, machine.Metadata.Platform, fallbackDirectory))
                ?? UsableDefaultDirectory(fallbackDirectory);
        }

        if (SameHost(machine.Metadata.HostID, localHostId) &&
            UsableDefaultDirectory(localDefaultDirectory) is { } localDirectory)
        {
            return localDirectory;
        }

        return string.Equals(machine.Metadata.Platform, HostPlatforms.Windows, StringComparison.OrdinalIgnoreCase)
            ? @"C:\Users\User"
            : null;
    }

    public static string ParentDirectory(
        string path,
        string? platform,
        string? fallbackDirectory = null)
    {
        var trimmed = path.Trim();
        var fallback = fallbackDirectory?.Trim();
        if (trimmed.Length == 0)
        {
            return string.IsNullOrWhiteSpace(fallback) ? RootFallback(platform) : fallback!;
        }

        if (HasWindowsDrivePrefix(trimmed))
        {
            var withoutTrailingSeparators = trimmed.TrimEnd('\\', '/');
            var lastSeparator = Math.Max(
                withoutTrailingSeparators.LastIndexOf('\\'),
                withoutTrailingSeparators.LastIndexOf('/'));
            return lastSeparator > 0
                ? withoutTrailingSeparators[..lastSeparator]
                : trimmed;
        }

        var normalized = trimmed.TrimEnd('\\', '/');
        var separator = Math.Max(normalized.LastIndexOf('/'), normalized.LastIndexOf('\\'));
        if (separator > 0)
        {
            return normalized[..separator];
        }

        if (separator == 0)
        {
            return normalized[..1];
        }

        return string.IsNullOrWhiteSpace(fallback) ? RootFallback(platform) : fallback!;
    }

    private static string? UsableDefaultDirectory(string? path)
    {
        var trimmed = path?.Trim();
        if (string.IsNullOrWhiteSpace(trimmed) || IsRootDirectory(trimmed))
        {
            return null;
        }

        return trimmed;
    }

    private static bool IsRootDirectory(string path)
    {
        var trimmed = path.Trim();
        return trimmed is "/" or "\\" or "//" ||
            (trimmed.Length >= 2 &&
                char.IsLetter(trimmed[0]) &&
                trimmed[1] == ':' &&
                trimmed[2..].Trim('\\', '/').Length == 0);
    }

    private static bool HasWindowsDrivePrefix(string path)
    {
        return path.Length >= 2 && char.IsLetter(path[0]) && path[1] == ':';
    }

    private static string RootFallback(string? platform)
    {
        return string.Equals(platform, HostPlatforms.Windows, StringComparison.OrdinalIgnoreCase)
            ? @"C:\Users\User"
            : "/";
    }

    private static bool SameHost(string? lhs, string? rhs)
    {
        return !string.IsNullOrWhiteSpace(lhs) &&
            !string.IsNullOrWhiteSpace(rhs) &&
            string.Equals(lhs, rhs, StringComparison.OrdinalIgnoreCase);
    }
}
