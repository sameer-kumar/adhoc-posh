$rootTfsUri = "http://TfsServer:8080/tfs/Projects"
$allProjectsUri = "$rootTfsUri/_apis/projects?api-version=3.1&`$top=256"
$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    foreach($prj in $responseObject.value)
    {
        $project = "$($prj.name)"
        Write-Verbose -Message "Deleting XAML builds for $project ..." -Verbose
        # "C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\TFSBuild.exe delete /collection:$rootTfsUri /DateRange:~1/1/2020 $project"
        $CMD = 'C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\TFSBuild.exe'
        $arg1 = 'delete'
        $arg2 = "/collection:$rootTfsUri"
        $arg3 = '/DateRange:~1/1/2020'
        $arg4 = "$project"
        & $CMD $arg1 $arg2 $arg3 $arg4 
        
        $arg1 = 'destroy'
        & $CMD $arg1 $arg2 $arg3 $arg4 
    }
}
else
{
    Write-Verbose -Message "No projects found" -Verbose
}