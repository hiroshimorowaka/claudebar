// Claude usage in the GNOME taskbar.
//
// The data and the usage card live in Quickshell (~/.local/share/claudebar/
// quickshell). That process writes what the icon shows — label, colors,
// stale mark, alert dot, tooltip, style — to $XDG_RUNTIME_DIR/claudebar.json.
// This extension draws it and forwards clicks.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const WIDGET = GLib.build_filenamev([GLib.get_user_data_dir(), 'claudebar', 'quickshell']);
const STATE = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'claudebar.json']);
const USAGE_URL = 'https://claude.ai/settings/usage';
const DIM = '#828484';

export default class ClaudebarExtension extends Extension {
    enable() {
        this._button = new PanelMenu.Button(0.5, 'Claudebar', true);

        const center = Clutter.ActorAlign.CENTER;
        const box = new St.BoxLayout({style_class: 'claudebar-box', y_align: center});
        this._icon = new St.Label({text: '', style_class: 'claudebar-icon', y_align: center});
        this._label = new St.Label({style_class: 'claudebar-label', y_align: center, visible: false});
        this._stale = new St.Label({text: '', style_class: 'claudebar-stale', y_align: center, visible: false});
        this._dot = new St.Widget({style_class: 'claudebar-dot', y_align: center, visible: false});
        for (const child of [this._icon, this._label, this._stale, this._dot])
            box.add_child(child);
        this._button.add_child(box);

        this._button.connect('button-press-event', (_actor, event) => this._onPress(event.get_button()));
        this._button.connect('notify::hover', () => this._syncTooltip());

        this._tooltip = new St.Label({style_class: 'claudebar-tooltip', visible: false});
        Main.layoutManager.addTopChrome(this._tooltip);

        Main.panel.addToStatusArea(this.uuid, this._button, 0, 'right');

        this._file = Gio.File.new_for_path(STATE);
        this._monitor = this._file.monitor_file(Gio.FileMonitorFlags.WATCH_MOVES, null);
        this._monitor.connect('changed', () => this._scheduleLoad());
        this._state = null;
        this._load();
    }

    disable() {
        if (this._loadId)
            GLib.source_remove(this._loadId);
        this._loadId = 0;
        this._monitor?.cancel();
        this._monitor = null;
        this._file = null;
        this._tooltip?.destroy();
        this._tooltip = null;
        this._button?.destroy();
        this._button = null;
        this._state = null;
    }

    _scheduleLoad() {
        if (this._loadId)
            return;
        this._loadId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 50, () => {
            this._loadId = 0;
            this._load();
            return GLib.SOURCE_REMOVE;
        });
    }

    _load() {
        try {
            const [, bytes] = this._file.load_contents(null);
            this._state = JSON.parse(new TextDecoder().decode(bytes));
        } catch (e) {
            this._state = null;
        }
        this._render();
    }

    // Glyph and label in the gauge color of the value shown, a pause mark for
    // cached data, a dot when another window is critical. Dim before any data.
    _render() {
        const s = this._state ?? {};
        const font = s.style?.fontFamily ? `font-family: "${s.style.fontFamily}";` : '';
        const color = s.color ?? DIM;
        this._icon.style = `color: ${color};`;
        this._label.text = s.label ?? '';
        this._label.style = `color: ${color}; ${font}`;
        this._label.visible = this._label.text !== '';
        this._stale.visible = !!s.stale;
        this._stale.style = `color: ${s.staleColor ?? DIM}; ${font}`;
        this._dot.visible = !!s.alert;
        this._dot.style = `background-color: ${s.alertColor ?? DIM};`;
        this._tooltip.style = `${font} color: ${s.style?.foreground ?? '#cacccc'}; ` +
            `background-color: ${s.style?.background ?? '#101315'}; ` +
            `border-color: ${s.style?.foreground ?? '#cacccc'}; border-radius: ${s.style?.radius ?? 0}px;`;
        this._syncTooltip();
    }

    _syncTooltip() {
        const text = this._state?.tooltip ?? '';
        if (!this._button.hover || text === '') {
            this._tooltip.hide();
            return;
        }
        this._tooltip.text = text;
        const [x, y] = this._button.get_transformed_position();
        const [, , width, height] = this._tooltip.get_preferred_size();
        const monitor = Main.layoutManager.findMonitorForActor(this._button);
        const bar = this._barGeometry();
        const left = Math.min(Math.max(monitor.x, x + this._button.width / 2 - width / 2), monitor.x + monitor.width - width);
        const top = bar.position === 'top' ? bar.edge + 6 : y - height - 6;
        this._tooltip.set_position(Math.round(left), Math.round(top));
        this._tooltip.show();
    }

    _onPress(button) {
        if (button === Clutter.BUTTON_PRIMARY) {
            const [x] = this._button.get_transformed_position();
            const bar = this._barGeometry();
            this._run(['qs', '-p', WIDGET, 'ipc', 'call', 'claudebar', 'toggleAt',
                String(Math.round(x + this._button.width / 2)), String(Math.round(bar.edge)),
                String(Math.round(bar.size)), bar.position]);
        } else if (button === Clutter.BUTTON_MIDDLE) {
            this._run(['qs', '-p', WIDGET, 'ipc', 'call', 'claudebar', 'refresh']);
        } else if (button === Clutter.BUTTON_SECONDARY) {
            this._run(['xdg-open', USAGE_URL]);
        }
        return Clutter.EVENT_STOP;
    }

    // The taskbar is the button's outermost ancestor below the UI group. The
    // half of the monitor it sits in tells a top bar from a bottom bar.
    _barGeometry() {
        let actor = this._button;
        while (actor.get_parent() && actor.get_parent() !== Main.layoutManager.uiGroup)
            actor = actor.get_parent();
        const [, top] = actor.get_transformed_position();
        const size = actor.height;
        const monitor = Main.layoutManager.findMonitorForActor(this._button);
        const isTop = top + size / 2 < monitor.y + monitor.height / 2;
        return {position: isTop ? 'top' : 'bottom', edge: isTop ? top + size : top, size};
    }

    _run(argv) {
        try {
            GLib.spawn_async(null, argv, null, GLib.SpawnFlags.SEARCH_PATH, null);
        } catch (e) {
            console.error(`claudebar: ${argv[0]} failed: ${e.message}`);
        }
    }
}
