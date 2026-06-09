namespace MapofAgents.Core;

public readonly record struct ThreadPopoverFrame(double Left, double Top, double Width, double Height);

public static class ThreadPopoverLayout
{
    public const double Margin = 24;
    public const double ReservedRailWidth = 348;
    public const double ReservedRailThreshold = 900;

    public static CanvasSize Size(double canvasWidth, double canvasHeight)
    {
        return new CanvasSize(
            Math.Min(440, Math.Max(360, canvasWidth * 0.34)),
            Math.Min(560, Math.Max(380, canvasHeight - 96)));
    }

    public static ThreadPopoverFrame Measure(
        double canvasWidth,
        double canvasHeight,
        CanvasPoint nodePosition,
        CanvasSize nodeSize,
        CanvasViewport viewport,
        CanvasPoint? savedOffset = null)
    {
        var size = Size(canvasWidth, canvasHeight);
        var scale = viewport.Scale > 0 ? viewport.Scale : 1;
        var nodeCenterX = viewport.Offset.X + nodePosition.X * scale;
        var nodeCenterY = viewport.Offset.Y + nodePosition.Y * scale;
        var nodeHalfWidth = Math.Max(1, nodeSize.Width) * scale / 2;
        var nodeHalfHeight = Math.Max(1, nodeSize.Height) * scale / 2;
        var effectiveWidth = EffectiveWidth(canvasWidth, size.Width);

        var rightCenterX = nodeCenterX + nodeHalfWidth + Margin + size.Width / 2;
        var leftCenterX = nodeCenterX - nodeHalfWidth - Margin - size.Width / 2;
        double centerX;

        if (rightCenterX + size.Width / 2 + Margin <= effectiveWidth)
        {
            centerX = rightCenterX;
        }
        else if (leftCenterX - size.Width / 2 - Margin >= 0)
        {
            centerX = leftCenterX;
        }
        else
        {
            centerX = Math.Clamp(
                rightCenterX,
                size.Width / 2 + Margin,
                effectiveWidth - size.Width / 2 - Margin);
        }

        var centerY = nodeCenterY + nodeHalfHeight + Margin + size.Height / 2;
        var baseFrame = FrameFromCenter(
            canvasWidth,
            canvasHeight,
            size.Width,
            size.Height,
            centerX,
            centerY);

        if (savedOffset is null)
        {
            return baseFrame;
        }

        return ClampFrame(
            canvasWidth,
            canvasHeight,
            size.Width,
            size.Height,
            baseFrame.Left + savedOffset.X,
            baseFrame.Top + savedOffset.Y);
    }

    public static ThreadPopoverFrame ClampFrame(
        double canvasWidth,
        double canvasHeight,
        double width,
        double height,
        double left,
        double top)
    {
        return FrameFromCenter(
            canvasWidth,
            canvasHeight,
            width,
            height,
            left + width / 2,
            top + height / 2);
    }

    private static ThreadPopoverFrame FrameFromCenter(
        double canvasWidth,
        double canvasHeight,
        double width,
        double height,
        double centerX,
        double centerY)
    {
        var effectiveWidth = EffectiveWidth(canvasWidth, width);
        var minX = width / 2 + Margin;
        var maxX = Math.Max(minX, effectiveWidth - width / 2 - Margin);
        var minY = height / 2 + Margin;
        var maxY = Math.Max(minY, canvasHeight - height / 2 - Margin);

        var clampedX = Math.Clamp(centerX, minX, maxX);
        var clampedY = Math.Clamp(centerY, minY, maxY);
        return new ThreadPopoverFrame(
            clampedX - width / 2,
            clampedY - height / 2,
            width,
            height);
    }

    private static double EffectiveWidth(double canvasWidth, double popoverWidth)
    {
        var reservedRightWidth = canvasWidth >= ReservedRailThreshold ? ReservedRailWidth : 0;
        return Math.Max(popoverWidth + Margin * 2, canvasWidth - reservedRightWidth);
    }
}
