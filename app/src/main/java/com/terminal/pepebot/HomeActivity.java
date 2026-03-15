package com.terminal.pepebot;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.View;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;

import com.termux.app.TermuxActivity;
import com.termux.shared.termux.TermuxConstants;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.Socket;
import java.net.SocketException;
import java.util.Enumeration;

public class HomeActivity extends AppCompatActivity {

    private boolean isServerRunning = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_home);

        ImageView ivLogo = findViewById(R.id.iv_home_logo);
        TextView tvTitle = findViewById(R.id.tv_home_title);
        android.view.animation.Animation bounceAnim = android.view.animation.AnimationUtils.loadAnimation(this, R.anim.jump_bounce);
        ivLogo.startAnimation(bounceAnim);
        tvTitle.startAnimation(bounceAnim);

        findViewById(R.id.card_dashboard).setOnClickListener(v -> openDashboard());
        findViewById(R.id.card_config).setOnClickListener(v -> showConfigDialog());
        findViewById(R.id.card_server).setOnClickListener(v -> toggleServer());
        findViewById(R.id.card_terminal).setOnClickListener(v -> openTerminal());
        findViewById(R.id.card_update).setOnClickListener(v -> updatePepebot());
        findViewById(R.id.card_about).setOnClickListener(v -> showAboutDialog());
    }

    @Override
    protected void onResume() {
        super.onResume();
        checkServerStatus();
    }

    private void checkServerStatus() {
        new Thread(() -> {
            boolean reachable = false;
            try (Socket socket = new Socket("127.0.0.1", 18790)) {
                reachable = true;
            } catch (IOException ignored) {}

            isServerRunning = reachable;
            runOnUiThread(() -> {
                ImageView icon = findViewById(R.id.iv_server_icon);
                TextView text = findViewById(R.id.tv_server_text);
                View dashboardCard = findViewById(R.id.card_dashboard);

                if (isServerRunning) {
                    icon.setImageResource(R.drawable.ic_stop);
                    text.setText("Stop Server");
                    // Using android.R.color.holo_red_light for the stop icon
                    icon.setColorFilter(getResources().getColor(android.R.color.holo_red_light, getTheme()));
                    
                    dashboardCard.setEnabled(true);
                    dashboardCard.setAlpha(1.0f);
                } else {
                    icon.setImageResource(R.drawable.ic_play);
                    text.setText("Start Server");
                    icon.setColorFilter(getResources().getColor(R.color.pepebot_secondary, getTheme()));

                    dashboardCard.setEnabled(false);
                    dashboardCard.setAlpha(0.5f);
                }
            });
        }).start();
    }

    private void toggleServer() {
        if (!isServerRunning) {
            File configFile = new File(TermuxConstants.TERMUX_HOME_DIR_PATH + "/.pepebot/config.json");
            if (!configFile.exists()) {
                showToast("Please configure Pepebot before starting the server.");
                showConfigDialog();
                return;
            }
            Intent intent = new Intent(this, TermuxActivity.class);
            intent.putExtra("RUN_COMMAND", "termux-chroot pepebot gateway");
            showToast("Termux Command Sent: Start Server");
            startActivity(intent);
        } else {
            new AlertDialog.Builder(this)
                    .setTitle("Stop Server")
                    .setMessage("Are you sure you want to stop the server?")
                    .setPositiveButton("Yes", (dialog, which) -> {
                        Intent intent = new Intent(this, TermuxActivity.class);
                        intent.putExtra("RUN_COMMAND", "CTRL_C");
                        showToast("Termux Command Sent: Stop Server");
                        startActivity(intent);
                    })
                    .setNegativeButton("No", null)
                    .show();
        }
    }

    private void showConfigDialog() {
        File configFile = new File(TermuxConstants.TERMUX_HOME_DIR_PATH + "/.pepebot/config.json");
        StringBuilder content = new StringBuilder();
        if (configFile.exists()) {
            try (FileInputStream fis = new FileInputStream(configFile)) {
                int ch;
                while ((ch = fis.read()) != -1) {
                    content.append((char) ch);
                }
            } catch (IOException e) {
                e.printStackTrace();
            }
        }

        View dialogView = getLayoutInflater().inflate(R.layout.dialog_config, null);
        Spinner spinnerProvider = dialogView.findViewById(R.id.spinner_provider);
        EditText etApiKey = dialogView.findViewById(R.id.et_api_key);
        
        EditText etTemperature = dialogView.findViewById(R.id.et_temperature);
        EditText etMaxIterations = dialogView.findViewById(R.id.et_max_iterations);
        EditText etBraveApi = dialogView.findViewById(R.id.et_brave_api_key);

        CheckBox cbTelegram = dialogView.findViewById(R.id.cb_telegram);
        EditText etTelegramToken = dialogView.findViewById(R.id.et_telegram_token);
        CheckBox cbDiscord = dialogView.findViewById(R.id.cb_discord);
        EditText etDiscordToken = dialogView.findViewById(R.id.et_discord_token);
        CheckBox cbWhatsapp = dialogView.findViewById(R.id.cb_whatsapp);

        // Define Providers
        String[] providersInfo = {
                "MAIA Router", "Anthropic", "OpenAI", "OpenRouter",
                "Gemini", "Groq", "Zhipu", "Vertex AI"
        };
        String[] providersKeys = {"maiarouter", "anthropic", "openai", "openrouter", "gemini", "groq", "zhipu", "vertex"};

        android.widget.ArrayAdapter<String> adapter = new android.widget.ArrayAdapter<>(
                this, android.R.layout.simple_spinner_dropdown_item, providersInfo);
        spinnerProvider.setAdapter(adapter);

        // Toggle visibility based on Checkbox state
        cbTelegram.setOnCheckedChangeListener((btn, isChecked) -> {
            etTelegramToken.setVisibility(isChecked ? View.VISIBLE : View.GONE);
        });
        cbDiscord.setOnCheckedChangeListener((btn, isChecked) -> {
            etDiscordToken.setVisibility(isChecked ? View.VISIBLE : View.GONE);
        });

        // Initialize JSON
        org.json.JSONObject rootObj = null;
        try {
            if (content.length() > 0) {
                rootObj = new org.json.JSONObject(content.toString());
            } else {
                rootObj = new org.json.JSONObject();
            }

            // Read Provider & Agent settings
            if (rootObj.has("agents") && rootObj.getJSONObject("agents").has("defaults")) {
                org.json.JSONObject defaults = rootObj.getJSONObject("agents").getJSONObject("defaults");
                
                String provider = defaults.optString("provider", "maiarouter");
                for (int i = 0; i < providersKeys.length; i++) {
                    if (providersKeys[i].equals(provider)) {
                        spinnerProvider.setSelection(i);
                        break;
                    }
                }
                
                etTemperature.setText(String.valueOf(defaults.optDouble("temperature", 0.7)));
                etMaxIterations.setText(String.valueOf(defaults.optInt("max_tool_iterations", 20)));
            }

            // Initial API Key loader based on selected provider
            if (rootObj.has("providers")) {
                org.json.JSONObject providersObj = rootObj.getJSONObject("providers");
                spinnerProvider.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener() {
                    @Override
                    public void onItemSelected(android.widget.AdapterView<?> parent, View view, int position, long id) {
                        String selectedKey = providersKeys[position];
                        if (providersObj.has(selectedKey)) {
                            // Some providers don't use api_key directly initially but the CLI does it this way
                            String key = providersObj.optJSONObject(selectedKey).optString("api_key", "");
                            etApiKey.setText(key);
                        } else {
                            etApiKey.setText("");
                        }
                    }

                    @Override
                    public void onNothingSelected(android.widget.AdapterView<?> parent) {}
                });
            }

            // Read Tools
            if (rootObj.has("tools") && rootObj.getJSONObject("tools").has("web") 
                && rootObj.getJSONObject("tools").getJSONObject("web").has("search")) {
                org.json.JSONObject searchObj = rootObj.getJSONObject("tools").getJSONObject("web").getJSONObject("search");
                etBraveApi.setText(searchObj.optString("api_key", ""));
            }

            // Read Channels
            if (rootObj.has("channels")) {
                org.json.JSONObject channelsObj = rootObj.getJSONObject("channels");
                if (channelsObj.has("telegram")) {
                    cbTelegram.setChecked(channelsObj.getJSONObject("telegram").optBoolean("enabled", false));
                    etTelegramToken.setText(channelsObj.getJSONObject("telegram").optString("token", ""));
                }
                if (channelsObj.has("discord")) {
                    cbDiscord.setChecked(channelsObj.getJSONObject("discord").optBoolean("enabled", false));
                    etDiscordToken.setText(channelsObj.getJSONObject("discord").optString("token", ""));
                }
                if (channelsObj.has("whatsapp")) {
                    cbWhatsapp.setChecked(channelsObj.getJSONObject("whatsapp").optBoolean("enabled", false));
                }
            }

        } catch (org.json.JSONException e) {
            e.printStackTrace();
            showToast("Failed to parse config.json");
        }

        final org.json.JSONObject finalRootObj = rootObj;

        AlertDialog dialog = new AlertDialog.Builder(this)
                .setView(dialogView)
                .setPositiveButton("Save", null) // Overridden in onShowListener to prevent auto-close
                .setNegativeButton("Cancel", null)
                .create();

        dialog.setOnShowListener(dialogInterface -> {
            android.widget.Button button = dialog.getButton(AlertDialog.BUTTON_POSITIVE);
            button.setOnClickListener(view -> {
                String apiKey = etApiKey.getText().toString().trim();
                
                // Allow empty API key ONLY for MAIARouter/Gemini implicitly if they don't require one, 
                // but user requested "api key harus diisi sesuai api provider". 
                if (apiKey.isEmpty()) {
                    showToast("API Key cannot be empty!");
                    return; // Halt save and keep dialog open
                }

                try {
                    if (finalRootObj != null) {
                        String selectedProviderKey = providersKeys[spinnerProvider.getSelectedItemPosition()];

                        // Save Provider, Temperature, Iterations Selection
                        if (!finalRootObj.has("agents")) finalRootObj.put("agents", new org.json.JSONObject());
                        if (!finalRootObj.getJSONObject("agents").has("defaults")) finalRootObj.getJSONObject("agents").put("defaults", new org.json.JSONObject());
                        
                        org.json.JSONObject defaults = finalRootObj.getJSONObject("agents").getJSONObject("defaults");
                        defaults.put("provider", selectedProviderKey);
                        
                        try {
                            defaults.put("temperature", Double.parseDouble(etTemperature.getText().toString()));
                        } catch (NumberFormatException ignored) {}
                        
                        try {
                            defaults.put("max_tool_iterations", Integer.parseInt(etMaxIterations.getText().toString()));
                        } catch (NumberFormatException ignored) {}

                        // Save Tools (Brave API)
                        if (!finalRootObj.has("tools")) finalRootObj.put("tools", new org.json.JSONObject());
                        org.json.JSONObject toolsObj = finalRootObj.getJSONObject("tools");
                        if (!toolsObj.has("web")) toolsObj.put("web", new org.json.JSONObject());
                        if (!toolsObj.getJSONObject("web").has("search")) toolsObj.getJSONObject("web").put("search", new org.json.JSONObject());
                        
                        toolsObj.getJSONObject("web").getJSONObject("search").put("api_key", etBraveApi.getText().toString());

                        // Save API Key
                        if (!finalRootObj.has("providers")) finalRootObj.put("providers", new org.json.JSONObject());
                        org.json.JSONObject pObj = finalRootObj.getJSONObject("providers");
                        if (!pObj.has(selectedProviderKey)) {
                            pObj.put(selectedProviderKey, new org.json.JSONObject());
                        }
                        pObj.getJSONObject(selectedProviderKey).put("api_key", apiKey);

                        // Save Channels
                        if (!finalRootObj.has("channels")) finalRootObj.put("channels", new org.json.JSONObject());
                        org.json.JSONObject cObj = finalRootObj.getJSONObject("channels");
                        
                        if (!cObj.has("telegram")) cObj.put("telegram", new org.json.JSONObject());
                        cObj.getJSONObject("telegram").put("enabled", cbTelegram.isChecked());
                        cObj.getJSONObject("telegram").put("token", etTelegramToken.getText().toString());
                        
                        if (!cObj.has("discord")) cObj.put("discord", new org.json.JSONObject());
                        cObj.getJSONObject("discord").put("enabled", cbDiscord.isChecked());
                        cObj.getJSONObject("discord").put("token", etDiscordToken.getText().toString());
                        
                        if (!cObj.has("whatsapp")) cObj.put("whatsapp", new org.json.JSONObject());
                        cObj.getJSONObject("whatsapp").put("enabled", cbWhatsapp.isChecked());

                        try {
                            File parentDir = configFile.getParentFile();
                            if (parentDir != null && !parentDir.exists()) {
                                parentDir.mkdirs();
                            }
                            try (FileOutputStream fos = new FileOutputStream(configFile)) {
                                fos.write(finalRootObj.toString(2).getBytes());
                                showToast("Config saved");
                                dialog.dismiss(); // Successfully saved
                            }
                        } catch (IOException e) {
                            e.printStackTrace();
                            showToast("Failed to save to config.json");
                        }
                    }
                } catch (org.json.JSONException e) {
                    e.printStackTrace();
                    showToast("Failed to build JSON");
                }
            });
        });
                
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        }
        dialog.show();
    }

    private void openDashboard() {
        String ip = getLocalIpAddress();
        // Fallback to localhost if no LAN IP found
        if (ip == null || ip.isEmpty()) {
            ip = "127.0.0.1";
        }
        String url = "http://dash.pepebot.space/#/login=" + ip + ":8080";
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setData(Uri.parse(url));
        try {
            startActivity(intent);
        } catch (Exception e) {
            showToast("Browser not found");
        }
    }

    private void updatePepebot() {
        Intent intent = new Intent(this, TermuxActivity.class);
        intent.putExtra("RUN_COMMAND", "pepebot update");
        startActivity(intent);
    }

    private void openTerminal() {
        Intent intent = new Intent(this, TermuxActivity.class);
        startActivity(intent);
    }

    private void showAboutDialog() {
        new AlertDialog.Builder(this)
                .setTitle("About Pepebot")
                .setMessage(
                        "Pepebot Android v1.0\n\nA modern terminal wrapper to run the Pepebot node smoothly on Android.\n\nBuilt with ❤️ by Pepebot 2026.")
                .setPositiveButton("OK", null)
                .show();
    }

    private String getLocalIpAddress() {
        try {
            for (Enumeration<NetworkInterface> en = NetworkInterface.getNetworkInterfaces(); en.hasMoreElements();) {
                NetworkInterface intf = en.nextElement();
                for (Enumeration<InetAddress> enumIpAddr = intf.getInetAddresses(); enumIpAddr.hasMoreElements();) {
                    InetAddress inetAddress = enumIpAddr.nextElement();
                    if (!inetAddress.isLoopbackAddress() && inetAddress instanceof Inet4Address) {
                        return inetAddress.getHostAddress();
                    }
                }
            }
        } catch (SocketException ex) {
            ex.printStackTrace();
        }
        return null;
    }

    private long backPressedTime;

    @Override
    public void onBackPressed() {
        if (backPressedTime + 2000 > System.currentTimeMillis()) {
            super.onBackPressed();
            finishAffinity(); // Ensure the whole app drops including terminal tasks
        } else {
            showToast("Tekan sekali lagi untuk keluar");
        }
        backPressedTime = System.currentTimeMillis();
    }

    private void showToast(String message) {
        Toast toast = new Toast(this);
        TextView tv = new TextView(this);
        tv.setText(message);
        tv.setTextColor(android.graphics.Color.BLACK);
        tv.setBackgroundColor(0xFFE0E0E0); // Light Gray
        tv.setPadding(40, 20, 40, 20);
        tv.setTextSize(14f);
        toast.setView(tv);
        toast.setDuration(Toast.LENGTH_LONG);
        toast.show();
    }
}
