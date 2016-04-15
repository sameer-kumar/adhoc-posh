$Purpose = 'IM TFS SharePoint Administration'
#[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client") | Out-Null
#[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime") | Out-Null
        
function Add-SPFile() {
<#
	.SYNOPSIS
		Uploads a file to specified location.

	.DESCRIPTION
		The Add-SPFile cmdlet uploads a file to specified web location via HTTP POST.

	.PARAMETER  DestinationObjectURL
		Specifies the Uniform Resource Identifier (URI) to which the file is sent.
        This parameter supports HTTP, and HTTPS.

	.PARAMETER  InputFileURL
		Specifies the file to use.
        Enter a path and file name. If you omit the path, the default is the current location.

	.EXAMPLE
		PS C:\> Add-SPFile -DestinationObjectURL "http://TFSprojectPortalServer/TFScollection/TFSProject/Administration/Requirements.docx" -InputFileURL "LocalRequirements.docx"

	.INPUTS
		System.String,System.String

	.OUTPUTS
		HashTable
        Add-SPFile returns a HashTable that contains the STATUS or EXCEPTION which are set by the cmdlet.
        STATUS holds Invoke-WebRequest results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		None.

	.LINK
		Invoke-WebRequest

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $DestinationObjectURL,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [string]
        $InputFileURL
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
    }
    Process {
        $resultObject = @{}
        try {
            # Upload the file.
            $tmp = Invoke-WebRequest -Uri $DestinationObjectURL -InFile $InputFileURL -Method PUT -UseDefaultCredentials 
            $resultObject.Status = $tmp.StatusDescription
            Write-Verbose -Message "File added to $DestinationObjectURL."
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

function Add-SPFolder() {
<#
	.SYNOPSIS
		Add folders to a specified SharePoint document library.

	.DESCRIPTION
		The Add-SPFolder cmdlet add specified folders to a SharePoint document library.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

    .PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.
        
	.PARAMETER  Folders
		Specifies the folders which needs to be added. This is an Array of string holding one or multiple names.
        
    .PARAMETER  ProjectRelativeURL
		Specifies the relative path of SP site URL to use.
        This is usually the portion of full site Url without the protocol and server name part.
        E.g. Site Url is http://<site>/projects/sitename", this parameter expects "/projects/sitename".

    .PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.

	.EXAMPLE
		PS C:\> Add-SPFolder -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Folders "@('Notes', 'Tasks')" -ProjectRelativeURL "/projects/TFSProjectName" -ClientContext "X-RequestDigest header" -UserCredential "{PSCredentioanObject}" 

	.EXAMPLE
		PS C:\> Add-SPFolder -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Folders "@('Notes', 'Tasks')" -ProjectRelativeURL "/projects/TFSProjectName"

	.INPUTS
		PSobject

	.OUTPUTS
		HashTable
        Add-SPFolder returns a HashTable that contains the STATUS or EXCEPTION which are set by the cmdlet.
        STATUS holds an array of Invoke-SPORestMethod results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		If you aren’t using OAuth to authorize your requests, SPS CRUD operations require the server’s request form digest value as the value of the X-RequestDigest header.

	.LINK
		Invoke-SPORestMethod
        
    .LINK
		https://msdn.microsoft.com/EN-US/library/office/dn292552.aspx
        https://msdn.microsoft.com/en-us/library/office/jj164022.aspx

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [ValidateScript({
            if($_.Name -ne $null){
                $true
            }
            else {
                throw "$_ must contain Name property."
            }
            
            if($_.Description -ne $null){
                $true
            }
            else {
                throw "$_ must contain Description property."
            }
            
            if($_.Folders -ne $null){
                $true
            }
            else {
                throw "$_ must contain Folders property."
            }
        })]
        [System.Object[]]
        $Folders,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=3)]
        [string]
        $ProjectRelativeURL,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=5)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
#        if ($UserCredential -eq $null) {
#            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
#            $UserCredential = $cred
#        }
    }
    Process {
        $foldersURL = $ApiUrl + "/web/folders/add"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            $resultObject.Status = @()
            $Folders.ForEach{
                $listTitle = $_.Name
                $_.Folders.Foreach{
                    # Add the folders
                    $addFolderUrl =  $foldersURL + "('$ProjectRelativeURL/$listTitle/$_')"
                    $resultObject.Status += Invoke-SPORestMethod -Url $addFolderUrl -Method "POST" -RequestDigest $digest -UserCredential $UserCredential
                    Write-Verbose -Message "$_ folder added to $listTitle."
                }
            }
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

function Add-SPList() {
<#
	.SYNOPSIS
		Adds a new SharePoint library.

	.DESCRIPTION
		The Add-SPList cmdlet adds new Document Library to specified SharePoint site.
        You can specify one or many Libraries to be created.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.
        
    .PARAMETER  Lists
		Specifies one or many Document Libraries to be created.
        This holds an Array of custom PSobjects having mandate properties as:
        -- Name as String
        -- Description as String
        
    .PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.

	.EXAMPLE
		PS C:\> Add-SPFolder -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Folders "@(@{Name='Design',Description='Design library'}, @{Name='Test',Description='Test library'})" -ProjectRelativeURL "/projects/TFSProjectName" -ClientContext "X-RequestDigest header" -UserCredential "{PSCredentioanObject}"

	.EXAMPLE
		PS C:\> Add-SPFolder -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Folders "@(@{Name='Design',Description='Design library'}, @{Name='Test',Description='Test library'})" -ProjectRelativeURL "/projects/TFSProjectName" 

	.INPUTS
		System.String,System.Object[],System.String,PSCredential

	.OUTPUTS
		HashTable
        Add-SPList returns a HashTable that contains the STATUS or EXCEPTION which are set by the cmdlet.
        STATUS holds an array of Invoke-SPORestMethod results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		If you aren’t using OAuth to authorize your requests, SPS CRUD operations require the server’s request form digest value as the value of the X-RequestDigest header.

	.LINK
		Invoke-SPORestMethod
        
    .LINK
		https://msdn.microsoft.com/EN-US/library/office/dn292552.aspx
        https://msdn.microsoft.com/en-us/library/office/jj164022.aspx
#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [ValidateScript({
            if($_.Name -ne $null){
                $true
            }
            else {
                throw "$_ must contain Name property."
            }
            
            if($_.Description -ne $null){
                $true
            }
            else {
                throw "$_ must contain Description property."
            }
        })]
        [System.Object[]]
        $Lists,

        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
#        if ($UserCredential -eq $null) {
#            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
#            $UserCredential = $cred
#        }
    }
    Process {
        $listURL = $ApiUrl + "/web/lists"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            $resultObject.Status = @()
            $Lists.ForEach{
                $listTitle = $_.Name
                $listDescription = $_.Description
                # Build Request body
                $body = New-Object PSCustomObject -Property @{
                    "__metadata" = (New-Object PSCustomObject -Property @{"type" = "SP.List"}); 
                    "AllowContentTypes" = $true; 
                    "BaseTemplate" = 101; 
                    "ContentTypesEnabled" = $true; 
                    "Description" = $listDescription; 
                    "Title" = $listTitle
                } 
                $metadata = ConvertTo-Json $body -Compress
            
                # Create the list 
                $resultObject.Status += Invoke-SPORestMethod -Url $listURL -Method "POST" -Metadata $metadata -RequestDigest $digest -UserCredential $UserCredential
                Write-Verbose -Message "$listTitle list added."
            }
        }
        catch {
            
			
            if($_.Exception.InnerException.Response.StatusCode -eq "NotFound"){
                #Write-Output "Not Found"
                #Write-Host "Not Found" -ForegroundColor Red
                $resultObject.Exception = $_
				Write-Error -Message "Not Found. $_"
            }
            elseif($_.Exception.InnerException.Response.StatusCode -eq "Unauthorized"){
                #Write-Output "Unauthorized"
                #Write-Host "Unauthorized" -ForegroundColor Red
                $resultObject.Exception = $_
				Write-Error -Message "Unauthorized. $_"
            }
            elseif($_.Exception.InnerException.Response.StatusCode -eq "Forbidden"){
                #Write-Output "Forbidden"
                #Write-Host "Forbidden" -ForegroundColor Red
                $resultObject.Exception = $_
				Write-Error -Message "Forbidden. $_"
            }
            elseif($_.Exception.InnerException.Response.StatusCode -eq "InternalServerError"){
                #Write-Output "InternalServerError"
                $ex = $_.Exception.InnerException.Response
                $responseStream = $ex.GetResponseStream()
                $responseReader = New-Object -TypeName System.IO.StreamReader -ArgumentList $responseStream
                $errorResult = $responseReader.ReadToEnd()
                $responseReader.Dispose()
                $responseStream.Dispose()
                if($errorResult -ne $null -and $errorResult.Length -ge 1) {
                    $resultJSObject = ConvertFrom-Json -InputObject $errorResult -ErrorAction SilentlyContinue
                    if($resultJSObject -ne $null) {
                        if($resultJSObject.error.message.value.Contains("already exists")) {
                            Write-Warning -Message "$($resultJSObject.error.message.value)"
                        }
                        else {
                            $resultObject.Exception = $resultJSObject.error.message.value
                            Write-Error -Message "InternalServerError[$($resultObject.Exception)]. $_"
                            $resultObject.Exception = $_
                        }
                    }
                }
				else {
					Write-Error -Message "InternalServerError. $_"
                    $resultObject.Exception = $_
				}
            }
            else {
                #Write-Output $_.Exception.Message
                #Write-Host $_ -ForegroundColor Red
				Write-Error -Message "$_"
                $resultObject.Exception = $_
            }
        }
        return $resultObject
    }
    End {}
}

function Add-SPQuickLaunchMenuNode {
    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [string]
        $NodeTitle,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=3)]
        [string]
        $NodeURL,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=5)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
#        if ($UserCredential -eq $null) {
#            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
#            $UserCredential = $cred
#        }
    }
    Process {
        $subsitesQuickLaunchURL = $ApiUrl + "/web/navigation/GetNodeById(1026)/children"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # ToDo: Validate if not already exists
            
            # Build Request body
            $body = New-Object PSCustomObject -Property @{
                "__metadata" = (New-Object PSCustomObject -Property @{"type" = "SP.NavigationNode"}); 
                "IsExternal" = $false;
                "Title" = "$NodeTitle";
                "Url" = "$NodeURL";
                "IsDocLib" = $false;
            } 
            $metadata = ConvertTo-Json $body -Compress
            
            # Create the list 
            $resultObject.Status = Invoke-SPORestMethod -Url $subsitesQuickLaunchURL -Method "POST" -Metadata $metadata -RequestDigest $digest -UserCredential $UserCredential
            Write-Verbose -Message "$NodeTitle added to QuickLaunch."
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

function Add-SPSubSite {
    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [string]
        $Title,

        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=3)]
        [string]
        $Description,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=4)]
        [string]
        $Url,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=5)]
        [string]
        $SiteTemplate,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=6)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=7)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
#        if ($UserCredential -eq $null) {
#            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
#            $UserCredential = $cred
#        }
    }
    Process {
        $subSiteURL = $ApiUrl + "/web/webinfos/add"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # Build Request body
            $body = New-Object PSCustomObject -Property @{
                "parameters" = (New-Object PSCustomObject -Property @{
                    "__metadata" = (New-Object PSCustomObject -Property @{"type" = "SP.WebInfoCreationInformation"}); 
                    "Url" = $Url; 
                    "Title" = $Title;
                    "Description" = "$Description";
                    "Language" = "1033"; 
                    "WebTemplate" = $SiteTemplate; 
                    "UseUniquePermissions" = "$true";    
                });
            } 

            $metadata = ConvertTo-Json $body -Compress
            $resultObject.Status = Invoke-SPORestMethod -Url $subSiteURL -Method "POST" -Metadata $metadata -RequestDigest $digest -UserCredential $UserCredential
            Write-Verbose -Message "$Title sub-site created."
        }
        catch {
            
            if($_.Exception.InnerException.Response.StatusCode -eq "InternalServerError"){
                $ex = $_.Exception.InnerException.Response
                $responseStream = $ex.GetResponseStream()
                $responseReader = New-Object -TypeName System.IO.StreamReader -ArgumentList $responseStream
                $errorResult = $responseReader.ReadToEnd()
                $responseReader.Dispose()
                $responseStream.Dispose()
                if($errorResult -ne $null -and $errorResult.Length -ge 1) {
                    $resultJSObject = ConvertFrom-Json -InputObject $errorResult -ErrorAction SilentlyContinue
                    if($resultJSObject -ne $null) {
                        if($resultJSObject.error.message.value.Contains("already in use")) {
                            Write-Warning -Message "$($resultJSObject.error.message.value)"
                        }
                        else {
                            $resultObject.Exception = $resultJSObject.error.message.value
                            Write-Error -Message "InternalServerError[$($resultObject.Exception)]. $_"
                        }
                    }
                }
				else {
					Write-Error -Message "InternalServerError. $_"
                    $resultObject.Exception = $_
				}
            }
            else {
			    Write-Error -Message "$_"
                $resultObject.Exception = $_
            }
        }
        return $resultObject
    }
    End {}
}

function Add-SPSiteUser() {
<#
	.SYNOPSIS
		Adds a user to the specified SharePoint site.

	.DESCRIPTION
		The Add-SPSiteUser cmdlet checks whether the specified logon name belongs to a valid user of the website, 
        and if the logon name does not already exist, adds it to the website.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.
        
    .PARAMETER  Sid
		Specifies the SIDs (Security Identifiers) of the corresponding account name.

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.
        
    .EXAMPLE
		PS C:\> Add-SPSiteUser -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Sid "Sid" -ClientContext "X-RequestDigest header" -UserCredential "{PSCredentioanObject}"

	.EXAMPLE
		PS C:\> Add-SPSiteUser -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -Sid "Sid" 

	.INPUTS
		System.String,System.String,System.String, PSCredential

	.OUTPUTS
		HashTable
        Add-SPSiteUser returns a HashTable that contains the STATUS or EXCEPTION which are set while invoking SPS Api.
        STATUS holds Invoke-SPORestMethod cmdlet results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		None.

	.LINK
		Invoke-SPORestMethod

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.sharepoint.spweb.ensureuser.aspx
        https://msdn.microsoft.com/EN-US/library/office/dn292552.aspx
        https://msdn.microsoft.com/en-us/library/office/jj164022.aspx

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [ValidateScript({
            try {
                $objSID = New-Object System.Security.Principal.SecurityIdentifier("$_")
                $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
                #$objUser.Value
                $true
            }
            catch {
                throw "$_ must be a valid Sid."
            }
        })]
        [string]
        $Sid,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
        $user = $null
    }
    Process {
        $addUserURL = $ApiUrl + "/web/ensureuser"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
				
                $digest = $ClientContext
            }
            
            # Build Request body
#            $body = New-Object PSCustomObject -Property @{
#                "logonName" = "c:0+.w|$Sid"; 
#            } 
#			$body = New-Object PSCustomObject -Property @{
#                "logonName" = "i:0#.w|$Sid"; 
#            } 
			$loginName = Get-NameBySid -Sid "$Sid"
			$body = New-Object PSCustomObject -Property @{
                "logonName" = "$loginName"; 
            } 
			
			
            $metadata = ConvertTo-Json $body -Compress
            
            # Add the user 
            $resultObject.Status = Invoke-SPORestMethod -Url $addUserURL -Method "POST" -Metadata $metadata -RequestDigest $digest -UserCredential $UserCredential
            Write-Verbose -Message "$Sid user added."
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

function Clear-SPSitePermissions() {
<#
	.SYNOPSIS
		Deletes current role assigments of a specified Sharepoint site.

	.DESCRIPTION
		The Clear-SPSitePermissions cmdlet removes all securable object role assignments on the Web site.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.
        
    .EXAMPLE
		PS C:\> Clear-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -ClientContext "X-RequestDigest header" -UserCredential "{PSCredentioanObject}"

	.EXAMPLE
		PS C:\> Clear-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api"

	.INPUTS
		System.String,System.String,PSCredential 

	.OUTPUTS
		HashTable
        Clear-SPSitePermissions returns a HashTable that contains the STATUS or EXCEPTION which are set while invoking SPS Api.
        STATUS holds Invoke-SPORestMethod cmdlet results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		None.

	.LINK
		Invoke-SPORestMethod

	.LINK
		https://msdn.microsoft.com/EN-US/library/microsoft.sharepoint.client.roleassignment.aspx
        https://msdn.microsoft.com/en-us/library/office/jj164022.aspx
#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
    }
    Process {
        $roleassignmentURL = $ApiUrl + "/web/roleassignments"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # Get current permissions for site.
            $sitePermissions = Get-SPSitePermissions -ApiUrl $ApiUrl
            if($sitePermissions -ne $null) {
                if($sitePermissions.GetType().Name -eq 'PSCustomObject') {
                    $principalId = $sitePermissions.PrincipalId
                    $roleDeletionURL = $roleassignmentURL + "($principalId)"
                    $resultObject.Status = Invoke-SPORestMethod -Url $roleDeletionURL -Method "POST" -RequestDigest $digest -XHTTPMethod "DELETE"
                    Write-Verbose -Message "Site permission cleared."
                }
                elseif($sitePermissions -is [Array]){
                    $sitePermissions.Foreach{
                        $principalId = $_.PrincipalId
                        $roleDeletionURL = $roleassignmentURL + "($principalId)"
                        $resultObject.Status = Invoke-SPORestMethod -Url $roleDeletionURL -Method "POST" -RequestDigest $digest -XHTTPMethod "DELETE"
                        Write-Verbose -Message "Site permissions cleared."
                    }
                }
            }
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

function Connect-SPOSite {
    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        $Url
    )
    #endregion Parameters
    Begin {
#        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client") | Out-Null
#        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime") | Out-Null
    }
    Process {
        if ($global:spoCred -eq $null) {
            $cred = Get-Credential -Message "Enter your credentials for SharePoint Online:"
            $global:spoCred = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($cred.UserName, $cred.Password)
        }
        $ctx = New-Object Microsoft.SharePoint.Client.ClientContext $Url
        $ctx.Credentials = $spoCred

        if (!$ctx.ServerObjectIsNull.Value) { 
            Write-Host "Connected to site: '$Url'" -ForegroundColor Green
        }
        return $ctx
    }
    End {}
}

function Get-SPClientContext() {
<#
	.SYNOPSIS
		Returns the Sharepoint server's request form digest value.

	.DESCRIPTION
		The Get-SPClientContext cmdlet makes an POST request to specified SPS site using REST Api and extract the X-RequestDigest header.
        This header or context information is used to authorize further SPS REST Api call.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.

	.EXAMPLE
		PS C:\> Get-SPClientContext -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserCredential "{PSCredentioanObject}"

	.EXAMPLE
		PS C:\> Get-SPClientContext -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api"

	.INPUTS
		System.String,PSCredential

	.OUTPUTS
		System.String
        Represents context info.

	.NOTES
		If you aren’t using OAuth to authorize your requests, CRUD operations require the server’s request form digest value as the value of the X-RequestDigest header.

	.LINK
		Invoke-SPORestMethod

	.LINK
		https://msdn.microsoft.com/en-us/library/office/jj164022.aspx

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {}
    Process {
		try {
        	$contextInfoURL = $ApiUrl + "/contextinfo"
        	$formDigest = $null
        	# Get the form digest 
        	$formDigest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
        	return $formDigest
		}
		catch {
			Write-Error -Message "$_"
		}
    }
    End {}
}

function Get-SPQuickLaunchMenuNodes {
    #region Parameters
    [CmdletBinding(DefaultParametersetName='AllNodes')]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1, ParameterSetName='AllNodes')]
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1, ParameterSetName='TargetNode')]
        [string]
        $ApiUrl,
        
        [Parameter(ValueFromPipeline=$true, Position=2, ParameterSetName='TargetNode')]
        [string]
        $TargetNodeTitle,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=3, ParameterSetName='TargetNode')]
        [int]
        $TargetNodeId,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4, ParameterSetName='AllNodes')]
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4, ParameterSetName='TargetNode')]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        $paramSetName = $PsCmdLet.ParameterSetName
    }
    Process {
		$navigationURL = $ApiUrl + "/web/navigation/QuickLaunch"
        try {
            $requestHeaders = New-Object 'system.collections.generic.dictionary[string,string]'
            $requestHeaders["Accept"] = "application/json;odata=verbose"
            $navigationNodes = Invoke-RestMethod -Uri $navigationURL -Method Get -ContentType "application/json;odata=verbose" -UseDefaultCredentials -Headers $requestHeaders
            if($navigationNodes -ne $null) {
                if($paramSetName -eq "TargetNode") {
                    return $navigationNodes.d.results | Where-Object {($_.Title -eq "$TargetNodeTitle") -and ($_.Id -eq $TargetNodeId)}
                }
                else {
                    return $navigationNodes.d.results 
                }
                
            }
            else {
				Write-Warning -Message "Could not get QuickLaunch navigation nodes from $ApiUrl"
                return $null
            }
        }
        catch {
            Write-Error -Message "$_"
			throw "$_"
        }
    }
    End {}
}

function Get-SPRoleDefinitionByName() {
<#
	.SYNOPSIS
		Returns the role definition with the specified name from the collection.

	.DESCRIPTION
		The Get-SPClientContext cmdlet queries the RoleDefinitionCollection and retrieves one based on specified role name.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  RoleName
		Specifies the Role name whose definition details needs to retrieved.
        Possible value may be either:
        -- 'Contribute'
        -- 'Design'
        -- 'Read'
        -- 'Edit'
        -- 'View Only'
        -- 'Full Control'

	.EXAMPLE
		PS C:\> Get-SPRoleDefinitionByName -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -RoleName "Read"

	.INPUTS
		System.String,System.String

	.OUTPUTS
		System.Int
        If found, an integer value else null.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/EN-US/library/office/microsoft.sharepoint.client.roledefinitioncollection.getbyname.aspx
#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [ValidateNotNullorEmpty()]
        [ValidateLength(1,255)]
        [ValidateSet('Contribute', 'Design', 'Read', 'Edit', 'View Only', 'Full Control')]
        [string]
        $RoleName
    )
    #endregion Parameters
    Begin {
        # Validate params and return menaningful messages here.
    }
    Process {
        # $roleDefinitionsURL = $ApiUrl + "/web/roledefinitions/getbyname('$RoleName')"
        $roleDefinitionsURL = $ApiUrl + "/web/roledefinitions/getbyname('$RoleName')/Id"
        try {
            $requestHeaders = New-Object 'system.collections.generic.dictionary[string,string]'
            $requestHeaders["Accept"] = "application/json;odata=verbose"
            $roleDefinition = Invoke-RestMethod -Uri $roleDefinitionsURL -Method Get -ContentType "application/json;odata=verbose" -UseDefaultCredentials -Headers $requestHeaders
            if($roleDefinition -ne $null) {
                return $roleDefinition.d.Id
            }
            else {
				Write-Warning -Message "Could not get role definition of $RoleName from $ApiUrl"
                return $null
            }
        }
        catch {
            Write-Error -Message "$_"
			throw "$_"
        }
    }
    End {}
}

function Get-SPSitePermissions() {
<#
	.SYNOPSIS
		Returns current permissions configured for specified Sharepoint web site.

	.DESCRIPTION
		The Get-SPSitePermissions cmdlet gets the collection of role assignments for a Sharepoint web site.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.

	.EXAMPLE
		PS C:\> Get-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserCredential "{PSCredentioanObject}"

	.EXAMPLE
		PS C:\> Get-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api"

	.INPUTS
		System.String,System.String

	.OUTPUTS
		System.String[]
        Site permissions.

	.NOTES
		None.

	.LINK
		https://msdn.microsoft.com/en-us/library/microsoft.sharepoint.spweb.roleassignments(v=office.12).aspx
#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
    }
    Process {
        try {
			$roleassignmentURL = $ApiUrl + "/web/roleassignments"
	        $sitePermissions = $null
	        $requestHeaders = New-Object 'system.collections.generic.dictionary[string,string]'
	        $requestHeaders["Accept"] = "application/json;odata=verbose"
	        
	        # Get current permissions for site.
	        if($UserCredential -ne $null) {
	            $sitePermissions = Invoke-RestMethod -Uri $roleassignmentURL -Method Get -ContentType "application/json;odata=verbose" -Credential $UserCredential -Headers $requestHeaders
	        }
	        else {
	            $sitePermissions = Invoke-RestMethod -Uri $roleassignmentURL -Method Get -ContentType "application/json;odata=verbose" -UseDefaultCredentials -Headers $requestHeaders
	        }
	        if(($sitePermissions -ne $null) -and ($sitePermissions -is [System.Object])) {
	            $sitePermissions = $sitePermissions.d.Results
	        }
	        return $sitePermissions
		}
		catch {
			Write-Error -Message "$_"
		}
    }
    End {}
}

function Invoke-SPORestMethod {
    <#
.Synopsis
    Sends an HTTP or HTTPS request to a SharePoint Online REST-compliant web service.
.DESCRIPTION
    This function sends an HTTP or HTTPS request to a Representational State 
    Transfer (REST)-compliant ("RESTful") SharePoint web service.
    When connecting, if Set-SPORestCredentials is not called then you will be
    prompted for your credentials. Those credentials are stored in a global
    variable $global:spoCred so that it will be available on subsequent calls.
.EXAMPLE
   Invoke-SPORestMethod -Url "https://contoso.sharepoint.com/_api/web"
.EXAMPLE
   Invoke-SPORestMethod -Url "https://contoso.sharepoint.com/_api/contextinfo" -Method "Post"
#>
    #region Parameters
    [CmdletBinding()]
    [OutputType([int])]
    Param (
        # The REST endpoint URL to call.
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.Uri]$Url,

        # Specifies the method used for the web request. The default value is "Get".
        [Parameter(Mandatory = $false, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Get", "Head", "Post", "Put", "Delete", "Trace", "Options", "Merge", "Patch")]
        [string]$Method = "Get",

        # Additional metadata that should be provided as part of the Body of the request.
        [Parameter(Mandatory = $false, Position = 2)]
        [ValidateNotNullOrEmpty()]
        [object]$Metadata,

        # The "X-RequestDigest" header to set. This is most commonly used to provide the form digest variable. Use "(Invoke-SPORestMethod -Url "https://contoso.sharepoint.com/_api/contextinfo" -Method "Post").GetContextWebInformation.FormDigestValue" to get the Form Digest value.
        [Parameter(Mandatory = $false, Position = 3)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestDigest,
        
        # The "If-Match" header to set. Provide this to make sure you are not overwritting an item that has changed since you retrieved it.
        [Parameter(Mandatory = $false, Position = 4)]
        [ValidateNotNullOrEmpty()]
        [string]$ETag, 
        
        # To work around the fact that many firewalls and other network intermediaries block HTTP verbs other than GET and POST, specify PUT, DELETE, or MERGE requests for -XHTTPMethod with a POST value for -Method.
        [Parameter(Mandatory = $false, Position = 5)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Get", "Head", "Post", "Put", "Delete", "Trace", "Options", "Merge", "Patch")]
        [string]$XHTTPMethod,

        [Parameter(Mandatory = $false, Position = 6)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("Verbose", "MinimalMetadata", "NoMetadata")]
        [string]$JSONVerbosity = "Verbose",

        # If the returned data is a binary data object such as a file from a SharePoint site specify the output file name to save the data to.
        [Parameter(Mandatory = $false, Position = 7)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=1)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
#        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client") | Out-Null
#        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime") | Out-Null
#        if ($UserCredential -eq $null) {
#            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
#            $UserCredential = $cred
#        }
    }
    Process {
        $request = [System.Net.WebRequest]::Create($Url)
        #$request.Credentials = $UserCredential
        $request.UseDefaultCredentials = $true
        $odata = ";odata=$($JSONVerbosity.ToLower())"
        $request.Accept = "application/json$odata"
        $request.ContentType = "application/json$odata"   
        $request.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")   
        $request.Method = $Method.ToUpper()

        if(![string]::IsNullOrEmpty($RequestDigest)) {
            $request.Headers.Add("X-RequestDigest", $RequestDigest)
        }
        if(![string]::IsNullOrEmpty($ETag)) {
            $request.Headers.Add("If-Match", $ETag)
        }
        if($XHTTPMethod -ne $null) {
            $request.Headers.Add("X-HTTP-Method", $XHTTPMethod.ToUpper())
        }
        if ($Metadata -is [string] -and ![string]::IsNullOrEmpty($Metadata)) {
            $body = [System.Text.Encoding]::UTF8.GetBytes($Metadata)
            $request.ContentLength = $body.Length
            $stream = $request.GetRequestStream()
            $stream.Write($body, 0, $body.Length)
            $stream.Close()
        } elseif ($Metadata -is [byte[]] -and $Metadata.Count -gt 0) {
            $request.ContentLength = $Metadata.Length
            $stream = $request.GetRequestStream()
            $stream.Write($Metadata, 0, $Metadata.Length)
            $stream.Close()
        } else {
            $request.ContentLength = 0
        }
        
        $response = $null
        try {
            $response = $request.GetResponse()
            $streamReader = New-Object System.IO.StreamReader $response.GetResponseStream()
            try {
                # If the response is a file (a binary stream) then save the file our output as-is.
                if ($response.ContentType.Contains("application/octet-stream")) {
                    if (![string]::IsNullOrEmpty($OutFile)) {
                        $fs = [System.IO.File]::Create($OutFile)
                        try {
                            $streamReader.BaseStream.CopyTo($fs)
                        } finally {
                            $fs.Dispose()
                        }
                        return
                    }
                    $memStream = New-Object System.IO.MemoryStream
                    try {
                        $streamReader.BaseStream.CopyTo($memStream)
                        Write-Output $memStream.ToArray()
                    } finally {
                        $memStream.Dispose()
                    }
                    return
                }
                # We don't have a file so assume JSON data.
                $data = $streamReader.ReadToEnd()

                # In many cases we might get two ID properties with different casing.
                # While this is legal in C# and JSON it is not with PowerShell so the
                # duplicate ID value must be renamed before we convert to a PSCustomObject.
                if ($data.Contains("`"ID`":") -and $data.Contains("`"Id`":")) {
                    $data = $data.Replace("`"ID`":", "`"ID-dup`":");
                }

                $results = ConvertFrom-Json -InputObject $data

                # The JSON verbosity setting changes the structure of the object returned.
                if ($JSONVerbosity -ne "verbose" -or $results.d -eq $null) {
                    Write-Output $results
                } else {
                    Write-Output $results.d 
                }
            }
            catch {
                throw
            }
            finally {
                $streamReader.Dispose()
            }
        }
        catch {
            throw 
        }
        finally {
            if($response -ne $null) {
                $response.Dispose()
            }
        }
    }
    End {}
} 

function Set-SPSubSiteNavigation {
    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(ValueFromPipeline=$true, Position=2)]
        [string]
        $SubSiteUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=3)]
        [string]
        $SubSiteTitle,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=5)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
        if($SubSiteUrl -eq $null) {
            $SubSiteUrl = $SubSiteTitle
        }
    }
    Process {
        $topNavigationBarURL = $ApiUrl + "/web/navigation/TopNavigationbar"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # Get Subsites node from QuickLaunch navigation menu. If found, add a navigation node for sub-site.
            $subSitesNode = Get-SPQuickLaunchMenuNodes -ApiUrl $ApiUrl -TargetNodeTitle "Subsites" -TargetNodeId 1026 -UserCredential $UserCredential 
            if($subSitesNode){
                $newNode = Add-SPQuickLaunchMenuNode -ApiUrl $ApiUrl -NodeTitle "$SubSiteTitle" -NodeURL "$SubSiteUrl" -UserCredential $UserCredential -ClientContext $ClientContext
            }
            
            # Add sub-site to parent site top navigation bar.
            # Build Request body
            $body = New-Object PSCustomObject -Property @{
                "__metadata" = (New-Object PSCustomObject -Property @{"type" = "SP.NavigationNode"}); 
                "Url" = $SubSiteUrl; 
                "Title" = $SubSiteTitle;
                "IsExternal" = $false;
                "IsDocLib" = $false;
            } 

            $metadata = ConvertTo-Json $body -Compress
            $resultObject.Status = Invoke-SPORestMethod -Url $topNavigationBarURL -Method "POST" -Metadata $metadata -RequestDigest $digest -UserCredential $UserCredential
            Write-Verbose -Message "$SubSiteTitle Sub-site added to top navigation bar."
        }
        catch {
			Write-Error -Message "$_"
            $resultObject.Exception = $_
        }
        return $resultObject
    }
    End {}
}

function Set-SPSitePermissions() {
<#
	.SYNOPSIS
		Configures the SPS web site with specified user and permissions defined as RoleAssignments.

	.DESCRIPTION
		The Set-SPSitePermissions cmdlet adds new role assignment with the specified principal and role definitions to the collection.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api
    
    .PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.
        
    .PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.
        
	.PARAMETER  UserRoles
		Specifies the collection of user and roles.

	.EXAMPLE
		PS C:\> Set-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserRoles "Hashtable" -ClientContext "$(Get-SPClientContext -ApiUrl 'http://TFSprojectPortalServer/TFScollection/TFSProject/_api')" -UserCredential "{PSCredentioanObject}"
        The UserRoles hashtable contains following info:
        -- PrincipalId: which can be retrived from Add-SPSiteUser cmdlet
        -- RoleDefinitionId: which can be retrieved from Get-SPRoleDefinitionByName cmdlet by passing friendly Role name.

	.EXAMPLE
		PS C:\> Set-SPSitePermissions -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserRoles "Hashtable"
        The UserRoles hashtable contains following info:
        -- PrincipalId: which can be retrived from Add-SPSiteUser cmdlet
        -- RoleDefinitionId: which can be retrieved from Get-SPRoleDefinitionByName cmdlet by passing friendly Role name.

	.INPUTS
		System.String,HashTable,String,PSCredential

	.OUTPUTS
		HashTable
        Add-SPFolder returns a HashTable that contains the STATUS or EXCEPTION which are set by the cmdlet.
        STATUS holds an array of Invoke-SPORestMethod results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		None.

	.LINK
		Get-SPRoleDefinitionByName
        Add-SPSiteUser
        Invoke-SPORestMethod

	.LINK
		https://msdn.microsoft.com/en-us/library/office/dn531432.aspx#bk_RoleAssignmentCollectionAddRoleAssignment
        https://msdn.microsoft.com/en-us/library/office/jj164022.aspx

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [hashtable]
        $UserRoles,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
    }
    Process {
        $roleassignmentURL = $ApiUrl + "/web/roleassignments"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # Add Users to site.
            $resultObject.Status = @()
            $UserRoles.GetEnumerator() | ForEach-Object {
                $principalId = $_.Key
                $roleDefinitionId = $_.Value
                $addRoleUrl = $roleassignmentURL + "/addroleassignment(principalid=$principalId, roledefid=$roleDefinitionId)"
                $newRole = Invoke-SPORestMethod -Url $addRoleUrl -Method "POST" -RequestDigest $digest
                $resultObject.Status += $newRole
                Write-Verbose -Message "Provisioned $_.Key to site."
            }
        }
        catch {
			Write-Error -Message "$_"
            $resultObject.Exception = $_
        }
        return $resultObject
    }
    End {}
}

function Stop-SPSitePermissionInheritance {
<#
	.SYNOPSIS
		Stop permissions' inheritance for site.

	.DESCRIPTION
		The Stop-SPSitePermissionInheritance cmdlet instructs the site to stop inheriting permissions.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.

	.EXAMPLE
		PS C:\> Stop-SPSitePermissionInheritance -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" 

	.INPUTS
		System.String,System.String,PSCrdential

	.OUTPUTS
		HashTable
        Stop-SPSitePermissionInheritance returns a HashTable that contains the STATUS or EXCEPTION which are set while invoking SPS Api.
        STATUS holds Invoke-SPORestMethod cmdlet results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		None.


#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
        
        # Get the form digest if not specified
        $contextInfoURL = $ApiUrl + "/contextinfo"
        if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
            $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
        }
        else {
            $digest = $ClientContext
        }
    }
    Process {
        $breakInheritanceUrl = $ApiUrl + "/web/breakroleinheritance(true)"
        $resultObject = @{}
        try {
            $resultObject.Status = Invoke-SPORestMethod -Url $breakInheritanceUrl -Method "POST" -RequestDigest $digest 
            Write-Verbose -Message "Site permissions inheritance stopped."
        }
        catch {
			Write-Error -Message "$_"
            $resultObject.Exception = $_
        }
        return $resultObject
    }
    End {}
}

function Test-SPList() {
    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ListUrl,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=2)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {}
    Process {
        if ($UserCredential -eq $null) {
            $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        }
        $resultObject = @{}
        $webRequest = [System.Net.WebRequest]::Create($ListURL)
        $webRequest.Credentials = $UserCredential
        $webRequest.Accept = "application/json;odata=verbose"
        $webRequest.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

        try {
            $webResponse = $webRequest.GetResponse()
            $reader = New-Object System.IO.StreamReader $webResponse.GetResponseStream()
            $data = $reader.ReadToEnd()
            $resultObject = ConvertFrom-Json -InputObject $data
        }
        catch {
            if($_.Exception.InnerException.Response.StatusCode -eq "NotFound"){
                $resultObject.Exception = "Not Found"
                #Write-Host "Not Found" -ForegroundColor Red
            }
            elseif($_.Exception.InnerException.Response.StatusCode -eq "Unauthorized"){
                $resultObject.Exception = "Unauthorized"
                #Write-Host "Unauthorized" -ForegroundColor Red
            }
            else {
                $resultObject.Exception = $_
                #Write-Host $_ -ForegroundColor Red
            }
        }
        return $resultObject
    }
    End {}
    
}

function Update-SiteSecurity {
<#
	.SYNOPSIS
		Resets the Sharepoint web site security permissions.

	.DESCRIPTION
		The Update-SiteSecurity cmdlet clears existing site permissions and adds new role assignment with the specified principal and role definitions to the collection.

	.PARAMETER  ApiUrl
		Specifies the URL of SharePoint Site REST Api endpoint.
        The format it expects is: http://<site url>/_api

	.PARAMETER  ClientContext
		Specifies the Form-Digest value used for SharePoint RESTful API calls.
        If not specified, this cmdlet invokes another POST request to get the context info.

	.PARAMETER  UserCredential
		Specifies the credential object who has administrative access to SPS server. This account is used to invoke REST actions.
        This is optional parameter. If not specified, current user's identity (-UseDefaultCredentials flag) would be used.
        
	.PARAMETER  UserRoles
		Specifies the collection of user and roles.
        
    .EXAMPLE
		PS C:\> Update-SiteSecurity -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserRoles "Array" -ClientContext "$(Get-SPClientContext -ApiUrl 'http://TFSprojectPortalServer/TFScollection/TFSProject/_api')" -UserCredential "{PSCredentioanObject}"
        UserRoles Array consists of Tuple with items:
        -- PrincipalName: this is domain account
        -- PrincipalSid: this is Sid associated of domain account
        -- SProleName: Friendly SharePoint role name like 'Design', 'Edit', 'Contribute', 'Read', 'View Only'
        -- RoleDefinitionId: Get-SPRoleDefinitionByName cmdlet can be used to pull this one.

	.EXAMPLE
		PS C:\> Update-SiteSecurity -ApiUrl "http://TFSprojectPortalServer/TFScollection/TFSProject/_api" -UserRoles "Array"
        UserRoles Array consists of Tuple with items:
        -- PrincipalName: this is domain account
        -- PrincipalSid: this is Sid associated of domain account
        -- SProleName: Friendly SharePoint role name like 'Design', 'Edit', 'Contribute', 'Read', 'View Only'
        -- RoleDefinitionId: Get-SPRoleDefinitionByName cmdlet can be used to pull this one.

	.INPUTS
		System.String,System.Object[],String,PSCredential

	.OUTPUTS
		HashTable
        Add-SPFolder returns a HashTable that contains the STATUS or EXCEPTION which are set by the cmdlet.
        STATUS holds an array of Invoke-SPORestMethod results. May be blank if successful.
        EXCEPTION holds any exception thrown in method invocation.

	.NOTES
		CAUTION: Remember calling this cmdlet removes existing permissions and then configures new role assignments.

	.LINK
		Clear-SPSitePermissions
        Set-SPSitePermissions
        Add-SPSiteUser
        Get-SPRoleDefinitionByName

	.LINK
		https://msdn.microsoft.com/en-us/library/office/jj164022.aspx
        https://msdn.microsoft.com/en-us/library/office/dn531432.aspx#bk_RoleAssignmentCollectionAddRoleAssignment

#>

    #region Parameters
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=1)]
        [string]
        $ApiUrl,
        
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, Position=2)]
        [ValidateScript({
            if($_.GetType().Name -eq 'Tuple`4'){
                $true
            }
            else {
                throw "$_ must contain Tuple with 4 items. Item1: SecurityPrincipalName, Item2: Sid, Item3: SPS friendly role, Item4: SPS role definition"
            }
        })]
        [System.Object[]]
        $UserRoles,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=3)]
        [string]
        $ClientContext,
        
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=4)]
        [PSCredential]
        $UserCredential
    )
    #endregion Parameters
    Begin {
        # if ($UserCredential -eq $null) {
        #   $cred = Get-Credential -Message "Enter your credentials for SharePoint:"
        #   $UserCredential = $cred
        # }
    }
    Process {
        $siteURL = $ApiUrl + "/web"
        $contextInfoURL = $ApiUrl + "/contextinfo"
        $resultObject = @{}
        try {
            # Get the form digest 
            if(($ClientContext -eq $null) -or ($ClientContext.Length -le 0)) {
                $digest = (Invoke-SPORestMethod -Url $contextInfoURL -Method "POST" -UserCredential $UserCredential).GetContextWebInformation.FormDigestValue 
            }
            else {
                $digest = $ClientContext
            }
            
            # Add Users to site.
            $rolePrincipalList = @{}
            $UserRoles.Foreach{
                $siteUser = Add-SPSiteUser -ApiUrl $ApiUrl -Sid $_.Item2 -ClientContext $digest -ErrorAction Stop
                if($siteUser.ContainsKey("Status")) {
                    $rolePrincipalList.Add("$($siteUser.Status.Id)", $_.Item4)
                }
                else {
                    Write-error -Message "User $($_.Item2) cannot be added to SP site using $ApiUrl. $($siteUser.Exception)" -ErrorAction Stop
                }
            }
            
            # remove existing users permissions/roles from site.
            Clear-SPSitePermissions -ApiUrl $ApiUrl -ClientContext $digest
            
            # break inheritance on site
            Stop-SPSitePermissionInheritance -ApiUrl $ApiUrl -ClientContext $digest
            
            # grant users permissions/roles to site.
            $resultObject.Status = @()
            $resultObject.Status += Set-SPSitePermissions -ApiUrl $ApiUrl -UserRoles $rolePrincipalList -ClientContext $digest
            Write-Verbose -Message "Site permissions have been reset."
        }
        catch {
            $resultObject.Exception = $_
			Write-Error -Message "$_"
        }
        return $resultObject
    }
    End {}
}

#Export-ModuleMember -Function 'Add-*', 'Clear-SPSitePermissions', 'Get-*', 'Set-SPSitePermissions', 'Test-*', 'Update-SiteSecurity'
#Export-ModuleMember -Variable 'Purpose'