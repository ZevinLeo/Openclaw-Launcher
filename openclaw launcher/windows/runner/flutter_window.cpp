#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "dwmapi.lib")

namespace {
constexpr int kDwmUseImmersiveDarkMode = 20;
constexpr int kDwmCaptionColor = 35;
constexpr int kDwmTextColor = 36;
constexpr int kMinWindowWidth = 1280;
constexpr int kMinWindowHeight = 720;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "openclaw/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setNativeTitleBarTheme") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args == nullptr) {
            result->Error("bad_args", "Arguments should be a map.");
            return;
          }
          const auto it = args->find(flutter::EncodableValue("dark"));
          if (it == args->end()) {
            result->Error("bad_args", "Missing 'dark' parameter.");
            return;
          }
          const auto* dark = std::get_if<bool>(&it->second);
          if (dark == nullptr) {
            result->Error("bad_args", "'dark' should be a bool.");
            return;
          }
          SetNativeTitleBarTheme(*dark);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetNativeTitleBarTheme(bool use_dark) {
  const HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  const BOOL dark_mode = use_dark ? TRUE : FALSE;
  DwmSetWindowAttribute(hwnd, kDwmUseImmersiveDarkMode, &dark_mode,
                        sizeof(dark_mode));

  // Match the app's immersive bar palette.
  const COLORREF caption_color =
      use_dark ? RGB(24, 24, 27) : RGB(243, 244, 246);
  const COLORREF text_color = use_dark ? RGB(244, 244, 245) : RGB(31, 41, 55);
  DwmSetWindowAttribute(hwnd, kDwmCaptionColor, &caption_color,
                        sizeof(caption_color));
  DwmSetWindowAttribute(hwnd, kDwmTextColor, &text_color, sizeof(text_color));
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto* minmax_info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd);
      const int scaled_min_width =
          MulDiv(kMinWindowWidth, dpi == 0 ? USER_DEFAULT_SCREEN_DPI : dpi,
                 USER_DEFAULT_SCREEN_DPI);
      const int scaled_min_height =
          MulDiv(kMinWindowHeight, dpi == 0 ? USER_DEFAULT_SCREEN_DPI : dpi,
                 USER_DEFAULT_SCREEN_DPI);

      minmax_info->ptMinTrackSize.x = scaled_min_width;
      minmax_info->ptMinTrackSize.y = scaled_min_height;
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
