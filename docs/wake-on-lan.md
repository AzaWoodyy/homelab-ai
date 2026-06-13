# Wake-on-LAN Setup Guide

This guide covers the target-PC and network setup required to make Wake-on-LAN reliable for the Windows gaming PC that hosts this homelab stack.

This repo no longer acts as the supported runtime home for the relay service itself. Use the companion Wake Relay project in [`wake-relay/`](../wake-relay/README.md) for the always-on machine that will send the magic packet.

The goal is simple:

- The gaming PC should wake from sleep when another device sends a magic packet.
- The gaming PC should also wake from shutdown if the motherboard and NIC support it and Fast Startup is not getting in the way.

## What Wake-on-LAN Depends On

Wake-on-LAN is only reliable when all of these are true:

- The gaming PC uses wired Ethernet, not Wi-Fi.
- The motherboard keeps standby power available to the Ethernet controller while the PC is asleep or shut down.
- The Ethernet adapter is configured to wake the machine on a magic packet.
- You test on the same local network first before trying anything more complicated.

If the Ethernet port link lights turn off completely after sleep or shutdown, Wake-on-LAN usually will not work until the BIOS/UEFI power settings are corrected.

## BIOS Or UEFI Prerequisites

In the motherboard firmware, enable the setting that allows the network adapter or PCIe device to power the machine back on. Vendors use different names, so look for one of these labels or something very close:

- `Wake on LAN`
- `Power On By PCI-E`
- `Power On By PCI`
- `Resume By PCI-E Device`
- `PCIe Device Power On`

Also look for power-saving options that remove standby power from the NIC and disable them when needed. Common names include:

- `ErP`
- `ErP Ready`
- `Deep Sleep`
- `EuP`
- `S5 Eco Mode`

Expected result:

- Wake-on-LAN or PCIe wake is enabled.
- ErP or deep-sleep-style settings that cut NIC standby power are disabled.

After saving firmware changes, do a full reboot before testing. A warm reboot is often enough, but if the board behaves strangely after a firmware change, power the machine off completely once and boot it again.

## Windows Power Settings

Windows power behavior matters because "wake from sleep" and "wake from shutdown" are not always the same thing.

- Sleep usually keeps enough power available for Wake-on-LAN when the firmware and NIC are configured correctly.
- Full shutdown wake is more sensitive and can fail when Fast Startup is enabled.

When you want Wake-on-LAN to work from a powered-off state, disable Fast Startup:

1. Open `Control Panel > Hardware and Sound > Power Options`.
2. Select `Choose what the power buttons do`.
3. Select `Change settings that are currently unavailable`.
4. Clear `Turn on fast startup (recommended)`.
5. Save changes.

Fast Startup can leave Windows in a hybrid-shutdown state that does not behave like a clean S5 shutdown for Wake-on-LAN. If Wake-on-LAN works from sleep but not from shutdown, Fast Startup is one of the first things to check.

## NIC Device Manager Settings

Configure the physical wired Ethernet adapter in Device Manager, not Wi-Fi and not a virtual adapter.

1. Open `Device Manager`.
2. Expand `Network adapters`.
3. Select the wired Ethernet adapter that is physically connected to the network.
4. Open `Properties`.

On the `Power Management` tab:

- Enable `Allow this device to wake the computer`.
- Enable `Only allow a magic packet to wake the computer`.

On the `Advanced` tab, enable the vendor-specific wake options that apply to magic packets. Common names include:

- `Wake on Magic Packet`
- `Shutdown Wake-On-Lan`
- `Wake From Shutdown`
- `Power On By Magic Packet`

If you see unrelated wake options such as pattern match wake, keep the focus on magic-packet wake first.

Do not use the MAC address from these adapter types:

- Wi-Fi
- Bluetooth
- Hyper-V virtual switches
- Tailscale
- Docker
- VPN adapters
- Any other virtual or tunnel adapter

The correct target is the physical wired Ethernet adapter that remains connected when the gaming PC sleeps or shuts down.

## Finding The Correct MAC Address

The source of truth for Wake-on-LAN is the gaming PC's physical MAC address for the wired Ethernet adapter that stays connected while the machine is asleep or shut down.

Preferred command:

```powershell
Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceDescription, MacAddress, LinkSpeed
```

Use that output to identify the active wired Ethernet adapter and copy its `MacAddress`.

Fallback command:

```powershell
ipconfig /all
```

In the fallback output, find the wired Ethernet adapter and copy its `Physical Address`.

Ignore addresses shown for Wi-Fi, Bluetooth, Hyper-V, Tailscale, Docker, VPN, or other virtual adapters.

## Where To Store The MAC Address

Store the chosen MAC address in the dedicated Wake Relay project's local-only config on the always-on machine.

The companion relay project expects a relay-specific local config file and shared secret, so keep the MAC address there rather than treating this repo as the place that runs the wake endpoint.

## Remote Wake Over Tailscale

Tailscale gives the remote access path, but it does not remove the basic Wake-on-LAN constraint: the magic packet still needs to be sent by a machine that is awake and on the same LAN as the gaming PC.

Use this model:

- Keep one always-on relay node on the home LAN.
- Install Tailscale on that relay node.
- Use the dedicated Wake Relay project on that relay node.
- Set the relay project's `target_mac` and `shared_secret` in that relay node's local config.
- Start the relay from the companion project.
- Open the relay's Tailscale HTTPS URL from your phone, MacBook, or laptop and press the wake button.

If the relay host can wake the gaming PC locally, then exposing that relay over Tailscale is the clean remote step.

## Validation Workflow

Use this validation flow from another device on the same LAN first. Do not start with remote wake across routers or over Tailscale.

1. Put the gaming PC to sleep.
2. From another device on the same LAN, send a magic packet to the stored wired-NIC MAC address using any Wake-on-LAN app or CLI.
3. Confirm that the gaming PC wakes.
4. Disable Fast Startup if you have not already.
5. Shut the gaming PC down fully.
6. Send the same magic packet again.
7. Confirm that the gaming PC also wakes from shutdown if the motherboard and NIC support it.

Expected outcome:

- Wake from sleep should work first.
- Wake from shutdown should work after Fast Startup is disabled, assuming the motherboard and Ethernet adapter support it.

If validation fails, re-check these items in order:

- The Ethernet cable is connected and the wired link lights stay on when the PC is asleep or shut down.
- BIOS/UEFI still provides standby power to the NIC.
- The NIC power-management and advanced wake settings are still enabled.
- The stored MAC address belongs to the wired Ethernet adapter, not a virtual or wireless adapter.
- Testing is happening on the same LAN before introducing any remote-routing variables.
