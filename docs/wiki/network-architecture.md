# VM Network Architecture

This article explains the hybrid network configuration used for local development and testing VMs in this project (defined in [network-config](../../environments/os/debian13/cloud-init/network-config) and managed via [build.py](../../environments/build.py)).

## The Challenge
When provisioning VMs automatically using Ansible, the Ansible controller (on the host machine / WSL) needs a **predictable, static IP address** to connect to. 

However, hardcoding static IPs directly on a physical network can lead to:
1. **IP conflicts** with other devices on your home or office router.
2. **Router configuration issues**, since most home routers generate IP addresses dynamically via DHCP and do not allow clients to self-assign arbitrary fixed IPs.
3. **Loss of internet access** inside the VM if default gateways and DNS servers are configured incorrectly.

## The Solution: Hybrid Dual-Adapter Network

To resolve this, every test and development VM in this repository is built with **two separate network interfaces**:

```mermaid
graph TD
    subgraph Host Machine (Physical PC)
        WSL[WSL / Ansible Control Node]
        VirtualBox[VirtualBox Engine]
        VBoxNet[VirtualBox Host-Only Adapter<br/>IP: 192.168.56.1]
    end
    
    subgraph Guest VM
        nic1[nic1 / enp0s3<br/>NAT (DHCP)]
        nic2[nic2 / enp0s8<br/>Host-Only (Static IP)]
    end
    
    Router[Physical Router / Local LAN]
    Internet[Internet]

    WSL -->|SSH Connects to 192.168.56.50| VBoxNet
    VBoxNet <--> nic2
    
    nic1 <-->|Virtual NAT Engine| Router
    Router <--> Internet
```

---

### Adapter 1: NAT (`nic1` / `enp0s3`)
* **Type:** Network Address Translation (NAT)
* **IP Assignment:** **DHCP** (`dhcp4: true`)
* **Purpose:** Outgoing Internet/LAN traffic (e.g. running `apt-get install` or downloading tools).

**How it works:**
VirtualBox runs an internal DHCP server that automatically assigns the VM a private IP address (typically `10.0.2.15`). 

When the VM requests a website or package:
1. VirtualBox intercepts the traffic.
2. It translates the VM's internal IP (`10.0.2.15`) into your host PC's physical IP address.
3. It sends the request out to your local router just like ordinary traffic from your host PC.

Since the VM is hidden behind VirtualBox NAT, it acts as a standard network client, **gracefully cooperating with your home router's DHCP** without needing any configuration on the router itself.

---

### Adapter 2: Host-Only (`nic2` / `enp0s8`)
* **Type:** Host-Only Network (`VirtualBox Host-Only Ethernet Adapter`)
* **IP Assignment:** **Static IP** (`192.168.56.50/24`)
* **Purpose:** SSH connection, file sharing, and Ansible provisioning.

**How it works:**
The Host-Only network is a **completely virtual, private network** created inside your host PC by VirtualBox. 
* Traffic on this interface is entirely software-defined and **never leaves your physical PC**. It cannot go to your home router.
* VirtualBox sets up a virtual host network card on your PC (usually configured with IP `192.168.56.1`).
* Because the network is completely isolated from the local physical LAN, we can safely manually assign a static IP like `192.168.56.50` inside [network-config](../../environments/os/debian13/cloud-init/network-config) without risking IP conflicts or DHCP problems on the real router.

---

## Configuration Example (cloud-init / systemd-networkd)

The interfaces are mapped explicitly in `network-config`:

```yaml
version: 2
ethernets:
  nic1:
    match:
      name: enp0s3
    dhcp4: true       # NAT: dynamically gets internet-routing IP
  nic2:
    match:
      name: enp0s8
    dhcp4: false      # Host-Only: static IP for local host communication
    addresses:
      - 192.168.56.50/24
```
