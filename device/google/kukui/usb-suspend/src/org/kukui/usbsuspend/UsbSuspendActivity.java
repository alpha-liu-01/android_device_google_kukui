package org.kukui.usbsuspend;

import android.net.Uri;
import android.os.Bundle;
import android.view.WindowInsets;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.appbar.MaterialToolbar;
import com.google.android.material.color.DynamicColors;
import com.google.android.material.materialswitch.MaterialSwitch;

public class UsbSuspendActivity extends AppCompatActivity {
    private static final Uri CHECKED = Uri.parse(
            "content://org.kukui.usbsuspend/isChecked/kukui_usb_suspend");

    private boolean ready;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        DynamicColors.applyToActivityIfAvailable(this);
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_usb_suspend);
        findViewById(R.id.root).setOnApplyWindowInsetsListener((view, insets) -> {
            android.graphics.Insets bars = insets.getInsets(
                    WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        MaterialToolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle(R.string.title);
        }

        MaterialSwitch powerOff = findViewById(R.id.power_off);
        TextView status = findViewById(R.id.status);
        if (!UsbSuspendStore.nodePresent()) {
            powerOff.setEnabled(false);
            status.setText(R.string.missing);
            return;
        }
        powerOff.setChecked(UsbSuspendStore.isPowerOff());
        ready = true;
        powerOff.setOnCheckedChangeListener((button, checked) -> {
            if (!ready)
                return;
            if (!UsbSuspendStore.setPowerOff(checked)) {
                ready = false;
                button.setChecked(UsbSuspendStore.isPowerOff());
                ready = true;
                status.setText(R.string.write_failed);
            } else {
                status.setText("");
                getContentResolver().notifyChange(CHECKED, null);
            }
        });
    }

    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
    }
}
