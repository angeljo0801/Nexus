package com.nexus.bridge;

import android.app.IntentService;
import android.content.Intent;
import android.os.Bundle;

import androidx.annotation.Nullable;

public final class NexusTermuxResultService extends IntentService {

    public static final String EXTRA_REQUEST_ID =
            "com.nexus.bridge.TERMUX_REQUEST_ID";

    public NexusTermuxResultService() {
        super("NexusTermuxResultService");
    }

    @Override
    protected void onHandleIntent(@Nullable Intent intent) {
        if (intent == null) {
            return;
        }

        final int requestId = intent.getIntExtra(EXTRA_REQUEST_ID, -1);
        if (requestId < 0) {
            return;
        }

        final Bundle resultBundle = intent.getBundleExtra("result");
        NexusAndroidBridgePlugin.deliverTermuxResult(
                requestId,
                resultBundle
        );
    }
}
