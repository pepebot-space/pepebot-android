package com.termux.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.system.Os;
import android.util.Pair;
import android.view.WindowManager;

import com.termux.R;
import com.termux.shared.file.FileUtils;
import com.termux.shared.termux.crash.TermuxCrashUtils;
import com.termux.shared.termux.file.TermuxFileUtils;
import com.termux.shared.interact.MessageDialogUtils;
import com.termux.shared.logger.Logger;
import com.termux.shared.markdown.MarkdownUtils;
import com.termux.shared.errors.Error;
import com.termux.shared.android.PackageUtils;
import com.termux.shared.termux.TermuxConstants;
import com.termux.shared.termux.TermuxUtils;
import com.termux.shared.termux.shell.command.environment.TermuxShellEnvironment;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import static com.termux.shared.termux.TermuxConstants.TERMUX_PREFIX_DIR;
import static com.termux.shared.termux.TermuxConstants.TERMUX_PREFIX_DIR_PATH;
import static com.termux.shared.termux.TermuxConstants.TERMUX_STAGING_PREFIX_DIR;
import static com.termux.shared.termux.TermuxConstants.TERMUX_STAGING_PREFIX_DIR_PATH;

/**
 * Install the Termux bootstrap packages if necessary by following the below
 * steps:
 * <p/>
 * (1) If $PREFIX already exist, assume that it is correct and be done. Note
 * that this relies on that we do not create a
 * broken $PREFIX directory below.
 * <p/>
 * (2) A progress dialog is shown with "Installing..." message and a spinner.
 * <p/>
 * (3) A staging directory, $STAGING_PREFIX, is cleared if left over from broken
 * installation below.
 * <p/>
 * (4) The zip file is loaded from a shared library.
 * <p/>
 * (5) The zip, containing entries relative to the $PREFIX, is is downloaded and
 * extracted by a zip input stream
 * continuously encountering zip file entries:
 * <p/>
 * (5.1) If the zip entry encountered is SYMLINKS.txt, go through it and
 * remember all symlinks to setup.
 * <p/>
 * (5.2) For every other zip entry, extract it into $STAGING_PREFIX and set
 * execute permissions if necessary.
 */
final class TermuxInstaller {

    private static final String LOG_TAG = "TermuxInstaller";

    /** Performs bootstrap setup if necessary. */
    static void setupBootstrapIfNeeded(final Activity activity, final Runnable whenDone) {
        String bootstrapErrorMessage;
        Error filesDirectoryAccessibleError;

        // This will also call Context.getFilesDir(), which should ensure that termux
        // files directory
        // is created if it does not already exist
        filesDirectoryAccessibleError = TermuxFileUtils.isTermuxFilesDirectoryAccessible(activity, true, true);
        boolean isFilesDirectoryAccessible = filesDirectoryAccessibleError == null;

        // Termux can only be run as the primary user (device owner) since only that
        // account has the expected file system paths. Verify that:
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && !PackageUtils.isCurrentUserThePrimaryUser(activity)) {
            bootstrapErrorMessage = activity.getString(R.string.bootstrap_error_not_primary_user_message,
                    MarkdownUtils.getMarkdownCodeForString(TERMUX_PREFIX_DIR_PATH, false));
            Logger.logError(LOG_TAG, "isFilesDirectoryAccessible: " + isFilesDirectoryAccessible);
            Logger.logError(LOG_TAG, bootstrapErrorMessage);
            sendBootstrapCrashReportNotification(activity, bootstrapErrorMessage);
            MessageDialogUtils.exitAppWithErrorMessage(activity,
                    activity.getString(R.string.bootstrap_error_title),
                    bootstrapErrorMessage);
            return;
        }

        if (!isFilesDirectoryAccessible) {
            bootstrapErrorMessage = Error.getMinimalErrorString(filesDirectoryAccessibleError);
            // noinspection SdCardPath
            if (PackageUtils.isAppInstalledOnExternalStorage(activity) &&
                    !TermuxConstants.TERMUX_FILES_DIR_PATH.equals(
                            activity.getFilesDir().getAbsolutePath().replaceAll("^/data/user/0/", "/data/data/"))) {
                bootstrapErrorMessage += "\n\n" + activity.getString(R.string.bootstrap_error_installed_on_portable_sd,
                        MarkdownUtils.getMarkdownCodeForString(TERMUX_PREFIX_DIR_PATH, false));
            }

            Logger.logError(LOG_TAG, bootstrapErrorMessage);
            sendBootstrapCrashReportNotification(activity, bootstrapErrorMessage);
            MessageDialogUtils.showMessage(activity,
                    activity.getString(R.string.bootstrap_error_title),
                    bootstrapErrorMessage, null);
            return;
        }

        // If prefix directory exists, even if its a symlink to a valid directory and
        // symlink is not broken/dangling
        if (FileUtils.directoryFileExists(TERMUX_PREFIX_DIR_PATH, true)) {
            if (TermuxFileUtils.isTermuxPrefixDirectoryEmpty()) {
                Logger.logInfo(LOG_TAG, "The termux prefix directory \"" + TERMUX_PREFIX_DIR_PATH
                        + "\" exists but is empty or only contains specific unimportant files.");
            } else {
                // Prefix exists and is non-empty. Check if path patching was done.
                if (!TermuxConstants.TERMUX_PACKAGE_NAME.equals("com.termux")) {
                    File patchMarker = new File(TERMUX_PREFIX_DIR_PATH + "/.pepebot_patched");
                    if (!patchMarker.exists()) {
                        Logger.logInfo(LOG_TAG,
                                "Running bootstrap path patching for " + TermuxConstants.TERMUX_PACKAGE_NAME);
                        String oldPkg = "com.termux";
                        String newPkg = TermuxConstants.TERMUX_PACKAGE_NAME;
                        patchTextFilesRecursive(TERMUX_PREFIX_DIR, oldPkg, newPkg);
                        patchSymlinksRecursive(TERMUX_PREFIX_DIR, oldPkg, newPkg);
                        File homeDir = TermuxConstants.TERMUX_HOME_DIR;
                        if (homeDir.exists()) {
                            patchTextFilesRecursive(homeDir, oldPkg, newPkg);
                        }
                        createLoginWrapper();
                        createElfWrappers();
                        try {
                            patchMarker.createNewFile();
                        } catch (Exception ignored) {
                        }
                        Logger.logInfo(LOG_TAG, "Bootstrap path patching completed.");
                    }
                }
                whenDone.run();
                return;
            }
        } else if (FileUtils.fileExists(TERMUX_PREFIX_DIR_PATH, false)) {
            Logger.logInfo(LOG_TAG, "The termux prefix directory \"" + TERMUX_PREFIX_DIR_PATH
                    + "\" does not exist but another file exists at its destination.");
        }

        final ProgressDialog progress = ProgressDialog.show(activity, null,
                activity.getString(R.string.bootstrap_installer_body), true, false);
        new Thread() {
            @Override
            public void run() {
                try {
                    Logger.logInfo(LOG_TAG, "Installing " + TermuxConstants.TERMUX_APP_NAME + " bootstrap packages.");

                    Error error;

                    // Delete prefix staging directory or any file at its destination
                    error = FileUtils.deleteFile("termux prefix staging directory", TERMUX_STAGING_PREFIX_DIR_PATH,
                            true);
                    if (error != null) {
                        showBootstrapErrorDialog(activity, whenDone, Error.getErrorMarkdownString(error));
                        return;
                    }

                    // Delete prefix directory or any file at its destination
                    error = FileUtils.deleteFile("termux prefix directory", TERMUX_PREFIX_DIR_PATH, true);
                    if (error != null) {
                        showBootstrapErrorDialog(activity, whenDone, Error.getErrorMarkdownString(error));
                        return;
                    }

                    // Create prefix staging directory if it does not already exist and set required
                    // permissions
                    error = TermuxFileUtils.isTermuxPrefixStagingDirectoryAccessible(true, true);
                    if (error != null) {
                        showBootstrapErrorDialog(activity, whenDone, Error.getErrorMarkdownString(error));
                        return;
                    }

                    // Create prefix directory if it does not already exist and set required
                    // permissions
                    error = TermuxFileUtils.isTermuxPrefixDirectoryAccessible(true, true);
                    if (error != null) {
                        showBootstrapErrorDialog(activity, whenDone, Error.getErrorMarkdownString(error));
                        return;
                    }

                    Logger.logInfo(LOG_TAG, "Extracting bootstrap zip to prefix staging directory \""
                            + TERMUX_STAGING_PREFIX_DIR_PATH + "\".");

                    final byte[] buffer = new byte[8096];
                    final List<Pair<String, String>> symlinks = new ArrayList<>(50);

                    final byte[] zipBytes = loadZipBytes();
                    try (ZipInputStream zipInput = new ZipInputStream(new ByteArrayInputStream(zipBytes))) {
                        ZipEntry zipEntry;
                        while ((zipEntry = zipInput.getNextEntry()) != null) {
                            if (zipEntry.getName().equals("SYMLINKS.txt")) {
                                BufferedReader symlinksReader = new BufferedReader(new InputStreamReader(zipInput));
                                String line;
                                while ((line = symlinksReader.readLine()) != null) {
                                    String[] parts = line.split("←");
                                    if (parts.length != 2)
                                        throw new RuntimeException("Malformed symlink line: " + line);
                                    String oldPath = parts[0];
                                    String newPath = TERMUX_STAGING_PREFIX_DIR_PATH + "/" + parts[1];
                                    symlinks.add(Pair.create(oldPath, newPath));

                                    error = ensureDirectoryExists(new File(newPath).getParentFile());
                                    if (error != null) {
                                        showBootstrapErrorDialog(activity, whenDone,
                                                Error.getErrorMarkdownString(error));
                                        return;
                                    }
                                }
                            } else {
                                String zipEntryName = zipEntry.getName();
                                File targetFile = new File(TERMUX_STAGING_PREFIX_DIR_PATH, zipEntryName);
                                boolean isDirectory = zipEntry.isDirectory();

                                error = ensureDirectoryExists(isDirectory ? targetFile : targetFile.getParentFile());
                                if (error != null) {
                                    showBootstrapErrorDialog(activity, whenDone, Error.getErrorMarkdownString(error));
                                    return;
                                }

                                if (!isDirectory) {
                                    try (FileOutputStream outStream = new FileOutputStream(targetFile)) {
                                        int readBytes;
                                        while ((readBytes = zipInput.read(buffer)) != -1)
                                            outStream.write(buffer, 0, readBytes);
                                    }
                                    if (zipEntryName.startsWith("bin/") || zipEntryName.startsWith("libexec") ||
                                            zipEntryName.startsWith("lib/apt/apt-helper")
                                            || zipEntryName.startsWith("lib/apt/methods")) {
                                        // noinspection OctalInteger
                                        Os.chmod(targetFile.getAbsolutePath(), 0700);
                                    }
                                }
                            }
                        }
                    }

                    if (symlinks.isEmpty())
                        throw new RuntimeException("No SYMLINKS.txt encountered");
                    for (Pair<String, String> symlink : symlinks) {
                        Os.symlink(symlink.first, symlink.second);
                    }

                    Logger.logInfo(LOG_TAG, "Moving termux prefix staging to prefix directory.");

                    if (!TERMUX_STAGING_PREFIX_DIR.renameTo(TERMUX_PREFIX_DIR)) {
                        throw new RuntimeException("Moving termux prefix staging to prefix directory failed");
                    }

                    Logger.logInfo(LOG_TAG, "Bootstrap packages installed successfully.");

                    // If the package name differs from the original com.termux, bootstrap
                    // files will have /data/data/com.termux paths hardcoded in scripts, configs,
                    // and symlinks. Patch all text files and recreate symlinks with correct paths.
                    if (!TermuxConstants.TERMUX_PACKAGE_NAME.equals("com.termux")) {
                        String oldPkg = "com.termux";
                        String newPkg = TermuxConstants.TERMUX_PACKAGE_NAME;
                        Logger.logInfo(LOG_TAG, "Patching bootstrap files: replacing " + oldPkg + " with " + newPkg);
                        patchTextFilesRecursive(TERMUX_PREFIX_DIR, oldPkg, newPkg);
                        patchSymlinksRecursive(TERMUX_PREFIX_DIR, oldPkg, newPkg);
                        File homeDir = TermuxConstants.TERMUX_HOME_DIR;
                        if (homeDir.exists()) {
                            patchTextFilesRecursive(homeDir, oldPkg, newPkg);
                        }
                        createLoginWrapper();
                        createElfWrappers();
                        try {
                            new File(TERMUX_PREFIX_DIR_PATH + "/.pepebot_patched").createNewFile();
                        } catch (Exception ignored) {
                        }
                        Logger.logInfo(LOG_TAG, "Bootstrap path patching completed.");
                    }

                    // Recreate env file since termux prefix was wiped earlier
                    TermuxShellEnvironment.writeEnvironmentToFile(activity);

                    activity.runOnUiThread(whenDone);

                } catch (final Exception e) {
                    showBootstrapErrorDialog(activity, whenDone,
                            Logger.getStackTracesMarkdownString(null, Logger.getStackTracesStringArray(e)));

                } finally {
                    activity.runOnUiThread(() -> {
                        try {
                            progress.dismiss();
                        } catch (RuntimeException e) {
                            // Activity already dismissed - ignore.
                        }
                    });
                }
            }
        }.start();
    }

    public static void showBootstrapErrorDialog(Activity activity, Runnable whenDone, String message) {
        Logger.logErrorExtended(LOG_TAG, "Bootstrap Error:\n" + message);

        // Send a notification with the exception so that the user knows why bootstrap
        // setup failed
        sendBootstrapCrashReportNotification(activity, message);

        activity.runOnUiThread(() -> {
            try {
                new AlertDialog.Builder(activity).setTitle(R.string.bootstrap_error_title)
                        .setMessage(R.string.bootstrap_error_body)
                        .setNegativeButton(R.string.bootstrap_error_abort, (dialog, which) -> {
                            dialog.dismiss();
                            activity.finish();
                        })
                        .setPositiveButton(R.string.bootstrap_error_try_again, (dialog, which) -> {
                            dialog.dismiss();
                            FileUtils.deleteFile("termux prefix directory", TERMUX_PREFIX_DIR_PATH, true);
                            TermuxInstaller.setupBootstrapIfNeeded(activity, whenDone);
                        }).show();
            } catch (WindowManager.BadTokenException e1) {
                // Activity already dismissed - ignore.
            }
        });
    }

    private static void sendBootstrapCrashReportNotification(Activity activity, String message) {
        final String title = TermuxConstants.TERMUX_APP_NAME + " Bootstrap Error";

        // Add info of all install Termux plugin apps as well since their target sdk or
        // installation
        // on external/portable sd card can affect Termux app files directory access or
        // exec.
        TermuxCrashUtils.sendCrashReportNotification(activity, LOG_TAG,
                title, null, "## " + title + "\n\n" + message + "\n\n" +
                        TermuxUtils.getTermuxDebugMarkdownString(activity),
                true, false, TermuxUtils.AppInfoMode.TERMUX_AND_PLUGIN_PACKAGES, true);
    }

    static void setupStorageSymlinks(final Context context) {
        final String LOG_TAG = "termux-storage";
        final String title = TermuxConstants.TERMUX_APP_NAME + " Setup Storage Error";

        Logger.logInfo(LOG_TAG, "Setting up storage symlinks.");

        new Thread() {
            public void run() {
                try {
                    Error error;
                    File storageDir = TermuxConstants.TERMUX_STORAGE_HOME_DIR;

                    error = FileUtils.clearDirectory("~/storage", storageDir.getAbsolutePath());
                    if (error != null) {
                        Logger.logErrorAndShowToast(context, LOG_TAG, error.getMessage());
                        Logger.logErrorExtended(LOG_TAG, "Setup Storage Error\n" + error.toString());
                        TermuxCrashUtils.sendCrashReportNotification(context, LOG_TAG, title, null,
                                "## " + title + "\n\n" + Error.getErrorMarkdownString(error),
                                true, false, TermuxUtils.AppInfoMode.TERMUX_PACKAGE, true);
                        return;
                    }

                    Logger.logInfo(LOG_TAG,
                            "Setting up storage symlinks at ~/storage/shared, ~/storage/downloads, ~/storage/dcim, ~/storage/pictures, ~/storage/music and ~/storage/movies for directories in \""
                                    + Environment.getExternalStorageDirectory().getAbsolutePath() + "\".");

                    // Get primary storage root "/storage/emulated/0" symlink
                    File sharedDir = Environment.getExternalStorageDirectory();
                    Os.symlink(sharedDir.getAbsolutePath(), new File(storageDir, "shared").getAbsolutePath());

                    File documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
                    Os.symlink(documentsDir.getAbsolutePath(), new File(storageDir, "documents").getAbsolutePath());

                    File downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
                    Os.symlink(downloadsDir.getAbsolutePath(), new File(storageDir, "downloads").getAbsolutePath());

                    File dcimDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM);
                    Os.symlink(dcimDir.getAbsolutePath(), new File(storageDir, "dcim").getAbsolutePath());

                    File picturesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
                    Os.symlink(picturesDir.getAbsolutePath(), new File(storageDir, "pictures").getAbsolutePath());

                    File musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC);
                    Os.symlink(musicDir.getAbsolutePath(), new File(storageDir, "music").getAbsolutePath());

                    File moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES);
                    Os.symlink(moviesDir.getAbsolutePath(), new File(storageDir, "movies").getAbsolutePath());

                    File podcastsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PODCASTS);
                    Os.symlink(podcastsDir.getAbsolutePath(), new File(storageDir, "podcasts").getAbsolutePath());

                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                        File audiobooksDir = Environment
                                .getExternalStoragePublicDirectory(Environment.DIRECTORY_AUDIOBOOKS);
                        Os.symlink(audiobooksDir.getAbsolutePath(),
                                new File(storageDir, "audiobooks").getAbsolutePath());
                    }

                    // Dir 0 should ideally be for primary storage
                    // https://cs.android.com/android/platform/superproject/+/android-12.0.0_r32:frameworks/base/core/java/android/app/ContextImpl.java;l=818
                    // https://cs.android.com/android/platform/superproject/+/android-12.0.0_r32:frameworks/base/core/java/android/os/Environment.java;l=219
                    // https://cs.android.com/android/platform/superproject/+/android-12.0.0_r32:frameworks/base/core/java/android/os/Environment.java;l=181
                    // https://cs.android.com/android/platform/superproject/+/android-12.0.0_r32:frameworks/base/services/core/java/com/android/server/StorageManagerService.java;l=3796
                    // https://cs.android.com/android/platform/superproject/+/android-7.0.0_r36:frameworks/base/services/core/java/com/android/server/MountService.java;l=3053

                    // Create "Android/data/com.termux" symlinks
                    File[] dirs = context.getExternalFilesDirs(null);
                    if (dirs != null && dirs.length > 0) {
                        for (int i = 0; i < dirs.length; i++) {
                            File dir = dirs[i];
                            if (dir == null)
                                continue;
                            String symlinkName = "external-" + i;
                            Logger.logInfo(LOG_TAG, "Setting up storage symlinks at ~/storage/" + symlinkName
                                    + " for \"" + dir.getAbsolutePath() + "\".");
                            Os.symlink(dir.getAbsolutePath(), new File(storageDir, symlinkName).getAbsolutePath());
                        }
                    }

                    // Create "Android/media/com.termux" symlinks
                    dirs = context.getExternalMediaDirs();
                    if (dirs != null && dirs.length > 0) {
                        for (int i = 0; i < dirs.length; i++) {
                            File dir = dirs[i];
                            if (dir == null)
                                continue;
                            String symlinkName = "media-" + i;
                            Logger.logInfo(LOG_TAG, "Setting up storage symlinks at ~/storage/" + symlinkName
                                    + " for \"" + dir.getAbsolutePath() + "\".");
                            Os.symlink(dir.getAbsolutePath(), new File(storageDir, symlinkName).getAbsolutePath());
                        }
                    }

                    Logger.logInfo(LOG_TAG, "Storage symlinks created successfully.");
                } catch (Exception e) {
                    Logger.logErrorAndShowToast(context, LOG_TAG, e.getMessage());
                    Logger.logStackTraceWithMessage(LOG_TAG, "Setup Storage Error: Error setting up link", e);
                    TermuxCrashUtils.sendCrashReportNotification(context, LOG_TAG, title, null,
                            "## " + title + "\n\n"
                                    + Logger.getStackTracesMarkdownString(null, Logger.getStackTracesStringArray(e)),
                            true, false, TermuxUtils.AppInfoMode.TERMUX_PACKAGE, true);
                }
            }
        }.start();
    }

    private static Error ensureDirectoryExists(File directory) {
        return FileUtils.createDirectoryFile(directory.getAbsolutePath());
    }

    public static byte[] loadZipBytes() {
        // Only load the shared library when necessary to save memory usage.
        System.loadLibrary("termux-bootstrap");
        return getZip();
    }

    public static native byte[] getZip();

    /**
     * Create a login wrapper script using /system/bin/sh for package name
     * compatibility.
     */
    private static void createLoginWrapper() {
        try {
            File loginFile = new File(TERMUX_PREFIX_DIR_PATH + "/bin/login");
            String ldLibPath = TERMUX_PREFIX_DIR_PATH + "/lib";
            String binPath = TERMUX_PREFIX_DIR_PATH + "/bin";
            String etcPath = TERMUX_PREFIX_DIR_PATH + "/etc";
            String wrapperScript = "#!/system/bin/sh\n" +
                    "export PREFIX=" + TERMUX_PREFIX_DIR_PATH + "\n" +
                    "export HOME=" + TermuxConstants.TERMUX_HOME_DIR_PATH + "\n" +
                    "export LD_LIBRARY_PATH=" + ldLibPath + "\n" +
                    "export PATH=" + binPath + ":" + binPath + "/applets:/system/bin:/system/xbin\n" +
                    "export LANG=en_US.UTF-8\n" +
                    "export SHELL=/system/bin/sh\n" +
                    "export TERMUX_PREFIX=" + TERMUX_PREFIX_DIR_PATH + "\n" +
                    "cd \"$HOME\"\n" +
                    "if [ -f " + etcPath + "/motd ]; then\n" +
                    "    cat " + etcPath + "/motd\n" +
                    "fi\n" +
                    "exec /system/bin/sh\n";
            FileOutputStream fos = new FileOutputStream(loginFile);
            fos.write(wrapperScript.getBytes());
            fos.close();
            // noinspection OctalInteger
            Os.chmod(loginFile.getAbsolutePath(), 0700);
            Logger.logInfo(LOG_TAG, "Login wrapper created successfully.");
        } catch (Exception e) {
            Logger.logStackTraceWithMessage(LOG_TAG, "Failed to create login wrapper", e);
        }
    }

    /**
     * Create wrapper scripts for ELF binaries that have hardcoded com.termux config
     * paths.
     * The ELF binaries are renamed to .bin and shell script wrappers are created
     * that pass
     * correct directory overrides via command-line options or environment
     * variables.
     */
    private static void createElfWrappers() {
        String prefix = TERMUX_PREFIX_DIR_PATH;
        String binDir = prefix + "/bin";
        String libDir = prefix + "/lib";

        // Create apt.conf with all correct path overrides.
        // This is used via APT_CONFIG env var so apt reads correct paths
        // during early initialization, before it tries to access apt.conf.d/ etc.
        try {
            String aptConf = "Dir \"" + prefix + "/\";\n" +
                    "Dir::State \"" + prefix + "/var/lib/apt/\";\n" +
                    "Dir::State::status \"" + prefix + "/var/lib/dpkg/status\";\n" +
                    "Dir::Cache \"" + prefix + "/var/cache/apt/\";\n" +
                    "Dir::Etc \"" + prefix + "/etc/apt/\";\n" +
                    "Dir::Etc::SourceList \"" + prefix + "/etc/apt/sources.list\";\n" +
                    "Dir::Etc::SourceParts \"" + prefix + "/etc/apt/sources.list.d/\";\n" +
                    "Dir::Etc::Parts \"" + prefix + "/etc/apt/apt.conf.d/\";\n" +
                    "Dir::Bin::dpkg \"" + binDir + "/dpkg\";\n" +
                    "Dir::Bin::Methods \"" + libDir + "/apt/methods/\";\n" +
                    "Dir::Bin::Solvers \"" + libDir + "/apt/solvers/\";\n" +
                    "Dir::Bin::Planners \"" + libDir + "/apt/planners/\";\n" +
                    "Dir::Bin::apt-key \"" + binDir + "/apt-key\";\n" +
                    "Dir::Bin::gpg \"" + binDir + "/gpgv\";\n" +
                    "Dir::Etc::Trusted \"" + prefix + "/etc/apt/trusted.gpg\";\n" +
                    "Dir::Etc::TrustedParts \"" + prefix + "/etc/apt/trusted.gpg.d/\";\n" +
                    "Dir::Log \"" + prefix + "/var/log/apt/\";\n" +
                    "Acquire::https::CaInfo \"" + prefix + "/etc/tls/cert.pem\";\n" +
                    "Acquire::https::Verify-Peer \"true\";\n";
            File aptConfFile = new File(prefix + "/etc/apt/apt.conf");
            FileOutputStream fos = new FileOutputStream(aptConfFile);
            fos.write(aptConf.getBytes());
            fos.close();

            // Create missing apt cache directories
            new File(prefix + "/var/cache/apt/archives/partial").mkdirs();
            new File(prefix + "/var/lib/apt/lists/partial").mkdirs();
            new File(prefix + "/var/log/apt").mkdirs();
            new File(prefix + "/tmp").mkdirs();

            // Create symlink bridge for dpkg path translation.
            // Deb packages contain paths like ./data/data/com.termux/files/usr/...
            // With --instdir=/data/data/com.terminal.pepebot, dpkg will try to create
            // /data/data/com.terminal.pepebot/data/data/com.termux/files/usr/...
            // The symlink bridges this to the actual prefix location.
            String appDataDir = TermuxConstants.TERMUX_INTERNAL_PRIVATE_APP_DATA_DIR_PATH;
            String bridgeDir = appDataDir + "/data/data/com.termux/files";
            new File(bridgeDir).mkdirs();
            File bridgeLink = new File(bridgeDir + "/usr");
            if (!bridgeLink.exists()) {
                try {
                    Os.symlink(appDataDir + "/files/usr", bridgeLink.getAbsolutePath());
                    Logger.logInfo(LOG_TAG, "dpkg symlink bridge created.");
                } catch (Exception e2) {
                    Logger.logStackTraceWithMessage(LOG_TAG, "Failed to create dpkg symlink bridge", e2);
                }
            }

            Logger.logInfo(LOG_TAG, "apt.conf and directories created.");
        } catch (Exception e) {
            Logger.logStackTraceWithMessage(LOG_TAG, "Failed to create apt.conf", e);
        }

        // apt family wrappers using APT_CONFIG env var
        String aptConfPath = prefix + "/etc/apt/apt.conf";
        String[] aptBinaries = { "apt", "apt-get", "apt-cache", "apt-config", "apt-mark" };
        for (String name : aptBinaries) {
            createSingleElfWrapper(binDir, libDir, name,
                    "export APT_CONFIG=\"" + aptConfPath + "\"\n" +
                            "exec \"" + binDir + "/" + name + ".bin\" \"$@\"\n");
        }

        // dpkg family wrapper with DPKG_ADMINDIR, PATH, and --instdir
        // --instdir points to app data dir so the symlink bridge translates
        // com.termux paths in .deb packages to com.terminal.pepebot
        String dpkgAdminDir = prefix + "/var/lib/dpkg";
        String appDataDir = TermuxConstants.TERMUX_INTERNAL_PRIVATE_APP_DATA_DIR_PATH;
        String dpkgEnv = "export DPKG_ADMINDIR=\"" + dpkgAdminDir + "\"\n" +
                "export PATH=\"" + binDir + ":" + binDir + "/applets:/system/bin:/system/xbin\"\n" +
                "export TMPDIR=\"" + prefix + "/tmp\"\n";

        // dpkg gets --instdir so the symlink bridge translates com.termux paths
        createSingleElfWrapper(binDir, libDir, "dpkg",
                dpkgEnv + "exec \"" + binDir + "/dpkg.bin\" --instdir=\"" + appDataDir + "\" \"$@\"\n");

        // dpkg-deb, dpkg-query, dpkg-trigger don't support --instdir
        String[] dpkgOtherBinaries = { "dpkg-deb", "dpkg-query", "dpkg-trigger" };
        for (String name : dpkgOtherBinaries) {
            createSingleElfWrapper(binDir, libDir, name,
                    dpkgEnv + "exec \"" + binDir + "/" + name + ".bin\" \"$@\"\n");
        }

        Logger.logInfo(LOG_TAG, "ELF binary wrappers created successfully.");
    }

    /**
     * Create a single ELF wrapper: rename binary to .bin and write a shell script
     * wrapper.
     */
    private static void createSingleElfWrapper(String binDir, String libDir,
            String name, String execCommand) {
        try {
            File origFile = new File(binDir + "/" + name);
            File binFile = new File(binDir + "/" + name + ".bin");

            if (!origFile.exists())
                return;

            // Check if it's actually an ELF binary (not already a wrapper script)
            byte[] header = new byte[4];
            java.io.FileInputStream fis = new java.io.FileInputStream(origFile);
            int bytesRead = fis.read(header);
            fis.close();
            if (bytesRead < 4 || header[0] != 0x7f || header[1] != 'E' ||
                    header[2] != 'L' || header[3] != 'F') {
                return; // Not an ELF binary, skip
            }

            // Rename original to .bin
            origFile.renameTo(binFile);

            // Create wrapper script
            String wrapper = "#!/system/bin/sh\n" +
                    "export LD_LIBRARY_PATH=\"" + libDir + "\"\n" +
                    execCommand;
            FileOutputStream fos = new FileOutputStream(origFile);
            fos.write(wrapper.getBytes());
            fos.close();
            // noinspection OctalInteger
            Os.chmod(origFile.getAbsolutePath(), 0700);
        } catch (Exception e) {
            Logger.logStackTraceWithMessage(LOG_TAG, "Failed to create wrapper for " + name, e);
        }
    }

    /**
     * Recursively patch all text files under a directory, replacing oldStr with
     * newStr.
     * Skips binary files (ELF) and symlinks.
     */
    private static void patchTextFilesRecursive(File dir, String oldPkg, String newPkg) {
        File[] files = dir.listFiles();
        if (files == null)
            return;

        // Old and new prefix paths for shebang replacement
        String oldPrefix = "/data/data/" + oldPkg + "/files/usr";
        String newPrefix = "/data/data/" + newPkg + "/files/usr";

        for (File file : files) {
            if (file.isDirectory() && !isSymlink(file)) {
                patchTextFilesRecursive(file, oldPkg, newPkg);
            } else if (file.isFile() && !isSymlink(file)) {
                try {
                    // Skip binary files by checking first bytes for ELF magic
                    byte[] header = new byte[4];
                    java.io.FileInputStream fis = new java.io.FileInputStream(file);
                    int bytesRead = fis.read(header);
                    fis.close();

                    if (bytesRead >= 4 && header[0] == 0x7f && header[1] == 'E' &&
                            header[2] == 'L' && header[3] == 'F') {
                        continue; // Skip ELF binaries
                    }

                    // Read file content
                    byte[] content = new byte[(int) file.length()];
                    fis = new java.io.FileInputStream(file);
                    fis.read(content);
                    fis.close();

                    String text = new String(content);
                    boolean modified = false;

                    // 1. Replace package name references in content
                    if (text.contains(oldPkg)) {
                        text = text.replace(oldPkg, newPkg);
                        modified = true;
                    }

                    // 2. Replace Termux shebangs with /system/bin/sh
                    // Since bash/sh ELF binaries have broken PT_INTERP linker paths,
                    // all scripts must use /system/bin/sh as interpreter
                    if (text.startsWith("#!")) {
                        String newText = text;
                        newText = newText.replace("#!" + newPrefix + "/bin/sh", "#!/system/bin/sh");
                        newText = newText.replace("#!" + newPrefix + "/bin/bash", "#!/system/bin/sh");
                        newText = newText.replace("#!" + newPrefix + "/bin/env", "#!/system/bin/env");
                        newText = newText.replace("#!" + oldPrefix + "/bin/sh", "#!/system/bin/sh");
                        newText = newText.replace("#!" + oldPrefix + "/bin/bash", "#!/system/bin/sh");
                        newText = newText.replace("#!" + oldPrefix + "/bin/env", "#!/system/bin/env");
                        if (!newText.equals(text)) {
                            text = newText;
                            modified = true;
                        }
                    }

                    if (modified) {
                        FileOutputStream fos = new FileOutputStream(file);
                        fos.write(text.getBytes());
                        fos.close();
                    }
                } catch (Exception e) {
                    // Silently skip files that can't be patched
                }
            }
        }
    }

    /**
     * Recursively fix symlinks under a directory whose target contains oldStr.
     */
    private static void patchSymlinksRecursive(File dir, String oldStr, String newStr) {
        File[] files = dir.listFiles();
        if (files == null)
            return;

        for (File file : files) {
            try {
                // Use lstat to detect symlinks (doesn't follow them)
                android.system.StructStat stat = Os.lstat(file.getAbsolutePath());
                boolean isLink = android.system.OsConstants.S_ISLNK(stat.st_mode);

                if (isLink) {
                    String target = Os.readlink(file.getAbsolutePath());
                    if (target.contains(oldStr)) {
                        String newTarget = target.replace(oldStr, newStr);
                        file.delete();
                        Os.symlink(newTarget, file.getAbsolutePath());
                    }
                } else if (file.isDirectory()) {
                    patchSymlinksRecursive(file, oldStr, newStr);
                }
            } catch (Exception e) {
                // Silently skip
            }
        }
    }

    /** Check if a file is a symbolic link */
    private static boolean isSymlink(File file) {
        try {
            File canon;
            if (file.getParent() == null) {
                canon = file;
            } else {
                File canonDir = file.getParentFile().getCanonicalFile();
                canon = new File(canonDir, file.getName());
            }
            return !canon.getCanonicalFile().equals(canon.getAbsoluteFile());
        } catch (Exception e) {
            return false;
        }
    }

}
