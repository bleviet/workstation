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

variable "vmx_path" {
  default     = ""
  description = "Absolute path to the prepared VMX file. Set by build.py via -var before calling packer build."
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

# No boot_command: the cloud image boots directly into a running OS.
# cloud-init reads the seed ISO (label=cidata) on first boot to create the
# vagrant user and enable SSH password auth, then Packer SSHes in.
source "vmware-vmx" "ubuntu2604" {
  source_path = var.vmx_path
  vm_name     = "ubuntu2604-vagrant-build"

  headless = false

  vmx_data = {
    "memsize"        = tostring(var.memory_mb)
    "numvcpus"       = tostring(var.cpus)
    "tools.syncTime" = "TRUE"
  }

  ssh_username = "vagrant"
  ssh_password = "vagrant"
  # ubuntu-desktop-minimal is ~800 MB; allow time for apt to finish.
  ssh_timeout  = "60m"

  shutdown_command = "echo 'vagrant' | sudo -S shutdown -P now"

  output_directory = "${path.root}/output"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  sources = ["source.vmware-vmx.ubuntu2604"]

  # Install packages absent from the server cloud base image.
  # ubuntu-desktop-minimal pulls in GNOME; this is the slow step (~30 min).
  provisioner "shell" {
    execute_command = "echo 'vagrant' | sudo -S bash -c '{{ .Vars }} bash {{ .Path }}'"
    inline = [
      "apt-get update -q",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y open-vm-tools curl ubuntu-desktop-minimal",
    ]
  }

  # vagrant user, passwordless sudo, insecure SSH key, VMware tools.
  provisioner "shell" {
    script          = "${path.root}/scripts/setup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  # Minimize box size: clean apt caches, zero free space.
  provisioner "shell" {
    script          = "${path.root}/scripts/cleanup.sh"
    execute_command = "echo 'vagrant' | sudo -S bash '{{ .Path }}'"
  }

  post-processor "vagrant" {
    output              = "${path.root}/ubuntu2604.box"
    provider_override   = "vmware"
    keep_input_artifact = false
  }
}
