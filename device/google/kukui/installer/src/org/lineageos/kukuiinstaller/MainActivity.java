package org.lineageos.kukuiinstaller;

import android.app.Activity;
import android.graphics.Insets;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.text.InputType;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView body;
    private TextView detail;
    private EditText rootSize;
    private Button androidOnly;
    private Button dual;
    private Button calculate;
    private Button install;
    private Button cancel;
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
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setMinimumHeight(getResources().getDisplayMetrics().heightPixels);
        body = new TextView(this);
        body.setTextSize(18);
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        detail = text("");
        detail.setVisibility(View.GONE);
        rootSize = new EditText(this);
        rootSize.setInputType(InputType.TYPE_CLASS_NUMBER);
        rootSize.setHint("Linux 根分区 GiB");
        rootSize.setVisibility(View.GONE);
        androidOnly = button("只装 Android");
        dual = button("Android 和 Linux");
        calculate = button("计算");
        install = button("安装");
        cancel = button("取消");
        calculate.setVisibility(View.GONE);
        install.setVisibility(View.GONE);
        cancel.setVisibility(View.GONE);
        androidOnly.setOnClickListener(v -> ask("android"));
        dual.setOnClickListener(v -> ask("dual"));
        calculate.setOnClickListener(v -> probeDual());
        install.setOnClickListener(v -> startInstall());
        cancel.setOnClickListener(v -> {
            installStarted = false;
            pendingMode = "";
            showChoices();
            scan();
        });
        column.addView(body);
        column.addView(androidOnly);
        column.addView(dual);
        column.addView(detail);
        column.addView(rootSize);
        column.addView(calculate);
        column.addView(install);
        column.addView(cancel);
        ScrollView scroll = new ScrollView(this);
        scroll.addView(column);
        scroll.setOnApplyWindowInsetsListener((v, insets) -> {
            int types = WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout()
                    | WindowInsets.Type.captionBar();
            Insets bars = insets.getInsets(types);
            int top = Math.max(bars.top, dp(96));
            v.setPadding(bars.left + dp(24), top, bars.right + dp(24), bars.bottom + dp(24));
            return WindowInsets.CONSUMED;
        });
        setContentView(scroll);
        scan();
        handler.post(poll);
    }

    private TextView text(String value) {
        TextView view = new TextView(this);
        view.setTextSize(18);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setText(value);
        return view;
    }

    private Button button(String label) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setEnabled(false);
        button.setTextSize(18);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT);
        params.topMargin = dp(12);
        button.setLayoutParams(params);
        return button;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void showChoices() {
        detail.setVisibility(View.GONE);
        rootSize.setVisibility(View.GONE);
        calculate.setVisibility(View.GONE);
        install.setVisibility(View.GONE);
        cancel.setVisibility(View.GONE);
        androidOnly.setVisibility(View.VISIBLE);
        dual.setVisibility(View.VISIBLE);
        body.setTextSize(18);
    }

    private void showWorking(String message) {
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        detail.setVisibility(View.GONE);
        rootSize.setVisibility(View.GONE);
        calculate.setVisibility(View.GONE);
        install.setVisibility(View.GONE);
        cancel.setVisibility(View.GONE);
        body.setTextSize(22);
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
        text.append("安装到 eMMC\n\n");
        text.append("启动盘: ").append(bootName.isEmpty() ? "没有找到" : bootName).append('\n');
        text.append(bootPath.isEmpty() ? "路径: 读不到" : bootPath).append('\n').append('\n');
        text.append("内置盘: mmcblk0\n");
        text.append(targetPath.isEmpty() ? "路径: 读不到" : targetPath).append('\n');
        text.append("removable: ").append(targetRemovable.isEmpty() ? "读不到" : targetRemovable);
        text.append("\n\n");
        identityOk = (bootPath.contains("11201000.usb") || bootPath.contains("11200000.usb"))
                && targetPath.contains("11230000.mmc")
                && !targetPath.contains("11201000.usb")
                && !targetPath.contains("11200000.usb")
                && "0".equals(targetRemovable)
                && !bootName.equals("mmcblk0");
        if (identityOk) {
            text.append("目标是 11230000.mmc。确认安装之前不会写入 eMMC。");
        } else {
            text.append("这两块盘对不上，安装按钮不会打开。");
        }
        body.setText(text.toString());
        androidOnly.setEnabled(identityOk);
        dual.setEnabled(identityOk);
        calculate.setEnabled(identityOk);
        install.setEnabled(identityOk);
        cancel.setEnabled(true);
    }

    private void ask(String mode) {
        pendingMode = mode;
        writeRequest("op=probe\nmode=" + mode + "\nconfirm=no\n");
        showWorking("正在计算分区大小。\n\n算完之后，选择和进度都会显示在这个窗口中间。");
    }

    private void showAndroidConfirm(String message) {
        showChoices();
        body.setText("安装到 eMMC");
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        detail.setVisibility(View.VISIBLE);
        install.setVisibility(View.VISIBLE);
        cancel.setVisibility(View.VISIBLE);
        detail.setText(message + "\n\n点安装之后才会写入 eMMC。写入过程请不要退出，也不要关机。");
        pendingMode = "android";
    }

    private void showDualConfirm(String text) {
        String root = value(text, "root_gib");
        String min = value(text, "min_gib");
        String max = value(text, "max_gib");
        String data = value(text, "data_gib");
        String message = value(text, "message");
        probedGib = root;
        showChoices();
        body.setText("安装到 eMMC");
        androidOnly.setVisibility(View.GONE);
        dual.setVisibility(View.GONE);
        detail.setVisibility(View.VISIBLE);
        rootSize.setVisibility(View.VISIBLE);
        calculate.setVisibility(View.VISIBLE);
        install.setVisibility(View.VISIBLE);
        cancel.setVisibility(View.VISIBLE);
        detail.setText(message + "\n\n可填 " + min + " 到 " + max
                + " GiB。当前计算：Linux 根分区 " + root
                + " GiB，Android 数据分区约 " + data
                + " GiB。\n改完数字先点计算。点安装之后才会写入。");
        rootSize.setText(root);
        pendingMode = "dual";
    }

    private void probeDual() {
        String typed = rootSize.getText().toString().trim();
        if (typed.isEmpty()) {
            detail.setText("先填写 Linux 根分区的 GiB。");
            return;
        }
        detail.setText("正在计算 " + typed + " GiB。");
        writeRequest("op=probe\nmode=dual\nroot_gib=" + typed + "\nconfirm=no\n");
    }

    private void startInstall() {
        if ("dual".equals(pendingMode)) {
            String typed = rootSize.getText().toString().trim();
            if (!typed.equals(probedGib)) {
                detail.setText("这个大小还没计算。先点计算。");
                return;
            }
            writeRequest("op=go\nmode=dual\nroot_gib=" + typed + "\nconfirm=yes\n");
        } else if ("android".equals(pendingMode)) {
            writeRequest("op=go\nmode=android\nconfirm=yes\n");
        } else {
            return;
        }
        installStarted = true;
        showWorking("正在写入 eMMC。\n\n进度会显示在这里。有的步骤要几分钟，百分比会暂时不动。\n请不要退出，也不要关机。");
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
        String message = value(text, "message");
        String percent = value(text, "percent");
        if ("confirm".equals(state) && identityOk && !installStarted) {
            if ("dual".equals(value(text, "mode")) || "dual".equals(pendingMode)) {
                showDualConfirm(text);
            } else {
                showAndroidConfirm(message);
            }
            return;
        }
        if ("running".equals(state)) {
            installStarted = true;
            String line = message.isEmpty() ? "正在写入 eMMC。" : message;
            if (!percent.isEmpty()) {
                line = line + "\n\n" + percent + "%";
            }
            showWorking(line + "\n\n请不要退出，也不要关机。");
        } else if ("ready_reboot".equals(state)) {
            showWorking(message + "\n\n安装器不会自己重启。");
        } else if ("failed".equals(state)) {
            installStarted = false;
            showChoices();
            body.setText(message + "\n\n可以再试一次。已经缩小的 Linux 根分区会保留。");
        }
    }

    private void writeRequest(String text) {
        File dir = filesDir();
        if (!dir.isDirectory() && !dir.mkdirs()) {
            body.setText("写不出请求目录");
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
