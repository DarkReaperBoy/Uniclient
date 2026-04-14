#include "utils.h"
#include <windows.h>
#include <io.h>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE* unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) { _dup2(_fileno(stdout), 1); }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) { _dup2(_fileno(stdout), 2); }
    std::ios::sync_with_stdio();
    FlushConsoleInputBuffer(GetStdHandle(STD_INPUT_HANDLE));
  }
}

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return {};

  std::vector<std::string> command_line_arguments;
  for (int i = 1; i < argc; i++) {
    int len = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, nullptr, 0, nullptr, nullptr);
    if (len > 0) {
      std::string arg(len - 1, '\0');
      WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, arg.data(), len, nullptr, nullptr);
      command_line_arguments.push_back(arg);
    }
  }
  ::LocalFree(argv);
  return command_line_arguments;
}
