package com.nexus.bridge;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;

import androidx.annotation.NonNull;
import java.io.File;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

public final class NexusAndroidBridgePlugin
        implements FlutterPlugin,
        MethodChannel.MethodCallHandler,
        ActivityAware,
        PluginRegistry.RequestPermissionsResultListener {

    private static final String TERMUX_PACKAGE = "com.termux";
    private static final String TERMUX_RUN_PERMISSION =
            "com.termux.permission.RUN_COMMAND";
    private static final int TERMUX_PERMISSION_REQUEST = 7419;
    private static final int NOTIFICATION_PERMISSION_REQUEST = 7420;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private ParcelFileDescriptor sharedModelDescriptor;
    private MethodChannel.Result pendingPermissionResult;
    private MethodChannel.Result pendingNotificationPermissionResult;

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
            case "termuxStatus":
                result.success(termuxStatus());
                break;
            case "requestTermuxRunCommandPermission":
                requestTermuxPermission(result);
                break;
            case "openTermux":
                openTermux(result);
                break;
            case "runTermuxScript":
                runTermuxScript(call, result);
                break;
            case "requestTaskNotificationPermission":
                requestTaskNotificationPermission(result);
                break;
            case "startBackgroundTask":
                startBackgroundTask(call, result);
                break;
            case "updateBackgroundTask":
                updateBackgroundTask(call, result);
                break;
            case "stopBackgroundTask":
                stopBackgroundTask(result);
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

    private Map<String, Object> termuxStatus() {
        final Map<String, Object> status = new HashMap<>();
        boolean installed = false;
        String version = null;

        try {
            final PackageInfo info =
                    context.getPackageManager().getPackageInfo(TERMUX_PACKAGE, 0);
            installed = true;
            version = info.versionName;
        } catch (Exception ignored) {
        }

        final boolean permissionGranted =
                context.checkSelfPermission(TERMUX_RUN_PERMISSION) == PackageManager.PERMISSION_GRANTED;

        status.put("installed", installed);
        status.put("runCommandPermission", permissionGranted);
        if (version != null) {
            status.put("version", version);
        }
        return status;
    }

    private void requestTermuxPermission(MethodChannel.Result result) {
        if (context.checkSelfPermission(TERMUX_RUN_PERMISSION) == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }

        if (activity == null) {
            result.error(
                    "NO_ACTIVITY",
                    "Nexus must be visible to request the Termux permission.",
                    null
            );
            return;
        }

        if (pendingPermissionResult != null) {
            result.error(
                    "PERMISSION_PENDING",
                    "A Termux permission request is already active.",
                    null
            );
            return;
        }

        pendingPermissionResult = result;
        activity.requestPermissions(
                new String[]{TERMUX_RUN_PERMISSION},
                TERMUX_PERMISSION_REQUEST
        );
    }

    private void openTermux(MethodChannel.Result result) {
        try {
            final Intent intent =
                    context.getPackageManager().getLaunchIntentForPackage(
                            TERMUX_PACKAGE
                    );
            if (intent == null) {
                result.error("TERMUX_MISSING", "Termux is not installed.", null);
                return;
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            result.success(null);
        } catch (Exception error) {
            result.error("TERMUX_OPEN_FAILED", error.getMessage(), null);
        }
    }

    private void runTermuxScript(
            MethodCall call,
            MethodChannel.Result result
    ) {
        final String script = call.argument("script");
        final String label = call.argument("label");

        if (script == null || script.trim().isEmpty()) {
            result.error("EMPTY_SCRIPT", "No Termux script was provided.", null);
            return;
        }

        final Map<String, Object> status = termuxStatus();
        if (!Boolean.TRUE.equals(status.get("installed"))) {
            result.error("TERMUX_MISSING", "Termux is not installed.", null);
            return;
        }
        if (!Boolean.TRUE.equals(status.get("runCommandPermission"))) {
            result.error(
                    "TERMUX_PERMISSION",
                    "Grant Nexus permission to run commands in Termux.",
                    null
            );
            return;
        }

        try {
            final Intent intent = new Intent();
            intent.setClassName(
                    TERMUX_PACKAGE,
                    "com.termux.app.RunCommandService"
            );
            intent.setAction("com.termux.RUN_COMMAND");
            intent.putExtra(
                    "com.termux.RUN_COMMAND_PATH",
                    "/data/data/com.termux/files/usr/bin/bash"
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_ARGUMENTS",
                    new String[]{"-s"}
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_WORKDIR",
                    "/data/data/com.termux/files/home"
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_BACKGROUND",
                    true
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_STDIN",
                    script
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_COMMAND_LABEL",
                    label == null ? "Nexus Phone Build" : label
            );
            intent.putExtra(
                    "com.termux.RUN_COMMAND_COMMAND_DESCRIPTION",
                    "Runs a Nexus-approved local build inside Termux."
            );

            context.startService(intent);
            result.success(null);
        } catch (SecurityException error) {
            result.error(
                    "TERMUX_SECURITY",
                    "Termux rejected the command. Enable allow-external-apps "
                            + "and grant the RUN_COMMAND permission.",
                    error.getMessage()
            );
        } catch (Exception error) {
            result.error("TERMUX_RUN_FAILED", error.getMessage(), null);
        }
    }

    private void requestTaskNotificationPermission(
            MethodChannel.Result result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true);
            return;
        }

        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }

        if (activity == null) {
            result.success(false);
            return;
        }

        if (pendingNotificationPermissionResult != null) {
            result.error(
                    "NOTIFICATION_PERMISSION_PENDING",
                    "A notification permission request is already active.",
                    null
            );
            return;
        }

        pendingNotificationPermissionResult = result;
        activity.requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST
        );
    }

    private void startBackgroundTask(
            MethodCall call,
            MethodChannel.Result result
    ) {
        try {
            final Intent intent = taskIntent(
                    NexusTaskForegroundService.ACTION_START,
                    call
            );
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
            result.success(null);
        } catch (Exception error) {
            result.error(
                    "BACKGROUND_TASK_START_FAILED",
                    error.getMessage(),
                    null
            );
        }
    }

    private void updateBackgroundTask(
            MethodCall call,
            MethodChannel.Result result
    ) {
        try {
            context.startService(
                    taskIntent(
                            NexusTaskForegroundService.ACTION_UPDATE,
                            call
                    )
            );
            result.success(null);
        } catch (Exception error) {
            result.error(
                    "BACKGROUND_TASK_UPDATE_FAILED",
                    error.getMessage(),
                    null
            );
        }
    }

    private void stopBackgroundTask(MethodChannel.Result result) {
        try {
            final Intent intent = new Intent(
                    context,
                    NexusTaskForegroundService.class
            );
            intent.setAction(NexusTaskForegroundService.ACTION_STOP);
            context.startService(intent);
            result.success(null);
        } catch (Exception error) {
            result.error(
                    "BACKGROUND_TASK_STOP_FAILED",
                    error.getMessage(),
                    null
            );
        }
    }

    private Intent taskIntent(String action, MethodCall call) {
        final Intent intent = new Intent(
                context,
                NexusTaskForegroundService.class
        );
        intent.setAction(action);

        final String title = call.argument("title");
        final String status = call.argument("status");
        final String elapsed = call.argument("elapsed");

        intent.putExtra(
                NexusTaskForegroundService.EXTRA_TITLE,
                title == null ? "Nexus is working" : title
        );
        intent.putExtra(
                NexusTaskForegroundService.EXTRA_STATUS,
                status == null ? "Working in the background…" : status
        );
        intent.putExtra(
                NexusTaskForegroundService.EXTRA_ELAPSED,
                elapsed == null ? "00:00" : elapsed
        );
        return intent;
    }

    @Override
    public boolean onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults
    ) {
        if (requestCode == TERMUX_PERMISSION_REQUEST) {
            final MethodChannel.Result result = pendingPermissionResult;
            pendingPermissionResult = null;
            if (result != null) {
                result.success(
                        grantResults.length > 0
                                && grantResults[0] == PackageManager.PERMISSION_GRANTED
                );
            }
            return true;
        }

        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            final MethodChannel.Result result =
                    pendingNotificationPermissionResult;
            pendingNotificationPermissionResult = null;
            if (result != null) {
                result.success(
                        grantResults.length > 0
                                && grantResults[0] == PackageManager.PERMISSION_GRANTED
                );
            }
            return true;
        }

        return false;
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
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(
            @NonNull ActivityPluginBinding binding
    ) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        closeSharedModel();
        if (pendingPermissionResult != null) {
            pendingPermissionResult.error(
                    "DETACHED",
                    "Nexus detached while requesting Termux permission.",
                    null
            );
            pendingPermissionResult = null;
        }
        if (pendingNotificationPermissionResult != null) {
            pendingNotificationPermissionResult.error(
                    "DETACHED",
                    "Nexus detached while requesting notification permission.",
                    null
            );
            pendingNotificationPermissionResult = null;
        }
        if (channel != null) {
            channel.setMethodCallHandler(null);
        }
        channel = null;
        context = null;
    }
}
