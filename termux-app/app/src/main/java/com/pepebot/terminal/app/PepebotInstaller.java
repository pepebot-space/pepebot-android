package com.pepebot.terminal.app;

import android.content.Context;
import android.os.Build;
import com.termux.shared.logger.Logger;
import com.termux.shared.termux.TermuxConstants;
import java.io.*;

public class PepebotInstaller {
    private static final String LOG_TAG = "PepebotInstaller";

    public static void installPepebotIfNeeded(Context context) {
        File pepebotBin = new File(TermuxConstants.TERMUX_BIN_PREFIX_DIR_PATH + "/pepebot");

        if (pepebotBin.exists()) {
            Logger.logInfo(LOG_TAG, "Pepebot already installed");
            return;
        }

        String arch = detectArchitecture();
        String assetName = "pepebot-" + arch;

        try {
            Logger.logInfo(LOG_TAG, "Installing pepebot: " + assetName);

            InputStream in = context.getAssets().open(assetName);
            FileOutputStream out = new FileOutputStream(pepebotBin);

            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }

            in.close();
            out.close();

            pepebotBin.setExecutable(true, false);

            Logger.logInfo(LOG_TAG, "Pepebot installed successfully");

        } catch (Exception e) {
            Logger.logStackTraceWithMessage(LOG_TAG, "Failed to install pepebot", e);
        }
    }

    private static String detectArchitecture() {
        String[] abis = Build.SUPPORTED_ABIS;
        if (abis.length > 0) {
            String primaryAbi = abis[0];
            if (primaryAbi.startsWith("arm64")) return "arm64";
            if (primaryAbi.startsWith("armeabi")) return "armv7";
            if (primaryAbi.equals("x86_64")) return "x86_64";
        }
        return "arm64";
    }
}
