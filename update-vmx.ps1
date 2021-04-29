Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $true -Confirm:$false
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false



$vc_ip = "srv-vcenter-01.megasp.net"
$vc_user = "administrator@megasp.net"
$vc_pass = "VMware1!"
$vc = ""


$nsx_ip = "srv-nsxt-manager-01.megasp.net"
$nsx_user = "admin"
$nsx_pass = "myPassword1!myPassword1!"
$nsx = ""

Function Debug($msg) {
    Write-Host -ForegroundColor Cyan "$msg"
}

Function Error($msg) {
    Write-Host -ForegroundColor Red "$msg"
    exit
}

Function post ($url, $user, $pass, $body, $return_error=$false) {
    $pair = "$($user):$($pass)"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)

    $headers = @{
        "Authorization" = "basic $base64"
        "Content-Type" = "application/json"
    }

    try {
        $request = Invoke-WebRequest -Uri $url -Body $body -Method POST -Headers $headers -SkipCertificateCheck 
    } catch {
        if ($return_error) {
            return "`n($_)`n"
            return "`n($_.Exception.Message)`n"
        }
        Debug "Error when doing a PUT $url with $body"
        Debug "`n($_.Exception.Message)`n"
        exit
    }

    if ($request.StatusCode -eq 201 -or $request.StatusCode -eq 200) {
        Debug "Successfully ran POST $url"
    } else {
        Debug "Unknown State during PUT $url : $requests"
        exit
    }

}

Debug "Connect to VC"
$vc = Connect-VIServer $vc_ip -User $vc_user  -WarningAction SilentlyContinue
Debug "Connect to NSX"
$nsx = Connect-NsxtServer -Server $nsx_ip -Username $nsx_user -WarningAction SilentlyContinue
if (!$vc -or !$nsx) {
    Error "Unable to connect! Exiting"
}

# connect


$n = $nsx
$tn_service = Get-NsxtService -Server $n -Name "com.vmware.nsx.transport_nodes"
$edge_cluster_service = Get-NsxtService -Server $n -Name "com.vmware.nsx.edge_clusters"
$edge_clusters = $edge_cluster_service.list().results

foreach ($edge_cluster in $edge_clusters) {
    $edges = $edge_cluster.members
    foreach ($edge in $edges) {
        $tn_id = $edge.transport_node_id
        $edge_tn =  $tn_service.list($null,$null, $null, $tn_id)

        if ($edge_tn.results[0].node_deployment_info.deployment_type -eq "VIRTUAL_MACHINE") {
            $edge_name = $edge_tn.results[0].node_deployment_info.display_name
            debug "Edge $edge_name is a VM"

            $edge_vm = Get-VM -Server $vc -Name $edge_name

            if ($edge_vm | Get-AdvancedSetting -Name 'ethernet0.pnicFeatures') {
                Debug "nothing to do"
            } else {
                debug "poweroff, and change vmx, power on and wait for status"

                # Put Edge in Maintenance Mode
                $json = [pscustomobject] @{
                    "maintenance_mode" = "true"
                }
    
                $body = $json | ConvertTo-Json -Depth 10
                $url = "https://$nsx_ip/api/v1/node/maintenance-mode"
                Debug "Putting Edge on Maintenance Mode: $edge_name"
                $res = post $url $nsx.user $nsx.password $body
exit
                Shutdown-VMGuest -Server $vc $edge_vm -Confirm:$false


 #               start-vm -Server $vc $edge_vm

            }
        }
    }
}

$edge_nodes = $tn_service.list().results | Where-Object {$_.node_deployment_info.resource_type -eq "EdgeNode"}
