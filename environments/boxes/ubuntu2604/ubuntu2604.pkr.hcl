packer {
  required_plugins {
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
    vagrant = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "ubuntu_version" {
  default     = "26.04"
  description = "Ubuntu 26.04 point release to download (e.g. 26.04 or 26.04.1)."
}

variable "disk_size_mb" {
  default     = 20480
  description = "Base disk size in MB. Vagrant expands to 512 GB on first boot."
}

variable "memory_mb" {
  default     = 2048
  description = "RAM for the build VM."
}

variable "cpus" {
  default     = 4
  description = "CPUs for the build VM."
}

# ---------------------------------------------------------------------------
# Source
# ---------------------------------------------------------------------------

source "vmware-iso" "ubuntu2604" {
  vm_name       = "ubuntu2604-vagrant-build"
  guest_os_type = "ubuntu-64"

  iso_url      = "https://releases.ubuntu.com/26.04/ubuntu-${var.ubuntu_version}-live-server-amd64.iso"
  # SHA256SUMS is standard GNU format — Packer resolves the correct hash by filename.
  iso_checksum = "file:https://releases.ubuntu.com/26.04/SHA256SUMS"

  memory    = var.memory_mb
  cpus      = var.cpus
  disk_size = var.disk_size_mb

  network        = "nat"
  http_directory = "${path.root}/http"
  headless       = false

  # Wait for GRUB menu, press 'e' to edit the default entry, navigate to the
  # end of the linux line, append autoinstall params, then boot with Ctrl+x.
  # Using the edit approach rather than the 'c' command line is more reliable
  # across GRUB versions — the command line resets casper state on some ISOs.
  boot_wait    = "12s"
  boot_command = [
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/",
    "<wait><leftCtrlOn>x<leftCtrlOff>"
  ]

  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout  = "60m"

  shutdown_command = "echo 'vagrant' | sudo -S shutdown -P now"

  vmx_data = {
    "tools.syncTime" = "TRUE"
  }

  output_directory = "${path.root}/output"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  sources = ["source.vmware-iso.ubuntu2604"]

  # Post-install: vagrant user, sudo, SSH key, open-vm-tools.
  provisioner "shell" {
    script          = "${path.root}/scripts/setup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  # Minimize box size: clean apt caches, zero free space.
  provisioner "shell" {
    script          = "${path.root}/scripts/cleanup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  # Package as a Vagrant box in the boxes/ubuntu2604/ directory.
  post-processor "vagrant" {
    output              = "${path.root}/ubuntu2604.box"
    provider_override   = "vmware"
    keep_input_artifact = false
  }
}
