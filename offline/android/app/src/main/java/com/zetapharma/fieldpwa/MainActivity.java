package com.zetapharma.fieldpwa;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.Plugin;
import com.capacitorjs.plugins.browser.BrowserPlugin;

import java.util.ArrayList;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Register plugins
        ArrayList<Class<? extends Plugin>> plugins = new ArrayList<>();
        plugins.add(BrowserPlugin.class);
        registerPlugins(plugins);
    }
}
