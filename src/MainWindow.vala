/*
* Copyright (c) 2017 Lains
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/
using Gtk;
using Granite;

namespace Quilter {
    public class MainWindow : Gtk.Window {
        public Gtk.HeaderBar toolbar;
        public File file;
        public Widgets.SourceView edit_view_content;
        public Widgets.WebView preview_view_content;
        public Widgets.StatusBar statusbar;

        private Gtk.Menu menu;
        private Gtk.Button new_button;
        private Gtk.Button open_button;
        private Gtk.Button save_button;
        private Gtk.Button save_as_button;
        private Gtk.MenuButton menu_button;
        private Gtk.Stack stack;
        private Gtk.StackSwitcher view_mode;
        private Gtk.ScrolledWindow edit_view;
        private Gtk.ScrolledWindow preview_view;
        private Gtk.Grid grid;
        private Widgets.Preferences preferences_dialog;
        private Widgets.Cheatsheet cheatsheet_dialog;
        private bool timer_scheduled = false;

        /*
         * 3 * 100 equals one beat, three keypresses. The normal typing speed.
         */
        private const int TIME_TO_REFRESH = 3 * 100;

        public bool is_fullscreen {
            get {
                var settings = AppSettings.get_default ();
                return settings.fullscreen;
            }
            set {
                var settings = AppSettings.get_default ();
                settings.fullscreen = value;

                if (settings.fullscreen)
                    fullscreen ();
                else
                    unfullscreen ();
            }
        }

        public MainWindow (Gtk.Application application) {
            Object (application: application,
                    resizable: true,
                    title: _("Quilter"),
                    height_request: 800,
                    width_request: 900);

            schedule_timer ();
            statusbar.update_wordcount ();
            statusbar.update_readtimecount ();
            show_statusbar ();
            focus_mode_toolbar ();

            var settings = AppSettings.get_default ();
            settings.changed.connect (() => {
                show_save_button ();
                focus_mode_toolbar ();
                show_statusbar ();
            });

            edit_view_content.changed.connect (() => {
                schedule_timer ();
                statusbar.update_wordcount ();
                statusbar.update_readtimecount ();
            });

            key_press_event.connect ((e) => {
                uint keycode = e.hardware_keycode;
                if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (match_keycode (Gdk.Key.q, keycode)) {
                        this.destroy ();
                    }
                }
                if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (match_keycode (Gdk.Key.s, keycode)) {
                        try {
                            Services.FileManager.save ();
                            saved_indicator (true);
                        } catch (Error e) {
                            warning ("Unexpected error during open: " + e.message);
                        }
                    }
                }
                if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (match_keycode (Gdk.Key.o, keycode)) {
                        try {
                            Services.FileManager.open ();
                        } catch (Error e) {
                            warning ("Unexpected error during open: " + e.message);
                        }
                    }
                }
                if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (match_keycode (Gdk.Key.h, keycode)) {
                        var cheatsheet_dialog = new Widgets.Cheatsheet (this);
                        cheatsheet_dialog.show_all ();
                    }
                }
                if ((e.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    if (match_keycode (Gdk.Key.z, keycode)) {
                        Widgets.SourceView.buffer.undo ();
                    }
                }
                if ((e.state & Gdk.ModifierType.CONTROL_MASK + Gdk.ModifierType.SHIFT_MASK) != 0) {
                    if (match_keycode (Gdk.Key.z, keycode)) {
                        Widgets.SourceView.buffer.redo ();
                    }
                }
                if (match_keycode (Gdk.Key.F11, keycode)) {
                    is_fullscreen = !is_fullscreen;
                }
                if (match_keycode (Gdk.Key.F1, keycode)) {
                    debug ("Press to change view...");
                    if (stack.get_visible_child_name () == "preview_view") {
                        stack.set_visible_child (edit_view);
                    } else if (stack.get_visible_child_name () == "edit_view") {
                        stack.set_visible_child (preview_view);
                    }
                    return true;
                }
                return false;
            });
        }

        construct {
            var context = this.get_style_context ();
            context.add_class ("quilter-window");
            toolbar = new Gtk.HeaderBar ();
            var settings = AppSettings.get_default ();
            string cache = Path.build_filename (Environment.get_user_cache_dir (), "com.github.lainsce.quilter");

            if (settings.last_file != null) {
                toolbar.subtitle = settings.last_file;
            } else if (settings.last_file == @"$cache/temp") {
                toolbar.subtitle = "New Document";
            }

			var header_context = toolbar.get_style_context ();
            header_context.add_class ("quilter-toolbar");

            new_button = new Gtk.Button ();
            new_button.has_tooltip = true;
            new_button.tooltip_text = (_("New file"));

            new_button.clicked.connect (() => {
                // New button pressed.
                // Start the creation of a clean slate.
                new_file ();
            });

            save_as_button = new Gtk.Button ();
            save_as_button.has_tooltip = true;
            save_as_button.tooltip_text = (_("Save as…"));

            save_as_button.clicked.connect (() => {
                try {
                    Services.FileManager.save_as ();
                    saved_indicator (true);
                } catch (Error e) {
                    warning ("Unexpected error during open: " + e.message);
                }
                toolbar.subtitle = settings.last_file;
            });

            save_button = new Gtk.Button ();
            save_button.has_tooltip = true;
            save_button.tooltip_text = (_("Save file"));

            save_button.clicked.connect (() => {
                try {
                    Services.FileManager.save ();
                    saved_indicator (true);
                } catch (Error e) {
                    warning ("Unexpected error during open: " + e.message);
                }
                toolbar.subtitle = settings.last_file;
            });

            open_button = new Gtk.Button ();
			      open_button.has_tooltip = true;
            open_button.tooltip_text = (_("Open…"));

            open_button.clicked.connect (() => {
                try {
                    Services.FileManager.open ();
                } catch (Error e) {
                    warning ("Unexpected error during open: " + e.message);
                }
                toolbar.subtitle = settings.last_file;
            });

            menu_button = new Gtk.MenuButton ();
            menu_button.has_tooltip = true;
            menu_button.tooltip_text = (_("Settings"));

            menu = new Gtk.Menu ();

            var cheatsheet = new Gtk.MenuItem.with_label (_("Markdown Cheatsheet"));
            cheatsheet.activate.connect (() => {
                debug ("Cheatsheet button pressed.");
                cheatsheet_dialog = new Widgets.Cheatsheet (this);
                cheatsheet_dialog.show_all ();
            });

            var preferences = new Gtk.MenuItem.with_label (_("Preferences"));
            preferences.activate.connect (() => {
                debug ("Prefs button pressed.");
                preferences_dialog = new Widgets.Preferences (this);
                preferences_dialog.show_all ();
            });

            var separator = new Gtk.SeparatorMenuItem ();

            menu.add (cheatsheet);
            menu.add (separator);
            menu.add (preferences);
            menu.show_all ();

            menu_button.popup = menu;

            edit_view = new Gtk.ScrolledWindow (null, null);
            edit_view_content = new Widgets.SourceView ();
            edit_view_content.monospace = true;
            edit_view.add (edit_view_content);

            preview_view = new Gtk.ScrolledWindow (null, null);
            preview_view_content = new Widgets.WebView (this);
            preview_view.add (preview_view_content);

            stack = new Gtk.Stack ();
            stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
            stack.add_titled (edit_view, "edit_view", _("Edit"));
            stack.add_titled (preview_view, "preview_view", _("Preview"));

            statusbar = new Widgets.StatusBar ();

            grid = new Gtk.Grid ();
            grid.orientation = Gtk.Orientation.VERTICAL;
            grid.add (stack);
            grid.add (statusbar);
            grid.show_all ();
            this.add (grid);

            view_mode = new Gtk.StackSwitcher ();
            view_mode.stack = stack;
            view_mode.valign = Gtk.Align.CENTER;
            view_mode.homogeneous = true;

            toolbar.pack_start (new_button);
            toolbar.pack_start (open_button);
            toolbar.pack_start (save_as_button);
            toolbar.pack_end (menu_button);
            toolbar.pack_end (view_mode);

            toolbar.show_close_button = true;
            toolbar.show_all ();

            int x = settings.window_x;
            int y = settings.window_y;
            int h = settings.window_height;
            int w = settings.window_width;

            if (x != -1 && y != -1) {
                this.move (x, y);
            }
            if (w != 0 && h != 0) {
                this.resize (w, h);
            }

            this.window_position = Gtk.WindowPosition.CENTER;
            this.set_titlebar (toolbar);
        }

        protected bool match_keycode (int keyval, uint code) {
            Gdk.KeymapKey [] keys;
            Gdk.Keymap keymap = Gdk.Keymap.get_default ();
            if (keymap.get_entries_for_keyval (keyval, out keys)) {
                foreach (var key in keys) {
                    if (code == key.keycode)
                        return true;
                    }
                }

            return false;
        }

        public override bool delete_event (Gdk.EventAny event) {
            int x, y, w, h;
            get_position (out x, out y);
            get_size (out w, out h);

            var settings = AppSettings.get_default ();
            settings.window_x = x;
            settings.window_y = y;
            settings.window_width = w;
            settings.window_height = h;

            if (settings.last_file != null) {
                debug ("Saving working file...");
                Services.FileManager.save_work_file ();
            } else if (settings.last_file == "New Document") {
                debug ("Saving cache...");
                Services.FileManager.save_tmp_file ();
            }
            return false;
        }

        private void schedule_timer () {
            if (!timer_scheduled) {
                Timeout.add (TIME_TO_REFRESH, render_func);
                timer_scheduled = true;
            }
        }

        private bool render_func () {
            preview_view_content.update_html_view ();
            timer_scheduled = false;
            return false;
        }

        public void focus_mode_toolbar () {
            var settings = AppSettings.get_default ();
            if (!settings.focus_mode) {
                new_button.set_image (new Gtk.Image.from_icon_name ("document-new", Gtk.IconSize.LARGE_TOOLBAR));
                save_button.set_image (new Gtk.Image.from_icon_name ("document-save", Gtk.IconSize.LARGE_TOOLBAR));
                save_as_button.set_image (new Gtk.Image.from_icon_name ("document-save-as", Gtk.IconSize.LARGE_TOOLBAR));
                open_button.set_image (new Gtk.Image.from_icon_name ("document-open", Gtk.IconSize.LARGE_TOOLBAR));
                menu_button.set_image (new Gtk.Image.from_icon_name ("open-menu", Gtk.IconSize.LARGE_TOOLBAR));
            } else {
                new_button.set_image (new Gtk.Image.from_icon_name ("document-new-symbolic", Gtk.IconSize.SMALL_TOOLBAR));
                save_button.set_image (new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.SMALL_TOOLBAR));
                save_as_button.set_image (new Gtk.Image.from_icon_name ("document-save-as-symbolic", Gtk.IconSize.SMALL_TOOLBAR));
                open_button.set_image (new Gtk.Image.from_icon_name ("document-open-symbolic", Gtk.IconSize.SMALL_TOOLBAR));
                menu_button.set_image (new Gtk.Image.from_icon_name ("open-menu-symbolic", Gtk.IconSize.SMALL_TOOLBAR));
            }
        }

        public void show_save_button () {
            var settings = AppSettings.get_default ();
            toolbar.pack_start (save_button);
            save_button.visible = settings.show_save_button;
        }

        public void show_statusbar () {
            var settings = AppSettings.get_default ();
            statusbar.visible = settings.statusbar;
        }

        public void saved_indicator (bool val) {
            edit_view_content.is_modified = val;

            string unsaved_identifier = "* ";

            if (!val) {
                if (!(unsaved_identifier in toolbar.subtitle)) {
                    toolbar.subtitle = unsaved_identifier + toolbar.subtitle;
                }
            } else {
                toolbar.subtitle = toolbar.subtitle.replace (unsaved_identifier, "");
            }
        }

        public void new_file () {
            debug ("New button pressed.");
            debug ("Buffer was modified. Asking user to save first.");

            if (edit_view_content.is_modified) {
                var dialog = new Services.DialogUtils.Dialog.display_save_confirm (Application.window);
                var result = dialog.run ();
                dialog.destroy ();

                if (result == Services.DialogUtils.DialogType.CANCEL) {
                    debug ("User cancelled, don't do anything.");
                } else if (result == Services.DialogUtils.DialogType.YES) {
                    debug ("User saves the file.");

                    try {
                        Services.FileManager.save ();
                    } catch (Error e) {
                        warning ("Unexpected error during save: " + e.message);
                    }
                } else if (result == Services.DialogUtils.DialogType.NO) {
                    debug ("User doesn't care about the file, shoot it to space.");

                    edit_view_content.is_modified = false;
                    file = null;
                    Widgets.SourceView.buffer.text = "";
                    toolbar.subtitle = "New Document";
                } else {
                    return;
                }
            }
            Widgets.SourceView.buffer.text = "";
            toolbar.subtitle = "New Document";
        }
    }
}
