#include "window_bridge.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxTransferBytes = 64 * 1024 * 1024;
using Bytes = std::vector<uint8_t>;
using MimeData = std::map<std::string, Bytes>;
struct Bridge {
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* channel;
  FlMethodChannel* shutdown;
  bool closing = false;
  guint shutdown_timer = 0;
  guint shutdown_generation = 0;
  GCancellable* shutdown_cancellable = nullptr;
  bool drop_enabled = false;
  std::string session_id;
  std::vector<std::string> mime_types;
  int drop_operation = 0;
  int drag_x = 0;
  int drag_y = 0;
  guint32 drag_time = 0;
  GdkDragContext* pending_context = nullptr;
  guint32 pending_time = 0;
  std::set<std::string> pending_types;
  bool pending_failed = false;
  guint drop_sequence = 0;
  MimeData pending_data;
  std::map<std::string, MimeData> drops;
  std::map<std::string, guint32> notifications;
};
FlValue* lookup(FlValue* args, const char* name) {
  return args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(args, name)
             : nullptr;
}
const char* string_value(FlValue* value, const char* fallback = "") {
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : fallback;
}
const char* string_arg(FlValue* args, const char* name) {
  return string_value(lookup(args, name));
}
int64_t int_arg(FlValue* args, const char* name, int64_t fallback = 0) {
  FlValue* value = lookup(args, name);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value)
             : fallback;
}
double number_arg(FlValue* args, const char* name) {
  FlValue* value = lookup(args, name);
  if (!value) return 0;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT)
    return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT)
    return fl_value_get_int(value);
  return 0;
}
bool bool_arg(FlValue* args, const char* name) {
  FlValue* value = lookup(args, name);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}
void result(FlMethodCall* call, FlValue* value = nullptr) {
  fl_method_call_respond_success(call, value, nullptr);
}
void error(FlMethodCall* call, const char* code, const char* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}
void map_string(FlValue* value, const char* name, const char* text) {
  fl_value_set_string_take(value, name, fl_value_new_string(text));
}
void map_int(FlValue* value, const char* name, int64_t number) {
  fl_value_set_string_take(value, name, fl_value_new_int(number));
}
void map_bool(FlValue* value, const char* name, bool enabled) {
  fl_value_set_string_take(value, name, fl_value_new_bool(enabled));
}
void cancel_pending_drop(Bridge* bridge);
struct ShutdownRequest {
  GtkWindow* window;
  guint generation;
};
void shutdown_warning(Bridge* bridge) {
  GtkWidget* dialog = gtk_message_dialog_new(
      bridge->window, GTK_DIALOG_MODAL, GTK_MESSAGE_WARNING, GTK_BUTTONS_CLOSE,
      "Trail could not safely finish saving and closing its sessions.");
  gtk_message_dialog_format_secondary_text(
      GTK_MESSAGE_DIALOG(dialog),
      "The window has been kept open to protect your data. Wait and try "
      "closing it again.");
  gtk_dialog_run(GTK_DIALOG(dialog));
  gtk_widget_destroy(dialog);
}
void release_shutdown_request(gpointer data) {
  auto* request = static_cast<ShutdownRequest*>(data);
  g_object_unref(request->window);
  delete request;
}
gboolean shutdown_timeout(gpointer data) {
  auto* request = static_cast<ShutdownRequest*>(data);
  auto* bridge = static_cast<Bridge*>(
      g_object_get_data(G_OBJECT(request->window), "ianvs-bridge"));
  if (bridge && bridge->shutdown_generation == request->generation) {
    bridge->shutdown_timer = 0;
    ++bridge->shutdown_generation;
    bridge->closing = false;
    g_cancellable_cancel(bridge->shutdown_cancellable);
    g_clear_object(&bridge->shutdown_cancellable);
    shutdown_warning(bridge);
  }
  return G_SOURCE_REMOVE;
}
void shutdown_response(GObject* object, GAsyncResult* response, gpointer data) {
  auto* request = static_cast<ShutdownRequest*>(data);
  auto* bridge = static_cast<Bridge*>(
      g_object_get_data(G_OBJECT(request->window), "ianvs-bridge"));
  g_autoptr(GError) failure = nullptr;
  g_autoptr(FlMethodResponse) reply = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), response, &failure);
  if (bridge && bridge->shutdown_generation == request->generation) {
    if (bridge->shutdown_timer) {
      g_source_remove(bridge->shutdown_timer);
      bridge->shutdown_timer = 0;
    }
    g_clear_object(&bridge->shutdown_cancellable);
    FlValue* value = reply && FL_IS_METHOD_SUCCESS_RESPONSE(reply)
                         ? fl_method_success_response_get_result(
                               FL_METHOD_SUCCESS_RESPONSE(reply))
                         : nullptr;
    auto is_false = [value](const char* name) {
      FlValue* flag = lookup(value, name);
      return flag && fl_value_get_type(flag) == FL_VALUE_TYPE_BOOL &&
             !fl_value_get_bool(flag);
    };
    bool safe = bool_arg(value, "completed") &&
                bool_arg(value, "safeToTerminate") && is_false("timedOut") &&
                is_false("unsafeToTerminate");
    if (safe) {
      // Match Flutter's application-exit path. Destroying the implicit FlView
      // directly races engine/plugin disposal and attempts RemoveView(0).
      bridge->drop_enabled = false;
      cancel_pending_drop(bridge);
      fl_method_channel_set_method_call_handler(bridge->channel, nullptr,
                                                nullptr, nullptr);
      g_clear_object(&bridge->channel);
      g_clear_object(&bridge->shutdown);
      g_autoptr(GApplication) application = G_APPLICATION(
          g_object_ref(gtk_window_get_application(request->window)));
      g_autoptr(GList) windows = g_list_copy(
          gtk_application_get_windows(GTK_APPLICATION(application)));
      for (GList* item = windows; item; item = item->next) {
        gtk_window_set_application(GTK_WINDOW(item->data), nullptr);
      }
      g_application_quit(application);
    } else {
      bridge->closing = false;
      shutdown_warning(bridge);
    }
  }
  release_shutdown_request(data);
}
gboolean close_window(GtkWidget*, GdkEvent*, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  if (!bridge->closing) {
    bridge->closing = true;
    ++bridge->shutdown_generation;
    bridge->shutdown_cancellable = g_cancellable_new();
    auto* timeout = new ShutdownRequest{
        GTK_WINDOW(g_object_ref(bridge->window)), bridge->shutdown_generation};
    bridge->shutdown_timer =
        g_timeout_add_full(G_PRIORITY_DEFAULT, 10000, shutdown_timeout, timeout,
                           release_shutdown_request);
    auto* request = new ShutdownRequest{
        GTK_WINDOW(g_object_ref(bridge->window)), bridge->shutdown_generation};
    fl_method_channel_invoke_method(bridge->shutdown, "requestShutdown",
                                    nullptr, bridge->shutdown_cancellable,
                                    shutdown_response, request);
  }
  return TRUE;
}
void clipboard_get(GtkClipboard*, GtkSelectionData* selection, guint,
                   gpointer data) {
  auto* items = static_cast<MimeData*>(data);
  g_autofree gchar* name =
      gdk_atom_name(gtk_selection_data_get_target(selection));
  auto found = items->find(name ? name : "");
  if (found == items->end()) return;
  gtk_selection_data_set(selection, gtk_selection_data_get_target(selection), 8,
                         found->second.data(), found->second.size());
}
void clipboard_clear(GtkClipboard*, gpointer data) {
  delete static_cast<MimeData*>(data);
}
void choose_file(Bridge* bridge, FlMethodCall* call, const char* method,
                 FlValue* args) {
  bool folder = !strcmp(method, "chooseTerminalFolder") ||
                !strcmp(method, "chooseZmodemReceiveDirectory");
  bool save = !strcmp(method, "chooseFileDownloadLocation");
  bool multiple = !strcmp(method, "chooseZmodemSendFiles");
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      save     ? "Save download"
      : folder ? "Choose folder"
               : "Open file",
      bridge->window,
      save     ? GTK_FILE_CHOOSER_ACTION_SAVE
      : folder ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER
               : GTK_FILE_CHOOSER_ACTION_OPEN,
      "Cancel", GTK_RESPONSE_CANCEL, save ? "Save" : "Open",
      GTK_RESPONSE_ACCEPT, nullptr);
  auto* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_local_only(chooser, TRUE);
  gtk_file_chooser_set_select_multiple(chooser, multiple);
  if (save) {
    gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
    g_autofree gchar* basename =
        g_path_get_basename(string_arg(args, "suggestedName"));
    gtk_file_chooser_set_current_name(chooser,
                                      *basename ? basename : "download");
  }
  const char* directory = string_arg(args, "initialDirectory");
  if (*directory && g_file_test(directory, G_FILE_TEST_IS_DIR))
    gtk_file_chooser_set_current_folder(chooser, directory);
  g_autoptr(FlValue) value = nullptr;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    if (multiple) {
      value = fl_value_new_list();
      GSList* files = gtk_file_chooser_get_filenames(chooser);
      for (auto* item = files; item; item = item->next)
        fl_value_append_take(
            value, fl_value_new_string(static_cast<char*>(item->data)));
      g_slist_free_full(files, g_free);
    } else {
      g_autofree gchar* path = gtk_file_chooser_get_filename(chooser);
      if (path) value = fl_value_new_string(path);
    }
  }
  gtk_widget_destroy(dialog);
  result(call, value);
}
bool allowed_url(const char* url) {
  g_autoptr(GError) failure = nullptr;
  g_autoptr(GUri) uri = g_uri_parse(url, G_URI_FLAGS_NONE, &failure);
  if (!uri) return false;
  const char* scheme = g_uri_get_scheme(uri);
  return scheme && ((!strcmp(scheme, "file") && g_uri_get_path(uri) &&
                     *g_uri_get_path(uri)) ||
                    ((!strcmp(scheme, "http") || !strcmp(scheme, "https")) &&
                     g_uri_get_host(uri) && *g_uri_get_host(uri)));
}
GDBusConnection* session_bus(GError** failure) {
  return g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, failure);
}
void notification(Bridge* bridge, FlMethodCall* call, FlValue* args,
                  bool close) {
  const std::string identifier = string_arg(args, "identifier");
  g_autoptr(GError) failure = nullptr;
  g_autoptr(GDBusConnection) bus = session_bus(&failure);
  if (!bus) {
    error(call, "notification_delivery_failed", failure->message);
    return;
  }
  GVariant* parameters = nullptr;
  if (close) {
    auto found = bridge->notifications.find(identifier);
    if (found == bridge->notifications.end()) {
      result(call);
      return;
    }
    parameters = g_variant_new("(u)", found->second);
  } else {
    GVariantBuilder actions, hints;
    g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
    g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
    guint32 replaces = bridge->notifications.count(identifier)
                           ? bridge->notifications[identifier]
                           : 0;
    parameters = g_variant_new(
        "(susssasa{sv}i)", "Trail", replaces, "utilities-terminal",
        string_arg(args, "title"), string_arg(args, "body"), &actions, &hints,
        static_cast<gint>(std::clamp<int64_t>(
            int_arg(args, "expiresAfterMs", -1), -1, G_MAXINT)));
  }
  g_autoptr(GVariant) response = g_dbus_connection_call_sync(
      bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", close ? "CloseNotification" : "Notify",
      parameters, close ? nullptr : G_VARIANT_TYPE("(u)"),
      G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &failure);
  if (!response) {
    error(call, "notification_delivery_failed", failure->message);
    return;
  }
  if (close)
    bridge->notifications.erase(identifier);
  else if (!identifier.empty()) {
    guint32 id;
    g_variant_get(response, "(u)", &id);
    bridge->notifications[identifier] = id;
  }
  result(call);
}
bool mime_matches(Bridge* bridge, const char* mime) {
  for (const auto& pattern : bridge->mime_types) {
    if (pattern == mime || pattern == "*/*") return true;
    auto slash = pattern.find('/');
    if (slash != std::string::npos && pattern.substr(slash) == "/*" &&
        !strncmp(pattern.c_str(), mime, slash + 1))
      return true;
  }
  return false;
}
std::vector<std::string> drag_types(Bridge* bridge, GdkDragContext* context) {
  std::vector<std::string> types;
  for (GList* node = gdk_drag_context_list_targets(context); node;
       node = node->next) {
    g_autofree gchar* name = gdk_atom_name(static_cast<GdkAtom>(node->data));
    if (name && mime_matches(bridge, name)) types.emplace_back(name);
  }
  return types;
}
int operation_mask(GdkDragAction action) {
  return ((action & GDK_ACTION_COPY) ? 1 : 0) |
         ((action & GDK_ACTION_MOVE) ? 2 : 0) |
         ((action & GDK_ACTION_LINK) ? 4 : 0);
}
void drag_event(Bridge* bridge, const char* phase, GdkDragContext* context,
                const char* drop_id = nullptr) {
  if (!bridge->drop_enabled) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  map_string(event, "phase", phase);
  map_string(event, "sessionId", bridge->session_id.c_str());
  g_autoptr(FlValue) types = fl_value_new_list();
  for (const auto& mime : drag_types(bridge, context))
    fl_value_append_take(types, fl_value_new_string(mime.c_str()));
  fl_value_set_string(event, "mimeTypes", types);
  // Flutter uses logical coordinates, as GTK does at the widget boundary.
  fl_value_set_string_take(event, "x", fl_value_new_float(bridge->drag_x));
  fl_value_set_string_take(event, "y", fl_value_new_float(bridge->drag_y));
  map_int(event, "operations",
          operation_mask(gdk_drag_context_get_actions(context)));
  if (drop_id) map_string(event, "dropId", drop_id);
  fl_method_channel_invoke_method(bridge->channel, "osc72DragEvent", event,
                                  nullptr, nullptr, nullptr);
}
gboolean drag_motion(GtkWidget*, GdkDragContext* context, gint x, gint y,
                     guint time, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  if (!bridge->drop_enabled || drag_types(bridge, context).empty())
    return FALSE;
  bool entering = bridge->drag_time == 0;
  bridge->drag_x = x;
  bridge->drag_y = y;
  bridge->drag_time = time;
  drag_event(bridge, entering ? "enter" : "update", context);
  GdkDragAction action = bridge->drop_operation == 1   ? GDK_ACTION_COPY
                         : bridge->drop_operation == 2 ? GDK_ACTION_MOVE
                         : bridge->drop_operation == 4
                             ? GDK_ACTION_LINK
                             : static_cast<GdkDragAction>(0);
  gdk_drag_status(context,
                  static_cast<GdkDragAction>(
                      action & gdk_drag_context_get_actions(context)),
                  time);
  return TRUE;
}
void drag_leave(GtkWidget*, GdkDragContext* context, guint, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  drag_event(bridge, "leave", context);
  bridge->drag_time = 0;
}
void cancel_pending_drop(Bridge* bridge) {
  if (bridge->pending_context) {
    gtk_drag_finish(bridge->pending_context, FALSE, FALSE,
                    bridge->pending_time);
    g_clear_object(&bridge->pending_context);
  }
  bridge->pending_types.clear();
  bridge->pending_data.clear();
  bridge->pending_failed = false;
}
gboolean drag_drop(GtkWidget* widget, GdkDragContext* context, gint x, gint y,
                   guint time, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  auto types = drag_types(bridge, context);
  if (!bridge->drop_enabled || bridge->drop_operation == 0 || types.empty() ||
      bridge->pending_context)
    return FALSE;
  bridge->drag_x = x;
  bridge->drag_y = y;
  bridge->drag_time = time;
  bridge->pending_data.clear();
  bridge->pending_types = std::set<std::string>(types.begin(), types.end());
  bridge->pending_context = GDK_DRAG_CONTEXT(g_object_ref(context));
  bridge->pending_time = time;
  bridge->pending_failed = false;
  for (const auto& mime : types)
    gtk_drag_get_data(widget, context, gdk_atom_intern(mime.c_str(), FALSE),
                      time);
  return TRUE;
}
void drag_received(GtkWidget*, GdkDragContext* context, gint, gint,
                   GtkSelectionData* selection, guint, guint time,
                   gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  if (bridge->pending_context != context) return;
  int length = gtk_selection_data_get_length(selection);
  size_t total = 0;
  for (const auto& item : bridge->pending_data) total += item.second.size();
  g_autofree gchar* mime =
      gdk_atom_name(gtk_selection_data_get_target(selection));
  if (!mime || bridge->pending_types.erase(mime) == 0) return;
  if (length >= 0 && total + length <= kMaxTransferBytes) {
    const auto* bytes = gtk_selection_data_get_data(selection);
    bridge->pending_data[mime] = Bytes(bytes, bytes + length);
  } else
    bridge->pending_failed = true;
  if (!bridge->pending_types.empty()) return;
  bool accepted = !bridge->pending_failed && !bridge->pending_data.empty();
  if (accepted) {
    // Bound unconsumed external data even if the Dart owner disappears.
    if (bridge->drops.size() >= 4) bridge->drops.erase(bridge->drops.begin());
    std::string id = std::to_string(++bridge->drop_sequence);
    bridge->drops[id] = std::move(bridge->pending_data);
    drag_event(bridge, "drop", context, id.c_str());
  }
  gtk_drag_finish(context, accepted, FALSE, time);
  bridge->drag_time = 0;
  g_clear_object(&bridge->pending_context);
}
void handle_method(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (!strcmp(method, "setTitle")) {
    gtk_window_set_title(bridge->window, string_arg(args, "title"));
    result(call);
  } else if (!strcmp(method, "setTitleBarLayout"))
    result(call);
  else if (!strcmp(method, "resizeBy")) {
    int width, height;
    gtk_window_get_size(bridge->window, &width, &height);
    double dw = number_arg(args, "widthDelta"),
           dh = number_arg(args, "heightDelta");
    if (!std::isfinite(dw) || !std::isfinite(dh)) {
      error(call, "invalid_size", "Window size must be finite");
      return;
    }
    gtk_window_resize(bridge->window, std::clamp(width + dw, 320.0, 32768.0),
                      std::clamp(height + dh, 240.0, 32768.0));
    result(call);
  } else if (!strcmp(method, "windowMetrics")) {
    int width, height;
    gtk_window_get_size(bridge->window, &width, &height);
    g_autoptr(FlValue) metrics = fl_value_new_map();
    map_int(metrics, "frameWidth", width);
    map_int(metrics, "frameHeight", height);
    map_int(metrics, "contentWidth",
            gtk_widget_get_allocated_width(GTK_WIDGET(bridge->view)));
    map_int(metrics, "contentHeight",
            gtk_widget_get_allocated_height(GTK_WIDGET(bridge->view)));
    map_int(metrics, "devicePixelRatio",
            gtk_widget_get_scale_factor(GTK_WIDGET(bridge->view)));
    result(call, metrics);
  } else if (!strcmp(method, "requestQuitConfirmation")) {
    result(call);
    gtk_window_close(bridge->window);
  } else if (!strcmp(method, "requestUserAttention")) {
    gtk_window_set_urgency_hint(bridge->window, TRUE);
    g_autoptr(FlValue) id = fl_value_new_int(1);
    result(call, id);
  } else if (!strcmp(method, "cancelUserAttention")) {
    gtk_window_set_urgency_hint(bridge->window, FALSE);
    result(call);
  } else if (!strcmp(method, "chooseFileDownloadLocation") ||
             !strcmp(method, "chooseTerminalFolder") ||
             !strcmp(method, "chooseZmodemReceiveDirectory") ||
             !strcmp(method, "chooseZmodemSendFiles") ||
             !strcmp(method, "chooseRecordingFile"))
    choose_file(bridge, call, method, args);
  else if (!strcmp(method, "openExternalUrl") ||
           !strcmp(method, "revealInFinder")) {
    g_autoptr(GError) failure = nullptr;
    g_autofree gchar* uri = nullptr;
    if (!strcmp(method, "revealInFinder")) {
      const char* path = string_arg(args, "path");
      if (!*path || !g_file_test(path, G_FILE_TEST_EXISTS)) {
        error(call, "recording_path_missing", "The path does not exist");
        return;
      }
      g_autofree gchar* parent = g_file_test(path, G_FILE_TEST_IS_DIR)
                                     ? g_strdup(path)
                                     : g_path_get_dirname(path);
      uri = g_filename_to_uri(parent, nullptr, &failure);
    } else
      uri = g_strdup(string_arg(args, "url"));
    if (!uri || !allowed_url(uri)) {
      error(call, "unsupported_url_scheme",
            "Only valid HTTP, HTTPS, and file URLs are allowed");
      return;
    }
    if (!gtk_show_uri_on_window(bridge->window, uri, GDK_CURRENT_TIME,
                                &failure))
      error(call, "open_failed", failure->message);
    else
      result(call);
  } else if (!strcmp(method, "movePathToTrash")) {
    const char* path = string_arg(args, "path");
    if (!*path || !g_file_test(path, G_FILE_TEST_EXISTS)) {
      error(call, "recording_path_missing", "The path does not exist");
      return;
    }
    g_autoptr(GFile) file = g_file_new_for_path(path);
    g_autoptr(GError) failure = nullptr;
    if (!g_file_trash(file, nullptr, &failure))
      error(call, "recording_trash_failed", failure->message);
    else {
      g_autoptr(FlValue) value = fl_value_new_bool(TRUE);
      result(call, value);
    }
  } else if (!strcmp(method, "showNotification") ||
             !strcmp(method, "closeNotification"))
    notification(bridge, call, args, !strcmp(method, "closeNotification"));
  else if (!strcmp(method, "writeClipboardText")) {
    const char* selection = string_arg(args, "selection");
    GdkAtom atom;
    if (!strcmp(selection, "c"))
      atom = GDK_SELECTION_CLIPBOARD;
    else if (!strcmp(selection, "p"))
      atom = GDK_SELECTION_PRIMARY;
    else if (!strcmp(selection, "s"))
      atom = GDK_SELECTION_SECONDARY;
    else {
      error(call, "unsupported_clipboard_selection",
            "This desktop does not provide the requested named clipboard");
      return;
    }
    GtkClipboard* clipboard = gtk_clipboard_get(atom);
    if (!clipboard) {
      error(call, "unsupported_clipboard_selection",
            "The requested selection is unavailable");
      return;
    }
    gtk_clipboard_set_text(clipboard, string_arg(args, "text"), -1);
    result(call);
  } else if (!strcmp(method, "writeClipboardMime")) {
    FlValue* list = lookup(args, "items");
    if (!list || fl_value_get_type(list) != FL_VALUE_TYPE_LIST) {
      error(call, "invalid_clipboard", "Expected clipboard MIME items");
      return;
    }
    auto* items = new MimeData();
    size_t size = 0;
    for (size_t i = 0; i < fl_value_get_length(list); ++i) {
      FlValue* item = fl_value_get_list_value(list, i);
      FlValue* bytes = lookup(item, "data");
      std::string mime = string_arg(item, "mime");
      if (mime.empty() || !bytes ||
          fl_value_get_type(bytes) != FL_VALUE_TYPE_UINT8_LIST)
        continue;
      size += fl_value_get_length(bytes);
      if (size > kMaxTransferBytes) {
        delete items;
        error(call, "clipboard_too_large", "Clipboard data exceeds 64 MiB");
        return;
      }
      (*items)[mime] =
          Bytes(fl_value_get_uint8_list(bytes),
                fl_value_get_uint8_list(bytes) + fl_value_get_length(bytes));
      FlValue* aliases = lookup(item, "aliases");
      if (aliases && fl_value_get_type(aliases) == FL_VALUE_TYPE_LIST)
        for (size_t j = 0; j < fl_value_get_length(aliases); ++j) {
          const char* alias = string_value(fl_value_get_list_value(aliases, j));
          if (*alias) (*items)[alias] = (*items)[mime];
        }
      if (mime == "text/plain") {
        (*items)["UTF8_STRING"] = (*items)[mime];
        (*items)["text/plain;charset=utf-8"] = (*items)[mime];
      }
    }
    std::vector<GtkTargetEntry> targets;
    for (const auto& item : *items)
      targets.push_back({const_cast<gchar*>(item.first.c_str()), 0, 0});
    if (targets.empty() ||
        !gtk_clipboard_set_with_data(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
                                     targets.data(), targets.size(),
                                     clipboard_get, clipboard_clear, items)) {
      delete items;
      error(call, "clipboard_write_failed", "No clipboard target was accepted");
      return;
    }
    result(call);
  } else if (!strcmp(method, "listClipboardMimeTypes")) {
    GdkAtom* targets = nullptr;
    gint count = 0;
    g_autoptr(FlValue) list = fl_value_new_list();
    if (gtk_clipboard_wait_for_targets(
            gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), &targets, &count)) {
      for (gint i = 0; i < count; ++i) {
        g_autofree gchar* name = gdk_atom_name(targets[i]);
        if (name && strchr(name, '/'))
          fl_value_append_take(list, fl_value_new_string(name));
      }
      g_free(targets);
    }
    result(call, list);
  } else if (!strcmp(method, "readClipboardMime")) {
    FlValue* requested = lookup(args, "mimeTypes");
    g_autoptr(FlValue) response = fl_value_new_map();
    g_autoptr(FlValue) items = fl_value_new_list();
    size_t total = 0;
    std::set<std::string> selected;
    GdkAtom* offered = nullptr;
    gint offered_count = 0;
    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    if (requested && fl_value_get_type(requested) == FL_VALUE_TYPE_LIST &&
        gtk_clipboard_wait_for_targets(clipboard, &offered, &offered_count)) {
      for (gint j = 0; j < offered_count; ++j) {
        g_autofree gchar* mime = gdk_atom_name(offered[j]);
        if (!mime || !strchr(mime, '/')) continue;
        for (size_t i = 0; i < fl_value_get_length(requested); ++i) {
          const char* pattern =
              string_value(fl_value_get_list_value(requested, i));
          if (g_pattern_match_simple(pattern, mime)) selected.insert(mime);
        }
      }
      g_free(offered);
    }
    for (const auto& mime : selected) {
      GtkSelectionData* content = gtk_clipboard_wait_for_contents(
          clipboard, gdk_atom_intern(mime.c_str(), FALSE));
      if (!content) continue;
      int length = gtk_selection_data_get_length(content);
      if (length >= 0 && total + length <= kMaxTransferBytes) {
        total += length;
        FlValue* item = fl_value_new_map();
        map_string(item, "mime", mime.c_str());
        fl_value_set_string_take(
            item, "data",
            fl_value_new_uint8_list(gtk_selection_data_get_data(content),
                                    length));
        fl_value_append_take(items, item);
      }
      gtk_selection_data_free(content);
    }
    fl_value_set_string(response, "items", items);
    result(call, response);
  } else if (!strcmp(method, "configureOsc72DropTarget")) {
    // A target change revokes the previous session's in-flight payload.
    cancel_pending_drop(bridge);
    bridge->drops.clear();
    bridge->drop_enabled = bool_arg(args, "enabled");
    bridge->session_id = string_arg(args, "sessionId");
    bridge->mime_types.clear();
    bridge->drop_operation = 0;
    FlValue* types = lookup(args, "mimeTypes");
    if (types && fl_value_get_type(types) == FL_VALUE_TYPE_LIST)
      for (size_t i = 0; i < fl_value_get_length(types); ++i)
        bridge->mime_types.emplace_back(
            string_value(fl_value_get_list_value(types, i)));
    if (!bridge->drop_enabled) {
      bridge->drops.clear();
      bridge->pending_data.clear();
      bridge->pending_types.clear();
    }
    result(call);
  } else if (!strcmp(method, "setOsc72DropDecision")) {
    bridge->drop_operation = int_arg(args, "operation");
    result(call);
  } else if (!strcmp(method, "releaseOsc72Drop")) {
    bridge->drops.erase(string_arg(args, "dropId"));
    result(call);
  } else if (!strcmp(method, "readOsc72DropData")) {
    auto drop = bridge->drops.find(string_arg(args, "dropId"));
    const std::string mime = string_arg(args, "mimeType");
    if (drop == bridge->drops.end() || !drop->second.count(mime)) {
      error(call, "drop_not_found", "Drop data is no longer available");
      return;
    }
    const auto& bytes = drop->second.at(mime);
    auto offset = int_arg(args, "offset");
    auto limit = int_arg(args, "maxBytes", 3072);
    if (offset < 0 || static_cast<size_t>(offset) > bytes.size() ||
        limit <= 0 || limit > 1024 * 1024) {
      error(call, "invalid_range", "Invalid drop byte range");
      return;
    }
    size_t length = std::min<size_t>(limit, bytes.size() - offset);
    g_autoptr(FlValue) response = fl_value_new_map();
    fl_value_set_string_take(
        response, "bytes",
        fl_value_new_uint8_list(bytes.data() + offset, length));
    map_bool(response, "eof", offset + length == bytes.size());
    map_int(response, "size", bytes.size());
    result(call, response);
  } else if (!strcmp(method, "osc72DropTargetStatus")) {
    g_autoptr(FlValue) status = fl_value_new_map();
    map_bool(status, "enabled", bridge->drop_enabled);
    map_string(status, "sessionId", bridge->session_id.c_str());
    g_autoptr(FlValue) types = fl_value_new_list();
    for (const auto& type : bridge->mime_types)
      fl_value_append_take(types, fl_value_new_string(type.c_str()));
    fl_value_set_string(status, "mimeTypes", types);
    map_int(status, "decision", bridge->drop_operation);
    map_int(status, "cachedDrops", bridge->drops.size());
    result(call, status);
  } else
    fl_method_call_respond_not_implemented(call, nullptr);
}
void destroy_bridge(gpointer data) {
  auto* bridge = static_cast<Bridge*>(data);
  cancel_pending_drop(bridge);
  if (bridge->shutdown_timer) g_source_remove(bridge->shutdown_timer);
  if (bridge->shutdown_cancellable)
    g_cancellable_cancel(bridge->shutdown_cancellable);
  g_clear_object(&bridge->shutdown_cancellable);
  g_clear_object(&bridge->channel);
  g_clear_object(&bridge->shutdown);
  delete bridge;
}
}  // namespace
void ianvs_window_bridge_register(GtkWindow* window, FlView* view) {
  auto* bridge = new Bridge{};
  bridge->window = window;
  bridge->view = view;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  bridge->channel = fl_method_channel_new(messenger, "app/window_bridge",
                                          FL_METHOD_CODEC(codec));
  bridge->shutdown =
      fl_method_channel_new(messenger, "app/shutdown", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(bridge->channel, handle_method,
                                            bridge, nullptr);
  g_object_set_data_full(G_OBJECT(window), "ianvs-bridge", bridge,
                         destroy_bridge);
  g_signal_connect(window, "delete-event", G_CALLBACK(close_window), bridge);
  gtk_drag_dest_set(GTK_WIDGET(view), static_cast<GtkDestDefaults>(0), nullptr,
                    0,
                    static_cast<GdkDragAction>(
                        GDK_ACTION_COPY | GDK_ACTION_MOVE | GDK_ACTION_LINK));
  gtk_drag_dest_set_track_motion(GTK_WIDGET(view), TRUE);
  g_signal_connect(view, "drag-motion", G_CALLBACK(drag_motion), bridge);
  g_signal_connect(view, "drag-leave", G_CALLBACK(drag_leave), bridge);
  g_signal_connect(view, "drag-drop", G_CALLBACK(drag_drop), bridge);
  g_signal_connect(view, "drag-data-received", G_CALLBACK(drag_received),
                   bridge);
}
