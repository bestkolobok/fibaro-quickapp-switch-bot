# SwitchBot QuickApp for Fibaro HC3

[![Fibaro Marketplace](https://img.shields.io/badge/Fibaro-Marketplace-blue)](https://marketplace.fibaro.com/items/switchbot-integration)
[![GitHub issues](https://img.shields.io/github/issues/bestkolobok/fibaro-quickapp-switch-bot)](https://github.com/bestkolobok/fibaro-quickapp-switch-bot/issues)
[![GitHub stars](https://img.shields.io/github/stars/bestkolobok/fibaro-quickapp-switch-bot)](https://github.com/bestkolobok/fibaro-quickapp-switch-bot/stargazers)

Integrate SwitchBot devices with Fibaro Home Center 3. Control your smart curtains and bots directly from Fibaro interface.

[👉 Marketplace](https://marketplace.fibaro.com/items/switchbot-integration)

## Requirements

- Fibaro Home Center 3
- SwitchBot account with API access enabled
- **SwitchBot Hub Mini** or **SwitchBot Hub 2** (required for cloud API access)
    - ⚠️ Original SwitchBot Hub (1st gen) does not support Cloud API
- SwitchBot devices paired with your Hub

## Supported Devices

| Device | Type | Features |
|--------|------|----------|
| SwitchBot Curtain | `com.fibaro.rollerShutter` | Open, Close, Set Position, Battery |
| SwitchBot Curtain 3 | `com.fibaro.rollerShutter` | Open, Close, Set Position, Battery |
| SwitchBot Bot | `com.fibaro.binarySwitch` | On, Off, Press, Battery |

## Installation

### Option 1: Import FQA file (Recommended)

1. Download `SwitchBot.fqa` from this repository
2. In Fibaro HC3, go to **Settings → Devices → Add Device → Other Device**
3. Choose **Upload File** and select the downloaded `.fqa` file

### Option 2: Manual Installation

1. Create new QuickApp (Generic Device type)
2. Copy contents of each `.lua` file to corresponding tabs

## Configuration

### 1. Get SwitchBot API Credentials

1. Open **SwitchBot** app on your phone
2. Go to **Profile → Preferences**
3. Tap on app version 10 times to enable **Developer Options**
4. Copy **Token** and **Secret Key**

### 2. Configure QuickApp Variables

Set the following variables in QuickApp settings:

| Variable | Description | Required |
|----------|-------------|----------|
| `profile_token` | API token from SwitchBot app | ✅ |
| `profile_secret` | Secret key from SwitchBot app | ✅ |

### 3. Add Devices

1. Click **"Test Connection"** to verify credentials
2. Click **"Search Devices"** to discover SwitchBot devices
3. Select devices from the dropdown
4. Click **"Add Selected"** to create child devices

## How It Works

### Smart Polling

The QuickApp uses intelligent polling to synchronize device states while respecting SwitchBot API limits (10,000 requests/day).

| Mode | Interval | When |
|------|----------|------|
| **Idle** | 5 min | Normal operation |
| **Sleep** | 15 min | Night time (23:00 - 07:00) |

**After sending a command:**
- UI immediately shows the target value
- Device updates are blocked for 30 seconds
- Single status request after 30 seconds to get actual state

This prevents UI "jumping" while the device is still moving.

### Webhook Support (Experimental)

For instant updates without polling, you can configure webhooks. This requires your HC3 to be accessible from the internet via a proxy.

See `webhook-examples/` folder for:
- **Cloudflare Worker** - free and easy to deploy
- **Node.js proxy** - for self-hosted solutions

## Development

This project uses [plua](https://github.com/jangabrielsson/plua) for QuickApp development.

### Prerequisites

Install plua:

```bash
pip install plua
```

Configure plua with your HC3 credentials:

```bash
plua config
```

### Development Workflow

#### 1. Unpack FQA for editing

**Important:** Always unpack from `SwitchBot.fqa` file, not from HC3:

```bash
plua -t unpack dist/SwitchBot.fqa src
```

This extracts `.lua` files to the project root (where `.project` file is located).

#### 2. Edit source files

Edit `.lua` files using your favorite editor.

#### 3. Local debugging with Desktop UI

Add header to `SwitchBot.lua` for desktop window:

```lua
--%%desktop:true
```

Run locally with Fibaro SDK emulation:

```bash
plua --fibaro src/SwitchBot.lua
```

This opens a desktop window showing QuickApp UI and debug output without uploading to HC3.

Other useful run options:

```bash
# Run for specific duration
plua --fibaro src/SwitchBot.lua --run-for 60

# Run in offline mode (no HC3 connection)
plua --fibaro src/SwitchBot.lua -o
```

#### 4. Pack FQA for distribution

```bash
plua -t pack src/SwitchBot.lua dist/SwitchBot.fqa
```

#### 5. Upload to HC3 for testing

```bash
plua -t uploadQA dist/SwitchBot.fqa
```

### Debug Directives

Add these to `SwitchBot.lua` header:

```lua
--%%name=SwitchBot
--%%type=com.fibaro.deviceController
--%%desktop:true
```

### Debug Levels

```lua
self:trace("Detailed info")      -- Verbose, for development
self:debug("General info")       -- Normal debugging
self:warning("Something wrong")  -- Warnings
self:error("Critical error")     -- Errors
```

## Issues & Feature Requests

Found a bug or have a feature request?

👉 [Create an issue](https://github.com/bestkolobok/fibaro-quickapp-switch-bot/issues/new)

## Support the Project

If you find this QuickApp useful:

⭐ **Give it a star on GitHub!** ⭐

It helps others discover the project and motivates further development.