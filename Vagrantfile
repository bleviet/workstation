require 'yaml'

Vagrant.configure("2") do |config|
  # Map custom OS names from your old build.py configs to standard Vagrant Cloud boxes
  os_box_map = {
    "debian13"   => "debian/bookworm64", # Fallback until debian13 (trixie) box exists
    "ubuntu2404" => "ubuntu/noble64",
    "ubuntu2604" => "alvistack/ubuntu-26.04",
    "alma9"      => "almalinux/9",
    "alma10"     => "almalinux/10"
  }

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
          ansible.limit = "all"
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

          # For testing VMs, map the entire repository workspace
          node.vm.synced_folder ".", "/home/vagrant/workspace/workstation"

          node.vm.provision "ansible_local" do |ansible|
            ansible.playbook = "provisioning/site.yml"
            ansible.inventory_path = "provisioning/inventory"
            ansible.limit = "all"
            ansible.extra_vars = { profile: m["profile"] || "headless" }
          end
        end
      end
    rescue Exception => e
      puts "Failed to load #{machines_yml}: #{e}"
    end
  end
end
