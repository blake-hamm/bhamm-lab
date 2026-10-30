# Network & MTU

The lab runs jumbo frames end to end, but **jumbo only survives on the
switching plane**. This page records the MTU ladder and the one rule that
follows from it: jumbo-to-jumbo flows must stay inside a single VLAN.

## Topology

- Proxmox nodes and the Kubernetes nodes are on VLAN 30.
- Inter-VLAN routing is done by the TP-Link Omada 10Gb switch (gateway
  `10.0.30.2`), *not* by OPNsense. OPNsense (`10.0.30.1`, `10.0.20.1`, ...)
  only serves WAN-bound traffic behind the 2.5Gb switch.
- Garage is dual-homed, so it is reachable on VLAN 30 (`10.0.30.21`).

## The MTU ladder

| Layer | Value | Source |
| --- | --- | --- |
| Proxmox physical NICs (`enp67s0f0/f1`) | 9216 | `ansible/templates/network/` |
| `vmbr0` | 9216 | `ansible/templates/network/` |
| `vmbr0.20`, `vmbr0.30`, Ceph VLAN 50 | 9000 / 9216 | `ansible/templates/network/` |
| Talos VMs (guest `eth0`) | 9000 | `tofu/proxmox/talos/variables.tf` |
| Garage VM (both NICs) | 9000 | `tofu/proxmox/garage/variables.tf`, `nix/hosts/garage/garage.nix` |
| Cilium pods | 8950 | `tofu/proxmox/talos/config/cilium-values.yaml` |
| USB4 mesh (`10.30.0.78/79`) | 65520 | `tofu/proxmox/talos/cluster.tf` |
| OPNsense `lagg1` + VLANs | 1500 (wg0 1420) | **not managed in ansible** |

Each layer is a step below its parent, so the ladder itself is correct.
8950 = 9000 − 50 (VXLAN); pods are deliberately large because backup traffic
to Garage is on-link and benefits from it.

## Where jumbo stops

The Omada switch forwards 9216-byte frames (measured: 8000-byte DF pings
pass between hosts on a VLAN) but its **L3 engine routes at 1500**, and it
does **not** emit ICMP *fragmentation needed* when it drops an oversized
datagram. The result is a silent black hole, not a fast-failing error.

This is a documented platform limitation, not a misconfiguration. The
SX3008F is an L2+ aggregation switch: TP-Link's forum has an open
*"[FEATURE REQUEST] Jumbo frames L3 routing"* thread stating the switch
*"is not capable of routing Jumbo frames in L3 standalone mode"*, with
reports on firmware 1.20.x that VLAN interfaces stay at MTU 1500 even when
L2 jumbo is set to 9216. The datasheet's *Jumbo Frame: 9 KB* line sits
under **Performance** (frame forwarding), not under L3 features. The L3
interface page reports `MTU is 1500 byte`, `ICMP unreachables are never
sent`, both read-only.

Naming, for future searches: the failure is a **PMTUD black hole**
(RFC 2923) in its silent form, the configuration is **MTU asymmetry across
a routed boundary** (L2 9216 / L3 1500), and the vendor limitation is
**no L3 jumbo forwarding**. The ICMP-free rescue is **PLPMTUD** (RFC 4821),
which `net.ipv4.tcp_mtu_probing = 1` approximates — that is why long-lived
flows (rclone backups) eventually complete at low throughput instead of
failing, while a TLS handshake dies first.

Measured from a pod on a VLAN 30 node:

| Destination | Path | 8000 B DF ping |
| --- | --- | --- |
| `10.0.30.11` (Proxmox, VLAN 30) | switched | passes |
| `10.0.30.21` (Garage, VLAN 30) | switched | passes |
| `10.0.20.11` (Proxmox, VLAN 20) | routed | dropped |

PMTU to a VLAN 20 address is exactly 1500: 1472-byte pings pass, 1500-byte
pings disappear. A pod still negotiates `mss:8848 pmtu:8900`, so every
jumbo segment it sends towards an inter-VLAN address is dropped and only
retransmission recovers.

## The rule

> **Jumbo-to-jumbo flows must be addressed on VLAN 30.**

Both ends being jumbo *and* a route in between is the broken case. Removing
any one of the three makes it work:

- **Same VLAN** — switched, jumbo intact. This is why Garage is
  `10.0.30.21` in `kubernetes/manifests/base/garage/endpoints-all.yaml` and
  why backups are fast.
- **Peer is 1500** — the peer advertises MSS 1460, so the sender caps itself
  and fits. Internet and Pi-hole traffic is unaffected.
- **Routed jumbo peer** — broken.

So from inside the cluster, always use the VLAN 30 address of an
infrastructure host: `10.0.30.11-13` for Proxmox (API `:8006`, RGW `:7480`,
node-exporter `:9100`, ceph `:9283`, smartctl `:9633`, systemd `:9558`),
`10.0.30.21` for Garage. All of those services bind `0.0.0.0`, so
re-addressing is a manifest change only.

This is already applied to:

- `kubernetes/manifests/base/ceph/rgw-endpoints-all.yaml` (`external-rgw`)
- `kube-prom-stack-all.yaml` scrape targets
- `.forgejo/workflows/ci-vault-smoke.yml`, which pins
  `-var proxmox_url=https://10.0.30.11:8006` — the job runs in a pod, so it
  is subject to the rule even though a workstation on VLAN 80 is not.

## Failure signature

Symptom-driven recognition, in the order it usually shows up:

1. `tofu` / any Go client against an inter-VLAN host fails with
   `EOF` on the first request, after the provider's retry budget
   (~101 s), with **no matching access-log line on the server** — the
   request never arrived.
2. `GODEBUG=tlsmlkem=0` makes the same command succeed. That is not a fix:
   it shrinks the TLS 1.3 ClientHello below the black hole, and silently
   drops post-quantum key exchange.
3. `curl` against the same URL works. Its ClientHello is small, so it never
   hits the boundary.
4. Socket stats on the client show `lost:N` climbing with `retrans` and RTO
   `backoff` while `bytes_acked` stays flat.

A TLS 1.3 ClientHello with a hybrid key share is 1455 bytes of payload and
1507 bytes on the wire — 7 bytes past the boundary, which is why Go clients
break while everything else appears healthy.

## Fixing it properly

Short of re-architecting, the durable options are:

1. **Address jumbo peers on VLAN 30** (done). Zero performance cost.
2. **Raise the switch's L3 MTU**, if the firmware allows it. It does not
   here: the *Jumbo Frame* toggle in the Omada UI governs switching only,
   and the routed interface MTU is fixed at 1500.
3. **MSS clamp** at the routed boundary. Omada switches do not offer it, and
   it would cap those flows at 1460 anyway, so option 1 is strictly better.

Do **not** lower Cilium's MTU to fix this: it would slow every on-link
backup for a problem that only exists on the routed path, and it hides the
black hole rather than fixing it.
