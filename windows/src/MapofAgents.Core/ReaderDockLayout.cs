namespace MapofAgents.Core;

public readonly record struct ReaderDockLayoutMetrics(
    int ColumnCount,
    int RowCount,
    double TileWidth,
    double TileHeight,
    double SlotWidth,
    double SlotHeight);

public static class ReaderDockLayout
{
    public const double MinimumColumnWidth = 430;
    public const double MinimumTileHeight = 430;
    public const double TileSpacing = 12;
    public const double ContentPadding = 14;
    public const int MaximumColumns = 4;

    public static ReaderDockLayoutMetrics Measure(
        double viewportWidth,
        double viewportHeight,
        int itemCount)
    {
        var width = Math.Max(MinimumColumnWidth, viewportWidth);
        var contentWidth = Math.Max(MinimumColumnWidth, width - (ContentPadding * 2));
        var height = Math.Max(MinimumTileHeight, viewportHeight);
        var contentHeight = Math.Max(MinimumTileHeight, height - (ContentPadding * 2));
        var count = Math.Max(itemCount, 1);
        var maxColumnsByWidth = Math.Max(
            1,
            Math.Min(
                MaximumColumns,
                (int)((width + TileSpacing) / (MinimumColumnWidth + TileSpacing))));
        var columnCount = Math.Max(1, Math.Min(maxColumnsByWidth, count));
        var rowCount = Math.Max(1, (int)Math.Ceiling((double)count / columnCount));
        var columnSpacing = Math.Max(columnCount - 1, 0) * TileSpacing;
        var rowSpacing = Math.Max(rowCount - 1, 0) * TileSpacing;
        var tileWidth = Math.Max(MinimumColumnWidth, Math.Floor((contentWidth - columnSpacing) / columnCount));
        var tileHeight = Math.Max(MinimumTileHeight, Math.Floor((contentHeight - rowSpacing) / rowCount));
        var slotWidth = tileWidth + (columnCount > 1 ? TileSpacing : 0);
        var slotHeight = tileHeight + (rowCount > 1 ? TileSpacing : 0);

        return new ReaderDockLayoutMetrics(
            columnCount,
            rowCount,
            tileWidth,
            tileHeight,
            slotWidth,
            slotHeight);
    }
}
