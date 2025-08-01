public class Tuba.Dialogs.Composer.Components.AttachmentsBin : Gtk.Grid, Attachable {
	public bool edit_mode { get; set; default = false; }
	public bool working { get; set; default = false; }
	public bool is_empty { get { return attachment_widgets.size == 0; } }
	public bool can_add_media {
		get {
			bool has_only_images = true;
			//  foreach (var attachment in attachment_widgets) {
			//  	if (attachment.kind == VIDEO || attachment.kind == AUDIO) {
			//  		has_only_images = false;
			//  		break;
			//  	}
			//  }

			return has_only_images && attachment_widgets.size < accounts.active.instance_info.compat_status_max_media_attachments;
		}
	}

	~AttachmentsBin () {
		debug ("Destroying Composer Component AttachmentsBin");
		foreach (var attachment in attachment_widgets) {
			attachment.cleanup ();
		}
	}

	public struct Metadata {
		string id;
		string description;
		string focus;
	}

	public string[] get_all_media_ids () {
		string[] result = {};

		foreach (var attachment in attachment_widgets) {
			if (attachment.media_id != null) result += attachment.media_id;
		}

		return result;
	}

	public Metadata[] get_all_metadata () {
		Metadata[] result = {};

		foreach (var attachment in attachment_widgets) {
			if (attachment.media_id != null) result += Metadata () {
				id = attachment.media_id,
				description = attachment.alt_text,
				focus = "%s,%s".printf (
					Utils.Units.float_to_2_point_string ((float) attachment.pos_x),
					Utils.Units.float_to_2_point_string ((float) attachment.pos_y)
				)
			};
		}

		return result;
	}

	private class Editor : Adw.NavigationPage {
		public signal void saved (float pos_x, float pos_y, string alt_text);
		public signal void toast (Adw.Toast toast);

		~Editor () {
			debug ("Destroying Composer Attachment Editor");
		}

		private bool _can_save = false;
		public bool can_save {
			get { return _can_save; }
			set {
				this.can_pop =
				_can_save = value;
			}
		}

		public int64 alt_max_chars = accounts.active.instance_info.tuba_max_alt_chars;
		public bool edit_mode { get; set; default = false; }
		public float pos_x { get; set; default = 0.0f; }
		public float pos_y { get; set; default = 0.0f; }
		public string media_id { get; set; }

		GtkSource.View alt_editor;
		Composer.Components.Editor.PlaceholderHack placeholder;
		Gtk.Box content_box;
		Gtk.Label dialog_char_counter;
		construct {
			// translators: title on the composer alt text editor dialog
			this.title = _("Attachment Editor");

			var toolbar_view = new Adw.ToolbarView ();
			var headerbar = new Adw.HeaderBar () {
				show_end_title_buttons = false,
				show_start_title_buttons = false,
				show_title = false
			};

			content_box = new Gtk.Box (VERTICAL, 0);
			toolbar_view.content = content_box;
			toolbar_view.add_top_bar (headerbar);

			alt_editor = new GtkSource.View () {
				vexpand = true,
				hexpand = true,
				accepts_tab = false,
				wrap_mode = Gtk.WrapMode.WORD_CHAR,
				margin_bottom = 6,
				margin_top = 6,
				margin_start = 6,
				margin_end = 6
			};
			alt_editor.remove_css_class ("view");
			alt_editor.add_css_class ("reset");

			// translators: placeholder shown in the composer alt text editor text area
			placeholder = new Composer.Components.Editor.PlaceholderHack (new Gtk.Label (_("Describe the media…")) {
				valign = Gtk.Align.START,
				halign = Gtk.Align.START,
				justify = Gtk.Justification.FILL,
				//  margin_top = 6,
				margin_start = 3,
				wrap = true,
				wrap_mode = Pango.WrapMode.WORD_CHAR,
				sensitive = false
			});
			alt_editor.add_overlay (placeholder, 0, 0);
			alt_editor.update_property (Gtk.AccessibleProperty.PLACEHOLDER, _("Describe the media…"), -1);

			Adw.StyleManager.get_default ().notify["dark"].connect (update_style_scheme);
			update_style_scheme ();

			#if LIBSPELLING
				var adapter = new Spelling.TextBufferAdapter ((GtkSource.Buffer) alt_editor.buffer, Spelling.Checker.get_default ());

				alt_editor.extra_menu = adapter.get_menu_model ();
				alt_editor.insert_action_group ("spelling", adapter);
				adapter.enabled = true;
			#endif

			content_box.append (new Gtk.ScrolledWindow () {
				hexpand = true,
				vexpand = true,
				child = alt_editor
			});

			dialog_char_counter = new Gtk.Label (alt_max_chars.to_string ()) {
				// translators: tooltip text on the remaining characters counter in the
				//				composer alt text editor
				tooltip_text = _("Remaining Characters"),
				css_classes = { "numeric", "dimmed" },
				margin_end = 6
			};
			headerbar.pack_end (dialog_char_counter);
			alt_editor.buffer.changed.connect (on_alt_editor_buffer_change);

			this.child = toolbar_view;
			this.hidden.connect (on_save);
		}

		private void on_alt_editor_buffer_change () {
			int total_count = Utils.Counting.chars (alt_editor.buffer.text, "en");
			placeholder.visible = total_count == 0;

			var t_val = total_count < alt_max_chars;
			this.can_save = t_val;

			dialog_char_counter.label = (alt_max_chars - total_count).to_string ();
			if (t_val) {
				dialog_char_counter.remove_css_class ("error");
			} else {
				dialog_char_counter.add_css_class ("error");
			}
		}

		protected void update_style_scheme () {
			var manager = GtkSource.StyleSchemeManager.get_default ();
			string scheme_name = "Adwaita";
			if (Adw.StyleManager.get_default ().dark) scheme_name += "-dark";
			((GtkSource.Buffer) alt_editor.buffer).style_scheme = manager.get_scheme (scheme_name);
		}

		bool working = false;
		private void on_save () {
			if (working) return;
			if (this.edit_mode) {
				saved (this.pos_x, this.pos_y, alt_editor.buffer.text);
				toast (new Adw.Toast (_("Saved Media Metadata")));
				return;
			}
			working = true;

			var builder = new Json.Builder ();
			builder.begin_object ();
				builder.set_member_name ("description");
				builder.add_string_value (alt_editor.buffer.text);

				builder.set_member_name ("focus");
				builder.add_string_value ("%s,%s".printf (
					Utils.Units.float_to_2_point_string (this.pos_x),
					Utils.Units.float_to_2_point_string (this.pos_y)
				));
			builder.end_object ();

			new Request.PUT (@"/api/v1/media/$media_id")
				.with_account (accounts.active)
				.body_json (builder)
				.then (() => {
					saved (this.pos_x, this.pos_y, alt_editor.buffer.text);
					// translators: toast shown when saving alt text and focus position in the composer
					toast (new Adw.Toast (_("Saved Media Metadata")));
					working = false;
				})
				.on_error ((code, message) => {
					toast (new Adw.Toast (@"$code $message"));
					working = false;
				})
				.exec ();
		}

		public Editor (string media_id, Gdk.Paintable? paintable = null, GLib.File? video = null, float pos_x = 0, float pos_y = 0, string alt_text = "", bool edit_mode) {
			this.media_id = media_id;
			this.edit_mode = edit_mode;
			if (paintable != null) {
				var focus_picker = new Widgets.FocusPicker (paintable);
				focus_picker.bind_property ("pos-x", this, "pos-x", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
				focus_picker.bind_property ("pos-y", this, "pos-y", GLib.BindingFlags.SYNC_CREATE | GLib.BindingFlags.BIDIRECTIONAL);
				focus_picker.add_css_class ("attachment-editor-picker");

				content_box.prepend (focus_picker);
			} else if (video != null) {
				content_box.prepend (new Gtk.Video.for_file (video));
			}

			this.pos_x = pos_x;
			this.pos_y = pos_y;
			alt_editor.buffer.text = alt_text;
		}

		public override void measure (
			Gtk.Orientation orientation,
			int for_size,
			out int minimum,
			out int natural,
			out int minimum_baseline,
			out int natural_baseline
		) {
			base.measure (
				orientation,
				for_size,
				out minimum,
				out natural,
				out minimum_baseline,
				out natural_baseline
			);

			if (orientation == HORIZONTAL) natural = int.max (minimum, int.max (natural, 423));
		}
	}

	// https://github.com/tootsuite/mastodon/blob/master/app/models/media_attachment.rb
	public const string[] SUPPORTED_MIMES = {
		"image/jpeg",
		"image/png",
		"image/gif",
		"image/heic",
		"image/heif",
		"image/webp",
		"image/avif",
		"audio/wave",
		"audio/wav",
		"audio/x-wav",
		"audio/x-pn-wave",
		"audio/vnd.wave",
		"audio/ogg",
		"audio/vorbis",
		"audio/mpeg",
		"audio/mp3",
		"audio/webm",
		"audio/flac",
		"audio/aac",
		"audio/m4a",
		"audio/x-m4a",
		"audio/mp4",
		"audio/3gpp",
		"video/x-ms-asf",
		"video/quicktime",
		"video/webm",
		"video/mp4",
		"video/ogg"
	};
	private Gtk.FileFilter filter = new Gtk.FileFilter () {
			name = _("All Supported Files")
	};
	private Gee.ArrayList<string> supported_mimes = new Gee.ArrayList<string>.wrap (SUPPORTED_MIMES);

	Gee.ArrayList<Composer.Components.Attachment> attachment_widgets = new Gee.ArrayList<Composer.Components.Attachment> ();
	construct {
		populate_filter ();
		this.column_spacing = this.row_spacing = 12;
		this.row_homogeneous = this.column_homogeneous = true;

		// HACK: 2 cols otherwise when there's
		//		 only 1 attachment, it expands
		this.attach (new Adw.Bin () { can_target = false, focusable = false, can_focus = false, accessible_role = PRESENTATION }, 0, 0);
		this.attach (new Adw.Bin () { can_target = false, focusable = false, can_focus = false, accessible_role = PRESENTATION }, 1, 0);
	}

	private void add_attachment (Composer.Components.Attachment attachment) {
		attachment.switch_place.connect (on_switch_place);
		attachment.delete_me.connect (on_delete);
		attachment.edit.connect (show_editor);
		this.attach (attachment, attachment_widgets.size % 2, (int) Math.floor (attachment_widgets.size / 2));
		attachment_widgets.add (attachment);
		this.notify_property ("is-empty");
		this.notify_property ("can-add-media");
		attachment.play_animation ();
	}

	private void on_switch_place (Composer.Components.Attachment from, Composer.Components.Attachment to) {
		int from_column;
		int from_row;
		this.query_child (from, out from_column, out from_row, null, null);

		int to_column;
		int to_row;
		this.query_child (to, out to_column, out to_row, null, null);

		this.remove (from);
		this.remove (to);

		this.attach (to, from_column, from_row);
		this.attach (from, to_column, to_row);

		int from_index = attachment_widgets.index_of (from);
		int to_index = attachment_widgets.index_of (to);

		var temp = attachment_widgets[from_index];
		attachment_widgets[from_index] = attachment_widgets[to_index];
		attachment_widgets[to_index] = temp;
	}

	private void on_delete (Composer.Components.Attachment attachment) {
		int removed_column;
		int removed_row;
		this.query_child (attachment, out removed_column, out removed_row, null, null);
		this.remove (attachment);

		int removed_index = attachment_widgets.index_of (attachment);
		attachment_widgets.remove (attachment);
		attachment.cleanup ();

		for (int i = removed_index; i < attachment_widgets.size; i++) {
			var child = attachment_widgets.get (i);
			int current_col, current_row;
			this.query_child (child, out current_col, out current_row, null, null);

			if (current_row > removed_row || (current_row == removed_row && current_col > removed_column)) {
				int new_row = current_row;
				int new_col = current_col;

				if (current_col == 0) {
					new_row = current_row - 1;
					new_col = 1;
				} else {
					new_col = current_col - 1;
				}

				this.remove (child);
				this.attach (child, new_col, new_row);
			}
		}

		this.notify_property ("is-empty");
		this.notify_property ("can-add-media");
		on_attachment_done ();
	}

	private void populate_filter () {
		if (
			accounts.active.instance_info != null
			&& accounts.active.instance_info.configuration != null
			&& accounts.active.instance_info.configuration.media_attachments != null
			&& accounts.active.instance_info.configuration.media_attachments.supported_mime_types != null
			&& accounts.active.instance_info.configuration.media_attachments.supported_mime_types.size > 0
			// if the only supported type is octet-stream, assume everything
			&& !(
				accounts.active.instance_info.configuration.media_attachments.supported_mime_types.size == 1
				&& accounts.active.instance_info.configuration.media_attachments.supported_mime_types[0] == "application/octet-stream"
			)
		) {
			supported_mimes = accounts.active.instance_info.configuration.media_attachments.supported_mime_types;
		}

		foreach (var mime_type in supported_mimes) {
			filter.add_mime_type (mime_type.down ());
		}
	}

	public async void upload_files (owned File[] files) {
		if (files.length == 0) return;

		// We want to only upload as many attachments as the server
		// accepts based on the amount we have already uploaded.
		var allowed_attachments_amount = accounts.active.instance_info.compat_status_max_media_attachments - attachment_widgets.size;

		bool reached_limit = false;
		File[] files_for_upload = {};
		foreach (File file in files) {
			if (accounts.active.instance_info.compat_status_max_image_size > 0) {
				try {
					var file_info = file.query_info ("standard::size,standard::content-type", 0);
					var file_content_type = file_info.get_content_type ();

					if (file_content_type != null) {
						file_content_type = file_content_type.down ();
						if (!supported_mimes.contains (file_content_type)) continue;

						var file_size = file_info.get_size ();
						var skip = (
							file_content_type.contains ("image/")
							&& file_size >= accounts.active.instance_info.compat_status_max_image_size
						) || (
							file_content_type.contains ("video/")
							&& file_size >= accounts.active.instance_info.compat_status_max_video_size
						);

						if (skip) {
							// translators: toast shown when uploading a file bigger than what the instance allows.
							//				The variable is a string filename
							toast (new Adw.Toast (_("File \"%s\" is bigger than the instance limit").printf (file.get_basename ())));
							continue;
						}
					}

				} catch (Error e) {
					warning (e.message);
				}
			}

			// we want to add a max of allowed_attachments_amount
			// previously this check would happen in advance, but
			// we can be more liberal about this and instead check
			// all of them and stop if we run out or we reach
			// allowed_attachments_amount.
			//
			// this way, if a user selected 5 items, can only upload
			// a max of 4, but one of them does not pass the check,
			// it will still pass since <= 4 were allowed in
			files_for_upload += file;
			if (files_for_upload.length >= allowed_attachments_amount) {
				reached_limit = true;
				break;
			}
		}

		if (reached_limit) {
			// translators: the variable is the total amount of attachments allowed (a number)
			toast (new Adw.Toast (_("Attachment limit reached (%lld)").printf (accounts.active.instance_info.compat_status_max_media_attachments)) {
				timeout = 3
			});
		}

		this.working = files_for_upload.length > 0;
		for (int i = 0; i < files_for_upload.length; i++) {
			var file13 = files_for_upload[i];

			var attachment = new Composer.Components.Attachment ();
			attachment.upload_error.connect (on_upload_error);
			attachment.notify["done"].connect (on_attachment_done);
			attachment.upload.begin (file13);
			add_attachment (attachment);
		}
	}

	private void on_upload_error (Composer.Components.Attachment attachment, string message) {
		toast (new Adw.Toast (message));
		on_delete (attachment);
	}

	private void on_attachment_done () {
		bool is_working = false;
		foreach (var attachment in attachment_widgets) {
			is_working = !attachment.done;
			if (is_working) break;
		}
		this.working = is_working;
	}

	public void show_file_selector () {
		var chooser = new Gtk.FileDialog () {
			// translators: Open file
			title = _("Open"),
			modal = true,
			default_filter = filter
		};
		chooser.open_multiple.begin (app.main_window, null, (obj, res) => {
			try {
				var files = chooser.open_multiple.end (res);

				File[] files_to_upload = {};
				var amount_of_files = files.get_n_items ();
				for (var i = 0; i < amount_of_files; i++) {
					var file = files.get_item (i) as File;

					if (file != null)
						files_to_upload += file;
				}

				upload_files.begin (files_to_upload);
			} catch (Error e) {
				// User dismissing the dialog also ends here so don't make it sound like
				// it's an error
				warning (@"Couldn't get the result of FileDialog for AttachmentsBin: $(e.message)");
			}
		});
	}

	public void preload_attachment (API.Attachment api_attachment, bool edit_mode = true) {
		if (accounts.active.instance_info.compat_status_max_media_attachments - attachment_widgets.size <= 0) return;

		var attachment = new Composer.Components.Attachment ();
		attachment.notify["done"].connect (on_attachment_done);
		attachment.preload (api_attachment.id, api_attachment.url, api_attachment.preview_url, Composer.Components.Attachment.MediaType.from_string (api_attachment.kind));
		attachment.edit_mode = edit_mode;

		float x = 0;
		float y = 0;
		if (api_attachment.meta != null && api_attachment.meta.focus != null) {
			x = api_attachment.meta.focus.x;
			y = api_attachment.meta.focus.y;
		}
		attachment.saved (x, y, api_attachment.description == null ? "" : api_attachment.description);

		add_attachment (attachment);
	}

	public void show_editor (Attachment attachment) {
		bool is_image = attachment.kind == IMAGE;
		var editor = new Editor (
			attachment.media_id,
			is_image ? attachment.paintable : null,
			is_image ? null : attachment.file,
			(float) attachment.pos_x,
			(float) attachment.pos_y,
			attachment.alt_text,
			attachment.edit_mode
		);

		editor.saved.connect (attachment.saved);
		editor.saved.connect_after (pop_req);
		editor.toast.connect (toast_req);
		push_subpage (editor);
	}

	private void pop_req () {
		this.pop_subpage ();
	}

	private void toast_req (Adw.Toast toast_obj) {
		toast (toast_obj);
	}
}
