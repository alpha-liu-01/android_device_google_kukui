package org.kukui.usbsuspend;

import android.content.Context;

import com.android.settingslib.drawer.SwitchController;
import com.android.settingslib.drawer.SwitchesProvider;

import java.util.Collections;
import java.util.List;

/**
 * Injects the USB sleep-power switch into Settings. Only this package is
 * installed on Kukui, so other devices never see the row.
 */
public class UsbSuspendSettings extends SwitchesProvider {
    static final String AUTHORITY = "org.kukui.usbsuspend";

    @Override
    protected List<SwitchController> createSwitchControllers() {
        Context context = getContext();
        if (context == null)
            return Collections.emptyList();
        return Collections.singletonList(new UsbSuspendSwitch(context));
    }
}
