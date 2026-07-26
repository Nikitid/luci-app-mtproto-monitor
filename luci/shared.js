'use strict';
'require baseclass';

/* Translations come from the bundled gettext catalogues in
 * /usr/lib/lua/luci/i18n, looked up through LuCI's own _() in cbi.js.
 *
 * Every key carries this context. LuCI merges every installed catalogue into
 * one window.TR table keyed by a hash of the string, in an unspecified order,
 * so a msgid shared with another catalogue either loses to it or silently
 * takes it over. "Connections" already collides that way: luci-base
 * translates it as "Соединения" while this page means "Подключения". A
 * context makes each key ours alone and keeps the collision impossible. */
var CONTEXT = 'mtproto-monitor';

function tr(text) {
	return _(text, CONTEXT);
}

function parse(stdout) {
	var result = { instances: [] };
	(stdout || '').replace(/\r/g, '').split('\n').forEach(function(line) {
		if (line.indexOf('instance=') === 0) {
			var fields = line.split('\t');
			var protection = (fields[10] || 'missing/missing').split('/');
			result.instances.push({
				key: fields[0].slice(9),
				label: fields[1] || '',
				service: fields[2] || '',
				version: fields[3] || 'unknown',
				protocol: fields[4] || '',
				port: Number(fields[5]) || 0,
				state: fields[6] || 'stopped',
				listening: fields[7] === '1',
				clients: Number(fields[8]) || 0,
				connections: Number(fields[9]) || 0,
				firewall: protection[0] || 'missing',
				upnp: protection[1] || 'missing'
			});
			return;
		}
		var equal = line.indexOf('=');
		if (equal > 0)
			result[line.slice(0, equal)] = line.slice(equal + 1);
	});
	[ 'timestamp', 'installed', 'running', 'listening', 'clients', 'connections' ]
		.forEach(function(key) { result[key] = Number(result[key]) || 0; });
	return result;
}

function parseHistory(stdout) {
	return (stdout || '').replace(/\r/g, '').split('\n').map(function(line) {
		var fields = line.split('\t');
		if (fields.length < 3)
			return null;
		return {
			timestamp: Number(fields[0]) || 0,
			clients: Number(fields[1]) || 0,
			connections: Number(fields[2]) || 0
		};
	}).filter(Boolean);
}

function pill(text, tone) {
	return E('span', { 'class': 'mtproto-pill ' + (tone || 'neutral') }, [ text ]);
}

function styles() {
	return E('style', {}, [ `
		.mtproto-page {
			--mtp-accent: #4f7dff;
			--mtp-accent-2: #8b5cf6;
			--mtp-grad: linear-gradient(135deg, #4f7dff, #8b5cf6);
			--mtp-border: rgba(128, 128, 128, .22);
			--mtp-border-strong: rgba(128, 128, 128, .34);
			--mtp-surface: rgba(128, 128, 128, .06);
			--mtp-surface-2: rgba(128, 128, 128, .11);
			--mtp-muted: rgba(128, 128, 128, .85);
			--mtp-good: #16a34a;
			--mtp-warn: #d97706;
			--mtp-bad: #e11d48;
			--mtp-info: #2f6fbe;
			--mtp-radius: 16px;
			--mtp-radius-sm: 11px;
			--mtp-shadow: 0 1px 2px rgba(0, 0, 0, .05),
				0 10px 30px -18px rgba(0, 0, 0, .45);
			max-width: 1220px;
		}
		.mtproto-page * { box-sizing: border-box; }
		.mtproto-header {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: 1rem;
			margin: 0 0 1.4rem;
		}
		.mtproto-header h2 {
			margin: 0 0 .35rem;
			font-size: clamp(1.45rem, 2.6vw, 1.85rem);
			font-weight: 750;
			letter-spacing: -.015em;
		}
		.mtproto-subtitle, .mtproto-muted {
			color: var(--mtp-muted);
			line-height: 1.5;
		}
		.mtproto-subtitle { margin: 0; max-width: 780px; }
		.mtproto-grid {
			display: grid;
			grid-template-columns: repeat(12, minmax(0, 1fr));
			gap: 1rem;
			margin: 1rem 0;
		}
		.mtproto-card {
			grid-column: span 6;
			position: relative;
			overflow: hidden;
			min-width: 0;
			padding: 1.1rem 1.15rem;
			border: 1px solid var(--mtp-border);
			border-radius: var(--mtp-radius);
			background: var(--mtp-surface);
			box-shadow: var(--mtp-shadow);
		}
		.mtproto-card::before {
			content: "";
			position: absolute;
			inset: 0 0 auto;
			height: 3px;
			background: var(--mtp-grad);
			opacity: .55;
		}
		.mtproto-card-label {
			margin-bottom: .5rem;
			color: var(--mtp-muted);
			font-size: .72rem;
			font-weight: 650;
			letter-spacing: .07em;
			text-transform: uppercase;
		}
		.mtproto-card-value {
			font-size: clamp(1.4rem, 2.4vw, 1.7rem);
			font-weight: 740;
			line-height: 1.15;
			font-variant-numeric: tabular-nums;
		}
		.mtproto-card-detail {
			margin-top: .5rem;
			color: var(--mtp-muted);
			font-size: .84rem;
			line-height: 1.45;
		}
		.mtproto-section {
			margin: 1rem 0;
			padding: 1.2rem 1.3rem;
			border: 1px solid var(--mtp-border);
			border-radius: var(--mtp-radius);
			background: var(--mtp-surface);
			box-shadow: var(--mtp-shadow);
		}
		.mtproto-section-head {
			display: flex;
			align-items: flex-start;
			justify-content: space-between;
			gap: 1rem;
			margin-bottom: 1rem;
		}
		.mtproto-section-head h3 { margin: 0 0 .3rem; }
		.mtproto-section-head p { margin: 0; color: var(--mtp-muted); }
		.mtproto-pill {
			display: inline-flex;
			align-items: center;
			gap: .4rem;
			padding: .26rem .65rem;
			border: 1px solid color-mix(in srgb, currentColor 30%, transparent);
			border-radius: 999px;
			background: color-mix(in srgb, currentColor 12%, transparent);
			font-size: .78rem;
			font-weight: 660;
			white-space: nowrap;
		}
		.mtproto-pill::before {
			content: "";
			width: .48rem;
			height: .48rem;
			border-radius: 50%;
			background: currentColor;
		}
		.mtproto-pill.good { color: var(--mtp-good); }
		.mtproto-pill.warn { color: var(--mtp-warn); }
		.mtproto-pill.bad { color: var(--mtp-bad); }
		.mtproto-pill.info { color: var(--mtp-info); }
		.mtproto-pill.neutral { color: var(--mtp-muted); }
		.mtproto-chart {
			display: block;
			width: 100%;
			height: 180px;
			border: 1px solid var(--mtp-border);
			border-radius: var(--mtp-radius-sm);
			background: color-mix(in srgb, currentColor 2%, transparent);
		}
		.mtproto-chart-grid {
			stroke: var(--mtp-border);
			stroke-width: 1;
		}
		.mtproto-chart-clients {
			fill: none;
			stroke: var(--mtp-accent);
			stroke-width: 3;
			vector-effect: non-scaling-stroke;
		}
		.mtproto-chart-connections {
			fill: none;
			stroke: var(--mtp-accent-2);
			stroke-width: 2;
			opacity: .72;
			vector-effect: non-scaling-stroke;
		}
		.mtproto-legend {
			display: flex;
			flex-wrap: wrap;
			gap: .5rem 1rem;
			margin-top: .65rem;
			color: var(--mtp-muted);
			font-size: .82rem;
		}
		.mtproto-legend b { color: inherit; }
		.mtproto-legend b.clients { color: var(--mtp-accent); }
		.mtproto-legend b.connections { color: var(--mtp-accent-2); }
		.mtproto-table { width: 100%; border-collapse: collapse; }
		.mtproto-table th, .mtproto-table td {
			padding: .65rem .45rem;
			border-top: 1px solid var(--mtp-border);
			text-align: left;
			vertical-align: middle;
		}
		.mtproto-table thead th {
			border-top: 0;
			color: var(--mtp-muted);
			font-size: .74rem;
			text-transform: uppercase;
		}
		.mtproto-table td.numeric { font-variant-numeric: tabular-nums; }
		.mtproto-instance-action {
			display: flex;
			align-items: center;
			justify-content: flex-end;
			flex-wrap: wrap;
			gap: .5rem;
			min-width: 15rem;
		}
		.mtproto-instance-result {
			flex-basis: 100%;
			color: var(--mtp-muted);
			font-size: .78rem;
			line-height: 1.35;
			text-align: right;
		}
		.mtproto-instance-result.good { color: var(--mtp-good); }
		.mtproto-instance-result.bad { color: var(--mtp-bad); }
		.mtproto-actions {
			display: flex;
			align-items: center;
			flex-wrap: wrap;
			gap: .6rem;
		}
		.mtproto-result { min-height: 1.4em; color: var(--mtp-muted); }
		.mtproto-result.good { color: var(--mtp-good); }
		.mtproto-result.bad { color: var(--mtp-bad); }
		.mtproto-note {
			padding: .85rem 1rem;
			border: 1px solid color-mix(in srgb, var(--mtp-info) 30%, var(--mtp-border));
			border-left: .26rem solid var(--mtp-info);
			border-radius: var(--mtp-radius-sm);
			background: color-mix(in srgb, var(--mtp-info) 7%, transparent);
			line-height: 1.5;
		}
		.mtproto-page .cbi-button {
			padding: .5rem .8rem;
			border: 1px solid var(--mtp-border);
			border-radius: var(--mtp-radius-sm);
			background: var(--mtp-surface-2);
			font-weight: 620;
			line-height: 1.2;
			cursor: pointer;
			transition: transform .12s ease, background .14s ease,
				border-color .14s ease, filter .14s ease;
		}
		.mtproto-page .cbi-button:hover {
			border-color: var(--mtp-border-strong);
			transform: translateY(-1px);
		}
		.mtproto-page .cbi-button-positive,
		.mtproto-page .cbi-button-apply {
			border-color: transparent;
			background-image: var(--mtp-grad);
			color: #fff;
		}
		.mtproto-page .cbi-button-positive:hover,
		.mtproto-page .cbi-button-apply:hover {
			background-image: var(--mtp-grad);
			filter: brightness(1.06);
		}
		.mtproto-page .cbi-button-negative {
			border-color: color-mix(in srgb, var(--mtp-bad) 40%, var(--mtp-border));
			color: var(--mtp-bad);
		}
		.mtproto-page .cbi-button-negative:hover {
			background: color-mix(in srgb, var(--mtp-bad) 12%, transparent);
		}
		.mtproto-page button[disabled] {
			opacity: .55;
			cursor: wait;
			transform: none;
		}
		.mtproto-overview {
			--mtp-good: #16a34a;
			--mtp-warn: #d97706;
			--mtp-bad: #e11d48;
			--mtp-muted: rgba(128, 128, 128, .85);
			display: grid;
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: .75rem;
		}
		.mtproto-overview-stat {
			padding: .75rem .8rem;
			border: 1px solid rgba(128, 128, 128, .22);
			border-radius: 11px;
			background: rgba(128, 128, 128, .06);
		}
		.mtproto-overview-stat span {
			display: block;
			color: var(--mtp-muted);
			font-size: .75rem;
		}
		.mtproto-overview-stat b {
			display: block;
			margin-top: .2rem;
			font-size: 1.25rem;
			font-variant-numeric: tabular-nums;
		}
		.mtproto-widget-footer {
			display: flex;
			justify-content: flex-end;
			margin-top: .75rem;
		}
		.mtproto-quick-link {
			display: inline-flex;
			align-items: center;
			min-height: 2.3rem;
			padding: .45rem .85rem;
			border: 1px solid var(--mtp-border);
			border-radius: var(--mtp-radius-sm);
			background: color-mix(in srgb, currentColor 5%, transparent);
			text-decoration: none;
			font-weight: 620;
			transition: background .14s ease, transform .14s ease,
				border-color .14s ease;
		}
		.mtproto-quick-link:hover {
			background: var(--mtp-surface-2);
			border-color: var(--mtp-border-strong);
			transform: translateY(-1px);
		}
		@media (max-width: 900px) {
			.mtproto-card { grid-column: 1 / -1; }
		}
		@media (max-width: 600px) {
			.mtproto-header, .mtproto-section-head { flex-direction: column; }
			.mtproto-card { grid-column: 1 / -1; }
			.mtproto-overview { grid-template-columns: 1fr; }
			.mtproto-table { display: block; overflow-x: auto; }
		}
	` ]);
}

return baseclass.extend({
	tr: tr,
	parse: parse,
	parseHistory: parseHistory,
	pill: pill,
	styles: styles
});
