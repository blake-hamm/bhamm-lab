# NUT Operations

Quick reference for managing and verifying the NUT (Network UPS Tools) power protection stack.

## Architecture Recap

- **Primary Servers:** Orange Pi Zero3 devices (`10.0.9.3`, `10.0.9.4`) running NixOS
  - Direct USB connection to CyberPower UPS units
  - Trigger global Forced Shutdown (FSD) when battery reaches 20%
- **Proxmox Clients:** `method`, `indy`, `japan`
  - Monitor `cyberpower@10.0.9.3` as NUT secondaries
  - Use `upssched` with a 10-minute local timer for early graceful shutdown
- **Talos Clients:** `nose`, `tail`
  - Use the `siderolabs/nut-client` Talos system extension
  - Monitor `cyberpower@10.0.9.4` as NUT secondaries
  - Shutdown on FSD only

## Orange Pi (NUT Server)

### Check UPS status
```bash
upsc cyberpower@localhost
```

### Check NUT services
```bash
systemctl status upsdrv.service upsd.service upsmon.service
```

### View NUT logs
```bash
journalctl -u nut-server -f
```

## Proxmox

### Check UPS connectivity
```bash
upsc cyberpower@10.0.9.3
systemctl status nut-monitor
```

### Check upssched timer status
```bash
cat /etc/nut/upssched.conf
cat /etc/nut/upssched-cmd
```

### Watch NUT client logs
```bash
journalctl -u nut-monitor -f
```

## Talos Bare Metal

### Verify extension is installed
```bash
talosctl -n <node-ip> get extensions
talosctl -n <node-ip> service ext-nut-client
```

### Read the live config
Find the PID from `talosctl -n <node-ip> service ext-nut-client`, then:
```bash
talosctl -n <node-ip> read /proc/<PID>/root/usr/local/etc/nut/upsmon.conf
```

### View NUT client logs
```bash
talosctl -n <node-ip> logs ext-nut-client
talosctl -n <node-ip> logs ext-nut-client --follow
```

## Testing

!!! warning "FSD triggers real shutdowns"
    Triggering a Forced Shutdown from the NUT server will cause **all connected clients** (Proxmox and Talos) to power off.

To test connectivity safely, use `upsc` from the client nodes. Do not trigger FSD unless you are ready for all connected systems to shut down.
