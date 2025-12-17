/**
 * SwitchBot Webhook Proxy for Fibaro HC3 (Node.js version)
 * 
 * Run this on a server accessible from internet (VPS, Raspberry Pi with port forwarding, etc.)
 * 
 * Setup:
 * 1. npm init -y
 * 2. npm install express node-fetch
 * 3. Set environment variables or edit config below
 * 4. node webhook-proxy.js
 * 5. Use http://<your-server>:3000/webhook as webhookUrl in SwitchBot QuickApp
 * 
 * For HTTPS (recommended), use nginx/caddy as reverse proxy or Let's Encrypt
 */

const express = require('express');
const fetch = require('node-fetch');

// Configuration - set via environment variables or edit here
const config = {
  port: process.env.PORT || 3000,
  hc3Url: process.env.HC3_URL || 'http://192.168.1.100',  // Your HC3 IP
  hc3User: process.env.HC3_USER || 'admin',
  hc3Password: process.env.HC3_PASSWORD || 'your-password',
  quickAppId: process.env.QUICKAPP_ID || '123'  // Your QuickApp device ID
};

const app = express();
app.use(express.json());

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ status: 'ok', message: 'SwitchBot Webhook Proxy' });
});

// Webhook endpoint
app.post('/webhook', async (req, res) => {
  console.log('Received webhook:', JSON.stringify(req.body, null, 2));
  
  try {
    const result = await forwardToFibaro(req.body);
    res.json({ success: true, hc3Status: result.status });
  } catch (error) {
    console.error('Error forwarding to HC3:', error.message);
    res.status(500).json({ success: false, error: error.message });
  }
});

async function forwardToFibaro(payload) {
  const url = `${config.hc3Url}/api/callAction`;
  
  // Basic auth
  const auth = Buffer.from(`${config.hc3User}:${config.hc3Password}`).toString('base64');
  
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      deviceId: parseInt(config.quickAppId),
      name: 'handleWebhook',
      args: [payload]
    })
  });
  
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HC3 responded with ${response.status}: ${text}`);
  }
  
  return response;
}

app.listen(config.port, () => {
  console.log(`Webhook proxy running on port ${config.port}`);
  console.log(`Webhook URL: http://localhost:${config.port}/webhook`);
  console.log(`Forwarding to: ${config.hc3Url} (QuickApp ID: ${config.quickAppId})`);
});
