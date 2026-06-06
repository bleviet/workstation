#!/bin/bash
# scripts/setup_local_jenkins.sh
# Automates the setup of a standalone Jenkins server locally for Linux

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JENKINS_WAR="${ROOT_DIR}/jenkins.war"
JENKINS_HOME_DIR="${ROOT_DIR}/jenkins_home"
JENKINS_VERSION="2.462.1" # LTS version, or use latest

echo "=== Local Jenkins Setup ==="

# Check Java
if ! command -v java >/dev/null 2>&1; then
    echo "ERROR: Java is required. Please install OpenJDK 17 or 21."
    exit 1
fi

# Download Jenkins if not present
if [ ! -f "$JENKINS_WAR" ]; then
    echo "Downloading Jenkins v${JENKINS_VERSION}..."
    curl -L -o "$JENKINS_WAR" "https://get.jenkins.io/war-stable/${JENKINS_VERSION}/jenkins.war"
fi

# Set up init scripts
echo "Configuring Jenkins bootstrap scripts..."
mkdir -p "${JENKINS_HOME_DIR}/init.groovy.d"
cp "${ROOT_DIR}/scripts/jenkins/init.groovy.d/"*.groovy "${JENKINS_HOME_DIR}/init.groovy.d/"

# Start Jenkins
export JENKINS_HOME="$JENKINS_HOME_DIR"
echo "Starting Jenkins..."
echo "-> The web interface will be available at http://localhost:8080"
echo "-> Login with admin / admin"
echo "-> The 'workstation-vm-builder' pipeline job will be created automatically!"
echo "-> Press Ctrl+C to stop Jenkins."
echo "==========================="

java -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true -jar "$JENKINS_WAR" --httpPort=8080
