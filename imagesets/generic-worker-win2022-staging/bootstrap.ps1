$TASKCLUSTER_REF = "main"

# use TLS 1.2 (see bug 1443595)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

md "C:\Install Logs"

# capture env
Get-ChildItem Env: | Out-File "C:\Install Logs\env.txt"

# needed for making http requests
$client = New-Object system.net.WebClient
$shell = new-object -com shell.application

# utility function to download a zip file and extract it
function Expand-ZIPFile($file, $destination, $url)
{
    $client.DownloadFile($url, $file)
    $zip = $shell.NameSpace($file)
    foreach($item in $zip.items())
    {
        $shell.Namespace($destination).copyhere($item)
    }
}

# allow powershell scripts to run
Set-ExecutionPolicy Unrestricted -Force -Scope Process

# Issue 681: Uninstall Windows Defender as it can interfere with tasks,
# degrade their performance, and e.g. prevents Generic Worker unit test
# TestAbortAfterMaxRunTime from running as intended.
Uninstall-WindowsFeature -Name Windows-Defender

# Services to disable
# taken (and edited) from GitHub Actions Windows runners
# https://github.com/actions/runner-images/blob/3b976c7acb0ce875060102c0c80f655b479aa5d4/images/windows/scripts/build/Configure-System.ps1#L140-L153
$servicesToDisable = @(
    'wuauserv' # Windows Update
    'usosvc' # update orchestrator
    'DiagTrack' # telemetry service
    'SysMain' # (Superfetch)
    'WSearch' # disk indexing
) | Get-Service -ErrorAction SilentlyContinue
Stop-Service $servicesToDisable
$servicesToDisable.WaitForStatus('Stopped', "00:01:00")
$servicesToDisable | Set-Service -StartupType Disabled

# skip OOBE (out of box experience)
@(
    "HideEULAPage",
    "HideLocalAccountScreen",
    "HideOEMRegistrationScreen",
    "HideOnlineAccountScreens",
    "HideWirelessSetupInOOBE",
    "NetworkLocation",
    "OEMAppId",
    "ProtectYourPC",
    "SkipMachineOOBE",
    "SkipUserOOBE"
) | ForEach-Object {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" -Name $psitem -Value 1
}

# install chocolatey package manager
Invoke-Expression ($client.DownloadString('https://chocolatey.org/install.ps1'))

# install nssm
Expand-ZIPFile -File "C:\nssm-2.24.zip" -Destination "C:\" -Url "http://www.nssm.cc/release/nssm-2.24.zip"

# configure hosts file for taskcluster-proxy access via http://taskcluster
$HostsFile_Base64 = "IyBDb3B5cmlnaHQgKGMpIDE5OTMtMjAwOSBNaWNyb3NvZnQgQ29ycC4NCiMNCiMgVGhpcyBpcyBhIHNhbXBsZSBIT1NUUyBmaWxlIHVzZWQgYnkgTWljcm9zb2Z0IFRDUC9JUCBmb3IgV2luZG93cy4NCiMNCiMgVGhpcyBmaWxlIGNvbnRhaW5zIHRoZSBtYXBwaW5ncyBvZiBJUCBhZGRyZXNzZXMgdG8gaG9zdCBuYW1lcy4gRWFjaA0KIyBlbnRyeSBzaG91bGQgYmUga2VwdCBvbiBhbiBpbmRpdmlkdWFsIGxpbmUuIFRoZSBJUCBhZGRyZXNzIHNob3VsZA0KIyBiZSBwbGFjZWQgaW4gdGhlIGZpcnN0IGNvbHVtbiBmb2xsb3dlZCBieSB0aGUgY29ycmVzcG9uZGluZyBob3N0IG5hbWUuDQojIFRoZSBJUCBhZGRyZXNzIGFuZCB0aGUgaG9zdCBuYW1lIHNob3VsZCBiZSBzZXBhcmF0ZWQgYnkgYXQgbGVhc3Qgb25lDQojIHNwYWNlLg0KIw0KIyBBZGRpdGlvbmFsbHksIGNvbW1lbnRzIChzdWNoIGFzIHRoZXNlKSBtYXkgYmUgaW5zZXJ0ZWQgb24gaW5kaXZpZHVhbA0KIyBsaW5lcyBvciBmb2xsb3dpbmcgdGhlIG1hY2hpbmUgbmFtZSBkZW5vdGVkIGJ5IGEgJyMnIHN5bWJvbC4NCiMNCiMgRm9yIGV4YW1wbGU6DQojDQojICAgICAgMTAyLjU0Ljk0Ljk3ICAgICByaGluby5hY21lLmNvbSAgICAgICAgICAjIHNvdXJjZSBzZXJ2ZXINCiMgICAgICAgMzguMjUuNjMuMTAgICAgIHguYWNtZS5jb20gICAgICAgICAgICAgICMgeCBjbGllbnQgaG9zdA0KDQojIGxvY2FsaG9zdCBuYW1lIHJlc29sdXRpb24gaXMgaGFuZGxlZCB3aXRoaW4gRE5TIGl0c2VsZi4NCiMJMTI3LjAuMC4xICAgICAgIGxvY2FsaG9zdA0KIwk6OjEgICAgICAgICAgICAgbG9jYWxob3N0DQoNCiMgVXNlZnVsIGZvciBnZW5lcmljLXdvcmtlciB0YXNrY2x1c3Rlci1wcm94eSBpbnRlZ3JhdGlvbg0KIyBTZWUgaHR0cHM6Ly9idWd6aWxsYS5tb3ppbGxhLm9yZy9zaG93X2J1Zy5jZ2k/aWQ9MTQ0OTk4MSNjNg0KMTI3LjAuMC4xICAgICAgICB0YXNrY2x1c3RlciAgICANCg=="
$HostsFile_Content = [System.Convert]::FromBase64String($HostsFile_Base64)
Set-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value $HostsFile_Content -Encoding Byte

# download gvim
$client.DownloadFile("http://artfiles.org/vim.org/pc/gvim80-069.exe", "C:\gvim80-069.exe")

# open up firewall for livelog (both PUT and GET interfaces)
New-NetFirewallRule -DisplayName "Allow livelog PUT requests" -Direction Inbound -LocalPort 60022 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow livelog GET requests" -Direction Inbound -LocalPort 60023 -Protocol TCP -Action Allow

# install go
Expand-ZIPFile -File "C:\go1.23.1.windows-amd64.zip" -Destination "C:\" -Url "https://storage.googleapis.com/golang/go1.23.1.windows-amd64.zip"

# install git
$client.DownloadFile("https://github.com/git-for-windows/git/releases/download/v2.46.2.windows.1/Git-2.46.2-64-bit.exe", "C:\Git-2.46.2-64-bit.exe")
& "C:\Git-2.46.2-64-bit.exe" /VERYSILENT /LOG="C:\Install Logs\git.txt" /NORESTART /SUPPRESSMSGBOXES

# install node
$client.DownloadFile("https://nodejs.org/dist/v20.17.0/node-v20.17.0-x64.msi", "C:\NodeSetup.msi")
msiexec /i C:\NodeSetup.msi /quiet

# install python 3.11.9
$client.DownloadFile("https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe", "C:\python-3.11.9-amd64.exe")
# issue 751: without /log <file> python fails to install on Azure workers, with exit code 1622, maybe default log location isn't writable(?)
& "C:\python-3.11.9-amd64.exe" /quiet InstallAllUsers=1 /log "C:\Install Logs\python-3.11.9.txt"

# set permanent env vars
[Environment]::SetEnvironmentVariable("GOROOT", "C:\goroot", "Machine")
[Environment]::SetEnvironmentVariable("PATH", [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";C:\Program Files\Vim\vim80;C:\goroot\bin;C:\Program Files\Python311", "Machine")
[Environment]::SetEnvironmentVariable("PATHEXT", [Environment]::GetEnvironmentVariable("PATHEXT", "Machine") + ";.PY", "Machine")

# set env vars for the currently running process
$env:GOROOT  = "C:\goroot"
$env:PATH    = $env:PATH + ";C:\goroot\bin\C:\Program Files\Git\cmd;C:\Program Files\Python311"
$env:PATHEXT = $env:PATHEXT + ";.PY"

md "C:\generic-worker"
md "C:\worker-runner"

# build generic-worker/livelog/start-worker/taskcluster-proxy from ${TASKCLUSTER_REF} commit / branch / tag etc
git clone https://github.com/taskcluster/taskcluster
Set-Location taskcluster
git checkout ${TASKCLUSTER_REF}
$revision = & git rev-parse HEAD
$env:CGO_ENABLED = "0"
go build -tags multiuser -o "C:\generic-worker\generic-worker.exe" -ldflags "-X main.revision=$revision" .\workers\generic-worker
go build -o "C:\generic-worker\livelog.exe" .\tools\livelog
go build -o "C:\generic-worker\taskcluster-proxy.exe" -ldflags "-X main.revision=$revision" .\tools\taskcluster-proxy
go build -o "C:\worker-runner\start-worker.exe" -ldflags "-X main.revision=$revision" .\tools\worker-runner\cmd\start-worker
& "C:\generic-worker\generic-worker.exe" --version
& "C:\generic-worker\generic-worker.exe" new-ed25519-keypair --file "C:\generic-worker\generic-worker-ed25519-signing-key.key"

# install generic-worker, using the steps suggested in https://docs.taskcluster.net/docs/reference/workers/worker-runner/deployment#recommended-setup
Set-Content -Path C:\generic-worker\install.bat @"
set nssm=C:\nssm-2.24\win64\nssm.exe
%nssm% install "Generic Worker" C:\generic-worker\generic-worker.exe
%nssm% set "Generic Worker" AppDirectory C:\generic-worker
%nssm% set "Generic Worker" AppParameters run --config C:\generic-worker\generic-worker-config.yml --worker-runner-protocol-pipe \\.\pipe\generic-worker
%nssm% set "Generic Worker" DisplayName "Generic Worker"
%nssm% set "Generic Worker" Description "A taskcluster worker that runs on all mainstream platforms"
%nssm% set "Generic Worker" Start SERVICE_DEMAND_START
%nssm% set "Generic Worker" Type SERVICE_WIN32_OWN_PROCESS
%nssm% set "Generic Worker" AppNoConsole 1
%nssm% set "Generic Worker" AppAffinity All
%nssm% set "Generic Worker" AppStopMethodSkip 0
%nssm% set "Generic Worker" AppExit Default Exit
%nssm% set "Generic Worker" AppRestartDelay 0
%nssm% set "Generic Worker" AppStdout C:\generic-worker\generic-worker-service.log
%nssm% set "Generic Worker" AppStderr C:\generic-worker\generic-worker-service.log
%nssm% set "Generic Worker" AppRotateFiles 0
"@
& "C:\generic-worker\install.bat"

# install worker-runner
Set-Content -Path C:\worker-runner\install.bat @"
set nssm=C:\nssm-2.24\win64\nssm.exe
%nssm% install worker-runner C:\worker-runner\start-worker.exe
%nssm% set worker-runner AppDirectory C:\worker-runner
%nssm% set worker-runner AppParameters C:\worker-runner\runner.yml
%nssm% set worker-runner DisplayName "Worker Runner"
%nssm% set worker-runner Description "Interface between workers and Taskcluster services"
%nssm% set worker-runner Start SERVICE_AUTO_START
%nssm% set worker-runner Type SERVICE_WIN32_OWN_PROCESS
%nssm% set worker-runner AppNoConsole 1
%nssm% set worker-runner AppAffinity All
%nssm% set worker-runner AppStopMethodSkip 0
%nssm% set worker-runner AppExit Default Exit
%nssm% set worker-runner AppRestartDelay 0
%nssm% set worker-runner AppStdout C:\worker-runner\worker-runner-service.log
%nssm% set worker-runner AppStderr C:\worker-runner\worker-runner-service.log
%nssm% set worker-runner AppRotateFiles 1
%nssm% set worker-runner AppRotateOnline 1
%nssm% set worker-runner AppRotateSeconds 3600
%nssm% set worker-runner AppRotateBytes 0
"@
& "C:\worker-runner\install.bat"

# configure worker-runner
Set-Content -Path C:\worker-runner\runner.yml @"
provider:
    providerType: %MY_CLOUD%
worker:
  implementation: generic-worker
  service: "Generic Worker"
  configPath: C:\generic-worker\generic-worker-config.yml
  protocolPipe: \\.\pipe\generic-worker
cacheOverRestarts: C:\generic-worker\start-worker-cache.json
"@

# get generic-worker and livelog source code (not required, but useful)
go get -t github.com/taskcluster/generic-worker github.com/taskcluster/livelog

# download cygwin (not required, but useful)
$client.DownloadFile("https://www.cygwin.com/setup-x86_64.exe", "C:\cygwin-setup-x86_64.exe")

# install cygwin
# complete package list: https://cygwin.com/packages/package_list.html
& "C:\cygwin-setup-x86_64.exe" --quiet-mode --wait --root C:\cygwin --site http://cygwin.mirror.constant.com --packages openssh,vim,curl,tar,wget,zip,unzip,diffutils,bzr

# open up firewall for ssh daemon
New-NetFirewallRule -DisplayName "Allow SSH inbound" -Direction Inbound -LocalPort 22 -Protocol TCP -Action Allow

# workaround for https://www.cygwin.com/ml/cygwin/2015-10/msg00036.html
# see:
#   1) https://www.cygwin.com/ml/cygwin/2015-10/msg00038.html
#   2) https://cygwin.com/git/gitweb.cgi?p=cygwin-csih.git;a=blob;f=cygwin-service-installation-helper.sh;h=10ab4fb6d47803c9ffabdde51923fc2c3f0496bb;hb=7ca191bebb52ae414bb2a2e37ef22d94f2658dc7#l2884
$env:LOGONSERVER = "\\" + $env:COMPUTERNAME

# configure sshd (not required, but useful)
# use Start-Process for now as not sure how to escape arguments using & notation
Start-Process "C:\cygwin\bin\bash.exe" -ArgumentList "--login -c `"ssh-host-config -y -c 'ntsec mintty' -u 'cygwinsshd' -w 'qwe123QWE!@#'`"" -Wait -NoNewWindow

# start sshd
net start cygsshd

# download bash setup script
$client.DownloadFile("https://raw.githubusercontent.com/petemoore/myscrapbook/master/setup.sh", "C:\cygwin\home\Administrator\setup.sh")

# run bash setup script
& "C:\cygwin\bin\bash.exe" --login -c 'chmod a+x setup.sh; ./setup.sh'

# install dependencywalker (useful utility for troubleshooting, not required)
md "C:\DependencyWalker"
Expand-ZIPFile -File "C:\depends22_x64.zip" -Destination "C:\DependencyWalker" -Url "http://dependencywalker.com/depends22_x64.zip"

# install ProcessExplorer (useful utility for troubleshooting, not required)
md "C:\ProcessExplorer"
Expand-ZIPFile -File "C:\ProcessExplorer.zip" -Destination "C:\ProcessExplorer" -Url "https://download.sysinternals.com/files/ProcessExplorer.zip"

# install ProcessMonitor (useful utility for troubleshooting, not required)
md "C:\ProcessMonitor"
Expand-ZIPFile -File "C:\ProcessMonitor.zip" -Destination "C:\ProcessMonitor" -Url "https://download.sysinternals.com/files/ProcessMonitor.zip"

# install Windows 10 SDK
choco install -y windows-sdk-10.0

# install VisualStudio 2019 Community
choco install -y visualstudio2019community --version 16.5.4.0 --package-parameters "--add Microsoft.VisualStudio.Workload.MSBuildTools;Microsoft.VisualStudio.Component.VC.160 --passive --locale en-US"
choco install -y visualstudio2019buildtools --version 16.5.4.0 --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools;includeRecommended --add Microsoft.VisualStudio.Component.VC.160 --add Microsoft.VisualStudio.Component.NuGet.BuildTools --add Microsoft.VisualStudio.Workload.UniversalBuildTools;includeRecommended --add Microsoft.VisualStudio.Workload.NetCoreBuildTools;includeRecommended --add Microsoft.Net.Component.4.5.TargetingPack --add Microsoft.Net.Component.4.6.TargetingPack --add Microsoft.Net.Component.4.7.TargetingPack --passive --locale en-US"

# install gcc for go race detector
choco install -y mingw --version 11.2.0.07112021

# Check if any of the video controllers are from NVIDIA
# Note, 0x10DE is the NVIDIA Corporation Vendor ID
$hasNvidiaGpu = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match "^PCI\\VEN_10DE" }

if ($hasNvidiaGpu) {
  $client.DownloadFile("https://download.microsoft.com/download/a/3/1/a3186ac9-1f9f-4351-a8e7-b5b34ea4e4ea/538.46_grid_win10_win11_server2019_server2022_dch_64bit_international_azure_swl.exe", "C:\nvidia_driver.exe")
  & "C:\nvidia_driver.exe" -s -noreboot *> "C:\Install Logs\nvidia.txt"
  # Need to fix this CUDA installation in staging...
  # Removing from here for now...
  # https://github.com/taskcluster/community-tc-config/issues/713
  # $client.DownloadFile("https://developer.download.nvidia.com/compute/cuda/12.6.1/local_installers/cuda_12.6.1_560.94_windows.exe", "C:\cuda_installer.exe")
  # & "C:\cuda_installer.exe" -s -noreboot *> "C:\Install Logs\cuda.txt"

}

# now shutdown, in preparation for creating an image
# Stop-Computer isn't working, also not when specifying -AsJob, so reverting to using `shutdown` command instead
#   * https://www.reddit.com/r/PowerShell/comments/65250s/windows_10_creators_update_stopcomputer_not/dgfofug/?st=j1o3oa29&sh=e0c29c6d
#   * https://support.microsoft.com/en-in/help/4014551/description-of-the-security-and-quality-rollup-for-the-net-framework-4
#   * https://support.microsoft.com/en-us/help/4020459
shutdown -s
