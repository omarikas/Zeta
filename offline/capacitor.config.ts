import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.zetapharma.fieldpwa',
  appName: 'Pharma Field',
  webDir: 'dist',
  server: {
    androidScheme: 'https'
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      backgroundColor: '#0176d3',
      showSpinner: false,
      androidSpinnerStyle: 'small',
      spinnerColor: '#ffffff'
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#0176d3'
    },
    App: {
      // Handle deep links for OAuth callbacks
      deepLinks: [
        {
          scheme: 'com.zetapharma.fieldpwa',
          path: '/oauth/callback'
        }
      ]
    }
  }
};

export default config;