/**
 * Vercel Serverless Function to proxy Salesforce OAuth token exchange
 * This avoids CORS issues when calling from GitHub Pages
 */

const SF_LOGIN_URL = 'https://zetapharma.my.salesforce.com';

export default async function handler(req, res) {
  // Handle CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  try {
    const { grant_type, client_id, client_secret, redirect_uri, code, code_verifier, refresh_token } = req.body;
    
    const tokenUrl = `${SF_LOGIN_URL}/services/oauth2/token`;
    
    const params = new URLSearchParams({
      grant_type: grant_type || 'authorization_code',
      client_id: client_id || '',
      client_secret: client_secret || '',
      redirect_uri: redirect_uri || '',
      code: code || '',
      code_verifier: code_verifier || '',
    });

    if (grant_type === 'refresh_token') {
      params.delete('code');
      params.delete('code_verifier');
      params.delete('redirect_uri');
      params.set('refresh_token', refresh_token || '');
    }

    const response = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    const data = await response.json();

    return res.status(response.status).json(data);
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}
