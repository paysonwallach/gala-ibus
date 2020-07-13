/*
 * gala-ibus
 *
 * Copyright © 2020 Payson Wallach
 *
 * Released under the terms of the GNU General Public License v3.0
 * (https://gnu.org/licenses/gpl.html)
 */

namespace GalaIBus {
    [DBus (name = "org.pantheon.gala.IBusManager")]
    public interface IBusManagerBusIface : Object {
        public signal void input_source_changed (InputSource input_source);

        public abstract void get_input_sources (out Gee.ArrayList<InputSource> input_sources);
        public abstract void set_input_source (InputSource input_source);
    }

    public class IBusManager : Object {
        private const string DBUS_NAME = "org.pantheon.gala.IBusManager";
        private const string DBUS_PATH = "/org/pantheon/gala/IBusManager";

        private static IBusManager? instance = null;

        private IBusManagerBusIface? bus = null;

        public signal void input_source_changed (InputSource input_source);

        public static IBusManager get_default () {
            if (instance == null)
                instance = new IBusManager ();

            return instance;
        }

        private IBusManager () {
            Bus.watch_name (BusType.SESSION, DBUS_NAME, BusNameWatcherFlags.NONE,
                () => connect_dbus (),
                () => bus = null);
        }

        private bool connect_dbus () {
            try {
                bus = Bus.get_proxy_sync (BusType.SESSION, DBUS_NAME, DBUS_PATH);
            } catch (Error err) {
                warning (@"connecting to $DBUS_NAME failed: $(err.message)");
                return false;
            }

            bus.input_source_changed.connect (input_source_changed);

            return true;
        });

        public void get_input_sources (out Gee.ArrayList<InputSource> input_sources) {
            if (bus == null)
                return;

            try {
                bus.get_input_sources (out input_sources);
            } catch (Error err) {
                warning (@"unable to get input sources: $(err.message)");
            }
        }

        public void set_input_source (InputSource input_source) {
            if (bus == null)
                return;

            try {
                bus.set_input_source (input_source);
            } catch (Error err) {
                warning (@"unable to set input sources: $(err.message)");
            }
        }
    }
}
