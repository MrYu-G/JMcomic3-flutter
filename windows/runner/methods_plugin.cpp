#include "methods_plugin.h"
#include <iostream>
#include <optional>
#include <thread>
#include <windows.h>
#include <netlistmgr.h>
#include "../rust.h"


void InvokeThread(std::string params, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    char* result_chars = invoke_ffi(params.c_str());
    result->Success(flutter::EncodableValue(std::string(result_chars)));
    free_str_ffi(result_chars);
}

namespace {

    flutter::EncodableValue DeviceStatus() {
        SYSTEM_POWER_STATUS power{};
        const bool has_power = GetSystemPowerStatus(&power) != FALSE;
        flutter::EncodableValue level;
        if (has_power && power.BatteryLifePercent <= 100 &&
            power.BatteryFlag != 255 && (power.BatteryFlag & 128) == 0) {
            level = flutter::EncodableValue(static_cast<int>(power.BatteryLifePercent));
        }
        // Query Windows connectivity without probing an external server. COM
        // may already be initialized by Flutter on this platform thread.
        std::string network = "unknown";
        const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        if (SUCCEEDED(initialized) || initialized == RPC_E_CHANGED_MODE) {
            INetworkListManager* manager = nullptr;
            if (SUCCEEDED(CoCreateInstance(CLSID_NetworkListManager, nullptr,
                    CLSCTX_ALL, IID_INetworkListManager,
                    reinterpret_cast<void**>(&manager)))) {
                VARIANT_BOOL connected = VARIANT_FALSE;
                if (SUCCEEDED(manager->get_IsConnectedToInternet(&connected))) {
                    network = connected == VARIANT_TRUE ? "connected" : "none";
                }
                manager->Release();
            }
            if (SUCCEEDED(initialized)) CoUninitialize();
        }
        return flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("battery_level"), level},
            {flutter::EncodableValue("charging"), flutter::EncodableValue(
                has_power && power.BatteryFlag != 255 && (power.BatteryFlag & 8) != 0)},
            {flutter::EncodableValue("network"), flutter::EncodableValue(network)},
        });
    }

    class MethodsPlugin : public flutter::Plugin {
    public:
        static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

        MethodsPlugin();

        virtual ~MethodsPlugin();

    private:
        // Called when a method is called on this plugin's channel from Dart.
        void HandleMethodCall(
                const flutter::MethodCall<flutter::EncodableValue> &method_call,
                std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
    };

// static
    void MethodsPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarWindows *registrar) {
        auto channel =
                std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
                        registrar->messenger(), "methods",
                                &flutter::StandardMethodCodec::GetInstance());

        auto plugin = std::make_unique<MethodsPlugin>();

        channel->SetMethodCallHandler(
                [plugin_pointer = plugin.get()](const auto &call, auto result) {
                    plugin_pointer->HandleMethodCall(call, std::move(result));
                });

        registrar->AddPlugin(std::move(plugin));
    }

    MethodsPlugin::MethodsPlugin() {}

    MethodsPlugin::~MethodsPlugin() {}

    void MethodsPlugin::HandleMethodCall(
            const flutter::MethodCall<flutter::EncodableValue> &method_call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

        if (method_call.method_name() == "device_status") {
            result->Success(DeviceStatus());
            return;
        }
        if (method_call.method_name().compare("invoke") == 0) {
            const auto *arguments = std::get_if<std::string>(method_call.arguments());
            std::thread t(InvokeThread, std::string(*arguments),std::move(result));
            t.detach();
            return;
        } else {
            result->NotImplemented();
        }

    }

}  // namespace


void MethodsPluginRegisterWithRegistrar(
        FlutterDesktopPluginRegistrarRef registrar) {
    MethodsPlugin::RegisterWithRegistrar(
            flutter::PluginRegistrarManager::GetInstance()
                    ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
