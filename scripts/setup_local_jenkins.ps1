# scripts/setup_local_jenkins.ps1
# Automates the setup of a standalone Jenkins server locally for Windows

param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$JenkinsWar = Join-Path $RootDir "jenkins.war"
$JenkinsHomeDir = Join-Path $RootDir "jenkins_home"
$JenkinsVersion = "2.555.2" # LTS version

Write-Host "=== Local Jenkins Setup ===" -ForegroundColor Cyan

$JavaBin = "C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin\java.exe"

if (-not (Test-Path $JavaBin)) {
    Write-Host "ERROR: Java is required but was not found at $JavaBin" -ForegroundColor Red
    exit 1
}

# Download Jenkins if not present
if (-not (Test-Path $JenkinsWar)) {
    Write-Host "Downloading Jenkins v${JenkinsVersion}..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://get.jenkins.io/war-stable/${JenkinsVersion}/jenkins.war" -OutFile $JenkinsWar
}

# Set up init scripts
Write-Host "Configuring Jenkins bootstrap scripts..." -ForegroundColor Yellow
$InitDir = Join-Path $JenkinsHomeDir "init.groovy.d"
if (-not (Test-Path $InitDir)) {
    New-Item -ItemType Directory -Path $InitDir | Out-Null
}
Copy-Item -Path (Join-Path $RootDir "scripts\jenkins\init.groovy.d\*.groovy") -Destination $InitDir -Force

# Start Jenkins
$env:JENKINS_HOME = $JenkinsHomeDir

Write-Host "Starting Jenkins..." -ForegroundColor Green
Write-Host "-> The web interface will be available at http://localhost:$Port" -ForegroundColor Cyan
Write-Host "-> Login with admin / admin" -ForegroundColor Cyan
Write-Host "-> The 'workstation-vm-builder' pipeline job will be created automatically!" -ForegroundColor Cyan
Write-Host "-> Press Ctrl+C to stop Jenkins." -ForegroundColor Yellow
Write-Host "===========================" -ForegroundColor Cyan

& $JavaBin "-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true" -jar $JenkinsWar --httpPort=$Port
