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
          vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
          vb.customize ["modifyvm", :id, "--audio-driver", "none"]
          vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
          vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
          
          if vm_data["accel3d"]
            vb.customize ["modifyvm", :id, "--accelerate3d", "on"]
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

        # Run Ansible locally inside the VM (no WSL needed on the host!)
        node.vm.provision "ansible_local" do |ansible|
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
            
            vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
            vb.customize ["modifyvm", :id, "--audio-driver", "none"]
            vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
            vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
          end

          node.vm.provider "vmware_desktop" do |v|
            v.gui = m["gui"] || false
            v.vmx["memsize"] = (m["ram_mb"] || 2048).to_s
            v.vmx["numvcpus"] = (m["cpus"] || 2).to_s
            v.vmx["vhv.enable"] = "TRUE"
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

          node.vm.provision "ansible_local" do |ansible|
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
      node.vm.hostname = "jenkins-param-vm"

      gui_enabled = ENV['JENKINS_PROFILE'] != 'headless'

      node.vm.provider "virtualbox" do |vb|
        vb.name = ENV['BUILD_TAG'] || "jenkins-param-vm"
        vb.gui = gui_enabled
        vb.memory = 4096
        vb.cpus = 2
        
        vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
        vb.customize ["modifyvm", :id, "--audio-driver", "none"]
        vb.customize ["modifyvm", :id, "--rtcuseutc", "on"]
        vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
      end

      node.vm.provider "vmware_desktop" do |v|
        v.gui = gui_enabled
        v.vmx["memsize"] = "4096"
        v.vmx["numvcpus"] = "2"
        v.vmx["vhv.enable"] = "TRUE"
      end

      node.vm.provider "libvirt" do |libvirt, override|
        if ENV['JENKINS_OS'] == "debian13"
          override.vm.box = "debian/trixie64"
        end

        libvirt.memory = 4096
        libvirt.cpus = 2
        libvirt.nested = true
        
        if gui_enabled
          libvirt.graphics_type = "spice"
          libvirt.video_type = "qxl"
        else
          libvirt.graphics_type = "none"
        end
      end

      node.vm.provision "ansible_local" do |ansible|
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
