using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ApplicationSupportFolderTests
{
    [TestMethod]
    public void EnsureExistsCreatesApplicationDataDirectory()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-support-{Guid.NewGuid():N}");

        try
        {
            var result = ApplicationSupportFolder.EnsureExists(directory);

            Assert.AreEqual(directory, result);
            Assert.IsTrue(Directory.Exists(directory));
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [TestMethod]
    public void EnsureExistsRejectsBlankDirectory()
    {
        Assert.ThrowsException<ArgumentException>(() => ApplicationSupportFolder.EnsureExists(" "));
    }

    [TestMethod]
    public void EnsureWebView2UserDataDirectoryCreatesStableChildFolder()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-support-{Guid.NewGuid():N}");

        try
        {
            var result = ApplicationSupportFolder.EnsureWebView2UserDataDirectory(directory);

            Assert.AreEqual(
                Path.Combine(directory, ApplicationSupportFolder.WebView2UserDataDirectoryName),
                result);
            Assert.IsTrue(Directory.Exists(result));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }
}
