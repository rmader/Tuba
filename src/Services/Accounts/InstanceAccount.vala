public class Tuba.InstanceAccount : API.Account, Streamable {

	public const string EVENT_NEW_POST = "update";
	public const string EVENT_EDIT_POST = "status.update";
	public const string EVENT_DELETE_POST = "delete";
	public const string EVENT_NOTIFICATION = "notification";
	public const string EVENT_CONVERSATION = "conversation";
	public const string EVENT_NOTIFICATIONS_MERGED = "notifications_merged";

	public const string KIND_MENTION = "mention";
	public const string KIND_REBLOG = "reblog";
	public const string KIND_FAVOURITE = "favourite";
	public const string KIND_FOLLOW = "follow";
	public const string KIND_POLL = "poll";
	public const string KIND_FOLLOW_REQUEST = "follow_request";
	public const string KIND_REMOTE_REBLOG = "__remote-reblog";
	public const string KIND_EDITED = "update";
	public const string KIND_REPLY = "tuba_reply";
	public const string KIND_SEVERED_RELATIONSHIPS = "severed_relationships";
	public const string KIND_ADMIN_REPORT = "admin.report";
	public const string KIND_ADMIN_SIGNUP = "admin.sign_up";
	public const string KIND_STATUS = "status";
	public const string KIND_PLEROMA_REACTION = "pleroma:emoji_reaction";
	public const string KIND_REACTION = "reaction";
	public const string KIND_ANNUAL_REPORT = "annual_report";
	public const string KIND_MODERATION_WARNING = "moderation_warning";

	// Not exactly sure where I'm going with this.
	// I don't want *all* features listed here, just
	// the ones that either take too long to figure
	// out or the ones I need *early*.
	// DO NOT use as the only feature detection
	// mechanism.
	[Flags]
	public enum InstanceFeatures {
		NONE,
		QUOTE,
		EMOJI_REACTIONS,
		BUBBLE,
		GROUP_NOTIFICATIONS,
		FEATURE_TAGS,
		ENDORSE_USERS,
		MUTUALS,
		TRANSLATION,
		ICESHRIMP,
		GLITCH,
		LOCAL_ONLY
	}
	public InstanceFeatures tuba_instance_features { get; set; default = NONE; }
	public string? tuba_iceshrimp_api_key { get; set; default = null; }

	private string? _tuba_streaming_url = null;
	public string? tuba_streaming_url {
		get { return _tuba_streaming_url == null ? this.instance : _tuba_streaming_url; }
		set { _tuba_streaming_url = value; }
	}

	private void tuba_instance_features_update_and_save (InstanceFeatures features) {
		if (features == tuba_instance_features || !settings.get_boolean ("auto-detect-features")) return;

		this.tuba_instance_features = features;
		try {
			accounts.update_account (this);
		} catch (Error e) {
			critical (@"Couldn't update instance features for $id: $(e.code) $(e.message)");
		}
	}

	public void tuba_update_iceshrimp_api_key (string? new_key) {
		if (this.tuba_iceshrimp_api_key == new_key) return;

		this.tuba_iceshrimp_api_key = new_key;
		try {
			accounts.update_account (this);
		} catch (Error e) {
			critical (@"Couldn't update instance features for $id: $(e.code) $(e.message)");
		}
	}

	private void tuba_update_streaming_url (string new_url) {
		if (new_url == "") return;

		string new_host = this.instance;
		try {
			var new_uri = GLib.Uri.parse (new_url, GLib.UriFlags.NONE);
			string? new_host_uri = new_uri.get_host ();

			if (new_host_uri != null && new_host_uri != "")
				new_host = @"https://$new_host_uri";
		} catch (Error e) {
			warning (@"$new_url is not a valid URI: $(e.code) $(e.message)");
		}

		if (new_host != tuba_streaming_url) {
			this.tuba_streaming_url = new_host;
			try {
				accounts.update_account (this);
				app.app_streams.upgrade (this.instance, new_host);
			} catch (Error e) {
				critical (@"Couldn't update instance features for $id: $(e.code) $(e.message)");
			}
		}
	}

	public string uuid { get; set; }
	public bool admin_mode { get; set; default=false; }
	public string? backend { set; get; }
	public API.Instance? instance_info { get; set; }
	public Gee.ArrayList<API.Emoji>? instance_emojis { get; set; }
	public string? instance { get; set; }
	public string? client_id { get; set; }
	public string? client_secret { get; set; }
	public string? access_token { get; set; }
	public bool needs_update { get; set; default=false; }
	public Error? error { get; set; } //TODO: use this field when server invalidates the auth token
	public bool tuba_probably_has_notification_filters { get; set; default=false; }
	public API.InstanceV2.APIVersions tuba_api_versions { get; set; default= new API.InstanceV2.APIVersions (); }

	public GLib.ListStore known_places = new GLib.ListStore (typeof (Place));
	public GLib.ListStore list_places = new GLib.ListStore (typeof (Place));
	public GLib.ListStore tags_places = new GLib.ListStore (typeof (Place));

	public Gee.HashMap<Type,Type> type_overrides = new Gee.HashMap<Type,Type> ();

	public new string handle_short {
		owned get { return @"@$username"; }
	}

	public new string handle {
		owned get { return full_handle; }
	}

	public bool is_active {
		get {
			if (accounts.active == null)
				return false;
			return accounts.active.access_token == access_token;
		}
	}

	public virtual signal void activated () {
		bump_sidebar_items ();
		gather_instance_info ();
		gather_instance_custom_emojis ();
		GLib.Idle.add (gather_fav_lists);
		GLib.Idle.add (gather_fav_tags);
		check_announcements ();

		if (_account_settings != null) _account_settings = null;
	}
	public virtual signal void deactivated () {}
	public virtual signal void added () {
		subscribed = true;
		check_notifications ();
	}
	public virtual signal void removed () {
		subscribed = false;
	}

	public void reconnect () {
		gather_instance_info ();
		gather_instance_custom_emojis ();
		GLib.Idle.add (gather_fav_lists);
		GLib.Idle.add (gather_fav_tags);
		check_announcements ();
		check_notifications ();
	}

	construct {
		this.construct_streamable ();
		this.stream_event[EVENT_NOTIFICATION].connect (on_notification_event);
		this.register_known_places (this.known_places);
		this.register_extra (this.list_places);
		this.register_extra (this.tags_places);

		#if DEV_MODE
			app.dev_new_notification.connect (node => {
				if (accounts.active.id != this.id) return;

				try {
					var entity = create_entity<API.Notification> (node);

					var id = int.parse (entity.id);
					if (id > last_received_id) {
						last_received_id = id;

						unread_count++;
						send_toast (entity);
					}
				} catch (Error e) {
					warning (@"on_notification_event: $(e.message)");
				}
			});
		#endif

		app.notify["is-online"].connect (on_network_change);
	}

	private void on_network_change () {
		if (is_active && app.is_online) {
			if (needs_update) {
			needs_update = false;
			new Request.GET (@"/api/v1/accounts/$(this.id)")
				.with_account (this)
				.then ((in_stream) => {
					var parser = Network.get_parser_from_inputstream (in_stream);
					var node = network.parse_node (parser);
					if (node == null) {
						needs_update = true;
						return;
					}

					var acc = API.Account.from (node);

					if (this.display_name != acc.display_name || this.avatar != acc.avatar) {
						this.display_name = acc.display_name;
						this.avatar = acc.avatar;
					}
				})
			.exec ();
			}

			reconnect ();
		}
	}

	~InstanceAccount () {
		destruct_streamable ();
	}

	public InstanceAccount.empty (string instance) {
		Object (
			id: "",
			instance: instance
		);
	}

	// Visibility options

	public class Visibility : Object {
		public string id { get; construct set; }
		public string name { get; construct set; }
		public string icon_name { get; construct set; }
		public string description { get; construct set; }

		private string? _small_icon_name = null;
		public string small_icon_name {
			get {
				return _small_icon_name ?? icon_name;
			}
			set {
				_small_icon_name = value;
			}
		}
	}
	public Gee.HashMap<string,Visibility> visibility = new Gee.HashMap<string,Visibility> ();
	public ListStore visibility_list = new ListStore (typeof (Visibility));
	public void set_visibility (Visibility obj) {
		this.visibility[obj.id] = obj;
		visibility_list.append (obj);
	}



	// Core functions

	public T create_entity<T> (Json.Node node) throws Error {
		var type = typeof (T);
		if (type_overrides.has_key (type))
			type = type_overrides[type];

		return Entity.from_json (type, node);
	}

	public Entity create_dynamic_entity (Type type, Json.Node node) throws Error {
		if (type_overrides.has_key (type))
			type = type_overrides[type];

		return Entity.from_json (type, node);
	}

	public async void verify_credentials () throws Error {
		var req = new Request.GET ("/api/v1/accounts/verify_credentials").with_account (this);
		yield req.await ();

		update_object (req.response_body);
	}

	public void update_object (InputStream in_stream) throws Error {
		var parser = Network.get_parser_from_inputstream (in_stream);
		var node = network.parse_node (parser);
		var updated = API.Account.from (node);
		patch (updated);

		debug (@"$handle: profile updated");
	}

	public async Entity resolve (string url) throws Error {
		debug (@"Resolving URL: \"$url\"…");
		var results = yield API.SearchResults.request (url, this);
		var entity = results.first ();
		debug (@"Found $(entity.get_class ().get_name ())");
		return entity;
	}

	public struct Kind {
		string? icon;
		string? description;
		string? url;
	}

	public virtual void describe_kind (
		string? kind,
		out Kind result,
		string? actor_name = null,
		string? callback_url = null,
		string? other_data = null
	) {
		switch (kind) {
			case KIND_MENTION:
				result = {
					"tuba-chat-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s mentioned you").printf (actor_name),
					callback_url
				};
				break;
			case KIND_REBLOG:
				result = {
					"tuba-media-playlist-repeat-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s boosted your post").printf (actor_name),
					callback_url
				};
				break;
			case KIND_REMOTE_REBLOG:
				result = {
					"tuba-media-playlist-repeat-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s boosted").printf (actor_name),
					callback_url
				};
				break;
			case KIND_FAVOURITE:
				result = {
					"tuba-starred-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s favorited your post").printf (actor_name),
					callback_url
				};
				break;
			case KIND_FOLLOW:
				result = {
					"contact-new-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s now follows you").printf (actor_name),
					callback_url
				};
				break;
			case KIND_FOLLOW_REQUEST:
				result = {
					"contact-new-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s wants to follow you").printf (actor_name),
					callback_url
				};
				break;
			case KIND_POLL:
				result = {
					"tuba-check-round-outline-symbolic",
					// translators: this is used for notifications
					_("Poll results"),
					null
				};
				break;
			case KIND_EDITED:
				result = {
					"document-edit-symbolic",
					// translators: the variable is a string user name,
					//				this is used for notifications
					_("%s edited a post").printf (actor_name),
					null
				};
				break;
			case KIND_REPLY:
				string reply_text;
				if (actor_name == null) {
					// translators: post header, on posts that are replies
					reply_text = _("In Reply");
				} else {
					// translators: the variable is a string user handle,
					//				post header, on posts that are replies
					reply_text = _("In Reply to %s").printf (actor_name);
				}

				result = {
					"tuba-reply-sender-symbolic",
					reply_text,
					null
				};
				break;
			case KIND_ADMIN_SIGNUP:
				result = {
					"tuba-build-alt-symbolic",
					// translators: the variable is a string user name,
					//				this is used for admin notifications
					_("%s signed up").printf (actor_name),
					null
				};
				break;
			case KIND_SEVERED_RELATIONSHIPS:
				result = {
					"tuba-heart-broken-symbolic",
					// translators: this is used for notifications,
					//				when you lost followers or following
					//				due to admin instance or user suspension
					//				or personal domain blocking
					_("Some of your relationships got severed"),
					null
				};
				break;
			case KIND_ANNUAL_REPORT:
				result = {
					"tuba-heart-broken-symbolic",
					// translators: this is used for notifications,
					//				when an annual report is available.
					//				it's similar to spotify wrapped, it
					//				shows profile stats / it's a recap
					//				of the year. The variable is the
					//				current year e.g. 2024. Please don't
					//				translate the hashtag.
					_("Your %s #FediWrapped is ready!").printf (other_data),
					null
				};
				break;
			case KIND_MODERATION_WARNING:
				result = {
					"tuba-police-badge2-symbolic",
					// translators: this is used for notifications,
					//				when you receive a warning from
					//				your server's admins
					_("Your account has received a moderation warning"),
					null
				};
				break;
			case KIND_ADMIN_REPORT:
				result = {
					"tuba-build-alt-symbolic",
					// translators: this is used for admin notifications
					_("Received a new report"),
					null
				};
				break;
			case KIND_STATUS:
				result = {
					"tuba-bell-outline-symbolic",
					// translators: the variable is a string user name,
					//				this is used for per-account notifications
					_("%s just posted").printf (actor_name),
					null
				};
				break;
			case KIND_PLEROMA_REACTION:
			case KIND_REACTION:
				string body;
				if (other_data == null) {
					// translators: the variable is a string user name,
					//				this is used for notifications
					body = _("%s reacted to your post").printf (actor_name);
				} else {
					// translators: the first variable is a string user name,
					//				the second variable is an emoji,
					//				this is used for notifications
					body = _("%s reacted to your post with %s").printf (actor_name, other_data);
				}

				result = {
					"tuba-smile-symbolic",
					body,
					callback_url
				};
				break;
			default:
				result = {
					null,
					null,
					null
				};
				break;
		}
	}

	public virtual void register_known_places (GLib.ListStore places) {}
	public virtual void register_extra (GLib.ListStore places, Place[]? extra = null) {}

	// Notifications

	public int unreviewed_follow_requests { get; set; default = 0; }
	public int unread_announcements { get; set; default = 0; }
	public int filtered_notifications_count { get; set; default = 0; }
	public int unread_count { get; set; default = 0; }
	public int last_read_id { get; set; default = 0; }
	public int last_received_id { get; set; default = 0; }

	public class StatusContentType : Object {
		public string mime { get; construct set; }
		public string icon_name { get; construct set; }
		public string title { get; construct set; }
		public string syntax { get; construct set; }

		public StatusContentType (string content_type) {
			mime = content_type;

			switch (content_type.down ()) {
				case "text/plain":
					icon_name = "tuba-paper-symbolic";
					// translators: this is a content type
					title = _("Plain Text");
					syntax = "fedi-basic";
					break;
				case "text/html":
					icon_name = "tuba-code-symbolic";
					title = "HTML";
					syntax = "fedi-html";
					break;
				case "text/markdown":
					icon_name = "tuba-markdown-symbolic";
					title = "Markdown";
					syntax = "fedi-markdown";
					break;
				case "text/bbcode":
					icon_name = "tuba-rich-text-symbolic";
					title = "BBCode";
					syntax = "fedi-basic";
					break;
				case "text/x.misskeymarkdown":
					icon_name = "tuba-rich-text-symbolic";
					title = "MFM";
					syntax = "fedi-basic";
					break;
				default:
					icon_name = "tuba-rich-text-symbolic";
					syntax = "fedi-basic";

					int slash = content_type.index_of_char ('/');
					int ct_l = content_type.length;
					if (slash == -1 || slash == ct_l) {
						title = content_type.up ();
					} else {
						title = content_type.slice (slash + 1, ct_l).up ();
					}

					break;
			}
		}

		public static EqualFunc<string> compare = (a, b) => {
			return ((StatusContentType) a).mime == ((StatusContentType) b).mime;
		};
	}

	public GLib.ListStore supported_mime_types = new GLib.ListStore (typeof (StatusContentType));
	public void gather_instance_info () {
		if (instance_info != null) return;

		new Request.GET ("/api/v1/instance")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				if (node == null) return;

				instance_info = API.Instance.from (node);

				var content_types = instance_info.compat_supported_mime_types;
				if (content_types != null) {
					supported_mime_types.remove_all ();
					foreach (string content_type in content_types) {
						supported_mime_types.append (new StatusContentType (content_type));
					}
				}

				var new_flags = this.tuba_instance_features;

				if (instance_info.pleroma == null) {
					gather_v2_instance_info ();
				} else if (instance_info.pleroma.metadata != null && instance_info.pleroma.metadata.features != null) {
					instance_info.tuba_can_translate = "akkoma:machine_translation" in instance_info.pleroma.metadata.features;

					new_flags = instance_info.supports_quote_posting ? new_flags | InstanceFeatures.QUOTE : new_flags & ~InstanceFeatures.QUOTE;
					new_flags = instance_info.tuba_can_translate ? new_flags | InstanceFeatures.TRANSLATION : new_flags & ~InstanceFeatures.TRANSLATION;
					if (instance_info.supports_bubble) new_flags |= InstanceFeatures.BUBBLE;
				}

				// LOCAL_ONLY is common between them and we can use it to skip the whole string parsing
				if (instance_info.version != null && !(InstanceFeatures.LOCAL_ONLY in new_flags)) {
					if ("Pleroma " in instance_info.version) {
						new_flags |= InstanceFeatures.EMOJI_REACTIONS | InstanceFeatures.FEATURE_TAGS | InstanceFeatures.ENDORSE_USERS | InstanceFeatures.MUTUALS | InstanceFeatures.LOCAL_ONLY;
					} else if ("Iceshrimp.NET/" in instance_info.version) {
						new_flags |= InstanceFeatures.ICESHRIMP | InstanceFeatures.EMOJI_REACTIONS | InstanceFeatures.LOCAL_ONLY | InstanceFeatures.BUBBLE;
					} else if ("+glitch" in instance_info.version) {
						new_flags |= InstanceFeatures.GLITCH | InstanceFeatures.LOCAL_ONLY | InstanceFeatures.FEATURE_TAGS | InstanceFeatures.ENDORSE_USERS;
					} else if ("+hometown" in instance_info.version) {
						new_flags |= InstanceFeatures.LOCAL_ONLY | InstanceFeatures.FEATURE_TAGS | InstanceFeatures.ENDORSE_USERS;
					} else if ("Akkoma " in instance_info.version) {
						new_flags |= InstanceFeatures.EMOJI_REACTIONS | InstanceFeatures.LOCAL_ONLY;
					}
				}
				tuba_instance_features_update_and_save (new_flags);

				if (instance_info.urls != null && instance_info.urls.streaming_api != null)
					tuba_update_streaming_url (instance_info.urls.streaming_api);

				app.handle_share ();
				bump_sidebar_items ();
			})
			.exec ();
	}

	protected virtual void bump_sidebar_items () {}

	private void gather_v2_instance_info () {
		new Request.GET ("/api/v2/instance")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				if (node == null) return;

				InstanceFeatures? new_flags = null;
				var instance_v2 = API.InstanceV2.from (node);
				if (instance_v2 != null) {
					new_flags = this.tuba_instance_features;

					if (instance_v2.configuration != null) {
						if (instance_v2.configuration.translation != null) this.instance_info.tuba_can_translate = instance_v2.configuration.translation.enabled;
						if (instance_v2.configuration.media_attachments != null) this.instance_info.tuba_max_alt_chars = instance_v2.configuration.media_attachments.description_limit;

						new_flags = instance_info.tuba_can_translate ? new_flags | InstanceFeatures.TRANSLATION : new_flags & ~InstanceFeatures.TRANSLATION;
					}

					if (instance_v2.api_versions != null && instance_v2.api_versions.mastodon > 0) {
						if (!this.tuba_api_versions.tuba_same (instance_v2.api_versions)) {
							this.tuba_api_versions = instance_v2.api_versions;
							accounts.update_account (this);
						}
						this.tuba_probably_has_notification_filters = true;

						if (this.tuba_api_versions.mastodon > 1) {
							gather_annual_report ();
							new_flags |= InstanceFeatures.GROUP_NOTIFICATIONS;
						}

						if (this.tuba_api_versions.mastodon > 5) {
							new_flags |= InstanceFeatures.ENDORSE_USERS;
						}

						if (this.tuba_api_versions.chuckya > 0) {
							new_flags |= InstanceFeatures.EMOJI_REACTIONS;
						}

						new_flags |= InstanceFeatures.FEATURE_TAGS | InstanceFeatures.MUTUALS;
						if (instance_info.supports_bubble) new_flags |= InstanceFeatures.BUBBLE;
					}
				}

				if (new_flags != null) tuba_instance_features_update_and_save (new_flags);
				bump_sidebar_items ();
			})
			.exec ();
	}

	public int tuba_last_fediwrapped_year { get; set; default=0; }
	API.AnnualReports? annual_report;
	private void gather_annual_report () {
		var now = new GLib.DateTime.now ();

		int year = 0;
		switch (now.get_month ()) {
			case 12:
				year = now.get_year ();
				break;
			case 1:
				year = now.get_year () - 1;
				break;
			default:
				return;
		}

		new Request.GET (@"/api/v1/annual_reports/$(year)")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				annual_report = API.AnnualReports.from (node);
				if (annual_report.annual_reports.size > 0) tuba_last_fediwrapped_year = year;
			})
			.exec ();
	}

	public void open_latest_wrapped () {
		if (tuba_last_fediwrapped_year == 0 || annual_report == null) return;
		annual_report.open (tuba_last_fediwrapped_year);
		tuba_last_fediwrapped_year = 0;
		annual_report = null;
	}

	public void gather_instance_custom_emojis () {
		if (instance_emojis != null) return;

		new Request.GET ("/api/v1/custom_emojis")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var node = network.parse_node (parser);
				if (node == null) return;

				Value res_emojis;
				Entity.des_list (out res_emojis, node, typeof (API.Emoji));
				instance_emojis = (Gee.ArrayList<Tuba.API.Emoji>) res_emojis;
			})
			.exec ();
	}

	public bool gather_fav_tags () {
		if (settings.favorite_tags_ids.length == 0) {
			this.register_extra (this.tags_places);
			return GLib.Source.REMOVE;
		}

		Place[] fav_tags = {};
		foreach (string tag in settings.favorite_tags_ids) {
			fav_tags += new Place () {
				icon = "tuba-hashtag-symbolic",
				title = tag,
				extra_data = new Gtk.StringObject (tag),
				open_func = (win, tag_obj) => {
					string tag_str = ((Gtk.StringObject) tag_obj).string;
					win.open_view (set_as_sidebar_item (new Views.Hashtag (tag_str, null, Uri.escape_string (tag_str))));
				}
			};
		}

		if (fav_tags.length > 0) {
			this.register_extra (this.tags_places, fav_tags);
		}

		return GLib.Source.REMOVE;
	}

	public bool gather_fav_lists () {
		if (settings.favorite_lists_ids.length == 0) {
			this.register_extra (this.list_places);
			return GLib.Source.REMOVE;
		}

		new Request.GET ("/api/v1/lists")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				Place[] fav_lists = {};
				string[] all_ids = {};
				Network.parse_array (parser, node => {
					var list = API.List.from (node);
					if (list.id in settings.favorite_lists_ids) {
						fav_lists += new Place () {
							icon = "tuba-list-compact-symbolic",
							title = list.title,
							extra_data = list,
							open_func = (win, list) => {
								win.open_view (set_as_sidebar_item (new Views.List ((API.List) list)));

							}
						};
					}

					all_ids += list.id;
				});
				this.register_extra (this.list_places, fav_lists);

				string[] new_favs = {};
				foreach (string fav_id in settings.favorite_lists_ids) {
					if (fav_id in all_ids) new_favs += fav_id;
				}
				settings.favorite_lists_ids = new_favs;
			})
			.exec ();

		return GLib.Source.REMOVE;
	}

	protected static Views.Base set_as_sidebar_item (Views.Base view) {
		view.is_sidebar_item = true;
		view.show_back_button = false;
		return view;
	}

	public void init_notifications () {
		new Request.GET (@"/api/v1/notifications$(Views.Notifications.get_notifications_excluded_types_query_param ())")
			.with_account (this)
			.with_param ("min_id", last_read_id.to_string ())
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var array = Network.get_array_mstd (parser);
				if (array != null) {
					unread_count = (int)array.get_length ();
					if (unread_count > 0) {
						last_received_id = int.parse (array.get_object_element (0).get_string_member_with_default ("id", "-1"));
					}
				}
			})
			.exec ();
	}

	public virtual void check_notifications () {
		new Request.GET ("/api/v1/markers?timeline[]=notifications")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var root = network.parse (parser);
				if (!root.has_member ("notifications")) return;
				var notifications = root.get_object_member ("notifications");
				last_read_id = int.parse (notifications.get_string_member_with_default ("last_read_id", "-1"));
				init_notifications ();
			})
			.exec ();
	}

	public void check_announcements () {
		new Request.GET ("/api/v1/announcements")
			.with_account (this)
			.then ((in_stream) => {
				var parser = Network.get_parser_from_inputstream (in_stream);
				var array = Network.get_array_mstd (parser);
				if (array != null) {
					int t_unread_announcements = 0;
					array.foreach_element ((array, i, node) => {
						if (node.get_object ().get_boolean_member_with_default ("read", true) == false) t_unread_announcements += 1;
					});
					unread_announcements = t_unread_announcements;
				}
			})
			.exec ();
	}

	public void read_notifications (int up_to_id) {
		debug (@"Reading notifications up to id $up_to_id");

		if (up_to_id > last_read_id) {
			last_read_id = up_to_id;

			if (last_read_id != -1) {
				// Mark as read
				new Request.POST ("/api/v1/markers")
					.with_account (this)
					.with_form_data ("notifications[last_read_id]", up_to_id.to_string ())
					.exec ();

				// Pleroma FE doesn't mark them as read by just updating the marker
				if (instance_info != null && instance_info.pleroma != null) {
					new Request.POST ("/api/v1/pleroma/notifications/read")
						.with_account (this)
						.with_form_data ("max_id", up_to_id.to_string ())
						.exec ();
				}

				foreach (string notification_id in sent_notifications.keys) {
					app.withdraw_notification (notification_id);
				}

				sent_notifications.clear ();
			}
		}

		unread_count = 0;

		//  if (sent_notification_ids.size > 0) {
		//  	sent_notification_ids.@foreach (entry => {
		//  		app.withdraw_notification (entry);
		//  		return true;
		//  	});
		//  }
		//  unread_toasts.@foreach (entry => {
		//  	var id = entry.key;
		//  	read_notification (id);
		//  	return true;
		//  });
	}

	//  public void read_notification (int id) {
	//  	if (id <= last_read_id) {
	//  		debug (@"Read notification with id: $id");
	//  		app.withdraw_notification (id.to_string ());
	//  		unread_toasts.unset (id);
	//  	}
	//  	unread_count = unread_toasts.size;
	//  	has_unread = unread_count > 0;
	//  }

	private Gee.HashMap<string, int> sent_notifications = new Gee.HashMap<string, int> ();
	private const string[] GROUPED_KINDS = {
		KIND_FAVOURITE,
		KIND_REBLOG
	};
	public void send_toast (API.Notification obj) {
		if (obj.kind != null && (obj.kind in settings.muted_notification_types)) return;

		var id = this.id;
		var others = 0;

		if (settings.group_push_notifications && obj.status != null && obj.kind in GROUPED_KINDS) {
			id = @"$id-$(obj.status.id)-$(obj.kind)";
			if (sent_notifications.has_key (id)) {
				others = sent_notifications.get (id) + 1;
			}
		} else {
			id = @"$id-$(obj.id)";
		}
		sent_notifications.set (id, others);

		obj.to_toast.begin (this, others, (_obj, res) => {
			app.send_notification (id, obj.to_toast.end (res));
		});
	}



	// Streamable

	public string? t_connection_url { get; set; }
	public bool subscribed { get; set; }

	public virtual string? get_stream_url () {
		if (instance == null || access_token == null) return null;
		return @"$instance/api/v1/streaming?stream=user:notification&access_token=$access_token";
	}

	public virtual void on_notification_event (Streamable.Event ev) {
		try {
			var entity = create_entity<API.Notification> (ev.get_node ());
			if (entity.status != null && entity.status.formal.tuba_filter_hidden) return;
			if (entity.kind == InstanceAccount.KIND_FOLLOW_REQUEST) unreviewed_follow_requests += 1;

			var id = int.parse (entity.id);
			if (id > last_received_id) {
				last_received_id = id;

				if (!(entity.kind in account_settings_notification_filters ()))
					unread_count++;
				send_toast (entity);
			}
		} catch (Error e) {
			warning (@"on_notification_event: $(e.message)");
		}
	}

	// Notification actions
	public virtual void open_status_url (string url) {}
	public virtual void answer_follow_request (string issuer_id, string fr_id, bool accept) {}
	public virtual void follow_back (string issuer_id, string acc_id) {}
	public virtual void reply_to_status_uri (string issuer_id, string uri) {}
	public virtual void remove_from_followers (string issuer_id, string acc_id) {}

	private GLib.Settings? _account_settings = null;
	private GLib.Settings account_settings () {
		if (accounts.active == this) return settings;
		if (_account_settings == null) _account_settings = new Settings.Account (this.uuid);
		return _account_settings;
	}

	private string[] account_settings_notification_filters () {
		if (accounts.active == this) {
			return ((Settings) account_settings ()).notification_filters;
		} else {
			return ((Settings.Account) account_settings ()).notification_filters;
		}
	}
}
