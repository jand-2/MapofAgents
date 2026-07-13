using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ArtifactCatalogTests
{
    [TestMethod]
    public void FiltersArtifactsWithoutMutatingSourceCatalog()
    {
        var catalog = CreateCatalog();
        catalog.Replace(
            "thread-1",
        [
            new TestArtifact("image-1", "image"),
            new TestArtifact("file-1", "file"),
            new TestArtifact("diff-1", "diff")
        ]);

        catalog.SetFilter(ArtifactCatalogFilter.Images);

        CollectionAssert.AreEqual(
            new[] { "image-1" },
            catalog.VisibleItems.Select(item => item.Id).ToArray());
        Assert.AreEqual(3, catalog.Count);
    }

    [TestMethod]
    public void ReplacingCatalogRebindsSelectionByStableId()
    {
        var catalog = CreateCatalog();
        var initial = new TestArtifact("file-1", "file");
        catalog.Replace("thread-1", [initial]);
        Assert.IsTrue(catalog.Select(initial));

        var replacement = new TestArtifact("file-1", "file");
        catalog.Replace("thread-1", [replacement]);

        Assert.AreSame(replacement, catalog.Selected);
    }

    [TestMethod]
    public void ChangingSourceClearsSelectionEvenWhenArtifactIdsOverlap()
    {
        var catalog = CreateCatalog();
        var first = new TestArtifact("file-1", "file");
        catalog.Replace("thread-1", [first]);
        Assert.IsTrue(catalog.Select(first));

        catalog.Replace("thread-2", [new TestArtifact("file-1", "file")]);

        Assert.AreEqual("thread-2", catalog.SourceId);
        Assert.IsNull(catalog.Selected);
    }

    [TestMethod]
    public void FilteringOrRemovalClearsHiddenSelection()
    {
        var catalog = CreateCatalog();
        var image = new TestArtifact("image-1", "image");
        catalog.Replace("thread-1", [image]);
        Assert.IsTrue(catalog.Select(image));

        catalog.SetFilter(ArtifactCatalogFilter.Files);

        Assert.IsNull(catalog.Selected);
        catalog.SetFilter(ArtifactCatalogFilter.All);
        Assert.IsTrue(catalog.Select(image));
        catalog.Replace("thread-1", []);
        Assert.IsNull(catalog.Selected);
    }

    [TestMethod]
    public void RejectsUnknownFiltersAndItemsOutsideCatalog()
    {
        var catalog = CreateCatalog();
        catalog.Replace("thread-1", [new TestArtifact("file-1", "file")]);

        Assert.ThrowsException<ArgumentOutOfRangeException>(() => catalog.SetFilter("unknown"));
        Assert.IsFalse(catalog.Select(new TestArtifact("file-2", "file")));
    }

    [TestMethod]
    public void PreviewLocationAcceptsWebAndExistingFilesOnly()
    {
        Assert.IsTrue(ArtifactPreviewLocation.TryResolve("https://example.com/image.png", out var webUri));
        Assert.AreEqual("https", webUri.Scheme);
        Assert.IsFalse(ArtifactPreviewLocation.TryResolve("ftp://example.com/image.png", out _));
        Assert.IsFalse(ArtifactPreviewLocation.TryResolve("/missing/image.png", out _));

        var temporaryPath = Path.GetTempFileName();
        try
        {
            Assert.IsTrue(ArtifactPreviewLocation.TryResolve(temporaryPath, out var fileUri));
            Assert.IsTrue(fileUri.IsFile);
        }
        finally
        {
            File.Delete(temporaryPath);
        }
    }

    private static ArtifactCatalog<TestArtifact> CreateCatalog()
    {
        return new ArtifactCatalog<TestArtifact>(item => item.Id, item => item.Kind);
    }

    private sealed record TestArtifact(string Id, string Kind);
}
