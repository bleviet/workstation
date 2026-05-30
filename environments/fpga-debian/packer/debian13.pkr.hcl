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

variable "debian_version" {
  default     = "13.5.0"
  description = "Debian release to download (matches the ISO filename)."
}

variable "iso_checksum" {
  default     = "sha256:95838884f5ea6c82421dfe6baaa5a639dbbe6756c1e380f9fe7a7cb0c1949d2a"
  description = "SHA-256 of debian-<version>-amd64-netinst.iso."
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

source "vmware-iso" "debian13" {
  vm_name       = "debian13-vagrant-build"
  guest_os_type = "debian12-64"   # VMware does not have a Debian 13 type yet

  iso_url      = "https://cdimage.debian.org/debian-cd/${var.debian_version}/amd64/iso-cd/debian-${var.debian_version}-amd64-netinst.iso"
  iso_checksum = var.iso_checksum

  memory    = var.memory_mb
  cpus      = var.cpus
  disk_size = var.disk_size_mb

  network        = "nat"
  http_directory = "${path.root}/http"
  headless       = false   # show VMware console during build

  # Wait for isolinux menu, then drop to boot prompt and inject preseed URL.
  boot_wait    = "5s"
  boot_command = [
    "<esc><wait>",
    "auto priority=critical ",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "net.ifnames=0 biosdevname=0<enter>"
  ]

  ssh_username = "vagrant"
  ssh_password = "vagrant"
  ssh_timeout  = "60m"

  shutdown_command = "echo 'vagrant' | sudo -S shutdown -P now"

  vmx_data = {
    "ethernet0.virtualDev" = "vmxnet3"
    "tools.syncTime"       = "TRUE"
  }

  output_directory = "${path.root}/output"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  sources = ["source.vmware-iso.debian13"]

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

  # Package as a Vagrant box in the environment root.
  post-processor "vagrant" {
    output              = "${path.root}/../debian13.box"
    provider_override   = "vmware_desktop"
    keep_input_artifact = false
  }
}
