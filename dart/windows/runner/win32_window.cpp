#include "win32_window.h"
#include <dwmapi.h>
#include <flutter_windows.h>
#pragma comment(lib, "dwmapi.lib")

namespace {
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) return;
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}
}  // namespace

Win32Window::Win32Window() {}

Win32Window::~Win32Window() {
  Destroy();
}

bool Win32Window::Create(const std::wstring& title, const Point& origin, const Size& size) {
  Destroy();

  const wchar_t* window_class = WindowClassName();
  WNDCLASS window_class_info = {};
  window_class_info.style = CS_HREDRAW | CS_VREDRAW;
  window_class_info.lpfnWndProc = WndProc;
  window_class_info.hInstance = GetModuleHandle(nullptr);
  window_class_info.lpszClassName = window_class;
  window_class_info.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&window_class_info);

  RECT rect = {0, 0, static_cast<LONG>(size.width), static_cast<LONG>(size.height)};
  AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

  window_handle_ = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, FlutterDesktopGetDpiForMonitor(MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY))),
      Scale(origin.y, FlutterDesktopGetDpiForMonitor(MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY))),
      rect.right - rect.left, rect.bottom - rect.top,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window_handle_) return false;

  UpdateTheme(window_handle_);
  return OnCreate();
}

Win32Window* Win32Window::GetThisFromHandle(HWND hwnd) noexcept {
  return reinterpret_cast<Win32Window*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame;
  GetClientRect(window_handle_, &frame);
  MoveWindow(content, frame.left, frame.top,
             frame.right - frame.left, frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() { return window_handle_; }

void Win32Window::SetQuitOnClose(bool quit) { quit_on_close_ = quit; }

void Win32Window::Show() { ShowWindow(window_handle_, SW_SHOW); }

bool Win32Window::OnCreate() { return true; }

void Win32Window::OnDestroy() {}

void Win32Window::Destroy() {
  OnDestroy();
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

const wchar_t* Win32Window::WindowClassName() { return kWindowClassName; }

int Win32Window::Scale(int source, UINT dpi) {
  return static_cast<int>(source * dpi / 96.0);
}

void Win32Window::UpdateTheme(HWND hwnd) {
  BOOL dark = TRUE;
  DwmSetWindowAttribute(hwnd, 20, &dark, sizeof(dark));
}

LRESULT CALLBACK Win32Window::WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    auto that = static_cast<Win32Window*>(cs->lpCreateParams);
    EnableFullDpiSupportIfAvailable(hwnd);
    that->window_handle_ = hwnd;
  } else if (Win32Window* that = GetThisFromHandle(hwnd)) {
    return that->MessageHandler(hwnd, message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                    WPARAM const wparam, LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      OnDestroy();
      if (quit_on_close_) PostQuitMessage(0);
      return 0;
    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top,
                   newRectSize->right - newRectSize->left, newRectSize->bottom - newRectSize->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_SIZE: {
      RECT frame;
      GetClientRect(hwnd, &frame);
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, frame.left, frame.top,
                   frame.right - frame.left, frame.bottom - frame.top, TRUE);
      }
      return 0;
    }
    case WM_ACTIVATE:
      if (child_content_ != nullptr) SetFocus(child_content_);
      return 0;
    case WM_SETTINGCHANGE:
      UpdateTheme(hwnd);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
