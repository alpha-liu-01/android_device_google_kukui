package org.kukui.usbsuspend;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

/** The sysfs node and the choice file the boot script reads back. */
final class UsbSuspendStore {
    static final String NODE =
            "/sys/devices/platform/soc/11201000.usb/suspend_power_off";
    static final String CHOICE = "/data/system/kukui_usb_suspend_power_off";

    private UsbSuspendStore() {}

    static boolean nodePresent() {
        return readText(NODE) != null;
    }

    /** True when sleep turns USB power off. */
    static boolean isPowerOff() {
        String current = readText(NODE);
        return current != null && current.trim().startsWith("1");
    }

    /**
     * Writes the node and the choice file together. A failed write puts both
     * back, and does not touch the choice file when the node is missing.
     */
    static boolean setPowerOff(boolean off) {
        if (!nodePresent())
            return false;
        String value = off ? "1" : "0";
        String previous = off ? "0" : "1";
        if (writeText(NODE, value) && writeText(CHOICE, value))
            return true;
        writeText(NODE, previous);
        writeText(CHOICE, previous);
        return false;
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
