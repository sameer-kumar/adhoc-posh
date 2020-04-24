$rootTfsUri = "http://TFsServer:8080/tfs"
$collectionName = "Projects"
$allProjectsUri = "$rootTfsUri/$($collectionName)/_apis/projects?api-version=3.1&`$top=256"
$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -UseBasicParsing #-Verbose
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    # Enumerate all projects
    foreach($prj in $responseObject.value)
    {
        $projectName = $($prj.Name)
        $tfsUri = $rootTfsUri + "/" + $collectionName + "/" + $projectName
        $releaseDefinitionsUri = "$tfsUri/_apis/release/definitions?api-version=3.1-preview"
        $releaseDefinitionsResponse = Invoke-WebRequest -Uri $releaseDefinitionsUri -UseDefaultCredentials -Method Get -UseBasicParsing -ContentType "application/json" #-Verbose
        $releaseDefinitionsResponseObject = $releaseDefinitionsResponse.Content | ConvertFrom-Json
        if($releaseDefinitionsResponseObject -ne $null -and $releaseDefinitionsResponseObject.count -ge 1)
        {
            # Enumerate release definitions of current project
            foreach($releaseDefinition in $releaseDefinitionsResponseObject.value)
            {
                $releaseDefinitionId = $releaseDefinition.Id
                $releaseDefinitionName = $releaseDefinition.Name
                Write-verbose "$releaseDefinitionName release definition exists in $projectName" -Verbose
                $releaseDefinitionDetailsUri = "$tfsUri/_apis/release/definitions/$($releaseDefinitionId)?api-version=3.1-preview&`$expand=environments"
                $releaseDefinitionDetailsResponse = Invoke-WebRequest -Uri $releaseDefinitionsUri -UseDefaultCredentials -Method Get -UseBasicParsing -ContentType "application/json" #-Verbose
                $releaseDefinitionDetailsResponseObject = $releaseDefinitionsResponse.Content | ConvertFrom-Json
            }
        }
    }
}
#api-version=3.1-preview
