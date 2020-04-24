# http://blog.majcica.com/2017/12/20/managing-vsts-tfs-release-definition-variables-from-powershell/
$releaseVariableName = 'DeploymentSvcAccountNameDev'
$releaseVariableValue = 'SvcAccount'

$rootTfsUri = "http://TFS:8080/tfs"
$collectionName = "Projects"
$allProjectsUri = "$rootTfsUri/$($collectionName)/_apis/projects?api-version=3.1&`$top=256"
$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    # Enumerate all projects
    foreach($prj in $responseObject.value)
    {
        $projectName = $($prj.Name)
        $tfsUri = $rootTfsUri + "/" + $collectionName + "/" + $projectName
        $releaseDefinitionsUri = "$tfsUri/_apis/release/definitions?api-version=3.1-preview"
        $releaseDefinitionsResponse = Invoke-WebRequest -Uri $releaseDefinitionsUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing -ContentType "application/json"
        $releaseDefinitionsResponseObject = $releaseDefinitionsResponse.Content | ConvertFrom-Json
        if($releaseDefinitionsResponseObject -ne $null -and $releaseDefinitionsResponseObject.count -ge 1)
        {
            # Enumerate release definitions of current project
            foreach($releaseDefinition in $releaseDefinitionsResponseObject.value)
            {
                $isUpdated = $false
                $releaseDefinitionId = $releaseDefinition.Id
                $releaseDefinitionName = $releaseDefinition.Name
                # get the variableGroups of this release definition
                $releaseDefinitionUri = "$tfsUri/_apis/release/definitions/$($releaseDefinitionId)?expand=Environments" 
                $releaseDefinitionResponse = Invoke-WebRequest -Uri $releaseDefinitionUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing -ContentType "application/json"
                $releaseDefinitionResponseObject = $releaseDefinitionResponse.Content | convertfrom-json
                # get Variable Groups
                if($releaseDefinitionResponseObject.variableGroups -ne $null -and $releaseDefinitionResponseObject.variableGroups.Count -ge 1)
                {
                    $varGroups = $releaseDefinitionResponseObject.variableGroups -join ","
                    $varGroupUri = "$tfsUri/_apis/distributedtask/variablegroups?groupIds=$varGroups" 
                    $varGroupResponse = Invoke-WebRequest -Uri $varGroupUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing -ContentType "application/json"
                    $varGroupResponseObject = $varGroupResponse.Content | convertfrom-json
                    # Enumerate variable groups of current release definition
                    foreach($varGroup in $varGroupResponseObject.value)
                    {
                        # Enumerate variables of current variable group
                        foreach($variable in $varGroup.variables)
                        {
                            # read the variable name from PSCustomObject
                            $props = Get-Member -InputObject $variable -MemberType NoteProperty
                            foreach($prop in $props) 
                            {
                                $propValue = $variable | Select-Object -ExpandProperty $prop.Name
                                $prop.Name + "=" + $propValue
                                if($prop.Name -eq $releaseVariableName)
                                {
                                    $newValue = [PSCustomObject]@{value=$releaseVariableValue}
                                    #$varGroupResponseObject.variables.PSObject.Properties.Item($prop.Name).Value = $newValue
                                    $item = $varGroupResponseObject.value | where-Object{$_.variables.PSObject.Properties.Name -eq $prop.Name} 
                                    $item.variables.PSObject.Properties.Item($prop.Name).Value = $newValue
                                    $isUpdated = $true
                                }
                            }
                        }
                    }
                    
                    if($isUpdated)
                    {
                        # Update the release definition for update variable groups
                        ## THIS FAILS. BELOW COMMENTED CODE IS WORKING FOR UPDATING RELEASE DEF VARS BUT NOT VARGROUPS.
                        $body = $varGroupResponseObject | ConvertTo-Json -Depth 10 -Compress
                        $updateReleaseDefinitionUri = "$tfsUri/_apis/release/definitions?api-version=3.1-preview" 
                        $updateReleaseDefinitionResponse = Invoke-WebRequest -Uri $updateReleaseDefinitionUri -UseDefaultCredentials -Method Put -Body $body -ContentType "application/json" -Verbose
                    }
                }
            }
        }
    }
}







<# get ENV variables

foreach($environment in $releaseResponseAsJson.environments)
{
    $environment.name
    $environment.variables
}

# Update Release definition variables
$newProductCode = [PSCustomObject]@{value='CSS-updated'}
$releaseResponseAsJson.variables.PSObject.Properties.Item('ProductCode').Value = $newProductCode
$body = $releaseResponseAsJson | ConvertTo-Json -Depth 10 -Compress
$releaseDefinitionUri = "$tfsUri/_apis/release/definitions?api-version=3.1-preview" 
$releaseResponse = Invoke-WebRequest -Uri $releaseDefinitionUri -UseDefaultCredentials -Method Put -Body $body -ContentType "application/json" -Verbose

#>