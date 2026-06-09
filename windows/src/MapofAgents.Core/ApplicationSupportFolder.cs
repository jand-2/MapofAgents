namespace MapofAgents.Core;

public static class ApplicationSupportFolder
{
    public const string WebView2UserDataDirectoryName = "WebView2";

    public static string EnsureExists(string applicationDataDirectory)
    {
        if (string.IsNullOrWhiteSpace(applicationDataDirectory))
        {
            throw new ArgumentException("Application data directory is required.", nameof(applicationDataDirectory));
        }

        Directory.CreateDirectory(applicationDataDirectory);
        return applicationDataDirectory;
    }

    public static string EnsureWebView2UserDataDirectory(string applicationDataDirectory)
    {
        var root = EnsureExists(applicationDataDirectory);
        var directory = Path.Combine(root, WebView2UserDataDirectoryName);
        Directory.CreateDirectory(directory);
        return directory;
    }
}
