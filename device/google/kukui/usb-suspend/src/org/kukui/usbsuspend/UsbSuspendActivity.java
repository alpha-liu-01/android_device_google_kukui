package org.kukui.usbsuspend;

import android.os.Bundle;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.color.DynamicColors;
import com.google.android.material.materialswitch.MaterialSwitch;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

public class UsbSuspendActivity extends AppCompatActivity {
    private static final String NODE =
            "/sys/devices/platform/soc/11201000.usb/suspend_power_off";
    private static final String CHOICE = "/data/system/kukui_usb_suspend_power_off";

    private boolean ready;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        DynamicColors.applyToActivityIfAvailable(this);
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_usb_suspend);
        MaterialSwitch powerOff = findViewById(R.id.power_off);
        TextView status = findViewById(R.id.status);
        String current = readText(NODE);
        if (current == null) {
            powerOff.setEnabled(false);
            status.setText(R.string.missing);
            return;
        }
        powerOff.setChecked(current.trim().startsWith("1"));
        ready = true;
        powerOff.setOnCheckedChangeListener((button, checked) -> {
            if (!ready)
                return;
            String value = checked ? "1" : "0";
            String previous = checked ? "0" : "1";
            if (!writeText(NODE, value) || !writeText(CHOICE, value)) {
                writeText(NODE, previous);
                writeText(CHOICE, previous);
                ready = false;
                button.setChecked(!checked);
                ready = true;
                status.setText(R.string.write_failed);
            } else {
                status.setText("");
            }
        });
    }

    private static String readText(String path) {
        try (FileInputStream in = new FileInputStream(path)) {
            byte[] buf = in.readNBytes(16);
            return new String(buf, StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static boolean writeText(String path, String value) {
        File file = new File(path);
        File parent = file.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs())
            return false;
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write((value + "\n").getBytes(StandardCharsets.UTF_8));
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }
}
