$rootTfsUri = "http://tfsvc:8080/tfs"
$collectionName = "Projects"
$allProjectsUri = "$rootTfsUri/$($collectionName)/_apis/projects?api-version=3.1&`$top=256"
$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -UseBasicParsing #-Verbose
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    # Enumerate all projects
    $buildDefinitions = @()
    $buildDefinitionsContent = @()
    foreach($prj in $responseObject.value)
    {
        $projectName = $($prj.Name)
        $tfsUri = $rootTfsUri + "/" + $collectionName + "/" + $projectName
        # The TYPE query parameter of value BUILD tells the TFS to return only definitions of the new build type. If nothing is specified all definitions are returned.
        $buildDefinitionsUri = "$tfsUri/_apis/build/definitions?api-version=2.0&includeAllProperties=true&type=xaml"
        #$buildDefinitionsUri = "$tfsUri/_apis/build/definitions?api-version=3.1&includeAllProperties=true"
        
        $buildDefinitionsResponse = Invoke-WebRequest -Uri $buildDefinitionsUri -UseDefaultCredentials -Method Get -UseBasicParsing -ContentType "application/json" #-Verbose
        $buildDefinitionsResponseObject = $buildDefinitionsResponse.Content | ConvertFrom-Json
        $buildDefinitionsContent += $buildDefinitionsResponse.Content
        if($buildDefinitionsResponseObject -ne $null -and $buildDefinitionsResponseObject.count -ge 1)
        {
            # Enumerate release definitions of current project
            foreach($buildDefinition in $buildDefinitionsResponseObject.value)
            {
                $buildDefinitionId = $buildDefinition.Id
                $buildDefinitionName = $buildDefinition.Name
                $buildDefinitionStatus = $buildDefinition.queueStatus
                if ($buildDefinitionStatus -ne 'disabled')
                {
                    Write-Host "$buildDefinitionName build definition exists in $projectName" -BackgroundColor DarkRed -ForegroundColor White -Verbose    
                }
                else
                {
                    Write-Host "$buildDefinitionName build definition exists in $projectName" -BackgroundColor DarkGreen -ForegroundColor White -Verbose
                }
                
                $buildDefinitions += $buildDefinition
            }
        }
    }

    $buildDefinitions | Select-Object  |  Out-File 'c:\temp\TfsBuildDefinitions.json' -Force
    $buildDefinitionsContent | Out-File 'c:\temp\TfsBuildDefinitionsv2.json' -Force
}
#api-version=3.1-preview&
