namespace MapofAgents.Core;

public static class ArtifactCatalogFilter
{
    public const string All = "all";
    public const string Images = "images";
    public const string Files = "files";
    public const string Diffs = "diffs";

    public static bool IsSupported(string filter)
    {
        return filter is All or Images or Files or Diffs;
    }
}

public static class ArtifactPreviewLocation
{
    public static bool TryResolve(string? path, out Uri uri)
    {
        if (!string.IsNullOrWhiteSpace(path) &&
            Uri.TryCreate(path, UriKind.Absolute, out var candidateUri))
        {
            if ((candidateUri.IsFile && File.Exists(candidateUri.LocalPath)) ||
                candidateUri.Scheme is "http" or "https")
            {
                uri = candidateUri;
                return true;
            }
        }

        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
        {
            uri = new Uri(Path.GetFullPath(path));
            return true;
        }

        uri = new Uri("about:blank");
        return false;
    }
}

/// <summary>
/// Owns artifact source, filtering, and selection state while leaving rendering
/// and platform-specific file previews to the host UI.
/// </summary>
public sealed class ArtifactCatalog<T> where T : class
{
    private readonly Func<T, string> _id;
    private readonly Func<T, string> _kind;
    private List<T> _items = [];

    public ArtifactCatalog(Func<T, string> id, Func<T, string> kind)
    {
        _id = id ?? throw new ArgumentNullException(nameof(id));
        _kind = kind ?? throw new ArgumentNullException(nameof(kind));
    }

    public string Filter { get; private set; } = ArtifactCatalogFilter.All;

    public string? SourceId { get; private set; }

    public T? Selected { get; private set; }

    public int Count => _items.Count;

    public IReadOnlyList<T> VisibleItems => _items.Where(MatchesFilter).ToList();

    public void Replace(string sourceId, IEnumerable<T> items)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceId);
        ArgumentNullException.ThrowIfNull(items);
        var selectedId = string.Equals(SourceId, sourceId, StringComparison.Ordinal) && Selected is not null
            ? _id(Selected)
            : null;
        SourceId = sourceId;
        _items = items.ToList();
        Selected = selectedId is null
            ? null
            : _items.FirstOrDefault(item => string.Equals(_id(item), selectedId, StringComparison.Ordinal));
        ClearHiddenSelection();
    }

    public void ClearSource()
    {
        SourceId = null;
        Selected = null;
        _items.Clear();
        Filter = ArtifactCatalogFilter.All;
    }

    public void SetFilter(string filter)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(filter);
        if (!ArtifactCatalogFilter.IsSupported(filter))
        {
            throw new ArgumentOutOfRangeException(nameof(filter), filter, "Unknown artifact filter.");
        }

        Filter = filter;
        ClearHiddenSelection();
    }

    public bool Select(T item)
    {
        ArgumentNullException.ThrowIfNull(item);
        var itemId = _id(item);
        var catalogItem = _items.FirstOrDefault(candidate =>
            string.Equals(_id(candidate), itemId, StringComparison.Ordinal));
        if (catalogItem is null || !MatchesFilter(catalogItem))
        {
            return false;
        }

        Selected = catalogItem;
        return true;
    }

    public void ClearSelection()
    {
        Selected = null;
    }

    private bool MatchesFilter(T item)
    {
        return Filter switch
        {
            ArtifactCatalogFilter.Images => _kind(item) == "image",
            ArtifactCatalogFilter.Files => _kind(item) == "file",
            ArtifactCatalogFilter.Diffs => _kind(item) == "diff",
            _ => true
        };
    }

    private void ClearHiddenSelection()
    {
        if (Selected is not null && !MatchesFilter(Selected))
        {
            Selected = null;
        }
    }
}
