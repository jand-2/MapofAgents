using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using MapofAgents.Core;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Web.WebView2.Core;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Graphics;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace MapofAgents.WindowsApp;

public sealed partial class MainWindow : Window
{
    private const string ThreadInboxModeActive = "active";
    private const string ThreadInboxModeFinished = "finished";
    private const string ThreadInboxModeNeedsYou = "needsYou";
    private const string ThreadInboxModeUnread = "unread";
    private const string ThreadInboxModeRecent = "recent";
    private const string ThreadInboxModeSearch = "search";
    private const string ThreadInboxModeArchived = "archived";
    private const string WorkflowFilterAll = "all";
    private const string WorkflowFilterOnWorkflows = "on-workflows";
    private const string WorkflowFilterNotOnWorkflows = "not-on-workflows";
    private const string WorkflowFilterThisWorkflow = "this-workflow";
    private const string WorkflowFilterWorkflowPrefix = "workflow::";
    private const string ActivityNotificationKindGeneral = "general";
    private const string ActivityNotificationKindCompleted = "completed";
    private const string ActivityNotificationKindNeedsInput = "needsInput";
    private const string ActivityNotificationKindFailed = "failed";
    private const int GwlWndProc = -4;
    private const uint WmGetMinMaxInfo = 0x0024;
    private const double ChromeMargin = 14;
    private const int MachineHealthRefreshMinimumChromeMilliseconds = 800;

    private enum RemoteFolderPickerMode
    {
        ChooseProject,
        ShowContents
    }

    private readonly ControlRoomStore _store = new();
    private readonly AppPreferencesStore _preferencesStore = new();
    private readonly CodexAutomationStore _automationStore = new();
    private readonly AppServerConnectionController _appServerConnectionController = new();
    private readonly WorkflowHookEventFileBridge _workflowHookEventFileBridge = new(
        defaultHostID: LocalHostIdentity.CanonicalHostID);
    private readonly ObservableCollection<ActivityEntry> _activity = [];
    private readonly ObservableCollection<NodeChoice> _folderChoices = [];
    private readonly ObservableCollection<NodeChoice> _machineChoices = [];
    private readonly ObservableCollection<NodeChoice> _readerCandidates = [];
    private readonly ObservableCollection<ReaderThreadItem> _readerThreads = [];
    private readonly ObservableCollection<ThreadArtifactItem> _threadArtifactItems = [];
    private readonly ObservableCollection<ArtifactDiffLineItem> _artifactPreviewDiffLines = [];
    private readonly ObservableCollection<ComposerAttachmentItem> _threadPopoverPendingAttachments = [];
    private readonly ObservableCollection<ReaderTranscriptFilterItem> _threadPopoverFilters = [];
    private readonly ObservableCollection<ReaderTranscriptRow> _threadPopoverMessages = [];
    private readonly ObservableCollection<ThreadAttentionItem> _threadAttentionItems = [];
    private readonly ObservableCollection<ThreadInboxItem> _threadInboxItems = [];
    private readonly ObservableCollection<ThreadInboxWorkflowFilterItem> _threadInboxWorkflowFilters = [];
    private readonly ObservableCollection<WorkflowMenuItem> _workflowMenuItems = [];
    private readonly ObservableCollection<TopNotificationItem> _topNotifications = [];
    private readonly ObservableCollection<TopNotificationItem> _topNotificationHistory = [];
    private readonly ObservableCollection<MachineHealthItem> _machineHealthItems = [];
    private readonly ObservableCollection<RemoteDiscoveryItem> _codexRemoteItems = [];
    private readonly ObservableCollection<RemoteDiscoveryItem> _tailnetMachineItems = [];
    private readonly ObservableCollection<EdgeRouteItem> _selectionRouteItems = [];
    private readonly ObservableCollection<PairingEndpointPreviewItem> _pairingEndpointPreviewItems = [];
    private readonly ObservableCollection<PairingEndpointPreviewItem> _generatedPairingEndpointItems = [];
    private readonly ObservableCollection<MachineRecoveryItem> _machineRecoveryItems = [];
    private readonly ObservableCollection<RuntimeDiagnosticItem> _runtimeDiagnosticItems = [];
    private readonly ObservableCollection<CodexModelOption> _newThreadModelOptions = [];
    private readonly ObservableCollection<string> _newThreadEffortOptions = [];
    private readonly ObservableCollection<MentionSuggestionItem> _newThreadMentionSuggestions = [];
    private readonly ObservableCollection<MentionSuggestionItem> _threadPopoverMentionSuggestions = [];
    private readonly HashSet<TextBox> _composerDraftBoxesWithKeyHandler = [];
    private readonly List<string> _readerThreadIds = [];
    private readonly TranscriptSessionStore _transcriptSessions = new();
    private readonly ArtifactCatalog<ThreadArtifactItem> _artifactCatalog = new(
        item => item.Id,
        item => item.KindKey);
    private readonly List<CodexDesktopRemote> _discoveredCodexRemotes = [];
    private readonly List<TailnetMachine> _discoveredTailnetMachines = [];
    private readonly Dictionary<string, ObservableCollection<ComposerAttachmentItem>> _readerPendingAttachments = [];
    private readonly Dictionary<string, HashSet<ReaderTranscriptCategory>> _readerTranscriptFilters = [];
    private readonly Dictionary<string, List<ThreadWorkflowMembership>> _threadWorkflowMembershipsByThreadId = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ThreadInboxCatalogThread> _threadInboxCatalogThreadsByKey = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ThreadInboxCatalogThread> _threadInboxServerCatalogThreadsByKey = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ThreadInboxCatalogThread> _threadInboxCatalogThreadsByItemId = new(StringComparer.OrdinalIgnoreCase);
    private IReadOnlyDictionary<string, CodexAutomationSummary> _threadAutomationsByThreadId =
        new Dictionary<string, CodexAutomationSummary>(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, AppServerEndpoint> _connectedAppServerEndpointsByHostId = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<CodexModelOption>> _newThreadModelsByHostId = new(StringComparer.OrdinalIgnoreCase);
    private readonly MentionCatalogSession _mentionCatalogSession = new();
    private readonly MentionSelectionController _newThreadMentionSelection = new();
    private readonly MentionSelectionController _threadPopoverMentionSelection = new();
    private readonly Dictionary<string, MentionSelectionController> _readerMentionSelections = new(StringComparer.Ordinal);
    private readonly WindowLifetimeCoordinator _windowLifetime = new();
    private readonly Dictionary<string, CodexRemoteTunnel> _codexRemoteTunnels = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<RuntimeDiagnosticStep>> _codexRemoteDiagnostics = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<ReaderTranscriptCategory> _threadPopoverTranscriptFilters = [];
    private readonly HashSet<string> _expandedTranscriptRows = new(StringComparer.Ordinal);
    private readonly HashSet<string> _stoppingThreadKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _codexRemoteOperationIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _ingestedWorkflowHookEventKeys = new(StringComparer.Ordinal);
    private AgentGraph _graph = new();
    private AppPreferences _preferences = new();
    private bool _webViewReady;
    private bool _graphDocumentReady;
    private bool _isMachinesRailVisible;
    private bool _isMachinesRailCollapsed;
    private bool _isActivityRailCollapsed;
    private bool _isActivityHistoryVisible;
    private bool _notifyOnCompleted;
    private bool _notifyOnNeedsInput = true;
    private bool _notifyOnFailed = true;
    private bool _isReadingModePresented;
    private bool _isMachineRecoveryVisible;
    private bool _isMachineConnectFormVisible;
    private bool _isCodexRemotesCollapsed;
    private bool _isTailnetCollapsed;
    private string? _expandedMachineHealthItemId;
    private bool _isThreadInboxSearchVisible;
    private bool _isThreadInboxCollapsed;
    private bool _isAttentionRailCollapsed;
    private bool _isRuntimeDiagnosticsCollapsed;
    private bool _isCreatingNewThread;
    private bool _isViewInitialized;
    private bool _isUpdatingThreadInboxWorkflowFilters;
    private bool _isRefreshingAppServerInbox;
    private bool _isRefreshingMachineHealth;
    private bool _isDiscoveringCodexRemotes;
    private bool _isDiscoveringTailnet;
    private bool _hasRequestedInitialMachineDiscovery;
    private bool _showsSubagents = true;
    private bool _isSyncingSelectionFields;
    private string? _statusStripErrorMessage;
    private string? _threadInboxWarningMessage;
    private string _localRuntimeStatus = HostStatuses.Disconnected;
    private string _localRuntimeMessage = "Not connected";
    private string _localRuntimeDetail = "Not connected";
    private string? _codexRemoteDiscoveryMessage;
    private string? _tailnetDiscoveryMessage;
    private string _newThreadTargetKind = NodeKinds.Folder;
    private int _commandFeedbackToken;
    private WorkflowNameEditorMode? _workflowNameEditorMode;
    private ItemsWrapGrid? _readerItemsPanel;
    private string _threadInboxMode = ThreadInboxModeActive;
    private string _threadInboxWorkflowFilter = WorkflowFilterAll;
    private string _lastDiagnosticsSummary = "No diagnostics run yet.";
    private string _lastDiagnosticsDetail = "Refresh machines or run diagnostics to update this report.";
    private string? _selectedNodeId;
    private int _threadInboxSearchGeneration;
    private string? _selectedEdgeId;
    private string? _pendingLinkSourceNodeId;
    private string? _threadPopoverNodeId;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _threadAutomationRefreshTimer;
    private string? _importedPairingEndpointUrl;
    private string? _importedPairingBearerToken;
    private string? _hoveredInboxNodeId;
    private string? _activeReaderFilterThreadId;
    private bool _isDraggingThreadPopover;
    private bool _isThreadPopoverRenaming;
    private bool _isApplyingNewThreadMention;
    private bool _isApplyingThreadPopoverMention;
    private bool _isApplyingReaderMention;
    private bool _isUpdatingPairingCode;
    private string? _draggingThreadPopoverNodeId;
    private string? _threadPopoverAttachmentError;
    private Point _threadPopoverDragStart;
    private Thickness _threadPopoverDragStartMargin;
    private bool _isUpdatingNewThreadModelChoices;
    private Flyout? _machinesFlyout;
    private bool _isMachinesFlyoutOpen;
    private bool _isSettingUpLocalMachine;
    private string? _lastLocalSetupDetail;
    private IntPtr _windowHandle;
    private IntPtr _originalWindowProc;
    private WndProcDelegate? _minimumSizeWindowProc;
    private CancellationTokenSource? _newThreadModelRefreshCancellation;
    private CancellationTokenSource? _workflowHookEventBridgeCancellation;
    private Task? _workflowHookEventBridgeTask;
    private Task? _threadAutomationRefreshTask;
    private bool _threadAutomationRenderRequested;
    private bool _windowStoresDisposed;

    public ObservableCollection<ReaderThreadItem> ReaderThreads => _readerThreads;

    public ObservableCollection<ThreadArtifactItem> ThreadArtifactItems => _threadArtifactItems;

    public ObservableCollection<ArtifactDiffLineItem> ArtifactPreviewDiffLines => _artifactPreviewDiffLines;

    public ObservableCollection<ComposerAttachmentItem> ThreadPopoverPendingAttachments => _threadPopoverPendingAttachments;

    public ObservableCollection<ReaderTranscriptFilterItem> ThreadPopoverFilters => _threadPopoverFilters;

    public ObservableCollection<ReaderTranscriptRow> ThreadPopoverMessages => _threadPopoverMessages;

    public ObservableCollection<ThreadAttentionItem> ThreadAttentionItems => _threadAttentionItems;

    public ObservableCollection<ThreadInboxItem> ThreadInboxItems => _threadInboxItems;

    public ObservableCollection<ThreadInboxWorkflowFilterItem> ThreadInboxWorkflowFilters => _threadInboxWorkflowFilters;

    public ObservableCollection<WorkflowMenuItem> WorkflowMenuItems => _workflowMenuItems;

    public ObservableCollection<MachineHealthItem> MachineHealthItems => _machineHealthItems;

    public ObservableCollection<RemoteDiscoveryItem> CodexRemoteItems => _codexRemoteItems;

    public ObservableCollection<RemoteDiscoveryItem> TailnetMachineItems => _tailnetMachineItems;

    public ObservableCollection<EdgeRouteItem> SelectionRouteItems => _selectionRouteItems;

    public ObservableCollection<PairingEndpointPreviewItem> PairingEndpointPreviewItems => _pairingEndpointPreviewItems;

    public ObservableCollection<PairingEndpointPreviewItem> GeneratedPairingEndpointItems => _generatedPairingEndpointItems;

    public ObservableCollection<MachineRecoveryItem> MachineRecoveryItems => _machineRecoveryItems;

    public ObservableCollection<RuntimeDiagnosticItem> RuntimeDiagnosticItems => _runtimeDiagnosticItems;

    public ObservableCollection<MentionSuggestionItem> NewThreadMentionSuggestions => _newThreadMentionSuggestions;

    public ObservableCollection<MentionSuggestionItem> ThreadPopoverMentionSuggestions => _threadPopoverMentionSuggestions;

    private bool IsDiscoveringMachines => _isDiscoveringCodexRemotes || _isDiscoveringTailnet;

    private bool IsMachineHealthRefreshRunning => _isRefreshingMachineHealth || IsDiscoveringMachines;

    public MainWindow()
    {
        InitializeComponent();
        _isViewInitialized = true;
        Title = "MapofAgents";
        ActivityList.ItemsSource = _activity;
        ActivityPopoverList.ItemsSource = _topNotificationHistory;
        TopNotificationList.ItemsSource = _topNotifications;
        NewThreadTargetBox.ItemsSource = _folderChoices;
        NewThreadModelBox.ItemsSource = _newThreadModelOptions;
        NewThreadEffortBox.ItemsSource = _newThreadEffortOptions;
        ApplyNewThreadPopoverShellPresentation();
        ApplyToolbarShellPresentation();
        ApplyToolbarButtonChromePresentation();
        ApplyToolbarCreationPresentation();
        ApplyNewThreadHeaderPresentation();
        ApplyNewThreadControlChrome();
        ApplyThreadComposerFooterPresentation();
        ApplyThreadComposerAttachmentToolbarPresentation();
        ApplySelectionInspectorChromePresentation();
        ApplyHealthPopoverShellPresentation();
        ApplyWorkflowNamePopoverPresentation();
        ApplyPairingPopoverShellPresentation();
        ApplyPairingContentPresentation();
        ApplyReaderDockChromePresentation();
        ApplyReaderHeaderActionPresentation();
        ApplyReaderHeaderControlPresentation();
        ApplyReaderEmptyStatePresentation();
        ApplyTranscriptErrorPresentation();
        ApplyStopTurnActionPresentation();
        ApplyThreadPopoverShellPresentation();
        ApplyThreadPopoverDragHandlePresentation();
        ApplyThreadHeaderActionPresentation();
        ApplyThreadHeaderIdentityActionPresentation();
        ApplyArtifactsActionPresentation();
        ApplyTranscriptFilterPresentation();
        ApplyCommandFeedbackLayout();
        ApplyOperationalRailHeaderTypography();
        ApplyMachineRecoveryPresentation();
        ApplyMachinesRailHeaderPresentation();
        ApplyMachineDiscoverySectionPresentation();
        ApplyAttentionRailHeaderPresentation();
        ApplyActivitySurfaceHeaderPresentation();
        ApplyTopNotificationCardPresentation();
        ApplyRuntimeDiagnosticsRailHeaderPresentation();
        ApplyRuntimeDiagnosticsRailPresentation();
        ApplyStatusStripLayout();
        ApplyThreadInboxEmptyStateLayout();
        ApplyThreadInboxSearchFieldLayout();
        ApplyThreadInboxWorkflowFilterLayout();
        SyncNewThreadModelChoices();
        ReaderCandidateBox.ItemsSource = _readerCandidates;
        SelectionRouteList.ItemsSource = _selectionRouteItems;
        MachineRecoveryList.ItemsSource = _machineRecoveryItems;
        AttentionRailList.ItemsSource = _threadAttentionItems;
        RuntimeDiagnosticsList.ItemsSource = _runtimeDiagnosticItems;
        ThreadInboxAttentionList.ItemsSource = _threadAttentionItems;
        ThreadInboxWorkflowFilterBox.ItemsSource = _threadInboxWorkflowFilters;
        SeedThreadInboxWorkflowFilters();
        RegisterThreadPopoverDragHandlers();
        _mentionCatalogSession.CatalogChanged += MentionCatalogSession_CatalogChanged;
        _threadPopoverPendingAttachments.CollectionChanged += (_, _) => UpdateThreadPopoverAttachmentChrome();
        _preferences = _preferencesStore.Load();
        ApplyPreferences(_preferences);
        UpdateNotificationPreferenceControls();
        RootGrid.Loaded += MainWindow_Loaded;
        RootGrid.SizeChanged += RootGrid_SizeChanged;
        Closed += MainWindow_Closed;
        ConfigureWindow();
    }

    private void ConfigureMachinesFlyout()
    {
        if (_machinesFlyout is not null)
        {
            return;
        }

        if (RootGrid.XamlRoot is null)
        {
            return;
        }

        if (MachinesRail.Parent is Panel parent)
        {
            parent.Children.Remove(MachinesRail);
        }

        MachinesRail.Width = 344;
        MachinesRail.MaxHeight = 680;
        MachinesRail.Visibility = Visibility.Collapsed;
        _machinesFlyout = new Flyout
        {
            Content = MachinesRail
        };
        _machinesFlyout.Opened += (_, _) =>
        {
            _isMachinesFlyoutOpen = true;
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
            UpdateChrome();
        };
        _machinesFlyout.Closed += (_, _) =>
        {
            _isMachinesFlyoutOpen = false;
            _isMachinesRailVisible = false;
            UpdateChrome();
        };
    }

    private void ShowMachinesFlyout()
    {
        ConfigureMachinesFlyout();
        if (_machinesFlyout is null)
        {
            return;
        }

        if (_isReadingModePresented)
        {
            return;
        }

        WorkflowPopover.Visibility = Visibility.Collapsed;
        WorkflowNamePopover.Visibility = Visibility.Collapsed;
        NewThreadPopover.Visibility = Visibility.Collapsed;
        HealthPopover.Visibility = Visibility.Collapsed;
        PairingPopover.Visibility = Visibility.Collapsed;
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        MachinesRail.Visibility = Visibility.Visible;
        MachinesRailContent.Visibility = Visibility.Visible;
        _machinesFlyout?.ShowAt(MachinesButton);
    }

    private void HideMachinesFlyout()
    {
        _isMachinesRailVisible = false;
        _machinesFlyout?.Hide();
    }

    private void ApplyNewThreadHeaderPresentation()
    {
        var presentation = NewThreadHeaderPresentation.Resolve();
        NewThreadHeaderIconBackground.Background = BrushFromHex(presentation.BackgroundHex);
        NewThreadHeaderThreadGlyph.Glyph = presentation.ThreadGlyph;
        NewThreadHeaderThreadGlyph.Foreground = BrushFromHex(presentation.ForegroundHex);
        NewThreadHeaderBadge.Background = BrushFromHex(presentation.BadgeBackgroundHex);
        NewThreadHeaderBadgeText.Text = presentation.BadgeText;
        NewThreadHeaderBadgeText.Foreground = BrushFromHex(presentation.BadgeForegroundHex);
    }

    private void ApplyNewThreadPopoverShellPresentation()
    {
        var presentation = NewThreadPopoverShellPresentation.Resolve();
        NewThreadPopover.Width = presentation.Width;
        NewThreadPopover.Height = presentation.Height;
        NewThreadPopover.BorderBrush = BrushFromHex(presentation.BorderHex);
        NewThreadPopover.BorderThickness = new Thickness(presentation.BorderThickness);
        NewThreadPopover.CornerRadius = new CornerRadius(presentation.CornerRadius);
        NewThreadPopover.Translation = new Vector3(0, 0, (float)presentation.ShadowTranslationZ);
    }

    private void ApplyNewThreadControlChrome()
    {
        var presentation = NewThreadControlChromePresentation.Resolve();
        foreach (var comboBox in new[]
        {
            NewThreadTargetKindBox,
            NewThreadTargetBox,
            NewThreadModelBox,
            NewThreadEffortBox,
            NewThreadApprovalPolicyBox,
            NewThreadSandboxModeBox
        })
        {
            ApplyNewThreadComboBoxChrome(comboBox, presentation);
        }

        ApplyNewThreadTextBoxChrome(
            NewThreadNameBox,
            presentation,
            presentation.FieldHorizontalPadding,
            presentation.FieldVerticalPadding,
            fixedHeight: true);
        ApplyNewThreadTextBoxChrome(
            NewThreadPromptBox,
            presentation,
            presentation.PromptHorizontalPadding,
            presentation.PromptVerticalPadding,
            fixedHeight: false);

        CreateThreadButton.Width = presentation.CreateButtonWidth;
        CreateThreadButton.Height = presentation.CreateButtonHeight;
        CreateThreadButton.MinWidth = 0;
        CreateThreadButton.MinHeight = 0;
        CreateThreadButton.CornerRadius = new CornerRadius(presentation.CreateButtonCornerRadius);
        CreateThreadButton.BorderThickness = new Thickness(presentation.CreateButtonBorderThickness);
        CreateThreadButton.Background = BrushFromHex(presentation.CreateButtonBackgroundHex);
        CreateThreadButton.BorderBrush = BrushFromHex(presentation.CreateButtonBorderHex);
        CreateThreadButton.Foreground = BrushFromHex(presentation.CreateButtonForegroundHex);
    }

    private void ApplyThreadComposerFooterPresentation()
    {
        var presentation = ThreadComposerFooterPresentation.Resolve();
        var outer = presentation.OuterPadding;
        var metadataForeground = BrushFromHex(presentation.MetadataForegroundHex);

        ApplyComposerMetadataRow(
            NewThreadComposerMetadataRow,
            NewThreadComposerModelChip,
            NewThreadComposerEffortChip,
            NewThreadComposerModelText,
            NewThreadComposerEffortText,
            presentation,
            outer);
        NewThreadComposerPromptRow.Padding = new Thickness(
            outer,
            presentation.SectionSpacing,
            outer,
            outer);
        NewThreadComposerPromptRow.ColumnSpacing = presentation.InputActionSpacing;
        NewThreadComposerInputStack.Spacing = presentation.MentionComposerSpacing;
        NewThreadComposerModelText.Foreground = metadataForeground;
        NewThreadComposerEffortText.Foreground = metadataForeground;

        ApplyComposerMetadataRow(
            ThreadPopoverComposerMetadataRow,
            ThreadPopoverComposerModelChip,
            ThreadPopoverComposerEffortChip,
            ThreadPopoverComposerModelText,
            ThreadPopoverComposerEffortText,
            presentation,
            outer);
        ThreadPopoverComposerPromptRow.Padding = new Thickness(
            outer,
            presentation.SectionSpacing,
            outer,
            outer);
        ThreadPopoverComposerPromptRow.ColumnSpacing = presentation.InputActionSpacing;
        ThreadPopoverComposerInputStack.Spacing = presentation.ReplyInputStackSpacing;
        ThreadPopoverAttachmentToolbar.Spacing = presentation.ReplyInputStackSpacing;
        ThreadPopoverActionStack.Spacing = presentation.ReplyActionStackSpacing;
        ThreadPopoverComposerModelText.Foreground = metadataForeground;
        ThreadPopoverComposerEffortText.Foreground = metadataForeground;
    }

    private void ApplyThreadComposerAttachmentToolbarPresentation()
    {
        var presentation = ThreadComposerAttachmentToolbarPresentation.Resolve();
        var foreground = BrushFromHex(presentation.ForegroundHex);
        ThreadPopoverAttachmentToolbar.Spacing = presentation.ToolbarSpacing;
        ApplyThreadComposerAttachmentButton(
            ThreadPopoverAttachButton,
            ThreadPopoverAttachIcon,
            presentation.AttachWindowsGlyph,
            presentation.AttachToolTip,
            presentation.AttachAccessibilityName,
            foreground,
            presentation);
        ApplyThreadComposerAttachmentButton(
            ThreadPopoverPasteButton,
            ThreadPopoverPasteIcon,
            presentation.PasteWindowsGlyph,
            presentation.PasteToolTip,
            presentation.PasteAccessibilityName,
            foreground,
            presentation);
        ThreadPopoverAttachmentCountText.FontSize = presentation.CountFontSize;
        ThreadPopoverAttachmentCountText.Foreground = BrushFromHex(presentation.CountForegroundHex);
    }

    private static void ApplyThreadComposerAttachmentButton(
        Button button,
        FontIcon icon,
        string glyph,
        string toolTip,
        string accessibilityName,
        Brush foreground,
        ThreadComposerAttachmentToolbarPresentationSnapshot presentation)
    {
        button.Width = presentation.ButtonSize;
        button.Height = presentation.ButtonSize;
        button.MinWidth = 0;
        button.MinHeight = 0;
        button.Padding = new Thickness(0);
        button.Background = BrushFromHex(presentation.BackgroundHex);
        button.BorderThickness = new Thickness(presentation.BorderThickness);
        button.Foreground = foreground;
        icon.Glyph = glyph;
        icon.FontSize = presentation.IconFontSize;
        icon.Foreground = foreground;
        ToolTipService.SetToolTip(button, toolTip);
        AutomationProperties.SetName(button, accessibilityName);
    }

    private static void ApplyComposerMetadataRow(
        StackPanel row,
        StackPanel modelChip,
        StackPanel effortChip,
        TextBlock modelText,
        TextBlock effortText,
        ThreadComposerFooterPresentationSnapshot presentation,
        double outerPadding)
    {
        row.Padding = new Thickness(
            outerPadding,
            outerPadding,
            outerPadding,
            0);
        row.Spacing = presentation.MetadataItemSpacing;
        modelChip.Spacing = presentation.MetadataChipSpacing;
        effortChip.Spacing = presentation.MetadataChipSpacing;
        modelText.FontSize = presentation.MetadataFontSize;
        effortText.FontSize = presentation.MetadataFontSize;
    }

    private void ApplySelectionInspectorChromePresentation()
    {
        var presentation = SelectionInspectorChromePresentation.Resolve();
        ApplySelectionInspectorTextBoxChrome(SelectionTitleBox, presentation);
        ApplySelectionInspectorTextBoxChrome(SelectionPathBox, presentation);

        SelectionDetailText.FontSize = presentation.DetailFontSize;
        SelectionDetailText.Foreground = BrushFromHex(presentation.DetailForegroundHex);

        CloseSelectionButton.Width = presentation.CloseButtonSize;
        CloseSelectionButton.Height = presentation.CloseButtonSize;
        CloseSelectionButton.CornerRadius = new CornerRadius(presentation.CloseButtonCornerRadius);
        CloseSelectionIcon.FontSize = presentation.CloseIconFontSize;

        SelectionActionRow.ColumnSpacing = presentation.ActionRowSpacing;
        ApplySelectionInspectorActionButton(
            SaveSelectionButton,
            SaveSelectionButtonStack,
            SaveSelectionIcon,
            SaveSelectionText,
            presentation.SaveBackgroundHex,
            presentation.SaveBorderHex,
            presentation.SaveForegroundHex,
            presentation);
        ApplySelectionInspectorActionButton(
            DeleteSelectionButton,
            DeleteSelectionButtonStack,
            DeleteSelectionIcon,
            DeleteSelectionText,
            presentation.DeleteBackgroundHex,
            presentation.DeleteBorderHex,
            presentation.DeleteForegroundHex,
            presentation);
    }

    private static void ApplySelectionInspectorTextBoxChrome(
        TextBox textBox,
        SelectionInspectorChromePresentationSnapshot presentation)
    {
        var background = BrushFromHex(presentation.FieldBackgroundHex);
        var pointerOverBackground = BrushFromHex(presentation.FieldPointerOverBackgroundHex);
        var border = BrushFromHex(presentation.FieldBorderHex);
        var focusedBorder = BrushFromHex(presentation.FieldFocusedBorderHex);
        var foreground = BrushFromHex(presentation.FieldForegroundHex);
        var placeholder = BrushFromHex(presentation.PlaceholderForegroundHex);

        textBox.Height = presentation.FieldHeight;
        textBox.MinHeight = 0;
        textBox.CornerRadius = new CornerRadius(presentation.FieldCornerRadius);
        textBox.Padding = new Thickness(
            presentation.FieldHorizontalPadding,
            presentation.FieldVerticalPadding,
            presentation.FieldHorizontalPadding,
            presentation.FieldVerticalPadding);
        textBox.BorderThickness = new Thickness(presentation.FieldBorderThickness);
        textBox.Background = background;
        textBox.BorderBrush = border;
        textBox.Foreground = foreground;
        textBox.FontSize = presentation.FieldFontSize;

        textBox.Resources["TextControlCornerRadius"] = new CornerRadius(presentation.FieldCornerRadius);
        textBox.Resources["TextControlBackground"] = background;
        textBox.Resources["TextControlBackgroundPointerOver"] = pointerOverBackground;
        textBox.Resources["TextControlBackgroundFocused"] = background;
        textBox.Resources["TextControlBorderBrush"] = border;
        textBox.Resources["TextControlBorderBrushPointerOver"] = border;
        textBox.Resources["TextControlBorderBrushFocused"] = focusedBorder;
        textBox.Resources["TextControlForeground"] = foreground;
        textBox.Resources["TextControlForegroundPointerOver"] = foreground;
        textBox.Resources["TextControlForegroundFocused"] = foreground;
        textBox.Resources["TextControlPlaceholderForeground"] = placeholder;
        textBox.Resources["TextControlPlaceholderForegroundPointerOver"] = placeholder;
        textBox.Resources["TextControlPlaceholderForegroundFocused"] = placeholder;
    }

    private static void ApplySelectionInspectorActionButton(
        Button button,
        StackPanel content,
        FontIcon icon,
        TextBlock text,
        string backgroundHex,
        string borderHex,
        string foregroundHex,
        SelectionInspectorChromePresentationSnapshot presentation)
    {
        var foreground = BrushFromHex(foregroundHex);
        button.MinHeight = presentation.ActionButtonMinHeight;
        button.CornerRadius = new CornerRadius(presentation.ActionButtonCornerRadius);
        button.BorderThickness = new Thickness(presentation.ActionButtonBorderThickness);
        button.Padding = new Thickness(
            presentation.ActionButtonHorizontalPadding,
            presentation.ActionButtonVerticalPadding,
            presentation.ActionButtonHorizontalPadding,
            presentation.ActionButtonVerticalPadding);
        button.Background = BrushFromHex(backgroundHex);
        button.BorderBrush = BrushFromHex(borderHex);
        button.Foreground = foreground;
        button.FontSize = presentation.ActionFontSize;
        content.Spacing = presentation.ActionContentSpacing;
        icon.FontSize = presentation.ActionIconFontSize;
        icon.Foreground = foreground;
        text.FontSize = presentation.ActionFontSize;
        text.Foreground = foreground;
    }

    private void ApplyHealthPopoverShellPresentation()
    {
        var presentation = HealthPopoverShellPresentation.Resolve();
        HealthPopover.Width = presentation.Width;
        HealthPopover.BorderBrush = BrushFromHex(presentation.BorderHex);
        HealthPopover.BorderThickness = new Thickness(presentation.BorderThickness);
        HealthPopover.CornerRadius = new CornerRadius(presentation.CornerRadius);
        HealthPopover.Translation = new Vector3(0, 0, (float)presentation.ShadowTranslationZ);

        var content = HealthPopoverContentPresentation.Resolve();
        HealthPopover.Padding = new Thickness(content.SurfacePadding);
        HealthPopoverContentStack.Spacing = content.SurfaceSpacing;
        HealthPopoverHeaderGrid.ColumnSpacing = content.HeaderSpacing;
        HealthPopoverHeaderIconSurface.Width = content.HeaderIconSize;
        HealthPopoverHeaderIconSurface.Height = content.HeaderIconSize;
        HealthPopoverHeaderIconSurface.CornerRadius = new CornerRadius(content.HeaderIconCornerRadius);
        HealthPopoverHeaderIconSurface.Background = BrushFromHex(content.HeaderIconBackgroundHex);
        HealthPopoverHeaderIcon.FontSize = content.HeaderIconFontSize;
        HealthPopoverHeaderIcon.Foreground = BrushFromHex(content.HeaderIconForegroundHex);
        HealthPopoverHeaderTextStack.Spacing = content.HeaderTextSpacing;
        HealthPopoverTitle.FontSize = content.HeaderTitleFontSize;
        HealthPopoverSubtitle.FontSize = content.HeaderSubtitleFontSize;
        HealthPopoverSubtitle.Foreground = BrushFromHex(content.HeaderSubtitleForegroundHex);
        CloseHealthPopoverButton.Width = content.CloseButtonSize;
        CloseHealthPopoverButton.Height = content.CloseButtonSize;
        CloseHealthPopoverButton.CornerRadius = new CornerRadius(content.CloseButtonCornerRadius);
        CloseHealthPopoverIcon.FontSize = content.CloseIconFontSize;

        HealthSummaryCard.Padding = new Thickness(content.SummaryPadding);
        HealthSummaryCard.CornerRadius = new CornerRadius(content.SummaryCornerRadius);
        HealthSummaryCard.BorderThickness = new Thickness(content.SummaryBorderThickness);
        HealthSummaryCard.Background = BrushFromHex(content.SummaryBackgroundHex);
        HealthSummaryCard.BorderBrush = BrushFromHex(content.SummaryBorderHex);
        HealthSummaryStack.Spacing = content.SummaryStackSpacing;
        HealthSummaryText.FontSize = content.SummaryTitleFontSize;
        HealthSummaryText.Foreground = BrushFromHex(content.SummaryTitleForegroundHex);
        HealthDetailText.FontSize = content.SummaryDetailFontSize;
        HealthDetailText.Foreground = BrushFromHex(content.SummaryDetailForegroundHex);

        HealthActionStack.Spacing = content.ActionStackSpacing;
        ApplyHealthPopoverActionButton(
            RefreshHealthPopoverButton,
            RefreshHealthPopoverButtonStack,
            RefreshHealthPopoverIcon,
            RefreshHealthPopoverText,
            content);
        ApplyHealthPopoverActionButton(
            RunDiagnosticsPopoverButton,
            RunDiagnosticsPopoverButtonStack,
            RunDiagnosticsPopoverIcon,
            RunDiagnosticsPopoverText,
            content);
        ApplyHealthPopoverActionButton(
            ToggleMachineRecoveryPopoverButton,
            ToggleMachineRecoveryPopoverButtonStack,
            ToggleMachineRecoveryPopoverIcon,
            MachineRecoveryToggleText,
            content);
        ApplyHealthPopoverActionButton(
            HealthPopoverViewLogsButton,
            HealthPopoverViewLogsButtonStack,
            HealthPopoverViewLogsIcon,
            HealthPopoverViewLogsText,
            content);
    }

    private static void ApplyHealthPopoverActionButton(
        Button button,
        StackPanel stack,
        PathIcon icon,
        TextBlock text,
        HealthPopoverContentPresentationSnapshot presentation)
    {
        var background = BrushFromHex(presentation.ActionButtonBackgroundHex);
        var border = BrushFromHex(presentation.ActionButtonBorderHex);
        var foreground = BrushFromHex(presentation.ActionButtonForegroundHex);

        button.MinHeight = presentation.ActionButtonMinHeight;
        button.Padding = new Thickness(
            presentation.ActionButtonHorizontalPadding,
            presentation.ActionButtonVerticalPadding,
            presentation.ActionButtonHorizontalPadding,
            presentation.ActionButtonVerticalPadding);
        button.CornerRadius = new CornerRadius(presentation.ActionButtonCornerRadius);
        button.Background = background;
        button.BorderBrush = border;
        button.BorderThickness = new Thickness(0);
        button.Foreground = foreground;
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        stack.Spacing = presentation.ActionContentSpacing;
        icon.Width = presentation.ActionIconSize;
        icon.Height = presentation.ActionIconSize;
        icon.Foreground = foreground;
        text.FontSize = presentation.ActionTextFontSize;
        text.Foreground = foreground;
    }

    private void ApplyPairingPopoverShellPresentation()
    {
        var presentation = PairingPopoverShellPresentation.Resolve();
        PairingPopover.Width = presentation.Width;
        PairingPopover.BorderBrush = BrushFromHex(presentation.BorderHex);
        PairingPopover.BorderThickness = new Thickness(presentation.BorderThickness);
        PairingPopover.CornerRadius = new CornerRadius(presentation.CornerRadius);
        PairingPopover.Translation = new Vector3(0, 0, (float)presentation.ShadowTranslationZ);
    }

    private void ApplyWorkflowNamePopoverPresentation()
    {
        var presentation = WorkflowNamePopoverPresentation.Resolve();
        WorkflowNamePopover.Width = presentation.Width;
        WorkflowNamePopover.Padding = new Thickness(presentation.Padding);
        WorkflowNamePopover.BorderBrush = BrushFromHex(presentation.BorderHex);
        WorkflowNamePopover.BorderThickness = new Thickness(presentation.BorderThickness);
        WorkflowNamePopover.CornerRadius = new CornerRadius(presentation.CornerRadius);
        WorkflowNamePopover.Translation = new Vector3(0, 0, (float)presentation.ShadowTranslationZ);
        WorkflowNamePopoverStack.Spacing = presentation.SurfaceSpacing;
        WorkflowNameHeaderGrid.ColumnSpacing = presentation.HeaderSpacing;
        WorkflowNameIconHost.Width = presentation.HeaderIconTileSize;
        WorkflowNameIconHost.Height = presentation.HeaderIconTileSize;
        WorkflowNameIconHost.CornerRadius = new CornerRadius(presentation.HeaderIconCornerRadius);
        WorkflowNameTitleText.FontSize = presentation.HeaderTitleFontSize;
        CloseWorkflowNamePopoverButton.Width = presentation.CloseButtonSize;
        CloseWorkflowNamePopoverButton.Height = presentation.CloseButtonSize;
        CloseWorkflowNamePopoverIcon.FontSize = presentation.CloseIconFontSize;
        WorkflowNameActionsGrid.ColumnSpacing = presentation.ActionSpacing;
    }

    private void ApplyPairingContentPresentation()
    {
        var presentation = PairingContentPresentation.Resolve();
        PairingHeaderTitleText.Text = "Secure device enrollment";
        RefreshPairingButton.Visibility = Visibility.Collapsed;
        PairingProgressRing.IsActive = false;
        PairingProgressRing.Visibility = Visibility.Collapsed;
        GeneratedPairingPanel.Visibility = Visibility.Collapsed;
        PairingImportPanel.Visibility = Visibility.Collapsed;
        PairingNetworkAccessBorder.Visibility = Visibility.Collapsed;
        PairingPopover.Padding = new Thickness(presentation.SurfacePadding);
        PairingPopoverStack.Spacing = presentation.SurfaceSpacing;

        PairingHeaderGrid.ColumnSpacing = presentation.HeaderSpacing;
        PairingHeaderIconHost.Width = presentation.HeaderIconTileSize;
        PairingHeaderIconHost.Height = presentation.HeaderIconTileSize;
        PairingHeaderIconHost.CornerRadius = new CornerRadius(presentation.HeaderIconCornerRadius);
        PairingHeaderIconHost.Background = BrushFromHex(presentation.HeaderIconBackgroundHex);
        PairingHeaderIcon.FontSize = presentation.HeaderIconFontSize;
        PairingHeaderIcon.Foreground = BrushFromHex(presentation.HeaderIconForegroundHex);
        PairingHeaderTextStack.Spacing = presentation.HeaderTextSpacing;
        PairingHeaderTitleText.FontSize = presentation.HeaderTitleFontSize;
        PairingPopoverSubtitle.FontSize = presentation.HeaderSubtitleFontSize;
        RefreshPairingButton.Width = presentation.HeaderActionButtonSize;
        RefreshPairingButton.Height = presentation.HeaderActionButtonSize;
        ClosePairingPopoverButton.Width = presentation.HeaderActionButtonSize;
        ClosePairingPopoverButton.Height = presentation.HeaderActionButtonSize;

        PairingBodyStack.Spacing = presentation.BodySpacing;
        PairingStatusStack.Spacing = presentation.StatusSpacing;
        PairingStatusIcon.FontSize = presentation.StatusIconFontSize;
        PairingStatusText.FontSize = presentation.StatusTextFontSize;
        PairingDetailBorder.Padding = new Thickness(presentation.DetailPadding);
        PairingDetailBorder.CornerRadius = new CornerRadius(presentation.DetailCornerRadius);
        PairingDetailText.FontSize = presentation.DetailFontSize;
        PairingNetworkAccessBorder.Padding = new Thickness(presentation.DetailPadding);
        PairingNetworkAccessBorder.CornerRadius = new CornerRadius(presentation.DetailCornerRadius);
        PairingNetworkAccessText.FontSize = presentation.NetworkAccessFontSize;

        PairingProgressRing.Width = presentation.LoadingWidth;
        PairingProgressRing.Height = presentation.LoadingHeight;
        GeneratedPairingPanel.ColumnSpacing = presentation.QrDetailSpacing;
        PairingQRCodeHost.Width = presentation.QrSize;
        PairingQRCodeHost.Height = presentation.QrSize;
        PairingQRCodeHost.CornerRadius = new CornerRadius(presentation.QrCornerRadius);
        PairingQRCodeImage.Margin = new Thickness(presentation.QrImagePadding);
        GeneratedPairingDetailsPanel.Width = presentation.GeneratedDetailsWidth;
        GeneratedPairingDetailsPanel.Spacing = presentation.GeneratedDetailsSpacing;
        CopyPairingUrlButtonStack.Spacing = presentation.ActionButtonContentSpacing;
        GeneratedPairingExpiryText.FontSize = presentation.ExpiryFontSize;

        PairingImportPanel.Spacing = presentation.ImportPanelSpacing;
        PairingCodeBox.MinHeight = presentation.ImportTextBoxMinHeight;
        PairingPreviewPanel.Padding = new Thickness(presentation.PreviewPanelPadding);
        PairingPreviewPanel.CornerRadius = new CornerRadius(presentation.PreviewPanelCornerRadius);
        ImportPairingButtonStack.Spacing = presentation.ActionButtonContentSpacing;
        SetPairingMessage(
            WindowsDeviceEnrollmentAvailability.Title,
            WindowsDeviceEnrollmentAvailability.Detail,
            "#FFD60A",
            "#1AFFD60A",
            "#26FFD60A",
            "\uE7BA");
    }

    private static void ApplyNewThreadComboBoxChrome(
        ComboBox comboBox,
        NewThreadControlChromePresentationSnapshot presentation)
    {
        var background = BrushFromHex(presentation.FieldBackgroundHex);
        var pointerOverBackground = BrushFromHex(presentation.FieldPointerOverBackgroundHex);
        var pressedBackground = BrushFromHex(presentation.FieldPressedBackgroundHex);
        var border = BrushFromHex(presentation.FieldBorderHex);
        var focusedBorder = BrushFromHex(presentation.FieldFocusedBorderHex);
        var foreground = BrushFromHex(presentation.FieldForegroundHex);
        var chevron = BrushFromHex(presentation.PickerChevronForegroundHex);

        comboBox.Height = presentation.FieldHeight;
        comboBox.MinHeight = 0;
        comboBox.MinWidth = 0;
        comboBox.Padding = new Thickness(
            presentation.FieldHorizontalPadding,
            presentation.FieldVerticalPadding,
            presentation.FieldHorizontalPadding,
            presentation.FieldVerticalPadding);
        comboBox.BorderThickness = new Thickness(presentation.FieldBorderThickness);
        comboBox.CornerRadius = new CornerRadius(presentation.FieldCornerRadius);
        comboBox.Background = background;
        comboBox.BorderBrush = border;
        comboBox.Foreground = foreground;
        comboBox.FontSize = presentation.FieldFontSize;

        comboBox.Resources["ComboBoxCornerRadius"] = new CornerRadius(presentation.FieldCornerRadius);
        comboBox.Resources["ComboBoxBackground"] = background;
        comboBox.Resources["ComboBoxBackgroundPointerOver"] = pointerOverBackground;
        comboBox.Resources["ComboBoxBackgroundPressed"] = pressedBackground;
        comboBox.Resources["ComboBoxBackgroundFocused"] = background;
        comboBox.Resources["ComboBoxBorderBrush"] = border;
        comboBox.Resources["ComboBoxBorderBrushPointerOver"] = border;
        comboBox.Resources["ComboBoxBorderBrushPressed"] = border;
        comboBox.Resources["ComboBoxBorderBrushFocused"] = focusedBorder;
        comboBox.Resources["ComboBoxForeground"] = foreground;
        comboBox.Resources["ComboBoxForegroundPointerOver"] = foreground;
        comboBox.Resources["ComboBoxForegroundPressed"] = foreground;
        comboBox.Resources["ComboBoxForegroundFocused"] = foreground;
        comboBox.Resources["ComboBoxDropDownGlyphForeground"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundPointerOver"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundPressed"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundFocused"] = chevron;
    }

    private static void ApplyNewThreadTextBoxChrome(
        TextBox textBox,
        NewThreadControlChromePresentationSnapshot presentation,
        double horizontalPadding,
        double verticalPadding,
        bool fixedHeight)
    {
        if (fixedHeight)
        {
            textBox.Height = presentation.FieldHeight;
        }

        textBox.MinHeight = 0;
        textBox.CornerRadius = new CornerRadius(presentation.FieldCornerRadius);
        textBox.Padding = new Thickness(
            horizontalPadding,
            verticalPadding,
            horizontalPadding,
            verticalPadding);
        textBox.BorderThickness = new Thickness(presentation.FieldBorderThickness);
        var background = BrushFromHex(presentation.FieldBackgroundHex);
        var pointerOverBackground = BrushFromHex(presentation.FieldPointerOverBackgroundHex);
        var focusedBorder = BrushFromHex(presentation.FieldFocusedBorderHex);
        var border = BrushFromHex(presentation.FieldBorderHex);
        var foreground = BrushFromHex(presentation.FieldForegroundHex);
        var placeholder = BrushFromHex(presentation.PlaceholderForegroundHex);
        textBox.Background = background;
        textBox.BorderBrush = border;
        textBox.Foreground = foreground;
        textBox.FontSize = presentation.FieldFontSize;

        textBox.Resources["TextControlCornerRadius"] = new CornerRadius(presentation.FieldCornerRadius);
        textBox.Resources["TextControlBackground"] = background;
        textBox.Resources["TextControlBackgroundPointerOver"] = pointerOverBackground;
        textBox.Resources["TextControlBackgroundFocused"] = background;
        textBox.Resources["TextControlBorderBrush"] = border;
        textBox.Resources["TextControlBorderBrushPointerOver"] = border;
        textBox.Resources["TextControlBorderBrushFocused"] = focusedBorder;
        textBox.Resources["TextControlForeground"] = foreground;
        textBox.Resources["TextControlForegroundPointerOver"] = foreground;
        textBox.Resources["TextControlForegroundFocused"] = foreground;
        textBox.Resources["TextControlPlaceholderForeground"] = placeholder;
        textBox.Resources["TextControlPlaceholderForegroundPointerOver"] = placeholder;
        textBox.Resources["TextControlPlaceholderForegroundFocused"] = placeholder;
    }

    private void ApplyOperationalRailHeaderTypography()
    {
        var typography = OperationalRailHeaderTypography.Resolve();
        foreach (var title in new[]
        {
            MachineRecoveryRailHeaderTitleText,
            MachinesRailHeaderTitleText,
            ActivityRailHeaderTitleText,
            AttentionRailHeaderTitleText,
            RuntimeDiagnosticsRailHeaderTitleText,
            ThreadInboxHeaderTitleText
        })
        {
            title.FontSize = typography.TitleFontSize;
        }

        MachineRecoveryRailHeaderStack.Spacing = typography.IconTitleSpacing;
    }

    private void ApplyMachineRecoveryPresentation()
    {
        var headerPresentation = MachineRecoveryPresentation.Header();
        MachineRecoveryRailHeaderIcon.Width = headerPresentation.IconSize;
        MachineRecoveryRailHeaderIcon.Height = headerPresentation.IconSize;
        MachineRecoveryRailHeaderIcon.Foreground = BrushFromHex(headerPresentation.ForegroundHex);
        AutomationProperties.SetName(MachineRecoveryRailHeaderIcon, headerPresentation.AccessibilityName);

        var railPresentation = MachineRecoveryPresentation.Rail();
        MachineRecoveryFooterActions.Visibility = railPresentation.ShowsFooterActions
            ? Visibility.Visible
            : Visibility.Collapsed;
        RecoveryEmptyText.Visibility = railPresentation.ShowsEmptyState
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyToolbarShellPresentation()
    {
        var presentation = ToolbarShellPresentation.Resolve();
        CommandBarSurface.Margin = new Thickness(presentation.EdgeInset);
        CommandBarSurface.Padding = new Thickness(presentation.Padding);
        CommandBarSurface.CornerRadius = new CornerRadius(presentation.CornerRadius);
        CommandBarSurface.MaxWidth = presentation.MaxWidth;
        CommandBarSurface.BorderBrush = BrushFromHex(presentation.BorderHex);
        CommandBarSurface.BorderThickness = new Thickness(presentation.BorderThickness);
        CommandBarLayoutRoot.Spacing = presentation.GroupSpacing;

        foreach (var divider in new[] { CommandBarWorkflowDivider, CommandBarCreationDivider, CommandBarPairingDivider })
        {
            divider.Width = presentation.DividerWidth;
            divider.Height = presentation.DividerHeight;
            divider.Fill = BrushFromHex(presentation.DividerFillHex);
        }
    }

    private void ApplyToolbarButtonChromePresentation()
    {
        var presentation = ToolbarButtonChromePresentation.Resolve();
        ApplyToolbarButtonChrome(WorkflowButton, presentation.Plain);
        ApplyToolbarButtonChrome(MachinesButton, presentation.Bordered);
        ApplyToolbarButtonChrome(AddFolderButton, presentation.Bordered);
        ApplyToolbarButtonChrome(AddThreadButton, presentation.Primary);
        ApplyToolbarButtonChrome(ReadingModeButton, presentation.Bordered);
        ApplyToolbarButtonChrome(ArrangeButton, presentation.Plain);
        ApplyToolbarButtonChrome(
            SubagentsButton,
            _showsSubagents ? presentation.Purple : presentation.Bordered);
        ApplyToolbarButtonChrome(SearchButton, presentation.Plain);
        ApplyToolbarButtonChrome(ActivityButton, presentation.Plain);
        ApplyToolbarButtonChrome(PairButton, presentation.Plain);
    }

    private static void ApplyToolbarButtonChrome(Button button, ToolbarButtonChromeRoleSnapshot role)
    {
        button.MinHeight = role.MinHeight;
        button.Padding = new Thickness(
            role.HorizontalPadding,
            role.VerticalPadding,
            role.HorizontalPadding,
            role.VerticalPadding);
        button.Background = BrushFromHex(role.BackgroundHex);
        button.BorderBrush = BrushFromHex(role.BorderHex);
        button.BorderThickness = new Thickness(role.BorderThickness);
        button.CornerRadius = new CornerRadius(role.CornerRadius);
        button.Foreground = BrushFromHex(role.ForegroundHex);
        button.FontSize = role.FontSize;
    }

    private void ApplyToolbarCreationPresentation()
    {
        var presentation = ToolbarCreationPresentation.Resolve();
        var folderStroke = BrushFromHex(presentation.FolderStrokeHex);
        var folderBadge = BrushFromHex(presentation.FolderBadgeFillHex);
        var folderPlus = BrushFromHex(presentation.FolderPlusHex);
        var threadStroke = BrushFromHex(presentation.ThreadStrokeHex);

        AddFolderIcon.Width = presentation.IconWidth;
        AddFolderIcon.Height = presentation.IconHeight;
        AddFolderOutlinePath.Stroke = folderStroke;
        AddFolderOutlinePath.StrokeThickness = presentation.StrokeThickness;
        AddFolderBadgeCircle.Fill = folderBadge;
        AddFolderBadgeCircle.Width = presentation.BadgeSize;
        AddFolderBadgeCircle.Height = presentation.BadgeSize;
        Canvas.SetLeft(AddFolderBadgeCircle, presentation.BadgeX);
        Canvas.SetTop(AddFolderBadgeCircle, presentation.BadgeY);
        AddFolderBadgePlusHorizontalLine.Stroke = folderPlus;
        AddFolderBadgePlusVerticalLine.Stroke = folderPlus;
        AddFolderBadgePlusHorizontalLine.StrokeThickness = presentation.PlusStrokeThickness;
        AddFolderBadgePlusVerticalLine.StrokeThickness = presentation.PlusStrokeThickness;
        AutomationProperties.SetName(AddFolderButton, presentation.FolderAccessibilityName);
        AutomationProperties.SetName(AddFolderIcon, presentation.FolderAccessibilityName);

        AddThreadIcon.Width = presentation.IconWidth;
        AddThreadIcon.Height = presentation.IconHeight;
        AddThreadBubblePath.Stroke = threadStroke;
        AddThreadBubblePath.StrokeThickness = presentation.ThreadStrokeThickness;
        AddThreadPlusHorizontalLine.Stroke = threadStroke;
        AddThreadPlusVerticalLine.Stroke = threadStroke;
        AddThreadPlusHorizontalLine.StrokeThickness = presentation.PlusStrokeThickness;
        AddThreadPlusVerticalLine.StrokeThickness = presentation.PlusStrokeThickness;
        AutomationProperties.SetName(AddThreadButton, presentation.ThreadAccessibilityName);
        AutomationProperties.SetName(AddThreadIcon, presentation.ThreadAccessibilityName);
    }

    private void ApplyReaderHeaderActionPresentation()
    {
        var clearPresentation = ReaderHeaderActionPresentation.ResolveClear();
        ClearReaderThreadsIcon.Width = clearPresentation.ClearIconDiameter;
        ClearReaderThreadsIcon.Height = clearPresentation.ClearIconDiameter;
        ClearReaderThreadsIconCircle.Stroke = BrushFromHex(clearPresentation.ClearCircleStrokeHex);
        ClearReaderThreadsIconGlyph.Glyph = clearPresentation.ClearGlyph;
        ClearReaderThreadsIconGlyph.FontSize = clearPresentation.ClearGlyphFontSize;
        ClearReaderThreadsIconGlyph.Foreground = BrushFromHex(clearPresentation.ClearForegroundHex);
        ClearReaderThreadsText.Text = clearPresentation.ClearLabel;
        ClearReaderThreadsText.Foreground = BrushFromHex(clearPresentation.ClearForegroundHex);
    }

    private void ApplyReaderHeaderControlPresentation()
    {
        var presentation = ReaderHeaderControlPresentation.Resolve();
        ApplyReaderCandidatePickerChrome(ReaderCandidateBox, presentation);
        ApplyReaderHeaderIconButton(AddReaderThreadButton, AddReaderThreadIcon, presentation.AddRemoveIconFontSize, presentation);
        ApplyReaderHeaderIconButton(RemoveReaderThreadButton, RemoveReaderThreadIcon, presentation.AddRemoveIconFontSize, presentation);
        ApplyReaderHeaderIconButton(CloseReaderButton, CloseReaderIcon, presentation.CloseIconFontSize, presentation);
    }

    private static void ApplyReaderCandidatePickerChrome(
        ComboBox comboBox,
        ReaderHeaderControlPresentationSnapshot presentation)
    {
        var background = BrushFromHex(presentation.PickerBackgroundHex);
        var pointerOverBackground = BrushFromHex(presentation.PickerPointerOverBackgroundHex);
        var pressedBackground = BrushFromHex(presentation.PickerPressedBackgroundHex);
        var border = BrushFromHex(presentation.PickerBorderHex);
        var focusedBorder = BrushFromHex(presentation.PickerFocusedBorderHex);
        var foreground = BrushFromHex(presentation.PickerForegroundHex);
        var chevron = BrushFromHex(presentation.PickerChevronForegroundHex);

        comboBox.Height = presentation.PickerHeight;
        comboBox.MinHeight = 0;
        comboBox.MinWidth = 0;
        comboBox.Padding = new Thickness(
            presentation.PickerHorizontalPadding,
            presentation.PickerVerticalPadding,
            presentation.PickerHorizontalPadding,
            presentation.PickerVerticalPadding);
        comboBox.CornerRadius = new CornerRadius(presentation.PickerCornerRadius);
        comboBox.BorderThickness = new Thickness(presentation.PickerBorderThickness);
        comboBox.Background = background;
        comboBox.BorderBrush = border;
        comboBox.Foreground = foreground;
        comboBox.FontSize = presentation.PickerFontSize;

        comboBox.Resources["ComboBoxCornerRadius"] = new CornerRadius(presentation.PickerCornerRadius);
        comboBox.Resources["ComboBoxBackground"] = background;
        comboBox.Resources["ComboBoxBackgroundPointerOver"] = pointerOverBackground;
        comboBox.Resources["ComboBoxBackgroundPressed"] = pressedBackground;
        comboBox.Resources["ComboBoxBackgroundFocused"] = background;
        comboBox.Resources["ComboBoxBorderBrush"] = border;
        comboBox.Resources["ComboBoxBorderBrushPointerOver"] = border;
        comboBox.Resources["ComboBoxBorderBrushPressed"] = border;
        comboBox.Resources["ComboBoxBorderBrushFocused"] = focusedBorder;
        comboBox.Resources["ComboBoxForeground"] = foreground;
        comboBox.Resources["ComboBoxForegroundPointerOver"] = foreground;
        comboBox.Resources["ComboBoxForegroundPressed"] = foreground;
        comboBox.Resources["ComboBoxForegroundFocused"] = foreground;
        comboBox.Resources["ComboBoxDropDownGlyphForeground"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundPointerOver"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundPressed"] = chevron;
        comboBox.Resources["ComboBoxDropDownGlyphForegroundFocused"] = chevron;
    }

    private static void ApplyReaderHeaderIconButton(
        Button button,
        FontIcon icon,
        double iconFontSize,
        ReaderHeaderControlPresentationSnapshot presentation)
    {
        var background = BrushFromHex(presentation.IconButtonBackgroundHex);
        var border = BrushFromHex(presentation.IconButtonBorderHex);
        var foreground = BrushFromHex(presentation.IconButtonForegroundHex);

        button.Width = presentation.IconButtonSize;
        button.Height = presentation.IconButtonSize;
        button.MinWidth = 0;
        button.MinHeight = 0;
        button.Padding = new Thickness(0);
        button.CornerRadius = new CornerRadius(presentation.IconButtonCornerRadius);
        button.BorderThickness = new Thickness(presentation.IconButtonBorderThickness);
        button.Background = background;
        button.BorderBrush = border;
        button.Foreground = foreground;
        icon.FontSize = iconFontSize;
        icon.Foreground = foreground;
    }

    private void ApplyReaderDockChromePresentation()
    {
        var presentation = ReaderDockChromePresentation.Resolve();
        var background = BrushFromHex(presentation.BackgroundHex);
        var hairline = BrushFromHex(presentation.HairlineHex);
        ReaderDock.Background = background;
        ReaderDockHeader.Background = background;
        ReaderDockTopHairline.Height = presentation.HairlineThickness;
        ReaderDockTopHairline.Fill = hairline;
        ReaderDockHeaderDivider.Height = presentation.HairlineThickness;
        ReaderDockHeaderDivider.Fill = hairline;
    }

    private void ApplyReaderEmptyStatePresentation()
    {
        var presentation = ReaderEmptyStatePresentation.Resolve();
        var iconStroke = BrushFromHex(presentation.IconStrokeHex);

        ReaderEmptyText.Width = presentation.Width;
        AutomationProperties.SetName(ReaderEmptyText, $"{presentation.Title}. {presentation.Detail}");
        ReaderEmptyStateStack.Spacing = presentation.StackSpacing;
        ReaderEmptyStateIcon.Width = presentation.IconWidth;
        ReaderEmptyStateIcon.Height = presentation.IconHeight;
        ReaderEmptyStateBackBubblePath.Stroke = iconStroke;
        ReaderEmptyStateBackBubblePath.StrokeThickness = presentation.IconStrokeThickness;
        ReaderEmptyStateFrontBubblePath.Stroke = iconStroke;
        ReaderEmptyStateFrontBubblePath.StrokeThickness = presentation.IconStrokeThickness;
        ReaderEmptyStateTitleText.Text = presentation.Title;
        ReaderEmptyStateTitleText.FontSize = presentation.TitleFontSize;
        ReaderEmptyStateTitleText.Foreground = BrushFromHex(presentation.TitleForegroundHex);
        ReaderEmptyStateDetailText.Text = presentation.Detail;
        ReaderEmptyStateDetailText.FontSize = presentation.DetailFontSize;
        ReaderEmptyStateDetailText.Foreground = BrushFromHex(presentation.DetailForegroundHex);
        ReaderEmptyStateDetailText.MaxWidth = presentation.DetailMaxWidth;
    }

    private void ApplyTranscriptErrorPresentation()
    {
        var presentation = TranscriptErrorPresentation.Resolve();
        ThreadPopoverTranscriptErrorBanner.Padding = new Thickness(presentation.Padding);
        ThreadPopoverTranscriptErrorBanner.Background = BrushFromHex(presentation.BackgroundHex);
        ThreadPopoverTranscriptErrorBanner.BorderBrush = BrushFromHex(presentation.BorderHex);
        ThreadPopoverTranscriptErrorBanner.BorderThickness = new Thickness(presentation.BorderThickness);
        ThreadPopoverTranscriptErrorBanner.CornerRadius = new CornerRadius(presentation.CornerRadius);
        ThreadPopoverTranscriptErrorContentStack.Spacing = presentation.ContentSpacing;
        ThreadPopoverTranscriptErrorHeaderGrid.ColumnSpacing = presentation.HeaderColumnSpacing;
        ThreadPopoverTranscriptErrorTextStack.Spacing = presentation.TextStackSpacing;
        ThreadPopoverTranscriptErrorActionsStack.Spacing = presentation.ActionSpacing;
        ThreadPopoverTranscriptErrorIcon.Glyph = presentation.WindowsGlyph;
        ThreadPopoverTranscriptErrorIcon.FontSize = presentation.IconFontSize;
        ThreadPopoverTranscriptErrorIcon.Foreground = BrushFromHex(presentation.IconForegroundHex);
        ThreadPopoverTranscriptErrorIcon.Margin = new Thickness(0, presentation.IconTopMargin, 0, 0);
        ThreadPopoverTranscriptErrorTitle.Text = presentation.Title;
        ThreadPopoverTranscriptErrorTitle.FontSize = presentation.TitleFontSize;
        ThreadPopoverTranscriptErrorTitle.Foreground = BrushFromHex(presentation.TitleForegroundHex);
        ThreadPopoverTranscriptErrorText.FontSize = presentation.DetailFontSize;
        ThreadPopoverTranscriptErrorText.Foreground = BrushFromHex(presentation.DetailForegroundHex);
        ThreadPopoverTranscriptErrorText.MaxLines = presentation.DetailMaxLines;
        RetryThreadPopoverTranscriptText.Text = presentation.RetryLabel;
        UseCachedThreadPopoverTranscriptText.Text = presentation.UseCachedLabel;
        RetryThreadPopoverTranscriptButton.Padding = new Thickness(
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding,
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding);
        UseCachedThreadPopoverTranscriptButton.Padding = RetryThreadPopoverTranscriptButton.Padding;
        RetryThreadPopoverTranscriptText.FontSize = presentation.ButtonFontSize;
        UseCachedThreadPopoverTranscriptText.FontSize = presentation.ButtonFontSize;
    }

    private void ApplyStopTurnActionPresentation()
    {
        var presentation = StopTurnActionPresentation.Resolve();
        var foreground = BrushFromHex(presentation.ForegroundHex);
        var background = BrushFromHex(presentation.BackgroundHex);
        var border = BrushFromHex(presentation.BorderHex);

        SelectionStopThreadButton.Foreground = foreground;
        SelectionStopThreadButton.Background = background;
        SelectionStopThreadButton.BorderBrush = border;
        SelectionStopThreadIcon.Glyph = presentation.WindowsGlyph;
        AutomationProperties.SetName(SelectionStopThreadButton, presentation.AccessibilityName);
        ToolTipService.SetToolTip(SelectionStopThreadButton, presentation.ToolTip);

        ThreadPopoverStopButton.Foreground = foreground;
        ThreadPopoverStopButton.Background = background;
        ThreadPopoverStopButton.BorderBrush = border;
        ThreadPopoverStopIcon.Glyph = presentation.WindowsGlyph;
        AutomationProperties.SetName(ThreadPopoverStopButton, presentation.AccessibilityName);
        ToolTipService.SetToolTip(ThreadPopoverStopButton, presentation.ToolTip);
    }

    private void ApplyThreadPopoverShellPresentation()
    {
        var presentation = ThreadPopoverShellPresentation.Resolve();
        ThreadPopover.BorderBrush = BrushFromHex(presentation.BorderHex);
        ThreadPopover.BorderThickness = new Thickness(presentation.BorderThickness);
        ThreadPopover.CornerRadius = new CornerRadius(presentation.CornerRadius);
        ThreadPopover.Translation = new Vector3(0, 0, (float)presentation.ShadowTranslationZ);
        ThreadPopoverHeaderLayoutGrid.ColumnSpacing = presentation.HeaderColumnSpacing;
        ThreadPopoverHeaderActionBar.Spacing = presentation.HeaderActionSpacing;
        ThreadPopoverHeaderControlsColumn.Margin = new Thickness(presentation.HeaderControlsLeftInset, 0, 0, 0);
        if (RootGrid.Resources["RailPanelShadow"] is Shadow shadow)
        {
            ThreadPopover.Shadow = shadow;
        }
    }

    private void ApplyThreadHeaderActionPresentation()
    {
        var presentation = ThreadHeaderActionPresentation.Resolve();
        ApplyThreadHeaderActionButton(
            RefreshThreadPopoverButton,
            RefreshThreadPopoverIcon,
            presentation.RefreshWindowsGlyph,
            presentation.RefreshToolTip,
            presentation.RefreshAccessibilityName,
            presentation);
        ApplyThreadHeaderActionButton(
            CloseThreadPopoverButton,
            CloseThreadPopoverIcon,
            presentation.CloseWindowsGlyph,
            presentation.CloseToolTip,
            presentation.CloseAccessibilityName,
            presentation);
    }

    private static void ApplyThreadHeaderActionButton(
        Button button,
        FontIcon icon,
        string glyph,
        string toolTip,
        string accessibilityName,
        ThreadHeaderActionPresentationSnapshot presentation)
    {
        var foreground = BrushFromHex(presentation.ForegroundHex);
        button.Width = presentation.HitTargetSize;
        button.Height = presentation.HitTargetSize;
        button.MinWidth = 0;
        button.MinHeight = 0;
        button.Padding = new Thickness(0);
        button.Background = BrushFromHex(presentation.BackgroundHex);
        button.BorderThickness = new Thickness(presentation.BorderThickness);
        button.Foreground = foreground;
        icon.Glyph = glyph;
        icon.FontSize = presentation.IconFontSize;
        icon.Foreground = foreground;
        ToolTipService.SetToolTip(button, toolTip);
        AutomationProperties.SetName(button, accessibilityName);
    }

    private void ApplyThreadHeaderIdentityActionPresentation()
    {
        var presentation = ThreadHeaderIdentityActionPresentation.Resolve();
        ApplyThreadHeaderIdentityButton(
            ThreadPopoverTitleActionButton,
            ThreadPopoverTitleActionIcon,
            presentation.RenameWindowsGlyph,
            presentation.RenameHitTargetSize,
            presentation.RenameIconFontSize,
            presentation.RenameForegroundHex,
            presentation.RenameToolTip,
            presentation.RenameAccessibilityName,
            presentation);
        ApplyThreadHeaderIdentityButton(
            ThreadPopoverCopyThreadIdButton,
            ThreadPopoverCopyThreadIdIcon,
            presentation.CopyWindowsGlyph,
            presentation.CopyHitTargetSize,
            presentation.CopyIconFontSize,
            presentation.CopyForegroundHex,
            presentation.CopyToolTip,
            presentation.CopyAccessibilityName,
            presentation);
    }

    private static void ApplyThreadHeaderIdentityButton(
        Button button,
        FontIcon icon,
        string glyph,
        double hitTargetSize,
        double iconFontSize,
        string foregroundHex,
        string toolTip,
        string accessibilityName,
        ThreadHeaderIdentityActionPresentationSnapshot presentation)
    {
        var foreground = BrushFromHex(foregroundHex);
        button.Width = hitTargetSize;
        button.Height = hitTargetSize;
        button.MinWidth = 0;
        button.MinHeight = 0;
        button.Padding = new Thickness(0);
        button.Background = BrushFromHex(presentation.BackgroundHex);
        button.BorderThickness = new Thickness(presentation.BorderThickness);
        button.Foreground = foreground;
        icon.Glyph = glyph;
        icon.FontSize = iconFontSize;
        icon.Foreground = foreground;
        ToolTipService.SetToolTip(button, toolTip);
        AutomationProperties.SetName(button, accessibilityName);
    }

    private static void ApplyStopTurnActionAvailability(
        Button button,
        FontIcon icon,
        StopTurnActionAvailability availability)
    {
        button.Visibility = availability.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        button.IsEnabled = availability.IsButtonEnabled;
        button.Opacity = availability.Opacity;
        icon.Glyph = availability.WindowsGlyph;
        AutomationProperties.SetName(button, availability.AccessibilityName);
        AutomationProperties.SetHelpText(button, availability.AccessibilityHint);
        ToolTipService.SetToolTip(button, availability.ToolTip);
    }

    private void ApplyThreadPopoverDragHandlePresentation()
    {
        var presentation = ThreadPopoverDragHandlePresentation.Resolve();
        var foreground = BrushFromHex(presentation.ForegroundHex);
        ThreadPopoverDragHandle.Width = presentation.HitTargetSize;
        ThreadPopoverDragHandle.Height = presentation.HitTargetSize;
        ThreadPopoverDragHandleIcon.Width = presentation.IconWidth;
        ThreadPopoverDragHandleIcon.Height = presentation.IconHeight;
        ApplyThreadPopoverDragLine(
            ThreadPopoverDragLineTop,
            foreground,
            presentation,
            presentation.TopLineOffset);
        ApplyThreadPopoverDragLine(
            ThreadPopoverDragLineMiddle,
            foreground,
            presentation,
            presentation.MiddleLineOffset);
        ApplyThreadPopoverDragLine(
            ThreadPopoverDragLineBottom,
            foreground,
            presentation,
            presentation.BottomLineOffset);
        AutomationProperties.SetName(ThreadPopoverDragHandle, presentation.AccessibilityName);
        ToolTipService.SetToolTip(ThreadPopoverDragHandle, presentation.ToolTip);
    }

    private static void ApplyThreadPopoverDragLine(
        Microsoft.UI.Xaml.Shapes.Rectangle line,
        Brush foreground,
        ThreadPopoverDragHandlePresentationSnapshot presentation,
        double topOffset)
    {
        line.Width = presentation.LineWidth;
        line.Height = presentation.LineHeight;
        line.RadiusX = presentation.LineRadius;
        line.RadiusY = presentation.LineRadius;
        line.Fill = foreground;
        Canvas.SetLeft(line, (presentation.IconWidth - presentation.LineWidth) / 2);
        Canvas.SetTop(line, topOffset);
    }

    private void ApplyArtifactsActionPresentation()
    {
        var presentation = ArtifactsActionPresentation.Resolve();
        var actionForeground = BrushFromHex(presentation.ActionForegroundHex);
        var headerForeground = BrushFromHex(presentation.HeaderForegroundHex);
        var emptyForeground = BrushFromHex(presentation.EmptyForegroundHex);

        ThreadPopoverArtifactsButton.Width = presentation.HitTargetSize;
        ThreadPopoverArtifactsButton.Height = presentation.HitTargetSize;
        ThreadPopoverArtifactsButton.Foreground = actionForeground;
        ThreadPopoverArtifactsShippingBoxIcon.Width = presentation.ActionIconSize;
        ThreadPopoverArtifactsShippingBoxIcon.Height = presentation.ActionIconSize;
        ThreadPopoverArtifactsShippingBoxPath.Stroke = actionForeground;
        ThreadPopoverArtifactsShippingBoxPath.StrokeThickness = presentation.StrokeThickness;
        AutomationProperties.SetName(ThreadPopoverArtifactsButton, presentation.AccessibilityName);
        ToolTipService.SetToolTip(ThreadPopoverArtifactsButton, presentation.ToolTip);

        ArtifactsHeaderShippingBoxIcon.Width = presentation.HeaderIconSize;
        ArtifactsHeaderShippingBoxIcon.Height = presentation.HeaderIconSize;
        ArtifactsHeaderShippingBoxPath.Stroke = headerForeground;
        ArtifactsHeaderShippingBoxPath.StrokeThickness = presentation.StrokeThickness;

        ArtifactsEmptyShippingBoxIcon.Width = presentation.EmptyIconSize;
        ArtifactsEmptyShippingBoxIcon.Height = presentation.EmptyIconSize;
        ArtifactsEmptyShippingBoxPath.Stroke = emptyForeground;
        ArtifactsEmptyShippingBoxPath.StrokeThickness = presentation.StrokeThickness;
    }

    private void ApplyTranscriptFilterPresentation()
    {
        var presentation = TranscriptFilterPresentation.Resolve();
        var foreground = BrushFromHex(presentation.ForegroundHex);

        ThreadPopoverFilterBarGrid.Padding = new Thickness(
            presentation.BarHorizontalPadding,
            presentation.BarVerticalPadding,
            presentation.BarHorizontalPadding,
            presentation.BarVerticalPadding);
        ThreadPopoverFilterColumns.ColumnSpacing = presentation.BarColumnSpacing;
        ThreadPopoverFilterButton.Foreground = foreground;
        ThreadPopoverFilterButton.Padding = new Thickness(
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding,
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding);
        ThreadPopoverFilterButton.CornerRadius = new CornerRadius(presentation.ButtonCornerRadius);
        AutomationProperties.SetName(ThreadPopoverFilterButton, presentation.AccessibilityName);
        ToolTipService.SetToolTip(ThreadPopoverFilterButton, presentation.ToolTip);
        ThreadPopoverFilterContentStack.Spacing = presentation.ButtonContentSpacing;
        ThreadPopoverFilterSummaryText.FontSize = presentation.SummaryFontSize;
        ThreadPopoverFilterDetailText.FontSize = presentation.DetailFontSize;
        ThreadPopoverFilterDetailText.Foreground =
            BrushFromHex(TranscriptFilterPresentation.DetailForegroundHex(isShowingAllRows: true));
        ThreadPopoverResetFiltersButton.Width = presentation.ResetButtonSize;
        ThreadPopoverResetFiltersButton.Height = presentation.ResetButtonSize;
        ThreadPopoverResetFiltersIcon.FontSize = presentation.ResetIconFontSize;
        ThreadPopoverFilterIcon.Width = presentation.IconSize;
        ThreadPopoverFilterIcon.Height = presentation.IconSize;
        ApplyTranscriptFilterIcon(
            ThreadPopoverFilterIconCircle,
            ThreadPopoverFilterIconTopLine,
            ThreadPopoverFilterIconMiddleLine,
            ThreadPopoverFilterIconBottomLine,
            foreground,
            presentation);

        ThreadPopoverFilteredEmptyIcon.Width = presentation.EmptyIconSize;
        ThreadPopoverFilteredEmptyIcon.Height = presentation.EmptyIconSize;
        ApplyTranscriptFilterIcon(
            ThreadPopoverFilteredEmptyIconCircle,
            ThreadPopoverFilteredEmptyIconTopLine,
            ThreadPopoverFilteredEmptyIconMiddleLine,
            ThreadPopoverFilteredEmptyIconBottomLine,
            foreground,
            presentation);

        ApplyTranscriptFilteredEmptyStatePresentation();
    }

    private void ApplyTranscriptFilteredEmptyStatePresentation()
    {
        var presentation = TranscriptFilteredEmptyStatePresentation.Resolve();
        var foreground = BrushFromHex(presentation.ForegroundHex);

        ThreadPopoverFilteredEmptyState.Width = double.NaN;
        ThreadPopoverFilteredEmptyState.MinHeight = 0;
        ThreadPopoverFilteredEmptyState.Padding = new Thickness(presentation.Padding);
        ThreadPopoverFilteredEmptyState.Background = BrushFromHex(presentation.BackgroundHex);
        ThreadPopoverFilteredEmptyState.BorderBrush = BrushFromHex(presentation.BorderHex);
        ThreadPopoverFilteredEmptyState.BorderThickness = new Thickness(presentation.BorderThickness);
        ThreadPopoverFilteredEmptyState.CornerRadius = new CornerRadius(presentation.CornerRadius);
        ThreadPopoverFilteredEmptyContentStack.Spacing = presentation.ContentSpacing;
        ThreadPopoverFilteredEmptyIcon.Width = presentation.IconSize;
        ThreadPopoverFilteredEmptyIcon.Height = presentation.IconSize;
        ThreadPopoverFilteredEmptyTitleText.Text = presentation.Title;
        ThreadPopoverFilteredEmptyTitleText.FontSize = presentation.TitleFontSize;
        ThreadPopoverFilteredEmptyTitleText.Foreground = foreground;
        ThreadPopoverFilteredEmptyResetButton.Padding = new Thickness(
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding,
            presentation.ButtonHorizontalPadding,
            presentation.ButtonVerticalPadding);
        ThreadPopoverFilteredEmptyResetButton.Foreground = foreground;
        ThreadPopoverFilteredEmptyResetStack.Spacing = presentation.ButtonContentSpacing;
        ThreadPopoverFilteredEmptyResetIcon.Glyph = presentation.ButtonWindowsGlyph;
        ThreadPopoverFilteredEmptyResetIcon.FontSize = presentation.ButtonIconFontSize;
        ThreadPopoverFilteredEmptyResetText.Text = presentation.ButtonText;
        ThreadPopoverFilteredEmptyResetText.FontSize = presentation.ButtonTextFontSize;
    }

    private void ApplyCommandFeedbackLayout()
    {
        ApplyCommandFeedbackLayout(CommandFeedbackLayout.Measure());
    }

    private void ApplyCommandFeedbackLayout(CommandFeedbackLayoutMetrics layout)
    {
        CommandFeedbackBubble.Width = layout.Width;
        CommandFeedbackBubble.Padding = new Thickness(
            layout.HorizontalPadding,
            layout.VerticalPadding,
            layout.HorizontalPadding,
            layout.VerticalPadding);
        CommandFeedbackBubble.CornerRadius = new CornerRadius(layout.CornerRadius);
        CommandFeedbackBubble.BorderThickness = new Thickness(layout.BorderThickness);
        CommandFeedbackBubble.Translation = new Vector3(0, 0, (float)layout.ShadowTranslationZ);
        CommandFeedbackText.FontSize = layout.TextFontSize;
        CommandFeedbackText.LineHeight = layout.TextLineHeight;
        CommandFeedbackText.MaxLines = layout.TextMaxLines;
    }

    private static void ApplyTranscriptFilterIcon(
        Microsoft.UI.Xaml.Shapes.Ellipse circle,
        Microsoft.UI.Xaml.Shapes.Line topLine,
        Microsoft.UI.Xaml.Shapes.Line middleLine,
        Microsoft.UI.Xaml.Shapes.Line bottomLine,
        Brush foreground,
        TranscriptFilterPresentationSnapshot presentation)
    {
        var circleSize = presentation.IconSize - (presentation.CircleInset * 2);
        Canvas.SetLeft(circle, presentation.CircleInset);
        Canvas.SetTop(circle, presentation.CircleInset);
        circle.Width = circleSize;
        circle.Height = circleSize;
        circle.Stroke = foreground;
        circle.StrokeThickness = presentation.StrokeThickness;

        ApplyTranscriptFilterLine(topLine, foreground, presentation, y: 5, width: presentation.TopLineWidth);
        ApplyTranscriptFilterLine(middleLine, foreground, presentation, y: 8, width: presentation.MiddleLineWidth);
        ApplyTranscriptFilterLine(bottomLine, foreground, presentation, y: 11, width: presentation.BottomLineWidth);
    }

    private static void ApplyTranscriptFilterLine(
        Microsoft.UI.Xaml.Shapes.Line line,
        Brush foreground,
        TranscriptFilterPresentationSnapshot presentation,
        double y,
        double width)
    {
        line.X1 = 4;
        line.X2 = line.X1 + width;
        line.Y1 = y;
        line.Y2 = y;
        line.Stroke = foreground;
        line.StrokeThickness = presentation.StrokeThickness;
    }

    private void ApplyAttentionRailHeaderPresentation()
    {
        var presentation = AttentionRailHeaderPresentation.Resolve();
        var foreground = BrushFromHex(presentation.StrokeHex);

        AttentionRailHeaderIcon.Width = presentation.IconWidth;
        AttentionRailHeaderIcon.Height = presentation.IconHeight;
        AttentionRailHeaderBubblePath.Stroke = foreground;
        AttentionRailHeaderBubblePath.StrokeThickness = presentation.StrokeThickness;
        AttentionRailHeaderExclamationLine.Stroke = foreground;
        AttentionRailHeaderExclamationLine.StrokeThickness = presentation.StrokeThickness;
        AttentionRailHeaderExclamationLine.Y1 = presentation.ExclamationLineTop;
        AttentionRailHeaderExclamationLine.Y2 = presentation.ExclamationLineBottom;
        AttentionRailHeaderExclamationDot.Fill = foreground;
        AttentionRailHeaderExclamationDot.Width = presentation.ExclamationDotSize;
        AttentionRailHeaderExclamationDot.Height = presentation.ExclamationDotSize;
        AutomationProperties.SetName(AttentionRailHeaderIcon, presentation.AccessibilityName);
    }

    private void ApplyActivitySurfaceHeaderPresentation()
    {
        var presentation = ActivitySurfaceHeaderPresentation.Resolve();
        var foreground = BrushFromHex(presentation.StrokeHex);
        var badge = BrushFromHex(presentation.BadgeHex);

        ActivityRailHeaderIcon.Width = presentation.RailIconWidth;
        ActivityRailHeaderIcon.Height = presentation.RailIconHeight;
        ActivityRailHeaderWaveformPath.Stroke = foreground;
        ActivityRailHeaderWaveformPath.StrokeThickness = presentation.RailStrokeThickness;
        AutomationProperties.SetName(ActivityRailHeaderIcon, presentation.RailAccessibilityName);

        ApplyActivityBellBadgeIcon(
            ActivityRailNotificationPreferencesIcon,
            ActivityRailNotificationPreferencesBellPath,
            ActivityRailNotificationPreferencesBadgeDot,
            foreground,
            badge,
            presentation,
            presentation.PreferencesAccessibilityName);
        ApplyActivityBellBadgeIcon(
            ActivityPopoverHeaderIcon,
            ActivityPopoverHeaderBellPath,
            ActivityPopoverHeaderBadgeDot,
            foreground,
            badge,
            presentation,
            presentation.HistoryAccessibilityName);
        ApplyActivityBellBadgeIcon(
            ActivityPopoverNotificationPreferencesIcon,
            ActivityPopoverNotificationPreferencesBellPath,
            ActivityPopoverNotificationPreferencesBadgeDot,
            foreground,
            badge,
            presentation,
            presentation.PreferencesAccessibilityName);
    }

    private static void ApplyActivityBellBadgeIcon(
        FrameworkElement icon,
        Microsoft.UI.Xaml.Shapes.Path bell,
        Microsoft.UI.Xaml.Shapes.Ellipse badgeDot,
        Brush foreground,
        Brush badge,
        ActivitySurfaceHeaderPresentationSnapshot presentation,
        string accessibilityName)
    {
        icon.Width = presentation.BellIconWidth;
        icon.Height = presentation.BellIconHeight;
        bell.Stroke = foreground;
        bell.StrokeThickness = presentation.BellStrokeThickness;
        badgeDot.Fill = badge;
        badgeDot.Width = presentation.BadgeSize;
        badgeDot.Height = presentation.BadgeSize;
        badgeDot.HorizontalAlignment = HorizontalAlignment.Left;
        badgeDot.VerticalAlignment = VerticalAlignment.Top;
        badgeDot.Margin = new Thickness(presentation.BadgeX, presentation.BadgeY, 0, 0);
        AutomationProperties.SetName(icon, accessibilityName);
    }

    private void ApplyTopNotificationCardPresentation()
    {
        var presentation = TopNotificationCardPresentation.Resolve();
        TopNotificationStack.Spacing = presentation.StackSpacing;
        DismissAllTopNotificationsButton.Padding = new Thickness(
            presentation.DismissAllHorizontalPadding,
            presentation.DismissAllVerticalPadding,
            presentation.DismissAllHorizontalPadding,
            presentation.DismissAllVerticalPadding);
        DismissAllTopNotificationsButton.CornerRadius = new CornerRadius(presentation.DismissAllCornerRadius);
        DismissAllTopNotificationsText.FontSize = presentation.DismissAllFontSize;
    }

    private void ApplyMachinesRailHeaderPresentation()
    {
        var presentation = MachinesRailHeaderPresentation.Resolve();
        var foreground = BrushFromHex(presentation.StrokeHex);

        MachinesRailHeaderIcon.Width = presentation.IconWidth;
        MachinesRailHeaderIcon.Height = presentation.IconHeight;
        ApplyMachinesRailHeaderUnit(MachinesRailHeaderUnitTop, foreground, presentation, row: 0);
        ApplyMachinesRailHeaderUnit(MachinesRailHeaderUnitMiddle, foreground, presentation, row: 1);
        ApplyMachinesRailHeaderUnit(MachinesRailHeaderUnitBottom, foreground, presentation, row: 2);
        ApplyMachinesRailHeaderIndicator(MachinesRailHeaderIndicatorTop, foreground, presentation, row: 0);
        ApplyMachinesRailHeaderIndicator(MachinesRailHeaderIndicatorMiddle, foreground, presentation, row: 1);
        ApplyMachinesRailHeaderIndicator(MachinesRailHeaderIndicatorBottom, foreground, presentation, row: 2);
        AutomationProperties.SetName(MachinesRailHeaderIcon, presentation.AccessibilityName);
    }

    private static void ApplyMachinesRailHeaderUnit(
        Microsoft.UI.Xaml.Shapes.Rectangle unit,
        Brush foreground,
        MachinesRailHeaderPresentationSnapshot presentation,
        int row)
    {
        var top = MachinesRailHeaderUnitTopOffset(presentation, row);
        Canvas.SetLeft(unit, presentation.UnitX);
        Canvas.SetTop(unit, top);
        unit.Width = presentation.UnitWidth;
        unit.Height = presentation.UnitHeight;
        unit.RadiusX = 1.2;
        unit.RadiusY = 1.2;
        unit.Stroke = foreground;
        unit.StrokeThickness = presentation.StrokeThickness;
    }

    private static void ApplyMachinesRailHeaderIndicator(
        Microsoft.UI.Xaml.Shapes.Ellipse indicator,
        Brush foreground,
        MachinesRailHeaderPresentationSnapshot presentation,
        int row)
    {
        var top = MachinesRailHeaderUnitTopOffset(presentation, row) +
            (presentation.UnitHeight - presentation.IndicatorSize) / 2;
        Canvas.SetLeft(indicator, presentation.UnitX + presentation.IndicatorInsetX);
        Canvas.SetTop(indicator, top);
        indicator.Width = presentation.IndicatorSize;
        indicator.Height = presentation.IndicatorSize;
        indicator.Fill = foreground;
    }

    private static double MachinesRailHeaderUnitTopOffset(
        MachinesRailHeaderPresentationSnapshot presentation,
        int row)
    {
        return presentation.UnitTopInset + row * (presentation.UnitHeight + presentation.UnitGap);
    }

    private void ApplyMachineDiscoverySectionPresentation()
    {
        var presentation = MachineDiscoverySectionPresentation.Resolve(
            itemCount: 0,
            isDiscovering: false,
            singularNoun: "remote",
            pluralNoun: "remotes",
            message: null);

        ApplyDiscoverySectionChrome(
            CodexRemotesSectionStack,
            CodexRemotesHeaderGrid,
            CodexRemotesHeaderIcon,
            CodexRemotesHeaderTitleText,
            CodexRemotesCollapseButton,
            CodexRemotesCollapseIcon,
            CodexRemotesContent,
            CodexRemotesCountText,
            CodexRemotesMessageFrame,
            CodexRemotesMessageText,
            CodexRemotesListScrollViewer,
            presentation);

        ApplyDiscoverySectionChrome(
            TailnetSectionStack,
            TailnetHeaderGrid,
            TailnetHeaderIcon,
            TailnetHeaderTitleText,
            TailnetCollapseButton,
            TailnetCollapseIcon,
            TailnetContent,
            TailnetCountText,
            TailnetMessageFrame,
            TailnetMessageText,
            TailnetListScrollViewer,
            presentation);
    }

    private static void ApplyDiscoverySectionChrome(
        StackPanel sectionStack,
        Grid headerGrid,
        FontIcon headerIcon,
        TextBlock headerTitle,
        Button collapseButton,
        FontIcon collapseIcon,
        StackPanel contentStack,
        TextBlock countText,
        Border messageFrame,
        TextBlock messageText,
        ScrollViewer listScrollViewer,
        MachineDiscoverySectionPresentationSnapshot presentation)
    {
        sectionStack.Spacing = presentation.SectionSpacing;
        headerGrid.ColumnSpacing = presentation.HeaderColumnSpacing;
        headerIcon.Width = presentation.HeaderIconWidth;
        headerIcon.FontSize = presentation.HeaderIconFontSize;
        headerTitle.FontSize = presentation.HeaderTitleFontSize;
        collapseButton.Width = presentation.CollapseButtonSize;
        collapseButton.Height = presentation.CollapseButtonSize;
        collapseIcon.FontSize = presentation.CollapseIconFontSize;
        contentStack.Spacing = presentation.ContentSpacing;
        countText.FontSize = presentation.CountFontSize;
        messageText.FontSize = presentation.MessageFontSize;
        messageFrame.Padding = new Thickness(
            presentation.MessageHorizontalPadding,
            presentation.MessageVerticalPadding,
            presentation.MessageHorizontalPadding,
            presentation.MessageVerticalPadding);
        listScrollViewer.MaxHeight = presentation.ListMaxHeight;
    }

    private void ApplyRuntimeDiagnosticsRailHeaderPresentation()
    {
        var presentation = RuntimeDiagnosticsRailHeaderPresentation.Resolve();
        var foreground = BrushFromHex(presentation.StrokeHex);

        RuntimeDiagnosticsRailHeaderIcon.Width = presentation.IconWidth;
        RuntimeDiagnosticsRailHeaderIcon.Height = presentation.IconHeight;
        ApplyRuntimeDiagnosticsRailHeaderEarTip(
            RuntimeDiagnosticsRailHeaderLeftEarTip,
            foreground,
            presentation,
            presentation.LeftEarTipX);
        ApplyRuntimeDiagnosticsRailHeaderEarTip(
            RuntimeDiagnosticsRailHeaderRightEarTip,
            foreground,
            presentation,
            presentation.RightEarTipX);

        RuntimeDiagnosticsRailHeaderTubePath.Stroke = foreground;
        RuntimeDiagnosticsRailHeaderTubePath.StrokeThickness = presentation.StrokeThickness;
        RuntimeDiagnosticsRailHeaderChestPiece.Stroke = foreground;
        RuntimeDiagnosticsRailHeaderChestPiece.StrokeThickness = presentation.StrokeThickness;
        Canvas.SetLeft(RuntimeDiagnosticsRailHeaderChestPiece, presentation.ChestPieceX);
        Canvas.SetTop(RuntimeDiagnosticsRailHeaderChestPiece, presentation.ChestPieceY);
        RuntimeDiagnosticsRailHeaderChestPiece.Width = presentation.ChestPieceSize;
        RuntimeDiagnosticsRailHeaderChestPiece.Height = presentation.ChestPieceSize;
        AutomationProperties.SetName(RuntimeDiagnosticsRailHeaderIcon, presentation.AccessibilityName);
    }

    private void ApplyRuntimeDiagnosticsRailPresentation()
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Pending);
        RuntimeDiagnosticsRailContent.Spacing = presentation.ContentSpacing;
    }

    private void ApplyStatusStripLayout()
    {
        var layout = StatusStripLayout.Resolve();
        StatusStripSurface.Margin = new Thickness(layout.EdgeInset);
        StatusStripSurface.Padding = new Thickness(
            layout.HorizontalPadding,
            layout.VerticalPadding,
            layout.HorizontalPadding,
            layout.VerticalPadding);
        StatusStripSurface.CornerRadius = new CornerRadius(layout.SurfaceCornerRadius);
        StatusStripStack.Spacing = layout.GroupSpacing;
        LocalStatusGroup.Spacing = layout.IconTextSpacing;
        RemoteStatusGroup.Spacing = layout.IconTextSpacing;

        foreach (var icon in new[] { StatusIcon, RemoteStatusIcon })
        {
            icon.FontSize = layout.IconFontSize;
        }

        LocalStatusConnectedIcon.Width = layout.LocalConnectedIconWidth;
        LocalStatusConnectedIcon.Height = layout.LocalConnectedIconHeight;
        LocalStatusConnectedCircle.Width = layout.LocalConnectedIconWidth;
        LocalStatusConnectedCircle.Height = layout.LocalConnectedIconHeight;
        LocalStatusConnectedCheckPath.StrokeThickness = layout.LocalConnectedCheckStrokeThickness;

        RemoteStatusAntennaIcon.Width = layout.RemoteAntennaIconWidth;
        RemoteStatusAntennaIcon.Height = layout.RemoteAntennaIconHeight;
        RemoteStatusAntennaOuterLeftPath.StrokeThickness = layout.RemoteAntennaStrokeThickness;
        RemoteStatusAntennaOuterRightPath.StrokeThickness = layout.RemoteAntennaStrokeThickness;
        RemoteStatusAntennaInnerLeftPath.StrokeThickness = layout.RemoteAntennaStrokeThickness;
        RemoteStatusAntennaInnerRightPath.StrokeThickness = layout.RemoteAntennaStrokeThickness;
        RemoteStatusAntennaStemLine.StrokeThickness = layout.RemoteAntennaStrokeThickness;

        foreach (var text in new[] { StatusText, RemoteStatusText, NodeCountText, LineCountText, StatusErrorText })
        {
            text.FontSize = layout.FontSize;
        }

        foreach (var divider in new[] { LocalStatusDivider, RemoteStatusDivider, StatusErrorDivider })
        {
            divider.Width = layout.DividerWidth;
            divider.Height = layout.DividerHeight;
            divider.Fill = BrushFromHex(layout.DividerFillHex);
        }

        StatusErrorText.MaxWidth = layout.ErrorMaxWidth;
        StatusErrorText.MaxLines = layout.ErrorMaxLines;
        StatusErrorText.IsTextSelectionEnabled = layout.IsErrorTextSelectable;
    }

    private void SetRemoteStatusAntennaBrush(SolidColorBrush brush)
    {
        RemoteStatusAntennaOuterLeftPath.Stroke = brush;
        RemoteStatusAntennaOuterRightPath.Stroke = brush;
        RemoteStatusAntennaInnerLeftPath.Stroke = brush;
        RemoteStatusAntennaInnerRightPath.Stroke = brush;
        RemoteStatusAntennaStemLine.Stroke = brush;
        RemoteStatusAntennaDot.Fill = brush;
    }

    private void ApplyThreadInboxEmptyStateLayout()
    {
        var layout = ThreadInboxEmptyStateLayout.Measure();
        ThreadInboxEmptyText.FontSize = layout.FontSize;
        ThreadInboxEmptyText.Margin = new Thickness(0, layout.VerticalPadding, 0, layout.VerticalPadding);
    }

    private void ApplyThreadInboxSearchFieldLayout()
    {
        var layout = ThreadInboxSearchFieldLayout.Measure();
        var background = BrushFromHex(layout.BackgroundHex);
        var pointerOverBackground = BrushFromHex(layout.PointerOverBackgroundHex);
        var border = BrushFromHex(layout.BorderHex);
        var focusedBorder = BrushFromHex(layout.FocusedBorderHex);
        var foreground = BrushFromHex(layout.ForegroundHex);
        var placeholder = BrushFromHex(layout.PlaceholderForegroundHex);

        ThreadInboxSearchBox.FontSize = layout.FontSize;
        ThreadInboxSearchBox.Height = layout.Height;
        ThreadInboxSearchBox.MinHeight = 0;
        ThreadInboxSearchBox.CornerRadius = new CornerRadius(layout.CornerRadius);
        ThreadInboxSearchBox.Padding = new Thickness(
            layout.HorizontalPadding,
            layout.VerticalPadding,
            layout.HorizontalPadding,
            layout.VerticalPadding);
        ThreadInboxSearchBox.BorderThickness = new Thickness(layout.BorderThickness);
        ThreadInboxSearchBox.Background = background;
        ThreadInboxSearchBox.BorderBrush = border;
        ThreadInboxSearchBox.Foreground = foreground;
        ThreadInboxSearchBox.Resources["TextControlCornerRadius"] = new CornerRadius(layout.CornerRadius);
        ThreadInboxSearchBox.Resources["TextControlBackground"] = background;
        ThreadInboxSearchBox.Resources["TextControlBackgroundPointerOver"] = pointerOverBackground;
        ThreadInboxSearchBox.Resources["TextControlBackgroundFocused"] = background;
        ThreadInboxSearchBox.Resources["TextControlBorderBrush"] = border;
        ThreadInboxSearchBox.Resources["TextControlBorderBrushPointerOver"] = border;
        ThreadInboxSearchBox.Resources["TextControlBorderBrushFocused"] = focusedBorder;
        ThreadInboxSearchBox.Resources["TextControlForeground"] = foreground;
        ThreadInboxSearchBox.Resources["TextControlForegroundPointerOver"] = foreground;
        ThreadInboxSearchBox.Resources["TextControlForegroundFocused"] = foreground;
        ThreadInboxSearchBox.Resources["TextControlPlaceholderForeground"] = placeholder;
        ThreadInboxSearchBox.Resources["TextControlPlaceholderForegroundPointerOver"] = placeholder;
        ThreadInboxSearchBox.Resources["TextControlPlaceholderForegroundFocused"] = placeholder;
    }

    private void ApplyThreadInboxWorkflowFilterLayout()
    {
        var layout = ThreadInboxWorkflowFilterLayout.Measure();
        var background = BrushFromHex(layout.BackgroundHex);
        var pointerOverBackground = BrushFromHex(layout.PointerOverBackgroundHex);
        var pressedBackground = BrushFromHex(layout.PressedBackgroundHex);
        var border = BrushFromHex(layout.BorderHex);
        var focusedBorder = BrushFromHex(layout.FocusedBorderHex);
        var foreground = BrushFromHex(layout.ForegroundHex);
        var chevron = BrushFromHex(layout.ChevronForegroundHex);

        ThreadInboxWorkflowFilterBox.FontSize = layout.FontSize;
        ThreadInboxWorkflowFilterBox.Height = layout.Height;
        ThreadInboxWorkflowFilterBox.MinHeight = 0;
        ThreadInboxWorkflowFilterBox.MinWidth = 0;
        ThreadInboxWorkflowFilterBox.CornerRadius = new CornerRadius(layout.CornerRadius);
        ThreadInboxWorkflowFilterBox.Padding = new Thickness(
            layout.HorizontalPadding,
            layout.VerticalPadding,
            layout.HorizontalPadding,
            layout.VerticalPadding);
        ThreadInboxWorkflowFilterBox.BorderThickness = new Thickness(layout.BorderThickness);
        ThreadInboxWorkflowFilterBox.Background = background;
        ThreadInboxWorkflowFilterBox.BorderBrush = border;
        ThreadInboxWorkflowFilterBox.Foreground = foreground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxCornerRadius"] = new CornerRadius(layout.CornerRadius);
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBackground"] = background;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBackgroundPointerOver"] = pointerOverBackground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBackgroundPressed"] = pressedBackground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBackgroundFocused"] = background;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBorderBrush"] = border;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBorderBrushPointerOver"] = border;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBorderBrushPressed"] = border;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxBorderBrushFocused"] = focusedBorder;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxForeground"] = foreground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxForegroundPointerOver"] = foreground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxForegroundPressed"] = foreground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxForegroundFocused"] = foreground;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxDropDownGlyphForeground"] = chevron;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxDropDownGlyphForegroundPointerOver"] = chevron;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxDropDownGlyphForegroundPressed"] = chevron;
        ThreadInboxWorkflowFilterBox.Resources["ComboBoxDropDownGlyphForegroundFocused"] = chevron;
    }

    private static void ApplyRuntimeDiagnosticsRailHeaderEarTip(
        Microsoft.UI.Xaml.Shapes.Ellipse earTip,
        Brush foreground,
        RuntimeDiagnosticsRailHeaderPresentationSnapshot presentation,
        double x)
    {
        Canvas.SetLeft(earTip, x);
        Canvas.SetTop(earTip, presentation.EarTipY);
        earTip.Width = presentation.EarTipSize;
        earTip.Height = presentation.EarTipSize;
        earTip.Fill = foreground;
    }

    private void MentionCatalogSession_CatalogChanged(
        object? sender,
        MentionCatalogChangedEventArgs eventArgs)
    {
        if (!_windowLifetime.TryCapture(out var lease))
        {
            return;
        }

        _ = _windowLifetime.TryDispatch(
            lease,
            callback => DispatcherQueue.TryEnqueue(() => callback()),
            RefreshVisibleMentionSuggestions);
    }

    private bool RunWindowOperation(Func<WindowLifetimeLease, Task> operation)
    {
        return _windowLifetime.TryRunTracked(operation, out _);
    }

    private async void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        if (_windowLifetime.IsShuttingDown)
        {
            return;
        }

        UninstallWindowMinimumSizeHook();
        RootGrid.Loaded -= MainWindow_Loaded;
        _mentionCatalogSession.CatalogChanged -= MentionCatalogSession_CatalogChanged;
        if (GraphView.CoreWebView2 is not null)
        {
            GraphView.CoreWebView2.NavigationCompleted -= GraphView_NavigationCompleted;
            GraphView.CoreWebView2.WebMessageReceived -= GraphView_WebMessageReceived;
        }

        StopThreadAutomationRefreshTimer();
        _newThreadModelRefreshCancellation?.Cancel();
        _workflowHookEventBridgeCancellation?.Cancel();
        StopAllCodexRemoteTunnels();

        try
        {
            var producerFaults = await _windowLifetime.ShutdownAsync();
            foreach (var fault in producerFaults)
            {
                Debug.WriteLine($"Window background producer failed during shutdown: {fault}");
            }
        }
        finally
        {
            _newThreadModelRefreshCancellation?.Dispose();
            _newThreadModelRefreshCancellation = null;
            DisposeWorkflowHookEventBridgeResources();
            if (!_windowStoresDisposed)
            {
                _windowStoresDisposed = true;
                _transcriptSessions.Dispose();
                _mentionCatalogSession.Dispose();
                _readerMentionSelections.Clear();
            }

            _windowLifetime.Dispose();
        }
    }

    private void StartWorkflowHookEventBridge()
    {
        if (_workflowHookEventBridgeTask is { IsCompleted: false } ||
            !_windowLifetime.TryCapture(out var windowLease))
        {
            return;
        }

        DisposeWorkflowHookEventBridgeResources();
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(windowLease.CancellationToken);
        if (!_windowLifetime.TryRunTracked(
            lease => _workflowHookEventFileBridge.RunAsync(
                (events, eventCancellationToken) =>
                {
                    if (!eventCancellationToken.IsCancellationRequested)
                    {
                        _ = _windowLifetime.TryDispatch(
                            lease,
                            callback => DispatcherQueue.TryEnqueue(() => callback()),
                            () =>
                            {
                                _ = _windowLifetime.TryRunTracked(
                                    ignoredLease => ApplyWorkflowHookEventsSafelyAsync(events),
                                    out _);
                            });
                    }

                    return Task.CompletedTask;
                },
                replayExistingEvents: false,
                cancellationToken: cancellation.Token),
            out var task))
        {
            cancellation.Dispose();
            return;
        }

        _workflowHookEventBridgeCancellation = cancellation;
        _workflowHookEventBridgeTask = task;
    }

    private void DisposeWorkflowHookEventBridgeResources()
    {
        _workflowHookEventBridgeCancellation?.Dispose();
        _workflowHookEventBridgeCancellation = null;
        _workflowHookEventBridgeTask = null;
    }

    private void StartThreadAutomationRefreshTimer()
    {
        if (_windowLifetime.IsShuttingDown)
        {
            return;
        }

        StopThreadAutomationRefreshTimer();
        _threadAutomationRefreshTimer = DispatcherQueue.CreateTimer();
        _threadAutomationRefreshTimer.Interval = TimeSpan.FromSeconds(10);
        _threadAutomationRefreshTimer.Tick += ThreadAutomationRefreshTimer_Tick;
        _threadAutomationRefreshTimer.Start();
    }

    private void ThreadAutomationRefreshTimer_Tick(
        Microsoft.UI.Dispatching.DispatcherQueueTimer sender,
        object args)
    {
        _ = RefreshThreadAutomationsAsync(renderAfterChange: true);
    }

    private void StopThreadAutomationRefreshTimer()
    {
        if (_threadAutomationRefreshTimer is null)
        {
            return;
        }

        _threadAutomationRefreshTimer.Stop();
        _threadAutomationRefreshTimer.Tick -= ThreadAutomationRefreshTimer_Tick;
        _threadAutomationRefreshTimer = null;
    }

    private Task RefreshThreadAutomationsAsync(bool renderAfterChange)
    {
        _threadAutomationRenderRequested |= renderAfterChange;
        if (_threadAutomationRefreshTask is { IsCompleted: false })
        {
            return _threadAutomationRefreshTask;
        }

        if (!_windowLifetime.TryRunTracked(
            RefreshThreadAutomationsCoreAsync,
            out var task))
        {
            return Task.CompletedTask;
        }

        _threadAutomationRefreshTask = task;
        return task;
    }

    private async Task RefreshThreadAutomationsCoreAsync(WindowLifetimeLease lease)
    {
        var previousSignature = AutomationSignature(_threadAutomationsByThreadId);
        IReadOnlyDictionary<string, CodexAutomationSummary> automations;
        try
        {
            automations = await Task.Run(
                () => _automationStore.LoadAutomationsByThreadId(),
                lease.CancellationToken);
        }
        catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
        {
            return;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or CodexAutomationStoreException)
        {
            automations = new Dictionary<string, CodexAutomationSummary>(StringComparer.OrdinalIgnoreCase);
        }

        if (!_windowLifetime.IsCurrent(lease))
        {
            return;
        }

        _threadAutomationsByThreadId = new Dictionary<string, CodexAutomationSummary>(
            automations,
            StringComparer.OrdinalIgnoreCase);
        var shouldRender = _threadAutomationRenderRequested;
        _threadAutomationRenderRequested = false;
        if (!shouldRender ||
            string.Equals(previousSignature, AutomationSignature(_threadAutomationsByThreadId), StringComparison.Ordinal))
        {
            return;
        }

        if (SelectedThreadNode() is { } selectedThread &&
            ThreadPopover.Visibility == Visibility.Visible)
        {
            UpdateThreadPopover(selectedThread);
        }

        UpdateChrome();
        await RenderGraphAsync();
    }

    private static string AutomationSignature(IReadOnlyDictionary<string, CodexAutomationSummary> automations)
    {
        return string.Join(
            "\u001F",
            automations
                .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                .Select(pair => string.Join(
                    "\u001E",
                    pair.Key,
                    pair.Value.Id,
                    pair.Value.Name,
                    pair.Value.Status,
                    pair.Value.RRule,
                    pair.Value.UpdatedAt?.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture) ?? "")));
    }

    private async Task ApplyWorkflowHookEventsSafelyAsync(IReadOnlyList<WorkflowEvent> events)
    {
        try
        {
            await ApplyWorkflowHookEventsAsync(events);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            AddActivity(
                $"Workflow hook event failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
            UpdateChrome();
        }
    }

    private async Task ApplyWorkflowHookEventsAsync(IReadOnlyList<WorkflowEvent> events)
    {
        var appliedNodeIDs = new List<string>();
        foreach (var workflowEvent in events)
        {
            if (!_ingestedWorkflowHookEventKeys.Add(workflowEvent.DedupeKey))
            {
                continue;
            }

            var result = WorkflowEventIngestor.Apply(_graph, workflowEvent);
            if (result.Applied && !string.IsNullOrWhiteSpace(result.NodeID))
            {
                appliedNodeIDs.Add(result.NodeID);
            }
        }

        if (appliedNodeIDs.Count == 0)
        {
            return;
        }

        await SaveGraphAsync();
        AddActivity(WorkflowHookEventActivityMessage(appliedNodeIDs));
        UpdateChrome();
        await RenderGraphAsync();
    }

    private string WorkflowHookEventActivityMessage(IReadOnlyList<string> appliedNodeIDs)
    {
        if (appliedNodeIDs.Count == 1 &&
            _graph.Nodes.TryGetValue(appliedNodeIDs[0], out var node))
        {
            return $"Materialized workflow folder {node.Title}.";
        }

        return $"Materialized {appliedNodeIDs.Count} workflow folder events.";
    }

    private void ConfigureOperationalRailPlacement()
    {
        var operationalLayout = OperationalRailLayout.MeasureForBottomInboxOverlay(RootHeight());
        OperationalRailsScroll.Width = operationalLayout.Width;
        OperationalRailsScroll.MaxHeight = operationalLayout.MaxHeight;
        OperationalRailsScroll.Margin = new Thickness(
            0,
            operationalLayout.TopInset,
            operationalLayout.RightInset,
            operationalLayout.BottomInset);
        OperationalRailsScroll.HorizontalAlignment = HorizontalAlignment.Right;
        OperationalRailsScroll.VerticalAlignment = VerticalAlignment.Top;
        OperationalRails.Width = operationalLayout.ContentWidth;
        OperationalRails.Margin = new Thickness(0, operationalLayout.ContentInset, 0, operationalLayout.ContentInset);
        OperationalRails.HorizontalAlignment = HorizontalAlignment.Right;

        if (ThreadInboxRail.Parent is Panel parent && parent != RootGrid)
        {
            parent.Children.Remove(ThreadInboxRail);
        }

        if (ThreadInboxRail.Parent is null)
        {
            RootGrid.Children.Add(ThreadInboxRail);
        }

        var layout = ThreadInboxDockLayout.Measure(RootHeight());
        ThreadInboxRail.Width = layout.Width;
        ThreadInboxRail.Margin = new Thickness(0, 0, layout.RightInset, layout.BottomInset);
        ThreadInboxRail.HorizontalAlignment = HorizontalAlignment.Right;
        ThreadInboxRail.VerticalAlignment = VerticalAlignment.Bottom;
        ThreadInboxRail.MaxHeight = layout.MaxHeight;
        ThreadInboxRail.Padding = new Thickness(layout.Padding);
        ThreadInboxRail.CornerRadius = new CornerRadius(layout.CornerRadius);
        ThreadInboxRail.BorderThickness = new Thickness(layout.BorderThickness);
        ThreadInboxRail.Translation = new Vector3(0, 0, (float)layout.ShadowTranslationZ);
        Canvas.SetZIndex(ThreadInboxRail, layout.ZIndex);
    }

    private void ApplyPreferences(AppPreferences preferences)
    {
        _showsSubagents = preferences.ShowSubagents;
        _notifyOnCompleted = preferences.NotifyOnCompleted;
        _notifyOnNeedsInput = preferences.NotifyOnNeedsInput;
        _notifyOnFailed = preferences.NotifyOnFailed;
        _isCodexRemotesCollapsed = preferences.CodexRemotesCollapsed;
        _isTailnetCollapsed = preferences.TailnetCollapsed;
        _isThreadInboxCollapsed = preferences.ThreadInboxCollapsed;
        _isActivityRailCollapsed = preferences.ActivityRailCollapsed;
        _isAttentionRailCollapsed = preferences.AttentionRailCollapsed;
        _isRuntimeDiagnosticsCollapsed = preferences.RuntimeDiagnosticsCollapsed;
    }

    private void SavePreferences()
    {
        _preferences = new AppPreferences
        {
            ShowSubagents = _showsSubagents,
            NotifyOnCompleted = _notifyOnCompleted,
            NotifyOnNeedsInput = _notifyOnNeedsInput,
            NotifyOnFailed = _notifyOnFailed,
            CodexRemotesCollapsed = _isCodexRemotesCollapsed,
            TailnetCollapsed = _isTailnetCollapsed,
            ThreadInboxCollapsed = _isThreadInboxCollapsed,
            ActivityRailCollapsed = _isActivityRailCollapsed,
            AttentionRailCollapsed = _isAttentionRailCollapsed,
            RuntimeDiagnosticsCollapsed = _isRuntimeDiagnosticsCollapsed
        };

        try
        {
            _preferencesStore.Save(_preferences);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            AddActivity(
                $"Could not save preferences: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void RegisterThreadPopoverDragHandlers()
    {
        ThreadPopover.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerPressed),
            true);
        ThreadPopoverDragHandle.AddHandler(
            UIElement.PointerPressedEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerPressed),
            true);
        RootGrid.AddHandler(
            UIElement.PointerMovedEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerMoved),
            true);
        RootGrid.AddHandler(
            UIElement.PointerReleasedEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerReleased),
            true);
        RootGrid.AddHandler(
            UIElement.PointerCanceledEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerCanceled),
            true);
        ThreadPopoverDragHandle.AddHandler(
            UIElement.PointerCaptureLostEvent,
            new PointerEventHandler(ThreadPopoverDragHandle_PointerCaptureLost),
            true);
    }

    private void ConfigureWindow()
    {
        InstallWindowMinimumSizeHook(WindowNative.GetWindowHandle(this));
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;
        var bounds = WindowStartupPlacement.CenterInWorkArea(
            workArea.X,
            workArea.Y,
            workArea.Width,
            workArea.Height,
            preferredWidth: WindowStartupPlacement.PreferredWidth,
            preferredHeight: WindowStartupPlacement.PreferredHeight);
        AppWindow.MoveAndResize(new RectInt32(bounds.X, bounds.Y, bounds.Width, bounds.Height));
        GraphView.DefaultBackgroundColor = WindowChromeColor(255, 29, 30, 32);
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBarDragRegion);
        ConfigureTitleBarChrome();

        if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop();
        }
    }

    private void InstallWindowMinimumSizeHook(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero || _originalWindowProc != IntPtr.Zero)
        {
            return;
        }

        _windowHandle = windowHandle;
        _minimumSizeWindowProc = WindowMinimumSizeProc;
        _originalWindowProc = SetWindowLongPtr(
            windowHandle,
            GwlWndProc,
            Marshal.GetFunctionPointerForDelegate(_minimumSizeWindowProc));
    }

    private void UninstallWindowMinimumSizeHook()
    {
        if (_windowHandle == IntPtr.Zero || _originalWindowProc == IntPtr.Zero)
        {
            return;
        }

        _ = SetWindowLongPtr(_windowHandle, GwlWndProc, _originalWindowProc);
        _windowHandle = IntPtr.Zero;
        _originalWindowProc = IntPtr.Zero;
        _minimumSizeWindowProc = null;
    }

    private IntPtr WindowMinimumSizeProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmGetMinMaxInfo && lParam != IntPtr.Zero)
        {
            var minMax = Marshal.PtrToStructure<MinMaxInfo>(lParam);
            var minimum = WindowStartupPlacement.MinimumTrackSizeForDpi(GetDpiForWindow(hwnd));
            minMax.MinTrackSize.X = Math.Max(minMax.MinTrackSize.X, minimum.Width);
            minMax.MinTrackSize.Y = Math.Max(minMax.MinTrackSize.Y, minimum.Height);
            Marshal.StructureToPtr(minMax, lParam, false);
        }

        return _originalWindowProc != IntPtr.Zero
            ? CallWindowProc(_originalWindowProc, hwnd, message, wParam, lParam)
            : DefWindowProc(hwnd, message, wParam, lParam);
    }

    private void ConfigureTitleBarChrome()
    {
        if (!AppWindowTitleBar.IsCustomizationSupported())
        {
            return;
        }

        var titleBar = AppWindow.TitleBar;
        titleBar.IconShowOptions = IconShowOptions.HideIconAndSystemMenu;
        titleBar.BackgroundColor = Colors.Transparent;
        titleBar.InactiveBackgroundColor = Colors.Transparent;
        titleBar.ForegroundColor = WindowChromeColor(255, 215, 220, 229);
        titleBar.InactiveForegroundColor = WindowChromeColor(255, 143, 155, 170);
        titleBar.ButtonBackgroundColor = Colors.Transparent;
        titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        titleBar.ButtonForegroundColor = WindowChromeColor(214, 215, 220, 229);
        titleBar.ButtonInactiveForegroundColor = WindowChromeColor(140, 167, 176, 191);
        titleBar.ButtonHoverForegroundColor = Colors.White;
        titleBar.ButtonPressedForegroundColor = Colors.White;
        titleBar.ButtonHoverBackgroundColor = WindowChromeColor(24, 255, 255, 255);
        titleBar.ButtonPressedBackgroundColor = WindowChromeColor(36, 255, 255, 255);
    }

    private static Windows.UI.Color WindowChromeColor(byte alpha, byte red, byte green, byte blue)
    {
        return Windows.UI.Color.FromArgb(alpha, red, green, blue);
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        RootGrid.Loaded -= MainWindow_Loaded;
        ConfigureOperationalRailPlacement();
        _ = _windowLifetime.TryRunTracked(InitializeMainWindowAsync, out _);
    }

    private async Task InitializeMainWindowAsync(WindowLifetimeLease lease)
    {
        try
        {
            await InitializeGraphViewAsync(lease);
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            _graph = await _store.LoadOrCreateAsync();
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            SetStatusStripError(null);
            await RefreshWorkflowMenuAsync();
            await RefreshWorkflowMembershipsAsync();
            await RefreshThreadAutomationsAsync(renderAfterChange: false);
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            StartThreadAutomationRefreshTimer();
            RebuildAppServerEndpointsFromGraph();
            StartWorkflowHookEventBridge();
            SyncLocalRuntimeStatusFromGraph();
            AddActivity("Loaded local control-room graph.");
            UpdateChrome();
            if (AppServerCatalogEndpoints().Any())
            {
                await RefreshAppServerThreadCatalogAsync(search: false);
            }

            await RenderGraphAsync();
        }
        catch (Exception exception)
        {
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            SetStatusStripError(exception.Message);
            SetStatus(HostStatuses.Unavailable, "Startup failed", exception.Message);
            AddActivity(
                $"Startup failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void RootGrid_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ConfigureOperationalRailPlacement();
        UpdateReaderHeaderLayout();
        if (_isReadingModePresented)
        {
            UpdateReader();
        }
        else if (SelectedThreadNode() is { } selectedThreadNode &&
            ThreadPopover.Visibility == Visibility.Visible)
        {
            UpdateThreadPopover(selectedThreadNode);
        }
        else if (_selectedEdgeId is not null &&
            _graph.ManualEdges.ContainsKey(_selectedEdgeId) &&
            SelectionInspector.Visibility == Visibility.Visible)
        {
            ApplySelectionInspectorLayout(SelectionInspectorLayout.ForEdge());
        }

        UpdateTopNotificationsChrome();
    }

    private async Task InitializeGraphViewAsync(WindowLifetimeLease? lease = null)
    {
        if (_webViewReady || !WindowLeaseIsCurrent(lease))
        {
            return;
        }

        var webViewUserDataDirectory = ApplicationSupportFolder.EnsureWebView2UserDataDirectory(
            WindowsLocalApplicationDataDirectory());
        var webViewEnvironment = await CoreWebView2Environment.CreateWithOptionsAsync(
            null,
            webViewUserDataDirectory,
            null);

        if (!WindowLeaseIsCurrent(lease))
        {
            return;
        }

        await GraphView.EnsureCoreWebView2Async(webViewEnvironment);
        if (!WindowLeaseIsCurrent(lease))
        {
            return;
        }

        GraphView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        GraphView.CoreWebView2.Settings.AreDevToolsEnabled = false;
        GraphView.CoreWebView2.Settings.IsStatusBarEnabled = false;
        GraphView.CoreWebView2.NavigationCompleted += GraphView_NavigationCompleted;
        GraphView.CoreWebView2.WebMessageReceived += GraphView_WebMessageReceived;
        _webViewReady = true;
    }

    private bool WindowLeaseIsCurrent(WindowLifetimeLease? lease)
    {
        return lease is { } captured
            ? _windowLifetime.IsCurrent(captured)
            : !_windowLifetime.IsShuttingDown;
    }

    private static string WindowsLocalApplicationDataDirectory()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MapofAgents",
            "MapofAgents.Windows");
    }

    private void GraphView_NavigationCompleted(CoreWebView2 sender, CoreWebView2NavigationCompletedEventArgs args)
    {
        if (_windowLifetime.IsShuttingDown)
        {
            return;
        }

        _graphDocumentReady = args.IsSuccess;
        if (!args.IsSuccess)
        {
            var message = $"Graph view navigation failed: {args.WebErrorStatus}";
            SetStatusStripError(message);
            AddActivity(
                message,
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void ConnectButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(ConnectFromFormAsync);
    }

    private async Task ConnectFromFormAsync(WindowLifetimeLease lease)
    {
        var token = string.IsNullOrWhiteSpace(BearerTokenBox.Password)
            ? null
            : BearerTokenBox.Password.Trim();
        var preparation = _appServerConnectionController.Prepare(new AppServerConnectionRequest(
            EndpointBox.Text,
            RemoteNameBox.Text,
            token,
            ImportedPairingEndpointTrust(token)));
        if (!preparation.IsValid)
        {
            var message = preparation.ErrorMessage ?? "Endpoint validation failed.";
            SetStatus(HostStatuses.Unavailable, "Invalid endpoint", message);
            AddActivity(
                message,
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
            _isMachineConnectFormVisible = true;
            UpdateChrome();
            return;
        }

        var endpoint = preparation.Endpoint!;
        ConnectButton.IsEnabled = false;
        SetStatus(HostStatuses.Connecting, "Connecting", endpoint.Url.ToString());
        AddActivity($"Connecting to {endpoint.Url}");

        try
        {
            var outcome = await _appServerConnectionController.ConnectAsync(
                preparation,
                lease.CancellationToken);
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            if (!outcome.IsConnected || outcome.InitializeResult is not { } result)
            {
                PublishConnectionFailure(outcome.Message);
                return;
            }

            var machineID = UpsertMachineFromInitialize(endpoint.Url, result);
            _connectedAppServerEndpointsByHostId[machineID] = new AppServerEndpoint(
                result.HostName,
                endpoint.Url,
                endpoint.BearerToken,
                endpoint.Trust);
            await RefreshNewThreadModelOptionsForHostAsync(
                machineID,
                _connectedAppServerEndpointsByHostId[machineID],
                lease.CancellationToken);
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            await SaveGraphAsync();
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            SetStatus(HostStatuses.Connected, "Connected", $"{result.HostName} - {result.Platform}");
            AddActivity($"Connected: {result.HostName} ({result.Platform})");
            await RefreshAppServerThreadCatalogAsync(search: false);
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            _isMachineConnectFormVisible = false;
            BearerTokenBox.Password = "";
            UpdateChrome();
            await RenderGraphAsync();
        }
        catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
        {
            // Window shutdown owns cancellation and suppresses late UI updates.
        }
        catch (Exception exception)
        {
            if (_windowLifetime.IsCurrent(lease))
            {
                PublishConnectionFailure(exception.Message);
            }
        }
        finally
        {
            if (_windowLifetime.IsCurrent(lease))
            {
                ConnectButton.IsEnabled = true;
                UpdateConnectButtonAvailability();
            }
        }
    }

    private void PublishConnectionFailure(string message)
    {
        SetStatus(HostStatuses.Unavailable, "Connection failed", message);
        AddActivity(
            $"Connection failed: {message}",
            showTopNotification: true,
            notificationKind: ActivityNotificationKindFailed);
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _isMachineConnectFormVisible = true;
        UpdateChrome();
    }

    private void EndpointBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateConnectButtonAvailability();
        UpdateBearerTokenBoxVisibility();
    }

    private void BearerTokenBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        UpdateConnectButtonAvailability();
        UpdateBearerTokenBoxVisibility();
    }

    private void UpdateConnectButtonAvailability()
    {
        if (ConnectButton is null || EndpointBox is null)
        {
            return;
        }

        ConnectButton.Opacity = string.IsNullOrWhiteSpace(EndpointBox.Text) ? 0.48 : 1;
    }

    private void UpdateBearerTokenBoxVisibility()
    {
        if (BearerTokenBox is null || EndpointBox is null)
        {
            return;
        }

        BearerTokenBox.Visibility = ShouldShowBearerTokenBox(
            EndpointBox.Text,
            BearerTokenBox.Password)
                ? Visibility.Visible
                : Visibility.Collapsed;
    }

    private static bool ShouldShowBearerTokenBox(string endpointText, string? bearerToken)
    {
        if (!string.IsNullOrWhiteSpace(bearerToken))
        {
            return true;
        }

        return Uri.TryCreate(endpointText.Trim(), UriKind.Absolute, out var endpointUri) &&
            !AppServerEndpointValidator.IsLoopback(endpointUri);
    }

    private AppServerEndpointTrust ImportedPairingEndpointTrust(string? bearerToken)
    {
        if (string.IsNullOrWhiteSpace(_importedPairingEndpointUrl) ||
            string.IsNullOrWhiteSpace(_importedPairingBearerToken) ||
            string.IsNullOrWhiteSpace(bearerToken))
        {
            return AppServerEndpointTrust.Standard;
        }

        return string.Equals(EndpointBox.Text.Trim(), _importedPairingEndpointUrl, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(bearerToken.Trim(), _importedPairingBearerToken, StringComparison.Ordinal)
                ? AppServerEndpointTrust.SignedPairingPayload
                : AppServerEndpointTrust.Standard;
    }

    private void AddMachineButton_Click(object sender, RoutedEventArgs e)
    {
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _isMachineConnectFormVisible = !_isMachineConnectFormVisible;
        AddActivity(_isMachineConnectFormVisible ? "Add remote form opened." : "Add remote form closed.");
        UpdateChrome();
        UpdateConnectButtonAvailability();
        UpdateBearerTokenBoxVisibility();
        if (_isMachineConnectFormVisible)
        {
            RemoteNameBox.Focus(FocusState.Programmatic);
            RemoteNameBox.SelectAll();
        }
    }

    private void CodexRemotesCollapseButton_Click(object sender, RoutedEventArgs e)
    {
        _isCodexRemotesCollapsed = !_isCodexRemotesCollapsed;
        SavePreferences();
        UpdateChrome();
    }

    private void TailnetCollapseButton_Click(object sender, RoutedEventArgs e)
    {
        _isTailnetCollapsed = !_isTailnetCollapsed;
        SavePreferences();
        UpdateChrome();
    }

    private void DiscoverMachinesButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (IsDiscoveringMachines)
            {
                ShowCommandFeedback("Machine discovery is already running.");
                return;
            }

            await DiscoverMachinesForRailAsync(automatic: false);

        });
    }

    private async Task DiscoverMachinesForRailAsync(bool automatic, bool showMachinesRail = true)
    {
        if (IsDiscoveringMachines)
        {
            return;
        }

        _hasRequestedInitialMachineDiscovery = true;
        if (showMachinesRail)
        {
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
        }

        _isDiscoveringCodexRemotes = true;
        _isDiscoveringTailnet = true;
        _codexRemoteDiscoveryMessage = "Discovering Codex remotes...";
        _tailnetDiscoveryMessage = "Discovering tailnet machines...";
        AddActivity(automatic
            ? "Discovering Codex remotes and tailnet machines for the Machines panel."
            : "Discovering Codex remotes and tailnet machines.");
        UpdateChrome();

        try
        {
            await Task.WhenAll(
                DiscoverCodexRemotesForRailAsync(),
                DiscoverTailnetMachinesForRailAsync());
        }
        catch (OperationCanceledException)
        {
            _codexRemoteDiscoveryMessage = "Machine discovery was canceled.";
            _tailnetDiscoveryMessage = "Tailnet discovery was canceled.";
            AddActivity("Machine discovery canceled.");
        }
        finally
        {
            _isDiscoveringCodexRemotes = false;
            _isDiscoveringTailnet = false;
            UpdateChrome();
        }
    }

    private void MaybeStartInitialMachineDiscovery()
    {
        if (!MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
                _hasRequestedInitialMachineDiscovery,
                _isReadingModePresented,
                _isMachinesFlyoutOpen,
                _isMachinesRailCollapsed,
                _isDiscoveringCodexRemotes,
                _isDiscoveringTailnet))
        {
            return;
        }

        _hasRequestedInitialMachineDiscovery = true;
        RunWindowOperation(_ => DiscoverMachinesForRailAsync(automatic: true));
    }

    private async Task DiscoverCodexRemotesForRailAsync()
    {
        try
        {
            var remotes = await CodexDesktopRemoteService.DiscoverAsync();
            _discoveredCodexRemotes.Clear();
            _discoveredCodexRemotes.AddRange(remotes);
            _codexRemoteDiscoveryMessage = remotes.Count == 0 ? "No Codex remotes found." : null;
            AddActivity($"Discovered {remotes.Count} Codex remote{(remotes.Count == 1 ? "" : "s")}.");
        }
        catch (CodexDesktopRemoteException exception)
        {
            _discoveredCodexRemotes.Clear();
            _codexRemoteDiscoveryMessage = exception.Message;
            AddActivity(
                $"Codex remote discovery failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private async Task DiscoverTailnetMachinesForRailAsync()
    {
        try
        {
            var machines = await TailnetDiscoveryService.DiscoverAsync();
            _discoveredTailnetMachines.Clear();
            _discoveredTailnetMachines.AddRange(machines);
            _tailnetDiscoveryMessage = machines.Count == 0 ? "No tailnet machines found." : null;
            AddActivity($"Discovered {machines.Count} tailnet machine{(machines.Count == 1 ? "" : "s")}.");
        }
        catch (TailnetDiscoveryException exception)
        {
            _discoveredTailnetMachines.Clear();
            _tailnetDiscoveryMessage = exception.Message;
            AddActivity(
                $"Tailnet discovery failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void FillRemoteDiscoveryEndpointButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: RemoteDiscoveryItem item })
        {
            ShowCommandFeedback(MachineDiscoveryActionPresentation.FillEndpointUnavailableReason);
            return;
        }

        if (string.IsNullOrWhiteSpace(item.Endpoint))
        {
            AddActivity(item.FillTooltip);
            ShowCommandFeedback(item.FillTooltip);
            return;
        }

        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _isMachineConnectFormVisible = true;
        RemoteNameBox.Text = item.Title;
        EndpointBox.Text = item.Endpoint;
        BearerTokenBox.Password = "";
        AddActivity($"Prepared {item.Title} endpoint.");
        UpdateChrome();
        UpdateBearerTokenBoxVisibility();
        EndpointBox.Focus(FocusState.Programmatic);
        EndpointBox.SelectAll();
    }

    private void OpenCodexRemoteDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: RemoteDiscoveryItem item } ||
                !item.IsCodexRemote)
            {
                return;
            }

            if (!TryFindCodexRemote(item.RemoteId, out var remote))
            {
                ShowCommandFeedback("This Codex remote is no longer available. Run discovery again.");
                return;
            }

            await ShowCodexRemoteDiagnosticsDialogAsync(remote);

        });
    }

    private async Task ShowCodexRemoteDiagnosticsDialogAsync(CodexDesktopRemote remote)
    {
        var titleBlock = new TextBlock
        {
            Text = remote.DisplayName,
            FontSize = 18,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#F2F5F9"),
            IsTextSelectionEnabled = true,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var subtitleBlock = new TextBlock
        {
            Text = remote.Hostname ?? remote.HostID,
            FontSize = 12,
            Foreground = BrushFromHex("#A7B0BF"),
            IsTextSelectionEnabled = true,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var headerText = new StackPanel
        {
            Spacing = 3
        };
        headerText.Children.Add(titleBlock);
        headerText.Children.Add(subtitleBlock);

        var headerIconSurface = new Border
        {
            Width = 34,
            Height = 34,
            CornerRadius = new CornerRadius(8),
            Background = BrushFromHex("#180A84FF"),
            Child = new FontIcon
            {
                Glyph = "\uE9D9",
                FontSize = 17,
                Foreground = BrushFromHex("#0A84FF")
            }
        };
        var header = new Grid
        {
            ColumnSpacing = 12
        };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(headerText, 1);
        header.Children.Add(headerIconSurface);
        header.Children.Add(headerText);

        var actionStack = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        Grid.SetColumn(actionStack, 2);
        header.Children.Add(actionStack);

        var rerunButton = RemoteDiagnosticsActionButton("\uE72C", "Re-run", "Run the full remote diagnostic again");
        var connectButton = RemoteDiagnosticsActionButton("\uE8CE", "Connect", "Start the remote App Server and attach the workflow relay");
        var copyButton = RemoteDiagnosticsActionButton("\uE8C8", "Copy Report", "Copy a token-redacted diagnostic report");
        actionStack.Children.Add(rerunButton);
        actionStack.Children.Add(connectButton);
        actionStack.Children.Add(copyButton);

        var summaryGrid = new Grid
        {
            ColumnSpacing = 14,
            RowSpacing = 8
        };
        for (var index = 0; index < 3; index++)
        {
            summaryGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }
        summaryGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        summaryGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var summarySurface = new Border
        {
            Padding = new Thickness(10),
            Background = BrushFromHex("#3D18191B"),
            BorderBrush = BrushFromHex("#22FFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = summaryGrid
        };

        var stepsHeader = new Grid
        {
            ColumnSpacing = 10
        };
        stepsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        stepsHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        stepsHeader.Children.Add(new TextBlock
        {
            Text = "Diagnostic Steps",
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#F2F5F9")
        });
        var progress = new ProgressRing
        {
            Width = 24,
            Height = 24,
            IsActive = false,
            Visibility = Visibility.Collapsed
        };
        Grid.SetColumn(progress, 1);
        stepsHeader.Children.Add(progress);

        var stepsStack = new StackPanel
        {
            Spacing = 8
        };
        var stepsScroll = new ScrollViewer
        {
            Content = stepsStack,
            Height = 340,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var stepsSurface = new Border
        {
            BorderBrush = BrushFromHex("#22FFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Background = BrushFromHex("#0CFFFFFF"),
            Child = stepsScroll
        };

        var body = new StackPanel
        {
            Width = 760,
            Spacing = 14
        };
        body.Children.Add(header);
        body.Children.Add(summarySurface);
        body.Children.Add(stepsHeader);
        body.Children.Add(stepsSurface);

        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Content = body,
            RequestedTheme = ElementTheme.Dark,
            CloseButtonText = "Close"
        };

        IReadOnlyList<RuntimeDiagnosticStep> CurrentSteps()
        {
            return _codexRemoteDiagnostics.TryGetValue(remote.Id, out var steps)
                ? steps
                : [];
        }

        bool IsBusy()
        {
            return _codexRemoteOperationIds.Contains(remote.Id) ||
                CurrentSteps().Any(step => string.Equals(step.Status, RuntimeDiagnosticStatuses.Running, StringComparison.OrdinalIgnoreCase));
        }

        void RebuildSummary()
        {
            summaryGrid.Children.Clear();
            var steps = CurrentSteps();
            var completedStepCount = steps.Count(step =>
                string.Equals(step.Status, RuntimeDiagnosticStatuses.Passed, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(step.Status, RuntimeDiagnosticStatuses.Warning, StringComparison.OrdinalIgnoreCase));
            AddRemoteDiagnosticsSummaryCell(summaryGrid, 0, 0, "\uE977", "Platform", remote.Platform);
            AddRemoteDiagnosticsSummaryCell(summaryGrid, 0, 1, "\uE756", "SSH", remote.Hostname ?? "Missing");
            AddRemoteDiagnosticsSummaryCell(summaryGrid, 0, 2, "\uF146", "Port", remote.SshPort?.ToString(CultureInfo.InvariantCulture) ?? "Default");
            AddRemoteDiagnosticsSummaryCell(summaryGrid, 1, 0, "\uE192", "Identity", string.IsNullOrWhiteSpace(remote.IdentityPath) ? "SSH config/default" : "Configured");
            AddRemoteDiagnosticsSummaryCell(
                summaryGrid,
                1,
                1,
                "\uE968",
                "App Server Ports",
                string.Join(", ", CodexRemoteTunnelService.RemoteAppServerPortCandidates(remote)));
            AddRemoteDiagnosticsSummaryCell(summaryGrid, 1, 2, "\uE9D9", "Steps", $"{completedStepCount}/{steps.Count}");
        }

        void RebuildSteps()
        {
            stepsStack.Children.Clear();
            var steps = CurrentSteps();
            if (steps.Count == 0)
            {
                stepsStack.Children.Add(RemoteDiagnosticsEmptyState());
                return;
            }

            foreach (var step in steps)
            {
                stepsStack.Children.Add(RemoteDiagnosticsStepRow(remote.Id, step, IsBusy(), action =>
                {
                    RunWindowOperation(async lease =>
                    {
                        var operation = RunCodexRemoteActionAsync(remote.Id, action);
                        RefreshDialog();
                        await operation;
                        if (_windowLifetime.IsCurrent(lease))
                        {
                            RefreshDialog();
                        }
                    });
                }));
            }
        }

        void RefreshDialog()
        {
            var busy = IsBusy();
            rerunButton.IsEnabled = remote.IsConnectable && !busy;
            connectButton.IsEnabled = remote.IsConnectable && !busy;
            progress.IsActive = busy;
            progress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            ToolTipService.SetToolTip(
                rerunButton,
                remote.IsConnectable ? "Run the full remote diagnostic again" : "This remote needs SSH setup before diagnostics can run");
            ToolTipService.SetToolTip(
                connectButton,
                remote.IsConnectable ? "Start the remote App Server and attach the workflow relay" : "This remote needs SSH setup before it can connect");
            RebuildSummary();
            RebuildSteps();
        }

        rerunButton.Click += (_, _) =>
        {
            RunWindowOperation(async lease =>
            {
                var operation = RunCodexRemoteOperationAsync(remote.Id, connect: false);
                RefreshDialog();
                await operation;
                if (_windowLifetime.IsCurrent(lease))
                {
                    RefreshDialog();
                }
            });
        };
        connectButton.Click += (_, _) =>
        {
            RunWindowOperation(async lease =>
            {
                var operation = RunCodexRemoteOperationAsync(remote.Id, connect: true);
                RefreshDialog();
                await operation;
                if (_windowLifetime.IsCurrent(lease))
                {
                    RefreshDialog();
                }
            });
        };
        copyButton.Click += (_, _) =>
        {
            CopyTextToClipboard(CodexRemoteTunnelService.DebugReport(remote, CurrentSteps()));
            copyButton.Content = RemoteDiagnosticsButtonContent("\uE73E", "Copied");
            ShowCommandFeedback("Copied remote diagnostics report.");
        };

        RefreshDialog();
        await dialog.ShowAsync();
    }

    private static Button RemoteDiagnosticsActionButton(string glyph, string label, string tooltip)
    {
        var button = new Button
        {
            Content = RemoteDiagnosticsButtonContent(glyph, label),
            Padding = new Thickness(10, 5, 10, 5),
            MinWidth = 0,
            MinHeight = 0,
            CornerRadius = new CornerRadius(6),
            Background = BrushFromHex("#1AFFFFFF"),
            BorderBrush = BrushFromHex("#22FFFFFF"),
            BorderThickness = new Thickness(1)
        };
        ToolTipService.SetToolTip(button, tooltip);
        AutomationProperties.SetName(button, label);
        return button;
    }

    private static StackPanel RemoteDiagnosticsButtonContent(string glyph, string label)
    {
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 5
        };
        content.Children.Add(new FontIcon
        {
            Glyph = glyph,
            FontSize = 12
        });
        content.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        return content;
    }

    private static void AddRemoteDiagnosticsSummaryCell(Grid summaryGrid, int row, int column, string glyph, string title, string value)
    {
        var cell = new Grid
        {
            ColumnSpacing = 7
        };
        cell.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        cell.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        cell.Children.Add(new FontIcon
        {
            Glyph = glyph,
            FontSize = 13,
            Width = 16,
            Foreground = BrushFromHex("#A7B0BF"),
            VerticalAlignment = VerticalAlignment.Top
        });
        var textStack = new StackPanel
        {
            Spacing = 2
        };
        textStack.Children.Add(new TextBlock
        {
            Text = title,
            FontSize = 11,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#A7B0BF")
        });
        textStack.Children.Add(new TextBlock
        {
            Text = value,
            FontSize = 12,
            Foreground = BrushFromHex("#F2F5F9"),
            IsTextSelectionEnabled = true,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2
        });
        Grid.SetColumn(textStack, 1);
        cell.Children.Add(textStack);
        Grid.SetRow(cell, row);
        Grid.SetColumn(cell, column);
        summaryGrid.Children.Add(cell);
    }

    private static UIElement RemoteDiagnosticsEmptyState()
    {
        var stack = new StackPanel
        {
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Padding = new Thickness(24)
        };
        stack.Children.Add(new FontIcon
        {
            Glyph = "\uE9D9",
            FontSize = 28,
            Foreground = BrushFromHex("#8F9BAA")
        });
        stack.Children.Add(new TextBlock
        {
            Text = "No diagnostics yet",
            FontSize = 15,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#F2F5F9"),
            HorizontalAlignment = HorizontalAlignment.Center
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Run diagnostics or connect this remote to collect SSH, App Server, tunnel, and relay evidence.",
            FontSize = 12,
            Foreground = BrushFromHex("#A7B0BF"),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 460
        });
        return stack;
    }

    private static UIElement RemoteDiagnosticsStepRow(
        string remoteId,
        RuntimeDiagnosticStep step,
        bool isBusy,
        Action<string> onAction)
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(step.Status);
        var rowStack = new StackPanel
        {
            Spacing = 7
        };
        var header = new Grid
        {
            ColumnSpacing = 8
        };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new FontIcon
        {
            Glyph = presentation.Glyph,
            FontSize = 15,
            Width = 18,
            Foreground = BrushFromHex(presentation.ForegroundHex),
            VerticalAlignment = VerticalAlignment.Center
        });
        var title = new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(step.Title) ? step.Id : step.Title,
            FontSize = 14,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#F2F5F9"),
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(title, 1);
        header.Children.Add(title);

        var statusPill = new Border
        {
            Padding = new Thickness(6, 2, 6, 2),
            CornerRadius = new CornerRadius(8),
            Background = BrushFromHex(RemoteDiagnosticsTintHex(presentation.ForegroundHex)),
            Child = new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(step.Status) ? RuntimeDiagnosticStatuses.Pending : step.Status,
                FontSize = 10,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = BrushFromHex(presentation.ForegroundHex)
            }
        };
        Grid.SetColumn(statusPill, 2);
        header.Children.Add(statusPill);

        var action = step.Action;
        if (!string.IsNullOrWhiteSpace(action))
        {
            var actionItem = CodexRemoteDiagnosticItem.FromStep(remoteId, step, isBusy);
            var actionButton = RemoteDiagnosticsActionButton(
                actionItem.ActionGlyph,
                actionItem.ActionLabel,
                actionItem.ActionTooltip);
            actionButton.IsEnabled = !isBusy;
            actionButton.Click += (_, _) => onAction(action);
            Grid.SetColumn(actionButton, 4);
            header.Children.Add(actionButton);
        }

        rowStack.Children.Add(header);

        if (!string.IsNullOrWhiteSpace(step.Detail))
        {
            rowStack.Children.Add(new TextBlock
            {
                Text = step.Detail,
                FontSize = 12,
                Foreground = BrushFromHex("#A7B0BF"),
                IsTextSelectionEnabled = true,
                TextWrapping = TextWrapping.Wrap
            });
        }

        if (!string.IsNullOrWhiteSpace(step.Evidence))
        {
            rowStack.Children.Add(new Border
            {
                Padding = new Thickness(7, 5, 7, 5),
                Background = BrushFromHex("#1AFFFFFF"),
                CornerRadius = new CornerRadius(6),
                Child = new TextBlock
                {
                    Text = step.Evidence,
                    FontSize = 11,
                    FontFamily = new FontFamily("Consolas"),
                    Foreground = BrushFromHex("#A7B0BF"),
                    IsTextSelectionEnabled = true,
                    TextWrapping = TextWrapping.Wrap,
                    MaxLines = 3
                }
            });
        }

        return new Border
        {
            Padding = new Thickness(10),
            Background = BrushFromHex("#4D18191B"),
            BorderBrush = BrushFromHex("#22FFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = rowStack
        };
    }

    private static string RemoteDiagnosticsTintHex(string foregroundHex)
    {
        var value = foregroundHex.TrimStart('#');
        return value.Length == 6 ? $"#1F{value}" : "#1AFFFFFF";
    }

    private void ConnectCodexRemoteDiscoveryButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: RemoteDiscoveryItem item })
            {
                return;
            }

            if (!item.CanConnect)
            {
                AddActivity(item.ConnectTooltip);
                ShowCommandFeedback(item.ConnectTooltip);
                return;
            }

            await RunCodexRemoteOperationAsync(item.RemoteId, connect: true);

        });
    }

    private async Task RunCodexRemoteOperationAsync(string remoteId, bool connect)
    {
        if (!TryFindCodexRemote(remoteId, out var remote))
        {
            ShowCommandFeedback("This Codex remote is no longer available. Run discovery again.");
            return;
        }

        if (_codexRemoteOperationIds.Contains(remote.Id))
        {
            ShowCommandFeedback(MachineDiscoveryActionPresentation.BusyUnavailableReason);
            return;
        }

        if (!remote.IsConnectable)
        {
            ShowCommandFeedback(MachineDiscoveryActionPresentation.SetupUnavailableReason);
            return;
        }

        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _codexRemoteOperationIds.Add(remote.Id);
        SetCodexRemoteDiagnostics(remote.Id, CodexRemoteTunnelService.PendingConnectionDiagnosticSteps(remote).ToList());
        AddActivity(connect
            ? $"Connecting Codex remote {remote.DisplayName}."
            : $"Diagnosing Codex remote {remote.DisplayName}.");
        UpdateChrome();

        try
        {
            if (connect)
            {
                UpsertCodexRemoteMachine(remote, HostStatuses.Connecting);
                await SaveGraphAsync();
                await RenderGraphAsync();
                StopCodexRemoteTunnel(remote.Id);
            }

            if (connect)
            {
                var result = await CodexRemoteTunnelService.StartTunnelWithDiagnosticsAsync(
                    remote,
                    steps => PublishCodexRemoteDiagnosticsAsync(remote.Id, steps));
                _codexRemoteTunnels[remote.Id] = result.Tunnel;
                var initialize = await new AppServerClient().InitializeAsync(result.Tunnel.Endpoint);
                _connectedAppServerEndpointsByHostId[remote.Id] = result.Tunnel.Endpoint;
                await RefreshNewThreadModelOptionsForHostAsync(remote.Id, result.Tunnel.Endpoint, CancellationToken.None);
                UpsertCodexRemoteMachine(remote, HostStatuses.Connected, initialize, result.Tunnel.Endpoint);
                var diagnostics = result.Diagnostics
                    .Concat(
                    [
                        new RuntimeDiagnosticStep
                        {
                            Id = "relay-handshake",
                            Title = "Relay handshake connected",
                            Status = RuntimeDiagnosticStatuses.Passed,
                            Detail = result.Tunnel.Endpoint.Url.ToString(),
                            Evidence = "initialize + initialized over workflow relay endpoint"
                        }
                    ])
                    .ToList();
                SetCodexRemoteDiagnostics(remote.Id, diagnostics);
                await SaveGraphAsync();
                SetStatus(HostStatuses.Connected, "Connected", $"{remote.DisplayName} - {result.Tunnel.Endpoint.Url}");
                AddActivity($"Connected Codex remote {remote.DisplayName}.");
                await RefreshAppServerThreadCatalogAsync(search: false);
                await RenderGraphAsync();
            }
            else
            {
                var diagnostics = await CodexRemoteTunnelService.DiagnoseAsync(
                    remote,
                    steps => PublishCodexRemoteDiagnosticsAsync(remote.Id, steps));
                SetCodexRemoteDiagnostics(remote.Id, diagnostics.ToList());
                AddActivity($"Diagnosed Codex remote {remote.DisplayName}.");
            }
        }
        catch (Exception exception)
        {
            var redactedExceptionMessage = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message);
            if (exception is CodexRemoteTunnelException tunnelException && tunnelException.DiagnosticSteps.Count > 0)
            {
                SetCodexRemoteDiagnostics(remote.Id, tunnelException.DiagnosticSteps.ToList());
            }
            else
            {
                SetCodexRemoteDiagnostics(remote.Id,
                [
                    new RuntimeDiagnosticStep
                    {
                        Id = connect ? "connect" : "remote-diagnostic",
                        Title = connect ? "Remote connection" : "Remote diagnostic",
                        Status = RuntimeDiagnosticStatuses.Failed,
                        Detail = redactedExceptionMessage
                    }
                ]);
            }

            if (connect)
            {
                StopCodexRemoteTunnel(remote.Id);
                UpsertCodexRemoteMachine(remote, HostStatuses.Unavailable, lastError: redactedExceptionMessage);
                await SaveGraphAsync();
                await RenderGraphAsync();
            }

            AddActivity(
                connect
                    ? $"Codex remote connection failed: {exception.Message}"
                    : $"Codex remote diagnostic failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
        finally
        {
            _codexRemoteOperationIds.Remove(remote.Id);
            UpdateChrome();
        }
    }

    private async Task RunCodexRemoteActionAsync(string remoteId, string action)
    {
        if (!TryFindCodexRemote(remoteId, out var remote))
        {
            ShowCommandFeedback("This Codex remote is no longer available. Run discovery again.");
            return;
        }

        if (_codexRemoteOperationIds.Contains(remote.Id))
        {
            ShowCommandFeedback("Wait for the current remote operation to finish.");
            return;
        }

        _codexRemoteOperationIds.Add(remote.Id);
        SetCodexRemoteDiagnostics(remote.Id,
        [
            new RuntimeDiagnosticStep
            {
                Id = action,
                Title = DiagnosticActionRunningTitle(action),
                Status = RuntimeDiagnosticStatuses.Running,
                Detail = remote.Hostname ?? remote.HostID
            }
        ]);
        UpdateChrome();

        var followUpConnect = false;
        var followUpDiagnose = false;
        try
        {
            switch (action)
            {
                case RuntimeDiagnosticActions.InstallCodexCLI:
                    await CodexRemoteTunnelService.InstallCodexCliAsync(remote);
                    followUpDiagnose = true;
                    break;
                case RuntimeDiagnosticActions.UpdateCodexCLI:
                    await CodexRemoteTunnelService.UpdateCodexCliAsync(remote);
                    followUpDiagnose = true;
                    break;
                case RuntimeDiagnosticActions.StartAppServer:
                    await CodexRemoteTunnelService.StartAppServerAsync(remote);
                    followUpConnect = true;
                    break;
                case RuntimeDiagnosticActions.RestartAppServer:
                    await CodexRemoteTunnelService.RestartAppServerAsync(remote);
                    followUpConnect = true;
                    break;
                default:
                    ShowCommandFeedback("This diagnostic action is not supported yet.");
                    break;
            }
        }
        catch (Exception exception)
        {
            SetCodexRemoteDiagnostics(remote.Id,
            [
                new RuntimeDiagnosticStep
                {
                    Id = action,
                    Title = DiagnosticActionFailureTitle(action),
                    Status = RuntimeDiagnosticStatuses.Failed,
                    Detail = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message),
                    Action = action
                }
            ]);
            AddActivity(
                $"Codex remote action failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
        finally
        {
            _codexRemoteOperationIds.Remove(remote.Id);
            UpdateChrome();
        }

        if (followUpConnect)
        {
            await RunCodexRemoteOperationAsync(remote.Id, connect: true);
        }
        else if (followUpDiagnose)
        {
            await RunCodexRemoteOperationAsync(remote.Id, connect: false);
        }
    }

    private Task PublishCodexRemoteDiagnosticsAsync(string remoteId, IReadOnlyList<RuntimeDiagnosticStep> steps)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!DispatcherQueue.TryEnqueue(() =>
            {
                SetCodexRemoteDiagnostics(remoteId, steps.ToList());
                UpdateChrome();
                completion.TrySetResult();
            }))
        {
            completion.TrySetResult();
        }

        return completion.Task;
    }

    private bool TryFindCodexRemote(string remoteId, out CodexDesktopRemote remote)
    {
        remote = _discoveredCodexRemotes.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, remoteId, StringComparison.OrdinalIgnoreCase))!;
        return remote is not null;
    }

    private void SetCodexRemoteDiagnostics(string remoteId, List<RuntimeDiagnosticStep> steps)
    {
        _codexRemoteDiagnostics[remoteId] = steps;
    }

    private void UpsertCodexRemoteMachine(
        CodexDesktopRemote remote,
        string status,
        AppServerInitializeResult? initialize = null,
        AppServerEndpoint? endpoint = null,
        string? lastError = null)
    {
        _graph.Nodes.TryGetValue(remote.Id, out var existingMachine);
        var platform = initialize?.Platform ?? remote.Platform;
        var endpointDescription = endpoint?.Url.ToString() ?? remote.DisplayAddress;
        _graph.Nodes[remote.Id] = new CanvasNode
        {
            Id = remote.Id,
            Kind = NodeKinds.Machine,
            Title = remote.DisplayName,
            Subtitle = $"{platform} - {endpointDescription}",
            Position = existingMachine?.Position ?? NextMachinePosition(),
            Size = existingMachine?.Size ?? CanvasSize.Machine,
            Metadata = new NodeMetadata
            {
                HostID = remote.Id,
                Platform = platform,
                HostStatus = status,
                HostLastError = status == HostStatuses.Unavailable
                    ? NormalizedHostLastError(lastError) ?? existingMachine?.Metadata.HostLastError
                    : null,
                CodexHome = initialize?.CodexHome ?? existingMachine?.Metadata.CodexHome,
                AppServerEndpointUrl = endpoint?.Url.ToString() ?? existingMachine?.Metadata.AppServerEndpointUrl
            }
        };
    }

    private static string? NormalizedHostLastError(string? lastError)
    {
        return string.IsNullOrWhiteSpace(lastError) ? null : lastError.Trim();
    }

    private void StopCodexRemoteTunnel(string remoteId)
    {
        if (_codexRemoteTunnels.Remove(remoteId, out var tunnel))
        {
            tunnel.Stop();
        }

        _connectedAppServerEndpointsByHostId.Remove(remoteId);
        _newThreadModelsByHostId.Remove(remoteId);
    }

    private void StopAllCodexRemoteTunnels()
    {
        foreach (var tunnel in _codexRemoteTunnels.Values)
        {
            tunnel.Stop();
        }

        _codexRemoteTunnels.Clear();
    }

    private static string DiagnosticActionRunningTitle(string action)
    {
        return action switch
        {
            RuntimeDiagnosticActions.InstallCodexCLI => "Installing Codex CLI",
            RuntimeDiagnosticActions.UpdateCodexCLI => "Updating Codex CLI",
            RuntimeDiagnosticActions.StartAppServer => "Starting App Server",
            RuntimeDiagnosticActions.RestartAppServer => "Restarting App Server",
            _ => "Running diagnostic action"
        };
    }

    private static string DiagnosticActionFailureTitle(string action)
    {
        return action switch
        {
            RuntimeDiagnosticActions.InstallCodexCLI => "Install failed",
            RuntimeDiagnosticActions.UpdateCodexCLI => "Update failed",
            RuntimeDiagnosticActions.StartAppServer => "Start failed",
            RuntimeDiagnosticActions.RestartAppServer => "Restart failed",
            _ => "Action failed"
        };
    }

    private void AddFolderButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            NewThreadPopover.Visibility = Visibility.Collapsed;
            WorkflowPopover.Visibility = Visibility.Collapsed;
            WorkflowNamePopover.Visibility = Visibility.Collapsed;
            HealthPopover.Visibility = Visibility.Collapsed;
            PairingPopover.Visibility = Visibility.Collapsed;

            if (CreateFolderUnavailableReason is { } reason)
            {
                ShowCommandFeedback(reason, AddFolderButton);
                return;
            }

            var machine = SelectedMachineNode() ?? LocalMachineNode();
            if (machine is null)
            {
                ShowCommandFeedback("Connect a machine before adding a folder.", AddFolderButton);
                return;
            }

            if (!IsLocalHostId(machine.Metadata.HostID))
            {
                var remoteFolderPath = TryFindCodexRemoteForMachine(machine, out var codexRemote)
                    ? await ShowRemoteFolderPickerAsync(codexRemote, DefaultFolderPathFor(machine))
                    : await PromptForMachineFolderPathAsync(machine);
                if (remoteFolderPath is null)
                {
                    AddActivity("Canceled folder creation.");
                    return;
                }

                await AddFolderNodeAsync(machine, remoteFolderPath);
                return;
            }

            var folderPath = await PickLocalFolderPathAsync();
            if (folderPath is null)
            {
                AddActivity("Canceled folder creation.");
                return;
            }

            await AddFolderNodeAsync(machine, folderPath);

        });
    }

    private void AddThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            WorkflowPopover.Visibility = Visibility.Collapsed;
            WorkflowNamePopover.Visibility = Visibility.Collapsed;
            HealthPopover.Visibility = Visibility.Collapsed;
            PairingPopover.Visibility = Visibility.Collapsed;

            if (CreateThreadUnavailableReason is { } reason)
            {
                ShowCommandFeedback(reason, AddThreadButton);
                return;
            }

            await ShowNewThreadPopoverAsync();

        });
    }

    private void ArrangeButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            ArrangeNodes();
            await SaveGraphAsync();
            AddActivity("Arranged workflow nodes.");
            await RenderGraphAsync();

        });
    }

    private void WorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            NewThreadPopover.Visibility = Visibility.Collapsed;
            WorkflowPopover.Visibility = Visibility.Collapsed;
            WorkflowNamePopover.Visibility = Visibility.Collapsed;
            HealthPopover.Visibility = Visibility.Collapsed;
            PairingPopover.Visibility = Visibility.Collapsed;
            await RefreshWorkflowMenuAsync();
            ShowWorkflowMenuFlyout();

        });
    }

    private void ShowWorkflowMenuFlyout()
    {
        var menuPresentation = ToolbarWorkflowPresentation.ResolveMenu();
        var flyout = new MenuFlyout();
        if (_workflowMenuItems.Count == 0)
        {
            flyout.Items.Add(new MenuFlyoutItem
            {
                Text = "No Workflows",
                IsEnabled = false
            });
        }
        else
        {
            flyout.Items.Add(new MenuFlyoutItem
            {
                Text = "Workflows",
                IsEnabled = false
            });
            foreach (var item in _workflowMenuItems)
            {
                var workflowItem = new MenuFlyoutItem
                {
                    Text = item.Title,
                    Icon = WorkflowMenuIcon(item.IsActive
                        ? menuPresentation.ActiveWorkflowIconKind
                        : menuPresentation.InactiveWorkflowIconKind),
                    Tag = item
                };
                workflowItem.Click += WorkflowFlyoutItem_Click;
                flyout.Items.Add(workflowItem);
            }
        }

        flyout.Items.Add(new MenuFlyoutSeparator());
        flyout.Items.Add(MenuCommandItem("New Workflow", menuPresentation.NewWorkflowIconKind, NewWorkflowButton_Click));
        flyout.Items.Add(MenuCommandItem("Rename", menuPresentation.RenameIconKind, SaveWorkflowButton_Click));
        flyout.Items.Add(MenuCommandItem("Save Copy", menuPresentation.DuplicateIconKind, DuplicateWorkflowButton_Click));
        flyout.Items.Add(MenuCommandItem(
            "Delete Workflow",
            menuPresentation.DeleteIconKind,
            DeleteWorkflowButton_Click,
            destructive: true));
        flyout.ShowAt(WorkflowButton);
    }

    private static MenuFlyoutItem MenuCommandItem(
        string text,
        string iconKind,
        RoutedEventHandler handler,
        bool destructive = false)
    {
        var item = new MenuFlyoutItem
        {
            Text = text,
            Icon = WorkflowMenuIcon(iconKind, destructive ? "#B42318" : null)
        };
        if (destructive)
        {
            item.Foreground = BrushFromHex("#B42318");
        }

        item.Click += handler;
        return item;
    }

    private static IconElement WorkflowMenuIcon(string iconKind, string? color = null)
    {
        return WorkflowIconElement(
            iconKind,
            ToolbarWorkflowPresentation.MenuIconSize,
            color ?? ToolbarWorkflowPresentation.StrokeHex);
    }

    private static IconElement WorkflowIconElement(string iconKind, double size, string color)
    {
        var icon = (PathIcon)XamlReader.Load(
            "<PathIcon xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" " +
            $"Width=\"{size}\" " +
            $"Height=\"{size}\" " +
            $"Data=\"{WorkflowMenuIconData(iconKind)}\" />");
        icon.Foreground = BrushFromHex(color);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        icon.VerticalAlignment = VerticalAlignment.Center;
        return icon;
    }

    private static string WorkflowMenuIconData(string iconKind)
    {
        return iconKind switch
        {
            ToolbarWorkflowPresentation.ActiveWorkflowIcon =>
                "M 6.2 11.3 L 2.6 7.7 L 4 6.3 L 6.2 8.5 L 12 2.7 L 13.4 4.1 Z",
            ToolbarWorkflowPresentation.InactiveWorkflowIcon =>
                "M 8 1.8 C 11.4 1.8 14.2 4.6 14.2 8 C 14.2 11.4 11.4 14.2 8 14.2 C 4.6 14.2 1.8 11.4 1.8 8 C 1.8 4.6 4.6 1.8 8 1.8 Z M 8 3.6 C 5.6 3.6 3.6 5.6 3.6 8 C 3.6 10.4 5.6 12.4 8 12.4 C 10.4 12.4 12.4 10.4 12.4 8 C 12.4 5.6 10.4 3.6 8 3.6 Z",
            ToolbarWorkflowPresentation.NewWorkflowIcon =>
                "M 7.1 2.2 L 8.9 2.2 L 8.9 7.1 L 13.8 7.1 L 13.8 8.9 L 8.9 8.9 L 8.9 13.8 L 7.1 13.8 L 7.1 8.9 L 2.2 8.9 L 2.2 7.1 L 7.1 7.1 Z",
            ToolbarWorkflowPresentation.RenameIcon =>
                "M 11.6 1.7 L 14.3 4.4 L 5.8 12.9 L 2.1 13.7 L 2.9 10 Z M 10.5 2.8 L 9.7 3.6 L 11.3 5.2 L 12.1 4.4 Z M 4.2 10.7 L 4 12.1 L 5.3 11.8 Z",
            ToolbarWorkflowPresentation.DuplicateIcon =>
                "M 5.2 1.6 L 12.2 1.6 L 14.2 3.6 L 14.2 11.8 L 11.8 11.8 L 11.8 4.8 L 9.8 2.9 L 5.2 2.9 Z M 2.6 4.2 L 9.6 4.2 L 11.6 6.2 L 11.6 14.4 L 2.6 14.4 Z M 9.3 5.5 L 9.3 6.5 L 10.3 6.5 Z",
            ToolbarWorkflowPresentation.DeleteIcon =>
                "M 5.8 1.7 L 10.2 1.7 L 10.7 3 L 13.6 3 L 13.6 4.5 L 2.4 4.5 L 2.4 3 L 5.3 3 Z M 3.4 5.4 L 12.6 5.4 L 11.8 14.2 L 4.2 14.2 Z M 5.8 7 L 7.1 7 L 7.1 12.5 L 5.8 12.5 Z M 8.9 7 L 10.2 7 L 10.2 12.5 L 8.9 12.5 Z",
            _ => throw new ArgumentOutOfRangeException(nameof(iconKind), iconKind, "Unknown workflow menu icon kind.")
        };
    }

    private void WorkflowFlyoutItem_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is MenuFlyoutItem { Tag: WorkflowMenuItem item })
            {
                await SelectWorkflowAsync(item);
            }

        });
    }

    private void ReadingModeButton_Click(object sender, RoutedEventArgs e)
    {
        _isReadingModePresented = !_isReadingModePresented;
        var selectedNodeId = _selectedNodeId;
        var selectedNodeIsThread = selectedNodeId is not null &&
            _graph.Nodes.TryGetValue(selectedNodeId, out var selectedNode) &&
            selectedNode.Kind == NodeKinds.CodexThread;
        var threadToAdd = ReaderModeOpeningPolicy.ThreadToAddWhenOpening(
            _isReadingModePresented,
            _readerThreadIds.Count,
            selectedNodeId,
            selectedNodeIsThread);
        if (threadToAdd is not null && !_readerThreadIds.Contains(threadToAdd))
        {
            _readerThreadIds.Add(threadToAdd);
        }

        AddActivity(_isReadingModePresented ? "Reading mode opened." : "Reading mode closed.");
        UpdateChrome();
    }

    private void SubagentsButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            _showsSubagents = !_showsSubagents;
            if (!_showsSubagents)
            {
                CloseHiddenSubagentSurfaces();
            }

            SavePreferences();
            AddActivity(_showsSubagents ? "Showing subagent nodes." : "Hiding subagent nodes.");
            await RenderGraphAsync();

        });
    }

    private void CloseHiddenSubagentSurfaces()
    {
        var hiddenIds = _graph.Nodes.Values
            .Where(node => node.Kind == NodeKinds.CodexThread && LooksLikeSubagent(node))
            .Select(node => node.Id)
            .ToHashSet(StringComparer.Ordinal);

        if (hiddenIds.Count == 0)
        {
            return;
        }

        var shouldHideSelectionInspector = false;
        var shouldResetThreadPopover = false;

        if (_selectedNodeId is not null && hiddenIds.Contains(_selectedNodeId))
        {
            _selectedNodeId = null;
            shouldHideSelectionInspector = true;
            shouldResetThreadPopover = true;
        }
        else if (_selectedEdgeId is not null &&
            _graph.ManualEdges.TryGetValue(_selectedEdgeId, out var selectedEdge) &&
            (hiddenIds.Contains(selectedEdge.Source) || hiddenIds.Contains(selectedEdge.Target)))
        {
            _selectedEdgeId = null;
            shouldHideSelectionInspector = true;
        }

        if (_pendingLinkSourceNodeId is not null && hiddenIds.Contains(_pendingLinkSourceNodeId))
        {
            _pendingLinkSourceNodeId = null;
        }

        if (_threadPopoverNodeId is not null && hiddenIds.Contains(_threadPopoverNodeId))
        {
            shouldResetThreadPopover = true;
        }

        _readerThreadIds.RemoveAll(hiddenIds.Contains);
        foreach (var hiddenId in hiddenIds)
        {
            _readerPendingAttachments.Remove(hiddenId);
            _readerTranscriptFilters.Remove(hiddenId);
            _transcriptSessions.Remove(hiddenId);
        }

        _expandedTranscriptRows.RemoveWhere(key =>
            hiddenIds.Any(hiddenId => key.StartsWith($"{hiddenId}::", StringComparison.Ordinal)));

        if (_artifactCatalog.SourceId is { } artifactSourceId && hiddenIds.Contains(artifactSourceId))
        {
            _artifactCatalog.ClearSource();
            ArtifactsPopover.Visibility = Visibility.Collapsed;
            CloseArtifactPreview();
        }

        if (shouldHideSelectionInspector)
        {
            SelectionInspector.Visibility = Visibility.Collapsed;
        }

        if (shouldResetThreadPopover)
        {
            ResetThreadPopoverData();
        }
    }

    private void ResetThreadPopoverData()
    {
        _threadPopoverNodeId = null;
        _threadPopoverMessages.Clear();
        _threadPopoverFilters.Clear();
        _threadPopoverPendingAttachments.Clear();
        _threadPopoverTranscriptFilters.Clear();
        ThreadPopoverDraftBox.Text = "";
        ThreadPopoverTitleBox.Text = "";
        ClearThreadPopoverMentionSuggestions();
        _isThreadPopoverRenaming = false;
        ThreadPopover.Visibility = Visibility.Collapsed;
        SetThreadPopoverAttachmentError(null);
        RefreshThreadPopoverAttachmentCount();
    }

    private void SearchButton_Click(object sender, RoutedEventArgs e)
    {
        _isThreadInboxCollapsed = false;
        SavePreferences();
        var wasSearchVisible = _threadInboxMode == ThreadInboxModeSearch && _isThreadInboxSearchVisible;
        _threadInboxMode = ThreadInboxModeSearch;
        _isThreadInboxSearchVisible = true;
        AddActivity(wasSearchVisible ? "Thread inbox search focused." : "Thread inbox search opened.");
        UpdateChrome();
        FocusThreadInboxSearchBox();
        RunWindowOperation(_ => SearchAppServerThreadCatalogWithDelayAsync());
    }

    private void MachinesButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isMachinesFlyoutOpen)
        {
            HideMachinesFlyout();
            return;
        }

        ShowMachinesFlyout();
        AddActivity("Machines menu opened.");
    }

    private void SetupLocalMachineButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SetupLocalMachineAsync();

        });
    }

    private async Task SetupLocalMachineAsync()
    {
        if (_isSettingUpLocalMachine)
        {
            ShowCommandFeedback("Local Codex setup is already running.", MachinesButton);
            return;
        }

        _isSettingUpLocalMachine = true;
        _lastLocalSetupDetail = "Starting local Codex App Server...";
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        SetStatus(HostStatuses.Connecting, "Starting local Codex", _lastLocalSetupDetail);
        UpsertLocalMachine(HostStatuses.Connecting, null, "Starting local Codex App Server...");
        AddActivity("Starting local Codex App Server.");
        UpdateChrome();
        if (!_isMachinesFlyoutOpen)
        {
            ShowMachinesFlyout();
        }

        try
        {
            var result = await LocalAppServerService.StartOrConnectAsync(_store.ApplicationDataDirectory);
            UpsertLocalMachine(
                HostStatuses.Connected,
                result,
                $"Connected via {result.Endpoint.Url}");
            RegisterLocalAppServerEndpoint(result.Endpoint);
            await SaveGraphAsync();
            await RefreshNewThreadModelOptionsForHostAsync(LocalHostIdentity.LocalMachineNodeID, result.Endpoint, CancellationToken.None);
            await RefreshAppServerThreadCatalogAsync(search: false);
            SetStatus(HostStatuses.Connected, "Connected", result.Endpoint.Url.ToString());
            _lastLocalSetupDetail = $"Local Codex App Server is running on {result.Endpoint.Url}.";
            AddActivity("Local Codex App Server connected.");
            await RenderGraphAsync();
        }
        catch (Exception exception)
        {
            var message = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message);
            _lastLocalSetupDetail = message;
            UpsertLocalMachine(HostStatuses.Unavailable, null, message);
            SetStatus(HostStatuses.Unavailable, "Local setup failed", message);
            AddActivity(
                $"Local Codex setup failed: {message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
            await SaveGraphAsync();
            await RenderGraphAsync();
        }
        finally
        {
            _isSettingUpLocalMachine = false;
            UpdateChrome();
        }
    }

    private void CloseHealthPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        HealthPopover.Visibility = Visibility.Collapsed;
    }

    private void CloseMachinesRailButton_Click(object sender, RoutedEventArgs e)
    {
        HideMachinesFlyout();
        AddActivity("Machines menu closed.");
    }

    private void RefreshHealthButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await RefreshMachineHealthAsync(
                showMachinesRail: true,
                detail: "Machine catalog refreshed from the active Windows workflow.",
                activityMessage: "Refreshing machine health.",
                discoverMachines: true);
            HealthPopover.Visibility = Visibility.Collapsed;
            UpdateChrome();

        });
    }

    private async Task RefreshMachineHealthAsync(
        bool showMachinesRail,
        string detail,
        string activityMessage,
        bool discoverMachines)
    {
        if (IsMachineHealthRefreshRunning)
        {
            ShowCommandFeedback("Connection refresh is already running.");
            return;
        }

        if (showMachinesRail)
        {
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
        }

        _isRefreshingMachineHealth = true;
        var refreshStartedAt = DateTimeOffset.UtcNow;
        _lastDiagnosticsSummary = "Refreshing machine health...";
        _lastDiagnosticsDetail = detail;
        AddActivity(activityMessage);
        UpdateChrome();

        try
        {
            if (discoverMachines)
            {
                await DiscoverMachinesForRailAsync(
                    automatic: false,
                    showMachinesRail: showMachinesRail);
            }

            if (!showMachinesRail && MachinesNeedingRecovery().Any())
            {
                _isMachinesRailVisible = true;
                _isMachinesRailCollapsed = false;
            }

            _lastDiagnosticsSummary = HealthSummary();
            _lastDiagnosticsDetail = detail;
        }
        finally
        {
            var remainingChromeDuration =
                TimeSpan.FromMilliseconds(MachineHealthRefreshMinimumChromeMilliseconds) -
                (DateTimeOffset.UtcNow - refreshStartedAt);
            if (remainingChromeDuration > TimeSpan.Zero)
            {
                await Task.Delay(remainingChromeDuration);
            }

            _isRefreshingMachineHealth = false;
            UpdateChrome();
        }
    }

    private void RefreshMachineHealth(bool showMachinesRail, string detail, string activityMessage)
    {
        if (showMachinesRail)
        {
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
        }

        _lastDiagnosticsSummary = HealthSummary();
        _lastDiagnosticsDetail = detail;
        AddActivity(activityMessage);
    }

    private void ToggleMachineDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MachineHealthItem item })
        {
            return;
        }

        _expandedMachineHealthItemId = string.Equals(_expandedMachineHealthItemId, item.Id, StringComparison.Ordinal)
            ? null
            : item.Id;
        UpdateMachineHealth();
    }

    private void RunDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        RunMachineDiagnostics();
    }

    private void RunMachineDiagnostics()
    {
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _isMachineRecoveryVisible = MachinesNeedingRecovery().Any();
        _graph.RuntimeDiagnostics = BuildRuntimeDiagnosticSteps();
        _lastDiagnosticsSummary = HealthSummary();
        _lastDiagnosticsDetail = _isMachineRecoveryVisible
            ? "Recovery actions are available for disconnected or unavailable machines."
            : "No machine recovery actions are needed.";
        HealthPopover.Visibility = Visibility.Collapsed;
        AddActivity("Ran machine diagnostics.");
        UpdateChrome();
    }

    private void ToggleMachineRecoveryButton_Click(object sender, RoutedEventArgs e)
    {
        _isMachineRecoveryVisible = !_isMachineRecoveryVisible;
        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        HealthPopover.Visibility = Visibility.Collapsed;
        AddActivity(_isMachineRecoveryVisible ? "Machine recovery opened." : "Machine recovery closed.");
        UpdateChrome();
    }

    private void MachineRecoveryStepActionButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: MachineRecoveryStepItem step } ||
                string.IsNullOrWhiteSpace(step.TargetId) ||
                !_graph.Nodes.TryGetValue(step.TargetId, out var machine))
            {
                return;
            }

            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
            _isMachineRecoveryVisible = true;
            _expandedMachineHealthItemId = machine.Id;

            switch (step.Id)
            {
                case "verify-endpoint":
                    await DiagnoseRecoveryTargetAsync(machine);
                    break;
                case "app-server":
                    await RepairRecoveryTargetAsync(machine);
                    break;
                case "reconnect":
                    await ReconnectRecoveryTargetAsync(machine);
                    break;
                case "remove-route":
                    await RemoveRecoveryRouteAsync(machine);
                    break;
                default:
                    ShowCommandFeedback("This recovery action is not supported yet.");
                    break;
            }

        });
    }

    private async Task DiagnoseRecoveryTargetAsync(CanvasNode machine)
    {
        if (TryFindCodexRemoteForMachine(machine, out var remote))
        {
            await RunCodexRemoteOperationAsync(remote.Id, connect: false);
            return;
        }

        RunMachineDiagnostics();
        AddActivity($"Ran diagnostics for {machine.Title}.");
    }

    private async Task RepairRecoveryTargetAsync(CanvasNode machine)
    {
        if (TryFindCodexRemoteForMachine(machine, out var remote))
        {
            var action = _codexRemoteDiagnostics.TryGetValue(remote.Id, out var diagnostics)
                ? diagnostics.FirstOrDefault(step => !string.IsNullOrWhiteSpace(step.Action))?.Action
                : null;
            if (!string.IsNullOrWhiteSpace(action))
            {
                await RunCodexRemoteActionAsync(remote.Id, action);
                return;
            }

            await RunCodexRemoteOperationAsync(remote.Id, connect: false);
            return;
        }

        PrepareSavedEndpointForReconnect(machine, "No remote SSH repair action exists for this saved route.");
    }

    private async Task ReconnectRecoveryTargetAsync(CanvasNode machine)
    {
        if (TryFindCodexRemoteForMachine(machine, out var remote))
        {
            await RunCodexRemoteOperationAsync(remote.Id, connect: true);
            return;
        }

        PrepareSavedEndpointForReconnect(machine, $"Prepared {machine.Title} endpoint for reconnect.");
    }

    private async Task RemoveRecoveryRouteAsync(CanvasNode machine)
    {
        if (!await ConfirmDisconnectMachineAsync(machine))
        {
            AddActivity("Canceled stale route removal.");
            return;
        }

        machine.Metadata.HostStatus = HostStatuses.Disconnected;
        machine.Metadata.HostLastError = null;
        machine.Metadata.AppServerEndpointUrl = null;
        StopCodexRemoteTunnel(machine.Id);
        if (IsLocalHostId(machine.Metadata.HostID))
        {
            UnregisterLocalAppServerEndpoint(machine);
            SyncLocalRuntimeStatusFromGraph();
        }

        await SaveGraphAsync();
        AddActivity($"Removed stale route for {machine.Title}.");
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void PrepareSavedEndpointForReconnect(CanvasNode machine, string message)
    {
        var endpoint = machine.Metadata.AppServerEndpointUrl;
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            ShowCommandFeedback("No saved endpoint exists for this machine.");
            RefreshMachineHealth(
                showMachinesRail: true,
                detail: $"No saved endpoint exists for {machine.Title}.",
                activityMessage: $"Could not reconnect {machine.Title}.");
            UpdateChrome();
            return;
        }

        _isMachineConnectFormVisible = true;
        RemoteNameBox.Text = machine.Title;
        EndpointBox.Text = endpoint.Trim();
        BearerTokenBox.Password = "";
        RefreshMachineHealth(
            showMachinesRail: true,
            detail: message,
            activityMessage: message);
        UpdateBearerTokenBoxVisibility();
        UpdateChrome();
        EndpointBox.Focus(FocusState.Programmatic);
        EndpointBox.SelectAll();
    }

    private void ViewLogsButton_Click(object sender, RoutedEventArgs e)
    {
        HealthPopover.Visibility = Visibility.Collapsed;
        var applicationSupportPath = ApplicationSupportFolder.EnsureExists(_store.ApplicationDataDirectory);
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = applicationSupportPath,
                UseShellExecute = true
            });
            AddActivity("Opened app support folder.");
        }
        catch (Exception exception) when (
            exception is Win32Exception or IOException or InvalidOperationException or UnauthorizedAccessException)
        {
            ShowCommandFeedback($"Could not open app support folder: {exception.Message}");
            AddActivity(
                $"Could not open app support folder: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }

        UpdateChrome();
    }

    private void AddFolderFromMachineButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: MachineHealthItem item } ||
                !_graph.Nodes.TryGetValue(item.Id, out var machine))
            {
                return;
            }

            if (!item.CanAddFolder)
            {
                AddActivity(item.FolderActionTooltip);
                ShowCommandFeedback(item.FolderActionTooltip);
                return;
            }

            var folderPath = TryFindCodexRemoteForMachine(machine, out var codexRemote)
                ? await ShowRemoteFolderPickerAsync(codexRemote, DefaultFolderPathFor(machine))
                : await PromptForMachineFolderPathAsync(machine);
            if (folderPath is null)
            {
                AddActivity("Canceled folder creation.");
                return;
            }

            await AddFolderNodeAsync(machine, folderPath);

        });
    }

    private async Task<string?> PickLocalFolderPathAsync()
    {
        var picker = new FolderPicker
        {
            ViewMode = PickerViewMode.List,
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

        var folder = await picker.PickSingleFolderAsync();
        return string.IsNullOrWhiteSpace(folder?.Path) ? null : folder.Path;
    }

    private async Task AddFolderNodeAsync(CanvasNode machine, string folderPath)
    {
        var id = $"folder-{Guid.NewGuid():N}";
        var title = FolderTitleForPath(folderPath);
        _graph.Nodes[id] = new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Folder,
            Title = title,
            Subtitle = folderPath,
            Position = NextFolderPosition(machine),
            Size = CanvasSize.Folder,
            Metadata = new NodeMetadata
            {
                HostID = machine.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID,
                Platform = machine.Metadata.Platform ?? HostPlatforms.Windows,
                FolderPath = folderPath
            },
            ZIndex = _graph.Nodes.Count
        };

        var edgeID = $"edge-{Guid.NewGuid():N}";
        _graph.ManualEdges[edgeID] = new CanvasEdge
        {
            Id = edgeID,
            Source = machine.Id,
            Target = id,
            Kind = EdgeKinds.MachineFolder,
            IsManual = false
        };

        await SaveGraphAsync();
        AddActivity($"Added {title} folder from {machine.Title}.");
        UpdateChrome();
        await RenderGraphAsync();
    }

    private async Task<string?> PromptForMachineFolderPathAsync(CanvasNode machine)
    {
        var pathBox = new TextBox
        {
            Header = "Folder path",
            Text = DefaultFolderPathFor(machine),
            PlaceholderText = DefaultFolderPathFor(machine),
            MinWidth = 360
        };

        var content = new StackPanel
        {
            Spacing = 10
        };
        content.Children.Add(new TextBlock
        {
            Text = $"Enter a project folder path on {machine.Title}.",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(pathBox);

        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = "Add Folder",
            Content = content,
            PrimaryButtonText = "Add Folder",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary)
        {
            return null;
        }

        var path = pathBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(path))
        {
            AddActivity("Folder path is required.");
            return null;
        }

        return path;
    }

    private async Task<string?> ShowRemoteFolderPickerAsync(
        CodexDesktopRemote remote,
        string initialPath,
        RemoteFolderPickerMode mode = RemoteFolderPickerMode.ChooseProject)
    {
        var startPath = string.IsNullOrWhiteSpace(initialPath) ? "~" : initialPath.Trim();
        var selectedPath = "";
        var currentPath = startPath;
        var isLoading = false;
        RemoteFolderListing? listing = null;
        using var cancellation = new CancellationTokenSource();

        var titleBlock = new TextBlock
        {
            Text = mode == RemoteFolderPickerMode.ShowContents ? "Folder Contents" : "Choose Project Folder",
            FontSize = 18,
            Foreground = BrushFromHex("#F2F5F9")
        };
        var subtitleBlock = new TextBlock
        {
            Text = remote.DisplayName,
            FontSize = 12,
            Foreground = BrushFromHex("#A7B0BF"),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var headerText = new StackPanel
        {
            Spacing = 2
        };
        headerText.Children.Add(titleBlock);
        headerText.Children.Add(subtitleBlock);

        var header = new Grid
        {
            ColumnSpacing = 10
        };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var headerIconSurface = new Border
        {
            Width = 34,
            Height = 34,
            CornerRadius = new CornerRadius(8),
            Background = BrushFromHex("#18FFD60A"),
            Child = new FontIcon
            {
                Glyph = "\uE8B7",
                FontSize = 16,
                Foreground = BrushFromHex("#FFD60A")
            }
        };
        Grid.SetColumn(headerText, 1);
        header.Children.Add(headerIconSurface);
        header.Children.Add(headerText);

        var parentButton = RemoteFolderIconButton("\uE70E", "Parent folder");
        var homeButton = RemoteFolderIconButton("\uE80F", "Home folder");
        var openButton = RemoteFolderIconButton("\uE8E5", "Open path");
        var refreshButton = RemoteFolderIconButton("\uE72C", "Refresh");
        var pathBox = new TextBox
        {
            Text = startPath,
            PlaceholderText = "Folder path",
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            MinWidth = 320
        };

        var pathBar = new Grid
        {
            ColumnSpacing = 8
        };
        pathBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        pathBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        pathBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        pathBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        pathBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(homeButton, 1);
        Grid.SetColumn(pathBox, 2);
        Grid.SetColumn(openButton, 3);
        Grid.SetColumn(refreshButton, 4);
        pathBar.Children.Add(parentButton);
        pathBar.Children.Add(homeButton);
        pathBar.Children.Add(pathBox);
        pathBar.Children.Add(openButton);
        pathBar.Children.Add(refreshButton);

        var folderRows = new StackPanel
        {
            Spacing = 0
        };
        var folderScroll = new ScrollViewer
        {
            Content = folderRows,
            Height = 290,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var footerPathText = new TextBlock
        {
            Text = startPath,
            FontSize = 11,
            Foreground = BrushFromHex("#8F9BAA"),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var progress = new ProgressRing
        {
            Width = 28,
            Height = 28,
            IsActive = false,
            Visibility = Visibility.Collapsed
        };
        var cancelButton = RemoteFolderFooterButton(
            mode == RemoteFolderPickerMode.ShowContents ? "Close" : "Cancel",
            prominent: false);
        var addCurrentButton = RemoteFolderCurrentFolderButton();
        addCurrentButton.Visibility = mode == RemoteFolderPickerMode.ChooseProject
            ? Visibility.Visible
            : Visibility.Collapsed;

        var folderSurface = new Border
        {
            BorderBrush = BrushFromHex("#24FFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Background = BrushFromHex("#0CFFFFFF"),
            Child = folderScroll
        };
        var body = new StackPanel
        {
            Width = 620,
            Spacing = 12
        };
        body.Children.Add(header);
        body.Children.Add(pathBar);
        body.Children.Add(folderSurface);

        var footerGrid = new Grid
        {
            ColumnSpacing = 10
        };
        footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(progress, 1);
        Grid.SetColumn(cancelButton, 2);
        Grid.SetColumn(addCurrentButton, 3);
        footerGrid.Children.Add(footerPathText);
        footerGrid.Children.Add(progress);
        footerGrid.Children.Add(cancelButton);
        footerGrid.Children.Add(addCurrentButton);
        body.Children.Add(footerGrid);

        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Content = body,
            RequestedTheme = ElementTheme.Dark
        };

        void UpdateCurrentFolderAction(bool loading)
        {
            var presentation = RemoteFolderPickerFooterPresentation.Resolve(listing?.Path, pathBox.Text);
            addCurrentButton.IsEnabled = !loading && presentation.CanAddCurrentFolder;
            ToolTipService.SetToolTip(
                addCurrentButton,
                presentation.UnavailableReason ?? presentation.AutomationName);
            AutomationProperties.SetName(addCurrentButton, presentation.AutomationName);
        }

        void UpdateLoadingState(bool loading)
        {
            isLoading = loading;
            progress.IsActive = loading;
            progress.Visibility = loading ? Visibility.Visible : Visibility.Collapsed;
            parentButton.IsEnabled = !loading && listing?.ParentPath is not null;
            homeButton.IsEnabled = !loading;
            openButton.IsEnabled = !loading && !string.IsNullOrWhiteSpace(pathBox.Text);
            refreshButton.IsEnabled = !loading;
            UpdateCurrentFolderAction(loading);
        }

        void AddStatusRow(string glyph, string message, string color)
        {
            var row = new Grid
            {
                ColumnSpacing = 8,
                Padding = new Thickness(12, 11, 12, 11)
            };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new FontIcon
            {
                Glyph = glyph,
                FontSize = 14,
                Foreground = BrushFromHex(color)
            });
            var text = new TextBlock
            {
                Text = message,
                FontSize = 12,
                Foreground = BrushFromHex(color),
                TextWrapping = TextWrapping.Wrap
            };
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            folderRows.Children.Add(row);
        }

        void RebuildRows(string? errorMessage = null)
        {
            folderRows.Children.Clear();
            if (!string.IsNullOrWhiteSpace(errorMessage))
            {
                AddStatusRow("\uE7BA", errorMessage, "#F59E0B");
            }
            else if (listing?.Entries.Count == 0)
            {
                AddStatusRow("\uE8B7", "No folders in this location.", "#8F9BAA");
            }

            foreach (var entry in listing?.Entries ?? [])
            {
                var openContent = new Grid
                {
                    ColumnSpacing = 8,
                    Padding = new Thickness(10, 7, 10, 7)
                };
                openContent.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                openContent.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                openContent.Children.Add(new FontIcon
                {
                    Glyph = "\uE8B7",
                    FontSize = 15,
                    Foreground = BrushFromHex("#FFD60A")
                });
                var textStack = new StackPanel
                {
                    Spacing = 2
                };
                textStack.Children.Add(new TextBlock
                {
                    Text = entry.Name,
                    FontSize = 13,
                    Foreground = BrushFromHex("#F2F5F9"),
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                textStack.Children.Add(new TextBlock
                {
                    Text = entry.Path,
                    FontSize = 11,
                    Foreground = BrushFromHex("#8F9BAA"),
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                Grid.SetColumn(textStack, 1);
                openContent.Children.Add(textStack);

                var openRowButton = new Button
                {
                    Tag = entry,
                    Content = openContent,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Stretch,
                    Background = BrushFromHex("#00FFFFFF"),
                    BorderBrush = BrushFromHex("#00FFFFFF"),
                    BorderThickness = new Thickness(0),
                    Padding = new Thickness(0),
                    CornerRadius = new CornerRadius(6)
                };
                ToolTipService.SetToolTip(openRowButton, "Open folder");
                AutomationProperties.SetName(openRowButton, $"Open {entry.Name}");
                openRowButton.Click += (_, _) =>
                {
                    if (!isLoading && openRowButton.Tag is RemoteFolderEntry selectedEntry)
                    {
                        RunWindowOperation(lease => LoadAsync(selectedEntry.Path, lease));
                    }
                };

                var addButton = RemoteFolderIconButton("\uE73E", "Add this folder");
                addButton.Visibility = mode == RemoteFolderPickerMode.ChooseProject
                    ? Visibility.Visible
                    : Visibility.Collapsed;
                addButton.Tag = entry;
                addButton.Click += (_, _) =>
                {
                    if (addButton.Tag is RemoteFolderEntry selectedEntry)
                    {
                        selectedPath = selectedEntry.Path.Trim();
                        dialog.Hide();
                    }
                };

                var row = new Grid
                {
                    ColumnSpacing = 6,
                    Padding = new Thickness(0, 1, 6, 1)
                };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                Grid.SetColumn(addButton, 1);
                row.Children.Add(openRowButton);
                row.Children.Add(addButton);
                folderRows.Children.Add(row);
            }
        }

        async Task LoadAsync(string path, WindowLifetimeLease lease)
        {
            var requestedPath = string.IsNullOrWhiteSpace(path) ? "~" : path.Trim();
            UpdateLoadingState(true);
            footerPathText.Text = requestedPath;
            using var loadCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                cancellation.Token,
                lease.CancellationToken);
            try
            {
                var nextListing = await CodexRemoteTunnelService.ListRemoteFoldersAsync(
                    remote,
                    requestedPath,
                    loadCancellation.Token);
                if (!_windowLifetime.IsCurrent(lease) || cancellation.IsCancellationRequested)
                {
                    return;
                }

                listing = nextListing;
                currentPath = nextListing.Path;
                pathBox.Text = nextListing.Path;
                footerPathText.Text = nextListing.Path;
                RebuildRows();
            }
            catch (OperationCanceledException) when (loadCancellation.IsCancellationRequested)
            {
            }
            catch (Exception exception)
            {
                if (!_windowLifetime.IsCurrent(lease) || cancellation.IsCancellationRequested)
                {
                    return;
                }

                var message = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message);
                footerPathText.Text = currentPath;
                RebuildRows(message);
            }
            finally
            {
                if (_windowLifetime.IsCurrent(lease) && !cancellation.IsCancellationRequested)
                {
                    UpdateLoadingState(false);
                }
            }
        }

        parentButton.Click += (_, _) =>
        {
            if (listing?.ParentPath is { } parentPath)
            {
                RunWindowOperation(lease => LoadAsync(parentPath, lease));
            }
        };
        homeButton.Click += (_, _) => RunWindowOperation(lease => LoadAsync(startPath, lease));
        openButton.Click += (_, _) => RunWindowOperation(lease => LoadAsync(pathBox.Text, lease));
        refreshButton.Click += (_, _) => RunWindowOperation(lease => LoadAsync(currentPath, lease));
        cancelButton.Click += (_, _) => dialog.Hide();
        addCurrentButton.Click += (_, _) =>
        {
            var presentation = RemoteFolderPickerFooterPresentation.Resolve(listing?.Path, pathBox.Text);
            if (!presentation.CanAddCurrentFolder)
            {
                ShowCommandFeedback(presentation.UnavailableReason ?? "Choose a folder before adding it.");
                return;
            }

            selectedPath = presentation.SelectedCurrentPath;
            dialog.Hide();
        };
        pathBox.TextChanged += (_, _) =>
        {
            openButton.IsEnabled = !isLoading && !string.IsNullOrWhiteSpace(pathBox.Text);
            UpdateCurrentFolderAction(isLoading);
        };
        dialog.Opened += (_, _) => RunWindowOperation(lease => LoadAsync(startPath, lease));
        dialog.Closing += (_, _) => cancellation.Cancel();
        UpdateCurrentFolderAction(isLoading);

        await dialog.ShowAsync();

        return string.IsNullOrWhiteSpace(selectedPath) ? null : selectedPath;
    }

    private static Button RemoteFolderCurrentFolderButton()
    {
        var presentation = RemoteFolderPickerFooterPresentation.Resolve(null, null);
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6
        };
        content.Children.Add(new FontIcon
        {
            Glyph = presentation.AddGlyph,
            FontSize = 12
        });
        content.Children.Add(new TextBlock
        {
            Text = presentation.AddLabel,
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center
        });

        var button = new Button
        {
            MinHeight = 32,
            MinWidth = 68,
            Padding = new Thickness(12, 0, 12, 0),
            CornerRadius = new CornerRadius(6),
            Background = BrushFromHex("#0A84FF"),
            BorderBrush = BrushFromHex("#0A84FF"),
            BorderThickness = new Thickness(1),
            Foreground = BrushFromHex("#FFFFFF"),
            Content = content
        };
        ToolTipService.SetToolTip(button, presentation.UnavailableReason);
        AutomationProperties.SetName(button, presentation.AutomationName);
        return button;
    }

    private static Button RemoteFolderFooterButton(string label, bool prominent)
    {
        var button = new Button
        {
            MinHeight = 32,
            MinWidth = 68,
            Padding = new Thickness(12, 0, 12, 0),
            CornerRadius = new CornerRadius(6),
            Background = prominent ? BrushFromHex("#0A84FF") : BrushFromHex("#1214161A"),
            BorderBrush = prominent ? BrushFromHex("#0A84FF") : BrushFromHex("#24FFFFFF"),
            BorderThickness = new Thickness(1),
            Foreground = BrushFromHex(prominent ? "#FFFFFF" : "#D7DCE5"),
            Content = label
        };
        ToolTipService.SetToolTip(button, label);
        AutomationProperties.SetName(button, label);
        return button;
    }

    private static Button RemoteFolderIconButton(string glyph, string tooltip)
    {
        var button = new Button
        {
            Width = 32,
            Height = 32,
            MinWidth = 0,
            MinHeight = 0,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(6),
            Background = BrushFromHex("#1214161A"),
            BorderBrush = BrushFromHex("#24FFFFFF"),
            BorderThickness = new Thickness(1),
            Foreground = BrushFromHex("#D7DCE5"),
            Content = new FontIcon
            {
                Glyph = glyph,
                FontSize = 13
            }
        };
        ToolTipService.SetToolTip(button, tooltip);
        AutomationProperties.SetName(button, tooltip);
        return button;
    }

    private bool TryFindCodexRemoteForMachine(CanvasNode machine, out CodexDesktopRemote remote)
    {
        remote = _discoveredCodexRemotes.FirstOrDefault(candidate =>
            CodexRemoteTunnelService.CanBrowseRemoteFolders(candidate) &&
            (SameIdentifier(candidate.Id, machine.Id) ||
                SameIdentifier(candidate.HostID, machine.Id) ||
                SameIdentifier(candidate.HostID, machine.Metadata.HostID)))!;
        if (remote is not null)
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(machine.Metadata.CodexHome) &&
            machine.Metadata.HostStatus == HostStatuses.Connected &&
            CodexDesktopRemoteService.IsValidSSHTarget(machine.Subtitle))
        {
            var persistedRemote = new CodexDesktopRemote
            {
                Id = machine.Id,
                DisplayName = machine.Title,
                HostID = machine.Metadata.HostID ?? machine.Id,
                Hostname = machine.Subtitle,
                Source = "workflow"
            };
            if (CodexRemoteTunnelService.CanBrowseRemoteFolders(persistedRemote))
            {
                remote = persistedRemote;
                return true;
            }
        }

        return false;
    }

    private static string DefaultFolderPathFor(CanvasNode machine)
    {
        var platform = machine.Metadata.Platform ?? HostPlatforms.Unknown;
        if (platform == HostPlatforms.Windows)
        {
            if (!string.IsNullOrWhiteSpace(machine.Metadata.CodexHome) &&
                machine.Metadata.CodexHome.EndsWith("\\.codex", StringComparison.OrdinalIgnoreCase))
            {
                return $"{machine.Metadata.CodexHome[..^"\\.codex".Length]}\\Desktop";
            }

            return "C:\\Users\\User\\Desktop";
        }

        if ((platform == HostPlatforms.MacOS || platform == HostPlatforms.Linux) &&
            !string.IsNullOrWhiteSpace(machine.Metadata.CodexHome) &&
            machine.Metadata.CodexHome.EndsWith("/.codex", StringComparison.OrdinalIgnoreCase))
        {
            return machine.Metadata.CodexHome[..^"/.codex".Length];
        }

        return "~";
    }

    private static string FolderTitleForPath(string folderPath)
    {
        var trimmed = folderPath.Trim().TrimEnd('\\', '/');
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return "Folder";
        }

        var lastSlash = Math.Max(trimmed.LastIndexOf('\\'), trimmed.LastIndexOf('/'));
        return lastSlash >= 0 && lastSlash < trimmed.Length - 1
            ? trimmed[(lastSlash + 1)..]
            : trimmed;
    }

    private void DisconnectMachineButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: MachineHealthItem item } ||
                !_graph.Nodes.TryGetValue(item.Id, out var machine))
            {
                return;
            }

            if (!await ConfirmDisconnectMachineAsync(machine))
            {
                AddActivity("Canceled machine disconnect.");
                return;
            }

            machine.Metadata.HostStatus = HostStatuses.Disconnected;
            machine.Metadata.HostLastError = null;
            StopCodexRemoteTunnel(machine.Id);
            if (IsLocalHostId(machine.Metadata.HostID))
            {
                UnregisterLocalAppServerEndpoint(machine);
                SyncLocalRuntimeStatusFromGraph();
            }

            await SaveGraphAsync();
            AddActivity($"Disconnected {machine.Title}.");
            UpdateChrome();
            await RenderGraphAsync();

        });
    }

    private void ActivityButton_Click(object sender, RoutedEventArgs e)
    {
        var shouldShowPopover = !_isActivityHistoryVisible;
        WorkflowPopover.Visibility = Visibility.Collapsed;
        WorkflowNamePopover.Visibility = Visibility.Collapsed;
        NewThreadPopover.Visibility = Visibility.Collapsed;
        HealthPopover.Visibility = Visibility.Collapsed;
        PairingPopover.Visibility = Visibility.Collapsed;
        _isActivityHistoryVisible = shouldShowPopover;
        UpdateActivityHistoryChrome();
        UpdateChrome();
    }

    private void CloseActivityPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        _isActivityHistoryVisible = false;
        UpdateChrome();
    }

    private void CloseActivityRailButton_Click(object sender, RoutedEventArgs e)
    {
        _isActivityRailCollapsed = !_isActivityRailCollapsed;
        SavePreferences();
        AddActivity(_isActivityRailCollapsed ? "Activity panel minimized." : "Activity panel expanded.");
        UpdateChrome();
    }

    private void NotificationPreferenceMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleMenuFlyoutItem item)
        {
            return;
        }

        if (ReferenceEquals(item, NotifyCompletedRailMenuItem) ||
            ReferenceEquals(item, NotifyCompletedPopoverMenuItem))
        {
            _notifyOnCompleted = item.IsChecked;
        }
        else if (ReferenceEquals(item, NotifyNeedsInputRailMenuItem) ||
            ReferenceEquals(item, NotifyNeedsInputPopoverMenuItem))
        {
            _notifyOnNeedsInput = item.IsChecked;
        }
        else if (ReferenceEquals(item, NotifyFailedRailMenuItem) ||
            ReferenceEquals(item, NotifyFailedPopoverMenuItem))
        {
            _notifyOnFailed = item.IsChecked;
        }

        PruneDisabledTopNotifications();
        SavePreferences();
        UpdateChrome();
    }

    private void DismissTopNotificationButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: TopNotificationItem item })
        {
            _topNotifications.Remove(item);
            UpdateTopNotificationsChrome();
        }
    }

    private void DismissAllTopNotificationsButton_Click(object sender, RoutedEventArgs e)
    {
        _topNotifications.Clear();
        UpdateTopNotificationsChrome();
    }

    private void AttentionRailCollapseButton_Click(object sender, RoutedEventArgs e)
    {
        _isAttentionRailCollapsed = !_isAttentionRailCollapsed;
        SavePreferences();
        UpdateChrome();
    }

    private void RuntimeDiagnosticsRailCollapseButton_Click(object sender, RoutedEventArgs e)
    {
        _isRuntimeDiagnosticsCollapsed = !_isRuntimeDiagnosticsCollapsed;
        SavePreferences();
        UpdateChrome();
    }

    private void RefreshPairingButton_Click(object sender, RoutedEventArgs e)
    {
        PairingPopover.Visibility = Visibility.Visible;
        SetPairingMessage(
            WindowsDeviceEnrollmentAvailability.Title,
            WindowsDeviceEnrollmentAvailability.Detail,
            "#FFD60A",
            "#1AFFD60A",
            "#26FFD60A",
            "\uE7BA");
    }

    private void PairingCodeBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isUpdatingPairingCode)
        {
            return;
        }

        UpdatePairingPreviewFromInput();
    }

    private void ImportPairingButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var payload = MapofAgentsPairingPayload.Decode(PairingCodeBox.Text);
            payload.ValidateForImport();
            var endpoint = payload.PreferredEndpoint()
                ?? throw new MapofAgentsPairingException("No pairing endpoint satisfies the Windows App Server security requirements.");

            RemoteNameBox.Text = string.IsNullOrWhiteSpace(payload.Name) ? "Paired Codex App Server" : payload.Name.Trim();
            EndpointBox.Text = endpoint.Url.Trim();
            BearerTokenBox.Password = payload.BearerToken.Trim();
            _importedPairingEndpointUrl = endpoint.Url.Trim();
            _importedPairingBearerToken = payload.BearerToken.Trim();
            _isUpdatingPairingCode = true;
            try
            {
                PairingCodeBox.Text = "";
            }
            finally
            {
                _isUpdatingPairingCode = false;
            }

            ClearPairingPreview();
            _isMachinesRailVisible = true;
            _isMachinesRailCollapsed = false;
            _isMachineConnectFormVisible = true;
            SetPairingMessage(
                "Pairing imported",
                string.IsNullOrWhiteSpace(endpoint.Label)
                    ? "Ready to connect with the imported endpoint."
                    : $"Ready to connect with {endpoint.Label}.",
                "#30D158",
                "#1A30D158",
                "#2630D158",
                "\uE73E");
            AddActivity($"Imported pairing for {RemoteNameBox.Text}.");
            UpdateChrome();
            UpdateBearerTokenBoxVisibility();
            EndpointBox.Focus(FocusState.Programmatic);
            EndpointBox.SelectAll();
        }
        catch (MapofAgentsPairingException exception)
        {
            SetPairingMessage(
                "Pairing import failed",
                exception.Message,
                "#B42318",
                "#1AB42318",
                "#26B42318",
                "\uE946");
            AddActivity(
                $"Pairing import failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void ClosePairingPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        PairingPopover.Visibility = Visibility.Collapsed;
    }

    private void SetReadyPairingMessage()
    {
        PairingNetworkAccessBorder.Visibility = Visibility.Collapsed;
        ClearPairingHeaderSubtitle();
        SetPairingMessage(
            "Ready to import",
            "Paste a mapofagents pairing URL or payload to prepare a remote connection.",
            "#0A84FF",
            "#1A0A84FF",
            "#260A84FF",
            "\uED14");
    }

    private void UpdatePairingPreviewFromInput()
    {
        if (PairingCodeBox is null)
        {
            return;
        }

        var text = PairingCodeBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            ClearPairingPreview();
            SetReadyPairingMessage();
            return;
        }

        try
        {
            var payload = MapofAgentsPairingPayload.Decode(text);
            var preview = MapofAgentsPairingImportPreview.FromPayload(payload);
            ApplyPairingPreview(preview);
        }
        catch (MapofAgentsPairingException exception)
        {
            ClearPairingPreview();
            SetPairingMessage(
                "Pairing preview unavailable",
                exception.Message,
                "#B42318",
                "#1AB42318",
                "#26B42318",
                "\uE946");
        }
    }

    private void ApplyPairingPreview(MapofAgentsPairingImportPreview preview)
    {
        _pairingEndpointPreviewItems.Clear();
        foreach (var endpoint in preview.Endpoints)
        {
            _pairingEndpointPreviewItems.Add(PairingEndpointPreviewItem.FromPreview(endpoint));
        }

        PairingPreviewHostText.Text = preview.HostName;
        PairingPreviewExpiryText.Text = preview.ExpiresAt is { } expiresAt
            ? $"Valid until {expiresAt.ToLocalTime():t}"
            : "No expiration provided";
        PairingPreviewPanel.Visibility = Visibility.Visible;
        ShowPairingHeaderSubtitle(preview.HostName);
        PairingNetworkAccessBorder.Visibility = Visibility.Collapsed;

        var preferred = preview.PreferredEndpoint;
        var detail = preferred is null
            ? "Ready to import this pairing."
            : $"Ready to import {preferred.Label} ({preferred.Kind}).";
        SetPairingMessage(
            "Pairing ready",
            detail,
            "#30D158",
            "#1A30D158",
            "#2630D158",
            "\uE73E");
    }

    private void ShowPairingHeaderSubtitle(string? hostName)
    {
        var subtitle = PairingMessagePresentation.HeaderSubtitle(hostName);
        if (subtitle is null)
        {
            ClearPairingHeaderSubtitle();
            return;
        }

        PairingPopoverSubtitle.Text = subtitle;
        PairingPopoverSubtitle.Visibility = Visibility.Visible;
    }

    private void ClearPairingHeaderSubtitle()
    {
        PairingPopoverSubtitle.Text = "";
        PairingPopoverSubtitle.Visibility = Visibility.Collapsed;
    }

    private void ClearPairingPreview()
    {
        _pairingEndpointPreviewItems.Clear();
        if (PairingPreviewPanel is not null)
        {
            PairingPreviewPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void SetPairingMessage(
        string title,
        string detail,
        string accentColor,
        string backgroundColor,
        string borderColor,
        string glyph)
    {
        var presentation = PairingMessagePresentation.Resolve(
            accentColor,
            backgroundColor,
            borderColor);
        PairingStatusIcon.Glyph = glyph;
        PairingStatusIcon.Foreground = BrushFromHex(presentation.AccentHex);
        PairingStatusText.Text = title;
        PairingStatusText.Foreground = BrushFromHex(presentation.AccentHex);
        PairingDetailBorder.Background = BrushFromHex(presentation.BackgroundHex);
        PairingDetailBorder.BorderBrush = BrushFromHex(presentation.BorderHex);
        PairingDetailText.Text = detail;
        PairingDetailText.Foreground = BrushFromHex(presentation.DetailForegroundHex);
    }

    private void CloseWorkflowNamePopoverButton_Click(object sender, RoutedEventArgs e)
    {
        _workflowNameEditorMode = null;
        WorkflowNamePopover.Visibility = Visibility.Collapsed;
    }

    private void SaveWorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        var currentTitle = ToolbarWorkflowPresentation.DisplayTitle(_graph.Title);
        BeginWorkflowNameEdit(WorkflowNameEditorMode.Rename, currentTitle);
    }

    private void DuplicateWorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        var currentTitle = ToolbarWorkflowPresentation.DisplayTitle(_graph.Title);
        BeginWorkflowNameEdit(WorkflowNameEditorMode.Duplicate, NextCopyWorkflowName(currentTitle));
    }

    private void NewWorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        BeginWorkflowNameEdit(WorkflowNameEditorMode.Create, NextWorkflowName());
    }

    private void SubmitWorkflowNameButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SubmitWorkflowNameAsync();

        });
    }

    private void WorkflowNameBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                e.Handled = true;
                await SubmitWorkflowNameAsync();
            }

        });
    }

    private void WorkflowNameBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateWorkflowNameSubmitAvailability();
    }

    private void BeginWorkflowNameEdit(WorkflowNameEditorMode mode, string draftName)
    {
        _workflowNameEditorMode = mode;
        WorkflowPopover.Visibility = Visibility.Collapsed;
        NewThreadPopover.Visibility = Visibility.Collapsed;
        HealthPopover.Visibility = Visibility.Collapsed;
        PairingPopover.Visibility = Visibility.Collapsed;

        var presentation = ToolbarWorkflowPresentation.ResolveNameEditor(WorkflowNameEditorModeKey(mode));
        WorkflowNameTitleText.Text = presentation.Title;
        WorkflowNameSubmitText.Text = presentation.ActionTitle;
        WorkflowNameIconHost.Background = BrushFromHex(presentation.BackgroundHex);
        WorkflowNameIconHost.Child = WorkflowIconElement(
            presentation.IconKind,
            presentation.IconSize,
            presentation.IconHex);
        CloseWorkflowNamePopoverButton.Width = presentation.CloseButtonSize;
        CloseWorkflowNamePopoverButton.Height = presentation.CloseButtonSize;
        CloseWorkflowNamePopoverIcon.Glyph = presentation.CloseGlyph;
        CloseWorkflowNamePopoverIcon.FontSize = presentation.CloseIconSize;
        WorkflowNameBox.Text = draftName;
        UpdateWorkflowNameSubmitAvailability();
        WorkflowNamePopover.Visibility = Visibility.Visible;
        WorkflowNameBox.Focus(FocusState.Programmatic);
        WorkflowNameBox.SelectAll();
    }

    private void UpdateWorkflowNameSubmitAvailability()
    {
        var hasName = !string.IsNullOrWhiteSpace(WorkflowNameBox.Text);
        WorkflowNameSubmitButton.IsEnabled = hasName;
        WorkflowNameSubmitButton.Opacity = hasName ? 1.0 : 0.55;
        ToolTipService.SetToolTip(
            WorkflowNameSubmitButton,
            hasName ? WorkflowNameSubmitText.Text : "Enter a workflow name before saving.");
    }

    private async Task SubmitWorkflowNameAsync()
    {
        if (_workflowNameEditorMode is not { } mode)
        {
            return;
        }

        var title = WorkflowNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            ShowCommandFeedback("Enter a workflow name before saving.");
            return;
        }

        switch (mode)
        {
            case WorkflowNameEditorMode.Create:
                _graph = await _store.CreateWorkflowAsync(title, Environment.MachineName);
                ClearWorkflowSelectionState();
                AddActivity($"Created {title}.");
                break;
            case WorkflowNameEditorMode.Rename:
                _graph.Title = title;
                await SaveGraphAsync();
                AddActivity($"Renamed workflow to {title}.");
                break;
            case WorkflowNameEditorMode.Duplicate:
                _graph = await _store.DuplicateActiveWorkflowAsync(title);
                ClearWorkflowSelectionState();
                AddActivity($"Saved workflow copy as {title}.");
                break;
        }

        _workflowNameEditorMode = null;
        WorkflowNamePopover.Visibility = Visibility.Collapsed;
        WorkflowPopover.Visibility = Visibility.Collapsed;
        await RefreshWorkflowMenuAsync();
        await RefreshWorkflowMembershipsAsync();
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void ClearWorkflowSelectionState()
    {
        _selectedNodeId = null;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        _readerThreadIds.Clear();
        SelectionInspector.Visibility = Visibility.Collapsed;
    }

    private static string WorkflowNameEditorModeKey(WorkflowNameEditorMode mode)
    {
        return mode switch
        {
            WorkflowNameEditorMode.Create => ToolbarWorkflowPresentation.NameEditorCreateMode,
            WorkflowNameEditorMode.Rename => ToolbarWorkflowPresentation.NameEditorRenameMode,
            WorkflowNameEditorMode.Duplicate => ToolbarWorkflowPresentation.NameEditorDuplicateMode,
            _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unknown workflow name editor mode.")
        };
    }

    private void DeleteWorkflowButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            var deletedTitle = string.IsNullOrWhiteSpace(_graph.Title) ? "workflow" : _graph.Title;
            if (_workflowMenuItems.Count <= 1)
            {
                ShowCommandFeedback("Keep at least one workflow.");
                await RefreshWorkflowMenuAsync();
                return;
            }

            if (!await ConfirmDeleteWorkflowAsync(deletedTitle))
            {
                AddActivity("Canceled workflow deletion.");
                return;
            }

            var replacement = await _store.DeleteWorkflowAsync(_graph.WorkspaceID);
            if (replacement is null)
            {
                ShowCommandFeedback("Keep at least one workflow.");
                await RefreshWorkflowMenuAsync();
                return;
            }

            _graph = replacement;
            _selectedNodeId = null;
            _selectedEdgeId = null;
            _pendingLinkSourceNodeId = null;
            _readerThreadIds.Clear();
            WorkflowPopover.Visibility = Visibility.Collapsed;
            SelectionInspector.Visibility = Visibility.Collapsed;
            await RefreshWorkflowMenuAsync();
            await RefreshWorkflowMembershipsAsync();
            AddActivity($"Deleted {deletedTitle}.");
            UpdateChrome();
            await RenderGraphAsync();

        });
    }

    private async Task SelectWorkflowAsync(WorkflowMenuItem item)
    {
        if (item.IsActive)
        {
            return;
        }

        var selected = await _store.SelectWorkflowAsync(item.Id);
        if (selected is null)
        {
            AddActivity("Workflow could not be selected.");
            await RefreshWorkflowMenuAsync();
            return;
        }

        _graph = selected;
        _selectedNodeId = null;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        _readerThreadIds.Clear();
        WorkflowPopover.Visibility = Visibility.Collapsed;
        SelectionInspector.Visibility = Visibility.Collapsed;
        await RefreshWorkflowMenuAsync();
        await RefreshWorkflowMembershipsAsync();
        AddActivity($"Switched to {item.Title}.");
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void CloseNewThreadButton_Click(object sender, RoutedEventArgs e)
    {
        NewThreadPopover.Visibility = Visibility.Collapsed;
        ClearNewThreadMentionSuggestions();
    }

    private void NewThreadTargetBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized)
        {
            return;
        }

        UpdateNewThreadTargetSummary();
        UpdateNewThreadMentionSuggestions();
    }

    private void NewThreadTargetKindBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized)
        {
            return;
        }

        _newThreadTargetKind = ComboBoxTag(NewThreadTargetKindBox, NodeKinds.Folder) == NodeKinds.Machine
            ? NodeKinds.Machine
            : NodeKinds.Folder;
        UpdateNewThreadTargetSource();
        UpdateNewThreadMentionSuggestions();
    }

    private void NewThreadModelBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized || _isUpdatingNewThreadModelChoices)
        {
            return;
        }

        if (SelectedNewThreadModelOption() is { } model)
        {
            _isUpdatingNewThreadModelChoices = true;
            try
            {
                SyncNewThreadEffortChoices(model, SelectedNewThreadEffort());
            }
            finally
            {
                _isUpdatingNewThreadModelChoices = false;
            }
        }

        UpdateNewThreadComposerSummary();
        UpdateNewThreadReadyText();
    }

    private void NewThreadEffortBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized)
        {
            return;
        }

        UpdateNewThreadComposerSummary();
        UpdateNewThreadReadyText();
    }

    private void NewThreadSandboxModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized)
        {
            return;
        }

        UpdateNewThreadPermissionWarning();
        UpdateNewThreadReadyText();
    }

    private void NewThreadPromptBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            ApplyMentionComposerLayout(
                textBox,
                MentionComposerLayout.NewThreadMinLines,
                MentionComposerLayout.NewThreadMaxLines);
        }

        if (!_isViewInitialized || _isApplyingNewThreadMention)
        {
            return;
        }

        UpdateNewThreadMentionSuggestions();
    }

    private void NewThreadPromptBox_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            AttachComposerDraftBoxKeyHandler(textBox);
            ApplyMentionComposerLayout(
                textBox,
                MentionComposerLayout.NewThreadMinLines,
                MentionComposerLayout.NewThreadMaxLines);
        }
    }

    private void NewThreadMentionSuggestionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MentionSuggestionItem item })
        {
            return;
        }

        ApplyNewThreadMention(item);
    }

    private void ApplyNewThreadMention(MentionSuggestionItem item)
    {
        if (NewThreadPromptBox is null ||
            !TryActiveMention(NewThreadPromptBox.Text, out var mention))
        {
            return;
        }

        var beforeMention = NewThreadPromptBox.Text[..mention.StartIndex];
        var nextText = $"{beforeMention}{item.InsertionText} ";
        _isApplyingNewThreadMention = true;
        NewThreadPromptBox.Text = nextText;
        NewThreadPromptBox.SelectionStart = nextText.Length;
        _isApplyingNewThreadMention = false;
        ClearNewThreadMentionSuggestions();
        NewThreadPromptBox.Focus(FocusState.Programmatic);
    }

    private void ThreadPopoverDraftBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            ApplyMentionComposerLayout(
                textBox,
                MentionComposerLayout.ThreadReplyMinLines,
                MentionComposerLayout.ThreadReplyMaxLines);
        }

        if (!_isViewInitialized || _isApplyingThreadPopoverMention)
        {
            return;
        }

        UpdateThreadPopoverMentionSuggestions();
        UpdateThreadPopoverSendChrome();
    }

    private void ThreadPopoverMentionSuggestionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MentionSuggestionItem item })
        {
            return;
        }

        ApplyThreadPopoverMention(item);
    }

    private void ApplyThreadPopoverMention(MentionSuggestionItem item)
    {
        if (ThreadPopoverDraftBox is null ||
            !TryGetSelectedThread(out _) ||
            !TryActiveMention(ThreadPopoverDraftBox.Text, out var mention))
        {
            return;
        }

        _isApplyingThreadPopoverMention = true;
        ThreadPopoverDraftBox.Text = TextWithInsertedMention(ThreadPopoverDraftBox.Text, item, mention);
        ThreadPopoverDraftBox.SelectionStart = ThreadPopoverDraftBox.Text.Length;
        _isApplyingThreadPopoverMention = false;
        ClearThreadPopoverMentionSuggestions();
        UpdateThreadPopoverSendChrome();
        ThreadPopoverDraftBox.Focus(FocusState.Programmatic);
    }

    private void ReaderDraftBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is not TextBox textBox)
        {
            return;
        }

        ApplyMentionComposerLayout(
            textBox,
            MentionComposerLayout.ThreadReplyMinLines,
            MentionComposerLayout.ThreadReplyMaxLines);

        if (!_isViewInitialized || _isApplyingReaderMention)
        {
            return;
        }

        if (TryReaderThreadItem(sender, out var item))
        {
            UpdateReaderMentionSuggestions(item, textBox.Text);
        }
    }

    private void ReaderMentionSuggestionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: MentionSuggestionItem suggestion } ||
            string.IsNullOrWhiteSpace(suggestion.OwnerThreadId) ||
            _readerThreads.FirstOrDefault(item => item.Id == suggestion.OwnerThreadId) is not { } readerItem)
        {
            return;
        }

        ApplyReaderMention(readerItem, suggestion, null);
    }

    private void ApplyReaderMention(
        ReaderThreadItem readerItem,
        MentionSuggestionItem suggestion,
        TextBox? composer)
    {
        if (!TryActiveMention(readerItem.DraftText, out var mention))
        {
            return;
        }

        _isApplyingReaderMention = true;
        readerItem.DraftText = TextWithInsertedMention(readerItem.DraftText, suggestion, mention);
        _isApplyingReaderMention = false;
        ClearReaderMentionSuggestions(readerItem);
        if (composer is not null)
        {
            composer.SelectionStart = composer.Text.Length;
            composer.Focus(FocusState.Programmatic);
        }
    }

    private void CreateThreadFromPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await CreateThreadFromPopoverAsync();

        });
    }

    private void AddReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        if (ReaderCandidateBox.SelectedItem is not NodeChoice { IsOpen: false } choice)
        {
            return;
        }

        AddThreadToReader(choice.Id, openReader: false);
    }

    private void ReaderCandidateBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_isViewInitialized)
        {
            return;
        }

        if (ReaderCandidateBox.SelectedItem is NodeChoice { IsOpen: true })
        {
            SelectFirstAvailableReaderCandidate();
            return;
        }

        UpdateReaderCandidateActionState();
    }

    private void RenameReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item } ||
            !_graph.Nodes.TryGetValue(item.Id, out var node))
        {
            return;
        }

        _selectedNodeId = item.Id;
        _selectedEdgeId = null;
        _isReadingModePresented = false;
        ShowSelectionInspector(node);
        AddActivity($"Opened {node.Title} details for rename.");
        UpdateChrome();
    }

    private void CopyReaderThreadIdButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item } ||
            string.IsNullOrWhiteSpace(item.ThreadIDLabel))
        {
            return;
        }

        CopyTextToClipboard(item.ThreadIDLabel);
        AddActivity($"Copied thread ID for {item.Title}.");
    }

    private void RefreshReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is FrameworkElement { DataContext: ReaderThreadItem item } &&
                _graph.Nodes.TryGetValue(item.Id, out var node))
            {
                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: false, userInitiated: true);
            }

        });
    }

    private void LoadOlderReaderTranscriptButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is FrameworkElement { DataContext: ReaderThreadItem item } &&
                _graph.Nodes.TryGetValue(item.Id, out var node))
            {
                if (_transcriptSessions.Snapshot(node.Id).IsLoadingOlder)
                {
                    ShowCommandFeedback(LoadOlderMessagesActionPresentation.UnavailableReason, sender as FrameworkElement);
                    return;
                }

                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: true, userInitiated: true);
            }

        });
    }

    private void RetryReaderTranscriptButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is FrameworkElement { DataContext: ReaderThreadItem item } &&
                _graph.Nodes.TryGetValue(item.Id, out var node))
            {
                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: false, userInitiated: true);
            }

        });
    }

    private void UseCachedReaderTranscriptButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item } ||
            !_graph.Nodes.TryGetValue(item.Id, out var node))
        {
            return;
        }

        _transcriptSessions.ClearError(node.Id);
        RefreshTranscriptSurfaces(node.Id);
        AddActivity($"Using cached transcript for {node.Title}.");
    }

    private void AttachReaderFilesButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryReaderThreadItem(sender, out var item) ||
                !_graph.Nodes.TryGetValue(item.Id, out var node))
            {
                return;
            }

            if (node.Metadata.RunStatus == ThreadRunStatuses.Running)
            {
                AddActivity($"{node.Title} is running. Stop the turn before changing attachments.");
                return;
            }

            var picker = new FileOpenPicker
            {
                ViewMode = PickerViewMode.List,
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary
            };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

            var files = await picker.PickMultipleFilesAsync();
            AddReaderAttachments(item, files);

        });
    }

    private void PasteReaderAttachmentsButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryReaderThreadItem(sender, out var item) ||
                !_graph.Nodes.TryGetValue(item.Id, out var node))
            {
                return;
            }

            if (node.Metadata.RunStatus == ThreadRunStatuses.Running)
            {
                AddActivity($"{node.Title} is running. Stop the turn before changing attachments.");
                return;
            }

            var didAttach = await AddClipboardAttachmentsAsync(attachment =>
            {
                attachment.ThreadId = item.Id;
                PendingReaderAttachments(item.Id).Add(attachment);
            });

            if (didAttach)
            {
                item.AttachmentErrorText = "";
                AddActivity($"Attached {PendingReaderAttachments(item.Id).Count} pending item{(PendingReaderAttachments(item.Id).Count == 1 ? "" : "s")}.");
            }
            else
            {
                item.AttachmentErrorText = ThreadAttachmentFeedbackPresentation.ClipboardUnavailableReason;
            }

        });
    }

    private void RemoveReaderAttachmentButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: ComposerAttachmentItem attachment } &&
            _readerPendingAttachments.TryGetValue(attachment.ThreadId, out var pendingAttachments))
        {
            pendingAttachments.Remove(attachment);
        }
    }

    private void AddReaderAttachments(ReaderThreadItem item, IEnumerable<StorageFile> files)
    {
        var added = 0;
        var pendingAttachments = PendingReaderAttachments(item.Id);
        foreach (var file in files)
        {
            pendingAttachments.Add(ComposerAttachmentItem.FromStorageFile(file, item.Id));
            added += 1;
        }

        if (added > 0)
        {
            item.AttachmentErrorText = "";
            AddActivity($"Attached {added} file{(added == 1 ? "" : "s")}.");
        }
    }

    private void OpenReaderThreadArtifactsButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item } ||
            !_graph.Nodes.TryGetValue(item.Id, out var node))
        {
            return;
        }

        if (ThreadArtifacts(node).Count == 0)
        {
            ShowCommandFeedback(
                ArtifactsActionPresentation.UnavailableReason,
                sender as FrameworkElement);
            return;
        }

        ShowArtifactsForThread(node);
    }

    private void CloseReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item })
        {
            return;
        }

        ClearReaderMentionSuggestions(item);
        _readerThreadIds.Remove(item.Id);
        _readerPendingAttachments.Remove(item.Id);
        _readerMentionSelections.Remove(item.Id);
        AddActivity($"Closed {item.Title} in reader.");
        UpdateChrome();
    }

    private void StopReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryReaderThreadItem(sender, out var item) ||
                !_graph.Nodes.TryGetValue(item.Id, out var node))
            {
                return;
            }

            await StopThreadAsync(node, "reader", sender as FrameworkElement);

        });
    }

    private async Task StopThreadAsync(
        CanvasNode node,
        string sourceLabel,
        FrameworkElement? feedbackAnchor = null)
    {
        var availability = StopTurnAvailability(node);
        if (!availability.CanInvoke)
        {
            ShowCommandFeedback(
                availability.UnavailableReason ?? StopTurnActionPresentation.NotRunningOrDisconnectedReason,
                feedbackAnchor);
            return;
        }

        var key = StopTurnKey(node);
        if (!_stoppingThreadKeys.Add(key))
        {
            ShowCommandFeedback(StopTurnActionPresentation.AlreadyStoppingReason, feedbackAnchor);
            return;
        }

        UpdateChrome();
        await Task.Yield();

        try
        {
            node.Metadata.RunStatus = ThreadRunStatuses.Idle;
            node.Metadata.LocalTranscript.Add(new LocalThreadMessage
            {
                Role = "system",
                Text = $"Stop requested from the Windows {sourceLabel}.",
                CreatedAt = DateTimeOffset.UtcNow
            });

            await SaveGraphAsync();
            AddActivity($"Stopped {node.Title}.");
        }
        finally
        {
            _stoppingThreadKeys.Remove(key);
            UpdateChrome();
        }

        await RenderGraphAsync();
    }

    private void SendReaderMessageButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryReaderThreadItem(sender, out var item) ||
                !_graph.Nodes.TryGetValue(item.Id, out var node))
            {
                return;
            }

            await SendReaderMessageAsync(item, node, sender as FrameworkElement);

        });
    }

    private void ReaderDraftBox_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            AttachComposerDraftBoxKeyHandler(textBox);
            ApplyMentionComposerLayout(
                textBox,
                MentionComposerLayout.ThreadReplyMinLines,
                MentionComposerLayout.ThreadReplyMaxLines);
        }
    }

    private void ComposerDraftBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is TextBox textBox && TryHandleMentionSelectionKey(textBox, e))
            {
                return;
            }

            if (e.Key != Windows.System.VirtualKey.Enter || IsShiftKeyDown())
            {
                return;
            }

            e.Handled = true;
            if (ReferenceEquals(sender, NewThreadPromptBox))
            {
                await CreateThreadFromPopoverAsync();
                return;
            }

            if (ReferenceEquals(sender, ThreadPopoverDraftBox))
            {
                await SendThreadPopoverMessageAsync(ThreadPopoverSendButton);
                return;
            }

            if (TryReaderThreadItem(sender, out var item) &&
                _graph.Nodes.TryGetValue(item.Id, out var node))
            {
                await SendReaderMessageAsync(item, node, sender as FrameworkElement);
            }

        });
    }

    private bool TryHandleMentionSelectionKey(TextBox composer, KeyRoutedEventArgs e)
    {
        if (!TryMentionSelectionKey(e.Key, out var key) ||
            (key == MentionSelectionKey.Enter && IsShiftKeyDown()))
        {
            return false;
        }

        if (ReferenceEquals(composer, NewThreadPromptBox))
        {
            return HandleMentionSelectionKey(
                composer,
                key,
                _newThreadMentionSelection,
                _newThreadMentionSuggestions,
                HideNewThreadMentionSuggestions,
                ApplyNewThreadMention,
                e);
        }

        if (ReferenceEquals(composer, ThreadPopoverDraftBox))
        {
            return HandleMentionSelectionKey(
                composer,
                key,
                _threadPopoverMentionSelection,
                _threadPopoverMentionSuggestions,
                HideThreadPopoverMentionSuggestions,
                ApplyThreadPopoverMention,
                e);
        }

        if (!TryReaderThreadItem(composer, out var readerItem))
        {
            return false;
        }

        var selection = ReaderMentionSelection(readerItem.Id);
        return HandleMentionSelectionKey(
            composer,
            key,
            selection,
            readerItem.MentionSuggestions,
            () => HideReaderMentionSuggestions(readerItem),
            suggestion => ApplyReaderMention(readerItem, suggestion, composer),
            e);
    }

    private static bool HandleMentionSelectionKey(
        TextBox composer,
        MentionSelectionKey key,
        MentionSelectionController selection,
        IList<MentionSuggestionItem> suggestions,
        Action dismiss,
        Action<MentionSuggestionItem> accept,
        KeyRoutedEventArgs eventArgs)
    {
        var result = selection.Handle(key, suggestions.Count);
        if (!result.Handled)
        {
            return false;
        }

        eventArgs.Handled = true;
        if (result.ShouldDismiss)
        {
            dismiss();
        }
        else if (result.ShouldAccept &&
            result.SelectedIndex >= 0 &&
            result.SelectedIndex < suggestions.Count)
        {
            accept(suggestions[result.SelectedIndex]);
        }
        else
        {
            ApplyMentionSelectionVisuals(selection, suggestions);
        }

        composer.Focus(FocusState.Programmatic);
        return true;
    }

    private static void ApplyMentionSelectionVisuals(
        MentionSelectionController selection,
        IEnumerable<MentionSuggestionItem> suggestions)
    {
        var index = 0;
        foreach (var suggestion in suggestions)
        {
            suggestion.IsKeyboardSelected = index == selection.SelectedIndex;
            index += 1;
        }
    }

    private static bool TryMentionSelectionKey(
        Windows.System.VirtualKey key,
        out MentionSelectionKey selectionKey)
    {
        selectionKey = key switch
        {
            Windows.System.VirtualKey.Up => MentionSelectionKey.ArrowUp,
            Windows.System.VirtualKey.Down => MentionSelectionKey.ArrowDown,
            Windows.System.VirtualKey.Enter => MentionSelectionKey.Enter,
            Windows.System.VirtualKey.Escape => MentionSelectionKey.Escape,
            _ => default
        };
        return key is Windows.System.VirtualKey.Up or
            Windows.System.VirtualKey.Down or
            Windows.System.VirtualKey.Enter or
            Windows.System.VirtualKey.Escape;
    }

    private async Task SendReaderMessageAsync(
        ReaderThreadItem item,
        CanvasNode node,
        FrameworkElement? feedbackAnchor = null)
    {
        var text = item.DraftText.Trim();
        var attachments = item.PendingAttachments.ToList();
        var availability = ThreadSendAvailability(node, text, attachments.Count);
        if (availability.UnavailableReason is { } unavailableReason)
        {
            ShowCommandFeedback(unavailableReason, feedbackAnchor);
            return;
        }

        node.Metadata.LocalTranscript.Add(new LocalThreadMessage
        {
            Role = "user",
            Text = string.IsNullOrWhiteSpace(text)
                ? $"Attached {attachments.Count} file{(attachments.Count == 1 ? "" : "s")}."
                : text,
            CreatedAt = DateTimeOffset.UtcNow
        });

        foreach (var attachment in attachments)
        {
            node.Metadata.LocalTranscript.Add(new LocalThreadMessage
            {
                Role = attachment.TranscriptRole,
                Text = attachment.TranscriptText,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        node.Metadata.LocalTranscript.Add(new LocalThreadMessage
        {
            Role = "system",
            Text = attachments.Count == 0
                ? "Windows preview recorded this message locally. Connect a Codex App Server route to send live turns."
                : "Windows preview recorded this message and its attachments locally. Connect a Codex App Server route to send live turns.",
            CreatedAt = DateTimeOffset.UtcNow
        });
        node.Metadata.IsUnread = false;
        item.DraftText = "";
        item.AttachmentErrorText = "";
        ClearReaderMentionSuggestions(item);
        item.PendingAttachments.Clear();
        await SaveGraphAsync();
        AddActivity($"Added local message to {node.Title}.");
        UpdateChrome();
        await RenderGraphAsync();
    }

    private static bool TryReaderThreadItem(object sender, out ReaderThreadItem item)
    {
        if (sender is FrameworkElement element)
        {
            if (element.Tag is ReaderThreadItem taggedItem)
            {
                item = taggedItem;
                return true;
            }

            if (element.DataContext is ReaderThreadItem contextItem)
            {
                item = contextItem;
                return true;
            }
        }

        item = null!;
        return false;
    }

    private void SaveThreadPopoverTitleButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            if (!_isThreadPopoverRenaming)
            {
                _isThreadPopoverRenaming = true;
                ThreadPopoverTitleBox.Text = node.Title;
                UpdateThreadPopoverTitleChrome();
                ThreadPopoverTitleBox.Focus(FocusState.Programmatic);
                ThreadPopoverTitleBox.SelectAll();
                return;
            }

            await CommitThreadPopoverTitleAsync(node);

        });
    }

    private void ThreadPopoverTitleBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter)
            {
                return;
            }

            e.Handled = true;
            if (TryGetSelectedThread(out var node))
            {
                await CommitThreadPopoverTitleAsync(node);
            }

        });
    }

    private void ThreadPopoverDraftBox_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            AttachComposerDraftBoxKeyHandler(textBox);
            ApplyMentionComposerLayout(
                textBox,
                MentionComposerLayout.ThreadReplyMinLines,
                MentionComposerLayout.ThreadReplyMaxLines);
        }
    }

    private void AttachComposerDraftBoxKeyHandler(TextBox textBox)
    {
        if (_composerDraftBoxesWithKeyHandler.Add(textBox))
        {
            textBox.AddHandler(
                UIElement.KeyDownEvent,
                new KeyEventHandler(ComposerDraftBox_KeyDown),
                handledEventsToo: true);
        }
    }

    private static void ApplyMentionComposerLayout(
        TextBox textBox,
        int minLines = MentionComposerLayout.DefaultMinLines,
        int maxLines = MentionComposerLayout.DefaultMaxLines)
    {
        var layout = MentionComposerLayout.Measure(textBox.Text, minLines, maxLines);
        textBox.MinHeight = layout.MinHeight;
        textBox.MaxHeight = layout.MaxHeight;
        textBox.Height = layout.Height;
    }

    private static bool IsShiftKeyDown()
    {
        return IsKeyDown(Windows.System.VirtualKey.LeftShift) ||
            IsKeyDown(Windows.System.VirtualKey.RightShift);
    }

    private static bool IsKeyDown(Windows.System.VirtualKey key)
    {
        var state = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(key);
        return (state & Windows.UI.Core.CoreVirtualKeyStates.Down) == Windows.UI.Core.CoreVirtualKeyStates.Down;
    }

    private async Task CommitThreadPopoverTitleAsync(CanvasNode node)
    {
        var title = ThreadPopoverTitleBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            AddActivity("Thread name is required.");
            return;
        }

        node.Title = title;
        if (node.Metadata.ThreadRef is not null)
        {
            node.Metadata.ThreadRef.Name = title;
        }

        await SaveGraphAsync();
        _isThreadPopoverRenaming = false;
        AddActivity($"Renamed {node.Title}.");
        UpdateThreadPopover(node);
        UpdateChrome();
        await RenderGraphAsync();
    }

	    private void CopyThreadPopoverThreadIdButton_Click(object sender, RoutedEventArgs e)
	    {
        if (!TryGetSelectedThread(out var node))
        {
            return;
        }

        var threadID = node.Metadata.ThreadRef?.ThreadID ?? node.Id;
        CopyTextToClipboard(threadID);
        AddActivity($"Copied thread ID for {node.Title}.");
    }

    private void OpenThreadPopoverArtifactsButton_Click(object sender, RoutedEventArgs e)
    {
        if (TryGetSelectedThread(out var node))
        {
            if (ThreadArtifacts(node).Count == 0)
            {
                ShowCommandFeedback(
                    ArtifactsActionPresentation.UnavailableReason,
                    sender as FrameworkElement);
                return;
            }

            ShowArtifactsForThread(node);
        }
    }

    private void OpenThreadPopoverAutomationButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetSelectedThread(out var node))
            {
                await ShowThreadAutomationDialogAsync(node, sender as FrameworkElement);
            }

        });
    }

    private void AttachThreadPopoverFilesButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!ThreadPopoverComposerIsEnabled())
            {
                return;
            }

            var picker = new FileOpenPicker
            {
                ViewMode = PickerViewMode.List,
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary
            };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

            var files = await picker.PickMultipleFilesAsync();
            AddThreadPopoverAttachments(files);

        });
    }

    private void PasteThreadPopoverAttachmentsButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!ThreadPopoverComposerIsEnabled())
            {
                return;
            }

            var data = Clipboard.GetContent();
            var didAttach = false;

            if (data.Contains(StandardDataFormats.StorageItems))
            {
                var items = await data.GetStorageItemsAsync();
                var files = items.OfType<StorageFile>().ToList();
                AddThreadPopoverAttachments(files);
                didAttach = files.Count > 0;
            }

            if (!didAttach && data.Contains(StandardDataFormats.Bitmap))
            {
                _threadPopoverPendingAttachments.Add(ComposerAttachmentItem.FromClipboardImage());
                didAttach = true;
            }

            if (!didAttach && data.Contains(StandardDataFormats.Text))
            {
                var text = (await data.GetTextAsync())
                    .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(line => line.Trim().Trim('"'))
                    .Where(System.IO.File.Exists)
                    .ToList();

                foreach (var path in text)
                {
                    _threadPopoverPendingAttachments.Add(ComposerAttachmentItem.FromPath(path));
                }

                didAttach = text.Count > 0;
            }

            if (didAttach)
            {
                SetThreadPopoverAttachmentError(null);
                AddActivity($"Attached {_threadPopoverPendingAttachments.Count} pending item{(_threadPopoverPendingAttachments.Count == 1 ? "" : "s")}.");
            }
            else
            {
                SetThreadPopoverAttachmentError(ThreadAttachmentFeedbackPresentation.ClipboardUnavailableReason);
            }

        });
    }

    private static void CopyTextToClipboard(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
    }

    private void RemoveThreadPopoverAttachmentButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: ComposerAttachmentItem attachment })
        {
            _threadPopoverPendingAttachments.Remove(attachment);
        }
    }

    private bool ThreadPopoverComposerIsEnabled()
    {
        if (!TryGetSelectedThread(out var node))
        {
            return false;
        }

        if (node.Metadata.RunStatus != ThreadRunStatuses.Running)
        {
            return true;
        }

        AddActivity($"{node.Title} is running. Stop the turn before changing the composer.");
        return false;
    }

    private void UpdateThreadPopoverSendChrome(CanvasNode? node = null)
    {
        if (ThreadPopoverSendButton is null)
        {
            return;
        }

        if (node is null && !TryGetSelectedThread(out node))
        {
            ThreadPopoverSendButton.Opacity = ThreadSendActionPresentation.UnavailableOpacity;
            ToolTipService.SetToolTip(ThreadPopoverSendButton, ThreadSendActionPresentation.MissingContentReason);
            AutomationProperties.SetHelpText(
                ThreadPopoverSendButton,
                ThreadSendActionPresentation.MissingContentReason);
            return;
        }

        var availability = ThreadSendAvailability(
            node,
            ThreadPopoverDraftBox?.Text ?? "",
            _threadPopoverPendingAttachments.Count);
        ThreadPopoverSendButton.IsEnabled = true;
        ThreadPopoverSendButton.Opacity = availability.Opacity;
        ToolTipService.SetToolTip(
            ThreadPopoverSendButton,
            availability.UnavailableReason ?? ThreadSendActionPresentation.ToolTip);
        AutomationProperties.SetHelpText(
            ThreadPopoverSendButton,
            availability.UnavailableReason ?? "");
    }

    private static ThreadSendActionAvailability ThreadSendAvailability(
        CanvasNode node,
        string draft,
        int pendingAttachmentCount)
    {
        return ThreadSendActionPresentation.Availability(
            isAwaitingResponse: node.Metadata.RunStatus == ThreadRunStatuses.Running,
            isSubmitting: false,
            draft: draft,
            pendingAttachmentCount: pendingAttachmentCount);
    }

    private void SetThreadPopoverAttachmentError(string? message)
    {
        _threadPopoverAttachmentError = string.IsNullOrWhiteSpace(message) ? null : message.Trim();
        RefreshThreadPopoverAttachmentError();
    }

    private void UpdateThreadPopoverAttachmentChrome()
    {
        UpdateThreadPopoverSendChrome();
        RefreshThreadPopoverAttachmentCount();
    }

    private void RefreshThreadPopoverAttachmentCount()
    {
        if (ThreadPopoverAttachmentCountText is null)
        {
            return;
        }

        var text = ThreadAttachmentFeedbackPresentation.CountText(_threadPopoverPendingAttachments.Count);
        ThreadPopoverAttachmentCountText.Text = text;
        ThreadPopoverAttachmentCountText.Visibility = string.IsNullOrWhiteSpace(text)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void RefreshThreadPopoverAttachmentError()
    {
        if (ThreadPopoverAttachmentErrorText is null)
        {
            return;
        }

        ThreadPopoverAttachmentErrorText.Text = _threadPopoverAttachmentError ?? "";
        ThreadPopoverAttachmentErrorText.Visibility = string.IsNullOrWhiteSpace(_threadPopoverAttachmentError)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void AddThreadPopoverAttachments(IEnumerable<StorageFile> files)
    {
        var added = 0;
        foreach (var file in files)
        {
            _threadPopoverPendingAttachments.Add(ComposerAttachmentItem.FromStorageFile(file));
            added += 1;
        }

        if (added > 0)
        {
            SetThreadPopoverAttachmentError(null);
            AddActivity($"Attached {added} file{(added == 1 ? "" : "s")}.");
        }
    }

    private async Task<bool> AddClipboardAttachmentsAsync(Action<ComposerAttachmentItem> addAttachment)
    {
        var data = Clipboard.GetContent();
        var didAttach = false;

        if (data.Contains(StandardDataFormats.StorageItems))
        {
            var items = await data.GetStorageItemsAsync();
            var files = items.OfType<StorageFile>().ToList();
            foreach (var file in files)
            {
                addAttachment(ComposerAttachmentItem.FromStorageFile(file));
            }

            didAttach = files.Count > 0;
        }

        if (!didAttach && data.Contains(StandardDataFormats.Bitmap))
        {
            addAttachment(ComposerAttachmentItem.FromClipboardImage());
            didAttach = true;
        }

        if (!didAttach && data.Contains(StandardDataFormats.Text))
        {
            var paths = (await data.GetTextAsync())
                .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.RemoveEmptyEntries)
                .Select(line => line.Trim().Trim('"'))
                .Where(System.IO.File.Exists)
                .ToList();

            foreach (var path in paths)
            {
                addAttachment(ComposerAttachmentItem.FromPath(path));
            }

            didAttach = paths.Count > 0;
        }

        return didAttach;
    }

    private void CloseArtifactsPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        ArtifactsPopover.Visibility = Visibility.Collapsed;
        CloseArtifactPreview();
        _artifactCatalog.ClearSource();
    }

    private void OpenArtifactPreviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ThreadArtifactItem item })
        {
            return;
        }

        ShowArtifactPreview(item);
    }

    private void CloseArtifactPreviewButton_Click(object sender, RoutedEventArgs e)
    {
        CloseArtifactPreview();
    }

    private void CopyArtifactPreviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (_artifactCatalog.Selected is not { } selectedArtifact)
        {
            return;
        }

        var copyText = selectedArtifact.KindKey == ThreadArtifactItem.KindImage &&
            !string.IsNullOrWhiteSpace(selectedArtifact.DisplayPath)
            ? selectedArtifact.DisplayPath!
            : selectedArtifact.PreviewText;
        CopyTextToClipboard(copyText);
        AddActivity(selectedArtifact.KindKey == ThreadArtifactItem.KindImage
            ? $"Copied image path for {selectedArtifact.Title}."
            : $"Copied preview for {selectedArtifact.Title}.");
    }

    private void ArtifactFilterAllButton_Click(object sender, RoutedEventArgs e)
    {
        SetArtifactFilter(ArtifactCatalogFilter.All);
    }

    private void ArtifactFilterImagesButton_Click(object sender, RoutedEventArgs e)
    {
        SetArtifactFilter(ArtifactCatalogFilter.Images);
    }

    private void ArtifactFilterFilesButton_Click(object sender, RoutedEventArgs e)
    {
        SetArtifactFilter(ArtifactCatalogFilter.Files);
    }

    private void ArtifactFilterDiffsButton_Click(object sender, RoutedEventArgs e)
    {
        SetArtifactFilter(ArtifactCatalogFilter.Diffs);
    }

    private void RefreshThreadPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetSelectedThread(out var node))
            {
                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: false, userInitiated: true);
            }

        });
    }

    private void LoadOlderThreadPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetSelectedThread(out var node))
            {
                if (_transcriptSessions.Snapshot(node.Id).IsLoadingOlder)
                {
                    ShowCommandFeedback(LoadOlderMessagesActionPresentation.UnavailableReason, sender as FrameworkElement);
                    return;
                }

                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: true, userInitiated: true);
            }

        });
    }

    private void RetryThreadPopoverTranscriptButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetSelectedThread(out var node))
            {
                await LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: false, userInitiated: true);
            }

        });
    }

    private void UseCachedThreadPopoverTranscriptButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedThread(out var node))
        {
            return;
        }

        _transcriptSessions.ClearError(node.Id);
        UpdateThreadPopover(node);
        AddActivity($"Using cached transcript for {node.Title}.");
    }

    private Task LoadThreadTranscriptForNodeAsync(string nodeId, bool appendOlder, bool userInitiated)
    {
        return _windowLifetime.TryRunTracked(
            lease => LoadThreadTranscriptForNodeCoreAsync(nodeId, appendOlder, userInitiated, lease),
            out var task)
            ? task
            : Task.CompletedTask;
    }

    private async Task LoadThreadTranscriptForNodeCoreAsync(
        string nodeId,
        bool appendOlder,
        bool userInitiated,
        WindowLifetimeLease lease)
    {
        if (!_graph.Nodes.TryGetValue(nodeId, out var node) ||
            node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        if (!TryGetThreadRefForTranscript(node, out var threadRef))
        {
            SetThreadTranscriptError(node, "This workflow node does not have a Codex thread reference.", userInitiated);
            return;
        }

        if (!TryGetAppServerEndpointForThread(node, out var endpoint))
        {
            SetThreadTranscriptError(node, "Reconnect this thread's machine before loading its transcript.", userInitiated);
            return;
        }

        if (appendOlder && !_transcriptSessions.Snapshot(node.Id).HasOlderPage)
        {
            AddActivity($"No older transcript page is available for {node.Title}.");
            return;
        }

        if (!_transcriptSessions.TryBeginLoad(
                node.Id,
                appendOlder,
                HasLoadedThreadTranscript(node),
                TimeSpan.FromSeconds(20),
                out var transcriptLoad))
        {
            return;
        }

        using var load = transcriptLoad!;
        RefreshTranscriptSurfaces(node.Id);

        try
        {
            if (!appendOlder)
            {
                load.SetPhase(TranscriptLoadPhase.LoadingHistory);
                RefreshTranscriptSurfaces(node.Id);
            }

            using var requestCancellation = CancellationTokenSource.CreateLinkedTokenSource(
                load.CancellationToken,
                lease.CancellationToken);
            var transcript = await new AppServerClient().LoadThreadTranscriptAsync(
                endpoint,
                threadRef,
                load.StartingCursor,
                cancellationToken: requestCancellation.Token);

            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            if (!_graph.Nodes.TryGetValue(nodeId, out var currentNode))
            {
                return;
            }

            if (!appendOlder)
            {
                load.SetPhase(TranscriptLoadPhase.HydratingArtifacts);
                RefreshTranscriptSurfaces(currentNode.Id);
            }

            currentNode.Metadata.LocalTranscript = MergeLoadedTranscriptMessages(
                transcript.Messages,
                currentNode.Metadata.LocalTranscript);
            currentNode.Metadata.LocalTranscriptTurns = MergeLoadedTranscriptTurns(
                transcript.Turns,
                currentNode.Metadata.LocalTranscriptTurns,
                currentNode.Metadata.LocalTranscript);
            load.Complete(transcript.NextCursor);
            await SaveGraphAsync();
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            AddActivity(appendOlder
                ? $"Loaded older messages for {currentNode.Title}."
                : $"Loaded transcript for {currentNode.Title}.");
        }
        catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
        {
            // Window shutdown owns this cancellation; do not publish an error.
        }
        catch (Exception exception)
        {
            load.Fail(exception.Message);
            if (_graph.Nodes.TryGetValue(nodeId, out var currentNode))
            {
                AddActivity(
                    $"Transcript unavailable for {currentNode.Title}: {exception.Message}",
                    showTopNotification: userInitiated,
                    notificationKind: ActivityNotificationKindFailed);
            }
        }
        finally
        {
            if (_windowLifetime.IsCurrent(lease))
            {
                RefreshTranscriptSurfaces(nodeId);
                UpdateChrome();
                await RenderGraphAsync();
            }
        }
    }

    private void SetThreadTranscriptError(CanvasNode node, string message, bool showNotification)
    {
        _transcriptSessions.SetError(node.Id, message);
        RefreshTranscriptSurfaces(node.Id);
        AddActivity(
            $"Transcript unavailable for {node.Title}: {message}",
            showTopNotification: showNotification,
            notificationKind: ActivityNotificationKindFailed);
    }

    private void QueueInitialThreadTranscriptLoad(CanvasNode node)
    {
        if (!TryGetThreadRefForTranscript(node, out _) ||
            !TryGetAppServerEndpointForThread(node, out _) ||
            !_transcriptSessions.TryReserveAutoLoad(node.Id))
        {
            return;
        }

        _ = LoadThreadTranscriptForNodeAsync(node.Id, appendOlder: false, userInitiated: false);
    }

    private bool TryGetThreadRefForTranscript(CanvasNode node, out ThreadRef threadRef)
    {
        if (node.Metadata.ThreadRef is { } existing &&
            !string.IsNullOrWhiteSpace(existing.ThreadID))
        {
            threadRef = existing;
            return true;
        }

        threadRef = new ThreadRef();
        return false;
    }

    private bool TryGetAppServerEndpointForThread(CanvasNode node, out AppServerEndpoint endpoint)
    {
        var hostID = node.Metadata.ThreadRef?.HostID ?? node.Metadata.HostID;
        return TryGetAppServerEndpointForHost(hostID, out endpoint);
    }

    private bool TryGetAppServerEndpointForHost(string? hostID, out AppServerEndpoint endpoint)
    {
        if (!string.IsNullOrWhiteSpace(hostID) &&
            _connectedAppServerEndpointsByHostId.TryGetValue(hostID, out var connectedEndpoint))
        {
            endpoint = connectedEndpoint;
            return true;
        }

        var machine = string.IsNullOrWhiteSpace(hostID)
            ? null
            : MachineNodes.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, hostID, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(candidate.Metadata.HostID, hostID, StringComparison.OrdinalIgnoreCase));
        if (machine is not null &&
            machine.Metadata.HostStatus == HostStatuses.Connected &&
            !string.IsNullOrWhiteSpace(machine.Metadata.AppServerEndpointUrl) &&
            Uri.TryCreate(machine.Metadata.AppServerEndpointUrl, UriKind.Absolute, out var url) &&
            AppServerEndpointValidator.IsLoopback(url))
        {
            endpoint = new AppServerEndpoint(machine.Title, url, null);
            if (IsLocalHostId(machine.Metadata.HostID))
            {
                RegisterLocalAppServerEndpoint(endpoint);
            }
            else
            {
                _connectedAppServerEndpointsByHostId[machine.Id] = endpoint;
            }

            return true;
        }

        endpoint = new AppServerEndpoint("", new Uri("ws://127.0.0.1"), null);
        return false;
    }

    private static List<LocalThreadMessage> MergeLoadedTranscriptMessages(
        IReadOnlyList<LocalThreadMessage> loadedMessages,
        IReadOnlyList<LocalThreadMessage> existingMessages)
    {
        var merged = new List<LocalThreadMessage>();
        var usedIds = new HashSet<string>(StringComparer.Ordinal);
        var loadedContentKeys = new HashSet<string>(StringComparer.Ordinal);

        void AddLoaded(LocalThreadMessage message)
        {
            if (!string.IsNullOrWhiteSpace(message.Id) && !usedIds.Add(message.Id))
            {
                return;
            }

            loadedContentKeys.Add(TranscriptContentKey(message));
            merged.Add(CloneThreadMessage(message));
        }

        void AddExistingIfDistinct(LocalThreadMessage message)
        {
            if (!string.IsNullOrWhiteSpace(message.Id) && !usedIds.Add(message.Id))
            {
                return;
            }

            if (loadedContentKeys.Contains(TranscriptContentKey(message)))
            {
                return;
            }

            merged.Add(CloneThreadMessage(message));
        }

        foreach (var message in loadedMessages)
        {
            AddLoaded(message);
        }

        foreach (var message in existingMessages)
        {
            AddExistingIfDistinct(message);
        }

        return merged
            .OrderBy(message => message.CreatedAt)
            .ToList();
    }

    private static LocalThreadMessage CloneThreadMessage(LocalThreadMessage message)
    {
        return new LocalThreadMessage
        {
            Id = message.Id,
            Role = message.Role,
            Text = message.Text,
            CreatedAt = message.CreatedAt
        };
    }

    private static string TranscriptContentKey(LocalThreadMessage message)
    {
        return $"{message.Role.Trim().ToLowerInvariant()}|{message.Text.Trim()}";
    }

    private static List<LocalThreadTurn> MergeLoadedTranscriptTurns(
        IReadOnlyList<LocalThreadTurn> loadedTurns,
        IReadOnlyList<LocalThreadTurn> existingTurns,
        IReadOnlyList<LocalThreadMessage> mergedMessages)
    {
        var merged = new List<LocalThreadTurn>();
        var usedIds = new HashSet<string>(StringComparer.Ordinal);
        var messageIds = mergedMessages
            .Select(message => message.Id)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .ToHashSet(StringComparer.Ordinal);

        void AddTurn(LocalThreadTurn turn)
        {
            if (string.IsNullOrWhiteSpace(turn.Id) || !usedIds.Add(turn.Id))
            {
                return;
            }

            var clone = CloneThreadTurn(turn);
            clone.ItemMessageIds = clone.ItemMessageIds
                .Where(id => messageIds.Contains(id))
                .Distinct(StringComparer.Ordinal)
                .ToList();
            merged.Add(clone);
        }

        foreach (var turn in loadedTurns)
        {
            AddTurn(turn);
        }

        foreach (var turn in existingTurns)
        {
            AddTurn(turn);
        }

        return merged
            .OrderBy(turn => turn.StartedAt)
            .ToList();
    }

    private static LocalThreadTurn CloneThreadTurn(LocalThreadTurn turn)
    {
        return new LocalThreadTurn
        {
            Id = turn.Id,
            Status = turn.Status,
            StartedAt = turn.StartedAt,
            CompletedAt = turn.CompletedAt,
            Error = turn.Error,
            ItemsView = turn.ItemsView,
            DurationMilliseconds = turn.DurationMilliseconds,
            ItemMessageIds = turn.ItemMessageIds.ToList()
        };
    }

    private void CloseThreadPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            _selectedNodeId = null;
            _selectedEdgeId = null;
            _pendingLinkSourceNodeId = null;
            ResetThreadPopoverData();
            await SendGraphCommandAsync("clearSelection");
            UpdateChrome();

        });
    }

    private void StopThreadPopoverButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            await StopThreadAsync(node, "thread popover", sender as FrameworkElement);

        });
    }

    private void SendThreadPopoverMessageButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SendThreadPopoverMessageAsync(sender as FrameworkElement);

        });
    }

    private void ThreadPopoverDraftBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is TextBox textBox && TryHandleMentionSelectionKey(textBox, e))
            {
                return;
            }

            if (e.Key != Windows.System.VirtualKey.Enter || IsShiftKeyDown())
            {
                return;
            }

            e.Handled = true;
            await SendThreadPopoverMessageAsync(ThreadPopoverSendButton);

        });
    }

    private async Task SendThreadPopoverMessageAsync(FrameworkElement? feedbackAnchor = null)
    {
        if (!TryGetSelectedThread(out var node))
        {
            return;
        }

        var text = ThreadPopoverDraftBox.Text.Trim();
        var attachments = _threadPopoverPendingAttachments.ToList();
        var availability = ThreadSendAvailability(node, text, attachments.Count);
        if (availability.UnavailableReason is { } unavailableReason)
        {
            ShowCommandFeedback(unavailableReason, feedbackAnchor);
            return;
        }

        node.Metadata.LocalTranscript.Add(new LocalThreadMessage
        {
            Role = "user",
            Text = string.IsNullOrWhiteSpace(text)
                ? $"Attached {attachments.Count} file{(attachments.Count == 1 ? "" : "s")}."
                : text,
            CreatedAt = DateTimeOffset.UtcNow
        });

        foreach (var attachment in attachments)
        {
            node.Metadata.LocalTranscript.Add(new LocalThreadMessage
            {
                Role = attachment.TranscriptRole,
                Text = attachment.TranscriptText,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        node.Metadata.LocalTranscript.Add(new LocalThreadMessage
        {
            Role = "system",
            Text = attachments.Count == 0
                ? "Windows preview recorded this message locally. Connect a Codex App Server route to send live turns."
                : "Windows preview recorded this message and its attachments locally. Connect a Codex App Server route to send live turns.",
            CreatedAt = DateTimeOffset.UtcNow
        });
        node.Metadata.IsUnread = false;
        ThreadPopoverDraftBox.Text = "";
        SetThreadPopoverAttachmentError(null);
        ClearThreadPopoverMentionSuggestions();
        _threadPopoverPendingAttachments.Clear();
        await SaveGraphAsync();
        AddActivity($"Added local message to {node.Title}.");
        UpdateThreadPopover(node);
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void ThreadPopoverDragHandle_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (_isDraggingThreadPopover)
        {
            e.Handled = true;
            return;
        }

        if (!IsThreadPopoverDragStart(sender, e))
        {
            return;
        }

        if (!TryGetSelectedThread(out var node) || sender is not UIElement element)
        {
            return;
        }

        _isDraggingThreadPopover = true;
        _draggingThreadPopoverNodeId = node.Id;
        _threadPopoverDragStart = e.GetCurrentPoint(RootGrid).Position;
        _threadPopoverDragStartMargin = ThreadPopover.Margin;
        ThreadPopover.Opacity = 0.98;
        element.CapturePointer(e.Pointer);
        e.Handled = true;
    }

    private bool IsThreadPopoverDragStart(object sender, PointerRoutedEventArgs e)
    {
        if (ReferenceEquals(sender, ThreadPopoverDragHandle))
        {
            return true;
        }

        var point = e.GetCurrentPoint(ThreadPopover).Position;
        return point.X >= ThreadPopoverWidth() - 140 &&
            point.X <= ThreadPopoverWidth() - 92 &&
            point.Y >= 0 &&
            point.Y <= 58;
    }

    private void ThreadPopoverDragHandle_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isDraggingThreadPopover)
        {
            return;
        }

        var current = e.GetCurrentPoint(RootGrid).Position;
        var frame = ThreadPopoverLayout.ClampFrame(
            RootWidth(),
            RootHeight(),
            ThreadPopoverWidth(),
            ThreadPopoverHeight(),
            _threadPopoverDragStartMargin.Left + current.X - _threadPopoverDragStart.X,
            _threadPopoverDragStartMargin.Top + current.Y - _threadPopoverDragStart.Y);
        ThreadPopover.Margin = new Thickness(frame.Left, frame.Top, 0, 0);
        e.Handled = true;
    }

    private void ThreadPopoverDragHandle_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!_isDraggingThreadPopover)
            {
                return;
            }

            var draggedNodeId = _draggingThreadPopoverNodeId;
            _isDraggingThreadPopover = false;
            _draggingThreadPopoverNodeId = null;
            ThreadPopover.Opacity = 1;

            if (sender is UIElement element)
            {
                element.ReleasePointerCapture(e.Pointer);
            }

            e.Handled = true;

            if (draggedNodeId is null ||
                !_graph.Nodes.TryGetValue(draggedNodeId, out var node) ||
                node.Kind != NodeKinds.CodexThread)
            {
                return;
            }

            var baseFrame = ThreadPopoverBaseFrame(node);
            node.Metadata.PopoverOffset = new CanvasPoint(
                ThreadPopover.Margin.Left - baseFrame.Left,
                ThreadPopover.Margin.Top - baseFrame.Top);
            await SaveGraphAsync();

        });
    }

    private void ThreadPopoverDragHandle_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        CancelThreadPopoverDrag(sender as UIElement, e);
    }

    private void ThreadPopoverDragHandle_PointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        CancelThreadPopoverDrag(sender as UIElement, e);
    }

    private void CancelThreadPopoverDrag(UIElement? element, PointerRoutedEventArgs e)
    {
        if (!_isDraggingThreadPopover)
        {
            return;
        }

        element?.ReleasePointerCapture(e.Pointer);
        _isDraggingThreadPopover = false;
        _draggingThreadPopoverNodeId = null;
        ThreadPopover.Margin = _threadPopoverDragStartMargin;
        ThreadPopover.Opacity = 1;
        e.Handled = true;
    }

    private void ReaderItemsPanel_Loaded(object sender, RoutedEventArgs e)
    {
        _readerItemsPanel = sender as ItemsWrapGrid;
        UpdateReaderLayout();
    }

    private void ReaderThreadList_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!_isViewInitialized || !_isReadingModePresented)
        {
            return;
        }

        UpdateReaderLayout();
    }

    private void CloseReaderButton_Click(object sender, RoutedEventArgs e)
    {
        _isReadingModePresented = false;
        AddActivity("Reading mode closed.");
        UpdateChrome();
    }

    private void RemoveLastReaderThreadButton_Click(object sender, RoutedEventArgs e)
    {
        if (_readerThreadIds.Count == 0)
        {
            return;
        }

        var lastID = _readerThreadIds[^1];
        _readerThreadIds.RemoveAt(_readerThreadIds.Count - 1);
        _readerTranscriptFilters.Remove(lastID);
        _readerPendingAttachments.Remove(lastID);
        _readerMentionSelections.Remove(lastID);
        var title = _graph.Nodes.TryGetValue(lastID, out var node) ? node.Title : "chat";
        AddActivity($"Removed {title} from reader.");
        UpdateChrome();
    }

    private void ClearReaderThreadsButton_Click(object sender, RoutedEventArgs e)
    {
        if (_readerThreadIds.Count == 0)
        {
            return;
        }

        foreach (var id in _readerThreadIds)
        {
            _readerTranscriptFilters.Remove(id);
            _readerPendingAttachments.Remove(id);
            _readerMentionSelections.Remove(id);
        }

        _readerThreadIds.Clear();
        AddActivity("Cleared reader chats.");
        UpdateChrome();
    }

    private void ToggleReaderTranscriptCategoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderTranscriptFilterItem filter } ||
            string.IsNullOrWhiteSpace(filter.ThreadId))
        {
            return;
        }

        ToggleReaderTranscriptCategory(filter.ThreadId, filter.CategoryKey);
    }

    private void ReaderTranscriptFilterButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: ReaderThreadItem item })
        {
            _activeReaderFilterThreadId = item.Id;
        }
    }

    private void ReaderTranscriptFilterMenu_Opening(object sender, object e)
    {
        if (sender is MenuFlyout { Target: FrameworkElement { DataContext: ReaderThreadItem item } })
        {
            _activeReaderFilterThreadId = item.Id;
        }
    }

    private void ToggleReaderTranscriptCategoryMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleMenuFlyoutItem { Tag: string categoryKey })
        {
            return;
        }

        var threadId = ReaderTranscriptMenuThreadId(sender);
        if (string.IsNullOrWhiteSpace(threadId))
        {
            return;
        }

        ToggleReaderTranscriptCategory(threadId, categoryKey);
    }

    private void ShowAllReaderTranscriptRowsMenuItem_Click(object sender, RoutedEventArgs e)
    {
        var threadId = ReaderTranscriptMenuThreadId(sender);
        if (string.IsNullOrWhiteSpace(threadId))
        {
            return;
        }

        _readerTranscriptFilters[threadId] = AllReaderTranscriptCategories();
        UpdateReader();
    }

    private string? ReaderTranscriptMenuThreadId(object sender)
    {
        if (sender is FrameworkElement { DataContext: ReaderThreadItem item })
        {
            return item.Id;
        }

        return _activeReaderFilterThreadId;
    }

    private void ToggleReaderTranscriptCategory(string threadId, string categoryKey)
    {
        if (!TryReaderTranscriptCategory(categoryKey, out var category))
        {
            return;
        }

        var activeCategories = ActiveReaderTranscriptCategories(threadId).ToHashSet();
        if (activeCategories.Contains(category))
        {
            if (activeCategories.Count == 1)
            {
                UpdateReader();
                return;
            }

            activeCategories.Remove(category);
        }
        else
        {
            activeCategories.Add(category);
        }

        _readerTranscriptFilters[threadId] = activeCategories;
        UpdateReader();
    }

    private void ResetReaderTranscriptFiltersButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderThreadItem item })
        {
            return;
        }

        _readerTranscriptFilters[item.Id] = AllReaderTranscriptCategories();
        UpdateReader();
    }

    private void ToggleThreadPopoverTranscriptCategoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderTranscriptFilterItem filter })
        {
            return;
        }

        ToggleThreadPopoverTranscriptCategory(filter.CategoryKey);
    }

    private void ToggleThreadPopoverTranscriptCategoryMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not ToggleMenuFlyoutItem { Tag: string categoryKey })
        {
            return;
        }

        ToggleThreadPopoverTranscriptCategory(categoryKey);
    }

    private void ShowAllThreadPopoverTranscriptRowsMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedThread(out var node))
        {
            return;
        }

        ResetThreadPopoverTranscriptFilters();
        UpdateThreadPopover(node);
    }

    private void ToggleThreadPopoverTranscriptCategory(string categoryKey)
    {
        if (!TryReaderTranscriptCategory(categoryKey, out var category))
        {
            return;
        }

        var activeCategories = ActiveThreadPopoverTranscriptCategories().ToHashSet();
        if (activeCategories.Contains(category))
        {
            if (activeCategories.Count == 1)
            {
                if (TryGetSelectedThread(out var selectedNode))
                {
                    UpdateThreadPopover(selectedNode);
                }

                return;
            }

            activeCategories.Remove(category);
        }
        else
        {
            activeCategories.Add(category);
        }

        _threadPopoverTranscriptFilters.Clear();
        foreach (var activeCategory in activeCategories)
        {
            _threadPopoverTranscriptFilters.Add(activeCategory);
        }

        if (TryGetSelectedThread(out var node))
        {
            UpdateThreadPopover(node);
        }
    }

    private void ResetThreadPopoverTranscriptFiltersButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryGetSelectedThread(out var node))
        {
            return;
        }

        ResetThreadPopoverTranscriptFilters();
        UpdateThreadPopover(node);
    }

    private void CopyTranscriptRowButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderTranscriptRow row } ||
            !row.CanCopyText ||
            string.IsNullOrWhiteSpace(row.FullText))
        {
            return;
        }

        CopyTextToClipboard(row.FullText);
        AddActivity($"Copied {row.RoleTitle.ToLowerInvariant()} message.");
    }

    private void ToggleTranscriptRowExpansionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ReaderTranscriptRow row } ||
            !row.IsExpandable)
        {
            return;
        }

        var key = TranscriptRowExpansionKey(row.ThreadId, row.Id);
        if (_expandedTranscriptRows.Contains(key))
        {
            _expandedTranscriptRows.Remove(key);
            AddActivity("Collapsed transcript row.");
        }
        else
        {
            _expandedTranscriptRows.Add(key);
            AddActivity("Expanded transcript row.");
        }

        RefreshTranscriptSurfaces(row.ThreadId);
    }

    private void RefreshInboxButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await RefreshAppServerThreadCatalogAsync(search: _threadInboxMode == ThreadInboxModeSearch);
            AddActivity("Thread inbox refreshed.");
            UpdateChrome();

        });
    }

    private void ThreadInboxActiveModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeActive);
    }

    private void ThreadInboxFinishedModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeFinished);
    }

    private void ThreadInboxNeedsModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeNeedsYou);
    }

    private void ThreadInboxUnreadModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeUnread);
    }

    private void ThreadInboxRecentModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeRecent);
    }

    private void ThreadInboxSearchModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeSearch);
    }

    private void ThreadInboxArchiveModeButton_Click(object sender, RoutedEventArgs e)
    {
        SetThreadInboxMode(ThreadInboxModeArchived);
    }

    private void ThreadInboxWorkflowFilterBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdatingThreadInboxWorkflowFilters)
        {
            return;
        }

        if (ThreadInboxWorkflowFilterBox?.SelectedItem is ThreadInboxWorkflowFilterItem item)
        {
            _threadInboxWorkflowFilter = item.Id;
            if (_isViewInitialized)
            {
                UpdateChrome();
            }
        }
    }

    private void ThreadInboxCollapseButton_Click(object sender, RoutedEventArgs e)
    {
        _isThreadInboxCollapsed = !_isThreadInboxCollapsed;
        SavePreferences();
        AddActivity(_isThreadInboxCollapsed ? "Thread inbox minimized." : "Thread inbox expanded.");
        UpdateChrome();
    }

    private void SetThreadInboxMode(string mode)
    {
        if (_threadInboxMode == mode)
        {
            if (mode == ThreadInboxModeSearch)
            {
                _isThreadInboxSearchVisible = true;
                UpdateChrome();
                FocusThreadInboxSearchBox();
            }

            return;
        }

        _threadInboxMode = mode;
        _isThreadInboxCollapsed = false;
        SavePreferences();
        _isThreadInboxSearchVisible = mode == ThreadInboxModeSearch;
        if (mode != ThreadInboxModeSearch)
        {
            _threadInboxSearchGeneration++;
        }

        AddActivity($"Showing {ThreadInboxModeLabel(mode)} inbox threads.");
        UpdateChrome();
        if (mode == ThreadInboxModeSearch)
        {
            FocusThreadInboxSearchBox();
            RunWindowOperation(_ => SearchAppServerThreadCatalogWithDelayAsync());
        }
    }

    private void ThreadInboxSearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdateThreadInbox();
        if (_threadInboxMode == ThreadInboxModeSearch)
        {
            RunWindowOperation(_ => SearchAppServerThreadCatalogWithDelayAsync());
        }
    }

    private void FocusThreadInboxSearchBox()
    {
        ThreadInboxSearchBox.Focus(FocusState.Programmatic);
        ThreadInboxSearchBox.SelectAll();
    }

    private void ThreadInboxItem_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: ThreadInboxItem item } ||
                string.IsNullOrWhiteSpace(item.ActiveNodeId) ||
                !_graph.Nodes.ContainsKey(item.ActiveNodeId))
            {
                return;
            }

            _hoveredInboxNodeId = item.ActiveNodeId;
            await SendGraphCommandAsync("highlightNode", item.ActiveNodeId);

        });
    }

    private void ThreadInboxItem_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: ThreadInboxItem item } ||
                string.IsNullOrWhiteSpace(item.ActiveNodeId) ||
                _hoveredInboxNodeId != item.ActiveNodeId)
            {
                return;
            }

            _hoveredInboxNodeId = null;
            await SendGraphCommandAsync("clearHighlight", item.ActiveNodeId);

        });
    }

    private void FocusAttentionRequestButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetAttentionItem(sender, out var item) ||
                string.IsNullOrWhiteSpace(item.OwningNodeId) ||
                !_graph.Nodes.TryGetValue(item.OwningNodeId, out var node))
            {
                return;
            }

            await FocusThreadNodeAsync(node, $"Focused attention request for {node.Title}.");

        });
    }

    private void AllowAttentionRequestButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetAttentionItem(sender, out var item))
            {
                await ResolveAttentionRequestAsync(
                    item,
                    $"Allowed {item.Method}.",
                    ThreadRunStatuses.Running,
                    $"Allowed attention request for {item.ThreadLabel}.");
            }

        });
    }

    private void DenyAttentionRequestButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetAttentionItem(sender, out var item))
            {
                await ResolveAttentionRequestAsync(
                    item,
                    $"Denied {item.Method}.",
                    ThreadRunStatuses.Idle,
                    $"Denied attention request for {item.ThreadLabel}.");
            }

        });
    }

    private void SendTypedAttentionRequestButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetAttentionItem(sender, out var item))
            {
                return;
            }

            var response = item.ResponseText.Trim();
            if (string.IsNullOrWhiteSpace(response))
            {
                AddActivity("Enter a response before sending.");
                return;
            }

            await ResolveAttentionRequestAsync(
                item,
                $"Responded to {item.Method}: {response}",
                ThreadRunStatuses.Running,
                $"Sent attention response for {item.ThreadLabel}.");

        });
    }

    private void DeclineTypedAttentionRequestButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (TryGetAttentionItem(sender, out var item))
            {
                await ResolveAttentionRequestAsync(
                    item,
                    $"Declined {item.Method}.",
                    ThreadRunStatuses.Idle,
                    $"Declined attention request for {item.ThreadLabel}.");
            }

        });
    }

    private static bool TryGetAttentionItem(object sender, out ThreadAttentionItem item)
    {
        item = sender is FrameworkElement { DataContext: ThreadAttentionItem directItem }
            ? directItem
            : sender is FrameworkElement { DataContext: ReaderTranscriptRow { AttentionItem: { } rowItem } }
                ? rowItem
                : new ThreadAttentionItem();

        return !string.IsNullOrWhiteSpace(item.Id);
    }

    private void OpenInboxThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: ThreadInboxItem item } ||
                string.IsNullOrWhiteSpace(item.ActiveNodeId))
            {
                if (sender is FrameworkElement { DataContext: ThreadInboxItem catalogItem })
                {
                    await AddInboxThreadToCanvasAsync(catalogItem);
                }

                return;
            }

            if (!_graph.Nodes.TryGetValue(item.ActiveNodeId, out var node))
            {
                return;
            }

            _selectedNodeId = item.ActiveNodeId;
            _selectedEdgeId = null;
            if (node.Metadata.IsUnread == true)
            {
                node.Metadata.IsUnread = false;
                await SaveGraphAsync();
            }

            ShowSelectionInspector(node);
            AddActivity($"Opened {node.Title} from inbox.");
            UpdateChrome();
            await SendGraphCommandAsync("selectNode", item.ActiveNodeId);

        });
    }

    private async Task FocusThreadNodeAsync(CanvasNode node, string activityMessage)
    {
        _selectedNodeId = node.Id;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        ShowSelectionInspector(node);
        AddActivity(activityMessage);
        UpdateChrome();
        await SendGraphCommandAsync("selectNode", node.Id);
    }

    private async Task ResolveAttentionRequestAsync(
        ThreadAttentionItem item,
        string transcriptText,
        string nextStatus,
        string activityMessage)
    {
        var request = _graph.PendingAttentionRequests.FirstOrDefault(request => request.Id == item.Id);
        if (request is null)
        {
            AddActivity("Attention request was already resolved.");
            UpdateChrome();
            return;
        }

        _graph.PendingAttentionRequests.Remove(request);
        if (!string.IsNullOrWhiteSpace(item.OwningNodeId) &&
            _graph.Nodes.TryGetValue(item.OwningNodeId, out var node))
        {
            node.Metadata.RunStatus = nextStatus;
            node.Metadata.IsUnread = true;
            node.Metadata.LocalTranscript.Add(new LocalThreadMessage
            {
                Role = "system",
                Text = transcriptText,
                CreatedAt = DateTimeOffset.UtcNow
            });

            if (_selectedNodeId == node.Id)
            {
                SyncSelectionInspector(node);
            }
        }

        await SaveGraphAsync();
        AddActivity(activityMessage);
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void AddInboxThreadToReaderButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: ThreadInboxItem item })
        {
            return;
        }

        if (!string.IsNullOrWhiteSpace(item.ActiveNodeId))
        {
            AddThreadToReader(item.ActiveNodeId, openReader: true);
        }
    }

    private void AddInboxThreadToCanvasButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is FrameworkElement { DataContext: ThreadInboxItem item })
            {
                await AddInboxThreadToCanvasAsync(item);
            }

        });
    }

    private void MarkInboxThreadReadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: ThreadInboxItem item })
            {
                return;
            }

            if (TryGetInboxGraphNode(item, out var node))
            {
                node.Metadata.IsUnread = node.Metadata.IsUnread != true;
                await SaveGraphAsync();
                AddActivity(node.Metadata.IsUnread == true ? $"Marked {node.Title} unread." : $"Marked {node.Title} read.");
                UpdateChrome();
                await RenderGraphAsync();
                return;
            }

            if (TryGetInboxCatalogThread(item, out var catalogThread))
            {
                catalogThread.Node.Metadata.IsUnread = catalogThread.Node.Metadata.IsUnread != true;
                AddActivity(catalogThread.Node.Metadata.IsUnread == true
                    ? $"Marked {catalogThread.Node.Title} unread."
                    : $"Marked {catalogThread.Node.Title} read.");
                UpdateChrome();
            }

        });
    }

    private void ArchiveInboxThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (sender is not FrameworkElement { DataContext: ThreadInboxItem item })
            {
                return;
            }

            if (TryGetInboxGraphNode(item, out var node))
            {
                if (node.Metadata.IsArchived != true &&
                    !await ConfirmArchiveInboxThreadAsync(node))
                {
                    return;
                }

                node.Metadata.IsArchived = node.Metadata.IsArchived != true;
                await SaveGraphAsync();
                AddActivity(node.Metadata.IsArchived == true ? $"Archived {node.Title}." : $"Restored {node.Title}.");
                UpdateChrome();
                await RenderGraphAsync();
                return;
            }

            if (TryGetInboxCatalogThread(item, out var catalogThread))
            {
                if (catalogThread.Node.Metadata.IsArchived != true &&
                    !await ConfirmArchiveInboxThreadAsync(catalogThread.Node))
                {
                    return;
                }

                catalogThread.Node.Metadata.IsArchived = catalogThread.Node.Metadata.IsArchived != true;
                AddActivity(catalogThread.Node.Metadata.IsArchived == true
                    ? $"Archived {catalogThread.Node.Title}."
                    : $"Restored {catalogThread.Node.Title}.");
                UpdateChrome();
            }

        });
    }

    private bool TryGetInboxGraphNode(ThreadInboxItem item, out CanvasNode node)
    {
        if (!string.IsNullOrWhiteSpace(item.ActiveNodeId) &&
            _graph.Nodes.TryGetValue(item.ActiveNodeId, out var graphNode))
        {
            node = graphNode;
            return true;
        }

        node = new CanvasNode();
        return false;
    }

    private bool TryGetInboxCatalogThread(ThreadInboxItem item, out ThreadInboxCatalogThread catalogThread)
    {
        if (_threadInboxCatalogThreadsByItemId.TryGetValue(item.Id, out var thread))
        {
            catalogThread = thread;
            return true;
        }

        catalogThread = new ThreadInboxCatalogThread("", "", "", "", false, new CanvasNode());
        return false;
    }

    private void OpenSelectedThreadInReaderButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            if (node.Metadata.IsUnread == true)
            {
                node.Metadata.IsUnread = false;
                await SaveGraphAsync();
                await RenderGraphAsync();
            }

            AddThreadToReader(node.Id, openReader: true);

        });
    }

    private void StopSelectedThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            await StopThreadAsync(node, "selection inspector", sender as FrameworkElement);

        });
    }

    private void MarkSelectedThreadReadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            node.Metadata.IsUnread = node.Metadata.IsUnread != true;
            await SaveGraphAsync();
            AddActivity(node.Metadata.IsUnread == true ? $"Marked {node.Title} unread." : $"Marked {node.Title} read.");
            SyncSelectionInspector(node);
            UpdateChrome();
            await RenderGraphAsync();

        });
    }

    private void ArchiveSelectedThreadButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (!TryGetSelectedThread(out var node))
            {
                return;
            }

            if (node.Metadata.IsArchived != true &&
                !await ConfirmArchiveThreadAsync(node))
            {
                return;
            }

            node.Metadata.IsArchived = node.Metadata.IsArchived != true;
            await SaveGraphAsync();
            AddActivity(node.Metadata.IsArchived == true ? $"Archived {node.Title}." : $"Restored {node.Title}.");
            SyncSelectionInspector(node);
            UpdateChrome();
            await RenderGraphAsync();

        });
    }

    private void SaveSelectionButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SaveSelectionAsync();

        });
    }

    private async Task SaveSelectionAsync()
    {
        if (_selectedEdgeId is not null && _graph.ManualEdges.TryGetValue(_selectedEdgeId, out var edge))
        {
            var label = SelectionTitleBox.Text.Trim();
            edge.Label = string.IsNullOrWhiteSpace(label) ? null : label;
            await SaveGraphAsync();
            AddActivity($"Saved {EdgeTitle(edge)}.");
            SyncSelectionInspector(edge);
            await RenderGraphAsync();
            return;
        }

        if (_selectedNodeId is null || !_graph.Nodes.TryGetValue(_selectedNodeId, out var node))
        {
            return;
        }

        var title = SelectionTitleBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(title))
        {
            node.Title = title;
            if (node.Metadata.ThreadRef is not null)
            {
                node.Metadata.ThreadRef.Name = title;
            }
        }

        if (node.Kind == NodeKinds.Folder)
        {
            var path = SelectionPathBox.Text.Trim();
            if (!string.IsNullOrWhiteSpace(path))
            {
                node.Subtitle = path;
                node.Metadata.FolderPath = path;
            }
        }

        await SaveGraphAsync();
        AddActivity($"Saved {node.Title}.");
        SyncSelectionInspector(node);
        await RenderGraphAsync();
    }

    private void SelectionTitleBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter)
            {
                return;
            }

            e.Handled = true;
            await SaveSelectionTitleOrLabelAsync();

        });
    }

    private void SelectionPathBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter)
            {
                return;
            }

            e.Handled = true;
            await SaveSelectionFolderPathAsync();

        });
    }

    private async Task SaveSelectionTitleOrLabelAsync()
    {
        if (_selectedEdgeId is not null && _graph.ManualEdges.TryGetValue(_selectedEdgeId, out var edge))
        {
            var label = SelectionTitleBox.Text.Trim();
            edge.Label = string.IsNullOrWhiteSpace(label) ? null : label;
            await SaveGraphAsync();
            AddActivity($"Saved {EdgeTitle(edge)}.");
            await RenderGraphAsync();
            return;
        }

        if (_selectedNodeId is null || !_graph.Nodes.TryGetValue(_selectedNodeId, out var node))
        {
            return;
        }

        var title = SelectionTitleBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            return;
        }

        node.Title = title;
        if (node.Metadata.ThreadRef is not null)
        {
            node.Metadata.ThreadRef.Name = title;
        }

        await SaveGraphAsync();
        AddActivity($"Saved {node.Title}.");
        await RenderGraphAsync();
    }

    private async Task SaveSelectionFolderPathAsync()
    {
        if (_selectedNodeId is null ||
            !_graph.Nodes.TryGetValue(_selectedNodeId, out var node) ||
            node.Kind != NodeKinds.Folder)
        {
            return;
        }

        var path = SelectionPathBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        node.Subtitle = path;
        node.Metadata.FolderPath = path;
        await SaveGraphAsync();
        AddActivity($"Saved {node.Title} path.");
        await RenderGraphAsync();
    }

    private void DeleteSelectionButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            if (_selectedEdgeId is not null && _graph.ManualEdges.TryGetValue(_selectedEdgeId, out var selectedEdge))
            {
                if (!await ConfirmDeleteLineAsync())
                {
                    return;
                }

                _graph.ManualEdges.Remove(_selectedEdgeId);
                _selectedEdgeId = null;
                _pendingLinkSourceNodeId = null;
                SelectionInspector.Visibility = Visibility.Collapsed;
                await SaveGraphAsync();
                AddActivity($"Deleted {EdgeTitle(selectedEdge)}.");
                await RenderGraphAsync();
                return;
            }

            if (_selectedNodeId is null || !_graph.Nodes.TryGetValue(_selectedNodeId, out var node))
            {
                return;
            }

            if (!await ConfirmDeleteNodeAsync(node))
            {
                return;
            }

            _graph.Nodes.Remove(_selectedNodeId);
            foreach (var edge in _graph.ManualEdges.Values
                         .Where(edge => edge.Source == _selectedNodeId || edge.Target == _selectedNodeId)
                         .Select(edge => edge.Id)
                         .ToList())
            {
                _graph.ManualEdges.Remove(edge);
            }

            _selectedNodeId = null;
            SelectionInspector.Visibility = Visibility.Collapsed;
            await SaveGraphAsync();
            AddActivity($"Deleted {node.Title}.");
            await RenderGraphAsync();

        });
    }

    private Task<bool> ConfirmArchiveThreadAsync(CanvasNode node)
    {
        return ConfirmDestructiveActionAsync(
            "Archive Codex Thread?",
            $"This archives the Codex thread \"{node.Title}\" on its owning machine and removes the node from this workflow map.",
            $"Archive {node.Title}");
    }

    private Task<bool> ConfirmArchiveInboxThreadAsync(CanvasNode node)
    {
        return ConfirmDestructiveActionAsync(
            "Archive Thread?",
            $"This archives the Codex thread on {MachineTitleFor(node)}. Canvas nodes are left alone unless you remove them separately.",
            $"Archive {node.Title}");
    }

    private Task<bool> ConfirmDeleteNodeAsync(CanvasNode node)
    {
        return ConfirmDestructiveActionAsync(
            "Delete Canvas Node?",
            $"This removes \"{node.Title}\" and its connected lines from this workflow map. It does not delete Codex thread history from disk.",
            $"Delete {node.Title}");
    }

    private Task<bool> ConfirmDeleteLineAsync()
    {
        return ConfirmDestructiveActionAsync(
            "Delete Line?",
            "This removes the selected manual line from this workflow map.",
            "Delete Line");
    }

    private Task<bool> ConfirmDeleteWorkflowAsync(string workflowName)
    {
        return ConfirmDestructiveActionAsync(
            "Delete Workflow",
            $"This permanently removes the saved workflow layout for {workflowName}. Codex threads on connected machines are not deleted.",
            "Delete Saved Layout");
    }

    private Task<bool> ConfirmDisconnectMachineAsync(CanvasNode machine)
    {
        return ConfirmDestructiveActionAsync(
            "Disconnect Machine?",
            $"This closes the active relay for {machine.Title}. Existing workflow nodes stay on the map, but remote folders and threads will be unavailable until you reconnect.",
            $"Disconnect {machine.Title}");
    }

    private async Task<bool> ConfirmDestructiveActionAsync(string title, string message, string primaryText)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = title,
            Content = new TextBlock
            {
                Text = message,
                TextWrapping = TextWrapping.Wrap
            },
            PrimaryButtonText = primaryText,
            PrimaryButtonStyle = DestructiveDialogPrimaryButtonStyle(),
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        var result = await dialog.ShowAsync();
        return result == ContentDialogResult.Primary;
    }

    private void CloseSelectionButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            _selectedNodeId = null;
            _selectedEdgeId = null;
            _pendingLinkSourceNodeId = null;
            SelectionInspector.Visibility = Visibility.Collapsed;
            ThreadPopover.Visibility = Visibility.Collapsed;
            await SendGraphCommandAsync("clearSelection");

        });
    }

    private void SelectionTitleBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!_isSyncingSelectionFields &&
            _selectedNodeId is not null &&
            SelectionTitleBox.FocusState != FocusState.Unfocused)
        {
            SelectionDetailText.Text = "Unsaved title change.";
        }
        else if (!_isSyncingSelectionFields &&
            _selectedEdgeId is not null &&
            SelectionTitleBox.FocusState != FocusState.Unfocused)
        {
            SelectionDetailText.Text = "Unsaved line label change.";
        }
    }

    private void SelectionPathBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!_isSyncingSelectionFields &&
            _selectedNodeId is not null &&
            SelectionPathBox.FocusState != FocusState.Unfocused)
        {
            SelectionDetailText.Text = "Unsaved folder path change.";
        }
    }

    private void ZoomOutButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SendGraphCommandAsync("zoomOut");

        });
    }

    private void ZoomInButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SendGraphCommandAsync("zoomIn");

        });
    }

    private void ResetViewButton_Click(object sender, RoutedEventArgs e)
    {
        RunWindowOperation(async lease =>
        {
            await SendGraphCommandAsync("resetView");

        });
    }

    private string UpsertMachineFromInitialize(Uri endpointUri, AppServerInitializeResult result)
    {
        var id = ConnectedMachineID(endpointUri, result.HostName);
        _graph.Nodes[id] = new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Machine,
            Title = result.HostName,
            Subtitle = $"{result.Platform} - {endpointUri}",
            Position = _graph.Nodes.TryGetValue(id, out var existingMachine)
                ? existingMachine.Position
                : NextMachinePosition(),
            Size = CanvasSize.Machine,
            Metadata = new NodeMetadata
            {
                HostID = id,
                Platform = result.Platform,
                HostStatus = HostStatuses.Connected,
                CodexHome = result.CodexHome,
                AppServerEndpointUrl = endpointUri.ToString()
            }
        };
        return id;
    }

    private void UpsertLocalMachine(
        string status,
        LocalAppServerStartResult? appServer,
        string detail)
    {
        var existingMachine = LocalMachineNode();
        var id = existingMachine?.Id ?? LocalHostIdentity.LocalMachineNodeID;
        var title = appServer?.InitializeResult.HostName;
        if (string.IsNullOrWhiteSpace(title))
        {
            title = string.IsNullOrWhiteSpace(existingMachine?.Title)
                ? Environment.MachineName
                : existingMachine.Title;
        }

        var platform = appServer?.InitializeResult.Platform
            ?? existingMachine?.Metadata.Platform
            ?? HostPlatforms.Windows;
        var endpointUrl = appServer?.Endpoint.Url.ToString()
            ?? existingMachine?.Metadata.AppServerEndpointUrl;
        var subtitleDetail = status == HostStatuses.Connected && !string.IsNullOrWhiteSpace(endpointUrl)
            ? endpointUrl
            : "local";

        _graph.Nodes[id] = new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Machine,
            Title = title,
            Subtitle = $"{platform} - {subtitleDetail}",
            Position = existingMachine?.Position ?? NextMachinePosition(),
            Size = existingMachine?.Size ?? CanvasSize.Machine,
            Metadata = new NodeMetadata
            {
                HostID = LocalHostIdentity.CanonicalHostID,
                Platform = platform,
                HostStatus = status,
                HostLastError = status == HostStatuses.Unavailable ? detail : null,
                CodexHome = appServer?.InitializeResult.CodexHome ?? existingMachine?.Metadata.CodexHome,
                AppServerEndpointUrl = endpointUrl
            }
        };

        if (status != HostStatuses.Connected)
        {
            UnregisterLocalAppServerEndpoint(_graph.Nodes[id]);
        }
    }

    private void RegisterLocalAppServerEndpoint(AppServerEndpoint endpoint)
    {
        _connectedAppServerEndpointsByHostId[LocalHostIdentity.CanonicalHostID] = endpoint;
        _connectedAppServerEndpointsByHostId[LocalHostIdentity.LocalMachineNodeID] = endpoint;
        if (LocalMachineNode() is { } machine)
        {
            _connectedAppServerEndpointsByHostId[machine.Id] = endpoint;
        }
    }

    private void UnregisterLocalAppServerEndpoint(CanvasNode? localMachine = null)
    {
        _connectedAppServerEndpointsByHostId.Remove(LocalHostIdentity.CanonicalHostID);
        _connectedAppServerEndpointsByHostId.Remove(LocalHostIdentity.LocalMachineNodeID);
        if (localMachine is not null)
        {
            _connectedAppServerEndpointsByHostId.Remove(localMachine.Id);
        }
    }

    private static string ConnectedMachineID(Uri endpointUri, string hostName)
    {
        var raw = string.IsNullOrWhiteSpace(hostName)
            ? endpointUri.Host
            : hostName;
        var compact = new string(raw
            .ToLowerInvariant()
            .Select(character => char.IsLetterOrDigit(character) ? character : '-')
            .ToArray())
            .Trim('-');
        return string.IsNullOrWhiteSpace(compact)
            ? "machine-connected-app-server"
            : $"machine-appserver-{compact}";
    }

    private async Task RenderGraphAsync()
    {
        if (_windowLifetime.IsShuttingDown)
        {
            return;
        }

        if (!_webViewReady)
        {
            await InitializeGraphViewAsync();
        }

        if (_windowLifetime.IsShuttingDown)
        {
            return;
        }

        UpdateChrome();
        if (!_graphDocumentReady || GraphView.CoreWebView2 is null)
        {
            _graphDocumentReady = false;
            GraphView.NavigateToString(GraphWebRenderer.Render(
                _graph,
                _showsSubagents,
                BrowsableMachineIds(),
                SemanticEdgeResolver.ResolveEdges(_graph),
                _threadAutomationsByThreadId));
            return;
        }

        await PostGraphMessageAsync(new
        {
            type = "graphUpdated",
            graph = _graph,
            semanticEdges = SemanticEdgeResolver.ResolveEdges(_graph),
            showsSubagents = _showsSubagents,
            browsableMachineIds = BrowsableMachineIds(),
            threadAutomationsByThreadId = _threadAutomationsByThreadId,
            selectedNodeId = _selectedNodeId ?? "",
            selectedEdgeId = _selectedEdgeId ?? ""
        });
    }

    private async Task SendGraphCommandAsync(string command)
    {
        await SendGraphCommandAsync(command, null);
    }

    private async Task SendGraphCommandAsync(string command, string? nodeId)
    {
        if (!_webViewReady || GraphView.CoreWebView2 is null)
        {
            return;
        }

        await PostGraphMessageAsync(new { type = command, id = nodeId });
    }

    private Task PostGraphMessageAsync(object payload)
    {
        if (!_webViewReady || !_graphDocumentReady || GraphView.CoreWebView2 is null)
        {
            return Task.CompletedTask;
        }

        var message = JsonSerializer.Serialize(payload, MapofAgentsJson.Options);
        GraphView.CoreWebView2.PostWebMessageAsJson(message);
        return Task.CompletedTask;
    }

    private void GraphView_WebMessageReceived(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        var messageJson = args.WebMessageAsJson;
        _ = _windowLifetime.TryRunTracked(
            lease => HandleGraphViewWebMessageAsync(messageJson, lease),
            out _);
    }

    private async Task HandleGraphViewWebMessageAsync(
        string messageJson,
        WindowLifetimeLease lease)
    {
        if (!_windowLifetime.IsCurrent(lease))
        {
            return;
        }

        try
        {
            using var document = JsonDocument.Parse(messageJson);
            if (!document.RootElement.TryGetProperty("type", out var typeElement))
            {
                return;
            }

            switch (typeElement.GetString())
            {
                case "nodeSelected":
                    SelectNodeFromMessage(document.RootElement);
                    break;
                case "edgeSelected":
                    SelectEdgeFromMessage(document.RootElement);
                    break;
                case "selectionCleared":
                    ClearSelectionFromGraphMessage();
                    break;
                case "nodeMoved":
                    await MoveNodeFromMessageAsync(document.RootElement);
                    break;
                case "nodeCommand":
                    await HandleNodeCommandAsync(document.RootElement);
                    break;
                case "linkTargetSelected":
                    await CompleteLinkFromMessageAsync(document.RootElement);
                    break;
                case "linkCancelled":
                    CancelPendingLink();
                    break;
                case "viewportChanged":
                    UpdateViewportFromMessage(document.RootElement);
                    break;
            }
        }
        catch (JsonException exception)
        {
            if (!_windowLifetime.IsCurrent(lease))
            {
                return;
            }

            var message = $"Ignored graph message: {exception.Message}";
            SetStatusStripError(message);
            AddActivity(
                message,
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
    }

    private void SelectNodeFromMessage(JsonElement root)
    {
        if (!root.TryGetProperty("id", out var idElement))
        {
            return;
        }

        var id = idElement.GetString();
        if (id is null || !_graph.Nodes.TryGetValue(id, out var node))
        {
            return;
        }

        _selectedNodeId = id;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        ShowSelectionInspector(node);
        AddActivity($"Selected {node.Title}.");
        UpdateChrome();
    }

    private void SelectEdgeFromMessage(JsonElement root)
    {
        if (!root.TryGetProperty("id", out var idElement))
        {
            return;
        }

        var id = idElement.GetString();
        if (id is null || !_graph.ManualEdges.TryGetValue(id, out var edge))
        {
            return;
        }

        _selectedNodeId = null;
        _selectedEdgeId = id;
        _pendingLinkSourceNodeId = null;
        ShowSelectionInspector(edge);
        AddActivity($"Selected {EdgeTitle(edge)}.");
        UpdateChrome();
    }

    private void ClearSelectionFromGraphMessage()
    {
        _selectedNodeId = null;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        SelectionInspector.Visibility = Visibility.Collapsed;
        ResetThreadPopoverData();
        UpdateChrome();
    }

    private async Task HandleNodeCommandAsync(JsonElement root)
    {
        if (!root.TryGetProperty("id", out var idElement) ||
            !root.TryGetProperty("command", out var commandElement))
        {
            return;
        }

        var id = idElement.GetString();
        var command = commandElement.GetString();
        if (string.IsNullOrWhiteSpace(id) ||
            string.IsNullOrWhiteSpace(command) ||
            !_graph.Nodes.TryGetValue(id, out var node))
        {
            return;
        }

        SelectNodeForCommand(node);
        switch (command)
        {
            case "link":
                await BeginLinkFromNodeAsync(node);
                break;
            case "addFolder":
                await AddFolderFromGraphNodeAsync(node);
                break;
            case "showContents":
                await ShowFolderContentsFromGraphAsync(node);
                break;
            case "openChat":
                await OpenThreadChatFromGraphAsync(node);
                break;
            case "automation":
                await OpenThreadAutomationFromGraphAsync(node);
                break;
            case "openReader":
                await OpenThreadInReaderFromGraphAsync(node);
                break;
            case "toggleRead":
                await ToggleThreadReadFromGraphAsync(node);
                break;
            case "stopThread":
                await StopThreadFromGraphAsync(node);
                break;
            case "archiveThread":
                await ArchiveThreadFromGraphAsync(node);
                break;
            case "forkThread":
                await ForkThreadFromGraphAsync(node);
                break;
            case "copyThreadId":
                CopyThreadIdFromGraph(node);
                break;
            case "reconnectOwner":
                await ReconnectThreadOwnerFromGraphAsync(node);
                break;
            case "deleteNode":
                await DeleteNodeFromGraphAsync(node);
                break;
        }

        UpdateChrome();
    }

    private void SelectNodeForCommand(CanvasNode node)
    {
        _selectedNodeId = node.Id;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        ShowSelectionInspector(node);
    }

    private async Task AddFolderFromGraphNodeAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.Machine)
        {
            return;
        }

        var isLocalHost = IsLocalHostId(node.Metadata.HostID);
        var hasRemoteBrowser = TryFindCodexRemoteForMachine(node, out var codexRemote);
        if (MachineFolderActionPolicy.UnavailableReason(node, isLocalHost, hasRemoteBrowser) is { } reason)
        {
            AddActivity(reason);
            ShowCommandFeedback(reason);
            return;
        }

        var folderPath = isLocalHost
            ? await PickLocalFolderPathAsync()
            : hasRemoteBrowser
                ? await ShowRemoteFolderPickerAsync(codexRemote, DefaultFolderPathFor(node))
                : await PromptForMachineFolderPathAsync(node);
        if (folderPath is null)
        {
            AddActivity("Canceled folder creation.");
            return;
        }

        await AddFolderNodeAsync(node, folderPath);
    }

    private async Task ShowFolderContentsFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.Folder)
        {
            return;
        }

        var folderPath = (node.Metadata.FolderPath ?? node.Subtitle).Trim();
        if (string.IsNullOrWhiteSpace(folderPath))
        {
            AddActivity("This folder node does not have a folder path.", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            ShowCommandFeedback("This folder node does not have a folder path.");
            return;
        }

        if (IsLocalHostId(node.Metadata.HostID))
        {
            OpenLocalFolderContents(folderPath, node.Title);
            return;
        }

        var owner = MachineForHost(node.Metadata.HostID);
        if (owner is not null && TryFindCodexRemoteForMachine(owner, out var remote))
        {
            _ = await ShowRemoteFolderPickerAsync(
                remote,
                folderPath,
                RemoteFolderPickerMode.ShowContents);
            return;
        }

        var message = $"Reconnect {MachineTitleFor(node)} before showing folder contents.";
        AddActivity(message, showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
        ShowCommandFeedback(message);
    }

    private void OpenLocalFolderContents(string folderPath, string folderTitle)
    {
        var expandedPath = Environment.ExpandEnvironmentVariables(folderPath.Trim());
        try
        {
            if (!Directory.Exists(expandedPath))
            {
                var message = $"Folder does not exist: {folderTitle}.";
                AddActivity(message, showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
                ShowCommandFeedback(message);
                return;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName = expandedPath,
                UseShellExecute = true
            });
            AddActivity($"Opened {folderTitle} contents.");
        }
        catch (Exception exception) when (
            exception is Win32Exception or IOException or InvalidOperationException or UnauthorizedAccessException)
        {
            var message = $"Could not open {folderTitle}: {exception.Message}";
            AddActivity(message, showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            ShowCommandFeedback(message);
        }
    }

    private List<string> BrowsableMachineIds()
    {
        return MachineNodes
            .Where(machine => MachineFolderActionPolicy.CanChooseProjectFolder(
                machine,
                IsLocalHostId(machine.Metadata.HostID),
                TryFindCodexRemoteForMachine(machine, out _)))
            .Select(machine => machine.Id)
            .ToList();
    }

    private async Task OpenThreadChatFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        _isReadingModePresented = false;
        var didChange = false;
        if (node.Metadata.IsUnread == true)
        {
            node.Metadata.IsUnread = false;
            didChange = true;
        }

        if (didChange)
        {
            await SaveGraphAsync();
            await RenderGraphAsync();
        }

        AddActivity($"Opened {node.Title}.");
        UpdateChrome();
        await SendGraphCommandAsync("selectNode", node.Id);
    }

    private async Task OpenThreadAutomationFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        await ShowThreadAutomationDialogAsync(node);
    }

    private async Task OpenThreadInReaderFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        var didChange = false;
        if (node.Metadata.IsUnread == true)
        {
            node.Metadata.IsUnread = false;
            didChange = true;
        }

        AddThreadToReader(node.Id, openReader: true);
        if (didChange)
        {
            await SaveGraphAsync();
            await RenderGraphAsync();
        }
    }

    private async Task ToggleThreadReadFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        node.Metadata.IsUnread = node.Metadata.IsUnread != true;
        await SaveGraphAsync();
        AddActivity(node.Metadata.IsUnread == true ? $"Marked {node.Title} unread." : $"Marked {node.Title} read.");
        SyncSelectionInspector(node);
        UpdateChrome();
        await RenderGraphAsync();
    }

    private async Task StopThreadFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        await StopThreadAsync(node, "canvas menu");
    }

    private async Task ArchiveThreadFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        if (node.Metadata.IsArchived != true &&
            !await ConfirmArchiveThreadAsync(node))
        {
            return;
        }

        node.Metadata.IsArchived = node.Metadata.IsArchived != true;
        await SaveGraphAsync();
        AddActivity(node.Metadata.IsArchived == true ? $"Archived {node.Title}." : $"Restored {node.Title}.");
        SyncSelectionInspector(node);
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void CopyThreadIdFromGraph(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        var threadID = node.Metadata.ThreadRef?.ThreadID ?? node.Id;
        CopyTextToClipboard(threadID);
        AddActivity($"Copied thread ID for {node.Title}.");
    }

    private async Task ReconnectThreadOwnerFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        var hostID = node.Metadata.ThreadRef?.HostID ?? node.Metadata.HostID;
        var owner = string.IsNullOrWhiteSpace(hostID)
            ? null
            : MachineNodes.FirstOrDefault(machine =>
                SameIdentifier(machine.Id, hostID) ||
                SameIdentifier(machine.Metadata.HostID, hostID));
        if (owner is null)
        {
            AddActivity($"Could not find an owning machine for {node.Title}.", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            ShowCommandFeedback("No owning machine is on this workflow map.");
            return;
        }

        _isMachinesRailVisible = true;
        _isMachinesRailCollapsed = false;
        _isMachineRecoveryVisible = true;
        _expandedMachineHealthItemId = owner.Id;
        RefreshMachineHealth(
            showMachinesRail: true,
            detail: $"Recovery opened for {owner.Title}, owner of {node.Title}.",
            activityMessage: $"Opened recovery for {owner.Title}.");
        UpdateChrome();
        await SendGraphCommandAsync("highlightNode", owner.Id);
    }

    private async Task ForkThreadFromGraphAsync(CanvasNode node)
    {
        if (node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        if (node.Metadata.ThreadRef is not { } sourceThreadRef ||
            string.IsNullOrWhiteSpace(sourceThreadRef.ThreadID))
        {
            AddActivity($"Cannot fork {node.Title} because it does not have a Codex thread ID.", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            return;
        }

        if (!TryGetAppServerEndpointForThread(node, out var endpoint))
        {
            AddActivity($"Reconnect {MachineTitleFor(node)} before forking {node.Title}.", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            return;
        }

        try
        {
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(25));
            var forkedRef = await new AppServerClient().ForkThreadAsync(
                endpoint,
                sourceThreadRef,
                node.Metadata.Model,
                cancellation.Token);

            forkedRef.HostID = string.IsNullOrWhiteSpace(forkedRef.HostID) ? sourceThreadRef.HostID : forkedRef.HostID;
            forkedRef.Cwd = string.IsNullOrWhiteSpace(forkedRef.Cwd) ? sourceThreadRef.Cwd : forkedRef.Cwd;
            forkedRef.Name = string.IsNullOrWhiteSpace(forkedRef.Name) ? $"{node.Title} fork" : forkedRef.Name;

            var forkNode = new CanvasNode
            {
                Id = UniqueNodeId(PreferredThreadNodeId(forkedRef)),
                Kind = NodeKinds.CodexThread,
                Title = forkedRef.Name!,
                Subtitle = string.IsNullOrWhiteSpace(forkedRef.Cwd) ? node.Subtitle : forkedRef.Cwd,
                Size = CanvasSize.Thread,
                Metadata = new NodeMetadata
                {
                    HostID = forkedRef.HostID,
                    Platform = node.Metadata.Platform ?? PlatformForHost(forkedRef.HostID),
                    ThreadRef = forkedRef,
                    Model = node.Metadata.Model,
                    ReasoningEffort = node.Metadata.ReasoningEffort,
                    ThreadKind = node.Metadata.ThreadKind ?? ThreadKinds.Thread,
                    ApprovalPolicy = node.Metadata.ApprovalPolicy,
                    SandboxMode = node.Metadata.SandboxMode,
                    RunStatus = ThreadRunStatuses.Idle,
                    LocalTranscript = new List<LocalThreadMessage>
                    {
                        new()
                        {
                            Role = "system",
                            Text = $"Forked from {node.Title}.",
                            CreatedAt = DateTimeOffset.UtcNow
                        }
                    }
                },
                ZIndex = _graph.Nodes.Count
            };

            var anchor = AnchorNodeForThread(forkNode);
            forkNode.Position = NextThreadPosition(anchor ?? node);
            _graph.Nodes[forkNode.Id] = forkNode;

            if (anchor is not null)
            {
                var anchorEdgeID = $"edge-{Guid.NewGuid():N}";
                _graph.ManualEdges[anchorEdgeID] = new CanvasEdge
                {
                    Id = anchorEdgeID,
                    Source = anchor.Id,
                    Target = forkNode.Id,
                    Kind = anchor.Kind == NodeKinds.Folder ? EdgeKinds.FolderThread : EdgeKinds.MachineThread,
                    IsManual = false
                };
            }

            var forkEdgeID = $"edge-{Guid.NewGuid():N}";
            _graph.ManualEdges[forkEdgeID] = new CanvasEdge
            {
                Id = forkEdgeID,
                Source = node.Id,
                Target = forkNode.Id,
                Kind = EdgeKinds.CreatedBy,
                IsManual = true,
                Label = "fork"
            };

            _selectedNodeId = forkNode.Id;
            _selectedEdgeId = null;
            _pendingLinkSourceNodeId = null;
            await SaveGraphAsync();
            AddActivity($"Forked {node.Title} as {forkNode.Title}.");
            UpdateChrome();
            await RenderGraphAsync();
            await SendGraphCommandAsync("selectNode", forkNode.Id);
        }
        catch (Exception exception)
        {
            SetStatusStripError(exception.Message);
            AddActivity($"Could not fork {node.Title}: {exception.Message}", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
        }
    }

    private async Task DeleteNodeFromGraphAsync(CanvasNode node)
    {
        if (!await ConfirmDeleteNodeAsync(node))
        {
            return;
        }

        _graph.Nodes.Remove(node.Id);
        foreach (var edge in _graph.ManualEdges.Values
                     .Where(edge => edge.Source == node.Id || edge.Target == node.Id)
                     .Select(edge => edge.Id)
                     .ToList())
        {
            _graph.ManualEdges.Remove(edge);
        }

        _readerThreadIds.Remove(node.Id);
        _readerPendingAttachments.Remove(node.Id);
        _readerTranscriptFilters.Remove(node.Id);
        _transcriptSessions.Remove(node.Id);
        if (_artifactCatalog.SourceId == node.Id)
        {
            _artifactCatalog.ClearSource();
            ArtifactsPopover.Visibility = Visibility.Collapsed;
            CloseArtifactPreview();
        }

        _selectedNodeId = null;
        _selectedEdgeId = null;
        _pendingLinkSourceNodeId = null;
        SelectionInspector.Visibility = Visibility.Collapsed;
        ThreadPopover.Visibility = Visibility.Collapsed;
        await SaveGraphAsync();
        AddActivity($"Deleted {node.Title}.");
        UpdateChrome();
        await RenderGraphAsync();
    }

    private async Task BeginLinkFromNodeAsync(CanvasNode node)
    {
        _pendingLinkSourceNodeId = _pendingLinkSourceNodeId == node.Id ? null : node.Id;
        if (_pendingLinkSourceNodeId is null)
        {
            AddActivity("Connection drawing cancelled.");
            await SendGraphCommandAsync("cancelLink");
            return;
        }

        AddActivity($"Choose a target node for a note line from {node.Title}.");
        await SendGraphCommandAsync("beginLink", node.Id);
    }

    private async Task CompleteLinkFromMessageAsync(JsonElement root)
    {
        if (!root.TryGetProperty("sourceId", out var sourceElement) ||
            !root.TryGetProperty("targetId", out var targetElement))
        {
            return;
        }

        var sourceID = sourceElement.GetString();
        var targetID = targetElement.GetString();
        if (string.IsNullOrWhiteSpace(sourceID) ||
            string.IsNullOrWhiteSpace(targetID) ||
            sourceID == targetID ||
            !_graph.Nodes.TryGetValue(sourceID, out var sourceNode) ||
            !_graph.Nodes.TryGetValue(targetID, out var targetNode))
        {
            CancelPendingLink();
            return;
        }

        if (_pendingLinkSourceNodeId is not null && _pendingLinkSourceNodeId != sourceID)
        {
            AddActivity("Connection source changed before the target was selected.");
            _pendingLinkSourceNodeId = null;
            await SendGraphCommandAsync("cancelLink");
            return;
        }

        var edgeID = $"edge-{Guid.NewGuid():N}";
        var edge = new CanvasEdge
        {
            Id = edgeID,
            Source = sourceID,
            Target = targetID,
            Kind = EdgeKinds.ManualNote,
            IsManual = true,
            Label = "note"
        };
        _graph.ManualEdges[edgeID] = edge;
        _pendingLinkSourceNodeId = null;
        _selectedNodeId = null;
        _selectedEdgeId = edgeID;

        await SaveGraphAsync();
        AddActivity($"Linked {sourceNode.Title} to {targetNode.Title}.");
        ShowSelectionInspector(edge);
        UpdateChrome();
        await RenderGraphAsync();
    }

    private void CancelPendingLink()
    {
        if (_pendingLinkSourceNodeId is null)
        {
            return;
        }

        _pendingLinkSourceNodeId = null;
        AddActivity("Connection drawing cancelled.");
        UpdateChrome();
    }

    private async Task MoveNodeFromMessageAsync(JsonElement root)
    {
        if (!root.TryGetProperty("id", out var idElement) ||
            !root.TryGetProperty("x", out var xElement) ||
            !root.TryGetProperty("y", out var yElement))
        {
            return;
        }

        var id = idElement.GetString();
        if (id is null || !_graph.Nodes.TryGetValue(id, out var node))
        {
            return;
        }

        node.Position = new CanvasPoint(xElement.GetDouble(), yElement.GetDouble());
        node.Metadata.HasManualPosition = true;
        await SaveGraphAsync();
        UpdateChrome();
    }

    private void UpdateViewportFromMessage(JsonElement root)
    {
        if (!root.TryGetProperty("x", out var xElement) ||
            !root.TryGetProperty("y", out var yElement) ||
            !root.TryGetProperty("scale", out var scaleElement))
        {
            return;
        }

        _graph.Viewport.Offset = new CanvasPoint(xElement.GetDouble(), yElement.GetDouble());
        _graph.Viewport.Scale = scaleElement.GetDouble();
        if (SelectedThreadNode() is { } node && ThreadPopover.Visibility == Visibility.Visible)
        {
            PositionThreadPopover(node);
        }
        else if (_selectedEdgeId is not null &&
            _graph.ManualEdges.ContainsKey(_selectedEdgeId) &&
            SelectionInspector.Visibility == Visibility.Visible)
        {
            ApplySelectionInspectorLayout(SelectionInspectorLayout.ForEdge());
        }
    }

    private void SyncSelectionInspector(CanvasNode node)
    {
        _isSyncingSelectionFields = true;

        ApplySelectionInspectorLayout(SelectionInspectorLayout.ForNode());
        SelectionKindText.Text = node.Kind switch
        {
            NodeKinds.Machine => "Machine",
            NodeKinds.Folder => "Folder",
            NodeKinds.CodexThread => "Thread",
            _ => "Node"
        };
        SelectionIcon.Glyph = SelectionGlyphFor(node);
        SelectionIcon.Foreground = SelectionForegroundFor(node);
        SelectionIconSurface.Background = SelectionBackgroundFor(node);
        SelectionTitleBox.Text = node.Title;
        SelectionTitleBox.PlaceholderText = "Title";
        SelectionPathBox.Visibility = node.Kind == NodeKinds.Folder ? Visibility.Visible : Visibility.Collapsed;
        SelectionPathBox.Text = node.Metadata.FolderPath ?? node.Subtitle;
        SelectionDetailText.Visibility = node.Kind == NodeKinds.Folder || string.IsNullOrWhiteSpace(node.Subtitle)
            ? Visibility.Collapsed
            : Visibility.Visible;
        SelectionDetailText.Text = node.Subtitle;
        UpdateSelectionRoutes(null);
        SelectionThreadPanel.Visibility = node.Kind == NodeKinds.CodexThread ? Visibility.Visible : Visibility.Collapsed;
        if (node.Kind == NodeKinds.CodexThread)
        {
            UpdateThreadSelectionPanel(node);
        }

        _isSyncingSelectionFields = false;
    }

    private void ShowSelectionInspector(CanvasNode node)
    {
        SyncSelectionInspector(node);
        SelectionInspector.Visibility = ShouldShowSelectionInspector(node)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void SyncSelectionInspector(CanvasEdge edge)
    {
        _isSyncingSelectionFields = true;

        ApplySelectionInspectorLayout(SelectionInspectorLayout.ForEdge());
        var editorPresentation = CanvasEdgePresentation.Editor(edge);
        SelectionKindText.Text = editorPresentation.Title;
        SelectionIcon.Glyph = editorPresentation.Glyph;
        SelectionIcon.FontSize = editorPresentation.IconFontSize;
        SelectionIcon.Foreground = BrushFromHex(editorPresentation.IconForegroundHex);
        SelectionIconSurface.Background = BrushFromHex(editorPresentation.IconBackgroundHex);
        SelectionTitleBox.PlaceholderText = "Label";
        SelectionTitleBox.Text = edge.Label ?? "";
        SelectionPathBox.Visibility = Visibility.Collapsed;
        SelectionPathBox.Text = "";
        SelectionThreadPanel.Visibility = Visibility.Collapsed;
        SelectionDetailText.Visibility = Visibility.Collapsed;
        SelectionDetailText.Text = "";
        UpdateSelectionRoutes(edge);

        _isSyncingSelectionFields = false;
    }

    private void ShowSelectionInspector(CanvasEdge edge)
    {
        SyncSelectionInspector(edge);
        SelectionInspector.Visibility = Visibility.Visible;
    }

    private void ApplySelectionInspectorLayout(SelectionInspectorLayoutMetrics layout)
    {
        SelectionInspector.HorizontalAlignment = HorizontalAlignment.Right;
        SelectionInspector.VerticalAlignment = VerticalAlignment.Top;
        SelectionInspector.Width = layout.Width;
        SelectionInspector.Margin = new Thickness(0, layout.TopInset, layout.RightInset, 0);
        SelectionInspector.Padding = new Thickness(layout.Padding);
        SelectionInspector.CornerRadius = new CornerRadius(layout.CornerRadius);
        SelectionInspector.Translation = new Vector3(0, 0, (float)layout.ShadowTranslationZ);
        SelectionInspectorContent.Spacing = layout.ContentSpacing;
        SelectionInspectorHeader.ColumnSpacing = layout.HeaderSpacing;
        SelectionIconSurface.Width = layout.IconSize;
        SelectionIconSurface.Height = layout.IconSize;
        SelectionIconSurface.CornerRadius = new CornerRadius(layout.IconCornerRadius);
    }

    private static bool ShouldShowSelectionInspector(CanvasNode node)
    {
        return node.Kind != NodeKinds.Machine && node.Kind != NodeKinds.CodexThread;
    }

    private void UpdateSelectionRoutes(CanvasEdge? edge)
    {
        _selectionRouteItems.Clear();
        if (edge is null)
        {
            SelectionRoutePanel.Visibility = Visibility.Collapsed;
            SelectionRouteCountText.Text = "";
            return;
        }

        var routes = _graph.MessageRoutes.Values
            .Where(route => route.CanvasEdgeID == edge.Id)
            .OrderByDescending(route => route.Timestamp)
            .Take(4)
            .Select(route => EdgeRouteItem.FromRoute(route, EndpointTitleForThread(route.SourceThreadID), EndpointTitleForThread(route.TargetThreadID)))
            .ToList();

        foreach (var route in routes)
        {
            _selectionRouteItems.Add(route);
        }

        SelectionRoutePanel.Visibility = routes.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        SelectionRouteCountText.Text = routes.Count == 0
            ? ""
            : $"{routes.Count} route{(routes.Count == 1 ? "" : "s")}";
    }

    private string EdgeTitle(CanvasEdge edge)
    {
        return string.IsNullOrWhiteSpace(edge.Label)
            ? $"{EndpointTitle(edge.Source)} to {EndpointTitle(edge.Target)} line"
            : $"{edge.Label} line";
    }

    private string EdgeDetail(CanvasEdge edge)
    {
        var label = CanvasEdgePresentation.KindLabel(edge.Kind);
        var source = EndpointTitle(edge.Source);
        var target = EndpointTitle(edge.Target);
        return $"{label} - {source} -> {target}";
    }

    private string EndpointTitle(string nodeId)
    {
        return _graph.Nodes.TryGetValue(nodeId, out var node)
            ? node.Title
            : nodeId;
    }

    private string EndpointTitleForThread(string threadId)
    {
        if (string.IsNullOrWhiteSpace(threadId))
        {
            return "unknown thread";
        }

        return _graph.Nodes.Values.FirstOrDefault(node =>
            node.Metadata.ThreadRef?.ThreadID == threadId ||
            node.Id == threadId)?.Title ?? threadId;
    }

    private static string SelectionGlyphFor(CanvasNode node)
    {
        return node.Kind switch
        {
            NodeKinds.Machine => "\uE950",
            NodeKinds.Folder => "\uE8B7",
            NodeKinds.CodexThread => "\uE8F2",
            _ => "\uE8A5"
        };
    }

    private static SolidColorBrush SelectionForegroundFor(CanvasNode node)
    {
        return node.Kind switch
        {
            NodeKinds.Machine => BrushFromHex("#30D158"),
            NodeKinds.Folder => BrushFromHex("#FFD60A"),
            NodeKinds.CodexThread => BrushFromHex("#0A84FF"),
            _ => BrushFromHex("#A7B0BF")
        };
    }

    private static SolidColorBrush SelectionBackgroundFor(CanvasNode node)
    {
        return node.Kind switch
        {
            NodeKinds.Machine => BrushFromHex("#1A30D158"),
            NodeKinds.Folder => BrushFromHex("#1AFFD60A"),
            NodeKinds.CodexThread => BrushFromHex("#1A0A84FF"),
            _ => BrushFromHex("#16697586")
        };
    }

    private bool TryGetSelectedThread(out CanvasNode node)
    {
        node = default!;
        if (_selectedNodeId is null ||
            !_graph.Nodes.TryGetValue(_selectedNodeId, out var selectedNode) ||
            selectedNode.Kind != NodeKinds.CodexThread)
        {
            return false;
        }

        node = selectedNode;
        return true;
    }

    private void UpdateThreadSelectionPanel(CanvasNode node)
    {
        var headerStatus = ThreadHeaderStatusFor(node);
        var isUnread = node.Metadata.IsUnread == true;
        var isArchived = node.Metadata.IsArchived == true;
        ApplyThreadStatusPillPresentation(
            SelectionThreadStatusPill,
            SelectionThreadStatusText,
            SelectionThreadStatusIcon,
            ThreadStatusPresentation.Resolve(headerStatus, isUnread));
        SelectionThreadMetaText.Text = SelectionThreadMetadataSummary(node);

        var latest = node.Metadata.LocalTranscript
            .OrderByDescending(message => message.CreatedAt)
            .FirstOrDefault();
        SelectionThreadLatestRoleText.Text = latest is null
            ? ThreadTranscriptEmptyStatePresentation.Title
            : ThreadRoleLabel(latest.Role);
        SelectionThreadLatestText.Text = latest is null
            ? ThreadTranscriptEmptyStatePresentation.Detail
            : latest.Text;

        ApplyStopTurnActionAvailability(
            SelectionStopThreadButton,
            SelectionStopThreadIcon,
            StopTurnAvailability(node));
        SelectionMarkReadText.Text = isUnread ? "Mark read" : "Mark unread";
        SelectionMarkReadIcon.Glyph = isUnread ? "\uE715" : "\uE119";
        SelectionArchiveText.Text = isArchived ? "Restore" : "Archive";
        SelectionArchiveIcon.Glyph = isArchived ? "\uE72D" : "\uE74D";
    }

    private string SelectionThreadMetadataSummary(CanvasNode node)
    {
        var metadata = ThreadComposerMetadataPresentation.Resolve(
            node.Metadata.Model,
            node.Metadata.ReasoningEffort);
        var parts = new List<string>();
        if (metadata.ShowsModel)
        {
            parts.Add(metadata.ModelText);
        }

        if (metadata.ShowsEffort)
        {
            parts.Add(metadata.EffortText);
        }

        parts.Add(node.Metadata.ApprovalPolicy ?? "on-request");
        parts.Add(node.Metadata.SandboxMode ?? "workspace-write");
        return $"{MachineTitleFor(node)} - {string.Join(" / ", parts)}";
    }

    private void UpdateThreadPopover(CanvasNode node)
    {
        UpdateThreadPopoverSize();

        var status = node.Metadata.RunStatus ?? ThreadRunStatuses.Idle;
        var headerStatus = ThreadHeaderStatusFor(node);
        var isUnread = node.Metadata.IsUnread == true;
        var isNewPopoverNode = _threadPopoverNodeId != node.Id;

        if (isNewPopoverNode)
        {
            ResetThreadPopoverTranscriptFilters();
            _threadPopoverPendingAttachments.Clear();
            ClearThreadPopoverMentionSuggestions();
            _threadPopoverAttachmentError = null;
            _isThreadPopoverRenaming = false;
        }

        ThreadPopoverTitleText.Text = node.Title;
        if (isNewPopoverNode || !_isThreadPopoverRenaming)
        {
            ThreadPopoverTitleBox.Text = node.Title;
        }
        UpdateThreadPopoverTitleChrome();

        _threadPopoverNodeId = node.Id;
        ThreadPopoverSubtitleText.Text = node.Subtitle;
        var iconPresentation = ThreadHeaderIconPresentation.Resolve(LooksLikeSubagent(node));
        var headerBrush = BrushFromHex(iconPresentation.HeaderForegroundHex);
        var kindBrush = BrushFromHex(iconPresentation.KindForegroundHex);
        ThreadPopoverHeaderIconSurface.Width = iconPresentation.HeaderSurfaceSize;
        ThreadPopoverHeaderIconSurface.Height = iconPresentation.HeaderSurfaceSize;
        ThreadPopoverHeaderIconSurface.CornerRadius = new CornerRadius(iconPresentation.HeaderSurfaceCornerRadius);
        ThreadPopoverHeaderIconGrid.Width = iconPresentation.HeaderIconGridWidth;
        ThreadPopoverHeaderIconGrid.Height = iconPresentation.HeaderIconGridHeight;
        ThreadPopoverHeaderThreadPairIcon.Width = iconPresentation.HeaderIconGridWidth;
        ThreadPopoverHeaderThreadPairIcon.Height = iconPresentation.HeaderIconGridHeight;
        ThreadPopoverHeaderIcon.Glyph = iconPresentation.HeaderGlyph;
        ThreadPopoverHeaderIcon.FontSize = iconPresentation.HeaderGlyphFontSize;
        ThreadPopoverHeaderIcon.Foreground = headerBrush;
        ThreadPopoverHeaderThreadPairBackBubblePath.Stroke = headerBrush;
        ThreadPopoverHeaderThreadPairBackBubblePath.StrokeThickness = iconPresentation.HeaderPairStrokeThickness;
        ThreadPopoverHeaderThreadPairBackBubblePath.Opacity = iconPresentation.HeaderPairBackOpacity;
        ThreadPopoverHeaderThreadPairFrontBubblePath.Stroke = headerBrush;
        ThreadPopoverHeaderThreadPairFrontBubblePath.StrokeThickness = iconPresentation.HeaderPairStrokeThickness;
        ThreadPopoverHeaderIcon.Visibility = iconPresentation.UsesHeaderThreadPairIcon ? Visibility.Collapsed : Visibility.Visible;
        ThreadPopoverHeaderThreadPairIcon.Visibility = iconPresentation.UsesHeaderThreadPairIcon ? Visibility.Visible : Visibility.Collapsed;
        ThreadPopoverHeaderIconSurface.Background = BrushFromHex(iconPresentation.HeaderBackgroundHex);
        ThreadPopoverKindText.Text = ThreadKindLabelFor(node);
        ThreadPopoverKindText.Foreground = kindBrush;
        ThreadPopoverKindIcon.Glyph = iconPresentation.KindGlyph;
        ThreadPopoverKindIcon.Foreground = kindBrush;
        ThreadPopoverKindPill.Background = BrushFromHex(iconPresentation.KindBackgroundHex);
        ThreadPopoverThreadIdText.Text = node.Metadata.ThreadRef?.ThreadID ?? node.Id;
        ApplyThreadStatusPillPresentation(
            ThreadPopoverStatusPill,
            ThreadPopoverStatusText,
            ThreadPopoverStatusIcon,
            ThreadStatusPresentation.Resolve(headerStatus, isUnread));
        ApplyThreadAutomationPresentation(node);
        var composerMetadata = ThreadComposerMetadataPresentation.Resolve(
            node.Metadata.Model,
            node.Metadata.ReasoningEffort);
        ThreadPopoverComposerMetadataRow.Visibility = composerMetadata.ShowsMetadataRow
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverComposerModelChip.Visibility = composerMetadata.ShowsModel
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverComposerEffortChip.Visibility = composerMetadata.ShowsEffort
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverComposerModelText.Text = composerMetadata.ModelText;
        ThreadPopoverComposerEffortText.Text = composerMetadata.EffortText;
        ApplyStopTurnActionAvailability(
            ThreadPopoverStopButton,
            ThreadPopoverStopIcon,
            StopTurnAvailability(node));
        var isComposerEnabled = status != ThreadRunStatuses.Running;
        ThreadPopoverAttachButton.IsEnabled = isComposerEnabled;
        ThreadPopoverPasteButton.IsEnabled = isComposerEnabled;
        ThreadPopoverDraftBox.IsEnabled = isComposerEnabled;
        ThreadPopoverSendButton.IsEnabled = true;
        UpdateThreadPopoverSendChrome(node);
        RefreshThreadPopoverAttachmentCount();
        RefreshThreadPopoverAttachmentError();
        UpdateThreadPopoverMentionSuggestions();
        var artifactCount = ThreadArtifacts(node).Count;
        ThreadPopoverArtifactsButton.IsEnabled = true;
        ThreadPopoverArtifactsButton.Opacity = artifactCount == 0
            ? ArtifactsActionPresentation.UnavailableOpacity
            : 1.0;
        AutomationProperties.SetHelpText(
            ThreadPopoverArtifactsButton,
            artifactCount == 0 ? ArtifactsActionPresentation.UnavailableReason : "");
        ToolTipService.SetToolTip(
            ThreadPopoverArtifactsButton,
            artifactCount == 0
                ? ArtifactsActionPresentation.UnavailableReason
                : $"{artifactCount} artifact{(artifactCount == 1 ? "" : "s")}");

        var rows = ReaderTranscriptRows(node);
        var activeCategories = ActiveThreadPopoverTranscriptCategories();
        var transcriptSession = _transcriptSessions.Snapshot(node.Id);
        var hasThreadPopoverError = !string.IsNullOrWhiteSpace(transcriptSession.Error);
        var threadPopoverTransientCounts = TranscriptTransientRows.Count(
            transcriptSession.IsLoading,
            hasThreadPopoverError);
        _threadPopoverFilters.Clear();
        foreach (var filter in ReaderTranscriptFilterItem.Build(
                     node.Id,
                     rows,
                     activeCategories,
                     includeCounts: false,
                     additionalProgressCount: threadPopoverTransientCounts.ProgressCount,
                     additionalSystemCount: threadPopoverTransientCounts.SystemCount))
        {
            _threadPopoverFilters.Add(filter);
        }
        UpdateThreadPopoverFilterChrome(rows, activeCategories);

        _threadPopoverMessages.Clear();
        foreach (var row in rows.Where(row => row.MatchesAnyCategory(activeCategories)))
        {
            _threadPopoverMessages.Add(row);
        }
        ThreadPopoverFilteredEmptyState.Visibility = rows.Count > 0 && _threadPopoverMessages.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdateThreadPopoverTranscriptState(node, rows, activeCategories);

        PositionThreadPopover(node);
        if (isNewPopoverNode)
        {
            QueueInitialThreadTranscriptLoad(node);
        }
    }

    private void UpdateThreadPopoverTitleChrome()
    {
        var presentation = ThreadHeaderIdentityActionPresentation.Resolve();
        var toolTip = _isThreadPopoverRenaming
            ? presentation.SaveToolTip
            : presentation.RenameToolTip;
        var accessibilityName = _isThreadPopoverRenaming
            ? presentation.SaveAccessibilityName
            : presentation.RenameAccessibilityName;
        ThreadPopoverTitleText.Visibility = _isThreadPopoverRenaming ? Visibility.Collapsed : Visibility.Visible;
        ThreadPopoverTitleBox.Visibility = _isThreadPopoverRenaming ? Visibility.Visible : Visibility.Collapsed;
        ThreadPopoverTitleActionIcon.Glyph = _isThreadPopoverRenaming
            ? presentation.SaveWindowsGlyph
            : presentation.RenameWindowsGlyph;
        ToolTipService.SetToolTip(ThreadPopoverTitleActionButton, toolTip);
        AutomationProperties.SetName(ThreadPopoverTitleActionButton, accessibilityName);
    }

    private void ApplyThreadAutomationPresentation(CanvasNode node)
    {
        var automation = ThreadAutomationFor(node);
        var presentation = ThreadAutomationPresentation.Resolve(automation);
        ThreadPopoverAutomationButton.Visibility = presentation.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        ThreadPopoverAutomationButton.Width = presentation.HitTargetSize;
        ThreadPopoverAutomationButton.Height = presentation.HitTargetSize;
        ThreadPopoverAutomationButton.MinWidth = 0;
        ThreadPopoverAutomationButton.MinHeight = 0;
        ThreadPopoverAutomationButton.Padding = new Thickness(0);
        ThreadPopoverAutomationButton.Background = BrushFromHex(presentation.BackgroundHex);
        ThreadPopoverAutomationButton.BorderThickness = new Thickness(presentation.BorderThickness);
        ThreadPopoverAutomationButton.Foreground = BrushFromHex(presentation.ForegroundHex);
        ThreadPopoverAutomationIcon.Glyph = presentation.WindowsGlyph;
        ThreadPopoverAutomationIcon.FontSize = presentation.IconFontSize;
        ThreadPopoverAutomationIcon.Foreground = BrushFromHex(presentation.ForegroundHex);
        ToolTipService.SetToolTip(ThreadPopoverAutomationButton, presentation.ToolTip);
        AutomationProperties.SetName(ThreadPopoverAutomationButton, presentation.AccessibilityName);
        AutomationProperties.SetHelpText(ThreadPopoverAutomationButton, presentation.AccessibilityValue);
    }

    private CodexAutomationSummary? ThreadAutomationFor(CanvasNode node)
    {
        var threadID = node.Metadata.ThreadRef?.ThreadID;
        return node.Kind == NodeKinds.CodexThread &&
            !string.IsNullOrWhiteSpace(threadID) &&
            _threadAutomationsByThreadId.TryGetValue(threadID, out var automation)
                ? automation
                : null;
    }

    private async Task ShowThreadAutomationDialogAsync(
        CanvasNode node,
        FrameworkElement? feedbackAnchor = null)
    {
        var automation = ThreadAutomationFor(node);
        if (automation is null)
        {
            const string message = "No Codex automation is linked to this thread.";
            AddActivity(message);
            ShowCommandFeedback(message, feedbackAnchor);
            return;
        }

        var current = automation;
        var titleBox = AutomationTextBox(current.Name, "Automation name", 18, bold: true);
        var promptBox = AutomationTextBox(current.Prompt, "Prompt", 13);
        promptBox.AcceptsReturn = true;
        promptBox.TextWrapping = TextWrapping.Wrap;
        promptBox.MinHeight = 112;
        promptBox.MaxHeight = 132;
        ScrollViewer.SetVerticalScrollBarVisibility(promptBox, ScrollBarVisibility.Auto);

        var statusBox = new ComboBox
        {
            MinWidth = 118,
            Items =
            {
                new ComboBoxItem { Content = "Active", Tag = CodexAutomationStatuses.Active },
                new ComboBoxItem { Content = "Paused", Tag = CodexAutomationStatuses.Paused }
            }
        };
        var frequencyBox = new ComboBox
        {
            MinWidth = 116,
            Items =
            {
                new ComboBoxItem { Content = "Daily", Tag = CodexAutomationScheduleFrequency.Daily.ToString() },
                new ComboBoxItem { Content = "Weekly", Tag = CodexAutomationScheduleFrequency.Weekly.ToString() },
                new ComboBoxItem { Content = "Custom", Tag = CodexAutomationScheduleFrequency.Custom.ToString() }
            }
        };
        var timePicker = new TimePicker
        {
            ClockIdentifier = "24HourClock",
            MinuteIncrement = 5,
            Width = 128
        };
        var rruleBox = AutomationTextBox(current.RRule, "RRULE", 12, monospace: true);
        rruleBox.MinWidth = 280;

        var runsInText = AutomationDetailValue();
        var nextRunText = AutomationDetailValue(secondary: true);
        var lastRunText = AutomationDetailValue(secondary: true);
        var intervalText = AutomationDetailValue();
        var threadTitleText = AutomationDetailValue(node.Title);
        var threadIDText = new TextBlock
        {
            Text = ShortThreadId(node.Metadata.ThreadRef?.ThreadID ?? node.Id),
            FontSize = 11,
            FontFamily = new FontFamily("Consolas"),
            Foreground = BrushFromHex("#A7B0BF"),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var errorText = new TextBlock
        {
            FontSize = 12,
            Foreground = BrushFromHex("#FF9F0A"),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed
        };

        var header = new Grid
        {
            ColumnSpacing = 10
        };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.Children.Add(new Border
        {
            Width = 28,
            Height = 28,
            CornerRadius = new CornerRadius(6),
            Background = BrushFromHex(current.IsActive
                ? ThreadAutomationPresentation.ActiveBackgroundHex
                : "#1AA7B0BF"),
            Child = new FontIcon
            {
                Glyph = ThreadAutomationPresentation.WindowsGlyph,
                FontSize = 14,
                Foreground = BrushFromHex(current.IsActive
                    ? ThreadAutomationPresentation.ActiveForegroundHex
                    : ThreadAutomationPresentation.InactiveForegroundHex)
            }
        });
        var headerText = new StackPanel
        {
            Spacing = 2
        };
        headerText.Children.Add(new TextBlock
        {
            Text = "Automations",
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#A7B0BF")
        });
        headerText.Children.Add(new TextBlock
        {
            Text = current.Name,
            FontSize = 15,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex("#F2F4F7"),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        Grid.SetColumn(headerText, 1);
        header.Children.Add(headerText);

        var scheduleRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8
        };
        scheduleRow.Children.Add(frequencyBox);
        scheduleRow.Children.Add(timePicker);
        scheduleRow.Children.Add(rruleBox);

        var detailsGrid = new Grid
        {
            ColumnSpacing = 14,
            RowSpacing = 16
        };
        for (var index = 0; index < 4; index++)
        {
            detailsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        }

        AddAutomationDetail(detailsGrid, 0, 0, "Status", statusBox);
        AddAutomationDetail(detailsGrid, 0, 1, "Runs in", runsInText);
        AddAutomationDetail(detailsGrid, 0, 2, "Next run", nextRunText);
        AddAutomationDetail(detailsGrid, 0, 3, "Last run", lastRunText);
        AddAutomationDetail(detailsGrid, 1, 0, "Chat", Stack(threadTitleText, threadIDText, spacing: 1));
        AddAutomationDetail(detailsGrid, 1, 1, "Schedule", scheduleRow, columnSpan: 2);
        AddAutomationDetail(detailsGrid, 1, 3, "Interval", intervalText);

        var detailsSurface = new Border
        {
            Padding = new Thickness(12),
            Background = BrushFromHex("#1F000000"),
            BorderBrush = BrushFromHex("#14FFFFFF"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Child = detailsGrid
        };

        var body = new StackPanel
        {
            Width = 640,
            Spacing = 14
        };
        body.Children.Add(header);
        body.Children.Add(titleBox);
        body.Children.Add(AutomationSection("Prompt", promptBox));
        body.Children.Add(errorText);
        body.Children.Add(AutomationSection("Details", detailsSurface));

        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Content = body,
            RequestedTheme = ElementTheme.Dark,
            PrimaryButtonText = "Save",
            SecondaryButtonText = "Reset",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false
        };

        void SetDraft(CodexAutomationSummary source)
        {
            current = source;
            var draft = CodexAutomationScheduleDraft.FromRRule(source.RRule);
            titleBox.Text = source.Name;
            promptBox.Text = source.Prompt;
            SelectComboBoxTag(statusBox, source.Status.ToUpperInvariant());
            SelectComboBoxTag(frequencyBox, draft.Frequency.ToString());
            timePicker.Time = new TimeSpan(draft.Hour, draft.Minute, 0);
            rruleBox.Text = source.RRule;
            errorText.Visibility = Visibility.Collapsed;
            UpdateScheduleControls();
            UpdateAutomationDialogState();
        }

        string SelectedStatus()
        {
            return (statusBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? CodexAutomationStatuses.Active;
        }

        CodexAutomationScheduleFrequency SelectedFrequency()
        {
            var tag = (frequencyBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
            return Enum.TryParse<CodexAutomationScheduleFrequency>(tag, out var frequency)
                ? frequency
                : CodexAutomationScheduleFrequency.Custom;
        }

        void ApplyScheduleControls()
        {
            var hour = Math.Clamp(timePicker.Time.Hours, 0, 23);
            var minute = Math.Clamp(timePicker.Time.Minutes, 0, 59);
            switch (SelectedFrequency())
            {
                case CodexAutomationScheduleFrequency.Daily:
                    rruleBox.Text = $"RRULE:FREQ=DAILY;BYHOUR={hour};BYMINUTE={minute}";
                    break;
                case CodexAutomationScheduleFrequency.Weekly:
                    var weeklyDays = CodexAutomationScheduleDraft.FromRRule(current.RRule).WeeklyDays;
                    if (string.IsNullOrWhiteSpace(weeklyDays))
                    {
                        weeklyDays = WeekdayCode(DateTimeOffset.Now.DayOfWeek);
                    }

                    rruleBox.Text = $"RRULE:FREQ=WEEKLY;BYHOUR={hour};BYMINUTE={minute};BYDAY={weeklyDays}";
                    break;
            }
        }

        void UpdateScheduleControls()
        {
            var isCustom = SelectedFrequency() == CodexAutomationScheduleFrequency.Custom;
            timePicker.Visibility = isCustom ? Visibility.Collapsed : Visibility.Visible;
            rruleBox.Visibility = isCustom ? Visibility.Visible : Visibility.Collapsed;
            UpdateAutomationDialogState();
        }

        void UpdateAutomationDialogState()
        {
            var draftName = titleBox.Text.Trim();
            var draftRRule = rruleBox.Text.Trim();
            var edited = new CodexAutomationSummary(
                current.Id,
                current.Kind,
                draftName.Length == 0 ? current.Name : draftName,
                promptBox.Text,
                SelectedStatus(),
                draftRRule,
                current.TargetThreadID,
                current.ExecutionEnvironment,
                current.Model,
                current.ReasoningEffort,
                current.CreatedAt,
                current.UpdatedAt,
                current.LastRunAt,
                current.ConfigurationPath);
            var hasChanges =
                !string.Equals(titleBox.Text, current.Name, StringComparison.Ordinal) ||
                !string.Equals(promptBox.Text, current.Prompt, StringComparison.Ordinal) ||
                !string.Equals(SelectedStatus(), current.Status.ToUpperInvariant(), StringComparison.Ordinal) ||
                !string.Equals(draftRRule, current.RRule, StringComparison.Ordinal);
            dialog.IsPrimaryButtonEnabled = hasChanges && draftName.Length > 0 && draftRRule.Length > 0;
            runsInText.Text = current.RunsInDisplayName;
            nextRunText.Text = AutomationDateText(edited.NextRun());
            lastRunText.Text = AutomationDateText(current.LastRunAt);
            intervalText.Text = SelectedFrequency() switch
            {
                CodexAutomationScheduleFrequency.Daily => $"Daily at {AutomationTimeText(timePicker.Time)}",
                CodexAutomationScheduleFrequency.Weekly => $"Weekly at {AutomationTimeText(timePicker.Time)}",
                _ => new CodexAutomationSchedule(draftRRule).DisplayName
            };
        }

        titleBox.TextChanged += (_, _) => UpdateAutomationDialogState();
        promptBox.TextChanged += (_, _) => UpdateAutomationDialogState();
        rruleBox.TextChanged += (_, _) => UpdateAutomationDialogState();
        statusBox.SelectionChanged += (_, _) => UpdateAutomationDialogState();
        frequencyBox.SelectionChanged += (_, _) =>
        {
            ApplyScheduleControls();
            UpdateScheduleControls();
        };
        timePicker.TimeChanged += (_, _) =>
        {
            ApplyScheduleControls();
            UpdateAutomationDialogState();
        };
        dialog.SecondaryButtonClick += (_, args) =>
        {
            args.Cancel = true;
            SetDraft(current);
        };
        dialog.PrimaryButtonClick += (_, args) =>
        {
            args.Cancel = true;
            var deferral = args.GetDeferral();
            if (!RunWindowOperation(async lease =>
            {
                try
                {
                    var saved = await SaveThreadAutomationAsync(new CodexAutomationEdit(
                        current.Id,
                        titleBox.Text.Trim(),
                        promptBox.Text,
                        SelectedStatus(),
                        rruleBox.Text.Trim()), lease);
                    if (_windowLifetime.IsCurrent(lease))
                    {
                        SetDraft(saved);
                        AddActivity($"Saved automation for {node.Title}.");
                    }
                }
                catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
                {
                }
                catch (Exception exception) when (
                    _windowLifetime.IsCurrent(lease) &&
                    (exception is IOException or UnauthorizedAccessException or CodexAutomationStoreException))
                {
                    errorText.Text = exception.Message;
                    errorText.Visibility = Visibility.Visible;
                }
                finally
                {
                    deferral.Complete();
                }
            }))
            {
                deferral.Complete();
            }
        };

        SetDraft(current);
        await dialog.ShowAsync();
    }

    private async Task<CodexAutomationSummary> SaveThreadAutomationAsync(
        CodexAutomationEdit edit,
        WindowLifetimeLease lease)
    {
        var saved = await Task.Run(
            () => _automationStore.Save(edit),
            lease.CancellationToken);
        lease.CancellationToken.ThrowIfCancellationRequested();
        await RefreshThreadAutomationsAsync(renderAfterChange: false);
        lease.CancellationToken.ThrowIfCancellationRequested();
        if (SelectedThreadNode() is { } selectedThread &&
            ThreadPopover.Visibility == Visibility.Visible)
        {
            UpdateThreadPopover(selectedThread);
        }

        UpdateChrome();
        await RenderGraphAsync();
        lease.CancellationToken.ThrowIfCancellationRequested();
        return saved;
    }

    private static TextBox AutomationTextBox(
        string text,
        string placeholder,
        double fontSize,
        bool bold = false,
        bool monospace = false)
    {
        return new TextBox
        {
            Text = text,
            PlaceholderText = placeholder,
            FontSize = fontSize,
            FontWeight = bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
            FontFamily = monospace ? new FontFamily("Consolas") : new FontFamily("Segoe UI"),
            Background = BrushFromHex("#18000000"),
            BorderBrush = BrushFromHex("#22FFFFFF"),
            Foreground = BrushFromHex("#F2F4F7"),
            PlaceholderForeground = BrushFromHex("#697586")
        };
    }

    private static TextBlock AutomationDetailValue(string text = "", bool secondary = false)
    {
        return new TextBlock
        {
            Text = text,
            FontSize = 13,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = BrushFromHex(secondary ? "#A7B0BF" : "#F2F4F7"),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
    }

    private static StackPanel AutomationSection(string title, UIElement content)
    {
        return Stack(
            new TextBlock
            {
                Text = title,
                FontSize = 11,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = BrushFromHex("#A7B0BF")
            },
            content,
            spacing: 6);
    }

    private static void AddAutomationDetail(
        Grid grid,
        int row,
        int column,
        string title,
        UIElement content,
        int columnSpan = 1)
    {
        while (grid.RowDefinitions.Count <= row)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        }

        var stack = AutomationSection(title, content);
        Grid.SetRow(stack, row);
        Grid.SetColumn(stack, column);
        if (columnSpan > 1)
        {
            Grid.SetColumnSpan(stack, columnSpan);
        }

        grid.Children.Add(stack);
    }

    private static StackPanel Stack(UIElement first, UIElement second, double spacing)
    {
        var stack = new StackPanel
        {
            Spacing = spacing
        };
        stack.Children.Add(first);
        stack.Children.Add(second);
        return stack;
    }

    private static void SelectComboBoxTag(ComboBox comboBox, string tag)
    {
        foreach (var item in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }

        if (comboBox.Items.Count > 0)
        {
            comboBox.SelectedIndex = 0;
        }
    }

    private static string AutomationDateText(DateTimeOffset? date)
    {
        return date is null
            ? "-"
            : date.Value.ToLocalTime().ToString("g", CultureInfo.CurrentCulture);
    }

    private static string AutomationTimeText(TimeSpan time)
    {
        return DateTime.Today.Add(time).ToString("t", CultureInfo.CurrentCulture);
    }

    private static string ShortThreadId(string threadID)
    {
        return threadID.Length > 14 ? $"{threadID[..8]}...{threadID[^4..]}" : threadID;
    }

    private static string WeekdayCode(DayOfWeek day)
    {
        return day switch
        {
            DayOfWeek.Sunday => "SU",
            DayOfWeek.Monday => "MO",
            DayOfWeek.Tuesday => "TU",
            DayOfWeek.Wednesday => "WE",
            DayOfWeek.Thursday => "TH",
            DayOfWeek.Friday => "FR",
            DayOfWeek.Saturday => "SA",
            _ => "MO"
        };
    }

    private void UpdateThreadPopoverTranscriptState(
        CanvasNode node,
        IReadOnlyList<ReaderTranscriptRow> rows,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories)
    {
        var transcriptSession = _transcriptSessions.Snapshot(node.Id);
        var isLoading = transcriptSession.IsLoading;
        var isLoadingOlder = transcriptSession.IsLoadingOlder;
        var showsProgress = activeCategories.Contains(ReaderTranscriptCategory.Progress);
        ThreadPopoverTranscriptLoadingBanner.Visibility = isLoading && showsProgress
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverTranscriptLoadingRing.IsActive = isLoading && showsProgress;
        var loadPhase = transcriptSession.EffectiveLoadPhase(HasLoadedThreadTranscript(node));
        var loadPresentation = TranscriptLoadPhasePresentation.Resolve(loadPhase);
        ThreadPopoverTranscriptLoadingIcon.Glyph = loadPresentation.WindowsGlyph;
        ThreadPopoverTranscriptLoadingTitle.Text = loadPresentation.Title;
        ThreadPopoverTranscriptLoadingDetail.Text = loadPresentation.Detail;
        ApplyTranscriptLoadingRowPresentation(
            ThreadPopoverTranscriptLoadingBanner,
            ThreadPopoverTranscriptLoadingGrid,
            ThreadPopoverTranscriptLoadingRing,
            ThreadPopoverTranscriptLoadingContentStack,
            ThreadPopoverTranscriptLoadingHeaderStack,
            ThreadPopoverTranscriptLoadingIcon,
            ThreadPopoverTranscriptLoadingTitle,
            ThreadPopoverTranscriptLoadingDetail,
            TranscriptLoadingRowPresentation.Resolve(HasLoadedThreadTranscript(node) || isLoadingOlder));

        var hasOlderCursor = transcriptSession.HasOlderPage;
        var loadOlderPresentation = LoadOlderMessagesActionPresentation.Resolve(hasOlderCursor, isLoadingOlder);
        ThreadPopoverLoadOlderButton.Visibility = loadOlderPresentation.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        ThreadPopoverLoadOlderButton.IsEnabled = loadOlderPresentation.IsButtonEnabled;
        ThreadPopoverLoadOlderButton.Opacity = loadOlderPresentation.Opacity;
        ThreadPopoverLoadOlderButton.MinHeight = loadOlderPresentation.ButtonMinHeight;
        ThreadPopoverLoadOlderButton.Padding = new Thickness(
            loadOlderPresentation.ButtonHorizontalPadding,
            loadOlderPresentation.ButtonVerticalPadding,
            loadOlderPresentation.ButtonHorizontalPadding,
            loadOlderPresentation.ButtonVerticalPadding);
        ToolTipService.SetToolTip(ThreadPopoverLoadOlderButton, loadOlderPresentation.ToolTip);
        AutomationProperties.SetHelpText(ThreadPopoverLoadOlderButton, loadOlderPresentation.AccessibilityHint);
        ThreadPopoverLoadOlderStack.Spacing = loadOlderPresentation.ContentSpacing;
        ThreadPopoverLoadOlderProgressRing.Width = loadOlderPresentation.ProgressRingSize;
        ThreadPopoverLoadOlderProgressRing.Height = loadOlderPresentation.ProgressRingSize;
        ThreadPopoverLoadOlderProgressRing.Visibility = loadOlderPresentation.ShowsProgress ? Visibility.Visible : Visibility.Collapsed;
        ThreadPopoverLoadOlderProgressRing.IsActive = loadOlderPresentation.ShowsProgress;
        ThreadPopoverLoadOlderIcon.FontSize = loadOlderPresentation.IdleIconFontSize;
        ThreadPopoverLoadOlderIcon.Visibility = !loadOlderPresentation.ShowsProgress && loadOlderPresentation.ShowsIdleIcon
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverLoadOlderText.Text = loadOlderPresentation.ButtonText;
        ThreadPopoverLoadOlderText.FontSize = loadOlderPresentation.TextFontSize;

        var showsSystem = activeCategories.Contains(ReaderTranscriptCategory.System);
        var hasError = !string.IsNullOrWhiteSpace(transcriptSession.Error);
        ThreadPopoverTranscriptErrorBanner.Visibility = hasError && showsSystem
            ? Visibility.Visible
            : Visibility.Collapsed;
        ThreadPopoverTranscriptErrorText.Text = transcriptSession.Error ?? "";
        UseCachedThreadPopoverTranscriptButton.Visibility = HasLoadedThreadTranscript(node)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ApplyTranscriptLoadingRowPresentation(
        Border loadingBanner,
        Grid loadingGrid,
        ProgressRing progressRing,
        StackPanel contentStack,
        StackPanel headerStack,
        FontIcon labelIcon,
        TextBlock titleText,
        TextBlock detailText,
        TranscriptLoadingRowPresentationSnapshot presentation)
    {
        loadingBanner.Padding = new Thickness(presentation.Padding);
        loadingBanner.Margin = new Thickness(0, presentation.VerticalMargin, 0, presentation.VerticalMargin);
        loadingBanner.HorizontalAlignment = LoadingRowHorizontalAlignment(presentation);
        loadingBanner.Background = BrushFromHex(presentation.BackgroundHex);
        loadingBanner.BorderBrush = BrushFromHex(presentation.BorderHex);
        loadingGrid.ColumnSpacing = presentation.OuterColumnSpacing;
        progressRing.Width = presentation.ProgressRingSize;
        progressRing.Height = presentation.ProgressRingSize;
        progressRing.Margin = new Thickness(0, presentation.ProgressRingTopMargin, 0, 0);
        contentStack.Spacing = presentation.ContentSpacing;
        headerStack.Spacing = presentation.HeaderSpacing;
        labelIcon.FontSize = presentation.LabelIconFontSize;
        titleText.FontSize = presentation.TitleFontSize;
        detailText.FontSize = presentation.DetailFontSize;
        detailText.MaxLines = presentation.DetailMaxLines;
    }

    private static HorizontalAlignment LoadingRowHorizontalAlignment(
        TranscriptLoadingRowPresentationSnapshot presentation)
    {
        return presentation.HorizontalAlignment == TranscriptLoadingRowPresentation.CenterAlignment
            ? HorizontalAlignment.Center
            : HorizontalAlignment.Left;
    }

    private static bool HasLoadedThreadTranscript(CanvasNode node)
    {
        return node.Metadata.LocalTranscript.Count > 0 ||
            node.Metadata.LocalTranscriptTurns.Count > 0;
    }

    private IReadOnlySet<ReaderTranscriptCategory> ActiveThreadPopoverTranscriptCategories()
    {
        if (_threadPopoverTranscriptFilters.Count > 0)
        {
            return _threadPopoverTranscriptFilters;
        }

        ResetThreadPopoverTranscriptFilters();
        return _threadPopoverTranscriptFilters;
    }

    private void ResetThreadPopoverTranscriptFilters()
    {
        _threadPopoverTranscriptFilters.Clear();
        foreach (var category in AllReaderTranscriptCategories())
        {
            _threadPopoverTranscriptFilters.Add(category);
        }
    }

    private void UpdateThreadPopoverFilterChrome(
        IReadOnlyList<ReaderTranscriptRow> rows,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories)
    {
        var categories = OrderedReaderTranscriptCategories();
        var selectedCategories = categories.Where(activeCategories.Contains).ToList();
        var isShowingAll = selectedCategories.Count == categories.Length;
        var summary = isShowingAll
            ? "All rows"
            : selectedCategories.Count > 2
                ? $"{selectedCategories.Count} filters"
                : string.Join(", ", selectedCategories.Select(ReaderTranscriptCategoryCompactTitle));

        ThreadPopoverFilterSummaryText.Text = string.IsNullOrWhiteSpace(summary) ? "All rows" : summary;
        ThreadPopoverFilterDetailText.Text = isShowingAll
            ? "Messages, progress, thoughts, tools, artifacts, approvals, events"
            : string.Join(", ", selectedCategories.Select(ReaderTranscriptCategoryTitle));
        ThreadPopoverFilterDetailText.Foreground =
            BrushFromHex(TranscriptFilterPresentation.DetailForegroundHex(isShowingAll));
        ThreadPopoverResetFiltersButton.Visibility = isShowingAll ? Visibility.Collapsed : Visibility.Visible;

        var counts = categories.ToDictionary(
            category => category,
            category => rows.Count(row => row.MatchesCategory(category)));
        UpdateThreadPopoverFilterItem(
            ThreadPopoverMessagesFilterItem,
            ReaderTranscriptCategory.Message,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverProgressFilterItem,
            ReaderTranscriptCategory.Progress,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverThoughtsFilterItem,
            ReaderTranscriptCategory.Thought,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverToolsFilterItem,
            ReaderTranscriptCategory.Tool,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverArtifactsFilterItem,
            ReaderTranscriptCategory.Artifact,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverApprovalsFilterItem,
            ReaderTranscriptCategory.Approval,
            counts,
            activeCategories);
        UpdateThreadPopoverFilterItem(
            ThreadPopoverSystemFilterItem,
            ReaderTranscriptCategory.System,
            counts,
            activeCategories);
    }

    private static void UpdateThreadPopoverFilterItem(
        ToggleMenuFlyoutItem item,
        ReaderTranscriptCategory category,
        IReadOnlyDictionary<ReaderTranscriptCategory, int> counts,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories)
    {
        item.Text = $"{ReaderTranscriptCategoryTitle(category)} ({counts.GetValueOrDefault(category)})";
        item.IsChecked = activeCategories.Contains(category);
    }

    private void PositionThreadPopover(CanvasNode node)
    {
        var frame = ThreadPopoverLayout.Measure(
            RootWidth(),
            RootHeight(),
            node.Position,
            node.Size,
            _graph.Viewport,
            node.Metadata.PopoverOffset);
        ThreadPopover.Width = frame.Width;
        ThreadPopover.Height = frame.Height;
        ThreadPopover.Margin = new Thickness(frame.Left, frame.Top, 0, 0);
    }

    private ThreadPopoverFrame ThreadPopoverBaseFrame(CanvasNode node)
    {
        return ThreadPopoverLayout.Measure(
            RootWidth(),
            RootHeight(),
            node.Position,
            node.Size,
            _graph.Viewport);
    }

    private double RootWidth()
    {
        return RootGrid.ActualWidth > 0 ? RootGrid.ActualWidth : 1600;
    }

    private double RootHeight()
    {
        return RootGrid.ActualHeight > 0 ? RootGrid.ActualHeight : 940;
    }

    private void UpdateThreadPopoverSize()
    {
        var size = ThreadPopoverLayout.Size(RootWidth(), RootHeight());
        ThreadPopover.Width = size.Width;
        ThreadPopover.Height = size.Height;
    }

    private double ThreadPopoverWidth()
    {
        return ThreadPopover.Width > 0 ? ThreadPopover.Width : 440;
    }

    private double ThreadPopoverHeight()
    {
        return ThreadPopover.Height > 0 ? ThreadPopover.Height : 560;
    }

    private static void ApplyThreadStatusPillPresentation(
        Border pill,
        TextBlock textBlock,
        Viewbox? icon,
        ThreadStatusPresentationSnapshot presentation)
    {
        var foreground = BrushFromHex(presentation.ForegroundHex);
        pill.MinWidth = presentation.MinWidth;
        pill.Padding = new Thickness(
            presentation.HorizontalPadding,
            presentation.VerticalPadding,
            presentation.HorizontalPadding,
            presentation.VerticalPadding);
        pill.CornerRadius = new CornerRadius(presentation.CornerRadius);
        pill.Background = BrushFromHex(presentation.BackgroundHex);
        pill.BorderBrush = BrushFromHex(presentation.BorderHex);
        pill.BorderThickness = new Thickness(presentation.BorderThickness);

        textBlock.Text = presentation.Text;
        textBlock.FontSize = presentation.TextFontSize;
        textBlock.Foreground = foreground;

        if (icon is not null)
        {
            icon.Width = presentation.IconWidth;
            icon.Height = presentation.IconHeight;
            icon.Child = ThreadStatusIconCanvas(
                presentation.IconKind,
                foreground,
                presentation.IconStrokeThickness);
        }
    }

    private static Canvas ThreadStatusIconCanvas(string iconKind, Brush foreground, double strokeThickness)
    {
        var canvas = new Canvas
        {
            Width = 14,
            Height = 14
        };

        switch (iconKind)
        {
            case ThreadStatusPresentation.CircleFillIcon:
                AddThreadStatusEllipse(canvas, foreground, 3.3, 3.3, 7.4, 7.4, filled: true, strokeThickness);
                break;
            case ThreadStatusPresentation.CheckmarkCircleIcon:
                AddThreadStatusEllipse(canvas, foreground, 1.9, 1.9, 10.2, 10.2, filled: false, strokeThickness);
                AddThreadStatusPath(canvas, "M 4.5 7.1 L 6.2 8.8 L 9.8 5", foreground, strokeThickness + 0.1);
                break;
            case ThreadStatusPresentation.XmarkOctagonIcon:
                AddThreadStatusPath(
                    canvas,
                    "M 5 1.6 L 9 1.6 L 12.4 5 L 12.4 9 L 9 12.4 L 5 12.4 L 1.6 9 L 1.6 5 Z",
                    foreground,
                    strokeThickness);
                AddThreadStatusPath(
                    canvas,
                    "M 5.1 5.1 L 8.9 8.9 M 8.9 5.1 L 5.1 8.9",
                    foreground,
                    strokeThickness);
                break;
            case ThreadStatusPresentation.ExclamationBubbleIcon:
                AddThreadStatusPath(
                    canvas,
                    "M 7 1.7 C 10.1 1.7 12.2 3.6 12.2 6.2 C 12.2 8.8 10.1 10.7 7 10.7 C 6.5 10.7 6 10.6 5.5 10.5 L 2.9 12.3 L 3.3 9.6 C 2.3 8.8 1.8 7.6 1.8 6.2 C 1.8 3.6 3.9 1.7 7 1.7 Z",
                    foreground,
                    strokeThickness);
                AddThreadStatusPath(canvas, "M 7 3.8 L 7 6.7", foreground, strokeThickness);
                AddThreadStatusEllipse(canvas, foreground, 6.35, 7.75, 1.3, 1.3, filled: true, strokeThickness);
                break;
            case ThreadStatusPresentation.ArrowTriangleCirclePathIcon:
                AddThreadStatusPath(
                    canvas,
                    "M 10.6 4.2 C 9.8 3.2 8.5 2.5 7 2.5 C 4.5 2.5 2.5 4.5 2.5 7",
                    foreground,
                    strokeThickness);
                AddThreadStatusPath(
                    canvas,
                    "M 10.3 1.9 L 10.9 4.5 L 8.3 4",
                    foreground,
                    strokeThickness);
                AddThreadStatusPath(
                    canvas,
                    "M 3.4 9.8 C 4.2 10.8 5.5 11.5 7 11.5 C 9.5 11.5 11.5 9.5 11.5 7",
                    foreground,
                    strokeThickness);
                AddThreadStatusPath(
                    canvas,
                    "M 3.7 12.1 L 3.1 9.5 L 5.7 10",
                    foreground,
                    strokeThickness);
                break;
            default:
                AddThreadStatusEllipse(canvas, foreground, 2.4, 2.4, 9.2, 9.2, filled: false, strokeThickness);
                break;
        }

        return canvas;
    }

    private static void AddThreadStatusEllipse(
        Canvas canvas,
        Brush foreground,
        double left,
        double top,
        double width,
        double height,
        bool filled,
        double strokeThickness)
    {
        var ellipse = new Microsoft.UI.Xaml.Shapes.Ellipse
        {
            Width = width,
            Height = height,
            Fill = filled ? foreground : BrushFromHex(ThreadStatusPresentation.BorderlessHex),
            Stroke = filled ? null : foreground,
            StrokeThickness = filled ? 0 : strokeThickness
        };
        Canvas.SetLeft(ellipse, left);
        Canvas.SetTop(ellipse, top);
        canvas.Children.Add(ellipse);
    }

    private static void AddThreadStatusPath(
        Canvas canvas,
        string data,
        Brush foreground,
        double strokeThickness)
    {
        var path = (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load(
            "<Path xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" " +
            $"Data=\"{data}\" />");
        path.Fill = BrushFromHex(ThreadStatusPresentation.BorderlessHex);
        path.Stroke = foreground;
        path.StrokeThickness = strokeThickness;
        path.StrokeStartLineCap = PenLineCap.Round;
        path.StrokeEndLineCap = PenLineCap.Round;
        path.StrokeLineJoin = PenLineJoin.Round;
        canvas.Children.Add(path);
    }

    private string ThreadHeaderStatusFor(CanvasNode node)
    {
        var status = node.Metadata.RunStatus ?? ThreadRunStatuses.Idle;
        return HasPendingAttention(node) || status == ThreadRunStatuses.NeedsInput
            ? ThreadRunStatuses.NeedsInput
            : status;
    }

    private StopTurnActionAvailability StopTurnAvailability(CanvasNode node)
    {
        return StopTurnActionPresentation.Availability(
            ThreadHeaderStatusFor(node),
            CanStopThread(node),
            IsStoppingThread(node));
    }

    private static bool CanStopThread(CanvasNode node)
    {
        return node.Kind == NodeKinds.CodexThread &&
            node.Metadata.RunStatus == ThreadRunStatuses.Running;
    }

    private bool IsStoppingThread(CanvasNode node)
    {
        return _stoppingThreadKeys.Contains(StopTurnKey(node));
    }

    private static string StopTurnKey(CanvasNode node)
    {
        return ThreadQualifiedID(node) ?? node.Id;
    }

    private static string ThreadRoleLabel(string role)
    {
        return role switch
        {
            _ when string.Equals(role, "assistant", StringComparison.OrdinalIgnoreCase) => "Assistant",
            _ when string.Equals(role, "user", StringComparison.OrdinalIgnoreCase) => "You",
            _ when string.Equals(role, "system", StringComparison.OrdinalIgnoreCase) => "System",
            _ => "Transcript"
        };
    }

    private void UpdateChrome()
    {
        var nodeCount = _graph.Nodes.Count;
        var edgeCount = SemanticEdgeResolver.AllEdges(_graph).Count;
        var remoteMachineNodes = RemoteMachineNodes().ToList();
        var hasMachineIssue = MachinesNeedingRecovery().Any();
        var threadCount = ThreadNodes.Count();
        var selectedThreadNode = SelectedThreadNode();
        var remoteStatus = StatusStripPresentation.Remote(remoteMachineNodes);

        var workflowPresentation = ToolbarWorkflowPresentation.Resolve();
        var workflowStroke = BrushFromHex(workflowPresentation.StrokeHex);
        WorkflowIcon.Width = workflowPresentation.IconWidth;
        WorkflowIcon.Height = workflowPresentation.IconHeight;
        WorkflowTopLeftRect.Stroke = workflowStroke;
        WorkflowTopLeftRect.StrokeThickness = workflowPresentation.StrokeThickness;
        WorkflowBottomLeftRect.Stroke = workflowStroke;
        WorkflowBottomLeftRect.StrokeThickness = workflowPresentation.StrokeThickness;
        WorkflowRightRect.Stroke = workflowStroke;
        WorkflowRightRect.StrokeThickness = workflowPresentation.StrokeThickness;
        WorkflowChevronIcon.Width = workflowPresentation.ChevronWidth;
        WorkflowChevronIcon.Height = workflowPresentation.ChevronHeight;
        WorkflowChevronPath.Stroke = BrushFromHex(workflowPresentation.ChevronStrokeHex);
        WorkflowChevronPath.StrokeThickness = workflowPresentation.ChevronStrokeThickness;
        ToolTipService.SetToolTip(WorkflowButton, workflowPresentation.ToolTip);
        AutomationProperties.SetName(WorkflowButton, workflowPresentation.DefaultTitle);
        WorkflowNameText.Text = ActiveWorkflowName();
        NodeCountText.Text = $"{nodeCount} nodes";
        LineCountText.Text = $"{edgeCount} lines";
        UpdateLocalStatusStrip();
        var remoteStatusBrush = BrushFromHex(remoteStatus.ForegroundHex);
        var usesRemoteAntennaIcon = remoteStatus.IconKind == StatusStripPresentation.RemoteAntennaIcon;
        RemoteStatusText.Text = remoteStatus.Text;
        RemoteStatusAntennaIcon.Visibility = usesRemoteAntennaIcon ? Visibility.Visible : Visibility.Collapsed;
        RemoteStatusIcon.Visibility = usesRemoteAntennaIcon ? Visibility.Collapsed : Visibility.Visible;
        RemoteStatusIcon.Glyph = remoteStatus.Glyph;
        RemoteStatusIcon.Foreground = remoteStatusBrush;
        SetRemoteStatusAntennaBrush(remoteStatusBrush);
        RemoteStatusText.Foreground = remoteStatusBrush;
        ToolTipService.SetToolTip(RemoteStatusGroup, remoteStatus.HelpText);
        ApplyThreadInboxSummaryPresentation();
        var readingPresentation = ToolbarReadingPresentation.Resolve(_readerThreadIds.Count);
        var readingStroke = BrushFromHex(readingPresentation.StrokeHex);
        ReadingModeButton.Style = ToolbarStyle(readingPresentation.StyleKey);
        ReadingModeIcon.Width = readingPresentation.IconWidth;
        ReadingModeIcon.Height = readingPresentation.IconHeight;
        ReadingModeLeftPane.BorderBrush = readingStroke;
        ReadingModeLeftPane.BorderThickness = new Thickness(readingPresentation.StrokeThickness);
        ReadingModeMiddlePane.BorderBrush = readingStroke;
        ReadingModeMiddlePane.BorderThickness = new Thickness(readingPresentation.StrokeThickness, readingPresentation.StrokeThickness, 0, readingPresentation.StrokeThickness);
        ReadingModeRightPane.BorderBrush = readingStroke;
        ReadingModeRightPane.BorderThickness = new Thickness(readingPresentation.StrokeThickness);
        ReadingModeText.Text = readingPresentation.Title;
        ToolTipService.SetToolTip(ReadingModeButton, readingPresentation.ToolTip);
        var subagentsPresentation = ToolbarSubagentsPresentation.Resolve(_showsSubagents);
        var subagentsIconBrush = BrushFromHex(subagentsPresentation.IconHex);
        SubagentsButton.Style = ToolbarStyle(subagentsPresentation.StyleKey);
        SubagentsRearPersonPath.Fill = subagentsIconBrush;
        SubagentsFrontPersonPath.Fill = subagentsIconBrush;
        SubagentsSlashLine.Stroke = BrushFromHex(subagentsPresentation.SlashHex);
        SubagentsSlashLine.StrokeThickness = subagentsPresentation.SlashStrokeThickness;
        SubagentsSlashLine.Visibility = subagentsPresentation.ShowsSlash ? Visibility.Visible : Visibility.Collapsed;
        ToolTipService.SetToolTip(SubagentsButton, subagentsPresentation.ToolTip);
        AutomationProperties.SetName(SubagentsButton, subagentsPresentation.AccessibilityName);
        var arrangePresentation = ToolbarArrangePresentation.Resolve();
        var arrangeStroke = BrushFromHex(arrangePresentation.StrokeHex);
        ArrangeTopLeftRect.Stroke = arrangeStroke;
        ArrangeBottomLeftRect.Stroke = arrangeStroke;
        ArrangeRightRect.Stroke = arrangeStroke;
        ToolTipService.SetToolTip(ArrangeButton, arrangePresentation.ToolTip);
        AutomationProperties.SetName(ArrangeButton, arrangePresentation.AccessibilityName);
        var activityPresentation = ToolbarActivityPresentation.Resolve();
        var activityForeground = BrushFromHex(activityPresentation.StrokeHex);
        ActivityIcon.Width = activityPresentation.IconWidth;
        ActivityIcon.Height = activityPresentation.IconHeight;
        ActivityBellPath.Stroke = activityForeground;
        ActivityBellPath.StrokeThickness = activityPresentation.StrokeThickness;
        ActivityBadgeDot.Fill = BrushFromHex(activityPresentation.BadgeHex);
        ActivityBadgeDot.Width = activityPresentation.BadgeSize;
        ActivityBadgeDot.Height = activityPresentation.BadgeSize;
        ActivityBadgeDot.HorizontalAlignment = HorizontalAlignment.Left;
        ActivityBadgeDot.VerticalAlignment = VerticalAlignment.Top;
        ActivityBadgeDot.Margin = new Thickness(activityPresentation.BadgeX, activityPresentation.BadgeY, 0, 0);
        AutomationProperties.SetName(ActivityButton, activityPresentation.AccessibilityName);
        AutomationProperties.SetName(ActivityIcon, activityPresentation.AccessibilityName);
        ToolTipService.SetToolTip(ActivityButton, activityPresentation.ToolTip);
        var pairingPresentation = ToolbarPairingPresentation.Resolve();
        var pairQrBrush = BrushFromHex(pairingPresentation.IconHex);
        PairQrTopLeftFinder.BorderBrush = pairQrBrush;
        PairQrTopLeftInner.Fill = pairQrBrush;
        PairQrTopRightFinder.BorderBrush = pairQrBrush;
        PairQrTopRightInner.Fill = pairQrBrush;
        PairQrBottomLeftFinder.BorderBrush = pairQrBrush;
        PairQrBottomLeftInner.Fill = pairQrBrush;
        PairQrModuleA.Fill = pairQrBrush;
        PairQrModuleB.Fill = pairQrBrush;
        PairQrModuleC.Fill = pairQrBrush;
        PairQrModuleD.Fill = pairQrBrush;
        PairQrModuleE.Fill = pairQrBrush;
        PairQrModuleF.Fill = pairQrBrush;
        PairButton.IsEnabled = pairingPresentation.IsEnabled;
        ToolTipService.SetToolTip(PairButton, pairingPresentation.ToolTip);
        AutomationProperties.SetName(PairButton, pairingPresentation.AccessibilityName);
        AutomationProperties.SetHelpText(PairButton, pairingPresentation.ToolTip);
        var searchPresentation = ToolbarSearchPresentation.Resolve(_threadInboxMode == ThreadInboxModeSearch);
        var searchStroke = BrushFromHex(searchPresentation.StrokeHex);
        SearchButton.Style = ToolbarStyle(searchPresentation.StyleKey);
        SearchLensEllipse.Stroke = searchStroke;
        SearchLensEllipse.StrokeThickness = searchPresentation.StrokeThickness;
        SearchHandleLine.Stroke = searchStroke;
        SearchHandleLine.StrokeThickness = searchPresentation.StrokeThickness;
        ToolTipService.SetToolTip(SearchButton, searchPresentation.ToolTip);
        ApplyToolbarButtonChromePresentation();
        UpdateMachinesButtonPresentation();

        UpdateCommandBarAvailability();
        UpdateChoices();
        UpdateMachineHealth();
        UpdateMachineDiscoverySections();
        UpdateReader();
        UpdateThreadInbox();
        UpdateRuntimeDiagnostics();
        UpdateReaderHeaderLayout();
        UpdateActivityRailChrome();
        UpdateActivityHistoryChrome();
        UpdateTopNotificationsChrome();
        UpdateStatusStripError();

        MachinesRail.Visibility = _isMachinesRailVisible && _isMachinesFlyoutOpen
            ? Visibility.Visible
            : Visibility.Collapsed;
        MachinesRailContent.Visibility = _isMachinesRailCollapsed ? Visibility.Collapsed : Visibility.Visible;
        MaybeStartInitialMachineDiscovery();
        if (_isReadingModePresented && _isMachinesFlyoutOpen)
        {
            _machinesFlyout?.Hide();
        }

        MachineConnectForm.Visibility = !_isMachinesRailCollapsed && _isMachineConnectFormVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        MachineConnectFormToggleIcon.Glyph = _isMachineConnectFormVisible ? "\uE711" : "\uE710";
        ToolTipService.SetToolTip(AddMachineButton, _isMachineConnectFormVisible ? "Close add remote form" : "Add remote");
        CloseMachinesRailIcon.Glyph = "\uE711";
        ToolTipService.SetToolTip(CloseMachinesRailButton, "Close");
        MachineRecoveryRail.Visibility = MachineRecoveryPresentation.ShouldShowRail(
            _isMachineRecoveryVisible,
            _machineRecoveryItems.Count)
                ? Visibility.Visible
                : Visibility.Collapsed;
        ActivityRail.Visibility = Visibility.Collapsed;
        ActivityRailContent.Visibility = _isActivityRailCollapsed ? Visibility.Collapsed : Visibility.Visible;
        ActivityRailCollapseIcon.Glyph = _isActivityRailCollapsed ? "\uE70D" : "\uE70E";
        ToolTipService.SetToolTip(CloseActivityRailButton, _isActivityRailCollapsed ? "Expand" : "Minimize");
        ActivityPopover.Visibility = !_isReadingModePresented && _isActivityHistoryVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        AttentionRail.Visibility = !_isReadingModePresented && _threadAttentionItems.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        AttentionRailContent.Visibility = _isAttentionRailCollapsed ? Visibility.Collapsed : Visibility.Visible;
        AttentionRailCollapseIcon.Glyph = _isAttentionRailCollapsed ? "\uE70D" : "\uE70E";
        ToolTipService.SetToolTip(AttentionRailCollapseButton, _isAttentionRailCollapsed ? "Expand" : "Minimize");
        RuntimeDiagnosticsRail.Visibility = !_isReadingModePresented && _runtimeDiagnosticItems.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        RuntimeDiagnosticsRailContent.Visibility = _isRuntimeDiagnosticsCollapsed ? Visibility.Collapsed : Visibility.Visible;
        RuntimeDiagnosticsRailCollapseIcon.Glyph = _isRuntimeDiagnosticsCollapsed ? "\uE70D" : "\uE70E";
        ToolTipService.SetToolTip(RuntimeDiagnosticsRailCollapseButton, _isRuntimeDiagnosticsCollapsed ? "Expand" : "Minimize");
        ReaderDock.Visibility = _isReadingModePresented ? Visibility.Visible : Visibility.Collapsed;
        if (_isReadingModePresented)
        {
            HealthPopover.Visibility = Visibility.Collapsed;
            PairingPopover.Visibility = Visibility.Collapsed;
            WorkflowNamePopover.Visibility = Visibility.Collapsed;
            _workflowNameEditorMode = null;
            _isActivityHistoryVisible = false;
            ActivityPopover.Visibility = Visibility.Collapsed;
            TopNotificationStack.Visibility = Visibility.Collapsed;
            CommandFeedbackBubble.Visibility = Visibility.Collapsed;
        }

        CommandBarSurface.Visibility = _isReadingModePresented ? Visibility.Collapsed : Visibility.Visible;
        ThreadInboxRail.Visibility = _isReadingModePresented ? Visibility.Collapsed : Visibility.Visible;
        StatusStripSurface.Visibility = _isReadingModePresented ? Visibility.Collapsed : Visibility.Visible;
        var hasOperationalRailContent =
            MachineRecoveryRail.Visibility == Visibility.Visible ||
            ActivityRail.Visibility == Visibility.Visible ||
            AttentionRail.Visibility == Visibility.Visible ||
            RuntimeDiagnosticsRail.Visibility == Visibility.Visible;
        OperationalRailsScroll.Visibility = !_isReadingModePresented && hasOperationalRailContent
            ? Visibility.Visible
            : Visibility.Collapsed;
        OperationalRails.Visibility = OperationalRailsScroll.Visibility;
        if (!_isReadingModePresented && selectedThreadNode is not null)
        {
            UpdateThreadPopover(selectedThreadNode);
        }

        ThreadPopover.Visibility = !_isReadingModePresented && selectedThreadNode is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
        var selectedNodeAllowsInspector = _selectedNodeId is not null &&
            _graph.Nodes.TryGetValue(_selectedNodeId, out var selectedInspectorNode) &&
            ShouldShowSelectionInspector(selectedInspectorNode);
        SelectionInspector.Visibility = _isReadingModePresented ||
            selectedThreadNode is not null ||
            (!selectedNodeAllowsInspector && _selectedEdgeId is null)
            ? Visibility.Collapsed
            : SelectionInspector.Visibility;
        if (_selectedEdgeId is not null && _graph.ManualEdges.ContainsKey(_selectedEdgeId))
        {
            ApplySelectionInspectorLayout(SelectionInspectorLayout.ForEdge());
        }
        else
        {
            ApplySelectionInspectorLayout(SelectionInspectorLayout.ForNode());
        }
        if (ArtifactsPopover.Visibility == Visibility.Visible && _artifactCatalog.SourceId is { } artifactSourceId)
        {
            if (_graph.Nodes.TryGetValue(artifactSourceId, out var artifactNode) &&
                artifactNode.Kind == NodeKinds.CodexThread)
            {
                _artifactCatalog.Replace(artifactNode.Id, ThreadArtifacts(artifactNode));
                ArtifactsSubtitleText.Text =
                    $"{artifactNode.Title} - {_artifactCatalog.Count} artifact{(_artifactCatalog.Count == 1 ? "" : "s")}";
                RefreshArtifactItems();
            }
            else
            {
                ArtifactsPopover.Visibility = Visibility.Collapsed;
                _artifactCatalog.ClearSource();
                CloseArtifactPreview();
            }
        }

        UpdateThreadInboxChrome();
    }

    private void UpdateReaderHeaderLayout()
    {
        if (!_isViewInitialized)
        {
            return;
        }

        var width = RootGrid.ActualWidth > 0 ? RootGrid.ActualWidth : 1180;
        var layout = ReaderHeaderLayout.Measure(width);

        ReaderDockHeader.Padding = new Thickness(
            layout.HorizontalPadding,
            layout.VerticalPadding,
            layout.RightPadding,
            layout.VerticalPadding);
        ReaderDockHeader.ColumnSpacing = layout.HeaderSpacing;
        ReaderTitleText.FontSize = layout.TitleFontSize;
        ReaderTitleText.FontWeight = string.Equals(layout.TitleFontWeightName, "SemiBold", StringComparison.OrdinalIgnoreCase)
            ? Microsoft.UI.Text.FontWeights.SemiBold
            : Microsoft.UI.Text.FontWeights.Normal;
        ReaderSummaryText.Visibility = layout.ShowsSummary ? Visibility.Visible : Visibility.Collapsed;
        ReaderAddLabelText.Visibility = layout.ShowsAddLabel ? Visibility.Visible : Visibility.Collapsed;
        ReaderCandidateBox.Width = layout.CandidateWidth;
        ClearReaderThreadsText.Visibility = layout.UsesIconOnlyClearButton ? Visibility.Collapsed : Visibility.Visible;
        ClearReaderThreadsButton.Width = layout.UsesIconOnlyClearButton ? layout.ClearButtonWidth : double.NaN;
        ClearReaderThreadsButton.Height = layout.UsesIconOnlyClearButton ? layout.ClearButtonHeight : double.NaN;
        ClearReaderThreadsButton.Padding = new Thickness(
            layout.ClearButtonHorizontalPadding,
            layout.ClearButtonVerticalPadding,
            layout.ClearButtonHorizontalPadding,
            layout.ClearButtonVerticalPadding);
        ToolTipService.SetToolTip(
            ClearReaderThreadsButton,
            layout.ClearButtonToolTip);
    }

    private Style ToolbarStyle(string key)
    {
        return RootGrid.Resources[key] as Style
            ?? throw new InvalidOperationException($"Missing toolbar style: {key}");
    }

    private CanvasNode? SelectedThreadNode()
    {
        if (_selectedNodeId is null ||
            !_graph.Nodes.TryGetValue(_selectedNodeId, out var node) ||
            node.Kind != NodeKinds.CodexThread)
        {
            return null;
        }

        return node;
    }

    private CanvasNode? SelectedMachineNode()
    {
        if (_selectedNodeId is null ||
            !_graph.Nodes.TryGetValue(_selectedNodeId, out var node) ||
            node.Kind != NodeKinds.Machine)
        {
            return null;
        }

        return node;
    }

    private CanvasNode? LocalMachineNode()
    {
        return MachineNodes.FirstOrDefault(node => IsLocalHostId(node.Metadata.HostID));
    }

    private void UpdateMachinesButtonPresentation()
    {
        var isBusy = _isSettingUpLocalMachine || IsMachineHealthRefreshRunning;
        var needsSetup = ShouldShowLocalMachineSetupRow();
        var needsAttention = needsSetup || MachinesNeedingRecovery().Any() || HasRemoteDiagnosticsAttention();
        var iconHex = isBusy
            ? "#6AB7FF"
            : needsAttention
                ? "#FF9F0A"
                : "#D7DCE5";
        var iconBrush = BrushFromHex(iconHex);
        MachinesButtonUnitTop.Stroke = iconBrush;
        MachinesButtonUnitMiddle.Stroke = iconBrush;
        MachinesButtonUnitBottom.Stroke = iconBrush;
        MachinesButtonIndicatorTop.Fill = iconBrush;
        MachinesButtonIndicatorMiddle.Fill = iconBrush;
        MachinesButtonIndicatorBottom.Fill = iconBrush;
        MachinesButtonStatusGlyph.Visibility = isBusy || needsAttention ? Visibility.Visible : Visibility.Collapsed;
        MachinesButtonStatusGlyph.Glyph = isBusy ? "\uE895" : "\uE7BA";
        MachinesButtonStatusGlyph.Foreground = iconBrush;
        MachinesButton.BorderBrush = needsAttention
            ? BrushFromHex("#66FF9F0A")
            : BrushFromHex(ToolbarButtonChromePresentation.BorderedBorderHex);
        MachinesButton.Foreground = needsAttention
            ? iconBrush
            : BrushFromHex(ToolbarButtonChromePresentation.BorderedForegroundHex);
        ToolTipService.SetToolTip(
            MachinesButton,
            needsSetup
                ? "Set up local Codex and machine connections"
                : needsAttention
                    ? "Open machine setup and recovery"
                    : "Open machine setup and connections");
    }

    private void UpdateCommandBarAvailability()
    {
        var folderUnavailableReason = CreateFolderUnavailableReason;
        var folderAvailability = ToolbarFeedbackButtonPresentation.Resolve(
            folderUnavailableReason,
            AddFolderToolTip());
        AddFolderButton.IsEnabled = true;
        AddFolderButton.Opacity = folderAvailability.Opacity;
        ToolTipService.SetToolTip(AddFolderButton, folderAvailability.ToolTip);
        AutomationProperties.SetHelpText(AddFolderButton, folderAvailability.AccessibilityHint);
        AutomationProperties.SetItemStatus(AddFolderButton, folderAvailability.AccessibilityValue);

        var threadUnavailableReason = CreateThreadUnavailableReason;
        var threadAvailability = ToolbarFeedbackButtonPresentation.Resolve(
            threadUnavailableReason,
            "Create Codex thread");
        AddThreadButton.IsEnabled = true;
        AddThreadButton.Opacity = threadAvailability.Opacity;
        ToolTipService.SetToolTip(AddThreadButton, threadAvailability.ToolTip);
        AutomationProperties.SetHelpText(AddThreadButton, threadAvailability.AccessibilityHint);
        AutomationProperties.SetItemStatus(AddThreadButton, threadAvailability.AccessibilityValue);
    }

    private bool ShouldShowLocalMachineSetupRow()
    {
        var localMachine = LocalMachineNode();
        return localMachine is null ||
            localMachine.Metadata.HostStatus != HostStatuses.Connected ||
            !HasUsableLocalAppServerEndpoint(localMachine);
    }

    private bool HasUsableLocalAppServerEndpoint(CanvasNode localMachine)
    {
        return TryGetUsableLocalAppServerEndpoint(localMachine, out _);
    }

    private bool TryGetUsableLocalAppServerEndpoint(CanvasNode localMachine, out AppServerEndpoint endpoint)
    {
        if (_connectedAppServerEndpointsByHostId.TryGetValue(localMachine.Id, out var cachedEndpoint) ||
            _connectedAppServerEndpointsByHostId.TryGetValue(LocalHostIdentity.CanonicalHostID, out cachedEndpoint) ||
            _connectedAppServerEndpointsByHostId.TryGetValue(LocalHostIdentity.LocalMachineNodeID, out cachedEndpoint))
        {
            endpoint = cachedEndpoint;
            return true;
        }

        if (localMachine.Metadata.HostStatus == HostStatuses.Connected &&
            !string.IsNullOrWhiteSpace(localMachine.Metadata.AppServerEndpointUrl) &&
            Uri.TryCreate(localMachine.Metadata.AppServerEndpointUrl, UriKind.Absolute, out var url) &&
            AppServerEndpointValidator.IsLoopback(url))
        {
            endpoint = new AppServerEndpoint(localMachine.Title, url, null);
            RegisterLocalAppServerEndpoint(endpoint);
            return true;
        }

        endpoint = new AppServerEndpoint("", new Uri("ws://127.0.0.1"), null);
        return false;
    }

    private bool HasRemoteDiagnosticsAttention()
    {
        return _codexRemoteDiagnostics.Values.Any(steps =>
            steps.Any(step =>
                step.Status == RuntimeDiagnosticStatuses.Failed ||
                step.Status == RuntimeDiagnosticStatuses.Warning ||
                step.Status == RuntimeDiagnosticStatuses.Running));
    }

    private string AddFolderToolTip()
    {
        if (SelectedMachineNode() is { } machine && !IsLocalHostId(machine.Metadata.HostID))
        {
            return "Add a project folder from the selected remote machine";
        }

        return "Add a folder to the workflow";
    }

    private void ShowCommandFeedback(string message, FrameworkElement? anchor = null)
    {
        RunWindowOperation(lease => ShowCommandFeedbackAsync(message, anchor, lease));
    }

    private async Task ShowCommandFeedbackAsync(
        string message,
        FrameworkElement? anchor,
        WindowLifetimeLease lease)
    {
        var token = ++_commandFeedbackToken;
        CommandFeedbackText.Text = message;
        UpdateCommandFeedbackPlacement(anchor);
        CommandFeedbackBubble.Visibility = Visibility.Visible;
        CommandFeedbackBubble.Opacity = 1.0;

        try
        {
            await Task.Delay(2200, lease.CancellationToken);
        }
        catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
        {
            return;
        }

        if (!_windowLifetime.IsCurrent(lease) || token != _commandFeedbackToken)
        {
            return;
        }

        CommandFeedbackBubble.Visibility = Visibility.Collapsed;
    }

    private void UpdateCommandFeedbackPlacement(FrameworkElement? anchor = null)
    {
        var layout = CommandFeedbackLayoutForAnchor(anchor);
        ApplyCommandFeedbackLayout(layout);
        CommandFeedbackBubble.Margin = new Thickness(
            layout.LeftInset,
            layout.TopInset,
            0,
            0);
    }

    private CommandFeedbackLayoutMetrics CommandFeedbackLayoutForAnchor(FrameworkElement? anchor)
    {
        if (anchor is null || anchor.ActualWidth <= 0)
        {
            return CommandFeedbackLayout.Measure();
        }

        try
        {
            var origin = anchor
                .TransformToVisual(RootGrid)
                .TransformPoint(new Point(0, 0));
            return CommandFeedbackLayout.MeasureAnchored(
                origin.X,
                origin.Y,
                anchor.ActualWidth,
                anchor.ActualHeight,
                RootWidth());
        }
        catch (ArgumentException)
        {
            return CommandFeedbackLayout.Measure();
        }
    }

    private async Task RefreshWorkflowMenuAsync()
    {
        var records = await _store.LoadWorkflowsAsync();
        _workflowMenuItems.Clear();
        foreach (var record in records)
        {
            _workflowMenuItems.Add(new WorkflowMenuItem(
                record.ID,
                record.Name,
                $"{record.NodeCount} node{(record.NodeCount == 1 ? "" : "s")} - {record.LineCount} line{(record.LineCount == 1 ? "" : "s")}",
                $"Updated {record.UpdatedAt.ToLocalTime():g}",
                record.IsActive));
        }

    }

    private void UpdateMachineHealth()
    {
        var machines = MachineNodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase).ToList();
        _machineHealthItems.Clear();
        foreach (var machine in machines)
        {
            _machineHealthItems.Add(MachineHealthItem.FromNode(
                machine,
                IsLocalHostId(machine.Metadata.HostID),
                TryFindCodexRemoteForMachine(machine, out _),
                string.Equals(_expandedMachineHealthItemId, machine.Id, StringComparison.Ordinal)));
        }

        var connected = machines.Count(node => node.Metadata.HostStatus == HostStatuses.Connected);
        var recoveryTargets = MachinesNeedingRecovery().ToList();
        _machineRecoveryItems.Clear();
        foreach (var target in recoveryTargets)
        {
            _machineRecoveryItems.Add(MachineRecoveryItem.FromNode(target));
        }

        HealthPopoverSubtitle.Text = $"{machines.Count} machine{(machines.Count == 1 ? "" : "s")} - {connected} connected";
        HealthSummaryText.Text = _lastDiagnosticsSummary;
        HealthDetailText.Text = _lastDiagnosticsDetail;
        UpdateLocalMachineSetupRow();
        UpdateConnectionRefreshRow();
        MachineRecoveryToggleText.Text = _isMachineRecoveryVisible ? "Hide Machine Recovery" : "Show Machine Recovery";
        RecoveryActionCountText.Text = $"{recoveryTargets.Count} action{(recoveryTargets.Count == 1 ? "" : "s")}";
        RecoveryEmptyText.Visibility = MachineRecoveryPresentation.Rail().ShowsEmptyState && recoveryTargets.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void UpdateLocalMachineSetupRow()
    {
        var localMachine = LocalMachineNode();
        var shouldShow = ShouldShowLocalMachineSetupRow();
        LocalMachineSetupRow.Visibility = shouldShow ? Visibility.Visible : Visibility.Collapsed;
        SetupLocalMachineButton.IsEnabled = !_isSettingUpLocalMachine;
        SetupLocalMachineButton.Opacity = _isSettingUpLocalMachine ? 0.64 : 1.0;

        if (_isSettingUpLocalMachine)
        {
            LocalMachineSetupIcon.Glyph = "\uE895";
            LocalMachineSetupIcon.Foreground = BrushFromHex("#6AB7FF");
            SetupLocalMachineButtonIcon.Glyph = "\uE895";
            SetupLocalMachineButtonText.Text = "Starting Local Codex";
            LocalMachineSetupStatusText.Text = _lastLocalSetupDetail ?? "Starting local Codex App Server...";
            return;
        }

        if (localMachine is null)
        {
            LocalMachineSetupIcon.Glyph = "\uE977";
            LocalMachineSetupIcon.Foreground = BrushFromHex("#FF9F0A");
            SetupLocalMachineButtonIcon.Glyph = "\uE768";
            SetupLocalMachineButtonText.Text = "Add Local Machine";
            LocalMachineSetupStatusText.Text = "Add this PC to the workflow and start local Codex App Server.";
            return;
        }

        if (localMachine.Metadata.HostStatus == HostStatuses.Unavailable)
        {
            LocalMachineSetupIcon.Glyph = "\uE7BA";
            LocalMachineSetupIcon.Foreground = BrushFromHex("#FF9F0A");
            SetupLocalMachineButtonIcon.Glyph = "\uE72C";
            SetupLocalMachineButtonText.Text = "Retry Local Codex";
            LocalMachineSetupStatusText.Text = _lastLocalSetupDetail
                ?? localMachine.Metadata.HostLastError
                ?? "Local Codex setup needs attention.";
            return;
        }

        if (localMachine.Metadata.HostStatus == HostStatuses.Connected)
        {
            LocalMachineSetupIcon.Glyph = "\uE7BA";
            LocalMachineSetupIcon.Foreground = BrushFromHex("#FF9F0A");
            SetupLocalMachineButtonIcon.Glyph = "\uE768";
            SetupLocalMachineButtonText.Text = "Finish Local Setup";
            LocalMachineSetupStatusText.Text = "Connected machine node found; start the local App Server route.";
            return;
        }

        LocalMachineSetupIcon.Glyph = "\uE977";
        LocalMachineSetupIcon.Foreground = BrushFromHex("#FF9F0A");
        SetupLocalMachineButtonIcon.Glyph = "\uE768";
        SetupLocalMachineButtonText.Text = "Start Local Codex";
        LocalMachineSetupStatusText.Text = _lastLocalSetupDetail
            ?? "Start the local Codex App Server and register this PC.";
    }

    private void UpdateConnectionRefreshRow()
    {
        var shouldShow = ShouldShowConnectionRefreshRow();
        ConnectionRefreshRow.Visibility = shouldShow ? Visibility.Visible : Visibility.Collapsed;
        var isRefreshing = IsMachineHealthRefreshRunning;
        var foreground = isRefreshing
            ? ThreadInboxPresentation.BlueHex
            : shouldShow
                ? ThreadInboxPresentation.OrangeHex
                : ThreadInboxPresentation.SecondaryHex;
        ConnectionRefreshIcon.Glyph = isRefreshing ? "\uE895" : "\uE72C";
        ConnectionRefreshIcon.Foreground = BrushFromHex(foreground);
        RefreshConnectionsButton.IsEnabled = !isRefreshing;
        RefreshConnectionsButton.Opacity = isRefreshing ? 0.64 : 1.0;
        RefreshConnectionsButtonIcon.Glyph = isRefreshing ? "\uE895" : "\uE72C";
        RefreshConnectionsButtonText.Text = isRefreshing ? "Refreshing Connections" : "Refresh Connections";
        var detail = ConnectionRefreshDetail();
        ConnectionRefreshStatusText.Text = detail;
        ToolTipService.SetToolTip(RefreshConnectionsButton, detail);
        AutomationProperties.SetHelpText(RefreshConnectionsButton, detail);
    }

    private bool ShouldShowConnectionRefreshRow()
    {
        return IsMachineHealthRefreshRunning ||
            _localRuntimeStatus != HostStatuses.Connected ||
            MachineNodes.Any(MachineNeedsConnectionRefresh) ||
            HasRemoteDiagnosticsAttention();
    }

    private string ConnectionRefreshDetail()
    {
        if (IsMachineHealthRefreshRunning)
        {
            return "Checking local runtime, saved routes, and discovered Codex remotes.";
        }

        if (_localRuntimeStatus != HostStatuses.Connected)
        {
            return "Local App Server is not connected.";
        }

        var recoveryCount = MachineNodes.Count(MachineNeedsConnectionRefresh);
        if (recoveryCount > 0)
        {
            return $"{recoveryCount} machine route{(recoveryCount == 1 ? "" : "s")} need attention.";
        }

        if (HasRemoteDiagnosticsAttention())
        {
            return "Remote diagnostics need attention.";
        }

        return "Refresh local and remote machine routes.";
    }

    private static bool MachineNeedsConnectionRefresh(CanvasNode machine)
    {
        return machine.Metadata.HostStatus != HostStatuses.Connected ||
            !string.IsNullOrWhiteSpace(machine.Metadata.HostLastError);
    }

    private void UpdateMachineDiscoverySections()
    {
        var remoteMachines = MachineNodes
            .Where(node => !IsLocalHostId(node.Metadata.HostID))
            .OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();
        var knownCodexRemoteKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var knownTailnetKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var discoveredCodexRemoteKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var remote in _discoveredCodexRemotes)
        {
            AddDiscoveryKeys(discoveredCodexRemoteKeys, CodexRemoteDiscoveryKeys(remote));
        }

        _codexRemoteItems.Clear();
        foreach (var machine in remoteMachines.Where(IsKnownCodexRemote))
        {
            var machineKeys = ExpandedDiscoveryKeys([machine.Title, machine.Subtitle, machine.Metadata.HostID, machine.Metadata.AppServerEndpointUrl])
                .ToList();
            if (machineKeys.Any(key => discoveredCodexRemoteKeys.Contains(key)))
            {
                continue;
            }

            _codexRemoteItems.Add(RemoteDiscoveryItem.FromMachine(machine, "ssh"));
            foreach (var key in machineKeys)
            {
                knownCodexRemoteKeys.Add(key);
            }
        }

        foreach (var remote in _discoveredCodexRemotes)
        {
            var keys = ExpandedDiscoveryKeys(CodexRemoteDiscoveryKeys(remote)).ToList();
            if (keys.Any(key => knownCodexRemoteKeys.Contains(key)))
            {
                continue;
            }

            var item = RemoteDiscoveryItem.FromCodexRemote(remote);
            ApplyCodexRemoteDiagnostics(item);
            _codexRemoteItems.Add(item);
            foreach (var key in keys)
            {
                knownCodexRemoteKeys.Add(key);
            }
        }

        _tailnetMachineItems.Clear();
        foreach (var machine in remoteMachines.Where(IsKnownTailnetMachine))
        {
            _tailnetMachineItems.Add(RemoteDiscoveryItem.FromMachine(machine, "tailnet"));
            AddDiscoveryKeys(
                knownTailnetKeys,
                [machine.Title, machine.Subtitle, machine.Metadata.HostID, machine.Metadata.AppServerEndpointUrl]);
        }

        foreach (var machine in _discoveredTailnetMachines)
        {
            var keys = ExpandedDiscoveryKeys(TailnetDiscoveryKeys(machine)).ToList();
            if (keys.Any(key => knownTailnetKeys.Contains(key)))
            {
                continue;
            }

            var item = RemoteDiscoveryItem.FromTailnetMachine(machine);
            _tailnetMachineItems.Add(item);
            foreach (var key in keys)
            {
                knownTailnetKeys.Add(key);
            }
        }

        var codexRemoteMessage = _codexRemoteDiscoveryMessage;
        if (string.IsNullOrWhiteSpace(codexRemoteMessage) && _codexRemoteItems.Count == 0)
        {
            codexRemoteMessage = "Use Discover to find Codex-managed SSH remotes.";
        }

        var codexPresentation = MachineDiscoverySectionPresentation.Resolve(
            _codexRemoteItems.Count,
            _isDiscoveringCodexRemotes,
            "remote",
            "remotes",
            codexRemoteMessage);
        CodexRemotesCountText.Text = codexPresentation.CountText;
        CodexRemotesCountText.Visibility = codexPresentation.ShowsCount ? Visibility.Visible : Visibility.Collapsed;
        CodexRemotesMessageText.Text = codexRemoteMessage ?? "";
        CodexRemotesMessageFrame.Visibility = codexPresentation.ShowsMessage ? Visibility.Visible : Visibility.Collapsed;
        CodexRemotesContent.Visibility = _isCodexRemotesCollapsed ? Visibility.Collapsed : Visibility.Visible;
        CodexRemotesCollapseIcon.Glyph = _isCodexRemotesCollapsed ? "\uE70D" : "\uE70E";
        ToolTipService.SetToolTip(
            CodexRemotesCollapseIcon,
            _isCodexRemotesCollapsed ? "Expand Codex Remotes" : "Collapse Codex Remotes");

        var tailnetMessage = _tailnetDiscoveryMessage;
        if (string.IsNullOrWhiteSpace(tailnetMessage) && _tailnetMachineItems.Count == 0)
        {
            tailnetMessage = "Use Discover to find Tailscale machines on this tailnet.";
        }

        var tailnetPresentation = MachineDiscoverySectionPresentation.Resolve(
            _tailnetMachineItems.Count,
            _isDiscoveringTailnet,
            "machine",
            "machines",
            tailnetMessage);
        TailnetCountText.Text = tailnetPresentation.CountText;
        TailnetCountText.Visibility = tailnetPresentation.ShowsCount ? Visibility.Visible : Visibility.Collapsed;
        TailnetMessageText.Text = tailnetMessage ?? "";
        TailnetMessageFrame.Visibility = tailnetPresentation.ShowsMessage ? Visibility.Visible : Visibility.Collapsed;
        TailnetContent.Visibility = _isTailnetCollapsed ? Visibility.Collapsed : Visibility.Visible;
        TailnetCollapseIcon.Glyph = _isTailnetCollapsed ? "\uE70D" : "\uE70E";
        ToolTipService.SetToolTip(
            TailnetCollapseIcon,
            _isTailnetCollapsed ? "Expand Tailnet" : "Collapse Tailnet");
        var isDiscoveringMachines = _isDiscoveringCodexRemotes || _isDiscoveringTailnet;
        DiscoverMachinesButton.IsEnabled = !isDiscoveringMachines;
        DiscoverMachinesButton.Opacity = isDiscoveringMachines ? 0.6 : 1.0;
        DiscoverMachinesIcon.Glyph = isDiscoveringMachines ? "\uE895" : "\uE72C";
        ToolTipService.SetToolTip(
            DiscoverMachinesButton,
            isDiscoveringMachines ? "Discovering machines" : "Discover Codex remotes and tailnet machines");

        static void AddDiscoveryKeys(HashSet<string> keys, IEnumerable<string?> values)
        {
            foreach (var key in ExpandedDiscoveryKeys(values))
            {
                keys.Add(key);
            }
        }

        static IEnumerable<string> ExpandedDiscoveryKeys(IEnumerable<string?> values)
        {
            foreach (var value in values)
            {
                var key = DiscoveryKey(value);
                if (key is not null)
                {
                    yield return key;
                }

                var endpointKey = EndpointHostKey(value);
                if (endpointKey is not null)
                {
                    yield return endpointKey;
                }
            }
        }
    }

    private static IEnumerable<string?> CodexRemoteDiscoveryKeys(CodexDesktopRemote remote)
    {
        yield return remote.Id;
        yield return remote.HostID;
        yield return remote.DisplayName;
        yield return remote.Hostname;
    }

    private static IEnumerable<string?> TailnetDiscoveryKeys(TailnetMachine machine)
    {
        yield return machine.Id;
        yield return machine.Name;
        yield return machine.DnsName;
        yield return machine.SuggestedWebSocketEndpoint();
        foreach (var address in machine.Addresses)
        {
            yield return address;
        }
    }

    private void ApplyCodexRemoteDiagnostics(RemoteDiscoveryItem item)
    {
        if (!item.IsCodexRemote)
        {
            return;
        }

        item.IsBusy = _codexRemoteOperationIds.Contains(item.RemoteId);
        item.ApplyCodexRemoteActionPresentation();

        var diagnostics = _codexRemoteDiagnostics.TryGetValue(item.RemoteId, out var steps)
            ? steps
            : [];
        item.ApplyCodexRemoteDiagnosticsSummary(diagnostics);
    }

    private static string? DiscoveryKey(string? value)
    {
        var key = value?.Trim().Trim('.').ToLowerInvariant();
        return string.IsNullOrWhiteSpace(key) ? null : key;
    }

    private static string? EndpointHostKey(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            !Uri.TryCreate(value.Trim(), UriKind.Absolute, out var uri))
        {
            return null;
        }

        return DiscoveryKey(uri.Host);
    }

    private static bool IsKnownCodexRemote(CanvasNode machine)
    {
        return !string.IsNullOrWhiteSpace(machine.Metadata.AppServerEndpointUrl) ||
            !string.IsNullOrWhiteSpace(machine.Metadata.CodexHome) ||
            machine.Metadata.HostStatus == HostStatuses.Connected;
    }

    private static bool IsKnownTailnetMachine(CanvasNode machine)
    {
        var values = new[]
        {
            machine.Metadata.HostID,
            machine.Title,
            machine.Subtitle,
            machine.Metadata.AppServerEndpointUrl
        };

        return values.Any(value =>
            !string.IsNullOrWhiteSpace(value) &&
            (value.Contains(".tail", StringComparison.OrdinalIgnoreCase) ||
             value.Contains("tailscale", StringComparison.OrdinalIgnoreCase) ||
             value.StartsWith("100.", StringComparison.OrdinalIgnoreCase) ||
             value.StartsWith("fd7a:", StringComparison.OrdinalIgnoreCase)));
    }

    private void UpdateRuntimeDiagnostics()
    {
        _runtimeDiagnosticItems.Clear();
        foreach (var step in _graph.RuntimeDiagnostics)
        {
            _runtimeDiagnosticItems.Add(RuntimeDiagnosticItem.FromStep(step));
        }
    }

    private IEnumerable<CanvasNode> MachinesNeedingRecovery()
    {
        return MachineNodes.Where(node =>
            MachineRecoveryPolicy.NeedsRecovery(node, IsLocalHostId(node.Metadata.HostID)));
    }

    private string HealthSummary()
    {
        var machines = MachineNodes.ToList();
        var connected = machines.Count(node => node.Metadata.HostStatus == HostStatuses.Connected);
        var recovery = MachinesNeedingRecovery().Count();
        return $"{connected}/{machines.Count} machine{(machines.Count == 1 ? "" : "s")} connected, {recovery} recovery target{(recovery == 1 ? "" : "s")}.";
    }

    private IEnumerable<CanvasNode> RemoteMachineNodes()
    {
        return MachineNodes.Where(node => !IsLocalHostId(node.Metadata.HostID));
    }

    private List<RuntimeDiagnosticStep> BuildRuntimeDiagnosticSteps()
    {
        var codexPath = FindExecutableOnPath("codex");
        var connectedCount = MachineNodes.Count(node => node.Metadata.HostStatus == HostStatuses.Connected);
        var endpoint = EndpointBox.Text.Trim();
        var threadCount = ThreadNodes.Count();

        return
        [
            new RuntimeDiagnosticStep
            {
                Id = "codex",
                Title = "Find Codex executable",
                Status = codexPath is null ? RuntimeDiagnosticStatuses.Warning : RuntimeDiagnosticStatuses.Passed,
                Detail = codexPath ?? "codex was not found on PATH.",
                Evidence = codexPath ?? ""
            },
            new RuntimeDiagnosticStep
            {
                Id = "connect",
                Title = "Connect runtime",
                Status = connectedCount > 0 ? RuntimeDiagnosticStatuses.Passed : RuntimeDiagnosticStatuses.Warning,
                Detail = connectedCount > 0
                    ? $"{connectedCount} App Server route{(connectedCount == 1 ? "" : "s")} connected."
                    : string.IsNullOrWhiteSpace(endpoint)
                        ? "No App Server endpoint entered."
                        : $"No connected App Server route for {endpoint}.",
                Evidence = endpoint
            },
            new RuntimeDiagnosticStep
            {
                Id = "account",
                Title = "Read account",
                Status = connectedCount > 0 ? RuntimeDiagnosticStatuses.Pending : RuntimeDiagnosticStatuses.Warning,
                Detail = connectedCount > 0
                    ? "Queued for account/read once the Windows preview keeps a live session."
                    : "Connect a Codex App Server before reading account state."
            },
            new RuntimeDiagnosticStep
            {
                Id = "models",
                Title = "List models",
                Status = connectedCount > 0 ? RuntimeDiagnosticStatuses.Pending : RuntimeDiagnosticStatuses.Warning,
                Detail = connectedCount > 0
                    ? "Queued for model listing once the live session bridge is active."
                    : "Connect a Codex App Server before listing models."
            },
            new RuntimeDiagnosticStep
            {
                Id = "threads",
                Title = "List threads",
                Status = threadCount > 0 ? RuntimeDiagnosticStatuses.Passed : RuntimeDiagnosticStatuses.Warning,
                Detail = $"{threadCount} workflow thread{(threadCount == 1 ? "" : "s")} loaded locally."
            }
        ];
    }

    private static string? FindExecutableOnPath(string name)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        var extensions = OperatingSystem.IsWindows()
            ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT;.COM")
                .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : [""];
        foreach (var directory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(directory, name.EndsWith(extension, StringComparison.OrdinalIgnoreCase)
                    ? name
                    : $"{name}{extension}");
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    private string NextWorkflowName()
    {
        var names = _workflowMenuItems
            .Select(item => item.Title)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!names.Contains("New Workflow"))
        {
            return "New Workflow";
        }

        var index = 2;
        while (names.Contains($"New Workflow {index}"))
        {
            index++;
        }

        return $"New Workflow {index}";
    }

    private string NextCopyWorkflowName(string baseName)
    {
        var names = _workflowMenuItems
            .Select(item => item.Title)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var copyName = $"{baseName} Copy";
        if (!names.Contains(copyName))
        {
            return copyName;
        }

        var index = 2;
        while (names.Contains($"{copyName} {index}"))
        {
            index++;
        }

        return $"{copyName} {index}";
    }

    private Task ShowNewThreadPopoverAsync()
    {
        if (CreateThreadUnavailableReason is { } reason)
        {
            ShowCommandFeedback(reason);
            return Task.CompletedTask;
        }

        WorkflowPopover.Visibility = Visibility.Collapsed;
        WorkflowNamePopover.Visibility = Visibility.Collapsed;
        PairingPopover.Visibility = Visibility.Collapsed;
        var preferredTarget = PreferredNewThreadTargetNode();
        _newThreadTargetKind = preferredTarget?.Kind == NodeKinds.Machine
            ? NodeKinds.Machine
            : preferredTarget?.Kind == NodeKinds.Folder || FolderNodes.Any()
                ? NodeKinds.Folder
                : NodeKinds.Machine;
        UpdateChoices(preferredTarget?.Id);
        _isCreatingNewThread = false;
        UpdateNewThreadCreatingChrome();
        NewThreadNameBox.Text = "";
        NewThreadPromptBox.Text = "";
        SyncNewThreadModelChoices();
        _ = RefreshNewThreadModelOptionsForSelectedTargetAsync();
        UpdateNewThreadComposerSummary();
        UpdateNewThreadPermissionWarning();
        UpdateNewThreadReadyText();
        NewThreadPopover.Visibility = NewThreadPopover.Visibility == Visibility.Visible
            ? Visibility.Collapsed
            : Visibility.Visible;
        return Task.CompletedTask;
    }

    private async Task CreateThreadFromPopoverAsync()
    {
        if (_isCreatingNewThread)
        {
            ShowCommandFeedback(NewThreadCreateActionPresentation.CreatingUnavailableReason, CreateThreadButton);
            return;
        }

        var targetKind = _newThreadTargetKind == NodeKinds.Machine ? NodeKinds.Machine : NodeKinds.Folder;
        if (NewThreadTargetBox.SelectedItem is not NodeChoice target ||
            !_graph.Nodes.TryGetValue(target.Id, out var targetNode))
        {
            AddActivity(NewThreadCreateActionPresentation.MissingTargetReason);
            ShowCommandFeedback(NewThreadCreateActionPresentation.MissingTargetReason, CreateThreadButton);
            return;
        }

        if (NewThreadTargetUnavailableReason(targetNode) is { } unavailableReason)
        {
            AddActivity(unavailableReason);
            ShowCommandFeedback(unavailableReason, CreateThreadButton);
            return;
        }

        var title = NewThreadNameBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            title = SuggestedThreadName();
        }

        var selectedModel = SelectedNewThreadModelOption();
        var model = selectedModel?.Id ?? NewThreadOptionDefaults.DefaultModel;
        var effort = selectedModel is null
            ? SelectedNewThreadEffort() ?? NewThreadOptionDefaults.DefaultReasoningEffort
            : NewThreadModelCatalog.CurrentReasoningEffort(selectedModel, SelectedNewThreadEffort());
        var approvalPolicy = ComboBoxTag(NewThreadApprovalPolicyBox, NewThreadOptionDefaults.DefaultApprovalPolicy);
        var sandboxMode = ComboBoxTag(NewThreadSandboxModeBox, NewThreadOptionDefaults.DefaultSandboxMode);
        if (ShouldConfirmNewThreadFullAccess(targetNode, sandboxMode) &&
            !await ConfirmRemoteFullAccessNewThreadAsync())
        {
            AddActivity("Canceled Full Access thread creation.");
            return;
        }

        SetNewThreadCreatingState(true);
        try
        {
            var hostID = targetNode.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID;
            var cwd = targetNode.Kind == NodeKinds.Folder
                ? targetNode.Metadata.FolderPath ?? targetNode.Subtitle
                : DefaultMachineThreadCwd(targetNode);
            var prompt = NewThreadPromptBox.Text.Trim();
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(60));
            var endpoint = await ResolveNewThreadTargetEndpointAsync(targetNode, cancellation.Token);
            if (endpoint is null)
            {
                var message = $"Reconnect {targetNode.Title} before creating a thread.";
                AddActivity(message, showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
                ShowCommandFeedback(message, CreateThreadButton);
                return;
            }

            var appServerClient = new AppServerClient();
            var threadRef = await appServerClient.StartThreadAsync(
                endpoint,
                hostID,
                cwd,
                model: model,
                name: title,
                approvalPolicy: approvalPolicy,
                sandboxMode: sandboxMode,
                cancellationToken: cancellation.Token);
            threadRef.HostID = string.IsNullOrWhiteSpace(threadRef.HostID) ? hostID : threadRef.HostID;
            threadRef.Cwd = string.IsNullOrWhiteSpace(threadRef.Cwd) ? cwd : threadRef.Cwd;
            threadRef.Name = string.IsNullOrWhiteSpace(threadRef.Name) ? title : threadRef.Name;

            AppServerTurnStartResult? startedTurn = null;
            if (!string.IsNullOrWhiteSpace(prompt))
            {
                startedTurn = await appServerClient.StartTurnAsync(
                    endpoint,
                    threadRef,
                    prompt,
                    model: model,
                    reasoningEffort: effort,
                    approvalPolicy: approvalPolicy,
                    sandboxMode: sandboxMode,
                    cancellationToken: cancellation.Token);
            }

            var id = UniqueNodeId(PreferredThreadNodeId(threadRef));

            _graph.Nodes[id] = new CanvasNode
            {
                Id = id,
                Kind = NodeKinds.CodexThread,
                Title = threadRef.Name ?? title,
                Subtitle = targetNode.Kind == NodeKinds.Folder
                    ? threadRef.Cwd
                    : $"Machine chat - {targetNode.Title}",
                Position = NextThreadPosition(targetNode),
                Size = CanvasSize.Thread,
                Metadata = new NodeMetadata
                {
                    HostID = threadRef.HostID,
                    Platform = targetNode.Metadata.Platform ?? HostPlatforms.Windows,
                    RunStatus = startedTurn is null ? ThreadRunStatuses.Idle : ThreadRunStatuses.Running,
                    Model = model,
                    ReasoningEffort = effort,
                    ThreadKind = ThreadKinds.Thread,
                    ApprovalPolicy = approvalPolicy,
                    SandboxMode = sandboxMode,
                    InitialPrompt = string.IsNullOrWhiteSpace(prompt) ? null : prompt,
                    LocalTranscript = string.IsNullOrWhiteSpace(prompt)
                        ? new List<LocalThreadMessage>()
                        : new List<LocalThreadMessage>
                        {
                            new LocalThreadMessage
                            {
                                Role = "user",
                                Text = prompt,
                                CreatedAt = DateTimeOffset.UtcNow
                            }
                        },
                    ThreadRef = threadRef
                },
                ZIndex = _graph.Nodes.Count
            };

            var edgeID = $"edge-{Guid.NewGuid():N}";
            _graph.ManualEdges[edgeID] = new CanvasEdge
            {
                Id = edgeID,
                Source = targetNode.Id,
                Target = id,
                Kind = targetKind == NodeKinds.Machine ? EdgeKinds.MachineThread : EdgeKinds.FolderThread,
                IsManual = false,
                Label = string.IsNullOrWhiteSpace(prompt) ? null : "initial prompt"
            };

            await SaveGraphAsync();
            _selectedNodeId = id;
            _selectedEdgeId = null;
            if (_isReadingModePresented && !_readerThreadIds.Contains(id))
            {
                _readerThreadIds.Add(id);
            }

            NewThreadPopover.Visibility = Visibility.Collapsed;
            AddActivity($"Created {title}.");
            if (startedTurn is not null)
            {
                AddActivity($"Started initial turn for {title}.");
            }

            await RenderGraphAsync();
        }
        catch (Exception exception)
        {
            var message = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message);
            AddActivity($"Create thread failed: {message}", showTopNotification: true, notificationKind: ActivityNotificationKindFailed);
            ShowCommandFeedback($"Create thread failed: {message}", CreateThreadButton);
        }
        finally
        {
            SetNewThreadCreatingState(false);
        }
    }

    private async Task<AppServerEndpoint?> ResolveNewThreadTargetEndpointAsync(
        CanvasNode targetNode,
        CancellationToken cancellationToken)
    {
        if (TryGetNewThreadTargetEndpoint(targetNode, out _, out var endpoint))
        {
            return endpoint;
        }

        if (NewThreadTargetIsRemote(targetNode))
        {
            return null;
        }

        AddActivity("Reconnecting local Codex App Server.");
        var result = await LocalAppServerService.StartOrConnectAsync(
            _store.ApplicationDataDirectory,
            cancellationToken);
        UpsertLocalMachine(
            HostStatuses.Connected,
            result,
            $"Connected via {result.Endpoint.Url}");
        RegisterLocalAppServerEndpoint(result.Endpoint);
        SetStatus(HostStatuses.Connected, "Connected", result.Endpoint.Url.ToString());
        _lastLocalSetupDetail = $"Local Codex App Server is running on {result.Endpoint.Url}.";
        await SaveGraphAsync();
        await RefreshNewThreadModelOptionsForHostAsync(
            LocalHostIdentity.LocalMachineNodeID,
            result.Endpoint,
            cancellationToken);
        return result.Endpoint;
    }

    private static string ComboBoxText(ComboBox comboBox, string fallback)
    {
        if (comboBox.SelectedItem is CodexModelOption model)
        {
            return string.IsNullOrWhiteSpace(model.Id) ? fallback : model.Id;
        }

        if (comboBox.SelectedItem is string value)
        {
            return string.IsNullOrWhiteSpace(value) ? fallback : value;
        }

        if (comboBox.SelectedItem is ComboBoxItem item)
        {
            return item.Content?.ToString() ?? fallback;
        }

        return comboBox.SelectedItem?.ToString() ?? fallback;
    }

    private static string ComboBoxTag(ComboBox comboBox, string fallback)
    {
        if (comboBox.SelectedItem is ComboBoxItem item)
        {
            return item.Tag?.ToString() ?? item.Content?.ToString() ?? fallback;
        }

        return comboBox.SelectedItem?.ToString() ?? fallback;
    }

    private void UpdateChoices(string? preferredNewThreadTargetId = null)
    {
        RebuildChoices(_folderChoices, FolderNodes);
        RebuildChoices(_machineChoices, MachineNodes);
        UpdateNewThreadTargetSource(preferredNewThreadTargetId);
        UpdateReaderCandidates();
    }

    private static void RebuildChoices(ObservableCollection<NodeChoice> choices, IEnumerable<CanvasNode> nodes)
    {
        var existingSelection = choices.Select(choice => choice.Id).ToHashSet(StringComparer.Ordinal);
        choices.Clear();
        foreach (var node in nodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase))
        {
            choices.Add(new NodeChoice(node.Id, node.Title, node.Subtitle));
        }

        _ = existingSelection;
    }

    private void UpdateNewThreadTargetSource(string? preferredTargetId = null)
    {
        if (NewThreadTargetBox is null || NewThreadTargetSummary is null)
        {
            return;
        }

        UpdateNewThreadTargetKindChoice();

        var choices = _newThreadTargetKind == NodeKinds.Machine ? _machineChoices : _folderChoices;
        if (_newThreadTargetKind == NodeKinds.Machine)
        {
            if (NewThreadTargetLabel is not null)
            {
                NewThreadTargetLabel.Text = "Machine";
            }
            NewThreadTargetBox.ItemsSource = choices;
        }
        else
        {
            if (NewThreadTargetLabel is not null)
            {
                NewThreadTargetLabel.Text = "Folder";
            }
            NewThreadTargetBox.ItemsSource = choices;
        }

        var selectedId = string.IsNullOrWhiteSpace(preferredTargetId)
            ? (NewThreadTargetBox.SelectedItem as NodeChoice)?.Id
            : preferredTargetId;
        var selectedChoice = string.IsNullOrWhiteSpace(selectedId)
            ? null
            : choices.FirstOrDefault(choice => string.Equals(choice.Id, selectedId, StringComparison.Ordinal));
        if (selectedChoice is not null)
        {
            NewThreadTargetBox.SelectedItem = selectedChoice;
        }
        else
        {
            NewThreadTargetBox.SelectedIndex = choices.Count > 0 ? 0 : -1;
        }

        UpdateNewThreadTargetSummary();
    }

    private void UpdateNewThreadTargetSummary()
    {
        if (NewThreadTargetSummary is null ||
            NewThreadTargetBox is null ||
            NewThreadNameBox is null)
        {
            return;
        }

        if (NewThreadTargetBox.SelectedItem is NodeChoice choice)
        {
            NewThreadTargetSummary.Text = choice.Title;
            SyncNewThreadModelChoices();
            _ = RefreshNewThreadModelOptionsForSelectedTargetAsync();
            UpdateNewThreadPermissionWarning();
            UpdateNewThreadReadyText();
            return;
        }

        NewThreadTargetSummary.Text = _newThreadTargetKind == NodeKinds.Machine
            ? "No machines available"
            : "No folders available";
        SyncNewThreadModelChoices();
        UpdateNewThreadPermissionWarning();
        UpdateNewThreadReadyText();
    }

    private string SuggestedThreadName()
    {
        if (NewThreadTargetBox?.SelectedItem is NodeChoice choice)
        {
            return NewThreadNamingPresentation.ResolveForTarget(choice.Title, _newThreadTargetKind);
        }

        return NewThreadNamingPresentation.DefaultThreadName;
    }

    private static string DefaultMachineThreadCwd(CanvasNode machine)
    {
        var localHostId = IsLocalHostId(machine.Metadata.HostID)
            ? machine.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID
            : LocalHostIdentity.CanonicalHostID;
        return ThreadDefaultCwdResolver.DefaultCwd(
                machine,
                localHostId,
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))
            ?? "";
    }

    private CanvasNode? PreferredNewThreadTargetNode()
    {
        if (_selectedNodeId is null || !_graph.Nodes.TryGetValue(_selectedNodeId, out var node))
        {
            return null;
        }

        return node.Kind is NodeKinds.Folder or NodeKinds.Machine ? node : null;
    }

    private void UpdateNewThreadTargetKindChoice()
    {
        if (NewThreadTargetKindBox is null)
        {
            return;
        }

        var selectedIndex = _newThreadTargetKind == NodeKinds.Machine ? 1 : 0;
        if (NewThreadTargetKindBox.SelectedIndex != selectedIndex)
        {
            NewThreadTargetKindBox.SelectedIndex = selectedIndex;
        }
    }

    private void UpdateNewThreadPermissionWarning()
    {
        if (NewThreadDangerWarning is null || NewThreadSandboxModeBox is null)
        {
            return;
        }

        var isFullAccess = ComboBoxTag(
            NewThreadSandboxModeBox,
            NewThreadOptionDefaults.DefaultSandboxMode) == "danger-full-access";
        NewThreadDangerWarning.Visibility = isFullAccess ? Visibility.Visible : Visibility.Collapsed;
        if (!isFullAccess)
        {
            return;
        }

        var presentation = NewThreadFullAccessWarningPresentation.Resolve(CurrentNewThreadTargetIsRemote());
        NewThreadDangerWarning.Background = BrushFromHex(presentation.BackgroundHex);
        NewThreadDangerWarning.BorderBrush = BrushFromHex(presentation.BorderHex);
        NewThreadDangerWarning.BorderThickness = new Thickness(presentation.BorderThickness);
        if (NewThreadDangerWarningIcon is not null)
        {
            NewThreadDangerWarningIcon.Width = presentation.IconWidth;
            NewThreadDangerWarningIcon.Height = presentation.IconHeight;
        }

        var warningIconBrush = BrushFromHex(presentation.IconHex);
        var warningMarkBrush = BrushFromHex(presentation.ExclamationHex);
        if (NewThreadDangerWarningTrianglePath is not null)
        {
            NewThreadDangerWarningTrianglePath.Fill = warningIconBrush;
        }

        if (NewThreadDangerWarningExclamationLine is not null)
        {
            NewThreadDangerWarningExclamationLine.Stroke = warningMarkBrush;
            NewThreadDangerWarningExclamationLine.StrokeThickness = presentation.ExclamationStrokeThickness;
        }

        if (NewThreadDangerWarningExclamationDot is not null)
        {
            NewThreadDangerWarningExclamationDot.Fill = warningMarkBrush;
        }

        if (NewThreadDangerWarningText is not null)
        {
            NewThreadDangerWarningText.Text = presentation.Text;
        }
    }

    private void UpdateNewThreadReadyText()
    {
        if (NewThreadReadyText is null ||
            NewThreadTargetBox is null ||
            CreateThreadButton is null)
        {
            return;
        }

        var unavailableReason = _isCreatingNewThread
            ? NewThreadCreateActionPresentation.CreatingUnavailableReason
            : NewThreadSelectedTargetUnavailableReason();
        var presentation = NewThreadCreateActionPresentation.Resolve(_isCreatingNewThread, unavailableReason);
        NewThreadReadyText.Text = presentation.StatusText;
        CreateThreadButton.IsEnabled = presentation.IsButtonEnabled;
        CreateThreadButton.Opacity = presentation.ButtonOpacity;
        ToolTipService.SetToolTip(CreateThreadButton, presentation.ToolTip);
    }

    private void SetNewThreadCreatingState(bool isCreating)
    {
        _isCreatingNewThread = isCreating;
        UpdateNewThreadCreatingChrome();
        UpdateNewThreadReadyText();
    }

    private void UpdateNewThreadCreatingChrome()
    {
        var isEditable = !_isCreatingNewThread;
        if (NewThreadConfigurationScroller is not null)
        {
            NewThreadConfigurationScroller.IsEnabled = isEditable;
        }

        if (NewThreadPromptBox is not null)
        {
            NewThreadPromptBox.IsEnabled = isEditable;
        }

        if (CreateThreadButtonIcon is not null)
        {
            CreateThreadButtonIcon.Opacity = _isCreatingNewThread ? 0 : 1;
        }

        if (CreateThreadProgressRing is not null)
        {
            CreateThreadProgressRing.Visibility = _isCreatingNewThread ? Visibility.Visible : Visibility.Collapsed;
            CreateThreadProgressRing.IsActive = _isCreatingNewThread;
        }

        if (CreateThreadButton is not null)
        {
            ToolTipService.SetToolTip(
                CreateThreadButton,
                _isCreatingNewThread ? "Creating this thread now." : "Create thread");
        }
    }

    private string? NewThreadSelectedTargetUnavailableReason()
    {
        if (NewThreadTargetBox?.SelectedItem is not NodeChoice choice ||
            !_graph.Nodes.TryGetValue(choice.Id, out var targetNode))
        {
            return NewThreadCreateActionPresentation.MissingTargetReason;
        }

        return NewThreadTargetUnavailableReason(targetNode);
    }

    private string? NewThreadTargetUnavailableReason(CanvasNode targetNode)
    {
        if (IsNewThreadTargetAvailable(targetNode))
        {
            return null;
        }

        return targetNode.Kind == NodeKinds.Machine
            ? "Connect this machine before creating a chat."
            : "Connect the machine that owns this folder before creating a thread.";
    }

    private bool IsNewThreadTargetAvailable(CanvasNode targetNode)
    {
        var owner = targetNode.Kind == NodeKinds.Machine
            ? targetNode
            : MachineNodes.FirstOrDefault(machine => SameIdentifier(machine.Metadata.HostID, targetNode.Metadata.HostID));
        if (owner is null && IsLocalHostId(targetNode.Metadata.HostID))
        {
            owner = LocalMachineNode();
        }

        return owner?.Metadata.HostStatus == HostStatuses.Connected;
    }

    private void UpdateNewThreadComposerSummary()
    {
        if (NewThreadComposerModelText is null ||
            NewThreadComposerEffortText is null ||
            NewThreadModelBox is null ||
            NewThreadEffortBox is null)
        {
            return;
        }

        NewThreadComposerModelText.Text = SelectedNewThreadModelOption()?.PickerTitle
            ?? NewThreadOptionDefaults.DefaultModel;
        NewThreadComposerEffortText.Text = SelectedNewThreadEffort()
            ?? NewThreadOptionDefaults.DefaultReasoningEffort;
    }

    private void SyncNewThreadModelChoices(string? preferredModelId = null, string? preferredEffort = null)
    {
        if (NewThreadModelBox is null || NewThreadEffortBox is null)
        {
            return;
        }

        var selectedModelId = preferredModelId ?? SelectedNewThreadModelOption()?.Id;
        var selectedEffort = preferredEffort ?? SelectedNewThreadEffort();
        var models = CurrentNewThreadModelOptions();
        var currentModel = NewThreadModelCatalog.CurrentModel(models, selectedModelId);

        _isUpdatingNewThreadModelChoices = true;
        try
        {
            _newThreadModelOptions.Clear();
            foreach (var option in models)
            {
                _newThreadModelOptions.Add(option);
            }

            NewThreadModelBox.SelectedItem = _newThreadModelOptions.FirstOrDefault(option =>
                string.Equals(option.Id, currentModel.Id, StringComparison.OrdinalIgnoreCase));
            SyncNewThreadEffortChoices(currentModel, selectedEffort);
        }
        finally
        {
            _isUpdatingNewThreadModelChoices = false;
        }

        UpdateNewThreadComposerSummary();
        UpdateNewThreadReadyText();
    }

    private void SyncNewThreadEffortChoices(CodexModelOption model, string? preferredEffort)
    {
        _newThreadEffortOptions.Clear();
        foreach (var effort in NewThreadModelCatalog.SupportedReasoningEfforts(model))
        {
            _newThreadEffortOptions.Add(effort);
        }

        var selectedEffort = NewThreadModelCatalog.CurrentReasoningEffort(model, preferredEffort);
        NewThreadEffortBox.SelectedItem = _newThreadEffortOptions.FirstOrDefault(effort =>
            string.Equals(effort, selectedEffort, StringComparison.OrdinalIgnoreCase));
    }

    private IReadOnlyList<CodexModelOption> CurrentNewThreadModelOptions()
    {
        if (NewThreadTargetBox?.SelectedItem is NodeChoice choice &&
            _graph.Nodes.TryGetValue(choice.Id, out var targetNode) &&
            NewThreadTargetHostKey(targetNode) is { } hostKey &&
            _newThreadModelsByHostId.TryGetValue(hostKey, out var remoteModels) &&
            remoteModels.Count > 0)
        {
            return remoteModels;
        }

        return NewThreadOptionDefaults.ModelOptions;
    }

    private CodexModelOption? SelectedNewThreadModelOption()
    {
        if (NewThreadModelBox?.SelectedItem is CodexModelOption model)
        {
            return model;
        }

        return NewThreadModelCatalog.CurrentModel(CurrentNewThreadModelOptions(), null);
    }

    private string? SelectedNewThreadEffort()
    {
        return NewThreadEffortBox?.SelectedItem switch
        {
            string effort when !string.IsNullOrWhiteSpace(effort) => effort,
            ComboBoxItem item => item.Content?.ToString(),
            _ => null
        };
    }

    private Task RefreshNewThreadModelOptionsForSelectedTargetAsync()
    {
        return _windowLifetime.TryRunTracked(
            RefreshNewThreadModelOptionsForSelectedTargetCoreAsync,
            out var task)
            ? task
            : Task.CompletedTask;
    }

    private async Task RefreshNewThreadModelOptionsForSelectedTargetCoreAsync(
        WindowLifetimeLease lease)
    {
        if (NewThreadTargetBox?.SelectedItem is not NodeChoice choice ||
            !_graph.Nodes.TryGetValue(choice.Id, out var targetNode) ||
            !TryGetNewThreadTargetEndpoint(targetNode, out var hostKey, out var endpoint))
        {
            return;
        }

        _newThreadModelRefreshCancellation?.Cancel();
        _newThreadModelRefreshCancellation?.Dispose();
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(lease.CancellationToken);
        _newThreadModelRefreshCancellation = cancellation;

        try
        {
            await RefreshNewThreadModelOptionsForHostAsync(hostKey, endpoint, cancellation.Token);
        }
        catch (OperationCanceledException)
        {
        }
    }

    private async Task RefreshNewThreadModelOptionsForHostAsync(
        string hostKey,
        AppServerEndpoint endpoint,
        CancellationToken cancellationToken)
    {
        try
        {
            var models = await new AppServerClient()
                .ListModelsAsync(endpoint, cancellationToken: cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            if (models.Count == 0)
            {
                return;
            }

            _newThreadModelsByHostId[hostKey] = models;
            if (NewThreadTargetBox?.SelectedItem is NodeChoice choice &&
                _graph.Nodes.TryGetValue(choice.Id, out var targetNode) &&
                string.Equals(NewThreadTargetHostKey(targetNode), hostKey, StringComparison.OrdinalIgnoreCase))
            {
                SyncNewThreadModelChoices();
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            AddActivity($"Could not load model list: {exception.Message}");
        }
    }

    private bool TryGetNewThreadTargetEndpoint(
        CanvasNode targetNode,
        out string hostKey,
        out AppServerEndpoint endpoint)
    {
        hostKey = NewThreadTargetHostKey(targetNode) ?? "";
        if (!string.IsNullOrWhiteSpace(hostKey) &&
            _connectedAppServerEndpointsByHostId.TryGetValue(hostKey, out endpoint!))
        {
            return true;
        }

        var machine = NewThreadTargetMachine(targetNode);
        if (machine is not null &&
            !IsLocalHostId(machine.Metadata.HostID) &&
            machine.Metadata.HostStatus == HostStatuses.Connected &&
            !string.IsNullOrWhiteSpace(machine.Metadata.AppServerEndpointUrl) &&
            Uri.TryCreate(machine.Metadata.AppServerEndpointUrl, UriKind.Absolute, out var url) &&
            AppServerEndpointValidator.IsLoopback(url))
        {
            hostKey = machine.Id;
            endpoint = new AppServerEndpoint(machine.Title, url, null);
            _connectedAppServerEndpointsByHostId[machine.Id] = endpoint;
            return true;
        }

        endpoint = new AppServerEndpoint("", new Uri("ws://127.0.0.1"), null);
        return false;
    }

    private string? NewThreadTargetHostKey(CanvasNode targetNode)
    {
        return NewThreadTargetMachine(targetNode)?.Id ??
            (string.IsNullOrWhiteSpace(targetNode.Metadata.HostID) ? null : targetNode.Metadata.HostID);
    }

    private CanvasNode? NewThreadTargetMachine(CanvasNode targetNode)
    {
        if (targetNode.Kind == NodeKinds.Machine)
        {
            return targetNode;
        }

        var hostID = targetNode.Metadata.HostID;
        if (string.IsNullOrWhiteSpace(hostID))
        {
            return null;
        }

        return MachineNodes.FirstOrDefault(machine =>
            string.Equals(machine.Id, hostID, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(machine.Metadata.HostID, hostID, StringComparison.OrdinalIgnoreCase));
    }

    private bool CurrentNewThreadTargetIsRemote()
    {
        return NewThreadTargetBox?.SelectedItem is NodeChoice choice &&
            _graph.Nodes.TryGetValue(choice.Id, out var targetNode) &&
            NewThreadTargetIsRemote(targetNode);
    }

    private static bool ShouldConfirmNewThreadFullAccess(CanvasNode targetNode, string sandboxMode)
    {
        return string.Equals(sandboxMode, "danger-full-access", StringComparison.OrdinalIgnoreCase) &&
            NewThreadTargetIsRemote(targetNode);
    }

    private static bool NewThreadTargetIsRemote(CanvasNode targetNode)
    {
        return !IsLocalHostId(targetNode.Metadata.HostID);
    }

    private static bool IsLocalHostId(string? hostID)
    {
        return LocalHostIdentity.IsLocalHostID(hostID, Environment.MachineName);
    }

    private Task<bool> ConfirmRemoteFullAccessNewThreadAsync()
    {
        return ConfirmDestructiveActionAsync(
            "Use Full Access on Remote Machine?",
            "This lets Codex run without filesystem sandboxing on the selected remote target. Continue only if you trust the machine, workspace, and prompt context.",
            "Create With Full Access");
    }

    private static Style DestructiveDialogPrimaryButtonStyle()
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Windows.UI.Color.FromArgb(255, 185, 28, 28))));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, new SolidColorBrush(Windows.UI.Color.FromArgb(255, 220, 38, 38))));
        style.Setters.Add(new Setter(Control.ForegroundProperty, new SolidColorBrush(Colors.White)));
        return style;
    }

    private void UpdateReaderCandidates()
    {
        _readerCandidates.Clear();
        foreach (var node in ThreadNodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase))
        {
            var isOpen = _readerThreadIds.Contains(node.Id);
            var suffix = isOpen ? " - open" : "";
            _readerCandidates.Add(new NodeChoice(node.Id, $"{node.Title}{suffix}", node.Subtitle, isOpen));
        }

        SelectFirstAvailableReaderCandidate();
        UpdateReaderCandidateActionState();
    }

    private void SelectFirstAvailableReaderCandidate()
    {
        ReaderCandidateBox.SelectedIndex = _readerCandidates.FirstOrDefault(choice => !choice.IsOpen) is { } available
            ? _readerCandidates.IndexOf(available)
            : -1;
    }

    private void UpdateReaderCandidateActionState()
    {
        AddReaderThreadButton.IsEnabled = ReaderCandidateBox.SelectedItem is NodeChoice { IsOpen: false };
    }

    private void AddThreadToReader(string nodeId, bool openReader)
    {
        if (!_graph.Nodes.TryGetValue(nodeId, out var node) || node.Kind != NodeKinds.CodexThread)
        {
            return;
        }

        if (!_readerThreadIds.Contains(nodeId))
        {
            _readerThreadIds.Add(nodeId);
            AddActivity($"Opened {node.Title} in reader.");
        }

        if (openReader)
        {
            _isReadingModePresented = true;
        }

        UpdateChrome();
    }

    private void UpdateReader()
    {
        _readerThreadIds.RemoveAll(id => !_graph.Nodes.TryGetValue(id, out var node) || node.Kind != NodeKinds.CodexThread);
        foreach (var filterID in _readerTranscriptFilters.Keys.Except(_readerThreadIds).ToList())
        {
            _readerTranscriptFilters.Remove(filterID);
        }
        foreach (var attachmentID in _readerPendingAttachments.Keys.Except(_readerThreadIds).ToList())
        {
            _readerPendingAttachments.Remove(attachmentID);
        }
        foreach (var mentionID in _readerMentionSelections.Keys.Except(_readerThreadIds).ToList())
        {
            _readerMentionSelections.Remove(mentionID);
        }

        _readerThreads.Clear();
        var tileLayout = MeasureReaderTileLayout();
        var pendingRequestCounts = PendingAttentionCountsByNodeId();
        UpdateReaderLayout(tileLayout);

        foreach (var id in _readerThreadIds)
        {
            if (!_graph.Nodes.TryGetValue(id, out var node))
            {
                continue;
            }

            var transcriptSession = _transcriptSessions.Snapshot(node.Id);
            var isLoadingTranscript = transcriptSession.IsLoading;
            var isLoadingOlder = transcriptSession.IsLoadingOlder;
            var hasOlderCursor = transcriptSession.HasOlderPage;
            var transcriptError = transcriptSession.Error;

            var iconPresentation = ThreadHeaderIconPresentation.Resolve(LooksLikeSubagent(node));
            _readerThreads.Add(new ReaderThreadItem(
                node.Id,
	                node.Title,
	                node.Subtitle,
	                node.Metadata.ThreadRef?.ThreadID ?? node.Id,
	                node.Metadata.Model,
	                node.Metadata.ReasoningEffort,
	                node.Metadata.ApprovalPolicy ?? "on-request",
                node.Metadata.SandboxMode ?? "workspace-write",
                node.Metadata.RunStatus ?? ThreadRunStatuses.Idle,
                node.Metadata.IsUnread == true,
                StopTurnAvailability(node),
                ThreadKindLabelFor(node),
                iconPresentation.KindGlyph,
                BrushFromHex(iconPresentation.KindForegroundHex),
                BrushFromHex(iconPresentation.KindBackgroundHex),
                iconPresentation.HeaderGlyph,
                iconPresentation.UsesHeaderThreadPairIcon,
                BrushFromHex(iconPresentation.HeaderForegroundHex),
                BrushFromHex(iconPresentation.HeaderBackgroundHex),
                LiveStateGlyphFor(node, pendingRequestCounts.GetValueOrDefault(node.Id)),
                LiveStateTextFor(node, pendingRequestCounts.GetValueOrDefault(node.Id)),
                LiveStateBrushFor(node, pendingRequestCounts.GetValueOrDefault(node.Id)),
                ReaderTranscriptRows(node),
                ActiveReaderTranscriptCategories(node.Id),
                PendingReaderAttachments(node.Id),
                isLoadingTranscript,
                isLoadingOlder,
                hasOlderCursor,
                transcriptError,
                HasLoadedThreadTranscript(node),
                tileLayout.TileWidth,
                tileLayout.TileHeight));
        }

        ReaderSummaryText.Text = _readerThreads.Count == 0
            ? "Choose a workflow chat to start reading."
            : $"{_readerThreads.Count} chat{(_readerThreads.Count == 1 ? "" : "s")}";
        ReaderEmptyText.Visibility = _readerThreads.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ReaderThreadList.Visibility = _readerThreads.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        RemoveReaderThreadButton.IsEnabled = _readerThreads.Count > 0;
        ClearReaderThreadsButton.IsEnabled = _readerThreads.Count > 0;
        ClearReaderThreadsButton.Visibility = _readerThreads.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private IReadOnlySet<ReaderTranscriptCategory> ActiveReaderTranscriptCategories(string threadId)
    {
        if (_readerTranscriptFilters.TryGetValue(threadId, out var categories) && categories.Count > 0)
        {
            return categories;
        }

        var allCategories = AllReaderTranscriptCategories();
        _readerTranscriptFilters[threadId] = allCategories;
        return allCategories;
    }

    private ObservableCollection<ComposerAttachmentItem> PendingReaderAttachments(string threadId)
    {
        if (_readerPendingAttachments.TryGetValue(threadId, out var attachments))
        {
            return attachments;
        }

        attachments = [];
        _readerPendingAttachments[threadId] = attachments;
        return attachments;
    }

    private void RefreshTranscriptSurfaces(string threadId)
    {
        if (string.IsNullOrWhiteSpace(threadId))
        {
            return;
        }

        if (_isReadingModePresented && _readerThreadIds.Contains(threadId))
        {
            UpdateReader();
        }

        if (_threadPopoverNodeId == threadId &&
            _graph.Nodes.TryGetValue(threadId, out var node))
        {
            UpdateThreadPopover(node);
        }
    }

    private void ApplyTranscriptRowState(string threadId, IReadOnlyList<ReaderTranscriptRow> rows)
    {
        foreach (var row in rows)
        {
            row.ApplyThreadState(
                threadId,
                _expandedTranscriptRows.Contains(TranscriptRowExpansionKey(threadId, row.Id)));
        }
    }

    private static string TranscriptRowExpansionKey(string threadId, string rowId)
    {
        return $"{threadId}::{rowId}";
    }

    private static HashSet<ReaderTranscriptCategory> AllReaderTranscriptCategories()
    {
        return OrderedReaderTranscriptCategories().ToHashSet();
    }

    private static ReaderTranscriptCategory[] OrderedReaderTranscriptCategories()
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

    private static string ReaderTranscriptCategoryTitle(ReaderTranscriptCategory category)
    {
        return ReaderTranscriptCategoryPresentation(category).Title;
    }

    private static string ReaderTranscriptCategoryCompactTitle(ReaderTranscriptCategory category)
    {
        return ReaderTranscriptCategoryPresentation(category).CompactTitle;
    }

    private static bool TryReaderTranscriptCategory(string key, out ReaderTranscriptCategory category)
    {
        if (!TranscriptCategoryPresentation.TryNormalizeKey(key, out var normalized))
        {
            category = default;
            return false;
        }

        category = normalized switch
        {
            TranscriptCategoryPresentation.KeyMessages => ReaderTranscriptCategory.Message,
            TranscriptCategoryPresentation.KeyProgress => ReaderTranscriptCategory.Progress,
            TranscriptCategoryPresentation.KeyThoughts => ReaderTranscriptCategory.Thought,
            TranscriptCategoryPresentation.KeyTools => ReaderTranscriptCategory.Tool,
            TranscriptCategoryPresentation.KeyArtifacts => ReaderTranscriptCategory.Artifact,
            TranscriptCategoryPresentation.KeyApprovals => ReaderTranscriptCategory.Approval,
            TranscriptCategoryPresentation.KeySystem => ReaderTranscriptCategory.System,
            _ => default
        };

        return true;
    }

    private static TranscriptCategoryPresentationSnapshot ReaderTranscriptCategoryPresentation(
        ReaderTranscriptCategory category,
        bool isActive = true)
    {
        return TranscriptCategoryPresentation.Resolve(
            ReaderTranscriptCategoryKey(category),
            isActive);
    }

    private static string ReaderTranscriptCategoryKey(ReaderTranscriptCategory category)
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

    private void UpdateReaderLayout()
    {
        UpdateReaderLayout(MeasureReaderTileLayout());
    }

    private void UpdateReaderLayout(ReaderTileLayout tileLayout)
    {
        if (_readerItemsPanel is not null)
        {
            _readerItemsPanel.ItemWidth = tileLayout.SlotWidth;
            _readerItemsPanel.ItemHeight = tileLayout.SlotHeight;
        }

        foreach (var item in _readerThreads)
        {
            item.TileWidth = tileLayout.TileWidth;
            item.TileHeight = tileLayout.TileHeight;
        }
    }

    private readonly record struct ReaderTileLayout(
        double TileWidth,
        double TileHeight,
        double SlotWidth,
        double SlotHeight);

    private ReaderTileLayout MeasureReaderTileLayout()
    {
        var viewportWidth = ReaderThreadHost.ActualWidth > 0
            ? ReaderThreadHost.ActualWidth
            : RootGrid.ActualWidth;
        var viewportHeight = ReaderThreadHost.ActualHeight > 0
            ? ReaderThreadHost.ActualHeight
            : RootGrid.ActualHeight - 90;
        var layout = ReaderDockLayout.Measure(viewportWidth, viewportHeight, _readerThreadIds.Count);
        return new ReaderTileLayout(
            layout.TileWidth,
            layout.TileHeight,
            layout.SlotWidth,
            layout.SlotHeight);
    }

    private List<ReaderTranscriptRow> ReaderTranscriptRows(CanvasNode node)
    {
        var rows = new List<ReaderTranscriptRow>();

        rows.AddRange(TimelineTranscriptRows(node));

        foreach (var request in _graph.PendingAttentionRequests
                     .Where(request => AttentionRequestMatchesNode(request, node))
                     .OrderBy(request => request.CreatedAt))
        {
            rows.Add(ReaderTranscriptRow.Attention(ThreadAttentionItem.FromRequest(
                request,
                node.Id,
                node.Title,
                MachineTitleFor(node),
                AttentionPromptText(request))));
        }

        var hasAttentionRequests = _graph.PendingAttentionRequests.Any(request => AttentionRequestMatchesNode(request, node));
        var isLoadingTranscript = _transcriptSessions.Snapshot(node.Id).IsLoading;

        if (node.Metadata.RunStatus == ThreadRunStatuses.Running)
        {
            rows.Add(ReaderTranscriptRow.PendingAssistant(DateTimeOffset.UtcNow));
        }
        else if (node.Metadata.LocalTranscript.Count == 0 && !hasAttentionRequests && !isLoadingTranscript)
        {
            rows.Add(ReaderTranscriptRow.EmptyTranscript(DateTimeOffset.UtcNow));
        }

        ApplyTranscriptRowState(node.Id, rows);
        return rows;
    }

    private static IReadOnlyList<ReaderTranscriptRow> TimelineTranscriptRows(CanvasNode node)
    {
        var messages = node.Metadata.LocalTranscript
            .OrderBy(message => message.CreatedAt)
            .ToList();
        if (messages.Count == 0 && node.Metadata.LocalTranscriptTurns.Count == 0)
        {
            return [];
        }

        if (node.Metadata.LocalTranscriptTurns.Count == 0)
        {
            return SyntheticTurnTranscriptRows(messages);
        }

        var rows = new List<ReaderTranscriptRow>();
        var messagesById = messages
            .GroupBy(message => message.Id, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => new Queue<LocalThreadMessage>(group),
                StringComparer.Ordinal);
        var usedMessageIds = new HashSet<string>(StringComparer.Ordinal);

        foreach (var turn in node.Metadata.LocalTranscriptTurns.OrderBy(turn => turn.StartedAt))
        {
            var turnMessages = new List<LocalThreadMessage>();
            foreach (var messageId in turn.ItemMessageIds)
            {
                if (!messagesById.TryGetValue(messageId, out var queue) || queue.Count == 0)
                {
                    continue;
                }

                var message = queue.Dequeue();
                turnMessages.Add(message);
                usedMessageIds.Add(message.Id);
            }

            AppendTurnTranscriptRows(rows, turn, turnMessages);
        }

        var missingMessages = messages
            .Where(message => !usedMessageIds.Contains(message.Id))
            .ToList();
        if (missingMessages.Count > 0)
        {
            rows.AddRange(SyntheticTurnTranscriptRows(missingMessages, "local"));
        }

        return rows;
    }

    private static IReadOnlyList<ReaderTranscriptRow> SyntheticTurnTranscriptRows(
        IReadOnlyList<LocalThreadMessage> messages,
        string idPrefix = "synthetic")
    {
        var rows = new List<ReaderTranscriptRow>();
        var current = new List<LocalThreadMessage>();
        var turnIndex = 1;

        void Flush()
        {
            if (current.Count == 0)
            {
                return;
            }

            var turn = new LocalThreadTurn
            {
                Id = $"{idPrefix}-turn-{turnIndex}-{current[0].Id}",
                Status = ThreadRunStatuses.Complete,
                StartedAt = current[0].CreatedAt,
                CompletedAt = current[^1].CreatedAt,
                ItemsView = ThreadTurnItemsViews.Full,
                ItemMessageIds = current.Select(message => message.Id).ToList()
            };
            AppendTurnTranscriptRows(rows, turn, current);
            current.Clear();
            turnIndex += 1;
        }

        foreach (var message in messages.OrderBy(message => message.CreatedAt))
        {
            if (message.Role.Equals("user", StringComparison.OrdinalIgnoreCase) && current.Count > 0)
            {
                Flush();
            }

            current.Add(message);
        }

        Flush();
        return rows;
    }

    private static void AppendTurnTranscriptRows(
        List<ReaderTranscriptRow> rows,
        LocalThreadTurn turn,
        IReadOnlyList<LocalThreadMessage> messages)
    {
        var itemRows = messages
            .OrderBy(message => message.CreatedAt)
            .Select(ReaderTranscriptRow.FromMessage)
            .ToList();

        if (ShouldShowTurnHeader(turn, itemRows))
        {
            rows.Add(ReaderTranscriptRow.TurnEvent(turn, itemRows));
        }

        if (itemRows.Count == 0)
        {
            rows.Add(ReaderTranscriptRow.EmptyTurn(turn));
        }
        else
        {
            rows.AddRange(itemRows);
        }
    }

    private static bool ShouldShowTurnHeader(
        LocalThreadTurn turn,
        IReadOnlyList<ReaderTranscriptRow> rows)
    {
        return rows.Count == 0 ||
            !string.Equals(turn.ItemsView, ThreadTurnItemsViews.Full, StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrWhiteSpace(turn.Error) ||
            turn.DurationMilliseconds.HasValue ||
            turn.CompletedAt.HasValue ||
            rows.Count > 2 ||
            rows.Any(row => row.Category is ReaderTranscriptCategory.Tool or ReaderTranscriptCategory.Artifact);
    }

    private static List<ThreadArtifactItem> ThreadArtifacts(CanvasNode node)
    {
        return node.Metadata.LocalTranscript
            .OrderByDescending(message => message.CreatedAt)
            .Select(ThreadArtifactItem.FromMessage)
            .OfType<ThreadArtifactItem>()
            .ToList();
    }

    private void ShowArtifactsForThread(CanvasNode node)
    {
        _artifactCatalog.SetFilter(ArtifactCatalogFilter.All);
        _artifactCatalog.Replace(node.Id, ThreadArtifacts(node));
        ArtifactsTitleText.Text = "Artifacts";
        ArtifactsSubtitleText.Text =
            $"{node.Title} - {_artifactCatalog.Count} artifact{(_artifactCatalog.Count == 1 ? "" : "s")}";
        ArtifactsPopover.Margin = _isReadingModePresented
            ? new Thickness(0, 72, 24, 0)
            : new Thickness(0, 84, 370, 0);
        RefreshArtifactItems();
        ArtifactsPopover.Visibility = Visibility.Visible;
    }

    private void RefreshArtifactItems()
    {
        _threadArtifactItems.Clear();
        foreach (var item in _artifactCatalog.VisibleItems)
        {
            _threadArtifactItems.Add(item);
        }

        if (_artifactCatalog.Selected is null &&
            ArtifactPreviewPopover.Visibility == Visibility.Visible)
        {
            CloseArtifactPreview();
        }

        ArtifactsEmptyState.Visibility = _threadArtifactItems.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdateArtifactFilterButtons();
    }

    private void SetArtifactFilter(string filter)
    {
        _artifactCatalog.SetFilter(filter);
        RefreshArtifactItems();
    }

    private void UpdateArtifactFilterButtons()
    {
        SetArtifactFilterButton(ArtifactFilterAllButton, _artifactCatalog.Filter == ArtifactCatalogFilter.All);
        SetArtifactFilterButton(ArtifactFilterImagesButton, _artifactCatalog.Filter == ArtifactCatalogFilter.Images);
        SetArtifactFilterButton(ArtifactFilterFilesButton, _artifactCatalog.Filter == ArtifactCatalogFilter.Files);
        SetArtifactFilterButton(ArtifactFilterDiffsButton, _artifactCatalog.Filter == ArtifactCatalogFilter.Diffs);
    }

    private static void SetArtifactFilterButton(Button button, bool isActive)
    {
        button.Background = BrushFromHex(isActive ? "#180A84FF" : "#262A2C30");
        button.BorderBrush = BrushFromHex(isActive ? "#440A84FF" : "#24FFFFFF");
        button.Foreground = BrushFromHex(isActive ? "#6AB7FF" : "#D7DCE5");
    }

    private void ShowArtifactPreview(ThreadArtifactItem item)
    {
        if (!_artifactCatalog.Select(item))
        {
            return;
        }

        ArtifactPreviewTitleText.Text = item.Title;
        ArtifactPreviewSubtitleText.Text = item.Subtitle;
        ArtifactPreviewIcon.Glyph = item.KindGlyph;
        ArtifactPreviewIcon.Foreground = item.BadgeForegroundBrush;
        ArtifactPreviewIconSurface.Background = BrushFromHex("#00FFFFFF");
        ArtifactPreviewBodyText.Text = item.PreviewText;
        ToolTipService.SetToolTip(
            CopyArtifactPreviewButton,
            item.KindKey == ThreadArtifactItem.KindImage && !string.IsNullOrWhiteSpace(item.DisplayPath)
                ? "Copy image path"
                : "Copy preview");
        ArtifactPreviewImage.Source = null;
        _artifactPreviewDiffLines.Clear();
        ArtifactPreviewImageScrollViewer.Visibility = Visibility.Collapsed;
        ArtifactPreviewDiffScrollViewer.Visibility = Visibility.Collapsed;
        ArtifactPreviewTextScrollViewer.Visibility = Visibility.Visible;

        if (item.KindKey == ThreadArtifactItem.KindImage &&
            ArtifactPreviewLocation.TryResolve(item.DisplayPath, out var imageUri))
        {
            ArtifactPreviewImage.Source = new BitmapImage(imageUri);
            ArtifactPreviewSubtitleText.Text = item.DisplayPath ?? item.Subtitle;
            ArtifactPreviewImageScrollViewer.Visibility = Visibility.Visible;
            ArtifactPreviewTextScrollViewer.Visibility = Visibility.Collapsed;
        }
        else if (item.KindKey == ThreadArtifactItem.KindDiff)
        {
            foreach (var line in ArtifactDiffLineItem.FromDiff(item.PreviewText))
            {
                _artifactPreviewDiffLines.Add(line);
            }

            ArtifactPreviewDiffScrollViewer.Visibility = Visibility.Visible;
            ArtifactPreviewTextScrollViewer.Visibility = Visibility.Collapsed;
        }

        ArtifactPreviewPopover.HorizontalAlignment = HorizontalAlignment.Center;
        ArtifactPreviewPopover.Margin = new Thickness(0, 112, 0, 0);
        ArtifactPreviewPopover.Visibility = Visibility.Visible;
    }

    private void CloseArtifactPreview()
    {
        _artifactCatalog.ClearSelection();
        ArtifactPreviewImage.Source = null;
        _artifactPreviewDiffLines.Clear();
        ArtifactPreviewPopover.Visibility = Visibility.Collapsed;
    }

    private void UpdateThreadInbox()
    {
        var query = _threadInboxMode == ThreadInboxModeSearch
            ? ThreadInboxSearchBox.Text.Trim()
            : "";
        _threadInboxItems.Clear();
        _threadAttentionItems.Clear();
        _threadInboxCatalogThreadsByItemId.Clear();

        foreach (var request in _graph.PendingAttentionRequests.OrderBy(request => request.CreatedAt))
        {
            var owningNode = NodeForAttentionRequest(request);
            _threadAttentionItems.Add(ThreadAttentionItem.FromRequest(
                request,
                owningNode?.Id,
                owningNode?.Title ?? request.ThreadID ?? "Unknown thread",
                owningNode is null ? (request.HostID ?? "Unknown host") : MachineTitleFor(owningNode),
                AttentionPromptText(request)));
        }

        var pendingRequestCounts = PendingAttentionCountsByNodeId();
        var activeThreadKeys = ThreadNodes
            .Select(ThreadQualifiedID)
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .Select(key => key!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var nodes = _threadInboxMode == ThreadInboxModeRecent || _threadInboxMode == ThreadInboxModeSearch
            ? ThreadNodes.OrderByDescending(InboxActivityAt).ThenBy(node => node.Title, StringComparer.OrdinalIgnoreCase)
            : ThreadNodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase);

        foreach (var node in nodes)
        {
            if (!NodeMatchesThreadInboxMode(node) || !NodeMatchesWorkflowFilter(node))
            {
                continue;
            }

            if (!string.IsNullOrWhiteSpace(query) &&
                !node.Title.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                !node.Subtitle.Contains(query, StringComparison.OrdinalIgnoreCase) &&
                !InboxPreviewText(node).Contains(query, StringComparison.OrdinalIgnoreCase) &&
                !MachineTitleFor(node).Contains(query, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var pendingRequestCount = pendingRequestCounts.GetValueOrDefault(node.Id);
            AddThreadInboxItem(
                node.Id,
                node,
                activeNodeId: node.Id,
                canAddToCanvas: false,
                pendingRequestCount: pendingRequestCount,
                memberships: WorkflowMembershipsFor(node));
        }

        var catalogThreads = _threadInboxMode == ThreadInboxModeRecent || _threadInboxMode == ThreadInboxModeSearch
            ? CatalogThreadCandidates(activeThreadKeys)
                .OrderByDescending(thread => InboxActivityAt(thread.Node))
                .ThenBy(thread => thread.Node.Title, StringComparer.OrdinalIgnoreCase)
            : CatalogThreadCandidates(activeThreadKeys)
                .OrderBy(thread => thread.Node.Title, StringComparer.OrdinalIgnoreCase);

        foreach (var catalogThread in catalogThreads)
        {
            var node = catalogThread.Node;
            var memberships = WorkflowMembershipsForKey(catalogThread.Key, activeNodeId: null);
            if (!NodeMatchesThreadInboxMode(node) || !MatchesWorkflowFilter(memberships))
            {
                continue;
            }

            if (!ThreadInboxNodeMatchesSearch(node, query))
            {
                continue;
            }

            var itemId = $"catalog::{catalogThread.Key}";
            _threadInboxCatalogThreadsByItemId[itemId] = catalogThread;
            AddThreadInboxItem(
                itemId,
                node,
                activeNodeId: null,
                canAddToCanvas: true,
                pendingRequestCount: 0,
                memberships: memberships);
        }

        if (_hoveredInboxNodeId is not null &&
            _threadInboxItems.All(item => item.ActiveNodeId != _hoveredInboxNodeId))
        {
            var staleHoverId = _hoveredInboxNodeId;
            _hoveredInboxNodeId = null;
            RunWindowOperation(_ => SendGraphCommandAsync("clearHighlight", staleHoverId));
        }

        var count = _threadInboxItems.Count;
        var requestCount = _threadAttentionItems.Count;
        var summary = ApplyThreadInboxSummaryPresentation();
        ThreadInboxEmptyText.Text = ThreadInboxEmptyStatePresentation.Resolve(
            _threadInboxMode,
            query,
            _threadInboxWorkflowFilter).Message;
        ThreadInboxEmptyText.Visibility = summary.ShowEmptyState ? Visibility.Visible : Visibility.Collapsed;
        ThreadInboxList.Visibility = count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private ThreadInboxSummarySnapshot ApplyThreadInboxSummaryPresentation()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve(
            _threadInboxMode,
            _threadInboxItems.Count,
            _threadAttentionItems.Count);
        var summaryBrush = BrushFromHex(summary.SummaryForegroundHex);
        ThreadInboxSummaryText.Text = summary.ThreadSummaryText;
        ThreadInboxSummaryText.FontSize = summary.SummaryFontSize;
        ThreadInboxSummaryText.Foreground = summaryBrush;
        ThreadInboxSummaryText.Visibility = summary.ShowThreadSummary ? Visibility.Visible : Visibility.Collapsed;
        ThreadInboxAttentionSummaryText.Text = summary.AttentionSummaryText;
        ThreadInboxAttentionSummaryText.FontSize = summary.SummaryFontSize;
        ThreadInboxAttentionSummaryText.Foreground = summaryBrush;
        ThreadInboxAttentionList.MaxHeight = summary.AttentionRequestListMaxHeight;
        ThreadInboxList.MaxHeight = summary.ThreadListMaxHeight;
        ThreadInboxAttentionSection.Visibility = summary.ShowAttentionSection ? Visibility.Visible : Visibility.Collapsed;
        return summary;
    }

    private void AddThreadInboxItem(
        string itemId,
        CanvasNode node,
        string? activeNodeId,
        bool canAddToCanvas,
        int pendingRequestCount,
        IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        var presentation = ThreadInboxPresentation.Resolve(
            node.Metadata.RunStatus,
            LooksLikeSubagent(node),
            pendingRequestCount,
            LiveStateDetailFor(node));
        _threadInboxItems.Add(new ThreadInboxItem(
            itemId,
            node.Title,
            node.Subtitle,
            MachineTitleFor(node),
            presentation.StatusText,
            presentation.LeadingGlyph,
            presentation.LeadingIconKind,
            presentation.LeadingUsesThreadPairIcon,
            BrushFromHex(presentation.LeadingHex),
            BrushFromHex(presentation.StatusHex),
            BrushFromHex(presentation.StatusBackgroundHex),
            node.Metadata.IsUnread == true,
            node.Metadata.IsArchived == true,
            ThreadKindLabelFor(node),
            ThreadKindGlyphFor(node),
            ThreadKindBrushFor(node),
            WorkflowLabelFor(memberships),
            WorkflowIconKindFor(memberships),
            WorkflowGlyphFor(memberships),
            WorkflowBrushFor(memberships),
            presentation.LiveStateIconKind,
            presentation.LiveStateGlyph,
            presentation.LiveStateText,
            presentation.LiveStateTitle,
            presentation.LiveStateDetail,
            BrushFromHex(presentation.LiveStateHex),
            InboxPreviewText(node),
            InboxActivityLabel(node),
            pendingRequestCount,
            activeNodeId,
            canAddToCanvas));
    }

    private bool ThreadInboxNodeMatchesSearch(CanvasNode node, string query)
    {
        return string.IsNullOrWhiteSpace(query) ||
            node.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            node.Subtitle.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            InboxPreviewText(node).Contains(query, StringComparison.OrdinalIgnoreCase) ||
            MachineTitleFor(node).Contains(query, StringComparison.OrdinalIgnoreCase);
    }

    private void UpdateThreadInboxChrome()
    {
        var headerPresentation = ThreadInboxHeaderPresentation.Resolve();
        var headerStroke = BrushFromHex(headerPresentation.StrokeHex);
        ThreadInboxHeaderTrayOutline.Stroke = headerStroke;
        ThreadInboxHeaderTrayOutline.StrokeThickness = headerPresentation.StrokeThickness;
        ThreadInboxHeaderTrayTopLine.Stroke = headerStroke;
        ThreadInboxHeaderTrayTopLine.StrokeThickness = headerPresentation.StrokeThickness;
        ThreadInboxHeaderTrayMiddleLine.Stroke = headerStroke;
        ThreadInboxHeaderTrayMiddleLine.StrokeThickness = headerPresentation.StrokeThickness;
        ThreadInboxRefreshIcon.Width = headerPresentation.ActionIconSize;
        ThreadInboxRefreshIcon.Height = headerPresentation.ActionIconSize;
        ThreadInboxRefreshArrowPath.Stroke = headerStroke;
        ThreadInboxRefreshArrowPath.StrokeThickness = headerPresentation.ActionStrokeThickness;
        ToolTipService.SetToolTip(RefreshInboxButton, headerPresentation.RefreshHelp);
        AutomationProperties.SetName(RefreshInboxButton, headerPresentation.RefreshAccessibilityLabel);
        ThreadInboxCollapseChevronIcon.Width = headerPresentation.ActionIconSize;
        ThreadInboxCollapseChevronIcon.Height = headerPresentation.ActionIconSize;
        ThreadInboxCollapseChevronUpPath.Stroke = headerStroke;
        ThreadInboxCollapseChevronUpPath.StrokeThickness = headerPresentation.ActionStrokeThickness;
        ThreadInboxCollapseChevronDownPath.Stroke = headerStroke;
        ThreadInboxCollapseChevronDownPath.StrokeThickness = headerPresentation.ActionStrokeThickness;
        ThreadInboxContent.Visibility = _isThreadInboxCollapsed ? Visibility.Collapsed : Visibility.Visible;
        ThreadInboxCollapseChevronUpPath.Visibility = _isThreadInboxCollapsed ? Visibility.Collapsed : Visibility.Visible;
        ThreadInboxCollapseChevronDownPath.Visibility = _isThreadInboxCollapsed ? Visibility.Visible : Visibility.Collapsed;
        ToolTipService.SetToolTip(
            ThreadInboxCollapseButton,
            _isThreadInboxCollapsed
                ? headerPresentation.CollapsedCollapseHelp
                : headerPresentation.ExpandedCollapseHelp);
        AutomationProperties.SetName(
            ThreadInboxCollapseButton,
            _isThreadInboxCollapsed
                ? headerPresentation.CollapsedCollapseAccessibilityLabel
                : headerPresentation.ExpandedCollapseAccessibilityLabel);
        ThreadInboxRefreshProgress.IsActive = _isRefreshingAppServerInbox;
        ThreadInboxRefreshProgress.Visibility = _isRefreshingAppServerInbox ? Visibility.Visible : Visibility.Collapsed;
        RefreshInboxButton.IsEnabled = !_isRefreshingAppServerInbox;
        ThreadInboxSearchBox.Visibility = !_isThreadInboxCollapsed && _isThreadInboxSearchVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        var warningPresentation = ThreadInboxWarningPresentation.Resolve(_threadInboxWarningMessage);
        var warningForeground = BrushFromHex(warningPresentation.ForegroundHex);
        ThreadInboxWarningIcon.Glyph = warningPresentation.Glyph;
        ThreadInboxWarningIcon.Foreground = warningForeground;
        ThreadInboxWarningIcon.FontSize = warningPresentation.IconFontSize;
        ThreadInboxWarningIcon.Width = warningPresentation.IconWidth;
        ThreadInboxWarningText.Text = warningPresentation.Text;
        ThreadInboxWarningText.Foreground = warningForeground;
        ThreadInboxWarningText.FontSize = warningPresentation.FontSize;
        ThreadInboxWarningText.MaxLines = warningPresentation.MaxLines;
        ThreadInboxWarningRow.Visibility = !_isThreadInboxCollapsed && warningPresentation.IsVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        var secondaryModeSelected = IsSecondaryThreadInboxMode(_threadInboxMode);
        var modePickerPresentation = ThreadInboxModePickerPresentation.Resolve(secondaryModeSelected);
        ThreadInboxModePickerGrid.ColumnSpacing = modePickerPresentation.PrimaryButtonSpacing;
        ApplyInboxModeButton(ThreadInboxActiveModeButton, _threadInboxMode == ThreadInboxModeActive, modePickerPresentation);
        ApplyInboxModeButton(ThreadInboxFinishedModeButton, _threadInboxMode == ThreadInboxModeFinished, modePickerPresentation);
        ApplyInboxModeButton(ThreadInboxSecondaryModeButton, secondaryModeSelected, modePickerPresentation);
        ThreadInboxSecondaryModeButton.Visibility = modePickerPresentation.ShowsSecondaryOverflow
            ? Visibility.Visible
            : Visibility.Collapsed;
        ApplyInboxSecondaryModeIcon(modePickerPresentation);
        ToolTipService.SetToolTip(
            ThreadInboxSecondaryModeButton,
            secondaryModeSelected
                ? $"Showing {ThreadInboxModeDisplayLabel(_threadInboxMode)} inbox threads"
                : modePickerPresentation.OverflowToolTip);
        ThreadInboxNeedsModeMenuItem.IsChecked = _threadInboxMode == ThreadInboxModeNeedsYou;
        ThreadInboxUnreadModeMenuItem.IsChecked = _threadInboxMode == ThreadInboxModeUnread;
        ThreadInboxRecentModeMenuItem.IsChecked = _threadInboxMode == ThreadInboxModeRecent;
        ThreadInboxArchivedModeMenuItem.IsChecked = _threadInboxMode == ThreadInboxModeArchived;
    }

    private void ApplyInboxSecondaryModeIcon(ThreadInboxModePickerPresentationSnapshot presentation)
    {
        ThreadInboxSecondaryModeIcon.Width = presentation.OverflowIconWidth;
        ThreadInboxSecondaryModeIcon.Height = presentation.OverflowIconHeight;
        var fill = BrushFromHex(presentation.OverflowFillHex);
        foreach (var dot in new[]
        {
            ThreadInboxSecondaryModeDotLeft,
            ThreadInboxSecondaryModeDotMiddle,
            ThreadInboxSecondaryModeDotRight
        })
        {
            dot.Width = presentation.OverflowDotSize;
            dot.Height = presentation.OverflowDotSize;
            dot.Fill = fill;
        }

        Canvas.SetLeft(ThreadInboxSecondaryModeDotLeft, 2.3);
        Canvas.SetLeft(
            ThreadInboxSecondaryModeDotMiddle,
            2.3 + presentation.OverflowDotSize + presentation.OverflowDotSpacing);
        Canvas.SetLeft(
            ThreadInboxSecondaryModeDotRight,
            2.3 + ((presentation.OverflowDotSize + presentation.OverflowDotSpacing) * 2));
        Canvas.SetTop(ThreadInboxSecondaryModeDotLeft, 6.4);
        Canvas.SetTop(ThreadInboxSecondaryModeDotMiddle, 6.4);
        Canvas.SetTop(ThreadInboxSecondaryModeDotRight, 6.4);
    }

    private void ApplyInboxModeButton(
        Button button,
        bool selected,
        ThreadInboxModePickerPresentationSnapshot modePickerPresentation)
    {
        button.Height = modePickerPresentation.PrimaryButtonHeight;
        button.MinHeight = 0;
        button.Padding = new Thickness(
            modePickerPresentation.PrimaryButtonHorizontalPadding,
            modePickerPresentation.PrimaryButtonVerticalPadding,
            modePickerPresentation.PrimaryButtonHorizontalPadding,
            modePickerPresentation.PrimaryButtonVerticalPadding);
        button.CornerRadius = new CornerRadius(modePickerPresentation.PrimaryButtonCornerRadius);
        button.BorderThickness = new Thickness(modePickerPresentation.PrimaryButtonBorderThickness);
        button.FontSize = modePickerPresentation.PrimaryButtonFontSize;
        button.Background = BrushFromHex(selected
            ? ThreadInboxModePickerPresentation.SelectedBackgroundHex
            : ThreadInboxModePickerPresentation.InactiveBackgroundHex);
        button.Foreground = BrushFromHex(selected
            ? ThreadInboxModePickerPresentation.SelectedFillHex
            : ThreadInboxModePickerPresentation.InactiveFillHex);
        button.BorderBrush = BrushFromHex(selected
            ? ThreadInboxModePickerPresentation.SelectedBorderHex
            : ThreadInboxModePickerPresentation.InactiveBorderHex);
    }

    private static bool IsSecondaryThreadInboxMode(string mode)
    {
        return mode is ThreadInboxModeNeedsYou
            or ThreadInboxModeUnread
            or ThreadInboxModeRecent
            or ThreadInboxModeArchived;
    }

    private async Task RefreshWorkflowMembershipsAsync()
    {
        _threadWorkflowMembershipsByThreadId.Clear();
        _threadInboxCatalogThreadsByKey.Clear();

        if (!File.Exists(_store.LibraryPath))
        {
            RefreshThreadInboxWorkflowFilters();
            return;
        }

        await using var stream = File.OpenRead(_store.LibraryPath);
        var library = await JsonSerializer.DeserializeAsync<ThreadInboxWorkflowLibraryDocument>(
            stream,
            MapofAgentsJson.Options);

        if (library is not null)
        {
            foreach (var workflow in library.Workflows)
            {
                AddWorkflowMemberships(workflow, library.ActiveWorkflowID);
            }
        }

        RefreshThreadInboxWorkflowFilters();
    }

    private void AddWorkflowMemberships(ThreadInboxWorkflowLibraryItem workflow, string? activeWorkflowID)
    {
        var workflowName = string.IsNullOrWhiteSpace(workflow.Name)
            ? workflow.Graph.Title
            : workflow.Name;
        if (string.IsNullOrWhiteSpace(workflowName))
        {
            workflowName = workflow.ID;
        }

        foreach (var node in workflow.Graph.Nodes.Values.Where(node => node.Kind == NodeKinds.CodexThread))
        {
            var key = ThreadQualifiedID(node);
            if (key is null)
            {
                continue;
            }

            var isActiveWorkflow = string.Equals(workflow.ID, activeWorkflowID, StringComparison.OrdinalIgnoreCase);
            RecordThreadInboxCatalogThread(
                key,
                workflow.ID,
                workflowName,
                node,
                isActiveWorkflow);

            _threadWorkflowMembershipsByThreadId.TryAdd(key, []);
            _threadWorkflowMembershipsByThreadId[key].RemoveAll(membership =>
                string.Equals(membership.WorkflowID, workflow.ID, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(membership.NodeID, node.Id, StringComparison.OrdinalIgnoreCase));
            _threadWorkflowMembershipsByThreadId[key].Add(new ThreadWorkflowMembership(
                workflow.ID,
                workflowName,
                node.Id,
                isActiveWorkflow));
        }
    }

    private void RecordThreadInboxCatalogThread(
        string key,
        string workflowID,
        string workflowName,
        CanvasNode node,
        bool isActiveWorkflow)
    {
        var snapshot = new ThreadInboxCatalogThread(
            key,
            workflowID,
            workflowName,
            node.Id,
            isActiveWorkflow,
            CloneCanvasNode(node));

        if (!_threadInboxCatalogThreadsByKey.TryGetValue(key, out var existing) ||
            !existing.IsActiveWorkflow && isActiveWorkflow)
        {
            _threadInboxCatalogThreadsByKey[key] = snapshot;
        }
    }

    private IEnumerable<ThreadInboxCatalogThread> CatalogThreadCandidates(IReadOnlySet<string> activeThreadKeys)
    {
        return _threadInboxCatalogThreadsByKey.Values
            .Concat(_threadInboxServerCatalogThreadsByKey.Values)
            .GroupBy(thread => thread.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .Where(thread =>
            !thread.IsActiveWorkflow &&
            !activeThreadKeys.Contains(thread.Key));
    }

    private void RebuildAppServerEndpointsFromGraph()
    {
        foreach (var machine in MachineNodes)
        {
            if (machine.Metadata.HostStatus != HostStatuses.Connected ||
                string.IsNullOrWhiteSpace(machine.Metadata.AppServerEndpointUrl) ||
                !Uri.TryCreate(machine.Metadata.AppServerEndpointUrl, UriKind.Absolute, out var url) ||
                !AppServerEndpointValidator.IsLoopback(url))
            {
                continue;
            }

            var endpoint = new AppServerEndpoint(machine.Title, url, null);
            if (IsLocalHostId(machine.Metadata.HostID))
            {
                RegisterLocalAppServerEndpoint(endpoint);
            }
            else
            {
                _connectedAppServerEndpointsByHostId[machine.Id] = endpoint;
            }
        }
    }

    private async Task SearchAppServerThreadCatalogWithDelayAsync()
    {
        var generation = ++_threadInboxSearchGeneration;
        await Task.Delay(350);
        if (generation != _threadInboxSearchGeneration ||
            _threadInboxMode != ThreadInboxModeSearch ||
            string.IsNullOrWhiteSpace(ThreadInboxSearchBox.Text))
        {
            return;
        }

        await RefreshAppServerThreadCatalogAsync(search: true);
    }

    private async Task RefreshAppServerThreadCatalogAsync(bool search)
    {
        var endpoints = AppServerCatalogEndpoints().ToList();
        if (endpoints.Count == 0)
        {
            _threadInboxWarningMessage = null;
            UpdateThreadInbox();
            return;
        }

        if (_isRefreshingAppServerInbox)
        {
            return;
        }

        _isRefreshingAppServerInbox = true;
        ThreadInboxSummaryText.Text = "Refreshing app-server threads...";
        ThreadInboxSummaryText.Visibility = Visibility.Visible;

        try
        {
            var query = ThreadInboxSearchBox.Text.Trim();
            var nextCatalog = search
                ? new Dictionary<string, ThreadInboxCatalogThread>(_threadInboxServerCatalogThreadsByKey, StringComparer.OrdinalIgnoreCase)
                : new Dictionary<string, ThreadInboxCatalogThread>(StringComparer.OrdinalIgnoreCase);
            var loadedCount = 0;
            var client = new AppServerClient();
            using var refreshCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(6));
            foreach (var (hostID, endpoint) in endpoints)
            {
                IReadOnlyList<AppServerThreadCatalogEntry> entries = search && !string.IsNullOrWhiteSpace(query)
                    ? await client.SearchThreadCatalogAsync(endpoint, hostID, query, cancellationToken: refreshCancellation.Token)
                    : await client.ListThreadCatalogAsync(endpoint, hostID, cancellationToken: refreshCancellation.Token);

                foreach (var entry in entries)
                {
                    var key = ThreadQualifiedID(entry.ThreadRef);
                    if (string.IsNullOrWhiteSpace(key))
                    {
                        continue;
                    }

                    nextCatalog[key] = ThreadInboxCatalogThreadFromAppServer(entry, key);
                    loadedCount++;
                }
            }

            _threadInboxServerCatalogThreadsByKey.Clear();
            foreach (var pair in nextCatalog)
            {
                _threadInboxServerCatalogThreadsByKey[pair.Key] = pair.Value;
            }

            _threadInboxWarningMessage = null;
            AddActivity(search
                ? $"Searched {loadedCount} app-server thread result{(loadedCount == 1 ? "" : "s")}."
                : $"Loaded {loadedCount} app-server thread{(loadedCount == 1 ? "" : "s")}.");
        }
        catch (Exception exception)
        {
            _threadInboxWarningMessage = exception.Message;
            AddActivity(
                $"Thread inbox app-server refresh failed: {exception.Message}",
                showTopNotification: true,
                notificationKind: ActivityNotificationKindFailed);
        }
        finally
        {
            _isRefreshingAppServerInbox = false;
            UpdateChrome();
        }
    }

    private IEnumerable<(string HostID, AppServerEndpoint Endpoint)> AppServerCatalogEndpoints()
    {
        foreach (var machine in MachineNodes.Where(machine => machine.Metadata.HostStatus == HostStatuses.Connected))
        {
            var hostID = IsLocalHostId(machine.Metadata.HostID)
                ? LocalHostIdentity.CanonicalHostID
                : machine.Id;
            if (_connectedAppServerEndpointsByHostId.TryGetValue(hostID, out var endpoint) ||
                _connectedAppServerEndpointsByHostId.TryGetValue(machine.Id, out endpoint))
            {
                yield return (hostID, endpoint);
                continue;
            }

            if (IsLocalHostId(machine.Metadata.HostID))
            {
                continue;
            }

            if (string.IsNullOrWhiteSpace(machine.Metadata.AppServerEndpointUrl) ||
                !Uri.TryCreate(machine.Metadata.AppServerEndpointUrl, UriKind.Absolute, out var url) ||
                !AppServerEndpointValidator.IsLoopback(url))
            {
                continue;
            }

            yield return (machine.Id, new AppServerEndpoint(machine.Title, url, null));
        }
    }

    private ThreadInboxCatalogThread ThreadInboxCatalogThreadFromAppServer(
        AppServerThreadCatalogEntry entry,
        string key)
    {
        var node = new CanvasNode
        {
            Id = $"thread-{entry.ThreadRef.ThreadID}",
            Kind = NodeKinds.CodexThread,
            Title = entry.Title,
            Subtitle = string.IsNullOrWhiteSpace(entry.ThreadRef.Cwd)
                ? entry.HostName
                : entry.ThreadRef.Cwd,
            Position = NextThreadPosition(),
            Size = CanvasSize.Thread,
            Metadata = new NodeMetadata
            {
                HostID = entry.ThreadRef.HostID,
                Platform = PlatformForHost(entry.ThreadRef.HostID),
                ThreadRef = entry.ThreadRef,
                Model = entry.Model,
                ReasoningEffort = entry.ReasoningEffort,
                ThreadKind = entry.ThreadKind,
                ApprovalPolicy = "on-request",
                SandboxMode = "workspace-write",
                RunStatus = entry.Status,
                IsArchived = entry.Archived,
                LocalTranscript = string.IsNullOrWhiteSpace(entry.Preview)
                    ? new List<LocalThreadMessage>()
                    : new List<LocalThreadMessage>
                    {
                        new()
                        {
                            Role = "assistant",
                            Text = entry.Preview,
                            CreatedAt = entry.LastActivityAt
                        }
                    }
            }
        };

        return new ThreadInboxCatalogThread(
            key,
            "app-server",
            entry.HostName,
            node.Id,
            IsActiveWorkflowThreadKey(key),
            node);
    }

    private bool IsActiveWorkflowThreadKey(string key)
    {
        return ThreadNodes.Any(node =>
            string.Equals(ThreadQualifiedID(node), key, StringComparison.OrdinalIgnoreCase));
    }

    private async Task AddInboxThreadToCanvasAsync(ThreadInboxItem item)
    {
        if (!string.IsNullOrWhiteSpace(item.ActiveNodeId) &&
            _graph.Nodes.TryGetValue(item.ActiveNodeId, out var activeNode))
        {
            await FocusThreadNodeAsync(activeNode, $"Opened {activeNode.Title} from inbox.");
            return;
        }

        if (!_threadInboxCatalogThreadsByItemId.TryGetValue(item.Id, out var catalogThread))
        {
            AddActivity("That inbox thread is no longer available.");
            UpdateChrome();
            return;
        }

        var source = catalogThread.Node;
        var node = CloneCanvasNode(source);
        node.Id = UniqueNodeId(string.IsNullOrWhiteSpace(source.Id) ? $"thread-{Guid.NewGuid():N}" : source.Id);
        node.Kind = NodeKinds.CodexThread;
        node.Size = CanvasSize.Thread;
        node.ZIndex = _graph.Nodes.Count;
        node.Metadata.IsArchived = false;
        node.Metadata.HasManualPosition = false;
        node.Metadata.ThreadRef ??= new ThreadRef
        {
            HostID = node.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID,
            ThreadID = source.Id,
            Cwd = "",
            Name = source.Title
        };
        node.Metadata.ThreadRef.Name ??= source.Title;
        node.Metadata.HostID ??= node.Metadata.ThreadRef.HostID;
        node.Metadata.Platform ??= PlatformForHost(node.Metadata.ThreadRef.HostID);

        var anchor = AnchorNodeForThread(node);
        node.Position = NextThreadPosition(anchor);
        _graph.Nodes[node.Id] = node;
        if (anchor is not null)
        {
            var edgeID = $"edge-{Guid.NewGuid():N}";
            _graph.ManualEdges[edgeID] = new CanvasEdge
            {
                Id = edgeID,
                Source = anchor.Id,
                Target = node.Id,
                Kind = anchor.Kind == NodeKinds.Folder ? EdgeKinds.FolderThread : EdgeKinds.MachineThread,
                IsManual = false
            };
        }

        await SaveGraphAsync();
        await RenderGraphAsync();
        await FocusThreadNodeAsync(node, $"Added {node.Title} to the current workflow.");
    }

    private CanvasPoint NextThreadPosition()
    {
        return AvoidCollisions(NextOpenPosition());
    }

    private CanvasPoint NextThreadPosition(CanvasNode? anchor)
    {
        if (anchor?.Kind == NodeKinds.Folder)
        {
            return AvoidCollisions(new CanvasPoint(
                anchor.Position.X,
                anchor.Position.Y + anchor.Size.Height + 150));
        }

        if (anchor is not null)
        {
            return AvoidCollisions(new CanvasPoint(
                anchor.Position.X + anchor.Size.Width + 170,
                anchor.Position.Y + 120));
        }

        return NextThreadPosition();
    }

    private CanvasPoint NextFolderPosition(CanvasNode machine)
    {
        var hostID = machine.Metadata.HostID;
        var existingFolderCount = FolderNodes.Count(folder =>
            string.Equals(folder.Metadata.HostID, hostID, StringComparison.OrdinalIgnoreCase));
        return AvoidCollisions(new CanvasPoint(
            machine.Position.X + 220 + existingFolderCount * 300,
            Math.Max(330, machine.Position.Y + 200)));
    }

    private CanvasPoint NextMachinePosition()
    {
        return AvoidCollisions(new CanvasPoint(140 + MachineNodes.Count() * 280, 130));
    }

    private CanvasPoint NextOpenPosition()
    {
        var count = _graph.Nodes.Count;
        return new CanvasPoint(180 + (count % 4) * 240, 180 + (count / 4) * 150);
    }

    private CanvasPoint AvoidCollisions(CanvasPoint point)
    {
        var candidate = point;
        for (var attempt = 1; attempt < 80 && _graph.Nodes.Values.Any(node => Overlaps(candidate, node)); attempt++)
        {
            var column = attempt % 5;
            var row = attempt / 5;
            candidate = new CanvasPoint(
                point.X + column * 240 + (row % 2) * 72,
                point.Y + row * 150);
        }

        return candidate;
    }

    private static bool Overlaps(CanvasPoint point, CanvasNode node)
    {
        var horizontalDistance = Math.Abs(point.X - node.Position.X);
        var verticalDistance = Math.Abs(point.Y - node.Position.Y);
        return horizontalDistance < node.Size.Width / 2 + CanvasSize.Thread.Width / 2 + 24 &&
               verticalDistance < node.Size.Height / 2 + CanvasSize.Thread.Height / 2 + 24;
    }

    private CanvasNode? AnchorNodeForThread(CanvasNode node)
    {
        var hostID = node.Metadata.ThreadRef?.HostID ?? node.Metadata.HostID;
        var cwd = node.Metadata.ThreadRef?.Cwd;
        if (!string.IsNullOrWhiteSpace(cwd))
        {
            var matchingFolder = FolderNodes.FirstOrDefault(folder =>
                SameIdentifier(folder.Metadata.HostID, hostID) &&
                SamePath(folder.Metadata.FolderPath ?? folder.Subtitle, cwd));
            if (matchingFolder is not null)
            {
                return matchingFolder;
            }
        }

        var hostFolder = FolderNodes.FirstOrDefault(folder => SameIdentifier(folder.Metadata.HostID, hostID));
        if (hostFolder is not null)
        {
            return hostFolder;
        }

        return MachineNodes.FirstOrDefault(machine => SameIdentifier(machine.Metadata.HostID, hostID));
    }

    private string PlatformForHost(string? hostID)
    {
        return MachineNodes.FirstOrDefault(machine => SameIdentifier(machine.Metadata.HostID, hostID))?.Metadata.Platform
            ?? HostPlatforms.Windows;
    }

    private CanvasNode? MachineForHost(string? hostID)
    {
        if (string.IsNullOrWhiteSpace(hostID))
        {
            return null;
        }

        return MachineNodes.FirstOrDefault(machine =>
            SameIdentifier(machine.Id, hostID) ||
            SameIdentifier(machine.Metadata.HostID, hostID));
    }

    private string UniqueNodeId(string preferredId)
    {
        var candidate = string.IsNullOrWhiteSpace(preferredId)
            ? $"thread-{Guid.NewGuid():N}"
            : preferredId;
        if (!_graph.Nodes.ContainsKey(candidate))
        {
            return candidate;
        }

        do
        {
            candidate = $"thread-{Guid.NewGuid():N}";
        } while (_graph.Nodes.ContainsKey(candidate));
        return candidate;
    }

    private static string PreferredThreadNodeId(ThreadRef threadRef)
    {
        var threadID = threadRef.ThreadID.Trim();
        var safeThreadID = new string(threadID
            .Select(character => char.IsLetterOrDigit(character) || character is '-' or '_' ? character : '-')
            .ToArray())
            .Trim('-');
        if (string.IsNullOrWhiteSpace(safeThreadID))
        {
            return $"thread-{Guid.NewGuid():N}";
        }

        return safeThreadID.StartsWith("thread-", StringComparison.OrdinalIgnoreCase)
            ? safeThreadID
            : $"thread-{safeThreadID}";
    }

    private static bool SamePath(string? lhs, string? rhs)
    {
        static string Normalize(string? value)
        {
            return (value ?? "")
                .Trim()
                .TrimEnd('\\', '/')
                .Replace('/', '\\');
        }

        return !string.IsNullOrWhiteSpace(lhs) &&
            !string.IsNullOrWhiteSpace(rhs) &&
            string.Equals(Normalize(lhs), Normalize(rhs), StringComparison.OrdinalIgnoreCase);
    }

    private void RefreshThreadInboxWorkflowFilters()
    {
        _isUpdatingThreadInboxWorkflowFilters = true;
        try
        {
            var selectedFilter = _threadInboxWorkflowFilter;
            _threadInboxWorkflowFilters.Clear();
            AddBaseThreadInboxWorkflowFilters();

            foreach (var option in ThreadInboxWorkflowFilterOptions())
            {
                var title = ThreadInboxWorkflowFilterPresentation.WorkflowTitle(
                    option.WorkflowName,
                    option.Count);

                _threadInboxWorkflowFilters.Add(ThreadInboxWorkflowFilterItemFor(
                    $"{WorkflowFilterWorkflowPrefix}{option.WorkflowID}",
                    title,
                    option.IsActiveWorkflow));
            }

            var selectedItem = _threadInboxWorkflowFilters.FirstOrDefault(item =>
                string.Equals(item.Id, selectedFilter, StringComparison.OrdinalIgnoreCase));
            if (selectedItem is null && string.Equals(selectedFilter, WorkflowFilterThisWorkflow, StringComparison.OrdinalIgnoreCase))
            {
                selectedItem = _threadInboxWorkflowFilters.FirstOrDefault(item =>
                    item.Id.StartsWith(WorkflowFilterWorkflowPrefix, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(item.Id[WorkflowFilterWorkflowPrefix.Length..], _graph.WorkspaceID, StringComparison.OrdinalIgnoreCase));
            }

            selectedItem ??= _threadInboxWorkflowFilters.First();
            _threadInboxWorkflowFilter = selectedItem.Id;
            ThreadInboxWorkflowFilterBox.SelectedItem = selectedItem;
        }
        finally
        {
            _isUpdatingThreadInboxWorkflowFilters = false;
        }
    }

    private void SeedThreadInboxWorkflowFilters()
    {
        if (_threadInboxWorkflowFilters.Count > 0)
        {
            return;
        }

        _isUpdatingThreadInboxWorkflowFilters = true;
        try
        {
            AddBaseThreadInboxWorkflowFilters();
            _threadInboxWorkflowFilter = WorkflowFilterAll;
            ThreadInboxWorkflowFilterBox.SelectedItem = _threadInboxWorkflowFilters[0];
        }
        finally
        {
            _isUpdatingThreadInboxWorkflowFilters = false;
        }
    }

    private void AddBaseThreadInboxWorkflowFilters()
    {
        _threadInboxWorkflowFilters.Add(ThreadInboxWorkflowFilterItemFor(WorkflowFilterAll, "All threads"));
        _threadInboxWorkflowFilters.Add(ThreadInboxWorkflowFilterItemFor(WorkflowFilterOnWorkflows, "On workflows"));
        _threadInboxWorkflowFilters.Add(ThreadInboxWorkflowFilterItemFor(WorkflowFilterNotOnWorkflows, "Not on workflows"));
    }

    private IEnumerable<ThreadInboxWorkflowFilterOption> ThreadInboxWorkflowFilterOptions()
    {
        var countsByID = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var namesByID = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var activeIDs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var activeThreadKeys = ThreadNodes
            .Select(ThreadQualifiedID)
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .Select(key => key!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        void CountMemberships(IEnumerable<ThreadWorkflowMembership> memberships)
        {
            var seenForThread = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var membership in memberships)
            {
                if (!seenForThread.Add(membership.WorkflowID))
                {
                    continue;
                }

                countsByID[membership.WorkflowID] = countsByID.GetValueOrDefault(membership.WorkflowID) + 1;
                namesByID.TryAdd(membership.WorkflowID, membership.WorkflowName);
                if (membership.IsActiveWorkflow)
                {
                    activeIDs.Add(membership.WorkflowID);
                }
            }
        }

        foreach (var node in ThreadNodes)
        {
            CountMemberships(WorkflowMembershipsFor(node));
        }

        foreach (var catalogThread in CatalogThreadCandidates(activeThreadKeys))
        {
            CountMemberships(WorkflowMembershipsForKey(catalogThread.Key, activeNodeId: null));
        }

        return countsByID
            .Select(pair => new ThreadInboxWorkflowFilterOption(
                pair.Key,
                namesByID.GetValueOrDefault(pair.Key) ?? pair.Key,
                pair.Value,
                activeIDs.Contains(pair.Key)))
            .OrderByDescending(option => option.IsActiveWorkflow)
            .ThenBy(option => option.WorkflowName, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static ThreadInboxWorkflowFilterItem ThreadInboxWorkflowFilterItemFor(
        string id,
        string title,
        bool isActiveWorkflow = false)
    {
        var presentation = ThreadInboxWorkflowFilterPresentation.Resolve(
            WorkflowFilterPresentationKindFor(id),
            isActiveWorkflow);
        return new ThreadInboxWorkflowFilterItem(
            id,
            title,
            WorkflowFilterGlyphFor(id, isActiveWorkflow),
            WorkflowFilterBrushFor(id, isActiveWorkflow),
            presentation.IconKind);
    }

    private static string WorkflowFilterPresentationKindFor(string id)
    {
        return id switch
        {
            WorkflowFilterAll => ThreadInboxWorkflowFilterPresentation.All,
            WorkflowFilterOnWorkflows => ThreadInboxWorkflowFilterPresentation.OnWorkflows,
            WorkflowFilterNotOnWorkflows => ThreadInboxWorkflowFilterPresentation.NotOnWorkflows,
            _ when id.StartsWith(WorkflowFilterWorkflowPrefix, StringComparison.OrdinalIgnoreCase) =>
                ThreadInboxWorkflowFilterPresentation.Workflow,
            _ => ThreadInboxWorkflowFilterPresentation.All
        };
    }

    private static string WorkflowFilterGlyphFor(string id, bool isActiveWorkflow)
    {
        if (isActiveWorkflow)
        {
            return "\uE73E";
        }

        return id switch
        {
            WorkflowFilterAll => "\uE8BD",
            WorkflowFilterOnWorkflows => "\uECA5",
            WorkflowFilterNotOnWorkflows => "\uE711",
            _ when id.StartsWith(WorkflowFilterWorkflowPrefix, StringComparison.OrdinalIgnoreCase) => "\uECA5",
            _ => "\uE8BD"
        };
    }

    private static SolidColorBrush WorkflowFilterBrushFor(string id, bool isActiveWorkflow)
    {
        if (isActiveWorkflow)
        {
            return BrushFromHex("#0A84FF");
        }

        return id switch
        {
            WorkflowFilterAll => BrushFromHex("#A7B0BF"),
            WorkflowFilterOnWorkflows => BrushFromHex("#0A84FF"),
            WorkflowFilterNotOnWorkflows => BrushFromHex("#8F9BAA"),
            _ when id.StartsWith(WorkflowFilterWorkflowPrefix, StringComparison.OrdinalIgnoreCase) => BrushFromHex("#A7B0BF"),
            _ => BrushFromHex("#A7B0BF")
        };
    }

    private bool NodeMatchesThreadInboxMode(CanvasNode node)
    {
        var isArchived = node.Metadata.IsArchived == true;
        if (_threadInboxMode == ThreadInboxModeArchived)
        {
            return isArchived;
        }

        if (isArchived)
        {
            return false;
        }

        var isFinished = IsFinishedThread(node);
        return _threadInboxMode switch
        {
            ThreadInboxModeFinished => isFinished,
            ThreadInboxModeNeedsYou => (node.Metadata.RunStatus ?? ThreadRunStatuses.Idle) == ThreadRunStatuses.NeedsInput ||
                HasPendingAttention(node),
            ThreadInboxModeUnread => node.Metadata.IsUnread == true,
            ThreadInboxModeRecent => true,
            ThreadInboxModeSearch => true,
            _ => !isFinished
        };
    }

    private bool NodeMatchesWorkflowFilter(CanvasNode node)
    {
        return MatchesWorkflowFilter(WorkflowMembershipsFor(node));
    }

    private bool MatchesWorkflowFilter(IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        var isOnWorkflow = memberships.Count > 0;
        return _threadInboxWorkflowFilter switch
        {
            WorkflowFilterOnWorkflows => isOnWorkflow,
            WorkflowFilterNotOnWorkflows => !isOnWorkflow,
            WorkflowFilterThisWorkflow => memberships.Any(membership => membership.IsActiveWorkflow),
            var workflowFilter when workflowFilter.StartsWith(WorkflowFilterWorkflowPrefix, StringComparison.OrdinalIgnoreCase) =>
                memberships.Any(membership => string.Equals(
                    membership.WorkflowID,
                    workflowFilter[WorkflowFilterWorkflowPrefix.Length..],
                    StringComparison.OrdinalIgnoreCase)),
            _ => true
        };
    }

    private List<ThreadWorkflowMembership> WorkflowMembershipsFor(CanvasNode node)
    {
        return WorkflowMembershipsForKey(ThreadQualifiedID(node), node.Id);
    }

    private List<ThreadWorkflowMembership> WorkflowMembershipsForKey(string? threadKey, string? activeNodeId)
    {
        var memberships = new List<ThreadWorkflowMembership>();
        if (!string.IsNullOrWhiteSpace(threadKey) &&
            _threadWorkflowMembershipsByThreadId.TryGetValue(threadKey, out var savedMemberships))
        {
            memberships.AddRange(savedMemberships);
        }

        if (!string.IsNullOrWhiteSpace(activeNodeId) &&
            !string.IsNullOrWhiteSpace(_graph.WorkspaceID) &&
            !memberships.Any(membership =>
                string.Equals(membership.WorkflowID, _graph.WorkspaceID, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(membership.NodeID, activeNodeId, StringComparison.OrdinalIgnoreCase)))
        {
            memberships.Add(new ThreadWorkflowMembership(
                _graph.WorkspaceID,
                ActiveWorkflowName(),
                activeNodeId,
                true));
        }

        return memberships
            .GroupBy(membership => $"{membership.WorkflowID}::{membership.NodeID}", StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderByDescending(membership => membership.IsActiveWorkflow)
            .ThenBy(membership => membership.WorkflowName, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private string ActiveWorkflowName()
    {
        var activeWorkflowTitle = _workflowMenuItems
            .FirstOrDefault(item => item.IsActive)
            ?.Title;
        return ToolbarWorkflowPresentation.DisplayActiveTitle(activeWorkflowTitle, _graph.Title);
    }

    private static string? ThreadQualifiedID(CanvasNode node)
    {
        var threadRef = node.Metadata.ThreadRef;
        if (threadRef is null ||
            string.IsNullOrWhiteSpace(threadRef.HostID) ||
            string.IsNullOrWhiteSpace(threadRef.ThreadID))
        {
            return null;
        }

        return $"{threadRef.HostID}::{threadRef.ThreadID}";
    }

    private static string? ThreadQualifiedID(ThreadRef threadRef)
    {
        if (string.IsNullOrWhiteSpace(threadRef.HostID) ||
            string.IsNullOrWhiteSpace(threadRef.ThreadID))
        {
            return null;
        }

        return $"{threadRef.HostID}::{threadRef.ThreadID}";
    }

    private static bool IsFinishedThread(CanvasNode node)
    {
        var status = node.Metadata.RunStatus ?? ThreadRunStatuses.Idle;
        return status is ThreadRunStatuses.Complete or ThreadRunStatuses.Failed;
    }

    private Dictionary<string, int> PendingAttentionCountsByNodeId()
    {
        var counts = new Dictionary<string, int>();
        foreach (var request in _graph.PendingAttentionRequests)
        {
            var node = NodeForAttentionRequest(request);
            if (node is null)
            {
                continue;
            }

            counts[node.Id] = counts.GetValueOrDefault(node.Id) + 1;
        }

        return counts;
    }

    private bool HasPendingAttention(CanvasNode node)
    {
        return _graph.PendingAttentionRequests.Any(request => AttentionRequestMatchesNode(request, node));
    }

    private CanvasNode? NodeForAttentionRequest(RuntimeAttentionRequest request)
    {
        return ThreadNodes.FirstOrDefault(node => AttentionRequestMatchesNode(request, node));
    }

    private static bool AttentionRequestMatchesNode(RuntimeAttentionRequest request, CanvasNode node)
    {
        var threadID = node.Metadata.ThreadRef?.ThreadID ?? node.Id;
        if (!SameIdentifier(request.ThreadID, threadID))
        {
            return false;
        }

        var requestHostID = request.HostID;
        if (string.IsNullOrWhiteSpace(requestHostID))
        {
            return true;
        }

        return SameIdentifier(requestHostID, node.Metadata.ThreadRef?.HostID) ||
            SameIdentifier(requestHostID, node.Metadata.HostID);
    }

    private static bool SameIdentifier(string? lhs, string? rhs)
    {
        return !string.IsNullOrWhiteSpace(lhs) &&
            !string.IsNullOrWhiteSpace(rhs) &&
            string.Equals(lhs, rhs, StringComparison.OrdinalIgnoreCase);
    }

    private static string AttentionPromptText(RuntimeAttentionRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.Prompt))
        {
            return request.Prompt.Trim();
        }

        if (request.RequestParams is { } parameters && parameters.ValueKind == JsonValueKind.Object)
        {
            if (parameters.TryGetProperty("questions", out var questions) &&
                questions.ValueKind == JsonValueKind.Array)
            {
                foreach (var question in questions.EnumerateArray())
                {
                    if (TryGetJsonString(question, "question", out var questionText) ||
                        TryGetJsonString(question, "header", out questionText))
                    {
                        return questionText;
                    }
                }
            }

            if (TryGetJsonString(parameters, "message", out var message) ||
                TryGetJsonString(parameters, "prompt", out message) ||
                TryGetJsonString(parameters, "summary", out message))
            {
                return message;
            }
        }

        return string.IsNullOrWhiteSpace(request.Summary) ? request.Method : request.Summary;
    }

    private static bool TryGetJsonString(JsonElement element, string propertyName, out string value)
    {
        value = "";
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var property) ||
            property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = property.GetString()?.Trim() ?? "";
        return !string.IsNullOrWhiteSpace(value);
    }

    private static string ThreadInboxModeDisplayLabel(string mode)
    {
        return mode switch
        {
            ThreadInboxModeFinished => "finished",
            ThreadInboxModeNeedsYou => "needs you",
            ThreadInboxModeUnread => "unread",
            ThreadInboxModeRecent => "recent",
            ThreadInboxModeSearch => "search",
            ThreadInboxModeArchived => "archived",
            _ => "active"
        };
    }

    private static string ThreadInboxModeLabel(string mode)
    {
        return mode switch
        {
            ThreadInboxModeFinished => "finished",
            ThreadInboxModeNeedsYou => "needs",
            ThreadInboxModeUnread => "unread",
            ThreadInboxModeRecent => "recent",
            ThreadInboxModeSearch => "search",
            ThreadInboxModeArchived => "archived",
            _ => "active"
        };
    }

    private string MachineTitleFor(CanvasNode node)
    {
        var hostID = node.Metadata.HostID;
        return MachineNodes.FirstOrDefault(machine => machine.Metadata.HostID == hostID)?.Title
            ?? node.Metadata.Platform
            ?? "Local";
    }

    private static string ThreadKindLabelFor(CanvasNode node)
    {
        return LooksLikeSubagent(node) ? "Subagent" : "Thread";
    }

    private static string ThreadKindGlyphFor(CanvasNode node)
    {
        return LooksLikeSubagent(node) ? "\uE716" : "\uE8F2";
    }

    private static SolidColorBrush ThreadKindBrushFor(CanvasNode node)
    {
        return LooksLikeSubagent(node) ? BrushFromHex("#BF5AF2") : BrushFromHex("#A7B0BF");
    }

    private static SolidColorBrush ThreadKindBackgroundFor(CanvasNode node)
    {
        return LooksLikeSubagent(node) ? BrushFromHex("#22BF5AF2") : BrushFromHex("#16697586");
    }

    private static bool LooksLikeSubagent(CanvasNode node)
    {
        if (string.Equals(node.Metadata.ThreadKind, ThreadKinds.Subagent, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return node.Metadata.InitialPrompt?.Contains("subagent", StringComparison.OrdinalIgnoreCase) == true ||
            node.Subtitle.Contains("subagent", StringComparison.OrdinalIgnoreCase) ||
            node.Title.Contains("subagent", StringComparison.OrdinalIgnoreCase);
    }

    private string WorkflowLabelFor(CanvasNode node)
    {
        return WorkflowLabelFor(WorkflowMembershipsFor(node));
    }

    private static string WorkflowLabelFor(IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        var active = memberships.FirstOrDefault(membership => membership.IsActiveWorkflow);
        if (active is not null)
        {
            if (memberships.Count > 1)
            {
                return $"Current workflow: {active.WorkflowName} + {memberships.Count - 1} more";
            }

            return $"Current workflow: {active.WorkflowName}";
        }

        if (memberships.Count == 1)
        {
            return memberships[0].WorkflowName;
        }

        if (memberships.Count > 1)
        {
            return "Multiple workflows";
        }

        return "Not on a workflow";
    }

    private string WorkflowGlyphFor(CanvasNode node)
    {
        return WorkflowGlyphFor(WorkflowMembershipsFor(node));
    }

    private static string WorkflowGlyphFor(IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        return WorkflowMembershipPresentationFor(memberships).Glyph;
    }

    private static string WorkflowIconKindFor(IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        return WorkflowMembershipPresentationFor(memberships).IconKind;
    }

    private static ThreadInboxWorkflowMembershipPresentationSnapshot WorkflowMembershipPresentationFor(
        IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        return ThreadInboxWorkflowMembershipPresentation.Resolve(
            memberships.Any(membership => membership.IsActiveWorkflow),
            memberships.Select(membership => membership.WorkflowID)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count());
    }

    private SolidColorBrush WorkflowBrushFor(CanvasNode node)
    {
        return WorkflowBrushFor(WorkflowMembershipsFor(node));
    }

    private static SolidColorBrush WorkflowBrushFor(IReadOnlyList<ThreadWorkflowMembership> memberships)
    {
        if (memberships.Any(membership => membership.IsActiveWorkflow))
        {
            return BrushFromHex("#0A84FF");
        }

        return memberships.Count == 0 ? BrushFromHex("#8F9BAA") : BrushFromHex("#A7B0BF");
    }

    private static string LiveStateGlyphFor(CanvasNode node, int pendingRequestCount)
    {
        return LiveStatePresentationFor(node, pendingRequestCount).Glyph;
    }

    private static SolidColorBrush LiveStateBrushFor(CanvasNode node, int pendingRequestCount)
    {
        return BrushFromHex(LiveStatePresentationFor(node, pendingRequestCount).ForegroundHex);
    }

    private static string LiveStateTextFor(CanvasNode node, int pendingRequestCount)
    {
        return LiveStatePresentationFor(node, pendingRequestCount).Text;
    }

    private static ThreadLiveStatePresentationSnapshot LiveStatePresentationFor(
        CanvasNode node,
        int pendingRequestCount)
    {
        return ThreadLiveStatePresentation.Resolve(
            node.Metadata.RunStatus,
            pendingRequestCount,
            LiveStateDetailFor(node));
    }

    private static string LiveStateDetailFor(CanvasNode node)
    {
        var detail = node.Metadata.LocalTranscript
            .OrderByDescending(message => message.CreatedAt)
            .Where(message => IsLiveStateDetailRole(message.Role))
            .Select(message => FirstLiveStateLine(message.Text))
            .FirstOrDefault(text => !string.IsNullOrWhiteSpace(text)) ?? "";

        return ClampInlineText(detail, 96);
    }

    private static string FirstLiveStateLine(string text)
    {
        return text
            .Trim()
            .Split(["\r\n", "\n", "\r"], StringSplitOptions.None)
            .FirstOrDefault()?
            .Trim() ?? "";
    }

    private static bool IsLiveStateDetailRole(string role)
    {
        return role.Equals("progress", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("event", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("tool", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsPreviewRole(string role)
    {
        return !role.Equals("system", StringComparison.OrdinalIgnoreCase) &&
            !IsLiveStateDetailRole(role);
    }

    private static string NormalizeInlineText(string text)
    {
        return string.Join(
            " ",
            text.Trim().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    private static string ClampInlineText(string text, int maxLength)
    {
        if (text.Length <= maxLength)
        {
            return text;
        }

        return $"{text[..Math.Max(0, maxLength - 3)]}...";
    }

    private static string InboxPreviewText(CanvasNode node)
    {
        var preview = node.Metadata.LocalTranscript
            .OrderByDescending(message => message.CreatedAt)
            .Where(message => IsPreviewRole(message.Role))
            .Select(message => NormalizeInlineText(message.Text))
            .FirstOrDefault(text => !string.IsNullOrWhiteSpace(text)) ?? "";

        return ClampInlineText(preview, 180);
    }

    private DateTimeOffset InboxActivityAt(CanvasNode node)
    {
        return node.Metadata.LocalTranscript.Count == 0
            ? _graph.UpdatedAt
            : node.Metadata.LocalTranscript.Max(message => message.CreatedAt);
    }

    private string InboxActivityLabel(CanvasNode node)
    {
        var activityAt = InboxActivityAt(node);
        return activityAt
            .ToLocalTime()
            .ToString("MMM d, yyyy 'at' h:mm:ss tt", CultureInfo.CurrentCulture);
    }

    private void ArrangeNodes()
    {
        var machines = MachineNodes.ToList();
        var folders = FolderNodes.ToList();
        var threads = ThreadNodes.ToList();

        for (var index = 0; index < machines.Count; index++)
        {
            machines[index].Position = new CanvasPoint(140 + index * 280, 130);
            machines[index].Metadata.HasManualPosition = false;
        }

        for (var index = 0; index < folders.Count; index++)
        {
            folders[index].Position = new CanvasPoint(230 + index * 470, 330);
            folders[index].Metadata.HasManualPosition = false;
        }

        for (var index = 0; index < threads.Count; index++)
        {
            threads[index].Position = new CanvasPoint(230 + (index % 3) * 290, 560 + (index / 3) * 196);
            threads[index].Metadata.HasManualPosition = false;
        }

        _graph.Viewport = new CanvasViewport();
    }

    private async Task SaveGraphAsync()
    {
        _graph.UpdatedAt = DateTimeOffset.UtcNow;
        try
        {
            await _store.SaveAsync(_graph);
            await RefreshWorkflowMembershipsAsync();
            SetStatusStripError(null);
        }
        catch (Exception exception)
        {
            SetStatusStripError(exception.Message);
            throw;
        }
    }

    private static CanvasNode CloneCanvasNode(CanvasNode node)
    {
        var json = JsonSerializer.Serialize(node, MapofAgentsJson.Options);
        return JsonSerializer.Deserialize<CanvasNode>(json, MapofAgentsJson.Options) ?? new CanvasNode();
    }

    private void SyncLocalRuntimeStatusFromGraph()
    {
        var localMachine = LocalMachineNode();
        if (localMachine is null)
        {
            UnregisterLocalAppServerEndpoint();
            SetStatus(
                HostStatuses.Disconnected,
                "Not connected",
                "No local machine node is registered.");
            return;
        }

        var status = localMachine.Metadata.HostStatus ?? HostStatuses.Disconnected;
        if (status == HostStatuses.Connected &&
            TryGetUsableLocalAppServerEndpoint(localMachine, out var endpoint))
        {
            SetStatus(HostStatuses.Connected, "Connected", endpoint.Url.ToString());
            return;
        }

        if (status == HostStatuses.Unavailable)
        {
            UnregisterLocalAppServerEndpoint(localMachine);
            var detail = localMachine.Metadata.HostLastError
                ?? _lastLocalSetupDetail
                ?? "Local Codex setup needs attention.";
            SetStatus(HostStatuses.Unavailable, "Local setup failed", detail);
            return;
        }

        if (status == HostStatuses.Connecting)
        {
            SetStatus(
                HostStatuses.Connecting,
                "Connecting",
                _lastLocalSetupDetail ?? "Starting local Codex App Server...");
            return;
        }

        UnregisterLocalAppServerEndpoint(localMachine);
        SetStatus(
            HostStatuses.Disconnected,
            "Not connected",
            status == HostStatuses.Connected
                ? "Connected machine node found; start the local App Server route."
                : "Local Codex App Server is not connected.");
    }

    private void SetStatus(string status, string message, string detail)
    {
        _localRuntimeStatus = StatusStripPresentation.NormalizeLocalStatus(status);
        _localRuntimeMessage = string.IsNullOrWhiteSpace(message)
            ? StatusStripPresentation.DefaultLocalMessage(_localRuntimeStatus)
            : message.Trim();
        _localRuntimeDetail = string.IsNullOrWhiteSpace(detail) ? _localRuntimeMessage : detail.Trim();
        UpdateLocalStatusStrip();
    }

    private void SetStatusStripError(string? message)
    {
        _statusStripErrorMessage = string.IsNullOrWhiteSpace(message) ? null : message.Trim();
        UpdateStatusStripError();
    }

    private void UpdateStatusStripError()
    {
        var hasError = !string.IsNullOrWhiteSpace(_statusStripErrorMessage);
        StatusErrorDivider.Visibility = hasError ? Visibility.Visible : Visibility.Collapsed;
        StatusErrorText.Visibility = hasError ? Visibility.Visible : Visibility.Collapsed;
        StatusErrorText.Text = hasError ? _statusStripErrorMessage! : "";
        StatusErrorText.Foreground = BrushFromHex(StatusStripPresentation.ErrorHex);
        ToolTipService.SetToolTip(StatusErrorText, hasError ? _statusStripErrorMessage : null);
        AutomationProperties.SetHelpText(StatusErrorText, hasError ? _statusStripErrorMessage : null);
    }

    private void UpdateLocalStatusStrip()
    {
        var localStatus = StatusStripPresentation.Local(
            _localRuntimeStatus,
            _localRuntimeMessage,
            _localRuntimeDetail);
        var localStatusBrush = BrushFromHex(localStatus.ForegroundHex);
        var usesLocalConnectedIcon = localStatus.IconKind == StatusStripPresentation.LocalConnectedIcon;
        StatusText.Text = localStatus.Text;
        StatusIcon.Visibility = usesLocalConnectedIcon ? Visibility.Collapsed : Visibility.Visible;
        StatusIcon.Glyph = localStatus.Glyph;
        StatusIcon.Foreground = localStatusBrush;
        LocalStatusConnectedIcon.Visibility = usesLocalConnectedIcon ? Visibility.Visible : Visibility.Collapsed;
        LocalStatusConnectedCircle.Fill = localStatusBrush;
        StatusText.Foreground = localStatusBrush;
        ToolTipService.SetToolTip(LocalStatusGroup, localStatus.HelpText);
    }

    private static SolidColorBrush BrushFromHex(string hex)
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

    private void AddActivity(
        string message,
        bool showTopNotification = false,
        string notificationKind = ActivityNotificationKindGeneral)
    {
        var now = DateTime.Now;
        _activity.Insert(0, new ActivityEntry(now.ToString("t"), message));
        while (_activity.Count > 80)
        {
            _activity.RemoveAt(_activity.Count - 1);
        }

        if (_isViewInitialized)
        {
            var resolvedNotificationKind = notificationKind == ActivityNotificationKindGeneral
                ? InferActivityNotificationKind(message)
                : notificationKind;

            if (showTopNotification && ShouldShowTopNotification(resolvedNotificationKind))
            {
                AppendTopNotification(message, now, resolvedNotificationKind);
            }

            UpdateActivityHistoryChrome();
            UpdateActivityRailChrome();
            UpdateTopNotificationsChrome();
        }
    }

    private void UpdateActivityRailChrome()
    {
        if (ActivityRailCountText is null || ActivityRailEmptyText is null || ActivityList is null)
        {
            return;
        }

        var presentation = ActivityRailPresentation.Resolve();
        ActivityRail.Width = presentation.Width;
        ActivityRail.Padding = new Thickness(presentation.Padding);
        ActivityRail.MaxHeight = presentation.MaxHeight;
        ActivityRailLayoutRoot.RowSpacing = presentation.SurfaceSpacing;
        ActivityRailContent.Spacing = presentation.ContentSpacing;
        ActivityRailCountText.FontSize = presentation.CountFontSize;
        ActivityRailEmptyText.Text = presentation.EmptyMessage;
        ActivityRailEmptyText.FontSize = presentation.EmptyFontSize;
        ActivityRailEmptyText.Padding = new Thickness(0, presentation.EmptyVerticalPadding, 0, presentation.EmptyVerticalPadding);
        ActivityList.MaxHeight = presentation.ListMaxHeight;
        ActivityRailCountText.Text = $"{_activity.Count} event{(_activity.Count == 1 ? "" : "s")}";
        ActivityRailCountText.Visibility = _activity.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        ActivityRailEmptyText.Visibility = _activity.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActivityList.Visibility = _activity.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        UpdateNotificationPreferenceControls();
    }

    private void UpdateActivityHistoryChrome()
    {
        UpdateTopNotificationPlacement();
        var presentation = ActivityHistoryPresentation.Resolve();
        ActivityPopover.Width = presentation.Width;
        ActivityPopoverStack.Spacing = presentation.SurfaceSpacing;
        ActivityPopoverHeaderGrid.ColumnSpacing = presentation.HeaderIconSpacing;
        ActivityPopoverHeaderStack.Spacing = presentation.HeaderIconSpacing;
        ActivityPopoverHeaderActionsStack.Spacing = presentation.HeaderActionSpacing;
        ActivityPopoverHeaderTitleText.FontSize = presentation.HeaderTitleFontSize;
        DismissCurrentNotificationsText.FontSize = presentation.DismissCurrentFontSize;
        CloseActivityPopoverButton.Width = presentation.CloseButtonSize;
        CloseActivityPopoverButton.Height = presentation.CloseButtonSize;
        CloseActivityPopoverIcon.FontSize = presentation.CloseIconFontSize;
        ActivityPopoverList.MaxHeight = presentation.MaxListHeight;
        ActivityPopoverNotificationPreferencesButton.Visibility = presentation.ShowsNotificationPreferencesButton
            ? Visibility.Visible
            : Visibility.Collapsed;
        DismissCurrentNotificationsText.Text = presentation.DismissCurrentLabel;
        ActivityPopoverEmptyText.Text = presentation.EmptyMessage;
        ActivityPopoverEmptyText.FontSize = presentation.EmptyFontSize;
        ActivityPopoverEmptyText.Padding = new Thickness(0, presentation.EmptyVerticalPadding, 0, presentation.EmptyVerticalPadding);
        ActivityPopoverEmptyText.Visibility = _topNotificationHistory.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        ActivityPopoverList.Visibility = _topNotificationHistory.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void AppendTopNotification(string message, DateTime timestamp, string notificationKind)
    {
        var notification = TopNotificationItem.Activity(message, timestamp, notificationKind);
        for (var index = _topNotifications.Count - 1; index >= 0; index--)
        {
            if (string.Equals(_topNotifications[index].Message, notification.Message, StringComparison.Ordinal))
            {
                _topNotifications.RemoveAt(index);
            }
        }

        for (var index = _topNotificationHistory.Count - 1; index >= 0; index--)
        {
            if (string.Equals(_topNotificationHistory[index].Message, notification.Message, StringComparison.Ordinal))
            {
                _topNotificationHistory.RemoveAt(index);
            }
        }

        _topNotifications.Insert(0, notification);
        _topNotificationHistory.Insert(0, notification);
        while (_topNotifications.Count > 5)
        {
            _topNotifications.RemoveAt(_topNotifications.Count - 1);
        }

        while (_topNotificationHistory.Count > 100)
        {
            _topNotificationHistory.RemoveAt(_topNotificationHistory.Count - 1);
        }
    }

    private static string InferActivityNotificationKind(string message)
    {
        if (message.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("error", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("invalid", StringComparison.OrdinalIgnoreCase))
        {
            return ActivityNotificationKindFailed;
        }

        if (message.Contains("needs input", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("needs you", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("attention", StringComparison.OrdinalIgnoreCase))
        {
            return ActivityNotificationKindNeedsInput;
        }

        if (message.Contains("completed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("complete", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("finished", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("succeeded", StringComparison.OrdinalIgnoreCase))
        {
            return ActivityNotificationKindCompleted;
        }

        return ActivityNotificationKindGeneral;
    }

    private bool ShouldShowTopNotification(string notificationKind)
    {
        return notificationKind switch
        {
            ActivityNotificationKindCompleted => _notifyOnCompleted,
            ActivityNotificationKindNeedsInput => _notifyOnNeedsInput,
            ActivityNotificationKindFailed => _notifyOnFailed,
            _ => true
        };
    }

    private void PruneDisabledTopNotifications()
    {
        for (var index = _topNotifications.Count - 1; index >= 0; index--)
        {
            if (!ShouldShowTopNotification(_topNotifications[index].NotificationKind))
            {
                _topNotifications.RemoveAt(index);
            }
        }
    }

    private void UpdateNotificationPreferenceControls()
    {
        NotifyCompletedRailMenuItem.IsChecked = _notifyOnCompleted;
        NotifyCompletedPopoverMenuItem.IsChecked = _notifyOnCompleted;
        NotifyNeedsInputRailMenuItem.IsChecked = _notifyOnNeedsInput;
        NotifyNeedsInputPopoverMenuItem.IsChecked = _notifyOnNeedsInput;
        NotifyFailedRailMenuItem.IsChecked = _notifyOnFailed;
        NotifyFailedPopoverMenuItem.IsChecked = _notifyOnFailed;

        var tooltip = $"Notification preferences: {NotificationPreferenceSummary()}";
        ToolTipService.SetToolTip(ActivityRailNotificationPreferencesButton, tooltip);
        ToolTipService.SetToolTip(ActivityPopoverNotificationPreferencesButton, tooltip);
    }

    private string NotificationPreferenceSummary()
    {
        var enabledKinds = new List<string>(capacity: 3);
        if (_notifyOnCompleted)
        {
            enabledKinds.Add("Completed");
        }

        if (_notifyOnNeedsInput)
        {
            enabledKinds.Add("Needs Input");
        }

        if (_notifyOnFailed)
        {
            enabledKinds.Add("Failed");
        }

        return enabledKinds.Count == 0
            ? "none"
            : string.Join(", ", enabledKinds);
    }

    private void UpdateTopNotificationsChrome()
    {
        UpdateTopNotificationPlacement();
        TopNotificationStack.Visibility = !_isReadingModePresented &&
            !_isActivityHistoryVisible &&
            _topNotifications.Count > 0
                ? Visibility.Visible
                : Visibility.Collapsed;
        DismissAllTopNotificationsButton.Visibility = _topNotifications.Count > 1
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void UpdateTopNotificationPlacement()
    {
        if (TopNotificationStack is null)
        {
            return;
        }

        var layout = TopNotificationLayout.Measure();
        TopNotificationStack.Width = layout.StackWidth;
        TopNotificationStack.Margin = new Thickness(
            layout.LeftInset,
            layout.TopInset,
            layout.RightInset,
            layout.BottomInset);
        if (ActivityPopover is not null)
        {
            ActivityPopover.Width = layout.HistoryWidth;
            ActivityPopover.Margin = new Thickness(
                layout.LeftInset,
                layout.TopInset,
                layout.RightInset,
                layout.BottomInset);
            ActivityPopover.Translation = new Vector3(0, 0, (float)layout.HistoryShadowTranslation);
        }
    }

    private void UpdateNewThreadMentionSuggestions()
    {
        if (NewThreadMentionPanel is null || NewThreadPromptBox is null)
        {
            return;
        }

        UpdateMentionSuggestionPanel(
            NewThreadPromptBox.Text,
            _newThreadMentionSuggestions,
            _newThreadMentionSelection,
            NewThreadMentionPanel,
            consumerId: "new-thread",
            excludedThreadNodeId: null,
            ownerThreadId: null,
            CurrentNewThreadMentionContext());
    }

    private void ClearNewThreadMentionSuggestions()
    {
        _newThreadMentionSelection.Reset();
        HideNewThreadMentionSuggestions();
    }

    private void HideNewThreadMentionSuggestions()
    {
        _mentionCatalogSession.ActivateContext("new-thread", null);
        _newThreadMentionSuggestions.Clear();
        if (NewThreadMentionPanel is not null)
        {
            NewThreadMentionPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateThreadPopoverMentionSuggestions()
    {
        if (ThreadPopoverMentionPanel is null || ThreadPopoverDraftBox is null)
        {
            return;
        }

        if (!ThreadPopoverComposerIsEnabled() || !TryGetSelectedThread(out var node))
        {
            ClearThreadPopoverMentionSuggestions();
            return;
        }

        UpdateMentionSuggestionPanel(
            ThreadPopoverDraftBox.Text,
            _threadPopoverMentionSuggestions,
            _threadPopoverMentionSelection,
            ThreadPopoverMentionPanel,
            consumerId: "thread-popover",
            excludedThreadNodeId: node.Id,
            ownerThreadId: null,
            MentionContextForThreadNode(node));
    }

    private void ClearThreadPopoverMentionSuggestions()
    {
        _threadPopoverMentionSelection.Reset();
        HideThreadPopoverMentionSuggestions();
    }

    private void HideThreadPopoverMentionSuggestions()
    {
        _mentionCatalogSession.ActivateContext("thread-popover", null);
        _threadPopoverMentionSuggestions.Clear();
        if (ThreadPopoverMentionPanel is not null)
        {
            ThreadPopoverMentionPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateReaderMentionSuggestions(ReaderThreadItem item, string text)
    {
        var selection = ReaderMentionSelection(item.Id);
        item.MentionSuggestions.Clear();
        if (!item.IsComposerEnabled || !TryActiveMention(text, out _))
        {
            _mentionCatalogSession.ActivateContext($"reader:{item.Id}", null);
            selection.Reset();
            item.MentionPanelVisibility = Visibility.Collapsed;
            return;
        }

        if (!selection.ActivateQuery(text))
        {
            _mentionCatalogSession.ActivateContext($"reader:{item.Id}", null);
            item.MentionPanelVisibility = Visibility.Collapsed;
            return;
        }

        var context = _graph.Nodes.TryGetValue(item.Id, out var node)
            ? MentionContextForThreadNode(node)
            : null;
        foreach (var suggestion in MentionSuggestionsForText(
            text,
            consumerId: $"reader:{item.Id}",
            excludedThreadNodeId: item.Id,
            ownerThreadId: item.Id,
            context))
        {
            item.MentionSuggestions.Add(suggestion);
        }

        selection.UpdateSuggestionCount(item.MentionSuggestions.Count);
        ApplyMentionSelectionVisuals(selection, item.MentionSuggestions);
        item.MentionPanelVisibility = item.MentionSuggestions.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void ClearReaderMentionSuggestions(ReaderThreadItem item)
    {
        ReaderMentionSelection(item.Id).Reset();
        HideReaderMentionSuggestions(item);
    }

    private void HideReaderMentionSuggestions(ReaderThreadItem item)
    {
        _mentionCatalogSession.ActivateContext($"reader:{item.Id}", null);
        item.MentionSuggestions.Clear();
        item.MentionPanelVisibility = Visibility.Collapsed;
    }

    private MentionSelectionController ReaderMentionSelection(string threadId)
    {
        if (!_readerMentionSelections.TryGetValue(threadId, out var selection))
        {
            selection = new MentionSelectionController();
            _readerMentionSelections[threadId] = selection;
        }

        return selection;
    }

    private void UpdateMentionSuggestionPanel(
        string text,
        ObservableCollection<MentionSuggestionItem> suggestions,
        MentionSelectionController selection,
        FrameworkElement panel,
        string consumerId,
        string? excludedThreadNodeId,
        string? ownerThreadId,
        MentionCatalogContext? context)
    {
        suggestions.Clear();
        if (!TryActiveMention(text, out _))
        {
            selection.Reset();
            _mentionCatalogSession.ActivateContext(consumerId, null);
            panel.Visibility = Visibility.Collapsed;
            return;
        }

        if (!selection.ActivateQuery(text))
        {
            _mentionCatalogSession.ActivateContext(consumerId, null);
            panel.Visibility = Visibility.Collapsed;
            return;
        }

        foreach (var suggestion in MentionSuggestionsForText(
                     text,
                     consumerId,
                     excludedThreadNodeId,
                     ownerThreadId,
                     context))
        {
            suggestions.Add(suggestion);
        }

        selection.UpdateSuggestionCount(suggestions.Count);
        ApplyMentionSelectionVisuals(selection, suggestions);
        panel.Visibility = suggestions.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private List<MentionSuggestionItem> MentionSuggestionsForText(
        string text,
        string consumerId,
        string? excludedThreadNodeId,
        string? ownerThreadId,
        MentionCatalogContext? context)
    {
        if (!TryActiveMention(text, out var mention))
        {
            _mentionCatalogSession.ActivateContext(consumerId, null);
            return [];
        }

        _mentionCatalogSession.ActivateContext(consumerId, context);
        if (context is not null)
        {
            _ = _mentionCatalogSession.EnsureRefreshedAsync(context);
        }

        var query = mention.Query.Trim();
        var candidates = WorkflowMentionSuggestions(excludedThreadNodeId, ownerThreadId)
            .Concat(CatalogMentionSuggestions(context, ownerThreadId));
        return candidates
            .Where(candidate => candidate.Trigger == mention.Trigger)
            .Where(candidate => string.IsNullOrWhiteSpace(query) ||
                candidate.Label.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                candidate.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                candidate.Subtitle.Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(candidate => candidate.SortPriority)
            .ThenBy(candidate => candidate.Title, StringComparer.OrdinalIgnoreCase)
            .Take(8)
            .ToList();
    }

    private IEnumerable<MentionSuggestionItem> WorkflowMentionSuggestions(
        string? excludedThreadNodeId,
        string? ownerThreadId)
    {
        foreach (var node in ThreadNodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase))
        {
            if (string.Equals(node.Id, excludedThreadNodeId, StringComparison.Ordinal))
            {
                continue;
            }

            var threadRef = node.Metadata.ThreadRef;
            if (threadRef is null || string.IsNullOrWhiteSpace(threadRef.ThreadID))
            {
                continue;
            }

            var hostID = string.IsNullOrWhiteSpace(threadRef.HostID)
                ? node.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID
                : threadRef.HostID;
            var cwd = string.IsNullOrWhiteSpace(threadRef.Cwd) ? node.Subtitle : threadRef.Cwd;
            var shortID = threadRef.ThreadID.Length > 8
                ? threadRef.ThreadID[..8]
                : threadRef.ThreadID;
            yield return MentionSuggestionItem.Thread(
                node.Title,
                $"{cwd} - {shortID}",
                $"[@\"{EscapedMentionLabel(node.Title)}\" chat](codex-thread://{PercentEncoded(hostID)}/{PercentEncoded(threadRef.ThreadID)})",
                ownerThreadId);
        }

        foreach (var node in FolderNodes.OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase))
        {
            var hostID = node.Metadata.HostID;
            var folderPath = node.Metadata.FolderPath;
            if (string.IsNullOrWhiteSpace(hostID) || string.IsNullOrWhiteSpace(folderPath))
            {
                continue;
            }

            var machineName = MachineNodes.FirstOrDefault(machine =>
                string.Equals(machine.Metadata.HostID, hostID, StringComparison.OrdinalIgnoreCase))?.Title;
            var subtitle = string.Join(
                " - ",
                new[] { machineName, folderPath }
                    .Where(value => !string.IsNullOrWhiteSpace(value)));
            yield return MentionSuggestionItem.Folder(
                node.Title,
                subtitle,
                $"[@\"{EscapedMentionLabel(node.Title)}\" folder](mapofagents-folder://{PercentEncoded(hostID)}/{PercentEncoded(node.Id)})",
                ownerThreadId);
        }
    }

    private IEnumerable<MentionSuggestionItem> CatalogMentionSuggestions(
        MentionCatalogContext? context,
        string? ownerThreadId)
    {
        IReadOnlyList<MentionCatalogCandidate> candidates = context is null
            ? [MentionCatalog.WorkflowBridgeCandidate]
            : _mentionCatalogSession.Candidates(context);
        return candidates.Select(candidate => MentionSuggestionItem.Catalog(candidate, ownerThreadId));
    }

    private void RefreshVisibleMentionSuggestions()
    {
        UpdateNewThreadMentionSuggestions();
        UpdateThreadPopoverMentionSuggestions();
        foreach (var item in _readerThreads.ToList())
        {
            if (TryActiveMention(item.DraftText, out _))
            {
                UpdateReaderMentionSuggestions(item, item.DraftText);
            }
        }
    }

    private MentionCatalogContext? CurrentNewThreadMentionContext()
    {
        return NewThreadTargetBox?.SelectedItem is NodeChoice choice &&
            _graph.Nodes.TryGetValue(choice.Id, out var targetNode)
                ? MentionContextForNewThreadTarget(targetNode)
                : null;
    }

    private MentionCatalogContext MentionContextForNewThreadTarget(CanvasNode targetNode)
    {
        var hostID = targetNode.Metadata.HostID ?? LocalHostIdentity.CanonicalHostID;
        var cwd = NewThreadTargetCwd(targetNode);
        var includeLocalFiles = !NewThreadTargetIsRemote(targetNode);
        AppServerEndpoint? endpoint = TryGetNewThreadTargetEndpoint(targetNode, out _, out var resolvedEndpoint)
            ? resolvedEndpoint
            : null;
        return MentionContext(hostID, cwd, includeLocalFiles, endpoint);
    }

    private MentionCatalogContext MentionContextForThreadNode(CanvasNode node)
    {
        var hostID = node.Metadata.ThreadRef?.HostID ??
            node.Metadata.HostID ??
            LocalHostIdentity.CanonicalHostID;
        var cwd = ThreadMentionRoot(node);
        var includeLocalFiles = IsLocalHostId(hostID);
        AppServerEndpoint? endpoint = TryGetAppServerEndpointForThread(node, out var resolvedEndpoint)
            ? resolvedEndpoint
            : null;
        return MentionContext(hostID, cwd, includeLocalFiles, endpoint);
    }

    private static MentionCatalogContext MentionContext(
        string hostID,
        string? cwd,
        bool includeLocalFiles,
        AppServerEndpoint? endpoint)
    {
        var endpointKey = endpoint?.Url.ToString() ?? "no-endpoint";
        var cwdKey = string.IsNullOrWhiteSpace(cwd) ? "no-cwd" : cwd.Trim();
        return new MentionCatalogContext(
            $"{hostID}|{cwdKey}|{includeLocalFiles}|{endpointKey}",
            string.IsNullOrWhiteSpace(cwd) ? null : cwd.Trim(),
            includeLocalFiles,
            endpoint);
    }

    private static string? ThreadMentionRoot(CanvasNode node)
    {
        if (!string.IsNullOrWhiteSpace(node.Metadata.ThreadRef?.Cwd))
        {
            return node.Metadata.ThreadRef.Cwd;
        }

        return Path.IsPathRooted(node.Subtitle) ? node.Subtitle : null;
    }

    private static string? NewThreadTargetCwd(CanvasNode targetNode)
    {
        return targetNode.Kind == NodeKinds.Folder
            ? targetNode.Metadata.FolderPath ?? targetNode.Subtitle
            : DefaultMachineThreadCwd(targetNode);
    }

    private static string TextWithInsertedMention(
        string text,
        MentionSuggestionItem item,
        ActiveMentionToken mention)
    {
        return $"{text[..mention.StartIndex]}{item.InsertionText} ";
    }

    private static bool TryActiveMention(string text, out ActiveMentionToken mention)
    {
        mention = default;
        var startIndex = text.LastIndexOfAny(['@', '$']);
        if (startIndex < 0)
        {
            return false;
        }

        if (startIndex > 0 && !char.IsWhiteSpace(text[startIndex - 1]))
        {
            return false;
        }

        var query = text[(startIndex + 1)..];
        if (query.Any(character =>
            char.IsWhiteSpace(character) ||
            character is '[' or ']' or '(' or ')' or '<' or '>'))
        {
            return false;
        }

        mention = new ActiveMentionToken(text[startIndex], query, startIndex);
        return true;
    }

    private static string PercentEncoded(string value)
    {
        return Uri.EscapeDataString(value);
    }

    private static string EscapedMentionLabel(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("[", "\\[", StringComparison.Ordinal)
            .Replace("]", "\\]", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal)
            .Replace("\r", " ", StringComparison.Ordinal)
            .Replace("\t", " ", StringComparison.Ordinal);
    }

    private IEnumerable<CanvasNode> MachineNodes =>
        _graph.Nodes.Values.Where(node => node.Kind == NodeKinds.Machine);

    private IEnumerable<CanvasNode> FolderNodes =>
        _graph.Nodes.Values.Where(node => node.Kind == NodeKinds.Folder);

    private IEnumerable<CanvasNode> ThreadNodes =>
        _graph.Nodes.Values.Where(node => node.Kind == NodeKinds.CodexThread);

    private bool HasMachineTarget =>
        MachineNodes.Any();

    private bool HasThreadTarget =>
        FolderNodes.Any() || MachineNodes.Any();

    private string? CreateFolderUnavailableReason =>
        HasMachineTarget ? null : "Connect or add a machine before adding a folder.";

    private string? CreateThreadUnavailableReason =>
        HasThreadTarget ? null : "Add or connect a machine, then add a folder or create a machine chat.";

    private delegate IntPtr WndProcDelegate(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr newProc);

    [DllImport("user32.dll")]
    private static extern IntPtr CallWindowProc(
        IntPtr previousProc,
        IntPtr hwnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(
        IntPtr hwnd,
        uint message,
        IntPtr wParam,
        IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [StructLayout(LayoutKind.Sequential)]
    private struct Win32Point
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MinMaxInfo
    {
        public Win32Point Reserved;
        public Win32Point MaxSize;
        public Win32Point MaxPosition;
        public Win32Point MinTrackSize;
        public Win32Point MaxTrackSize;
    }
}

public readonly record struct ActiveMentionToken(char Trigger, string Query, int StartIndex);

public sealed class MentionSuggestionItem : INotifyPropertyChanged
{
    private bool _isKeyboardSelected;

    public event PropertyChangedEventHandler? PropertyChanged;

    public char Trigger { get; set; } = '@';

    public string Label { get; set; } = "";

    public string Title { get; set; } = "";

    public string Subtitle { get; set; } = "";

    public string InsertionText { get; set; } = "";

    public string? OwnerThreadId { get; set; }

    public string Glyph { get; set; } = "\uE8F2";

    public SolidColorBrush ForegroundBrush { get; set; } = MentionBrush("#A7B0BF");

    public int SortPriority { get; set; }

    public bool IsKeyboardSelected
    {
        get => _isKeyboardSelected;
        set
        {
            if (_isKeyboardSelected == value)
            {
                return;
            }

            _isKeyboardSelected = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsKeyboardSelected)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(RowBackgroundBrush)));
        }
    }

    public string AccessibilityLabel => string.IsNullOrWhiteSpace(Subtitle)
        ? Title
        : $"{Title}, {Subtitle}";

    public SolidColorBrush RowBackgroundBrush =>
        MentionBrush(IsKeyboardSelected ? "#260A84FF" : "#00FFFFFF");

    public Thickness RowPadding =>
        new(
            MentionSuggestionPanelPresentation.RowHorizontalPadding,
            MentionSuggestionPanelPresentation.RowVerticalPadding,
            MentionSuggestionPanelPresentation.RowHorizontalPadding,
            MentionSuggestionPanelPresentation.RowVerticalPadding);

    public Thickness RowMargin =>
        new(0, 0, 0, MentionSuggestionPanelPresentation.RowSpacing);

    public GridLength IconColumnWidth =>
        new(MentionSuggestionPanelPresentation.IconWidth);

    public double ContentSpacing => MentionSuggestionPanelPresentation.ContentSpacing;

    public double IconFontSize => MentionSuggestionPanelPresentation.IconFontSize;

    public double TitleFontSize => MentionSuggestionPanelPresentation.TitleFontSize;

    public double SubtitleFontSize => MentionSuggestionPanelPresentation.SubtitleFontSize;

    public SolidColorBrush TitleForegroundBrush =>
        MentionBrush(MentionSuggestionPanelPresentation.TitleForegroundHex);

    public SolidColorBrush SubtitleForegroundBrush =>
        MentionBrush(MentionSuggestionPanelPresentation.SubtitleForegroundHex);

    public static MentionSuggestionItem Thread(
        string title,
        string subtitle,
        string insertionText,
        string? ownerThreadId = null)
    {
        return new MentionSuggestionItem
        {
            Trigger = '@',
            Label = title,
            Title = title,
            Subtitle = subtitle,
            InsertionText = insertionText,
            OwnerThreadId = ownerThreadId,
            Glyph = "\uE8F2",
            ForegroundBrush = MentionBrush(MentionSuggestionPanelPresentation.ThreadForegroundHex),
            SortPriority = 1
        };
    }

    public static MentionSuggestionItem Folder(
        string title,
        string subtitle,
        string insertionText,
        string? ownerThreadId = null)
    {
        return new MentionSuggestionItem
        {
            Trigger = '@',
            Label = title,
            Title = title,
            Subtitle = subtitle,
            InsertionText = insertionText,
            OwnerThreadId = ownerThreadId,
            Glyph = "\uE8B7",
            ForegroundBrush = MentionBrush(MentionSuggestionPanelPresentation.FolderForegroundHex),
            SortPriority = 2
        };
    }

    public static MentionSuggestionItem Catalog(
        MentionCatalogCandidate candidate,
        string? ownerThreadId = null)
    {
        return new MentionSuggestionItem
        {
            Trigger = candidate.Trigger,
            Label = candidate.Label,
            Title = candidate.Title,
            Subtitle = candidate.Subtitle,
            InsertionText = candidate.InsertionText,
            OwnerThreadId = ownerThreadId,
            Glyph = GlyphFor(candidate.Kind),
            ForegroundBrush = BrushFor(candidate.Kind),
            SortPriority = MentionCatalog.SortPriority(candidate.Kind)
        };
    }

    private static string GlyphFor(string kind)
    {
        return kind switch
        {
            MentionCatalog.KindPlugin => "\uECAA",
            MentionCatalog.KindFile => "\uE8A5",
            MentionCatalog.KindSkill => "\uE950",
            MentionCatalog.KindFolder => "\uE8B7",
            _ => "\uE8F2"
        };
    }

    private static SolidColorBrush BrushFor(string kind)
    {
        return kind switch
        {
            MentionCatalog.KindPlugin => MentionBrush(MentionSuggestionPanelPresentation.PluginForegroundHex),
            MentionCatalog.KindFile => MentionBrush(MentionSuggestionPanelPresentation.FileForegroundHex),
            MentionCatalog.KindSkill => MentionBrush(MentionSuggestionPanelPresentation.SkillForegroundHex),
            MentionCatalog.KindFolder => MentionBrush(MentionSuggestionPanelPresentation.FolderForegroundHex),
            _ => MentionBrush(MentionSuggestionPanelPresentation.ThreadForegroundHex)
        };
    }

    private static SolidColorBrush MentionBrush(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Gray);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }

}

public sealed class ActivityEntry
{
    public ActivityEntry(string timeLabel, string message)
    {
        TimeLabel = timeLabel;
        Message = string.IsNullOrWhiteSpace(message) ? "Activity updated." : message.Trim();
    }

    public string TimeLabel { get; }

    public string Message { get; }

    public string Title => ActivityTitle(Message);

    public string Detail => $"{TimeLabel} - {Message}";

    public string Glyph => ActivityGlyph(Message);

    public SolidColorBrush ForegroundBrush => ActivityBrush(Message);

    private static ActivityRailPresentationSnapshot RailPresentation => ActivityRailPresentation.Resolve();

    public Thickness RowPadding { get; } = new(
        RailPresentation.RowHorizontalPadding,
        RailPresentation.RowVerticalPadding,
        RailPresentation.RowHorizontalPadding,
        RailPresentation.RowVerticalPadding);

    public double RowColumnSpacing { get; } = RailPresentation.RowColumnSpacing;

    public double RowIconColumnWidth { get; } = RailPresentation.RowIconColumnWidth;

    public double RowIconFontSize { get; } = RailPresentation.RowIconFontSize;

    public double RowContentSpacing { get; } = RailPresentation.RowContentSpacing;

    public double RowTitleFontSize { get; } = RailPresentation.RowTitleFontSize;

    public double RowDetailFontSize { get; } = RailPresentation.RowDetailFontSize;

    public int RowDetailMaxLines { get; } = RailPresentation.RowDetailMaxLines;

    private static string ActivityTitle(string message)
    {
        if (message.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("error", StringComparison.OrdinalIgnoreCase))
        {
            return "Action failed";
        }

        if (message.Contains("connected", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("disconnected", StringComparison.OrdinalIgnoreCase))
        {
            return "Connection updated";
        }

        if (message.Contains("thread", StringComparison.OrdinalIgnoreCase))
        {
            return "Thread activity";
        }

        if (message.Contains("workflow", StringComparison.OrdinalIgnoreCase))
        {
            return "Workflow activity";
        }

        return "MapofAgents";
    }

    private static string ActivityGlyph(string message)
    {
        if (message.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("error", StringComparison.OrdinalIgnoreCase))
        {
            return "\uE7BA";
        }

        if (message.Contains("connected", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("disconnected", StringComparison.OrdinalIgnoreCase))
        {
            return "\uE930";
        }

        if (message.Contains("thread", StringComparison.OrdinalIgnoreCase))
        {
            return "\uE8F2";
        }

        if (message.Contains("workflow", StringComparison.OrdinalIgnoreCase))
        {
            return "\uE8BD";
        }

        return "\uE946";
    }

    private static SolidColorBrush ActivityBrush(string message)
    {
        if (message.Contains("failed", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("error", StringComparison.OrdinalIgnoreCase))
        {
            return BrushFromHex("#B42318");
        }

        if (message.Contains("connected", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("disconnected", StringComparison.OrdinalIgnoreCase))
        {
            return BrushFromHex("#30D158");
        }

        if (message.Contains("thread", StringComparison.OrdinalIgnoreCase))
        {
            return BrushFromHex("#0A84FF");
        }

        if (message.Contains("workflow", StringComparison.OrdinalIgnoreCase))
        {
            return BrushFromHex("#BF5AF2");
        }

        return BrushFromHex("#A7B0BF");
    }

    private static SolidColorBrush BrushFromHex(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Gray);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }

}

public enum WorkflowNameEditorMode
{
    Create,
    Rename,
    Duplicate
}

public sealed class TopNotificationItem
{
    public string Id { get; init; } = Guid.NewGuid().ToString();

    public string Glyph { get; init; } = "\uE946";

    public string IconKind { get; init; } = TopNotificationPresentation.FontGlyphIcon;

    public string Title { get; init; } = "MapofAgents";

    public string Message { get; init; } = "";

    public string Detail { get; init; } = "";

    public string Action { get; init; } = "";

    public string NotificationKind { get; init; } = "general";

    public string DisplayedAtLabel { get; init; } = "";

    public string TimelineText
    {
        get
        {
            var action = string.IsNullOrWhiteSpace(Action) ? Detail : Action;
            return string.IsNullOrWhiteSpace(DisplayedAtLabel)
                ? action
                : $"Shown {DisplayedAtLabel} - {action}";
        }
    }

    public SolidColorBrush ForegroundBrush { get; init; } = BrushFromHex("#A7B0BF");

    public SolidColorBrush MessageBrush { get; init; } = BrushFromHex("#A7B0BF");

    public SolidColorBrush BorderBrush { get; init; } = BrushFromHex("#24FFFFFF");

    public double CardWidth { get; } = TopNotificationCardPresentation.Width;

    public Thickness CardMargin { get; } = new(0, 0, 0, TopNotificationCardPresentation.BottomGap);

    public Thickness CardPadding { get; } = new(
        TopNotificationCardPresentation.HorizontalPadding,
        TopNotificationCardPresentation.VerticalPadding,
        TopNotificationCardPresentation.HorizontalPadding,
        TopNotificationCardPresentation.VerticalPadding);

    public double CardBorderThickness { get; } = TopNotificationCardPresentation.BorderThickness;

    public CornerRadius CardCornerRadius { get; } = new(TopNotificationCardPresentation.CornerRadius);

    public Vector3 CardTranslation { get; } = new(0, 0, (float)TopNotificationCardPresentation.ShadowTranslationZ);

    public double CardColumnSpacing { get; } = TopNotificationCardPresentation.ColumnSpacing;

    public double CardIconFrameSize { get; } = TopNotificationCardPresentation.IconFrameSize;

    public Thickness CardIconMargin { get; } = new(0, TopNotificationCardPresentation.IconTopMargin, 0, 0);

    public double CardFontGlyphSize { get; } = TopNotificationCardPresentation.FontGlyphSize;

    public double CardFilledIconSize { get; } = TopNotificationCardPresentation.FilledIconSize;

    public double CardContentSpacing { get; } = TopNotificationCardPresentation.ContentSpacing;

    public double CardTitleFontSize { get; } = TopNotificationCardPresentation.TitleFontSize;

    public double CardMessageFontSize { get; } = TopNotificationCardPresentation.MessageFontSize;

    public int CardMessageMaxLines { get; } = TopNotificationCardPresentation.MessageMaxLines;

    public double CardTimelineFontSize { get; } = TopNotificationCardPresentation.TimelineFontSize;

    public int CardTimelineMaxLines { get; } = TopNotificationCardPresentation.TimelineMaxLines;

    public double CardDismissButtonSize { get; } = TopNotificationCardPresentation.DismissButtonSize;

    public double CardDismissIconFontSize { get; } = TopNotificationCardPresentation.DismissIconFontSize;

    public Thickness RowMargin { get; } = new(0, 0, 0, ActivityHistoryPresentation.RowBottomGap);

    public Thickness RowPadding { get; } = new(ActivityHistoryPresentation.RowPadding);

    public double RowColumnSpacing { get; } = ActivityHistoryPresentation.RowColumnSpacing;

    public double RowIconColumnWidth { get; } = ActivityHistoryPresentation.RowIconColumnWidth;

    public double RowIconFontSize { get; } = ActivityHistoryPresentation.RowIconFontSize;

    public Visibility FontGlyphIconVisibility =>
        IconKind == TopNotificationPresentation.FontGlyphIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility CheckmarkCircleFillIconVisibility =>
        IconKind == TopNotificationPresentation.CheckmarkCircleFillIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ExclamationBubbleFillIconVisibility =>
        IconKind == TopNotificationPresentation.ExclamationBubbleFillIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility XmarkOctagonFillIconVisibility =>
        IconKind == TopNotificationPresentation.XmarkOctagonFillIcon ? Visibility.Visible : Visibility.Collapsed;

    public double RowContentSpacing { get; } = ActivityHistoryPresentation.RowContentSpacing;

    public double RowTitleTimeSpacing { get; } = ActivityHistoryPresentation.RowTitleTimeSpacing;

    public double RowTitleFontSize { get; } = ActivityHistoryPresentation.RowTitleFontSize;

    public double RowTimeFontSize { get; } = ActivityHistoryPresentation.RowTimeFontSize;

    public double RowMessageFontSize { get; } = ActivityHistoryPresentation.RowMessageFontSize;

    public double RowActionFontSize { get; } = ActivityHistoryPresentation.RowActionFontSize;

    public static TopNotificationItem Activity(string message, DateTime timestamp, string notificationKind)
    {
        var trimmed = string.IsNullOrWhiteSpace(message) ? "Activity updated." : message.Trim();
        var presentation = TopNotificationPresentation.Resolve(trimmed, notificationKind);
        return new TopNotificationItem
        {
            Title = presentation.Title,
            Message = trimmed,
            Detail = "Activity",
            Action = presentation.Action,
            NotificationKind = notificationKind,
            DisplayedAtLabel = timestamp.ToString("MMM d, h:mm:ss tt"),
            Glyph = presentation.Glyph,
            IconKind = presentation.IconKind,
            ForegroundBrush = BrushFromHex(presentation.ForegroundHex),
            MessageBrush = BrushFromHex(presentation.MessageHex),
            BorderBrush = BrushFromHex(presentation.BorderHex)
        };
    }

    private static SolidColorBrush BrushFromHex(string hex)
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
}

public sealed record ThreadInboxWorkflowFilterOption(
    string WorkflowID,
    string WorkflowName,
    int Count,
    bool IsActiveWorkflow);

public sealed record ThreadWorkflowMembership(
    string WorkflowID,
    string WorkflowName,
    string? NodeID,
    bool IsActiveWorkflow);

public sealed record ThreadInboxCatalogThread(
    string Key,
    string WorkflowID,
    string WorkflowName,
    string NodeID,
    bool IsActiveWorkflow,
    CanvasNode Node);

public sealed class ThreadInboxWorkflowFilterItem
{
    public ThreadInboxWorkflowFilterItem()
    {
    }

    public ThreadInboxWorkflowFilterItem(
        string id,
        string title,
        string glyph,
        SolidColorBrush glyphBrush,
        string iconKind)
    {
        Id = id;
        Title = title;
        Glyph = glyph;
        GlyphBrush = glyphBrush;
        IconKind = iconKind;
    }

    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Glyph { get; set; } = "\uE8BD";

    public SolidColorBrush GlyphBrush { get; set; } = new(Windows.UI.Color.FromArgb(255, 167, 176, 191));

    public string IconKind { get; set; } = ThreadInboxWorkflowFilterPresentation.TrayFullIcon;

    public Visibility TrayFullIconVisibility =>
        IconKind == ThreadInboxWorkflowFilterPresentation.TrayFullIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility RectangleGroupIconVisibility =>
        IconKind == ThreadInboxWorkflowFilterPresentation.RectangleGroupIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility DashedRectangleIconVisibility =>
        IconKind == ThreadInboxWorkflowFilterPresentation.DashedRectangleIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility RectangleStackIconVisibility =>
        IconKind == ThreadInboxWorkflowFilterPresentation.RectangleStackIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility CheckmarkRectangleStackIconVisibility =>
        IconKind == ThreadInboxWorkflowFilterPresentation.CheckmarkRectangleStackIcon ? Visibility.Visible : Visibility.Collapsed;
}

public sealed class ThreadInboxWorkflowLibraryDocument
{
    [JsonPropertyName("activeWorkflowID")]
    public string? ActiveWorkflowID { get; set; }

    [JsonPropertyName("workflows")]
    public List<ThreadInboxWorkflowLibraryItem> Workflows { get; set; } = [];
}

public sealed class ThreadInboxWorkflowLibraryItem
{
    [JsonPropertyName("id")]
    public string ID { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("graph")]
    public AgentGraph Graph { get; set; } = new();
}

public sealed class WorkflowMenuItem
{
    public WorkflowMenuItem()
    {
    }

    public WorkflowMenuItem(string id, string title, string detail, string updatedLabel, bool isActive)
    {
        Id = id;
        Title = title;
        Detail = detail;
        UpdatedLabel = updatedLabel;
        IsActive = isActive;
    }

    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string UpdatedLabel { get; set; } = "";

    public bool IsActive { get; set; }

    public Visibility ActiveVisibility => IsActive ? Visibility.Visible : Visibility.Collapsed;
}

public sealed class NodeChoice
{
    public NodeChoice()
    {
    }

    public NodeChoice(string id, string title, string subtitle, bool isOpen = false)
    {
        Id = id;
        Title = title;
        Subtitle = subtitle;
        IsOpen = isOpen;
    }

    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Subtitle { get; set; } = "";

    public bool IsOpen { get; set; }

    public double ChoiceOpacity => IsOpen ? 0.52 : 1.0;
}

public sealed class PairingEndpointPreviewItem
{
    public static PairingEndpointPreviewItem FromPreview(MapofAgentsPairingEndpointImportPreview preview)
    {
        return new PairingEndpointPreviewItem
        {
            Id = preview.Id,
            Kind = preview.Kind,
            Label = preview.Label,
            Url = preview.Url,
            IsPreferred = preview.IsPreferred
        };
    }

    public string Id { get; set; } = "";

    public string Kind { get; set; } = "";

    public string Label { get; set; } = "";

    public string Url { get; set; } = "";

    public bool IsPreferred { get; set; }

    public string Title => string.IsNullOrWhiteSpace(Label)
        ? KindLabel
        : $"{KindLabel} - {Label}";

    public string KindLabel => Kind.Trim().ToLowerInvariant() switch
    {
        "tailnet" => "Tailnet",
        "local" => "Local",
        "manual" => "Manual",
        _ => "Endpoint"
    };

    public string Glyph => Kind.Trim().ToLowerInvariant() switch
    {
        "tailnet" => "\uE774",
        "local" => "\uE968",
        _ => "\uEC4E"
    };

    public SolidColorBrush GlyphBrush => Kind.Trim().ToLowerInvariant() switch
    {
        "tailnet" => PairingBrush("#30D158"),
        "local" => PairingBrush("#A7B0BF"),
        _ => PairingBrush("#64A8FF")
    };

    public Visibility PreferredVisibility => IsPreferred ? Visibility.Visible : Visibility.Collapsed;

    private static SolidColorBrush PairingBrush(string hex)
    {
        var value = hex.TrimStart('#');
        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Gray);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(255, red, green, blue));
    }
}

public sealed class RemoteDiscoveryItem
{
    public string SourceNodeId { get; set; } = "";

    public string RemoteId { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string Endpoint { get; set; } = "";

    public string StatusKey { get; set; } = HostStatuses.Disconnected;

    public string BadgeText { get; set; } = "setup";

    public string Glyph { get; set; } = "\uEA3A";

    public bool IsCodexRemote { get; set; }

    public bool IsConnectable { get; set; }

    public bool IsBusy { get; set; }

    public bool CanConnect { get; set; }

    public double ConnectOpacity { get; set; } = MachineDiscoveryActionPresentation.AvailableOpacity;

    public Visibility ConnectVisibility => IsCodexRemote ? Visibility.Visible : Visibility.Collapsed;

    public string ConnectTooltip { get; set; } = "Start remote App Server and connect through SSH";

    public string DiagnosticsTooltip { get; set; } = "Open remote diagnostics";

    public string ConnectAutomationName { get; set; } = "Connect Codex remote";

    public string DiagnosticsAutomationName { get; set; } = "Open remote diagnostics";

    public bool ShowFillEndpointAction { get; set; }

    public string DiagnosticsSummaryGlyph { get; set; } = "";

    public string DiagnosticsSummaryText { get; set; } = "";

    public SolidColorBrush DiagnosticsSummaryBrush { get; set; } = Brush("#A7B0BF");

    public bool ShowsDiagnosticsSummary { get; set; }

    public bool ShowsDiagnosticsButton { get; set; }

    public Visibility DiagnosticsSummaryVisibility =>
        ShowsDiagnosticsSummary ? Visibility.Visible : Visibility.Collapsed;

    public Visibility DiagnosticsSummaryButtonVisibility =>
        ShowsDiagnosticsButton ? Visibility.Visible : Visibility.Collapsed;

    public Thickness DiagnosticsSummaryMargin { get; set; } = new(
        MachineDiscoverySectionPresentation.DiagnosticLeftPadding,
        0,
        0,
        MachineDiscoverySectionPresentation.DiagnosticBottomGap);

    public SolidColorBrush StatusBrush { get; set; } = Brush("#A7B0BF");

    public SolidColorBrush BadgeForegroundBrush { get; set; } = Brush("#A7B0BF");

    public SolidColorBrush BadgeBackgroundBrush { get; set; } = Brush("#16697586");

    public Thickness RowMargin { get; set; } = new(0, 0, 0, MachineDiscoverySectionPresentation.RowBottomGap);

    public Thickness RowPadding { get; set; } = new(
        MachineDiscoverySectionPresentation.RowHorizontalPadding,
        MachineDiscoverySectionPresentation.RowVerticalPadding,
        MachineDiscoverySectionPresentation.RowHorizontalPadding,
        MachineDiscoverySectionPresentation.RowVerticalPadding);

    public double RowColumnSpacing { get; set; } = MachineDiscoverySectionPresentation.RowColumnSpacing;

    public double RowIconWidth { get; set; } = MachineDiscoverySectionPresentation.RowIconWidth;

    public double RowIconFontSize { get; set; } = MachineDiscoverySectionPresentation.RowIconFontSize;

    public double RowTitleFontSize { get; set; } = MachineDiscoverySectionPresentation.RowTitleFontSize;

    public double RowDetailFontSize { get; set; } = MachineDiscoverySectionPresentation.RowDetailFontSize;

    public Thickness BadgePadding { get; set; } = new(
        MachineDiscoverySectionPresentation.BadgeHorizontalPadding,
        MachineDiscoverySectionPresentation.BadgeVerticalPadding,
        MachineDiscoverySectionPresentation.BadgeHorizontalPadding,
        MachineDiscoverySectionPresentation.BadgeVerticalPadding);

    public double BadgeFontSize { get; set; } = MachineDiscoverySectionPresentation.BadgeFontSize;

    public double ActionButtonSize { get; set; } = MachineDiscoverySectionPresentation.ActionButtonSize;

    public bool CanFillEndpoint => FillPresentation.CanInvoke;

    public Visibility FillVisibility => ShowFillEndpointAction ? Visibility.Visible : Visibility.Collapsed;

    public string FillTooltip => FillPresentation.ToolTip;

    public string FillAutomationName => FillPresentation.AutomationName;

    public double FillOpacity => FillPresentation.Opacity;

    private MachineDiscoveryActionPresentationSnapshot FillPresentation =>
        MachineDiscoveryActionPresentation.FillEndpoint(!string.IsNullOrWhiteSpace(Endpoint));

    public static RemoteDiscoveryItem FromMachine(CanvasNode machine, string badge)
    {
        var status = machine.Metadata.HostStatus ?? HostStatuses.Disconnected;
        var endpoint = machine.Metadata.AppServerEndpointUrl ?? "";
        var detail = DetailFor(machine, endpoint);
        return new RemoteDiscoveryItem
        {
            SourceNodeId = machine.Id,
            Title = string.IsNullOrWhiteSpace(machine.Title) ? "Remote Machine" : machine.Title,
            Detail = detail,
            Endpoint = endpoint,
            StatusKey = status,
            BadgeText = badge,
            ShowFillEndpointAction = !string.IsNullOrWhiteSpace(endpoint),
            Glyph = GlyphFor(status),
            StatusBrush = BrushForStatus(status),
            BadgeForegroundBrush = BadgeForegroundFor(badge, status),
            BadgeBackgroundBrush = BadgeBackgroundFor(badge, status)
        };
    }

    public static RemoteDiscoveryItem FromCodexRemote(CodexDesktopRemote remote)
    {
        var status = remote.IsConnectable ? HostStatuses.Connected : HostStatuses.Disconnected;
        var badge = remote.IsConnectable ? "ssh" : "setup";
        var item = new RemoteDiscoveryItem
        {
            SourceNodeId = remote.Id,
            RemoteId = remote.Id,
            Title = string.IsNullOrWhiteSpace(remote.DisplayName) ? "Codex Remote" : remote.DisplayName,
            Detail = CodexRemoteDetailFor(remote),
            StatusKey = status,
            BadgeText = badge,
            Glyph = GlyphFor(status),
            IsCodexRemote = true,
            IsConnectable = remote.IsConnectable,
            StatusBrush = BrushForStatus(status),
            BadgeForegroundBrush = BadgeForegroundFor(badge, status),
            BadgeBackgroundBrush = BadgeBackgroundFor(badge, status)
        };
        item.ApplyCodexRemoteActionPresentation();
        return item;
    }

    public static RemoteDiscoveryItem FromTailnetMachine(TailnetMachine machine)
    {
        var status = machine.IsOnline ? HostStatuses.Connected : HostStatuses.Disconnected;
        var endpoint = machine.SuggestedWebSocketEndpoint() ?? "";
        return new RemoteDiscoveryItem
        {
            SourceNodeId = machine.Id,
            Title = string.IsNullOrWhiteSpace(machine.Name) ? "Tailnet Machine" : machine.Name,
            Detail = TailnetDetailFor(machine, endpoint),
            Endpoint = endpoint,
            StatusKey = status,
            BadgeText = "tailnet",
            ShowFillEndpointAction = true,
            Glyph = GlyphFor(status),
            StatusBrush = BrushForStatus(status),
            BadgeForegroundBrush = BadgeForegroundFor("tailnet", status),
            BadgeBackgroundBrush = BadgeBackgroundFor("tailnet", status)
        };
    }

    private static string DetailFor(CanvasNode machine, string endpoint)
    {
        if (!string.IsNullOrWhiteSpace(endpoint))
        {
            return endpoint;
        }

        var platform = string.IsNullOrWhiteSpace(machine.Metadata.Platform)
            ? "remote"
            : machine.Metadata.Platform;
        var host = string.IsNullOrWhiteSpace(machine.Metadata.HostID)
            ? machine.Subtitle
            : machine.Metadata.HostID;
        return string.IsNullOrWhiteSpace(host) ? platform : $"{platform} - {host}";
    }

    private static string CodexRemoteDetailFor(CodexDesktopRemote remote)
    {
        var platform = string.IsNullOrWhiteSpace(remote.Platform) || remote.Platform == HostPlatforms.Unknown
            ? "codex remote"
            : remote.Platform;
        var address = string.IsNullOrWhiteSpace(remote.DisplayAddress) ? remote.Source : remote.DisplayAddress;
        return string.IsNullOrWhiteSpace(address)
            ? platform
            : $"{platform} - {address}";
    }

    private static string TailnetDetailFor(TailnetMachine machine, string endpoint)
    {
        var platform = string.IsNullOrWhiteSpace(machine.Platform) || machine.Platform == HostPlatforms.Unknown
            ? "tailnet"
            : machine.Platform;
        var state = machine.IsOnline
            ? "online"
            : machine.LastSeenAt is null
                ? "offline"
                : $"last seen {machine.LastSeenAt.Value.LocalDateTime:g}";
        var address = string.IsNullOrWhiteSpace(endpoint) ? machine.DisplayAddress : endpoint;
        return string.IsNullOrWhiteSpace(address)
            ? $"{platform} - {state}"
            : $"{platform} - {state} - {address}";
    }

    private static string GlyphFor(string status)
    {
        return MachineHealthPresentation.Resolve(status).Glyph;
    }

    private static SolidColorBrush BrushForStatus(string status)
    {
        return Brush(MachineHealthPresentation.Resolve(status).ForegroundHex);
    }

    private static SolidColorBrush BadgeForegroundFor(string badge, string status)
    {
        if (string.Equals(badge, "tailnet", StringComparison.OrdinalIgnoreCase))
        {
            return Brush("#38BDF8");
        }

        return status == HostStatuses.Connected
            ? Brush("#30D158")
            : Brush("#A7B0BF");
    }

    private static SolidColorBrush BadgeBackgroundFor(string badge, string status)
    {
        if (string.Equals(badge, "tailnet", StringComparison.OrdinalIgnoreCase))
        {
            return Brush("#1638BDF8");
        }

        return status == HostStatuses.Connected
            ? Brush("#1630D158")
            : Brush("#16697586");
    }

    public void ApplyCodexRemoteActionPresentation()
    {
        var connect = MachineDiscoveryActionPresentation.ConnectCodexRemote(IsConnectable, IsBusy);
        CanConnect = connect.CanInvoke;
        ConnectOpacity = connect.Opacity;
        ConnectTooltip = connect.ToolTip;
        ConnectAutomationName = connect.AutomationName;
    }

    public void ApplyCodexRemoteDiagnosticsSummary(IEnumerable<RuntimeDiagnosticStep> diagnostics)
    {
        var presentation = CodexRemoteDiagnosticsSummaryPresentation.Resolve(diagnostics, IsBusy);
        ShowsDiagnosticsSummary = presentation.ShowsSummary;
        ShowsDiagnosticsButton = presentation.ShowsDiagnosticsButton;
        DiagnosticsSummaryGlyph = presentation.Glyph;
        DiagnosticsSummaryText = presentation.Text;
        DiagnosticsSummaryBrush = Brush(presentation.ForegroundHex);
        DiagnosticsTooltip = presentation.ToolTip;
        DiagnosticsAutomationName = presentation.AutomationName;
        if (presentation.ShowsSummary)
        {
            StatusBrush = Brush(presentation.ForegroundHex);
        }
    }

    private static SolidColorBrush Brush(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Transparent);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }
}

public sealed class CodexRemoteDiagnosticItem
{
    public string RemoteId { get; set; } = "";

    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string Status { get; set; } = RuntimeDiagnosticStatuses.Pending;

    public string? Action { get; set; }

    public string Glyph { get; set; } = "\uEA3A";

    public SolidColorBrush StatusBrush { get; set; } = Brush("#A7B0BF");

    public bool IsBusy { get; set; }

    public bool CanRunAction => !IsBusy;

    public double ActionOpacity => CanRunAction
        ? MachineDiscoveryActionPresentation.AvailableOpacity
        : MachineDiscoveryActionPresentation.UnavailableOpacity;

    public Visibility ActionVisibility => string.IsNullOrWhiteSpace(Action) ? Visibility.Collapsed : Visibility.Visible;

    public Thickness RowMargin { get; set; } = new(
        MachineDiscoverySectionPresentation.DiagnosticLeftPadding,
        0,
        0,
        MachineDiscoverySectionPresentation.DiagnosticBottomGap);

    public double ColumnSpacing { get; set; } = MachineDiscoverySectionPresentation.DiagnosticColumnSpacing;

    public double IconWidth { get; set; } = MachineDiscoverySectionPresentation.DiagnosticIconWidth;

    public double IconFontSize { get; set; } = MachineDiscoverySectionPresentation.DiagnosticIconFontSize;

    public double TitleFontSize { get; set; } = MachineDiscoverySectionPresentation.DiagnosticTitleFontSize;

    public double DetailFontSize { get; set; } = MachineDiscoverySectionPresentation.DiagnosticDetailFontSize;

    public Thickness ActionPadding { get; set; } = new(
        MachineDiscoverySectionPresentation.DiagnosticActionHorizontalPadding,
        MachineDiscoverySectionPresentation.DiagnosticActionVerticalPadding,
        MachineDiscoverySectionPresentation.DiagnosticActionHorizontalPadding,
        MachineDiscoverySectionPresentation.DiagnosticActionVerticalPadding);

    public double ActionIconFontSize { get; set; } = MachineDiscoverySectionPresentation.DiagnosticActionIconFontSize;

    public string ActionLabel => Action switch
    {
        RuntimeDiagnosticActions.InstallCodexCLI => "Install",
        RuntimeDiagnosticActions.UpdateCodexCLI => "Update",
        RuntimeDiagnosticActions.StartAppServer => "Start",
        RuntimeDiagnosticActions.RestartAppServer => "Restart",
        _ => "Run"
    };

    public string ActionGlyph => Action switch
    {
        RuntimeDiagnosticActions.InstallCodexCLI => "\uE896",
        RuntimeDiagnosticActions.UpdateCodexCLI => "\uE895",
        RuntimeDiagnosticActions.StartAppServer => "\uE768",
        RuntimeDiagnosticActions.RestartAppServer => "\uE72C",
        _ => "\uE7C3"
    };

    public string ActionTooltip => IsBusy ? "Wait for the current remote operation to finish." : Action switch
    {
        RuntimeDiagnosticActions.InstallCodexCLI => "Install Codex CLI on this remote",
        RuntimeDiagnosticActions.UpdateCodexCLI => "Update Codex CLI on this remote",
        RuntimeDiagnosticActions.StartAppServer => "Start Codex App Server on this remote",
        RuntimeDiagnosticActions.RestartAppServer => "Restart Codex App Server on this remote",
        _ => "Run diagnostic action"
    };

    public static CodexRemoteDiagnosticItem FromStep(string remoteId, RuntimeDiagnosticStep step, bool isBusy)
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(step.Status);
        return new CodexRemoteDiagnosticItem
        {
            RemoteId = remoteId,
            Id = step.Id,
            Title = step.Title,
            Detail = step.Detail,
            Status = step.Status,
            Action = step.Action,
            IsBusy = isBusy,
            Glyph = presentation.Glyph,
            StatusBrush = Brush(presentation.ForegroundHex)
        };
    }

    private static SolidColorBrush Brush(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Transparent);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }
}

public sealed class MachineHealthItem
{
    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string StatusText { get; set; } = "";

    public string StatusGlyph { get; set; } = MachineHealthPresentation.DisconnectedGlyph;

    public double StatusIconColumnWidth { get; set; } = MachineHealthPresentation.IconColumnWidth;

    public double FilledCheckIconSize { get; set; } = MachineHealthPresentation.FilledCheckIconSize;

    public double FilledCheckStrokeThickness { get; set; } = MachineHealthPresentation.FilledCheckStrokeThickness;

    public Visibility StatusFontIconVisibility { get; set; } = Visibility.Visible;

    public Visibility FilledCheckIconVisibility { get; set; } = Visibility.Collapsed;

    public string EndpointDetail { get; set; } = "";

    public string PlatformDetail { get; set; } = "";

    public string CodexDetail { get; set; } = "";

    public Visibility CodexDetailVisibility { get; set; } = Visibility.Collapsed;

    public string ErrorDetail { get; set; } = "";

    public Visibility ErrorDetailVisibility { get; set; } = Visibility.Collapsed;

    public Visibility ExpandedDetailsVisibility { get; set; } = Visibility.Collapsed;

    public string DetailGlyph { get; set; } = "\uE946";

    public string DetailButtonTooltip { get; set; } = "Show machine details";

    public string DetailButtonName { get; set; } = "Show machine details";

    public bool CanAddFolder { get; set; }

    public string FolderActionTooltip { get; set; } = "Add project folder";

    public string FolderActionAutomationName { get; set; } = "Add folder";

    public double FolderActionOpacity { get; set; } = 1.0;

    public Visibility RemoteActionVisibility { get; set; } = Visibility.Visible;

    public SolidColorBrush StatusForegroundBrush { get; set; } = Brush("#A7B0BF");

    public SolidColorBrush StatusBackgroundBrush { get; set; } = Brush("#12697586");

    public SolidColorBrush StatusBorderBrush { get; set; } = Brush("#24697586");

    public static MachineHealthItem FromNode(CanvasNode node, bool isLocal, bool hasRemoteBrowser, bool isExpanded)
    {
        var status = node.Metadata.HostStatus ?? HostStatuses.Disconnected;
        var presentation = MachineHealthPresentation.Resolve(status);
        var folderAction = MachineHealthFolderActionPresentation.Resolve(isLocal, status, hasRemoteBrowser);
        var endpointDetail = EndpointDetailFor(node);
        var platformDetail = node.Metadata.Platform ?? HostPlatforms.Unknown;
        var codexDetail = node.Metadata.CodexHome ?? "";
        var hostLastError = NormalizedHostLastError(node.Metadata.HostLastError);
        return new MachineHealthItem
        {
            Id = node.Id,
            Title = node.Title,
            Detail = CollapsedDetailFor(node),
            StatusText = presentation.Text,
            StatusGlyph = presentation.Glyph,
            StatusIconColumnWidth = presentation.IconColumnWidth,
            FilledCheckIconSize = presentation.FilledCheckIconSize,
            FilledCheckStrokeThickness = presentation.FilledCheckStrokeThickness,
            StatusFontIconVisibility = presentation.UsesFilledCheckIcon ? Visibility.Collapsed : Visibility.Visible,
            FilledCheckIconVisibility = presentation.UsesFilledCheckIcon ? Visibility.Visible : Visibility.Collapsed,
            EndpointDetail = endpointDetail,
            PlatformDetail = platformDetail,
            CodexDetail = codexDetail,
            CodexDetailVisibility = string.IsNullOrWhiteSpace(codexDetail) ? Visibility.Collapsed : Visibility.Visible,
            ErrorDetail = hostLastError ?? "",
            ErrorDetailVisibility = hostLastError is null ? Visibility.Collapsed : Visibility.Visible,
            ExpandedDetailsVisibility = isExpanded ? Visibility.Visible : Visibility.Collapsed,
            DetailGlyph = isExpanded ? "\uE70E" : "\uE946",
            DetailButtonTooltip = isExpanded ? "Hide details" : DetailTooltip(endpointDetail, status, hostLastError),
            DetailButtonName = isExpanded ? "Hide machine details" : "Show machine details",
            CanAddFolder = folderAction.CanInvoke,
            FolderActionTooltip = folderAction.ToolTip,
            FolderActionAutomationName = folderAction.AutomationName,
            FolderActionOpacity = folderAction.Opacity,
            RemoteActionVisibility = folderAction.IsVisible ? Visibility.Visible : Visibility.Collapsed,
            StatusForegroundBrush = Brush(presentation.ForegroundHex),
            StatusBackgroundBrush = Brush(presentation.BackgroundHex),
            StatusBorderBrush = Brush(presentation.BorderHex)
        };
    }

    private static string CollapsedDetailFor(CanvasNode node)
    {
        if (NormalizedHostLastError(node.Metadata.HostLastError) is { } lastError)
        {
            return lastError;
        }

        if (!string.IsNullOrWhiteSpace(node.Subtitle))
        {
            return node.Subtitle;
        }

        return EndpointDetailFor(node);
    }

    private static string EndpointDetailFor(CanvasNode node)
    {
        if (!string.IsNullOrWhiteSpace(node.Metadata.AppServerEndpointUrl))
        {
            return node.Metadata.AppServerEndpointUrl;
        }

        if (!string.IsNullOrWhiteSpace(node.Subtitle))
        {
            return node.Subtitle;
        }

        return string.IsNullOrWhiteSpace(node.Metadata.CodexHome)
            ? "No endpoint recorded."
            : node.Metadata.CodexHome;
    }

    private static string DetailTooltip(string endpointDetail, string status, string? hostLastError)
    {
        return hostLastError is null
            ? $"{endpointDetail}\n{RecoveryHintForStatus(status)}"
            : $"{hostLastError}\n{endpointDetail}";
    }

    private static string? NormalizedHostLastError(string? lastError)
    {
        return string.IsNullOrWhiteSpace(lastError) ? null : lastError.Trim();
    }

    private static string RecoveryHintForStatus(string status)
    {
        return status switch
        {
            HostStatuses.Connected => "Ready for project folders and workflow threads.",
            HostStatuses.Connecting => "Connection is in progress. Refresh health after the route settles.",
            HostStatuses.Unavailable => "Runtime failed or could not be reached. Run diagnostics and restart the App Server.",
            _ => "Reconnect this machine or remove the saved route if it is stale."
        };
    }

    private static SolidColorBrush Brush(string hex)
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
}

public sealed class RuntimeDiagnosticItem
{
    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string Glyph { get; set; } = "\uEA3A";

    public SolidColorBrush StatusBrush { get; set; } = DiagnosticBrush("#8F9BAA");

    public Visibility FontIconVisibility { get; set; } = Visibility.Visible;

    public Visibility PendingCircleIconVisibility { get; set; } = Visibility.Collapsed;

    public Visibility RunningArrowsIconVisibility { get; set; } = Visibility.Collapsed;

    public Visibility FilledCheckIconVisibility { get; set; } = Visibility.Collapsed;

    public Visibility FilledXIconVisibility { get; set; } = Visibility.Collapsed;

    public Visibility FilledWarningIconVisibility { get; set; } = Visibility.Collapsed;

    public SolidColorBrush DetailBrush { get; set; } = DiagnosticBrush(RuntimeDiagnosticsRailPresentation.DetailForegroundHex);

    public double RowColumnSpacing { get; set; } = RuntimeDiagnosticsRailPresentation.RowColumnSpacing;

    public Thickness RowPadding { get; set; } = new(0, RuntimeDiagnosticsRailPresentation.RowVerticalPadding, 0, RuntimeDiagnosticsRailPresentation.RowVerticalPadding);

    public double IconColumnWidth { get; set; } = RuntimeDiagnosticsRailPresentation.IconColumnWidth;

    public double IconFontSize { get; set; } = RuntimeDiagnosticsRailPresentation.IconFontSize;

    public double FilledStatusIconSize { get; set; } = RuntimeDiagnosticsRailPresentation.FilledStatusIconSize;

    public double FilledStatusIconStrokeThickness { get; set; } = RuntimeDiagnosticsRailPresentation.FilledStatusIconStrokeThickness;

    public double DetailStackSpacing { get; set; } = RuntimeDiagnosticsRailPresentation.DetailStackSpacing;

    public double TitleFontSize { get; set; } = RuntimeDiagnosticsRailPresentation.TitleFontSize;

    public double DetailFontSize { get; set; } = RuntimeDiagnosticsRailPresentation.DetailFontSize;

    public int DetailLineLimit { get; set; } = RuntimeDiagnosticsRailPresentation.DetailLineLimit;

    public TextWrapping DetailTextWrapping { get; set; } = RuntimeDiagnosticsRailPresentation.DetailAllowsWrapping
        ? TextWrapping.Wrap
        : TextWrapping.NoWrap;

    public TextTrimming DetailTextTrimming { get; set; } = DetailTextTrimmingFor(
        RuntimeDiagnosticsRailPresentation.DetailTrimmingMode);

    public static RuntimeDiagnosticItem FromStep(RuntimeDiagnosticStep step)
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(step.Status);
        return new RuntimeDiagnosticItem
        {
            Title = string.IsNullOrWhiteSpace(step.Title) ? step.Id : step.Title,
            Detail = string.IsNullOrWhiteSpace(step.Detail) ? presentation.StatusLabel : step.Detail,
            Glyph = presentation.Glyph,
            StatusBrush = DiagnosticBrush(presentation.ForegroundHex),
            FontIconVisibility = presentation.UsesPendingCircleIcon ||
                presentation.UsesRunningArrowsIcon ||
                presentation.UsesFilledCheckIcon ||
                presentation.UsesFilledXIcon ||
                presentation.UsesFilledWarningIcon
                ? Visibility.Collapsed
                : Visibility.Visible,
            PendingCircleIconVisibility = presentation.UsesPendingCircleIcon ? Visibility.Visible : Visibility.Collapsed,
            RunningArrowsIconVisibility = presentation.UsesRunningArrowsIcon ? Visibility.Visible : Visibility.Collapsed,
            FilledCheckIconVisibility = presentation.UsesFilledCheckIcon ? Visibility.Visible : Visibility.Collapsed,
            FilledXIconVisibility = presentation.UsesFilledXIcon ? Visibility.Visible : Visibility.Collapsed,
            FilledWarningIconVisibility = presentation.UsesFilledWarningIcon ? Visibility.Visible : Visibility.Collapsed,
            DetailBrush = DiagnosticBrush(presentation.DetailForegroundHex),
            RowColumnSpacing = presentation.RowColumnSpacing,
            RowPadding = new Thickness(0, presentation.RowVerticalPadding, 0, presentation.RowVerticalPadding),
            IconColumnWidth = presentation.IconColumnWidth,
            IconFontSize = presentation.IconFontSize,
            FilledStatusIconSize = presentation.FilledStatusIconSize,
            FilledStatusIconStrokeThickness = presentation.FilledStatusIconStrokeThickness,
            DetailStackSpacing = presentation.DetailStackSpacing,
            TitleFontSize = presentation.TitleFontSize,
            DetailFontSize = presentation.DetailFontSize,
            DetailLineLimit = presentation.DetailLineLimit,
            DetailTextWrapping = presentation.DetailAllowsWrapping ? TextWrapping.Wrap : TextWrapping.NoWrap,
            DetailTextTrimming = DetailTextTrimmingFor(presentation.DetailTrimmingMode)
        };
    }

    private static TextTrimming DetailTextTrimmingFor(string mode)
    {
        return string.Equals(
            mode,
            RuntimeDiagnosticsRailPresentation.DetailTrimmingMode,
            StringComparison.Ordinal)
            ? TextTrimming.CharacterEllipsis
            : TextTrimming.None;
    }

    private static SolidColorBrush DiagnosticBrush(string hex)
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
}

public sealed class MachineRecoveryItem
{
    public string Id { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string StatusText { get; set; } = "";

    public string StatusGlyph { get; set; } = "\uE950";

    public string NextText { get; set; } = "";

    public SolidColorBrush StatusBrush { get; set; } = RecoveryBrush("#A7B0BF");

    public SolidColorBrush StatusBackgroundBrush { get; set; } = RecoveryBrush("#12697586");

    public SolidColorBrush StatusBorderBrush { get; set; } = RecoveryBrush("#24697586");

    public List<MachineRecoveryStepItem> Steps { get; set; } = [];

    public static MachineRecoveryItem FromNode(CanvasNode node)
    {
        var status = node.Metadata.HostStatus ?? HostStatuses.Disconnected;
        var steps = StepsFor(node, status);
        var recommended = RecommendedStep(steps);
        foreach (var step in steps)
        {
            step.IsRecommended = step == recommended;
        }

        return new MachineRecoveryItem
        {
            Id = node.Id,
            Title = node.Title,
            Detail = DetailFor(node),
            StatusText = MachineRecoveryPresentation.TargetStatus(status).Text,
            StatusGlyph = status == HostStatuses.Unavailable
                ? MachineRecoveryPresentation.WarningGlyph
                : MachineRecoveryPresentation.MachineGlyph,
            NextText = recommended is null
                ? "Next: refresh health after this route settles."
                : $"Next: {recommended.Summary}",
            StatusBrush = StatusBrushFor(status),
            StatusBackgroundBrush = StatusBackgroundFor(status),
            StatusBorderBrush = StatusBorderFor(status),
            Steps = steps
        };
    }

    private static List<MachineRecoveryStepItem> StepsFor(CanvasNode node, string status)
    {
        return
        [
            VerifyEndpointStep(node, status),
            AppServerStep(node, status),
            ReconnectStep(node, status),
            RemoveRouteStep(node, status)
        ];
    }

    private static MachineRecoveryStepItem? RecommendedStep(List<MachineRecoveryStepItem> steps)
    {
        return steps.FirstOrDefault(step => step.StatusKey == RecoveryStepStatus.Running) ??
            steps.FirstOrDefault(step => step.Id == "verify-endpoint" && step.StatusKey != RecoveryStepStatus.Passed) ??
            steps.FirstOrDefault(step => step.Id == "app-server" && step.StatusKey != RecoveryStepStatus.Passed) ??
            steps.FirstOrDefault(step => step.Id == "reconnect" && step.StatusKey != RecoveryStepStatus.Passed) ??
            steps.FirstOrDefault(step => step.Id == "remove-route" && step.StatusKey != RecoveryStepStatus.Passed);
    }

    private static MachineRecoveryStepItem VerifyEndpointStep(CanvasNode node, string status)
    {
        var statusKey = status switch
        {
            HostStatuses.Connecting => RecoveryStepStatus.Running,
            HostStatuses.Unavailable => RecoveryStepStatus.Failed,
            _ => RecoveryStepStatus.Warning
        };

        return MachineRecoveryStepItem.Create(
            "verify-endpoint",
            node.Id,
            "Verify endpoint",
            statusKey == RecoveryStepStatus.Failed
                ? NormalizedHostLastError(node.Metadata.HostLastError) ?? "Saved endpoint failed its last probe."
                : $"Probe {EndpointFor(node)} before reconnecting.",
            statusKey,
            "Probe",
            "verify endpoint");
    }

    private static MachineRecoveryStepItem AppServerStep(CanvasNode node, string status)
    {
        var statusKey = status == HostStatuses.Unavailable
            ? RecoveryStepStatus.Failed
            : RecoveryStepStatus.Warning;
        return MachineRecoveryStepItem.Create(
            "app-server",
            node.Id,
            "Restart/probe app-server",
            status == HostStatuses.Connecting
                ? "Wait for the current app-server probe to finish."
                : "Start Codex App Server on the target, then refresh health.",
            status == HostStatuses.Connecting ? RecoveryStepStatus.Pending : statusKey,
            "Restart",
            "restart app-server");
    }

    private static MachineRecoveryStepItem ReconnectStep(CanvasNode node, string status)
    {
        var statusKey = status switch
        {
            HostStatuses.Connecting => RecoveryStepStatus.Running,
            HostStatuses.Connected => RecoveryStepStatus.Passed,
            _ => RecoveryStepStatus.Pending
        };
        return MachineRecoveryStepItem.Create(
            "reconnect",
            node.Id,
            "Reconnect",
            status == HostStatuses.Connecting
                ? "A connection attempt is already in progress."
                : "Open a fresh relay after the endpoint is healthy.",
            statusKey,
            "Reconnect",
            "reconnect");
    }

    private static MachineRecoveryStepItem RemoveRouteStep(CanvasNode node, string status)
    {
        return MachineRecoveryStepItem.Create(
            "remove-route",
            node.Id,
            "Remove stale route",
            "Use only when this saved endpoint is no longer valid.",
            status == HostStatuses.Connected ? RecoveryStepStatus.Passed : RecoveryStepStatus.Warning,
            "Remove",
            "remove stale route");
    }

    private static string DetailFor(CanvasNode node)
    {
        if (NormalizedHostLastError(node.Metadata.HostLastError) is { } lastError)
        {
            return lastError;
        }

        var platform = node.Metadata.Platform ?? HostPlatforms.Unknown;
        var endpoint = string.IsNullOrWhiteSpace(node.Subtitle)
            ? node.Metadata.CodexHome ?? "No endpoint recorded."
            : node.Subtitle;
        return $"{platform} - {endpoint}";
    }

    private static string EndpointFor(CanvasNode node)
    {
        return string.IsNullOrWhiteSpace(node.Subtitle)
            ? node.Metadata.HostID ?? "saved route"
            : node.Subtitle;
    }

    private static string? NormalizedHostLastError(string? lastError)
    {
        return string.IsNullOrWhiteSpace(lastError) ? null : lastError.Trim();
    }

    private static SolidColorBrush StatusBrushFor(string status)
    {
        return RecoveryBrush(MachineRecoveryPresentation.TargetStatus(status).ForegroundHex);
    }

    private static SolidColorBrush StatusBackgroundFor(string status)
    {
        return RecoveryBrush(MachineRecoveryPresentation.TargetStatus(status).BackgroundHex);
    }

    private static SolidColorBrush StatusBorderFor(string status)
    {
        return RecoveryBrush(MachineRecoveryPresentation.TargetStatus(status).BorderHex);
    }

    internal static SolidColorBrush RecoveryBrush(string hex)
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
}

public sealed class MachineRecoveryStepItem
{
    public string Id { get; set; } = "";

    public string TargetId { get; set; } = "";

    public string Title { get; set; } = "";

    public string Detail { get; set; } = "";

    public string Summary { get; set; } = "";

    public string ActionText { get; set; } = "";

    public string ActionGlyph { get; set; } = MachineRecoveryPresentation.DefaultActionGlyph;

    public string Glyph { get; set; } = "\uEA3A";

    public string StatusKey { get; set; } = RecoveryStepStatus.Pending;

    public bool IsRecommended { get; set; }

    public Visibility RecommendedVisibility => IsRecommended ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ActionVisibility =>
        string.IsNullOrWhiteSpace(ActionText) ? Visibility.Collapsed : Visibility.Visible;

    public SolidColorBrush StatusBrush =>
        MachineRecoveryItem.RecoveryBrush(MachineRecoveryPresentation.StepStatus(StatusKey).ForegroundHex);

    public SolidColorBrush BackgroundBrush => IsRecommended
        ? MachineRecoveryItem.RecoveryBrush("#140A84FF")
        : MachineRecoveryItem.RecoveryBrush("#242A2C30");

    public SolidColorBrush BorderBrush => IsRecommended
        ? MachineRecoveryItem.RecoveryBrush("#550A84FF")
        : MachineRecoveryItem.RecoveryBrush("#22FFFFFF");

    public SolidColorBrush ActionBackgroundBrush => IsRecommended
        ? MachineRecoveryItem.RecoveryBrush("#220A84FF")
        : MachineRecoveryItem.RecoveryBrush("#00FFFFFF");

    public SolidColorBrush ActionBorderBrush => IsRecommended
        ? MachineRecoveryItem.RecoveryBrush("#660A84FF")
        : MachineRecoveryItem.RecoveryBrush("#33FFFFFF");

    public string ActionTooltip =>
        string.IsNullOrWhiteSpace(ActionText) ? "" : Summary;

    public string ActionAutomationName =>
        string.IsNullOrWhiteSpace(ActionText) ? "" : $"{ActionText} {Title}";

    public static MachineRecoveryStepItem Create(
        string id,
        string targetId,
        string title,
        string detail,
        string statusKey,
        string actionText,
        string summary)
    {
        return new MachineRecoveryStepItem
        {
            Id = id,
            TargetId = targetId,
            Title = title,
            Detail = detail,
            Summary = summary,
            ActionText = actionText,
            ActionGlyph = MachineRecoveryPresentation.StepAction(id).Glyph,
            StatusKey = statusKey,
            Glyph = GlyphFor(statusKey)
        };
    }

    private static string GlyphFor(string statusKey)
    {
        return MachineRecoveryPresentation.StepStatus(statusKey).Glyph;
    }
}

public static class RecoveryStepStatus
{
    public const string Pending = "pending";
    public const string Running = "running";
    public const string Passed = "passed";
    public const string Warning = "warning";
    public const string Failed = "failed";
}

public sealed class ReaderTranscriptFilterItem
{
    public string ThreadId { get; set; } = "";

    public string CategoryKey { get; set; } = "";

    public string DisplayText { get; set; } = "";

    public string Tooltip { get; set; } = "";

    public string Glyph { get; set; } = "\uEA3A";

    public SolidColorBrush BackgroundBrush { get; set; } = ReaderBrush("#12697586");

    public SolidColorBrush BorderBrush { get; set; } = ReaderBrush("#24697586");

    public SolidColorBrush ForegroundBrush { get; set; } = ReaderBrush("#A7B0BF");

    public static List<ReaderTranscriptFilterItem> Build(
        string threadId,
        IReadOnlyList<ReaderTranscriptRow> rows,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories,
        bool includeCounts = true,
        int additionalProgressCount = 0,
        int additionalSystemCount = 0)
    {
        return
        [
            Create(threadId, ReaderTranscriptCategory.Message, TranscriptCategoryPresentation.KeyMessages, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.Progress, TranscriptCategoryPresentation.KeyProgress, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.Thought, TranscriptCategoryPresentation.KeyThoughts, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.Tool, TranscriptCategoryPresentation.KeyTools, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.Artifact, TranscriptCategoryPresentation.KeyArtifacts, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.Approval, TranscriptCategoryPresentation.KeyApprovals, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount),
            Create(threadId, ReaderTranscriptCategory.System, TranscriptCategoryPresentation.KeySystem, rows, activeCategories, includeCounts, additionalProgressCount, additionalSystemCount)
        ];
    }

    private static ReaderTranscriptFilterItem Create(
        string threadId,
        ReaderTranscriptCategory category,
        string key,
        IReadOnlyList<ReaderTranscriptRow> rows,
        IReadOnlySet<ReaderTranscriptCategory> activeCategories,
        bool includeCounts,
        int additionalProgressCount,
        int additionalSystemCount)
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

        var isActive = activeCategories.Contains(category);
        var presentation = TranscriptCategoryPresentation.Resolve(key, isActive);
        return new ReaderTranscriptFilterItem
        {
            ThreadId = threadId,
            CategoryKey = key,
            DisplayText = includeCounts ? $"{presentation.Title} {count}" : presentation.Title,
            Tooltip = $"{(isActive ? "Hide" : "Show")} {presentation.Title.ToLowerInvariant()} rows",
            Glyph = presentation.WindowsGlyph,
            BackgroundBrush = ReaderBrush(presentation.BadgeBackgroundHex),
            BorderBrush = ReaderBrush(presentation.BorderHex),
            ForegroundBrush = ReaderBrush(presentation.ForegroundHex)
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
}

public enum ReaderTranscriptCategory
{
    Message,
    Progress,
    Thought,
    Tool,
    Artifact,
    Approval,
    System
}

public sealed class ReaderTranscriptRow : INotifyPropertyChanged
{
    private const int PreviewCharacterLimit = 1500;

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string ThreadId { get; set; } = "";

    public ReaderTranscriptCategory Category { get; set; }

    public HashSet<ReaderTranscriptCategory> Categories { get; set; } = [];

    public string CategoryLabel { get; set; } = "";

    public string CategoryGlyph { get; set; } = "\uEA3A";

    public string RoleTitle { get; set; } = "";

    public string HeaderStatusGlyph { get; set; } = "";

    public string SourceRole { get; set; } = "";

    public string Text { get; set; } = "";

    public string FullText { get; set; } = "";

    public string CollapsedText { get; set; } = "";

    public bool UsesDetailsDisclosure { get; set; }

    public string InlineTextGlyph { get; set; } = "";

    public Visibility InlineTextGlyphVisibility =>
        string.IsNullOrWhiteSpace(InlineTextGlyph) ? Visibility.Collapsed : Visibility.Visible;

    public double InlineTextGlyphColumnSpacing =>
        string.IsNullOrWhiteSpace(InlineTextGlyph)
            ? 0
            : IsEmptyTurnDetails
            ? ThreadTurnEventPresentation.EmptyContentSpacing
            : 8;

    public double InlineTextGlyphFontSize => IsEmptyTurnDetails
        ? ThreadTurnEventPresentation.EmptyIconFontSize
        : 12;

    public bool CanCopyText { get; set; }

    public Visibility CopyButtonVisibility =>
        CanCopyText && !string.IsNullOrWhiteSpace(FullText) ? Visibility.Visible : Visibility.Collapsed;

    public bool IsExpanded { get; private set; }

    public bool IsExpandable => UsesDetailsDisclosure
        ? !string.IsNullOrWhiteSpace(FullText)
        : FullText.Length > PreviewCharacterLimit;

    public Visibility ExpansionButtonVisibility => IsExpandable && !UsesDetailsDisclosure
        ? Visibility.Visible
        : Visibility.Collapsed;

    public Visibility HeaderDisclosureButtonVisibility => IsExpandable && UsesDetailsDisclosure
        ? Visibility.Visible
        : Visibility.Collapsed;

    public string ExpansionButtonText => UsesDetailsDisclosure
        ? IsExpanded
            ? TranscriptToolRowPresentation.HideDetailsLabel
            : TranscriptToolRowPresentation.ShowDetailsLabel
        : IsExpanded
        ? "Show less"
        : "Show full";

    public string ExpansionButtonToolTip => UsesDetailsDisclosure
        ? "Toggle tool details"
        : "Toggle full message";

    public string ExpansionGlyph => IsExpanded ? "\uE70E" : "\uE70D";

    public string TimeLabel { get; set; } = "";

    public bool IsEmptyTranscriptState { get; set; }

    public bool IsTurnEventHeader { get; set; }

    public bool IsEmptyTurnDetails { get; set; }

    public SolidColorBrush BackgroundBrush { get; set; } = ReaderBrush("#662A2C30");

    public SolidColorBrush BorderBrush { get; set; } = ReaderBrush("#22FFFFFF");

    public SolidColorBrush HeaderStatusBrush { get; set; } = ReaderBrush(TranscriptCategoryPresentation.SecondaryHex);

    public Thickness RowBorderThickness { get; set; } = new(0);

    public Thickness RowPadding => IsTurnEventHeader
        ? new Thickness(
            ThreadTurnEventPresentation.HeaderHorizontalPadding,
            ThreadTurnEventPresentation.HeaderVerticalPadding,
            ThreadTurnEventPresentation.HeaderHorizontalPadding,
            ThreadTurnEventPresentation.HeaderVerticalPadding)
        : new Thickness(IsEmptyTurnDetails
            ? ThreadTurnEventPresentation.EmptyPadding
            : TranscriptRowLayout.Padding);

    public CornerRadius RowCornerRadius => new(IsTurnEventHeader
        ? ThreadTurnEventPresentation.HeaderCornerRadius
        : IsEmptyTurnDetails
        ? ThreadTurnEventPresentation.EmptyCornerRadius
        : TranscriptRowLayout.CornerRadius);

    public double RowContentSpacing => IsTurnEventHeader
        ? ThreadTurnEventPresentation.HeaderContentSpacing
        : IsEmptyTurnDetails
        ? 0
        : TranscriptRowLayout.ContentSpacing;

    public SolidColorBrush BadgeBackgroundBrush { get; set; } = ReaderBrush("#12697586");

    public SolidColorBrush BadgeForegroundBrush { get; set; } = ReaderBrush("#A7B0BF");

    public Visibility BadgeVisibility => IsEmptyTranscriptState || IsEmptyTurnDetails || Category == ReaderTranscriptCategory.Message
        ? Visibility.Collapsed
        : Visibility.Visible;

    public int RoleTitleColumn => BadgeVisibility == Visibility.Visible ? 1 : 0;

    public Visibility HeaderStatusGlyphVisibility =>
        IsTurnEventHeader && !string.IsNullOrWhiteSpace(HeaderStatusGlyph)
            ? Visibility.Visible
            : Visibility.Collapsed;

    public double HeaderTitleStackSpacing => HeaderStatusGlyphVisibility == Visibility.Visible
        ? ThreadTurnEventPresentation.HeaderStatusIconSpacing
        : 0;

    public double HeaderStatusGlyphFontSize => ThreadTurnEventPresentation.HeaderStatusIconFontSize;

    public Visibility TimeLabelVisibility => IsEmptyTranscriptState || IsEmptyTurnDetails ? Visibility.Collapsed : Visibility.Visible;

    public Visibility EmptyStateHeaderVisibility => IsEmptyTranscriptState ? Visibility.Visible : Visibility.Collapsed;

    public Visibility TranscriptHeaderVisibility => IsEmptyTranscriptState || IsEmptyTurnDetails ? Visibility.Collapsed : Visibility.Visible;

    public VerticalAlignment RowContentVerticalAlignment => IsEmptyTranscriptState
        ? VerticalAlignment.Center
        : VerticalAlignment.Top;

    public HorizontalAlignment RowHorizontalAlignment => IsEmptyTranscriptState
        ? HorizontalAlignment.Center
        : IsTurnEventHeader
        ? HorizontalAlignment.Stretch
        : IsEmptyTurnDetails
        ? HorizontalAlignment.Stretch
        : SourceRole == "user"
        ? HorizontalAlignment.Right
        : HorizontalAlignment.Left;

    public double RowMinWidth => IsEmptyTranscriptState
        ? ThreadTranscriptEmptyStatePresentation.Width
        : IsTurnEventHeader
        ? 0
        : IsEmptyTurnDetails
        ? 0
        : SourceRole == "user" ? 220 : 0;

    public double RowMinHeight => IsEmptyTranscriptState ? ThreadTranscriptEmptyStatePresentation.MinHeight : 0;

    public double RowMaxWidth => IsEmptyTranscriptState
        ? ThreadTranscriptEmptyStatePresentation.Width
        : IsTurnEventHeader
        ? ThreadTurnEventPresentation.HeaderMaxWidth
        : IsEmptyTurnDetails
        ? ThreadTurnEventPresentation.EmptyMaxWidth
        : 410;

    public double EmptyStateIconFontSize => ThreadTranscriptEmptyStatePresentation.IconFontSize;

    public double EmptyStateTitleFontSize => ThreadTranscriptEmptyStatePresentation.TitleFontSize;

    public double RowTextFontSize => IsEmptyTranscriptState
        ? ThreadTranscriptEmptyStatePresentation.DetailFontSize
        : IsTurnEventHeader
        ? ThreadTurnEventPresentation.HeaderDetailFontSize
        : IsEmptyTurnDetails
        ? ThreadTurnEventPresentation.EmptyTextFontSize
        : UsesDetailsDisclosure
        ? IsExpanded ? 12 : 11
        : 13;

    public FontFamily RowTextFontFamily => UsesDetailsDisclosure && IsExpanded
        ? new FontFamily("Consolas")
        : new FontFamily("Segoe UI");

    public SolidColorBrush RoleForegroundBrush =>
        IsEmptyTranscriptState
            ? ReaderBrush(ThreadTranscriptEmptyStatePresentation.TitleForegroundHex)
        : IsEmptyTurnDetails
            ? ReaderBrush(ThreadTurnEventPresentation.EmptyForegroundHex)
        : Category == ReaderTranscriptCategory.Message
            ? ReaderBrush(TranscriptMessageRowPresentation.Resolve(SourceRole).RoleForegroundHex)
            : BadgeForegroundBrush;

    public SolidColorBrush TextForegroundBrush =>
        IsEmptyTranscriptState
            ? ReaderBrush(ThreadTranscriptEmptyStatePresentation.DetailForegroundHex)
            : IsTurnEventHeader
            ? ReaderBrush(ThreadTurnEventPresentation.HeaderDetailForegroundHex)
            : IsEmptyTurnDetails
            ? ReaderBrush(ThreadTurnEventPresentation.EmptyForegroundHex)
            : UsesDetailsDisclosure && !IsExpanded
            ? ReaderBrush(TranscriptCategoryPresentation.SecondaryHex)
            : Category is ReaderTranscriptCategory.Progress or ReaderTranscriptCategory.Thought
            ? ReaderBrush("#A7B0BF")
            : ReaderBrush("#F2F4F7");

    public TextAlignment RowTextAlignment => IsEmptyTranscriptState ? TextAlignment.Center : TextAlignment.Left;

    public ThreadAttentionItem? AttentionItem { get; set; }

    public Visibility AttentionApprovalVisibility =>
        AttentionItem?.SupportsApprovalDecision == true ? Visibility.Visible : Visibility.Collapsed;

    public Visibility AttentionTypedResponseVisibility =>
        AttentionItem?.SupportsTypedResponse == true ? Visibility.Visible : Visibility.Collapsed;

    public Visibility AttentionFocusButtonVisibility =>
        AttentionItem?.HasOwningNode == true ? Visibility.Visible : Visibility.Collapsed;

    public string AttentionFocusToolTip => AttentionTranscriptRowPresentation.FocusToolTip;

    public string AttentionFocusAccessibilityName => AttentionTranscriptRowPresentation.FocusAccessibilityName;

    public double AttentionFocusIconWidth => AttentionItem?.FocusIconWidth ?? AttentionRequestCardPresentation.FocusIconWidth;

    public double AttentionFocusIconHeight => AttentionItem?.FocusIconHeight ?? AttentionRequestCardPresentation.FocusIconHeight;

    public double AttentionFocusIconStrokeThickness =>
        AttentionItem?.FocusIconStrokeThickness ?? AttentionRequestCardPresentation.FocusIconStrokeThickness;

    public double AttentionActionButtonSpacing =>
        AttentionItem?.ActionButtonSpacing ?? AttentionRequestCardPresentation.ActionButtonSpacing;

    public Thickness AttentionActionButtonPadding => AttentionItem?.ActionButtonPadding ?? new Thickness(
        AttentionRequestCardPresentation.ActionButtonHorizontalPadding,
        AttentionRequestCardPresentation.ActionButtonVerticalPadding,
        AttentionRequestCardPresentation.ActionButtonHorizontalPadding,
        AttentionRequestCardPresentation.ActionButtonVerticalPadding);

    public IReadOnlyList<AttentionResponseChoiceItem> AttentionResponseChoices
    {
        get
        {
            if (AttentionItem is null)
            {
                return Array.Empty<AttentionResponseChoiceItem>();
            }

            return AttentionItem.ResponseChoices;
        }
    }

    public Visibility AttentionChoiceResponseVisibility =>
        AttentionItem?.ChoiceResponseVisibility ?? Visibility.Collapsed;

    public Visibility AttentionFreeformResponseVisibility =>
        AttentionItem?.FreeformResponseVisibility ?? Visibility.Collapsed;

    public AttentionResponseChoiceItem? SelectedAttentionResponseChoice
    {
        get => AttentionItem?.SelectedResponseChoice;
        set
        {
            if (AttentionItem is not null)
            {
                AttentionItem.SelectedResponseChoice = value;
                OnPropertyChanged(nameof(SelectedAttentionResponseChoice));
                OnPropertyChanged(nameof(AttentionResponseText));
                OnPropertyChanged(nameof(CanSendTypedAttentionResponse));
            }
        }
    }

    public bool CanSendTypedAttentionResponse =>
        AttentionItem?.CanSendTypedResponse == true;

    public string AttentionResponseText
    {
        get => AttentionItem?.ResponseText ?? "";
        set
        {
            if (AttentionItem is not null)
            {
                AttentionItem.ResponseText = value;
                OnPropertyChanged(nameof(AttentionResponseText));
                OnPropertyChanged(nameof(CanSendTypedAttentionResponse));
            }
        }
    }

    private void OnPropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void ApplyThreadState(string threadId, bool isExpanded)
    {
        ThreadId = threadId;
        IsExpanded = isExpanded && IsExpandable;
        Text = UsesDetailsDisclosure
            ? IsExpanded
                ? FullText
                : CollapsedText
            : DisplayText(FullText, IsExpanded);
    }

    public bool MatchesCategory(ReaderTranscriptCategory category)
    {
        return Category == category || Categories.Contains(category);
    }

    public bool MatchesAnyCategory(IReadOnlySet<ReaderTranscriptCategory> categories)
    {
        return categories.Any(MatchesCategory);
    }

    public static ReaderTranscriptRow FromMessage(LocalThreadMessage message)
    {
        var role = message.Role.Trim().ToLowerInvariant();
        var messageCategories = MessageCategorySet(role);
        var allowsApprovalTextHeuristic = role is "assistant" or "system" or "event";

        if (role is "approval" or "attention" ||
            (allowsApprovalTextHeuristic && LooksLikeApprovalText(message.Text)))
        {
            return Approval("Approval", message.Text, message.CreatedAt, message.Id);
        }

        if (role is "system" or "event")
        {
            return SystemRow("Event", message.Text, message.CreatedAt, message.Id);
        }

        if (role is "reasoning" or "thought")
        {
            return Thought("Reasoning", message.Text, message.CreatedAt, message.Id);
        }

        if (role is "tool" or "function")
        {
            return Tool("Tool", message.Text, message.CreatedAt, message.Id);
        }

        if (role is "artifact" or "file" or "diff" or "image" || LooksLikeArtifactText(message.Text))
        {
            return Artifact("Artifact", message.Text, message.CreatedAt, message.Id, messageCategories);
        }

        if (role == "assistant" && IsProgressLikeAssistantText(message.Text))
        {
            return Progress("Assistant progress", message.Text, message.CreatedAt, message.Id, canCopyText: true);
        }

        var messagePresentation = TranscriptMessageRowPresentation.Resolve(role);
        return Create(
            ReaderTranscriptCategory.Message,
            "Message",
            messagePresentation.WindowsGlyph,
            messagePresentation.RoleTitle,
            message.Text,
            message.CreatedAt,
            ReaderBrush(messagePresentation.RowBackgroundHex),
            ReaderBrush(messagePresentation.RowBorderHex),
            ReaderBrush(messagePresentation.BadgeBackgroundHex),
            ReaderBrush(messagePresentation.RoleForegroundHex),
            messageCategories,
            message.Id,
            sourceRole: messagePresentation.SourceRole,
            canCopyText: true);
    }

    public static ReaderTranscriptRow Progress(
        string title,
        string text,
        DateTimeOffset createdAt,
        string? id = null,
        bool canCopyText = false,
        string inlineTextGlyph = "")
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.Progress);
        return Create(
            ReaderTranscriptCategory.Progress,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            title,
            text,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: id,
            canCopyText: canCopyText,
            inlineTextGlyph: inlineTextGlyph);
    }

    public static ReaderTranscriptRow PendingAssistant(DateTimeOffset createdAt)
    {
        var presentation = PendingAssistantPresentation.Resolve();
        return Progress(
            presentation.RoleTitle,
            presentation.Text,
            createdAt,
            "awaiting-response",
            inlineTextGlyph: presentation.WindowsGlyph);
    }

    public static ReaderTranscriptRow Thought(string title, string text, DateTimeOffset createdAt, string? id = null)
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.Thought);
        return Create(
            ReaderTranscriptCategory.Thought,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            title,
            text,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: id);
    }

    public static ReaderTranscriptRow Tool(string title, string text, DateTimeOffset createdAt, string? id = null)
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.Tool);
        var toolPresentation = TranscriptToolRowPresentation.Resolve(text);
        var row = Create(
            ReaderTranscriptCategory.Tool,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            string.IsNullOrWhiteSpace(title) || title == "Tool" ? toolPresentation.Title : title,
            toolPresentation.Body,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: id);
        row.UsesDetailsDisclosure = toolPresentation.HasDetails;
        row.CollapsedText = toolPresentation.Summary;
        row.ApplyThreadState("", false);
        return row;
    }

    public static ReaderTranscriptRow Artifact(
        string title,
        string text,
        DateTimeOffset createdAt,
        string? id = null,
        IEnumerable<ReaderTranscriptCategory>? categories = null)
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.Artifact);
        return Create(
            ReaderTranscriptCategory.Artifact,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            title,
            text,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            categories,
            id);
    }

    public static ReaderTranscriptRow Approval(string title, string text, DateTimeOffset createdAt, string? id = null)
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.Approval);
        return Create(
            ReaderTranscriptCategory.Approval,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            title,
            text,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: id);
    }

    public static ReaderTranscriptRow Attention(ThreadAttentionItem item)
    {
        var presentation = AttentionTranscriptRowPresentation.Resolve();
        var row = Create(
            ReaderTranscriptCategory.Approval,
            presentation.CategoryLabel,
            presentation.CategoryWindowsGlyph,
            item.Method,
            item.PromptText,
            item.CreatedAt,
            ReaderBrush(presentation.RowBackgroundHex),
            ReaderBrush(presentation.RowBorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.BadgeForegroundHex),
            id: $"attention:{item.Id}");
        row.RowBorderThickness = new Thickness(presentation.RowBorderThickness);
        row.AttentionItem = item;
        return row;
    }

    public static ReaderTranscriptRow TurnEvent(LocalThreadTurn turn, IReadOnlyList<ReaderTranscriptRow> itemRows)
    {
        var category = CategoryPresentation(ReaderTranscriptCategory.System);
        var presentation = ThreadTurnEventPresentation.Resolve(turn);
        var row = Create(
            ReaderTranscriptCategory.System,
            category.CompactTitle,
            category.WindowsGlyph,
            presentation.HeaderTitle,
            presentation.Detail,
            turn.StartedAt,
            ReaderBrush(presentation.HeaderBackgroundHex),
            ReaderBrush(presentation.HeaderBorderHex),
            ReaderBrush(category.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: $"turn:{turn.Id}");
        row.IsTurnEventHeader = true;
        row.HeaderStatusGlyph = presentation.WindowsGlyph;
        row.HeaderStatusBrush = ReaderBrush(presentation.ForegroundHex);
        row.RowBorderThickness = new Thickness(0);
        return row;
    }

    public static ReaderTranscriptRow EmptyTurn(LocalThreadTurn turn)
    {
        var category = CategoryPresentation(ReaderTranscriptCategory.System);
        var presentation = ThreadTurnEventPresentation.Resolve(turn);
        var row = Create(
            ReaderTranscriptCategory.System,
            category.CompactTitle,
            presentation.EmptyWindowsGlyph,
            presentation.EmptyTitle,
            presentation.EmptyDetail,
            turn.StartedAt,
            ReaderBrush(presentation.EmptyBackgroundHex),
            ReaderBrush(presentation.EmptyBorderHex),
            ReaderBrush(category.BadgeBackgroundHex),
            ReaderBrush(presentation.EmptyForegroundHex),
            id: $"turn:{turn.Id}:empty");
        row.IsEmptyTurnDetails = true;
        row.InlineTextGlyph = presentation.EmptyWindowsGlyph;
        row.RowBorderThickness = new Thickness(0);
        row.RoleTitle = "";
        return row;
    }

    public static ReaderTranscriptRow SystemRow(string title, string text, DateTimeOffset createdAt, string? id = null)
    {
        var presentation = CategoryPresentation(ReaderTranscriptCategory.System);
        return Create(
            ReaderTranscriptCategory.System,
            presentation.CompactTitle,
            presentation.WindowsGlyph,
            title,
            text,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BadgeBackgroundHex),
            ReaderBrush(presentation.ForegroundHex),
            id: id);
    }

    public static ReaderTranscriptRow EmptyTranscript(DateTimeOffset createdAt)
    {
        var presentation = ThreadTranscriptEmptyStatePresentation.Resolve();
        var row = Create(
            ReaderTranscriptCategory.System,
            "",
            presentation.WindowsGlyph,
            presentation.Title,
            presentation.Detail,
            createdAt,
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.BorderHex),
            ReaderBrush(presentation.BackgroundHex),
            ReaderBrush(presentation.TitleForegroundHex),
            id: "empty-transcript");
        row.IsEmptyTranscriptState = true;
        return row;
    }

    private static string TurnGlyph(string status)
    {
        return ThreadTurnEventPresentation.WindowsGlyph(status);
    }

    private static TranscriptCategoryPresentationSnapshot CategoryPresentation(
        ReaderTranscriptCategory category,
        bool isActive = true)
    {
        return TranscriptCategoryPresentation.Resolve(CategoryKeyFor(category), isActive);
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

    private static ReaderTranscriptRow Create(
        ReaderTranscriptCategory category,
        string categoryLabel,
        string categoryGlyph,
        string roleTitle,
        string text,
        DateTimeOffset createdAt,
        SolidColorBrush backgroundBrush,
        SolidColorBrush borderBrush,
        SolidColorBrush badgeBackgroundBrush,
        SolidColorBrush badgeForegroundBrush,
        IEnumerable<ReaderTranscriptCategory>? categories = null,
        string? id = null,
        string sourceRole = "",
        bool canCopyText = false,
        string inlineTextGlyph = "")
    {
        var categorySet = categories?.ToHashSet() ?? new HashSet<ReaderTranscriptCategory>();
        categorySet.Add(category);
        var row = new ReaderTranscriptRow
        {
            Id = string.IsNullOrWhiteSpace(id) ? Guid.NewGuid().ToString() : id!,
            Category = category,
            Categories = categorySet,
            CategoryLabel = categoryLabel,
            CategoryGlyph = categoryGlyph,
            RoleTitle = roleTitle,
            SourceRole = sourceRole,
            FullText = text,
            InlineTextGlyph = inlineTextGlyph,
            CanCopyText = canCopyText,
            TimeLabel = FormatTimeLabel(createdAt),
            BackgroundBrush = backgroundBrush,
            BorderBrush = borderBrush,
            BadgeBackgroundBrush = badgeBackgroundBrush,
            BadgeForegroundBrush = badgeForegroundBrush
        };
        row.ApplyThreadState("", false);
        return row;
    }

    private static string DisplayText(string text, bool isExpanded)
    {
        if (isExpanded || text.Length <= PreviewCharacterLimit)
        {
            return text;
        }

        return text[..PreviewCharacterLimit];
    }

    private static HashSet<ReaderTranscriptCategory> MessageCategorySet(string role)
    {
        return role is "user" or "assistant"
            ? [ReaderTranscriptCategory.Message]
            : [];
    }

    private static bool LooksLikeApprovalText(string text)
    {
        var firstLine = FirstLine(text);
        return firstLine.StartsWith("approval required", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("needs approval", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("needs input", StringComparison.OrdinalIgnoreCase) ||
            firstLine.Contains("requires approval", StringComparison.OrdinalIgnoreCase);
    }

    private static bool LooksLikeArtifactText(string text)
    {
        var trimmed = text.Trim();
        var firstLine = FirstLine(trimmed);
        return firstLine.StartsWith("artifact:", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("artifact ", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("file artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("image artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("diff artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("diff --git ", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("\n--- ", StringComparison.Ordinal) && trimmed.Contains("\n+++ ", StringComparison.Ordinal);
    }

    private static bool IsProgressLikeAssistantText(string text)
    {
        var firstLine = FirstLine(text).ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(firstLine))
        {
            return false;
        }

        string[] progressVerbs =
        [
            "add", "adding", "build", "building", "check", "checking", "collect", "collecting",
            "fetch", "fetching", "hydrate", "hydrating", "inspect", "inspecting", "load", "loading",
            "look", "looking", "open", "opening", "patch", "patching", "prepare", "preparing",
            "read", "reading", "review", "reviewing", "run", "running", "scan", "scanning",
            "scope", "scoping", "start", "starting", "test", "testing", "update", "updating",
            "validate", "validating", "verify", "verifying", "wait", "waiting", "wire", "wiring",
            "work", "working"
        ];

        if (progressVerbs.Any(verb => firstLine.StartsWith($"{verb} ", StringComparison.Ordinal)))
        {
            return true;
        }

        string[] firstPersonPrefixes = ["i am ", "i'm ", "i’m ", "i will ", "i'll ", "i’ll ", "i have ", "i've ", "i’ve "];
        foreach (var prefix in firstPersonPrefixes)
        {
            if (!firstLine.StartsWith(prefix, StringComparison.Ordinal))
            {
                continue;
            }

            var remainder = firstLine[prefix.Length..];
            if (progressVerbs.Any(verb =>
                    remainder.StartsWith($"{verb} ", StringComparison.Ordinal) ||
                    remainder.StartsWith($"going to {verb} ", StringComparison.Ordinal)))
            {
                return true;
            }
        }

        return firstLine.StartsWith("working on ", StringComparison.Ordinal) ||
            firstLine.StartsWith("waiting on ", StringComparison.Ordinal) ||
            firstLine.StartsWith("now ", StringComparison.Ordinal) ||
            firstLine.StartsWith("next ", StringComparison.Ordinal);
    }

    private static string FirstLine(string text)
    {
        return text
            .Trim()
            .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
            .FirstOrDefault()?
            .Trim() ?? "";
    }

    private static string FormatTimeLabel(DateTimeOffset value)
    {
        return value == default ? "" : value.ToLocalTime().ToString("t");
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
}

public sealed class ComposerAttachmentItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string ThreadId { get; set; } = "";

    public string Name { get; set; } = "";

    public string Detail { get; set; } = "";

    public string KindKey { get; set; } = ThreadArtifactItem.KindFile;

    public string KindGlyph { get; set; } = ThreadAttachmentChipPresentation.FileGlyph;

    public string? SourcePath { get; set; }

    public Thickness ChipPadding =>
        new(
            ThreadAttachmentChipPresentation.HorizontalPadding,
            ThreadAttachmentChipPresentation.VerticalPadding,
            ThreadAttachmentChipPresentation.HorizontalPadding,
            ThreadAttachmentChipPresentation.VerticalPadding);

    public Thickness TrayChipMargin =>
        new(
            0,
            0,
            ThreadAttachmentTrayLayout.ItemSpacing,
            ThreadAttachmentTrayLayout.BottomPadding);

    public SolidColorBrush ChipBackgroundBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).ChipBackgroundHex);

    public SolidColorBrush ChipBorderBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).ChipBorderHex);

    public SolidColorBrush KindForegroundBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).KindForegroundHex);

    public SolidColorBrush NameForegroundBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).NameForegroundHex);

    public SolidColorBrush DetailForegroundBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).DetailForegroundHex);

    public SolidColorBrush RemoveForegroundBrush =>
        BrushForHex(ThreadAttachmentChipPresentation.Resolve(KindKey).RemoveForegroundHex);

    public double ContentSpacing => ThreadAttachmentChipPresentation.ContentSpacing;

    public double NameFontSize => ThreadAttachmentChipPresentation.NameFontSize;

    public double DetailFontSize => ThreadAttachmentChipPresentation.DetailFontSize;

    public double IconFontSize => ThreadAttachmentChipPresentation.IconFontSize;

    public double RemoveIconFontSize => ThreadAttachmentChipPresentation.RemoveIconFontSize;

    public string TranscriptRole => KindKey switch
    {
        ThreadArtifactItem.KindImage => "image",
        ThreadArtifactItem.KindDiff => "diff",
        _ => "file"
    };

    public string TranscriptText
    {
        get
        {
            var kindLabel = KindKey switch
            {
                ThreadArtifactItem.KindImage => "Image artifact",
                ThreadArtifactItem.KindDiff => "Diff artifact",
                _ => "File artifact"
            };
            var source = string.IsNullOrWhiteSpace(SourcePath)
                ? "Attached locally from the Windows composer."
                : SourcePath;
            return $"{kindLabel}: {Name}\n{source}";
        }
    }

    public static ComposerAttachmentItem FromStorageFile(StorageFile file, string threadId = "")
    {
        return FromNameAndPath(file.Name, string.IsNullOrWhiteSpace(file.Path) ? null : file.Path, threadId);
    }

    public static ComposerAttachmentItem FromPath(string path, string threadId = "")
    {
        return FromNameAndPath(System.IO.Path.GetFileName(path), path, threadId);
    }

    public static ComposerAttachmentItem FromClipboardImage(string threadId = "")
    {
        var name = $"screenshot-{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}.png";
        return new ComposerAttachmentItem
        {
            ThreadId = threadId,
            Name = name,
            Detail = "Image - clipboard",
            KindKey = ThreadArtifactItem.KindImage,
            KindGlyph = ThreadAttachmentChipPresentation.GlyphFor(ThreadArtifactItem.KindImage)
        };
    }

    private static ComposerAttachmentItem FromNameAndPath(string name, string? path, string threadId)
    {
        var kind = KindForName(name);
        return new ComposerAttachmentItem
        {
            ThreadId = threadId,
            Name = string.IsNullOrWhiteSpace(name) ? "attachment" : name,
            Detail = $"{KindLabel(kind)} - {SourceLabel(path)}",
            KindKey = kind,
            KindGlyph = ThreadAttachmentChipPresentation.GlyphFor(kind),
            SourcePath = path
        };
    }

    private static string KindForName(string name)
    {
        var extension = System.IO.Path.GetExtension(name).ToLowerInvariant();
        return extension switch
        {
            ".png" or ".jpg" or ".jpeg" or ".gif" or ".webp" or ".heic" or ".bmp" => ThreadArtifactItem.KindImage,
            ".diff" or ".patch" => ThreadArtifactItem.KindDiff,
            _ => ThreadArtifactItem.KindFile
        };
    }

    private static string KindLabel(string kind)
    {
        return kind switch
        {
            ThreadArtifactItem.KindImage => "Image",
            ThreadArtifactItem.KindDiff => "Diff",
            _ => "File"
        };
    }

    private static string SourceLabel(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "local attachment";
        }

        var directory = System.IO.Path.GetDirectoryName(path);
        return string.IsNullOrWhiteSpace(directory) ? "local file" : directory;
    }

    private static SolidColorBrush BrushForHex(string hex)
    {
        var value = hex.TrimStart('#');
        var alpha = (byte)255;
        if (value.Length == 8)
        {
            byte.TryParse(value[..2], NumberStyles.HexNumber, null, out alpha);
            value = value[2..];
        }

        if (value.Length != 6 ||
            !byte.TryParse(value[..2], NumberStyles.HexNumber, null, out var red) ||
            !byte.TryParse(value[2..4], NumberStyles.HexNumber, null, out var green) ||
            !byte.TryParse(value[4..6], NumberStyles.HexNumber, null, out var blue))
        {
            return new SolidColorBrush(Colors.Gray);
        }

        return new SolidColorBrush(Windows.UI.Color.FromArgb(alpha, red, green, blue));
    }
}

public sealed class ThreadArtifactItem
{
    public const string KindImage = "image";
    public const string KindFile = "file";
    public const string KindDiff = "diff";

    public string Id { get; set; } = Guid.NewGuid().ToString();

    public string KindKey { get; set; } = KindFile;

    public string KindLabel { get; set; } = "File";

    public string KindGlyph { get; set; } = "\uE7C3";

    public string Title { get; set; } = "Artifact";

    public string Subtitle { get; set; } = "";

    public string Preview { get; set; } = "";

    public string PreviewText { get; set; } = "";

    public string? DisplayPath { get; set; }

    public SolidColorBrush BadgeBackgroundBrush { get; set; } = ArtifactBrush("#180A84FF");

    public SolidColorBrush BadgeForegroundBrush { get; set; } = ArtifactBrush("#6AB7FF");

    public static ThreadArtifactItem? FromMessage(LocalThreadMessage message)
    {
        var role = message.Role.Trim().ToLowerInvariant();
        var text = message.Text.Trim();
        if (!IsArtifactRole(role) && !LooksLikeArtifactText(text))
        {
            return null;
        }

        var kind = KindFor(role, text);
        var kindLabel = KindLabelFor(kind);
        var preview = string.IsNullOrWhiteSpace(text)
            ? "Artifact produced by this thread."
            : text;
        return new ThreadArtifactItem
        {
            Id = message.Id,
            KindKey = kind,
            KindLabel = kindLabel,
            KindGlyph = GlyphFor(kind),
            Title = TitleFor(kind, text),
            Subtitle = $"{kindLabel} - {FormatTimeLabel(message.CreatedAt)}",
            Preview = preview,
            PreviewText = PreviewTextFor(kind, preview),
            DisplayPath = DisplayPathFor(kind, text),
            BadgeBackgroundBrush = BackgroundFor(kind),
            BadgeForegroundBrush = ForegroundFor(kind)
        };
    }

    private static bool IsArtifactRole(string role)
    {
        return role is "artifact" or "file" or "image" or "diff";
    }

    private static bool LooksLikeArtifactText(string text)
    {
        var trimmed = text.Trim();
        var firstLine = FirstLine(trimmed);
        return firstLine.StartsWith("artifact:", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("artifact ", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("file artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("image artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("diff artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("diff --git ", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("\n--- ", StringComparison.Ordinal) && trimmed.Contains("\n+++ ", StringComparison.Ordinal);
    }

    private static string KindFor(string role, string text)
    {
        var firstLine = FirstLine(text);
        if (role == KindDiff ||
            firstLine.StartsWith("diff artifact", StringComparison.OrdinalIgnoreCase) ||
            firstLine.StartsWith("diff --git ", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("\n--- ", StringComparison.Ordinal) && text.Contains("\n+++ ", StringComparison.Ordinal))
        {
            return KindDiff;
        }

        if (role == KindImage ||
            firstLine.StartsWith("image artifact", StringComparison.OrdinalIgnoreCase) ||
            HasImageExtension(firstLine))
        {
            return KindImage;
        }

        return KindFile;
    }

    private static string PreviewTextFor(string kind, string preview)
    {
        if (kind == KindImage && !LooksLikeImagePath(preview))
        {
            return $"{preview}\n\nImage preview unavailable until a local or cached image path is present.";
        }

        return preview;
    }

    private static string? DisplayPathFor(string kind, string text)
    {
        string? fallbackImagePath = null;
        foreach (var line in Lines(text))
        {
            var candidate = TrimArtifactPrefix(line);
            if (string.IsNullOrWhiteSpace(candidate))
            {
                continue;
            }

            if (LooksLikeAbsolutePath(candidate) ||
                LooksLikeFileUri(candidate))
            {
                return candidate;
            }

            if (kind == KindImage && HasImageExtension(candidate))
            {
                fallbackImagePath ??= candidate;
            }
        }

        return fallbackImagePath;
    }

    private static IEnumerable<string> Lines(string text)
    {
        return text
            .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
            .Select(line => line.Trim().Trim('"', '\''))
            .Where(line => !string.IsNullOrWhiteSpace(line));
    }

    private static string TrimArtifactPrefix(string line)
    {
        string[] prefixes =
        [
            "Artifact:",
            "Artifact ",
            "File artifact:",
            "File artifact ",
            "Image artifact:",
            "Image artifact ",
            "Diff artifact:",
            "Diff artifact ",
            "Source:",
            "Path:",
            "Cached:"
        ];
        foreach (var prefix in prefixes)
        {
            if (line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return line[prefix.Length..].Trim().Trim('"', '\'');
            }
        }

        return line;
    }

    private static bool LooksLikeAbsolutePath(string value)
    {
        return System.IO.Path.IsPathRooted(value) ||
            value.Length > 2 && char.IsLetter(value[0]) && value[1] == ':' && (value[2] == '\\' || value[2] == '/');
    }

    private static bool LooksLikeFileUri(string value)
    {
        return value.StartsWith("file://", StringComparison.OrdinalIgnoreCase);
    }

    private static bool LooksLikeImagePath(string value)
    {
        var firstLine = FirstLine(value);
        return HasImageExtension(firstLine);
    }

    private static bool HasImageExtension(string text)
    {
        string[] extensions = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".bmp"];
        return extensions.Any(extension => text.Contains(extension, StringComparison.OrdinalIgnoreCase));
    }

    private static string TitleFor(string kind, string text)
    {
        var firstLine = FirstLine(text);
        if (kind == KindDiff && firstLine.StartsWith("diff --git ", StringComparison.OrdinalIgnoreCase))
        {
            var parts = firstLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 4)
            {
                return FileNameFromPath(parts[3]);
            }
        }

        string[] prefixes =
        [
            "Artifact:",
            "Artifact ",
            "File artifact:",
            "File artifact ",
            "Image artifact:",
            "Image artifact ",
            "Diff artifact:",
            "Diff artifact "
        ];
        foreach (var prefix in prefixes)
        {
            if (firstLine.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                var title = firstLine[prefix.Length..].Trim();
                return ShortTitle(string.IsNullOrWhiteSpace(title) ? KindLabelFor(kind) : title);
            }
        }

        return ShortTitle(string.IsNullOrWhiteSpace(firstLine) ? KindLabelFor(kind) : firstLine);
    }

    private static string ShortTitle(string title)
    {
        var normalized = title.Trim().Trim('"', '\'');
        if (normalized.Length <= 72)
        {
            return FileNameFromPath(normalized);
        }

        return $"{normalized[..69]}...";
    }

    private static string FileNameFromPath(string value)
    {
        var trimmed = value.Trim().Trim('"', '\'');
        if (trimmed.StartsWith("b/", StringComparison.Ordinal))
        {
            trimmed = trimmed[2..];
        }

        var slash = Math.Max(trimmed.LastIndexOf('/'), trimmed.LastIndexOf('\\'));
        return slash >= 0 && slash + 1 < trimmed.Length
            ? trimmed[(slash + 1)..]
            : trimmed;
    }

    private static string KindLabelFor(string kind)
    {
        return kind switch
        {
            KindImage => "Image",
            KindDiff => "Diff",
            _ => "File"
        };
    }

    private static string GlyphFor(string kind)
    {
        return kind switch
        {
            KindImage => "\uEB9F",
            KindDiff => "\uE8AB",
            _ => "\uE7C3"
        };
    }

    private static SolidColorBrush ForegroundFor(string kind)
    {
        return kind switch
        {
            KindImage => ArtifactBrush("#A78BFA"),
            KindDiff => ArtifactBrush("#F59E0B"),
            _ => ArtifactBrush("#6AB7FF")
        };
    }

    private static SolidColorBrush BackgroundFor(string kind)
    {
        return kind switch
        {
            KindImage => ArtifactBrush("#18A78BFA"),
            KindDiff => ArtifactBrush("#18F59E0B"),
            _ => ArtifactBrush("#180A84FF")
        };
    }

    private static string FirstLine(string text)
    {
        return text
            .Trim()
            .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
            .FirstOrDefault()?
            .Trim() ?? "";
    }

    private static string FormatTimeLabel(DateTimeOffset value)
    {
        return value == default ? "" : value.ToLocalTime().ToString("g");
    }

    private static SolidColorBrush ArtifactBrush(string hex)
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
}

public sealed class ArtifactDiffLineItem
{
    public string Text { get; set; } = "";

    public SolidColorBrush ForegroundBrush { get; set; } = DiffBrush("#D7DCE5");

    public SolidColorBrush BackgroundBrush { get; set; } = DiffBrush("#00000000");

    public static IReadOnlyList<ArtifactDiffLineItem> FromDiff(string diffText)
    {
        return diffText
            .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
            .Select(Create)
            .ToList();
    }

    private static ArtifactDiffLineItem Create(string line)
    {
        return new ArtifactDiffLineItem
        {
            Text = string.IsNullOrEmpty(line) ? " " : line,
            ForegroundBrush = ForegroundFor(line),
            BackgroundBrush = BackgroundFor(line)
        };
    }

    private static SolidColorBrush ForegroundFor(string line)
    {
        if (line.StartsWith("+", StringComparison.Ordinal) && !line.StartsWith("+++", StringComparison.Ordinal))
        {
            return DiffBrush("#34D399");
        }

        if (line.StartsWith("-", StringComparison.Ordinal) && !line.StartsWith("---", StringComparison.Ordinal))
        {
            return DiffBrush("#F97066");
        }

        if (line.StartsWith("@@", StringComparison.Ordinal))
        {
            return DiffBrush("#6AB7FF");
        }

        if (line.StartsWith("diff --git", StringComparison.Ordinal) ||
            line.StartsWith("---", StringComparison.Ordinal) ||
            line.StartsWith("+++", StringComparison.Ordinal) ||
            line.StartsWith("*** ", StringComparison.Ordinal))
        {
            return DiffBrush("#A7B0BF");
        }

        return DiffBrush("#D7DCE5");
    }

    private static SolidColorBrush BackgroundFor(string line)
    {
        if (line.StartsWith("+", StringComparison.Ordinal) && !line.StartsWith("+++", StringComparison.Ordinal))
        {
            return DiffBrush("#1834D399");
        }

        if (line.StartsWith("-", StringComparison.Ordinal) && !line.StartsWith("---", StringComparison.Ordinal))
        {
            return DiffBrush("#18F97066");
        }

        if (line.StartsWith("@@", StringComparison.Ordinal))
        {
            return DiffBrush("#180A84FF");
        }

        return DiffBrush("#00000000");
    }

    private static SolidColorBrush DiffBrush(string hex)
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
}

public sealed class EdgeRouteItem
{
    public string StateText { get; set; } = "";

    public string TimestampText { get; set; } = "";

    public string RouteText { get; set; } = "";

    public string Snippet { get; set; } = "";

    public SolidColorBrush StateBrush { get; set; } = RouteBrush(MessageRouteDeliveryPresentation.UnknownForegroundHex);

    public static EdgeRouteItem FromRoute(MessageRoute route, string sourceTitle, string targetTitle)
    {
        var state = string.IsNullOrWhiteSpace(route.DeliveryState)
            ? MessageRouteDeliveryStates.Unknown
            : route.DeliveryState.Trim();
        var presentation = MessageRouteDeliveryPresentation.Resolve(state);

        return new EdgeRouteItem
        {
            StateText = presentation.Label,
            TimestampText = FormatTimeLabel(route.Timestamp),
            RouteText = $"{sourceTitle} -> {targetTitle}",
            Snippet = string.IsNullOrWhiteSpace(route.Snippet) ? "No snippet recorded for this delivery." : route.Snippet.Trim(),
            StateBrush = RouteBrush(presentation.ForegroundHex)
        };
    }

    private static string FormatTimeLabel(DateTimeOffset value)
    {
        return value == default ? "" : value.ToLocalTime().ToString("h:mm:ss tt");
    }

    private static SolidColorBrush RouteBrush(string hex)
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
}

public sealed class ThreadAttentionItem : INotifyPropertyChanged
{
    private string _responseText = "";
    private AttentionResponseChoiceItem? _selectedResponseChoice;

    public event PropertyChangedEventHandler? PropertyChanged;

    public static ThreadAttentionItem FromRequest(
        RuntimeAttentionRequest request,
        string? owningNodeId,
        string threadLabel,
        string hostLabel,
        string promptText)
    {
        var presentation = AttentionRequestCardPresentation.Resolve(request.Method, promptText);
        var item = new ThreadAttentionItem
        {
            Id = request.Id,
            OwningNodeId = owningNodeId,
            Method = presentation.MethodText,
            ThreadLabel = string.IsNullOrWhiteSpace(threadLabel) ? "Unknown thread" : threadLabel,
            HostLabel = string.IsNullOrWhiteSpace(hostLabel) ? "Unknown host" : hostLabel,
            PromptText = presentation.PromptText,
            ShowTargetLabel = presentation.ShowTargetLabel,
            CreatedAt = request.CreatedAt,
            SupportsApprovalDecision = SupportsApprovalDecisionFor(request.Method),
            SupportsTypedResponse = SupportsTypedResponseFor(request.Method)
        };

        var responseChoices = RuntimeAttentionRequestPresentation.TypedResponseChoices(request);
        foreach (var choice in responseChoices)
        {
            item.ResponseChoices.Add(AttentionResponseChoiceItem.FromChoice(choice));
        }

        if (item.ResponseChoices.Count > 0)
        {
            var initialValue = RuntimeAttentionRequestPresentation.InitialTypedResponseValue(request, responseChoices);
            item.SelectedResponseChoice = item.ResponseChoices.FirstOrDefault(choice =>
                string.Equals(choice.Value, initialValue, StringComparison.OrdinalIgnoreCase)) ?? item.ResponseChoices[0];
        }
        else
        {
            item.ResponseText = "";
        }

        return item;
    }

    public string Id { get; set; } = "";

    public string? OwningNodeId { get; set; }

    public string Method { get; set; } = "";

    public string ThreadLabel { get; set; } = "";

    public string HostLabel { get; set; } = "";

    public string PromptText { get; set; } = "";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    private static AttentionRequestCardSnapshot CardLayout =>
        AttentionRequestCardPresentation.Resolve("attention", "response");

    public Thickness CardMargin => new(0, 0, 0, CardLayout.BottomMargin);

    public Thickness CardPadding => new(
        CardLayout.HorizontalPadding,
        CardLayout.VerticalPadding,
        CardLayout.HorizontalPadding,
        CardLayout.VerticalPadding);

    public CornerRadius CardCornerRadius => new(CardLayout.CornerRadius);

    public double CardSpacing => CardLayout.StackSpacing;

    public Thickness CardBorderThickness => new(CardLayout.BorderThickness);

    public SolidColorBrush CardBackgroundBrush => AttentionBrush(CardLayout.BackgroundHex);

    public SolidColorBrush CardBorderBrush => AttentionBrush(CardLayout.BorderHex);

    public double FocusIconWidth => CardLayout.FocusIconWidth;

    public double FocusIconHeight => CardLayout.FocusIconHeight;

    public double FocusIconStrokeThickness => CardLayout.FocusIconStrokeThickness;

    public double ActionButtonSpacing => CardLayout.ActionButtonSpacing;

    public Thickness ActionButtonPadding => new(
        CardLayout.ActionButtonHorizontalPadding,
        CardLayout.ActionButtonVerticalPadding,
        CardLayout.ActionButtonHorizontalPadding,
        CardLayout.ActionButtonVerticalPadding);

    public bool SupportsApprovalDecision { get; set; }

    public bool SupportsTypedResponse { get; set; }

    public List<AttentionResponseChoiceItem> ResponseChoices { get; } = [];

    public AttentionResponseChoiceItem? SelectedResponseChoice
    {
        get => _selectedResponseChoice;
        set
        {
            if (ReferenceEquals(_selectedResponseChoice, value))
            {
                return;
            }

            _selectedResponseChoice = value;
            ResponseText = value?.Value ?? "";
            OnPropertyChanged(nameof(SelectedResponseChoice));
        }
    }

    public string ResponseText
    {
        get => _responseText;
        set
        {
            var normalizedValue = value ?? "";
            if (_responseText == normalizedValue)
            {
                return;
            }

            _responseText = normalizedValue;
            OnPropertyChanged(nameof(ResponseText));
            OnPropertyChanged(nameof(CanSendTypedResponse));
        }
    }

    public bool HasOwningNode => !string.IsNullOrWhiteSpace(OwningNodeId);

    public string TargetLabel => $"{ThreadLabel} - {HostLabel}";

    public bool ShowTargetLabel { get; set; }

    public Visibility TargetVisibility => ShowTargetLabel ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ApprovalVisibility => SupportsApprovalDecision ? Visibility.Visible : Visibility.Collapsed;

    public Visibility TypedResponseVisibility => SupportsTypedResponse ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ChoiceResponseVisibility =>
        SupportsTypedResponse && ResponseChoices.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

    public Visibility FreeformResponseVisibility =>
        SupportsTypedResponse && ResponseChoices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

    public bool CanSendTypedResponse =>
        SupportsTypedResponse && !string.IsNullOrWhiteSpace(ResponseText);

    private static bool SupportsApprovalDecisionFor(string method)
    {
        return method == "item/commandExecution/requestApproval" ||
            method == "item/fileChange/requestApproval" ||
            method == "item/permissions/requestApproval";
    }

    private static bool SupportsTypedResponseFor(string method)
    {
        return method.Contains("requestUserInput", StringComparison.OrdinalIgnoreCase) ||
            method.Contains("elicitation/request", StringComparison.OrdinalIgnoreCase);
    }

    private static SolidColorBrush AttentionBrush(string hex)
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

    private void OnPropertyChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed class AttentionResponseChoiceItem
{
    public string Label { get; set; } = "";

    public string Value { get; set; } = "";

    public static AttentionResponseChoiceItem FromChoice(RuntimeAttentionResponseChoice choice)
    {
        var value = choice.Value ?? "";
        var label = string.IsNullOrWhiteSpace(choice.Label) ? value : choice.Label;
        return new AttentionResponseChoiceItem
        {
            Label = label,
            Value = value
        };
    }

    public static AttentionResponseChoiceItem FromChoice(RuntimeAttentionResponseChoiceSnapshot choice)
    {
        var value = choice.Value ?? "";
        var label = string.IsNullOrWhiteSpace(choice.Label) ? value : choice.Label;
        return new AttentionResponseChoiceItem
        {
            Label = label,
            Value = value
        };
    }
}

public sealed class ThreadInboxItem
{
    public ThreadInboxItem()
    {
    }

    public ThreadInboxItem(
        string id,
        string title,
        string subtitle,
        string hostName,
        string statusText,
        string leadingGlyph,
        string leadingIconKind,
        bool leadingUsesThreadPairIcon,
        SolidColorBrush leadingBrush,
        SolidColorBrush statusBrush,
        SolidColorBrush statusBackgroundBrush,
        bool unread,
        bool archived,
        string threadKindLabel,
        string threadKindGlyph,
        SolidColorBrush threadKindBrush,
        string workflowLabel,
        string workflowIconKind,
        string workflowGlyph,
        SolidColorBrush workflowBrush,
        string liveStateIconKind,
        string liveStateGlyph,
        string liveStateText,
        string liveStateTitle,
        string liveStateDetail,
        SolidColorBrush liveStateBrush,
        string previewText,
        string activityLabel,
        int pendingRequestCount = 0,
        string? activeNodeId = null,
        bool canAddToCanvas = false)
    {
        Id = id;
        Title = title;
        Subtitle = subtitle;
        HostName = hostName;
        StatusText = statusText;
        LeadingGlyph = leadingGlyph;
        LeadingIconKind = leadingIconKind;
        LeadingUsesThreadPairIcon = leadingUsesThreadPairIcon;
        LeadingBrush = leadingBrush;
        StatusBrush = statusBrush;
        StatusBackgroundBrush = statusBackgroundBrush;
        Unread = unread;
        Archived = archived;
        ThreadKindLabel = threadKindLabel;
        ThreadKindGlyph = threadKindGlyph;
        ThreadKindBrush = threadKindBrush;
        WorkflowLabel = workflowLabel;
        WorkflowIconKind = workflowIconKind;
        WorkflowGlyph = workflowGlyph;
        WorkflowBrush = workflowBrush;
        LiveStateIconKind = liveStateIconKind;
        LiveStateGlyph = liveStateGlyph;
        LiveStateText = liveStateText;
        LiveStateTitle = liveStateTitle;
        LiveStateDetail = liveStateDetail;
        LiveStateBrush = liveStateBrush;
        PreviewText = previewText;
        ActivityLabel = activityLabel;
        PendingRequestCount = pendingRequestCount;
        ActiveNodeId = activeNodeId ?? "";
        CanAddToCanvas = canAddToCanvas;
    }

    public string Id { get; set; } = "";

    public string ActiveNodeId { get; set; } = "";

    private static ThreadInboxRowLayoutMetrics RowLayout => ThreadInboxRowLayout.Measure();

    public Thickness RowPadding => new(
        RowLayout.HorizontalPadding,
        RowLayout.VerticalPadding,
        RowLayout.HorizontalPadding,
        RowLayout.VerticalPadding);

    public CornerRadius RowCornerRadius => new(RowLayout.CornerRadius);

    public double RowSpacing => RowLayout.RowSpacing;

    public double TopRowIconTextSpacing => RowLayout.TopRowIconTextSpacing;

    public Thickness PendingRequestBadgePadding => new(
        RowLayout.PendingBadgeHorizontalPadding,
        RowLayout.PendingBadgeVerticalPadding,
        RowLayout.PendingBadgeHorizontalPadding,
        RowLayout.PendingBadgeVerticalPadding);

    public CornerRadius PendingRequestBadgeCornerRadius => new(RowLayout.PendingBadgeCornerRadius);

    public double PendingRequestBadgeFontSize => RowLayout.PendingBadgeFontSize;

    public SolidColorBrush PendingRequestBadgeForegroundBrush => BrushFromHex(RowLayout.PendingBadgeForegroundHex);

    public SolidColorBrush PendingRequestBadgeBackgroundBrush => BrushFromHex(RowLayout.PendingBadgeBackgroundHex);

    public Thickness StatusBadgePadding => new(
        RowLayout.StatusBadgeHorizontalPadding,
        RowLayout.StatusBadgeVerticalPadding,
        RowLayout.StatusBadgeHorizontalPadding,
        RowLayout.StatusBadgeVerticalPadding);

    public Thickness StatusBadgeLeadingMargin => new(RowLayout.StatusBadgeLeadingInset, 0, 0, 0);

    public CornerRadius StatusBadgeCornerRadius => new(RowLayout.StatusBadgeCornerRadius);

    public double StatusBadgeFontSize => RowLayout.StatusBadgeFontSize;

    public double ActionRowSpacing => RowLayout.ActionRowSpacing;

    public double ActivityTimestampFontSize => RowLayout.ActivityTimestampFontSize;

    public int ActivityTimestampMaxLines => RowLayout.ActivityTimestampMaxLines;

    public SolidColorBrush ActivityTimestampForegroundBrush =>
        BrushFromHex(RowLayout.ActivityTimestampForegroundHex);

    public string Title { get; set; } = "";

    public string Subtitle { get; set; } = "";

    public string HostName { get; set; } = "";

    public string StatusText { get; set; } = "";

    public string LeadingGlyph { get; set; } = "\uE8F2";

    public string LeadingIconKind { get; set; } = ThreadInboxPresentation.LeadingThreadPairIcon;

    public bool LeadingUsesThreadPairIcon { get; set; }

    public bool LeadingUsesCustomStatusIcon =>
        LeadingIconKind is ThreadInboxPresentation.LeadingRunningIcon
            or ThreadInboxPresentation.LeadingNeedsInputIcon
            or ThreadInboxPresentation.LeadingFailedIcon;

    public Visibility LeadingGlyphVisibility =>
        LeadingUsesThreadPairIcon || LeadingUsesCustomStatusIcon ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LeadingThreadPairIconVisibility => LeadingUsesThreadPairIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LeadingRunningIconVisibility =>
        LeadingIconKind == ThreadInboxPresentation.LeadingRunningIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LeadingNeedsInputIconVisibility =>
        LeadingIconKind == ThreadInboxPresentation.LeadingNeedsInputIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LeadingFailedIconVisibility =>
        LeadingIconKind == ThreadInboxPresentation.LeadingFailedIcon ? Visibility.Visible : Visibility.Collapsed;

    public SolidColorBrush LeadingBrush { get; set; } = new(Windows.UI.Color.FromArgb(255, 167, 176, 191));

    private static ThreadInboxRowLeadingPresentationSnapshot LeadingPairPresentation =>
        ThreadInboxRowLeadingPresentation.Resolve();

    public double LeadingThreadPairIconWidth => LeadingPairPresentation.IconWidth;

    public double LeadingThreadPairIconHeight => LeadingPairPresentation.IconHeight;

    public double LeadingThreadPairStrokeThickness => LeadingPairPresentation.StrokeThickness;

    public double LeadingThreadPairBackBubbleOpacity => LeadingPairPresentation.BackBubbleOpacity;

    public double LeadingStatusIconWidth => ThreadInboxPresentation.LeadingStatusIconWidth;

    public double LeadingStatusIconHeight => ThreadInboxPresentation.LeadingStatusIconHeight;

    public double LeadingStatusIconStrokeThickness => ThreadInboxPresentation.LeadingStatusIconStrokeThickness;

    public SolidColorBrush StatusBrush { get; set; } = new(Windows.UI.Color.FromArgb(255, 167, 176, 191));

    public SolidColorBrush StatusBackgroundBrush { get; set; } = new(Windows.UI.Color.FromArgb(18, 105, 117, 134));

    public bool Unread { get; set; }

    public Visibility UnreadVisibility => Unread ? Visibility.Visible : Visibility.Collapsed;

    public bool Archived { get; set; }

    public string ThreadKindLabel { get; set; } = "Thread";

    public string ThreadKindGlyph { get; set; } = "\uE8F2";

    public bool ThreadKindUsesBubbleIcon =>
        string.Equals(ThreadKindGlyph, ThreadHeaderIconPresentation.ThreadGlyph, StringComparison.Ordinal);

    public Visibility ThreadKindGlyphVisibility => ThreadKindUsesBubbleIcon ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ThreadKindBubbleIconVisibility => ThreadKindUsesBubbleIcon ? Visibility.Visible : Visibility.Collapsed;

    private static ThreadInboxRowKindPresentationSnapshot KindBubblePresentation =>
        ThreadInboxRowKindPresentation.Resolve();

    public double ThreadKindBubbleIconWidth => KindBubblePresentation.IconWidth;

    public double ThreadKindBubbleIconHeight => KindBubblePresentation.IconHeight;

    public double ThreadKindBubbleStrokeThickness => KindBubblePresentation.StrokeThickness;

    public SolidColorBrush ThreadKindBrush { get; set; } = new(Windows.UI.Color.FromArgb(255, 167, 176, 191));

    public string WorkflowLabel { get; set; } = "";

    public string WorkflowIconKind { get; set; } = ThreadInboxWorkflowMembershipPresentation.RectangleGroupIcon;

    public string WorkflowGlyph { get; set; } = "\uE8FD";

    public bool WorkflowUsesCustomIcon =>
        WorkflowIconKind is ThreadInboxWorkflowMembershipPresentation.RectangleGroupIcon
            or ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpIcon
            or ThreadInboxWorkflowMembershipPresentation.DashedRectangleIcon
            or ThreadInboxWorkflowMembershipPresentation.RectangleSwapIcon;

    public Visibility WorkflowGlyphVisibility => WorkflowUsesCustomIcon ? Visibility.Collapsed : Visibility.Visible;

    public Visibility WorkflowRectangleGroupIconVisibility =>
        WorkflowIconKind == ThreadInboxWorkflowMembershipPresentation.RectangleGroupIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility WorkflowSquareStackIconVisibility =>
        WorkflowIconKind == ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility WorkflowDashedRectangleIconVisibility =>
        WorkflowIconKind == ThreadInboxWorkflowMembershipPresentation.DashedRectangleIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility WorkflowRectangleSwapIconVisibility =>
        WorkflowIconKind == ThreadInboxWorkflowMembershipPresentation.RectangleSwapIcon ? Visibility.Visible : Visibility.Collapsed;

    private ThreadInboxWorkflowMembershipPresentationSnapshot WorkflowIconPresentation =>
        ThreadInboxWorkflowMembershipPresentation.Resolve(
            WorkflowIconKind == ThreadInboxWorkflowMembershipPresentation.RectangleGroupIcon,
            WorkflowIconKind switch
            {
                ThreadInboxWorkflowMembershipPresentation.DashedRectangleIcon => 0,
                ThreadInboxWorkflowMembershipPresentation.RectangleSwapIcon => 1,
                ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpIcon => 2,
                _ => 1
            });

    public double WorkflowIconWidth => WorkflowIconPresentation.IconWidth;

    public double WorkflowIconHeight => WorkflowIconPresentation.IconHeight;

    public double WorkflowIconStrokeThickness => WorkflowIconPresentation.StrokeThickness;

    public double WorkflowIconSecondaryOpacity => WorkflowIconPresentation.SecondaryOpacity;

    public SolidColorBrush WorkflowBrush { get; set; } = new(Windows.UI.Color.FromArgb(255, 53, 111, 203));

    public string LiveStateIconKind { get; set; } = ThreadLiveStatePresentation.ClockIcon;

    public string LiveStateGlyph { get; set; } = "\uE823";

    public bool LiveStateUsesCustomIcon =>
        LiveStateIconKind is ThreadLiveStatePresentation.ClockIcon
            or ThreadLiveStatePresentation.ArrowTriangleCirclePathIcon
            or ThreadLiveStatePresentation.HandRaisedIcon
            or ThreadLiveStatePresentation.CheckmarkCircleIcon
            or ThreadLiveStatePresentation.XmarkOctagonIcon;

    public Visibility LiveStateGlyphVisibility => LiveStateUsesCustomIcon ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LiveStateClockIconVisibility =>
        LiveStateIconKind == ThreadLiveStatePresentation.ClockIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LiveStateRunningIconVisibility =>
        LiveStateIconKind == ThreadLiveStatePresentation.ArrowTriangleCirclePathIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LiveStateWaitingIconVisibility =>
        LiveStateIconKind == ThreadLiveStatePresentation.HandRaisedIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LiveStateFinishedIconVisibility =>
        LiveStateIconKind == ThreadLiveStatePresentation.CheckmarkCircleIcon ? Visibility.Visible : Visibility.Collapsed;

    public Visibility LiveStateFailedIconVisibility =>
        LiveStateIconKind == ThreadLiveStatePresentation.XmarkOctagonIcon ? Visibility.Visible : Visibility.Collapsed;

    public double LiveStateIconWidth => ThreadLiveStatePresentation.IconWidth;

    public double LiveStateIconHeight => ThreadLiveStatePresentation.IconHeight;

    public double LiveStateIconStrokeThickness => ThreadLiveStatePresentation.StrokeThickness;

    public string LiveStateText { get; set; } = "Idle";

    public string LiveStateTitle { get; set; } = "Idle";

    public string LiveStateDetail { get; set; } = "";

    public string LiveStateDetailText => string.IsNullOrWhiteSpace(LiveStateDetail)
        ? ""
        : $"\u00B7 {LiveStateDetail}";

    public Visibility LiveStateDetailVisibility => string.IsNullOrWhiteSpace(LiveStateDetail)
        ? Visibility.Collapsed
        : Visibility.Visible;

    public SolidColorBrush LiveStateBrush { get; set; } =
        BrushFromHex(ThreadLiveStatePresentation.SecondaryHex);

    public string PreviewText { get; set; } = "";

    public Visibility PreviewVisibility => string.IsNullOrWhiteSpace(PreviewText)
        ? Visibility.Collapsed
        : Visibility.Visible;

    public string ActivityLabel { get; set; } = "";

    public int PendingRequestCount { get; set; }

    public Visibility PendingRequestVisibility => PendingRequestCount > 0 ? Visibility.Visible : Visibility.Collapsed;

    public bool CanAddToCanvas { get; set; }

    public Visibility AddToCanvasVisibility => CanAddToCanvas ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ThreadActionVisibility => Visibility.Visible;

    public ThreadInboxRowActionPresentationSnapshot ActionPresentation =>
        ThreadInboxRowActionPresentation.Resolve(Unread, Archived, Title);

    public string AddToCanvasToolTip => ActionPresentation.AddToCanvasToolTip;

    public string AddToCanvasAccessibilityLabel => ActionPresentation.AddToCanvasAccessibilityLabel;

    public double ActionButtonSize => ActionPresentation.ActionButtonSize;

    public SolidColorBrush ActionIconBrush => BrushFromHex(ActionPresentation.ActionIconHex);

    public double AddToCanvasStrokeThickness => ActionPresentation.AddToCanvasStrokeThickness;

    public double AddToCanvasBackLayerOpacity => ActionPresentation.AddToCanvasBackLayerOpacity;

    public double MarkReadStrokeThickness => ActionPresentation.MarkReadStrokeThickness;

    public double MarkReadBadgeSize => ActionPresentation.MarkReadBadgeSize;

    public double ArchiveStrokeThickness => ActionPresentation.ArchiveStrokeThickness;

    public string MarkReadLabel => ActionPresentation.MarkReadLabel;

    public string MarkReadAccessibilityLabel => ActionPresentation.MarkReadAccessibilityLabel;

    public Visibility MarkReadEnvelopeOpenVisibility =>
        ActionPresentation.MarkReadIconKind == ThreadInboxRowActionPresentation.EnvelopeOpenIcon
            ? Visibility.Visible
            : Visibility.Collapsed;

    public Visibility MarkReadEnvelopeBadgeVisibility =>
        ActionPresentation.MarkReadIconKind == ThreadInboxRowActionPresentation.EnvelopeBadgeIcon
            ? Visibility.Visible
            : Visibility.Collapsed;

    public string ArchiveLabel => ActionPresentation.ArchiveLabel;

    public string ArchiveAccessibilityLabel => ActionPresentation.ArchiveAccessibilityLabel;

    public Visibility ArchiveActionVisibility =>
        ActionPresentation.ShowsArchiveAction ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ArchiveBoxIconVisibility =>
        ActionPresentation.ArchiveIconKind == ThreadInboxRowActionPresentation.ArchiveBoxIcon
            ? Visibility.Visible
            : Visibility.Collapsed;

    private static SolidColorBrush BrushFromHex(string hex)
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
}
