#!powershell

# (c) 2015, Henrik Wallström <henrik@wallstroms.nu>
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# WANT_JSON
# POWERSHELL_COMMON

$params = Parse-Args $args -supports_check_mode $true
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -type "bool" -default $false

$name = Get-AnsibleParam -obj $params -name "name" -type "str" -failifempty $true
$site = Get-AnsibleParam -obj $params -name "site" -type "str" -failifempty $true
$state = Get-AnsibleParam -obj $params -name "state" -type "str" -default "present" -validateset "absent","present"
$physical_path = Get-AnsibleParam -obj $params -name "physical_path" -type "str" -aliases "path"
$application_pool = Get-AnsibleParam -obj $params -name "application_pool" -type "str"

# Authentication Parameters
$anonymousAuthentication = Get-Attr $params "anonymous_authentication" $FALSE;
$basicAuthentication = Get-Attr $params "basic_authentication" $FALSE;
$windowsAuthentication = Get-Attr $params "windows_authentication" $FALSE;
$formsAuthentication = Get-Attr $params "forms_authentication" $FALSE;

# SSL flags
$sslFlags = Get-Attr $params "ssl_flags" $FALSE;

$result = @{
  application_pool = $application_pool
  changed = $false
  physical_path = $physical_path
}

# Ensure WebAdministration module is loaded
if ((Get-Module "WebAdministration" -ErrorAction SilentlyContinue) -eq $null) {
  Import-Module WebAdministration
}

# Application info
$application = Get-WebApplication -Site $site -Name $name

try {
  # Add application
  if (($state -eq 'present') -and (-not $application)) {
    if (-not $physical_path) {
      Fail-Json $result "missing required arguments: path"
    }
    if (-not (Test-Path -Path $physical_path)) {
      Fail-Json $result "specified folder must already exist: path"
    }

    $application_parameters = @{
      Name = $name
      PhysicalPath = $physical_path
      Site = $site
    }

    if ($application_pool) {
      $application_parameters.ApplicationPool = $application_pool
    }

    if (-not $check_mode) {
        $application = New-WebApplication @application_parameters -Force
    }
    $result.changed = $true
  }

  # Remove application
  if ($state -eq 'absent' -and $application) {
    $application = Remove-WebApplication -Site $site -Name $name -WhatIf:$check_mode
    $result.changed = $true
  }

  $application = Get-WebApplication -Site $site -Name $name
  if ($application) {

    # Change Physical Path if needed
    if ($physical_path) {
      if (-not (Test-Path -Path $physical_path)) {
        Fail-Json $result "specified folder must already exist: path"
      }

      $app_folder = Get-Item $application.PhysicalPath
      $folder = Get-Item $physical_path
      if ($folder.FullName -ne $app_folder.FullName) {
        Set-ItemProperty "IIS:\Sites\$($site)\$($name)" -name physicalPath -value $physical_path -WhatIf:$check_mode
        $result.changed = $true
      }
    }

    # Change Application Pool if needed
    if ($application_pool) {
      if ($application_pool -ne $application.applicationPool) {
        Set-ItemProperty "IIS:\Sites\$($site)\$($name)" -name applicationPool -value $application_pool -WhatIf:$check_mode
        $result.changed = $true
      }
    }

    # Authentication settings
    if ($anonymousAuthentication) {
        $currentAnonymousAuthentication = (Get-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -PSPath IIS:\ -location $site/$name).Value
        if ($anonymousAuthentication -ne $currentAnonymousAuthentication) {
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value $anonymousAuthentication -PSPath IIS:\ -location $site/$name
            $result.changed = $true
        }
    }
    if ($basicAuthentication) {
        $currentBasicAuthentication = (Get-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -PSPath IIS:\ -location $site/$name).Value
        if ($basicAuthentication -ne $currentBasicAuthentication) {
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -value $basicAuthentication -PSPath IIS:\ -location $site/$name
            $result.changed = $true
        }
    }
    if ($windowsAuthentication) {
        $result.DEBUG = "Reaching here"
        $currentWindowsAuthentication = (Get-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -PSPath IIS:\ -location $site/$name).Value
        if ($windowsAuthentication -ne $currentWindowsAuthentication) {
            $result.DEBUG += "Going to set windowAuthentication to be $windowsAuthentication"
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value $windowsAuthentication -PSPath IIS:\ -location $site/$name
            $result.changed = $true
        }
    }
    if ($formsAuthentication) {
        $currentFormsAuthentication = (Get-WebConfiguration system.web/authentication "IIS:Sites\$site\$name")
        if ($formsAuthentication -ne $currentFormsAuthentication.mode) {
            $currentFormsAuthentication.mode = "Forms"
            $currentFormsAuthentication | Set-WebConfiguration system.web/authentication
            $result.changed = $true
        }
    }
    if ($sslFlags) {
        $ConfigSection = Get-IISConfigSection -SectionPath "system.webServer/security/access" -CommitPath "$site" -Location "$name"
        #to set:
        Set-IISConfigAttributeValue -AttributeName sslFlags -AttributeValue "$sslFlags" -ConfigElement $ConfigSection
    }
  }
} catch {
  Fail-Json $result $_.Exception.Message
}

# When in check-mode or on removal, this may fail
$application = Get-WebApplication -Site $site -Name $name
if ($application) {
  $result.physical_path = $application.PhysicalPath
  $result.application_pool = $application.ApplicationPool
}

Exit-Json $result
