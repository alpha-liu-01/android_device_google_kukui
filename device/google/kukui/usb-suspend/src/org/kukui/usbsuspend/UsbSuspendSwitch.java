package org.kukui.usbsuspend;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;

import com.android.settingslib.drawer.EntryController;
import com.android.settingslib.drawer.SwitchController;

/** The switch row on Settings > System. The row opens the explanation. */
public class UsbSuspendSwitch extends SwitchController {
    static final String KEY = "kukui_usb_suspend";
    static final String CATEGORY = "com.android.settings.category.ia.system";

    private final Context mContext;

    UsbSuspendSwitch(Context context) {
        mContext = context;
    }

    @Override
    public String getSwitchKey() {
        return KEY;
    }

    @Override
    protected EntryController.MetaData getMetaData() {
        Intent intent = new Intent(mContext, UsbSuspendActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pending = PendingIntent.getActivity(mContext, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new EntryController.MetaData(CATEGORY)
                .setTitle(R.string.title)
                .setSummary(R.string.summary)
                .setIcon(R.drawable.ic_usb_sleep)
                .setIconTintable(true)
                .setPendingIntent(pending);
    }

    @Override
    protected boolean isChecked() {
        return UsbSuspendStore.isPowerOff();
    }

    @Override
    protected boolean onCheckedChanged(boolean checked) {
        return UsbSuspendStore.setPowerOff(checked);
    }

    @Override
    protected String getErrorMessage(boolean attemptedChecked) {
        if (!UsbSuspendStore.nodePresent())
            return mContext.getString(R.string.missing);
        return mContext.getString(R.string.write_failed);
    }
}
