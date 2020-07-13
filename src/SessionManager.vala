/*
 * gala-ibus
 *
 * Copyright © 2020 Payson Wallach
 *
 * Released under the terms of the GNU General Public License v3.0
 * (https://gnu.org/licenses/gpl.html)
 *
 * This file includes code based upon work by budgie-desktop
 * (https://github.com/solus-project/budgie-desktop)
 */

namespace GalaIBus.SessionManager {
    [DBus (name = "org.gnome.SessionManager")]
    public interface SessionManager : Object {
        public abstract async ObjectPath register_client (string app_id, string client_start_id) throws Error;
    }

    [DBus (name = "org.gnome.SessionManager.ClientPrivate")]
    public interface SessionClient : Object {
        public abstract void end_session_response (bool is_ok, string reason) throws Error;

        public signal void stop ();
        public signal void query_end_session (uint flags);
        public signal void end_session (uint flags);
        public signal void cancel_end_session ();
    }

    public const string GNOME_SESSION_MANAGER_IFACE = "org.gnome.SessionManager";
    public const string GNOME_SESSION_MANAGER_PATH = "/org/gnome/SessionManager";

    private const string DESKTOP_AUTOSTART_ID_KEY = "DESKTOP_AUTOSTART_ID";

    public async SessionClient? register_with_session (string app_id) {
        SessionClient? sclient = null;
        ObjectPath? path = null;
        string? start_id = Environment.get_variable (DESKTOP_AUTOSTART_ID_KEY);

        if (start_id != null)
            Environment.unset_variable (DESKTOP_AUTOSTART_ID_KEY);
        else
            start_id = "";

        try {
            SessionManager? session = yield Bus.get_proxy (Bus.SESSION, GNOME_SESSION_MANAGER_IFACE, GNOME_SESSION_MANAGER_PATH);
            path = yield session.register_client (app_id, start_id);
        } catch (Error err) {
            warning (@"unable to get PrivateClient proxy: $(err.message)");
            return null;
        }

        return sclient;
    }
}
