#include "flutter_window.h"
#include <optional>
#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetUpWindowChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::SetUpWindowChannel() {
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.uniclient.app/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        HWND hwnd = GetHandle();
        if (!hwnd) {
          result->Error("no_window", "Window not available");
          return;
        }
        if (method == "minimize") {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success();
        } else if (method == "maximize") {
          ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
        } else if (method == "close") {
          PostMessage(hwnd, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "startDrag") {
          // Hand off to the system move loop (Dart calls this on title-bar drag).
          ReleaseCapture();
          SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (method == "showWindowMenu") {
          POINT pt;
          GetCursorPos(&pt);
          HMENU menu = GetSystemMenu(hwnd, FALSE);
          if (menu) {
            const int cmd = TrackPopupMenu(
                menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd,
                nullptr);
            if (cmd) PostMessage(hwnd, WM_SYSCOMMAND, cmd, 0);
          }
          result->Success();
        } else if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != 0));
        } else if (method == "getButtonLayout") {
          // Windows convention: minimize/maximize/close on the right.
          result->Success(
              flutter::EncodableValue(std::string(":minimize,maximize,close")));
        } else if (method == "getOneSideControls") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "getResizeEnabled") {
          result->Success(flutter::EncodableValue(true));
        } else if (method == "setDecorated") {
          bool decorated = true;
          const auto* args = call.arguments();
          if (args && std::holds_alternative<bool>(*args)) {
            decorated = std::get<bool>(*args);
          }
          SetFrameless(!decorated);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Mirror the Linux runner: push window-state changes to the custom titlebar.
  switch (message) {
    case WM_SIZE: {
      const bool maximized = IsZoomed(hwnd) != 0;
      if (window_channel_ && maximized != last_maximized_) {
        last_maximized_ = maximized;
        window_channel_->InvokeMethod(
            "maximizeChanged",
            std::make_unique<flutter::EncodableValue>(maximized));
      }
      break;
    }
    case WM_ACTIVATE:
      if (window_channel_) {
        window_channel_->InvokeMethod(
            "windowFocusChanged",
            std::make_unique<flutter::EncodableValue>(
                LOWORD(wparam) != WA_INACTIVE));
      }
      break;
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
