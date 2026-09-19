package com.nexus.bridge;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.PowerManager;
import android.os.IBinder;

import androidx.annotation.Nullable;

public final class NexusTaskForegroundService extends Service {

    public static final String ACTION_START =
            "com.nexus.bridge.action.START_BACKGROUND_TASK";
    public static final String ACTION_UPDATE =
            "com.nexus.bridge.action.UPDATE_BACKGROUND_TASK";
    public static final String ACTION_STOP =
            "com.nexus.bridge.action.STOP_BACKGROUND_TASK";

    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_STATUS = "status";
    public static final String EXTRA_ELAPSED = "elapsed";
    public static final String EXTRA_STARTED_AT_MILLIS = "startedAtMillis";

    private static final String CHANNEL_ID = "nexus_background_work";
    private static final int NOTIFICATION_ID = 7401;
    private PowerManager.WakeLock wakeLock;

    @Override
    public void onCreate() {
        super.onCreate();
        ensureChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            return START_NOT_STICKY;
        }

        final String action = intent.getAction();
        if (ACTION_STOP.equals(action)) {
            releaseWakeLock();
            stopForeground(true);
            stopSelf();
            return START_NOT_STICKY;
        }

        final String title = value(
                intent.getStringExtra(EXTRA_TITLE),
                "Nexus is working"
        );
        final String status = value(
                intent.getStringExtra(EXTRA_STATUS),
                "Working in the background…"
        );
        final String elapsed = value(
                intent.getStringExtra(EXTRA_ELAPSED),
                "00:00"
        );
        final long startedAtMillis = intent.getLongExtra(
                EXTRA_STARTED_AT_MILLIS,
                System.currentTimeMillis()
        );

        final Notification notification =
                buildNotification(title, status, elapsed, startedAtMillis);

        if (ACTION_START.equals(action)) {
            acquireWakeLock();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                );
            } else {
                startForeground(NOTIFICATION_ID, notification);
            }
        } else {
            final NotificationManager manager =
                    getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.notify(NOTIFICATION_ID, notification);
            }
        }

        return START_STICKY;
    }

    private void acquireWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            return;
        }
        final PowerManager manager =
                (PowerManager) getSystemService(POWER_SERVICE);
        if (manager == null) {
            return;
        }
        wakeLock = manager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Nexus:BackgroundWork"
        );
        wakeLock.setReferenceCounted(false);
        wakeLock.acquire();
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        wakeLock = null;
    }

    private Notification buildNotification(
            String title,
            String status,
            String elapsed,
            long startedAtMillis
    ) {
        final Intent launch =
                getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pending = null;
        if (launch != null) {
            launch.addFlags(
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                            | Intent.FLAG_ACTIVITY_CLEAR_TOP
            );
            pending = PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT
                            | PendingIntent.FLAG_IMMUTABLE
            );
        }

        int icon = getApplicationInfo().icon;
        if (icon == 0) {
            icon = android.R.drawable.stat_notify_sync;
        }

        final Notification.Builder builder =
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        ? new Notification.Builder(this, CHANNEL_ID)
                        : new Notification.Builder(this);

        builder.setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(status)
                .setSubText(elapsed)
                .setWhen(startedAtMillis)
                .setUsesChronometer(true)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setProgress(0, 0, true)
                .setShowWhen(false);

        if (pending != null) {
            builder.setContentIntent(pending);
        }

        return builder.build();
    }

    private void ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }

        final NotificationManager manager =
                getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }

        final NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Nexus background work",
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription(
                "Shows active Nexus AI, file, Git and build work."
        );
        channel.setShowBadge(false);
        manager.createNotificationChannel(channel);
    }

    private static String value(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        return value;
    }

    @Override
    public void onDestroy() {
        releaseWakeLock();
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
