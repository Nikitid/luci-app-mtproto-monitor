'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require mtproto-monitor.shared as common';

var helper = '/usr/libexec/mtproto-monitor';
var firewallBusyPort = null;
var firewallFeedback = {};

/* A result line is a report on an action just taken, not instance state. The
 * table is rebuilt every poll, so without an expiry the line stays under the
 * row until the page is reloaded. */
var feedbackTimeout = 15000;

function setFeedback(port, tone, text, pending) {
	firewallFeedback[port] = {
		tone: tone,
		text: text,
		until: pending ? Infinity : Date.now() + feedbackTimeout
	};
}

function currentFeedback(port) {
	var feedback = firewallFeedback[port];
	if (!feedback)
		return null;
	if (Date.now() > feedback.until) {
		delete firewallFeedback[port];
		return null;
	}
	return feedback;
}

function chart(history) {
	var width = 1000;
	var height = 180;
	var padding = 14;
	var maximum = Math.max(1, history.reduce(function(max, point) {
		return Math.max(max, point.clients, point.connections);
	}, 0));

	function points(key) {
		if (!history.length)
			return '';
		return history.map(function(point, index) {
			var x = history.length === 1 ? width / 2 :
				padding + index * (width - padding * 2) / (history.length - 1);
			var y = height - padding - point[key] * (height - padding * 2) / maximum;
			return x.toFixed(1) + ',' + y.toFixed(1);
		}).join(' ');
	}

	return E('div', {}, [
		E('svg', {
			'class': 'mtproto-chart',
			'viewBox': '0 0 ' + width + ' ' + height,
			'preserveAspectRatio': 'none',
			'role': 'img',
			'aria-label': common.tr('Client and connection history')
		}, [
			E('line', { 'class': 'mtproto-chart-grid', x1: 0, y1: height / 2, x2: width, y2: height / 2 }),
			E('polyline', { 'class': 'mtproto-chart-connections', 'points': points('connections') }),
			E('polyline', { 'class': 'mtproto-chart-clients', 'points': points('clients') })
		]),
		E('div', { 'class': 'mtproto-legend' }, [
			E('span', {}, [ E('b', { 'class': 'clients' }, [ '● ' ]), common.tr('Unique active clients') ]),
			E('span', {}, [ E('b', { 'class': 'connections' }, [ '◆ ' ]), common.tr('Active TCP connections') ]),
			E('span', {}, [ common.tr('Last 30 minutes; refreshes every 5 seconds.') ])
		])
	]);
}

function statePill(instance) {
	if (instance.state !== 'running')
		return common.pill(common.tr('Stopped'), 'bad');
	if (!instance.listening)
		return common.pill(common.tr('Not listening'), 'warn');
	return common.pill(common.tr('Running'), 'good');
}

function protectionPill(instance) {
	if (instance.firewall !== 'active')
		return common.pill(common.tr('WAN closed'), 'bad');
	if (instance.upnp === 'missing')
		return common.pill(common.tr('Open · UPnP conflict'), 'warn');
	return common.pill(common.tr('WAN open'), 'good');
}

function firewallAction(instance, open) {
	firewallBusyPort = instance.port;
	setFeedback(instance.port, '',
		common.tr('Applying firewall settings…'), true);
	refreshPage();
	return fs.exec(helper, [ open ? 'firewall-open' : 'firewall-close', String(instance.port) ])
		.then(function(response) {
			setFeedback(instance.port, 'good', (response.stdout || (open ?
				common.tr('WAN access opened.') :
				common.tr('WAN access closed.'))).trim());
		})
		.catch(function(error) {
			setFeedback(instance.port, 'bad', error.message || common.tr('Unable to change WAN access.'));
		})
		.finally(function() {
			firewallBusyPort = null;
			refreshPage();
		});
}

function confirmFirewallAction(instance, open) {
	var cancel = E('button', {
		'class': 'cbi-button',
		'click': ui.hideModal
	}, [ common.tr('Cancel') ]);
	var confirm = E('button', {
		'class': 'cbi-button ' + (open ? 'cbi-button-positive' : 'cbi-button-negative'),
		'click': function() {
			ui.hideModal();
			firewallAction(instance, open);
		}
	}, [ open ?
		common.tr('Open WAN access') :
		common.tr('Close WAN access')
	]);
	ui.showModal(open ?
		common.tr('Open proxy port') :
		common.tr('Close proxy port'), [
		E('p', {}, [ open ?
			common.tr('Allow new TCP connections from WAN to port %d for %s?').format(instance.port, instance.label) :
			common.tr('Block new TCP connections from WAN to port %d for %s? Existing sessions may continue until they disconnect.').format(instance.port, instance.label)
		]),
		E('div', { 'class': 'right' }, [ cancel, ' ', confirm ])
	]);
}

function instanceRows(snapshot) {
	if (!snapshot.instances.length) {
		return E('tr', {}, [
			E('td', { 'colspan': 7, 'class': 'mtproto-muted' }, [
				common.tr('No supported proxy installation detected.')
			])
		]);
	}
	return snapshot.instances.map(function(instance) {
		var open = instance.firewall !== 'active';
		var busy = firewallBusyPort != null;
		var feedback = currentFeedback(instance.port);
		var button = E('button', {
			'class': 'cbi-button ' + (open ? 'cbi-button-positive' : 'cbi-button-negative'),
			'disabled': busy ? '' : null,
			'click': function() { confirmFirewallAction(instance, open); }
		}, [ firewallBusyPort === instance.port ?
			common.tr('Applying…') :
			open ?
				common.tr('Open WAN access') :
				common.tr('Close WAN access')
		]);
		return E('tr', {}, [
			E('td', {}, [
				E('strong', {}, [ instance.label ]),
				E('div', { 'class': 'mtproto-muted' }, [ instance.service + ' · ' + instance.version ])
			]),
			E('td', {}, [ statePill(instance) ]),
			E('td', {}, [ instance.protocol ]),
			E('td', { 'class': 'numeric' }, [ String(instance.port) ]),
			E('td', { 'class': 'numeric' }, [ String(instance.clients) ]),
			E('td', { 'class': 'numeric' }, [ String(instance.connections) ]),
			E('td', {}, [
				E('div', { 'class': 'mtproto-instance-action' }, [
					protectionPill(instance),
					button,
					feedback ? E('div', {
						'class': 'mtproto-instance-result ' + feedback.tone
					}, [ feedback.text ]) : ''
				])
			])
		]);
	});
}

function renderPage(snapshot, history) {
	var servicePill = snapshot.running === snapshot.installed && snapshot.installed > 0 ?
		common.pill(common.tr('Healthy'), 'good') :
		common.pill(snapshot.installed ?
			common.tr('Needs attention') :
			common.tr('Not installed'), snapshot.installed ? 'warn' : 'neutral');
	var page = E('div', { 'class': 'mtproto-page' }, [
		common.styles(),
		E('div', { 'class': 'mtproto-header' }, [
			E('div', {}, [
				E('h2', {}, [ 'MTProto Monitor' ]),
				E('p', { 'class': 'mtproto-subtitle' }, [
					common.tr('Unique active clients are deduplicated by remote network address. Connection count remains a secondary transport metric.')
				])
			]),
			servicePill
		]),
		E('div', { 'class': 'mtproto-grid' }, [
			E('div', { 'class': 'mtproto-card' }, [
				E('div', { 'class': 'mtproto-card-label' }, [ common.tr('Clients now') ]),
				E('div', { 'class': 'mtproto-card-value', 'id': 'mtp-clients' }, [ String(snapshot.clients) ]),
				E('div', { 'class': 'mtproto-card-detail' }, [ common.tr('Unique active addresses') ])
			]),
			E('div', { 'class': 'mtproto-card' }, [
				E('div', { 'class': 'mtproto-card-label' }, [ common.tr('Connections now') ]),
				E('div', { 'class': 'mtproto-card-value', 'id': 'mtp-connections' }, [ String(snapshot.connections) ]),
				E('div', { 'class': 'mtproto-card-detail' }, [ common.tr('Established inbound TCP') ])
			])
		]),
		E('div', { 'class': 'mtproto-section', 'id': 'mtp-history' }, [
			E('div', { 'class': 'mtproto-section-head' }, [
				E('div', {}, [
					E('h3', {}, [ common.tr('Activity') ]),
					E('p', {}, [ common.tr('Sanitized aggregate history; client addresses are never stored.') ])
				])
			]),
			chart(history)
		]),
		E('div', { 'class': 'mtproto-section' }, [
			E('div', { 'class': 'mtproto-section-head' }, [
				E('div', {}, [
					E('h3', {}, [ common.tr('Proxy instances') ]),
					E('p', {}, [ common.tr('Package Go, legacy Go/SOCKS5 and Rust layouts are detected automatically.') ])
				])
			]),
			E('table', { 'class': 'mtproto-table' }, [
				E('thead', {}, [ E('tr', {}, [
					E('th', {}, [ common.tr('Implementation') ]),
					E('th', {}, [ common.tr('Status') ]),
					E('th', {}, [ common.tr('Protocol') ]),
					E('th', {}, [ common.tr('Port') ]),
					E('th', {}, [ common.tr('Clients') ]),
					E('th', {}, [ common.tr('Connections') ]),
					E('th', { 'class': 'right' }, [ common.tr('WAN access') ])
				]) ]),
				E('tbody', { 'id': 'mtp-instance-rows' }, instanceRows(snapshot))
			])
		])
	]);
	return page;
}

function refreshPage() {
	return Promise.all([
		L.resolveDefault(fs.exec(helper, [ 'status' ]), { stdout: '' }),
		L.resolveDefault(fs.exec(helper, [ 'history' ]), { stdout: '' })
	]).then(function(data) {
		var snapshot = common.parse(data[0].stdout);
		var history = common.parseHistory(data[1].stdout);
		var clients = document.getElementById('mtp-clients');
		if (!clients)
			return;
		clients.textContent = snapshot.clients;
		document.getElementById('mtp-connections').textContent = snapshot.connections;
		document.getElementById('mtp-instance-rows').replaceChildren.apply(
			document.getElementById('mtp-instance-rows'), instanceRows(snapshot));
		var historyNode = document.getElementById('mtp-history');
		historyNode.replaceChild(chart(history), historyNode.lastElementChild);
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec(helper, [ 'status' ]), { stdout: '' }),
			L.resolveDefault(fs.exec(helper, [ 'history' ]), { stdout: '' })
		]);
	},
	render: function(data) {
		poll.add(refreshPage, 5);
		return renderPage(common.parse(data[0].stdout), common.parseHistory(data[1].stdout));
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
