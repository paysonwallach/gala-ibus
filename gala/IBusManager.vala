/*
 * gala-ibus
 *
 * Copyright © 2020 Payson Wallach
 *
 * Released under the terms of the GNU General Public License v3.0
 * (https://gnu.org/licenses/gpl.html)
 */

namespace GalaIBus {
    public class IBusManager : Object {
        private const int MAX_INTPUT_SOURCE_ACTIVATION_TIME = 4000; // ms
        private const int PRELOAD_ENGINES_DELAY_TIME = 30; // sec

        private CandidatePopup candidate_popup;
        private IBus.Bus ibus;
        private IBus.PanelService panel_service;
        private Gee.HashMap<string, IBus.EngineDesc> engines;
        private string? current_engine_name;
        private uint preload_engines_id;
        private ulong register_properties_id;
        private Cancellable? cancellable;
        private bool is_ready;

        public delegate void SetEngineCallbackType ();

        public signal void ready (bool state);
        public signal void set_cursor_location (int x, int y, int width, int height);
        public signal void focus_in ();
        public signal void focus_out ();
        public signal void set_content_type (uint purpose, uint hints);
        public signal void properties_registered (string current_engine_name, IBus.PropList properties_list);
        public signal void property_updated (string current_engine_name, IBus.Property prop);

        public IBusManager () {
            Object ();
        }

        construct {
            IBus.init ();

            candidate_popup = new CandidatePopup ();
            engines = new Gee.HashMap<string, IBus.EngineDesc> ();
            is_ready = false;
            register_properties_id = 0;
            current_engine_name = null;
            preload_engines_id = 0U;

            ibus = new IBus.Bus.async ();

            ibus.connected.connect (on_connected);
            ibus.disconnected.connect (on_disconnected);
            ibus.set_watch_ibus_signal (true);
            ibus.global_engine_changed.connect (on_engine_changed);

            spawn_ibus_daemon ();
        }

        private void spawn_ibus_daemon (...) {
            try {
                var subprocess = new Subprocess (SubprocessFlags.NONE, "ibus-daemon", "--panel", "disable", va_list ());
            } catch (Error err) {
                warning (@"Failed to spawn ibus-daemon: $(err.message)");
            }
        }

        private void update_readiness () {
            is_ready = engines.size > 0 && panel_service != null;
            ready (is_ready);
        }

        private void on_connected () {
            cancellable = new Cancellable ();

            ibus.list_engines_async.begin (-1, cancellable, (_, result) => {
                try {
                    foreach (var engine in ibus.list_engines_async_finish (result)) {
                        engines.set (engine.get_name (), engine);
                    }
                    update_readiness ();
                } catch (Error err) {
                    if (err.matches (IOError.quark (), IOError.CANCELLED))
                        return;

                    warning (err.message);

                    on_disconnected ();
                }
            });
            ibus.request_name_async.begin (
                IBus.SERVICE_PANEL, IBus.BusNameFlag.REPLACE_EXISTING,
                -1, cancellable, (_, result) => {
                var success = false;

                try {
                    success = (bool) ibus.request_name_async_finish (result);
                } catch (Error err) {
                    if (err.matches (IOError.quark (), IOError.CANCELLED))
                        return;

                    warning (err.message);
                }

                if (success) {
                    panel_service = new IBus.PanelService (ibus.get_connection ());

                    candidate_popup.set_panel_service (panel_service);
                    panel_service.update_property.connect (on_update_property);
                    panel_service.set_cursor_location.connect ((x, y, width, height) => {
                        set_cursor_location (x, y, width, height);
                    });
                    panel_service.focus_in.connect ((input_context_path) => {
                        if (input_context_path.has_suffix ("InputContext_1"))
                            focus_in ();
                    });
                    panel_service.focus_out.connect ((input_context_path) => {
                        focus_out ();
                    });

                    try {
                        check_ibus_version (1, 5, 10);
                        panel_service.set_content_type.connect ((purpose, hints) => {
                            set_content_type (purpose, hints);
                        });
                    } catch (Error err) {
                        warning (err.message);
                    }

                    ibus.get_global_engine_async.begin (-1, cancellable, (bus, result) => {
                        IBus.EngineDesc engine;

                        try {
                            engine = ibus.get_global_engine_async_finish (result);

                            if (engine != null)
                                return;
                        } catch (Error err) {
                            return;
                        }
                        on_engine_changed (engine.get_name ());
                    });

                    update_readiness ();
                } else {
                    on_disconnected ();
                }
            });
        }

        private void on_disconnected () {
            if (cancellable != null) {
                cancellable.cancel ();
                cancellable = null;
            }

            if (preload_engines_id != 0) {
                Source.remove (preload_engines_id);
                preload_engines_id = 0U;
            }

            if (panel_service != null)
                panel_service.destroy ();

            panel_service = null;
            candidate_popup.set_panel_service (null);
            engines.clear ();
            is_ready = false;
            register_properties_id = 0;
            current_engine_name = null;

            ready (false);
        }

        private void on_engine_changed (string name) {
            if (!is_ready)
                return;

            current_engine_name = name;

            if (register_properties_id != 0)
                return;

            register_properties_id = panel_service.register_properties.connect ((properties_list) => {
                if (properties_list.@get (0) != null)
                    return;

                panel_service.disconnect (register_properties_id);
                register_properties_id = 0;

                properties_registered (current_engine_name, properties_list);
            });
        }

        private void on_update_property (IBus.Property prop) {
            property_updated (current_engine_name, prop);
        }

        private void check_ibus_version (int minimum_required_major, int minimum_required_minor, int minimum_required_micro) {
            if ((IBus.MAJOR_VERSION > minimum_required_major) ||
                (IBus.MAJOR_VERSION == minimum_required_major && IBus.MINOR_VERSION > minimum_required_minor) ||
                (IBus.MAJOR_VERSION == minimum_required_major && IBus.MINOR_VERSION == minimum_required_minor &&
                 IBus.MICRO_VERSION >= minimum_required_micro))
                return;

            error (@"Found IBus version $(IBus.MAJOR_VERSION).$(IBus.MINOR_VERSION).$(IBus.MICRO_VERSION) but required is $minimum_required_major.$minimum_required_minor.$minimum_required_micro");
        }

        public void restart_daemon (...) {
            spawn_ibus_daemon ("-r", va_list ());
        }

        public void activate_property (string name, uint state) {
            panel_service.property_activate (name, state);
        }

        public IBus.EngineDesc? get_engine_desc (string id) {
            if (!is_ready || engines.has_key (id))
                return null;

            return engines.@get (id);
        }

        public void set_engine (string id, SetEngineCallbackType? callback = null) {
            if (!is_ready) {
                if (callback != null)
                    callback ();
                return;
            }

            ibus.set_global_engine_async.begin (id, MAX_INTPUT_SOURCE_ACTIVATION_TIME, cancellable, (_, result) => {
                try {
                    ibus.set_global_engine_async_finish (result);
                } catch (Error err) {
                    if (!err.matches (IOError.quark (), IOError.CANCELLED))
                        warning (err.message);
                }

                if (callback != null)
                    callback ();
            });
        }

        public void preload_engines (string[] ids) {
            if (ibus != null || ids.length == 0)
                return;

            if (preload_engines_id != 0) {
                Source.remove (preload_engines_id);
                preload_engines_id = 0U;
            }

            preload_engines_id = Timeout.add_seconds (PRELOAD_ENGINES_DELAY_TIME, () => {
                ibus.preload_engines_async.begin (ids, -1, cancellable, null);
                preload_engines_id = 0U;

                return Source.REMOVE;
            });
        }

    }
}
