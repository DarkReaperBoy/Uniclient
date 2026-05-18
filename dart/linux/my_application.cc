#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <math.h>

#ifdef HAVE_APPINDICATOR
#include <libayatana-appindicator/app-indicator.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* tray_channel;
  FlMethodChannel* window_channel;
  GDBusConnection* session_bus;
  guint xdp_settings_signal_id;
#ifdef HAVE_APPINDICATOR
  AppIndicator* indicator;
  GtkWidget* tray_menu;
  GtkWidget* show_hide_item;
  GtkWidget* notifications_item;
  GtkWidget* streamer_item;
  GtkWidget* ghost_item;
  int badge_toggle;
  gchar* badge_dir;
#endif
  int close_behavior; // 0=Run in Background, 1=Close to Taskbar, 2=Quit
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ── Tray helpers ──

// Resolve the icon path from the bundle's data directory.
static gchar* get_icon_path() {
  gchar* exe_path = g_file_read_link("/proc/self/exe", NULL);
  if (!exe_path) return nullptr;
  gchar* exe_dir = g_path_get_dirname(exe_path);
  gchar* icon_path = g_build_filename(exe_dir, "data", "uniclient.png", NULL);
  g_free(exe_dir);
  g_free(exe_path);
  return icon_path;
}

static void toggle_window_visibility(MyApplication* self) {
  if (!self->window) return;
  if (gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    gtk_widget_hide(GTK_WIDGET(self->window));
  } else {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
  }
#ifdef HAVE_APPINDICATOR
  // Update menu label.
  if (self->show_hide_item) {
    gboolean visible = gtk_widget_get_visible(GTK_WIDGET(self->window));
    gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item),
                            visible ? "Hide" : "Show");
  }
#endif
}

#ifdef HAVE_APPINDICATOR
static void on_tray_show_hide(GtkMenuItem* /*item*/, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  gboolean was_visible = self->window &&
      gtk_widget_get_visible(GTK_WIDGET(self->window));
  toggle_window_visibility(self);
  if (was_visible && self->tray_channel) {
    fl_method_channel_invoke_method(
        self->tray_channel, "onWindowHidden", nullptr, nullptr, nullptr,
        nullptr);
  }
}

static void on_tray_streamer_toggle(GtkMenuItem* /*item*/, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->tray_channel) {
    fl_method_channel_invoke_method(
        self->tray_channel, "onStreamerToggle", nullptr, nullptr, nullptr,
        nullptr);
  }
}

static void on_tray_ghost_toggle(GtkMenuItem* /*item*/, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->tray_channel) {
    fl_method_channel_invoke_method(
        self->tray_channel, "onGhostToggle", nullptr, nullptr, nullptr,
        nullptr);
  }
}

static void on_tray_notifications_toggle(GtkMenuItem* /*item*/,
                                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->tray_channel) {
    fl_method_channel_invoke_method(
        self->tray_channel, "onNotificationsToggle", nullptr, nullptr, nullptr,
        nullptr);
  }
}

static void on_tray_quit(GtkMenuItem* /*item*/, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  // Notify Dart side that the app is quitting.
  if (self->tray_channel) {
    fl_method_channel_invoke_method(
        self->tray_channel, "onQuit", nullptr, nullptr, nullptr, nullptr);
  }
  // Allow the app to close normally.
  if (self->window) {
    gtk_widget_destroy(GTK_WIDGET(self->window));
  }
}

static void update_tray_badge(MyApplication* self, int count,
                              gboolean muted) {
  if (!self->indicator) return;

  if (count <= 0) {
    gchar* icon_path = get_icon_path();
    gchar* icon_dir = icon_path ? g_path_get_dirname(icon_path) : nullptr;
    app_indicator_set_icon_theme_path(self->indicator,
                                     icon_dir ? icon_dir : "");
    app_indicator_set_icon_full(self->indicator, "uniclient", "UniClient");
    g_free(icon_dir);
    g_free(icon_path);
    return;
  }

  gchar* icon_path = get_icon_path();
  if (!icon_path) return;

  GError* error = NULL;
  GdkPixbuf* base = gdk_pixbuf_new_from_file(icon_path, &error);
  g_free(icon_path);
  if (!base) {
    if (error) g_error_free(error);
    return;
  }

  int w = gdk_pixbuf_get_width(base);
  int h = gdk_pixbuf_get_height(base);

  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
  cairo_t* cr = cairo_create(surface);
  gdk_cairo_set_source_pixbuf(cr, base, 0, 0);
  cairo_paint(cr);
  g_object_unref(base);

  double badge_r = w * 0.28;
  double cx = w - badge_r - 1;
  double cy = h - badge_r - 1;

  if (muted) {
    cairo_set_source_rgb(cr, 0.6, 0.6, 0.6);
  } else {
    cairo_set_source_rgb(cr, 0.93, 0.28, 0.27);
  }
  cairo_arc(cr, cx, cy, badge_r, 0, 2 * M_PI);
  cairo_fill(cr);

  char text[8];
  if (count > 99)
    snprintf(text, sizeof(text), "99+");
  else
    snprintf(text, sizeof(text), "%d", count);

  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_BOLD);
  cairo_set_font_size(cr, badge_r * 1.2);

  cairo_text_extents_t extents;
  cairo_text_extents(cr, text, &extents);
  cairo_move_to(cr, cx - extents.width / 2 - extents.x_bearing,
                cy - extents.height / 2 - extents.y_bearing);
  cairo_show_text(cr, text);

  if (!self->badge_dir) {
    self->badge_dir =
        g_build_filename(g_get_tmp_dir(), "uniclient_tray", NULL);
    g_mkdir_with_parents(self->badge_dir, 0700);
  }

  self->badge_toggle = !self->badge_toggle;
  const char* name =
      self->badge_toggle ? "uniclient_badge_a" : "uniclient_badge_b";
  gchar* filename = g_strdup_printf("%s.png", name);
  gchar* path = g_build_filename(self->badge_dir, filename, NULL);
  cairo_surface_write_to_png(surface, path);
  g_free(path);
  g_free(filename);

  cairo_destroy(cr);
  cairo_surface_destroy(surface);

  app_indicator_set_icon_theme_path(self->indicator, self->badge_dir);
  app_indicator_set_icon_full(self->indicator, name, "UniClient");
}

static void init_tray(MyApplication* self) {
  gchar* icon_path = get_icon_path();

  // AppIndicator needs the icon path directory + icon name without extension.
  // It uses icon theme lookup, so we set the theme path to the directory and
  // the icon name to the filename without extension.
  gchar* icon_dir = nullptr;
  const gchar* icon_name = "uniclient";
  if (icon_path) {
    icon_dir = g_path_get_dirname(icon_path);
  }

  self->indicator = app_indicator_new_with_path(
      "com.uniclient.app",
      icon_name,
      APP_INDICATOR_CATEGORY_COMMUNICATIONS,
      icon_dir ? icon_dir : "");

  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_title(self->indicator, "UniClient");

  // Build the tray context menu.
  self->tray_menu = gtk_menu_new();

  self->show_hide_item = gtk_menu_item_new_with_label("Hide");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), self->show_hide_item);
  g_signal_connect(self->show_hide_item, "activate",
                   G_CALLBACK(on_tray_show_hide), self);

  self->notifications_item =
      gtk_menu_item_new_with_label("Disable Notifications");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu),
                        self->notifications_item);
  g_signal_connect(self->notifications_item, "activate",
                   G_CALLBACK(on_tray_notifications_toggle), self);

  self->streamer_item = gtk_menu_item_new_with_label("Enable Streamer Mode");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), self->streamer_item);
  g_signal_connect(self->streamer_item, "activate",
                   G_CALLBACK(on_tray_streamer_toggle), self);

  self->ghost_item = gtk_menu_item_new_with_label("Enable Ghost Mode");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), self->ghost_item);
  g_signal_connect(self->ghost_item, "activate",
                   G_CALLBACK(on_tray_ghost_toggle), self);

  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), separator);

  GtkWidget* quit_item = gtk_menu_item_new_with_label("Quit");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_tray_quit), self);

  gtk_widget_show_all(self->tray_menu);
  gtk_widget_hide(self->streamer_item);
  app_indicator_set_menu(self->indicator, GTK_MENU(self->tray_menu));

  g_free(icon_path);
  g_free(icon_dir);
}
#endif

// Deferred handler for Ctrl+Q `quitApp` — runs on the next main-loop
// iteration so the method-call response has already been delivered to
// Dart before we tear down the Flutter view.
static gboolean quit_app_idle(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window) {
    gtk_widget_destroy(GTK_WIDGET(self->window));
  }
  return G_SOURCE_REMOVE;
}

// ── MethodChannel handler (Dart → Native) ──

static void tray_method_call_handler(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "setTooltip") == 0) {
#ifdef HAVE_APPINDICATOR
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      const gchar* tooltip = fl_value_get_string(args);
      app_indicator_set_label(self->indicator, tooltip, tooltip);
    }
#endif
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "toggleVisibility") == 0) {
    toggle_window_visibility(self);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "showWindow") == 0) {
    if (self->window && !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      gtk_widget_show(GTK_WIDGET(self->window));
      gtk_window_present(self->window);
#ifdef HAVE_APPINDICATOR
      if (self->show_hide_item)
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item), "Hide");
#endif
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "hideWindow") == 0) {
    if (self->window && gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      gtk_widget_hide(GTK_WIDGET(self->window));
#ifdef HAVE_APPINDICATOR
      if (self->show_hide_item)
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item), "Show");
#endif
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "minimizeWindow") == 0) {
    // Telegram Desktop spec §24.4 Ctrl+M `minimize_telegram` — iconify the
    // window (standard minimize to taskbar). Works regardless of tray
    // availability. Unlike hideWindow (which removes the window from the
    // taskbar entirely), minimize leaves the taskbar entry intact.
    if (self->window && gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      gtk_window_iconify(self->window);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "quitApp") == 0) {
    // Telegram Desktop spec §24.4 Ctrl+Q `quit_telegram` — fully quit the
    // application (unlike Ctrl+W which only hides to tray). Respond to
    // the method call first, then defer the window destroy to the next
    // main-loop iteration via g_idle_add so the method channel finishes
    // unwinding before the FlView is torn down. Without the defer, the
    // Flutter engine logs "GetFfiCallbackMetadata called after shutdown"
    // because Dart's response-return path is still executing when the
    // view is destroyed.
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    g_idle_add(quit_app_idle, self);
  } else if (g_strcmp0(method, "setStreamerTrayItem") == 0) {
#ifdef HAVE_APPINDICATOR
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->streamer_item && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* show_val = fl_value_lookup_string(args, "show");
      FlValue* enabled_val = fl_value_lookup_string(args, "enabled");
      gboolean show = show_val ? fl_value_get_bool(show_val) : FALSE;
      gboolean enabled = enabled_val ? fl_value_get_bool(enabled_val) : FALSE;
      if (show) {
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->streamer_item),
                                enabled ? "Disable Streamer Mode"
                                        : "Enable Streamer Mode");
        gtk_widget_show(self->streamer_item);
      } else {
        gtk_widget_hide(self->streamer_item);
      }
    }
#endif
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setNotificationsTrayItem") == 0) {
#ifdef HAVE_APPINDICATOR
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->notifications_item &&
        fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* enabled_val = fl_value_lookup_string(args, "enabled");
      gboolean enabled = enabled_val ? fl_value_get_bool(enabled_val) : TRUE;
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->notifications_item),
                              enabled ? "Disable Notifications"
                                      : "Enable Notifications");
    }
#endif
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setUnreadBadge") == 0) {
#ifdef HAVE_APPINDICATOR
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* count_val = fl_value_lookup_string(args, "count");
      FlValue* muted_val = fl_value_lookup_string(args, "muted");
      int count = count_val ? (int)fl_value_get_int(count_val) : 0;
      gboolean muted = muted_val ? fl_value_get_bool(muted_val) : FALSE;
      update_tray_badge(self, count, muted);
    }
#endif
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setGhostTrayItem") == 0) {
#ifdef HAVE_APPINDICATOR
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->ghost_item && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* show_val = fl_value_lookup_string(args, "show");
      FlValue* enabled_val = fl_value_lookup_string(args, "enabled");
      gboolean show = show_val ? fl_value_get_bool(show_val) : FALSE;
      gboolean enabled = enabled_val ? fl_value_get_bool(enabled_val) : FALSE;
      if (show) {
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->ghost_item),
                                enabled ? "Disable Ghost Mode"
                                        : "Enable Ghost Mode");
        gtk_widget_show(self->ghost_item);
      } else {
        gtk_widget_hide(self->ghost_item);
      }
    }
#endif
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "updateAppIcon") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* icon_val = fl_value_lookup_string(args, "icon");
      if (icon_val && fl_value_get_type(icon_val) == FL_VALUE_TYPE_STRING) {
        const gchar* icon_name = fl_value_get_string(icon_val);
        gchar* exe_path = g_file_read_link("/proc/self/exe", NULL);
        if (exe_path) {
          gchar* exe_dir = g_path_get_dirname(exe_path);
          gchar* icon_file = g_strdup_printf("%s.png", icon_name);
          gchar* icon_path = g_build_filename(
              exe_dir, "data", "flutter_assets", "assets", "icons",
              "ayu", icon_file, NULL);
          if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
            if (self->window) {
              GError* error = NULL;
              GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(icon_path, &error);
              if (pixbuf) {
                gtk_window_set_icon(self->window, pixbuf);
                g_object_unref(pixbuf);
              }
              if (error) g_error_free(error);
            }
#ifdef HAVE_APPINDICATOR
            if (self->indicator) {
              gchar* ayu_icon_dir = g_build_filename(
                  exe_dir, "data", "flutter_assets", "assets", "icons",
                  "ayu", NULL);
              gchar* bare_name = g_strdup(icon_name);
              app_indicator_set_icon_theme_path(self->indicator, ayu_icon_dir);
              app_indicator_set_icon_full(self->indicator, bare_name,
                                         "UniClient");
              g_free(bare_name);
              g_free(ayu_icon_dir);
            }
#endif
          }
          g_free(icon_path);
          g_free(icon_file);
          g_free(exe_dir);
          g_free(exe_path);
        }
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setCloseBehavior") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
      self->close_behavior = (int)fl_value_get_int(args);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "isAvailable") == 0) {
#ifdef HAVE_APPINDICATOR
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
#else
    g_autoptr(FlValue) result = fl_value_new_bool(FALSE);
#endif
    fl_method_call_respond_success(method_call, result, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

// Intercept window close to hide instead of destroy.
// Respects close_behavior: 0=Run in Background, 1=Close to Taskbar, 2=Quit.
static gboolean on_window_delete(GtkWidget* /*widget*/,
                                 GdkEvent* /*event*/,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  // Behavior 2 = Quit: allow normal close (destroy window).
  if (self->close_behavior == 2) {
    return FALSE;
  }

#ifdef HAVE_APPINDICATOR
  if (self->indicator) {
    if (self->close_behavior == 1) {
      // Behavior 1 = Close to Taskbar: iconify (minimize) instead of hiding.
      gtk_window_iconify(self->window);
    } else {
      // Behavior 0 = Run in Background: hide to tray.
      gtk_widget_hide(GTK_WIDGET(self->window));
      if (self->show_hide_item)
        gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item), "Show");
    }
    if (self->tray_channel) {
      fl_method_channel_invoke_method(
          self->tray_channel, "onWindowHidden", nullptr, nullptr, nullptr,
          nullptr);
    }
    return TRUE;  // Prevent destruction.
  }
#endif
  (void)self;
  return FALSE;  // No tray — allow normal close.
}

// ── Window control method channel ──

// Track maximize state changes and notify Dart.
static gboolean on_window_state(GtkWidget* /*widget*/,
                                GdkEventWindowState* event,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    gboolean maximized =
        (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
    if (self->window_channel) {
      g_autoptr(FlValue) args = fl_value_new_bool(maximized);
      fl_method_channel_invoke_method(self->window_channel, "maximizeChanged",
                                     args, nullptr, nullptr, nullptr);
    }
  }
  return FALSE;
}

// Query button layout from XDG desktop portal (Wayland fallback).
// Spec §1: when XSettings is unavailable, fall back to
// org.gnome.desktop.wm.preferences::button-layout via the portal.
static gchar* query_xdp_button_layout(GDBusConnection* connection) {
  if (!connection) return NULL;

  g_autoptr(GError) error = NULL;
  g_autoptr(GVariant) result = g_dbus_connection_call_sync(
      connection,
      "org.freedesktop.portal.Desktop",
      "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Settings",
      "Read",
      g_variant_new("(ss)", "org.gnome.desktop.wm.preferences", "button-layout"),
      G_VARIANT_TYPE("(v)"),
      G_DBUS_CALL_FLAGS_NONE,
      1000,  // 1s timeout
      NULL,
      &error);

  if (!result) return NULL;

  // Portal Read returns (v). The inner variant wraps the GSettings value,
  // which is itself a variant wrapping the actual string.
  g_autoptr(GVariant) outer = NULL;
  g_variant_get(result, "(v)", &outer);
  if (!outer) return NULL;

  g_autoptr(GVariant) inner = NULL;
  GVariant* target = outer;
  if (g_variant_is_of_type(outer, G_VARIANT_TYPE_VARIANT)) {
    inner = g_variant_get_variant(outer);
    target = inner;
  }

  if (g_variant_is_of_type(target, G_VARIANT_TYPE_STRING)) {
    const gchar* str = g_variant_get_string(target, NULL);
    if (str && str[0] != '\0') {
      return g_strdup(str);
    }
  }

  return NULL;
}

// Handle XDG portal SettingChanged signal for live button layout updates.
// Signal signature: (ssv) — namespace, key, value.
static void on_xdp_setting_changed(GDBusConnection* /*connection*/,
                                   const gchar* /*sender*/,
                                   const gchar* /*object_path*/,
                                   const gchar* /*interface_name*/,
                                   const gchar* /*signal_name*/,
                                   GVariant* parameters,
                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->window_channel) return;

  const gchar* ns = NULL;
  const gchar* key = NULL;
  g_autoptr(GVariant) value = NULL;
  g_variant_get(parameters, "(&s&sv)", &ns, &key, &value);

  if (g_strcmp0(ns, "org.gnome.desktop.wm.preferences") != 0 ||
      g_strcmp0(key, "button-layout") != 0) {
    return;
  }

  g_autoptr(GVariant) inner = NULL;
  GVariant* target = value;
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    inner = g_variant_get_variant(value);
    target = inner;
  }

  if (g_variant_is_of_type(target, G_VARIANT_TYPE_STRING)) {
    const gchar* layout = g_variant_get_string(target, NULL);
    if (layout && layout[0] != '\0') {
      g_autoptr(FlValue) args = fl_value_new_string(layout);
      fl_method_channel_invoke_method(self->window_channel,
                                     "buttonLayoutChanged",
                                     args, nullptr, nullptr, nullptr);
    }
  }
}

static void window_method_call_handler(FlMethodChannel* /*channel*/,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "close") == 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    if (self->window) gtk_widget_destroy(GTK_WIDGET(self->window));
  } else if (g_strcmp0(method, "minimize") == 0) {
    if (self->window) gtk_window_iconify(self->window);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "maximize") == 0) {
    if (self->window) {
      if (gtk_window_is_maximized(self->window))
        gtk_window_unmaximize(self->window);
      else
        gtk_window_maximize(self->window);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    gboolean maximized =
        self->window ? gtk_window_is_maximized(self->window) : FALSE;
    g_autoptr(FlValue) result = fl_value_new_bool(maximized);
    fl_method_call_respond_success(method_call, result, nullptr);
  } else if (g_strcmp0(method, "setDecorated") == 0) {
    // Toggle between native system frame and client-side (custom) titlebar.
    // Spec §1: NativeWindowFrameSupported() is true on Linux.
    FlValue* args = fl_method_call_get_args(method_call);
    gboolean decorated = fl_value_get_bool(args);
    if (self->window) {
      gtk_window_set_decorated(self->window, decorated);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "resize") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->window && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* w_val = fl_value_lookup_string(args, "width");
      FlValue* h_val = fl_value_lookup_string(args, "height");
      if (w_val && h_val) {
        gint w = (gint)fl_value_get_int(w_val);
        gint h = (gint)fl_value_get_int(h_val);
        gtk_window_resize(self->window, w, h);
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "startDrag") == 0) {
    // Respond first, then start the drag — begin_move_drag may redirect
    // the event loop so the response must be sent beforehand.
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    if (self->window) {
      GdkDevice* device = gdk_seat_get_pointer(
          gdk_display_get_default_seat(gdk_display_get_default()));
      gint x, y;
      gdk_device_get_position(device, NULL, &x, &y);
      gtk_window_begin_move_drag(self->window, 1, x, y, GDK_CURRENT_TIME);
    }
  } else if (g_strcmp0(method, "getButtonLayout") == 0) {
    // Spec §1: read button layout from desktop environment at runtime.
    // 1. GTK's gtk-decoration-layout (aggregates XSettings on X11 and
    //    XDG portal on Wayland in GTK 3.24+).
    // 2. Explicit XDG portal query (Wayland fallback when GTK doesn't
    //    pick up the portal value).
    // 3. Windows-style right-side buttons (spec §1 default).
    GtkSettings* settings = gtk_settings_get_default();
    gchar* layout = NULL;
    if (settings) {
      g_object_get(settings, "gtk-decoration-layout", &layout, NULL);
    }
    if (layout && layout[0] != '\0') {
      g_autoptr(FlValue) result = fl_value_new_string(layout);
      fl_method_call_respond_success(method_call, result, nullptr);
      g_free(layout);
    } else {
      g_free(layout);
      // XDG portal fallback (Wayland).
      gchar* xdp_layout = query_xdp_button_layout(self->session_bus);
      if (xdp_layout) {
        g_autoptr(FlValue) result = fl_value_new_string(xdp_layout);
        fl_method_call_respond_success(method_call, result, nullptr);
        g_free(xdp_layout);
      } else {
        g_autoptr(FlValue) result = fl_value_new_string(":minimize,maximize,close");
        fl_method_call_respond_success(method_call, result, nullptr);
      }
    }
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

// Callback for live gtk-decoration-layout changes — pushes to Dart.
static void on_decoration_layout_changed(GObject* /*settings*/,
                                         GParamSpec* /*pspec*/,
                                         gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (!self->window_channel) return;
  GtkSettings* settings = gtk_settings_get_default();
  gchar* layout = NULL;
  if (settings) {
    g_object_get(settings, "gtk-decoration-layout", &layout, NULL);
  }
  if (layout && layout[0] != '\0') {
    g_autoptr(FlValue) args = fl_value_new_string(layout);
    fl_method_channel_invoke_method(self->window_channel, "buttonLayoutChanged",
                                   args, nullptr, nullptr, nullptr);
    g_free(layout);
  } else {
    g_free(layout);
    // Try XDG portal fallback.
    gchar* xdp_layout = query_xdp_button_layout(self->session_bus);
    if (xdp_layout) {
      g_autoptr(FlValue) args = fl_value_new_string(xdp_layout);
      fl_method_channel_invoke_method(self->window_channel, "buttonLayoutChanged",
                                     args, nullptr, nullptr, nullptr);
      g_free(xdp_layout);
    } else {
      g_autoptr(FlValue) args = fl_value_new_string(":minimize,maximize,close");
      fl_method_channel_invoke_method(self->window_channel, "buttonLayoutChanged",
                                     args, nullptr, nullptr, nullptr);
    }
  }
}

// Implements GApplication::activate.
// Called on first launch AND when a second instance tries to start.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Second activation: just raise the existing window and return.
  if (self->window) {
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
#ifdef HAVE_APPINDICATOR
    if (self->show_hide_item)
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item), "Hide");
#endif
    return;
  }

  // First activation: create the window.
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Spec §1: Custom client-side titlebar by default — remove WM decorations.
  // Flutter draws its own titlebar (CustomTitlebar widget).
  gtk_window_set_decorated(window, FALSE);

  // Spec §1: Default 800x600, large-screen default 1024x768, minimum 380x480.
  int def_w = 800, def_h = 600;
  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (!monitor) monitor = gdk_display_get_monitor(display, 0);
    if (monitor) {
      GdkRectangle workarea;
      gdk_monitor_get_workarea(monitor, &workarea);
      if (workarea.width >= 1280 && workarea.height >= 800) {
        def_w = 1024;
        def_h = 768;
      }
    }
  }
  gtk_window_set_default_size(window, def_w, def_h);
  GdkGeometry geometry;
  geometry.min_width = 380;
  geometry.min_height = 480;
  gtk_window_set_geometry_hints(window, NULL, &geometry, GDK_HINT_MIN_SIZE);

  // Set window icon from bundled PNG.
  gchar* icon_path = get_icon_path();
  if (icon_path) {
    gtk_window_set_icon_from_file(window, icon_path, NULL);
    g_free(icon_path);
  }

  // Intercept close to minimize to tray.
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete), self);

  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Set up the tray MethodChannel.
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->tray_channel = fl_method_channel_new(
      messenger, "com.uniclient.app/tray", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->tray_channel, tray_method_call_handler, self, nullptr);

  // Window control method channel (minimize, maximize, close, drag).
  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      messenger, "com.uniclient.app/window", FL_METHOD_CODEC(window_codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_handler, self, nullptr);

  // Track maximize state changes to notify Dart.
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(on_window_state), self);

  // Watch for live gtk-decoration-layout changes and push to Dart.
  GtkSettings* gtk_settings = gtk_settings_get_default();
  if (gtk_settings) {
    g_signal_connect(gtk_settings, "notify::gtk-decoration-layout",
                     G_CALLBACK(on_decoration_layout_changed), self);
  }

  // Subscribe to XDG portal SettingChanged for button layout (Wayland).
  // Spec §1: watch for live changes via portal when XSettings unavailable.
  {
    g_autoptr(GError) bus_error = NULL;
    self->session_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &bus_error);
    if (self->session_bus) {
      self->xdp_settings_signal_id = g_dbus_connection_signal_subscribe(
          self->session_bus,
          "org.freedesktop.portal.Desktop",
          "org.freedesktop.portal.Settings",
          "SettingChanged",
          "/org/freedesktop/portal/desktop",
          NULL,
          G_DBUS_SIGNAL_FLAGS_NONE,
          on_xdp_setting_changed,
          self,
          NULL);
    }
  }

#ifdef HAVE_APPINDICATOR
  init_tray(self);
#endif

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // If another instance owns the D-Bus name, forward activate to it
  // (raises its window) and exit this process.
  if (g_application_get_is_remote(application)) {
    g_application_activate(application);
    *exit_status = 0;
    return TRUE;
  }

  // We are the primary instance — activate normally.
  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(application);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(application);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->tray_channel);
  g_clear_object(&self->window_channel);
  if (self->xdp_settings_signal_id && self->session_bus) {
    g_dbus_connection_signal_unsubscribe(self->session_bus,
                                        self->xdp_settings_signal_id);
    self->xdp_settings_signal_id = 0;
  }
  g_clear_object(&self->session_bus);
#ifdef HAVE_APPINDICATOR
  g_clear_object(&self->indicator);
  if (self->tray_menu) {
    gtk_widget_destroy(self->tray_menu);
    self->tray_menu = nullptr;
  }
  g_free(self->badge_dir);
  self->badge_dir = nullptr;
#endif
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->tray_channel = nullptr;
  self->window_channel = nullptr;
  self->session_bus = nullptr;
  self->close_behavior = 0;
  self->xdp_settings_signal_id = 0;
#ifdef HAVE_APPINDICATOR
  self->indicator = nullptr;
  self->tray_menu = nullptr;
  self->show_hide_item = nullptr;
  self->notifications_item = nullptr;
  self->streamer_item = nullptr;
  self->ghost_item = nullptr;
  self->badge_toggle = 0;
  self->badge_dir = nullptr;
#endif
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_DEFAULT_FLAGS,
                                     nullptr));
}
