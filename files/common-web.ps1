import-module webadministration -ErrorAction SilentlyContinue

function Resolve-Error($ErrorRecord=$Error[0])
{
   $ErrorRecord | Format-List * -Force
   $ErrorRecord.InvocationInfo |Format-List *
   $Exception = $ErrorRecord.Exception
   for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
   {   "$i" * 80
       $Exception |Format-List * -Force
   }
}
$ErrorActionPreference = 'Stop'
trap
{
	write-error $_
	Resolve-Error $_
    exit 1
}

function apppool([string] $name, [object] $processModel, [string] $runtimeVersion = "v4.0", [string] $pipelineMode = "Integrated", [string] $startMode = "OnDemand", [string] $state = "present") {
    "Creating / Updating AppPool {0}..." -f $name

    $success = $false;
    $attempts = 0;
    $change = $false;

    $supported_process_model_properties = @(
        'identityType',
        'userName',
        'password',
        'loadUserProfile', #boolean
        'setProfileEnvironment',#boolean
        'maxProcesses', #int32
        'idleTimeout',#int32 in minutes
        'logonType'
    )

    while($success -eq $false -and $attempts -lt 5)
    {
        try
        {
            $attempts++;

            if ($state -eq "absent")
            {
               try { Remove-WebAppPool -Name $name } catch {}
            }
            else {
            if ((Test-Path IIS:\AppPools\$name) -eq $false)
            {
                New-WebAppPool -Name $name
                $change = $true
            }

            $app_pool = Get-ItemProperty IIS:\AppPools\$name | select *

            if ($app_pool.managedRuntimeVersion -ne $runtimeVersion) {
                Set-ItemProperty IIS:\AppPools\$name -name managedRuntimeVersion -value $runtimeVersion
                $change = $true
            }

            if ($app_pool.startMode -ne $startMode) {
                Set-ItemProperty IIS:\AppPools\$name -name startMode -value $startMode
                #Set-WebConfigurationProperty "/system.applicationHost/applicationPools/add[@name='$name']" -name startMode -value $startMode
                $change = $true
            }

            $current_process_model = $app_pool.processModel

            $processModel.keys | ForEach-Object {
                $t_key = $_
                $t_value = $processModel[$_]

                if (! $supported_process_model_properties.Contains($t_key)) {
                    return
                }
                # When the property of processModel is an complex object eg. idleTimeout
                if ($t_key -eq 'idleTimeout') {
                    if ($current_process_model.idleTimeout.TotalMinutes -ne $t_value) {
                        "Update $t_key " + $current_process_model.idleTimeout.TotalMinutes + " => $t_value"
                        Set-ItemProperty IIS:\AppPools\$name -Name processModel.idleTimeout -value ( [TimeSpan]::FromMinutes($t_value))
                        $change = $true
                    }
                    return
                }

                # Simple key => value
                if ( $current_process_model.$t_key -ne $t_value) {
                    "Update $t_key " + $current_process_model.$t_key + " => $t_value"
                    Set-ItemProperty IIS:\AppPools\$name -name processModel.$t_key -value $t_value
                    $change = $true
                }
            }

            if ($processModel.identityType -eq "SpecificUser") {
                Set-ItemProperty "IIS:\AppPools\$name" -name processModel -value @{userName=$processModel.username;password=$processModel.password;identitytype=3}
            }

            if ($startMode -eq "AlwaysRunning")
            {
                #Clear-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$name']/recycling/periodicRestart/requests"
                #Clear-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$name']/recycling/periodicRestart/schedule"
                #Clear-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$name']/recycling/periodicRestart/time"
                #Clear-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$name']/recycling/periodicRestart/memory"
                #Add-WebConfiguration "/system.applicationHost/applicationPools/add[@name='$name']/recycling/periodicRestart/schedule" -value (New-TimeSpan -h 00 -m 00)
            }
            }
            $success = $true;

            if ($change -and $state -ne 'absent') {
                Restart-WebAppPool -Name $name
            }

        }
        catch [Exception]
        {
            $_.Exception
        }
    }
}


function website([string] $name, [string] $state = "present", [string] $path, [string] $apppool, [string] $port = 443, [bool] $Ssl = $true, [string] $certHash = "", [string] $IpAddress = "*", [string] $hostHeader = "localhost", [bool] $anonymousAuthentication = $false, [bool] $basicAuthentication = $false, [bool] $windowsAuthentication = $false, [bool] $formsAuthentication = $false) {
    "Creating / Updating WebSite {0}..." -f $name

    $success = $false;
    $attempts = 0;

    if ($state -eq "absent")
     {
         Remove-Website -Name $name
	     $success = $true;
     }

    while($success -eq $false -and $attempts -lt 5)
    {
		try
		{
			$attempts++;

			if ((Test-Path $path) -eq $false)
			{
				New-item $path -ItemType directory
			}

			if ((Test-Path IIS:\Sites\$name) -eq $false)
			{
                New-WebSite -Name $name -Port $port -HostHeader $hostHeader -PhysicalPath $path -IPAddress $IpAddress
			}
			else
			{
				Set-ItemProperty IIS:\Sites\$name -name physicalpath -value $path
			}


            if ($certHash -ne "")
            {
                if (Get-WebBinding -Name $name -IPAddress $IpAddress -Port $port -HostHeader $hostHeader -Protocol http) {
                  Remove-WebBinding -Name $name -BindingInformation "${IpAddress}:${port}:${hostHeader}" -Protocol http
                }

                if (!(Get-WebBinding -Name $name -IPAddress $IpAddress -Port $port -HostHeader $hostHeader -Protocol https)) {
                  New-WebBinding -Name $name -IPAddress $IpAddress -Port $port -HostHeader $hostHeader -Protocol https
                }
                $httpsBinding = Get-WebBinding -Name $name -Protocol "https"
                $httpsBinding.AddSslCertificate($certHash, "my")
            }


            $web_site =  Get-ItemProperty IIS:\Sites\$name | select *


			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value $anonymousAuthentication -PSPath IIS:\ -location $name
			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -value $basicAuthentication -PSPath IIS:\ -location $name
			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value $windowsAuthentication -PSPath IIS:\ -location $name

            if ($formsAuthentication)
			{
				Set-WebConfigurationProperty -filter /system.web/authentication -name mode -value Forms -PSPath IIS:\ -location $name
			}

            if ($web_site.applicationPool -ne $apppool) {
                Set-ItemProperty "IIS:\Sites\$name" -name ApplicationPool -value "$apppool"
            }

            if ($state -eq 'started')
            {
                Start-Website $name
            }
            elseif ($state -eq 'stopped')
            {
                Stop-Website $name
            }
            elseif ($state -eq 'restarted')
            {
                Stop-Website $name
                sleep 5
                Start-Website $name
            }

			$success = $true;
		}
		catch [Exception]
		{
			$_.Exception
		}
	}
}

# Not in use - we use our custom win_iis_webapplication in the library folder
function application([string] $name, [string] $path, [string] $website, [string] $apppool, [bool] $preloadEnabled = $false, [bool] $anonymousAuthentication = $false, [bool] $basicAuthentication = $false, [bool] $windowsAuthentication = $false, [bool] $formsAuthentication = $false) {
	 "Creating / Updating Application {0}..." -f $name

	$success = $false;
    $attempts = 0;

    while($success -eq $false -and $attempts -lt 5)
    {
		try
		{
			$attempts++;

			if ((Test-Path IIS:\Sites\$website\$name) -eq $false)
			{
				New-WebApplication -Name $name -PhysicalPath $path -Site $website -ApplicationPool $apppool
			}

			Set-ItemProperty IIS:\Sites\$website\$name -name ApplicationPool -value $apppool
			Set-ItemProperty IIS:\Sites\$website\$name -name PhysicalPath -value $path
			Set-ItemProperty IIS:\Sites\$website\$name -name preloadEnabled -value $preloadEnabled

			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value $anonymousAuthentication -PSPath IIS:\ -location $website/$name
			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/basicAuthentication -name enabled -value $basicAuthentication -PSPath IIS:\ -location $website/$name
			Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value $windowsAuthentication -PSPath IIS:\ -location $website/$name

			if ($formsAuthentication)
			{
				Set-WebConfigurationProperty -filter /system.web/authentication -name mode -value Forms -PSPath IIS:\ -location $website/$name
			}

			$success = $true;
		}
		catch [Exception]
		{
			$_.Exception
		}
	}
}

function xmlPeek($filePath, $xpath) {
    [xml] $fileXml = Get-Content $filePath
    return $fileXml.SelectSingleNode($xpath).InnerText
}

function xmlPoke($file, $xpath, $value, $ns, $append = $false) {
    $filePath = $file.FullName

    #"Poking $filePath at $xpath with $value..."

    [xml] $fileXml = Get-Content $filePath
    #$node = $fileXml.SelectSingleNode($xpath, $ns)
    if ($ns -ne $null)
    {
		$nodes = $fileXml | Select-Xml $xpath -Namespace $ns
	}
	else
	{
		$nodes = $fileXml | Select-Xml $xpath
	}

	$xml = [xml]("<xml>{0}</xml>"-f $value);

    foreach($node in $nodes)
    {
	    if ($node -and $node.Node) {
		    if ($append -eq $false)
		    {
			    while($node.Node.HasChildNodes)
				{
					$rem = $node.Node.RemoveChild($node.Node.FirstChild);
				}
		    }
		    $xml["xml"].ChildNodes | foreach { setNode -fileXml $fileXml -node $node.Node -child $_ }
		    $fileXml.Save($filePath)
		    #"Done"
	    }
    }
}

function setNode($fileXml, $node, $child)
{
	if ($child.NodeType -eq "Text")
	{
		$text = $fileXml.CreateTextNode($child.Value);
		$appended = $node.AppendChild($text);
	}
	elseif ($child.NodeType -eq "Element")
	{
		$prefix = $child.Prefix;
		$localName = $child.LocalName;
		$namespaceURI = if($child.NamespaceURI) { $child.NamespaceURI } else { $node.NamespaceURI };
		$el = $fileXml.CreateElement($prefix, $localName, $namespaceURI);
		$child.Attributes | foreach { $el.SetAttribute($_.Name, $_.Value) }
		$appended = $node.AppendChild($el);
		$child.ChildNodes | foreach { setNode -fileXml $fileXml -node $el -child $_ }
	}
	else
	{
		("Unsupported element = {0}" -f $child.NodeType)
	}
}

Function Merge-Object($Base, $Additional) {
    $new = $Base |
        foreach { $_.Keys } |
        foreach -Begin {
            $output = @{}
        } -Process {
            if ($Additional[$_] -ne $null)
            {
                $output[$_] = $Additional[$_]
            }
            else
            {
                $output[$_] = $Base[$_]
            }
        } -End {
            New-Object PSObject -Property $Output
        }
    return $new
}
