#ifndef IANVS_WINDOW_BRIDGE_H_
#define IANVS_WINDOW_BRIDGE_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
void ianvs_window_bridge_register(GtkWindow* window, FlView* view);
#endif
