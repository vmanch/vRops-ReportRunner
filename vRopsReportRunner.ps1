#Powershell script which runs vRops report via the suite-api and downloads them locally
#v1.0 vMan.ch, 21.06.2016 - Initial Version

<#

    The following command must be run once to generate the Credential file to connect to each environment.

        Run once for per virtual center 
        
        $cred = Get-Credential
        $cred | Export-Clixml -Path "c:\vRops\Config\vc.xml"

#>

#vars
$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName
$Output = $ScriptPath  +'\Reports\'
$vRopsAddress = 'vc.vman.local'
$vRopsCreds = Import-Clixml -Path "$ScriptPath\config\VC.xml"
$vCenter = '7d3a8453-6559-4d4c-9005-3f8655e4394f'
$Report = '1f66552f-7bb4-4d2c-9661-81a811de19b0'

## Function

Function GetReport([String]$vRopsAddress, [String]$vCenter, [String]$Report, [String]$Env, $vRopsCreds, $Path){

Write-host 'Running Report for' $Env

#Take all certs.
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


#RUN Report

$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')

$RunReporturl = 'https://'+$vRopsAddress+'/suite-api/api/reports'

$Body = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ops:report xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
    <ops:resourceId>$vCenter</ops:resourceId>
    <ops:reportDefinitionId>$Report</ops:reportDefinitionId>
    <ops:traversalSpec adapterInstanceAssociation="false">
        <ops:name>vSphere Hosts and Clusters</ops:name>
        <ops:rootAdapterKindKey>VMWARE</ops:rootAdapterKindKey>
        <ops:rootResourceKindKey>vSphere World</ops:rootResourceKindKey>
    </ops:traversalSpec>
</ops:report>
"@


[xml]$Data = Invoke-RestMethod -Method POST -uri $RunReporturl -Credential $vRopsCreds -ContentType $ContentType -Headers $header -Body $body

$ReportLink = $Data.report.links.link.href

$ReportLinkurl = 'https://' + $vRopsAddress + $ReportLink

#Check if report is run to download

[xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -Credential $vRopsCreds -ContentType $ContentType -Headers $header


While ($ReportStatus.report.status -ne "COMPLETED") {
    [xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -Credential $vRopsCreds -ContentType $ContentType -Headers $header
    Write-host 'Waiting for' $Env 'report to finish running, current status: '  $ReportStatus.report.status
    Sleep 3
      } # End of block statement


$ReportDownload = $ReportLinkurl + '/download?format=CSV'


$ReportOutputfile = $Path + '\collections\' + $Env + '_OversizedVMReport.csv'

Invoke-RestMethod -Method GET -uri $ReportDownload -Credential $vRopsCreds -ContentType $ContentType -Headers $header -OutFile $ReportOutputfile

Write-host 'Report for' $Env 'finished'

return $ReportOutputfile
}


$Report = GetReport $vRopsAddress $vCenter $Report 'VC' $vRopsCreds $ScriptPath