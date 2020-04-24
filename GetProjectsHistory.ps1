# **********TFS Rest Api will only return 256 records at a time**********
$rootTfsUri = "http://tfs:8080/tfs/Collection"
$allProjectsUri = "$rootTfsUri/_apis/projects?api-version=3.1&`$top=256"
$projectStats = @{}

function Get-MaxChangeset($Project, $LastChngset)
{
    $projectUri = "$rootTfsUri/$($Project.name)/_apis/tfvc/changesets?api-version=3.1&`$top=256&orderby=id desc"
    $lastchangeset = $LastChngset
    if($lastchangeset -ne $null){
        $projectUri += "&searchCriteria.toId=$($lastchangeset.changesetId)"
    }

    $nestedsubresponse = Invoke-WebRequest -Uri $projectUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
    $nestedsubresponseObject = $nestedsubresponse.Content | ConvertFrom-Json
    if($nestedsubresponseObject.count -ge 1)
    {
        # exclude false positives.
        $lastchangeset = $nestedsubresponseObject.value | `
                    where-object {
                        ($_.checkedInBy.displayName -notlike "*Project Collection Service Accounts*") } | `
                    Sort-Object changesetId -Descending | Select-Object -First 1

        if( ($lastchangeset -eq $null) -and ($nestedsubresponseObject.count -ge 256) )
        {
            # More records to search. Pick the bottom from current list and send it back for next batch api call.
            $lastchangeset = $nestedsubresponseObject.value | Sort-Object changesetId | Select-Object -First 1
            $lastchangeset = Get-MaxChangeset $Project $lastchangeset
        }
    }

    return $lastchangeset
}

$response = Invoke-WebRequest -Uri $allProjectsUri -UseDefaultCredentials -Method Get -Verbose -UseBasicParsing
$responseObject = $response.Content | ConvertFrom-Json
if($responseObject.count -ge 1)
{
    foreach($prj in $responseObject.value)
    {
        $lastchangeset = Get-MaxChangeset $prj $null
        if($lastchangeset -ne $null)
        {
            $projectStats.Add("$($prj.name)", $lastchangeset.createdDate)
        }
        else
        {
            $projectStats.Add("$($prj.name)", $lastchangeset)
        }
    }

    $projectStats.GetEnumerator() | Export-Csv "CheckInHistory.csv"
}
