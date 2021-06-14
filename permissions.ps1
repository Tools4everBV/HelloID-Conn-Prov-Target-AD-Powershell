$config = $configuration | ConvertFrom-Json 

[string]$userName = $config.connection.username
[string]$userPassword = $config.connection.userpwd

# Convert to SecureString
[securestring]$secStringPassword = ConvertTo-SecureString $userPassword -AsPlainText -Force

[pscredential]$credObject = New-Object System.Management.Automation.PSCredential ($userName, $secStringPassword)

Write-Verbose -Verbose 'Creating Session'
$sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck

$session = New-PSSession  -ComputerName $config.connection.serverfqdn -Credential $credObject -UseSSL -SessionOption $sessionOption

Write-Verbose -Verbose 'Creating Session'
Import-PSSession -Session $session -module ActiveDirectory -AllowClobber | Out-Null
Write-Verbose -Verbose 'imported Session'
$adGroups = Get-ADGroup -Filter *
foreach($group in $adGroups)
{
	$row = @{
		DisplayName = $group.name;
		Identification = @{
			Id = $group.name;
			DisplayName = $group.name;
            Type = "Group";
		}
	};

	Write-Output ($row | ConvertTo-Json -Depth 10)
}