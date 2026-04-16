#include "my_application.h"
#include <stdlib.h>

int main(int argc, char** argv) {
  // Force native Wayland — never fall back to XWayland.
  setenv("GDK_BACKEND", "wayland", 1);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
