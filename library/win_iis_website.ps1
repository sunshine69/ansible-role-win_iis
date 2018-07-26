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

$params = Parse-Args $args;

# Name parameter
$name = Get-Attr $params "name" $FALSE;
If ($name -eq $FALSE) {
    Fail-Json @{} "missing required argument: name";
}

# State parameter
$state = Get-Attr $params "state" $FALSE;
$state.ToString().ToLower();
If (($state -ne $FALSE) -and ($state -ne 'started') -and ($state -ne 'stopped') -and ($state -ne 'restarted') -and ($state -ne 'absent')) {
  Fail-Json @{} "state is '$state'; must be 'started', 'restarted', 'stopped' or 'absent'"
}

# Path parameter
$physical_path = Get-Attr $params "physical_path" $FALSE;
$site_id = Get-Attr $params "site_id" $FALSE;

# Application Pool Parameter
$application_pool = Get-Attr $params "application_pool" $FALSE;

# Binding Parameters
$bind_port = Get-Attr $params "port" $FALSE;
$bind_ip = Get-Attr $params "ip" $FALSE;
$bind_hostname = Get-Attr $params "hostname" $FALSE;
$bind_ssl = Get-Attr $params "ssl" $FALSE;

# Authentication parameters
$anonymousAuthentication = Get-Attr $params "anonymous_authentication" $FALSE;
$basicAuthentication = Get-Attr $params "basic_authentication" $FALSE;
$windowsAuthentication = Get-Attr $params "windows_authentication" $FALSE;
$formsAuthentication = Get-Attr $params "forms_authentication" $FALSE;

# Custom site Parameters from string where properties
# are separated by a pipe and property name/values by colon.
# Ex. "foo:1|bar:2"
$parameters = Get-Attr $params "parameters" $null;
if($parameters -ne $null) {
  $parameters = @($parameters -split '\|' | ForEach {
    return ,($_ -split "\:", 2);
  })
}


# Ensure WebAdministration module is loaded
if ((Get-Module "WebAdministration" -ErrorAction SilentlyContinue) -eq $null) {
  Import-Module WebAdministration
}

# Result
$result = @{
  site = @{}
  changed = $false
};

# Site info
$site = Get-Website | Where { $_.Name -eq $name }

Try {
  # Add site
  If(($state -ne 'absent') -and (-not $site)) {
    If ($physical_path -eq $FALSE) {
      Fail-Json @{} "missing required arguments: physical_path"
    }
    ElseIf (-not (Test-Path $physical_path)) {
      Fail-Json @{} "specified folder must already exist: physical_path"
    }

    $site_parameters = @{
      Name = $name
      PhysicalPath = $physical_path
    };

    If ($application_pool) {
      $site_parameters.ApplicationPool = $application_pool
    }

    If ($site_id) {
        $site_parameters.ID = $site_id
    }

    If ($bind_port) {
      $site_parameters.Port = $bind_port
    }

    If ($bind_ip) {
      $site_parameters.IPAddress = $bind_ip
    }

    If ($bind_hostname) {
      $site_parameters.HostHeader = $bind_hostname
    }

    # Fix for error "New-Item : Index was outside the bounds of the array."
    # This is a bug in the New-WebSite commandlet. Apparently there must be at least one site configured in IIS otherwise New-WebSite crashes.
    # For more details, see http://stackoverflow.com/questions/3573889/ps-c-new-website-blah-throws-index-was-outside-the-bounds-of-the-array
    $sites_list = get-childitem -Path IIS:\sites
    if ($sites_list -eq $null) { $site_parameters.ID = 1 }

    $site = New-Website @site_parameters -Force
    $result.changed = $true
  }

  # Remove site
  If ($state -eq 'absent' -and $site) {
    $site = Remove-Website -Name $name
    $result.changed = $true
  }

  $site = Get-Website | Where { $_.Name -eq $name }
  If($site) {
    # Change Physical Path if needed
    if($physical_path) {
      If (-not (Test-Path $physical_path)) {
        Fail-Json @{} "specified folder must already exist: physical_path"
      }

      $folder = Get-Item $physical_path
      If($folder.FullName -ne $site.PhysicalPath) {
        Set-ItemProperty "IIS:\Sites\$($site.Name)" -name physicalPath -value $folder.FullName
        $result.changed = $true
      }
    }

    # Change Application Pool if needed
    if($application_pool) {
      If($application_pool -ne $site.applicationPool) {
        Set-ItemProperty "IIS:\Sites\$($site.Name)" -name applicationPool -value $application_pool
        $result.changed = $true
      }
    }

    # Set properties
    if($parameters) {
      $parameters | foreach {
        $property_value = Get-ItemProperty "IIS:\Sites\$($site.Name)" $_[0]

        switch ($property_value.GetType().Name)
        {
            "ConfigurationAttribute" { $parameter_value = $property_value.value }
            "String" { $parameter_value = $property_value }
        }

        if((-not $parameter_value) -or ($parameter_value) -ne $_[1]) {
          Set-ItemProperty "IIS:\Sites\$($site.Name)" $_[0] $_[1]
          $result.changed = $true
        }
      }
    }

    # Set authentication type
    if ($anonymousAuthentication) {
        Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value $anonymousAuthentication -PSPath IIS:\ -location $name
    }
    if ($windowsAuthentication) {
        Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value $windowsAuthentication -PSPath IIS:\ -location $name
    }
    if ($basicAuthentication) {
        Set-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -value $basicAuthentication -PSPath IIS:\ -location $name
    }
    if ($formsAuthentication) {
        Set-WebConfigurationProperty -filter /system.web/authentication -name mode -value Forms -PSPath IIS:\ -location $name
    }

    # Set run state
    if (($state -eq 'stopped') -and ($site.State -eq 'Started'))
    {
      Stop-Website -Name $name -ErrorAction Stop
      $result.changed = $true
    }
    if ((($state -eq 'started') -and ($site.State -eq 'Stopped')) -or ($state -eq 'restarted'))
    {
      Start-Website -Name $name -ErrorAction Stop
      $result.changed = $true
    }
  }
}
Catch
{
  Fail-Json @{} $_.Exception.Message
}

if ($state -ne 'absent')
{
  $site = Get-Website | Where { $_.Name -eq $name }
}

if ($site)
{
  $result.site = @{
    Name = $site.Name
    ID = $site.ID
    State = $site.State
    PhysicalPath = $site.PhysicalPath
    ApplicationPool = $site.applicationPool
    Bindings = @($site.Bindings.Collection | ForEach-Object { $_.BindingInformation })
  }
}

Exit-Json $result
