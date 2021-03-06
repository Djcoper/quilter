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
namespace Quilter.Widgets {
    public class SourceView : Gtk.SourceView {
        public static new Gtk.SourceBuffer buffer;
        public bool is_modified {get; set; default = false;}
        public File file;
        public WebView webview;
        private string font;
        private GtkSpell.Checker spell = null;
        private Gtk.TextTag blackfont;
        private Gtk.TextTag lightgrayfont;
        private Gtk.TextTag darkgrayfont;
        private Gtk.TextTag whitefont;

        public signal void changed ();

        public bool spellcheck {
            set {
                if (value) {
                    try {
                        var settings = AppSettings.get_default ();
                        var last_language = settings.spellcheck_language;
                        bool language_set = false;
                        var language_list = GtkSpell.Checker.get_language_list ();
                        foreach (var element in language_list) {
                            if (last_language == element) {
                                language_set = true;
                                spell.set_language (last_language);
                                break;
                            }
                        }

                        if (language_list.length () == 0) {
                            spell.set_language (null);
                        } else if (!language_set) {
                            last_language = language_list.first ().data;
                            spell.set_language (last_language);
                        }
                        spell.attach (this);
                    } catch (Error e) {
                        warning (e.message);
                    }
                } else {
                    spell.detach ();
                }
            }
        }

        public SourceView () {
            update_settings ();
            var settings = AppSettings.get_default ();
            settings.changed.connect (update_settings);

            try {
                string text;
                var file = File.new_for_path (settings.last_file);

                if (file.query_exists ()) {
                    string filename = file.get_path ();
                    GLib.FileUtils.get_contents (filename, out text);
                    set_text (text, true);
                } else {
                    string filename = Services.FileManager.setup_tmp_file ().get_path ();
                    GLib.FileUtils.get_contents (filename, out text);
                    set_text (text, true);
                }
            } catch (Error e) {
                warning ("Error: %s\n", e.message);
            }
        }

        construct {
            var settings = AppSettings.get_default ();
            var manager = Gtk.SourceLanguageManager.get_default ();
            var language = manager.guess_language (null, "text/x-markdown");
            buffer = new Gtk.SourceBuffer.with_language (language);
            buffer.highlight_syntax = true;
            buffer.set_max_undo_levels (20);
            buffer.changed.connect (() => {
                on_text_modified ();
                Application.window.saved_indicator (false);
            });

            darkgrayfont = buffer.create_tag(null, "foreground", "#222");
            lightgrayfont = buffer.create_tag(null, "foreground", "#BBB");
            blackfont = buffer.create_tag(null, "foreground", "#000");
            whitefont = buffer.create_tag(null, "foreground", "#FFF");

            spell = new GtkSpell.Checker ();
            spellcheck = settings.spellcheck;
            settings.changed.connect (spellcheck_enable);

            this.populate_popup.connect ((menu) => {
                menu.selection_done.connect (() => {
                    var selected = get_selected (menu);

                    if (selected != null) {
                        try {
                            spell.set_language (selected.label);
                            settings.spellcheck_language = selected.label;
                        } catch (Error e) {}
                    }
                });
            });

            is_modified = false;
            Timeout.add_seconds (20, () => {
                on_text_modified ();
                return true;
            });

            this.set_buffer (buffer);
            this.set_wrap_mode (Gtk.WrapMode.WORD);
            this.left_margin = 80;
            this.top_margin = 40;
            this.right_margin = 80;
            this.bottom_margin = 40;
            this.set_pixels_above_lines(4);
            this.set_pixels_inside_wrap(4);
            this.expand = true;
            this.has_focus = true;
            this.set_tab_width (4);
            this.set_insert_spaces_instead_of_tabs (true);
        }

        private Gtk.MenuItem? get_selected (Gtk.Menu? menu) {
            if (menu == null) return null;
            var active = menu.get_active () as Gtk.MenuItem;

            if (active == null) return null;
            var sub_menu = active.get_submenu () as Gtk.Menu;
            if (sub_menu != null) {
                return sub_menu.get_active () as Gtk.MenuItem;
            }

            return null;
        }

        public void on_text_modified () {
            if (!is_modified) {
                is_modified = true;
            } else {
                changed ();
                Services.FileManager.save_work_file ();
                is_modified = false;
            }
        }

        public void set_text (string text, bool opening = true) {
            if (opening) {
                buffer.begin_not_undoable_action ();
                buffer.changed.disconnect (on_text_modified);
            }

            buffer.text = text;

            if (opening) {
                buffer.end_not_undoable_action ();
                buffer.changed.connect (on_text_modified);
            }

            Gtk.TextIter? start = null;
            buffer.get_start_iter (out start);
            buffer.place_cursor (start);
        }

        public void use_default_font (bool value) {
            if (!value) {
                return;
            }

            var default_font = "PT Mono 11";

            this.font = default_font;
        }

        private void update_settings () {
            var settings = AppSettings.get_default ();
            if (!settings.focus_mode) {
                Gtk.TextIter start, end;
                buffer.get_bounds (out start, out end);
                buffer.remove_tag(lightgrayfont, start, end);
                buffer.remove_tag(darkgrayfont, start, end);
                buffer.remove_tag(blackfont, start, end);
                buffer.remove_tag(whitefont, start, end);
                this.font = settings.font;
                use_default_font (settings.use_system_font);
                this.override_font (Pango.FontDescription.from_string (this.font));
                buffer.notify["cursor-position"].disconnect (set_focused_text);
            } else {
                set_focused_text ();
                buffer.notify["cursor-position"].connect (set_focused_text);
                this.font = "PT Mono 13";
                this.override_font (Pango.FontDescription.from_string (this.font));
            }

            set_scheme (get_default_scheme ());
        }

        private void spellcheck_enable () {
            var settings = AppSettings.get_default ();
            if (settings.spellcheck != false) {
                spellcheck = settings.spellcheck;
            } else {
                spellcheck = settings.spellcheck;
            }
        }

        public void set_scheme (string id) {
            var style_manager = Gtk.SourceStyleSchemeManager.get_default ();
            var style = style_manager.get_scheme (id);
            buffer.set_style_scheme (style);
        }

        private string get_default_scheme () {
            var settings = AppSettings.get_default ();
            if (!settings.dark_mode) {
                var provider = new Gtk.CssProvider ();
                provider.load_from_resource ("/com/github/lainsce/quilter/app-stylesheet.css");
                Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = false;
                Gtk.TextIter start, end;
                buffer.get_bounds (out start, out end);
                buffer.remove_tag(whitefont, start, end);
                return "quilter";
            } else {
                var provider = new Gtk.CssProvider ();
                provider.load_from_resource ("/com/github/lainsce/quilter/app-stylesheet-dark.css");
                Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
                Gtk.TextIter start, end;
                buffer.get_bounds (out start, out end);
                buffer.remove_tag(blackfont, start, end);
                return "quilter-dark";
            }
        }

        public void set_focused_text () {
            Gtk.TextIter cursor_iter;
            Gtk.TextIter start, end;
            var settings = AppSettings.get_default ();

            buffer.get_bounds (out start, out end);

            var cursor = buffer.get_insert ();
            buffer.get_iter_at_mark (out cursor_iter, cursor);
            buffer.apply_tag(lightgrayfont, start, end);
            buffer.apply_tag(darkgrayfont, start, end);
            buffer.remove_tag(blackfont, start, end);
            buffer.remove_tag(whitefont, start, end);

            if (cursor != null) {
                var start_sentence = cursor_iter;
                if (cursor_iter != start)
                    start_sentence.backward_lines (1);

                var end_sentence = cursor_iter;
                if (cursor_iter != end)
                    end_sentence.forward_lines (2);

                if (!settings.dark_mode) {
                    buffer.apply_tag(lightgrayfont, start_sentence, end_sentence);
                    buffer.apply_tag(blackfont, start_sentence, end_sentence);
                    buffer.remove_tag(whitefont, start_sentence, end_sentence);
                } else {
                    buffer.apply_tag(darkgrayfont, start_sentence, end_sentence);
                    buffer.apply_tag(whitefont, start_sentence, end_sentence);
                    buffer.remove_tag(blackfont, start_sentence, end_sentence);
                }
            }
        }
    }
}
