package org.lineageos.kukuiinstaller;

import android.graphics.Insets;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.color.DynamicColors;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class MainActivity extends AppCompatActivity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView body;
    private TextView detail;
    private TextInputLayout rootSizeLayout;
    private TextInputEditText rootSize;
    private MaterialButton androidOnly;
    private MaterialButton dual;
    private MaterialButton updateSystem;
    private MaterialButton calculate;
    private MaterialButton install;
    private MaterialButton cancel;
    private String bootName = "";
    private String bootPath = "";
    private String targetPath = "";
    private String targetRemovable = "";
    private boolean identityOk;
    private String pendingMode = "";
    private String probedGib = "";
    private String seenStatus = "";
    private boolean installStarted;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        DynamicColors.applyToActivityIfAvailable(this);
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(R.layout.activity_main);
        View scroll = findViewById(R.id.scroll);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> {
            int types = WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout()
                    | WindowInsets.Type.captionBar();
            Insets bars = insets.getInsets(types);
            int top = Math.max(bars.top, dp(96));
            v.setPadding(bars.left, top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
        body = findViewById(R.id.body);
        detail = findViewById(R.id.detail);
        rootSizeLayout = findViewById(R.id.root_size_layout);
        rootSize = findViewById(R.id.root_size);
        androidOnly = findViewById(R.id.android_only);
        dual = findViewById(R.id.dual);
        updateSystem = findViewById(R.id.update_system);
        calculate = findViewById(R.id.calculate);
        install = findViewById(R.id.install);
        cancel = findViewById(R.id.cancel);
        androidOnly.setOnClickListener(v -> ask("android"));
        dual.setOnClickListener(v -> ask("dual"));
        updateSystem.setOnClickListener(v -> ask("update"));
        calculate.setOnClickListener(v -> probeDual());
        install.setOnClickListener(v -> startInstall());
        cancel.setOnClickListener(v -> {
            installStarted = false;
            pendingMode = "";
            showChoices();
            scan();
        });
        scan();
        handler.post(poll);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void showChoices() {
        detail.setVisibility(View.GONE);
        rootSizeLayout.setVisibility(View.GONE);
        calculate.setVisibility(View.GONE);
        install.setVisibility(View.GONE);
        cancel.setVisibility(View.GONE);
        androidOnly.setVisibility(View.VISIBLE);
        dual.setVisibility(View.VISIBLE);
        updateSystem.setVisibility(View.VISIBLE);
        install.setText(R.string.install);
        body.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyLarge);
    }

    private void showWorking(String message) {
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        updateSystem.setVisibility(View.GONE);
        detail.setVisibility(View.GONE);
        rootSizeLayout.setVisibility(View.GONE);
        calculate.setVisibility(View.GONE);
        install.setVisibility(View.GONE);
        cancel.setVisibility(View.GONE);
        body.setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_HeadlineSmall);
        body.setText(message);
    }

    private void scan() {
        StringBuilder text = new StringBuilder();
        bootName = "";
        bootPath = "";
        targetPath = "";
        targetRemovable = "";
        String superDev = readLink("/dev/block/by-name/super");
        if (superDev.isEmpty()) {
            superDev = mountSource();
        }
        String node = fileName(superDev);
        if (node.startsWith("dm-")) {
            File slaves = new File("/sys/class/block/" + node + "/slaves");
            File[] kids = slaves.listFiles();
            if (kids != null && kids.length > 0) {
                node = kids[0].getName();
            }
        }
        bootName = diskOf(node);
        // The block symlink is relative but still contains the controller,
        // for example 11201000.usb or 11230000.mmc. The device symlink does not.
        bootPath = readLink("/sys/class/block/" + bootName);
        targetPath = readLink("/sys/class/block/mmcblk0");
        targetRemovable = readText("/sys/class/block/mmcblk0/removable").trim();
        text.append(getString(R.string.title)).append("\n\n");
        if (bootName.isEmpty()) {
            text.append(getString(R.string.boot_missing));
        } else {
            text.append(getString(R.string.boot_line, bootName));
        }
        text.append('\n');
        text.append(bootPath.isEmpty() ? getString(R.string.path_unread) : bootPath);
        text.append("\n\n");
        text.append(getString(R.string.internal_disk)).append('\n');
        text.append(targetPath.isEmpty() ? getString(R.string.path_unread) : targetPath);
        text.append('\n');
        if (targetRemovable.isEmpty()) {
            text.append(getString(R.string.removable_unread));
        } else {
            text.append(getString(R.string.removable_line, targetRemovable));
        }
        text.append("\n\n");
        identityOk = (bootPath.contains("11201000.usb") || bootPath.contains("11200000.usb"))
                && targetPath.contains("11230000.mmc")
                && !targetPath.contains("11201000.usb")
                && !targetPath.contains("11200000.usb")
                && "0".equals(targetRemovable)
                && !bootName.equals("mmcblk0");
        text.append(getString(identityOk ? R.string.identity_ok : R.string.identity_bad));
        body.setText(text.toString());
        androidOnly.setEnabled(identityOk);
        dual.setEnabled(identityOk);
        updateSystem.setEnabled(identityOk);
        calculate.setEnabled(identityOk);
        install.setEnabled(identityOk);
        cancel.setEnabled(true);
    }

    private void ask(String mode) {
        pendingMode = mode;
        writeRequest("op=probe\nmode=" + mode + "\nconfirm=no\n");
        showWorking(getString(R.string.calculating));
    }

    private void showAndroidConfirm(String status) {
        showChoices();
        body.setText(R.string.title);
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        updateSystem.setVisibility(View.GONE);
        detail.setVisibility(View.VISIBLE);
        install.setVisibility(View.VISIBLE);
        cancel.setVisibility(View.VISIBLE);
        detail.setText(localize(status) + "\n\n" + getString(R.string.confirm_write_install));
        pendingMode = "android";
    }

    private void showUpdateConfirm(String status) {
        showChoices();
        body.setText(R.string.title_update);
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        updateSystem.setVisibility(View.GONE);
        detail.setVisibility(View.VISIBLE);
        install.setVisibility(View.VISIBLE);
        install.setText(R.string.update);
        cancel.setVisibility(View.VISIBLE);
        detail.setText(localize(status) + "\n\n" + getString(R.string.confirm_write_update));
        pendingMode = "update";
    }

    private void showDualConfirm(String status) {
        String root = value(status, "root_gib");
        probedGib = root;
        showChoices();
        body.setText(R.string.title);
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        updateSystem.setVisibility(View.GONE);
        detail.setVisibility(View.VISIBLE);
        rootSizeLayout.setVisibility(View.VISIBLE);
        calculate.setVisibility(View.VISIBLE);
        install.setVisibility(View.VISIBLE);
        cancel.setVisibility(View.VISIBLE);
        String text = localize(status);
        if ("1".equals(value(status, "resume"))) {
            text = text + "\n\n" + getString(R.string.resume_note);
        }
        detail.setText(text + "\n\n" + getString(R.string.dual_next));
        rootSize.setText(root);
        pendingMode = "dual";
    }

    private void probeDual() {
        String typed = rootSize.getText() == null ? "" : rootSize.getText().toString().trim();
        if (typed.isEmpty()) {
            detail.setText(R.string.need_root_gib);
            return;
        }
        detail.setText(getString(R.string.calculating_gib, typed));
        writeRequest("op=probe\nmode=dual\nroot_gib=" + typed + "\nconfirm=no\n");
    }

    private void startInstall() {
        if ("dual".equals(pendingMode)) {
            String typed = rootSize.getText() == null ? "" : rootSize.getText().toString().trim();
            if (!typed.equals(probedGib)) {
                detail.setText(R.string.size_not_calculated);
                return;
            }
            writeRequest("op=go\nmode=dual\nroot_gib=" + typed + "\nconfirm=yes\n");
        } else if ("android".equals(pendingMode)) {
            writeRequest("op=go\nmode=android\nconfirm=yes\n");
        } else if ("update".equals(pendingMode)) {
            writeRequest("op=go\nmode=update\nconfirm=yes\n");
        } else {
            return;
        }
        installStarted = true;
        showWorking(getString(R.string.writing));
    }

    private final Runnable poll = new Runnable() {
        @Override
        public void run() {
            File status = new File(filesDir(), "status");
            String text = status.isFile() ? readText(status.getPath()) : "";
            if (!text.isEmpty() && !text.equals(seenStatus)) {
                seenStatus = text;
                applyStatus(text);
            }
            handler.postDelayed(this, 500);
        }
    };

    private void applyStatus(String text) {
        String state = value(text, "state");
        String message = localize(text);
        String percent = value(text, "percent");
        if ("confirm".equals(state) && identityOk && !installStarted) {
            String mode = value(text, "mode");
            if ("dual".equals(mode) || "dual".equals(pendingMode)) {
                showDualConfirm(text);
            } else if ("update".equals(mode)) {
                showUpdateConfirm(text);
            } else {
                showAndroidConfirm(text);
            }
            return;
        }
        if ("running".equals(state)) {
            installStarted = true;
            String line = message.isEmpty() ? getString(R.string.writing) : message;
            if (!percent.isEmpty()) {
                line = line + "\n\n" + percent + "%";
            }
            showWorking(line + "\n\n" + getString(R.string.stay_on));
        } else if ("ready_reboot".equals(state)) {
            showWorking(message + "\n\n" + getString(R.string.ready_suffix));
        } else if ("failed".equals(state)) {
            installStarted = false;
            showChoices();
            int retry = "update".equals(pendingMode)
                    ? R.string.retry_update : R.string.retry_install;
            body.setText(message + "\n\n" + getString(retry));
        }
    }

    private String localize(String status) {
        String code = value(status, "code");
        if (code.isEmpty()) {
            return "";
        }
        return switch (code) {
            case "boot_not_usb" -> getString(R.string.code_boot_not_usb,
                    value(status, "boot"), value(status, "path"));
            case "mmc_not_emmc" -> getString(R.string.code_mmc_not_emmc, value(status, "path"));
            case "mmc_removable" -> getString(R.string.code_mmc_removable,
                    value(status, "removable"));
            case "part_name_mismatch" -> getString(R.string.code_part_name_mismatch,
                    value(status, "part"), value(status, "got"), value(status, "want"));
            case "super_not_usb" -> getString(R.string.code_super_not_usb,
                    value(status, "disk"), value(status, "path"));
            case "attr_failed" -> getString(R.string.code_attr_failed, value(status, "part"));
            case "clear_attr_failed" -> getString(R.string.code_clear_attr_failed,
                    value(status, "part"));
            case "e2fsck_failed" -> getString(R.string.code_e2fsck_failed,
                    value(status, "exit_code"));
            case "userdata_not_f2fs" -> getString(R.string.code_userdata_not_f2fs,
                    value(status, "fstype"));
            case "unknown_mode" -> getString(R.string.code_unknown_mode, value(status, "mode"));
            case "unknown_request" -> getString(R.string.code_unknown_request,
                    value(status, "op"));
            case "gib_out_of_range" -> getString(R.string.code_gib_out_of_range,
                    value(status, "min_gib"), value(status, "max_gib"));
            case "confirm_android" -> getString(R.string.code_confirm_android,
                    value(status, "data_gib"));
            case "confirm_update" -> getString(R.string.code_confirm_update,
                    value(status, "parent"));
            case "confirm_dual" -> getString(R.string.code_confirm_dual,
                    value(status, "root_gib"), value(status, "min_gib"),
                    value(status, "max_gib"), value(status, "data_gib"));
            default -> {
                int id = getResources().getIdentifier("code_" + code, "string", getPackageName());
                yield id == 0 ? code : getString(id);
            }
        };
    }

    private void writeRequest(String text) {
        File dir = filesDir();
        if (!dir.isDirectory() && !dir.mkdirs()) {
            body.setText(R.string.request_dir_failed);
            return;
        }
        File request = new File(dir, "request");
        try (FileWriter writer = new FileWriter(request)) {
            writer.write(text);
        } catch (IOException e) {
            body.setText(e.getMessage());
        }
    }

    private File filesDir() {
        File dir = getExternalFilesDir(null);
        if (dir != null) {
            return dir;
        }
        return getFilesDir();
    }

    private static String value(String text, String key) {
        for (String line : text.split("\n")) {
            if (line.startsWith(key + "=")) {
                return line.substring(key.length() + 1);
            }
        }
        return "";
    }

    private static String diskOf(String name) {
        String current = name;
        while (new File("/sys/class/block/" + current + "/partition").exists()) {
            String link = readLink("/sys/class/block/" + current);
            int slash = link.lastIndexOf('/');
            if (slash <= 0) {
                break;
            }
            String parent = link.substring(0, slash);
            int slash2 = parent.lastIndexOf('/');
            String disk = slash2 >= 0 ? parent.substring(slash2 + 1) : parent;
            if (disk.isEmpty() || disk.equals(current)) {
                break;
            }
            current = disk;
        }
        return current;
    }

    private static String mountSource() {
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/mounts"))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.contains(" /vendor ") || line.contains(" /metadata ")) {
                    return line.split(" ")[0];
                }
            }
        } catch (IOException ignored) {
        }
        return "";
    }

    private static String readText(String path) {
        try {
            return new String(Files.readAllBytes(Path.of(path)), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    private static String readLink(String path) {
        try {
            return Files.readSymbolicLink(Path.of(path)).toString();
        } catch (IOException e) {
            return "";
        }
    }

    private static String fileName(String path) {
        int slash = path.lastIndexOf('/');
        return slash >= 0 ? path.substring(slash + 1) : path;
    }
}
