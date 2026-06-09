namespace MapofAgents.Core;

public readonly record struct MessageRouteDeliveryPresentationSnapshot(
    string Label,
    string ForegroundHex);

public static class MessageRouteDeliveryPresentation
{
    public const string PendingForegroundHex = ThreadInboxPresentation.BlueHex;
    public const string DeliveredForegroundHex = ThreadInboxPresentation.GreenHex;
    public const string FailedForegroundHex = ThreadInboxPresentation.RedHex;
    public const string UnknownForegroundHex = ThreadInboxPresentation.SecondaryHex;

    public static MessageRouteDeliveryPresentationSnapshot Resolve(string? deliveryState)
    {
        var normalized = Normalize(deliveryState);
        return new MessageRouteDeliveryPresentationSnapshot(
            LabelFor(normalized),
            ForegroundHexFor(normalized));
    }

    private static string Normalize(string? deliveryState)
    {
        return deliveryState?.Trim() switch
        {
            MessageRouteDeliveryStates.Pending => MessageRouteDeliveryStates.Pending,
            MessageRouteDeliveryStates.Delivered => MessageRouteDeliveryStates.Delivered,
            MessageRouteDeliveryStates.Failed => MessageRouteDeliveryStates.Failed,
            _ => MessageRouteDeliveryStates.Unknown
        };
    }

    private static string LabelFor(string deliveryState)
    {
        return deliveryState switch
        {
            MessageRouteDeliveryStates.Pending => "Pending",
            MessageRouteDeliveryStates.Delivered => "Delivered",
            MessageRouteDeliveryStates.Failed => "Failed",
            _ => "Unknown"
        };
    }

    private static string ForegroundHexFor(string deliveryState)
    {
        return deliveryState switch
        {
            MessageRouteDeliveryStates.Pending => PendingForegroundHex,
            MessageRouteDeliveryStates.Delivered => DeliveredForegroundHex,
            MessageRouteDeliveryStates.Failed => FailedForegroundHex,
            _ => UnknownForegroundHex
        };
    }
}
