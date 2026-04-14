#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  struct Point { unsigned int x; unsigned int y; Point(unsigned int x, unsigned int y) : x(x), y(y) {} };
  struct Size { unsigned int width; unsigned int height; Size(unsigned int width, unsigned int height) : width(width), height(height) {} };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title, const Point& origin, const Size& size);
  void Show();
  void SetQuitOnClose(bool quit);
  HWND GetHandle();

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  virtual LRESULT MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                                 LPARAM const lparam) noexcept;
  void SetChildContent(HWND content);
  RECT GetClientArea();

 private:
  friend class Win32WindowImpl;
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept;
  static Win32Window* GetThisFromHandle(HWND window) noexcept;

  bool quit_on_close_ = false;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
