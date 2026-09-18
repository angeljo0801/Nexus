package com.nexus.bridge;

import android.content.Context;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import androidx.annotation.NonNull;

import java.io.File;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class NexusAndroidBridgePlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private MethodChannel channel;
    private Context context;
    private ParcelFileDescriptor sharedModelDescriptor;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(
                binding.getBinaryMessenger(),
                "com.nexus/shared_model"
        );
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(
            @NonNull MethodCall call,
            @NonNull MethodChannel.Result result
    ) {
        switch (call.method) {
            case "openSharedModel":
                openSharedModel(call, result);
                break;
            case "closeSharedModel":
                closeSharedModel();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void openSharedModel(
            MethodCall call,
            MethodChannel.Result result
    ) {
        final String raw = call.argument("uri");
        if (raw == null || raw.trim().isEmpty()) {
            result.error(
                    "INVALID_URI",
                    "No external model URI was provided.",
                    null
            );
            return;
        }

        try {
            closeSharedModel();
            final Uri uri = Uri.parse(raw);
            if ("file".equals(uri.getScheme())) {
                final String path = uri.getPath();
                if (path == null || !new File(path).exists()) {
                    result.error(
                            "MISSING_FILE",
                            "The external model file no longer exists.",
                            null
                    );
                    return;
                }
                result.success(path);
                return;
            }

            final ParcelFileDescriptor descriptor =
                    context.getContentResolver().openFileDescriptor(uri, "r");
            sharedModelDescriptor = descriptor;
            if (descriptor == null) {
                result.error(
                        "OPEN_FAILED",
                        "Android could not open the external model.",
                        null
                );
                return;
            }

            result.success("/proc/self/fd/" + descriptor.getFd());
        } catch (Exception error) {
            result.error("OPEN_FAILED", error.getMessage(), null);
        }
    }

    private void closeSharedModel() {
        if (sharedModelDescriptor == null) {
            return;
        }
        try {
            sharedModelDescriptor.close();
        } catch (Exception ignored) {
        }
        sharedModelDescriptor = null;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        closeSharedModel();
        if (channel != null) {
            channel.setMethodCallHandler(null);
        }
        channel = null;
        context = null;
    }
}
