public class Tuba.Views.ContentBase : Views.Base {

	#if USE_LISTVIEW
		protected Gtk.ListView content;
	#else
		protected Gtk.ListBox content;
		protected signal void reached_close_to_top ();
	#endif
	public GLib.ListStore model;
	private bool bottom_reached_locked = false;

	public virtual bool empty {
		get { return model.get_n_items () <= 0; }
	}

	construct {
		model = new GLib.ListStore (typeof (Widgetizable));

		#if USE_LISTVIEW
			Gtk.SignalListItemFactory signallistitemfactory = new Gtk.SignalListItemFactory ();
			signallistitemfactory.bind.connect (bind_listitem_cb);

			content = new Gtk.ListView (new Gtk.NoSelection (model), signallistitemfactory) {
				css_classes = { "content", "background" },
				single_click_activate = true
			};

			content.activate.connect (on_content_item_activated);
		#else
			model.items_changed.connect (on_content_changed);

			content = new Gtk.ListBox () {
				selection_mode = Gtk.SelectionMode.NONE,
				css_classes = { "fake-content", "background" }
			};

			content.row_activated.connect (on_content_item_activated);
			content.bind_model (model, on_create_model_widget);
		#endif
		content_box.child = content;

		scrolled.vadjustment.value_changed.connect (on_scrolled_vadjustment_value_change);
		scroll_to_top_rev.bind_property ("child-revealed", scroll_to_top_rev, "visible", GLib.BindingFlags.SYNC_CREATE);
	}
	~ContentBase () {
		debug ("Destroying ContentBase");
	}

	protected virtual void on_scrolled_vadjustment_value_change () {
		if (
			!bottom_reached_locked
			&& scrolled.vadjustment.value > scrolled.vadjustment.upper - scrolled.vadjustment.page_size * 2
		) {
			bottom_reached_locked = true;
			on_bottom_reached ();
		}

		var is_close_to_top = scrolled.vadjustment.value <= 100;
		set_scroll_to_top_reveal_child (
			!is_close_to_top
			&& scrolled.vadjustment.value + scrolled.vadjustment.page_size + 100 < scrolled.vadjustment.upper
		);

		#if !USE_LISTVIEW
			if (is_close_to_top) reached_close_to_top ();
		#endif
	}

	protected void set_scroll_to_top_reveal_child (bool reveal) {
		if (reveal == scroll_to_top_rev.reveal_child) return;
		if (reveal) scroll_to_top_rev.visible = true;

		scroll_to_top_rev.reveal_child = reveal;
	}

	#if USE_LISTVIEW
		protected virtual void bind_listitem_cb (GLib.Object item) {
			((Gtk.ListItem) item).child = on_create_model_widget (((Gtk.ListItem) item).item);

			var gtklistitemwidget = ((Gtk.ListItem) item).child.get_parent ();
			if (gtklistitemwidget != null) {
				gtklistitemwidget.add_css_class ("card");
				gtklistitemwidget.add_css_class ("card-spacing");
				gtklistitemwidget.focusable = true;

				// Thread lines overflow slightly
				gtklistitemwidget.overflow = Gtk.Overflow.HIDDEN;
			}
		}
	#endif

	public override void dispose () {
		#if !USE_LISTVIEW
			unbind_listboxes ();
		#endif
		base.dispose ();
	}

	public override void clear () {
		base.clear ();
		this.model.remove_all ();
	}

	protected virtual void clear_all_but_first (int i = 1) {
		base.clear ();

		if (model.n_items > i)
			model.splice (i, model.n_items - i, {});
	}

	public override void on_content_changed () {
		if (empty) {
			base_status = new StatusMessage ();
		} else {
			base_status = null;
		}
	}

	#if !USE_LISTVIEW
		public override void unbind_listboxes () {
			if (content != null)
				content.bind_model (null, null);
			base.unbind_listboxes ();
		}
	#endif

	public virtual Gtk.Widget on_create_model_widget (Object obj) {
		var obj_widgetable = obj as Widgetizable;
		if (obj_widgetable == null)
			Process.exit (0);

		#if !USE_LISTVIEW
			Gtk.Widget widget = obj_widgetable.to_widget ();
			widget.add_css_class ("card");
			widget.add_css_class ("card-spacing");
			widget.focusable = true;

			// Thread lines overflow slightly
			widget.overflow = Gtk.Overflow.HIDDEN;
			return widget;
		#else
			return obj_widgetable.to_widget ();
		#endif
	}

	public virtual void on_bottom_reached () {
		uint timeout = 0;
		timeout = Timeout.add (1000, () => {
			bottom_reached_locked = false;
			GLib.Source.remove (timeout);

			return true;
		}, Priority.LOW);
	}

	#if USE_LISTVIEW
		public virtual void on_content_item_activated (uint pos) {
			((Widgetizable) ((ListModel) content.model).get_item (pos)).open ();
		}
	#else
		public virtual void on_content_item_activated (Gtk.ListBoxRow row) {
			Signal.emit_by_name (row, "open");
		}
	#endif
}
