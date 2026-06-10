using System.Text.Json;
using MapofAgents.Core;

namespace MapofAgents.WindowsApp;

internal static class GraphWebRenderer
{
    public static string Render(
        AgentGraph graph,
        bool showsSubagents = true,
        IReadOnlyCollection<string>? browsableMachineIds = null,
        IReadOnlyList<CanvasEdge>? semanticEdges = null)
    {
        var graphJson = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        var showsSubagentsJson = JsonSerializer.Serialize(showsSubagents, MapofAgentsJson.Options);
        var browsableMachineIdsJson = JsonSerializer.Serialize(
            browsableMachineIds ?? Array.Empty<string>(),
            MapofAgentsJson.Options);
        var semanticEdgesJson = JsonSerializer.Serialize(
            semanticEdges ?? SemanticEdgeResolver.ResolveEdges(graph),
            MapofAgentsJson.Options);
        var statusPresentationsJson = JsonSerializer.Serialize(
            GraphNodeStatusPresentation.WebPresentationMap(),
            MapofAgentsJson.Options);
        var iconPresentationsJson = JsonSerializer.Serialize(
            NodeIconPresentation.WebPresentationMap(),
            MapofAgentsJson.Options);
        var threadUpdatedFormattingJson = JsonSerializer.Serialize(
            ThreadNodeUpdatedPresentation.WebFormatterConfig(),
            MapofAgentsJson.Options);
        var edgeControlStylesJson = JsonSerializer.Serialize(
            CanvasEdgePresentation.WebControlStyleMap(),
            MapofAgentsJson.Options);
        var edgeControlPolicyJson = JsonSerializer.Serialize(
            CanvasEdgePresentation.WebControlPolicy(),
            MapofAgentsJson.Options);
        var edgeControlLayout = CanvasEdgePresentation.WebControlLayout();
        var edgeArrowTreatmentJson = JsonSerializer.Serialize(
            CanvasEdgePresentation.WebArrowTreatment(),
            MapofAgentsJson.Options);
        var edgeVisualTreatmentJson = JsonSerializer.Serialize(
            CanvasEdgePresentation.WebVisualTreatment(),
            MapofAgentsJson.Options);
        var folderActionPresentationJson = JsonSerializer.Serialize(
            GraphNodeActionPresentation.FolderActionWebConfig(),
            MapofAgentsJson.Options);
        var linkActionPresentationJson = JsonSerializer.Serialize(
            GraphNodeLinkActionPresentation.WebConfig(),
            MapofAgentsJson.Options);
        var nodeCardPresentation = GraphNodeCardPresentation.Resolve();
        var nodeCardMaterial = GraphNodeCardPresentation.WebMaterial();
        return $$"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root {
  color-scheme: dark;
  --canvas-bg: {{nodeCardMaterial.CanvasBackgroundHex}};
  --text: {{nodeCardMaterial.PrimaryTextHex}};
  --muted: {{nodeCardMaterial.SecondaryTextHex}};
  --tertiary: {{nodeCardMaterial.TertiaryTextHex}};
  --surface: {{nodeCardMaterial.SurfaceCss}};
  --surface-strong: {{nodeCardMaterial.StrongSurfaceCss}};
  --stroke: {{nodeCardMaterial.StrokeCss}};
  --stroke-soft: {{nodeCardMaterial.SoftStrokeCss}};
  --shadow: {{nodeCardMaterial.DefaultShadowCss}};
  --node-updated-color: {{ThreadNodeUpdatedPresentation.TextForegroundHex}};
  --node-updated-font-size: {{ThreadNodeUpdatedPresentation.TextFontSize}}px;
  --node-updated-line-height: {{ThreadNodeUpdatedPresentation.TextLineHeight}}px;
  --node-pill-font-size: {{nodeCardPresentation.PillFontSize}}px;
  --node-pill-line-height: {{nodeCardPresentation.PillLineHeight}}px;
  --node-pill-icon-font-size: {{nodeCardPresentation.PillIconFontSize}}px;
  --node-pill-svg-icon-size: {{nodeCardPresentation.PillSvgIconSize}}px;
  --selected: #0a84ff;
  --machine: #30d158;
  --folder: #ffd60a;
  --thread: #0a84ff;
  --agent: #bf5af2;
}

* {
  box-sizing: border-box;
}

html,
body {
  width: 100%;
  height: 100%;
  margin: 0;
  overflow: hidden;
  font-family: "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
  background: var(--canvas-bg);
  user-select: none;
  overscroll-behavior: none;
  scrollbar-width: none;
}

::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}

#stage {
  position: fixed;
  inset: 0;
  cursor: grab;
  overflow: hidden;
  background: var(--canvas-bg);
}

#stage.dragging {
  cursor: grabbing;
}

#stage.linking {
  cursor: crosshair;
}

#edges {
  position: absolute;
  inset: 0;
}

#world {
  position: absolute;
  inset: 0;
  transform-origin: 0 0;
  will-change: transform;
}

.node {
  position: absolute;
  height: var(--node-height);
  border-radius: {{nodeCardPresentation.SurfaceCornerRadius}}px;
  border: {{nodeCardPresentation.BorderWidth}}px solid var(--node-border);
  background: var(--surface);
  box-shadow: 0 {{nodeCardPresentation.ShadowYOffset}}px {{nodeCardPresentation.DefaultShadowRadius}}px var(--shadow);
  backdrop-filter: blur(18px) saturate(1.10);
  color: var(--text);
  overflow: hidden;
  transition: border-color 120ms ease, box-shadow 120ms ease, opacity 120ms ease;
}

.node::before,
.node::after {
  content: "";
  position: absolute;
  pointer-events: none;
}

.node::before {
  inset: 0;
  border-radius: {{nodeCardPresentation.SurfaceCornerRadius}}px;
  border: {{nodeCardPresentation.SelectedBorderWidth}}px solid rgba(10, 132, 255, 0);
  transition: border-color 120ms ease;
}

.node::after {
  inset: {{nodeCardPresentation.HighlightInset}}px;
  border-radius: {{nodeCardPresentation.HighlightCornerRadius}}px;
  border: {{nodeCardPresentation.HighlightBorderWidth}}px solid rgba(10, 132, 255, 0);
  box-shadow: 0 0 0 rgba(10, 132, 255, 0);
  transition: border-color 120ms ease, box-shadow 120ms ease;
}

.node.dimmed {
  opacity: 0.36;
}

.node.highlighted {
  overflow: visible;
}

.node:hover {
  box-shadow: 0 {{nodeCardPresentation.ShadowYOffset}}px {{nodeCardPresentation.HoverShadowRadius}}px rgba(0, 0, 0, 0.10);
}

.node.highlighted::after {
  border-color: rgba(10, 132, 255, 0.85);
  box-shadow: 0 0 {{nodeCardPresentation.HighlightShadowRadius}}px rgba(10, 132, 255, 0.40);
}

.node.selected {
  border-color: rgba(10, 132, 255, 0);
  --node-selected-stroke: var(--selected);
  box-shadow: 0 {{nodeCardPresentation.ShadowYOffset}}px {{nodeCardPresentation.EmphasisShadowRadius}}px rgba(0, 0, 0, 0.18);
}

.node.selected::before {
  border-color: var(--node-selected-stroke);
}

.node.link-source {
  border-color: rgba(48, 209, 88, 0);
  --node-selected-stroke: #30d158;
  box-shadow: 0 0 0 3px rgba(48, 209, 88, 0.14), 0 {{nodeCardPresentation.ShadowYOffset}}px {{nodeCardPresentation.EmphasisShadowRadius}}px rgba(0, 0, 0, 0.18);
}

.node.link-source::before {
  border-color: var(--node-selected-stroke);
}

.node.link-targetable:not(.link-source):hover {
  border-color: #38bdf8;
  box-shadow: 0 0 0 3px rgba(56, 189, 248, 0.14), 0 {{nodeCardPresentation.ShadowYOffset}}px {{nodeCardPresentation.EmphasisShadowRadius}}px rgba(0, 0, 0, 0.18);
}

.node-inner {
  display: grid;
  grid-template-rows: auto 1fr auto;
  gap: {{nodeCardPresentation.InnerGap}}px;
  height: 100%;
  padding: {{nodeCardPresentation.InnerPadding}}px;
}

.node-heading {
  display: flex;
  gap: {{nodeCardPresentation.HeadingGap}}px;
  align-items: flex-start;
  min-width: 0;
}

.node-icon {
  display: grid;
  place-items: center;
  width: {{nodeCardPresentation.IconSize}}px;
  height: {{nodeCardPresentation.IconSize}}px;
  flex: 0 0 {{nodeCardPresentation.IconSize}}px;
  border-radius: {{nodeCardPresentation.IconCornerRadius}}px;
  color: var(--accent);
  background: var(--accent-soft);
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  font-size: {{nodeCardPresentation.IconFontSize}}px;
  line-height: 1;
}

.thread-pair-icon {
  position: relative;
  display: block;
  width: 18px;
  height: 16px;
}

.thread-pair-icon::before,
.thread-pair-icon::after {
  content: "";
  position: absolute;
  border: 1.7px solid currentColor;
  border-radius: 6px;
}

.thread-pair-icon::before {
  left: 0;
  top: 5px;
  width: 10px;
  height: 7px;
}

.thread-pair-icon::after {
  left: 6px;
  top: 2px;
  width: 11px;
  height: 8px;
}

.node-copy {
  flex: 1 1 auto;
  min-width: 0;
}

.node-actions {
  display: flex;
  align-items: center;
  gap: {{nodeCardPresentation.ActionGap}}px;
  margin-left: auto;
  flex: 0 0 auto;
}

.node-action {
  display: grid;
  place-items: center;
  width: 18px;
  height: 18px;
  padding: 0;
  border: 0;
  border-radius: 0;
  color: #a7b0bf;
  background: transparent;
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  font-size: 12px;
  line-height: 1;
  cursor: pointer;
  opacity: var(--node-action-opacity, 1);
}

.node-action:hover {
  color: var(--accent);
  background: transparent;
}

.node-action.unavailable {
  opacity: var(--node-action-opacity, 0.48);
}

.node-action.unavailable:hover {
  color: #a7b0bf;
  background: transparent;
}

.node-action.link-active {
  color: var(--node-link-active-color, #30d158);
  border: var(--node-link-active-border-width, 1.3px) solid currentColor;
  border-radius: var(--node-link-active-border-radius, 999px);
  background: transparent;
}

.node-link-icon {
  display: inline-grid;
  place-items: center;
  width: 18px;
  height: 18px;
  line-height: 1;
}

.fluent-link-icon {
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  font-size: 12px;
}

.dotted-connection-icon svg {
  display: block;
  width: 16px;
  height: 16px;
  overflow: visible;
}

.dotted-connection-icon .triangle-path {
  fill: none;
  stroke: currentColor;
  stroke-width: 1.35px;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-dasharray: 1.25 2.1;
}

.dotted-connection-icon .triangle-point {
  fill: currentColor;
}

.folder-add-icon {
  position: relative;
  display: grid;
  place-items: center;
  width: 14px;
  height: 14px;
}

.folder-add-icon .folder-base {
  font-size: 12px;
}

.folder-add-icon .folder-plus {
  position: absolute;
  right: -4px;
  bottom: -3px;
  display: grid;
  place-items: center;
  width: 10px;
  height: 10px;
  border-radius: 999px;
  background: #a7b0bf;
  font-family: "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
  font-size: 8px;
  font-weight: 800;
  line-height: 1;
}

.folder-add-icon .folder-plus::before {
  content: "+";
  color: #18191b;
}

.node-action:hover .folder-add-icon .folder-plus {
  background: var(--accent);
}

.node-action.unavailable:hover .folder-add-icon .folder-plus {
  background: #a7b0bf;
}

.node-action:disabled {
  color: rgba(167, 176, 191, 0.42);
  cursor: default;
}

	.node-action:disabled:hover {
	  color: rgba(167, 176, 191, 0.42);
	  background: transparent;
	}

	.node-context-menu {
	  position: fixed;
	  z-index: 20;
	  display: none;
	  min-width: 218px;
	  padding: 6px;
	  border: 1px solid rgba(255, 255, 255, 0.16);
	  border-radius: 8px;
	  background: rgba(35, 36, 40, 0.96);
	  color: var(--text);
	  box-shadow: 0 18px 46px rgba(0, 0, 0, 0.38);
	  backdrop-filter: blur(22px) saturate(1.12);
	}

	.context-menu-item {
	  display: grid;
	  grid-template-columns: 20px minmax(0, 1fr);
	  align-items: center;
	  gap: 8px;
	  width: 100%;
	  min-height: 30px;
	  padding: 5px 8px;
	  border: 0;
	  border-radius: 6px;
	  background: transparent;
	  color: var(--text);
	  font: 12.5px "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
	  text-align: left;
	  cursor: pointer;
	}

	.context-menu-item:hover {
	  background: rgba(255, 255, 255, 0.08);
	}

	.context-menu-item:disabled {
	  color: rgba(167, 176, 191, 0.46);
	  cursor: default;
	}

	.context-menu-item:disabled:hover {
	  background: transparent;
	}

	.context-menu-icon {
	  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
	  font-size: 13px;
	  color: var(--muted);
	  text-align: center;
	}

	.context-menu-icon .node-link-icon {
	  width: 16px;
	  height: 16px;
	  margin: 0 auto;
	}

	.context-menu-item.destructive,
	.context-menu-item.destructive .context-menu-icon {
	  color: #f97066;
	}

	.context-menu-separator {
	  height: 1px;
	  margin: 5px 4px;
	  background: rgba(255, 255, 255, 0.12);
	}

		.node-title-row {
		  display: flex;
	  align-items: center;
	  gap: {{nodeCardPresentation.TitleRowGap}}px;
	  min-width: 0;
	}

	.node-title {
	  min-width: 0;
	  font-size: {{nodeCardPresentation.TitleFontSize}}px;
  line-height: 1.22;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

	.agent-badge {
	  flex: 0 0 auto;
	  height: {{nodeCardPresentation.AgentBadgeHeight}}px;
	  padding: 1px {{nodeCardPresentation.AgentBadgeHorizontalPadding}}px;
  border-radius: 999px;
  color: var(--agent);
  background: rgba(191, 90, 242, 0.12);
	  font-size: {{nodeCardPresentation.AgentBadgeFontSize}}px;
  font-weight: 700;
  line-height: 16px;
}

	.unread-dot {
	  width: {{nodeCardPresentation.UnreadDotSize}}px;
	  height: {{nodeCardPresentation.UnreadDotSize}}px;
	  flex: 0 0 {{nodeCardPresentation.UnreadDotSize}}px;
  border-radius: 50%;
  background: #0a84ff;
}

	.node-subtitle {
	  margin-top: {{nodeCardPresentation.SubtitleTopMargin}}px;
	  color: var(--muted);
	  font-size: {{nodeCardPresentation.SubtitleFontSize}}px;
  line-height: 1.25;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  overflow-wrap: normal;
  word-break: normal;
}

.node.compact .node-subtitle {
  display: block;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.node-footer {
  display: flex;
  align-items: center;
  gap: {{nodeCardPresentation.FooterGap}}px;
  min-height: {{nodeCardPresentation.FooterMinHeight}}px;
  min-width: 0;
}

.node-updated {
  min-width: 0;
  color: var(--node-updated-color);
  font-size: var(--node-updated-font-size);
  line-height: var(--node-updated-line-height);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pill {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  flex: 0 0 auto;
  min-width: 0;
  max-width: 100%;
  height: {{nodeCardPresentation.PillHeight}}px;
  padding: 0 {{nodeCardPresentation.PillHorizontalPadding}}px;
  border-radius: 999px;
  color: var(--accent);
  background: var(--accent-soft);
  border: 0;
  font-size: var(--node-pill-font-size);
  line-height: var(--node-pill-line-height);
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pill-icon {
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  font-size: var(--node-pill-icon-font-size);
  line-height: 1;
}

.pill-svg-icon {
  display: inline-block;
  width: var(--node-pill-svg-icon-size);
  height: var(--node-pill-svg-icon-size);
  font-family: inherit;
  font-size: 0;
  flex: 0 0 auto;
}

.pill-svg-icon svg {
  display: block;
  width: 100%;
  height: 100%;
  overflow: visible;
}

.meta-pill {
  flex: 0 0 auto;
  font-weight: 500;
}

.spacer {
  flex: 1 1 auto;
  min-width: 0;
}

.tiny {
  color: #a7b0bf;
  background: rgba(167, 176, 191, 0.12);
  border-color: rgba(167, 176, 191, 0.18);
}

.status-blue {
  color: #0a84ff;
  background: rgba(10, 132, 255, 0.10);
  border-color: rgba(10, 132, 255, 0.18);
}

.status-green {
  color: #30d158;
  background: rgba(48, 209, 88, 0.10);
  border-color: rgba(48, 209, 88, 0.18);
}

.status-orange {
  color: #b45309;
  background: rgba(180, 83, 9, 0.10);
  border-color: rgba(180, 83, 9, 0.18);
}

.status-red {
  color: #c2410c;
  background: rgba(194, 65, 12, 0.10);
  border-color: rgba(194, 65, 12, 0.18);
}

.status-pill {
  color: var(--status-color);
  background: var(--status-bg);
  border-color: var(--status-border);
}

#edgeControls {
  position: absolute;
  inset: 0;
  pointer-events: none;
}

.edge-control {
  position: absolute;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: {{edgeControlLayout.Gap}}px;
  min-width: {{edgeControlLayout.MinWidth}}px;
  min-height: {{edgeControlLayout.MinHeight}}px;
  padding: {{edgeControlLayout.VerticalPadding}}px {{edgeControlLayout.HorizontalPadding}}px;
  border: {{edgeControlLayout.BorderWidth}}px solid var(--edge-stroke);
  border-radius: 999px;
  color: #ffffff;
  background: rgba(0, 0, 0, {{edgeControlLayout.BackgroundOpacity}});
  box-shadow: 0 {{edgeControlLayout.ShadowYOffset}}px {{edgeControlLayout.ShadowRadius}}px rgba(0, 0, 0, {{edgeControlLayout.ShadowOpacity}});
  font-family: "Segoe UI Variable", "Segoe UI", system-ui, sans-serif;
  font-size: {{edgeControlLayout.LabelFontSize}}px;
  font-weight: {{edgeControlLayout.LabelFontWeight}};
  line-height: {{edgeControlLayout.LabelLineHeight}}px;
  white-space: nowrap;
  cursor: pointer;
  pointer-events: auto;
  transform: translate(-50%, -50%);
}

.edge-control:hover {
  background: rgba(0, 0, 0, {{edgeControlLayout.HoverBackgroundOpacity}});
  border-color: var(--edge-tint);
}

.edge-control.selected {
  background: var(--edge-selected-bg);
  border-color: var(--edge-tint);
}

.edge-control-icon {
  color: var(--edge-tint);
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  font-size: {{edgeControlLayout.IconFontSize}}px;
  font-weight: {{edgeControlLayout.IconFontWeight}};
  line-height: 1;
}

.edge-control.selected .edge-control-icon {
  color: #ffffff;
}

.edge-thread-pair-icon {
  position: relative;
  display: block;
  width: {{edgeControlLayout.ThreadPairIconWidth}}px;
  height: {{edgeControlLayout.ThreadPairIconHeight}}px;
  color: currentColor;
}

.edge-thread-pair-icon::before,
.edge-thread-pair-icon::after {
  content: "";
  position: absolute;
  border: 1.35px solid currentColor;
  border-radius: 5px;
}

.edge-thread-pair-icon::before {
  left: 0;
  top: 4px;
  width: 7px;
  height: 5px;
}

.edge-thread-pair-icon::after {
  left: 5px;
  top: 1px;
  width: 8px;
  height: 6px;
}

#linkHint {
  position: fixed;
  left: 50%;
  bottom: 18px;
  transform: translateX(-50%);
  display: none;
  align-items: center;
  gap: 8px;
  max-width: min(520px, calc(100vw - 64px));
  padding: 9px 12px;
  border-radius: 8px;
  border: 1px solid rgba(48, 209, 88, 0.34);
  color: #d8f7e5;
  background: rgba(21, 76, 39, 0.88);
  box-shadow: 0 12px 30px rgba(0, 0, 0, 0.38);
  font-size: 12px;
  font-weight: 650;
  pointer-events: none;
}

#linkHint.visible {
  display: flex;
}

.hint-icon {
  font-family: "Segoe Fluent Icons", "Segoe MDL2 Assets";
  color: #30d158;
}

.hint-icon .node-link-icon {
  width: 16px;
  height: 16px;
}
</style>
</head>
<body>
<main id="stage" aria-label="MapofAgents graph">
  <canvas id="edges"></canvas>
  <section id="world"></section>
</main>
<div id="linkHint"><span class="hint-icon"><span class="node-link-icon dotted-connection-icon" aria-hidden="true"><svg viewBox="0 0 18 18" focusable="false"><path class="triangle-path" d="M3.3 12.2 L9 3.2 L14.7 12.2 Z" /><circle class="triangle-point" cx="3.3" cy="12.2" r="1.45" /><circle class="triangle-point" cx="9" cy="3.2" r="1.45" /><circle class="triangle-point" cx="14.7" cy="12.2" r="1.45" /></svg></span></span><span>Click a target node to create a note line. Click empty canvas to cancel.</span></div>
<script>
let graph = {{graphJson}};
let semanticEdges = {{semanticEdgesJson}};
const stage = document.getElementById("stage");
const canvas = document.getElementById("edges");
const world = document.getElementById("world");
const linkHint = document.getElementById("linkHint");
const ctx = canvas.getContext("2d");
let nodes = [];
let edges = [];
let editableEdges = [];
let nodeById = new Map();
let edgeVisualOffsets = new Map();
let selectedNodeId = null;
let selectedEdgeId = null;
let pendingLinkSourceId = null;
let highlightedNodeId = null;
let view = {
  x: graph.viewport?.offset?.x ?? 0,
  y: graph.viewport?.offset?.y ?? 0,
  scale: graph.viewport?.scale ?? 1
};
	let stageDrag = null;
	let nodeDrag = null;
	let showsSubagents = {{showsSubagentsJson}};
	let browsableMachineIds = new Set({{browsableMachineIdsJson}});
	const statusPresentations = {{statusPresentationsJson}};
		const iconPresentations = {{iconPresentationsJson}};
			const threadUpdatedFormatting = {{threadUpdatedFormattingJson}};
			const edgeControlStyles = {{edgeControlStylesJson}};
			const edgeControlPolicy = {{edgeControlPolicyJson}};
			const edgeArrowTreatment = {{edgeArrowTreatmentJson}};
			const edgeVisualTreatment = {{edgeVisualTreatmentJson}};
			const folderActionPresentation = {{folderActionPresentationJson}};
			const linkActionPresentation = {{linkActionPresentationJson}};
			document.documentElement.style.setProperty("--node-link-active-color", linkActionPresentation.activeHex || "#30D158");
			document.documentElement.style.setProperty("--node-link-active-border-width", `${linkActionPresentation.activeBorderWidth || 1.3}px`);
			document.documentElement.style.setProperty("--node-link-active-border-radius", `${linkActionPresentation.activeBorderRadius || 999}px`);
			const nodeFooterSpacerBeforeMetadata = {{(nodeCardPresentation.FooterSpacerBeforeMetadata ? "true" : "false")}};
			let threadUpdatedRelativeFormatter = null;
	let contextMenuNodeId = null;
	const contextMenu = document.createElement("div");
	contextMenu.className = "node-context-menu";
	document.body.appendChild(contextMenu);

const colors = {
  machine: "#30d158",
  folder: "#ffd60a",
  codexThread: "#0a84ff",
  agent: "#bf5af2",
  unknown: "#68758a"
};

function manualEdgesFromGraph(sourceGraph) {
  return Object.values(sourceGraph?.manualEdges || {});
}

function isEditableEdge(edge) {
  return Boolean(edge?.isManual) ||
    edge?.kind === "manualNote" ||
    edge?.kind === "threadMessage" ||
    edge?.kind === "createdBy";
}

function setGraphData(nextGraph, nextSemanticEdges = semanticEdges) {
  graph = nextGraph || { nodes: {}, manualEdges: {} };
  semanticEdges = Array.isArray(nextSemanticEdges) ? nextSemanticEdges : [];
  const manualEdges = manualEdgesFromGraph(graph);
  nodes = Object.values(graph.nodes || {}).sort((a, b) => (a.zIndex || 0) - (b.zIndex || 0));
  edges = semanticEdges.concat(manualEdges);
  editableEdges = edgeControlPolicy?.showsControlsForAllStoredGraphEdges
    ? manualEdges
    : manualEdges.filter(isEditableEdge);
  nodeById = new Map(nodes.map(node => [node.id, node]));
  edgeVisualOffsets = parallelWorkflowEdgeOffsets(edges);
}

setGraphData(graph, semanticEdges);

function escapeText(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function isSubagent(node) {
  if (node.kind !== "codexThread") {
    return false;
  }

  if (String(node.metadata?.threadKind ?? "").toLowerCase() === "subagent") {
    return true;
  }

  const label = `${node.metadata?.threadRef?.name ?? ""} ${node.title ?? ""}`.toLowerCase();
  return label.includes("agent");
}

function isVisibleNode(node) {
  return Boolean(node) && (showsSubagents || !isSubagent(node));
}

function isVisibleEdge(edge) {
  if (!edge) {
    return false;
  }

  return isVisibleNode(nodeById.get(edge.source)) && isVisibleNode(nodeById.get(edge.target));
}

function accentFor(node) {
  if (isSubagent(node)) {
    return colors.agent;
  }

  return colors[node.kind] || colors.unknown;
}

function nodeBorderOpacityFor(node) {
  if (node.kind === "machine") {
    return 0.72;
  }

  if (node.kind === "folder") {
    return 0.82;
  }

  if (node.kind === "codexThread") {
    return 0.78;
  }

  return 0.72;
}

function alphaHex(hex, alpha) {
  const clean = hex.replace("#", "");
  const r = parseInt(clean.slice(0, 2), 16);
  const g = parseInt(clean.slice(2, 4), 16);
  const b = parseInt(clean.slice(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function statusFor(node) {
  return node.metadata?.hostStatus || node.metadata?.runStatus || node.metadata?.platform || node.kind;
}

function iconFor(node) {
  const key = isSubagent(node) ? "subagent" : node.kind;
  const presentation = iconPresentations[key] || iconPresentations.unknown;
  if (presentation?.usesThreadPairIcon) {
    return "<span class=\"thread-pair-icon\" aria-hidden=\"true\"></span>";
  }

  return escapeText(presentation?.glyph || "\uE8A5");
}

function machineStatusLabel(status) {
  switch (status) {
    case "connected":
      return "connected";
    case "connecting":
      return "connecting";
    case "unavailable":
      return "runtime failed";
    case "disconnected":
      return "offline";
    default:
      return status || "offline";
  }
}

function fallbackStatusPresentation() {
  return {
    label: "unknown",
    glyph: "\uEA3A",
    showsGlyph: true,
    foregroundHex: "#A7B0BF",
    backgroundCss: "rgba(167, 176, 191, 0.10)",
    borderCss: "rgba(167, 176, 191, 0.18)"
  };
}

function statusMeta(node) {
  if (node.kind === "machine") {
    const status = node.metadata?.hostStatus || "disconnected";
    return statusPresentations.machine?.[status] ||
      statusPresentations.machine?.disconnected ||
      fallbackStatusPresentation();
  }

  if (node.kind === "folder") {
    return statusPresentations.folder?.folder ||
      fallbackStatusPresentation();
  }

  if (node.metadata?.isUnread) {
    return statusPresentations.thread?.unread ||
      fallbackStatusPresentation();
  }

  const status = node.metadata?.runStatus || "unknown";
  return statusPresentations.thread?.[status] ||
    statusPresentations.thread?.unknown ||
    fallbackStatusPresentation();
}

	function statusPillHtml(node) {
	  const meta = statusMeta(node);
	  const icon = statusPillIconHtml(meta);
	  const style = `--status-color:${meta.foregroundHex}; --status-bg:${meta.backgroundCss}; --status-border:${meta.borderCss};`;
	  return `<span class="pill status-pill" style="${style}">${icon}${escapeText(meta.label)}</span>`;
	}

	function statusPillIconHtml(meta) {
	  if (!meta?.showsGlyph) {
	    return "";
	  }

	  const svg = statusPillSvgIcon(meta.iconKind);
	  if (svg) {
	    return `<span class="pill-icon pill-svg-icon" aria-hidden="true">${svg}</span>`;
	  }

	  return `<span class="pill-icon" aria-hidden="true">${escapeText(meta.glyph)}</span>`;
	}

	function statusPillSvgIcon(iconKind) {
	  switch (iconKind) {
	    case "circleFill":
	      return `<svg viewBox="0 0 14 14" focusable="false"><circle cx="7" cy="7" r="3.7" fill="currentColor"></circle></svg>`;
	    case "circle":
	      return `<svg viewBox="0 0 14 14" focusable="false"><circle cx="7" cy="7" r="4.6" fill="none" stroke="currentColor" stroke-width="1.35"></circle></svg>`;
	    case "checkmarkCircle":
	      return `<svg viewBox="0 0 14 14" focusable="false"><circle cx="7" cy="7" r="5.1" fill="none" stroke="currentColor" stroke-width="1.25"></circle><path d="M4.5 7.1 L6.2 8.8 L9.8 5" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"></path></svg>`;
	    case "xmarkOctagon":
	      return `<svg viewBox="0 0 14 14" focusable="false"><path d="M5 1.6 L9 1.6 L12.4 5 L12.4 9 L9 12.4 L5 12.4 L1.6 9 L1.6 5 Z" fill="none" stroke="currentColor" stroke-width="1.18" stroke-linejoin="round"></path><path d="M5.1 5.1 L8.9 8.9 M8.9 5.1 L5.1 8.9" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round"></path></svg>`;
	    case "exclamationBubble":
	      return `<svg viewBox="0 0 14 14" focusable="false"><path d="M7 1.7 C10.1 1.7 12.2 3.6 12.2 6.2 C12.2 8.8 10.1 10.7 7 10.7 C6.5 10.7 6 10.6 5.5 10.5 L2.9 12.3 L3.3 9.6 C2.3 8.8 1.8 7.6 1.8 6.2 C1.8 3.6 3.9 1.7 7 1.7 Z" fill="none" stroke="currentColor" stroke-width="1.18" stroke-linejoin="round"></path><path d="M7 3.8 L7 6.7" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round"></path><circle cx="7" cy="8.4" r="0.65" fill="currentColor"></circle></svg>`;
	    case "arrowTriangle2CirclePath":
	      return `<svg viewBox="0 0 14 14" focusable="false"><path d="M10.6 4.2 C9.8 3.2 8.5 2.5 7 2.5 C4.5 2.5 2.5 4.5 2.5 7" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"></path><path d="M10.3 1.9 L10.9 4.5 L8.3 4" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"></path><path d="M3.4 9.8 C4.2 10.8 5.5 11.5 7 11.5 C9.5 11.5 11.5 9.5 11.5 7" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"></path><path d="M3.7 12.1 L3.1 9.5 L5.7 10" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"></path></svg>`;
	    default:
	      return "";
	  }
	}

function latestThreadActivityDate(node) {
  const transcript = Array.isArray(node.metadata?.localTranscript)
    ? node.metadata.localTranscript
    : [];
  let latest = null;
  for (const message of transcript) {
    const candidate = new Date(message?.createdAt || "");
    if (Number.isNaN(candidate.getTime())) {
      continue;
    }

    if (!latest || candidate > latest) {
      latest = candidate;
    }
  }

  return latest;
}

function workflowUpdatedDate() {
  const candidate = new Date(graph.updatedAt || "");
  return Number.isNaN(candidate.getTime()) ? null : candidate;
}

function threadActivityDate(node) {
  const latest = latestThreadActivityDate(node);
  if (latest) {
    return latest;
  }

  return node.metadata?.runStatus ? workflowUpdatedDate() : null;
}

function threadUpdatedText(node) {
  if (node.kind !== "codexThread") {
    return "";
  }

  const latest = threadActivityDate(node);
  if (!latest) {
    return "";
  }

  const deltaSeconds = Math.round((Date.now() - latest.getTime()) / 1000);
  const absoluteSeconds = Math.abs(deltaSeconds);
  const nowThresholdSeconds = Number(threadUpdatedFormatting?.nowThresholdSeconds) || 5;
  if (absoluteSeconds < nowThresholdSeconds) {
    return "updated now";
  }

  const unit = threadUpdatedUnitFor(absoluteSeconds);
  const unitSeconds = Math.max(1, Number(unit.seconds) || 1);
  const value = Math.max(1, Math.round(absoluteSeconds / unitSeconds));
  const signedValue = deltaSeconds < 0 ? value : -value;
  return `updated ${formatThreadRelativeTime(signedValue, unit)}`;
}

function threadUpdatedUnitFor(absoluteSeconds) {
  const units = Array.isArray(threadUpdatedFormatting?.units)
    ? threadUpdatedFormatting.units
    : [];
  for (const unit of units) {
    const ceilingSeconds = Number(unit.ceilingSeconds) || Number.POSITIVE_INFINITY;
    if (absoluteSeconds < ceilingSeconds) {
      return unit;
    }
  }

  return units.length > 0
    ? units[units.length - 1]
    : { unit: "year", seconds: 31557600, singularLabel: "yr.", pluralLabel: "yr." };
}

function formatThreadRelativeTime(signedValue, unit) {
  const unitName = String(unit.unit || "second");
  if (typeof Intl !== "undefined" && typeof Intl.RelativeTimeFormat === "function") {
    try {
      threadUpdatedRelativeFormatter ??= new Intl.RelativeTimeFormat(undefined, {
        numeric: "always",
        style: threadUpdatedFormatting?.intlStyle || "short"
      });
      return threadUpdatedRelativeFormatter.format(signedValue, unitName);
    } catch {
      // Fall through to deterministic English labels if the browser rejects a unit.
    }
  }

  const value = Math.abs(signedValue);
  const label = value === 1
    ? String(unit.singularLabel || unitName)
    : String(unit.pluralLabel || unit.singularLabel || unitName);
  return signedValue > 0
    ? `in ${value} ${label}`
    : `${value} ${label} ago`;
}

		function nodeActionsHtml(node) {
	  const canChooseFolder = canChooseProject(node);
	  const canAddFolder = node.kind === "machine" && (canChooseFolder || node.metadata?.hostStatus === "connected");
	  const folderPresentation = folderActionFor(canChooseFolder, canAddFolder);
	  const folderClass = folderPresentation.cssClass ? ` ${folderPresentation.cssClass}` : "";
	  const folderAriaDisabled = folderPresentation.isAriaDisabled ? ' aria-disabled="true"' : "";
	  const folderOpacity = Number(folderPresentation.opacity);
	  const folderStyle = Number.isFinite(folderOpacity) ? ` style="--node-action-opacity: ${folderOpacity}"` : "";
		  const folderAction = node.kind === "machine"
		    ? `<button class="node-action${folderClass}" data-command="addFolder" title="${escapeText(folderPresentation.toolTip)}" aria-label="${escapeText(folderPresentation.toolTip)}"${folderAriaDisabled}${folderStyle}><span class="folder-add-icon" aria-hidden="true"><span class="folder-base">&#xE8B7;</span><span class="folder-plus"></span></span></button>`
		    : "";
		  const drawLink = linkActionPresentation.draw;
		  return `
		    <div class="node-actions">
	      ${folderAction}
	      <button class="node-action node-link-action" data-command="link" title="${escapeText(drawLink.label)}" aria-label="${escapeText(drawLink.label)}">${linkActionIconHtml(drawLink)}</button>
	    </div>`;
			}

		function folderActionFor(canChooseFolder, canAddFolder) {
		  if (canChooseFolder) {
		    return {
		      toolTip: folderActionPresentation.chooseProjectToolTip,
		      cssClass: "",
		      isAriaDisabled: false,
		      opacity: folderActionPresentation.availableOpacity
		    };
		  }

		  if (canAddFolder) {
		    return {
		      toolTip: folderActionPresentation.addProjectToolTip,
		      cssClass: "",
		      isAriaDisabled: false,
		      opacity: folderActionPresentation.availableOpacity
		    };
		  }

		  return {
		    toolTip: folderActionPresentation.unavailableToolTip,
		    cssClass: folderActionPresentation.unavailableCssClass,
		    isAriaDisabled: folderActionPresentation.unavailableAriaDisabled,
		    opacity: folderActionPresentation.unavailableOpacity
		  };
		}

		function canChooseProject(node) {
		  return node?.kind === "machine" && browsableMachineIds.has(node.id);
	}

	function dottedConnectionIconHtml() {
	  return `<span class="node-link-icon dotted-connection-icon" aria-hidden="true"><svg viewBox="0 0 18 18" focusable="false"><path class="triangle-path" d="M3.3 12.2 L9 3.2 L14.7 12.2 Z"></path><circle class="triangle-point" cx="3.3" cy="12.2" r="1.45"></circle><circle class="triangle-point" cx="9" cy="3.2" r="1.45"></circle><circle class="triangle-point" cx="14.7" cy="12.2" r="1.45"></circle></svg></span>`;
	}

	function linkActionIconHtml(presentation) {
	  if (presentation?.iconKind === "dottedTrianglePath") {
	    return dottedConnectionIconHtml();
	  }

	  const glyph = presentation?.glyph || linkActionPresentation.draw.glyph;
	  return `<span class="node-link-icon fluent-link-icon" aria-hidden="true">${escapeText(glyph)}</span>`;
	}

	function contextMenuItemsFor(node) {
	  const items = [];
	  if (node.kind === "machine") {
	    items.push({
	      command: "addFolder",
	      icon: "&#xE8B7;",
	      text: canChooseProject(node) ? "Choose Project" : "Add Project"
	    });
	    items.push({ separator: true });
	  }

	  if (node.kind === "folder") {
	    items.push({
	      command: "showContents",
	      icon: "&#xE8E5;",
	      text: "Show Contents"
	    });
	    items.push({ separator: true });
	  }

	  if (node.kind === "codexThread") {
	    const isUnread = Boolean(node.metadata?.isUnread);
	    const isArchived = Boolean(node.metadata?.isArchived);
	    const isRunning = node.metadata?.runStatus === "running";
	    const hasThreadRef = Boolean(node.metadata?.threadRef?.threadID);
	    items.push({ command: "openChat", icon: "&#xE8F2;", text: "Open Chat" });
	    items.push({ command: "openReader", icon: "&#xE8A5;", text: "Open in Reader" });
	    items.push({
	      command: "toggleRead",
	      icon: isUnread ? "&#xE715;" : "&#xE119;",
	      text: isUnread ? "Mark as Read" : "Mark as Unread"
	    });
	    if (isRunning) {
	      items.push({ command: "stopThread", icon: "&#xE71A;", text: "Stop Turn" });
	    }
	    items.push({
	      command: "archiveThread",
	      icon: isArchived ? "&#xE845;" : "&#xE74D;",
	      text: isArchived ? "Restore Codex Thread" : "Archive Codex Thread",
	      destructive: !isArchived
	    });
	    items.push({
	      command: "forkThread",
	      icon: "&#xE8F0;",
	      text: "Duplicate / Fork",
	      disabled: !hasThreadRef
	    });
	    items.push({
	      command: "copyThreadId",
	      icon: "&#xE8C8;",
	      text: "Copy Thread ID",
	      disabled: !hasThreadRef
	    });
	    items.push({
	      command: "reconnectOwner",
	      icon: "&#xE895;",
	      text: "Reconnect Owner",
	      disabled: !hasThreadRef
	    });
	    items.push({ separator: true });
	  }

	  items.push({
	    command: "link",
	    icon: linkActionIconHtml(linkActionPresentation.draw),
	    text: linkActionPresentation.draw.label
	  });
	  items.push({ separator: true });
	  items.push({ command: "deleteNode", icon: "&#xE74D;", text: "Delete from Canvas", destructive: true });
	  return items;
	}

	function hideNodeContextMenu() {
	  contextMenuNodeId = null;
	  contextMenu.style.display = "none";
	  contextMenu.replaceChildren();
	}

	function postNodeCommand(id, command) {
	  if (window.chrome?.webview) {
	    window.chrome.webview.postMessage({ type: "nodeCommand", id, command });
	  }
	}

	function showNodeContextMenu(node, event) {
	  event.preventDefault();
	  event.stopPropagation();
	  selectNode(node.id, false);
	  contextMenuNodeId = node.id;
	  contextMenu.replaceChildren();

	  for (const item of contextMenuItemsFor(node)) {
	    if (item.separator) {
	      const separator = document.createElement("div");
	      separator.className = "context-menu-separator";
	      contextMenu.appendChild(separator);
	      continue;
	    }

	    const button = document.createElement("button");
	    button.type = "button";
	    button.className = `context-menu-item${item.destructive ? " destructive" : ""}`;
	    button.disabled = Boolean(item.disabled);
	    button.dataset.command = item.command;
	    button.innerHTML = `<span class="context-menu-icon" aria-hidden="true">${item.icon}</span><span>${escapeText(item.text)}</span>`;
	    button.addEventListener("click", clickEvent => {
	      clickEvent.stopPropagation();
	      if (!button.disabled) {
	        postNodeCommand(node.id, item.command);
	      }
	      hideNodeContextMenu();
	    });
	    contextMenu.appendChild(button);
	  }

	  contextMenu.style.display = "block";
	  const rect = contextMenu.getBoundingClientRect();
	  const left = Math.max(8, Math.min(event.clientX, window.innerWidth - rect.width - 8));
	  const top = Math.max(8, Math.min(event.clientY, window.innerHeight - rect.height - 8));
	  contextMenu.style.left = `${left}px`;
	  contextMenu.style.top = `${top}px`;
	}

function renderNodes() {
  if (nodes.length === 0) {
    world.innerHTML = `<section id="edgeControls" aria-label="Line controls"></section>`;
    renderEdgeControls();
    draw();
    return;
  }

  const nodeHtml = nodes.map(node => {
    const width = node.size?.width ?? 200;
    const height = node.size?.height ?? 96;
    const left = (node.position?.x ?? 0) - width / 2;
    const top = (node.position?.y ?? 0) - height / 2;
    const accent = accentFor(node);
    const nodeBorder = alphaHex(accent, nodeBorderOpacityFor(node));
    const model = node.metadata?.model;
    const effort = node.metadata?.reasoningEffort;
    const agentBadge = isSubagent(node) ? "<span class=\"agent-badge\">agent</span>" : "";
    const unreadDot = node.metadata?.isUnread ? "<span class=\"unread-dot\"></span>" : "";
    const subtitle = String(node.subtitle || "").trim();
    const subtitleHtml = subtitle ? `<div class="node-subtitle">${escapeText(subtitle)}</div>` : "";
    const compact = height < 110 ? " compact" : "";
    const hidden = !showsSubagents && isSubagent(node) ? "display:none;" : "";
    const updatedText = threadUpdatedText(node);
    return `
      <article
        class="node${compact}"
        data-node-id="${escapeText(node.id)}"
        style="left:${left}px; top:${top}px; width:${width}px; --node-height:${height}px; --accent:${accent}; --accent-soft:${alphaHex(accent, 0.12)}; --node-border:${nodeBorder}; ${hidden}">
        <div class="node-inner">
          <div class="node-heading">
            <div class="node-icon">${iconFor(node)}</div>
            <div class="node-copy">
              <div class="node-title-row">
                <div class="node-title">${escapeText(node.title || node.kind)}</div>
                ${agentBadge}
                ${unreadDot}
              </div>
              ${subtitleHtml}
            </div>
            ${nodeActionsHtml(node)}
          </div>
          <div></div>
          <div class="node-footer">
            ${statusPillHtml(node)}
            ${updatedText ? `<span class="node-updated" title="${escapeText(updatedText)}">${escapeText(updatedText)}</span>` : ""}
            ${nodeFooterSpacerBeforeMetadata ? "<span class=\"spacer\"></span>" : ""}
            ${model ? `<span class="pill tiny meta-pill">${escapeText(model)}</span>` : ""}
            ${effort ? `<span class="pill tiny meta-pill">${escapeText(effort)}</span>` : ""}
          </div>
        </div>
      </article>`;
  }).join("");
  world.innerHTML = `<section id="edgeControls" aria-label="Line controls"></section>${nodeHtml}`;
  renderEdgeControls();

	  for (const element of world.querySelectorAll(".node")) {
	    element.addEventListener("contextmenu", event => {
	      const node = nodeById.get(element.dataset.nodeId);
	      if (node) {
	        showNodeContextMenu(node, event);
	      }
	    });
	    element.addEventListener("pointerdown", event => {
	      if (event.button !== 0) {
	        return;
      }

      event.stopPropagation();
      const node = nodeById.get(element.dataset.nodeId);
      if (!node) {
        return;
      }

      if (pendingLinkSourceId) {
        event.preventDefault();
        if (pendingLinkSourceId === node.id) {
          cancelLinkMode(true);
        } else {
          completeLinkTo(node.id);
        }
        return;
      }

      selectNode(node.id);
      nodeDrag = {
        node,
        element,
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        nodeX: node.position?.x ?? 0,
        nodeY: node.position?.y ?? 0,
        moved: false
      };
      element.setPointerCapture(event.pointerId);
    });
  }

  for (const action of world.querySelectorAll(".node-action")) {
    action.addEventListener("pointerdown", event => {
      event.stopPropagation();
    });
	    action.addEventListener("click", event => {
	      event.stopPropagation();
      const element = action.closest(".node");
      const node = element ? nodeById.get(element.dataset.nodeId) : null;
      if (!node || !window.chrome?.webview) {
        return;
      }

      if (action.dataset.command === "link" && pendingLinkSourceId) {
        if (pendingLinkSourceId === node.id) {
          cancelLinkMode(true);
        } else {
          completeLinkTo(node.id);
        }
        return;
      }

	      selectNode(node.id, action.dataset.command !== "link");
	      postNodeCommand(node.id, action.dataset.command);
	    });
	  }
	}

function resizeCanvas() {
  const dpr = window.devicePixelRatio || 1;
  const width = Math.max(1, Math.floor(window.innerWidth));
  const height = Math.max(1, Math.floor(window.innerHeight));
  canvas.width = width * dpr;
  canvas.height = height * dpr;
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}

function usesReducedGrid() {
  if (selectedEdgeId) {
    return true;
  }

  const selectedNode = selectedNodeId ? nodeById.get(selectedNodeId) : null;
  return selectedNode?.kind === "codexThread";
}

function drawGrid() {
  const reduced = usesReducedGrid();
  ctx.save();

  if (reduced) {
    strokeScreenGrid(48, edgeVisualTreatment?.gridReducedCss || "rgba(167, 176, 191, 0.14)");
  } else {
    strokeScreenGrid(24, edgeVisualTreatment?.gridMinorCss || "rgba(167, 176, 191, 0.12)", index => index % 4 !== 0);
    strokeScreenGrid(24, edgeVisualTreatment?.gridMajorCss || "rgba(167, 176, 191, 0.20)", index => index % 4 === 0);
  }

  ctx.restore();
}

function strokeScreenGrid(spacing, color, includeLine = () => true) {
  const width = window.innerWidth;
  const height = window.innerHeight;
  ctx.beginPath();
  ctx.strokeStyle = color;
  ctx.lineWidth = 1;

  for (let column = 0, x = 0; x <= width; column++, x += spacing) {
    if (includeLine(column)) {
      ctx.moveTo(x, 0);
      ctx.lineTo(x, height);
    }
  }

  for (let row = 0, y = 0; y <= height; row++, y += spacing) {
    if (includeLine(row)) {
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
    }
  }

  ctx.stroke();
}

function nodeBounds(node) {
  const width = node.size?.width ?? 200;
  const height = node.size?.height ?? 96;
  return {
    x: (node.position?.x ?? 0) - width / 2,
    y: (node.position?.y ?? 0) - height / 2,
    width,
    height
  };
}

function nodeCenter(node) {
  return {
    x: node.position?.x ?? 0,
    y: node.position?.y ?? 0
  };
}

function rectEdgePoint(bounds, center, toward) {
  const dx = toward.x - center.x;
  const dy = toward.y - center.y;
  if (Math.abs(dx) <= 0.01 && Math.abs(dy) <= 0.01) {
    return center;
  }

  const halfWidth = bounds.width / 2;
  const halfHeight = bounds.height / 2;
  const scaleX = Math.abs(dx) > 0.01 ? halfWidth / Math.abs(dx) : Number.POSITIVE_INFINITY;
  const scaleY = Math.abs(dy) > 0.01 ? halfHeight / Math.abs(dy) : Number.POSITIVE_INFINITY;
  const scale = Math.min(scaleX, scaleY);
  const length = Math.max(0.01, Math.hypot(dx, dy));
  const outset = 5;
  return {
    x: center.x + dx * scale + (dx / length) * outset,
    y: center.y + dy * scale + (dy / length) * outset
  };
}

function parallelEdgeRank(edge) {
  if (edge.kind === "threadMessage") {
    return 0;
  }
  if (edge.kind === "createdBy") {
    return 1;
  }
  return 2;
}

function parallelWorkflowEdgeOffsets(edgeList) {
  const groups = new Map();
  for (const edge of edgeList) {
    if (edge.kind !== "threadMessage" && edge.kind !== "createdBy") {
      continue;
    }
    const key = `${edge.source}->${edge.target}`;
    const group = groups.get(key) || [];
    group.push(edge);
    groups.set(key, group);
  }

  const offsets = new Map();
  for (const group of groups.values()) {
    if (group.length <= 1) {
      continue;
    }
    group.sort((a, b) => {
      const rankDelta = parallelEdgeRank(a) - parallelEdgeRank(b);
      return rankDelta !== 0 ? rankDelta : String(a.id).localeCompare(String(b.id));
    });
    const midpoint = (group.length - 1) / 2;
    group.forEach((edge, index) => {
      offsets.set(edge.id, (index - midpoint) * 10);
    });
  }

  return offsets;
}

function focusedNodeId() {
  if (pendingLinkSourceId) {
    return null;
  }

  const node = selectedNodeId ? nodeById.get(selectedNodeId) : null;
  return node?.kind === "codexThread" ? node.id : null;
}

function focusedNodeNeighborhood() {
  const focusId = focusedNodeId();
  if (!focusId) {
    return null;
  }

  const neighborhood = new Set([focusId]);
  for (const edge of edges) {
    if (edge.source === focusId || edge.target === focusId) {
      neighborhood.add(edge.source);
      neighborhood.add(edge.target);
    }
  }

  return neighborhood;
}

function updateNodeStateClasses() {
  const neighborhood = focusedNodeNeighborhood();
  for (const element of world.querySelectorAll(".node")) {
    const nodeId = element.dataset.nodeId;
    element.classList.toggle("selected", nodeId === selectedNodeId);
    element.classList.toggle("dimmed", Boolean(neighborhood) && !neighborhood.has(nodeId));
  }
}

function edgeMeta(edge, isSelected, focusOpacity) {
  const selectedColor = "rgba(10, 132, 255, 1)";
  const selectedWidth = 4;
  if (isSelected) {
    return {
      color: selectedColor,
      width: selectedWidth,
      dash: edge.kind === "machineFolder" || edge.kind === "folderThread" || edge.kind === "machineThread" ? [] : [9, 8],
      label: normalizeEdgeLabel(edge.label),
      labelT: 0.52,
      labelOffsetY: -10,
      arrow: edge.kind === "createdBy" || edge.kind === "threadMessage",
      labelColor: "#6ab7ff",
      labelFill: "rgba(10, 132, 255, 0.15)",
      labelStroke: "rgba(10, 132, 255, 0.76)",
      labelChip: edge.isManual
    };
  }

  if (edge.kind === "createdBy") {
    return {
      color: `rgba(255, 159, 10, ${0.82 * focusOpacity})`,
      width: 3,
      dash: [9, 8],
      label: normalizeEdgeLabel(edge.label || "created"),
      labelT: 0.86,
      labelOffsetY: -20,
      arrow: true,
      labelColor: "#ff9f0a",
      labelFill: "rgba(255, 159, 10, 0.15)",
      labelStroke: "rgba(255, 159, 10, 0.72)",
      labelChip: false
    };
  }

  if (edge.kind === "threadMessage") {
    return {
      color: `rgba(10, 132, 255, ${0.78 * focusOpacity})`,
      width: 3,
      dash: [9, 8],
      label: normalizeEdgeLabel(edge.label || "message"),
      labelT: 0.52,
      labelOffsetY: -10,
      arrow: true,
      labelColor: "#6ab7ff",
      labelFill: "rgba(10, 132, 255, 0.15)",
      labelStroke: "rgba(10, 132, 255, 0.70)",
      labelChip: false
    };
  }

  if (edge.kind === "manualNote" || edge.isManual) {
    return {
      color: `rgba(48, 209, 88, ${0.72 * focusOpacity})`,
      width: 3,
      dash: [9, 8],
      label: normalizeEdgeLabel(edge.label),
      labelT: 0.52,
      labelOffsetY: -10,
      arrow: false,
      labelColor: "#30d158",
      labelFill: "rgba(48, 209, 88, 0.14)",
      labelStroke: "rgba(48, 209, 88, 0.54)",
      labelChip: true
    };
  }

  return {
    color: focusOpacity === 1
      ? (edgeVisualTreatment?.workflowEdgeCss || "rgba(167, 176, 191, 0.52)")
      : `rgba(167, 176, 191, ${0.52 * focusOpacity})`,
    width: 3,
    dash: [],
    label: normalizeEdgeLabel(edge.label),
    labelT: 0.52,
    labelOffsetY: -10,
    arrow: false,
    labelColor: edgeVisualTreatment?.workflowLabelHex || "#A7B0BF",
    labelFill: edgeVisualTreatment?.workflowLabelFillCss || "rgba(167, 176, 191, 0.12)",
    labelStroke: edgeVisualTreatment?.workflowLabelStrokeCss || "rgba(167, 176, 191, 0.38)",
    labelChip: false
  };
}

function normalizeEdgeLabel(label) {
  const text = String(label ?? "").trim();
  if (!text) {
    return "";
  }

  return text.toLowerCase() === "created by" ? "created" : text;
}

function cubicPoint(geometry, t) {
  const oneMinusT = 1 - t;
  const p0 = geometry.from;
  const p1 = geometry.control1;
  const p2 = geometry.control2;
  const p3 = geometry.to;
  return {
    x:
      oneMinusT * oneMinusT * oneMinusT * p0.x +
      3 * oneMinusT * oneMinusT * t * p1.x +
      3 * oneMinusT * t * t * p2.x +
      t * t * t * p3.x,
    y:
      oneMinusT * oneMinusT * oneMinusT * p0.y +
      3 * oneMinusT * oneMinusT * t * p1.y +
      3 * oneMinusT * t * t * p2.y +
      t * t * t * p3.y
  };
}

function drawRoundedRect(x, y, width, height, radius) {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + width - r, y);
  ctx.quadraticCurveTo(x + width, y, x + width, y + r);
  ctx.lineTo(x + width, y + height - r);
  ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
  ctx.lineTo(x + r, y + height);
  ctx.quadraticCurveTo(x, y + height, x, y + height - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

function drawEdgeLabel(label, point, meta) {
  if (!label) {
    return;
  }

  const fontSize = 10.5;
  ctx.save();
  ctx.setLineDash([]);
  ctx.font = `700 ${fontSize}px "Segoe UI Variable", "Segoe UI", system-ui, sans-serif`;
  ctx.textBaseline = "middle";

  if (!meta.labelChip) {
    ctx.textAlign = "center";
    ctx.fillStyle = meta.labelColor;
    ctx.fillText(label, point.x, point.y);
    ctx.restore();
    return;
  }

  const padX = 8;
  const padY = 4;
  const radius = 10;
  const textWidth = ctx.measureText(label).width;
  const width = textWidth + padX * 2;
  const height = fontSize + padY * 2;
  const x = point.x - width / 2;
  const y = point.y - height / 2;
  drawRoundedRect(x, y, width, height, radius);
  ctx.fillStyle = meta.labelFill;
  ctx.fill();
  ctx.strokeStyle = meta.labelStroke;
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.fillStyle = meta.labelColor;
  ctx.fillText(label, x + padX, point.y);
  ctx.restore();
}

function drawEdgeArrow(geometry, meta) {
  if (!meta.arrow) {
    return;
  }

  const connectorStartT = Number(edgeArrowTreatment?.connectorStartT) || 0.93;
  const arrowTailT = Number(edgeArrowTreatment?.arrowTailT) || 0.9;
  if (edgeArrowTreatment?.drawsSolidConnector !== false) {
    const connectorStart = cubicPoint(geometry, connectorStartT);
    ctx.save();
    ctx.setLineDash([]);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = meta.color;
    ctx.lineWidth = meta.width;
    ctx.beginPath();
    ctx.moveTo(connectorStart.x, connectorStart.y);
    ctx.lineTo(geometry.to.x, geometry.to.y);
    ctx.stroke();
    ctx.restore();
  }

  const tail = cubicPoint(geometry, arrowTailT);
  const tip = geometry.to;
  const angle = Math.atan2(tip.y - tail.y, tip.x - tail.x);
  const selectedSize = Number(edgeArrowTreatment?.selectedHeadSize) || 14;
  const defaultSize = Number(edgeArrowTreatment?.defaultHeadSize) || 11;
  const size = meta.width >= 4 ? selectedSize : defaultSize;
  ctx.save();
  ctx.setLineDash([]);
  ctx.fillStyle = meta.color;
  ctx.beginPath();
  ctx.moveTo(tip.x, tip.y);
  ctx.lineTo(
    tip.x - Math.cos(angle - Math.PI / 6) * size,
    tip.y - Math.sin(angle - Math.PI / 6) * size
  );
  ctx.lineTo(
    tip.x - Math.cos(angle + Math.PI / 6) * size,
    tip.y - Math.sin(angle + Math.PI / 6) * size
  );
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

function worldPointFromEvent(event) {
  return {
    x: (event.clientX - view.x) / view.scale,
    y: (event.clientY - view.y) / view.scale
  };
}

function edgeGeometry(edge) {
  const source = nodeById.get(edge.source);
  const target = nodeById.get(edge.target);
  if (!source || !target || (!showsSubagents && (isSubagent(source) || isSubagent(target)))) {
    return null;
  }

  const sourceBounds = nodeBounds(source);
  const targetBounds = nodeBounds(target);
  const sourceCenter = nodeCenter(source);
  const targetCenter = nodeCenter(target);
  const centerDX = targetCenter.x - sourceCenter.x;
  const centerDY = targetCenter.y - sourceCenter.y;
  const centerLength = Math.hypot(centerDX, centerDY);
  const visualOffset = edgeVisualOffsets.get(edge.id) || 0;
  const normal = centerLength > 0.01
    ? { x: -centerDY / centerLength, y: centerDX / centerLength }
    : { x: 0, y: 0 };
  const sourceAim = {
    x: targetCenter.x + normal.x * visualOffset,
    y: targetCenter.y + normal.y * visualOffset
  };
  const targetAim = {
    x: sourceCenter.x + normal.x * visualOffset,
    y: sourceCenter.y + normal.y * visualOffset
  };
  const from = rectEdgePoint(sourceBounds, sourceCenter, sourceAim);
  const to = rectEdgePoint(targetBounds, targetCenter, targetAim);
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  if (Math.abs(dy) > Math.abs(dx) * 1.25) {
    const sign = dy >= 0 ? 1 : -1;
    const controlOffset = Math.max(60, Math.abs(dy) * 0.28);
    return {
      source,
      target,
      from,
      control1: { x: from.x, y: from.y + sign * controlOffset },
      control2: { x: to.x, y: to.y - sign * controlOffset },
      to
    };
  }

  const sign = dx >= 0 ? 1 : -1;
  const controlOffset = Math.max(60, Math.abs(dx) * 0.28);
  return {
    source,
    target,
    from,
    control1: { x: from.x + sign * controlOffset, y: from.y },
    control2: { x: to.x - sign * controlOffset, y: to.y },
    to
  };
}

function distanceToSegment(point, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) {
    return Math.hypot(point.x - a.x, point.y - a.y);
  }

  const t = Math.max(0, Math.min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared));
  const projection = { x: a.x + t * dx, y: a.y + t * dy };
  return Math.hypot(point.x - projection.x, point.y - projection.y);
}

function distanceToEdge(point, geometry) {
  let previous = geometry.from;
  let closest = Number.POSITIVE_INFINITY;
  for (let index = 1; index <= 36; index++) {
    const current = cubicPoint(geometry, index / 36);
    closest = Math.min(closest, distanceToSegment(point, previous, current));
    previous = current;
  }

  return closest;
}

function findEdgeAt(point) {
  const threshold = 9 / Math.max(0.6, view.scale);
  let best = null;
  let bestDistance = threshold;
  for (let index = editableEdges.length - 1; index >= 0; index--) {
    const edge = editableEdges[index];
    const geometry = edgeGeometry(edge);
    if (!geometry) {
      continue;
    }

    const distance = distanceToEdge(point, geometry);
    if (distance <= bestDistance) {
      best = edge;
      bestDistance = distance;
    }
  }

  return best;
}

function edgeLabel(edge) {
  const customLabel = normalizeEdgeLabel(edge.label);
  if (customLabel) {
    return customLabel;
  }

  switch (edge.kind) {
    case "machineFolder":
      return "folder";
    case "folderThread":
    case "machineThread":
      return "thread";
    case "manualNote":
      return "note";
    case "threadMessage":
      return "message";
    case "createdBy":
      return "created";
    default:
      return "line";
  }
}

function edgeControlStyle(edge) {
  const style = edgeControlStyles[edge.kind] || edgeControlStyles.line;
  return {
    icon: edgeControlIconHtml(style),
    tint: style.tintHex,
    stroke: style.strokeCss,
    selectedBg: style.selectedBackgroundCss,
    help: style.helpText,
    labelOffset: Number(style.labelOffset) || 12
  };
}

function edgeControlIconHtml(style) {
  if (style?.usesThreadPairIcon) {
    return "<span class=\"edge-thread-pair-icon\"></span>";
  }

  return escapeText(style?.glyph || "\uE8F3");
}

function edgeLabelOffset(edge) {
  return edgeControlStyle(edge).labelOffset;
}

function cubicTangent(geometry, t) {
  const oneMinusT = 1 - t;
  const p0 = geometry.from;
  const p1 = geometry.control1;
  const p2 = geometry.control2;
  const p3 = geometry.to;
  return {
    x:
      3 * oneMinusT * oneMinusT * (p1.x - p0.x) +
      6 * oneMinusT * t * (p2.x - p1.x) +
      3 * t * t * (p3.x - p2.x),
    y:
      3 * oneMinusT * oneMinusT * (p1.y - p0.y) +
      6 * oneMinusT * t * (p2.y - p1.y) +
      3 * t * t * (p3.y - p2.y)
  };
}

function edgeControlPosition(edge) {
  const geometry = edgeGeometry(edge);
  if (!geometry) {
    return null;
  }

  const midpoint = cubicPoint(geometry, 0.5);
  const tangent = cubicTangent(geometry, 0.5);
  const length = Math.max(0.01, Math.hypot(tangent.x, tangent.y));
  const offset = edgeLabelOffset(edge);
  return {
    x: midpoint.x + (-tangent.y / length) * offset,
    y: midpoint.y + (tangent.x / length) * offset
  };
}

function renderEdgeControls() {
  const container = document.getElementById("edgeControls");
  if (!container) {
    return;
  }

  container.innerHTML = editableEdges.map(edge => {
    const style = edgeControlStyle(edge);
    const label = edgeLabel(edge);
    return `
      <button
        class="edge-control"
        data-edge-id="${escapeText(edge.id)}"
        style="--edge-tint:${style.tint}; --edge-stroke:${style.stroke}; --edge-selected-bg:${style.selectedBg};"
        title="${style.help}"
        aria-label="${escapeText(label)} line">
        <span class="edge-control-icon" aria-hidden="true">${style.icon}</span>
        <span>${escapeText(label)}</span>
      </button>`;
  }).join("");

  for (const control of container.querySelectorAll(".edge-control")) {
    control.addEventListener("pointerdown", event => {
      event.stopPropagation();
    });
    control.addEventListener("click", event => {
      event.stopPropagation();
      selectEdge(control.dataset.edgeId);
    });
  }

  updateEdgeControls();
}

function updateEdgeControls() {
  const container = document.getElementById("edgeControls");
  if (!container) {
    return;
  }

  for (const control of container.querySelectorAll(".edge-control")) {
    const edge = editableEdges.find(item => item.id === control.dataset.edgeId);
    const position = edge ? edgeControlPosition(edge) : null;
    control.classList.toggle("selected", control.dataset.edgeId === selectedEdgeId);
    if (!position) {
      control.style.display = "none";
      continue;
    }

    control.style.display = "";
    control.style.left = `${position.x}px`;
    control.style.top = `${position.y}px`;
  }
}

function drawEdges() {
  ctx.save();
  ctx.translate(view.x, view.y);
  ctx.scale(view.scale, view.scale);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  for (const edge of edges) {
    const geometry = edgeGeometry(edge);
    if (!geometry) {
      continue;
    }

    const { source, target, from, control1, control2, to } = geometry;
    const isSelected = selectedEdgeId === edge.id;
    const isFocused = isSelected || !selectedNodeId || selectedNodeId === source.id || selectedNodeId === target.id;
    const meta = edgeMeta(edge, isSelected, isFocused ? 1 : 0.18);
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.bezierCurveTo(control1.x, control1.y, control2.x, control2.y, to.x, to.y);
    ctx.strokeStyle = meta.color;
    ctx.lineWidth = meta.width;
    if (meta.dash.length > 0) {
      ctx.setLineDash(meta.dash);
    } else {
      ctx.setLineDash([]);
    }
    ctx.stroke();
    drawEdgeArrow(geometry, meta);
  }

  ctx.restore();
}

function draw() {
  ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
  drawGrid();
  drawEdges();
  updateEdgeControls();
}

function applyView() {
  view.scale = Math.max(0.35, Math.min(2.4, view.scale));
  world.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.scale})`;
  draw();
}

function postViewportChanged() {
  if (window.chrome?.webview) {
    window.chrome.webview.postMessage({ type: "viewportChanged", x: view.x, y: view.y, scale: view.scale });
  }
}

function selectNode(id, notifyHost = true) {
  pendingLinkSourceId = null;
  selectedNodeId = id;
  selectedEdgeId = null;
  applyLinkState();
  updateNodeStateClasses();

  draw();

  if (notifyHost && window.chrome?.webview) {
    window.chrome.webview.postMessage({ type: "nodeSelected", id });
  }
}

function selectEdge(id) {
  pendingLinkSourceId = null;
  selectedNodeId = null;
  selectedEdgeId = id;
  applyLinkState();
  updateNodeStateClasses();

  draw();

  if (window.chrome?.webview) {
    window.chrome.webview.postMessage({ type: "edgeSelected", id });
  }
}

function clearSelection() {
  selectedNodeId = null;
  selectedEdgeId = null;
  pendingLinkSourceId = null;
  applyLinkState();
  updateNodeStateClasses();
  draw();
}

function highlightNode(id) {
  highlightedNodeId = id && nodeById.has(id) ? id : null;
  for (const element of world.querySelectorAll(".node")) {
    element.classList.toggle("highlighted", element.dataset.nodeId === highlightedNodeId);
  }
}

function clearHighlight(id = null) {
  if (id && highlightedNodeId !== id) {
    return;
  }

  highlightedNodeId = null;
  for (const element of world.querySelectorAll(".node")) {
    element.classList.remove("highlighted");
  }
}

function beginLinkMode(sourceId) {
  if (!sourceId || !nodeById.has(sourceId)) {
    cancelLinkMode(false);
    return;
  }

  selectedNodeId = sourceId;
  selectedEdgeId = null;
  pendingLinkSourceId = sourceId;
  updateNodeStateClasses();
  applyLinkState();
  draw();
}

function cancelLinkMode(notifyHost) {
  const hadPendingLink = Boolean(pendingLinkSourceId);
  pendingLinkSourceId = null;
  applyLinkState();
  draw();
  if (notifyHost && hadPendingLink && window.chrome?.webview) {
    window.chrome.webview.postMessage({ type: "linkCancelled" });
  }
}

function completeLinkTo(targetId) {
  const sourceId = pendingLinkSourceId;
  pendingLinkSourceId = null;
  applyLinkState();
  if (!sourceId || !targetId || sourceId === targetId) {
    draw();
    if (window.chrome?.webview) {
      window.chrome.webview.postMessage({ type: "linkCancelled" });
    }
    return;
  }

  if (window.chrome?.webview) {
    window.chrome.webview.postMessage({ type: "linkTargetSelected", sourceId, targetId });
  }
}

function updateLinkActionButton(linkAction, presentation, isActive) {
  linkAction.classList.toggle("link-active", isActive);
  linkAction.innerHTML = linkActionIconHtml(presentation);
  linkAction.title = presentation.label || linkActionPresentation.draw.label;
  linkAction.setAttribute("aria-label", presentation.label || linkActionPresentation.draw.label);
}

function applyLinkState() {
  stage.classList.toggle("linking", Boolean(pendingLinkSourceId));
  linkHint.classList.toggle("visible", Boolean(pendingLinkSourceId));
  for (const element of world.querySelectorAll(".node")) {
    const nodeId = element.dataset.nodeId;
    const isSource = pendingLinkSourceId === nodeId;
    const isTargetable = Boolean(pendingLinkSourceId) && pendingLinkSourceId !== nodeId;
    element.classList.toggle("link-source", isSource);
    element.classList.toggle("link-targetable", isTargetable);
	    const linkAction = element.querySelector(".node-link-action");
	    if (linkAction) {
	      if (isSource) {
	        updateLinkActionButton(linkAction, linkActionPresentation.cancel, true);
	      } else if (isTargetable) {
	        updateLinkActionButton(linkAction, linkActionPresentation.complete, true);
	      } else {
	        updateLinkActionButton(linkAction, linkActionPresentation.draw, false);
	      }
	    }
  }
}

function updateSubagentVisibility() {
  for (const element of world.querySelectorAll(".node")) {
    const node = nodeById.get(element.dataset.nodeId);
    element.style.display = !showsSubagents && node && isSubagent(node) ? "none" : "";
  }
  draw();
}

function applyGraphUpdate(payload) {
  const nextGraph = payload?.graph;
  if (!nextGraph) {
    return;
  }

  hideNodeContextMenu();
  if (typeof payload.showsSubagents === "boolean") {
    showsSubagents = payload.showsSubagents;
  }
  if (Array.isArray(payload.browsableMachineIds)) {
    browsableMachineIds = new Set(payload.browsableMachineIds);
  }
  const previousSelectedNodeId = selectedNodeId;
  const previousSelectedEdgeId = selectedEdgeId;
  const previousPendingLinkSourceId = pendingLinkSourceId;
  const previousHighlightId = highlightedNodeId;

  setGraphData(nextGraph, payload.semanticEdges);

  const requestedNodeId = payload.selectedNodeId ?? previousSelectedNodeId;
  const requestedEdgeId = payload.selectedEdgeId ?? previousSelectedEdgeId;
  const requestedNode = requestedNodeId ? nodeById.get(requestedNodeId) : null;
  const requestedEdge = requestedEdgeId ? edges.find(edge => edge.id === requestedEdgeId) : null;
  const pendingLinkSource = previousPendingLinkSourceId ? nodeById.get(previousPendingLinkSourceId) : null;

  selectedNodeId = isVisibleNode(requestedNode) ? requestedNode.id : null;
  selectedEdgeId = !selectedNodeId && isVisibleEdge(requestedEdge)
    ? requestedEdge.id
    : null;
  pendingLinkSourceId = isVisibleNode(pendingLinkSource)
    ? previousPendingLinkSourceId
    : null;
  highlightedNodeId = previousHighlightId && nodeById.has(previousHighlightId) ? previousHighlightId : null;

  renderNodes();
  applyLinkState();
  updateNodeStateClasses();
  if (highlightedNodeId) {
    highlightNode(highlightedNodeId);
  }
  applyView();
}

function parseHostMessage(data) {
  if (typeof data !== "string") {
    return data;
  }

  try {
    return JSON.parse(data);
  } catch {
    return null;
  }
}

function handleHostMessage(data) {
  const payload = parseHostMessage(data);
  if (!payload) {
    return;
  }

  switch (payload?.type) {
    case "graphUpdated":
      applyGraphUpdate(payload);
      break;
    case "zoomIn":
      view.scale *= 1.15;
      applyView();
      postViewportChanged();
      break;
    case "zoomOut":
      view.scale /= 1.15;
      applyView();
      postViewportChanged();
      break;
    case "resetView":
      view = { x: 0, y: 0, scale: 1 };
      applyView();
      postViewportChanged();
      break;
    case "clearSelection":
      clearSelection();
      break;
    case "highlightNode":
      highlightNode(payload.id);
      break;
    case "clearHighlight":
      clearHighlight(payload.id);
      break;
    case "selectNode":
      if (payload.id && nodeById.has(payload.id)) {
        selectNode(payload.id);
      }
      break;
    case "selectEdge":
      if (payload.id && edges.some(edge => edge.id === payload.id)) {
        selectEdge(payload.id);
      }
      break;
    case "beginLink":
      beginLinkMode(payload.id);
      break;
    case "cancelLink":
      cancelLinkMode(false);
      break;
    case "showSubagents":
      showsSubagents = true;
      updateSubagentVisibility();
      break;
    case "hideSubagents":
      showsSubagents = false;
      updateSubagentVisibility();
      break;
  }
}

	stage.addEventListener("pointerdown", event => {
	  hideNodeContextMenu();
	  if (event.button !== 0) {
	    return;
	  }

  if (pendingLinkSourceId) {
    event.preventDefault();
    cancelLinkMode(true);
    return;
  }

  const edge = findEdgeAt(worldPointFromEvent(event));
  if (edge) {
    event.preventDefault();
    selectEdge(edge.id);
    return;
  }

  stageDrag = { x: event.clientX, y: event.clientY, viewX: view.x, viewY: view.y, moved: false };
  stage.classList.add("dragging");
  stage.setPointerCapture(event.pointerId);
});

stage.addEventListener("pointermove", event => {
  if (!stageDrag) {
    return;
  }

  view.x = stageDrag.viewX + event.clientX - stageDrag.x;
  view.y = stageDrag.viewY + event.clientY - stageDrag.y;
  stageDrag.moved = stageDrag.moved || Math.abs(event.clientX - stageDrag.x) > 2 || Math.abs(event.clientY - stageDrag.y) > 2;
  applyView();
});

stage.addEventListener("pointerup", event => {
  if (!stageDrag) {
    return;
  }

  const current = stageDrag;
  stageDrag = null;
  stage.classList.remove("dragging");
  stage.releasePointerCapture(event.pointerId);
  if (current.moved) {
    postViewportChanged();
  } else {
    clearSelection();
    if (window.chrome?.webview) {
      window.chrome.webview.postMessage({ type: "selectionCleared" });
    }
  }
});

window.addEventListener("pointermove", event => {
  if (!nodeDrag) {
    return;
  }

  const dx = (event.clientX - nodeDrag.startX) / view.scale;
  const dy = (event.clientY - nodeDrag.startY) / view.scale;
  if (Math.abs(dx) > 1 || Math.abs(dy) > 1) {
    nodeDrag.moved = true;
  }

  const nextX = nodeDrag.nodeX + dx;
  const nextY = nodeDrag.nodeY + dy;
  const width = nodeDrag.node.size?.width ?? 200;
  const height = nodeDrag.node.size?.height ?? 96;
  nodeDrag.node.position = { x: nextX, y: nextY };
  nodeDrag.element.style.left = `${nextX - width / 2}px`;
  nodeDrag.element.style.top = `${nextY - height / 2}px`;
  draw();
});

window.addEventListener("pointerup", event => {
  if (!nodeDrag) {
    return;
  }

  const current = nodeDrag;
  nodeDrag = null;
  try {
    current.element.releasePointerCapture(current.pointerId);
  } catch {
  }

  if (current.moved && window.chrome?.webview) {
    window.chrome.webview.postMessage({
      type: "nodeMoved",
      id: current.node.id,
      x: current.node.position?.x ?? 0,
      y: current.node.position?.y ?? 0
    });
  } else if (!current.moved) {
    selectNode(current.node.id);
  }
});

	stage.addEventListener("wheel", event => {
	  hideNodeContextMenu();
	  event.preventDefault();
  const oldScale = view.scale;
  const worldX = (event.clientX - view.x) / oldScale;
  const worldY = (event.clientY - view.y) / oldScale;
  const nextScale = Math.max(0.35, Math.min(2.4, oldScale * Math.exp(-event.deltaY * 0.001)));
  view.x = event.clientX - worldX * nextScale;
  view.y = event.clientY - worldY * nextScale;
  view.scale = nextScale;
  applyView();
  postViewportChanged();
}, { passive: false });

	window.addEventListener("resize", () => {
	  hideNodeContextMenu();
	  resizeCanvas();
	});

window.addEventListener("message", event => {
  handleHostMessage(event.data);
});

if (window.chrome?.webview) {
  window.chrome.webview.addEventListener("message", event => {
    handleHostMessage(event.data);
  });
}

renderNodes();
resizeCanvas();
applyView();
</script>
</body>
</html>
""";
    }
}
