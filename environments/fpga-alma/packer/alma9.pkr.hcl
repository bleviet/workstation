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

variable "alma_version" {
  default     = "9.8"
  description = "AlmaLinux minor release to download (matches the ISO filename)."
}

variable "iso_checksum" {
  default     = "sha256:7762a4b45a66235726db145a573658964bf77bf7b9bc1c018afe86a4cf37cc2e"
  description = "SHA-256 of AlmaLinux-<version>-x86_64-minimal.iso. Verify from https://repo.almalinux.org/almalinux/9/isos/x86_64/CHECKSUM"
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

source "vmware-iso" "alma9" {
  vm_name       = "alma9-vagrant-build"
  guest_os_type = "rhel9-64"

  iso_url      = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-${var.alma_version}-x86_64-minimal.iso"
  iso_checksum = var.iso_checksum

  memory    = var.memory_mb
  cpus      = var.cpus
  disk_size = var.disk_size_mb

  network        = "nat"
  http_directory = "${path.root}/http"
  headless       = false

  # Wait for isolinux menu, press Tab to edit the boot command, append kickstart URL.
  boot_wait    = "15s"
  boot_command = [
    "<tab><wait>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<enter>"
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
  sources = ["source.vmware-iso.alma9"]

  # Post-install: vagrant user, sudo, SSH key, open-vm-tools.
  provisioner "shell" {
    script          = "${path.root}/scripts/setup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  # Minimize box size: clean dnf caches, zero free space.
  provisioner "shell" {
    script          = "${path.root}/scripts/cleanup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  # Package as a Vagrant box in the environment root.
  post-processor "vagrant" {
    output              = "${path.root}/../alma9.box"
    provider_override   = "vmware"
    keep_input_artifact = false
  }
}
