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
			common.pill(common.tr('Not installed', 'Не установлен'), 'neutral') :
			snapshot.running === snapshot.installed && snapshot.listening === snapshot.running ?
				common.pill(common.tr('Running', 'Работает'), 'good') :
				common.pill(common.tr('Needs attention', 'Нужно внимание'), 'warn');
		return E('div', {}, [
			common.styles(),
			E('div', { 'class': 'mtproto-page' }, [
				E('div', { 'class': 'mtproto-overview' }, [
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('Active clients', 'Активные клиенты') ]),
						E('b', {}, [ String(snapshot.clients) ])
					]),
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('TCP connections', 'TCP-подключения') ]),
						E('b', {}, [ String(snapshot.connections) ])
					]),
					E('div', { 'class': 'mtproto-overview-stat' }, [
						E('span', {}, [ common.tr('Proxy status', 'Статус прокси') ]),
						E('div', { 'style': 'margin-top:.35rem' }, [ state ])
					])
				]),
				E('div', { 'class': 'mtproto-widget-footer' }, [
					E('a', {
						'class': 'mtproto-quick-link',
						'href': L.url('admin', 'status', 'mtproto-monitor')
					}, [
						common.tr('Open detailed monitor', 'Открыть подробный монитор')
					])
				])
			])
		]);
	}
});
