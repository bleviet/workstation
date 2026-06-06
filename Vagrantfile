require 'yaml'

Vagrant.configure("2") do |config|
  # Map custom OS names from your old build.py configs to standard Vagrant Cloud boxes
  os_box_map = {
    "debian13"   => "bento/debian-13", # bento for VBox/VMware, libvirt overrides to debian/trixie64
    "ubuntu2404" => "bento/ubuntu-24.04",
    "ubuntu2604" => "bento/ubuntu-26.04",
    "alma9"      => "almalinux/9",
    "alma10"     => "almalinux/10"
  }

  pre_provision_script = <<-SHELL
    export DEBIAN_FRONTEND=noninteractive

    # 1. Install Ansible if missing
    if ! command -v ansible-playbook &> /dev/null; then
      if [ -f /etc/debian_version ]; then
        apt-get update -qq
        apt-get install -y -qq ansible-core || apt-get install -y -qq ansible
      elif [ -f /etc/redhat-release ]; then
        dnf install -y epel-release
        dnf install -y ansible-core
      fi
    fi

    # 2. Fix Ubuntu boot delays and VirtualBox graphics
    if [ -f /etc/debian_version ]; then
      # Mask the network-wait service so it doesn't hang the boot for 2 minutes
      systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
      systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

      # Rebuild VirtualBox Guest Additions if they crashed against the bleeding-edge kernel
      if command -v systemctl &> /dev/null && systemctl is-failed --quiet vboxadd-service.service 2>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq dkms build-essential linux-headers-$(uname -r)
        if [ -f /sbin/rcvboxadd ]; then
          /sbin/rcvboxadd setup || true
          systemctl restart vboxadd-service.service || true
        fi
      fi
      
      # Force X11 instead of Wayland for GDM3 to fix slow VirtualBox 3D acceleration
      if [ -f /etc/gdm3/custom.conf ]; then
        sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
      fi
    fi
  SHELL

  # --- 0. Load Local Settings ---
  settings = {}
  settings_file = "environments/settings.yml"
  if File.exist?(settings_file)
    begin
      settings = YAML.load_file(settings_file) || {}
    rescue Exception => e
      puts "Failed to load #{settings_file}: #{e}"
    end
  end

  # Configure VMware Desktop cloning directory globally
  if settings["vmware_base_folder"]
    ENV['VAGRANT_VMWARE_CLONE_DIRECTORY'] = settings["vmware_base_folder"]
  end

  # Configure VirtualBox default machine folder globally
  if settings["vbox_base_folder"]
    # This invokes VBoxManage (if available) to set the global Default Machine Folder
    system("VBoxManage setproperty machinefolder \"#{settings['vbox_base_folder']}\" >nul 2>&1")
  end

  # --- 1. Load FPGA Environments ---
  Dir.glob("environments/fpga-*/vm.yml").each do |vm_yml_path|
    begin
      vm_data = YAML.load_file(vm_yml_path)
      config.vm.define vm_data["name"] do |node|
        node.vm.box = os_box_map[vm_data["os"]] || "ubuntu/noble64"
        node.vm.hostname = vm_data["hostname"] || vm_data["name"]

        node.vm.provider "virtualbox" do |vb|
          vb.name = vm_data["name"]
          vb.gui = vm_data["gui"] || true # Default to GUI for FPGA dev
          vb.memory = vm_data["ram_mb"] || 32768
          vb.cpus = vm_data["cpus"] || 8
          
          vb.customize ["modifyvm", :id, "--vram", (vm_data["vram_mb"] || 256).to_s]
          vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
          vb.customize ["modifyvm", :id, "--audio-driver", "none"]
          vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
          vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
          vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
          vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
          
          if vm_data["accel3d"]
            vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
          end
          if vm_data.dig("usb", "ehci")
            vb.customize ["modifyvm", :id, "--usbehci", "on"]
          end
          if vm_data.dig("usb", "xhci")
            vb.customize ["modifyvm", :id, "--usbxhci", "on"]
          end
        end

        node.vm.provider "vmware_desktop" do |v|
          v.gui = vm_data["gui"] || true
          v.vmx["memsize"] = (vm_data["ram_mb"] || 32768).to_s
          v.vmx["numvcpus"] = (vm_data["cpus"] || 8).to_s
          v.vmx["vhv.enable"] = "TRUE"
          v.vmx["mks.enable3d"] = vm_data["accel3d"] ? "TRUE" : "FALSE"
          v.vmx["svga.vramSize"] = ((vm_data["vram_mb"] || 256) * 1024 * 1024).to_s
          v.vmx["isolation.tools.copy.disable"] = "FALSE"
          v.vmx["isolation.tools.paste.disable"] = "FALSE"
          v.vmx["isolation.tools.dnd.disable"] = "FALSE"
          
          if vm_data.dig("usb", "xhci") || vm_data.dig("usb", "ehci")
            v.vmx["usb.present"] = "TRUE"
            if vm_data.dig("usb", "xhci")
              v.vmx["usb_xhci.present"] = "TRUE"
            end
          end
        end

        node.vm.provider "libvirt" do |libvirt, override|
          if vm_data["os"] == "debian13"
            override.vm.box = "debian/trixie64"
          end

          libvirt.memory = vm_data["ram_mb"] || 32768
          libvirt.cpus = vm_data["cpus"] || 8
          libvirt.nested = true
          
          if vm_data["gui"] || true
            libvirt.graphics_type = "spice"
            libvirt.video_type = "qxl"
            libvirt.video_vram = (vm_data["vram_mb"] || 256) * 1024
            if vm_data["accel3d"]
              libvirt.graphics_gl = true
            end
          else
            libvirt.graphics_type = "none"
          end

          if vm_data.dig("usb", "xhci")
             libvirt.usb_controller :model => "qemu-xhci"
          end
        end

        # Mount shared folders specified in vm.yml
        if vm_data["shared_folders"]
          vm_data["shared_folders"].each do |sf|
            host_path = File.expand_path(sf["host"], File.dirname(vm_yml_path))
            node.vm.synced_folder host_path, sf["guest"], create: sf["create"]
          end
        end

        # Pre-install Ansible natively to avoid Vagrant PPA bugs on new Ubuntu releases
        node.vm.provision "shell", inline: pre_provision_script

        # Run Ansible locally inside the VM (no WSL needed on the host!)
        node.vm.provision "ansible_local" do |ansible|
          ansible.install = false
          ansible.playbook = "provisioning/site.yml"
          ansible.inventory_path = "provisioning/inventory"
          ansible.limit = "localhost"
          ansible.extra_vars = { profile: vm_data["profile"] || "desktop-gnome" }
        end
      end
    rescue Exception => e
      puts "Failed to load #{vm_yml_path}: #{e}"
    end
  end

  # --- 2. Load Automated Test Machines ---
  machines_yml = "tests/vm/machines.yml"
  if File.exist?(machines_yml)
    begin
      test_data = YAML.load_file(machines_yml)
      (test_data["machines"] || []).each do |m|
        config.vm.define m["name"] do |node|
          node.vm.box = os_box_map[m["os"]] || "ubuntu/noble64"
          node.vm.hostname = m["name"]

          node.vm.provider "virtualbox" do |vb|
            vb.name = m["name"]
            vb.gui = m["gui"] || false
            vb.memory = m["ram_mb"] || 2048
            vb.cpus = m["cpus"] || 2
            
            vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
            vb.customize ["modifyvm", :id, "--audio-driver", "none"]
            vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
            vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
            vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
            vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
          end

          node.vm.provider "vmware_desktop" do |v|
            v.gui = m["gui"] || false
            v.vmx["memsize"] = (m["ram_mb"] || 2048).to_s
            v.vmx["numvcpus"] = (m["cpus"] || 2).to_s
            v.vmx["vhv.enable"] = "TRUE"
            v.vmx["isolation.tools.copy.disable"] = "FALSE"
            v.vmx["isolation.tools.paste.disable"] = "FALSE"
            v.vmx["isolation.tools.dnd.disable"] = "FALSE"
          end

          node.vm.provider "libvirt" do |libvirt, override|
            if m["os"] == "debian13"
              override.vm.box = "debian/trixie64"
            end

            libvirt.memory = m["ram_mb"] || 2048
            libvirt.cpus = m["cpus"] || 2
            libvirt.nested = true
            
            if m["gui"]
              libvirt.graphics_type = "spice"
              libvirt.video_type = "qxl"
            else
              libvirt.graphics_type = "none"
            end
          end

          # For testing VMs, map the entire repository workspace
          node.vm.synced_folder ".", "/home/vagrant/workspace/workstation"

          node.vm.provision "shell", inline: pre_provision_script

          node.vm.provision "ansible_local" do |ansible|
            ansible.install = false
            ansible.playbook = "provisioning/site.yml"
            ansible.inventory_path = "provisioning/inventory"
            ansible.limit = "localhost"
            ansible.extra_vars = { profile: m["profile"] || "headless" }
          end
        end
      end
    rescue Exception => e
      puts "Failed to load #{machines_yml}: #{e}"
    end
  end

  # --- 3. Load Parameterized Jenkins VM ---
  if ENV['JENKINS_PARAM_BUILD'] == 'true'
    config.vm.define "jenkins-param-vm" do |node|
      node.vm.box = os_box_map[ENV['JENKINS_OS']] || "ubuntu/noble64"
      vm_name = "workstation-#{ENV['JENKINS_OS']}-#{ENV['JENKINS_PROFILE']}-#{ENV['BUILD_NUMBER']}"
      node.vm.hostname = "workstation-#{ENV['BUILD_NUMBER']}"

      gui_enabled = ENV['JENKINS_PROFILE'] != 'headless'
      
      # Parse hardware specifications or fallback to safe defaults
      vm_ram = (ENV['JENKINS_RAM_MB'] || 4096).to_i
      vm_cpus = (ENV['JENKINS_CPUS'] || 2).to_i
      vm_vram = (ENV['JENKINS_VRAM_MB'] || 128).to_i
      vm_accel3d = ENV['JENKINS_ACCEL3D'] == 'true'
      vm_usb = ENV['JENKINS_USB'] == 'true'

      node.vm.provider "virtualbox" do |vb|
        vb.name = vm_name
        vb.gui = gui_enabled
        vb.memory = vm_ram
        vb.cpus = vm_cpus
        
        vb.customize ["modifyvm", :id, "--vram", vm_vram.to_s]
        vb.customize ["modifyvm", :id, "--graphicscontroller", "vboxsvga"]
        vb.customize ["modifyvm", :id, "--audio-driver", "none"]
        vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
        vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
        vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
        vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
        
        if vm_accel3d
          vb.customize ["modifyvm", :id, "--accelerate3d", "off"]
        end
        if vm_usb
          vb.customize ["modifyvm", :id, "--usbehci", "on"]
          vb.customize ["modifyvm", :id, "--usbxhci", "on"]
        end
      end

      node.vm.provider "vmware_desktop" do |v|
        v.gui = gui_enabled
        v.vmx["memsize"] = vm_ram.to_s
        v.vmx["numvcpus"] = vm_cpus.to_s
        v.vmx["vhv.enable"] = "TRUE"
        v.vmx["mks.enable3d"] = vm_accel3d ? "TRUE" : "FALSE"
        v.vmx["svga.vramSize"] = (vm_vram * 1024 * 1024).to_s
        v.vmx["isolation.tools.copy.disable"] = "FALSE"
        v.vmx["isolation.tools.paste.disable"] = "FALSE"
        v.vmx["isolation.tools.dnd.disable"] = "FALSE"
        
        if vm_usb
          v.vmx["usb.present"] = "TRUE"
          v.vmx["usb_xhci.present"] = "TRUE"
        end
      end

      node.vm.provider "libvirt" do |libvirt, override|
        if ENV['JENKINS_OS'] == "debian13"
          override.vm.box = "debian/trixie64"
        end

        libvirt.memory = vm_ram
        libvirt.cpus = vm_cpus
        libvirt.nested = true
        
        if gui_enabled
          libvirt.graphics_type = "spice"
          libvirt.video_type = "qxl"
          libvirt.video_vram = vm_vram * 1024
          if vm_accel3d
            libvirt.graphics_gl = true
          end
        else
          libvirt.graphics_type = "none"
        end
        
        if vm_usb
           libvirt.usb_controller :model => "qemu-xhci"
        end
      end

      node.vm.provision "shell", inline: pre_provision_script

      node.vm.provision "ansible_local" do |ansible|
        ansible.install = false
        ansible.playbook = "provisioning/site.yml"
        ansible.inventory_path = "provisioning/inventory"
        ansible.limit = "localhost"
        
        features = {}
        features["fpga"] = { "enabled" => true } if ENV['JENKINS_FPGA'] == 'true'
        features["xrdp"] = true if ENV['JENKINS_XRDP'] == 'true'

        extra_vars = { 
          "profile" => ENV['JENKINS_PROFILE'] || "headless"
        }
        extra_vars["features"] = features unless features.empty?
        
        ansible.extra_vars = extra_vars
      end
    end
  end
end
