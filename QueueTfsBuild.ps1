$rootTfsUri = "http://myTFS:8080/tfs"
$collectionName = "Default"
$projectName = "Project1"
$tfsUri = $rootTfsUri + "/" + $collectionName + "/" + $projectName
$buildDefinitionUri = "$tfsUri/_apis/build/definitions?api-version=3.1&name=CSSDevCI-vnext" 

# first get build definition id
$buildResponse = Invoke-WebRequest -Uri $buildDefinitionUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing -ContentType "application/json" 
$buildResponseAsJson = $buildResponse.Content | convertfrom-json
$buildDefinitionId = $buildResponseAsJson.value.id

# Now queue this build definition
$requestContentString = @"
{
    "definition": {
        "id" : "$buildDefinitionId"
    }
}
"@

$buildUri = "$tfsUri/_apis/build/builds?api-version=3.1"
$buildResponse = Invoke-WebRequest -Uri $buildUri -UseDefaultCredentials -Method Post -Verbose -UseBasicParsing -ContentType "application/json" -Body $requestContentString
$buildNumber = ($buildResponse.Content | ConvertFrom-Json).buildNumber
