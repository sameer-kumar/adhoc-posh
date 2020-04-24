function Get-VariableGroupDetails
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory, ValueFromPipeline=$true, Position=1, HelpMessage="VariableGroup name to be searched and used.")]
        [string]
        $VariableGroupName,

        [parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2, HelpMessage="Uri of Tfs Project containing the Variabnle group to be searched.")]
        [string]
        $TfsProjectUri
    )
    Begin
    {
        if (!($PSBoundParameters.ContainsKey("TfsProjectUri")))
        {
            #http://tfs/Projects/PRJ/_apis/distributedtask/variablegroups
            $tfsCollectionUri = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
            #"http://Tfs:8080/tfs/Projects"
            $tfsProjectName = $env:SYSTEM_TEAMPROJECT
            $tfProjectUri = "$tfsCollectionUri/$tfsProjectName"
        }
        else
        {
            $tfProjectUri = $TfsProjectUri
        }

        $variableCollection = @()
    }
    Process
    {
        $tfsVariableGroupsUri = "$tfProjectUri/_apis/distributedtask/variablegroups?api-version=3.1&`$top=256"
        $response = Invoke-WebRequest -Uri $tfsVariableGroupsUri -UseDefaultCredentials -Method Get -UseBasicParsing #-Verbose
        $responseObject = $response.Content | ConvertFrom-Json
        if($responseObject.count -ge 1)
        {
            # Enumerate all variable groups
            foreach($group in $responseObject.value)
            {
                $groupName = $($group.Name)
                if ($groupName -eq $VariableGroupName)
                {
                    $variableEntries = $($group.variables)
                    $variableEntries2 = $group.variables | Get-Member | Where-Object{$_.MemberType -eq 'NoteProperty'}
                    $keyItem = "value="
                    foreach($variableEntry in $variableEntries2)
                    {
                        $key = $variableEntry.Name
                        #$value = $variableEntry.Definition.Substring($variableEntry.Definition.LastIndexOf('=')+1)
                        $value = $variableEntry.Definition.Substring($variableEntry.Definition.IndexOf($keyItem)+$keyItem.Length)
                        $value = $value.TrimEnd('}')
                        $variableCollection += @{$key=$value;}
                    }
                }
            }
        }
        else
        {
            Write-Error -Message "No variable groups found for this project - $tfsProjectName" -Verbose
        }

        return $variableCollection
    }
    End{}
}

$varList = Get-VariableGroupDetails -VariableGroupName 'CBMPEnvironmentVariablesDEV' -TfsProjectUri 'http://tfwa/Projects/FixedIncome.CBMP'
$releaseVaraiables = $varlist
if($releaseVaraiables)
{
    foreach($releaseVaraiable in $releaseVaraiables)
    {
        Write-Verbose "variable is $($releaseVaraiable.Keys[0]) and value is $($releaseVaraiable.values[0])" -Verbose
    }
}