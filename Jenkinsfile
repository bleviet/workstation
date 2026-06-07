pipeline {
    agent {
        node {
            label ''
            // Allocate a unique workspace folder for each build configuration
            customWorkspace "workspace/workstation-${params.OS}-${params.PROFILE}-${env.BUILD_NUMBER}"
        }
    }

    parameters {
        choice(name: 'OS', choices: ['debian13', 'ubuntu2404', 'ubuntu2604', 'alma9', 'alma10'], description: 'Select the OS variant')
        choice(name: 'PROFILE', choices: ['headless', 'desktop-gnome', 'desktop-xfce', 'desktop-i3wm'], description: 'Select the environment profile')
        choice(name: 'PROVIDER', choices: ['virtualbox', 'libvirt', 'vmware_desktop'], description: 'Select Vagrant provider')
        choice(name: 'RAM_MB', choices: ['4096', '8192', '16384', '32768'], description: 'Memory (RAM) in MB. FPGA development requires 32768.')
        choice(name: 'CPUS', choices: ['2', '4', '8', '16'], description: 'Number of logical CPUs.')
        choice(name: 'VRAM_MB', choices: ['128', '256'], description: 'Video RAM in MB.')
        booleanParam(name: 'ACCEL3D', defaultValue: false, description: 'Enable 3D hardware acceleration for the desktop?')
        booleanParam(name: 'USB_PASSTHROUGH', defaultValue: false, description: 'Enable USB xHCI/EHCI passthrough (Required for JTAG/FPGA boards)?')
        booleanParam(name: 'FPGA_DEV', defaultValue: false, description: 'Enable FPGA development tools?')
        booleanParam(name: 'XRDP', defaultValue: false, description: 'Enable remote desktop via xRDP?')
        booleanParam(name: 'DESTROY_AFTER_BUILD', defaultValue: true, description: 'Destroy the VM after provisioning? Uncheck to keep it running for manual usage.')
    }

    environment {
        // Suppress Vagrant color output in Jenkins
        VAGRANT_NO_COLOR = '1'
        VAGRANT_HOME = 'D:/.vagrant.d'
        
        // Pass parameters to Vagrantfile via environment variables
        JENKINS_PARAM_BUILD = 'true'
        JENKINS_OS = "${params.OS}"
        JENKINS_PROFILE = "${params.PROFILE}"
        JENKINS_PROVIDER = "${params.PROVIDER}"
        JENKINS_RAM_MB = "${params.RAM_MB}"
        JENKINS_CPUS = "${params.CPUS}"
        JENKINS_VRAM_MB = "${params.VRAM_MB}"
        JENKINS_ACCEL3D = "${params.ACCEL3D}"
        JENKINS_USB = "${params.USB_PASSTHROUGH}"
        JENKINS_FPGA = "${params.FPGA_DEV}"
        JENKINS_XRDP = "${params.XRDP}"
    }

    stages {
        stage('Syntax Check') {
            when {
                expression { isUnix() }
            }
            steps {
                sh 'ansible-playbook ansible/site.yml --syntax-check'
            }
        }

        stage('Provision VM') {
            steps {
                script {
                    echo "Provisioning ${params.OS} with ${params.PROFILE} using ${params.PROVIDER}..."
                    echo "FPGA Enabled: ${params.FPGA_DEV}"
                    echo "xRDP Enabled: ${params.XRDP}"
                    
                    if (isUnix()) {
                        sh "vagrant up jenkins-param-vm --provider=${params.PROVIDER}"
                    } else {
                        powershell "vagrant up jenkins-param-vm --provider=${params.PROVIDER}"
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                try {
                    // Test if we have a node context. If SCM checkout failed, this throws an exception.
                    def is_unix = isUnix()
                    
                    if (params.DESTROY_AFTER_BUILD) {
                        echo "Cleaning up: Destroying the temporary VM..."
                        if (is_unix) {
                            sh 'vagrant destroy jenkins-param-vm -f || true'
                        } else {
                            powershell 'vagrant destroy jenkins-param-vm -f || true'
                        }
                    } else {
                        echo "VM retention requested. The VM is still running."
                        echo "Connect using: vagrant ssh jenkins-param-vm"
                        echo "Ensure you destroy it manually later to free resources."
                    }
                } catch (org.jenkinsci.plugins.workflow.steps.MissingContextVariableException e) {
                    echo "Pipeline failed before a workspace was allocated. No VM to clean up."
                }
            }
        }
    }
}
