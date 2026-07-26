'use strict';
'require baseclass';
'require fs';
'require mtproto-monitor.shared as common';

var helper = '/usr/libexec/mtproto-monitor';

return baseclass.extend({
	title: 'MTProto',
	load: function() {
		return L.resolveDefault(fs.exec(helper, [ 'status' ]), { stdout: '' });
	},
	render: function(data) {
		var snapshot = common.parse(data.stdout);
		var state = snapshot.installed === 0 ?
			common.pill(common.tr('Not installed'), 'neutral') :
			snapshot.running === snapshot.installed && snapshot.listening === snapshot.running ?
				common.pill(common.tr('Running'), 'good') :
				common.pill(common.tr('Needs attention'), 'warn');
		return E('div', {}, [
			common.styles(),
			E('div', { 'class': 'mtproto-page' }, [
				E('div', { 'class': 'mtproto-overview' }, [
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('Active clients') ]),
						E('b', {}, [ String(snapshot.clients) ])
					]),
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('TCP connections') ]),
						E('b', {}, [ String(snapshot.connections) ])
					]),
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('Proxy status') ]),
						E('div', { 'style': 'margin-top:.35rem' }, [ state ])
					])
				]),
				E('div', { 'class': 'mtproto-widget-footer' }, [
					E('a', {
						'class': 'mtproto-quick-link',
						'href': L.url('admin', 'status', 'mtproto-monitor')
					}, [
						common.tr('Open detailed monitor')
					])
				])
			])
		]);
	}
});
