using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Numerics;
using MapofAgents.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace MapofAgents.WindowsApp;

public sealed class ReaderThreadItem : INotifyPropertyChanged
{
    private string _draftText = "";
    private string _attachmentErrorText = "";
    private Visibility _mentionPanelVisibility = Visibility.Collapsed;
    private double _tileWidth = 430;
    private double _tileHeight = 430;

    public ReaderThreadItem()
    {
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ReaderThreadItem(
        string id,
        string title,
        string subtitle,
        string threadId,
        string? model,
        string? effort,
        string approval,
        string sandbox,
        string status,
        bool isUnread,
        StopTurnActionAvailability stopAvailability,
        string threadKindText,
        string threadKindGlyph,
        SolidColorBrush threadKindBrush,
        SolidColorBrush threadKindBackgroundBrush,
        string headerGlyph,
        bool headerUsesThreadPairIcon,
        SolidColorBrush headerIconBrush,
        SolidColorBrush headerIconBackgroundBrush,
        string liveStateGlyph,
        string liveStateText,
        SolidColorBrush liveStateBrush,
        List<ReaderTranscriptRow> messages,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories,
        ObservableCollection<ComposerAttachmentItem> pendingAttachments,
        bool isLoadingTranscript,
        bool isLoadingOlder,
        bool hasOlderCursor,
        string? transcriptError,
        bool hasLoadedTranscript,
        double tileWidth,
        double tileHeight)
    {
        Id = id;
        Title = title;
        Subtitle = subtitle;
        ThreadIDLabel = threadId;
        var composerMetadata = ThreadComposerMetadataPresentation.Resolve(model, effort);
        Model = composerMetadata.ModelText;
        Effort = composerMetadata.EffortText;
        ComposerMetadataVisibility = composerMetadata.ShowsMetadataRow
            ? Visibility.Visible
            : Visibility.Collapsed;
        ModelChipVisibility = composerMetadata.ShowsModel ? Visibility.Visible : Visibility.Collapsed;
        EffortChipVisibility = composerMetadata.ShowsEffort ? Visibility.Visible : Visibility.Collapsed;
        Approval = approval;
        Sandbox = sandbox;
        ThreadKindText = threadKindText;
        ThreadKindGlyph = threadKindGlyph;
        ThreadKindBrush = threadKindBrush;
        ThreadKindBackgroundBrush = threadKindBackgroundBrush;
        HeaderGlyph = headerGlyph;
        HeaderUsesThreadPairIcon = headerUsesThreadPairIcon;
        HeaderIconBrush = headerIconBrush;
        HeaderIconBackgroundBrush = headerIconBackgroundBrush;
        var headerIconPresentation = ThreadHeaderIconPresentation.Resolve(!headerUsesThreadPairIcon);
        HeaderSurfaceSize = headerIconPresentation.HeaderSurfaceSize;
        HeaderSurfaceCornerRadius = new CornerRadius(headerIconPresentation.HeaderSurfaceCornerRadius);
        HeaderIconGridWidth = headerIconPresentation.HeaderIconGridWidth;
        HeaderIconGridHeight = headerIconPresentation.HeaderIconGridHeight;
        HeaderGlyphFontSize = headerIconPresentation.HeaderGlyphFontSize;
        HeaderPairBackGlyphFontSize = headerIconPresentation.HeaderPairBackGlyphFontSize;
        HeaderPairFrontGlyphFontSize = headerIconPresentation.HeaderPairFrontGlyphFontSize;
        HeaderPairBackOpacity = headerIconPresentation.HeaderPairBackOpacity;
        var shellPresentation = ThreadPopoverShellPresentation.ResolveReaderTile();
        HeaderColumnSpacing = shellPresentation.HeaderColumnSpacing;
        HeaderActionSpacing = shellPresentation.HeaderActionSpacing;
        HeaderControlsMargin = new Thickness(shellPresentation.HeaderControlsLeftInset, 0, 0, 0);
        LiveStateGlyph = liveStateGlyph;
        LiveStateText = liveStateText;
        LiveStateBrush = liveStateBrush;
        var statusPresentation = ThreadStatusPresentation.Resolve(status, isUnread);
        var stopPresentation = StopTurnActionPresentation.Resolve();
        StatusText = statusPresentation.Text;
        StatusGlyph = statusPresentation.Glyph;
        StatusForegroundBrush = ReaderBrush(statusPresentation.ForegroundHex);
        StatusBackgroundBrush = ReaderBrush(statusPresentation.BackgroundHex);
        StatusBorderBrush = ReaderBrush(statusPresentation.BorderHex);
        StatusPillBorderThickness = new Thickness(statusPresentation.BorderThickness);
        StatusPillPadding = new Thickness(
            statusPresentation.HorizontalPadding,
            statusPresentation.VerticalPadding,
            statusPresentation.HorizontalPadding,
            statusPresentation.VerticalPadding);
        StatusPillCornerRadius = new CornerRadius(statusPresentation.CornerRadius);
        StatusPillMinWidth = statusPresentation.MinWidth;
        StatusIconFontSize = statusPresentation.IconFontSize;
        StatusTextFontSize = statusPresentation.TextFontSize;
        StopButtonGlyph = stopAvailability.WindowsGlyph;
        StopButtonForegroundBrush = ReaderBrush(stopPresentation.ForegroundHex);
        StopButtonBackgroundBrush = ReaderBrush(stopPresentation.BackgroundHex);
        StopButtonBorderBrush = ReaderBrush(stopPresentation.BorderHex);
        CanStopTurn = stopAvailability.CanInvoke;
        StopButtonIsEnabled = stopAvailability.IsButtonEnabled;
        StopButtonVisibility = stopAvailability.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        StopButtonOpacity = stopAvailability.Opacity;
        StopButtonTooltip = stopAvailability.ToolTip;
        StopButtonAccessibilityName = stopAvailability.AccessibilityName;
        StopButtonAccessibilityHint = stopAvailability.AccessibilityHint;
        IsComposerEnabled = status != ThreadRunStatuses.Running;
        PendingAttachments = pendingAttachments;
        SendButtonGlyph = ThreadSendActionPresentation.WindowsGlyph;
        PendingAttachments.CollectionChanged += (_, _) => NotifySendActionChanged();
        IsTranscriptLoading = isLoadingTranscript;
        IsTranscriptLoadingOlder = isLoadingOlder;
        TranscriptLoadingVisibility = isLoadingTranscript &&
            activeCategories.Contains(ReaderTranscriptCategory.Progress)
                ? Visibility.Visible
                : Visibility.Collapsed;
        var loadingPresentation = TranscriptLoadPhasePresentation.Resolve(
            TranscriptLoadPhasePresentation.InitialPhase(isLoadingOlder, hasLoadedTranscript));
        var loadingRowPresentation = TranscriptLoadingRowPresentation.Resolve(hasLoadedTranscript || isLoadingOlder);
        TranscriptLoadingGlyph = loadingPresentation.WindowsGlyph;
        TranscriptLoadingTitle = loadingPresentation.Title;
        TranscriptLoadingDetail = loadingPresentation.Detail;
        TranscriptLoadingPadding = new Thickness(loadingRowPresentation.Padding);
        TranscriptLoadingMargin = new Thickness(0, loadingRowPresentation.VerticalMargin, 0, loadingRowPresentation.VerticalMargin);
        TranscriptLoadingHorizontalAlignment = LoadingRowHorizontalAlignment(loadingRowPresentation);
        TranscriptLoadingBackgroundBrush = ReaderBrush(loadingRowPresentation.BackgroundHex);
        TranscriptLoadingBorderBrush = ReaderBrush(loadingRowPresentation.BorderHex);
        var loadOlderPresentation = LoadOlderMessagesActionPresentation.Resolve(hasOlderCursor, isLoadingOlder);
        LoadOlderButtonVisibility = loadOlderPresentation.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        IsLoadOlderEnabled = loadOlderPresentation.IsButtonEnabled;
        LoadOlderButtonOpacity = loadOlderPresentation.Opacity;
        LoadOlderButtonTooltip = loadOlderPresentation.ToolTip;
        LoadOlderAccessibilityHint = loadOlderPresentation.AccessibilityHint;
        LoadOlderProgressVisibility = loadOlderPresentation.ShowsProgress ? Visibility.Visible : Visibility.Collapsed;
        LoadOlderIconVisibility = !loadOlderPresentation.ShowsProgress && loadOlderPresentation.ShowsIdleIcon
            ? Visibility.Visible
            : Visibility.Collapsed;
        LoadOlderButtonText = loadOlderPresentation.ButtonText;
        var hasTranscriptError = !string.IsNullOrWhiteSpace(transcriptError);
        var transientCounts = TranscriptTransientRows.Count(isLoadingTranscript, hasTranscriptError);
        TranscriptErrorText = transcriptError ?? "";
        TranscriptErrorVisibility = hasTranscriptError &&
            activeCategories.Contains(ReaderTranscriptCategory.System)
                ? Visibility.Visible
                : Visibility.Collapsed;
        UseCachedTranscriptVisibility = hasLoadedTranscript ? Visibility.Visible : Visibility.Collapsed;
        Filters = ReaderTranscriptFilterItem.Build(
            id,
            messages,
            activeCategories,
            additionalProgressCount: transientCounts.ProgressCount,
            additionalSystemCount: transientCounts.SystemCount);
        Messages = messages
            .Where(row => row.MatchesAnyCategory(activeCategories))
            .ToList();
        var categories = OrderedTranscriptCategories();
        var selectedCategories = categories.Where(activeCategories.Contains).ToList();
        var isShowingAllRows = selectedCategories.Count == categories.Length;
        FilterSummaryText = isShowingAllRows
            ? "All rows"
            : selectedCategories.Count > 2
                ? $"{selectedCategories.Count} filters"
                : string.Join(", ", selectedCategories.Select(CompactTitleFor));
        FilterDetailText = isShowingAllRows
            ? "Messages, progress, thoughts, tools, artifacts, approvals, events"
            : string.Join(", ", selectedCategories.Select(TitleFor));
        FilterDetailBrush = ReaderBrush(TranscriptFilterPresentation.DetailForegroundHex(isShowingAllRows));
        ResetFiltersVisibility = isShowingAllRows ? Visibility.Collapsed : Visibility.Visible;
        MessageFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Message,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        ProgressFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Progress,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        ThoughtFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Thought,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        ToolFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Tool,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        ArtifactFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Artifact,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        ApprovalFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.Approval,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        SystemFilterMenuText = MenuTitleFor(
            ReaderTranscriptCategory.System,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount);
        IsMessageFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Message);
        IsProgressFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Progress);
        IsThoughtFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Thought);
        IsToolFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Tool);
        IsArtifactFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Artifact);
        IsApprovalFilterActive = activeCategories.Contains(ReaderTranscriptCategory.Approval);
        IsSystemFilterActive = activeCategories.Contains(ReaderTranscriptCategory.System);
        FilteredEmptyVisibility = messages.Count + transientCounts.TotalCount > 0 &&
            Messages.Count == 0 &&
            TranscriptErrorVisibility != Visibility.Visible &&
            TranscriptLoadingVisibility != Visibility.Visible
            ? Visibility.Visible
            : Visibility.Collapsed;
        var artifactCount = messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Artifact));
        HasArtifacts = artifactCount > 0;
        ArtifactButtonTooltip = artifactCount == 0
            ? ArtifactsActionPresentation.UnavailableReason
            : $"{artifactCount} artifact{(artifactCount == 1 ? "" : "s")}";
        ArtifactButtonOpacity = artifactCount == 0
            ? ArtifactsActionPresentation.UnavailableOpacity
            : 1.0;
        ArtifactButtonAccessibilityHint = artifactCount == 0
            ? ArtifactsActionPresentation.UnavailableReason
            : "";
        MessageCountText = $"{messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Message))} messages";
        ProgressCountText = $"{CountFor(
            ReaderTranscriptCategory.Progress,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount)} progress";
        ThoughtCountText = $"{messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Thought))} thoughts";
        ToolCountText = $"{messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Tool))} tools";
        ArtifactCountText = $"{messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Artifact))} artifacts";
        ApprovalCountText = $"{messages.Count(row => row.MatchesCategory(ReaderTranscriptCategory.Approval))} approvals";
        SystemCountText = $"{CountFor(
            ReaderTranscriptCategory.System,
            messages,
            transientCounts.ProgressCount,
            transientCounts.SystemCount)} events";
        ComposerHintText = ComposerHint(composerMetadata, sandbox);
        TileWidth = tileWidth;
        TileHeight = tileHeight;
    }

    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Subtitle { get; set; } = "";

    public string ThreadKindText { get; set; } = "Thread";

    public string ThreadKindGlyph { get; set; } = "\uE8F2";

    public SolidColorBrush ThreadKindBrush { get; set; } = ReaderBrush("#A7B0BF");

    public SolidColorBrush ThreadKindBackgroundBrush { get; set; } = ReaderBrush(ThreadHeaderIconPresentation.ThreadKindBackgroundHex);

    public SolidColorBrush HeaderIconBrush { get; set; } = ReaderBrush("#0A84FF");

    public SolidColorBrush HeaderIconBackgroundBrush { get; set; } = ReaderBrush(ThreadHeaderIconPresentation.ThreadHeaderBackgroundHex);

    public string HeaderGlyph { get; set; } = ThreadHeaderIconPresentation.ThreadGlyph;

    public bool HeaderUsesThreadPairIcon { get; set; }

    public Visibility HeaderGlyphVisibility => HeaderUsesThreadPairIcon ? Visibility.Collapsed : Visibility.Visible;

    public Visibility HeaderThreadPairIconVisibility => HeaderUsesThreadPairIcon ? Visibility.Visible : Visibility.Collapsed;

    public double HeaderSurfaceSize { get; set; } = ThreadHeaderIconPresentation.HeaderSurfaceSize;

    public CornerRadius HeaderSurfaceCornerRadius { get; set; } = new(ThreadHeaderIconPresentation.HeaderSurfaceCornerRadius);

    public double HeaderIconGridWidth { get; set; } = ThreadHeaderIconPresentation.HeaderIconGridWidth;

    public double HeaderIconGridHeight { get; set; } = ThreadHeaderIconPresentation.HeaderIconGridHeight;

    public double HeaderGlyphFontSize { get; set; } = ThreadHeaderIconPresentation.HeaderGlyphFontSize;

    public double HeaderPairBackGlyphFontSize { get; set; } = ThreadHeaderIconPresentation.HeaderPairBackGlyphFontSize;

    public double HeaderPairFrontGlyphFontSize { get; set; } = ThreadHeaderIconPresentation.HeaderPairFrontGlyphFontSize;

    public double HeaderPairBackOpacity { get; set; } = ThreadHeaderIconPresentation.HeaderPairBackOpacity;

    public double HeaderColumnSpacing { get; set; } = ThreadPopoverShellPresentation.HeaderColumnSpacing;

    public double HeaderActionSpacing { get; set; } = ThreadPopoverShellPresentation.HeaderActionSpacing;

    public Thickness HeaderControlsMargin { get; set; } =
        new(ThreadPopoverShellPresentation.HeaderControlsLeftInset, 0, 0, 0);

    private static ThreadHeaderActionPresentationSnapshot HeaderActionPresentation =>
        ThreadHeaderActionPresentation.Resolve();

    public double HeaderActionButtonSize => HeaderActionPresentation.HitTargetSize;

    public double HeaderActionIconFontSize => HeaderActionPresentation.IconFontSize;

    public Thickness HeaderActionButtonBorderThickness =>
        new(HeaderActionPresentation.BorderThickness);

    public SolidColorBrush HeaderActionButtonBackgroundBrush =>
        ReaderBrush(HeaderActionPresentation.BackgroundHex);

    public SolidColorBrush HeaderActionForegroundBrush =>
        ReaderBrush(HeaderActionPresentation.ForegroundHex);

    public string RefreshButtonGlyph => HeaderActionPresentation.RefreshWindowsGlyph;

    public string RefreshButtonToolTip => HeaderActionPresentation.RefreshToolTip;

    public string RefreshButtonAccessibilityName => HeaderActionPresentation.RefreshAccessibilityName;

    public string CloseButtonGlyph => HeaderActionPresentation.CloseWindowsGlyph;

    public string CloseButtonToolTip => HeaderActionPresentation.CloseToolTip;

    public string CloseButtonAccessibilityName => HeaderActionPresentation.CloseAccessibilityName;

    private static ArtifactsActionPresentationSnapshot HeaderArtifactsPresentation =>
        ArtifactsActionPresentation.Resolve();

    public double ArtifactButtonIconSize => HeaderArtifactsPresentation.ActionIconSize;

    public double ArtifactButtonStrokeThickness => HeaderArtifactsPresentation.StrokeThickness;

    public SolidColorBrush ArtifactButtonForegroundBrush =>
        ReaderBrush(HeaderArtifactsPresentation.ActionForegroundHex);

    public string ThreadIDLabel { get; set; } = "";

    private static ThreadHeaderIdentityActionPresentationSnapshot HeaderIdentityPresentation =>
        ThreadHeaderIdentityActionPresentation.Resolve();

    public double RenameButtonSize => HeaderIdentityPresentation.RenameHitTargetSize;

    public double RenameButtonIconFontSize => HeaderIdentityPresentation.RenameIconFontSize;

    public string RenameButtonGlyph => HeaderIdentityPresentation.RenameWindowsGlyph;

    public string RenameButtonToolTip => HeaderIdentityPresentation.RenameToolTip;

    public string RenameButtonAccessibilityName => HeaderIdentityPresentation.RenameAccessibilityName;

    public double CopyThreadIdButtonSize => HeaderIdentityPresentation.CopyHitTargetSize;

    public double CopyThreadIdButtonIconFontSize => HeaderIdentityPresentation.CopyIconFontSize;

    public string CopyThreadIdButtonGlyph => HeaderIdentityPresentation.CopyWindowsGlyph;

    public string CopyThreadIdButtonToolTip => HeaderIdentityPresentation.CopyToolTip;

    public string CopyThreadIdButtonAccessibilityName => HeaderIdentityPresentation.CopyAccessibilityName;

    public Thickness IdentityActionButtonBorderThickness =>
        new(HeaderIdentityPresentation.BorderThickness);

    public SolidColorBrush IdentityActionButtonBackgroundBrush =>
        ReaderBrush(HeaderIdentityPresentation.BackgroundHex);

    public SolidColorBrush RenameButtonForegroundBrush =>
        ReaderBrush(HeaderIdentityPresentation.RenameForegroundHex);

    public SolidColorBrush CopyThreadIdButtonForegroundBrush =>
        ReaderBrush(HeaderIdentityPresentation.CopyForegroundHex);

    private static ThreadComposerAttachmentToolbarPresentationSnapshot AttachmentToolbarPresentation =>
        ThreadComposerAttachmentToolbarPresentation.Resolve();

    public double AttachmentToolbarSpacing => AttachmentToolbarPresentation.ToolbarSpacing;

    public double AttachmentToolbarButtonSize => AttachmentToolbarPresentation.ButtonSize;

    public double AttachmentToolbarIconFontSize => AttachmentToolbarPresentation.IconFontSize;

    public Thickness AttachmentToolbarButtonBorderThickness =>
        new(AttachmentToolbarPresentation.BorderThickness);

    public SolidColorBrush AttachmentToolbarButtonBackgroundBrush =>
        ReaderBrush(AttachmentToolbarPresentation.BackgroundHex);

    public SolidColorBrush AttachmentToolbarForegroundBrush =>
        ReaderBrush(AttachmentToolbarPresentation.ForegroundHex);

    public double AttachmentToolbarCountFontSize => AttachmentToolbarPresentation.CountFontSize;

    public SolidColorBrush AttachmentToolbarCountForegroundBrush =>
        ReaderBrush(AttachmentToolbarPresentation.CountForegroundHex);

    public string AttachButtonGlyph => AttachmentToolbarPresentation.AttachWindowsGlyph;

    public string AttachButtonToolTip => AttachmentToolbarPresentation.AttachToolTip;

    public string AttachButtonAccessibilityName => AttachmentToolbarPresentation.AttachAccessibilityName;

    public string PasteButtonGlyph => AttachmentToolbarPresentation.PasteWindowsGlyph;

    public string PasteButtonToolTip => AttachmentToolbarPresentation.PasteToolTip;

    public string PasteButtonAccessibilityName => AttachmentToolbarPresentation.PasteAccessibilityName;

    public string LiveStateGlyph { get; set; } = "\uE823";

    public string LiveStateText { get; set; } = "Idle";

    public SolidColorBrush LiveStateBrush { get; set; } =
        ReaderBrush(ThreadLiveStatePresentation.SecondaryHex);

    public string Model { get; set; } = "";

    public string Effort { get; set; } = "";

    public Visibility ComposerMetadataVisibility { get; set; } = Visibility.Collapsed;

    public Visibility ModelChipVisibility { get; set; } = Visibility.Collapsed;

    public Visibility EffortChipVisibility { get; set; } = Visibility.Collapsed;

    public string Approval { get; set; } = "";

    public string Sandbox { get; set; } = "";

    public string StatusText { get; set; } = "";

    public string StatusGlyph { get; set; } = "\uEA3A";

    public SolidColorBrush StatusForegroundBrush { get; set; } = ReaderBrush("#A7B0BF");

    public SolidColorBrush StatusBackgroundBrush { get; set; } = ReaderBrush("#1CA7B0BF");

    public SolidColorBrush StatusBorderBrush { get; set; } = ReaderBrush(ThreadStatusPresentation.BorderlessHex);

    public Thickness StatusPillBorderThickness { get; set; } = new(ThreadStatusPresentation.PillBorderThickness);

    public Thickness StatusPillPadding { get; set; } = new(
        ThreadStatusPresentation.PillHorizontalPadding,
        ThreadStatusPresentation.PillVerticalPadding,
        ThreadStatusPresentation.PillHorizontalPadding,
        ThreadStatusPresentation.PillVerticalPadding);

    public CornerRadius StatusPillCornerRadius { get; set; } = new(ThreadStatusPresentation.PillCornerRadius);

    public double StatusPillMinWidth { get; set; } = ThreadStatusPresentation.PillMinWidth;

    public double StatusIconFontSize { get; set; } = ThreadStatusPresentation.PillIconFontSize;

    public double StatusTextFontSize { get; set; } = ThreadStatusPresentation.PillTextFontSize;

    public bool CanStopTurn { get; set; }

    public bool StopButtonIsEnabled { get; set; }

    public Visibility StopButtonVisibility { get; set; } = Visibility.Collapsed;

    public double StopButtonOpacity { get; set; } = StopTurnActionPresentation.AvailableOpacity;

    public string StopButtonTooltip { get; set; } = StopTurnActionPresentation.ToolTip;

    public string StopButtonAccessibilityName { get; set; } = StopTurnActionPresentation.AccessibilityName;

    public string StopButtonAccessibilityHint { get; set; } = "";

    public string StopButtonGlyph { get; set; } = StopTurnActionPresentation.WindowsGlyph;

    public SolidColorBrush StopButtonForegroundBrush { get; set; } = ReaderBrush(StopTurnActionPresentation.ForegroundHex);

    public SolidColorBrush StopButtonBackgroundBrush { get; set; } = ReaderBrush(StopTurnActionPresentation.BackgroundHex);

    public SolidColorBrush StopButtonBorderBrush { get; set; } = ReaderBrush(StopTurnActionPresentation.BorderHex);

    public bool IsComposerEnabled { get; set; } = true;

    public string SendButtonGlyph { get; set; } = ThreadSendActionPresentation.WindowsGlyph;

    public string SendButtonTooltip => SendAvailability.UnavailableReason ?? ThreadSendActionPresentation.ToolTip;

    public double SendButtonOpacity => SendAvailability.Opacity;

    public string SendButtonAccessibilityHint => SendAvailability.UnavailableReason ?? "";

    public bool HasArtifacts { get; set; }

    public string ArtifactButtonTooltip { get; set; } = ArtifactsActionPresentation.UnavailableReason;

    public double ArtifactButtonOpacity { get; set; } = ArtifactsActionPresentation.UnavailableOpacity;

    public string ArtifactButtonAccessibilityHint { get; set; } = ArtifactsActionPresentation.UnavailableReason;

    public ObservableCollection<ComposerAttachmentItem> PendingAttachments { get; set; } = [];

    public string PendingAttachmentSummaryText =>
        ThreadAttachmentFeedbackPresentation.CountText(PendingAttachments.Count);

    public Visibility PendingAttachmentSummaryVisibility =>
        string.IsNullOrWhiteSpace(PendingAttachmentSummaryText) ? Visibility.Collapsed : Visibility.Visible;

    public bool IsTranscriptLoading { get; set; }

    public bool IsTranscriptLoadingOlder { get; set; }

    public Visibility TranscriptLoadingVisibility { get; set; } = Visibility.Collapsed;

    public string TranscriptLoadingGlyph { get; set; } = TranscriptLoadPhasePresentation.LoadingHistoryGlyph;

    public string TranscriptLoadingTitle { get; set; } = "Loading message history";

    public string TranscriptLoadingDetail { get; set; } = "Waiting on thread history from Codex App Server.";

    public Thickness TranscriptLoadingPadding { get; set; } =
        new(TranscriptLoadingRowPresentation.RegularPadding);

    public Thickness TranscriptLoadingMargin { get; set; } =
        new(0, TranscriptLoadingRowPresentation.InitialVerticalMargin, 0, TranscriptLoadingRowPresentation.InitialVerticalMargin);

    public HorizontalAlignment TranscriptLoadingHorizontalAlignment { get; set; } = HorizontalAlignment.Center;

    public SolidColorBrush TranscriptLoadingBackgroundBrush { get; set; } =
        ReaderBrush(TranscriptLoadingRowPresentation.RegularBackgroundHex);

    public SolidColorBrush TranscriptLoadingBorderBrush { get; set; } =
        ReaderBrush(TranscriptLoadingRowPresentation.RegularBorderHex);

    private TranscriptLoadingRowPresentationSnapshot TranscriptLoadingPresentation =>
        TranscriptLoadingRowPresentation.Resolve(TranscriptLoadingHorizontalAlignment != HorizontalAlignment.Center);

    public double TranscriptLoadingOuterColumnSpacing =>
        TranscriptLoadingPresentation.OuterColumnSpacing;

    public double TranscriptLoadingProgressRingSize =>
        TranscriptLoadingPresentation.ProgressRingSize;

    public Thickness TranscriptLoadingProgressRingMargin =>
        new(0, TranscriptLoadingPresentation.ProgressRingTopMargin, 0, 0);

    public double TranscriptLoadingContentSpacing =>
        TranscriptLoadingPresentation.ContentSpacing;

    public double TranscriptLoadingHeaderSpacing =>
        TranscriptLoadingPresentation.HeaderSpacing;

    public double TranscriptLoadingLabelIconFontSize =>
        TranscriptLoadingPresentation.LabelIconFontSize;

    public double TranscriptLoadingTitleFontSize =>
        TranscriptLoadingPresentation.TitleFontSize;

    public double TranscriptLoadingDetailFontSize =>
        TranscriptLoadingPresentation.DetailFontSize;

    public int TranscriptLoadingDetailMaxLines =>
        TranscriptLoadingPresentation.DetailMaxLines;

    public Visibility LoadOlderButtonVisibility { get; set; } = Visibility.Collapsed;

    public bool IsLoadOlderEnabled { get; set; }

    public double LoadOlderButtonOpacity { get; set; } = LoadOlderMessagesActionPresentation.AvailableOpacity;

    public string LoadOlderButtonTooltip { get; set; } = LoadOlderMessagesActionPresentation.ToolTip;

    public string LoadOlderAccessibilityHint { get; set; } = "";

    public double LoadOlderButtonMinHeight => LoadOlderMessagesActionPresentation.ButtonMinHeight;

    public Thickness LoadOlderButtonPadding => new(
        LoadOlderMessagesActionPresentation.ButtonHorizontalPadding,
        LoadOlderMessagesActionPresentation.ButtonVerticalPadding,
        LoadOlderMessagesActionPresentation.ButtonHorizontalPadding,
        LoadOlderMessagesActionPresentation.ButtonVerticalPadding);

    public double LoadOlderContentSpacing => LoadOlderMessagesActionPresentation.ContentSpacing;

    public double LoadOlderProgressRingSize => LoadOlderMessagesActionPresentation.ProgressRingSize;

    public double LoadOlderIdleIconFontSize => LoadOlderMessagesActionPresentation.IdleIconFontSize;

    public double LoadOlderTextFontSize => LoadOlderMessagesActionPresentation.TextFontSize;

    public Visibility LoadOlderProgressVisibility { get; set; } = Visibility.Collapsed;

    public Visibility LoadOlderIconVisibility { get; set; } = Visibility.Collapsed;

    public string LoadOlderButtonText { get; set; } = "Show older messages";

    public Visibility TranscriptErrorVisibility { get; set; } = Visibility.Collapsed;

    public string TranscriptErrorText { get; set; } = "";

    public Visibility UseCachedTranscriptVisibility { get; set; } = Visibility.Collapsed;

    private static TranscriptErrorPresentationSnapshot ErrorPresentation =>
        TranscriptErrorPresentation.Resolve();

    public string TranscriptErrorGlyph => ErrorPresentation.WindowsGlyph;

    public string TranscriptErrorTitle => ErrorPresentation.Title;

    public string TranscriptErrorRetryLabel => ErrorPresentation.RetryLabel;

    public string TranscriptErrorUseCachedLabel => ErrorPresentation.UseCachedLabel;

    public Thickness TranscriptErrorPadding => new(ErrorPresentation.Padding);

    public CornerRadius TranscriptErrorCornerRadius => new(ErrorPresentation.CornerRadius);

    public Thickness TranscriptErrorBorderThickness => new(ErrorPresentation.BorderThickness);

    public double TranscriptErrorContentSpacing => ErrorPresentation.ContentSpacing;

    public double TranscriptErrorHeaderColumnSpacing => ErrorPresentation.HeaderColumnSpacing;

    public double TranscriptErrorTextStackSpacing => ErrorPresentation.TextStackSpacing;

    public double TranscriptErrorActionSpacing => ErrorPresentation.ActionSpacing;

    public Thickness TranscriptErrorIconMargin => new(0, ErrorPresentation.IconTopMargin, 0, 0);

    public double TranscriptErrorIconFontSize => ErrorPresentation.IconFontSize;

    public double TranscriptErrorTitleFontSize => ErrorPresentation.TitleFontSize;

    public double TranscriptErrorDetailFontSize => ErrorPresentation.DetailFontSize;

    public Thickness TranscriptErrorButtonPadding => new(
        ErrorPresentation.ButtonHorizontalPadding,
        ErrorPresentation.ButtonVerticalPadding,
        ErrorPresentation.ButtonHorizontalPadding,
        ErrorPresentation.ButtonVerticalPadding);

    public double TranscriptErrorButtonFontSize => ErrorPresentation.ButtonFontSize;

    public int TranscriptErrorDetailMaxLines => ErrorPresentation.DetailMaxLines;

    public SolidColorBrush TranscriptErrorBackgroundBrush => ReaderBrush(ErrorPresentation.BackgroundHex);

    public SolidColorBrush TranscriptErrorBorderBrush => ReaderBrush(ErrorPresentation.BorderHex);

    public SolidColorBrush TranscriptErrorIconBrush => ReaderBrush(ErrorPresentation.IconForegroundHex);

    public SolidColorBrush TranscriptErrorTitleBrush => ReaderBrush(ErrorPresentation.TitleForegroundHex);

    public SolidColorBrush TranscriptErrorDetailBrush => ReaderBrush(ErrorPresentation.DetailForegroundHex);

    public List<ReaderTranscriptRow> Messages { get; set; } = [];

    public Visibility FilteredEmptyVisibility { get; set; } = Visibility.Collapsed;

    private static TranscriptFilterPresentationSnapshot FilterPresentation =>
        TranscriptFilterPresentation.Resolve();

    private static TranscriptFilteredEmptyStatePresentationSnapshot FilteredEmptyPresentation =>
        TranscriptFilteredEmptyStatePresentation.Resolve();

    public Thickness FilterBarPadding => new(
        FilterPresentation.BarHorizontalPadding,
        FilterPresentation.BarVerticalPadding,
        FilterPresentation.BarHorizontalPadding,
        FilterPresentation.BarVerticalPadding);

    public double FilterBarColumnSpacing => FilterPresentation.BarColumnSpacing;

    public Thickness FilterButtonPadding => new(
        FilterPresentation.ButtonHorizontalPadding,
        FilterPresentation.ButtonVerticalPadding,
        FilterPresentation.ButtonHorizontalPadding,
        FilterPresentation.ButtonVerticalPadding);

    public CornerRadius FilterButtonCornerRadius => new(FilterPresentation.ButtonCornerRadius);

    public double FilterButtonContentSpacing => FilterPresentation.ButtonContentSpacing;

    public double FilterSummaryFontSize => FilterPresentation.SummaryFontSize;

    public double FilterDetailFontSize => FilterPresentation.DetailFontSize;

    public double FilterResetButtonSize => FilterPresentation.ResetButtonSize;

    public double FilterResetIconFontSize => FilterPresentation.ResetIconFontSize;

    public Thickness FilteredEmptyMargin => new(0);

    public Thickness FilteredEmptyPadding => new(FilteredEmptyPresentation.Padding);

    public CornerRadius FilteredEmptyCornerRadius => new(FilteredEmptyPresentation.CornerRadius);

    public Thickness FilteredEmptyBorderThickness => new(FilteredEmptyPresentation.BorderThickness);

    public SolidColorBrush FilteredEmptyBackgroundBrush =>
        ReaderBrush(FilteredEmptyPresentation.BackgroundHex);

    public SolidColorBrush FilteredEmptyBorderBrush =>
        ReaderBrush(FilteredEmptyPresentation.BorderHex);

    public SolidColorBrush FilteredEmptyForegroundBrush =>
        ReaderBrush(FilteredEmptyPresentation.ForegroundHex);

    public double FilteredEmptyContentSpacing => FilteredEmptyPresentation.ContentSpacing;

    public double FilteredEmptyIconSize => FilteredEmptyPresentation.IconSize;

    public string FilteredEmptyTitle => FilteredEmptyPresentation.Title;

    public double FilteredEmptyTitleFontSize => FilteredEmptyPresentation.TitleFontSize;

    public Thickness FilteredEmptyResetButtonPadding => new(
        FilteredEmptyPresentation.ButtonHorizontalPadding,
        FilteredEmptyPresentation.ButtonVerticalPadding,
        FilteredEmptyPresentation.ButtonHorizontalPadding,
        FilteredEmptyPresentation.ButtonVerticalPadding);

    public double FilteredEmptyResetButtonContentSpacing =>
        FilteredEmptyPresentation.ButtonContentSpacing;

    public string FilteredEmptyResetButtonGlyph =>
        FilteredEmptyPresentation.ButtonWindowsGlyph;

    public double FilteredEmptyResetButtonIconFontSize =>
        FilteredEmptyPresentation.ButtonIconFontSize;

    public string FilteredEmptyResetButtonText =>
        FilteredEmptyPresentation.ButtonText;

    public double FilteredEmptyResetButtonTextFontSize =>
        FilteredEmptyPresentation.ButtonTextFontSize;

    public List<ReaderTranscriptFilterItem> Filters { get; set; } = [];

    public string FilterSummaryText { get; set; } = "All rows";

    public string FilterDetailText { get; set; } = "Messages, progress, thoughts, tools, artifacts, approvals, events";

    public SolidColorBrush FilterDetailBrush { get; set; } =
        ReaderBrush(TranscriptFilterPresentation.DetailForegroundHex(isShowingAllRows: true));

    public Visibility ResetFiltersVisibility { get; set; } = Visibility.Collapsed;

    public string MessageFilterMenuText { get; set; } = "Messages (0)";

    public string ProgressFilterMenuText { get; set; } = "Progress (0)";

    public string ThoughtFilterMenuText { get; set; } = "Thoughts (0)";

    public string ToolFilterMenuText { get; set; } = "Tools (0)";

    public string ArtifactFilterMenuText { get; set; } = "Artifacts (0)";

    public string ApprovalFilterMenuText { get; set; } = "Approvals (0)";

    public string SystemFilterMenuText { get; set; } = "System (0)";

    public bool IsMessageFilterActive { get; set; } = true;

    public bool IsProgressFilterActive { get; set; } = true;

    public bool IsThoughtFilterActive { get; set; } = true;

    public bool IsToolFilterActive { get; set; } = true;

    public bool IsArtifactFilterActive { get; set; } = true;

    public bool IsApprovalFilterActive { get; set; } = true;

    public bool IsSystemFilterActive { get; set; } = true;

    public string MessageCountText { get; set; } = "0 messages";

    public string ProgressCountText { get; set; } = "0 progress";

    public string ThoughtCountText { get; set; } = "0 thoughts";

    public string ToolCountText { get; set; } = "0 tools";

    public string ArtifactCountText { get; set; } = "0 artifacts";

    public string ApprovalCountText { get; set; } = "0 approvals";

    public string SystemCountText { get; set; } = "0 events";

    public string ComposerHintText { get; set; } = "";

    public Visibility AttachmentErrorVisibility => string.IsNullOrWhiteSpace(AttachmentErrorText)
        ? Visibility.Collapsed
        : Visibility.Visible;

    public string AttachmentErrorText
    {
        get => _attachmentErrorText;
        set
        {
            var next = string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
            if (string.Equals(_attachmentErrorText, next, StringComparison.Ordinal))
            {
                return;
            }

            _attachmentErrorText = next;
            OnPropertyChanged(nameof(AttachmentErrorText));
            OnPropertyChanged(nameof(AttachmentErrorVisibility));
        }
    }

    public ObservableCollection<MentionSuggestionItem> MentionSuggestions { get; set; } = [];

    public Visibility MentionPanelVisibility
    {
        get => _mentionPanelVisibility;
        set
        {
            if (_mentionPanelVisibility == value)
            {
                return;
            }

            _mentionPanelVisibility = value;
            OnPropertyChanged(nameof(MentionPanelVisibility));
        }
    }

    public string DraftText
    {
        get => _draftText;
        set
        {
            if (string.Equals(_draftText, value, StringComparison.Ordinal))
            {
                return;
            }

            _draftText = value;
            OnPropertyChanged(nameof(DraftText));
            NotifySendActionChanged();
        }
    }

    public double TileWidth
    {
        get => _tileWidth;
        set
        {
            if (Math.Abs(_tileWidth - value) < 0.5)
            {
                return;
            }

            _tileWidth = value;
            OnPropertyChanged(nameof(TileWidth));
        }
    }

    public double TileHeight
    {
        get => _tileHeight;
        set
        {
            if (Math.Abs(_tileHeight - value) < 0.5)
            {
                return;
            }

            _tileHeight = value;
            OnPropertyChanged(nameof(TileHeight));
        }
    }

    private static ThreadPopoverShellPresentationSnapshot ShellPresentation =>
        ThreadPopoverShellPresentation.ResolveReaderTile();

    public SolidColorBrush ShellBorderBrush => ReaderBrush(ShellPresentation.BorderHex);

    public Thickness ShellBorderThickness => new(ShellPresentation.BorderThickness);

    public CornerRadius ShellCornerRadius => new(ShellPresentation.CornerRadius);

    public Vector3 ShellTranslation => new(0, 0, (float)ShellPresentation.ShadowTranslationZ);

    private void OnPropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private ThreadSendActionAvailability SendAvailability =>
        ThreadSendActionPresentation.Availability(
            isAwaitingResponse: !IsComposerEnabled,
            isSubmitting: false,
            draft: DraftText,
            pendingAttachmentCount: PendingAttachments.Count);

    private void NotifySendActionChanged()
    {
        OnPropertyChanged(nameof(SendButtonTooltip));
        OnPropertyChanged(nameof(SendButtonOpacity));
        OnPropertyChanged(nameof(SendButtonAccessibilityHint));
        OnPropertyChanged(nameof(PendingAttachmentSummaryText));
        OnPropertyChanged(nameof(PendingAttachmentSummaryVisibility));
    }

    private static ReaderTranscriptCategory[] OrderedTranscriptCategories()
    {
        return
        [
            ReaderTranscriptCategory.Message,
            ReaderTranscriptCategory.Progress,
            ReaderTranscriptCategory.Thought,
            ReaderTranscriptCategory.Tool,
            ReaderTranscriptCategory.Artifact,
            ReaderTranscriptCategory.Approval,
            ReaderTranscriptCategory.System
        ];
    }

    private static string MenuTitleFor(
        ReaderTranscriptCategory category,
        IReadOnlyList<ReaderTranscriptRow> rows,
        int additionalProgressCount = 0,
        int additionalSystemCount = 0)
    {
        return $"{TitleFor(category)} ({CountFor(category, rows, additionalProgressCount, additionalSystemCount)})";
    }

    private static int CountFor(
        ReaderTranscriptCategory category,
        IReadOnlyList<ReaderTranscriptRow> rows,
        int additionalProgressCount = 0,
        int additionalSystemCount = 0)
    {
        var count = rows.Count(row => row.MatchesCategory(category));
        if (category == ReaderTranscriptCategory.Progress)
        {
            count += additionalProgressCount;
        }
        else if (category == ReaderTranscriptCategory.System)
        {
            count += additionalSystemCount;
        }

        return count;
    }

    private static string ComposerHint(
        ThreadComposerMetadataPresentationSnapshot metadata,
        string sandbox)
    {
        var parts = new List<string>();
        if (metadata.ShowsModel)
        {
            parts.Add(metadata.ModelText);
        }

        if (metadata.ShowsEffort)
        {
            parts.Add(metadata.EffortText);
        }

        if (!string.IsNullOrWhiteSpace(sandbox))
        {
            parts.Add(sandbox.Trim());
        }

        return string.Join(" / ", parts);
    }

    private static string TitleFor(ReaderTranscriptCategory category)
    {
        return TranscriptCategoryPresentation.Resolve(CategoryKeyFor(category)).Title;
    }

    private static string CompactTitleFor(ReaderTranscriptCategory category)
    {
        return TranscriptCategoryPresentation.Resolve(CategoryKeyFor(category)).CompactTitle;
    }

    private static string CategoryKeyFor(ReaderTranscriptCategory category)
    {
        return category switch
        {
            ReaderTranscriptCategory.Message => TranscriptCategoryPresentation.KeyMessages,
            ReaderTranscriptCategory.Progress => TranscriptCategoryPresentation.KeyProgress,
            ReaderTranscriptCategory.Thought => TranscriptCategoryPresentation.KeyThoughts,
            ReaderTranscriptCategory.Tool => TranscriptCategoryPresentation.KeyTools,
            ReaderTranscriptCategory.Artifact => TranscriptCategoryPresentation.KeyArtifacts,
            ReaderTranscriptCategory.Approval => TranscriptCategoryPresentation.KeyApprovals,
            _ => TranscriptCategoryPresentation.KeySystem
        };
    }

    private static SolidColorBrush ReaderBrush(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], System.Globalization.NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], System.Globalization.NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], System.Globalization.NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], System.Globalization.NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Gray);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }

    private static HorizontalAlignment LoadingRowHorizontalAlignment(
        TranscriptLoadingRowPresentationSnapshot presentation)
    {
        return presentation.HorizontalAlignment == TranscriptLoadingRowPresentation.CenterAlignment
            ? HorizontalAlignment.Center
            : HorizontalAlignment.Left;
    }
}
