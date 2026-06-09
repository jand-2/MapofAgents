using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class HostPlatformResolverTests
{
    [TestMethod]
    public void ResolvesCommonPlatformLabels()
    {
        Assert.AreEqual(HostPlatforms.Windows, HostPlatformResolver.Resolve("Windows DESKTOP-EXAMPLE"));
        Assert.AreEqual(HostPlatforms.MacOS, HostPlatformResolver.Resolve("darwin arm64"));
        Assert.AreEqual(HostPlatforms.Linux, HostPlatformResolver.Resolve("linux"));
        Assert.AreEqual(HostPlatforms.Unknown, HostPlatformResolver.Resolve(""));
    }
}
