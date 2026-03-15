package com.terminal.pepebot;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.animation.Animation;
import android.view.animation.AnimationUtils;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.appcompat.app.AppCompatActivity;

import com.termux.app.TermuxActivity;
import com.termux.shared.file.FileUtils;
import com.termux.shared.termux.TermuxConstants;
import com.termux.shared.termux.file.TermuxFileUtils;

public class SplashActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_splash);

        ImageView logo = findViewById(R.id.iv_logo);
        TextView title = findViewById(R.id.tv_title);

        Animation bounceAnim = AnimationUtils.loadAnimation(this, R.anim.splash_bounce);
        logo.startAnimation(bounceAnim);
        title.startAnimation(bounceAnim);

        // Delay for 2 seconds then determine destination based on installation status
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            boolean isBootstrapInstalled = FileUtils.directoryFileExists(TermuxConstants.TERMUX_PREFIX_DIR_PATH, true)
                    && !TermuxFileUtils.isTermuxPrefixDirectoryEmpty();

            Intent intent;
            if (isBootstrapInstalled) {
                intent = new Intent(SplashActivity.this, HomeActivity.class);
            } else {
                intent = new Intent(SplashActivity.this, TermuxActivity.class);
            }
            startActivity(intent);
            finish();
        }, 2000);
    }
}
