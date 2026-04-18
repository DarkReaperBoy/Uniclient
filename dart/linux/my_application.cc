#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#ifdef HAVE_APPINDICATOR
#include <libayatana-appindicator/app-indicator.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* tray_channel;
#ifdef HAVE_APPINDICATOR
  AppIndicator* indicator;
  GtkWidget* tray_menu;
  GtkWidget* show_hide_item;
#endif
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
  toggle_window_visibility(MY_APPLICATION(user_data));
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

  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), separator);

  GtkWidget* quit_item = gtk_menu_item_new_with_label("Quit");
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_tray_quit), self);

  gtk_widget_show_all(self->tray_menu);
  app_indicator_set_menu(self->indicator, GTK_MENU(self->tray_menu));

  g_free(icon_path);
  g_free(icon_dir);
}
#endif

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
static gboolean on_window_delete(GtkWidget* /*widget*/,
                                 GdkEvent* /*event*/,
                                 gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
#ifdef HAVE_APPINDICATOR
  // If tray is available, minimize to tray instead of quitting.
  if (self->indicator) {
    gtk_widget_hide(GTK_WIDGET(self->window));
    if (self->show_hide_item)
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->show_hide_item), "Show");
    // Notify Dart that window was hidden.
    if (self->tray_channel) {
      fl_method_channel_invoke_method(
          self->tray_channel, "onWindowHidden", nullptr, nullptr, nullptr,
          nullptr);
    }
    return TRUE;  // Prevent destruction.
  }
#endif
  (void)self;
  return FALSE;  // Allow normal close.
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

  GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
  gtk_widget_show(GTK_WIDGET(header_bar));
  gtk_header_bar_set_title(header_bar, "UniClient");
  gtk_header_bar_set_show_close_button(header_bar, TRUE);
  gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

  gtk_window_set_default_size(window, 1280, 800);

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
#ifdef HAVE_APPINDICATOR
  g_clear_object(&self->indicator);
  if (self->tray_menu) {
    gtk_widget_destroy(self->tray_menu);
    self->tray_menu = nullptr;
  }
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
#ifdef HAVE_APPINDICATOR
  self->indicator = nullptr;
  self->tray_menu = nullptr;
  self->show_hide_item = nullptr;
#endif
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_DEFAULT_FLAGS,
                                     nullptr));
}
