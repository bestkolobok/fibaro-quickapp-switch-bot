/**
 * SwitchBot Webhook Proxy for Fibaro HC3
 *
 * Deploy this as a Cloudflare Worker to receive webhooks from SwitchBot
 * and forward them to your Fibaro HC3.
 *
 * Setup:
 * 1. Create account at https://workers.cloudflare.com
 * 2. Create new Worker and paste this code
 * 3. Set environment variables (Settings -> Variables):
 *    - HC3_URL: Your Fibaro HC3 URL (e.g., http://192.168.1.100)
 *    - HC3_USER: Admin username
 *    - HC3_PASSWORD: Admin password
 *    - QUICKAPP_ID: Your SwitchBot QuickApp device ID
 * 4. Deploy and copy the Worker URL
 * 5. Use Worker URL as webhookUrl in SwitchBot QuickApp
 */

export default {
  async fetch(request, env) {
    // Only accept POST requests
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    try {
      // Get webhook payload from SwitchBot
      const payload = await request.json();

      console.log('Received webhook:', JSON.stringify(payload));

      // Forward to Fibaro HC3
      const hc3Response = await forwardToFibaro(payload, env);

      return new Response(JSON.stringify({
        success: true,
        hc3Status: hc3Response.status
      }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      });

    } catch (error) {
      console.error('Error:', error.message);
      return new Response(JSON.stringify({
        success: false,
        error: error.message
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
};

async function forwardToFibaro(payload, env) {
  const { HC3_URL, HC3_USER, HC3_PASSWORD, QUICKAPP_ID } = env;

  if (!HC3_URL || !HC3_USER || !HC3_PASSWORD || !QUICKAPP_ID) {
    throw new Error('Missing environment variables');
  }

  // Fibaro HC3 API endpoint
  const url = `${HC3_URL}/api/callAction`;

  // Basic auth header
  const auth = btoa(`${HC3_USER}:${HC3_PASSWORD}`);

  // Call QuickApp method
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      deviceId: parseInt(QUICKAPP_ID),
      name: 'handleWebhook',
      args: [payload]
    })
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`HC3 error: ${response.status} - ${text}`);
  }

  return response;
}