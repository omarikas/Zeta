# OAuth Configuration for Capacitor App

This document describes the OAuth setup for the Pharma Field app, which supports both web (PWA) and native (Capacitor) platforms.

## OAuth Flow

The app uses the **Authorization Code with PKCE** flow for secure authentication.

### Platform-Specific Callback URLs

| Platform | Callback URL |
|----------|--------------|
| Web (PWA) | `https://omarikas.github.io/Zeta` |
| Capacitor (iOS/Android) | `com.zetapharma.fieldpwa://oauth/callback` |

## Salesforce Connected App Configuration

To enable OAuth for the Capacitor app, you need to add the custom URL scheme callback to your Salesforce Connected App:

1. Go to **Setup** → **App Manager**
2. Find your Connected App (Client ID: `3MVG9U65ySgtae71Qj6sHa91riS85fiD5Ndf7MVHpJQwOPlo1bAScoaXG28Yvfwx05xwl.R8NaGGLPFUDSj_y`)
3. Click **Edit**
4. In **OAuth Scopes**, ensure these scopes are selected:
   - `api` - Access APIs
   - `refresh_token** - Perform requests on your behalf at any time
5. in **Callback URL**, add:
   - `https://omarikas.github.io/Zeta` (for web PWA)
   - `com.zetapharma.fieldpwa://oauth/callback` (for Capacitor app)
6. Save the changes

## Vercel Token Proxy

The Vercel serverless function at `/api/sf-token.js` handles the token exchange to avoid CORS issues.

### Configuration

The token proxy is deployed at: `https://zeta-pwa.vercel.app/api/sf-token`

### How It Works

1. The app sends the authorization code to the Vercel proxy
2. The proxy forwards the request to Salesforce with the client secret
3. The proxy returns the token response to the app

### Environment Variables (Optional)

For enhanced security, you can set these environment variables in Vercel:

| Variable | Description |
|----------|-------------|
| `SF_CLIENT_ID` | Salesforce Connected App Client ID |
| `SF_CLIENT_SECRET` | Salesforce Connected App Client Secret |

## Native App Configuration

### iOS (Info.plist)

The custom URL scheme is registered in `ios/App/App/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.zetapharma.fieldpwa</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.zetapharma.fieldpwa</string>
        </array>
    </dict>
</array>
```

### Android (AndroidManifest.xml)

The intent filter is added to `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.zetapharma.fieldpwa" android:host="oauth" android:pathPrefix="/callback" />
</intent-filter>
```

## Building and Running

### Web (PWA)
```bash
npm run build
# Deploy dist/ to GitHub Pages
```

### Capacitor (iOS/Android)
```bash
npm run build
npx cap sync
npx cap open ios     # Open in Xcode
npx cap open android # Open in Android Studio
```

## Troubleshooting

### Common Issues

1. **"Invalid callback URL" error**
   - Ensure the callback URL is added to the Salesforce Connected App
   - Check for trailing slashes or typos

2. **Deep link not opening app (iOS)**
   - Verify `CFBundleURLTypes` is correctly configured in Info.plist
   - Ensure the URL scheme matches exactly

3. **Deep link not opening app (Android)**
   - Verify the intent filter in AndroidManifest.xml
   - Check that `android:launchMode="singleTask"` is set on MainActivity

4. **Token exchange fails**
   - Check that the Vercel function is deployed and accessible
   - Verify the client secret matches the Salesforce Connected App